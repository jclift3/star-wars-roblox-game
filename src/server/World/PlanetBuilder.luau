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

-- Paving sits just proud of the ground, flush with the plaza slab, so a road
-- and the square it leaves from are one continuous surface to walk on.
local ROAD_Y = 0.25
local ROAD_THICKNESS = 1
-- Narrower than the gap between blocks: the leftover is a verge, and a road
-- that exactly fills its gap reads as a floor rather than as a road.
local ROAD_WIDTH = 18
--[[
	Every crossing is two slabs overlapping, so each layer of paving gets its
	own height or their top faces are coplanar and z-fight -- the roads
	visibly flicker. Planets sit at multiples of 12,000 studs from the world
	origin, where a float32 resolves to roughly 0.004 studs, so the steps are
	deliberately much larger than they need to be to separate the faces. The
	tallest is 0.36 over the plaza, well under a character's step height.
]]
local ROAD_LIFT_NS = 0.12
local ROAD_LIFT_EW = 0.24
local ROAD_LIFT_RADIAL = 0.36

local TOWER_BASE_Y = -400
local SKYLANE_STEP = 220

type Style = {
	buildingColors: { Color3 },
	minFloors: number,
	maxFloors: number,
	floorHeight: number,
	windowColor: Color3,
	scatter: string, -- "Dunes" | "Rocks" | "Trees" | "Drifts" | "None"
	-- The building geometry itself. See the Architecture section below.
	shape: (Instance, Vector3, Vector2, Style, Random) -> (),
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

-- A WedgePart slopes down along +Z, so two mirrored wedges make a pitched roof.
local function wedge(
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material
): WedgePart
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

local function pick<T>(list: { T }, rng: Random): T
	return list[rng:NextInteger(1, #list)]
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
-- Architecture
--------------------------------------------------------------------------------

--[[
	How each world builds.

	This used to switch on `terrain`, which meant five looks across nine
	worlds: Korriban was Tatooine in different sand, and Coruscant, Taris and
	Nar Shaddaa were one style between them. A planet now declares an
	`architecture` and that picks a *shape function*, not just a palette --
	because the palette was never the problem. Every world ran the same stack
	of tapering boxes with window strips.

	Scatter still follows terrain, because trees and dunes genuinely are facts
	about the ground rather than about the people who built there.
]]

local SCATTER: { [string]: string } = {
	Desert = "Dunes",
	Ice = "Drifts",
	Forest = "Trees",
	Swamp = "Trees",
	Volcanic = "Rocks",
}

--- Window strips down two faces. Neon so they still read at night.
local function windowBands(
	parent: Instance,
	base: Vector3,
	style: Style,
	yStart: number,
	floors: number,
	width: number,
	depth: number
)
	for floor = 1, floors do
		local y = yStart + (floor - 0.5) * style.floorHeight
		for _, side in { 1, -1 } do
			local band = block(
				parent,
				CFrame.new(base + Vector3.new(0, y, side * depth * 0.5)),
				Vector3.new(width * 0.82, 2.2, 0.4),
				style.windowColor,
				Enum.Material.Neon
			)
			band.Name = "Windows"
			band.CanCollide = false
		end
	end
end

--- Tatooine. Sandblasted adobe drums under domes: no straight skyline at all.
local function adobeShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local span = math.min(footprint.X, footprint.Y)
	local height = rng:NextInteger(style.minFloors, style.maxFloors) * style.floorHeight

	cylinder(
		parent,
		CFrame.new(base + Vector3.new(0, height * 0.5, 0)) * UPRIGHT,
		Vector3.new(height, span, span),
		color,
		Enum.Material.Sandstone
	).Name =
		"Drum"

	ball(
		parent,
		CFrame.new(base + Vector3.new(0, height, 0)),
		Vector3.new(span, span * 0.85, span),
		color,
		Enum.Material.Sandstone
	).Name =
		"Dome"

	-- A lean-to annex, offset so no two neighbours line up.
	local annex = span * rng:NextNumber(0.4, 0.6)
	local angle = rng:NextNumber(0, math.pi * 2)
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (span * 0.5 + annex * 0.4)
	cylinder(
		parent,
		CFrame.new(base + offset + Vector3.new(0, annex * 0.4, 0)) * UPRIGHT,
		Vector3.new(annex * 0.8, annex, annex),
		color,
		Enum.Material.Sandstone
	).Name =
		"Annex"

	-- Slit windows, not bands. Desert buildings keep the sun out.
	for _ = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local slit = block(
			parent,
			CFrame.new(
				base + Vector3.new(math.cos(a), 0, math.sin(a)) * span * 0.5 + Vector3.new(0, height * 0.6, 0)
			),
			Vector3.new(1.6, 3.2, 1.6),
			style.windowColor,
			Enum.Material.Neon
		)
		slit.Name = "Slit"
		slit.CanCollide = false
	end
end

--- Korriban. Stepped funerary stone. No windows anywhere: these are tombs.
local function zigguratShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local width, depth = footprint.X, footprint.Y
	local tiers = rng:NextInteger(3, 5)
	local tierHeight = style.floorHeight
	local y = 0

	for _ = 1, tiers do
		block(
			parent,
			CFrame.new(base + Vector3.new(0, y + tierHeight * 0.5, 0)),
			Vector3.new(width, tierHeight, depth),
			color,
			Enum.Material.Slate
		).Name =
			"Step"
		y += tierHeight
		width *= 0.74
		depth *= 0.74
	end

	-- The burning slit over the door, and the only light on the building.
	local mouth = block(
		parent,
		CFrame.new(base + Vector3.new(0, tierHeight * 0.45, footprint.Y * 0.5)),
		Vector3.new(footprint.X * 0.22, tierHeight * 0.55, 0.6),
		style.windowColor,
		Enum.Material.Neon
	)
	mouth.Name = "Mouth"
	mouth.CanCollide = false

	-- Flanking obelisks. These are what make the valley read as a valley of
	-- tombs from a distance rather than as a stack of crates.
	for _, side in { 1, -1 } do
		local obelisk = block(
			parent,
			CFrame.new(base + Vector3.new(side * footprint.X * 0.62, y * 0.55, footprint.Y * 0.45)),
			Vector3.new(footprint.X * 0.1, y * 1.1, footprint.X * 0.1),
			Palette.SithBlack,
			Enum.Material.Slate
		)
		obelisk.Name = "Obelisk"
		obelisk.CFrame = obelisk.CFrame * CFrame.Angles(0, 0, side * 0.04)
	end
end

--- Taris. Sheared-off duracrete towers with their frames showing.
local function ruinShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local width, depth = footprint.X, footprint.Y
	local floors = rng:NextInteger(style.minFloors, style.maxFloors)
	local standing = math.max(1, math.floor(floors * rng:NextNumber(0.35, 0.8)))
	local height = standing * style.floorHeight

	block(
		parent,
		CFrame.new(base + Vector3.new(0, height * 0.5, 0)),
		Vector3.new(width, height, depth),
		color,
		Enum.Material.CrackedLava
	).Name =
		"Shell"

	windowBands(parent, base, style, 0, standing - 1, width, depth)

	-- The sheared top: a half-floor slab covering part of the footprint, so
	-- the roofline is broken rather than flat.
	local keep = rng:NextNumber(0.35, 0.7)
	block(
		parent,
		CFrame.new(base + Vector3.new(width * (0.5 - keep * 0.5), height + style.floorHeight * 0.3, 0)),
		Vector3.new(width * keep, style.floorHeight * 0.6, depth),
		color,
		Enum.Material.CrackedLava
	).Name =
		"Shear"

	-- Girders left standing where the floors above used to be.
	for _ = 1, rng:NextInteger(2, 4) do
		local exposed = rng:NextNumber(6, style.floorHeight * 2)
		block(
			parent,
			CFrame.new(
				base
					+ Vector3.new(
						rng:NextNumber(-width * 0.45, width * 0.45),
						height + exposed * 0.5,
						rng:NextNumber(-depth * 0.45, depth * 0.45)
					)
			),
			Vector3.new(1.2, exposed, 1.2),
			Palette.DroidRust,
			Enum.Material.CorrodedMetal
		).Name =
			"Girder"
	end

	-- Rubble at the foot, which is where the height went.
	for _ = 1, rng:NextInteger(2, 4) do
		local chunk = rng:NextNumber(4, 11)
		local a = rng:NextNumber(0, math.pi * 2)
		local slab = block(
			parent,
			CFrame.new(
				base
					+ Vector3.new(math.cos(a), 0, math.sin(a)) * (width * 0.5 + chunk * 0.6)
					+ Vector3.new(0, chunk * 0.3, 0)
			),
			Vector3.new(chunk, chunk * 0.6, chunk),
			color,
			Enum.Material.Concrete
		)
		slab.Name = "Rubble"
		slab.CFrame = slab.CFrame * CFrame.Angles(rng:NextNumber(-0.4, 0.4), a, rng:NextNumber(-0.4, 0.4))
	end
end

--- Nar Shaddaa. Slabs stacked by whoever got there first, and signage.
local function neonStackShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local width, depth = footprint.X, footprint.Y
	local slabs = rng:NextInteger(3, 5)
	local y = 0

	for slab = 1, slabs do
		local height = style.floorHeight * rng:NextNumber(0.8, 1.6)
		-- Each slab shoves sideways rather than shrinking, so the tower
		-- overhangs the street the way a Hutt world should.
		local shove = Vector3.new(
			rng:NextNumber(-width * 0.22, width * 0.22),
			0,
			rng:NextNumber(-depth * 0.22, depth * 0.22)
		)
		local w = width * rng:NextNumber(0.7, 1.05)
		local d = depth * rng:NextNumber(0.7, 1.05)

		block(
			parent,
			CFrame.new(base + shove + Vector3.new(0, y + height * 0.5, 0)),
			Vector3.new(w, height, d),
			pick(style.buildingColors, rng),
			Enum.Material.DiamondPlate
		).Name =
			`Slab{slab}`

		-- A sign on most of them. Neon is the whole identity of this world.
		if rng:NextNumber() < 0.7 then
			local sign = block(
				parent,
				CFrame.new(base + shove + Vector3.new(0, y + height * 0.5, d * 0.5 + 0.6)),
				Vector3.new(w * 0.7, height * 0.5, 0.5),
				style.windowColor,
				Enum.Material.Neon
			)
			sign.Name = "Sign"
			sign.CanCollide = false
		end

		y += height
	end

	-- A vertical strip running the full height, the classic Hutt-slum tell.
	local strip = block(
		parent,
		CFrame.new(base + Vector3.new(width * 0.5 + 0.5, y * 0.5, 0)),
		Vector3.new(0.6, y * 0.9, 2.4),
		Palette.SaberPurple,
		Enum.Material.Neon
	)
	strip.Name = "Strip"
	strip.CanCollide = false
end

--- Coruscant. Smooth tapering towers, dense glass, a mast on every one.
local function spireShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local width, depth = footprint.X, footprint.Y
	local floors = rng:NextInteger(style.minFloors, style.maxFloors)
	local tiers = 4
	local y = 0
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
			Enum.Material.Metal
		).Name =
			"Storey"
		windowBands(parent, base, style, y, tierFloors, width, depth)

		y += height
		-- A gentle taper. The old generator used 0.82 per tier, which turned a
		-- twelve-floor tower into a wedding cake.
		width *= 0.93
		depth *= 0.93
	end

	cylinder(
		parent,
		CFrame.new(base + Vector3.new(0, y + 22, 0)) * UPRIGHT,
		Vector3.new(44, 2.4, 2.4),
		Palette.WornSteel,
		Enum.Material.Metal
	).Name =
		"Mast"

	local beacon = ball(
		parent,
		CFrame.new(base + Vector3.new(0, y + 44, 0)),
		Vector3.new(3, 3, 3),
		Palette.BlasterRed,
		Enum.Material.Neon
	)
	beacon.Name = "Beacon"
	beacon.CanCollide = false
end

--- Ord Mantell. Prefab huts on stilts with corrugated pitched roofs.
local function frontierShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local width, depth = footprint.X * 0.8, footprint.Y * 0.8
	local stilt = rng:NextNumber(4, 9)
	local height = rng:NextInteger(style.minFloors, style.maxFloors) * style.floorHeight

	-- Stilts. Everything here is built above a wet season.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(
				parent,
				CFrame.new(base + Vector3.new(sx * width * 0.42, stilt * 0.5, sz * depth * 0.42)),
				Vector3.new(1.6, stilt, 1.6),
				Palette.DroidRust,
				Enum.Material.CorrodedMetal
			).Name =
				"Stilt"
		end
	end

	block(
		parent,
		CFrame.new(base + Vector3.new(0, stilt + height * 0.5, 0)),
		Vector3.new(width, height, depth),
		color,
		Enum.Material.CorrodedMetal
	).Name =
		"Hut"

	-- Pitched roof from two mirrored wedges. A flat roof is what made every
	-- world look like the same industrial estate.
	local pitch = height * 0.5
	for _, side in { 1, -1 } do
		wedge(
			parent,
			CFrame.new(base + Vector3.new(0, stilt + height + pitch * 0.5, side * depth * 0.25))
				* CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
			Vector3.new(width, pitch, depth * 0.5),
			Palette.WornSteel,
			Enum.Material.CorrodedMetal
		).Name =
			"Roof"
	end

	-- One lit window and a stovepipe.
	local pane = block(
		parent,
		CFrame.new(base + Vector3.new(0, stilt + height * 0.55, depth * 0.5)),
		Vector3.new(width * 0.3, height * 0.3, 0.4),
		style.windowColor,
		Enum.Material.Neon
	)
	pane.Name = "Pane"
	pane.CanCollide = false

	cylinder(
		parent,
		CFrame.new(base + Vector3.new(width * 0.3, stilt + height + pitch + 4, 0)) * UPRIGHT,
		Vector3.new(9, 1.4, 1.4),
		Palette.DarkMetal,
		Enum.Material.CorrodedMetal
	).Name =
		"Stovepipe"
end

--- Tython. Low stone halls behind a colonnade. Nothing here is in a hurry.
local function jediStoneShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local width, depth = footprint.X, footprint.Y
	local height = rng:NextInteger(style.minFloors, style.maxFloors) * style.floorHeight

	block(
		parent,
		CFrame.new(base + Vector3.new(0, height * 0.5, 0)),
		Vector3.new(width * 0.78, height, depth * 0.78),
		color,
		Enum.Material.Limestone
	).Name =
		"Hall"

	-- Pillars around the perimeter, which is the whole silhouette.
	local pillars = 8
	for i = 1, pillars do
		local a = (i / pillars) * math.pi * 2
		cylinder(
			parent,
			CFrame.new(
				base + Vector3.new(math.cos(a) * width * 0.46, height * 0.45, math.sin(a) * depth * 0.46)
			) * UPRIGHT,
			Vector3.new(height * 0.9, 3.4, 3.4),
			color,
			Enum.Material.Limestone
		).Name =
			"Pillar"
	end

	-- A wide overhanging lid resting on them.
	block(
		parent,
		CFrame.new(base + Vector3.new(0, height * 0.95, 0)),
		Vector3.new(width * 1.08, height * 0.12, depth * 1.08),
		color,
		Enum.Material.Limestone
	).Name =
		"Lid"

	-- Shallow stepped roof above the lid.
	for step = 1, 3 do
		local shrink = 1 - step * 0.22
		block(
			parent,
			CFrame.new(base + Vector3.new(0, height * (1.0 + step * 0.1), 0)),
			Vector3.new(width * 0.85 * shrink, height * 0.1, depth * 0.85 * shrink),
			color,
			Enum.Material.Limestone
		).Name =
			"Roof"
	end

	local lantern = ball(
		parent,
		CFrame.new(base + Vector3.new(0, height * 1.42, 0)),
		Vector3.new(4, 4, 4),
		style.windowColor,
		Enum.Material.Neon
	)
	lantern.Name = "Lantern"
	lantern.CanCollide = false
end

--- Hoth. Half-buried domes joined by tunnels. Most of it is under the snow.
local function iceBunkerShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local span = math.min(footprint.X, footprint.Y)
	local rise = span * rng:NextNumber(0.28, 0.42)

	-- The dome sits low: two thirds of it is below the surface, which is why
	-- this reads as dug in rather than as another box.
	ball(
		parent,
		CFrame.new(base + Vector3.new(0, rise - span * 0.35, 0)),
		Vector3.new(span, span, span),
		color,
		Enum.Material.Glacier
	).Name =
		"Dome"

	-- A wind berm on the weather side.
	local a = rng:NextNumber(0, math.pi * 2)
	local berm = block(
		parent,
		CFrame.new(
			base + Vector3.new(math.cos(a), 0, math.sin(a)) * span * 0.62 + Vector3.new(0, rise * 0.3, 0)
		),
		Vector3.new(span * 0.9, rise * 0.7, span * 0.25),
		Palette.HothSnow,
		Enum.Material.Snow
	)
	berm.Name = "Berm"
	berm.CFrame = berm.CFrame * CFrame.Angles(0, -a, 0)

	-- The tunnel mouth, and the only thing you can actually walk to.
	local mouthAngle = a + math.pi
	local mouth = Vector3.new(math.cos(mouthAngle), 0, math.sin(mouthAngle)) * span * 0.45
	block(
		parent,
		CFrame.new(base + mouth + Vector3.new(0, 5, 0)),
		Vector3.new(14, 10, 14),
		Palette.WornSteel,
		Enum.Material.Metal
	).Name =
		"TunnelMouth"

	local glow = block(
		parent,
		CFrame.new(base + mouth * 1.4 + Vector3.new(0, 5, 0)),
		Vector3.new(8, 6, 0.5),
		style.windowColor,
		Enum.Material.Neon
	)
	glow.Name = "Glow"
	glow.CanCollide = false

	-- Aerials, because a buried base needs something above the snowline.
	for _ = 1, rng:NextInteger(1, 3) do
		local mastAngle = rng:NextNumber(0, math.pi * 2)
		cylinder(
			parent,
			CFrame.new(
				base
					+ Vector3.new(math.cos(mastAngle), 0, math.sin(mastAngle)) * span * 0.3
					+ Vector3.new(0, rise + 9, 0)
			) * UPRIGHT,
			Vector3.new(20, 1, 1),
			Palette.DarkMetal,
			Enum.Material.Metal
		).Name =
			"Aerial"
	end
end

--- Dromund Kaas. Tall, black, buttressed and pointed. Deliberately unfriendly.
local function gothicShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local width, depth = footprint.X * 0.7, footprint.Y * 0.7
	local floors = rng:NextInteger(style.minFloors, style.maxFloors)
	local height = floors * style.floorHeight

	block(
		parent,
		CFrame.new(base + Vector3.new(0, height * 0.5, 0)),
		Vector3.new(width, height, depth),
		color,
		Enum.Material.Slate
	).Name =
		"Tower"

	-- Buttress fins on all four corners, leaning in. These do more for the
	-- silhouette than any amount of extra height.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local fin = block(
				parent,
				CFrame.new(base + Vector3.new(sx * width * 0.55, height * 0.4, sz * depth * 0.55)),
				Vector3.new(width * 0.14, height * 0.85, depth * 0.14),
				color,
				Enum.Material.Slate
			)
			fin.Name = "Buttress"
			fin.CFrame = fin.CFrame * CFrame.Angles(sz * 0.06, 0, -sx * 0.06)
		end
	end

	-- Narrow vertical slits rather than window bands. Nothing here wants light.
	for _, side in { 1, -1 } do
		for i = 1, 3 do
			local slit = block(
				parent,
				CFrame.new(base + Vector3.new((i - 2) * width * 0.28, height * 0.5, side * depth * 0.5)),
				Vector3.new(1.4, height * 0.6, 0.4),
				style.windowColor,
				Enum.Material.Neon
			)
			slit.Name = "Slit"
			slit.CanCollide = false
		end
	end

	-- The point.
	local spike = height * 0.34
	for _, side in { 1, -1 } do
		wedge(
			parent,
			CFrame.new(base + Vector3.new(0, height + spike * 0.5, side * depth * 0.25))
				* CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
			Vector3.new(width, spike, depth * 0.5),
			color,
			Enum.Material.Slate
		).Name =
			"Crown"
	end
end

local ARCHITECTURE: { [string]: Style } = {
	Adobe = {
		buildingColors = { Palette.TatooineSand, Palette.TatooineRock, Palette.SandtrooperTan },
		minFloors = 1,
		maxFloors = 2,
		floorHeight = 11,
		windowColor = Palette.CoruscantLight,
		scatter = "None",
		shape = adobeShape,
	},
	SithZiggurat = {
		buildingColors = { Palette.SithBlack, Palette.MustafarBasalt, Palette.DarkMetal },
		minFloors = 2,
		maxFloors = 4,
		floorHeight = 13,
		windowColor = Palette.SaberRed,
		scatter = "None",
		shape = zigguratShape,
	},
	Ruin = {
		buildingColors = { Palette.WornSteel, Palette.Gunmetal, Palette.NabooStone, Palette.CoruscantPlate },
		minFloors = 4,
		maxFloors = 11,
		floorHeight = 15,
		windowColor = Palette.DroidGold,
		scatter = "None",
		shape = ruinShape,
	},
	NeonStack = {
		buildingColors = { Palette.DarkMetal, Palette.Gunmetal, Palette.ImperialGrey, Palette.SmugglerBrown },
		minFloors = 3,
		maxFloors = 8,
		floorHeight = 13,
		windowColor = Palette.TwilekRed,
		scatter = "None",
		shape = neonStackShape,
	},
	Spire = {
		buildingColors = { Palette.CoruscantPlate, Palette.HullGrey, Palette.WornSteel, Palette.NabooStone },
		minFloors = 6,
		maxFloors = 14,
		floorHeight = 16,
		windowColor = Palette.CoruscantLight,
		scatter = "None",
		shape = spireShape,
	},
	Frontier = {
		buildingColors = { Palette.RebelTan, Palette.SmugglerBrown, Palette.DroidRust, Palette.RebelOlive },
		minFloors = 1,
		maxFloors = 2,
		floorHeight = 12,
		windowColor = Palette.DroidGold,
		scatter = "None",
		shape = frontierShape,
	},
	JediStone = {
		buildingColors = { Palette.NabooStone, Palette.JediCream, Palette.SandtrooperTan },
		minFloors = 1,
		maxFloors = 3,
		floorHeight = 13,
		windowColor = Palette.SaberYellow,
		scatter = "None",
		shape = jediStoneShape,
	},
	IceBunker = {
		buildingColors = { Palette.HothIce, Palette.StormtrooperShadow, Palette.WornSteel },
		minFloors = 1,
		maxFloors = 2,
		floorHeight = 12,
		windowColor = Palette.BlasterBlue,
		scatter = "None",
		shape = iceBunkerShape,
	},
	ImperialGothic = {
		buildingColors = { Palette.ImperialBlack, Palette.DarkMetal, Palette.ImperialGrey },
		minFloors = 4,
		maxFloors = 9,
		floorHeight = 15,
		windowColor = Palette.SaberRed,
		scatter = "None",
		shape = gothicShape,
	},
}

-- At load, not at first visit. A typo here means a world silently looks like
-- a different world, which is exactly the bug this whole section exists to
-- fix, and you would not see it until someone travelled there.
for _, id in Planets.ids() do
	local name = Planets.get(id).architecture
	if not ARCHITECTURE[name] then
		warn(`[PlanetBuilder] {id}: unknown architecture "{name}"; it will build as Spire`)
	end
end

local function styleFor(planet: Planets.PlanetDef): Style
	local base = ARCHITECTURE[planet.architecture] or ARCHITECTURE.Spire
	local style = table.clone(base)
	style.scatter = SCATTER[planet.terrain] or "None"
	return style
end

--------------------------------------------------------------------------------
-- Roads
--------------------------------------------------------------------------------

--[[
	Somewhere to walk.

	The settlement always had streets in the sense that it left gaps between
	blocks, but a gap is not a road: it is the same ground as everywhere else,
	so a town read as buildings dropped on a plain and there was no clue which
	way anything was. Paving the gaps costs sixteen parts and turns the same
	layout into a place with a direction.

	Roads also answer "how do I find anything". One runs from the plaza to
	every landmark on the planet, so following a road is a navigation method
	that needs no UI -- and the landmarks it reaches are the Reach objectives.
]]

--- Ground you have paved: the planet's own colour, darker, packed hard.
local function roadLook(planet: Planets.PlanetDef): (Color3, Enum.Material)
	local terrain = planet.terrain
	if terrain == "Urban" then
		return planet.groundColor:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Concrete
	elseif terrain == "Ice" then
		-- Cleared, not covered. A path through snow is the dark line in it.
		return planet.groundColor:Lerp(Color3.new(0, 0, 0), 0.4), Enum.Material.Ice
	elseif terrain == "Desert" then
		return planet.groundColor:Lerp(Color3.new(0, 0, 0), 0.22), Enum.Material.Sand
	end
	return planet.groundColor:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Ground
end

--- One straight run of paving between two points on the ground plane.
--- `lift` separates this run from whatever it crosses; see the ROAD_LIFT_* notes.
local function pave(
	parent: Instance,
	from: Vector3,
	to: Vector3,
	color: Color3,
	material: Enum.Material,
	lift: number
)
	local y = ROAD_Y + lift
	local flatFrom = Vector3.new(from.X, y, from.Z)
	local flatTo = Vector3.new(to.X, y, to.Z)
	local run = (flatTo - flatFrom).Magnitude
	if run < 1 then
		return
	end

	local road = block(
		parent,
		CFrame.lookAt((flatFrom + flatTo) * 0.5, flatTo),
		-- lookAt points -Z along the run, so length is the Z component.
		Vector3.new(ROAD_WIDTH, ROAD_THICKNESS, run),
		color,
		material
	)
	road.Name = "Road"
end

--[[
	The street grid inside town.

	Lines are laid on the *boundaries* between blocks rather than through
	their centres, which is where `buildSettlement` already leaves its margin,
	and each is cut to the chord of the settlement circle at that offset. The
	town is round, so a square grid over it would run streets out into empty
	desert past the last house.
]]
local function buildStreets(parent: Instance, planet: Planets.PlanetDef, origin: Vector3)
	local streets = folder("Streets", parent)
	local color, material = roadLook(planet)
	local reach = math.floor(SETTLEMENT_RADIUS / BLOCK_SIZE)

	for line = -reach, reach + 1 do
		local offset = (line - 0.5) * BLOCK_SIZE
		if math.abs(offset) >= SETTLEMENT_RADIUS then
			continue
		end
		local half = math.sqrt(SETTLEMENT_RADIUS ^ 2 - offset ^ 2)

		pave(
			streets,
			origin + Vector3.new(offset, 0, -half),
			origin + Vector3.new(offset, 0, half),
			color,
			material,
			ROAD_LIFT_NS
		)
		pave(
			streets,
			origin + Vector3.new(-half, 0, offset),
			origin + Vector3.new(half, 0, offset),
			color,
			material,
			ROAD_LIFT_EW
		)
	end
end

--------------------------------------------------------------------------------
-- Ground and scatter
--------------------------------------------------------------------------------

--[[
	Shape on the horizon.

	The walkable floor is a single flat slab and stays one for now -- every
	placement in this file assumes ground at y = 0, so real elevation is a
	change to how buildings, spawns and landmarks find their footing, not a
	change to the ground. What was cheap and missing is a *skyline*: nine
	worlds whose horizon was the same straight line, which is most of why
	they felt like the same world at a distance.

	So: relief outside the play area, sized to be read rather than climbed.
	Deliberately nothing on Urban worlds, where the horizon should be city.
]]
local RELIEF: { [string]: string } = {
	Desert = "Mesa",
	Ice = "Ridge",
	Volcanic = "Ridge",
	Forest = "Hill",
	Swamp = "Hill",
}

local function buildRelief(parent: Instance, planet: Planets.PlanetDef, origin: Vector3, rng: Random)
	local kind = RELIEF[planet.terrain]
	if not kind then
		return
	end

	local hills = folder("Relief", parent)
	local color = planet.rockColor or planet.groundColor
	local material = if kind == "Ridge" and planet.terrain == "Ice"
		then Enum.Material.Glacier
		elseif kind == "Mesa" then Enum.Material.Sandstone
		else Enum.Material.Rock

	local count = rng:NextInteger(14, 18)
	for i = 1, count do
		-- Evenly spaced with jitter, so the ring is a range of hills rather
		-- than a fence with regular posts.
		local angle = (i - 1) * (math.pi * 2 / count) + rng:NextNumber(-0.14, 0.14)
		local distance = rng:NextNumber(1120, 1300)
		local base = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local width = rng:NextNumber(220, 400)

		if kind == "Hill" then
			-- A hill is the scatter mound at ten times the size: the shape
			-- was right, only ever the scale was wrong.
			local height = width * rng:NextNumber(0.5, 0.8)
			local mound = ball(
				hills,
				CFrame.new(base + Vector3.new(0, height * 0.1, 0))
					* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Vector3.new(width, height, width * rng:NextNumber(0.8, 1.3)),
				color,
				material
			)
			mound.Name = "Hill"
			continue
		end

		-- Mesas and ridges are both stacked, shrinking slabs -- the same
		-- trick the skyline uses, which is what makes them read as one
		-- object from a long way off. A mesa is squat, a ridge is not.
		local tiers = rng:NextInteger(2, 4)
		local tierHeight = if kind == "Mesa" then width * 0.3 else width * 0.62
		local y = -20 -- buried, so no seam shows where the slab ends
		local w, d = width, width * rng:NextNumber(0.6, 1.1)

		for tier = 1, tiers do
			local height = tierHeight * (1 - (tier - 1) * 0.2)
			local slab = block(
				hills,
				CFrame.new(base + Vector3.new(0, y + height * 0.5, 0))
					* CFrame.Angles(0, angle + rng:NextNumber(-0.2, 0.2), 0),
				Vector3.new(w, height, d),
				color,
				material
			)
			slab.Name = kind
			y += height
			w *= 0.74
			d *= 0.74
		end
	end
end

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

	buildStreets(town, planet, origin)

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

			style.shape(town, centre + jitter, footprint, style, rng)

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

--[[
	A name floating over a landmark, so a place says what it is.

	`sightRange` is the distance the sign gives up at, and it is derived from
	the landmark's own size rather than fixed. A flat 900 studs signed
	everything identically, and because a BillboardGui is drawn with
	`LightInfluence = 0` it ignores the fog that is busy hiding the building
	underneath it -- so a small structure out on the edge of town was a crisp
	label hanging over an empty horizon. A sign should not outrun the thing it
	is pointing at.
]]
local function nameplate(parent: Instance, position: Vector3, text: string, sightRange: number)
	local anchor = marker(parent, "Nameplate", position, Vector3.new(1, 1, 1))

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(320, 40)
	gui.MaxDistance = sightRange
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
	-- Roughly where the structure stops being a shape and starts being a
	-- speck: a cantina announces itself across its own street, a spaceport
	-- across the district.
	nameplate(site, position + Vector3.new(0, top + 10, 0), poi.displayName, 240 + def.radius * 4)
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
	-- Collected as each landmark settles on a position, because where they
	-- end up is decided below and nothing knows it until then.
	local reached: { Vector3 } = {}

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

	local poiCount = math.max(1, #planet.pointsOfInterest)

	for index, poi in planet.pointsOfInterest do
		local position
		local centre = if poi.zone then centres[poi.zone] else nil
		--[[
			Each landmark gets its own slice of the compass, the way the
			districts already do, instead of a free-for-all bearing.

			The bearing survives everything downstream -- the oversize rule
			below pushes a landmark straight out along it -- so two rolls of
			the same angle put two buildings on one line of sight, and their
			signs render stacked on top of each other. Anchorhead and the
			cantina were doing exactly that.
		]]
		local angle = (index - 1) * (math.pi * 2 / poiCount) + rng:NextNumber(-0.25, 0.25)

		if centre then
			-- Outside the patrol ring, so the landmark is among its people
			-- without standing on top of one of their waypoints.
			position = centre
				+ Vector3.new(math.cos(angle) * LANDMARK_OFFSET, 0, math.sin(angle) * LANDMARK_OFFSET)
		else
			-- No district named: fall back to an even circle. Honest rather
			-- than wrong -- it is somewhere, just nowhere in particular.
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
		table.insert(reached, position)
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

	--[[
		A road out of town to every landmark that stands outside it.

		It starts at the edge of the settlement, not at the plaza. Drawn from
		the centre it would be a straight line across a grid of buildings,
		cutting through whichever houses stood on the bearing -- inside the
		walls the street grid is already the road, and out here there is
		nothing to cut through. Landmarks that took a yard in town get
		nothing, correctly: they are on a street already.

		Straight, because a curve would have to know what it was curving
		around, and a road you can see the whole length of is the navigation.
	]]
	if planet.hasWalkableGround then
		local roads = folder("Roads", root)
		local color, material = roadLook(planet)
		for index, destination in reached do
			local bearing = destination - origin
			local flat = Vector3.new(bearing.X, 0, bearing.Z)
			if flat.Magnitude > SETTLEMENT_RADIUS then
				pave(
					roads,
					origin + flat.Unit * (SETTLEMENT_RADIUS * 0.94),
					destination,
					color,
					material,
					-- Radials all leave the same ring, so two landmarks on
					-- close bearings overlap near the town edge: give each
					-- its own height too.
					ROAD_LIFT_RADIAL + index * 0.04
				)
			end
		end
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
		buildRelief(root, planet, origin, rng)
		anchors = buildSettlement(root, planet, origin, style, rng)
		buildScatter(root, planet, origin, style, rng)
	else
		anchors = buildVerticalCity(root, planet, origin, rng)
	end

	buildMarkers(planet, root, origin, anchors, style, rng)
end

return PlanetBuilder
