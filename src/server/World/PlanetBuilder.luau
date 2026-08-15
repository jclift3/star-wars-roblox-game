--!strict
--[[
	PlanetBuilder.luau

	Generates a planet's geography, settlement and markers.

	WHY PROCEDURAL
	Eight hand-built worlds is more map than this project can maintain, and the
	previous version's answer -- one random box per building, no overlap check,
	on a flat slab -- is why its towns looked like spilled cargo. A generator
	that understands streets, block footprints and silhouettes produces a place
	that reads as a place, and it does so identically on every server.

	DETERMINISM
	Every planet seeds its own Random from its id. Two servers build the same
	Tatooine, so a player describing where they buried something is not lying,
	and so a designer can iterate against a stable layout.

	MARKERS ARE THE CONTRACT
	The generator emits three marker folders that the rest of the game reads:
	  Workspace/Spawns/<Planet>  -- where players appear
	  Workspace/Zones/<Planet>   -- where NPCs live; multi-part zones are patrol routes
	  Workspace/POI/<Planet>     -- mission "Reach" targets, sized to the landmark
	Nothing else in the codebase knows how the world was made, so a hand-built
	map can replace this entirely as long as it emits the same markers.
]]

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Config.Palette)
local Planets = require(Shared.Config.Planets)

local PlanetBuilder = {}

-- Planets are laid out on a grid in one Workspace, far enough apart that no
-- two are ever in the same streaming region.
local PLANET_SPACING = 12000
local GROUND_SIZE = 3000
local GROUND_THICKNESS = 40

local SETTLEMENT_RADIUS = 520
local BLOCK_SIZE = 130
local STREET_WIDTH = 26

local TOWER_BASE_Y = -400
local SKYLANE_STEP = 220

type Style = {
	buildingColors: { Color3 },
	minFloors: number,
	maxFloors: number,
	floorHeight: number,
	domed: boolean,
	windowColor: Color3,
	scatter: string, -- "Dunes" | "Rocks" | "Trees" | "Drifts" | "None"
}

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

--- Stable seed from a planet id, so every server builds the same world.
local function seedFrom(id: string): number
	local seed = 7
	for i = 1, #id do
		seed = (seed * 31 + string.byte(id, i)) % 2147483647
	end
	return seed
end

--- Each planet's own patch of the shared Workspace.
local function originFor(planetId: string): Vector3
	local ids = Planets.ids()
	table.sort(ids)
	local index = table.find(ids, planetId) or 1
	local column = (index - 1) % 4
	local row = (index - 1) // 4
	return Vector3.new(column * PLANET_SPACING, 0, row * PLANET_SPACING)
end

PlanetBuilder.originFor = originFor

local function folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function block(
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[
	A marker part: invisible, non-colliding, and invisible to raycasts.

	CanQuery matters more than it looks. A zone volume that blocked queries
	would break every line-of-sight check an NPC standing inside it makes,
	which is exactly the sort of bug that reads as "the AI is broken".
]]
local function marker(parent: Instance, name: string, position: Vector3, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = size
	p.Position = position
	p.Parent = parent
	return p
end

--------------------------------------------------------------------------------
-- Styles
--------------------------------------------------------------------------------

local function styleFor(planet: Planets.PlanetDef): Style
	local terrain = planet.terrain

	if terrain == "Desert" then
		return {
			buildingColors = { Palette.TatooineSand, Palette.TatooineRock, Palette.SmugglerBrown },
			minFloors = 1,
			maxFloors = 2,
			floorHeight = 11,
			domed = true, -- moisture farms and adobe, not office blocks
			windowColor = Palette.CoruscantLight,
			scatter = "Dunes",
		}
	elseif terrain == "Ice" then
		return {
			buildingColors = { Palette.HothIce, Palette.WornSteel, Palette.Gunmetal },
			minFloors = 1,
			maxFloors = 2,
			floorHeight = 12,
			domed = true,
			windowColor = Palette.BlasterBlue,
			scatter = "Drifts",
		}
	elseif terrain == "Volcanic" then
		return {
			buildingColors = { Palette.MustafarBasalt, Palette.DarkMetal, Palette.Gunmetal },
			minFloors = 2,
			maxFloors = 5,
			floorHeight = 14,
			domed = false,
			windowColor = Palette.SaberRed,
			scatter = "Rocks",
		}
	elseif terrain == "Forest" or terrain == "Swamp" then
		return {
			buildingColors = { Palette.SmugglerBrown, Palette.WookieeBrown, Palette.NabooStone },
			minFloors = 1,
			maxFloors = 3,
			floorHeight = 12,
			domed = true,
			windowColor = Palette.DroidGold,
			scatter = "Trees",
		}
	elseif terrain == "Ocean" then
		return {
			buildingColors = { Palette.HullWhite, Palette.WornSteel, Palette.KaminoSea },
			minFloors = 1,
			maxFloors = 3,
			floorHeight = 14,
			domed = true,
			windowColor = Palette.CoruscantLight,
			scatter = "None",
		}
	end

	return {
		buildingColors = { Palette.CoruscantPlate, Palette.Gunmetal, Palette.WornSteel, Palette.NabooStone },
		minFloors = 4,
		maxFloors = 12,
		floorHeight = 16,
		domed = false,
		windowColor = Palette.CoruscantLight,
		scatter = "None",
	}
end

--------------------------------------------------------------------------------
-- Ground and scatter
--------------------------------------------------------------------------------

local function buildGround(parent: Instance, planet: Planets.PlanetDef, origin: Vector3)
	local material = if planet.terrain == "Desert"
		then Enum.Material.Sand
		elseif planet.terrain == "Ice" then Enum.Material.Glacier
		elseif planet.terrain == "Volcanic" then Enum.Material.Basalt
		elseif planet.terrain == "Forest" then Enum.Material.Grass
		elseif planet.terrain == "Swamp" then Enum.Material.LeafyGrass
		elseif planet.terrain == "Ocean" then Enum.Material.Water
		else Enum.Material.Concrete

	local ground = block(
		parent,
		CFrame.new(origin - Vector3.new(0, GROUND_THICKNESS * 0.5, 0)),
		Vector3.new(GROUND_SIZE, GROUND_THICKNESS, GROUND_SIZE),
		planet.groundColor,
		material
	)
	ground.Name = "Ground"
end

--[[
	Scatters landscape features outside the settlement.

	Kept out of the town radius deliberately: a boulder in the middle of a
	street is the single clearest tell that a world was generated rather than
	designed.
]]
local function buildScatter(
	parent: Instance,
	planet: Planets.PlanetDef,
	origin: Vector3,
	style: Style,
	rng: Random
)
	if style.scatter == "None" then
		return
	end

	local scatter = folder("Scatter", parent)
	local rockColor = planet.rockColor or planet.groundColor

	for _ = 1, 140 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(SETTLEMENT_RADIUS + 90, GROUND_SIZE * 0.46)
		local position = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

		if style.scatter == "Trees" then
			local height = rng:NextNumber(28, 60)
			local trunk = block(
				scatter,
				CFrame.new(position + Vector3.new(0, height * 0.5, 0)),
				Vector3.new(4, height, 4),
				Palette.SmugglerBrown,
				Enum.Material.Wood
			)
			trunk.Name = "Trunk"

			for i = 1, 3 do
				local canopy = Instance.new("Part")
				canopy.Anchored = true
				canopy.Shape = Enum.PartType.Ball
				canopy.Size = Vector3.new(1, 1, 1) * rng:NextNumber(26, 40) * (1 - (i - 1) * 0.18)
				canopy.Position = position
					+ Vector3.new(rng:NextNumber(-5, 5), height + (i - 1) * 9, rng:NextNumber(-5, 5))
				canopy.Color = if planet.terrain == "Swamp" then Palette.NabooGrass else Palette.NabooGrass
				canopy.Material = Enum.Material.Grass
				canopy.Parent = scatter
			end
		else
			-- Dunes, drifts and boulders are all the same shape with different
			-- proportions: a squashed ellipsoid half-buried in the ground.
			local width = rng:NextNumber(30, 110)
			local height = if style.scatter == "Rocks" then width * rng:NextNumber(0.5, 1.1) else width * 0.28

			local mound = Instance.new("Part")
			mound.Anchored = true
			mound.Shape = Enum.PartType.Ball
			mound.Size = Vector3.new(width, height, width * rng:NextNumber(0.7, 1.4))
			mound.CFrame = CFrame.new(position + Vector3.new(0, height * 0.15, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
			mound.Color = rockColor
			mound.Material = if style.scatter == "Drifts" then Enum.Material.Snow else Enum.Material.Rock
			mound.Parent = scatter
		end
	end
end

--------------------------------------------------------------------------------
-- Settlement
--------------------------------------------------------------------------------

--[[
	One building: stacked, shrinking boxes with lit window bands.

	The taper is what does the work. A single box of a random height is a
	crate; two or three boxes that step inward as they rise is a silhouette,
	and silhouette is most of what makes a skyline legible from a distance.
]]
local function buildBuilding(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local floors = rng:NextInteger(style.minFloors, style.maxFloors)
	local width, depth = footprint.X, footprint.Y
	local color = style.buildingColors[rng:NextInteger(1, #style.buildingColors)]
	local y = 0

	local tiers = math.clamp(math.floor(floors / 3) + 1, 1, 3)
	local remaining = floors

	for tier = 1, tiers do
		local tierFloors = if tier == tiers
			then remaining
			else math.max(1, math.floor(remaining / (tiers - tier + 1)))
		remaining -= tierFloors
		local height = tierFloors * style.floorHeight

		block(
			parent,
			CFrame.new(base + Vector3.new(0, y + height * 0.5, 0)),
			Vector3.new(width, height, depth),
			color,
			Enum.Material.Concrete
		).Name =
			"Storey"

		-- Window bands on the two long faces. Neon rather than a texture so
		-- they read at night, which is when a city needs to look like one.
		for floor = 1, tierFloors do
			local windowY = y + (floor - 0.5) * style.floorHeight
			for _, side in { 1, -1 } do
				local band = block(
					parent,
					CFrame.new(base + Vector3.new(0, windowY, side * depth * 0.5)),
					Vector3.new(width * 0.82, 2.2, 0.4),
					style.windowColor,
					Enum.Material.Neon
				)
				band.Name = "Windows"
				band.CanCollide = false
			end
		end

		y += height
		width *= 0.82
		depth *= 0.82
	end

	if style.domed then
		local dome = Instance.new("Part")
		dome.Anchored = true
		dome.Shape = Enum.PartType.Ball
		dome.Size = Vector3.new(width * 1.05, width * 0.75, depth * 1.05)
		dome.Position = base + Vector3.new(0, y, 0)
		dome.Color = style.buildingColors[rng:NextInteger(1, #style.buildingColors)]
		dome.Material = Enum.Material.Concrete
		dome.Name = "Dome"
		dome.Parent = parent
	else
		-- A mast or vent stack. Cheap vertical interest along the roofline.
		block(
			parent,
			CFrame.new(base + Vector3.new(rng:NextNumber(-width * 0.2, width * 0.2), y + 9, 0)),
			Vector3.new(2, 18, 2),
			Palette.DarkMetal,
			Enum.Material.Metal
		).Name =
			"Mast"
	end
end

local function buildStreetLamp(parent: Instance, position: Vector3, color: Color3)
	block(
		parent,
		CFrame.new(position + Vector3.new(0, 7, 0)),
		Vector3.new(0.8, 14, 0.8),
		Palette.DarkMetal,
		Enum.Material.Metal
	).Name =
		"LampPost"

	local head = block(
		parent,
		CFrame.new(position + Vector3.new(0, 14.4, 0)),
		Vector3.new(2, 0.8, 2),
		color,
		Enum.Material.Neon
	)
	head.Name = "Lamp"
	head.CanCollide = false

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 34
	light.Brightness = 1.6
	light.Parent = head
end

--[[
	Lays a settlement out on a street grid.

	Buildings sit inside blocks with a street margin, so nothing ever
	intersects and there is always a walkable route between them -- which
	matters twice over, because NPC pathfinding needs somewhere to path.

	Returns the block centres left *empty*, which is what anything that needs
	to stand somewhere gets given.
]]
local function buildSettlement(
	parent: Instance,
	planet: Planets.PlanetDef,
	origin: Vector3,
	style: Style,
	rng: Random
): { Vector3 }
	local town = folder("Settlement", parent)

	-- Somewhere to stand. This used to collect the centres buildings were
	-- placed on, so players spawned *inside* a house and got shoved through
	-- the floor by the depenetration solver.
	local open: { Vector3 } = { origin }

	local plaza_ = block(
		town,
		CFrame.new(origin + Vector3.new(0, 0.25, 0)),
		Vector3.new(BLOCK_SIZE * 1.6, 1, BLOCK_SIZE * 1.6),
		planet.groundColor:Lerp(Color3.new(1, 1, 1), 0.12),
		Enum.Material.Slate
	)
	plaza_.Name = "Plaza"

	local reach = math.floor(SETTLEMENT_RADIUS / BLOCK_SIZE)
	for gx = -reach, reach do
		for gz = -reach, reach do
			-- The centre block is the plaza, and a scattering of others are
			-- left empty so the town has yards and alleys rather than a
			-- perfectly packed grid.
			if gx == 0 and gz == 0 then
				continue
			end
			local empty = rng:NextNumber() < 0.22

			local centre = origin + Vector3.new(gx * BLOCK_SIZE, 0, gz * BLOCK_SIZE)
			if (centre - origin).Magnitude > SETTLEMENT_RADIUS then
				continue
			end

			if empty then
				table.insert(open, centre)
				continue
			end

			local usable = BLOCK_SIZE - STREET_WIDTH
			local footprint = Vector2.new(
				rng:NextNumber(usable * 0.45, usable * 0.85),
				rng:NextNumber(usable * 0.45, usable * 0.85)
			)
			local jitter = Vector3.new(
				rng:NextNumber(-1, 1) * (usable - footprint.X) * 0.4,
				0,
				rng:NextNumber(-1, 1) * (usable - footprint.Y) * 0.4
			)

			buildBuilding(town, centre + jitter, footprint, style, rng)

			if rng:NextNumber() < 0.3 then
				buildStreetLamp(
					town,
					centre + Vector3.new(BLOCK_SIZE * 0.5 - 6, 0, BLOCK_SIZE * 0.5 - 6),
					style.windowColor
				)
			end
		end
	end

	return open
end

--------------------------------------------------------------------------------
-- Vertical city
--------------------------------------------------------------------------------

--[[
	Coruscant. No ground, only towers and the platforms bolted to them.

	This is the one planet where falling is a real threat rather than a bug,
	so every platform is generated as a solid slab with a lip, and the spawn
	markers are placed on platforms rather than anywhere in open air.
]]
local function buildVerticalCity(
	parent: Instance,
	planet: Planets.PlanetDef,
	origin: Vector3,
	rng: Random
): { Vector3 }
	local city = folder("Towers", parent)
	local platforms: { Vector3 } = {}
	local ceiling = planet.flightCeiling or 1400

	for gx = -5, 5 do
		for gz = -5, 5 do
			local centre = origin + Vector3.new(gx * 240, 0, gz * 240)
			local width = rng:NextNumber(70, 150)
			local top = rng:NextNumber(ceiling * 0.45, ceiling * 0.95)
			local height = top - TOWER_BASE_Y

			local tower = block(
				city,
				CFrame.new(centre + Vector3.new(0, TOWER_BASE_Y + height * 0.5, 0)),
				Vector3.new(width, height, width),
				Palette.CoruscantPlate,
				Enum.Material.Metal
			)
			tower.Name = "Tower"

			-- Window bands every few hundred studs rather than every floor:
			-- at this scale individual floors are invisible anyway, and the
			-- part count is not.
			local y = TOWER_BASE_Y + 60
			while y < top - 40 do
				local band = block(
					city,
					CFrame.new(centre + Vector3.new(0, y, 0)),
					Vector3.new(width * 1.01, 6, width * 1.01),
					Palette.CoruscantLight,
					Enum.Material.Neon
				)
				band.Name = "Windows"
				band.CanCollide = false
				y += rng:NextNumber(45, 90)
			end

			-- Landing platforms cantilevered off the tower at skylane heights.
			local platformY = math.floor(top / SKYLANE_STEP) * SKYLANE_STEP
			while platformY > TOWER_BASE_Y + 200 do
				if rng:NextNumber() < 0.35 then
					local offset = Vector3.new(width * 0.5 + 45, 0, 0)
					local rotated = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * offset
					local position = centre + Vector3.new(0, platformY, 0) + rotated

					local pad = block(
						city,
						CFrame.new(position),
						Vector3.new(90, 4, 90),
						Palette.CoruscantPlate,
						Enum.Material.DiamondPlate
					)
					pad.Name = "Platform"
					table.insert(platforms, position + Vector3.new(0, 2, 0))
				end
				platformY -= SKYLANE_STEP
			end
		end
	end

	return platforms
end

--------------------------------------------------------------------------------
-- Landmarks
--------------------------------------------------------------------------------

--[[
	The buildings behind the names.

	Every point of interest used to be an invisible box. The waypoint sent you
	to "the sandcrawler in the wastes", you arrived at empty sand, and the
	objective ticked anyway -- the place existed only as a coordinate and a
	line of text. Each kind now gets a silhouette you can pick out from a
	distance and a sign saying what it is.

	Proportion does the work, not part count: a shape that is unmistakably
	wider than it is tall, or stepped, or half-buried, reads from far enough
	away to be worth walking towards.
]]

-- Roblox cylinders lie along X, so a standing one is turned a quarter turn and
-- sized (height, diameter, diameter).
local UPRIGHT = CFrame.Angles(0, 0, math.pi * 0.5)

local function cylinder(
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local p = block(parent, cf, size, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = block(parent, cf, size, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

--- A name floating over a landmark, so a place says what it is.
local function nameplate(parent: Instance, position: Vector3, text: string)
	local anchor = marker(parent, "Nameplate", position, Vector3.new(1, 1, 1))

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(320, 40)
	-- Readable across a district but not from the next one: a horizon full of
	-- floating labels is a map screen, not a world.
	gui.MaxDistance = 900
	gui.LightInfluence = 0
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = Palette.HullWhite
	label.TextStrokeTransparency = 0.35
	label.Text = text
	label.Parent = gui
end

--[[
	A builder takes the ground point it stands on and returns how tall it came
	out, which is where the sign goes. Its footprint is declared beside it
	instead of measured afterwards, because the footprint has to be known
	*before* anything is built: a spaceport wider than a city block cannot be
	dropped into one.

	That radius earns its keep twice more. It sizes the point-of-interest
	marker, and "reached" is measured from that marker -- a flat 28 studs was
	calibrated against an invisible point, and you cannot stand 28 studs from
	the middle of a sandcrawler because the hull is there. A place that does
	not say how big it is is a place that cannot be arrived at.
]]
type Landmark = (Instance, Vector3, Style, Random) -> number
type LandmarkDef = { radius: number, build: Landmark }

--- A Jawa sandcrawler: a tracked wedge that threw a tread and stayed put.
local function buildSandcrawler(parent: Instance, base: Vector3, style: Style, rng: Random): number
	-- Everything hangs off one frame, so the whole machine leans together
	-- rather than each box leaning on its own.
	local root = CFrame.new(base)
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		* CFrame.Angles(0, 0, math.rad(7))

	local hull = Palette.DroidRust
	local plate = Palette.SmugglerBrown

	block(parent, root * CFrame.new(0, 20, 0), Vector3.new(112, 36, 64), hull, Enum.Material.CorrodedMetal).Name =
		"Hull"
	block(parent, root * CFrame.new(-8, 48, 0), Vector3.new(80, 24, 52), plate, Enum.Material.CorrodedMetal).Name =
		"Deck"
	-- The sloped face a sandcrawler is recognised by.
	block(
		parent,
		root * CFrame.new(48, 40, 0) * CFrame.Angles(0, 0, math.rad(-32)),
		Vector3.new(34, 6, 56),
		plate,
		Enum.Material.CorrodedMetal
	).Name =
		"Prow"

	-- Lit viewports, which is what makes it read as inhabited at dusk.
	local eyes = block(
		parent,
		root * CFrame.new(56, 30, 0),
		Vector3.new(1.5, 5, 34),
		Palette.DroidGold,
		Enum.Material.Neon
	)
	eyes.Name = "Viewport"
	eyes.CanCollide = false

	-- Tracks, sunk to the axles. Cylinders roll along Z here, so they are
	-- turned about Y rather than the usual quarter turn about Z.
	for _, side in { 1, -1 } do
		for i = -1, 1 do
			cylinder(
				parent,
				root * CFrame.new(i * 38, 4, side * 33) * CFrame.Angles(0, math.pi * 0.5, 0),
				Vector3.new(12, 30, 30),
				Palette.DarkMetal,
				Enum.Material.Metal
			).Name =
				"Tread"
		end
	end

	-- The ramp the Jawas run their salvage down, and the tread that put the
	-- crawler here in the first place lying beside it.
	block(
		parent,
		root * CFrame.new(72, 8, 0) * CFrame.Angles(0, 0, math.rad(-24)),
		Vector3.new(48, 3, 28),
		plate,
		Enum.Material.CorrodedMetal
	).Name =
		"Ramp"
	block(
		parent,
		CFrame.new(base + Vector3.new(rng:NextNumber(-70, 70), 2, rng:NextNumber(40, 80)))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Vector3.new(36, 4, 12),
		Palette.DarkMetal,
		Enum.Material.CorrodedMetal
	).Name =
		"BrokenTread"

	-- Salvage, because a scrap dealer with no scrap around it is a warehouse.
	for _ = 1, 7 do
		local size = rng:NextNumber(5, 12)
		block(
			parent,
			CFrame.new(base + Vector3.new(rng:NextNumber(-90, 90), size * 0.5, rng:NextNumber(-70, 70)))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Vector3.new(size, size, size * rng:NextNumber(0.6, 1.4)),
			if rng:NextNumber() < 0.5 then Palette.DroidRust else style.buildingColors[1],
			Enum.Material.CorrodedMetal
		).Name =
			"Salvage"
	end

	return 64
end

--- Something that used to fly, nose-down in the ground.
local function buildWreck(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local root = CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local hull = style.buildingColors[#style.buildingColors]

	block(
		parent,
		root * CFrame.new(0, 22, 0) * CFrame.Angles(0, 0, math.rad(28)),
		Vector3.new(96, 22, 44),
		hull,
		Enum.Material.CorrodedMetal
	).Name =
		"Hull"
	-- One wing still attached and one thrown clear, which is the difference
	-- between a crashed ship and a parked one.
	block(
		parent,
		root * CFrame.new(-6, 34, 32) * CFrame.Angles(math.rad(20), 0, math.rad(28)),
		Vector3.new(52, 4, 34),
		Palette.WornSteel,
		Enum.Material.CorrodedMetal
	).Name =
		"Wing"
	block(
		parent,
		root
			* CFrame.new(rng:NextNumber(50, 80), 3, rng:NextNumber(-80, -50))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(12)),
		Vector3.new(46, 4, 30),
		Palette.WornSteel,
		Enum.Material.CorrodedMetal
	).Name =
		"TornWing"

	for _ = 1, 9 do
		local size = rng:NextNumber(3, 9)
		block(
			parent,
			CFrame.new(base + Vector3.new(rng:NextNumber(-80, 80), size * 0.4, rng:NextNumber(-80, 80)))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Vector3.new(size, size * 0.5, size),
			Palette.DarkMetal,
			Enum.Material.CorrodedMetal
		).Name =
			"Debris"
	end

	return 54
end

--- Landing pads and the tower that talks them down.
local function buildSpaceport(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local plateColor = style.buildingColors[1]

	for i = 1, 3 do
		local angle = (i - 1) * (math.pi * 2 / 3) + rng:NextNumber(-0.2, 0.2)
		local centre = base + Vector3.new(math.cos(angle) * 78, 0, math.sin(angle) * 78)

		cylinder(
			parent,
			CFrame.new(centre + Vector3.new(0, 1.5, 0)) * UPRIGHT,
			Vector3.new(3, 68, 68),
			Palette.WornSteel,
			Enum.Material.DiamondPlate
		).Name =
			"Pad"

		-- Approach lights. A pad without them is a floor.
		for light = 1, 6 do
			local a = (light - 1) * (math.pi * 2 / 6)
			local lamp = cylinder(
				parent,
				CFrame.new(centre + Vector3.new(math.cos(a) * 30, 3.4, math.sin(a) * 30)) * UPRIGHT,
				Vector3.new(1.2, 4, 4),
				style.windowColor,
				Enum.Material.Neon
			)
			lamp.Name = "PadLight"
			lamp.CanCollide = false
		end
	end

	-- Control tower, set back from the pads.
	block(
		parent,
		CFrame.new(base + Vector3.new(0, 30, 0)),
		Vector3.new(22, 60, 22),
		plateColor,
		Enum.Material.Concrete
	).Name =
		"Tower"
	block(
		parent,
		CFrame.new(base + Vector3.new(0, 66, 0)),
		Vector3.new(38, 12, 38),
		Palette.Gunmetal,
		Enum.Material.Metal
	).Name =
		"ControlRoom"
	local glass = block(
		parent,
		CFrame.new(base + Vector3.new(0, 66, 0)),
		Vector3.new(39, 6, 39),
		Palette.CockpitGlass,
		Enum.Material.Glass
	)
	glass.Name = "Glass"
	glass.CanCollide = false
	block(
		parent,
		CFrame.new(base + Vector3.new(0, 82, 0)),
		Vector3.new(2, 20, 2),
		Palette.DarkMetal,
		Enum.Material.Metal
	).Name =
		"Mast"

	return 92
end

--- A low drum with a lit sign and a doorway you can actually walk into.
local function buildCantina(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local wall = style.buildingColors[rng:NextInteger(1, #style.buildingColors)]

	cylinder(
		parent,
		CFrame.new(base + Vector3.new(0, 13, 0)) * UPRIGHT,
		Vector3.new(26, 74, 74),
		wall,
		Enum.Material.Concrete
	).Name =
		"Hall"
	ball(
		parent,
		CFrame.new(base + Vector3.new(0, 26, 0)),
		Vector3.new(74, 30, 74),
		wall,
		Enum.Material.Concrete
	).Name =
		"Roof"

	-- Entrance: a stub porch with a dark doorway, so the front is obvious.
	block(
		parent,
		CFrame.new(base + Vector3.new(38, 9, 0)),
		Vector3.new(18, 18, 26),
		wall,
		Enum.Material.Concrete
	).Name =
		"Porch"
	block(
		parent,
		CFrame.new(base + Vector3.new(47, 7, 0)),
		Vector3.new(2, 14, 12),
		Palette.ImperialBlack,
		Enum.Material.SmoothPlastic
	).Name =
		"Doorway"

	local sign = block(
		parent,
		CFrame.new(base + Vector3.new(47, 21, 0)),
		Vector3.new(1.5, 7, 22),
		style.windowColor,
		Enum.Material.Neon
	)
	sign.Name = "Sign"
	sign.CanCollide = false

	local glow = Instance.new("PointLight")
	glow.Color = style.windowColor
	glow.Range = 44
	glow.Brightness = 2
	glow.Parent = sign

	return 44
end

--- A walled compound. Whoever holds it wants you to come in by the gate.
local function buildBase(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local wallColor = style.buildingColors[1]
	local reach = 82

	-- Three sides and two stubs, leaving a gate. A sealed box would be a
	-- landmark you can only look at.
	local sides = {
		{ offset = Vector3.new(0, 9, -reach), size = Vector3.new(reach * 2, 18, 6) },
		{ offset = Vector3.new(-reach, 9, 0), size = Vector3.new(6, 18, reach * 2) },
		{ offset = Vector3.new(0, 9, reach), size = Vector3.new(reach * 2, 18, 6) },
		{ offset = Vector3.new(reach, 9, -reach * 0.6), size = Vector3.new(6, 18, reach * 0.8) },
		{ offset = Vector3.new(reach, 9, reach * 0.6), size = Vector3.new(6, 18, reach * 0.8) },
	}
	for _, side in sides do
		block(parent, CFrame.new(base + side.offset), side.size, wallColor, Enum.Material.Concrete).Name =
			"Wall"
	end

	block(
		parent,
		CFrame.new(base + Vector3.new(0, 22, 0)),
		Vector3.new(70, 44, 56),
		wallColor,
		Enum.Material.Concrete
	).Name =
		"Keep"
	block(
		parent,
		CFrame.new(base + Vector3.new(0, 48, 0)),
		Vector3.new(52, 8, 42),
		Palette.Gunmetal,
		Enum.Material.Metal
	).Name =
		"Parapet"

	for _, corner in { Vector3.new(-reach, 0, -reach), Vector3.new(-reach, 0, reach) } do
		cylinder(
			parent,
			CFrame.new(base + corner + Vector3.new(0, 15, 0)) * UPRIGHT,
			Vector3.new(30, 20, 20),
			wallColor,
			Enum.Material.Concrete
		).Name =
			"Turret"
		local lamp = ball(
			parent,
			CFrame.new(base + corner + Vector3.new(0, 32, 0)),
			Vector3.new(8, 8, 8),
			style.windowColor,
			Enum.Material.Neon
		)
		lamp.Name = "TurretLight"
		lamp.CanCollide = false
	end

	-- Something parked inside, so the compound looks used.
	block(
		parent,
		CFrame.new(base + Vector3.new(rng:NextNumber(30, 50), 5, rng:NextNumber(-40, 40)))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Vector3.new(26, 10, 14),
		Palette.Gunmetal,
		Enum.Material.Metal
	).Name =
		"Crate"

	return 56
end

--- A couple of domes and a vaporator. The smallest thing worth a name.
local function buildOutpost(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local wall = style.buildingColors[rng:NextInteger(1, #style.buildingColors)]

	for i = 1, 2 do
		local centre = base + Vector3.new((i - 1.5) * 44, 0, rng:NextNumber(-10, 10))
		local width = if i == 1 then 44 else 32
		cylinder(
			parent,
			CFrame.new(centre + Vector3.new(0, 7, 0)) * UPRIGHT,
			Vector3.new(14, width, width),
			wall,
			Enum.Material.Concrete
		).Name =
			"Hut"
		ball(
			parent,
			CFrame.new(centre + Vector3.new(0, 14, 0)),
			Vector3.new(width, width * 0.6, width),
			wall,
			Enum.Material.Concrete
		).Name =
			"Dome"
	end

	-- The vaporator: the one silhouette that says "somebody lives here" on a
	-- planet where water is the whole economy.
	local mast = base + Vector3.new(rng:NextNumber(28, 40), 0, rng:NextNumber(20, 34))
	cylinder(
		parent,
		CFrame.new(mast + Vector3.new(0, 13, 0)) * UPRIGHT,
		Vector3.new(26, 5, 5),
		Palette.WornSteel,
		Enum.Material.Metal
	).Name =
		"Vaporator"
	for fin = 1, 3 do
		local angle = (fin - 1) * (math.pi * 2 / 3)
		block(
			parent,
			CFrame.new(mast + Vector3.new(math.cos(angle) * 4, 22, math.sin(angle) * 4))
				* CFrame.Angles(0, -angle, 0),
			Vector3.new(2, 10, 6),
			Palette.DarkMetal,
			Enum.Material.Metal
		).Name =
			"Fin"
	end

	return 30
end

--- Awnings and stalls: colour at head height, which is what a market is.
local function buildMarket(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local awnings = { Palette.RebelOrange, Palette.TwilekRed, Palette.RebelBlue, Palette.NabooGrass }

	for row = -1, 1, 2 do
		for i = -1, 1 do
			local centre = base + Vector3.new(i * 34, 0, row * 26)

			for _, corner in
				{
					Vector3.new(-11, 0, -8),
					Vector3.new(11, 0, -8),
					Vector3.new(-11, 0, 8),
					Vector3.new(11, 0, 8),
				}
			do
				block(
					parent,
					CFrame.new(centre + corner + Vector3.new(0, 6, 0)),
					Vector3.new(1.2, 12, 1.2),
					Palette.DarkMetal,
					Enum.Material.Metal
				).Name =
					"Post"
			end

			block(
				parent,
				CFrame.new(centre + Vector3.new(0, 12.6, 0)) * CFrame.Angles(math.rad(6) * row, 0, 0),
				Vector3.new(26, 1, 20),
				awnings[rng:NextInteger(1, #awnings)],
				Enum.Material.Fabric
			).Name =
				"Awning"
			block(
				parent,
				CFrame.new(centre + Vector3.new(0, 3.5, 0)),
				Vector3.new(22, 7, 8),
				style.buildingColors[1],
				Enum.Material.WoodPlanks
			).Name =
				"Counter"

			for _ = 1, 2 do
				local size = rng:NextNumber(4, 7)
				block(
					parent,
					CFrame.new(
						centre + Vector3.new(rng:NextNumber(-10, 10), size * 0.5, rng:NextNumber(6, 11))
					) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
					Vector3.new(size, size, size),
					Palette.SmugglerBrown,
					Enum.Material.WoodPlanks
				).Name =
					"Crate"
			end
		end
	end

	return 20
end

--- A stepped ziggurat. Old, and built by people who wanted it to look old.
local function buildTemple(parent: Instance, base: Vector3, style: Style, _rng: Random): number
	local stone = style.buildingColors[#style.buildingColors]
	local y = 0
	local width = 130

	for tier = 1, 4 do
		local height = 14 - tier
		block(
			parent,
			CFrame.new(base + Vector3.new(0, y + height * 0.5, 0)),
			Vector3.new(width, height, width),
			stone,
			Enum.Material.Slate
		).Name =
			"Tier"
		y += height
		width *= 0.78
	end

	-- A colonnade on the top step, which is what separates a temple from a
	-- pile of steps.
	for i = -1, 1, 2 do
		for j = -1, 1, 2 do
			cylinder(
				parent,
				CFrame.new(base + Vector3.new(i * width * 0.3, y + 11, j * width * 0.3)) * UPRIGHT,
				Vector3.new(22, 7, 7),
				stone,
				Enum.Material.Slate
			).Name =
				"Pillar"
		end
	end
	block(
		parent,
		CFrame.new(base + Vector3.new(0, y + 24, 0)),
		Vector3.new(width * 0.9, 5, width * 0.9),
		stone,
		Enum.Material.Slate
	).Name =
		"Lintel"

	return y + 30
end

-- An unknown kind falls back to an outpost rather than to nothing: a config
-- typo should leave a small building with the right name over it, which is
-- visibly wrong, instead of empty ground, which is indistinguishable from the
-- bug this whole section exists to fix.
local OUTPOST: LandmarkDef = { radius = 50, build = buildOutpost }

local LANDMARKS: { [string]: LandmarkDef } = {
	Sandcrawler = { radius = 78, build = buildSandcrawler },
	Ruin = { radius = 62, build = buildWreck },
	Spaceport = { radius = 116, build = buildSpaceport },
	Cantina = { radius = 52, build = buildCantina },
	Base = { radius = 92, build = buildBase },
	Outpost = OUTPOST,
	Market = { radius = 58, build = buildMarket },
	Temple = { radius = 74, build = buildTemple },
}

local function landmarkFor(poi: Planets.PointOfInterest): LandmarkDef
	return LANDMARKS[poi.landmark or poi.kind] or OUTPOST
end

--- Builds the structure for one point of interest, and signs it.
local function buildLandmark(
	parent: Instance,
	poi: Planets.PointOfInterest,
	def: LandmarkDef,
	position: Vector3,
	style: Style,
	rng: Random
)
	local site = folder(poi.id, parent)
	local top = def.build(site, position, style, rng)
	nameplate(site, position + Vector3.new(0, top + 10, 0), poi.displayName)
end

--------------------------------------------------------------------------------
-- Markers
--------------------------------------------------------------------------------

-- How far a zone's three patrol points spread around its centre.
local ZONE_SPREAD = 70

-- Far enough out that the widest landmark clears the patrol ring. A building
-- standing on a waypoint is a building with NPCs walking into it.
local LANDMARK_OFFSET = ZONE_SPREAD * 2.2

--[[
	Emits spawn, zone and POI markers.

	WHERE A ZONE GOES IS CONFIG, NOT LUCK
	Each district's distance from the town centre is declared on the planet
	(`Planets.ZoneDef`). It used to be derived from the order a zone's first
	spawn rule happened to appear in the list, which put Tatooine's Wastes at
	ring 0 -- downtown -- and its Town three rings out in the desert, and so
	dropped twelve aggressive Tusken Raiders onto a level 1 spawn point.

	Each zone gets three parts, which NPCService reads as a patrol route, so
	guards walk a circuit without anyone hand-placing waypoints.

	A point of interest is placed inside the district it belongs to, so that
	"the Jawa crawler they live in still" has Jawas around it and the mission
	that sends you there is a place rather than a coordinate. Its landmark is
	built at the same point, and the landmarks claim their ground before the
	spawn points are chosen -- a player who materialises inside a temple is
	pushed through the floor by the depenetration solver.
]]
local function buildMarkers(
	planet: Planets.PlanetDef,
	root: Instance,
	origin: Vector3,
	anchors: { Vector3 },
	style: Style,
	rng: Random
)
	local planetId = planet.id
	local zoneRoot = folder(planetId, folder("Zones", Workspace))
	zoneRoot:ClearAllChildren()

	-- Kept so points of interest can be dropped into their district below.
	local centres: { [string]: Vector3 } = {}
	local count = math.max(1, #planet.zones)

	for index, def in planet.zones do
		-- Districts are fanned around the compass rather than stacked on one
		-- bearing, so walking out of town in any direction finds something.
		local angle = (index - 1) * (math.pi * 2 / count) + rng:NextNumber(-0.3, 0.3)
		local radius = def.distance * SETTLEMENT_RADIUS
		local centre = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

		-- Vertical cities have no ground, so districts snap to a platform
		-- instead of hanging in the air.
		if not planet.hasWalkableGround and #anchors > 0 then
			centre = anchors[math.min(index, #anchors)]
		end
		centres[def.id] = centre

		local zone = folder(def.id, zoneRoot)
		local baseAngle = rng:NextNumber(0, math.pi * 2)
		for point = 1, 3 do
			local spokeAngle = baseAngle + (point - 1) * (math.pi * 2 / 3)
			local spread = rng:NextNumber(ZONE_SPREAD * 0.4, ZONE_SPREAD)
			local position = centre
				+ Vector3.new(math.cos(spokeAngle) * spread, 0, math.sin(spokeAngle) * spread)
			if not planet.hasWalkableGround and #anchors > 0 then
				position = anchors[rng:NextInteger(1, #anchors)]
			end
			marker(zone, `Point{point}`, position + Vector3.new(0, 3, 0), Vector3.new(60, 1, 60))
		end
	end

	local poiRoot = folder(planetId, folder("POI", Workspace))
	poiRoot:ClearAllChildren()
	local landmarkRoot = folder("Landmarks", root)

	--[[
		Open ground that has been given to something.

		`anchors` are the block centres the settlement left empty, and they are
		the only places in town known to be clear. A landmark takes the nearest
		one to where it wanted to stand, and what is left over goes to the
		spawn points.
	]]
	local claimed: { [number]: boolean } = {}

	--[[
		`limit` is the whole point. Every anchor is a block inside the
		settlement, so an unbounded search will happily answer "the middle of
		town" for a landmark that asked to stand on the edge of the desert --
		which is how the Lars Homestead ended up several hundred studs from
		the farmstead it is named after, and from the farmers who make it a
		place rather than a building.
	]]
	local function claimNear(position: Vector3, limit: number): Vector3?
		local bestIndex: number? = nil
		local bestDistance = limit
		for i, anchor in anchors do
			if claimed[i] then
				continue
			end
			local distance = (anchor - position).Magnitude
			if distance < bestDistance then
				bestIndex, bestDistance = i, distance
			end
		end
		if not bestIndex then
			return nil
		end
		claimed[bestIndex] = true
		return anchors[bestIndex]
	end

	for index, poi in planet.pointsOfInterest do
		local position
		local centre = if poi.zone then centres[poi.zone] else nil
		if centre then
			-- Outside the patrol ring, so the landmark is among its people
			-- without standing on top of one of their waypoints.
			local angle = rng:NextNumber(0, math.pi * 2)
			position = centre
				+ Vector3.new(math.cos(angle) * LANDMARK_OFFSET, 0, math.sin(angle) * LANDMARK_OFFSET)
		else
			-- No district named: fall back to an even circle. Honest rather
			-- than wrong -- it is somewhere, just nowhere in particular.
			local angle = (index - 1) * (math.pi * 2 / math.max(1, #planet.pointsOfInterest))
			local distance = SETTLEMENT_RADIUS * 0.55
			position = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		end

		local def = landmarkFor(poi)

		if not planet.hasWalkableGround then
			-- No ground at all: a platform or nowhere, so any platform will
			-- do and the search is deliberately unbounded.
			position = claimNear(position, math.huge) or position
		elseif (position - origin).Magnitude < SETTLEMENT_RADIUS then
			-- There are houses in the way, so it takes an empty yard -- but
			-- only one within a block of where it wanted to stand.
			local yard = if def.radius <= BLOCK_SIZE * 0.5 then claimNear(position, BLOCK_SIZE) else nil

			if yard then
				position = yard
			else
				--[[
					No free yard nearby, or too big for a city block: it
					stands just past the last street on its district's
					bearing, which is where a spaceport or a fortress belongs
					anyway. Moving it outwards keeps it on its own compass
					point; the alternative -- taking whatever block happened
					to be free -- is a farmstead in the middle of downtown.
				]]
				local bearing = position - origin
				local out = if bearing.Magnitude > 1 then bearing.Unit else Vector3.new(1, 0, 0)
				position = origin + out * (SETTLEMENT_RADIUS + def.radius + 40)
			end
		end

		buildLandmark(landmarkRoot, poi, def, position, style, rng)
		-- The marker is sized to the landmark rather than to a fixed box, so
		-- everything measuring against it -- "have I reached this", "where do
		-- the pickups go" -- scales with the building instead of guessing.
		marker(
			poiRoot,
			poi.id,
			position + Vector3.new(0, 3, 0),
			Vector3.new(def.radius * 2, 20, def.radius * 2)
		)
	end

	local spawnFolder = folder(planetId, folder("Spawns", Workspace))
	spawnFolder:ClearAllChildren()

	local open: { Vector3 } = {}
	for i, anchor in anchors do
		if not claimed[i] then
			table.insert(open, anchor)
		end
	end
	if #open == 0 then
		table.insert(open, origin)
	end

	for i = 1, math.min(6, #open) do
		marker(
			spawnFolder,
			`Spawn{i}`,
			open[rng:NextInteger(1, #open)] + Vector3.new(0, 4, 0),
			Vector3.new(8, 1, 8)
		)
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Builds `planetId` into Workspace, or does nothing if it is already there.
function PlanetBuilder.build(planetId: string)
	local planetsFolder = folder("Planets", Workspace)
	if planetsFolder:FindFirstChild(planetId) then
		return
	end

	local planet = Planets.get(planetId)
	local origin = originFor(planetId)
	local rng = Random.new(seedFrom(planetId))
	local style = styleFor(planet)

	local root = folder(planetId, planetsFolder)
	local anchors: { Vector3 }

	if planet.hasWalkableGround then
		buildGround(root, planet, origin)
		anchors = buildSettlement(root, planet, origin, style, rng)
		buildScatter(root, planet, origin, style, rng)
	else
		anchors = buildVerticalCity(root, planet, origin, rng)
	end

	buildMarkers(planet, root, origin, anchors, style, rng)
end

return PlanetBuilder
