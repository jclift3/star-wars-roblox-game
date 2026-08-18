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
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)
local Ships = require(Shared.Config.Ships)
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
	seat: VehicleSeat,
	chassis: BasePart,
	drive: LinearVelocity,
	attitude: AlignOrientation,
	yaw: number,
	speed: number,
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

	seated = {
		model = model,
		def = Ships.get(shipId),
		seat = seat,
		chassis = chassis,
		drive = drive,
		attitude = attitude,
		-- Starts from where the speeder is actually pointing, so mounting one
		-- that has been parked facing away does not snap it round.
		yaw = math.atan2(-chassis.CFrame.LookVector.X, -chassis.CFrame.LookVector.Z),
		speed = 0,
	}
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

	-- Yaw is integrated so a held key turns at a rate rather than snapping to
	-- an angle, which is the difference between steering and pointing.
	s.yaw -= s.seat.Steer * math.rad(def.turnSpeed) * dt

	local throttle = s.seat.Throttle
	local target = def.speed * throttle * (if throttle < 0 then REVERSE_FRACTION else 1)
	local step = def.acceleration * dt
	s.speed += math.clamp(target - s.speed, -step, step)

	local heading = CFrame.Angles(0, s.yaw, 0)

	local vertical: number
	local distance = groundDistance(s.chassis, def.hoverHeight * 3)
	if distance then
		vertical = math.clamp((def.hoverHeight - distance) * HOVER_GAIN, -HOVER_FALL, HOVER_RISE)
	else
		-- Nothing within reach to push against. Riding off a cliff should be
		-- a fall, not a hover at altitude, and the hover catches it again as
		-- soon as the ground comes back into range.
		vertical = -FREEFALL
	end

	s.drive.VectorVelocity = heading.LookVector * s.speed + Vector3.new(0, vertical, 0)
	-- Lean into the turn. Purely cosmetic -- the heading above has already
	-- decided where the speeder goes -- and it is most of what makes a swoop
	-- feel different from a cargo sled.
	s.attitude.CFrame = heading * CFrame.Angles(0, 0, -s.seat.Steer * math.rad(def.bank))
end

function VehicleController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.KeyCode ~= Ships.SUMMON_KEY then
			return
		end
		-- A panel has the keyboard. Summoning a speeder out from under a shop
		-- window is not what pressing a letter in a menu should ever mean.
		if Panels.anyOpen() then
			return
		end
		Net.fireServer(Net.Event.SummonVehicle)
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
