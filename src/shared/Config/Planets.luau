--!strict
--[[
	Planets.luau

	The galaxy: every world, its atmosphere, its gravity, who controls it, and
	who you meet when you land.

	TRAVEL ECONOMY
	Two ways to cross the galaxy, deliberately different in cost:
	  - Flying it yourself is free in credits but burns fuel, and fuel scales
	    with real distance between `coords`. Long hauls are a decision.
	  - Fast travel skips the flight and charges credits instead.
	That split means a rich player buys time and a poor player spends it, which
	is the trade a sandbox should be offering.

	GRAVITY
	Per-planet, in studs/sec^2. Roblox's default is 196.2. Low gravity is not
	decoration -- it changes jump height and fall damage, so Kamino's platforms
	and Hoth's ravines play differently from Tatooine's flats.
]]

local Palette = require(script.Parent.Palette)
--[[
	Required outright, which is safe in this direction only.

	NPCArchetypes pulls Species, Costumes and Weapons, none of which touch this
	file, so there is no cycle -- but the reverse is not true, which is why
	`rollLevel` and `hostileIn` over there take bare structural types rather
	than importing ours.

	Worth the edge for two things a string could not do: `Behavior.Aggressive`
	in the spawn tables below is a constant the checker sees rather than a
	spelling nobody verifies, and `validate` can compare an archetype's level
	range against the band of the district it was placed in.
]]
local NPCArchetypes = require(script.Parent.NPCArchetypes)
-- Pulls Types and nothing else, so it is safe from anywhere. Used by the XP
-- budget check in `validate`, which is the only place the curve and the world
-- are ever compared.
local Progression = require(script.Parent.Progression)

local Planets = {}

Planets.DEFAULT_GRAVITY = 196.2

--[[
	How wide one district's level band is, as a fraction of the planet's range.

	Wide enough that a district holds a mix rather than a rank of identical
	enemies, and narrow enough that the next one out is noticeably worse. A
	quarter also makes consecutive bands overlap, so the step between districts
	is a slope and not a cliff -- you meet the top of the next band before you
	leave the current one.
]]
Planets.BAND_WIDTH = 0.25

--- No band is narrower than this, however short the planet's level range.
Planets.BAND_MIN_WIDTH = 2

--[[
	How far above the player a district's floor has to be before the game says
	something.

	Three, because two is an ordinary fight you might win and four is one you
	have already lost. The point is to interrupt *before* the death, which is
	the whole complaint this exists to answer: the old world killed you first
	and explained afterwards, if at all.
]]
Planets.UNDERLEVELLED_BY = 3

--[[
	How far apart two worlds sit in the one shared Workspace.

	Every planet is built into the same place at a different address, far
	enough apart that no two are ever in the same streaming region.
	`Planets.originFor` turns an id into that address.
]]
Planets.WORLD_SPACING = 12000

--[[
	The vertical city's grid, in studs. Client-visible on purpose.

	`PlanetBuilder.buildVerticalCity` stands its towers on multiples of
	`TOWER_GRID` and cantilevers their landing platforms at multiples of
	`SKYLANE_STEP` in Y. Those two numbers are the whole shape of Coruscant,
	and until the sky had traffic in it only the builder needed to know them.

	`SkyTrafficController` now flies between those towers, on the client,
	from the same two constants -- which is the reason they moved out of
	PlanetBuilder and into config. A lane spacing privately agreed by one
	side is how a hundred airspeeders end up flying through the buildings.
]]
Planets.TOWER_GRID = 240
Planets.SKYLANE_STEP = 220

--[[
	How many tower rows stand either side of the middle.

	Was a literal `5` in `buildVerticalCity` and a private `LANE_SPREAD = 5`
	in `SkyTrafficController`, which is the same disagreement `TOWER_GRID`
	moved here to prevent -- widening one without the other either empties
	the outskirts of traffic or flies a lane past the last building.

	Raised from 5 to 8 on 2026-08-29. At 5 the skyline was 2,640 studs across
	in total, and once the middle 800 of that became walkable decks the
	remaining city was two rings deep: you could see the edge of the world
	from the street. Eight puts the far towers 1,920 studs out, which is past
	the point Coruscant's own haze has finished with them.
]]
Planets.TOWER_REACH = 8

--[[
	How far out a world's ground reaches, in studs. Client-visible for the
	same reason `TOWER_GRID` is.

	`SETTLEMENT_RADIUS` is the radius of one district; `PlanetBuilder` puts a
	district centre at `ZoneDef.distance * SETTLEMENT_RADIUS`, fills level
	terrain out to `Planets.groundRadius`, and rings the relief through the
	`RELIEF_MARGIN` band beyond that. `Planets.worldRadius` is where the land
	stops entirely.

	The client needs `worldRadius` to answer a question the ground never had
	to ask: **am I high above the world, or have I flown off the side of it?**
	A downward ray answers neither on its own -- past the rim it finds nothing
	at fifty studs exactly as it finds nothing at nine hundred. Horizontal
	distance from `Planets.originFor` separates the two, and it only works if
	both sides measure the plate the same way.
]]
Planets.SETTLEMENT_RADIUS = 520
Planets.RELIEF_MARGIN = 450

export type SpawnRule = {
	archetype: string,
	count: number,
	-- Where they belong. The world builder resolves these against tagged zones
	-- in the map rather than scattering NPCs at random, which is what made the
	-- old version's crowds feel like debris.
	zone: string?,
	behavior: string?, -- overrides the archetype's default
	--[[
		A named character from Config/Cast.luau rather than one of a crowd.

		Never written in the tables below: `Cast.onPlanet` builds these rules,
		and NPCService spawns them alongside the planet's own. It lives on the
		rule anyway because respawn is scheduled from a rule, and a rule that
		forgot it was Overseer Vashk would bring him back as an anonymous Sith
		Lord who attacks his own student.
	]]
	cast: string?,
	--[[
		Stand inside this landmark, rather than anywhere in the district.

		A zone is normally the right unit -- a merchant belongs in the market
		and it does not matter which end of it. It is the wrong unit when the
		whole point of the NPC is *where he is*: the ship broker only makes
		sense on the landing field, and Anchorhead's landing field is a
		building at one edge of a district with thirty-two other people in it,
		so a rule that named only "Town" would put the one man who sells
		starships anywhere but the pad.

		Names a point of interest on this same planet. `validate` requires
		that it is not `drawn` and that it sits in `zone`: a drawn place has
		no building of its own to have an inside, and its district *is* the
		landmark, so the zone alone already says everything this field could.
	]]
	poi: string?,
}

--- An inclusive level range. See `Planets.bandFor`.
export type Band = { min: number, max: number }

--[[
	A district of a planet, and how far out of town it sits.

	`distance` is a multiple of the settlement radius: 0 is the middle of town,
	1 its edge, and anything above that is wilderness. It exists because the
	world builder used to derive a zone's ring from the order its first spawn
	rule happened to be declared -- which put Tatooine's Wastes downtown and
	its town out in the desert, and dropped twelve aggressive Tusken Raiders
	on a level 1 player's spawn point.

	Distance is also the difficulty dial -- and since 2026-08-16 it is one in
	fact and not just in intent. `Planets.bandFor` turns it into the level range
	of everything that spawns in the district, so walking outward *is* walking
	into harder things rather than merely being supposed to.
]]
--[[
	A rectangle of layout cells, inclusive at both ends.

	Column then row, 1-based, matching the way the grid below is written:
	`from = Vector2.new(4, 2)` is the fourth character of the second string.
]]
export type CellRect = {
	from: Vector2,
	to: Vector2,
}

--[[
	A settlement drawn as a picture instead of rolled from a seed.

	`PlanetBuilder` has always laid towns out radially: rings of blocks around
	a centre, jittered by a Random. That reads as a *place* from the ground
	but it cannot be authored -- you cannot put the cantina across the street
	from the spaceport, or run one long road the whole way through, because
	nobody decides where anything goes.

	A `layout` is a picture of the town, one character per `cell` studs, north
	at the top and west at the left. Row 1 column 1 is the north-west corner;
	`grid[2]:sub(4, 4)` is the cell at column 4, row 2, which is why `CellRect`
	is written column-then-row against everything Lua usually does.

	The grid is centred on the settlement origin, so an odd-sized grid has a
	cell exactly on it and an even-sized one has a corner there. `legend` maps
	each glyph to a prefab id in `PlanetBuilder.PREFABS`; a glyph that appears
	in the grid and not in the legend is open ground, which is how roads,
	plazas and the desert outside the walls are all written as spaces.

	Only worlds with a `layout` use any of this. The other eight keep the
	radial generator, and are meant to -- an authored grid is worth writing
	for a town you want to remember the shape of, and a waste of a day for a
	mining camp seen once.
]]
export type LayoutDef = {
	cell: number,
	legend: { [string]: string },
	grid: { string },
}

--[[
	One walkable storey of a world whose ground is built rather than filled.

	Coruscant is the whole reason this exists. `hasWalkableGround = false` was
	doing two unrelated jobs at once: "lay no terrain", which is right, and
	"have no districts", which is what left the capital as 121 towers with
	90x90 slabs cantilevered off them at random bearings. Nothing connected
	them, nothing had an inside, and the planet's ~160 people and all six of
	its points of interest were standing on them. Reported from a play test in
	four words: *"I can't go anywhere."*

	A deck splits the two meanings apart. `hasWalkableGround` keeps the real
	one -- no `FillCylinder`, no relief, no scatter -- and a `decks` list says
	the surface is authored plates instead. Each deck is one district, drawn
	with the same ASCII `LayoutDef` that Anchorhead, Taris and Nar Shaddaa
	already use, so every deck gets streets, buildings with walk-in interiors,
	crowds and patrol routes through code that was already there. The one
	thing it adds is `y`.

	Ordered so that **down is dangerous**, which is not a new rule: it falls
	straight out of `ZoneDef.distance` and `Planets.bandFor`. The Senate
	district is the top deck and the lowest-levelled; the Underlevels are the
	bottom deck and the highest. "The lower you go, the more ghetto it gets"
	is therefore a fact about the level bands and not just about the paint.
]]
export type DeckDef = {
	-- Must name a `ZoneDef` on the same planet. `validate` says so, because
	-- a deck whose zone is a typo builds a whole storey nobody spawns on.
	zone: string,
	-- Height above the planet origin, in studs. `SKYLANE_STEP` apart, so the
	-- towers' window bands and the decks line up rather than nearly doing so.
	y: number,
	layout: LayoutDef,
}

export type ZoneDef = {
	id: string,
	distance: number,
	--[[
		Where this district is, when the planet has an authored layout.

		`distance` puts a district on a compass fan at a radius, which is the
		right answer for wilderness -- the Dune Sea is "far out that way" and
		nothing more needs saying. It is the wrong answer for anywhere inside
		a town, where the market being *east of the plaza and north of the
		docks* is the whole point and a fan cannot express it.

		So both live here: a district with `cells` is a rectangle of the grid
		and its centre is that rectangle's centre; a district without keeps
		its ring. Outer districts are deliberately left on `distance`, because
		authoring a 3,000-stud desert as characters would be typing sand.
	]]
	cells: CellRect?,
	--[[
		The level range here, when distance alone gets it wrong.

		Almost always nil. `bandFor` spreads the planet's own `minLevel`..
		`maxLevel` across its districts by distance, which is right whenever
		difficulty and remoteness agree -- and they were authored to agree, so
		45 hand-written pairs would say the same thing as the dial already
		does, and then drift from it the first time a zone moved.

		Worth writing out when they genuinely disagree: somewhere close to
		town that is dangerous anyway, or a far district that is only scenery
		until much later.
	]]
	band: Band?,
}

export type PointOfInterest = {
	id: string,
	displayName: string,
	kind: string, -- "Spaceport" | "Cantina" | "Market" | "Base" | "Temple" | "Ruin" | "Outpost"
	description: string,
	-- What gets built here, when `kind` is too broad to draw. Both Tatooine's
	-- sandcrawler and the hull out in the Dune Sea are Ruins, and they should
	-- not look alike. Defaults to `kind`.
	landmark: string?,
	-- The district this place stands in. Without it the point of interest is
	-- dropped on an arbitrary circle with nothing around it, so a mission can
	-- send you to a "Jawa crawler they live in still" that has no Jawas.
	zone: string?,
	--[[
		This place is already on the page: build nothing, only name it.

		A landmark is normally a building the world builder puts down on a
		yard it claims, and anything wider than half a city block cannot fit
		in one -- so it is pushed out past the last street instead. That is
		the right answer for a spaceport and the wrong one for a Sith
		academy, which is not a building standing in a district but the
		district itself. Korriban's would have ended up six hundred studs
		north of the Academy Grounds, with the students still in the grounds.

		Set it and the point of interest is only its name, its sign and its
		waypoint; the district's own `cells` say where it is. Requires a
		layout and a zone with `cells`, both checked at boot -- without them
		there is nothing on the page to have drawn it, and the result is a
		named place with no building anywhere, which is the bug this whole
		mechanism exists to prevent.
	]]
	drawn: boolean?,
}

--[[
	An extra star in the sky.

	Roblox's Lighting has exactly one real sun, driven by ClockTime, so a binary
	system's second star has to be a rendered body rather than a light source.
	`yaw` and `pitch` are its offset from the true sun in degrees -- which is
	what gives it its own rise and set times rather than making it a decal
	stapled to the first one.
]]
export type CompanionSun = {
	yaw: number,
	pitch: number,
	sizeDegrees: number,
	color: Color3,
}

export type PlanetDef = {
	id: string,
	displayName: string,
	description: string,

	-- Galaxy map ---------------------------------------------------------
	-- Arbitrary units; only relative distance matters. Roughly mirrors the
	-- canon Core-to-Outer-Rim layout so the map reads correctly.
	coords: Vector3,
	region: string, -- "Core" | "Inner Rim" | "Mid Rim" | "Outer Rim"

	-- Environment ---------------------------------------------------------
	gravity: number,
	terrain: string, -- "Desert" | "Ice" | "Urban" | "Swamp" | "Ocean" | "Volcanic" | "Forest"
	--[[
		How this world *builds*, which is not what its ground is made of.

		Until 2026-08-15 `PlanetBuilder` picked a building style from `terrain`
		alone, so Korriban and Tatooine — both "Desert" — ran identical
		geometry in different sand, and Coruscant, Taris and Nar Shaddaa were
		one style between them. Nine worlds shared five looks and the boys
		spotted it in the first ten minutes.

		One of: "Adobe" | "SithZiggurat" | "Ruin" | "NeonStack" | "Spire"
		      | "Frontier" | "JediStone" | "IceBunker" | "ImperialGothic"
		Each is a separate shape function in `PlanetBuilder.ARCHITECTURE`, not
		just a palette. Adding one means adding it there too; PlanetBuilder
		warns about an unknown name when it loads, not when you fly there.
	]]
	architecture: string,
	groundColor: Color3,
	rockColor: Color3?,

	--[[
		The Roblox terrain material this world's land is made of.

		Required on every world with `hasWalkableGround`, and **no two of them
		may share one**, which is a stranger rule than it looks and the reason
		this is a declared field rather than a lookup from `terrain`.

		There is exactly one `Workspace.Terrain` for the whole place and
		`Terrain:SetMaterialColor` is a property *of that instance*, not of a
		region. Tatooine and Korriban are both "Desert", so a lookup by terrain
		kind would give them both Sand — and whichever world was walked into
		second would repaint the first one's dunes. The failure is silent,
		remote, and only visible after travelling twice, which is the worst
		combination this codebase has. `validate` refuses it instead.
	]]
	terrainMaterial: Enum.Material?,
	skyTint: Color3,
	fogColor: Color3,
	fogStart: number,
	fogEnd: number,
	ambientLight: Color3,
	outdoorAmbient: Color3,
	-- Fraction of a real hour for one in-game day. Short days make the
	-- lighting change often enough to notice in a single session.
	dayLength: number,
	windSpeed: number?,
	companionSun: CompanionSun?,

	-- Rules ---------------------------------------------------------------
	-- Coruscant is a vertical city: there is no ground to walk on, only
	-- platforms and skylanes. Systems that assume a spawnable surface must
	-- check this rather than dropping the player into the abyss.
	-- The only switch: false sends the planet down `buildVerticalCity`.
	-- There used to be a `verticalCity` flag beside it that nothing read,
	-- which let Nar Shaddaa declare itself a stack of platforms while
	-- building as ordinary ground.
	hasWalkableGround: boolean,
	-- Height above which the player is in open sky and needs a ship.
	flightCeiling: number?,

	--[[
		How many hulls are in the air over this world at any moment.

		Ambient only: nothing here can be shot, boarded, landed on or
		collided with, and no NPC is inside one. It is scenery that moves,
		and it is the difference between a city and a model of a city --
		121 towers standing in dead air read as an unfinished level, which
		is what Coruscant looked like from the moment it was built.

		Absent means an empty sky, which is right for eight of the nine:
		the wastes of Korriban do not have rush hour. Drawn entirely on the
		client (`SkyTrafficController`) because nothing about it is a fact
		the server needs to hold -- but seeded per planet and flown off the
		shared clock, so two players in one room see the same sky.
	]]
	airTraffic: number?,

	controllingFaction: string,
	minLevel: number,
	maxLevel: number,
	lawLevel: number, -- 0 = lawless, 1 = patrolled; drives crime response

	-- Declared centre-outward. Every `zone` named by a spawn rule or a point
	-- of interest must appear here; Planets.validate says so.
	zones: { ZoneDef },
	spawns: { SpawnRule },
	pointsOfInterest: { PointOfInterest },

	--[[
		An authored town, replacing the radial generator for this world only.

		Absent on most planets on purpose. See `LayoutDef`: a world with one
		gets its buildings, roads and district centres from the picture, a
		world without keeps the rings it has always had, and both go through
		the same marker-emitting code afterwards so nothing downstream can
		tell which it walked into.
	]]
	layout: LayoutDef?,

	--[[
		Stacked walkable storeys, for a world with no ground to lay a town on.

		Only Coruscant. See `DeckDef`: each entry is one district drawn as its
		own picture at its own height, and the whole authored-town pipeline --
		streets, interiors, crowds, patrol routes -- runs once per deck. A
		planet with `decks` must not also have a `layout`; there is only one
		settlement origin and they would be built on top of each other.
	]]
	decks: { DeckDef }?,
}

local defs: { [string]: PlanetDef } = {}

local function def(p: PlanetDef): PlanetDef
	defs[p.id] = p
	return p
end

local V3 = Vector3.new

--------------------------------------------------------------------------------

def({
	id = "Tatooine",
	displayName = "Tatooine",
	description = "Twin suns, no water, and every kind of trouble passing through on its way somewhere else.",
	coords = V3(820, -40, 610),
	region = "Outer Rim",

	gravity = 178,
	terrain = "Desert",
	architecture = "Adobe",
	groundColor = Palette.TatooineSand,
	rockColor = Palette.TatooineRock,
	terrainMaterial = Enum.Material.Sand,
	skyTint = Color3.fromRGB(255, 226, 178),
	fogColor = Color3.fromRGB(226, 200, 156),
	fogStart = 400,
	fogEnd = 2600,
	ambientLight = Color3.fromRGB(120, 104, 80),
	outdoorAmbient = Color3.fromRGB(160, 140, 108),
	dayLength = 0.25,
	windSpeed = 12,

	-- Tatoo II. Trails the primary and sits a little lower, so it rises after
	-- it and sets before it -- there is a stretch of every evening with one sun
	-- left in the sky, which is the shot the whole planet is famous for.
	companionSun = {
		yaw = 6,
		pitch = -3.5,
		sizeDegrees = 2.4,
		color = Color3.fromRGB(255, 188, 120),
	},

	hasWalkableGround = true,
	controllingFaction = "Hutt",
	minLevel = 1,
	maxLevel = 20,
	lawLevel = 0.2,

	--[[
		ANCHORHEAD, DRAWN RATHER THAN ROLLED

		The first authored town in the game, and the test of whether the rest
		are worth writing. Everything about it is a decision instead of a
		seed: one wall with four gates, two avenues crossing at a plaza, the
		market on the east side and the cantina quarter down in the
		south-west, where the three inner districts below point at it.

		Read it as a map. North is the top, west is the left, and touching
		cells that share a glyph are one building -- `hh` over two rows is a
		house with an upstairs, `WWWW` is one wall and not four posts. Two
		houses side by side need a gap between them; that is the only rule
		that is not obvious from looking at it.

		32 studs a cell, 26 cells square: 832 studs across, which fits inside
		the 520-stud settlement radius on the axes and stops short of the
		dunes `buildScatter` throws down at 610. The spaceport does not appear
		here on purpose -- it is 116 studs across, too big for any block, so
		`buildMarkers` puts it out past the wall with a road to it, which is
		where a landing field belongs anyway.
	]]
	layout = {
		cell = 32,
		legend = {
			W = "Wall",
			G = "Gate",
			["."] = "Road",
			P = "Plaza",
			h = "House",
			s = "Shop",
			H = "Hall",
			t = "Tower",
			y = "Yard",
			l = "Lamp",
		},
		grid = {
			"WWWWWWWWWWWWGGWWWWWWWWWWWW",
			"Whh h.hhh hh..hh hhh.h hhW",
			"Whh h.hhh hh..hh hhh.h hhW",
			"W  y .  yy  .. y  y . y  W",
			"Whhtt.hh  hh..hh  hh.tthhW",
			"W........................W",
			"Whh h.hhh hh..hh hhh.h hhW",
			"Whh h.hhh hh..hh hhh.h hhW",
			"W yy . y  y .. y  y . yy W",
			"Whh l.HHH hh..hh sss.ssHHW",
			"Whh l.HHH PPPPPP sss.ssHHW",
			"Whhhh.HHH PPPPPP sss.ssHHW",
			"G.........PPPPPP.........G",
			"G.........PPPPPP.........G",
			"Whh l.hh  PPPPPP  ss.sshhW",
			"Whhhh.hh  PPPPPP  ss.sshhW",
			"Whh h.hh  hh..hh ss .ss hW",
			"Whyy .yy  hh..hh  h . yhhW",
			"Whyy .yy  hh..hh  h . yhhW",
			"Whh l.hh  hh..hh hh .l hhW",
			"W........................W",
			"Why y.yy  hh..hh  hh.hh hW",
			"Why y.yy  hh..hh  hh.hh hW",
			"W  y . yy   .. y  y . y  W",
			"Whhtt.hh  hh..hh  hh.tthhW",
			"WWWWWWWWWWWWGGWWWWWWWWWWWW",
		},
	},

	zones = {
		--[[
			`distance` still sets the level band -- that is what it is for,
			and it is unchanged. `cells` only says where on the page the
			district is, which a bearing rolled from the seed could never say:
			the market is east of the plaza and the cantina quarter is behind
			it to the south-west, and now it is every time.
		]]
		-- West to column 7 so the town hall block is inside it. A district is
		-- also who is standing in the buildings drawn in it, and the hall was
		-- three cells outside the only rectangle that could have staffed it.
		{ id = "Town", distance = 0, cells = { from = Vector2.new(7, 10), to = Vector2.new(17, 17) } },
		{ id = "Market", distance = 0.3, cells = { from = Vector2.new(18, 10), to = Vector2.new(25, 17) } },
		{ id = "Cantina", distance = 0.5, cells = { from = Vector2.new(3, 18), to = Vector2.new(10, 24) } },
		-- The outer four used to run out to 2.1 -- 1092 studs, most of a
		-- kilometre of empty sand -- which left five of this planet's six
		-- landmarks as smudges in the fog and made the walk between
		-- districts dead time. Pulled in so they read as one settlement's
		-- outskirts. The ordering is what matters rather than the scale:
		-- this is still the difficulty dial, and the Dune Sea is still the
		-- far edge with the Tuskens on it.
		--[[
			THE ONE PLACE ON THIS PLANET A LEVEL 1 CHARACTER CAN FIGHT

			Reported from play, 2026-08-17: *"I should be able to discover
			random tasks or go out of camp to combat raiders."* The nearest
			district here that held anything aggressive was the Farmstead,
			which bands 8-13, and `Radiant` only writes a Cull where
			something is aggressive -- so a new Tatooine character had the
			story missions and nothing else.

			**This is the one district in the game that needs `band`.** On
			Korriban and Taris the fix was a `distance = 0` rectangle drawn
			just outside the gate, because both of those grids draw ground
			outside their wall. Anchorhead's does not: it is 26 cells square
			and every cell of it is inside the wall. A district with no
			`cells` is placed radially at `distance * SETTLEMENT_RADIUS`, and
			the wall alone reaches 416 studs -- so anywhere outside it is
			`distance` 0.85 or more, which derives a band of 8 or worse.

			Which is exactly the disagreement `bandFor` documents `band` for.
			The Boneyard is where Anchorhead pushes its dead machines over
			the lip and forgets them. It is a hundred yards from the north
			gate and it is full of children and thieves. It is *outside*
			without being *far*, and the two are not the same fact.
		]]
		{ id = "Boneyard", distance = 0.95, band = { min = 1, max = 6 } },
		{ id = "Farmstead", distance = 0.8 },
		{ id = "Wastes", distance = 1.05 },
		{ id = "Palace", distance = 1.3 },
		{ id = "DuneSea", distance = 1.6 },
	},
	spawns = {
		-- Claim-jumpers again, at the bottom of the ladder this time.
		-- `Smuggler` rolls 3-24 and the Boneyard bands 1-6, so these come
		-- out at 3-6: the first thing on Tatooine that will fight you and
		-- the first thing you can beat.
		{
			archetype = "Smuggler",
			count = 10,
			zone = "Boneyard",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{ archetype = "Jawa", count = 14, zone = "Wastes" },
		-- Claim-jumpers working the Jawas' scrap, and the reason this district
		-- exists in the level curve at all: the Wastes band 10-15, and the
		-- stretch from 10 to 16 was the thinnest in the galaxy -- about a
		-- third of the XP per sweep that level 17 could reach.
		{ archetype = "Smuggler", count = 10, zone = "Wastes", behavior = NPCArchetypes.Behavior.Aggressive },
		{ archetype = "MoistureFarmer", count = 8, zone = "Farmstead" },
		{ archetype = "Civilian", count = 22, zone = "Town" },
		-- Nine, because the market district has nine places to stand: six shop
		-- counters drawn in the grid above and three points on the street.
		-- NPCService fills the emptiest first, so this is one trader per shop
		-- with the remainder outside -- at five it was a coin toss whether any
		-- given shop had anybody in it, and an empty shop you can walk into is
		-- worse than a solid one. Adding a tenth `s` costs a trader, not a bug.
		{ archetype = "Merchant", count = 9, zone = "Market" },
		--[[
			The only man in the galaxy who will sell you a hull, times five.

			One per spaceport and nowhere else, which is the whole change:
			starships used to sit on the general counter next to the ration
			packs, so the trader in the market sold you something that could
			only ever be landed at a field two districts away.

			`poi` rather than the zone alone, because Anchorhead's landing
			field is too wide for a city block and stands out past the wall,
			while the Town district it belongs to has thirty-two other people
			in it. Named by district on the three worlds whose spaceport is
			drawn into the grid -- there the district *is* the landing field.
		]]
		{ archetype = "ShipBroker", count = 1, zone = "Town", poi = "Anchorhead" },
		{ archetype = "Smuggler", count = 8, zone = "Cantina" },
		-- Out in the Dune Sea rather than sharing the Wastes with the Jawas.
		-- Level 5-16 and aggressive at 180 studs, against a level 1 story
		-- objective standing in the same sand, is not a difficulty curve.
		{ archetype = "TuskenRaider", count = 12, zone = "DuneSea" },
		-- The raid the farmers keep talking about. Bands 8-13, which is the
		-- step between the town missions and the Dune Sea -- and it used not
		-- to exist: you left Anchorhead around level 6 and the next thing on
		-- the planet that would fight you was nine levels further out.
		{ archetype = "TuskenRaider", count = 8, zone = "Farmstead" },
		{ archetype = "ImperialTrooper", count = 10, zone = "Town" },
		{
			archetype = "CartelEnforcer",
			count = 6,
			zone = "Palace",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		-- Out of the cantina. They band 18-45 and the cantina bands 5-10, so
		-- every hunter in Anchorhead was pinned to the archetype's floor and
		-- standing somewhere the story sends a level 5 player.
		{ archetype = "BountyHunter", count = 3, zone = "DuneSea" },
	},
	pointsOfInterest = {
		--[[
			THESE NAMES ARE THREE AND A HALF THOUSAND YEARS EARLY

			They used to be Mos Eisley, Chalmun's Cantina, Jabba's Palace and
			the Lars Homestead -- every one of them Original Trilogy, and none
			of them existing in 3,640 BBY. Chalmun, Jabba and the Lars family
			are all unborn by several millennia.

			Tatooine itself is era-correct and stays: it is a Star Map world
			in KOTOR and a full planet in the era this game is set in, with
			Anchorhead, Czerka Corporation, Jawas and Sand People all present.
			So the planet is right and only the signage was wrong.
		]]
		{
			id = "Anchorhead",
			displayName = "Anchorhead",
			kind = "Spaceport",
			description = "A mining town that grew a landing field. Czerka runs it, and Czerka is not sentimental.",
			zone = "Town",
		},
		{
			id = "DuneCantina",
			displayName = "The Dry Well",
			kind = "Cantina",
			description = "Warm drinks, cold company, and every rumour on the planet for the price of listening.",
			zone = "Cantina",
		},
		{
			id = "HuttEstate",
			displayName = "Nagurra's Estate",
			kind = "Base",
			description = "A Hutt's compound behind a wall. You get in by invitation or by force.",
			zone = "Palace",
		},
		{
			id = "MoistureFarm",
			displayName = "Vantel Moisture Farm",
			kind = "Outpost",
			-- The generic outpost drew one shed. "Forty vaporators" is the
			-- description's own number and the whole silhouette of a farm on
			-- this world: two domes in a walled yard, ringed by a field of
			-- condensers.
			landmark = "MoistureFarm",
			description = "Forty vaporators and one family, on the edge of the Dune Sea.",
			zone = "Farmstead",
		},
		{
			id = "Boneyard",
			displayName = "The Boneyard",
			kind = "Ruin",
			-- Gives the district a POI, which is what makes `Radiant` write
			-- a Salvage here as well as a Cull.
			--
			-- `Ruin` draws one intact wreck, which is the opposite of the
			-- word: a boneyard is the same machines the farm uses, stripped
			-- and in rows.
			landmark = "Boneyard",
			description = "Vaporators, speeders and one hauler, all of them stripped. Anchorhead's answer to a graveyard.",
			zone = "Boneyard",
		},
		{
			id = "SandcrawlerWreck",
			displayName = "Sandcrawler Wreck",
			kind = "Ruin",
			landmark = "Sandcrawler",
			description = "A Jawa crawler that broke an axle and never moved again. They live in it still.",
			zone = "Wastes",
		},
		{
			id = "DuneSeaWreck",
			displayName = "Dune Sea Wreck",
			kind = "Ruin",
			description = "Half a hull sticking out of the sand. Nobody agrees on what it used to be.",
			zone = "DuneSea",
		},
	},
})

def({
	id = "Coruscant",
	displayName = "Coruscant",
	description = "A single city wrapped around an entire world. Thirteen years after the Sacking the Senate District is spotless and the Underlevels are still rubble with people living in it.",
	coords = V3(0, 0, 0),
	region = "Core",

	gravity = 196.2,
	terrain = "Urban",
	-- Declared and, since the decks below, finally drawn. `spireShape` and
	-- `spireDress` -- tiered towers with a 0.93 taper, ledges, continuous
	-- Neon glazing and a mast -- sat in `PlanetBuilder` unreachable for two
	-- weeks, because Coruscant was the one world with no ground layout and
	-- so nothing ever called `buildRoom` on it.
	architecture = "Spire",
	groundColor = Palette.CoruscantPlate,
	rockColor = Palette.WornSteel,
	skyTint = Color3.fromRGB(168, 186, 214),
	fogColor = Color3.fromRGB(96, 108, 132),
	fogStart = 300,
	fogEnd = 4000,
	-- A city of canyons between towers shades itself, so it needs more fill
	-- light than its own sky suggests to stay readable down among the traffic.
	ambientLight = Color3.fromRGB(106, 114, 134),
	outdoorAmbient = Color3.fromRGB(154, 164, 186),
	dayLength = 0.3,

	-- No *terrain* anywhere: no cylinder of soil, no relief, no scatter, and
	-- no cloud deck in orbit. It no longer means "nowhere to stand" -- the
	-- five `decks` at the bottom of this entry are the ground, and they are
	-- built, not filled.
	hasWalkableGround = false,
	flightCeiling = 1400,
	-- The busiest sky in the galaxy. Raised from 26 when the tower grid went
	-- from 11 rows to 17: the same hull count over 2.4x the area is a quieter
	-- sky, and this is the one world where traffic doing the work of a crowd
	-- is not a saving but the point.
	airTraffic = 54,

	-- The Republic still holds its own capital. It was sacked, not taken: the
	-- treaty left the Senate sitting in a city it had watched burn, which is
	-- why the Imperial diplomats in the Works are so hard to look at.
	controllingFaction = "Republic",
	minLevel = 10,
	maxLevel = 34,
	lawLevel = 1.0,

	-- Distance is the difficulty dial and nothing else here: every district
	-- is a deck stacked on the same footprint, so `bandFor` reads these and
	-- the compass fan they normally drive is never used. Ordered top deck
	-- first, which is why the Senate is 0 and the Underlevels 1.5 -- the
	-- descent through the city *is* the walk out of town.
	zones = {
		{ id = "Plaza", distance = 0 },
		-- Skylane and Works swapped places 2026-08-29, when the decks gave
		-- these numbers a physical meaning. "The high commercial lane" has to
		-- be above "resettlement stacks thrown up in a hurry", and once it is,
		-- the band it inherits has to be the easier of the two as well --
		-- otherwise descending the city gets *safer* for one storey.
		{ id = "Skylane", distance = 0.35 },
		{ id = "Works", distance = 0.7 },
		{ id = "TempleRuin", distance = 1.1 },
		{ id = "Underlevels", distance = 1.5 },
	},
	spawns = {
		{ archetype = "Civilian", count = 40, zone = "Plaza" },
		{ archetype = "ProtocolDroid", count = 12, zone = "Plaza" },
		{ archetype = "Merchant", count = 8, zone = "Plaza" },
		{ archetype = "ShipBroker", count = 1, zone = "Plaza", poi = "CoruscantSpaceport" },
		{ archetype = "RepublicSecurity", count = 24, zone = "Skylane" },
		{ archetype = "RepublicVeteran", count = 6, zone = "Works" },
		{ archetype = "Civilian", count = 20, zone = "Works" },
		-- The embassy. The treaty is nominally still in force, so Imperial
		-- officers walk around the capital they burned and nobody may say so.
		-- They did not come alone: the escort is what the Coruscant story
		-- chain actually fights, and it has to be here for those Kill
		-- objectives to have anything to count.
		{ archetype = "ImperialOfficer", count = 4, zone = "Works" },
		{ archetype = "ImperialTrooper", count = 14, zone = "Works" },
		-- The escort proper, and the thing The Long Fall tells you to clear off
		-- the skybridge. It has always been the mission's Kill target; it just
		-- used to stand there until you shot first.
		{
			archetype = "ImperialCommando",
			count = 6,
			zone = "Skylane",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{ archetype = "RepublicPilot", count = 5, zone = "Plaza" },
		{ archetype = "JediKnight", count = 3, zone = "TempleRuin" },
		{ archetype = "Smuggler", count = 6, zone = "Underlevels" },
		--[[
			The two outer districts, which until now held three quest givers
			and six smugglers between them.

			Nobody has a writ to be picking over the Temple ruin and everybody
			is, so it is the one place on the capital where an Imperial squad
			will shoot rather than file a complaint. The Underlevels are worse
			and quieter: hunters working a district the Republic stopped
			policing about a century ago.
		]]
		{
			archetype = "ImperialCommando",
			count = 8,
			zone = "TempleRuin",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{
			archetype = "BountyHunter",
			count = 10,
			zone = "Underlevels",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		--[[
			And what the hunters are down there for.

			*"There is also mutant monsters in the lower levels"* -- Landon,
			and he is describing a difficulty curve rather than a bestiary:
			the well made the bottom of the city somewhere you arrive rather
			than somewhere you spawn, and it needed to be worth the descent.
			These are the only melee enemies on the planet, so the Underlevels
			are also the one deck that does not fight like the other four.
		]]
		{ archetype = "UnderlevelMutant", count = 14, zone = "Underlevels" },
		{ archetype = "MutantBrute", count = 4, zone = "Underlevels" },
	},
	pointsOfInterest = {
		{
			id = "JediTempleRuin",
			displayName = "The Temple Ruin",
			kind = "Temple",
			-- It was drawing Tython's intact ziggurat, so the word "ruin" was
			-- carried entirely by the sign. A colonnade with most of its
			-- columns down and a spire lying across the terrace says
			-- "never rebuilt" without the sign's help.
			landmark = "TempleRuin",
			description = "Never rebuilt. The Order says it is a memorial; everyone else can see it is an admission.",
			zone = "TempleRuin",
		},
		{
			id = "SenateDistrict",
			displayName = "Senate District",
			kind = "Market",
			description = "Polished towers and patrolled skylanes. Nothing happens here except conversation.",
			zone = "Plaza",
		},
		{
			id = "TheWorks",
			displayName = "The Works",
			kind = "Outpost",
			description = "Resettlement stacks thrown up in a hurry. The Sacking's refugees are still in them.",
			zone = "Works",
		},
		{
			id = "Underlevels",
			displayName = "The Underlevels",
			kind = "Cantina",
			description = "Below the rubble line. No sunlight, no patrols, no questions.",
			zone = "Underlevels",
		},
		{
			id = "CoruscantSpaceport",
			displayName = "Skydock Seven",
			kind = "Spaceport",
			description = "Landing platform for anyone the Senate has cleared to land, which is fewer people every year.",
			zone = "Plaza",
		},
		{
			id = "SkylaneAlpha",
			displayName = "Skylane Alpha",
			kind = "Outpost",
			-- All three shared one builder and all three were sheds, which
			-- made the defining thing about Coruscant -- that the city is
			-- vertical and the traffic is above you -- invisible from the
			-- ground. A control deck and two rows of lit pylons receding into
			-- the fog is the lane itself, and it reads from a long way off.
			landmark = "Skylane",
			description = "The high commercial lane. Traffic moves fast and does not stop for you.",
			zone = "Skylane",
		},
		{
			id = "SkylaneBeta",
			displayName = "Skylane Beta",
			kind = "Outpost",
			landmark = "Skylane",
			description = "A mid-level freight lane threading between the towers.",
			zone = "Skylane",
		},
		{
			id = "SkylaneGamma",
			displayName = "Skylane Gamma",
			kind = "Outpost",
			landmark = "Skylane",
			description = "The low lane, close enough to the underlevels that patrols go in pairs.",
			zone = "Underlevels",
		},
	},

	--[[
		FIVE STOREYS OF CITY, STACKED ON ONE FOOTPRINT

		Every other authored world draws its districts side by side on one
		page, because on a planet with soil that is what a town is. Coruscant's
		districts are the same page five times over at five heights, 220 studs
		apart, and the tower grid is punched through all of them -- which is
		the only arrangement in which "the lower you go, the more ghetto it
		becomes" is a thing you can *see* rather than a thing you are told.

		Read each grid as a map, exactly as Anchorhead's: north at the top,
		west at the left, touching cells that share a glyph are one building.
		22 cells at 32 studs is 704 studs a side, which puts the corner at 498
		-- inside the 610 that `tools/gridcheck.py` insists on, and clear of
		the first ring of towers with room for `PlanetBuilder` to drop any
		tower whose footprint would come through a street.

		EVERY DECK HAS A LANDING PAD, and that is not decoration. This whole
		job started with *"I spawn on a platform but can't get my spaceship and
		can't go anywhere"*: a starship may only be called down within
		`Ships.PAD_RANGE` of a part tagged `Ships.PAD_TAG`, Coruscant's only
		pads belonged to a spaceport the vertical-city builder had dropped on
		a random tower platform, and no path led to it. Until turbolifts land,
		a hull is also the only way between decks -- so a deck with no pad is a
		deck you can be stranded on, which is the bug this is fixing.
	]]
	decks = {
		--[[
			THE SENATE DISTRICT. Sunlight, width, and nothing to be afraid of.

			The top deck is deliberately the emptiest: one enormous plaza in
			the middle with the towers standing off it, shop frontage on two
			streets and the landing field in the north-west corner. It is the
			first thing a player sees when they arrive, and the contrast with
			the bottom deck four storeys down is the whole point of building
			five of these.
		]]
		{
			zone = "Plaza",
			y = 440,
			layout = {
				cell = 32,
				legend = {
					["."] = "Road",
					L = "Pad",
					T = "Tower",
					s = "Shop",
					P = "Plaza",
					H = "Hall",
					y = "Yard",
					X = "Lift",
					V = "Void",
				},
				grid = {
					"..LLLL......TTTT......",
					"..LLLL......TTTT......",
					"..LLLL..............XX",
					"....................XX",
					".ssss.sss......sss.ss.",
					".ssss.sss......sss.ss.",
					"......................",
					".TT.PPP.......PP.TT...",
					".TT.PPP.VVVVV.PP.TT...",
					"....PPP.VVVVV.PP......",
					"....PPP.VVVVV.PP......",
					"....PPP.VVVVV.PP......",
					"....PPP.VVVVV.PP......",
					".TT.PPP.......PP.TT...",
					".TT.PPPPPPPPPPPP.TT...",
					"......................",
					".HHH..ssss.....ssss...",
					".HHH..ssss.....ssss...",
					".HHH..................",
					"......................",
					"..yy....TTTT....yy....",
					"..yy....TTTT....yy....",
				},
			},
		},

		--[[
			SKYLANE ALPHA. Two lanes of moving traffic and the strip between.

			Drawn as two full-width paved runs with a spine of freight halls
			between them, which is what a commercial lane is: somewhere things
			pass through rather than somewhere anybody lives. The housing rows
			at the top and bottom are the only reason it is a district at all.
		]]
		{
			zone = "Skylane",
			y = 220,
			layout = {
				cell = 32,
				legend = {
					["."] = "Road",
					T = "Tower",
					h = "House",
					P = "Plaza",
					s = "Shop",
					H = "Hall",
					L = "Pad",
					y = "Yard",
					X = "Lift",
					V = "Void",
				},
				grid = {
					"..TT..............TT..",
					"..TT..............TT..",
					"....................XX",
					".hhh.hhh.hhh.hhh.hhhXX",
					".hhh.hhh.hhh.hhh.hhh..",
					"......................",
					".PPPPPPPPPPPPPPPPPPPP.",
					".PPPPPP.......PPPPPPP.",
					".PPPPPP.VVVVV.PPPPPPP.",
					"........VVVVV.........",
					".ss..HH.VVVVV.HH...ss.",
					".ss..HH.VVVVV.HH...ss.",
					".ss..HH.VVVVV.HH...ss.",
					"......................",
					".PPPPPPPPPPPPPPPPPPPP.",
					".PPPPPPPPPPPPPPPPPPPP.",
					".PPPPPPPPPPPPPPPPPPPP.",
					"......................",
					".hhh.hhh.hhh.hhh.hhh..",
					".hhh.hhh.hhh.hhh.hhh..",
					"..LLLL........yy......",
					"..LLLL........yy......",
				},
			},
		},

		--[[
			THE WORKS. Resettlement stacks, thirteen years after the Sacking.

			Housing rows top, middle and bottom with no space between them,
			because that is what "thrown up in a hurry" looks like on a page.
			The Imperial embassy's escort stands somewhere in here, which is
			why it is the busiest deck after the Senate.
		]]
		{
			zone = "Works",
			y = 0,
			layout = {
				cell = 32,
				legend = {
					["."] = "Road",
					h = "House",
					T = "Tower",
					s = "Shop",
					P = "Plaza",
					L = "Pad",
					H = "Hall",
					y = "Yard",
					X = "Lift",
					V = "Void",
				},
				grid = {
					"hhh.hhh.hhh.hhh.hhh...",
					"hhh.hhh.hhh.hhh.hhh...",
					"hhh.hhh.hhh.hhh.hhh.XX",
					"....................XX",
					".TT..ssss....ssss..TT.",
					".TT..ssss....ssss..TT.",
					"......................",
					".PPPPPP.......PPPPPPP.",
					".PPPPPP.VVVVV.PPPPPPP.",
					".PPPPPP.VVVVV.PPPPPPP.",
					"........VVVVV.........",
					"..LLLL..VVVVV.HH......",
					"..LLLL..VVVVV.HH......",
					"..LLLL........HH......",
					"......................",
					"hhh.hhh.hhh.hhh.hhh...",
					"hhh.hhh.hhh.hhh.hhh...",
					"......................",
					".yy...TTTT.....yy.....",
					".yy...TTTT.....yy.....",
					"......................",
					"hhh.hhh.hhh.hhh.hhh...",
				},
			},
		},

		--[[
			THE TEMPLE RUIN. Mostly not there any more.

			The emptiest grid in the game, and on purpose: two broken wall runs,
			four stubs of tower and a huge open yard where the Temple stood.
			`JediTempleRuin`'s own geometry lands in that yard, and the eight
			Imperial commandos picking over it have nowhere to hide.
		]]
		{
			zone = "TempleRuin",
			y = -220,
			layout = {
				cell = 32,
				legend = {
					["."] = "Road",
					W = "Wall",
					T = "Tower",
					y = "Yard",
					H = "Hall",
					L = "Pad",
					X = "Lift",
					V = "Void",
				},
				grid = {
					"......................",
					"..WWWW........WWWW....",
					"..WWWW........WWWW..XX",
					"....................XX",
					"....TT........TT......",
					"....TT........TT......",
					"......................",
					"..yyyyy.......yyyy....",
					"..yyyyy.VVVVV.yyyy....",
					"..yyyyy.VVVVV.yyyy....",
					"..yyyyy.VVVVV.yyyy....",
					"........VVVVV.........",
					".HHH....VVVVV.HHH.....",
					".HHH..........HHH.....",
					"......................",
					"..LLLL................",
					"..LLLL................",
					"......................",
					".WWWWWW......WWWWWW...",
					".WWWWWW......WWWWWW...",
					"......................",
					".....TT......TT.......",
				},
			},
		},

		--[[
			THE UNDERLEVELS. No sunlight, no patrols, no questions.

			Every alley one cell wide, every block of housing pressed against
			the next, and the only open ground on the deck is the yard the
			bounty hunters work out of. It is the same 22x22 page as the Senate
			district and it is the opposite thing, which is the comparison the
			whole feature is for.
		]]
		{
			zone = "Underlevels",
			y = -440,
			layout = {
				cell = 32,
				legend = {
					["."] = "Road",
					h = "House",
					s = "Shop",
					y = "Yard",
					L = "Pad",
					H = "Hall",
					T = "Tower",
					X = "Lift",
					V = "Void",
				},
				grid = {
					"hhhh.hh.hhhh.hh.hhhh..",
					"hhhh.hh.hhhh.hh.hhhh..",
					"....................XX",
					"hh.hhh.hh.hhh.hh.hhhXX",
					"hh.hhh.hh.hhh.hh.hhh..",
					"......................",
					".ss..ss..ss..ss..ss...",
					".ss..ss.......ss..ss..",
					"........VVVVV.........",
					"..yyyy..VVVVV.LLLL....",
					"..yyyy..VVVVV.LLLL....",
					"..yyyy..VVVVV.LLLL....",
					"........VVVVV.........",
					".HHHH...........hhh...",
					".HHHH.....hhh....hhh..",
					".HHHH.................",
					"......................",
					"hhh.hh.hhh.hh.hhh.hh..",
					"hhh.hh.hhh.hh.hhh.hh..",
					"......................",
					"..TT..........TT......",
					"..TT..........TT......",
				},
			},
		},
		-- Annotated, and it is not decoration. Luau infers an array's element
		-- type from its first entry and then demands the rest match it
		-- *exactly*, so the Plaza's legend became the type of a legend and the
		-- four decks below it were each rejected for the glyphs the Plaza did
		-- not happen to use. Five districts drawn with five vocabularies is
		-- the entire point of authoring them separately.
	} :: { DeckDef },
})

def({
	id = "Hoth",
	displayName = "Hoth",
	description = "Ice, wind, and a starship graveyard: thousands of hulls from a battle nobody can now explain, half-buried and walkable.",
	coords = V3(-940, 120, 480),
	region = "Outer Rim",

	gravity = 210, -- heavier than standard; jumps are shorter here
	terrain = "Ice",
	architecture = "IceBunker",
	groundColor = Palette.HothSnow,
	rockColor = Palette.HothIce,
	terrainMaterial = Enum.Material.Snow,
	skyTint = Color3.fromRGB(206, 226, 244),
	fogColor = Color3.fromRGB(216, 232, 244),
	fogStart = 60,
	fogEnd = 900, -- whiteout: you cannot see trouble coming
	ambientLight = Color3.fromRGB(96, 108, 124),
	outdoorAmbient = Color3.fromRGB(150, 168, 190),
	dayLength = 0.4,
	windSpeed = 40,

	hasWalkableGround = true,
	controllingFaction = "Republic",
	minLevel = 10,
	maxLevel = 46,
	lawLevel = 0.6,

	--[[
		AUREK BASE AND THE GRAVEYARD, DRAWN RATHER THAN ROLLED

		The whole planet is one line -- you are either inside the wire or you
		are not -- so the map is drawn as two halves of a page with a wall
		between them, and the wall has exactly one gate in it.

		Inside is a Republic salvage operation, and it is drawn like one: no
		shops anywhere, because Hoth's population is troopers, pilots, droids
		and the civilians who service them, and there is not one Merchant in
		the spawn list. Halls, quarters, a muster square and a pad. If a Shop
		cell were drawn here, its counter would be handed to a trooper.

		Outside is the Graveyard, and the hulls are `Wall`. That is the trick
		this map turns: a rampart is a long solid run you cannot walk through
		and can walk *on*, which is exactly what the description has always
		claimed -- "you do not cross it, you climb it". They are staggered so
		the gaps never line up, so getting from the gate to the far ice is a
		route rather than a walk. Nothing out here is an anchor: past the wire
		everything shoots, and anchors are where players spawn.

		The Fissure stays off the grid. It is under the map, not on it.
	]]
	layout = {
		cell = 32,
		legend = {
			W = "Wall",
			G = "Gate",
			["."] = "Road",
			P = "Plaza",
			h = "House",
			H = "Hall",
			T = "Tower",
			l = "Lamp",
		},
		grid = {
			"WWWWWWWWWWWWWWWWWWWWWWWWWW",
			"WT..............T......T.W",
			"W..HHHH...HHHH...........W",
			"W..HHHH...HHHH...HHHHHH..W",
			"W................HHHHHH..W",
			"W..PPPPPPPPPPP...........W",
			"W..PPPPPPPPPPP...PPPPPP..W",
			"W................PPPPPP..W",
			"W..HHHH...hh.hh..PPPPPP..W",
			"W..HHHH...hh.hh..........W",
			"W..................l.....W",
			"Wl.......................W",
			"WWWWWWWWWWWGGWWWWWWWWWWWWW",
			"..........................",
			"..WWWWWWWWW.....WWWWWWW...",
			"..WWWWWWWWW.....WWWWWWW...",
			"..........................",
			"WWWWWWW.....WWWWWWWWWWWW..",
			"WWWWWWW.....WWWWWWWWWWWW..",
			"..........................",
			"....WWWWWWWWW.....WWWWWWWW",
			"....WWWWWWWWW.....WWWWWWWW",
		},
	},

	zones = {
		{ id = "Base", distance = 0, cells = { from = Vector2.new(1, 1), to = Vector2.new(16, 13) } },
		{ id = "Hangar", distance = 0.35, cells = { from = Vector2.new(17, 1), to = Vector2.new(26, 13) } },
		-- Imperial salvage teams are out on the ice racing you for the same
		-- wrecks, not inside the base you land at. Drawn as the whole page
		-- below the wire, so "outside" is a place and not a direction.
		{ id = "Graveyard", distance = 1.5, cells = { from = Vector2.new(1, 14), to = Vector2.new(26, 22) } },
		{ id = "Fissure", distance = 2.2 },
	},
	spawns = {
		{ archetype = "RepublicTrooper", count = 26, zone = "Base" },
		{ archetype = "RepublicPilot", count = 8, zone = "Hangar" },
		{ archetype = "Civilian", count = 10, zone = "Base" },
		{ archetype = "ProtocolDroid", count = 4, zone = "Hangar" },
		-- No `poi`: Aurek Hangar is drawn into the grid, so the Hangar
		-- district is the landing field rather than containing it.
		{ archetype = "ShipBroker", count = 1, zone = "Hangar" },
		--[[
			Both sides are salvaging the same wrecks and neither filed for the
			claim, so past the wire everything on this planet shoots.

			It did not before: the Republic base was the whole of Hoth's
			population that would react to you at all, and the Graveyard and
			the Fissure -- the two districts the entire planet exists for --
			held seventeen NPCs who watched you walk past.
		]]
		{
			archetype = "ImperialScout",
			count = 14,
			zone = "Graveyard",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{
			archetype = "ImperialCommando",
			count = 6,
			zone = "Graveyard",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		-- Fourteen, because the Fissure is one of only three districts in the
		-- galaxy that band into the forties and the XP budget check will not
		-- pass without them. Whoever went down there first is still down there.
		{
			archetype = "BountyHunter",
			count = 14,
			zone = "Fissure",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
	},
	pointsOfInterest = {
		{
			id = "AurekBase",
			displayName = "Aurek Base",
			kind = "Base",
			description = "A Republic salvage operation in tunnels cut through the glacier. The only warm place on the planet.",
			zone = "Base",
			drawn = true,
		},
		{
			id = "AurekHangar",
			displayName = "Aurek Hangar",
			kind = "Spaceport",
			description = "Recovery sleds on standby and a permanent smell of hot metal.",
			zone = "Hangar",
			drawn = true,
		},
		{
			id = "TheGraveyard",
			displayName = "The Graveyard",
			kind = "Ruin",
			landmark = "Ruin",
			description = "Hulls the size of city blocks, on their sides in the snow. You do not cross it, you climb it.",
			zone = "Graveyard",
			-- The hulls are the rampart runs on the grid. North Ravine below
			-- is deliberately *not* drawn: it is the second landmark in this
			-- district, so it is pushed past the last hull, out onto the ice
			-- where a crevasse the sensors keep losing belongs.
			drawn = true,
		},
		{
			id = "GlacialFissure",
			displayName = "Glacial Fissure",
			kind = "Ruin",
			description = "Do not go in alone. Do not go in armed only with a blaster.",
			zone = "Fissure",
		},
		{
			id = "NorthRavine",
			displayName = "North Ravine",
			kind = "Outpost",
			description = "A crevasse the perimeter sensors keep losing track of. Something keeps breaking them.",
			zone = "Graveyard",
		},
	},
})

def({
	id = "Tython",
	displayName = "Tython",
	description = "Green, quiet and old. The Jedi came back here after Coruscant burned, and built nothing they could defend.",
	coords = V3(-180, -60, -240),
	-- Tython sits deep enough in to be a Core world, which is half of why the
	-- Order chose it: everything that matters is within reach and nothing that
	-- matters has to be explained to anyone.
	region = "Core",

	gravity = 190,
	terrain = "Forest",
	architecture = "JediStone",
	groundColor = Palette.NabooGrass,
	rockColor = Palette.NabooStone,
	terrainMaterial = Enum.Material.Grass,
	skyTint = Color3.fromRGB(198, 224, 255),
	fogColor = Color3.fromRGB(186, 210, 214),
	fogStart = 500,
	fogEnd = 3400,
	ambientLight = Color3.fromRGB(96, 106, 96),
	outdoorAmbient = Color3.fromRGB(150, 164, 148),
	dayLength = 0.35,
	windSpeed = 8,

	hasWalkableGround = true,
	controllingFaction = "Jedi",
	minLevel = 30,
	maxLevel = 36,
	lawLevel = 0.8,

	--[[
		THE TEMPLE, THE VILLAGE AND THE LANDING, DRAWN RATHER THAN ROLLED

		The first grid with no `Wall` and no `Gate` anywhere on it. Every other
		drawn world so far opens with a perimeter, because every other world
		has decided what it is afraid of. Tython has not, and the description
		on this planet already says so out loud: they built nothing they could
		defend. Putting a rampart glyph here would quietly contradict it.

		So the only thing the map fortifies is symmetry. The Temple precinct
		is the one place where anything lines up -- two towers, three halls in
		a rank, and a plaza sixteen cells wide that everything else is spaced
		off. It is the Order's idea of itself, drawn.

		Kalikori Village below it is deliberately none of that. The Twi'leks
		were here first and were not asked, so their houses sit at whatever
		spacing the ground allowed, in twos and threes, with one yard and two
		lamps and no through road that goes anywhere in particular.

		The Stalls are a separate district at the *same* distance as the
		Village, which is the rule Korriban taught: a `Shop` room hands its
		counter to whoever the district spawns, so the district has to be all
		traders. It costs nothing -- `bandFor` spreads levels over the span of
		distances, and 0.4 is already in it.

		The Gnarls and Forge Ridge stay off the grid entirely. They are the
		hostile half of the planet and they are supposed to feel like leaving.
	]]
	layout = {
		cell = 32,
		legend = {
			-- No `W` and no `G`. See above; their absence is the point.
			["."] = "Road",
			P = "Plaza",
			y = "Yard",
			h = "House",
			s = "Shop",
			H = "Hall",
			T = "Tower",
			l = "Lamp",
		},
		grid = {
			"....TT............TT....",
			"....TT............TT....",
			"........................",
			"...HHHH...HHHH...HHHH...",
			"...HHHH...HHHH...HHHH...",
			"........................",
			"....PPPPPPPPPPPPPPPP....",
			"....PPPPPPPPPPPPPPPP....",
			"........................",
			"........................",
			".hh....hhh..............",
			".hh....hhh.....sss..sss.",
			"...............sss..sss.",
			"...hh.....hh............",
			"...hh.....hh....sss.....",
			"..l.............sss.....",
			".hhh..HHH........l......",
			".hhh..HHH...............",
			"..............PPPPPPPPP.",
			"..yyy.........PPPPPPPPP.",
			"..yyy...hhh...PPPPPPPPP.",
			"........hhh.............",
			"....l..........HHH......",
			"...............HHH......",
		},
	},

	zones = {
		{ id = "Temple", distance = 0, cells = { from = Vector2.new(1, 1), to = Vector2.new(24, 9) } },
		{ id = "Village", distance = 0.4, cells = { from = Vector2.new(1, 11), to = Vector2.new(13, 24) } },
		-- Same distance as the Village on purpose: a trading district, not a
		-- level band. See the note on the layout.
		{ id = "Stalls", distance = 0.4, cells = { from = Vector2.new(14, 11), to = Vector2.new(24, 17) } },
		{
			id = "Spaceport",
			distance = 0.8,
			cells = { from = Vector2.new(14, 18), to = Vector2.new(24, 24) },
		},
		-- The Gnarls are wilderness, and the only hostile ground on the planet.
		{ id = "Gnarls", distance = 1.7 },
		{ id = "ForgeRidge", distance = 2.3 },
	},
	spawns = {
		{ archetype = "JediKnight", count = 10, zone = "Temple" },
		{ archetype = "Civilian", count = 24, zone = "Village" },
		-- Moved out of the Village and up by one when the Stalls were drawn:
		-- three shop counters plus a ring of three needs six bodies.
		{ archetype = "Merchant", count = 6, zone = "Stalls" },
		{ archetype = "ProtocolDroid", count = 6, zone = "Temple" },
		{ archetype = "RepublicSecurity", count = 10, zone = "Spaceport" },
		{ archetype = "ShipBroker", count = 1, zone = "Spaceport" },
		{ archetype = "RepublicVeteran", count = 6, zone = "Gnarls" },
		-- Nothing here is fortified, and the Empire has noticed. Patrols probe
		-- the Gnarls; the Order calls it a training opportunity. They shoot on
		-- sight, which is what "probe" means and what the Repel the Assault
		-- objective has always assumed -- it just used to require you to start
		-- the fight yourself.
		{
			archetype = "ImperialTrooper",
			count = 10,
			zone = "Gnarls",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		-- And what the patrols are escorting. The Forge Ridge is the far edge
		-- of the planet and had nothing on it at all.
		{
			archetype = "SithHonourGuard",
			count = 8,
			zone = "ForgeRidge",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
	},
	pointsOfInterest = {
		{
			id = "TythonTemple",
			displayName = "The Temple",
			kind = "Temple",
			description = "Archives, terraces and a council chamber with no doors on it. Either faith or denial.",
			zone = "Temple",
			drawn = true,
		},
		{
			id = "KalikoriVillage",
			displayName = "Kalikori Village",
			kind = "Market",
			description = "A Twi'lek settlement that was here first and is repeatedly reminded that it was not asked.",
			zone = "Village",
			drawn = true,
		},
		{
			id = "TythonSpaceport",
			displayName = "Tython Landing",
			kind = "Spaceport",
			description = "One pad, one clerk, and a list of everyone who has ever come down it.",
			zone = "Spaceport",
			drawn = true,
		},
		{
			id = "TheGnarls",
			displayName = "The Gnarls",
			kind = "Outpost",
			description = "Wilderness the Order uses for training because it does not forgive inattention.",
			zone = "Gnarls",
		},
		{
			id = "ForgeRidge",
			displayName = "Forge Ridge",
			kind = "Ruin",
			-- The place the lightsaber chain ends, and it was a crashed
			-- freighter. A standing ring with an anvil and live coals at the
			-- centre is what the five quests have been walking towards.
			landmark = "Forge",
			description = "Where sabers are made. Getting up here is the easy half.",
			zone = "ForgeRidge",
		},
	},
})

def({
	id = "Taris",
	displayName = "Taris",
	description = "A city that died standing up. Twenty-eight thousand years of architecture, bombed flat from orbit and then left. Everything is at an angle.",
	coords = V3(1180, 260, -880),
	region = "Outer Rim",

	gravity = 196.2,
	terrain = "Urban",
	architecture = "Ruin",
	groundColor = Palette.WornSteel,
	rockColor = Palette.DarkMetal,
	terrainMaterial = Enum.Material.Asphalt,
	skyTint = Color3.fromRGB(150, 146, 138),
	fogColor = Color3.fromRGB(132, 128, 122),
	fogStart = 200,
	fogEnd = 2000,
	ambientLight = Color3.fromRGB(78, 76, 74),
	outdoorAmbient = Color3.fromRGB(124, 122, 118),
	dayLength = 0.4,
	windSpeed = 18,

	-- There is ground; it is just thirty metres of rubble on top of the old
	-- ground. The Undercity is what is under that.
	hasWalkableGround = true,

	-- Nominally a Republic resettlement effort. Czerka does the actual work,
	-- which is the joke the whole planet is built on.
	controllingFaction = "Republic",
	minLevel = 1,
	maxLevel = 26,
	lawLevel = 0.3,

	--[[
		THE RESETTLEMENT CAMP AND THE DIG, DRAWN RATHER THAN ROLLED

		The whole planet is one joke and the map is the punchline: a tidy
		Republic rectangle bolted onto the side of a hole in the ground.

		North of the fence is the colony, and it is drawn the way a colony
		that arrived in crates would be — identical two-cell huts in even
		ranks, four to a row, on a track grid nobody chose. Six of them, a
		mess hall, a muster square, and a wire perimeter with one gate in it.
		It is meant to look like a form someone filled in.

		South of the fence is Taris. Nothing lines up: leaning towers in
		clumps, spoil heaps, two sheds at angles to everything, and the
		twenty-eight thousand years of architecture the colony is standing on
		poking through the rubble. There is no wall around it because there
		is nothing here anyone would defend.

		The fence is the point. It is one glyph wide and one gate long, and
		it is the only thing on the planet the Republic actually finished.
	]]
	layout = {
		cell = 32,
		legend = {
			-- Wire, not stone: the Republic fenced the colony and nothing
			-- else. Written `#` rather than `W` because it is a different
			-- kind of thing from Anchorhead's town wall and the legend is
			-- per planet precisely so it can say so.
			["#"] = "Wall",
			G = "Gate",
			["."] = "Road",
			P = "Plaza",
			h = "House",
			s = "Shop",
			H = "Hall",
			T = "Tower",
			y = "Yard",
			l = "Lamp",
		},
		grid = {
			"########################",
			"#.hh.hh.hh.hh..ss..ss..#",
			"#.hh.hh.hh.hh..ss..ss..#",
			"#......................#",
			"#.hh.hh.hh.hh.....l....#",
			"#.hh.hh.hh.hh..........#",
			"#......................#",
			"#.HHHH..PPPP...........#",
			"#.HHHH..PPPP...........#",
			"########GG##############",
			"........................",
			"..TT....TTT.....TT......",
			"..TT....TTT.....TT......",
			"........................",
			".yyy...TT....HHH...TTTT.",
			".yyy...TT....HHH...TTTT.",
			"........................",
			"...TTT....HH....yyyy....",
			"...TTT....HH....yyyy....",
			".......l........l.......",
			"..TTT......TT......TTT..",
			"..TTT......TT......TTT..",
		},
	},

	zones = {
		{ id = "Camp", distance = 0, cells = { from = Vector2.new(2, 2), to = Vector2.new(15, 9) } },
		--[[
			The two shopfronts on the camp's east side, split off Camp at the
			same `distance` so the band is identical and only the casting
			changes. Korriban's Bazaar exists for the same reason, and the
			rule generalises: **a `Shop` room needs a district that can
			trade.** Placement fills the emptiest part first without caring
			who it is filling it with, so a district holding twenty-two
			refugees and three merchants will put a refugee behind the
			counter about seven times in eight, and the player walks in to a
			lit shop with no `Trade` prompt in it.

			A `Hall` has no such problem and is not split anywhere: nobody
			expects a particular job from a person standing in a mess tent.
		]]
		{ id = "Depot", distance = 0, cells = { from = Vector2.new(16, 2), to = Vector2.new(23, 9) } },
		--[[
			The first three rows past the gate, taken off the top of the Dig
			and given something to fight in them. Same reasoning as
			Korriban's TombApproach, which has the note: `distance` is a
			difficulty dial, so 0 bands this at the planet's floor, and
			`Radiant` writes a Cull for any district holding something
			Aggressive. Declared before the Dig because `cells` rectangles
			are resolved in order.

			The Scrapper prologue still walks a level 1 player through here
			on the way to the Dig, and that is now the point rather than the
			risk: the district bands 1-7 and the droids in it roll 2-7, so
			the walk out of camp is the first fight instead of a corridor.

			Rows 12-14 hold three tower blocks and nothing else -- no yards,
			no lamps, no halls -- so there is no anchor here for the builder
			to hand out as a player spawn, and no shopfront to staff.
		]]
		{ id = "SpoilLine", distance = 0, cells = { from = Vector2.new(2, 12), to = Vector2.new(23, 14) } },
		{ id = "Dig", distance = 0.5, cells = { from = Vector2.new(2, 15), to = Vector2.new(23, 22) } },
		{ id = "SinkingSector", distance = 1.2 },
		{ id = "Lot9", distance = 1.8 },
		{ id = "Undercity", distance = 2.4 },
	},
	spawns = {
		{ archetype = "Civilian", count = 22, zone = "Camp" },
		{ archetype = "RepublicTrooper", count = 6, zone = "Camp" },
		-- Five for five places: three on the track outside and the two
		-- shopfronts drawn on the camp's east side. The count is the number
		-- of parts the district has, not a guess at how busy it should look.
		{ archetype = "Merchant", count = 5, zone = "Depot" },
		--[[
			Czerka's survey droids, still working a claim Czerka abandoned,
			and claim-jumpers working the droids.

			`WarDroid` rolls 2-24 and `Smuggler` 3-24; the SpoilLine bands
			1-7, so they come out at 2-7 and 3-7 -- the only fight in the
			galaxy a freshly made character can walk to. Reported from play,
			2026-08-17: *"I don't have any other missions I can complete or a
			means to level up."*
		]]
		{
			archetype = "WarDroid",
			count = 6,
			zone = "SpoilLine",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{
			archetype = "Smuggler",
			count = 6,
			zone = "SpoilLine",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{ archetype = "Jawa", count = 8, zone = "Dig" },
		{ archetype = "Researcher", count = 6, zone = "Dig" },
		{ archetype = "ProtocolDroid", count = 4, zone = "Dig" },
		-- Scavengers who got to the Sinking Sector first and do not intend to
		-- share it. The Camp and the Dig stay peaceful on purpose: the
		-- Scrapper prologue sends a level 1 player into the Dig, and the
		-- "your level is too low" banner is gated on a district holding
		-- something aggressive.
		{
			archetype = "Smuggler",
			count = 8,
			zone = "SinkingSector",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		-- Collecting on behalf of whoever is left to collect from.
		{
			archetype = "CartelEnforcer",
			count = 6,
			zone = "SinkingSector",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		-- Czerka's security, which is a euphemism.
		{ archetype = "WarDroid", count = 10, zone = "Lot9", behavior = NPCArchetypes.Behavior.Aggressive },
		{
			archetype = "CartelEnforcer",
			count = 6,
			zone = "Undercity",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{
			archetype = "ImperialCommando",
			count = 4,
			zone = "Undercity",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
	},
	pointsOfInterest = {
		{
			id = "ResettlementCamp",
			displayName = "Resettlement Camp",
			kind = "Outpost",
			description = "The Republic's optimistic little colony. Prefab huts, one water plant, and a sign with a slogan on it.",
			zone = "Camp",
			drawn = true,
		},
		{
			id = "SpoilLine",
			displayName = "The Spoil Line",
			kind = "Ruin",
			-- `Radiant` writes a Salvage only for a district that has a POI
			-- and is not the hub, so this second entry is the difference
			-- between one repeatable mission out here and two.
			description = "Where the Dig throws what it cannot sell. Three survey towers and a very great deal of rust.",
			zone = "SpoilLine",
			-- The towers on rows 12-14 are already on the grid.
			drawn = true,
		},
		{
			id = "TheDig",
			displayName = "The Dig",
			kind = "Ruin",
			description = "Salvage cranes over a spoil heap the size of a hill. Everything anyone here owns came out of it.",
			zone = "Dig",
			drawn = true,
		},
		{
			id = "SinkingSector",
			displayName = "The Sinking Sector",
			kind = "Ruin",
			-- "Twenty degrees" is a number in the description, so the builder
			-- honours it exactly: four towers leaning about their feet at
			-- twenty degrees, catwalks between them, rubble banked where each
			-- one went in.
			landmark = "LeaningTowers",
			description = "Towers leaning at twenty degrees and still settling. You go up through them, not around.",
			zone = "SinkingSector",
		},
		{
			id = "CzerkaLot9",
			displayName = "Czerka Lot 9",
			kind = "Base",
			description = "A warehouse Czerka does not admit owning, on a planet nobody audits.",
			zone = "Lot9",
		},
		{
			id = "TheUndercity",
			displayName = "The Undercity",
			kind = "Cantina",
			description = "Below the rubble line. No sky, and the quiet is not the good kind.",
			zone = "Undercity",
		},
	},
})

def({
	id = "Korriban",
	displayName = "Korriban",
	description = "Red rock, no water, and a valley of mausoleums bigger than the city that serves them. Everything here is a grave with a door.",
	coords = V3(1420, -180, 340),
	region = "Outer Rim",

	gravity = 202,
	terrain = "Desert",
	architecture = "SithZiggurat",
	groundColor = Palette.ZabrakRust,
	rockColor = Palette.MustafarBasalt,
	-- Sandstone, not Sand: Korriban is the other "Desert" world and the two
	-- may not share a material. See `terrainMaterial` on PlanetDef.
	terrainMaterial = Enum.Material.Sandstone,
	skyTint = Color3.fromRGB(212, 118, 78),
	fogColor = Color3.fromRGB(140, 74, 52),
	fogStart = 300,
	fogEnd = 3000,
	-- Lifted from RGB(90, 52, 42) after the 2026-08-15 playtest: it was the
	-- darkest palette in the file and the valley read as black. It should feel
	-- like a hot red dusk, not like being underground.
	ambientLight = Color3.fromRGB(126, 82, 68),
	outdoorAmbient = Color3.fromRGB(176, 116, 92),
	dayLength = 0.45,
	windSpeed = 20,

	hasWalkableGround = true,
	controllingFaction = "Empire",
	-- The widest band in the game, and deliberately: this is the Acolyte's
	-- prologue *and* the Act 4 payoff. At level 3 the Valley is a skybox you
	-- walk past with locked doors on it. At level 40 the doors are the game.
	minLevel = 1,
	maxLevel = 46,
	lawLevel = 0.9,

	--[[
		THE VALLEY OF THE DARK LORDS, DRAWN RATHER THAN ROLLED

		The second authored map, and the one that says whether the first was a
		system or an anecdote. Anchorhead is a town: a wall, a plaza, streets
		on a rough square. This is not a town at all, and that is the point --
		it is a corridor with a wall across each end, and it has to come out
		of the same twelve glyphs.

		Read north to south, because that is the walk the game asks you to
		make. The Academy sits at the head of the valley behind its own wall:
		the ziggurat in the middle of rows 2-4, two lecture halls at its
		shoulders, the training hall below it, and the practice yards where
		eighteen acolytes stand around waiting for someone to take a swing at.
		Row 10 is the wall it keeps its students behind, and the gate in it is
		the only reason you ever leave.

		Then eleven rows of nothing but road and cliff. The four `tttt` blocks
		are the tomb facades -- the ones the Academy teaches you not to go
		into -- and the space between them is deliberately empty: it is the
		one stretch of this planet that is supposed to feel like being
		outdoors and outnumbered. Nothing is drawn there, so nothing softens
		it.

		At the mouth, Dreshdae. Czerka's office and the cantina on the west,
		the bazaar's two shopfronts on the east, and a small plaza between
		them where the road finally widens. The south gate is the way off the
		map.

		Two rules that are not visible in the picture:

		- **There is not one anchor cell in the valley.** `Plaza`, `Yard` and
		  `Lamp` are the cells the builder hands out as player spawn points,
		  and the valley bands 19-30 with fourteen aggressive war droids in
		  it. The avenue is `.` rather than `P` for exactly this reason: it
		  paves, so the crowd can stand on it, and it does not anchor, so
		  nobody wakes up on it. Every anchor on Korriban is inside the
		  Academy or inside Dreshdae.
		- 21 by 28 cells at 32 studs is 672 by 896, so the far corner is 560
		  studs out -- inside the 610 where `buildScatter` starts throwing
		  down rocks, which is the real limit on how big a grid may be.
	]]
	layout = {
		cell = 32,
		legend = {
			W = "Wall",
			G = "Gate",
			["."] = "Road",
			P = "Plaza",
			h = "House",
			s = "Shop",
			H = "Hall",
			t = "Tower",
			y = "Yard",
			l = "Lamp",
		},
		grid = {
			"WWWWWWWWWWWWWWWWWWWWW",
			"W.HH....ttttt....HH.W",
			"W.HH....ttttt....HH.W",
			"W.......ttttt.......W",
			"W........yyy........W",
			"W.yyyy...yyy...yyyy.W",
			"W.yyyy..HHHHH..yyyy.W",
			"W.yyyy..HHHHH..yyyy.W",
			"W...l...........l...W",
			"WWWWWWWWWGGGWWWWWWWWW",
			"WW.................WW",
			"WWtttt.........ttttWW",
			"WWtttt.........ttttWW",
			"WWtttt.........ttttWW",
			"WW.................WW",
			"WW.................WW",
			"WW.................WW",
			"WWtttt.........ttttWW",
			"WWtttt.........ttttWW",
			"WWtttt.........ttttWW",
			"WW.................WW",
			"W...................W",
			"W.hhh.HHH...sss.hhh.W",
			"W.hhh.HHH...sss.hhh.W",
			"W...l....PPP....l...W",
			"W.HHHH.hhPPPhh.ssss.W",
			"W.HHHH.hhPPPhh.ssss.W",
			"WWWWWWWWWGGGWWWWWWWWW",
		},
	},

	zones = {
		--[[
			`distance` is untouched, so every band on this planet is the same
			number it was before the map existed. `cells` only says where.

			The Valley's rectangle is the reason `rectExtents` exists.
			Seventeen cells across and eleven deep is not a circle, and the
			circle that contains it reaches into the Academy at one end --
			where a level 1 Acolyte opens their eyes, nineteen levels under
			the honour guard.
		]]
		{ id = "Academy", distance = 0, cells = { from = Vector2.new(2, 2), to = Vector2.new(20, 9) } },
		--[[
			THE FIRST FIGHT, AND WHY IT IS AT DISTANCE 0

			Reported from play, 2026-08-17: *"I don't have any other missions
			I can complete or a means to level up. I should be able to
			discover random tasks or go out of camp to combat raiders."*

			The Academy bands 1-12 and is deliberately peaceful -- it is the
			Acolyte's spawn point. The only road out was the Valley, which
			bands 19-30. So the nearest thing on this planet that would fight
			a level 1 character was eighteen levels above them, and because
			`Radiant` only writes a Cull where something is `Aggressive`, the
			one district every Acolyte lives in generated no repeatable work
			either. Two story missions at 3 and 7, then nothing until 19.

			`distance` is a difficulty dial and not a map coordinate -- the
			Valley already sits at 1.4 between two districts at 0 and 0.6 --
			so this takes 0 to band at the planet's own floor. It is the same
			same-distance split the Bazaar is, for the same reason: the
			rectangle decides where, `distance` decides how hard.

			**It takes the first four tomb facades and no anchors.** Rows
			11-14 are road and Tower, so there is nothing here the builder
			hands out as a player spawn, which is what keeps a fresh Acolyte
			from waking up in the middle of it.
		]]
		{
			id = "TombApproach",
			distance = 0,
			cells = { from = Vector2.new(3, 11), to = Vector2.new(19, 14) },
		},
		{ id = "Dreshdae", distance = 0.6, cells = { from = Vector2.new(2, 22), to = Vector2.new(12, 28) } },
		--[[
			Split off Dreshdae at the same distance, so it bands identically
			and is the same place as far as the difficulty curve is
			concerned. It exists because a district is also a casting call:
			Dreshdae mixes civilians, researchers and traders, and placement
			fills the emptiest part first without caring who it is filling it
			with -- which puts a farmer behind the counter and the merchants
			out on the street. Two shopfronts in a district that contains
			nothing but merchants cannot be staffed by anyone else.
		]]
		{ id = "Bazaar", distance = 0.6, cells = { from = Vector2.new(13, 22), to = Vector2.new(20, 28) } },
		-- Gives up rows 11-14 to the TombApproach above. It keeps the second
		-- pair of facades and the far half of the avenue, which is still the
		-- long walk the Act 4 payoff wants.
		{ id = "Valley", distance = 1.4, cells = { from = Vector2.new(3, 15), to = Vector2.new(19, 21) } },
		{ id = "Tombs", distance = 2.0 },
		{ id = "Wastes", distance = 2.6 },
	},
	spawns = {
		--[[
			Your classmates, and not your problem yet.

			The Academy bands 1-12 and these are the Acolyte origin's spawn
			point, so eighteen aggressive level 22 Sith stood on the exact
			square metre a new Acolyte opens their eyes on. Overridden to
			Guard: they will still fight if you start it, which is what the
			duelling-pit missions want, and they will not open with it.
		]]
		{ archetype = "SithAcolyte", count = 18, zone = "Academy", behavior = NPCArchetypes.Behavior.Guard },
		{ archetype = "ImperialTrooper", count = 10, zone = "Academy" },
		--[[
			Czerka keeps the Academy's records, which is the whole of The
			Quiet in one spawn rule: the form that collects an acolyte was
			printed by a contractor.

			Mechanically they are here because the Academy had nobody in it
			who could be spoken to. `SithAcolyte` and `ImperialTrooper` are
			both `interactable = false`, so the Acolyte prologue's "ask
			around" objective had to be sent to Dreshdae -- and the only road
			from here to Dreshdae is the Valley, which bands 19-30 and holds
			twenty-two aggressive things. The origin's first mission walked a
			level 1 character into it. Reported from play, 2026-08-17.
		]]
		{ archetype = "Researcher", count = 4, zone = "Academy" },
		--[[
			The same classmates, one gate further out, with the safety off.

			`SithAcolyte` is `Aggressive` in its own archetype -- the Academy
			rule above is the exception, not this one -- and it rolls 2-14,
			which clamps into the TombApproach's 1-12 band without pinning.
			That is the whole fix: `Radiant` writes a Cull wherever something
			is Aggressive, so this one rule posts a repeatable level 1 hunt
			outside the door of the district every Acolyte spawns in.

			It is also the honest version of Korriban. The Academy does not
			forbid students killing each other; it forbids doing it indoors.
		]]
		{
			archetype = "SithAcolyte",
			count = 10,
			zone = "TombApproach",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{ archetype = "Civilian", count = 16, zone = "Dreshdae" },
		{ archetype = "Researcher", count = 4, zone = "Dreshdae" },
		-- Six for five places: three points on the avenue and the two
		-- shopfronts drawn on the east side. Placement fills the emptiest
		-- first, so that is one trader behind each counter and the rest out
		-- front, and the planet's "only vendor" line stops being a lie about
		-- a locked door.
		{ archetype = "Merchant", count = 6, zone = "Bazaar" },
		{
			archetype = "SithHonourGuard",
			count = 8,
			zone = "Valley",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		-- Stand-ins for tuk'ata and shyracks until the game has a non-humanoid
		-- rig. Same job: the thing out of town that kills you. Pulled in from
		-- the Wastes, which band 35-46 -- eleven levels past a war droid's
		-- ceiling even after widening it -- to the Valley, which they fit.
		{ archetype = "WarDroid", count = 14, zone = "Valley", behavior = NPCArchetypes.Behavior.Aggressive },
		{
			archetype = "ImperialCommando",
			count = 6,
			zone = "Tombs",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		-- Out to the Wastes with him. He is level 40-50 and the Tombs band
		-- 27-38, so the planet's single most dangerous thing was spawning
		-- two levels under the guards posted in front of it.
		{ archetype = "SithLord", count = 1, zone = "Wastes" },
		{
			archetype = "SithHonourGuard",
			count = 14,
			zone = "Wastes",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
	},
	pointsOfInterest = {
		{
			id = "SithAcademy",
			displayName = "The Academy",
			kind = "Base",
			description = "Dormitories, training pits, and an Overseer who has been keeping notes for thirty years.",
			zone = "Academy",
			-- The ziggurat and its halls are cells on the grid. A `Base` is
			-- 92 studs wide, too big for a city block, so the generator would
			-- have shoved this one six hundred studs north of the Academy --
			-- with the students still standing in the Academy.
			drawn = true,
		},
		{
			id = "Dreshdae",
			displayName = "Dreshdae",
			kind = "Market",
			description = "The one settlement. A Czerka office, a cantina, and the only vendor on the planet.",
			zone = "Dreshdae",
			drawn = true,
		},
		{
			id = "TombApproach",
			displayName = "The Lower Approach",
			kind = "Ruin",
			-- A POI here is not decoration. `Radiant` writes a Salvage only
			-- for a district that has one and is not the hub, so this is
			-- what turns one repeatable mission into two.
			description = "The first four facades, robbed centuries ago. Acolytes settle things here where the Overseers cannot see.",
			zone = "TombApproach",
			-- The facades are the `tttt` blocks on rows 12-14. Already drawn.
			drawn = true,
		},
		{
			id = "ValleyOfTheDarkLords",
			displayName = "Valley of the Dark Lords",
			kind = "Temple",
			landmark = "Temple",
			description = "Four tomb facades cut into the cliffs. The Academy teaches students not to go in.",
			zone = "Valley",
			-- Four of them, and they are the `tttt` blocks in the cliff wall.
			-- One temple standing in the middle of the avenue would be a
			-- worse answer than the picture already is.
			drawn = true,
		},
		{
			id = "TombOfTulakHord",
			displayName = "Tomb of Tulak Hord",
			kind = "Ruin",
			-- The worst case in the game before this line existed: `Ruin`
			-- means "something that used to fly, nose-down in the ground",
			-- so a world whose entire claim on the player is that it is a
			-- valley of tombs had a crashed freighter in it with a sign
			-- saying TOMB. A cut facade with a filled doorway is the whole
			-- description -- sealed, and by someone who meant it.
			landmark = "Tomb",
			description = "Sealed, and the seal is not there to keep anything in.",
			zone = "Tombs",
		},
		{
			id = "KorribanWastes",
			displayName = "The Wastes",
			kind = "Outpost",
			description = "Shyrack caves and a red horizon. Nobody patrols this and nobody needs to.",
			zone = "Wastes",
		},
	},
})

def({
	id = "NarShaddaa",
	displayName = "Nar Shaddaa",
	description = "The Smuggler's Moon. Everything is for sale and most of it is a trap.",
	coords = V3(640, 90, -220),
	region = "Mid Rim",

	gravity = 182,
	terrain = "Urban",
	architecture = "NeonStack",
	groundColor = Palette.CoruscantPlate,
	rockColor = Palette.DarkMetal,
	terrainMaterial = Enum.Material.Pavement,
	skyTint = Color3.fromRGB(126, 96, 138),
	fogColor = Color3.fromRGB(72, 58, 82),
	fogStart = 200,
	fogEnd = 2200,
	ambientLight = Color3.fromRGB(72, 60, 84),
	outdoorAmbient = Color3.fromRGB(110, 96, 126),
	dayLength = 0.3,

	hasWalkableGround = true,
	flightCeiling = 1100,
	-- Thinner than Coruscant's, and lower, because half of it is not
	-- supposed to be there. A smuggler's moon with an empty sky is a
	-- smuggler's moon nobody is smuggling anything off.
	airTraffic = 12,

	controllingFaction = "Hutt",
	minLevel = 12,
	maxLevel = 45,
	lawLevel = 0.0, -- nobody is coming to help you

	--[[
		THE PROMENADE, THE MARKET, THE DOCKS AND THE REFUGE

		The fifth authored grid, and the first that is a city rather than a
		settlement. So it is drawn the opposite way round to Fort Garnik:
		nothing here is symmetrical, no two stalls are the same width, and
		there is no open ground anywhere -- every road is one cell wide and
		has a building pressed against both sides of it. A moon that sold
		its last empty square metre a thousand years ago.

		One bulkhead across the middle with two gates in it, and that line
		is the whole social geography of the place. North of it people shop.
		South of it are the docks and the refugee sector, which is where the
		moon puts the people it has finished with, and **neither of them
		holds one anchor cell**: between them they contain thirty-eight
		hunters and troopers who shoot on sight, and anchors are where
		players spawn.

		Six shopfronts, because PLANETS.md promises "every vendor in the
		game" here and until now the moon had no interior at all.
	]]
	layout = {
		cell = 32,
		legend = {
			W = "Wall",
			G = "Gate",
			["."] = "Road",
			P = "Plaza",
			h = "House",
			s = "Shop",
			H = "Hall",
			T = "Tower",
			l = "Lamp",
		},
		grid = {
			"TT..hhh..hhh....sss..ss...",
			"TT..hhh..hhh....sss..ss...",
			"..........................",
			"hh..HHHH...hh..ss...sss...",
			"hh..HHHH...hh..ss...sss...",
			"..l........l.....l........",
			"PPP.......PPP...ss..ss....",
			"PPP.......PPP...ss..ss....",
			"..........................",
			"hh..HHHH..hhh...PP...PP...",
			"hh..HHHH..hhh.............",
			"WWWWWGGWWWWWWWWWWWGGWWWWWW",
			"..........................",
			".TT.....TT.....hh...hh....",
			".TT.....TT.....hh...hh....",
			"..........................",
			"hhh..hhh..hhh.hh..hh..hh..",
			"hhh..hhh..hhh.hh..hh..hh..",
			"..........................",
			".TT...TT...TT...T.....T...",
			".TT...TT...TT.............",
			"...............hh..hh..hh.",
			"hhhh...hhhh....hh..hh..hh.",
			"hhhh...hhhh...............",
			"..............hhh....hhh..",
			"..............hhh....hhh..",
		},
	},

	zones = {
		{ id = "Promenade", distance = 0, cells = { from = Vector2.new(1, 1), to = Vector2.new(14, 11) } },
		{ id = "Market", distance = 0.35, cells = { from = Vector2.new(15, 1), to = Vector2.new(26, 11) } },
		{ id = "Docks", distance = 0.8, cells = { from = Vector2.new(1, 13), to = Vector2.new(13, 26) } },
		{ id = "Refuge", distance = 1.4, cells = { from = Vector2.new(14, 13), to = Vector2.new(26, 26) } },
	},
	spawns = {
		{ archetype = "Civilian", count = 26, zone = "Promenade" },
		{ archetype = "Smuggler", count = 16, zone = "Docks" },
		{ archetype = "ShipBroker", count = 1, zone = "Docks" },
		{ archetype = "Merchant", count = 10, zone = "Market" },
		{ archetype = "CartelEnforcer", count = 18, zone = "Promenade" },
		{
			archetype = "BountyHunter",
			count = 10,
			zone = "Docks",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		-- Moved out of the Market once the market grew counters. Emptiest-first
		-- placement does not care who it stands behind one, and a protocol
		-- droid is not a shopkeeper; a district with shops in it should
		-- contain shopkeepers and nothing else.
		{ archetype = "ProtocolDroid", count = 6, zone = "Promenade" },
		-- The Empire has no writ on a Hutt moon, which is exactly why it keeps
		-- a garrison at the docks -- and why there is a standing bounty on the
		-- uniform. Without them the open contract counts nothing. Aggressive
		-- because a garrison with a price on its head does not wait to be
		-- addressed, and because the contract is fifteen kills and used to
		-- require you to throw the first punch fifteen times.
		{
			archetype = "ImperialTrooper",
			count = 16,
			zone = "Docks",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		-- The refugee sector needs somebody living in it, or the mission that
		-- sends you there is a walk to an empty marker.
		{ archetype = "Jawa", count = 6, zone = "Refuge" },
		{ archetype = "Civilian", count = 14, zone = "Refuge" },
		-- And somebody preying on them. The Refuge bands 37-45 and was the
		-- softest district on the moon, which is backwards for its far edge.
		{
			archetype = "BountyHunter",
			count = 12,
			zone = "Refuge",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
	},
	pointsOfInterest = {
		{
			id = "Promenade",
			displayName = "The Promenade",
			kind = "Market",
			description = "Neon over neon. Buy anything, and be bought if you are careless.",
			zone = "Promenade",
			drawn = true,
		},
		{
			id = "RefugeeSector",
			displayName = "Refugee Sector",
			kind = "Ruin",
			description = "Where the moon puts the people it has finished with.",
			zone = "Refuge",
			drawn = true,
		},
		{
			id = "NarDocks",
			displayName = "Docking Bay 41",
			kind = "Spaceport",
			description = "No manifests, no inspections, double the docking fee.",
			zone = "Docks",
			-- A `Spaceport` is 116 studs wide, so without this the berths
			-- get shoved 676 studs clear of the freighters they belong to.
			drawn = true,
		},
	},
})

def({
	id = "OrdMantell",
	displayName = "Ord Mantell",
	description = "Mud, rain, and a war being fought over a hill nobody can name. A Republic world losing a grubby civil war to its own separatists.",
	coords = V3(-680, 40, -420),
	region = "Mid Rim",

	gravity = 194,
	terrain = "Swamp",
	architecture = "Frontier",
	groundColor = Color3.fromRGB(88, 84, 62),
	rockColor = Palette.SmugglerBrown,
	terrainMaterial = Enum.Material.Mud,
	skyTint = Color3.fromRGB(150, 156, 152),
	fogColor = Color3.fromRGB(122, 128, 122),
	-- Was 80/1200 with a much thicker Swamp air mix, which put a grey wall
	-- about forty studs out and hid every landmark on the planet. Still the
	-- haziest world that is not Hoth; it just no longer blinds you.
	fogStart = 220,
	fogEnd = 2400,
	ambientLight = Color3.fromRGB(104, 110, 104),
	outdoorAmbient = Color3.fromRGB(150, 158, 150),
	dayLength = 0.35,
	windSpeed = 14,

	hasWalkableGround = true,
	controllingFaction = "Republic",
	-- The smallest planet in the game and the only one you never come back to.
	-- One town, one battlefield, one swamp -- so the band is narrow on purpose.
	minLevel = 1,
	maxLevel = 6,
	lawLevel = 0.5,

	--[[
		FORT GARNIK, DRELLIAD, AND THE FIELDS

		Three places on one page, and the argument between them is the
		Conscript's whole prologue.

		The fort is symmetrical and it is the only thing here that is:
		barracks either side of a muster square, a mess and an armoury behind
		them, a watchtower on each front corner, sandbags all the way round
		and one gate. It is a diagram of an army. Everything the army is
		actually doing is south of that gate.

		Drelliad is the same eight shacks the army's report calls a village,
		with a hall and a market row a few rows further down. No wall, because
		it has been liberated three times and a wall would only have told
		somebody where to start.

		The Savrip Fields are the east half, and they are drawn with the same
		glyph as the fort's sandbags — four trench lines with the gaps in
		different places, an observation tower, and nothing else at all. That
		is the tile map doing the one thing PLANETS.md said it was for:
		a trench is a row of one character.

		**No anchor cell east of column 13.** The Fields band above the fort
		and hold fourteen aggressive militia, and anchors are where players
		spawn.
	]]
	layout = {
		cell = 32,
		legend = {
			W = "Wall",
			G = "Gate",
			["."] = "Road",
			P = "Plaza",
			h = "House",
			s = "Shop",
			H = "Hall",
			T = "Tower",
			-- No `Yard`. Every anchor cell on this planet is deliberate and
			-- there are only twenty-nine of them; a glyph that means "open
			-- ground you can also spawn on" is exactly the one that would
			-- get sprinkled into the Fields without anybody noticing.
			l = "Lamp",
		},
		grid = {
			"WWWWWWWWWWWWWWWWWWWWWWWWWW",
			"WT......................TW",
			"W..HHHH....PPPP....HHHH..W",
			"W..HHHH....PPPP....HHHH..W",
			"W..........PPPP..........W",
			"W..HHHH....PPPP....HHHH..W",
			"W..HHHH....PPPP....HHHH..W",
			"W...l................l...W",
			"WWWWWWWWWWWWGGWWWWWWWWWWWW",
			"..........................",
			".hh..hh..hh...............",
			".hh..hh..hh..WWWWW.WWWWWWW",
			"..........................",
			".hh..HHH.hh...............",
			".hh..HHH.hh..WWWWWWW.WWWWW",
			"...l......................",
			"..........................",
			".............WWW.WWWWW.WWW",
			".sss...hh.................",
			".sss...hh.........TT......",
			"..................TT......",
			"...PPP.......WWWWWW.WWWWWW",
			"...PPP....................",
			"..........................",
		},
	},

	zones = {
		{ id = "Garrison", distance = 0, cells = { from = Vector2.new(2, 2), to = Vector2.new(25, 8) } },
		{ id = "Village", distance = 0.5, cells = { from = Vector2.new(1, 11), to = Vector2.new(12, 16) } },
		-- Split off Drelliad at the same `distance`, for the reason Taris's
		-- Depot is: the one shopfront on the planet cannot be staffed by a
		-- frightened farmer, and eighteen civilians against two merchants is
		-- what the district would otherwise be casting from.
		{ id = "Market", distance = 0.5, cells = { from = Vector2.new(1, 18), to = Vector2.new(12, 23) } },
		{ id = "Fields", distance = 1.3, cells = { from = Vector2.new(14, 11), to = Vector2.new(26, 24) } },
		{ id = "Wilds", distance = 2.0 },
	},
	spawns = {
		{ archetype = "RepublicTrooper", count = 20, zone = "Garrison" },
		{ archetype = "RepublicVeteran", count = 6, zone = "Garrison" },
		{ archetype = "ProtocolDroid", count = 3, zone = "Garrison" },
		{ archetype = "Merchant", count = 4, zone = "Market" },
		-- Frightened, and not grateful. They have been liberated three times.
		{ archetype = "Civilian", count = 18, zone = "Village" },
		--[[
			Stand-in for the Separatist Militia archetype, which does not exist
			yet: poorly armed irregulars are the closest thing the roster has.

			They shoot. This is a civil war and they are the other side of it,
			and it is the Conscript's home world -- the four districts here
			band 1-3, 2-4, 3-5 and 4-6, which is the gentlest slope in the
			galaxy and had nothing standing on it. The Garrison and the
			Village stay safe.
		]]
		{ archetype = "Smuggler", count = 14, zone = "Fields", behavior = NPCArchetypes.Behavior.Aggressive },
		{ archetype = "Smuggler", count = 8, zone = "Wilds", behavior = NPCArchetypes.Behavior.Aggressive },
	},
	pointsOfInterest = {
		{
			id = "FortGarnik",
			displayName = "Fort Garnik",
			kind = "Base",
			description = "Barracks, an armoury, and a sergeant who has stopped pretending this is going anywhere.",
			zone = "Garrison",
			-- The fort is the grid: four barracks blocks, a muster square and
			-- a rampart. A 92-stud `Base` dropped on top of it would be a
			-- second, rounder fort standing beside the real one.
			drawn = true,
		},
		{
			id = "DrelliadVillage",
			displayName = "Drelliad Village",
			kind = "Market",
			description = "Liberated three times. Nobody here waves at the column any more.",
			zone = "Village",
			drawn = true,
		},
		{
			id = "SavripFields",
			displayName = "The Savrip Fields",
			kind = "Outpost",
			description = "Trenches, wire and artillery craters, over a hill with no name on any map.",
			zone = "Fields",
			-- The trench lines are the landmark. An `Outpost` hut in the
			-- middle of them would be the one building nobody dug in.
			drawn = true,
		},
		{
			id = "JaggedWilds",
			displayName = "The Jagged Wilds",
			kind = "Ruin",
			description = "Swamp, separatist camps, and a wreck you are not supposed to find.",
			zone = "Wilds",
		},
	},
})

def({
	id = "DromundKaas",
	displayName = "Dromund Kaas",
	description = "Permanent storm over the Sith Empire's capital. Lightning, black stone, and a jungle that is aggressively alive.",
	coords = V3(1680, -60, 780),
	region = "Outer Rim",

	gravity = 198,
	terrain = "Forest",
	architecture = "ImperialGothic",
	groundColor = Color3.fromRGB(52, 58, 48),
	rockColor = Palette.ImperialBlack,
	-- LeafyGrass, not Grass: Tython is the other "Forest" world.
	terrainMaterial = Enum.Material.LeafyGrass,
	skyTint = Color3.fromRGB(88, 92, 108),
	fogColor = Color3.fromRGB(58, 62, 74),
	fogStart = 120,
	fogEnd = 1600,
	ambientLight = Color3.fromRGB(48, 52, 62),
	outdoorAmbient = Color3.fromRGB(82, 88, 102),
	-- The storm never breaks, so the day barely reads as one. Long cycle.
	dayLength = 0.6,
	windSpeed = 34,

	hasWalkableGround = true,
	controllingFaction = "Empire",
	minLevel = 46,
	maxLevel = 50,
	-- Total order, which is not the same as safety.
	lawLevel = 1.0,

	--[[
		KAAS CITY, THE NEXUS ROAD AND THE DARK TEMPLE, DRAWN RATHER THAN ROLLED

		The last world in the game, so it is drawn as a diagram of a state.

		Kaas City is the only settlement in the galaxy laid out on a true
		lattice: sixteen identical blocks, four to a rank, every street the
		same width, a parade ground bored through the middle of it. Anchorhead
		is crooked because it grew; this is straight because it was issued.
		Two spires flank the gate from the inside, which is where the Empire
		puts a tower -- watching the road, and everyone on it.

		The Nexus Road is the point of the map. It is four cells wide and five
		long with a rampart down each side and no way off it, because the
		description has always said it is guarded in *both* directions. Ten
		Honour Guard live in that corridor and they are aggressive, so there
		is not one anchor cell between the walls: nobody spawns on this road,
		they only ever walk onto it.

		The Dark Temple grounds are what the same architecture looks like when
		it is older than the people maintaining it -- the same black walls, in
		fragments, with the paving surviving only where the road comes in. Its
		hall is the one room in the game meant to be entered under fire.

		The Exchange is split off the city at the *same* distance, the rule
		every drawn world has followed since Korriban: a `Shop` hands its
		counter to whoever its district spawns, so the district has to be all
		traders.
	]]
	layout = {
		cell = 32,
		legend = {
			W = "Wall",
			G = "Gate",
			["."] = "Road",
			P = "Plaza",
			h = "House",
			s = "Shop",
			H = "Hall",
			T = "Tower",
			l = "Lamp",
		},
		grid = {
			"WWWWWWWWWWWWWWWWWWWWWWWWWW",
			"W.hhhh..hhhh..hhhh..ssss.W",
			"W.hhhh..hhhh..hhhh..ssss.W",
			"W........................W",
			"W.HHHH..PPPPPPPPPP..ssss.W",
			"W.HHHH..PPPPPPPPPP..ssss.W",
			"W.......PPPPPPPPPP.......W",
			"W.hhhh..PPPPPPPPPP..ssss.W",
			"W.hhhh..PPPPPPPPPP..ssss.W",
			"W........................W",
			"W.HHHH..hhhh..hhhh..hhhh.W",
			"W.HHHH..hhhh..hhhh..hhhh.W",
			"Wl........T..T..........lW",
			"WWWWWWWWWWWGGWWWWWWWWWWWWW",
			"         W....W           ",
			"         W....W           ",
			"         W....W           ",
			"         W....W           ",
			"         W....W           ",
			"  WWWWW   ....   WWWWW    ",
			"          ....            ",
			"  W    HHHHHHHH      W    ",
			"  W    HHHHHHHH      W    ",
			"  W    HHHHHHHH      W    ",
			"                          ",
			"  WWW      WWWW     WWW   ",
		},
	},

	zones = {
		{ id = "KaasCity", distance = 0, cells = { from = Vector2.new(1, 1), to = Vector2.new(19, 14) } },
		-- Same distance as the city: a trading district, not a level band.
		{ id = "Exchange", distance = 0, cells = { from = Vector2.new(20, 1), to = Vector2.new(26, 14) } },
		-- The corridor only, not the jungle either side of it -- a patrol
		-- ring inscribed in the wider rectangle would put Honour Guard on top
		-- of their own ramparts.
		{
			id = "NexusRoad",
			distance = 1.1,
			cells = { from = Vector2.new(11, 15), to = Vector2.new(14, 19) },
		},
		{
			id = "DarkTemple",
			distance = 1.9,
			cells = { from = Vector2.new(1, 20), to = Vector2.new(26, 26) },
		},
	},
	spawns = {
		{ archetype = "ImperialOfficer", count = 12, zone = "KaasCity" },
		{ archetype = "ImperialTrooper", count = 22, zone = "KaasCity" },
		{ archetype = "Civilian", count = 20, zone = "KaasCity" },
		-- Six, in the Exchange: three counters and a ring of three.
		{ archetype = "Merchant", count = 6, zone = "Exchange" },
		{
			archetype = "SithHonourGuard",
			count = 10,
			zone = "NexusRoad",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{ archetype = "ImperialCommando", count = 8, zone = "NexusRoad" },
		-- Honour Guard rather than acolytes at the Dark Temple: this is the
		-- last district in the game, banding 48-50, and an acolyte tops out
		-- at 38. The endgame world's endgame district was spawning enemies
		-- ten levels under it.
		{
			archetype = "SithHonourGuard",
			count = 10,
			zone = "DarkTemple",
			behavior = NPCArchetypes.Behavior.Aggressive,
		},
		{ archetype = "SithLord", count = 2, zone = "DarkTemple" },
	},
	pointsOfInterest = {
		{
			id = "KaasCitadel",
			displayName = "The Citadel",
			kind = "Base",
			description = "The Dark Council's antechambers. Everyone here is waiting to be seen by someone worse.",
			zone = "KaasCity",
			drawn = true,
		},
		{
			id = "NexusRoad",
			displayName = "The Nexus Road",
			kind = "Outpost",
			description = "The road out of the city, guarded the whole way, in both directions.",
			zone = "NexusRoad",
			drawn = true,
		},
		{
			id = "DarkTempleGrounds",
			displayName = "Dark Temple Grounds",
			kind = "Temple",
			description = "Black walls in the rain, and a household that has kept them for longer than anyone can account for.",
			zone = "DarkTemple",
			drawn = true,
		},
	},
})

--------------------------------------------------------------------------------

Planets.defs = defs
Planets.STARTING_PLANET = "Tatooine"

-- Travel economics. Tuned so a mid-galaxy hop is a few hundred credits and a
-- full-tank ship crosses roughly two long jumps before refuelling.
Planets.FUEL_PER_UNIT = 0.012
Planets.CREDITS_PER_UNIT = 0.9
Planets.MIN_FAST_TRAVEL_COST = 120

function Planets.get(id: string): PlanetDef
	local p = defs[id]
	assert(p, `Planets.get: unknown planet "{id}"`)
	return p
end

function Planets.exists(id: string): boolean
	return defs[id] ~= nil
end

--- Whether `planetId` defines the point of interest `poiId`.
function Planets.hasPOI(planetId: string, poiId: string): boolean
	local p = defs[planetId]
	if not p then
		return false
	end
	for _, poi in p.pointsOfInterest do
		if poi.id == poiId then
			return true
		end
	end
	return false
end

--- The point of interest itself, if `planetId` defines one called `poiId`.
function Planets.getPOI(planetId: string, poiId: string): PointOfInterest?
	local p = defs[planetId]
	if not p then
		return nil
	end
	for _, poi in p.pointsOfInterest do
		if poi.id == poiId then
			return poi
		end
	end
	return nil
end

--- Whether `planetId` declares a district called `zoneId`.
function Planets.hasZone(planetId: string, zoneId: string): boolean
	local p = defs[planetId]
	if not p then
		return false
	end
	for _, zone in p.zones do
		if zone.id == zoneId then
			return true
		end
	end
	return false
end

--[[
	The level range of everything that lives in one district.

	Derived from `ZoneDef.distance` rather than authored, because the planet
	already declares `minLevel`..`maxLevel` and the zones already declare how
	far out they are: the band is what those two facts mean together. Writing
	it out per zone would be 45 restatements of an existing number, and the
	first time a district moved, 45 chances to forget.

	Spread across the planet's *own* span of distances, not a galaxy-wide
	scale, so every world uses its whole level range whether its districts run
	out to 1.6 (Tatooine) or 2.6 (Korriban). The innermost district starts at
	the planet's floor and the outermost ends at its ceiling.

	`ZoneDef.band` overrides all of this, for the districts where difficulty
	and remoteness genuinely disagree.
]]
function Planets.bandFor(planetId: string, zoneId: string): Band
	local p = Planets.get(planetId)

	local zone: ZoneDef? = nil
	local nearest, furthest = math.huge, -math.huge
	for _, z in p.zones do
		if z.id == zoneId then
			zone = z
		end
		nearest = math.min(nearest, z.distance)
		furthest = math.max(furthest, z.distance)
	end

	-- An undeclared zone gets the whole planet, which is the honest answer:
	-- nothing is known about where it is. `Planets.validate` reports it
	-- separately, so this does not need to be an error as well.
	if not zone then
		return { min = p.minLevel, max = p.maxLevel }
	end
	if zone.band then
		return zone.band
	end

	local span = math.max(0, p.maxLevel - p.minLevel)
	local width = math.max(Planets.BAND_MIN_WIDTH, math.round(span * Planets.BAND_WIDTH))
	-- The band slides rather than stretches, so every district is the same
	-- width and only its floor moves outward.
	local travel = math.max(0, span - width)

	-- A planet whose districts are all at one distance -- or which has one
	-- district -- puts everything in the innermost band rather than dividing
	-- by zero.
	local reach = furthest - nearest
	local t = if reach > 0 then (zone.distance - nearest) / reach else 0

	local low = p.minLevel + math.round(t * travel)
	return { min = low, max = math.min(p.maxLevel, low + width) }
end

--[[
	Whether `level` is far enough under `band` to be worth interrupting for.

	Here rather than in the controller that draws the warning, because the
	server picks NPC levels from the same bands and any second opinion about
	what "too low" means would be a warning that does not match the fight.
]]
function Planets.underlevelled(level: number, band: Band): boolean
	return band.min - level > Planets.UNDERLEVELLED_BY
end

--[[
	The level of the weakest thing on this planet that will attack you, or nil
	if nothing will.

	Not `minLevel` of the archetype and not `band.min` of the district: the
	number an NPC can actually roll, which is the two of them clamped
	together. That distinction is the entire reason this function exists.
	A district can band 1-12 and still contain nothing under level 5, because
	`rollLevel` clamps the band into the archetype's range -- so "the band
	starts at 1" is not the same claim as "there is a level 1 fight here",
	and only the second one is any use to a new character.

	Asked by `Origins.validate`, which cannot compute it: it would need
	NPCArchetypes, and this module already has it.
]]
function Planets.lowestHostileLevel(planetId: string): number?
	local p = defs[planetId]
	if not p then
		return nil
	end
	local lowest: number? = nil
	for _, rule in p.spawns do
		if not NPCArchetypes.exists(rule.archetype) then
			continue
		end
		local a = NPCArchetypes.get(rule.archetype)
		-- Anything else fights only at Hostile reputation, which a new
		-- character does not have with anyone. See the `aggressive == 0`
		-- check in `validate` for the same reasoning at planet scale.
		if (rule.behavior or a.behavior) ~= NPCArchetypes.Behavior.Aggressive then
			continue
		end
		local band = if rule.zone then Planets.bandFor(planetId, rule.zone) else nil
		local low = if band then math.clamp(band.min, a.minLevel, a.maxLevel) else a.minLevel
		if not lowest or low < lowest then
			lowest = low
		end
	end
	return lowest
end

--- Whether `archetypeId` appears anywhere in this planet's spawn rules.
function Planets.spawnsArchetype(planetId: string, archetypeId: string): boolean
	local p = defs[planetId]
	if not p then
		return false
	end
	for _, rule in p.spawns do
		if rule.archetype == archetypeId then
			return true
		end
	end
	return false
end

--[[
	How many columns and rows an authored grid has.

	Columns come from the longest row rather than the first, so one short line
	reads as open ground on its east end instead of shifting the whole town
	half a block west of where the picture says it is. `validate` still
	reports the ragged row; this is what happens in the meantime.
]]
function Planets.layoutSize(layout: LayoutDef): (number, number)
	local columns = 0
	for _, row in layout.grid do
		columns = math.max(columns, #row)
	end
	return columns, #layout.grid
end

--[[
	Where the centre of cell (column, row) sits, relative to the settlement.

	The grid is centred on the origin with north at the top, so column 1 is
	the west edge, row 1 the north edge, and increasing row means increasing
	Z. One function rather than two so the builder that puts a house down and
	the marker code that decides which district the house is in cannot end up
	half a cell apart.
]]
function Planets.cellOffset(layout: LayoutDef, column: number, row: number): Vector3
	local columns, rows = Planets.layoutSize(layout)
	local half = layout.cell
	return Vector3.new((column - (columns + 1) / 2) * half, 0, (row - (rows + 1) / 2) * half)
end

--[[
	The centre of a district rectangle, and how far the district reaches.

	Reach is half the longer side *plus half a cell*, because the rectangle is
	inclusive of its end cells: without the extra half, standing in the corner
	shop of the market would not count as being in the market.
]]
function Planets.rectBounds(layout: LayoutDef, rect: CellRect): (Vector3, number)
	local a = Planets.cellOffset(layout, rect.from.X, rect.from.Y)
	local b = Planets.cellOffset(layout, rect.to.X, rect.to.Y)
	local span = math.max(math.abs(b.X - a.X), math.abs(b.Z - a.Z))
	return (a + b) / 2, span / 2 + layout.cell / 2
end

--[[
	Half the width and half the depth of a district rectangle, in studs.

	`rectBounds` answers with one radius, which is the right shape for a
	district that is about as deep as it is wide and the wrong one for a
	valley. Korriban's is seventeen cells long and eleven across: a circle
	big enough to reach its ends also reaches into the Academy at one end and
	Dreshdae at the other -- and the Academy is where a level 1 Acolyte wakes
	up, with the valley's guards banding nineteen levels above him.

	Two half-sides describe the rectangle that was actually drawn, which is
	what the author meant by drawing it.
]]
function Planets.rectExtents(layout: LayoutDef, rect: CellRect): Vector3
	local a = Planets.cellOffset(layout, rect.from.X, rect.from.Y)
	local b = Planets.cellOffset(layout, rect.to.X, rect.to.Y)
	return Vector3.new(math.abs(b.X - a.X) + layout.cell, 0, math.abs(b.Z - a.Z) + layout.cell) * 0.5
end

--[[
	Every mistake an ASCII grid can make that the type checker cannot see.

	Pulled out of `validate` when decks arrived, because Coruscant has five
	grids and the checks were written once, inline, against `p.layout`. Five
	unchecked pictures is exactly the situation this function exists to
	prevent -- a glyph the legend does not know builds nothing, and nothing
	is precisely what open ground looks like from the street. So the space
	character is the *only* way to write open ground, and any other unlisted
	glyph is reported: otherwise a typo'd `H` for `h` is a hall that was
	never there, and a bug you find by counting buildings.

	`label` rather than a planet id, because "Coruscant: deck "Underlevels""
	is the sentence that gets someone to the right grid and "Coruscant" is
	not.
]]
local function checkGrid(
	problems: { string },
	label: string,
	layout: LayoutDef,
	prefabExists: (string) -> boolean
)
	local columns, rows = Planets.layoutSize(layout)
	if layout.cell <= 0 then
		table.insert(problems, `{label} cell size {layout.cell} must be positive`)
	end
	if rows == 0 then
		table.insert(problems, `{label} has no rows`)
	end

	for glyph, prefab in layout.legend do
		if #glyph ~= 1 then
			table.insert(problems, `{label} legend key "{glyph}" is not a single character`)
		elseif glyph == " " then
			table.insert(problems, `{label} legend claims " ", which always means open ground`)
		end
		if not prefabExists(prefab) then
			table.insert(problems, `{label} glyph "{glyph}" names unknown prefab "{prefab}"`)
		end
	end

	local used: { [string]: boolean } = {}
	for r, line in layout.grid do
		-- A ragged row does not error -- `layoutSize` takes the longest --
		-- but it shifts every cell east of it, so the picture stops being
		-- what gets built.
		if #line ~= columns then
			table.insert(problems, `{label} row {r} is {#line} characters, not {columns}`)
		end
		for c = 1, #line do
			local glyph = line:sub(c, c)
			used[glyph] = true
			if glyph ~= " " and not layout.legend[glyph] then
				table.insert(problems, `{label} row {r} column {c} uses undeclared glyph "{glyph}"`)
			end
		end
	end

	for glyph in layout.legend do
		if not used[glyph] then
			table.insert(problems, `{label} legend declares "{glyph}", which never appears in the grid`)
		end
	end
end

--[[
	Cross-checks every planet against the ids it references.

	Zone names are strings written in two places -- the spawn rules and the
	points of interest -- and a typo in either used to produce a district that
	silently did not exist, so its NPCs were placed nowhere in particular.

	Takes `prefabExists` as an argument for the same reason `Factions.validate`
	takes `planetExists`: the prefabs live in `PlanetBuilder`, which is a server
	module that already requires this one, and requiring it back would be a
	cycle -- and would drag the whole builder into every client that wants to
	know a planet's name. `prefabHasRoom` and `landmarkExists` come the same way
	and for the same reason; three predicates is the price of the boundary
	staying one-way.
]]
function Planets.validate(
	prefabExists: (string) -> boolean,
	prefabHasRoom: (string) -> boolean,
	landmarkExists: (string) -> boolean
): { string }
	local problems = {}

	--[[
		Two worlds made of the same terrain material.

		`Terrain:SetMaterialColor` belongs to the one shared `Workspace.Terrain`
		and is applied when a planet is first walked into, so a shared material
		does not error and does not look wrong either -- it repaints a world you
		are not standing on. You find out by flying back to Tatooine and
		discovering the dunes went rust-red while you were on Korriban. Nothing
		in the running game can report that, so it is refused here.
	]]
	local materialOwner: { [string]: string } = {}
	for _, id in Planets.ids() do
		local p = defs[id]
		if not p.hasWalkableGround then
			continue
		end
		local material = p.terrainMaterial
		if not material then
			table.insert(problems, `{id}: has walkable ground but no terrainMaterial`)
			continue
		end
		local owner = materialOwner[material.Name]
		if owner then
			table.insert(problems, `{id}: terrainMaterial "{material.Name}" is already {owner}'s`)
		else
			materialOwner[material.Name] = id
		end
	end

	for id, p in defs do
		-- A world that asks for no traffic and a world that asks for none
		-- look identical in the sky and different in the file, and the one
		-- that typed a number meant something by it.
		local traffic = p.airTraffic
		if traffic and traffic <= 0 then
			table.insert(problems, `{id}: airTraffic {traffic} would draw nothing; leave it out instead`)
		end

		-- The authored grid, if this world has one. `columns` and `rows` are
		-- kept out here for the district-rectangle check further down.
		local layout = p.layout
		local columns, rows = 0, 0
		if layout then
			columns, rows = Planets.layoutSize(layout)
			checkGrid(problems, `{id}: layout`, layout, prefabExists)
		end

		--[[
			The stacked storeys, and the four ways a deck goes wrong silently.

			A deck is a whole district's worth of geometry keyed by a string,
			so a typo'd zone builds five hundred parts nobody ever spawns on
			and leaves the district it meant to fill standing on nothing. Two
			decks at one height interleave two street grids. A deck on a
			planet that also has a `layout` builds both at the same origin.
			None of the four errors, and all four look like "the city is
			broken" from the ground.
		]]
		local decks = p.decks
		if decks then
			if layout then
				table.insert(problems, `{id}: has both a layout and decks; they share one origin`)
			end
			local heights: { [number]: string } = {}
			local decked: { [string]: boolean } = {}
			for _, deck in decks do
				checkGrid(problems, `{id}: deck "{deck.zone}"`, deck.layout, prefabExists)
				if decked[deck.zone] then
					table.insert(problems, `{id}: two decks both claim zone "{deck.zone}"`)
				end
				decked[deck.zone] = true

				local owner = heights[deck.y]
				if owner then
					table.insert(problems, `{id}: decks "{deck.zone}" and "{owner}" are both at y = {deck.y}`)
				else
					heights[deck.y] = deck.zone
				end

				local found = false
				for _, zone in p.zones do
					if zone.id == deck.zone then
						found = true
						break
					end
				end
				if not found then
					table.insert(problems, `{id}: deck names unknown zone "{deck.zone}"`)
				end
			end

			-- A district with no deck on a decked world has no ground under
			-- it at all: its crowd, its landmark and its spawn points are
			-- placed in open air and fall out of the world on the first
			-- Heartbeat.
			for _, zone in p.zones do
				if not decked[zone.id] then
					table.insert(problems, `{id}: zone "{zone.id}" has no deck to stand on`)
				end
			end
		end

		local seen: { [string]: boolean } = {}
		for _, zone in p.zones do
			if seen[zone.id] then
				table.insert(problems, `{id}: duplicate zone "{zone.id}"`)
			end
			seen[zone.id] = true
			if zone.distance < 0 then
				table.insert(problems, `{id}: zone "{zone.id}" has negative distance`)
			end

			--[[
				A district rectangle that is not on the grid.

				`cellOffset` happily returns a position for column 40 of a
				32-column town, and the result is a district whose spawn
				points, NPCs and points of interest all sit in the desert
				outside the walls -- a whole zone quietly relocated, which
				reads as "the market is empty" rather than as an error.
			]]
			local cells = zone.cells
			if cells then
				if not layout then
					table.insert(problems, `{id}: zone "{zone.id}" has cells but the planet has no layout`)
				elseif
					cells.from.X < 1
					or cells.from.Y < 1
					or cells.to.X > columns
					or cells.to.Y > rows
					or cells.from.X > cells.to.X
					or cells.from.Y > cells.to.Y
				then
					table.insert(
						problems,
						`{id}: zone "{zone.id}" spans ({cells.from.X},{cells.from.Y})-({cells.to.X},{cells.to.Y}), `
							.. `outside a {columns}x{rows} grid`
					)
				end
			end

			local band = zone.band
			if band then
				if band.min > band.max then
					table.insert(problems, `{id}: zone "{zone.id}" has an inverted band`)
				end
				-- An authored band outside the planet's own range is almost
				-- always the mistake it looks like, and it would show up as a
				-- district that ignores the world it is on.
				if band.min < p.minLevel or band.max > p.maxLevel then
					table.insert(
						problems,
						`{id}: zone "{zone.id}" band {band.min}-{band.max} is outside the planet's {p.minLevel}-{p.maxLevel}`
					)
				end
			end
		end

		--[[
			A building you can walk into, drawn where no district reaches.

			An interior is standing room added to the district its cells fall
			in, so a room outside every rectangle is one nobody is ever put
			in: a lit shop with stock on the shelves, a counter, and no
			shopkeeper, which reads to a player as a bug in the shop system
			rather than as a gap in the map. Solid buildings do not have this
			problem, which is why it only starts mattering now.

			Reported once per building rather than once per cell: a three-by-
			three hall is nine cells and one mistake, and the cell that gets
			named is its north-west corner.
		]]
		if layout then
			for r, line in layout.grid do
				for c = 1, #line do
					local glyph = line:sub(c, c)
					local prefab = layout.legend[glyph]
					if not prefab or not prefabHasRoom(prefab) then
						continue
					end
					-- Part of a building already reported from its corner.
					local west = line:sub(c - 1, c - 1)
					local north = if r > 1 then layout.grid[r - 1]:sub(c, c) else ""
					if (c > 1 and west == glyph) or north == glyph then
						continue
					end

					local housed = false
					for _, zone in p.zones do
						local cells = zone.cells
						if
							cells
							and c >= cells.from.X
							and c <= cells.to.X
							and r >= cells.from.Y
							and r <= cells.to.Y
						then
							housed = true
							break
						end
					end
					if not housed then
						table.insert(
							problems,
							`{id}: the "{prefab}" at row {r} column {c} is in no district, `
								.. `so nobody will ever be inside it`
						)
					end
				end
			end
		end

		--[[
			A place that says the layout drew it, on a world with no layout.

			`drawn` suppresses the building entirely, so getting it wrong
			costs you the landmark and leaves the name, the sign and the
			waypoint all pointing at bare ground -- which is precisely the
			failure the points-of-interest system was written to stop, now
			available by typo. It needs a grid to have been drawn on and a
			district with `cells` to say where on the grid that was.
		]]
		for _, poi in p.pointsOfInterest do
			if not poi.drawn then
				continue
			end
			if not layout then
				table.insert(problems, `{id}: "{poi.id}" is marked drawn but the planet has no layout`)
			end
			local zoneId = poi.zone
			if not zoneId then
				table.insert(problems, `{id}: "{poi.id}" is marked drawn but names no zone`)
				continue
			end
			local located = false
			for _, zone in p.zones do
				if zone.id == zoneId and zone.cells then
					located = true
				end
			end
			if not located then
				table.insert(problems, `{id}: "{poi.id}" is marked drawn but zone "{zoneId}" has no cells`)
			end
		end

		local aggressive = 0
		for _, rule in p.spawns do
			if rule.zone and not seen[rule.zone] then
				table.insert(problems, `{id}: spawn "{rule.archetype}" names undeclared zone "{rule.zone}"`)
				continue
			end
			--[[
				A rule that asks to stand somewhere that cannot be stood in.

				All three ways this goes wrong fail the same way at runtime --
				`placementFor` finds no marker and falls back to the district,
				so the broker is somewhere in town and nothing says otherwise.
				That is the config-that-silently-does-nothing failure mode, and
				the only cheap place to catch it is here.
			]]
			local wanted = rule.poi
			if wanted then
				local target: PointOfInterest? = nil
				for _, poi in p.pointsOfInterest do
					if poi.id == wanted then
						target = poi
						break
					end
				end
				if not target then
					table.insert(problems, `{id}: spawn "{rule.archetype}" names unknown POI "{wanted}"`)
				elseif target.drawn then
					table.insert(
						problems,
						`{id}: spawn "{rule.archetype}" stands at drawn POI "{wanted}", which has no interior`
					)
				elseif target.zone ~= rule.zone then
					table.insert(
						problems,
						`{id}: spawn "{rule.archetype}" stands at POI "{wanted}", which is not in zone "{rule.zone}"`
					)
				end
			end

			if not NPCArchetypes.exists(rule.archetype) then
				continue
			end
			local a = NPCArchetypes.get(rule.archetype)
			if (rule.behavior or a.behavior) ~= NPCArchetypes.Behavior.Aggressive then
				continue
			end
			aggressive += rule.count

			--[[
				An archetype that cannot reach the band of its own district.

				`rollLevel` clamps the band into the archetype's range, so a
				mismatch does not error -- it pins every spawn to one end and
				the district quietly fills with enemies at the wrong level. The
				2026-08-16 audit found war droids capped at 12 standing in
				Korriban's level 35-46 Wastes and aggressive level 22 Sith
				acolytes in its level 1-12 Academy, which is where the Acolyte
				origin wakes up.

				Only asked of Aggressive spawns. A quest giver's level is a
				number on a nameplate, and Ord Mantell's Republic veteran is
				meant to out-rank the level 1-6 world he hands missions out on.
			]]
			if rule.zone then
				local band = Planets.bandFor(id, rule.zone)
				if a.maxLevel < band.min or a.minLevel > band.max then
					table.insert(
						problems,
						`{id}: "{rule.archetype}" is level {a.minLevel}-{a.maxLevel} but "{rule.zone}" bands {band.min}-{band.max}`
					)
				end
			end
		end

		--[[
			A world with nothing that will fight you.

			The whole level-band design -- distance out of town means danger --
			assumes danger exists, and `Radiant` will not compose a Cull mission
			for a district without it. Six of the nine planets failed this on
			2026-08-16: 812 NPCs in the galaxy and 43 of them hostile, which is
			why the playtest report was "I'm not exactly seeing enemies".

			Non-Aggressive archetypes only fight at Hostile reputation, and a
			new character starts every faction at neutral, so they do not count.
		]]
		if aggressive == 0 then
			table.insert(problems, `{id}: nothing on this planet is Aggressive, so there is nothing to fight`)
		end
		for _, poi in p.pointsOfInterest do
			if poi.zone and not seen[poi.zone] then
				table.insert(problems, `{id}: POI "{poi.id}" names undeclared zone "{poi.zone}"`)
			end
			--[[
				A `landmark` naming no builder.

				`landmarkFor` falls back to an outpost, which is deliberate for
				an unrecognised `kind` -- the builder set is smaller than the
				vocabulary and a small building with the right sign over it is
				an honest stand-in. It is the wrong answer for a `landmark`,
				because that field is only ever written on purpose: misspell
				it and the Tomb of Tulak Hord goes back to being a shed while
				the config still says it is a tomb.
			]]
			local landmark = poi.landmark
			if landmark and not landmarkExists(landmark) then
				table.insert(problems, `{id}: POI "{poi.id}" names unknown landmark "{landmark}"`)
			end
		end
	end

	--[[
		THE XP BUDGET

		Whether the galaxy actually contains enough to fight to reach the level
		cap -- checked level by level, not in total.

		`Progression.xpForNextLevel` is a formula and the world is a pile of
		spawn tables, and until 2026-08-16 nothing ever compared the two. The
		curve asked for 1,040,647 XP to reach 50 while every hostile NPC in
		existence was worth 21,480 between them, so the cap sat about fifty
		clearances of the entire galaxy past the end of the story. That is the
		arithmetic under the playtest note that levelling did not feel logical,
		and it is exactly the failure mode this codebase keeps producing: two
		systems that are each internally consistent and never introduced.

		For each level, sums the reward of every Aggressive spawn whose district
		bands within `REACH` levels of it -- what a player at that level can
		walk to and be attacked by -- and requires that to cover one level's
		worth of XP.

		ONE, not some comfortable multiple. NPCs respawn, so a player can clear
		the same district repeatedly; the honest floor is that a single sweep of
		everything in range is not *already* short. Authored missions (about
		33,000 XP across all 25) and radiant postings sit on top of this and are
		deliberately not counted, so the real curve is gentler than the check.
	]]
	local REACH = 3
	local reachable = table.create(Progression.MAX_LEVEL, 0)
	for id, p in defs do
		for _, rule in p.spawns do
			if not NPCArchetypes.exists(rule.archetype) then
				continue
			end
			local a = NPCArchetypes.get(rule.archetype)
			if (rule.behavior or a.behavior) ~= NPCArchetypes.Behavior.Aggressive then
				continue
			end
			local band = if rule.zone
				then Planets.bandFor(id, rule.zone)
				else { min = p.minLevel, max = p.maxLevel }
			local worth = rule.count * a.xpReward
			local from = math.max(1, band.min - REACH)
			local to = math.min(Progression.MAX_LEVEL, band.max + REACH)
			for level = from, to do
				reachable[level] += worth
			end
		end
	end
	for level = 1, Progression.MAX_LEVEL - 1 do
		local need = Progression.xpForNextLevel(level)
		if reachable[level] < need then
			table.insert(
				problems,
				`level {level} costs {need} XP but only {reachable[level]} is reachable within {REACH} levels of it`
			)
		end
	end

	table.sort(problems)
	return problems
end

--- Straight-line galaxy-map distance between two worlds.
function Planets.distance(a: string, b: string): number
	return (Planets.get(a).coords - Planets.get(b).coords).Magnitude
end

--[[
	Fuel needed to fly `from` to `to` yourself.

	`fuelCostMult` comes from the Navigator skill, so investing in Piloting
	visibly widens the range you can operate at.
]]
function Planets.fuelCost(from: string, to: string, fuelCostMult: number?): number
	if from == to then
		return 0
	end
	local cost = Planets.distance(from, to) * Planets.FUEL_PER_UNIT * (fuelCostMult or 1)
	return math.max(1, math.floor(cost + 0.5))
end

--- Credits to skip the flight entirely.
function Planets.fastTravelCost(from: string, to: string, priceMult: number?): number
	if from == to then
		return 0
	end
	local cost = Planets.distance(from, to) * Planets.CREDITS_PER_UNIT * (priceMult or 1)
	return math.max(Planets.MIN_FAST_TRAVEL_COST, math.floor(cost + 0.5))
end

--- Total NPCs a planet asks for, so the streaming budget can be sanity-checked.
function Planets.populationOf(id: string): number
	local total = 0
	for _, rule in Planets.get(id).spawns do
		total += rule.count
	end
	return total
end

--[[
	Planets appropriate for a player of `level`, nearest first from `from`.

	`from` is a planet id. It was called `origin` until an origin became a
	character's background rather than a starting point, at which time the name
	was a trap: two concepts, one word, and nothing that would error.
]]
function Planets.suggestedFor(level: number, from: string): { PlanetDef }
	local out = {}
	for _, p in defs do
		if level + 4 >= p.minLevel then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a, b)
		return Planets.distance(from, a.id) < Planets.distance(from, b.id)
	end)
	return out
end

function Planets.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

--[[
	Where in the shared Workspace this world is built, in studs.

	Sorted ids on a four-wide grid, which makes the address a pure function
	of the catalogue: no stored coordinates to fall out of step, and a
	server and a client that both ask get the same answer.

	It lived in PlanetBuilder until the client needed it. A world's address
	is not a fact about how it is drawn -- it is where the place *is*, and
	the drawing code being the only thing that knew meant nothing on the
	client could reason about a position in world space at all.
]]
function Planets.originFor(planetId: string): Vector3
	local ids = Planets.ids()
	local index = table.find(ids, planetId) or 1
	local column = (index - 1) % 4
	local row = (index - 1) // 4
	return Vector3.new(column * Planets.WORLD_SPACING, 0, row * Planets.WORLD_SPACING)
end

--[[
	How far the level ground reaches on a world, in studs.

	Derived rather than a constant because the play area is not the same size
	on every world: district centres sit at `ZoneDef.distance *
	SETTLEMENT_RADIUS`, and those run from Tatooine's Dune Sea at 1.6 to
	Korriban's Wastes at 2.6. A fixed radius would leave four worlds with
	their outer districts standing in the hills -- and a landmark on a swell
	is a building with its ground floor inside the terrain.

	The margin covers the landmark's own footprint and the ring of people laid
	out around it, both of which stand outside the centre they were given.
]]
function Planets.groundRadius(planetId: string): number
	local planet = defs[planetId]
	if not planet then
		return 900
	end
	if not planet.hasWalkableGround then
		-- A vertical city has no plate at all; its extent is its tower grid,
		-- half a square past the last row so the outermost footprints are
		-- inside it.
		return Planets.TOWER_GRID * (Planets.TOWER_REACH + 0.5)
	end
	local furthest = 0
	for _, zone in planet.zones do
		furthest = math.max(furthest, zone.distance)
	end
	return math.max(900, furthest * Planets.SETTLEMENT_RADIUS + 220)
end

--- How far *any* of a world reaches: level ground plus the ring of relief.
function Planets.worldRadius(planetId: string): number
	return Planets.groundRadius(planetId) + Planets.RELIEF_MARGIN
end

return Planets
