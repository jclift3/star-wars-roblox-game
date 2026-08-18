--!strict
--[[
	CabinBuilder.luau

	Draws the inside of a starship: one sealed room, four slots, and a
	window with stars in it.

	The counterpart to PlanetBuilder, and deliberately much smaller. A planet
	is a landscape with districts, crowds and level bands; a cabin is a box
	you own. Everything the box is made of is derived from
	`Furnishings.cabinFor(shipId)` and everything standing in it comes from
	`Furnishings.SLOTS`, so this file decides nothing about content -- which
	is the same division PlanetBuilder keeps with Planets.luau.

	THE ROOM IS SEALED, SO IT HAS TO CARRY ITS OWN LIGHT
	A cabin is built five thousand studs under the map (see InteriorService),
	where the sun does not reach and, more to the point, where there is
	nothing outside the walls to see. Without lamps in here the player
	teleports into a black rectangle and reports the feature as broken.

	AND ITS OWN VIEW
	Same problem, one step further out: a window onto five thousand studs of
	nothing is a black pane, and a black pane looks like a bug rather than
	like space. The specks behind the viewport are the cheapest honest fix --
	a couple of dozen anchored Neon studs, laid out from a seed so a given
	hull's window is the same window every time you board it.

	FURNITURE COLLIDES
	A bunk you fall through is scenery. A bunk you can sit on the edge of is
	furniture, and this room exists to be lived in rather than looked at. The
	risk that buys is a player wedged behind a Dejarik table, which is why
	`spawnPointOf` puts them down at the aft bulkhead rather than in the
	middle of the floor where the Table slot is.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Furnishings = require(Shared.Config.Furnishings)
local Palette = require(Shared.Config.Palette)

local CabinBuilder = {}

--- Hull thickness, in studs. Walls are drawn outside the clear space, so a
--- cabin's declared size is the room you actually get.
local WALL = 1

--- How far in from the aft bulkhead the player materialises.
local SPAWN_INSET = 3

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

local function shell(
	name: string,
	size: Vector3,
	cf: CFrame,
	colour: Color3,
	material: Enum.Material,
	parent: Instance
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[
	The starfield outside the viewport.

	Seeded off the cabin so the courier's window and the freighter's window
	are different windows, and off nothing else so either one is the same on
	every boarding. Drawn as a slab of specks a little way beyond the glass
	rather than as a flat backdrop, because a flat one has no parallax and
	reads as wallpaper the moment the player steps sideways.
]]
local function starfield(cabin: Furnishings.CabinDef, pane: CFrame, parent: Instance)
	local rng = Random.new(#cabin.id * 97 + math.floor(cabin.size.X))
	local spread = cabin.size.X * 0.6

	for i = 1, 26 do
		local speck = Instance.new("Part")
		speck.Name = `Star{i}`
		local scale = rng:NextNumber(0.16, 0.42)
		speck.Size = Vector3.new(scale, scale, scale)
		speck.CFrame = pane
			* CFrame.new(
				rng:NextNumber(-spread, spread),
				rng:NextNumber(-spread * 0.5, spread * 0.5),
				-rng:NextNumber(6, 34)
			)
		speck.Color = if rng:NextNumber() < 0.25 then Palette.SaberBlue else Palette.SaberWhite
		speck.Material = Enum.Material.Neon
		speck.Anchored = true
		speck.CanCollide = false
		speck.CanQuery = false
		speck.CanTouch = false
		speck.CastShadow = false
		speck.Parent = parent
	end
end

--- Puts one furnishing down at its slot, facing the way the slot faces.
local function furnish(def: Furnishings.FurnishingDef, anchor: CFrame, parent: Instance)
	local group = Instance.new("Folder")
	group.Name = def.id
	group.Parent = parent

	for _, spec in def.parts do
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
		local rot = spec.rot or Vector3.zero
		p.CFrame = anchor
			* CFrame.new(spec.offset)
			* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		p.Color = spec.color or Palette.WornSteel
		p.Material = spec.material or Enum.Material.Metal
		p.Transparency = spec.transparency or 0
		p.Anchored = true
		p.CanCollide = true
		-- Nothing in a cabin is interactive, and a hundred touch-enabled
		-- parts in a room the player walks around is a hundred signals fired
		-- at whatever else is listening.
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = group
	end
end

--[[
	Builds one cabin, unparented, pivoted on the middle of its floor.

	`placed` is the player's `profile.cabin`: a slot id to a furnishing id.
	Unknown ids are skipped rather than refused -- a profile saved before a
	furnishing was renamed should open a slightly emptier room, not fail to
	open one.
]]
function CabinBuilder.build(shipId: string, placed: { [string]: string }): Model
	local cabin = Furnishings.cabinFor(shipId)
	local size = cabin.size
	local halfX, halfZ = size.X * 0.5, size.Z * 0.5

	local model = Instance.new("Model")
	model.Name = cabin.id
	model:SetAttribute("ShipId", shipId)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local outer = Vector3.new(size.X + WALL * 2, 0, size.Z + WALL * 2)

	shell(
		"Deck",
		Vector3.new(outer.X, WALL, outer.Z),
		CFrame.new(0, -WALL * 0.5, 0),
		Palette.DarkMetal,
		Enum.Material.DiamondPlate,
		model
	)
	shell(
		"Overhead",
		Vector3.new(outer.X, WALL, outer.Z),
		CFrame.new(0, size.Y + WALL * 0.5, 0),
		Palette.Gunmetal,
		Enum.Material.Metal,
		model
	)
	shell(
		"WallPort",
		Vector3.new(WALL, size.Y, size.Z),
		CFrame.new(-halfX - WALL * 0.5, size.Y * 0.5, 0),
		Palette.Gunmetal,
		Enum.Material.Metal,
		model
	)
	shell(
		"WallStarboard",
		Vector3.new(WALL, size.Y, size.Z),
		CFrame.new(halfX + WALL * 0.5, size.Y * 0.5, 0),
		Palette.Gunmetal,
		Enum.Material.Metal,
		model
	)
	shell(
		"BulkheadAft",
		Vector3.new(outer.X, size.Y, WALL),
		CFrame.new(0, size.Y * 0.5, halfZ + WALL * 0.5),
		Palette.Gunmetal,
		Enum.Material.Metal,
		model
	)

	--[[
		The forward bulkhead is drawn in three pieces around the window.

		A whole wall with a transparent pane laid over it is a wall, and the
		point of the viewport is that you can see through it. Splitting it
		is four extra parts and it means the glass is the only thing between
		the player and the stars.
	]]
	local paneWidth = size.X * 0.5
	local paneHeight = size.Y * 0.28
	local paneY = size.Y * 0.62
	local forwardZ = -halfZ - WALL * 0.5
	local sideWidth = (outer.X - paneWidth) * 0.5

	shell(
		"BulkheadForePort",
		Vector3.new(sideWidth, size.Y, WALL),
		CFrame.new(-(paneWidth + sideWidth) * 0.5, size.Y * 0.5, forwardZ),
		Palette.Gunmetal,
		Enum.Material.Metal,
		model
	)
	shell(
		"BulkheadForeStarboard",
		Vector3.new(sideWidth, size.Y, WALL),
		CFrame.new((paneWidth + sideWidth) * 0.5, size.Y * 0.5, forwardZ),
		Palette.Gunmetal,
		Enum.Material.Metal,
		model
	)
	shell(
		"BulkheadForeUnder",
		Vector3.new(paneWidth, paneY - paneHeight * 0.5, WALL),
		CFrame.new(0, (paneY - paneHeight * 0.5) * 0.5, forwardZ),
		Palette.Gunmetal,
		Enum.Material.Metal,
		model
	)
	local overheadGap = size.Y - (paneY + paneHeight * 0.5)
	shell(
		"BulkheadForeOver",
		Vector3.new(paneWidth, overheadGap, WALL),
		CFrame.new(0, size.Y - overheadGap * 0.5, forwardZ),
		Palette.Gunmetal,
		Enum.Material.Metal,
		model
	)

	local paneCF = CFrame.new(0, paneY, forwardZ)
	local pane = shell(
		"Viewport",
		Vector3.new(paneWidth, paneHeight, WALL * 0.4),
		paneCF,
		Palette.DarkMetal,
		Enum.Material.Glass,
		model
	)
	pane.Transparency = 0.85
	pane.Reflectance = 0.15
	pane.CanQuery = false
	pane.CanTouch = false

	local void = Instance.new("Folder")
	void.Name = "Starfield"
	void.Parent = model
	starfield(cabin, paneCF, void)

	--[[
		Two lamps rather than one.

		A single light in the middle of the overhead flattens everything and
		puts the player's own shadow on whatever they walked over to look at.
		Fore and aft at two thirds height is a lit room with a dark corner in
		it, which is what a cargo hold looks like.
	]]
	for i, z in { -halfZ * 0.5, halfZ * 0.5 } do
		local lamp = Instance.new("Part")
		lamp.Name = `Lamp{i}`
		lamp.Size = Vector3.new(size.X * 0.4, 0.3, 1.2)
		lamp.CFrame = CFrame.new(0, size.Y - 0.4, z)
		lamp.Color = Palette.CoruscantLight
		lamp.Material = Enum.Material.Neon
		lamp.Anchored = true
		lamp.CanCollide = false
		lamp.CanQuery = false
		lamp.CanTouch = false
		lamp.CastShadow = false
		lamp.Parent = model

		local light = Instance.new("PointLight")
		light.Color = Palette.CoruscantLight
		light.Brightness = 1.6
		light.Range = math.max(size.X, size.Z) * 0.8
		light.Shadows = false
		light.Parent = lamp
	end

	for _, slot in Furnishings.SLOTS do
		local id = placed[slot.id]
		if id and Furnishings.exists(id) then
			local def = Furnishings.get(id)
			-- A furnishing filed under the wrong slot would stand in the
			-- right place for the wrong room; `Furnishings.validate` measures
			-- it against its declared slot, so honour that and not the map.
			if def.slot == slot.id then
				furnish(def, Furnishings.anchorFor(cabin, slot), model)
			end
		end
	end

	return model
end

--[[
	Where the player stands when they board, in cabin-local space.

	Aft, facing the viewport: the first thing you see on entering your own
	ship should be the reason you wanted one. Also the only patch of floor
	guaranteed clear of furniture, since the Table slot is the middle.
]]
function CabinBuilder.spawnPointOf(shipId: string): CFrame
	local cabin = Furnishings.cabinFor(shipId)
	local z = cabin.size.Z * 0.5 - SPAWN_INSET
	-- Three studs up: a HumanoidRootPart placed on the deck is a character
	-- half-buried in it.
	return CFrame.new(Vector3.new(0, 3, z), Vector3.new(0, 3, z - 1))
end

return CabinBuilder
