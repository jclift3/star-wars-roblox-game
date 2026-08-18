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
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)
local Ships = require(Shared.Config.Ships)
local Furnishings = require(Shared.Config.Furnishings)
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
	--- True while above `Ships.CEILING`, so the star map opens on the way up
	--- and not again every frame the player spends up there.
	aloft: boolean,
}? =
	nil

local hoverParams = RaycastParams.new()
hoverParams.FilterType = Enum.RaycastFilterType.Exclude
hoverParams.IgnoreWater = true

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
		aloft = false,
	}
end

--[[
	Raises the star map, once, on the way out of the atmosphere.

	This is the whole of "leaving the planet" on the client, and it is
	deliberately only a panel: which world you go to, what it costs and
	whether you may is decided by TravelService, which does not take the
	client's word for any of it. Nothing is gained by reaching this height
	that pressing G on the ground would not also give you -- except the one
	thing that matters, which is that it happens at the moment it means
	something.

	Resolved through the loader rather than required, for the reason
	`Panels` gives: a controller that failed to load should cost you the map,
	not the ability to fly.
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
		--[[
			One ray does both jobs, and its length is the only reason it can.

			Cast the full ceiling, and the two answers that come back are the
			two the flight loop needs: a hit closer than the hull's own ride
			height is a floor to be pushed off, and no hit at all means there
			is nothing within `Ships.CEILING` underneath -- which is what
			leaving a planet looks like from inside the cockpit.

			Flying off the *edge* of a world's terrain plate reads as nil too,
			at any altitude. That is not a false positive worth guarding: past
			the edge of the ground there is no more planet, and offering the
			star map is the right answer to being there.
		]]
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

		local aloft = below == nil
		if aloft and not s.aloft then
			raiseStarMap()
		end
		s.aloft = aloft
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
	local function bind(character: Model)
		release()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not (humanoid and humanoid:IsA("Humanoid")) then
			return
		end
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			local seat = humanoid.SeatPart
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
