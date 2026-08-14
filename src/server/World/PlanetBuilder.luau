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
	  Workspace/POI/<Planet>     -- mission "Reach" targets
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
-- Markers
--------------------------------------------------------------------------------

--[[
	Emits spawn, zone and POI markers.

	Zones are placed on rings out from the centre: the first zone a planet
	declares sits in the town, later ones progressively further out. Each gets
	three parts, which NPCService reads as a patrol route -- so guards walk a
	circuit without anyone hand-placing waypoints.
]]
local function buildMarkers(planet: Planets.PlanetDef, origin: Vector3, anchors: { Vector3 }, rng: Random)
	local planetId = planet.id

	local spawnFolder = folder(planetId, folder("Spawns", Workspace))
	spawnFolder:ClearAllChildren()

	local spawnPoints = if #anchors > 0 then anchors else { origin }
	for i = 1, math.min(6, #spawnPoints) do
		local index = if #anchors > 0 then rng:NextInteger(1, #spawnPoints) else 1
		marker(spawnFolder, `Spawn{i}`, spawnPoints[index] + Vector3.new(0, 4, 0), Vector3.new(8, 1, 8))
	end

	local zoneNames: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, rule in planet.spawns do
		local name = rule.zone or "Default"
		if not seen[name] then
			seen[name] = true
			table.insert(zoneNames, name)
		end
	end

	local zoneRoot = folder(planetId, folder("Zones", Workspace))
	zoneRoot:ClearAllChildren()

	for index, name in zoneNames do
		local zone = folder(name, zoneRoot)
		-- Ring 0 is the town centre; each later zone steps outward.
		local ring = (index - 1) * 190
		local baseAngle = rng:NextNumber(0, math.pi * 2)

		for point = 1, 3 do
			local angle = baseAngle + (point - 1) * (math.pi * 2 / 3)
			local distance = if ring == 0 then rng:NextNumber(40, 120) else ring + rng:NextNumber(-40, 40)
			local position = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

			-- Vertical cities have no ground, so zones snap to the nearest
			-- platform instead of hanging in the air.
			if not planet.hasWalkableGround and #anchors > 0 then
				position = anchors[rng:NextInteger(1, #anchors)]
			end

			marker(zone, `Point{point}`, position + Vector3.new(0, 3, 0), Vector3.new(60, 1, 60))
		end
	end

	local poiRoot = folder(planetId, folder("POI", Workspace))
	poiRoot:ClearAllChildren()

	for index, poi in planet.pointsOfInterest do
		local angle = (index - 1) * (math.pi * 2 / math.max(1, #planet.pointsOfInterest))
		local distance = SETTLEMENT_RADIUS * 0.55
		local position = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if not planet.hasWalkableGround and #anchors > 0 then
			position = anchors[math.min(index, #anchors)]
		end
		marker(poiRoot, poi.id, position + Vector3.new(0, 3, 0), Vector3.new(40, 20, 40))
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

	buildMarkers(planet, origin, anchors, rng)
end

return PlanetBuilder
