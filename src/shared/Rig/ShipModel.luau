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
ShipModel.PROMPT = "Board"
ShipModel.BOARD_POINT = "BoardPoint"

--[[
	Shared with VehicleService, which flips the boarding prompt between the two
	as the pilot's seat fills and empties. Two files reading one word each is
	how a label and the rule it describes drift apart.
]]
ShipModel.PILOT_TEXT = "Pilot"
ShipModel.RIDE_TEXT = "Ride"

--- How far above the hull the boarding prompt floats. See `ShipModel.build`.
local BOARD_CLEARANCE = 3

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

--[[
	A seat. Nothing about it is how the player gets into it; see `build`.

	NOTHING IN THIS FILE CAN BE SAT ON BY WALKING INTO IT
	Reported from play twice, 2026-08-19: *"I was able to sit in the ship but
	it doesn't move"*, and then, after a fix aimed at which seat he had landed
	in, *"I'm still not able to drive."*

	The reason is above, in the header that is proud of it: the chassis is
	sized to the whole bounding box and is the only part that collides. Every
	seat offset in `Ships.luau` is comfortably inside that box, so the seats
	are not furniture the player can reach -- they are sealed in a solid
	invisible shell. On the Hover-Sled the driver's seat's top face is seven
	tenths of a stud beneath the chassis roof, and a character standing on the
	hull is standing on that roof. `Touched` cannot fire between two parts that
	never overlap.

	Which makes "sitting down" a question of whether the physics solver let the
	character penetrate the collider for a frame on the way in. It did once. It
	is not something to fix by tuning, because there is no seat position that is
	both inside the hull, where a seat belongs, and outside the collider, which
	is drawn around the hull by definition.

	So `CanTouch` is off and boarding is a `ProximityPrompt`, the same verb this
	game already uses for vendors, terminals and dropped loot. It works
	regardless of geometry, and it says out loud that the ship can be boarded
	at all.

	The prompt is emphatically *not* on the seat, though the first attempt at
	this put it there and that attempt was reported as *"holding E does
	nothing, I've stood on all sides without ever seeing a prompt"*. A prompt
	draws a billboard at its parent, a seat is in the middle of the hull, and
	the hull is opaque -- so the label was being drawn correctly and painted
	over by the ship every frame. See `build`, which hangs it in clear air.
]]
local function buildSeat(name: string, size: Vector3, offset: Vector3, vehicle: boolean): BasePart
	local seat: BasePart = if vehicle then Instance.new("VehicleSeat") else Instance.new("Seat")
	seat.Name = name
	seat.Size = size
	seat.Color = Color3.fromRGB(38, 38, 42)
	seat.Material = Enum.Material.Fabric
	seat.CanCollide = false
	seat.CanQuery = false
	seat.CanTouch = false
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
		ONE PROMPT, AND IT HANGS IN THE AIR ABOVE THE HULL

		Not one per seat, and not at a seat. A `ProximityPrompt` draws its
		label at its parent, and every seat this file makes is buried in the
		middle of an opaque ship, so a prompt on a seat is a billboard behind
		a wall: correct, active, and painted over. That was reported from play
		as a prompt that never appeared at all.

		Hanging it three studs clear of the top of the bounding box puts it in
		open sky from every angle a player can stand at, which is the whole
		point -- the label is the only thing that tells them the ship can be
		boarded. `RequiresLineOfSight` stays off for the one angle that is
		still blocked, looking up at it from underneath.

		One prompt rather than one per seat because the seat you get is not a
		choice worth a menu: VehicleService puts you at the controls if they
		are free and in the back if they are not, and rewrites `ActionText` so
		the label says which of those is about to happen.

		The reach is derived from the hull, because a prompt centred on a
		forty-stud freighter is a long way from someone standing at its ramp.
	]]
	local board = Instance.new("Attachment")
	board.Name = ShipModel.BOARD_POINT
	board.Position = Vector3.new(0, size.Y * 0.5 + BOARD_CLEARANCE, 0)
	board.Parent = chassis

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = ShipModel.PROMPT
	prompt.ActionText = ShipModel.PILOT_TEXT
	prompt.ObjectText = def.displayName
	prompt.KeyboardKeyCode = Ships.BOARD_PROMPT_KEY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = math.max(16, size.Magnitude)
	prompt.RequiresLineOfSight = false
	prompt.Parent = board

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
	A hull with none of the machinery: parts, anchored, and nothing else.

	No chassis, no seats, no constraints and no collision -- this is a
	picture of a ship, and every piece of machinery costs something to a
	thing that exists twenty-six at a time in a skylane, or six at a time on
	a racing circuit, and is never driven by anybody. Whoever built it moves
	it by `PivotTo`.

	The root is an empty part at the hull origin rather than the model's
	bounding box, because the bounding box centre is not the nose-to-tail
	middle of anything with a container on its back, and a position means
	"where the ship is", not "where the average of its parts is".

	Nothing here gets a PointLight, which is why `buildPart` takes a flag.
	The turbines are shared with the ships players fly, where the glow
	throwing light on the road is the point; on something the player is not
	sitting in it lights nothing and is charged for anyway, once per engine.

	`floor` is a transparency nothing may be more solid than. Zero leaves
	the hull exactly as its config draws it; a ghost passes something higher.

	`scale` multiplies every size and every offset, which is the only honest
	way to make a traffic hull bigger: the alternative is re-authoring forty
	part offsets by hand, and the first one that is missed puts an engine
	through a wing. It applies to `size` and `offset` and deliberately not to
	`rot` -- a rotation does not have a length.
]]
local function staticHull(name: string, parts: { Ships.ShipPart }, floor: number, scale: number): Model
	local model = Instance.new("Model")
	model.Name = name

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

	for _, spec in parts do
		local p = buildPart(spec, false)
		local at = specCFrame(spec)
		if scale ~= 1 then
			p.Size *= scale
			at = at.Rotation + at.Position * scale
		end
		p.CFrame = at
		p.Transparency = math.max(p.Transparency, floor)
		p.Anchored = true
		p.CastShadow = false
		p.Parent = model
	end

	return model
end

--- An ambient sky-traffic hull, at whatever size its config asks for.
function ShipModel.buildTraffic(hull: Ships.TrafficHull): Model
	return staticHull(hull.id, hull.parts, 0, hull.scale or 1)
end

--[[
	A see-through, unpiloted copy of a real speeder.

	A rival on a racing circuit, and it is a ghost rather than a vehicle for
	a reason that is not laziness. A solid rival is a rival that can be
	parked across the start line, rammed off a corner, or shunted round the
	lap by whichever brother worked that out first -- and the two players
	this is for share a room, so it would be worked out. Nothing you can
	touch can be used against you, and nothing you can touch can be used
	against your brother either.

	It is also the honest shape for what these are: their positions are pure
	functions of elapsed time, so a rival that could be knocked off its line
	would be lying about where it is anyway.
]]
function ShipModel.buildGhost(shipId: string, transparency: number): Model
	-- Never scaled. A ghost is a rival on a circuit whose real counterpart the
	-- player is sitting in, and a lap record set against a bigger one is a lie.
	return staticHull(shipId, Ships.get(shipId).parts, transparency, 1)
end

--- The driver's seat of a built speeder, or nil if this is not one.
function ShipModel.driverSeat(model: Model): VehicleSeat?
	local seat = model:FindFirstChild(ShipModel.DRIVER_SEAT)
	return if seat and seat:IsA("VehicleSeat") then seat else nil
end

--- The boarding prompt built by `ShipModel.build`, if this model has one.
--- Traffic hulls do not, which is why the caller has to cope with nil.
function ShipModel.boardPrompt(model: Model): ProximityPrompt?
	local chassis = model:FindFirstChild(ShipModel.CHASSIS)
	local point = chassis and chassis:FindFirstChild(ShipModel.BOARD_POINT)
	local prompt = point and point:FindFirstChild(ShipModel.PROMPT)
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
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
