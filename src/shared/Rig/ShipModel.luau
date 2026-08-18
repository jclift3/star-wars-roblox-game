--!strict
--[[
	ShipModel.luau

	Turns a ShipDef's part list into a driveable vehicle.

	Mirrors WeaponModel: the config holds shape and the rig module holds
	assembly, so adding a speeder is a table entry and never a code change.
	The two files do not share a builder even though they both walk a list of
	part specs, because the interesting half is different in each -- a weapon
	ends with a muzzle attachment and a swing trail, a vehicle ends with a
	seat, a collider and two constraints.

	THE PHYSICS ROOT IS AN INVISIBLE CHASSIS, NOT THE SEAT
	The obvious build makes the VehicleSeat the PrimaryPart, and it turns
	badly: the seat is off-centre on anything with a passenger, so the whole
	vehicle yaws about the driver's hip instead of about itself. A chassis
	part at the hull origin fixes that and earns its keep twice over -- it is
	also the only part with mass and the only part that collides, so the
	speeder has one predictable centre of gravity and one collision box
	instead of thirty concave ones.

	THE CONSTRAINTS ARE BUILT HERE, DISABLED
	Same reasoning as the weapon's swing trail. The model is made on the
	server and replicated, so building the constraints into it means the
	client that ends up driving finds them already there and only has to
	switch them on. A client that creates its own physics constraints on a
	replicated model is a client the server has to trust about their limits.
]]

local Ships = require(script.Parent.Parent.Config.Ships)

local ShipModel = {}

ShipModel.DRIVER_SEAT = "DriverSeat"
ShipModel.CHASSIS = "Chassis"
ShipModel.DRIVE = "Drive"
ShipModel.ATTITUDE = "Attitude"

local function resolveShape(shape: string?): (Enum.PartType, boolean)
	if shape == "Ball" then
		return Enum.PartType.Ball, false
	elseif shape == "Cylinder" then
		return Enum.PartType.Cylinder, false
	elseif shape == "Wedge" then
		return Enum.PartType.Block, true
	end
	return Enum.PartType.Block, false
end

local function specCFrame(spec: Ships.ShipPart): CFrame
	local rot = spec.rot or Vector3.zero
	return CFrame.new(spec.offset) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
end

--- `lit` is false for ambient traffic; see `ShipModel.buildTraffic`.
local function buildPart(spec: Ships.ShipPart, lit: boolean): BasePart
	local shapeType, isWedge = resolveShape(spec.shape)

	local p: BasePart
	if isWedge then
		p = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		block.Shape = shapeType
		p = block
	end

	p.Name = spec.name
	p.Size = spec.size
	p.Color = spec.color or Color3.fromRGB(120, 122, 128)
	p.Material = spec.material or Enum.Material.Metal
	p.Transparency = spec.transparency or 0
	p.Reflectance = spec.reflectance or 0
	p.CanCollide = false -- the chassis is the collider; see the header
	p.CanQuery = false -- must not block the hover raycast fired from inside it
	p.CanTouch = false
	p.Massless = true

	if lit and spec.light then
		local light = Instance.new("PointLight")
		light.Color = spec.light.color
		light.Range = spec.light.range
		light.Brightness = spec.light.brightness
		light.Shadows = false
		light.Parent = p
	end

	return p
end

--[[
	The axis-aligned box that contains every part, in hull-local studs.

	Computed rather than declared so a speeder cannot be given a collider
	that disagrees with its own geometry -- the failure that produces is a
	vehicle that stops a stud short of walls, or clips through them, and it
	is invisible in the config either way.
]]
local function halfExtent(cf: CFrame, size: Vector3): Vector3
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) * 0.5
end

local function boundingSize(def: Ships.ShipDef): (Vector3, Vector3)
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = -min

	for _, spec in def.parts do
		local half = halfExtent(specCFrame(spec), spec.size)
		min = min:Min(spec.offset - half)
		max = max:Max(spec.offset + half)
	end

	return max - min, (max + min) * 0.5
end

local function buildSeat(name: string, size: Vector3, offset: Vector3, vehicle: boolean): BasePart
	local seat: BasePart = if vehicle then Instance.new("VehicleSeat") else Instance.new("Seat")
	seat.Name = name
	seat.Size = size
	seat.Color = Color3.fromRGB(38, 38, 42)
	seat.Material = Enum.Material.Fabric
	seat.CanCollide = false
	seat.CanQuery = false
	-- Seats are entered through Touched, so this one property is the whole
	-- difference between furniture and a vehicle.
	seat.CanTouch = true
	seat.Massless = true
	seat.CFrame = CFrame.new(offset)
	return seat
end

--[[
	Builds an unparented, unpositioned speeder, pivoted on its hull centre.

	The caller places it. Nothing here reads the world, so this is safe to
	call before deciding where the thing is going to end up.
]]
function ShipModel.build(shipId: string): Model
	local def = Ships.get(shipId)

	local model = Instance.new("Model")
	model.Name = shipId
	model:SetAttribute("ShipId", shipId)

	local size, centre = boundingSize(def)

	local chassis = Instance.new("Part")
	chassis.Name = ShipModel.CHASSIS
	-- Slightly inside the visible shell: a collider flush with the bodywork
	-- catches on doorways the speeder visibly fits through.
	chassis.Size = size * 0.92
	chassis.CFrame = CFrame.new(centre)
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.CanQuery = false
	chassis.CanTouch = false
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.2, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local root = Instance.new("Attachment")
	root.Name = "RootAttachment"
	root.Parent = chassis

	local function attach(p: BasePart)
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = p
		weld.Parent = p
	end

	for _, spec in def.parts do
		local p = buildPart(spec, true)
		p.CFrame = specCFrame(spec)
		attach(p)
	end

	attach(buildSeat(ShipModel.DRIVER_SEAT, def.seatSize, def.seatOffset, true))
	for i, offset in def.passengerOffsets do
		attach(buildSeat(`Passenger{i}`, def.seatSize, offset, false))
	end

	--[[
		Velocity, not force.

		A repulsorlift is not a car: there is no traction to model and no
		reason for a speeder to keep sliding after the rider lets go. Driving
		the velocity directly makes the handling exactly what the config
		says it is, on every planet, regardless of the gravity the world
		happens to be using -- which matters here, because `PlanetDef.gravity`
		varies and a force-driven hover would need retuning per world.
	]]
	local drive = Instance.new("LinearVelocity")
	drive.Name = ShipModel.DRIVE
	drive.Attachment0 = root
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	drive.VectorVelocity = Vector3.zero
	drive.MaxForce = math.huge
	drive.Enabled = false
	drive.Parent = chassis

	-- Holds the hull at a heading the driver integrates, which is also what
	-- keeps it upright: a speeder that can pitch and roll freely ends every
	-- collision on its back.
	local attitude = Instance.new("AlignOrientation")
	attitude.Name = ShipModel.ATTITUDE
	attitude.Mode = Enum.OrientationAlignmentMode.OneAttachment
	attitude.Attachment0 = root
	attitude.RigidityEnabled = false
	attitude.MaxTorque = math.huge
	attitude.Responsiveness = 40
	attitude.Enabled = false
	attitude.Parent = chassis

	return model
end

--[[
	Builds a traffic hull: the same parts, none of the machinery.

	No chassis, no seats, no constraints and no collision -- an ambient hull
	is a picture of a ship, and every one of those costs something to a
	thing that exists twenty-six at a time and is never within a hundred
	studs of the player. It is anchored instead, and whoever built it moves
	it by `PivotTo`.

	The root is an empty part at the hull origin rather than the model's
	bounding box, because the bounding box centre is not the nose-to-tail
	middle of anything with a container on its back, and a lane's position
	means "where the ship is", not "where the average of its parts is".

	Nothing here gets a PointLight, which is why `buildPart` takes a flag.
	The turbines are shared with the ships players fly, where the glow
	throwing light on the road is the point; up in a lane it lights nothing
	and is charged for anyway, once per engine per hull.
]]
function ShipModel.buildTraffic(hull: Ships.TrafficHull): Model
	local model = Instance.new("Model")
	model.Name = hull.id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	for _, spec in hull.parts do
		local p = buildPart(spec, false)
		p.CFrame = specCFrame(spec)
		p.Anchored = true
		p.CastShadow = false
		p.Parent = model
	end

	return model
end

--- The driver's seat of a built speeder, or nil if this is not one.
function ShipModel.driverSeat(model: Model): VehicleSeat?
	local seat = model:FindFirstChild(ShipModel.DRIVER_SEAT)
	return if seat and seat:IsA("VehicleSeat") then seat else nil
end

--- The speeder a seat belongs to, walking up from any seat in it.
function ShipModel.of(seat: BasePart): Model?
	local model = seat.Parent
	if model and model:IsA("Model") and model:GetAttribute("ShipId") ~= nil then
		return model
	end
	return nil
end

return ShipModel
