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

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)
local Ships = require(Shared.Config.Ships)
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

--- A named place and how far off it is, or nil to put the line away.
local function showBearing(caption: string?, value: string?)
	local hud = ServiceLoader.find("HudController")
	if hud then
		hud.setBearing(caption, value)
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

local function findConstraints(chassis: BasePart): (LinearVelocity?, AlignOrientation?)
	local drive = chassis:FindFirstChild(ShipModel.DRIVE)
	local attitude = chassis:FindFirstChild(ShipModel.ATTITUDE)
	return (if drive and drive:IsA("LinearVelocity") then drive else nil),
		(if attitude and attitude:IsA("AlignOrientation") then attitude else nil)
end

local function release()
	local current = seated
	seated = nil
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
		speedMult = stats.ShipSpeedMult or 1,
		turnMult = stats.ShipTurnMult or 1,
		-- Left blank rather than seeded from `profile.currentPlanet`: the
		-- flight loop's first frame reads it off the hull's own position,
		-- which is the same question asked of the thing that actually knows.
		system = nil,
		origin = Vector3.zero,
		worldRadius = 0,
		ceiling = Ships.CEILING,
		aloft = false,
		strayed = false,
	}
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

local function onStep(dt: number)
	local s = seated
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
			-- ground, no ceiling, and a Y that means nothing on its own. What
			-- the player wants instead is which way is home.
			local nearest, away = Orbit.nearestSystem(position)
			showAltitude(nil)
			showBearing("DEEP SPACE", `{Planets.get(nearest).displayName}  {math.floor(away)}`)
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

			showBearing(nil)
			showAltitude(altitude, s.ceiling, aloft)
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

	player.CharacterAdded:Connect(bind)
	local existing = player.Character
	if existing then
		bind(existing)
	end

	RunService.Heartbeat:Connect(onStep)
end

return VehicleController
