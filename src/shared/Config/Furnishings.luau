--!strict
--[[
	Furnishings.luau

	The inside of your starship, and the things you put in it.

	A hull has been a shape with a seat welded to it since ROADMAP 2c. It is
	the most expensive thing a player buys and the only one they never get to
	be *inside* of, which is the note this file answers (`note.txt`, item 1:
	"Customization on interior of spaceships"). A cabin is the one room in
	the game that is yours: nobody spawns in it, no mission sends you there,
	and nothing in it is required to finish anything.

	PURELY COSMETIC, AND SAID OUT LOUD
	No furnishing grants a stat, a discount, a heal or a flag. That is a
	decision and not an omission. This project's own rule is that a stat
	named in `Progression.LIVE_STATS` must have a reader, and the inverse is
	the same rule: a bunk that quietly restores health is a bunk the player
	has to sleep in before every mission, which turns a room you chose into
	a chore you perform. Wanting the Dejarik table is the whole mechanic.

	FOUR SLOTS, ONE ITEM EACH
	A slot is a place in the room; a furnishing declares which slot it fills.
	One at a time, replaced rather than accumulated, which is what makes this
	a choice: an inventory of thirty ornaments all placed at once is a
	warehouse, and a warehouse is not a decision about who you are.

	SLOTS ARE FRACTIONS OF THE ROOM, NOT COORDINATES
	`SlotDef.at` is measured in room-halves: (-0.5, 0.5) is the far left
	corner and (0, 0) the middle of the floor. Three cabins of three sizes
	therefore share one set of slots and one catalogue, and a bigger hull
	simply spreads them further apart. Absolute coordinates would have meant
	every furnishing declaring a position per cabin, and a Dejarik table
	standing in the wall of the one hull nobody tested.
]]

local Palette = require(script.Parent.Palette)

local Furnishings = {}

local V3 = Vector3.new

--[[
	The key that puts you inside your ship, and back out again.

	Declared here for the reason `Ships.SUMMON_KEY` is declared in Ships: the
	client binds it and the HUD legend advertises it, and a door nobody was
	told about is a room nobody enters. This project has shipped that exact
	bug twice ("finished but unreachable is not finished", 2026-08-17).

	H, for hatch. V summons, W A S D walk, 1-6 are abilities and B/G/J/K/M
	are the panels.
]]
Furnishings.BOARD_KEY = Enum.KeyCode.H
Furnishings.BOARD_HINT = "CABIN"

--[[
	How near your own hull you must stand to board it.

	Generous on purpose. The alternative to a wide radius is a player circling
	their own freighter looking for the door, and there is no door -- the hull
	is a solid shell with no interior geometry, which is exactly why boarding
	is a teleport rather than a walk through a hatch.
]]
Furnishings.BOARD_RANGE = 30

export type FurnishingPart = {
	name: string,
	shape: string?, -- "Block" | "Cylinder" | "Ball" | "Wedge"
	size: Vector3,
	offset: Vector3, -- studs from the slot anchor, +Y up, facing -Z
	rot: Vector3?, -- euler degrees
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
}

export type SlotDef = {
	id: string,
	displayName: string,
	--[[
		Where in the room, in halves. X and Z run -0.5 to 0.5 across the
		floor; Y is ignored -- everything stands on the deck, and a
		furnishing that hangs declares that in its own part offsets.
	]]
	at: Vector3,
	--[[
		Degrees of yaw. 0 faces the nose of the ship, which is -Z.

		A piece against a wall faces *away* from it, which is the whole of
		why this field exists: a bunk's local -Z is its open side, and the
		open side of a bunk pushed against the port wall points to
		starboard. Getting the sign backwards points the furniture into
		the hull, and everything that overhangs -- a krayt skull's horns,
		a console's screens -- overhangs through the wall.
	]]
	facing: number,
}

export type FurnishingDef = {
	id: string,
	displayName: string,
	description: string,
	slot: string,
	cost: number,
	requiredLevel: number,
	parts: { FurnishingPart },
}

export type CabinDef = {
	id: string,
	displayName: string,
	description: string,
	--- Interior clear space in studs: width (X), height (Y), length (Z).
	size: Vector3,
}

--------------------------------------------------------------------------------
-- The rooms
--------------------------------------------------------------------------------

--[[
	One cabin per hull, and the hull you fly is the room you get.

	Keyed by ship id rather than by a `cabin` field on `ShipDef`, because a
	cabin is not a fact about how a ship flies and Ships.luau is already the
	longest config in the project. `forShip` falls back to the smallest, so
	a hull added tomorrow has an inside on the day it is added.
]]
local cabins: { [string]: CabinDef } = {
	SkipjackCourier = {
		id = "CourierCabin",
		displayName = "Courier Berth",
		description = "One room behind the cockpit bulkhead. You can touch both walls without moving your feet.",
		size = V3(16, 11, 22),
	},
	LonghaulFreighter = {
		id = "FreighterHold",
		displayName = "Freighter Hold",
		description = "A cargo hold with a bunk in it, which is what every freighter crew has ever lived in.",
		size = V3(28, 14, 40),
	},
	DaggerInterceptor = {
		id = "InterceptorCabin",
		displayName = "Interceptor Cabin",
		description = "Czerka's brochure calls it a stateroom. It is the space left over behind the reactor.",
		size = V3(18, 12, 24),
	},
}

local DEFAULT_CABIN: CabinDef = cabins.SkipjackCourier

--- The cabin inside `shipId`, whatever it is.
function Furnishings.cabinFor(shipId: string): CabinDef
	return cabins[shipId] or DEFAULT_CABIN
end

--------------------------------------------------------------------------------
-- The slots
--------------------------------------------------------------------------------

--[[
	Ordered, because this is also the order the inventory panel lists them in
	and "where you sleep" before "what you hung on the wall" is the order
	anyone would furnish a room in.
]]
Furnishings.SLOTS = {
	-- Port wall, opening to starboard.
	{ id = "Berth", displayName = "Berth", at = V3(-0.32, 0, 0.28), facing = -90 },
	{ id = "Table", displayName = "Table", at = V3(0, 0, 0), facing = 0 },
	-- Against the forward bulkhead, so it reads as the thing you would be
	-- looking at if the cabin had a viewport. It does; the builder puts one
	-- there.
	{ id = "Console", displayName = "Console", at = V3(0, 0, -0.36), facing = 180 },
	-- Starboard wall, opening to port.
	{ id = "Trophy", displayName = "Trophy", at = V3(0.34, 0, 0.3), facing = 90 },
} :: { SlotDef }

function Furnishings.slot(id: string): SlotDef?
	for _, slot in Furnishings.SLOTS do
		if slot.id == id then
			return slot
		end
	end
	return nil
end

--[[
	Where a slot's furnishing stands, relative to the middle of the cabin
	floor.

	Lives in config rather than in CabinBuilder because `validate` measures
	against exactly this transform. A builder with a private copy of the
	arithmetic is a builder that can disagree with the check that is
	supposed to be catching it -- the same reason `Planets.TOWER_GRID` is
	shared with the traffic lanes rather than restated in both.
]]
function Furnishings.anchorFor(cabin: CabinDef, slot: SlotDef): CFrame
	return CFrame.new(slot.at.X * cabin.size.X, 0, slot.at.Z * cabin.size.Z)
		* CFrame.Angles(0, math.rad(slot.facing), 0)
end

--------------------------------------------------------------------------------
-- The catalogue
--------------------------------------------------------------------------------

local defs: { [string]: FurnishingDef } = {}

local function def(f: FurnishingDef): FurnishingDef
	defs[f.id] = f
	return f
end

--- A slab on legs: the shape most furniture in this file is a variation of.
local function slab(
	name: string,
	size: Vector3,
	at: Vector3,
	colour: Color3,
	material: Enum.Material
): FurnishingPart
	return { name = name, size = size, offset = at, color = colour, material = material }
end

--------------------------------------------------------------------------------
-- Berths
--------------------------------------------------------------------------------

def({
	id = "SpacerBunk",
	displayName = "Spacer's Bunk",
	description = "A frame, a pad, and a strap so you stay in it when the artificial gravity stutters.",
	slot = "Berth",
	cost = 600,
	requiredLevel = 1,
	parts = {
		slab("Frame", V3(6.4, 0.6, 3), V3(0, 1.4, 0), Palette.Gunmetal, Enum.Material.Metal),
		slab("Mattress", V3(6, 0.5, 2.6), V3(0, 1.95, 0), Palette.RebelTan, Enum.Material.Fabric),
		slab("LegFore", V3(0.4, 1.4, 0.4), V3(-2.8, 0.7, 0), Palette.DarkMetal, Enum.Material.Metal),
		slab("LegAft", V3(0.4, 1.4, 0.4), V3(2.8, 0.7, 0), Palette.DarkMetal, Enum.Material.Metal),
		slab("Strap", V3(0.4, 0.1, 2.8), V3(0, 2.2, 0), Palette.SmugglerBrown, Enum.Material.Fabric),
	},
})

def({
	id = "HuttSilkBerth",
	displayName = "Nal Hutta Silk Berth",
	description = "Upholstered by somebody who has never slept in a ship. Wide enough that you notice how narrow everything else is.",
	slot = "Berth",
	cost = 5200,
	requiredLevel = 18,
	parts = {
		slab("Base", V3(7, 1.6, 4), V3(0, 0.8, 0), Palette.CopperTrim, Enum.Material.Wood),
		slab("Cushion", V3(6.6, 0.8, 3.6), V3(0, 1.9, 0), Palette.NabooRoyal, Enum.Material.Fabric),
		slab("Bolster", V3(1.2, 1.2, 3.6), V3(-2.9, 2.6, 0), Palette.NabooRoyal, Enum.Material.Fabric),
		slab("Canopy", V3(7, 0.3, 4.2), V3(0, 5.4, 0), Palette.CopperTrim, Enum.Material.Metal),
		slab("PostFore", V3(0.3, 3.6, 0.3), V3(-3.2, 3.6, -1.8), Palette.CopperTrim, Enum.Material.Metal),
		slab("PostAft", V3(0.3, 3.6, 0.3), V3(3.2, 3.6, -1.8), Palette.CopperTrim, Enum.Material.Metal),
	},
})

def({
	id = "MeditationSlab",
	displayName = "Meditation Slab",
	description = "Bare stone, cut on Tython and shipped at ruinous cost by people who would tell you the cost is the point.",
	slot = "Berth",
	cost = 3400,
	requiredLevel = 12,
	parts = {
		slab("Slab", V3(6, 1.2, 3.2), V3(0, 0.6, 0), Palette.NabooStone, Enum.Material.Slate),
		slab("Mat", V3(5.4, 0.2, 2.8), V3(0, 1.3, 0), Palette.JediBrown, Enum.Material.Fabric),
		{
			name = "Lamp",
			shape = "Ball",
			size = V3(0.8, 0.8, 0.8),
			offset = V3(0, 2.4, -1.4),
			color = Palette.SaberBlue,
			material = Enum.Material.Neon,
		},
	},
})

--------------------------------------------------------------------------------
-- Tables
--------------------------------------------------------------------------------

def({
	id = "CrateTable",
	displayName = "Crate and Two Drums",
	description = "A shipping crate on its end with the manifest still stencilled on it. Everybody's first table.",
	slot = "Table",
	cost = 250,
	requiredLevel = 1,
	parts = {
		slab("Crate", V3(3.4, 2.4, 3.4), V3(0, 1.2, 0), Palette.RebelTan, Enum.Material.WoodPlanks),
		{
			name = "DrumLeft",
			shape = "Cylinder",
			size = V3(1.8, 1.6, 1.6),
			offset = V3(-3, 0.9, 0),
			rot = V3(0, 0, 90),
			color = Palette.WornSteel,
			material = Enum.Material.CorrodedMetal,
		},
		{
			name = "DrumRight",
			shape = "Cylinder",
			size = V3(1.8, 1.6, 1.6),
			offset = V3(3, 0.9, 0),
			rot = V3(0, 0, 90),
			color = Palette.WornSteel,
			material = Enum.Material.CorrodedMetal,
		},
	},
})

def({
	id = "DejarikTable",
	displayName = "Dejarik Table",
	description = "A holochess board with a stuck rotary. Whoever owned it last left a game unfinished, and it is losing.",
	slot = "Table",
	cost = 4800,
	requiredLevel = 14,
	parts = {
		{
			name = "Pedestal",
			shape = "Cylinder",
			size = V3(2.2, 1.6, 1.6),
			offset = V3(0, 1.1, 0),
			rot = V3(0, 0, 90),
			color = Palette.Gunmetal,
			material = Enum.Material.Metal,
		},
		{
			name = "Board",
			shape = "Cylinder",
			size = V3(0.5, 5.6, 5.6),
			offset = V3(0, 2.2, 0),
			rot = V3(0, 0, 90),
			color = Palette.DarkMetal,
			material = Enum.Material.Metal,
		},
		{
			name = "Grid",
			shape = "Cylinder",
			size = V3(0.15, 5, 5),
			offset = V3(0, 2.5, 0),
			rot = V3(0, 0, 90),
			color = Palette.SaberBlue,
			material = Enum.Material.Neon,
			transparency = 0.35,
		},
		{
			name = "Piece",
			size = V3(0.5, 0.9, 0.5),
			offset = V3(1.2, 3, -0.8),
			color = Palette.SaberBlue,
			material = Enum.Material.Neon,
			transparency = 0.25,
		},
	},
})

def({
	id = "SabaccTable",
	displayName = "Sabacc Table",
	description = "Felt, a card shoe, and a scorch mark where somebody settled an argument about the shoe.",
	slot = "Table",
	cost = 1600,
	requiredLevel = 6,
	parts = {
		slab("Top", V3(6, 0.4, 4), V3(0, 2.4, 0), Palette.RebelOlive, Enum.Material.Fabric),
		slab("Rim", V3(6.4, 0.3, 4.4), V3(0, 2.2, 0), Palette.SmugglerBrown, Enum.Material.Wood),
		slab("LegLeft", V3(0.5, 2.2, 0.5), V3(-2.5, 1.1, 0), Palette.DarkMetal, Enum.Material.Metal),
		slab("LegRight", V3(0.5, 2.2, 0.5), V3(2.5, 1.1, 0), Palette.DarkMetal, Enum.Material.Metal),
		slab("Shoe", V3(1.2, 0.7, 0.9), V3(2, 2.9, 0.9), Palette.DroidSilver, Enum.Material.Metal),
	},
})

--------------------------------------------------------------------------------
-- Consoles
--------------------------------------------------------------------------------

def({
	id = "NavConsole",
	displayName = "Navigator's Console",
	description = "Charts, a coffee ring, and the jump you have not committed to yet.",
	slot = "Console",
	cost = 900,
	requiredLevel = 1,
	parts = {
		slab("Desk", V3(7, 0.5, 2.4), V3(0, 2.6, 0), Palette.Gunmetal, Enum.Material.Metal),
		slab("Riser", V3(6.6, 2.4, 0.6), V3(0, 1.4, 0.8), Palette.DarkMetal, Enum.Material.Metal),
		slab("Screen", V3(5, 2.2, 0.3), V3(0, 4, 0.9), Palette.CoruscantLight, Enum.Material.Neon),
		slab("Keys", V3(4, 0.2, 1.2), V3(0, 2.9, -0.4), Palette.DarkMetal, Enum.Material.Metal),
	},
})

def({
	id = "HolomapPlinth",
	displayName = "Holomap Plinth",
	description = "A galaxy the size of a dinner table, one tenth of it lit. The lit tenth is the part anybody still flies to.",
	slot = "Console",
	cost = 7500,
	requiredLevel = 22,
	parts = {
		{
			name = "Plinth",
			shape = "Cylinder",
			size = V3(2.6, 3.4, 3.4),
			offset = V3(0, 1.3, 0),
			rot = V3(0, 0, 90),
			color = Palette.Gunmetal,
			material = Enum.Material.Metal,
		},
		{
			name = "Galaxy",
			shape = "Ball",
			size = V3(4.6, 4.6, 4.6),
			offset = V3(0, 4.6, 0),
			color = Palette.SaberBlue,
			material = Enum.Material.Neon,
			transparency = 0.55,
		},
		{
			name = "Core",
			shape = "Ball",
			size = V3(1, 1, 1),
			offset = V3(0, 4.6, 0),
			color = Palette.SaberWhite,
			material = Enum.Material.Neon,
		},
	},
})

def({
	id = "SliceRig",
	displayName = "Slicer's Rig",
	description = "Three screens, none of them showing anything you would want logged. Popular with Scrappers and with nobody's port authority.",
	slot = "Console",
	cost = 3200,
	requiredLevel = 10,
	parts = {
		slab("Desk", V3(7.5, 0.5, 2.6), V3(0, 2.6, 0), Palette.DarkMetal, Enum.Material.DiamondPlate),
		slab("ScreenLeft", V3(2.2, 1.8, 0.2), V3(-2.4, 3.9, 0.8), Palette.BlasterGreen, Enum.Material.Neon),
		slab("ScreenMid", V3(2.4, 2, 0.2), V3(0, 4, 1), Palette.BlasterGreen, Enum.Material.Neon),
		slab("ScreenRight", V3(2.2, 1.8, 0.2), V3(2.4, 3.9, 0.8), Palette.BlasterGreen, Enum.Material.Neon),
		slab("Tower", V3(1.4, 2.2, 1.4), V3(3.4, 1.1, -0.4), Palette.Gunmetal, Enum.Material.Metal),
	},
})

--------------------------------------------------------------------------------
-- Trophies
--------------------------------------------------------------------------------

def({
	id = "ToolRack",
	displayName = "Tool Rack",
	description = "Hydrospanners in order of size, which is either professionalism or the only thing aboard you control.",
	slot = "Trophy",
	cost = 400,
	requiredLevel = 1,
	parts = {
		slab("Board", V3(4.4, 3.4, 0.3), V3(0, 3.2, 0), Palette.WornSteel, Enum.Material.Metal),
		slab("SpannerBig", V3(0.4, 2.2, 0.3), V3(-1.4, 3.4, -0.3), Palette.DroidSilver, Enum.Material.Metal),
		slab("SpannerMid", V3(0.35, 1.8, 0.3), V3(0, 3.2, -0.3), Palette.DroidSilver, Enum.Material.Metal),
		slab("SpannerSmall", V3(0.3, 1.4, 0.3), V3(1.3, 3, -0.3), Palette.DroidSilver, Enum.Material.Metal),
	},
})

def({
	id = "KraytSkull",
	displayName = "Krayt Skull",
	description = "Bought in Anchorhead from a man who swears he killed it. He did not, and neither did you.",
	slot = "Trophy",
	cost = 2800,
	requiredLevel = 8,
	parts = {
		slab("Mount", V3(3, 0.6, 0.6), V3(0, 3.4, 0), Palette.SmugglerBrown, Enum.Material.Wood),
		slab("Skull", V3(2.6, 2.2, 3.4), V3(0, 4.6, -1.2), Palette.TatooineRock, Enum.Material.Sand),
		slab("HornLeft", V3(0.5, 2.6, 0.5), V3(-1, 6.2, -1.4), Palette.SandtrooperTan, Enum.Material.Sand),
		slab("HornRight", V3(0.5, 2.6, 0.5), V3(1, 6.2, -1.4), Palette.SandtrooperTan, Enum.Material.Sand),
	},
})

def({
	id = "AstromechDock",
	displayName = "Astromech Dock",
	description = "A charging cradle with an occupant who does not talk about where the last owner went.",
	slot = "Trophy",
	cost = 6400,
	requiredLevel = 20,
	parts = {
		slab("Cradle", V3(3.4, 0.8, 3.4), V3(0, 0.4, 0), Palette.DarkMetal, Enum.Material.DiamondPlate),
		{
			name = "Body",
			shape = "Cylinder",
			size = V3(3.6, 2.4, 2.4),
			offset = V3(0, 2.2, 0),
			rot = V3(0, 0, 90),
			color = Palette.DroidWhiteBlue,
			material = Enum.Material.Metal,
		},
		{
			name = "Dome",
			shape = "Ball",
			size = V3(2.4, 2.4, 2.4),
			offset = V3(0, 4, 0),
			color = Palette.AstromechBlue,
			material = Enum.Material.Metal,
		},
		{
			name = "Eye",
			shape = "Cylinder",
			size = V3(0.3, 0.8, 0.8),
			offset = V3(0, 4.2, -1.1),
			rot = V3(0, 90, 0),
			color = Palette.SaberBlue,
			material = Enum.Material.Neon,
		},
	},
})

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Furnishings.get(id: string): FurnishingDef
	local d = defs[id]
	assert(d, `Furnishings.get: unknown furnishing "{id}"`)
	return d
end

function Furnishings.exists(id: string): boolean
	return defs[id] ~= nil
end

function Furnishings.all(): { [string]: FurnishingDef }
	return defs
end

function Furnishings.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

--- The half-size of `size` after `rot`, on each world axis.
local function halfExtent(cf: CFrame, size: Vector3): Vector3
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) * 0.5
end

--- Half a stud, so a piece flush with a wall is not a piece inside it.
local CLEARANCE = 0.5

--[[
	Checks the catalogue against the room it has to fit in.

	The failure worth catching here is silent and only visible from inside
	one particular hull: a bunk half a stud too long is a bunk sticking
	through the wall of the courier, which is the ship most players buy
	first and the one this is measured against.

	Measured *through the slot's own anchor*, not as a bare footprint. A
	berth is six studs long and stands in a cabin sixteen wide, which sounds
	fatal and is not, because the berth is turned side-on to the wall it is
	pushed against. Checking width against width instead of checking the
	placed box against the room condemns almost every piece in this file.
]]
function Furnishings.validate(): { string }
	local problems: { string } = {}

	-- The tightest room anything has to fit in. Bigger cabins are safe by
	-- construction: a slot is a fraction of the room, so a longer hull moves
	-- the same furniture further from the same walls.
	local smallest = DEFAULT_CABIN
	for _, cabin in cabins do
		if cabin.size.X * cabin.size.Z < smallest.size.X * smallest.size.Z then
			smallest = cabin
		end
	end
	local room = smallest.size

	for id, d in defs do
		if d.cost < 0 then
			table.insert(problems, `Furnishings: "{id}" has a negative cost`)
		end
		if #d.parts == 0 then
			table.insert(problems, `Furnishings: "{id}" has no parts and would be invisible`)
		end

		local slot = Furnishings.slot(d.slot)
		if not slot then
			table.insert(problems, `Furnishings: "{id}" fills unknown slot "{d.slot}"`)
			continue
		end

		-- The box every part of this piece fits in, in its own axes.
		local min = Vector3.new(math.huge, math.huge, math.huge)
		local max = -min
		for _, p in d.parts do
			local r = p.rot or Vector3.zero
			local cf = CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
			-- Rotation-aware, for the same reason Ships.validate is: half the
			-- furniture in this file is a cylinder lying on its side, and
			-- reading `size.Y` off one of those understates it by its length.
			local half = halfExtent(cf, p.size)
			min = min:Min(p.offset - half)
			max = max:Max(p.offset + half)
		end

		local anchor = Furnishings.anchorFor(smallest, slot)
		local centre = anchor:PointToWorldSpace((min + max) * 0.5)
		local half = halfExtent(anchor.Rotation, max - min)
		local lo, hi = centre - half, centre + half

		if lo.X < -room.X * 0.5 + CLEARANCE or hi.X > room.X * 0.5 - CLEARANCE then
			table.insert(
				problems,
				`Furnishings: "{id}" in the {slot.id} slot reaches through the side wall of the {smallest.id}`
			)
		end
		if lo.Z < -room.Z * 0.5 + CLEARANCE or hi.Z > room.Z * 0.5 - CLEARANCE then
			table.insert(
				problems,
				`Furnishings: "{id}" in the {slot.id} slot reaches through a bulkhead of the {smallest.id}`
			)
		end
		if hi.Y > room.Y - CLEARANCE then
			table.insert(
				problems,
				`Furnishings: "{id}" stands {hi.Y} tall and would go through the ceiling of the {smallest.id}`
			)
		end
		if lo.Y < -CLEARANCE then
			table.insert(problems, `Furnishings: "{id}" hangs below the deck of the {smallest.id}`)
		end
	end

	table.sort(problems)
	return problems
end

return Furnishings
