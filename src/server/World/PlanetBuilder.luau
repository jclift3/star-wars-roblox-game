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

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Config.Palette)
local Planets = require(Shared.Config.Planets)
-- Only for `Ships.PAD_TAG`. The spaceport has been drawing landing pads since
-- the first world was generated; this is what lets something land on them.
local Ships = require(Shared.Config.Ships)

local PlanetBuilder = {}

local SETTLEMENT_RADIUS = 520
local BLOCK_SIZE = 130
local STREET_WIDTH = 26

--[[
	The land is Roblox terrain; everything built on it is parts.

	This was the answer to the 2026-08-16 playtest note "why is everything
	still so blocky". It was not a lighting problem -- Future technology,
	Atmosphere, bloom and thirty materials were already in -- and it was not
	really the buildings either. It was that **there was not one voxel of
	terrain in the game**. Every world was a flat 3,000-stud plate with the
	horizon made of stacked shrinking slabs and hundred-stud plastic spheres,
	and no amount of post-processing fixes a landscape you can see the corners
	of.

	Terrain costs nothing to acquire, which matters: the project's standing
	rule is no marketplace mesh ids, and voxel terrain is the only smooth,
	textured, self-shadowing geometry Roblox gives away.

	The plate is no longer one fixed size. The old one was a 3,000-stud square
	on every world, which is millions of voxels and was only ever that big so
	that the smallest world's ground reached its fog; now it is measured off
	the planet's own districts (`flatRadiusFor`) plus the width of the relief.
	Hoth's ends inside its 900-stud whiteout, Tython's runs to 1,866 under a
	3,400-stud view, and neither pays for the other.
]]
local Terrain = Workspace.Terrain
--[[
	Only deep enough to look like ground from on top of it and to give the
	sunk balls of `mound` something to merge into. Nothing on a walkable world
	goes underground, and depth is a straight multiplier on voxel count.
]]
local TERRAIN_DEPTH = 16
--[[
	How far past the outermost district the plate runs, and the band the
	relief occupies inside that.

	The hills are `FillBall`s, which bring their own volume, so the plate does
	not have to reach the far side of them -- only far enough that the seam
	where it ends is behind a hill rather than in open view.
]]
local RELIEF_MARGIN = 450

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
-- The tower grid and the height between platform decks. Declared in config
-- rather than here because the client's ambient traffic flies down the gaps
-- these leave; see the note beside them in Planets.luau.
local TOWER_GRID = Planets.TOWER_GRID
local SKYLANE_STEP = Planets.SKYLANE_STEP

type Style = {
	buildingColors: { Color3 },
	minFloors: number,
	maxFloors: number,
	floorHeight: number,
	windowColor: Color3,
	--[[
		What a plain wall on this world is made of.

		Each `shape` function already picks its own materials part by part;
		this is for the shared machinery that has no shape function to ask --
		a room shell, a rampart -- and it is the difference between an
		authored shop on Tatooine being sandstone and being grey concrete
		with the right paint on it.
	]]
	wallMaterial: Enum.Material,
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
local originFor = Planets.originFor

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

--------------------------------------------------------------------------------
-- Silhouette detail
--------------------------------------------------------------------------------

--[[
	The second half of "why is everything still so blocky", and a different
	complaint from the first half hiding inside the same sentence.

	Terrain answered *the ground is a plate*. This answers **the buildings are
	correct boxes with nothing on them**: one flat colour, one material, a
	perfect right angle where the wall meets the floor and another where it
	meets the sky. Real construction has a footing, a shadow line, a lip, and
	junk on the roof, and it is those small horizontals that tell the eye how
	big something is. Without them a twelve-storey tower and a shed are the
	same picture at different zooms -- which is most of what "blocky" means
	once the lighting is already right.

	These are helpers rather than one pass over every building, because each
	shape function is the only thing that knows where its own roofline ended
	up, and three of the nine have no ground line to put a footing on (Hoth is
	half buried, Ord Mantell is on stilts, Nar Shaddaa overhangs).

	Everything that hangs off a wall is `CanCollide = false`. A ledge you can
	stand on is a ledge the boys will stand on, and none of these have
	anything under them. The one exception is Hoth's supply crates, which sit
	on the ground like the boulders in `buildScatter` and are solid for the
	same reason.
]]

--- A lighter or darker version of a colour. Negative darkens.
local function shade(color: Color3, amount: number): Color3
	return color:Lerp(if amount < 0 then Color3.new() else Color3.new(1, 1, 1), math.abs(amount))
end

--[[
	A footing course: a low slab a little wider than the building.

	The single highest-value part in this section. A wall that meets the
	ground at an unbroken right angle reads as an object sitting *on* a
	surface; the same wall with a plinth reads as a building standing *in* the
	ground, and it costs one part.
]]
local function plinth(
	parent: Instance,
	base: Vector3,
	width: number,
	depth: number,
	color: Color3,
	material: Enum.Material
)
	local p = block(
		parent,
		CFrame.new(base + Vector3.new(0, 1.4, 0)),
		Vector3.new(width * 1.07, 2.8, depth * 1.07),
		shade(color, -0.18),
		material
	)
	p.Name = "Plinth"
	p.CanCollide = false
end

--- An overhanging lip at `y`. A shadow line, which is what reads at distance.
local function cornice(
	parent: Instance,
	base: Vector3,
	y: number,
	width: number,
	depth: number,
	color: Color3,
	material: Enum.Material
)
	local p = block(
		parent,
		CFrame.new(base + Vector3.new(0, y, 0)),
		Vector3.new(width * 1.06, 1.6, depth * 1.06),
		shade(color, -0.12),
		material
	)
	p.Name = "Cornice"
	p.CanCollide = false
end

--[[
	Vents, tanks and ducting on a flat roof.

	A flat roofline is a straight line against the sky, and a straight line
	against the sky is the one thing the eye reads as artificial from any
	distance. Four boxes at four heights break it for the cost of four parts.
]]
local function roofClutter(
	parent: Instance,
	base: Vector3,
	y: number,
	width: number,
	depth: number,
	rng: Random
)
	for _ = 1, rng:NextInteger(2, 4) do
		local w = math.min(width, depth) * rng:NextNumber(0.12, 0.26)
		local h = rng:NextNumber(2.5, 7)
		local at = base
			+ Vector3.new(
				rng:NextNumber(-width * 0.33, width * 0.33),
				y + h * 0.5,
				rng:NextNumber(-depth * 0.33, depth * 0.33)
			)

		local box = if rng:NextNumber() < 0.4
			then cylinder(
				parent,
				CFrame.new(at) * UPRIGHT,
				Vector3.new(h, w, w),
				Palette.WornSteel,
				Enum.Material.Metal
			)
			else block(
				parent,
				CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Vector3.new(w, h, w * rng:NextNumber(0.7, 1.5)),
				Palette.DarkMetal,
				Enum.Material.DiamondPlate
			)
		box.Name = "Vent"
		box.CanCollide = false
	end
end

--[[
	A pipe run down the outside of a face, with a bracket collar or two.

	Pipes on the outside are the tell that a building was serviced rather than
	printed, and they are the cheapest vertical detail there is: they break a
	blank wall without touching the silhouette.
]]
local function conduit(parent: Instance, at: Vector3, height: number, rng: Random)
	local radius = rng:NextNumber(0.5, 1.1)
	local pipe = cylinder(
		parent,
		CFrame.new(at + Vector3.new(0, height * 0.5, 0)) * UPRIGHT,
		Vector3.new(height, radius * 2, radius * 2),
		Palette.DroidRust,
		Enum.Material.CorrodedMetal
	)
	pipe.Name = "Conduit"
	pipe.CanCollide = false

	for i = 1, 2 do
		local collar = cylinder(
			parent,
			CFrame.new(at + Vector3.new(0, height * (i / 3), 0)) * UPRIGHT,
			Vector3.new(0.8, radius * 3, radius * 3),
			Palette.DarkMetal,
			Enum.Material.Metal
		)
		collar.Name = "Collar"
		collar.CanCollide = false
	end
end

--- Tatooine. Sandblasted adobe drums under domes: no straight skyline at all.
local function adobeShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local span = math.min(footprint.X, footprint.Y)
	local height = rng:NextInteger(style.minFloors, style.maxFloors) * style.floorHeight

	-- A packed-earth footing, wind-worn wider than the wall above it.
	plinth(parent, base, span, span, color, Enum.Material.Sandstone)

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

	-- A vaporator stack off the dome. Water is the only reason anyone lives
	-- here, so the machinery that gets it belongs on the skyline.
	local vaporator = base + Vector3.new(span * 0.22, height + span * 0.3, span * 0.1)
	conduit(parent, vaporator, span * 0.5, rng)
	ball(
		parent,
		CFrame.new(vaporator + Vector3.new(0, span * 0.5, 0)),
		Vector3.new(4.5, 4.5, 4.5),
		Palette.WornSteel,
		Enum.Material.Metal
	).Name =
		"Condenser"
end

--- Korriban. Stepped funerary stone. No windows anywhere: these are tombs.
local function zigguratShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local width, depth = footprint.X, footprint.Y
	local tiers = rng:NextInteger(3, 5)
	local tierHeight = style.floorHeight
	local y = 0

	plinth(parent, base, width, depth, color, Enum.Material.Slate)

	for _ = 1, tiers do
		block(
			parent,
			CFrame.new(base + Vector3.new(0, y + tierHeight * 0.5, 0)),
			Vector3.new(width, tierHeight, depth),
			color,
			Enum.Material.Slate
		).Name =
			"Step"
		-- A capping course on every tier. A ziggurat is nothing but stacked
		-- horizontals, so the horizontals are what have to be legible; without
		-- them four boxes of the same colour read as one tapering box.
		cornice(parent, base, y + tierHeight, width, depth, color, Enum.Material.Slate)
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

	-- Service risers left hanging on the outside, which is what a building
	-- with its frame showing would have. They stop short of the shear, so
	-- they read as cut off rather than as decoration.
	for _, side in { 1, -1 } do
		conduit(
			parent,
			base + Vector3.new(side * width * 0.36, 0, depth * 0.5 + 0.8),
			height * rng:NextNumber(0.55, 0.9),
			rng
		)
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

	-- Tanks and ducting on top, and pipework down the back. On a world that
	-- is entirely other people's leftovers this is not decoration -- the
	-- plumbing being on the outside *is* the architecture.
	roofClutter(parent, base, y, width, depth, rng)
	for _ = 1, rng:NextInteger(1, 3) do
		conduit(
			parent,
			base + Vector3.new(rng:NextNumber(-width * 0.4, width * 0.4), 0, -depth * 0.5 - 0.8),
			y * rng:NextNumber(0.5, 0.95),
			rng
		)
	end
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
		--[[
			A ledge where each tier hands over to the next.

			The taper is only 0.93, which is deliberate -- 0.82 made a wedding
			cake -- but the cost of a gentle taper is that the joins vanish and
			a 180-stud tower becomes one smooth extrusion with no scale to it.
			The ledge puts the joins back without putting the wedding cake back.
		]]
		cornice(parent, base, y, width, depth, color, Enum.Material.Metal)
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

	--[[
		A porch and its railing.

		No plinth on this world -- the whole point of the stilts is that
		nothing touches the ground -- so the horizontal that gives the hut its
		scale has to be up at the floor line instead. A rail also reads as
		somebody living here, which no amount of corrugated wall does.
	]]
	local porch = depth * 0.3
	local deck = block(
		parent,
		CFrame.new(base + Vector3.new(0, stilt - 0.4, depth * 0.5 + porch * 0.5)),
		Vector3.new(width * 0.8, 0.8, porch),
		Palette.SmugglerBrown,
		Enum.Material.WoodPlanks
	)
	deck.Name = "Porch"
	deck.CanCollide = false

	for i = 0, 3 do
		local post = block(
			parent,
			CFrame.new(base + Vector3.new((i / 3 - 0.5) * width * 0.8, stilt + 2, depth * 0.5 + porch)),
			Vector3.new(0.7, 4.4, 0.7),
			Palette.SmugglerBrown,
			Enum.Material.WoodPlanks
		)
		post.Name = "Post"
		post.CanCollide = false
	end

	local rail = block(
		parent,
		CFrame.new(base + Vector3.new(0, stilt + 4, depth * 0.5 + porch)),
		Vector3.new(width * 0.82, 0.6, 0.6),
		Palette.SmugglerBrown,
		Enum.Material.WoodPlanks
	)
	rail.Name = "Rail"
	rail.CanCollide = false
end

--- Tython. Low stone halls behind a colonnade. Nothing here is in a hurry.
local function jediStoneShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local width, depth = footprint.X, footprint.Y
	local height = rng:NextInteger(style.minFloors, style.maxFloors) * style.floorHeight

	--[[
		A stepped stylobate the colonnade stands on.

		Two courses rather than one, because a temple you walk *up* to is the
		oldest trick there is for making a low building look important, and
		this style is the one place in the game where the buildings are
		supposed to be older than everyone looking at them.
	]]
	for step = 1, 2 do
		local spread = 1.16 - (step - 1) * 0.07
		local course = block(
			parent,
			CFrame.new(base + Vector3.new(0, (step - 0.5) * 1.6, 0)),
			Vector3.new(width * spread, 1.6, depth * spread),
			shade(color, -0.1),
			Enum.Material.Limestone
		)
		course.Name = "Stylobate"
		course.CanCollide = false
	end

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

	--[[
		Crates and a fuel drum stacked by the mouth.

		The only detail this style can carry. Everything else is buried, so
		there is no wall to trim and no roof to clutter -- but a supply dump
		outside the door is what makes a smooth white dome read as somewhere
		people are living rather than as a shape in the snow.
	]]
	for i = 1, rng:NextInteger(3, 5) do
		local size = rng:NextNumber(3, 5.5)
		local bearing = mouthAngle + rng:NextNumber(-0.9, 0.9)
		local at = base
			+ Vector3.new(math.cos(bearing), 0, math.sin(bearing)) * (span * 0.45 + rng:NextNumber(9, 18))
			+ Vector3.new(0, size * 0.5, 0)

		local crate = if i % 3 == 0
			then cylinder(
				parent,
				CFrame.new(at) * UPRIGHT,
				Vector3.new(size, size * 0.8, size * 0.8),
				Palette.DroidRust,
				Enum.Material.CorrodedMetal
			)
			else block(
				parent,
				CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Vector3.new(size, size, size * rng:NextNumber(0.8, 1.2)),
				Palette.WornSteel,
				Enum.Material.DiamondPlate
			)
		crate.Name = "Supplies"
	end
end

--- Dromund Kaas. Tall, black, buttressed and pointed. Deliberately unfriendly.
local function gothicShape(parent: Instance, base: Vector3, footprint: Vector2, style: Style, rng: Random)
	local color = pick(style.buildingColors, rng)
	local width, depth = footprint.X * 0.7, footprint.Y * 0.7
	local floors = rng:NextInteger(style.minFloors, style.maxFloors)
	local height = floors * style.floorHeight

	plinth(parent, base, width, depth, color, Enum.Material.Slate)

	block(
		parent,
		CFrame.new(base + Vector3.new(0, height * 0.5, 0)),
		Vector3.new(width, height, depth),
		color,
		Enum.Material.Slate
	).Name =
		"Tower"

	--[[
		Two string courses banding the tower, and a lip under the crown.

		This style's problem is that it is *tall* -- a black box eight floors
		high with nothing crossing it has no scale at all, and the buttresses
		only make the verticals stronger. The horizontals have to come from
		somewhere, and a banded tower is the correct answer for the look
		anyway.
	]]
	for i = 1, 2 do
		cornice(parent, base, height * (i * 0.31), width, depth, color, Enum.Material.Slate)
	end
	cornice(parent, base, height, width, depth, color, Enum.Material.Slate)

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
		wallMaterial = Enum.Material.Sandstone,
		scatter = "None",
		shape = adobeShape,
	},
	SithZiggurat = {
		buildingColors = { Palette.SithBlack, Palette.MustafarBasalt, Palette.DarkMetal },
		minFloors = 2,
		maxFloors = 4,
		floorHeight = 13,
		windowColor = Palette.SaberRed,
		wallMaterial = Enum.Material.Slate,
		scatter = "None",
		shape = zigguratShape,
	},
	Ruin = {
		buildingColors = { Palette.WornSteel, Palette.Gunmetal, Palette.NabooStone, Palette.CoruscantPlate },
		minFloors = 4,
		maxFloors = 11,
		floorHeight = 15,
		windowColor = Palette.DroidGold,
		wallMaterial = Enum.Material.Concrete,
		scatter = "None",
		shape = ruinShape,
	},
	NeonStack = {
		buildingColors = { Palette.DarkMetal, Palette.Gunmetal, Palette.ImperialGrey, Palette.SmugglerBrown },
		minFloors = 3,
		maxFloors = 8,
		floorHeight = 13,
		windowColor = Palette.TwilekRed,
		wallMaterial = Enum.Material.DiamondPlate,
		scatter = "None",
		shape = neonStackShape,
	},
	Spire = {
		buildingColors = { Palette.CoruscantPlate, Palette.HullGrey, Palette.WornSteel, Palette.NabooStone },
		minFloors = 6,
		maxFloors = 14,
		floorHeight = 16,
		windowColor = Palette.CoruscantLight,
		wallMaterial = Enum.Material.Metal,
		scatter = "None",
		shape = spireShape,
	},
	Frontier = {
		buildingColors = { Palette.RebelTan, Palette.SmugglerBrown, Palette.DroidRust, Palette.RebelOlive },
		minFloors = 1,
		maxFloors = 2,
		floorHeight = 12,
		windowColor = Palette.DroidGold,
		wallMaterial = Enum.Material.CorrodedMetal,
		scatter = "None",
		shape = frontierShape,
	},
	JediStone = {
		buildingColors = { Palette.NabooStone, Palette.JediCream, Palette.SandtrooperTan },
		minFloors = 1,
		maxFloors = 3,
		floorHeight = 13,
		windowColor = Palette.SaberYellow,
		wallMaterial = Enum.Material.Limestone,
		scatter = "None",
		shape = jediStoneShape,
	},
	IceBunker = {
		buildingColors = { Palette.HothIce, Palette.StormtrooperShadow, Palette.WornSteel },
		minFloors = 1,
		maxFloors = 2,
		floorHeight = 12,
		windowColor = Palette.BlasterBlue,
		wallMaterial = Enum.Material.Metal,
		scatter = "None",
		shape = iceBunkerShape,
	},
	ImperialGothic = {
		buildingColors = { Palette.ImperialBlack, Palette.DarkMetal, Palette.ImperialGrey },
		minFloors = 4,
		maxFloors = 9,
		floorHeight = 15,
		windowColor = Palette.SaberRed,
		wallMaterial = Enum.Material.Slate,
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

--[[
	Raises a mound out of the terrain plate.

	The trick that makes terrain worth using at all: a ball whose centre sits
	*below* the surface only shows its cap, and where two caps overlap the
	voxels merge into one continuous slope with no seam and no decision about
	which one is on top. Fourteen of them in a ring stop being fourteen hills
	and become a range, which is precisely what fourteen part-spheres never
	managed however carefully they were placed.
]]
local function mound(centre: Vector3, width: number, height: number, material: Enum.Material)
	-- Sunk by its own radius less the height wanted above ground.
	local radius = width * 0.5
	Terrain:FillBall(centre + Vector3.new(0, height - radius, 0), radius, material)
end

--[[
	How far out this world's land is dead level. Nothing shapes the ground
	inside it; all the relief is beyond it.

	It is derived rather than a constant because the play area is not the same
	size on every world. `buildMarkers` puts a district centre at
	`ZoneDef.distance * SETTLEMENT_RADIUS`, and those go from Tatooine's Dune
	Sea at 1.6 to Korriban's Wastes at 2.6 -- 1,352 studs, more than twice the
	settlement. A fixed 900 would have left four worlds with their outer
	districts standing in the hills.

	And that is a real break, not a cosmetic one. A landmark is placed at the
	origin's own Y, so a district on a swell is a building with its ground
	floor inside the hill. Worse, `NPCService.pointOn` casts down from twelve
	studs above the zone marker to find the floor, and **a ray that begins
	inside terrain reports no hit at all** -- so it falls back to the height
	the marker claimed and the district's whole population spawns underground.
	Parts never did this, because a part the ray starts inside is a part it
	still hits on the way out.

	The margin covers the landmark's own footprint and the ring of people laid
	out around it, both of which stand outside the centre it was given.
]]
local function flatRadiusFor(planet: Planets.PlanetDef): number
	local furthest = 0
	for _, zone in planet.zones do
		furthest = math.max(furthest, zone.distance)
	end
	return math.max(900, furthest * SETTLEMENT_RADIUS + 220)
end

--[[
	The horizon: a ring of hills, mesas or ridges, in terrain.

	Ringed rather than scattered because it is scenery for a settlement in the
	middle, and because a mountain in the middle distance is the cheapest thing
	there is for making a flat world look like it has somewhere else in it.
]]
local function buildRelief(
	planet: Planets.PlanetDef,
	origin: Vector3,
	flat: number,
	ground: Enum.Material,
	rng: Random
)
	local kind = RELIEF[planet.terrain]
	if not kind then
		return
	end

	--[[
		Rock, not the ground material, so the hills read as a different
		substance from the plain -- and specifically a material no *other*
		planet has claimed, because `SetMaterialColor` is global. Rock and
		Glacier are the two nobody walks on, so they are free to be recoloured
		by whichever world was entered last: at 1,200 studs, through fog, the
		hue is carrying almost nothing and the silhouette is carrying all of
		it.
	]]
	local material = if planet.terrain == "Ice" then Enum.Material.Glacier else Enum.Material.Rock
	Terrain:SetMaterialColor(material, planet.rockColor or planet.groundColor)

	local count = rng:NextInteger(14, 18)
	for i = 1, count do
		-- Evenly spaced with jitter, so the ring is a range of hills rather
		-- than a fence with regular posts.
		local angle = (i - 1) * (math.pi * 2 / count) + rng:NextNumber(-0.14, 0.14)
		-- Straddling the edge of the plate, so the seam where the land stops
		-- is inside a hill instead of a visible cliff onto nothing.
		local distance = rng:NextNumber(flat + RELIEF_MARGIN * 0.75, flat + RELIEF_MARGIN * 1.2)
		local base = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local width = rng:NextNumber(220, 400)

		if kind == "Hill" then
			mound(base, width, width * rng:NextNumber(0.30, 0.48), material)
			continue
		end

		if kind == "Mesa" then
			--[[
				A mesa is a cliff with a flat top, so it is the one landform
				that wants the hard edge a box gives -- and terrain softens
				it just enough to stop it reading as a crate. A skirt of
				mounds around the base hides the corners where they meet the
				plain, which is the only part that ever looked wrong.
			]]
			local height = width * rng:NextNumber(0.34, 0.52)
			local depth = width * rng:NextNumber(0.6, 1.1)
			Terrain:FillBlock(
				CFrame.new(base + Vector3.new(0, height * 0.5 - 30, 0))
					* CFrame.Angles(0, angle + rng:NextNumber(-0.3, 0.3), 0),
				Vector3.new(width, height + 60, depth),
				material
			)
			for _ = 1, 5 do
				local a = rng:NextNumber(0, math.pi * 2)
				local r = width * rng:NextNumber(0.45, 0.62)
				mound(
					base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r),
					width * rng:NextNumber(0.4, 0.7),
					height * rng:NextNumber(0.2, 0.45),
					material
				)
			end
			continue
		end

		--[[
			A ridge is a line of overlapping mounds rather than one long one,
			so it has a crest that rises and falls. Laid across the radius --
			tangential to the ring -- because a ridge pointing at the town
			reads as a wall and a ridge lying along the horizon reads as
			distance.
		]]
		local along = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local steps = rng:NextInteger(4, 6)
		for s = 1, steps do
			local t = (s - (steps + 1) * 0.5) / steps
			mound(
				base + along * (t * width * 1.7),
				width * rng:NextNumber(0.55, 0.85),
				-- Tallest in the middle, so the ridge has a summit.
				width
					* rng:NextNumber(0.34, 0.58)
					* (1 - math.abs(t) * 0.9),
				material
			)
		end
	end

	-- Rolling ground between the flat pad and the hills, so the plain does not
	-- read as a table with scenery standing on it.
	local swells = rng:NextInteger(26, 34)
	for _ = 1, swells do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(flat + 60, flat + RELIEF_MARGIN * 0.75)
		mound(
			origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d),
			rng:NextNumber(180, 340),
			rng:NextNumber(10, 34),
			ground
		)
	end
end

--[[
	Lays the planet's land down as terrain.

	One `FillCylinder` for the whole disc, with its top face exactly at the
	origin's Y so the settlement, the roads and every marker keep the height
	they already assumed. Terrain voxels are four studs and world-aligned, and
	planet origins are multiples of 12,000, so that top face lands on a voxel
	boundary rather than half inside one.

	The colour is `SetMaterialColor`, which is a property of the single shared
	`Workspace.Terrain` -- see `PlanetDef.terrainMaterial` for why every walkable
	world therefore has to own a different material, and why `Planets.validate`
	refuses it rather than trusting it.
]]
local function buildGround(planet: Planets.PlanetDef, origin: Vector3, flat: number): Enum.Material
	local material = planet.terrainMaterial or Enum.Material.Ground
	Terrain:SetMaterialColor(material, planet.groundColor)

	-- No UPRIGHT here. `Terrain:FillCylinder` runs its axis along the CFrame's
	-- *up* vector; only Part cylinders lie along X. Turning this one a quarter
	-- turn would lay the whole planet on its side.
	Terrain:FillCylinder(
		CFrame.new(origin - Vector3.new(0, TERRAIN_DEPTH * 0.5, 0)),
		TERRAIN_DEPTH,
		flat + RELIEF_MARGIN,
		material
	)
	return material
end

--[[
	Scatters landscape features outside the settlement.

	Kept out of the town radius deliberately: a boulder in the middle of a
	street is the single clearest tell that a world was generated rather than
	designed.

	**Dunes and drifts are terrain; trees and boulders stay parts.** The split
	is the point: a dune is *the ground doing something*, so as a part it was
	always an ellipsoid intersecting a plate at a visible seam, and as terrain
	it merges into the surface and you cannot find where it starts. A boulder
	or a tree is an object standing *on* the ground, and a hard edge against
	the land is what it is supposed to have.

	Which is also why the two get different distances. Parts may stand
	anywhere from the edge of town outwards, exactly as before. Terrain may
	not touch the flat pad at all -- see `flatRadiusFor` for what a dune under
	a district does to the people who live in it.
]]
local function buildScatter(
	parent: Instance,
	planet: Planets.PlanetDef,
	origin: Vector3,
	flat: number,
	ground: Enum.Material,
	style: Style,
	rng: Random
)
	if style.scatter == "None" then
		return
	end

	local scatter = folder("Scatter", parent)
	local rockColor = planet.rockColor or planet.groundColor
	local shapesGround = style.scatter == "Dunes" or style.scatter == "Drifts"

	for _ = 1, 140 do
		local angle = rng:NextNumber(0, math.pi * 2)
		-- Either way, kept inside the edge of the plate: a tree standing past
		-- where the land stops is a tree standing on nothing.
		local distance = if shapesGround
			then rng:NextNumber(flat + 40, flat + RELIEF_MARGIN * 0.8)
			else rng:NextNumber(SETTLEMENT_RADIUS + 90, flat + RELIEF_MARGIN * 0.8)
		local position = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

		if shapesGround then
			-- Smaller and denser than the swells they lie among, so the two
			-- passes read as one surface at two scales rather than as a ring.
			local width = rng:NextNumber(60, 190)
			mound(position, width, width * rng:NextNumber(0.10, 0.20), ground)
			continue
		end

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
			-- A boulder: an ellipsoid sitting mostly proud of the ground.
			local width = rng:NextNumber(30, 110)
			local height = width * rng:NextNumber(0.5, 1.1)

			local boulder = Instance.new("Part")
			boulder.Anchored = true
			boulder.Shape = Enum.PartType.Ball
			boulder.Size = Vector3.new(width, height, width * rng:NextNumber(0.7, 1.4))
			boulder.CFrame = CFrame.new(position + Vector3.new(0, height * 0.15, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
			boulder.Color = rockColor
			boulder.Material = Enum.Material.Rock
			boulder.Parent = scatter
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
-- Interiors
--------------------------------------------------------------------------------

--[[
	Somewhere to go in.

	Every landmark was a solid exterior. You walked up to the cantina, found a
	painted-on doorway, and walked around the outside of it -- which is most
	of why a town read as scenery rather than as a place.

	Interiors are built *in place*: the room is inside the building's own
	footprint, on the same ground, at the same coordinates. The alternative --
	a separate space you teleport into -- would need its own instance
	machinery, and would silently break everything that assumes an NPC and a
	player who can see each other are in the same world: pathfinding,
	waypoints, line of sight, and the proximity prompts vendors and dialogue
	run on. Built in place, none of those has to learn that interiors exist.

	The rule that keeps it cheap: **a building with an interior is built as a
	shell from the start.** Nothing is hollowed out afterwards, so there is
	never a solid version and a hollow version of the same wall to keep in
	step.

	This section sits above both of its customers -- the authored layouts and
	the landmarks -- because it is machinery, not content. A landmark decides
	what a cantina is; a prefab decides what a shop is; neither owns the wall.
]]

local WALL_THICKNESS = 3
-- The camera sits behind and above the character, so a room at head height
-- is a room you play from inside the ceiling. 22 studs is the shortest that
-- stays comfortable.
local ROOM_HEIGHT = 22
-- Floors sit slightly proud of the ground for the same reason roads do: two
-- coplanar surfaces z-fight. See the ROAD_LIFT notes.
local FLOOR_Y = 0.5

--[[
	FURNITURE IS NOT SLABS

	The first pass built a bunk as one flat box and a table as another, which
	from inside the room read as black rectangles floating against the wall --
	not furniture, just parts. Anything an eye is meant to name needs the bit
	that holds it up: legs under a table, posts under a bunk, a stem above a
	lamp. Three or four parts each, and the room stops being a box with
	rubbish in it.
]]

--- A ceiling lamp: stem, shade, and a bulb under the shade rather than a
--- glowing ball hanging in mid-air, which reads as a small indoor sun.
local function ceilingLamp(parent: Instance, position: Vector3, color: Color3, range: number)
	cylinder(
		parent,
		CFrame.new(position + Vector3.new(0, 3, 0)) * UPRIGHT,
		Vector3.new(6, 1, 1),
		Palette.DarkMetal,
		Enum.Material.Metal
	).Name =
		"LampStem"
	cylinder(
		parent,
		CFrame.new(position) * UPRIGHT,
		Vector3.new(1.5, 9, 9),
		Palette.DarkMetal,
		Enum.Material.Metal
	).Name =
		"LampShade"

	local bulb = ball(
		parent,
		CFrame.new(position - Vector3.new(0, 1.5, 0)),
		Vector3.new(3, 3, 3),
		color,
		Enum.Material.Neon
	)
	bulb.Name = "Lamp"
	bulb.CanCollide = false

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 2.2
	light.Parent = bulb
end

--- A table: top, and the legs that stop it being a slab in mid-air.
local function table_(parent: Instance, base: Vector3, size: Vector3, color: Color3, material: Enum.Material)
	local height = size.Y
	block(
		parent,
		CFrame.new(base + Vector3.new(0, height, 0)),
		Vector3.new(size.X, 1.5, size.Z),
		color,
		material
	).Name =
		"Table"
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			block(
				parent,
				CFrame.new(
					base + Vector3.new(x * (size.X * 0.5 - 1.5), height * 0.5, z * (size.Z * 0.5 - 1.5))
				),
				Vector3.new(1.5, height, 1.5),
				Palette.DarkMetal,
				Enum.Material.Metal
			).Name =
				"Leg"
		end
	end
end

--- A double bunk: corner posts the whole height, two frames, and bedding, so
--- it reads as somewhere a soldier sleeps rather than as two black shelves.
local function bunk(parent: Instance, base: Vector3, blanket: Color3)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			block(
				parent,
				CFrame.new(base + Vector3.new(x * 8.4, 8, z * 4.4)),
				Vector3.new(1.4, 16, 1.4),
				Palette.WornSteel,
				Enum.Material.Metal
			).Name =
				"BunkPost"
		end
	end

	for _, y in { 4, 11 } do
		block(
			parent,
			CFrame.new(base + Vector3.new(0, y, 0)),
			Vector3.new(18, 1, 10),
			Palette.WornSteel,
			Enum.Material.Metal
		).Name =
			"BunkFrame"
		block(
			parent,
			CFrame.new(base + Vector3.new(0, y + 1.4, 0)),
			Vector3.new(17, 1.8, 9),
			Palette.HullWhite,
			Enum.Material.Fabric
		).Name =
			"Mattress"
		block(
			parent,
			CFrame.new(base + Vector3.new(-3, y + 1.8, 0)),
			Vector3.new(10, 1.6, 9.4),
			blanket,
			Enum.Material.Fabric
		).Name =
			"Blanket"
		block(
			parent,
			CFrame.new(base + Vector3.new(7, y + 2, 0)),
			Vector3.new(3.5, 1.6, 6),
			Palette.HullWhite,
			Enum.Material.Fabric
		).Name =
			"Pillow"
	end
end

--- A footlocker: a box with a lid, which is the difference between a chest
--- and a cube.
local function footlocker(parent: Instance, base: Vector3)
	block(
		parent,
		CFrame.new(base + Vector3.new(0, 2.5, 0)),
		Vector3.new(6, 5, 8),
		Palette.DarkMetal,
		Enum.Material.DiamondPlate
	).Name =
		"Footlocker"
	block(
		parent,
		CFrame.new(base + Vector3.new(0, 5.5, 0)),
		Vector3.new(6.6, 1.2, 8.6),
		Palette.WornSteel,
		Enum.Material.Metal
	).Name =
		"Lid"
end

--[[
	A round wall, built from straight segments, with one segment left out for
	the door.

	Leaving out a segment rather than working out which ones fall inside a
	doorway of a given width means the opening is however wide one chord is,
	and the caller does not get to choose -- but it also means there is no
	arithmetic that can round the wrong way and seal the building. At 16
	segments the gap comes out near 14 studs on a cantina, which is a double
	door. The missing segment is always index 0, so a caller aims the doorway
	by deciding which way is +X.
]]
local function roundWall(
	parent: Instance,
	base: Vector3,
	radius: number,
	height: number,
	color: Color3,
	material: Enum.Material
)
	local segments = 16
	-- Chord of one segment, widened so neighbours overlap at the corners
	-- instead of leaving a slot you can see daylight through.
	local width = 2 * radius * math.sin(math.pi / segments) * 1.2

	for i = 1, segments - 1 do
		local angle = (i / segments) * math.pi * 2
		local at = base + Vector3.new(math.cos(angle) * radius, height * 0.5, math.sin(angle) * radius)
		block(
			parent,
			CFrame.new(at) * CFrame.Angles(0, -angle, 0),
			Vector3.new(WALL_THICKNESS, height, width),
			color,
			material
		).Name =
			"Wall"
	end
end

--[[
	A rectangular room shell: floor, ceiling, and four walls with a doorway
	in the middle of the +X side.

	`size` is the outside footprint, so a caller can drop a shell where a
	solid block used to stand and have the building keep the silhouette it
	had.

	`base` is a CFrame rather than a position because the doorway is always
	local +X and a room in a street grid has to open onto the street. Turning
	the whole shell is the only way to move a door that stays put relative to
	the fittings inside it -- a door parameter would leave the counter facing
	a wall.
]]
local function roomShell(
	parent: Instance,
	base: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material
)
	local halfX, halfZ = size.X * 0.5, size.Z * 0.5
	local height = size.Y

	block(
		parent,
		base * CFrame.new(0, FLOOR_Y, 0),
		Vector3.new(size.X, 1, size.Z),
		color:Lerp(Color3.new(0, 0, 0), 0.35),
		Enum.Material.Slate
	).Name =
		"Floor"
	block(
		parent,
		base * CFrame.new(0, height, 0),
		Vector3.new(size.X, WALL_THICKNESS, size.Z),
		color,
		material
	).Name =
		"Ceiling"

	for _, side in
		{
			{ at = Vector3.new(-halfX, height * 0.5, 0), size = Vector3.new(WALL_THICKNESS, height, size.Z) },
			{ at = Vector3.new(0, height * 0.5, -halfZ), size = Vector3.new(size.X, height, WALL_THICKNESS) },
			{ at = Vector3.new(0, height * 0.5, halfZ), size = Vector3.new(size.X, height, WALL_THICKNESS) },
		}
	do
		block(parent, base * CFrame.new(side.at), side.size, color, material).Name = "Wall"
	end

	-- The entrance wall: two jambs and a lintel. Splitting it here rather
	-- than punching a hole afterwards is the shell rule in miniature.
	local jamb = (size.Z - 16) * 0.5
	for _, sign in { -1, 1 } do
		block(
			parent,
			base * CFrame.new(halfX, height * 0.5, sign * (16 + jamb) * 0.5),
			Vector3.new(WALL_THICKNESS, height, jamb),
			color,
			material
		).Name =
			"Jamb"
	end
	block(
		parent,
		base * CFrame.new(halfX, height - 3, 0),
		Vector3.new(WALL_THICKNESS, 8, 16),
		color,
		material
	).Name =
		"Lintel"
end

--------------------------------------------------------------------------------
-- Authored layouts
--------------------------------------------------------------------------------

--[[
	What one glyph of an authored grid puts on the ground.

	Deliberately thin. A prefab is a footprint and a storey count handed to the
	planet's own `style.shape` -- so an authored town on Tatooine is still
	built out of Adobe, and the same grid dropped on Hoth would come up as
	IceBunker. A prefab table that drew its own houses would be a tenth
	architecture quietly ignoring the nine, and the boys would spot it in ten
	minutes the way they spotted five styles across nine worlds.

	`build` is the exception, for the handful of things no architecture has:
	a rampart, a gate, a lamp post.
]]
type PrefabDef = {
	-- Fraction of the cell rectangle the building fills. Nil builds nothing.
	fill: number?,
	--[[
		Storeys, as a multiplier on the style's own range rather than a count.

		Adobe is 1-2 floors and Spire is 6-14, so an absolute "a tower is five
		storeys" would be a tower on Tatooine and a bungalow on Coruscant. A
		multiplier means tall *for this world*, which is what the author meant.
	]]
	floorScale: number?,
	-- Paving over the whole rectangle, at road height.
	paved: boolean?,
	--[[
		Somewhere a landmark or a player spawn may be put.

		Roads are walkable and deliberately are not offered. `claimNear` gives
		a landmark the nearest free anchor, and a spaceport dropped in the
		middle of the high street is worse than one in a yard behind it.
	]]
	anchor: boolean?,
	build: ((Instance, Vector3, Vector2, Style) -> ())?,
	--[[
		The fittings of a building you can walk into.

		Setting this builds the footprint as a `roomShell` turned to face the
		street, and then calls this to put things in it. Which prefabs get one
		is a judgement rather than a default: a house you can enter and find
		empty is a worse discovery than a house you cannot enter, and forty
		houses is forty times the parts to make that discovery in.

		It returns where the floor is left clear, in the room's own frame,
		because the thing that placed the counter is the only thing that knows
		what is still free. That spot becomes the district's standing room
		indoors -- the same `Inside` marker a cantina gets -- so the answer
		cannot be a constant: a shop's clear floor is in front of its counter
		and a hall's is past the end of its table.
	]]
	room: ((Instance, CFrame, Vector2, Style) -> Vector3)?,
}

--- A stretch of town wall, crenellated along whichever way it runs.
local function buildRampart(parent: Instance, centre: Vector3, span: Vector2, style: Style)
	local color = style.buildingColors[1]
	local height = style.floorHeight * 1.5
	local thickness = math.min(span.X, span.Y) * 0.55

	local alongX = span.X >= span.Y
	local body = if alongX
		then Vector3.new(span.X, height, thickness)
		else Vector3.new(thickness, height, span.Y)
	block(parent, CFrame.new(centre + Vector3.new(0, height * 0.5, 0)), body, color, Enum.Material.Brick).Name =
		"Rampart"

	local run = if alongX then span.X else span.Y
	local step = 14
	for i = 0, math.max(0, math.floor(run / step) - 1) do
		local at = -run * 0.5 + step * (i + 0.5)
		local offset = if alongX then Vector3.new(at, height + 2, 0) else Vector3.new(0, height + 2, at)
		local size = if alongX
			then Vector3.new(step * 0.55, 4, thickness)
			else Vector3.new(thickness, 4, step * 0.55)
		block(parent, CFrame.new(centre + offset), size, color, Enum.Material.Brick).Name = "Merlon"
	end
end

--- The break in a wall: a pier each side and a lintel over, walkable between.
local function buildGate(parent: Instance, centre: Vector3, span: Vector2, style: Style)
	local color = style.buildingColors[1]
	local height = style.floorHeight * 1.5
	local alongX = span.X >= span.Y
	local run = if alongX then span.X else span.Y
	local thickness = math.min(span.X, span.Y) * 0.55
	local pier = 12

	for _, side in { -1, 1 } do
		local at = side * (run * 0.5 - pier * 0.5)
		local offset = if alongX
			then Vector3.new(at, (height + 8) * 0.5, 0)
			else Vector3.new(0, (height + 8) * 0.5, at)
		local size = if alongX
			then Vector3.new(pier, height + 8, thickness)
			else Vector3.new(thickness, height + 8, pier)
		block(parent, CFrame.new(centre + offset), size, color, Enum.Material.Brick).Name = "Pier"
	end

	-- Above head height on purpose: the gateway has to be walked and pathed
	-- through, and a lintel a character catches on is a wall with a picture
	-- of a door on it.
	local lintel = if alongX then Vector3.new(run, 7, thickness) else Vector3.new(thickness, 7, run)
	block(parent, CFrame.new(centre + Vector3.new(0, height + 11, 0)), lintel, color, Enum.Material.Brick).Name =
		"Lintel"
end

local function buildLampCell(parent: Instance, centre: Vector3, _span: Vector2, style: Style)
	buildStreetLamp(parent, centre, style.windowColor)
end

--[[
	FITTINGS ARE WRITTEN IN THE ROOM'S OWN FRAME

	`at` is the room's centre turned so that local +X is the door, and `inner`
	is the floor measured the same way -- X from the back wall to the door, Y
	across. Everything below multiplies through `at` rather than adding to a
	position, because half these rooms are turned a quarter circle and a
	counter placed in world space would end up through a side wall.
]]

--- A shop: a counter to stand behind, a stocked shelf, and light to see by.
local function fitShop(parent: Instance, at: CFrame, inner: Vector2, style: Style): Vector3
	local run = inner.Y * 0.62
	--[[
		Measured out from the inside of the back wall rather than as fractions
		of the room.

		A shop rectangle is anything from one cell to nine, and the same
		fraction that is a comfortable gap in the big one stands the shelf
		inside the counter in the small one. The furniture does not want to
		scale; only the room does.
	]]
	local back = -inner.X * 0.5 + WALL_THICKNESS * 0.5

	block(
		parent,
		at * CFrame.new(back + 1.5, 9, 0),
		Vector3.new(2.5, 18, run + 6),
		Palette.WornSteel,
		Enum.Material.Metal
	).Name =
		"Shelf"
	-- An empty shelf is a wall with a ledge on it. Sitting *on* the shelf
	-- face rather than in front of it: the smallest shop here is 25 studs
	-- deep and three of those are the walk behind the counter.
	for column = -1, 1 do
		for _, y in { 6, 13 } do
			local goods = block(
				parent,
				at * CFrame.new(back + 2.5, y, column * run * 0.3),
				Vector3.new(2, 3.5, 5),
				style.windowColor,
				Enum.Material.Neon
			)
			goods.Name = "Goods"
			goods.CanCollide = false
		end
	end

	-- Far enough off the shelf to leave a shopkeeper room to stand between
	-- the two. Overhang and stock behind are the details that say "someone
	-- sells things here" rather than "there is a box in this room".
	local counter = back + 11
	block(
		parent,
		at * CFrame.new(counter, 5, 0),
		Vector3.new(5, 10, run),
		Palette.SmugglerBrown,
		Enum.Material.WoodPlanks
	).Name =
		"Counter"
	block(
		parent,
		at * CFrame.new(counter + 1.5, 10.4, 0),
		Vector3.new(8, 1.4, run + 2),
		Palette.DarkMetal,
		Enum.Material.Wood
	).Name =
		"CounterTop"

	-- In the corners by the door, where a delivery would have been dropped.
	-- Skipped in a narrow shop: `roomShell`'s doorway is 16 studs and the
	-- corners are the only place these fit, so in a one-cell frontage the
	-- crates would be standing in the door.
	if inner.Y >= 40 then
		for _, side in { -1, 1 } do
			block(
				parent,
				at * CFrame.new(inner.X * 0.5 - 8, 3, side * (inner.Y * 0.5 - 7)),
				Vector3.new(7, 6, 7),
				Palette.DroidRust,
				Enum.Material.CorrodedMetal
			).Name =
				"Crate"
		end
	end

	ceilingLamp(parent, (at * CFrame.new(0, ROOM_HEIGHT - 3, 0)).Position, style.windowColor, 42)

	--[[
		The customer's side of the counter, not the shopkeeper's.

		Behind it is a six-stud walkway between shelf and counter, and a
		standing spot that narrow is one an NPC gets shoved out of by the
		first thing that touches it. In front there is the width of the room,
		the trader is still within the twelve studs a `Trade` prompt reaches,
		and he is facing the door -- which is where a player comes in.
	]]
	return Vector3.new((counter + 2.5 + inner.X * 0.5) * 0.5, 0, 0)
end

--- A hall: one long table and benches down the middle, which is the
--- difference between somewhere people are called to and a shed.
local function fitHall(parent: Instance, at: CFrame, inner: Vector2, style: Style): Vector3
	local length = inner.X * 0.55
	local width = math.min(13, inner.Y * 0.3)

	block(
		parent,
		at * CFrame.new(0, 9, 0),
		Vector3.new(length, 1.6, width),
		Palette.SmugglerBrown,
		Enum.Material.WoodPlanks
	).Name =
		"Table"
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			block(
				parent,
				at * CFrame.new(x * (length * 0.5 - 2), 4.5, z * (width * 0.5 - 2)),
				Vector3.new(2, 9, 2),
				Palette.DarkMetal,
				Enum.Material.Metal
			).Name =
				"Leg"
		end
	end

	for _, side in { -1, 1 } do
		local bench = width * 0.5 + 5
		block(
			parent,
			at * CFrame.new(0, 5, side * bench),
			Vector3.new(length, 1.4, 5),
			Palette.SmugglerBrown,
			Enum.Material.Wood
		).Name =
			"Bench"
		for _, x in { -1, 1 } do
			block(
				parent,
				at * CFrame.new(x * (length * 0.5 - 3), 2.5, side * bench),
				Vector3.new(1.6, 5, 4),
				Palette.DarkMetal,
				Enum.Material.Metal
			).Name =
				"BenchLeg"
		end
	end

	ceilingLamp(parent, (at * CFrame.new(-length * 0.4, ROOM_HEIGHT - 3, 0)).Position, style.windowColor, 40)
	ceilingLamp(parent, (at * CFrame.new(length * 0.4, ROOM_HEIGHT - 3, 0)).Position, style.windowColor, 40)

	-- The floor between the end of the table and the door, which is the only
	-- part of a hall not taken up by furniture -- and the part people stand
	-- in anyway, because it is where you are when you come through the door.
	return Vector3.new((length + inner.X) * 0.25, 0, 0)
end

local PREFABS: { [string]: PrefabDef } = {
	House = { fill = 0.72, floorScale = 0.8 },
	Hall = { fill = 0.88, room = fitHall },
	Shop = { fill = 0.78, room = fitShop },
	Tower = { fill = 0.55, floorScale = 1.8 },
	Wall = { build = buildRampart },
	Gate = { build = buildGate, paved = true },
	Road = { paved = true },
	Plaza = { paved = true, anchor = true },
	Yard = { anchor = true },
	Lamp = { anchor = true, build = buildLampCell },
}

--[[
	Whether `id` is something a layout legend is allowed to point at.

	`Planets.validate` takes this as an argument rather than requiring this
	module: PlanetBuilder is server-only and already requires Planets, so the
	dependency can only run one way.
]]
function PlanetBuilder.prefabExists(id: string): boolean
	return PREFABS[id] ~= nil
end

--- Whether `id` builds a room a player can walk into, and so needs somebody in
--- it. Injected into `Planets.validate` alongside `prefabExists`.
function PlanetBuilder.prefabHasRoom(id: string): boolean
	local prefab = PREFABS[id]
	return prefab ~= nil and prefab.room ~= nil
end

type LayoutRect = { glyph: string, from: Vector2, to: Vector2 }

--[[
	Standing room inside one authored building.

	`cell` is the middle of the rectangle it came out of, and it is carried
	all the way to `buildMarkers` because that is the only thing that can say
	which district a room belongs to -- a district is a rectangle of cells,
	and a room's world position would have to be turned back into one.
]]
type RoomSpot = { at: Vector3, cell: Vector2, size: number }

--[[
	The glyph at a cell, with everything off the page reading as open ground.

	Short rows read as open ground on their east end rather than shifting
	everything after them, and a cell just outside the grid is desert rather
	than a wall -- which is what lets the door search below walk off the edge
	without a bounds check at every step. `Planets.validate` reports the
	ragged row separately.
]]
local function glyphAt(layout: Planets.LayoutDef, column: number, row: number): string
	local line = layout.grid[row]
	if not line or column < 1 or column > #line then
		return " "
	end
	return line:sub(column, column)
end

--- Whether a cell is ground somebody could stand on: paving, a yard, or
--- nothing at all. Buildings and ramparts are not.
local function walkable(layout: Planets.LayoutDef, column: number, row: number): boolean
	local prefabId = layout.legend[glyphAt(layout, column, row)]
	local prefab = if prefabId then PREFABS[prefabId] else nil
	if not prefab then
		return true
	end
	return prefab.paved == true or prefab.anchor == true
end

--[[
	Which way a building's door should face: the side of its rectangle with
	the most open ground against it.

	Returned as a quarter turn about Y, and whether that turn swaps the
	footprint's axes. Ties go to +X, which is the way `roomShell` builds
	anyway, so the common case costs no rotation at all.

	Without this a door points wherever +X happens to point, which in a street
	grid is a three-in-four chance of opening into the neighbour's back wall.
	A door that does not open is worse than no door, because the player spends
	a minute finding that out.
]]
local FACINGS: { { dx: number, dz: number, yaw: number, turned: boolean } } = {
	{ dx = 1, dz = 0, yaw = 0, turned = false },
	{ dx = -1, dz = 0, yaw = math.pi, turned = false },
	{ dx = 0, dz = 1, yaw = -math.pi * 0.5, turned = true },
	{ dx = 0, dz = -1, yaw = math.pi * 0.5, turned = true },
}

local function doorFacing(layout: Planets.LayoutDef, rect: LayoutRect): (number, boolean)
	local bestYaw, bestTurned, bestScore = 0, false, -1

	for _, facing in FACINGS do
		local open, run = 0, 0
		if facing.dx ~= 0 then
			local column = if facing.dx > 0 then rect.to.X + 1 else rect.from.X - 1
			for row = rect.from.Y, rect.to.Y do
				run += 1
				open += if walkable(layout, column, row) then 1 else 0
			end
		else
			local row = if facing.dz > 0 then rect.to.Y + 1 else rect.from.Y - 1
			for column = rect.from.X, rect.to.X do
				run += 1
				open += if walkable(layout, column, row) then 1 else 0
			end
		end

		-- Scored per cell, so a long side does not win merely for being long.
		-- The door goes on the clearest side, not the widest one.
		local score = open / run
		if score > bestScore then
			bestYaw, bestTurned, bestScore = facing.yaw, facing.turned, score
		end
	end

	return bestYaw, bestTurned
end

--[[
	The nearest paving to a point inside an authored town, or nil if there is
	none near enough to be the same place.

	`ontoStreet` does this for the radial generator by rounding onto a block
	line, which is arithmetic that only holds because that generator draws its
	streets on those lines. An authored town's streets are wherever the author
	drew them, so this reads the grid instead: it walks outward in rings from
	the cell the point landed in and takes the first paved one.

	Without it every NPC patrol point inside Anchorhead's walls is snapped
	onto a street grid the town does not have, and the crowd stands in the
	houses.
]]
local LAYOUT_SNAP_CELLS = 5

local function ontoPaving(layout: Planets.LayoutDef, origin: Vector3, at: Vector3): Vector3?
	local columns, rows = Planets.layoutSize(layout)
	local column = math.round((at.X - origin.X) / layout.cell + (columns + 1) / 2)
	local row = math.round((at.Z - origin.Z) / layout.cell + (rows + 1) / 2)

	-- Outside the page entirely: wilderness districts are not snapped, they
	-- are already standing on open ground.
	if column < 1 or column > columns or row < 1 or row > rows then
		return nil
	end

	-- Nearest by real distance, not by the square it sits in: a cell four
	-- along and four down is further away than one five along, and taking
	-- the first square ring that hits would pick the diagonal.
	local best: Vector3? = nil
	local bestDistance = math.huge

	for dz = -LAYOUT_SNAP_CELLS, LAYOUT_SNAP_CELLS do
		for dx = -LAYOUT_SNAP_CELLS, LAYOUT_SNAP_CELLS do
			local c, r = column + dx, row + dz
			local prefabId = layout.legend[glyphAt(layout, c, r)]
			local prefab = if prefabId then PREFABS[prefabId] else nil
			if not (prefab and prefab.paved) then
				continue
			end

			local cell = origin + Planets.cellOffset(layout, c, r)
			local distance = (Vector3.new(cell.X, 0, cell.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude
			if distance < bestDistance then
				best, bestDistance = cell, distance
			end
		end
	end

	return best
end

--[[
	Groups touching cells that share a glyph into single rectangles.

	`WWWW` is one wall, not four wall segments with three seams down them, and
	a two-by-two `HH` block is one house rather than four huts pressed
	together. The rule an author has to hold in their head is the simple one
	it looks like: cells that touch and match are one building, and the way to
	write two houses is to leave a gap between them.

	Greedy -- run right while the glyph holds, then down while the whole run
	holds. That does not find the largest rectangles an L-shaped block could
	be cut into; it finds the ones you would read off the page, which is the
	entire reason for writing the town as a page.
]]
local function layoutRects(layout: Planets.LayoutDef): { LayoutRect }
	local columns, rows = Planets.layoutSize(layout)

	local taken: { { boolean } } = {}
	for row = 1, rows do
		taken[row] = table.create(columns, false)
	end

	local rects: { LayoutRect } = {}
	for row = 1, rows do
		for column = 1, columns do
			local glyph = glyphAt(layout, column, row)
			if glyph == " " or taken[row][column] then
				continue
			end

			local right = column
			while
				right < columns
				and glyphAt(layout, right + 1, row) == glyph
				and not taken[row][right + 1]
			do
				right += 1
			end

			local bottom = row
			while bottom < rows do
				local whole = true
				for c = column, right do
					if glyphAt(layout, c, bottom + 1) ~= glyph or taken[bottom + 1][c] then
						whole = false
						break
					end
				end
				if not whole then
					break
				end
				bottom += 1
			end

			for r = row, bottom do
				for c = column, right do
					taken[r][c] = true
				end
			end
			table.insert(
				rects,
				{ glyph = glyph, from = Vector2.new(column, row), to = Vector2.new(right, bottom) }
			)
		end
	end
	return rects
end

--[[
	A building with an inside: shell, street door, lit sign, and whatever the
	prefab puts in it.

	Deliberately not a tenth `shape` function. The nine build a silhouette out
	of solids and there is no way to hollow one without maintaining a second
	version of it; this builds the shell first -- the rule from the Interiors
	section -- and then borrows the same trim helpers the shapes use, so from
	the street it still reads as the same world.

	One storey, always. A room is only worth building where a player can walk
	into it, and stairs are a system this does not have; a second floor would
	be a ceiling with nothing above it. That is why the prefabs with a `room`
	have no `floorScale`.

	Returns the standing room inside it, as a position and the side of a
	square. Square because `marker` builds axis-aligned parts and most of
	these rooms are turned a quarter circle, so a rectangle would be laid
	across the walls it was measured to fit between.
]]
local function buildRoom(
	parent: Instance,
	layout: Planets.LayoutDef,
	rect: LayoutRect,
	centre: Vector3,
	footprint: Vector2,
	style: Style,
	rng: Random,
	fittings: (Instance, CFrame, Vector2, Style) -> Vector3
): (Vector3, number)
	local color = pick(style.buildingColors, rng)
	local yaw, turned = doorFacing(layout, rect)
	local at = CFrame.new(centre) * CFrame.Angles(0, yaw, 0)

	-- Local X runs from the back wall to the door, so a turned building has
	-- to swap the footprint's axes or the room comes out across itself.
	local inner = if turned then Vector2.new(footprint.Y, footprint.X) else footprint

	plinth(parent, centre, footprint.X, footprint.Y, color, style.wallMaterial)
	roomShell(parent, at, Vector3.new(inner.X, ROOM_HEIGHT, inner.Y), color, style.wallMaterial)
	cornice(parent, centre, ROOM_HEIGHT + 2.5, footprint.X, footprint.Y, color, style.wallMaterial)
	roofClutter(parent, centre, ROOM_HEIGHT + 3, footprint.X, footprint.Y, rng)

	-- A lit plate on the lintel. The one part that says "this one opens" from
	-- across the street, which is most of the value of building an inside.
	local sign = block(
		parent,
		at * CFrame.new(inner.X * 0.5 + 2, ROOM_HEIGHT - 5, 0),
		Vector3.new(1.5, 4.5, 15),
		style.windowColor,
		Enum.Material.Neon
	)
	sign.Name = "Sign"
	sign.CanCollide = false

	local glow = Instance.new("PointLight")
	glow.Color = style.windowColor
	glow.Range = 34
	glow.Brightness = 1.6
	glow.Parent = sign

	--[[
		The standing room is kept well inside the clear floor rather than
		filling it.

		NPCService scatters anywhere within one of these and then drops what
		it picks to whatever is underneath, so a box that reached the counter
		would put a trader standing on it -- the same mistake the cantina's
		interior marker was sized down to avoid. A quarter of the depth is
		short of the counter in the smallest shop here, which is the one the
		arithmetic has to survive.
	]]
	local clear = fittings(parent, at, inner, style)
	local room = math.clamp(math.min(inner.X * 0.25, inner.Y * 0.4), 4, 12)
	return (at * CFrame.new(clear)).Position, room
end

--[[
	Builds a town from its picture instead of from the seed.

	Same contract as `buildSettlement` -- returns the ground left open, and
	everything downstream (landmarks, patrol rings, spawn markers) cannot tell
	which of the two it was handed. That is the point of doing it this way
	round: the authored layout is a different *source* of anchors, not a
	different world-building pipeline, so the eight worlds without one keep
	working untouched.

	The second return is the insides of whatever it built rooms in, which is
	the one thing a generated settlement has no equivalent of.
]]
local function buildFromLayout(
	parent: Instance,
	planet: Planets.PlanetDef,
	layout: Planets.LayoutDef,
	origin: Vector3,
	style: Style,
	rng: Random
): ({ Vector3 }, { RoomSpot })
	local town = folder("Settlement", parent)
	local paving = folder("Streets", town)
	local roadColor, roadMaterial = roadLook(planet)

	local open: { Vector3 } = {}
	local rooms: { RoomSpot } = {}

	for _, rect in layoutRects(layout) do
		local prefabId = layout.legend[rect.glyph]
		local prefab = if prefabId then PREFABS[prefabId] else nil
		if not prefab then
			continue
		end

		local a = Planets.cellOffset(layout, rect.from.X, rect.from.Y)
		local b = Planets.cellOffset(layout, rect.to.X, rect.to.Y)
		local centre = origin + (a + b) * 0.5
		local span = Vector2.new(math.abs(b.X - a.X) + layout.cell, math.abs(b.Z - a.Z) + layout.cell)

		-- Rectangles never overlap, so one lift is enough and there is no
		-- z-fighting to separate the way the radial street grid has.
		if prefab.paved then
			block(
				paving,
				CFrame.new(centre + Vector3.new(0, ROAD_Y + ROAD_LIFT_NS, 0)),
				Vector3.new(span.X, ROAD_THICKNESS, span.Y),
				roadColor,
				roadMaterial
			).Name =
				"Paving"
		end

		-- Every cell of a large yard, not just its centre: a plaza that
		-- offers one anchor is a plaza six players queue up on.
		if prefab.anchor then
			for column = rect.from.X, rect.to.X do
				for row = rect.from.Y, rect.to.Y do
					table.insert(open, origin + Planets.cellOffset(layout, column, row))
				end
			end
		end

		local custom = prefab.build
		if custom then
			custom(town, centre, span, style)
			continue
		end

		local fill = prefab.fill
		if not fill then
			continue
		end

		-- Inset, so two rectangles that share an edge on the page still have
		-- an alley between them on the ground.
		local footprint = Vector2.new(math.max(8, span.X * fill), math.max(8, span.Y * fill))

		local fittings = prefab.room
		if fittings then
			local at, size = buildRoom(town, layout, rect, centre, footprint, style, rng, fittings)
			table.insert(rooms, {
				at = at,
				cell = Vector2.new(
					math.floor((rect.from.X + rect.to.X) * 0.5),
					math.floor((rect.from.Y + rect.to.Y) * 0.5)
				),
				size = size,
			})
			continue
		end

		local scale = prefab.floorScale
		local shaped = style
		if scale then
			shaped = table.clone(style)
			shaped.minFloors = math.max(1, math.round(style.minFloors * scale))
			shaped.maxFloors = math.max(shaped.minFloors, math.round(style.maxFloors * scale))
		end
		shaped.shape(town, centre, footprint, shaped, rng)
	end

	-- A layout that builds nothing walkable would otherwise hand back an
	-- empty anchor list and drop every spawn marker on the origin anyway.
	if #open == 0 then
		table.insert(open, origin)
	end
	return open, rooms
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

	--[[
		121 towers is by far the largest single view in the game, and until
		2026-08-16 every one of them was a square-section box on an exact
		240-stud grid with a flat top -- which is the most literally blocky
		thing here, and the thing the playtest note was most likely looking at.

		The fixes below are nearly free, which is the constraint that matters at
		this count: an off-square footprint costs *no* parts at all, and the
		setback and mast cost two.

		The grid itself is deliberately left exact. Jittering the centres is
		the obvious fourth fix and it is the one that cannot be had cheaply:
		the landing platforms cantilever 45 studs past the widest face, which
		at 240-stud spacing already brings a pad's outer edge to within nothing
		of its neighbour's wall. Moving a tower closer puts a pad *inside* the
		next tower -- and pads are the anchors this function returns, which
		become landmark positions and NPC spawn points. A jittered skyline is
		not worth a district spawning inside a wall.
	]]
	for gx = -5, 5 do
		for gz = -5, 5 do
			local centre = origin + Vector3.new(gx * TOWER_GRID, 0, gz * TOWER_GRID)
			local width = rng:NextNumber(70, 150)
			-- Not square, but never wider than `width` could already be, for
			-- the clearance reason above. A grid of square towers is a grid
			-- however it is lit: every one looks the same from every side.
			local depth = math.clamp(width * rng:NextNumber(0.55, 1.5), 60, 150)
			local top = rng:NextNumber(ceiling * 0.45, ceiling * 0.95)
			local height = top - TOWER_BASE_Y

			local tower = block(
				city,
				CFrame.new(centre + Vector3.new(0, TOWER_BASE_Y + height * 0.5, 0)),
				Vector3.new(width, height, depth),
				Palette.CoruscantPlate,
				Enum.Material.Metal
			)
			tower.Name = "Tower"

			-- A setback crown, and on some of them a mast. Between the two,
			-- no two towers end at the same shape -- and the skyline was one
			-- flat row of identical tops before them.
			local crown = rng:NextNumber(40, 110)
			block(
				city,
				CFrame.new(centre + Vector3.new(0, top + crown * 0.5, 0)),
				Vector3.new(width * rng:NextNumber(0.4, 0.75), crown, depth * rng:NextNumber(0.4, 0.75)),
				Palette.CoruscantPlate,
				Enum.Material.Metal
			).Name =
				"Crown"

			if rng:NextNumber() < 0.45 then
				local mast = cylinder(
					city,
					CFrame.new(centre + Vector3.new(0, top + crown + 35, 0)) * UPRIGHT,
					Vector3.new(70, 3, 3),
					Palette.WornSteel,
					Enum.Material.Metal
				)
				mast.Name = "Mast"
				mast.CanCollide = false
			end

			-- Window bands every few hundred studs rather than every floor:
			-- at this scale individual floors are invisible anyway, and the
			-- part count is not.
			local y = TOWER_BASE_Y + 60
			while y < top - 40 do
				local band = block(
					city,
					CFrame.new(centre + Vector3.new(0, y, 0)),
					Vector3.new(width * 1.01, 6, depth * 1.01),
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
					-- Measured off the wider axis, since the offset is then
					-- rotated to any bearing and a pad sized for the narrow
					-- side would end up inside the tower on the deep one.
					local offset = Vector3.new(math.max(width, depth) * 0.5 + 45, 0, 0)
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

--[[
	`interior`, when a landmark has one, is where inside it people stand --
	an offset from the building's own base. It becomes a part in the
	landmark's district zone, which NPCService reads as somewhere to spawn
	and as a stop on that district's patrol route, so a cantina has drinkers
	in it and the guards outside walk in and back out again.

	A room nobody is in is a room, not a place; furniture was the cheap half
	of the job.
]]
type LandmarkDef = { radius: number, build: Landmark, interior: Vector3? }

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

--[[
	Landing pads and the tower that talks them down.

	The three pads are tagged `Ships.PAD_TAG` as they are made. They were
	drawn from the beginning and were pure scenery until starships landed
	(ROADMAP 2c); tagging at build time means the answer to "where can I put
	a ship down" is the world itself rather than a second list of coordinates
	that has to be kept true as the generator changes.

	The tag goes on after the pivot has *not* happened yet -- `buildLandmark`
	turns the whole Model afterwards -- which is exactly why the tag is on the
	part and not a stored position. A tagged part reports where it ended up.
]]
local function buildSpaceport(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local plateColor = style.buildingColors[1]

	for i = 1, 3 do
		local angle = (i - 1) * (math.pi * 2 / 3) + rng:NextNumber(-0.2, 0.2)
		local centre = base + Vector3.new(math.cos(angle) * 78, 0, math.sin(angle) * 78)

		local pad = cylinder(
			parent,
			CFrame.new(centre + Vector3.new(0, 1.5, 0)) * UPRIGHT,
			Vector3.new(3, 68, 68),
			Palette.WornSteel,
			Enum.Material.DiamondPlate
		)
		pad.Name = "Pad"
		CollectionService:AddTag(pad, Ships.PAD_TAG)

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

--[[
	A low drum you can walk into: bar, tables, and a lit sign over the door.

	The first interior, and the obvious one to be first. A cantina is where
	the genre puts its conversations, and it is where this game's vendors and
	dialogue already happen -- until now, on the pavement outside a building
	that had no inside.
]]
local function buildCantina(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local wall = style.buildingColors[rng:NextInteger(1, #style.buildingColors)]
	local dark = wall:Lerp(Color3.new(0, 0, 0), 0.45)
	local radius = 37

	roundWall(parent, base, radius, ROOM_HEIGHT, wall, Enum.Material.Concrete)
	cylinder(
		parent,
		CFrame.new(base + Vector3.new(0, FLOOR_Y, 0)) * UPRIGHT,
		Vector3.new(1, radius * 2 - 2, radius * 2 - 2),
		dark,
		Enum.Material.Slate
	).Name =
		"Floor"
	cylinder(
		parent,
		CFrame.new(base + Vector3.new(0, ROOM_HEIGHT + 1, 0)) * UPRIGHT,
		Vector3.new(2, radius * 2 + 2, radius * 2 + 2),
		dark,
		Enum.Material.Concrete
	).Name =
		"Ceiling"

	--[[
		A dome needs half a ball, and Roblox only has whole ones -- so the
		lower half has to be buried in something. Resting the equator on the
		wall head buries it in the *room*, which is why the first version hung
		a huge lit bowl over the tables. The drum buries it instead, and a
		dome on a drum is the Tatooine silhouette anyway.
	]]
	local domeRise = 12
	cylinder(
		parent,
		CFrame.new(base + Vector3.new(0, ROOM_HEIGHT + domeRise * 0.5, 0)) * UPRIGHT,
		Vector3.new(domeRise, radius * 2 + 2, radius * 2 + 2),
		wall,
		Enum.Material.Concrete
	).Name =
		"Drum"

	local roof = ball(
		parent,
		CFrame.new(base + Vector3.new(0, ROOM_HEIGHT + domeRise, 0)),
		Vector3.new(radius * 2 + 2, domeRise * 2, radius * 2 + 2),
		wall,
		Enum.Material.Concrete
	)
	roof.Name = "Roof"
	roof.CanCollide = false

	-- Entrance: posts and a canopy, framing the gap the wall left at +X.
	for _, side in { -1, 1 } do
		block(
			parent,
			CFrame.new(base + Vector3.new(radius + 4, 8, side * 9)),
			Vector3.new(12, 16, 4),
			wall,
			Enum.Material.Concrete
		).Name =
			"Post"
	end
	block(
		parent,
		CFrame.new(base + Vector3.new(radius + 4, 17, 0)),
		Vector3.new(14, 2, 22),
		wall,
		Enum.Material.Concrete
	).Name =
		"Canopy"

	local sign = block(
		parent,
		CFrame.new(base + Vector3.new(radius + 4, 21, 0)),
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

	-- The bar, opposite the door, so walking in points you at it. Overhang
	-- and a foot rail: the two details that say "bar" rather than "wall".
	block(
		parent,
		CFrame.new(base + Vector3.new(-16, 5, 0)),
		Vector3.new(5, 10, 42),
		Palette.SmugglerBrown,
		Enum.Material.WoodPlanks
	).Name =
		"Counter"
	block(
		parent,
		CFrame.new(base + Vector3.new(-15, 10.5, 0)),
		Vector3.new(9, 1.4, 44),
		dark,
		Enum.Material.Wood
	).Name =
		"CounterTop"
	cylinder(
		parent,
		-- Lying along Z, so it is turned about Y rather than the usual
		-- quarter turn about Z that stands a cylinder up.
		CFrame.new(base + Vector3.new(-11, 2, 0)) * CFrame.Angles(0, math.pi * 0.5, 0),
		Vector3.new(42, 1.6, 1.6),
		Palette.WornSteel,
		Enum.Material.Metal
	).Name =
		"FootRail"
	block(
		parent,
		CFrame.new(base + Vector3.new(-27, 8, 0)),
		Vector3.new(3, 16, 38),
		dark,
		Enum.Material.Metal
	).Name =
		"Shelf"
	for i = -3, 3 do
		local bottle = cylinder(
			parent,
			CFrame.new(base + Vector3.new(-25, 13, i * 5)) * UPRIGHT,
			Vector3.new(5, 2, 2),
			style.windowColor,
			Enum.Material.Neon
		)
		bottle.Name = "Bottle"
		bottle.CanCollide = false
	end

	-- Tables around the floor. The bearings skip due -X, which is the bar,
	-- and are pulled off due +X, which is the walk in from the door.
	for _, bearing in { 30, 90, 270, 330 } do
		local angle = math.rad(bearing)
		local at = base + Vector3.new(math.cos(angle) * 22, 0, math.sin(angle) * 22)

		cylinder(
			parent,
			CFrame.new(at + Vector3.new(0, 4, 0)) * UPRIGHT,
			Vector3.new(8, 3, 3),
			Palette.DarkMetal,
			Enum.Material.Metal
		).Name =
			"TablePost"
		cylinder(
			parent,
			CFrame.new(at + Vector3.new(0, 8.5, 0)) * UPRIGHT,
			Vector3.new(1.5, 13, 13),
			Palette.SmugglerBrown,
			Enum.Material.WoodPlanks
		).Name =
			"Table"

		for stool = 1, 3 do
			local around = angle + stool * (math.pi * 2 / 3)
			cylinder(
				parent,
				CFrame.new(at + Vector3.new(math.cos(around) * 11, 3, math.sin(around) * 11)) * UPRIGHT,
				Vector3.new(6, 6, 6),
				dark,
				Enum.Material.Metal
			).Name =
				"Stool"
		end
	end

	ceilingLamp(parent, base + Vector3.new(0, ROOM_HEIGHT - 3, 0), style.windowColor, 60)
	ceilingLamp(parent, base + Vector3.new(-18, ROOM_HEIGHT - 3, 0), style.windowColor, 40)

	-- Wall head, drum, then the dome cap on top of it.
	return ROOM_HEIGHT + 24
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
	--[[
		Each side is a slab plus a coping course and buttresses down its
		length. A bare 164-stud slab standing on open sand does not read as a
		wall -- it reads as a stray block, which is exactly how it looked in
		the first playtest. The buttresses give it a rhythm and the coping
		gives it a top, and between them the eye names it.
	]]
	for _, side in sides do
		block(parent, CFrame.new(base + side.offset), side.size, wallColor, Enum.Material.Concrete).Name =
			"Wall"
		block(
			parent,
			CFrame.new(base + side.offset + Vector3.new(0, 10, 0)),
			Vector3.new(side.size.X + 3, 2.5, side.size.Z + 3),
			Palette.Gunmetal,
			Enum.Material.Concrete
		).Name =
			"Coping"

		-- Along whichever axis this side is long, and facing outwards.
		local alongX = side.size.X > side.size.Z
		local run = if alongX then side.size.X else side.size.Z
		local out = if alongX then math.sign(side.offset.Z) else math.sign(side.offset.X)
		local count = math.max(2, math.floor(run / 42))

		for i = 0, count do
			local along = (i / count - 0.5) * (run - 10)
			local step = if alongX then Vector3.new(along, -1, out * 3) else Vector3.new(out * 3, -1, along)
			block(
				parent,
				CFrame.new(base + side.offset + step),
				if alongX then Vector3.new(7, 16, 10) else Vector3.new(10, 16, 7),
				wallColor,
				Enum.Material.Concrete
			).Name =
				"Buttress"
		end
	end

	-- The keep is a barracks you can walk into, and its door faces the gate,
	-- so the way in from outside runs straight through to the way inside.
	roomShell(parent, CFrame.new(base), Vector3.new(70, ROOM_HEIGHT, 56), wallColor, Enum.Material.Concrete)
	block(
		parent,
		CFrame.new(base + Vector3.new(0, ROOM_HEIGHT + 5, 0)),
		Vector3.new(52, 8, 42),
		Palette.Gunmetal,
		Enum.Material.Metal
	).Name =
		"Parapet"

	-- Bunks down the back wall with footlockers beside them, and a briefing
	-- table: enough that the room says who sleeps here.
	for i = -1, 1 do
		local at = base + Vector3.new(-22, 0, i * 17)
		bunk(parent, at, wallColor)
		footlocker(parent, at + Vector3.new(13, 0, 0))
	end

	table_(
		parent,
		base + Vector3.new(8, 0, 0),
		Vector3.new(20, 5, 14),
		Palette.WornSteel,
		Enum.Material.Metal
	)
	-- What a briefing table is for. Faint, and it does not collide, so it
	-- reads as projected rather than as a slab resting on the furniture.
	local holo = block(
		parent,
		CFrame.new(base + Vector3.new(8, 9, 0)),
		Vector3.new(16, 4, 10),
		style.windowColor,
		Enum.Material.Neon
	)
	holo.Name = "Hologram"
	holo.CanCollide = false
	holo.Transparency = 0.65

	ceilingLamp(parent, base + Vector3.new(0, ROOM_HEIGHT - 5, 0), style.windowColor, 55)

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
	-- Off to one side of the yard. It used to be allowed to land half inside
	-- the keep -- which now means half inside a room -- or across the line
	-- from the gate to the keep door, which is now a way in.
	local yard = CFrame.new(base + Vector3.new(rng:NextNumber(46, 64), 5, rng:NextNumber(24, 44)))
		* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	block(parent, yard, Vector3.new(26, 10, 14), Palette.Gunmetal, Enum.Material.Metal).Name = "Crate"
	-- Banding and feet. One dark box on open sand is not a supply crate, it
	-- is a mystery object, and the eye reads it as a mistake.
	for _, x in { -8, 0, 8 } do
		block(
			parent,
			yard * CFrame.new(x, 0, 0),
			Vector3.new(2.5, 10.6, 14.6),
			Palette.WornSteel,
			Enum.Material.Metal
		).Name =
			"Band"
	end
	for _, x in { -10, 10 } do
		block(
			parent,
			yard * CFrame.new(x, -4.5, 0),
			Vector3.new(4, 3, 15),
			Palette.DarkMetal,
			Enum.Material.Metal
		).Name =
			"Skid"
	end

	return ROOM_HEIGHT + 20
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

--------------------------------------------------------------------------------
-- Named landmarks
--------------------------------------------------------------------------------

--[[
	The eight builders above are *kinds*. A market is a market on any world,
	and one builder serving nine planets is the right trade for it.

	It is the wrong trade for a place with a name, and the state of the game
	before this section is the argument: **the Tomb of Tulak Hord was a
	crashed starship.** `Ruin` means "something that used to fly, nose-down in
	the ground", it was the closest of the eight, and so Korriban -- a world
	whose entire claim on the player is that it is a valley of tombs -- had a
	downed freighter lying in it with a sign saying TOMB. The Jedi Temple
	ruin was an intact ziggurat. The moisture farm the config describes as
	"forty vaporators and one family" was a two-hut shed with one vaporator.

	These cost no machinery. `landmarkFor` has read `poi.landmark or poi.kind`
	since the sandcrawler, so a named place is a builder plus one line of
	config, and the fallback for a world that has not earned one is still the
	generic kind. What this section must not become is one builder per point
	of interest: `LeaningTowers` serves two Taris districts and would serve
	any fallen city. The test for adding one is whether **the description
	already sitting in the config** describes something the generic builder
	cannot draw -- every one of these was written from those words, and where
	the words give a number ("towers leaning at twenty degrees") the number is
	honoured exactly.
]]

--[[
	A Sith tomb cut into a rock face, and sealed.

	Built back to front from every other landmark here: the mass is a cliff
	*behind* the door rather than a building in front of it, because a tomb is
	a hole in something and a freestanding one is a mausoleum. The jambs are
	battered -- they lean in six degrees -- since a trapezoid reads as ancient
	and a rectangle reads as a doorframe.

	The config says "Sealed, and the seal is not there to keep anything in",
	so the doorway is filled flush and the braziers are lit. Somebody is still
	coming out here to tend them, which is the more frightening reading.
]]
local function buildTomb(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local stone = shade(style.buildingColors[#style.buildingColors], -0.15)
	local dark = shade(stone, -0.4)

	-- One mass behind the facade, wider and deeper than anything in front of
	-- it, so the tomb is seen against rock from every approach.
	block(
		parent,
		CFrame.new(base + Vector3.new(-48, 34, 0)),
		Vector3.new(76, 68, 150),
		dark,
		Enum.Material.Rock
	).Name =
		"Cliff"
	for i = -1, 1, 2 do
		block(
			parent,
			CFrame.new(base + Vector3.new(-16, 28, i * 52)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0),
			Vector3.new(32, 56, 46),
			dark,
			Enum.Material.Rock
		).Name =
			"Buttress"
	end

	for _, side in { 1, -1 } do
		block(
			parent,
			CFrame.new(base + Vector3.new(-2, 25, side * 15)) * CFrame.Angles(math.rad(6) * side, 0, 0),
			Vector3.new(14, 42, 10),
			stone,
			Enum.Material.Slate
		).Name =
			"Jamb"
	end
	block(
		parent,
		CFrame.new(base + Vector3.new(-2, 49, 0)),
		Vector3.new(18, 8, 46),
		stone,
		Enum.Material.Slate
	).Name =
		"Lintel"
	block(
		parent,
		CFrame.new(base + Vector3.new(-3, 23, 0)),
		Vector3.new(7, 38, 22),
		shade(stone, -0.3),
		Enum.Material.Slate
	).Name =
		"Seal"

	-- The dais and its steps. The doorway standing a few studs proud of the
	-- ground is what turns walking in into an approach.
	block(parent, CFrame.new(base + Vector3.new(3, 2, 0)), Vector3.new(28, 4, 54), stone, Enum.Material.Slate).Name =
		"Dais"
	for step = 1, 3 do
		local height = 4 - step
		block(
			parent,
			CFrame.new(base + Vector3.new(17 + step * 5, height * 0.5, 0)),
			Vector3.new(5, height, 54),
			stone,
			Enum.Material.Slate
		).Name =
			"Step"
	end

	for _, side in { 1, -1 } do
		local at = base + Vector3.new(28, 0, side * 32)
		block(
			parent,
			CFrame.new(at + Vector3.new(0, 17, 0)),
			Vector3.new(8, 34, 8),
			stone,
			Enum.Material.Slate
		).Name =
			"Obelisk"
		-- A tapered cap, because a flat-topped post is a bollard.
		block(parent, CFrame.new(at + Vector3.new(0, 36, 0)), Vector3.new(5, 6, 5), dark, Enum.Material.Slate).Name =
			"Cap"

		-- Nothing else on this planet is lit at ground level, so from the
		-- valley floor the tomb is two red points and a shape.
		cylinder(
			parent,
			CFrame.new(at + Vector3.new(7, 7, 0)) * UPRIGHT,
			Vector3.new(4, 10, 10),
			Palette.DarkMetal,
			Enum.Material.Metal
		).Name =
			"Brazier"
		local fire = ball(
			parent,
			CFrame.new(at + Vector3.new(7, 10, 0)),
			Vector3.new(8, 5, 8),
			Palette.SaberRed,
			Enum.Material.Neon
		)
		fire.Name = "Fire"
		fire.CanCollide = false

		local glow = Instance.new("PointLight")
		glow.Color = Palette.SaberRed
		glow.Range = 42
		glow.Brightness = 2.5
		glow.Parent = fire
	end

	return 58
end

--[[
	A temple that came down, and was left down.

	The hard part of a ruin is that "broken" is not a shape: a pile of rubble
	reads as rubble, never as something that used to be a building. So this is
	built as a temple that is *mostly still there* -- an intact terrace, a
	colonnade with the columns knocked out of it, and the fallen ones lying
	where they landed, still in their line and broken into drums. The eye
	rebuilds the temple out of the gap, which no amount of debris would do.

	One corner of the upper step is simply absent. A missing quarter says
	"something hit this" more economically than anything scattered around it.
]]
local function buildTempleRuin(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local stone = style.buildingColors[#style.buildingColors]
	local burnt = shade(stone, -0.45)

	block(
		parent,
		CFrame.new(base + Vector3.new(0, 5, 0)),
		Vector3.new(150, 10, 118),
		stone,
		Enum.Material.Slate
	).Name =
		"Terrace"
	for _, quarter in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1) } do
		block(
			parent,
			CFrame.new(base + Vector3.new(quarter.X * 30, 14, quarter.Y * 24)),
			Vector3.new(58, 8, 46),
			shade(stone, -0.1),
			Enum.Material.Slate
		).Name =
			"Step"
	end

	--[[
		The colonnade. How much of each bay is left is rolled per bay, and a
		column that fell lies in three drums rather than one piece -- a
		column that came down whole did not come down.
	]]
	for _, side in { 1, -1 } do
		for bay = 1, 6 do
			local at = base + Vector3.new((bay - 3.5) * 24, 0, side * 46)
			local state = rng:NextInteger(1, 3)
			if state == 1 then
				cylinder(
					parent,
					CFrame.new(at + Vector3.new(0, 32, 0)) * UPRIGHT,
					Vector3.new(44, 11, 11),
					stone,
					Enum.Material.Slate
				).Name =
					"Column"
				block(
					parent,
					CFrame.new(at + Vector3.new(0, 56, 0)),
					Vector3.new(14, 4, 14),
					stone,
					Enum.Material.Slate
				).Name =
					"Capital"
			else
				local height = if state == 2 then rng:NextNumber(9, 22) else 5
				cylinder(
					parent,
					CFrame.new(at + Vector3.new(0, 10 + height * 0.5, 0)) * UPRIGHT,
					Vector3.new(height, 11, 11),
					burnt,
					Enum.Material.Slate
				).Name =
					"Stump"
			end

			if state == 3 then
				for drum = 1, 3 do
					cylinder(
						parent,
						CFrame.new(at + Vector3.new(0, 15.5, side * (16 + drum * 15)))
							* CFrame.Angles(0, math.pi * 0.5 + rng:NextNumber(-0.22, 0.22), 0),
						Vector3.new(14, 11, 11),
						stone,
						Enum.Material.Slate
					).Name =
						"Drum"
				end
			end
		end
	end

	-- The spire is the only diagonal on the site, which is what makes
	-- everything else read as level ground rather than as a heap.
	block(
		parent,
		CFrame.new(base + Vector3.new(28, 28, -20)) * CFrame.Angles(0, math.rad(24), math.rad(-58)),
		Vector3.new(96, 20, 20),
		shade(stone, -0.2),
		Enum.Material.Slate
	).Name =
		"FallenSpire"
	block(
		parent,
		CFrame.new(base + Vector3.new(-52, 32, 12)),
		Vector3.new(24, 54, 24),
		burnt,
		Enum.Material.Slate
	).Name =
		"SpireStump"

	return 66
end

--[[
	A moisture farm: a sunken homestead in a field of vaporators.

	The count is the whole landmark. `buildOutpost` puts up one vaporator and
	that is enough to say somebody lives here; the config here says forty, and
	forty is not a bigger version of one -- a lone mast is a homestead and a
	field of them is an industry. Sixteen is what the part budget allows,
	on two rings so the near masts do not stand in front of the far ones.

	The house is a courtyard pit rather than another dome, which is the one
	piece of Tatooine architecture that is actually about the planet: where
	the problem is the sun, you live underground and the roof is a hole.
]]
local function buildMoistureFarm(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local wall = style.buildingColors[1]
	local lip = 26

	-- A dark floor inside a low kerb: a hole from outside, a room from the
	-- edge of it. The segment facing the road is left out, and that gap is
	-- the ramp down -- the same trick `roundWall` plays with its doorway.
	for seg = 1, 16 do
		if seg ~= 1 then
			local angle = (seg - 1) * (math.pi * 2 / 16)
			block(
				parent,
				CFrame.new(base + Vector3.new(math.cos(angle) * lip, 3, math.sin(angle) * lip))
					* CFrame.Angles(0, -angle, 0),
				Vector3.new(4, 6, 11),
				wall,
				Enum.Material.Sandstone
			).Name =
				"Kerb"
		end
	end
	cylinder(
		parent,
		CFrame.new(base + Vector3.new(0, -1, 0)) * UPRIGHT,
		Vector3.new(2, lip * 2, lip * 2),
		shade(wall, -0.6),
		Enum.Material.Sand
	).Name =
		"Courtyard"
	block(
		parent,
		CFrame.new(base + Vector3.new(lip + 7, -1.5, 0)) * CFrame.Angles(0, 0, math.rad(9)),
		Vector3.new(22, 2, 12),
		shade(wall, -0.3),
		Enum.Material.Sandstone
	).Name =
		"Ramp"

	-- The only parts of the house above ground are the way in and the
	-- condenser on top of it.
	for _, at in { Vector3.new(-32, 0, 18), Vector3.new(-24, 0, -26) } do
		local width = if at.Z > 0 then 26 else 18
		cylinder(
			parent,
			CFrame.new(base + at + Vector3.new(0, 4, 0)) * UPRIGHT,
			Vector3.new(8, width, width),
			wall,
			Enum.Material.Sandstone
		).Name =
			"Dome"
		ball(
			parent,
			CFrame.new(base + at + Vector3.new(0, 8, 0)),
			Vector3.new(width, width * 0.7, width),
			wall,
			Enum.Material.Sandstone
		).Name =
			"Cap"
	end

	-- Everything the farm exists to do ends up in the cistern, so it is the
	-- one thing on the site that is metal and looked after.
	cylinder(
		parent,
		CFrame.new(base + Vector3.new(-6, 9, 34)) * UPRIGHT,
		Vector3.new(18, 30, 30),
		Palette.WornSteel,
		Enum.Material.Metal
	).Name =
		"Cistern"
	block(
		parent,
		CFrame.new(base + Vector3.new(-6, 19, 34)),
		Vector3.new(32, 2, 32),
		Palette.DarkMetal,
		Enum.Material.DiamondPlate
	).Name =
		"CisternLid"

	for ring = 1, 2 do
		local radius = 42 + ring * 18
		local count = 5 + ring * 2
		for i = 1, count do
			local angle = (i - 1) * (math.pi * 2 / count) + ring * 0.45
			local at = base + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			local height = rng:NextNumber(20, 28)
			cylinder(
				parent,
				CFrame.new(at + Vector3.new(0, height * 0.5, 0)) * UPRIGHT,
				Vector3.new(height, 4, 4),
				Palette.WornSteel,
				Enum.Material.Metal
			).Name =
				"Vaporator"
			for fin = 1, 3 do
				local spoke = (fin - 1) * (math.pi * 2 / 3) + angle
				block(
					parent,
					CFrame.new(at + Vector3.new(math.cos(spoke) * 3.5, height - 4, math.sin(spoke) * 3.5))
						* CFrame.Angles(0, -spoke, 0),
					Vector3.new(1.5, 8, 5),
					Palette.DarkMetal,
					Enum.Material.Metal
				).Name =
					"Fin"
			end
		end
	end

	return 34
end

--[[
	A scrapyard, which is not the same thing as a wreck.

	`Ruin` builds something that came down: one hull, at an angle, ground
	disturbed around it. A boneyard is the opposite of a crash -- nothing here
	fell, it was all dragged in and taken apart -- so everything is level, in
	rows, and missing its panels. Rows are the cheap half of that: a straight
	line of anything says a person put it there.

	The hauler is the only large piece and it is on its side, because that is
	how you get at the underside, and it is built as two hull sections with a
	gap between them. The gap is the part that was cut out and sold, and it is
	the entire difference between stripped and parked.
]]
local function buildBoneyard(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local rust = Palette.DroidRust
	local root = CFrame.new(base + Vector3.new(-20, 22, 10)) * CFrame.Angles(0, math.rad(18), math.rad(74))

	block(parent, root * CFrame.new(-26, 0, 0), Vector3.new(44, 26, 30), rust, Enum.Material.CorrodedMetal).Name =
		"Hull"
	block(parent, root * CFrame.new(30, 0, 0), Vector3.new(36, 26, 30), rust, Enum.Material.CorrodedMetal).Name =
		"Hull"
	for i = -1, 1 do
		block(
			parent,
			root * CFrame.new(i * 8, 0, 0),
			Vector3.new(2, 24, 28),
			Palette.DarkMetal,
			Enum.Material.Metal
		).Name =
			"Rib"
	end

	-- Masts snapped at different heights and stood in a line.
	for i = 1, 6 do
		local height = rng:NextNumber(6, 20)
		cylinder(
			parent,
			CFrame.new(base + Vector3.new(22 + (i % 2) * 12, height * 0.5, (i - 3.5) * 15)) * UPRIGHT,
			Vector3.new(height, 4, 4),
			Palette.WornSteel,
			Enum.Material.CorrodedMetal
		).Name =
			"Husk"
	end

	-- Chassis up on blocks with the engine bay empty. A speeder with its
	-- body still on is a parked speeder.
	for _ = 1, 3 do
		local turn = CFrame.new(base + Vector3.new(rng:NextNumber(-48, -22), 0, rng:NextNumber(-54, -22)))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		block(parent, turn * CFrame.new(0, 4, 0), Vector3.new(24, 2, 8), rust, Enum.Material.CorrodedMetal).Name =
			"Chassis"
		for _, dx in { -9, 9 } do
			block(
				parent,
				turn * CFrame.new(dx, 1.5, 0),
				Vector3.new(4, 3, 7),
				Palette.DarkMetal,
				Enum.Material.Metal
			).Name =
				"Block"
		end
	end

	-- Cut panels, stacked flat. Salvage is sorted; a crash site is not.
	for i = 1, 4 do
		block(
			parent,
			CFrame.new(base + Vector3.new(40, 1 + i * 1.6, -32))
				* CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0),
			Vector3.new(26, 1.4, 18),
			shade(style.buildingColors[1], -0.2),
			Enum.Material.CorrodedMetal
		).Name =
			"Panel"
	end

	return 32
end

--[[
	A city block that sank: towers off plumb, and a way up through them.

	Twenty degrees comes from the config's own description and is worth
	honouring to the number. Five degrees reads as a modelling mistake and
	forty reads as falling over this second; twenty is unmistakably deliberate
	and unmistakably wrong, which is the whole effect.

	They lean in *different* directions on purpose. A row all leaning the same
	way is a hillside. Leaning apart, they are a district that subsided
	unevenly -- which is what "and still settling" means.

	Each tower is rotated about its foot rather than its centre. Rotating a
	box about the middle lifts one bottom corner clear of the ground and
	buries the other, and the lifted corner is the tell.
]]
local function buildLeaningTowers(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local tallest = 0
	local feet: { Vector3 } = {}

	for i = 1, 4 do
		local bearing = (i - 1) * (math.pi * 2 / 4) + 0.5
		local at = base + Vector3.new(math.cos(bearing) * 38, 0, math.sin(bearing) * 38)
		local height = rng:NextNumber(54, 98)
		local width = rng:NextNumber(20, 30)
		local wall = pick(style.buildingColors, rng)
		table.insert(feet, at)
		tallest = math.max(tallest, height * math.cos(math.rad(20)))

		local root = CFrame.new(at)
			* CFrame.Angles(0, -(bearing + rng:NextNumber(-0.9, 0.9)), 0)
			* CFrame.Angles(0, 0, -math.rad(20) * rng:NextNumber(0.75, 1.15))
			* CFrame.new(0, height * 0.5, 0)

		block(parent, root, Vector3.new(width, height, width), wall, style.wallMaterial).Name = "Tower"
		cornice(parent, at, 0, width, width, wall, style.wallMaterial)

		-- Bands in the tower's own frame. `windowBands` takes a world point
		-- and cannot tilt, which is fine for a building that stands up.
		local floors = math.floor(height / style.floorHeight)
		for floor = 1, floors do
			local y = (floor - 0.5) * style.floorHeight - height * 0.5
			for _, side in { 1, -1 } do
				local band = block(
					parent,
					root * CFrame.new(0, y, side * width * 0.5),
					Vector3.new(width * 0.8, 2.2, 0.4),
					style.windowColor,
					Enum.Material.Neon
				)
				band.Name = "Windows"
				band.CanCollide = false
			end
		end

		-- Rubble banked against the foot. Without it the tower meets flat
		-- ground at an angle, and the gap under the raised edge is visible
		-- from a hundred studs away.
		for _ = 1, 4 do
			local size = rng:NextNumber(6, 13)
			block(
				parent,
				CFrame.new(at + Vector3.new(rng:NextNumber(-16, 16), size * 0.3, rng:NextNumber(-16, 16)))
					* CFrame.Angles(
						rng:NextNumber(-0.4, 0.4),
						rng:NextNumber(0, math.pi),
						rng:NextNumber(-0.4, 0.4)
					),
				Vector3.new(size, size * 0.6, size * rng:NextNumber(0.7, 1.3)),
				shade(wall, -0.3),
				Enum.Material.Concrete
			).Name =
				"Rubble"
		end
	end

	-- "You go up through them, not around": a plank between two of the feet,
	-- which is the only thing here that says these are passable rather than
	-- scenery. It is not a real route -- the towers are solid -- but it is
	-- the promise the district's interiors will have to keep.
	for i = 1, #feet - 1 do
		local a, b = feet[i], feet[i + 1]
		local mid = (a + b) * 0.5 + Vector3.new(0, 26 + i * 5, 0)
		local span = (b - a).Magnitude
		block(
			parent,
			CFrame.new(mid, b + Vector3.new(0, mid.Y - base.Y, 0)) * CFrame.Angles(0, math.pi * 0.5, 0),
			Vector3.new(span, 1.2, 7),
			Palette.WornSteel,
			Enum.Material.DiamondPlate
		).Name =
			"Catwalk"
	end

	return tallest + 12
end

--[[
	A saber forge: standing stones, an anvil and a fire, on a ridge.

	Deliberately the smallest thing in this section. The config's line is
	"Where sabers are made. Getting up here is the easy half", and a building
	would contradict it -- the point of the place is that there is nothing
	here, and the difficulty is what you brought with you. So: a ring, a
	stone to work on, and a fire, which is a forge in any culture that has
	not yet invented a roof.

	The stones are tilted a few degrees each and are not evenly spaced. An
	even ring of upright posts is a fence.
]]
local function buildForge(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local stone = style.buildingColors[#style.buildingColors]

	for i = 1, 9 do
		-- The gap at the road end is the way in, so the ring is not closed.
		local angle = (i - 1) * (math.pi * 2 / 10) + math.pi * 0.1
		local at = base + Vector3.new(math.cos(angle) * 34, 0, math.sin(angle) * 34)
		local height = rng:NextNumber(14, 26)
		block(
			parent,
			CFrame.new(at + Vector3.new(0, height * 0.5, 0))
				* CFrame.Angles(rng:NextNumber(-0.08, 0.08), -angle, rng:NextNumber(-0.08, 0.08)),
			Vector3.new(rng:NextNumber(5, 9), height, rng:NextNumber(3, 5)),
			shade(stone, rng:NextNumber(-0.2, 0.1)),
			Enum.Material.Rock
		).Name =
			"Standing"
	end

	block(
		parent,
		CFrame.new(base + Vector3.new(0, 1.5, 0)),
		Vector3.new(52, 3, 52),
		stone,
		Enum.Material.Rock
	).Name =
		"Floor"
	block(
		parent,
		CFrame.new(base + Vector3.new(-8, 6, 0)),
		Vector3.new(16, 6, 12),
		shade(stone, -0.25),
		Enum.Material.Rock
	).Name =
		"Anvil"

	local coals = cylinder(
		parent,
		CFrame.new(base + Vector3.new(10, 4, 0)) * UPRIGHT,
		Vector3.new(3, 16, 16),
		Palette.MustafarLava,
		Enum.Material.Neon
	)
	coals.Name = "Coals"
	coals.CanCollide = false

	local glow = Instance.new("PointLight")
	glow.Color = Palette.MustafarLava
	glow.Range = 48
	glow.Brightness = 2.2
	glow.Parent = coals

	return 32
end

--[[
	A traffic lane over a city with no ground.

	Coruscant has three of these and they were three identical sheds, because
	`Outpost` is what an unrecognised kind falls back to and a skylane is not
	a building at all. It is a *direction*: the landmark is the lane, and the
	only structure is the shelf you stand on to watch it go past.

	So the pylons run along the lane rather than ringing the platform, and
	they carry lit markers that recede. Two rows converging into the fog is
	the one composition that says "this goes somewhere and you are standing
	still", which is exactly the config's "traffic moves fast and does not
	stop for you".
]]
local function buildSkylane(parent: Instance, base: Vector3, style: Style, rng: Random): number
	local deck = shade(style.buildingColors[1], -0.15)

	block(
		parent,
		CFrame.new(base + Vector3.new(0, 1, 0)),
		Vector3.new(46, 2, 62),
		deck,
		Enum.Material.DiamondPlate
	).Name =
		"Deck"
	-- A rail on three sides. The fourth is the lane, and a barrier across
	-- the thing you came to look at is worse than a drop.
	for _, edge in { Vector3.new(-23, 0, 0), Vector3.new(0, 0, -31), Vector3.new(0, 0, 31) } do
		local along = if edge.X ~= 0 then Vector3.new(2, 5, 62) else Vector3.new(46, 5, 2)
		block(
			parent,
			CFrame.new(base + edge + Vector3.new(0, 4, 0)),
			along,
			Palette.DarkMetal,
			Enum.Material.Metal
		).Name =
			"Rail"
	end

	-- The control shack, at the back so it does not stand in the view.
	block(
		parent,
		CFrame.new(base + Vector3.new(-16, 8, 20)),
		Vector3.new(14, 12, 16),
		style.buildingColors[1],
		Enum.Material.Metal
	).Name =
		"Shack"
	local pane = block(
		parent,
		CFrame.new(base + Vector3.new(-8.6, 10, 20)),
		Vector3.new(0.6, 5, 12),
		style.windowColor,
		Enum.Material.Neon
	)
	pane.Name = "Pane"
	pane.CanCollide = false

	for lane = 1, 2 do
		local side = if lane == 1 then 1 else -1
		for i = 1, 7 do
			local at = base + Vector3.new(34 + i * 30, 0, side * (22 + i * 9))
			local height = rng:NextNumber(30, 54)
			cylinder(
				parent,
				CFrame.new(at + Vector3.new(0, height * 0.5, 0)) * UPRIGHT,
				Vector3.new(height, 4, 4),
				Palette.DarkMetal,
				Enum.Material.Metal
			).Name =
				"Pylon"

			local marker_ = block(
				parent,
				CFrame.new(at + Vector3.new(0, height, 0)),
				Vector3.new(9, 1.6, 1.6),
				if lane == 1 then Palette.CoruscantLight else Palette.BlasterBlue,
				Enum.Material.Neon
			)
			marker_.Name = "LaneMarker"
			marker_.CanCollide = false
		end
	end

	return 26
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
	Cantina = { radius = 52, build = buildCantina, interior = Vector3.new(0, 0, 0) },
	Base = { radius = 92, build = buildBase, interior = Vector3.new(20, 0, 0) },
	Outpost = OUTPOST,
	Market = { radius = 58, build = buildMarket },
	Temple = { radius = 74, build = buildTemple },

	-- Named places. Keyed by the string a POI puts in `landmark`; the radius
	-- is the footprint the marker reserves, and undersizing it is what sends
	-- the crowd rings walking through the building.
	Tomb = { radius = 70, build = buildTomb },
	TempleRuin = { radius = 86, build = buildTempleRuin },
	MoistureFarm = { radius = 84, build = buildMoistureFarm },
	Boneyard = { radius = 68, build = buildBoneyard },
	LeaningTowers = { radius = 74, build = buildLeaningTowers },
	Forge = { radius = 56, build = buildForge },
	Skylane = { radius = 54, build = buildSkylane },
}

--[[
	True if `id` names a landmark builder.

	Exists so `Planets.validate` can catch a `poi.landmark` no builder answers
	to. Falling back to an outpost is right for an unknown *kind* and wrong for
	a declared name: "Tomb" misspelt puts a small generic hut on the Valley of
	the Dark Lords and says nothing about why.
]]
function PlanetBuilder.landmarkExists(id: string): boolean
	return LANDMARKS[id] ~= nil
end

local function landmarkFor(poi: Planets.PointOfInterest): LandmarkDef
	return LANDMARKS[poi.landmark or poi.kind] or OUTPOST
end

--- The rotation that turns a builder's +X into `facing`.
--- Both callers need it: the building turns by it, and so does anything
--- expressed as an offset from the building's own front.
local function facingAngle(facing: Vector3): number
	return -math.atan2(facing.Z, facing.X)
end

--[[
	Builds the structure for one point of interest, aims its door, and signs it.

	EVERY BUILDER PUTS ITS DOOR ON +X
	`roundWall` leaves out the segment at angle zero and `roomShell` splits its
	+X wall into two jambs and a lintel; neither takes a bearing, because a
	shell with a hole in one known side is far simpler to write -- and to keep
	right -- than one that has to work out which segments a doorway of a given
	width covers. The cost of that simplicity was that every door in the game
	faced world east: the road out of town arrived at whichever wall happened
	to be nearest and the entrance was round the side.

	Turning the finished model pays that cost once, here, instead of in eight
	builders. It is a Model rather than a Folder for exactly this reason --
	`PivotTo` is the only thing in the file that needs one.
]]
local function buildLandmark(
	parent: Instance,
	poi: Planets.PointOfInterest,
	def: LandmarkDef,
	position: Vector3,
	facing: Vector3,
	style: Style,
	rng: Random
)
	local site = Instance.new("Model")
	site.Name = poi.id
	site.Parent = parent
	local top = def.build(site, position, style, rng)

	-- Pivot about the position the builder was given, not the bounding-box
	-- centre Roblox would pick: the landmark has to stay where it was placed,
	-- and its marker and its road are both aimed at that exact point.
	site.WorldPivot = CFrame.new(position)
	site:PivotTo(CFrame.new(position) * CFrame.Angles(0, facingAngle(facing), 0))

	-- Roughly where the structure stops being a shape and starts being a
	-- speck: a cantina announces itself across its own street, a spaceport
	-- across the district.
	-- Name first here, kind in brackets: standing in front of the building
	-- you already know what it is, and the signpost that sent you here is
	-- the place that leads on the kind.
	nameplate(
		site,
		position + Vector3.new(0, top + 10, 0),
		`{poi.displayName}  ({poi.kind})`,
		240 + def.radius * 4
	)
end

--------------------------------------------------------------------------------
-- Signpost
--------------------------------------------------------------------------------

--[[
	A finger-post in the plaza naming every landmark on the planet and
	pointing at it.

	Roads answer "where does this go" once you are already standing on one.
	They do not answer "where is the cantina", which is the question a player
	actually asks: a landmark's own sign gives up a few hundred studs out --
	deliberately, so signs do not outrun the fog -- and a town is wider than
	that. One post at the town centre with an arm per place, each turned to
	its bearing, answers it from the one spot everybody passes through, and
	is the sort of thing a frontier town would have anyway.
]]
local function buildSignpost(parent: Instance, at: Vector3, places: { { kind: string, at: Vector3 } })
	if #places == 0 then
		return
	end

	local post = folder("Signpost", parent)
	-- Arms stack up from just over head height instead of hanging off a tall
	-- post. From the ground the top of a 50-stud post is seen nearly edge-on,
	-- and a sign you have to crane at is a sign you do not read.
	local LOWEST_ARM = 8
	local ARM_SPACING = 5
	local height = LOWEST_ARM + (#places - 1) * ARM_SPACING + 4

	cylinder(
		post,
		CFrame.new(at + Vector3.new(0, height * 0.5, 0)) * UPRIGHT,
		Vector3.new(height, 3, 3),
		Palette.SmugglerBrown,
		Enum.Material.WoodPlanks
	).Name =
		"Post"

	for index, place in places do
		local bearing = Vector3.new(place.at.X - at.X, 0, place.at.Z - at.Z)
		if bearing.Magnitude < 1 then
			continue
		end
		local facing = bearing.Unit
		-- A CFrame turned by t about Y sends its local +X to
		-- (cos t, 0, -sin t), so pointing +X along a bearing of `a` needs -a.
		local angle = -math.atan2(facing.Z, facing.X)
		local y = LOWEST_ARM + (index - 1) * ARM_SPACING

		local arm = block(
			post,
			CFrame.new(at + facing * 10 + Vector3.new(0, y, 0)) * CFrame.Angles(0, angle, 0),
			Vector3.new(20, 4.5, 1),
			Palette.SmugglerBrown,
			Enum.Material.WoodPlanks
		)
		arm.Name = "Arm"
		arm.CanCollide = false

		--[[
			Painted on the plank, both faces, rather than floating over it.

			A BillboardGui always turns to face the camera, so six of them on
			one post are six lines of text hanging in mid-air on top of each
			other, attached to nothing -- which is exactly how it looked. A
			SurfaceGui is writing *on* the sign.
		]]
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Face"
			gui.Face = face
			gui.PixelsPerStud = 28
			gui.LightInfluence = 0
			gui.Parent = arm

			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(0.94, 0.76)
			label.Position = UDim2.fromScale(0.03, 0.12)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Palette.HullWhite
			--[[
				The kind, and only the kind.

				TextScaled fits the *width* as well as the height, so a long
				string is not big text that runs off the plank -- it is small
				text, and "Cantina - The Dry Well" came out as a thin smear
				you had to already know to read. One word fills the sign.

				Where two of a kind exist the player gets two arms reading
				RUIN pointing different ways, which is true and still more
				use than either name. The building's own plate has the name.
			]]
			label.Text = string.upper(place.kind)
			label.Parent = gui
		end
	end
end

--------------------------------------------------------------------------------
-- Markers
--------------------------------------------------------------------------------

-- How far a zone's patrol points spread around its centre, at the smallest
-- population. Districts with more people in them get proportionally more room.
local ZONE_SPREAD = 70

-- Where a *second* landmark in one district goes, since it cannot have the
-- middle. Only the vertical cities have any, and they snap to a platform.
local LANDMARK_OFFSET = ZONE_SPREAD * 2.2

-- Kept clear around a landmark so its district's waypoints ring the building
-- rather than land in it. Small: people inside a market are the market.
local LANDMARK_CLEARANCE = 30

--[[
	How many NPCs one patrol point is expected to hold.

	Every district used to get three points and a seventy-stud ring regardless
	of whether six merchants or forty-four civilians were assigned to it. Nar
	Shaddaa's Promenade is 26 Civilians plus 18 CartelEnforcers at `distance =
	0` -- so the biggest crowd on the moon stood inside a circle two hundred
	studs across, centred on the plaza the player lands on. Every planet's
	first district is at distance 0 and every planet's first district is its
	most populous, so every planet did this.
]]
local ZONE_POINT_LOAD = 6

-- More than this and a district stops being a district. Twelve points at the
-- reach below already spans most of a settlement.
local ZONE_POINTS_MAX = 12

--[[
	The nearest ground inside a settlement that is certainly clear, and the
	shape of it.

	A point chosen by angle and distance lands inside a house about as often as
	not: `buildSettlement` fills most of every block and leaves the rest as its
	yard. The street grid is the one part of town guaranteed to be empty --
	every footprint is inset by `STREET_WIDTH` and `buildStreets` paves what is
	left -- so moving the point onto the nearer of the two street lines through
	it costs at most half a block and puts it somewhere a person can stand.

	Returns a box lying *along* that street rather than a square, so a busy
	district reads as people spread down a street instead of a knot at a
	junction.
]]
local function ontoStreet(origin: Vector3, at: Vector3): (Vector3, Vector3)
	-- Streets run on block boundaries, at `(line - 0.5) * BLOCK_SIZE`.
	local function nearestLine(v: number): number
		return (math.round(v / BLOCK_SIZE + 0.5) - 0.5) * BLOCK_SIZE
	end

	local dx = at.X - origin.X
	local dz = at.Z - origin.Z
	local lineX, lineZ = nearestLine(dx), nearestLine(dz)

	if math.abs(lineX - dx) <= math.abs(lineZ - dz) then
		-- Snapped in X, so the street runs along Z.
		return Vector3.new(origin.X + lineX, at.Y, at.Z), Vector3.new(STREET_WIDTH, 1, BLOCK_SIZE)
	end
	return Vector3.new(at.X, at.Y, origin.Z + lineZ), Vector3.new(BLOCK_SIZE, 1, STREET_WIDTH)
end

--[[
	Emits spawn, zone and POI markers.

	WHERE A ZONE GOES IS CONFIG, NOT LUCK
	Each district's distance from the town centre is declared on the planet
	(`Planets.ZoneDef`). It used to be derived from the order a zone's first
	spawn rule happened to appear in the list, which put Tatooine's Wastes at
	ring 0 -- downtown -- and its Town three rings out in the desert, and so
	dropped twelve aggressive Tusken Raiders onto a level 1 spawn point.

	THE ORDER HERE IS THE POINT
	District centres, then landmarks, then the crowds, then the player's spawn
	points -- each step taking its ground and the next working round it.

	A point of interest is placed inside the district it belongs to, so that
	"the Jawa crawler they live in still" has Jawas around it and the mission
	that sends you there is a place rather than a coordinate. So the landmark
	goes down first and its district's patrol route -- which NPCService reads
	off the parts named Point01.. -- is a ring around it. Doing it the other
	way round, which this used to, means the ring is drawn blind and the
	building has to be shoved clear of it.

	Player spawns come last, out of the yards no landmark claimed: someone who
	materialises inside a temple is pushed through the floor by the
	depenetration solver.
]]
local function buildMarkers(
	planet: Planets.PlanetDef,
	root: Instance,
	origin: Vector3,
	anchors: { Vector3 },
	rooms: { RoomSpot },
	style: Style,
	rng: Random
)
	local planetId = planet.id
	local zoneRoot = folder(planetId, folder("Zones", Workspace))
	zoneRoot:ClearAllChildren()

	-- Where each district sits, so points of interest can be dropped into
	-- theirs below and their crowds laid out around them after that.
	local centres: { [string]: Vector3 } = {}
	local count = math.max(1, #planet.zones)

	-- How crowded each district is meant to be. Read off the spawn rules
	-- rather than authored on the zone, so a planet that gains a spawn rule
	-- gains the room to put those people in. See ZONE_POINT_LOAD.
	local population: { [string]: number } = {}
	for _, rule in planet.spawns do
		if rule.zone then
			population[rule.zone] = (population[rule.zone] or 0) + rule.count
		end
	end

	--[[
		How big an authored district is, where one says so.

		Only set for zones with `cells`. Everywhere else the ring is sized off
		the district's population further down, which is the right answer when
		nobody has decided where the district's edges are.
	]]
	local reaches: { [string]: number } = {}
	--[[
		The same districts as half-sides rather than as one radius.

		A circle wide enough to reach the ends of a long district also reaches
		sideways into whatever was drawn beside it -- which on Korriban is the
		Academy at one end of the valley and Dreshdae at the other, nineteen
		levels apart. The rectangle the author drew is the shape they meant.
	]]
	local extents: { [string]: Vector3 } = {}
	local layout = planet.layout

	for index, def in planet.zones do
		-- Districts are fanned around the compass rather than stacked on one
		-- bearing, so walking out of town in any direction finds something.
		local angle = (index - 1) * (math.pi * 2 / count) + rng:NextNumber(-0.3, 0.3)
		local radius = def.distance * SETTLEMENT_RADIUS
		local centre = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

		-- An authored district is where the grid says, not where the fan
		-- lands. This is the whole reason `cells` exists: the market being
		-- east of the plaza is a fact about the town, and a bearing rolled
		-- from the seed cannot express it.
		local cells = def.cells
		if layout and cells then
			local at, reach = Planets.rectBounds(layout, cells)
			centre = origin + at
			reaches[def.id] = reach
			extents[def.id] = Planets.rectExtents(layout, cells)
		end

		-- Vertical cities have no ground, so districts snap to a platform
		-- instead of hanging in the air.
		if not planet.hasWalkableGround and #anchors > 0 then
			centre = anchors[math.min(index, #anchors)]
		end
		centres[def.id] = centre
	end

	local poiRoot = folder(planetId, folder("POI", Workspace))
	poiRoot:ClearAllChildren()
	local landmarkRoot = folder("Landmarks", root)
	-- Collected as each landmark settles on a position, because where they
	-- end up is decided below and nothing knows it until then. Roads and the
	-- signpost both read it.
	local reached: { { kind: string, at: Vector3 } } = {}

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

	--- Where each district's landmark ended up, for its crowd to gather round.
	local landmarks: { [string]: { at: Vector3, radius: number } } = {}
	--- How many have been placed in each district, since only one gets the middle.
	local placed: { [string]: number } = {}

	for index, poi in planet.pointsOfInterest do
		local position
		local def = landmarkFor(poi)
		local centre = if poi.zone then centres[poi.zone] else nil
		local nth = if poi.zone then (placed[poi.zone] or 0) else 0
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
			--[[
				The middle of its district. Its people are ringed around it
				afterwards, which is the whole of what makes a landmark a
				place rather than scenery.

				This used to be pushed *past* the patrol ring to keep the
				building off the waypoints -- so the more crowded a district
				was, the further its landmark stood from the crowd, and Nar
				Shaddaa's Promenade ended up an empty market street with
				forty-four people two hundred studs behind it. Clearance is
				now the ring's problem, where it costs nothing.

				A second landmark in one district cannot also have the
				middle. Only the vertical cities have any, and they snap to a
				platform below regardless.
			]]
			local offset = if nth == 0 then 0 else LANDMARK_OFFSET + def.radius
			position = centre + Vector3.new(math.cos(angle) * offset, 0, math.sin(angle) * offset)
		else
			-- No district named: fall back to an even circle. Honest rather
			-- than wrong -- it is somewhere, just nowhere in particular.
			local distance = SETTLEMENT_RADIUS * 0.55
			position = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		end

		--[[
			A place the layout already built stays exactly where it was drawn.

			Everything below this is the business of finding ground for a
			building, and there is no building to find ground for: the
			ziggurat, the tomb faces and the shopfronts are cells on the
			grid. It keeps its marker and its arm on the signpost, which is
			all a point of interest was ever for once the geometry exists.

			It also claims no yard and reserves no clearance, deliberately --
			an empty middle is somewhere the crowd should be standing, and
			the drawn building is already keeping them out of its own
			footprint by being solid.
		]]
		if poi.drawn and centre then
			position = centre
		elseif not planet.hasWalkableGround then
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

		-- Recorded only now, because claiming a yard or being pushed past the
		-- last street both move it, and it is where the building actually
		-- stands that the crowd has to gather round. A drawn place is not
		-- recorded at all: it took no ground, so it has not used up the
		-- middle of its district and a second landmark there may still have
		-- it.
		if poi.zone and not poi.drawn then
			placed[poi.zone] = nth + 1
			if nth == 0 then
				landmarks[poi.zone] = { at = position, radius = def.radius }
			end
		end

		--[[
			The front faces the way you arrive from.

			Out of town that is the road, which is drawn along this same
			bearing a few dozen lines below; in town it is the plaza, which is
			where the street grid and the signpost send you from. Either way
			the thing a player walks up to is the door.
		]]
		local inbound = Vector3.new(origin.X - position.X, 0, origin.Z - position.Z)
		local facing = if inbound.Magnitude > 1 then inbound.Unit else Vector3.new(1, 0, 0)

		if not poi.drawn then
			buildLandmark(landmarkRoot, poi, def, position, facing, style, rng)
		end
		table.insert(reached, { kind = poi.kind, at = position })

		-- Standing room indoors, added to the district the landmark belongs
		-- to. Small on purpose: NPCService scatters within a zone part and
		-- then drops whatever it picks to the floor, so a box the size of
		-- the room would put people on the tables and behind the bar.
		-- A drawn place gets none: its rooms come from the grid instead, and
		-- an interior offset from a building that was never built is a
		-- standing spot in the open air.
		if def.interior and poi.zone and not poi.drawn then
			-- Turned with the building. The offset is written in the
			-- builder's own frame -- the Base's is +X, meaning "just inside
			-- the door" -- so leaving it in world space would put the
			-- standing room outside a rotated building, in a wall.
			local inside = CFrame.Angles(0, facingAngle(facing), 0) * def.interior
			marker(
				folder(poi.zone, zoneRoot),
				"Inside",
				position + inside + Vector3.new(0, 3, 0),
				Vector3.new(16, 1, 16)
			)
		end
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
		The crowd, ringed around whatever its district is famous for.

		Each zone gets several parts, which NPCService reads as a patrol
		route, so people walk a circuit without anyone hand-placing waypoints.
		The ring is centred on the district's landmark where it has one -- and
		on the bare district centre where it does not -- because a market with
		its traders on the far side of a two-hundred-stud circle is an empty
		market, whatever the geometry says about who belongs to which zone.

		It has to run after the landmarks for that reason: the building takes
		its ground first and the ring opens up around it, rather than the ring
		being drawn blind and the building shoved outside it.
	]]
	for _, def in planet.zones do
		local landmark = landmarks[def.id]
		local authored = reaches[def.id]
		-- An authored district stays where it was drawn even when it has a
		-- landmark. Anchorhead's spaceport is too big for a city block and
		-- ends up out past the wall; following it would take all thirty-two
		-- townspeople out to the landing field with it.
		local centre = if landmark and not authored then landmark.at else centres[def.id]
		local zone = folder(def.id, zoneRoot)
		local points = math.clamp(math.ceil((population[def.id] or 0) / ZONE_POINT_LOAD), 3, ZONE_POINTS_MAX)
		-- Linear in the number of points, so the ring grows about as fast as
		-- the crowd does rather than falling behind it.
		local reach = ZONE_SPREAD * (points / 3)
		-- Nobody is asked to stand where the building is. Widening the ring
		-- to suit is what used to be done by moving the building instead.
		local inner = math.max(reach * 0.4, (if landmark then landmark.radius else 0) + LANDMARK_CLEARANCE)
		reach = math.max(reach, inner + ZONE_SPREAD)

		-- An authored district is exactly the size of its rectangle. Sizing
		-- it off the crowd instead would spill the market's traders into the
		-- houses behind it, and the author drew where the market ends.
		if authored then
			reach = authored
			inner = math.min(inner, reach * 0.55)
		end

		-- Published so the client can work out which district the player is
		-- standing in. Districts are placed procedurally from the planet's
		-- seed, so this is the only record of where this one ended up, and
		-- attributes replicate where a Lua table would not.
		zone:SetAttribute("Centre", centre)
		zone:SetAttribute("Reach", reach)

		local baseAngle = rng:NextNumber(0, math.pi * 2)
		for point = 1, points do
			local spokeAngle = baseAngle + (point - 1) * (math.pi * 2 / points)
			-- An authored district fills its rectangle rather than a circle
			-- inscribed in it, so the same fraction of the way out is a
			-- different number of studs east than it is north. The angle is
			-- untouched: the ring is also the patrol route, and a walker who
			-- doubles back has stopped patrolling.
			local half = extents[def.id]
			local position
			if half then
				local out = rng:NextNumber(inner / reach, 1)
				position = centre
					+ Vector3.new(math.cos(spokeAngle) * half.X * out, 0, math.sin(spokeAngle) * half.Z * out)
			else
				local spread = rng:NextNumber(inner, reach)
				position = centre
					+ Vector3.new(math.cos(spokeAngle) * spread, 0, math.sin(spokeAngle) * spread)
			end
			local size = Vector3.new(60, 1, 60)

			if not planet.hasWalkableGround and #anchors > 0 then
				position = anchors[rng:NextInteger(1, #anchors)]
			elseif layout then
				-- An authored town's streets are where the author drew them,
				-- so `ontoStreet`'s block arithmetic would put the crowd
				-- inside the houses. Points off the grid are left alone --
				-- those districts are already standing on open ground.
				local paved = ontoPaving(layout, origin, position)
				if paved then
					position = Vector3.new(paved.X, position.Y, paved.Z)
					size = Vector3.new(layout.cell * 0.9, 1, layout.cell * 0.9)
				end
			elseif (position - origin).Magnitude < SETTLEMENT_RADIUS then
				position, size = ontoStreet(origin, position)
			end

			-- Zero-padded because NPCService sorts these by name to build the
			-- patrol route, and Point10 sorts between Point1 and Point2 --
			-- which turns a walk round the district into a zigzag across it.
			marker(zone, `Point{string.format("%02d", point)}`, position + Vector3.new(0, 3, 0), size)
		end
	end

	--[[
		The insides of the authored buildings, as standing room in whichever
		district they were drawn in.

		Exactly what a landmark's `interior` offset does, and deliberately the
		same marker rather than a second mechanism: NPCService already reads
		every part of a zone folder as somewhere one of that district's people
		may stand, so a shop gets a shopkeeper without a line of new AI or a
		single new spawn rule. A room in no declared district gets nothing --
		it is a building on the outskirts, and inventing a district to put one
		person in would move that district's whole crowd.

		Named to sort before the ring points because that ordering is also the
		patrol route, and a route is more legible if it starts indoors and
		goes out than if it wanders in halfway round.
	]]
	for index, room in rooms do
		local zoneId: string? = nil
		for _, def in planet.zones do
			local cells = def.cells
			if
				cells
				and room.cell.X >= cells.from.X
				and room.cell.X <= cells.to.X
				and room.cell.Y >= cells.from.Y
				and room.cell.Y <= cells.to.Y
			then
				zoneId = def.id
				break
			end
		end

		if zoneId then
			marker(
				folder(zoneId, zoneRoot),
				`Inside{string.format("%02d", index)}`,
				room.at + Vector3.new(0, 3, 0),
				Vector3.new(room.size, 1, room.size)
			)
		end
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
		buildSignpost(root, origin + Vector3.new(26, 0, 26), reached)

		local roads = folder("Roads", root)
		local color, material = roadLook(planet)
		for index, place in reached do
			local bearing = place.at - origin
			local flat = Vector3.new(bearing.X, 0, bearing.Z)
			if flat.Magnitude > SETTLEMENT_RADIUS then
				pave(
					roads,
					origin + flat.Unit * (SETTLEMENT_RADIUS * 0.94),
					place.at,
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
	local rooms: { RoomSpot } = {}

	if planet.hasWalkableGround then
		local flat = flatRadiusFor(planet)
		local ground = buildGround(planet, origin, flat)
		buildRelief(planet, origin, flat, ground, rng)
		local layout = planet.layout
		if layout then
			anchors, rooms = buildFromLayout(root, planet, layout, origin, style, rng)
		else
			anchors = buildSettlement(root, planet, origin, style, rng)
		end
		buildScatter(root, planet, origin, flat, ground, style, rng)
	else
		anchors = buildVerticalCity(root, planet, origin, rng)
	end

	buildMarkers(planet, root, origin, anchors, rooms, style, rng)
end

return PlanetBuilder
