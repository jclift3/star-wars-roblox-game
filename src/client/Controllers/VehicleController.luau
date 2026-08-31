--!strict
--[[
	VehicleController.luau

	Calls the speeder in, and flies it once you are sitting on it.

	WHY THE DRIVING IS HERE AND NOT ON THE SERVER
	Roblox hands a seated vehicle's physics to the driver's own machine, and
	the whole point of that is that pressing W and moving are the same
	moment. Writing the constraints from the server instead would put a round
	trip between them -- twice, since the server also learns about `Throttle`
	late -- and at 200 studs a second the vehicle would arrive somewhere the
	player did not aim it. VehicleService documents what this concedes.

	IT DRIVES A HEADING, NOT A TORQUE
	The yaw is a number this file integrates and then hands to an
	`AlignOrientation`, rather than a turning force applied to a hull. A
	repulsorlift has nothing to grip, so there is no traction model worth
	writing, and a heading is the only version that behaves identically on
	Tatooine and on Hoth -- `PlanetDef.gravity` differs per world, and a
	force-driven speeder would need retuning on each of the nine.

	A STARSHIP IS THE SAME LOOP WITH A SECOND ANGLE
	Flight (ROADMAP 2c) added `pitch` beside `yaw` and changed exactly one
	other thing: a speeder's velocity is its heading flattened plus a hover
	correction, and a starship's is its heading as written. Everything else
	-- the integrator, the acceleration ramp, the bank, the constraints --
	is shared, because the two are not different vehicles. One of them has
	stopped looking for the ground.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)
local Ships = require(Shared.Config.Ships)
local Upgrades = require(Shared.Config.Upgrades)
local Furnishings = require(Shared.Config.Furnishings)
local Orbit = require(Shared.Config.Orbit)
local Planets = require(Shared.Config.Planets)
local Progression = require(Shared.Config.Progression)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local ShipModel = require(Shared.Rig.ShipModel)

local VehicleController = {
	name = "VehicleController",
	priority = 24,
}

local player = Players.LocalPlayer

--[[
	How hard the hover pulls back to its ride height, per stud of error.

	Stiff enough that a speeder crossing a dune does not sink into it, soft
	enough that cresting one does not throw the rider off. This is a velocity
	gain rather than a spring constant -- there is no mass in it, so it reads
	the same on every vehicle in the file.
]]
local HOVER_GAIN = 6
local HOVER_RISE = 40 -- studs/sec, climbing
local HOVER_FALL = 55 -- studs/sec, dropping back down
local FREEFALL = 90 -- studs/sec over a gap, where there is nothing to hover above

--- Reverse is a manoeuvre, not a direction of travel.
local REVERSE_FRACTION = 0.35

--[[
	The fraction of top speed a hull has to lose in one frame to have crashed.

	Braking from full throttle to nothing takes `def.acceleration` studs/sec²
	-- the fastest ramp in the file is the Dagger's 150, which at 60Hz is
	2.5 studs/sec in a frame, or well under one percent of its top speed.
	Half of top speed in a single frame is not deceleration; it is a wall.
]]
local HARD_STOP = 0.5

--[[
	How hard the hyperdrive pulls the hull up to lane speed, in studs/sec².

	Nothing to do with `ShipDef.acceleration`, which is a repulsorlift
	shoving air about at a few hundred studs a second. A lane is doing
	fifteen hundred, and reaching that at a Skipjack's 340/s² would eat a
	quarter of the crossing. Four seconds of spool, near enough, at every
	distance -- long enough to read as a drive winding up and short enough
	that the shortest jump is still mostly travel.
]]
local JUMP_ACCELERATION = 400

--[[
	Where the player has said they are going, or nil.

	Module-level rather than per-seat, because a course outlives a seat:
	the fuel is already spent, and a pilot who set one, got out to pick up a
	crate and got back in has not changed their mind. Cleared on arrival, on
	abort, and when the character is replaced.
]]
local course: string? = nil

local seated: {
	model: Model,
	def: Ships.ShipDef,
	starship: boolean,
	seat: VehicleSeat,
	chassis: BasePart,
	drive: LinearVelocity,
	attitude: AlignOrientation,
	yaw: number,
	--- Radians. Always zero on a speeder, which never reads it.
	pitch: number,
	speed: number,
	--[[
		Top speed and turn rate after the Piloting tree, resolved once.

		`Progression.computeStats` walks every node in the game, which is
		fine to do when somebody sits down and not at 60Hz. Held here rather
		than looked up per frame for that reason alone -- a rank bought
		mid-flight simply applies the next time you get in.
	]]
	speedMult: number,
	turnMult: number,
	--[[
		Which world's system the hull is in, and that world's geography.

		Resolved once on sitting down until 2026-08-29, which was honest
		while twelve thousand studs of grid was a wall. It is a road now, and
		a pilot who crosses it would otherwise spend the rest of the flight
		measuring their altitude against a world a system behind them.

		`system` is nil out in the dark between them, where none of the other
		three has a meaning -- which is why they are cached rather than read:
		the flight loop asks every frame and the answer changes about once a
		minute.
	]]
	system: string?,
	origin: Vector3,
	worldRadius: number,
	--- Where this world's atmosphere ends. Not `Ships.CEILING` everywhere:
	--- two worlds stand buildings up past it. See `Orbit.ceilingFor`.
	ceiling: number,
	--- True while in orbit, so the transition fires on the way up and not
	--- again every frame the player spends up there.
	aloft: boolean,
	--- The same latch for having flown off the side of the world, which is a
	--- different place with a different answer.
	strayed: boolean,
	--- Where the hyperdrive is taking this hull, while it is engaged.
	jumpTo: string?,
	--- Studs per second the lane is pulling toward. `Orbit.jumpSpeedFor`.
	jumpSpeed: number,
	--- Seconds the engage key has been held, and whether it was down last
	--- frame. The pair is what makes engaging a hold and aborting a press.
	engageHeld: number,
	engageDown: boolean,
	--- How fast the hull was actually moving last frame, and how fast it had
	--- been *told* to. The impact test needs both; see `HARD_STOP`.
	lastActual: number,
	lastCommand: number,
}? =
	nil

local hoverParams = RaycastParams.new()
hoverParams.FilterType = Enum.RaycastFilterType.Exclude
hoverParams.IgnoreWater = true

--[[
	The two things this file says to the rest of the client.

	Both go through `ServiceLoader.find` rather than a require, for the reason
	`Panels` gives and `raiseStarMap` repeats: a controller that failed to
	load should cost you the view, not the ability to fly.
]]
local function toast(message: string, kind: string?)
	local hud = ServiceLoader.find("HudController")
	if hud then
		hud.toast(message, kind)
	end
end

--- Height on the gauge, or nil to put it away. Starships only: on a speeder
--- it would be a permanent zero, which invites the player to try to move it.
local function showAltitude(altitude: number?, ceiling: number?, inSpace: boolean?)
	local hud = ServiceLoader.find("HudController")
	if hud then
		hud.setAltitude(altitude, ceiling, inSpace)
	end
end

--[[
	Puts the hull's condition on the HUD, read off the model's own attributes.

	Not off `ClientState`, even though the profile carries the damage. The
	model is what the server writes the moment an impact lands, and it is
	what a passenger and a bystander are both already seeing -- so reading
	it here means the gauge cannot lag the wreck it is describing, and one
	number is showing on every screen in the room.
]]
local function showIntegrity(model: Model?)
	local hud = ServiceLoader.find("HudController")
	if not hud then
		return
	end
	local current = if model then model:GetAttribute("Integrity") else nil
	local max = if model then model:GetAttribute("MaxIntegrity") else nil
	if type(current) == "number" and type(max) == "number" then
		hud.setIntegrity(current, max)
	else
		hud.setIntegrity(nil, nil)
	end
end

--- A named place and how far off it is, or nil to put the line away.
local function showBearing(caption: string?, value: string?)
	local hud = ServiceLoader.find("HudController")
	if hud then
		hud.setBearing(caption, value)
	end
end

--- Shows or hides the legend's flight rows. Only this controller knows
--- whether anybody is at a starship's controls, and CLIMB in the legend of a
--- player standing in a desert reads as the legend lying.
local function showFlightKeys(visible: boolean)
	local hud = ServiceLoader.find("HudController")
	if hud then
		hud.setFlightKeys(visible)
	end
end

--- Turns the hyperspace streaks on or off. `fraction` is how far the drive
--- has spooled up, 0..1, which is the only cue that anything is spooling.
local function showStreaks(on: boolean, fraction: number?)
	local lines = ServiceLoader.find("StarlineController")
	if lines then
		lines.setStreaking(on, fraction)
	end
end

--[[
	Tells the sky which side of the atmosphere the camera is on.

	This is the whole of "reaching space" on the client, and it is one
	boolean on purpose. Everything that makes orbit *look* like orbit --
	the stars, the black, the vacuum ambient -- is AtmosphereController's
	job, and it already owns every other thing that decides what the sky
	is doing. A second place that writes `Lighting` is a fight over it.
]]
local function enterSpace(inSpace: boolean)
	local sky = ServiceLoader.find("AtmosphereController")
	if sky then
		sky.setInSpace(inSpace)
	end
end

--[[
	THE CLIMB KEY AND THE EJECT KEY WERE THE SAME KEY

	`Ships.PITCH_UP_KEY` is Space, which is the right key for climbing and is
	also the one Roblox has already spent on getting out of a seat: a seated
	`Humanoid` that sees a jump sets `Humanoid.Jump`, and a `VehicleSeat`
	reads that as the rider asking to leave. So a player trying to reach
	orbit -- the only way to reach orbit -- was thrown out of his own ship,
	which is exactly what it looked like from the cockpit.

	Rebinding the climb would have been the cheap fix and the wrong one.
	Space is what every player already reaches for to go up, and it is the
	key Logan reached for unprompted; moving it would trade a bug nobody can
	work around for a control nobody can guess.

	So the input is sunk instead, at a priority above the default jump
	control, for exactly as long as somebody is at a starship's controls.
	This is the same shape as the `ProximityPromptService.Enabled` write
	below -- a client-only suppression of a stock behaviour that has no
	business firing while flying -- and it is undone in `release`, which
	every way of leaving a seat already goes through.

	Deliberately starships only. A speeder cannot climb, so on one of those
	Space still means what it has always meant: get off.
]]
local JUMP_ACTION = "HollowingFlightClimb"
--- Above the default jump control, which is what makes this a sink rather
--- than a race with it.
local JUMP_PRIORITY = Enum.ContextActionPriority.High.Value

--- Whether the sink is currently in force, so `onStep` can see a leak.
local jumpSunk = false

local function holdJump(hold: boolean)
	if hold == jumpSunk then
		return
	end
	jumpSunk = hold
	if hold then
		ContextActionService:BindActionAtPriority(JUMP_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, JUMP_PRIORITY, Enum.PlayerActions.CharacterJump)
	else
		ContextActionService:UnbindAction(JUMP_ACTION)
	end
end

local function findConstraints(chassis: BasePart): (LinearVelocity?, AlignOrientation?)
	local drive = chassis:FindFirstChild(ShipModel.DRIVE)
	local attitude = chassis:FindFirstChild(ShipModel.ATTITUDE)
	return (if drive and drive:IsA("LinearVelocity") then drive else nil),
		(if attitude and attitude:IsA("AlignOrientation") then attitude else nil)
end

local function release()
	local current = seated
	seated = nil
	-- Unconditionally, and before the early return. A jump left sunk is a
	-- player who can walk but never jump again, which is a far worse bug than
	-- the one it is here to fix.
	holdJump(false)
	showFlightKeys(false)
	-- With the other flight readouts, and for the same reason: standing in a
	-- yard, the condition of a speeder is nobody's live question.
	showIntegrity(nil)
	if not current then
		return
	end
	-- Getting out is the one exit from orbit that is not a descent, and the
	-- sky has no other way to learn about it.
	if current.aloft then
		enterSpace(false)
	end
	if current.starship then
		showAltitude(nil)
		showBearing(nil)
		-- A crossing is a thing the *hull* is doing, so it ends when the pilot
		-- stops being at the controls. `seated` is already nil, so this is the
		-- one exit `endJump` cannot clean up after.
		current.jumpTo = nil
		showStreaks(false)
	end
	-- Left enabled, a speeder nobody is driving keeps whatever velocity was
	-- last written into it. The server anchors it a moment later; this is what
	-- stops it drifting in the meantime.
	if current.drive.Parent then
		current.drive.VectorVelocity = Vector3.zero
		current.drive.Enabled = false
	end
	if current.attitude.Parent then
		current.attitude.Enabled = false
	end
end

local function take(seat: VehicleSeat)
	local model = ShipModel.of(seat)
	local chassis = model and model.PrimaryPart
	if not (model and chassis) then
		return
	end

	local shipId = model:GetAttribute("ShipId") :: string?
	if not shipId or not Ships.exists(shipId) then
		return
	end

	local drive, attitude = findConstraints(chassis)
	if not (drive and attitude) then
		warn(`[VehicleController] {shipId} is missing its drive constraints`)
		return
	end

	drive.Enabled = true
	attitude.Enabled = true

	local profile = ServiceLoader.get("ClientState").get()
	local skills: { [string]: number } = if profile then profile.skills else {}
	local stats = Progression.computeStats(skills)
	local fitted = if profile then profile.shipParts[shipId] else nil

	seated = {
		model = model,
		def = Ships.get(shipId),
		starship = Ships.isStarship(shipId),
		seat = seat,
		chassis = chassis,
		drive = drive,
		attitude = attitude,
		-- Starts from where the speeder is actually pointing, so mounting one
		-- that has been parked facing away does not snap it round.
		yaw = math.atan2(-chassis.CFrame.LookVector.X, -chassis.CFrame.LookVector.Z),
		pitch = 0,
		speed = 0,
		--[[
			Two multipliers into one, and it has to be a product.

			The skill number is what the *pilot* brings and the fitted part
			is what the *hull* brings, so a maxed Piloting tree and a Mk V
			engine both paying out is the correct answer -- and it is the
			only combination in the game where the character sheet and the
			garage compound. Adding them instead would make whichever you
			built second feel like it did nothing.
		]]
		speedMult = (stats.ShipSpeedMult or 1) * Upgrades.multiplier(fitted, "Engine"),
		turnMult = (stats.ShipTurnMult or 1) * Upgrades.multiplier(fitted, "Gyro"),
		lastActual = 0,
		lastCommand = 0,
		-- Left blank rather than seeded from `profile.currentPlanet`: the
		-- flight loop's first frame reads it off the hull's own position,
		-- which is the same question asked of the thing that actually knows.
		system = nil,
		origin = Vector3.zero,
		worldRadius = 0,
		ceiling = Ships.CEILING,
		aloft = false,
		strayed = false,
		jumpTo = nil,
		jumpSpeed = 0,
		engageHeld = 0,
		engageDown = false,
	}

	showIntegrity(model)
	--[[
		Watched rather than polled, and watched rather than pushed.

		The gauge has to move at the moment the crash lands, and the crash is
		decided on the server -- so the client is told by the only thing
		Roblox is already replicating, which is the attribute itself. No
		remote, no per-frame read, and it disconnects with the seat.
	]]
	local seatedNow = seated
	local watchIntegrity = model:GetAttributeChangedSignal("Integrity"):Connect(function()
		if seated == seatedNow then
			showIntegrity(model)
		end
	end)
	seat:GetPropertyChangedSignal("Occupant"):Once(function()
		watchIntegrity:Disconnect()
	end)

	if Ships.isStarship(shipId) then
		holdJump(true)
		showFlightKeys(true)
	end
end

--[[
	Raises the star map, once, for a pilot who has run out of world.

	It used to open on reaching orbit, and that was the single worst thing
	about reaching orbit: you climbed for it and were handed a panel over the
	view at the exact moment there was finally something to look at. Space is
	now a place you arrive in, and G still opens the map anywhere.

	What is left is the case the map is genuinely the answer to -- being off
	the side of the plate, where there is no planet under you to go back down
	to. Which world you go to, what it costs and whether you may is still
	TravelService's to decide; it does not take the client's word for any of
	it, so opening the panel concedes nothing.
]]
local function raiseStarMap()
	local map = ServiceLoader.find("GalaxyMapController")
	if map then
		map.setOpen(true)
	end
end

--[[
	Height above whatever is under the speeder, or nil over a gap.

	Cast from the chassis centre rather than its underside, because the
	underside is inside the collider and a ray that starts inside a part does
	not report it. The vehicle's own parts set `CanQuery = false` for the same
	reason, and the character is excluded because the rider is welded into
	this assembly and would otherwise be the ground.
]]
local function groundDistance(chassis: BasePart, reach: number): number?
	hoverParams.FilterDescendantsInstances = { chassis.Parent :: Instance, player.Character :: Instance }
	local hit = Workspace:Raycast(chassis.Position, Vector3.new(0, -reach, 0), hoverParams)
	return if hit then (chassis.Position - hit.Position).Magnitude else nil
end

--[[
	Drops the hull out of the lane and hands the controls back.

	Used by all three ways a crossing ends -- arriving, aborting, and getting
	out of the seat -- because all three want exactly the same thing done and
	a second copy of it is a second place to forget the starlines.

	The speed is pulled back to what the ship can actually do. Left at lane
	speed a pilot would drop out over a world doing fifteen hundred studs a
	second with the controls live, which is not an arrival, it is a
	projectile.
]]
local function endJump()
	local s = seated
	showStreaks(false)
	if not s then
		return
	end
	s.jumpTo = nil
	s.speed = math.min(s.speed, s.def.speed * s.speedMult)
end

--[[
	Lights the hyperdrive, or says which key is missing.

	Three refusals and every one of them names the next thing to do rather
	than the state, which is this project's most expensive recurring bug
	(2026-08-17, and three times since). "No course set" is a fact the player
	already has; the star map's key is what they do not.
]]
local function engage()
	local s = seated
	if not (s and s.starship) then
		return
	end

	local destination = course
	if not destination then
		local key = Panels.toggleKey("GalaxyMapController")
		toast(`No course set. Open the star map ({if key then key.Name else "G"}) and choose one.`, "Error")
		return
	end
	if not s.aloft then
		toast("Reach orbit before the hyperdrive will light", "Error")
		return
	end
	if destination == s.system then
		course = nil
		toast(`You are already at {Planets.get(destination).displayName}`, "Error")
		return
	end

	--[[
		Priced off where the ship is, not off `profile.currentPlanet`.

		A pilot who set a course, flew out into the void and then engaged has
		already covered part of the distance, and charging them the duration
		of a crossing they have started is the sort of arithmetic that makes
		a player stop trusting the instrument. Out in deep space the nearest
		world is the honest answer to "from where".
	]]
	local from = s.system or (Orbit.nearestSystem(s.chassis.Position))
	s.jumpTo = destination
	s.jumpSpeed = Orbit.jumpSpeedFor(from, destination)
	showStreaks(true, 0)
	toast(`Hyperdrive engaged -- {Planets.get(destination).displayName}`, "Success")
end

local function onStep(dt: number)
	local s = seated
	--[[
		The sink is re-checked against the truth every frame rather than only
		being undone on the way out.

		`release` already unbinds it unconditionally, and every exit path is
		*supposed* to go through `release`. But the cost of that reasoning
		being wrong once -- a seat vacated by something that does not touch
		`SeatPart`, a `release` that raised halfway -- is a player who can
		walk and never jump again for the rest of the session, with no way to
		tell what happened or to undo it. That is the worst class of bug this
		project can ship, and it is the one 2026-08-29's play test reported.

		So: the binding follows "is this player at a starship's controls right
		now", asked from scratch sixty times a second, and can be wrong for at
		most one frame.
	]]
	if jumpSunk and not (s and s.starship) then
		holdJump(false)
	end
	if not s then
		return
	end
	if not s.chassis.Parent or s.seat.Occupant == nil then
		release()
		return
	end

	local def = s.def
	local turnRate = math.rad(def.turnSpeed) * s.turnMult

	-- Yaw is integrated so a held key turns at a rate rather than snapping to
	-- an angle, which is the difference between steering and pointing.
	s.yaw -= s.seat.Steer * turnRate * dt

	if s.starship then
		--[[
			The engage key is *held*, not tapped, because engaging costs fuel
			and locks the controls away for twenty seconds -- the two things a
			mis-keyed press must never do. Aborting is a fresh press and takes
			effect instantly, because that is a panic button and a panic
			button you have to hold is not one.

			`engageDown` is what makes the release matter: without it the same
			held key that lit the drive would abort the jump on the very next
			frame.
		]]
		local held = UserInputService:IsKeyDown(Ships.ENGAGE_KEY)
		if s.jumpTo then
			if held and not s.engageDown then
				endJump()
				toast("Hyperdrive disengaged", "Info")
			end
		elseif held then
			s.engageHeld += dt
			if s.engageHeld >= Ships.ENGAGE_HOLD then
				s.engageHeld = 0
				engage()
			end
		else
			s.engageHeld = 0
		end
		s.engageDown = held
	end

	local lane = s.jumpTo
	if lane then
		--[[
			In the lane the heading is written, not steered. Taking the
			controls away is what makes a crossing a crossing rather than
			twenty seconds of holding W, and it is the only thing that makes
			arrival deterministic -- the drop-out test below is a distance to
			a fixed point, and a pilot who could steer could miss it forever.
		]]
		local toward = Orbit.arrivalPointFor(lane) - s.chassis.Position
		local direction = if toward.Magnitude > 1 then toward.Unit else -s.chassis.CFrame.LookVector
		s.yaw = math.atan2(-direction.X, -direction.Z)
		s.pitch = math.asin(math.clamp(direction.Y, -1, 1))
	elseif s.starship then
		--[[
			Pitch is integrated the same way and then *decays* to level when
			neither key is held. A held angle would mean a player who nosed up
			to clear a ridge and let go is still climbing a minute later, in
			a game where the only reference is a horizon they can no longer
			see. Levelling itself is the flight model's one act of mercy.
		]]
		local up = UserInputService:IsKeyDown(Ships.PITCH_UP_KEY)
		local down = UserInputService:IsKeyDown(Ships.PITCH_DOWN_KEY)
		local input = (if up then 1 else 0) - (if down then 1 else 0)
		if input ~= 0 then
			local limit = math.rad(Ships.MAX_PITCH)
			s.pitch = math.clamp(s.pitch + input * turnRate * dt, -limit, limit)
		else
			s.pitch -= math.clamp(s.pitch, -turnRate * dt, turnRate * dt)
		end
	end

	local throttle = s.seat.Throttle
	local target = def.speed * s.speedMult * throttle * (if throttle < 0 then REVERSE_FRACTION else 1)
	local step = def.acceleration * dt
	if lane then
		-- The throttle is ignored too. A lane runs at one speed, and its own
		-- acceleration is used because a hull's is tuned for a dogfight and
		-- would spend half the crossing spooling up.
		target = s.jumpSpeed
		step = JUMP_ACCELERATION * dt
	end
	s.speed += math.clamp(target - s.speed, -step, step)

	local heading = CFrame.Angles(0, s.yaw, 0) * CFrame.Angles(s.pitch, 0, 0)
	local velocity = heading.LookVector * s.speed

	if s.starship then
		local below = groundDistance(s.chassis, Ships.CEILING)
		if below and below < def.hoverHeight then
			-- Never a downward push, only a floor. A starship that is climbing
			-- harder than the correction keeps its own climb.
			velocity = Vector3.new(
				velocity.X,
				math.max(velocity.Y, math.min((def.hoverHeight - below) * HOVER_GAIN, HOVER_RISE)),
				velocity.Z
			)
		end

		--[[
			Reaching orbit used to be "the downward ray found nothing", and
			that was two bugs in one line.

			An empty ray means one of two opposite things and cannot tell you
			which. Past the rim of the plate it finds no ground however low
			you are -- so a starship could reach space by driving sideways off
			a cliff at fifty studs. And on Coruscant, which has no ground at
			all, it finds nothing anywhere, so the whole city was in orbit.

			Two questions, asked separately. *How high* is the hull's own Y,
			since every world is built with its ground at zero. *Over what* is
			horizontal distance from the world's origin against the radius
			`PlanetBuilder` filled the terrain to. Being high over the world
			is orbit; being anywhere over nothing is having left it; and the
			ray goes back to the one job it is good at, which is finding the
			floor to push off.
		]]
		local position = s.chassis.Position
		local system = Orbit.systemAt(position)
		if system ~= s.system then
			s.system = system
			if system then
				s.origin = Planets.originFor(system)
				s.worldRadius = Planets.worldRadius(system)
				s.ceiling = Orbit.ceilingFor(system)
			end
		end

		if not system then
			--[[
				DEEP SPACE IS A PLACE NOW, NOT AN ERROR

				This branch used to be one line further down, and it toasted
				*"Beyond the world's edge"* and threw the star map over the
				view. That was the honest answer while there was nowhere to
				go: the nine worlds sat 12,000 studs apart in one Workspace
				and nothing crossed the gap, so leaving one was a mistake by
				definition.

				It is a road now. Being between worlds is where you are for
				most of a crossing, and warning a player about the middle of
				the journey they set out on is the game arguing with them.

				G still opens the star map anywhere, which is the escape
				hatch that means nobody out here can be stranded.
			]]
			if not s.aloft then
				enterSpace(true)
			end
			s.aloft = true
			s.strayed = false

			-- The altimeter has nothing to measure against out here -- no
			-- ground, no ceiling, and a Y that means nothing on its own. The
			-- bearing line below is what replaces it.
			showAltitude(nil)
		else
			local altitude = position.Y
			local flat = position - s.origin
			local overWorld = Vector3.new(flat.X, 0, flat.Z).Magnitude <= s.worldRadius
			-- Asymmetric on purpose: you leave the atmosphere at the ceiling
			-- and re-enter it a little below. `Orbit.REENTRY_DROP` says why.
			local threshold = if s.aloft then s.ceiling - Orbit.REENTRY_DROP else s.ceiling
			local aloft = altitude >= threshold
			--[[
				The one shape of "nowhere" still worth a warning: off the rim
				of the plate, low, and inside a system all the same. No ground
				under you and not high enough to be in orbit either -- which
				is a player who rode off a cliff, not one who set out.

				`aloft` no longer asks whether you are over the plate. It did
				while off-the-plate was an error state; now that drifting past
				the rim at altitude is simply the first thousand studs of a
				crossing, the height alone is the question.
			]]
			local strayed = below == nil and not overWorld and not aloft

			if aloft ~= s.aloft then
				enterSpace(aloft)
			end
			if strayed and not s.strayed then
				toast("Beyond the world's edge -- set a course", "Error")
				raiseStarMap()
			end
			s.aloft = aloft
			s.strayed = strayed

			showAltitude(altitude, s.ceiling, aloft)
		end

		if lane then
			--[[
				Dropping out is a distance, not a timer.

				`Orbit.ARRIVAL_RADIUS` is 2,400 and `SYSTEM_RADIUS` is 3,600,
				so the destination has already become the player's world a
				beat *before* the streaks stop -- its sky, its weather, its
				crowd and its mission board are all in place by the time
				there is anything to look at.
			]]
			local away = (Orbit.arrivalPointFor(lane) - position).Magnitude
			showStreaks(true, if s.jumpSpeed > 0 then math.clamp(s.speed / s.jumpSpeed, 0, 1) else 1)
			showBearing("HYPERSPACE", `{Planets.get(lane).displayName}  {math.floor(away)}`)
			if away <= Orbit.ARRIVAL_RADIUS then
				endJump()
				course = nil
				toast(`Dropping out over {Planets.get(lane).displayName}`, "Success")
			end
		elseif course then
			-- A course bought and not yet flown. The distance counts down as
			-- you close on it under your own power, so a pilot who never
			-- engages still arrives, slowly, which is the point of Part 1.
			local held = course :: string
			local away = (Orbit.arrivalPointFor(held) - position).Magnitude
			showBearing("COURSE", `{Planets.get(held).displayName}  {math.floor(away)}`)
		elseif not system then
			-- Nowhere in particular and nowhere to be. Which way is home is
			-- the only thing left worth saying.
			local nearest, away = Orbit.nearestSystem(position)
			showBearing("DEEP SPACE", `{Planets.get(nearest).displayName}  {math.floor(away)}`)
		else
			showBearing(nil)
		end
	else
		local vertical: number
		local distance = groundDistance(s.chassis, def.hoverHeight * 3)
		if distance then
			vertical = math.clamp((def.hoverHeight - distance) * HOVER_GAIN, -HOVER_FALL, HOVER_RISE)
		else
			-- Nothing within reach to push against. Riding off a cliff should
			-- be a fall, not a hover at altitude, and the hover catches it
			-- again as soon as the ground comes back into range.
			vertical = -FREEFALL
		end
		velocity = Vector3.new(velocity.X, vertical, velocity.Z)
	end

	s.drive.VectorVelocity = velocity
	-- Lean into the turn. Purely cosmetic -- the heading above has already
	-- decided where the vehicle goes -- and it is most of what makes a swoop
	-- feel different from a cargo sled.
	s.attitude.CFrame = heading * CFrame.Angles(0, 0, -s.seat.Steer * math.rad(def.bank))

	--[[
		A CRASH IS THE SPEED YOU DID NOT KEEP

		No `Touched` connections, no collision groups, no hitboxes. The hull
		is a real physics body being *commanded* to a velocity by the
		constraint above, so when it meets a wall the command does not
		change and the body's own speed collapses. The gap between the two
		is the crash, and it is one property read per frame on a part this
		loop is already holding.

		That is not a shortcut -- it is the only version that works
		everywhere this vehicle can go. It costs nothing on nine worlds of
		procedurally generated geometry that nobody tagged, it catches a
		canyon wall and a docking gantry and another player's parked
		freighter with the same line, and it cannot be fooled by geometry
		the builder forgot to mark as solid.

		`HARD_STOP` is what separates a crash from a hill. Cresting a dune
		or scraping a wall bleeds speed over several frames; hitting
		something loses most of it inside one. The threshold is a fraction
		of the hull's own top speed rather than a constant, so a Swoop and a
		HoverSled agree about what counts as an accident.

		WHAT THE THROTTLE ASKED FOR HAS TO COME OFF THE TOP
		Speed the hull gave up because the *pilot* gave it up is not a
		crash, and the first draft of this could not tell the difference.
		Dropping out of hyperspace sheds about eleven hundred studs a second
		inside one frame -- so every arrival in the game, at the end of every
		journey the player paid a fare for, would have wrecked the ship they
		arrived in. Lifting off the throttle is a milder version of the same
		lie.

		Subtracting the fall in the *commanded* speed leaves only the part
		nobody asked for, which is the definition of a collision: still
		holding W, and no longer moving.
	]]
	local actual = s.chassis.AssemblyLinearVelocity.Magnitude
	local unbidden = (s.lastActual - actual) - (s.lastCommand - s.speed)
	s.lastActual = actual
	s.lastCommand = s.speed
	if unbidden > def.speed * HARD_STOP then
		Net.fireServer(Net.Event.VehicleImpact, unbidden)
	end
end

function VehicleController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		-- A panel has the keyboard. Summoning a speeder out from under a shop
		-- window is not what pressing a letter in a menu should ever mean.
		if Panels.anyOpen() then
			return
		end
		if input.KeyCode == Ships.SUMMON_KEY then
			Net.fireServer(Net.Event.SummonVehicle)
		elseif input.KeyCode == Furnishings.BOARD_KEY then
			-- Boarding lives with summoning rather than in a controller of
			-- its own: it is the same hull, the same one key press, and the
			-- server decides whether there is a ship to board.
			Net.fireServer(Net.Event.ToggleCabin)
		end
	end)

	--[[
		Seat changes are watched on the humanoid rather than on any particular
		vehicle, because there is no moment at which this controller is told
		which speeder it is about to be sitting in. `SeatPart` is the one
		signal that fires for every way a rider can end up on or off one --
		walking into it, being thrown off it, the server dismissing it out
		from under them, or dying.
	]]
	--[[
		A PROMPT IS FOR SOMEBODY WHO IS NOT ON BOARD YET

		The boarding prompt hangs above the hull and is the only way into a
		ship, so it has to stay live while anyone is flying -- that is how the
		second brother gets in the back. But it also follows the driver around
		the planet, which is what he reported: a `Ride` label parked in the
		middle of his windscreen for the whole journey.

		Turning the whole service off for the duration is a client-only write
		to a property the server never touches, so it cannot race the
		`Enabled` flag VehicleService is keeping honest on the prompt itself.
		It is also the right answer rather than merely the cheap one: every
		prompt in this game -- vendors, terminals, dropped loot, this -- is
		something you would have to get off the speeder to use anyway.

		Deliberately keyed on being in *a ship*, not on driving one. A
		passenger is riding too, and a chair in the player's cabin is not a
		ship at all.
	]]
	local function bind(character: Model)
		release()
		ProximityPromptService.Enabled = true
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not (humanoid and humanoid:IsA("Humanoid")) then
			return
		end
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			local seat = humanoid.SeatPart
			ProximityPromptService.Enabled = seat == nil or ShipModel.of(seat) == nil
			if seat and seat:IsA("VehicleSeat") then
				take(seat)
			else
				release()
			end
		end)
	end

	--[[
		The course is only ever set by the server saying so.

		The client could perfectly well remember which world was clicked, and
		it would be wrong every time the fare bounced -- not enough credits,
		too low a level, no hull at the controls. A course the player has not
		paid for is a HUD line counting down to a jump that will never light.
	]]
	Net.onClientEvent(Net.Event.CourseSet, function(planetId: string)
		course = planetId
	end)

	--[[
		Getting out, which stopped being possible in a starship the moment the
		climb fix sank the jump. `Ships.EXIT_KEY` says why it is this key.

		It writes `Humanoid.Sit = false` rather than touching the seat,
		because that is exactly what the stock jump did and so it arrives at
		the server through the same door: `VehicleService` refuses a dismount
		in orbit and re-seats you, and an exit that went around that would be
		a way to step out into vacuum.
	]]
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.KeyCode ~= Ships.EXIT_KEY then
			return
		end
		local s = seated
		local occupant = s and s.seat.Occupant
		if occupant then
			occupant.Sit = false
		end
	end)

	player.CharacterAdded:Connect(function(character: Model)
		-- Dying is not an abort, but it does end the crossing, and a course
		-- that outlived the pilot would light the drive again on the next
		-- press without charging for it.
		course = nil
		showStreaks(false)
		bind(character)
	end)
	local existing = player.Character
	if existing then
		bind(existing)
	end

	RunService.Heartbeat:Connect(onStep)
end

return VehicleController
