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

local Planets = {}

Planets.DEFAULT_GRAVITY = 196.2

export type SpawnRule = {
	archetype: string,
	count: number,
	-- Where they belong. The world builder resolves these against tagged zones
	-- in the map rather than scattering NPCs at random, which is what made the
	-- old version's crowds feel like debris.
	zone: string?,
	behavior: string?, -- overrides the archetype's default
}

--[[
	A district of a planet, and how far out of town it sits.

	`distance` is a multiple of the settlement radius: 0 is the middle of town,
	1 its edge, and anything above that is wilderness. It exists because the
	world builder used to derive a zone's ring from the order its first spawn
	rule happened to be declared -- which put Tatooine's Wastes downtown and
	its town out in the desert, and dropped twelve aggressive Tusken Raiders
	on a level 1 player's spawn point.

	Distance is also the difficulty dial. A player walks outward, so hostile
	zones belong further out than the ones a starting mission sends them to.
]]
export type ZoneDef = {
	id: string,
	distance: number,
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
	groundColor: Color3,
	rockColor: Color3?,
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
	hasWalkableGround: boolean,
	verticalCity: boolean?,
	-- Height above which the player is in open sky and needs a ship.
	flightCeiling: number?,

	controllingFaction: string,
	minLevel: number,
	maxLevel: number,
	lawLevel: number, -- 0 = lawless, 1 = patrolled; drives crime response

	-- Declared centre-outward. Every `zone` named by a spawn rule or a point
	-- of interest must appear here; Planets.validate says so.
	zones: { ZoneDef },
	spawns: { SpawnRule },
	pointsOfInterest: { PointOfInterest },
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
	groundColor = Palette.TatooineSand,
	rockColor = Palette.TatooineRock,
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

	zones = {
		{ id = "Town", distance = 0 },
		{ id = "Market", distance = 0.3 },
		{ id = "Cantina", distance = 0.5 },
		-- The outer four used to run out to 2.1 -- 1092 studs, most of a
		-- kilometre of empty sand -- which left five of this planet's six
		-- landmarks as smudges in the fog and made the walk between
		-- districts dead time. Pulled in so they read as one settlement's
		-- outskirts. The ordering is what matters rather than the scale:
		-- this is still the difficulty dial, and the Dune Sea is still the
		-- far edge with the Tuskens on it.
		{ id = "Farmstead", distance = 0.8 },
		{ id = "Wastes", distance = 1.05 },
		{ id = "Palace", distance = 1.3 },
		{ id = "DuneSea", distance = 1.6 },
	},
	spawns = {
		{ archetype = "Jawa", count = 14, zone = "Wastes" },
		{ archetype = "MoistureFarmer", count = 8, zone = "Farmstead" },
		{ archetype = "Civilian", count = 22, zone = "Town" },
		{ archetype = "Merchant", count = 5, zone = "Market" },
		{ archetype = "Smuggler", count = 8, zone = "Cantina" },
		-- Out in the Dune Sea rather than sharing the Wastes with the Jawas.
		-- Level 5-16 and aggressive at 180 studs, against a level 1 story
		-- objective standing in the same sand, is not a difficulty curve.
		{ archetype = "TuskenRaider", count = 12, zone = "DuneSea" },
		{ archetype = "ImperialTrooper", count = 10, zone = "Town" },
		{ archetype = "CartelEnforcer", count = 6, zone = "Palace" },
		{ archetype = "BountyHunter", count = 3, zone = "Cantina" },
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
			description = "Forty vaporators and one family, on the edge of the Dune Sea.",
			zone = "Farmstead",
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

	-- The headline feature of this planet: no walkable ground anywhere. You
	-- move between towers on platforms and skybridges, or you fly.
	hasWalkableGround = false,
	verticalCity = true,
	flightCeiling = 1400,

	-- The Republic still holds its own capital. It was sacked, not taken: the
	-- treaty left the Senate sitting in a city it had watched burn, which is
	-- why the Imperial diplomats in the Works are so hard to look at.
	controllingFaction = "Republic",
	minLevel = 10,
	maxLevel = 34,
	lawLevel = 1.0,

	-- Distance is horizontal spread here; a vertical city snaps its zones to
	-- whichever platforms the builder made, so the order matters more than
	-- the numbers.
	zones = {
		{ id = "Plaza", distance = 0 },
		{ id = "Works", distance = 0.35 },
		{ id = "Skylane", distance = 0.7 },
		{ id = "TempleRuin", distance = 1.1 },
		{ id = "Underlevels", distance = 1.5 },
	},
	spawns = {
		{ archetype = "Civilian", count = 40, zone = "Plaza" },
		{ archetype = "ProtocolDroid", count = 12, zone = "Plaza" },
		{ archetype = "Merchant", count = 8, zone = "Plaza" },
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
		{ archetype = "ImperialCommando", count = 4, zone = "Skylane" },
		{ archetype = "RepublicPilot", count = 5, zone = "Plaza" },
		{ archetype = "JediKnight", count = 3, zone = "TempleRuin" },
		{ archetype = "Smuggler", count = 6, zone = "Underlevels" },
	},
	pointsOfInterest = {
		{
			id = "JediTempleRuin",
			displayName = "The Temple Ruin",
			kind = "Temple",
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
			description = "The high commercial lane. Traffic moves fast and does not stop for you.",
			zone = "Skylane",
		},
		{
			id = "SkylaneBeta",
			displayName = "Skylane Beta",
			kind = "Outpost",
			description = "A mid-level freight lane threading between the towers.",
			zone = "Skylane",
		},
		{
			id = "SkylaneGamma",
			displayName = "Skylane Gamma",
			kind = "Outpost",
			description = "The low lane, close enough to the underlevels that patrols go in pairs.",
			zone = "Underlevels",
		},
	},
})

def({
	id = "Hoth",
	displayName = "Hoth",
	description = "Ice, wind, and a starship graveyard: thousands of hulls from a battle nobody can now explain, half-buried and walkable.",
	coords = V3(-940, 120, 480),
	region = "Outer Rim",

	gravity = 210, -- heavier than standard; jumps are shorter here
	terrain = "Ice",
	groundColor = Palette.HothSnow,
	rockColor = Palette.HothIce,
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

	zones = {
		{ id = "Base", distance = 0 },
		{ id = "Hangar", distance = 0.35 },
		-- Imperial salvage teams are out on the ice racing you for the same
		-- wrecks, not inside the base you land at.
		{ id = "Graveyard", distance = 1.5 },
		{ id = "Fissure", distance = 2.2 },
	},
	spawns = {
		{ archetype = "RepublicTrooper", count = 26, zone = "Base" },
		{ archetype = "RepublicPilot", count = 8, zone = "Hangar" },
		{ archetype = "Civilian", count = 10, zone = "Base" },
		{ archetype = "ProtocolDroid", count = 4, zone = "Hangar" },
		{ archetype = "ImperialScout", count = 14, zone = "Graveyard" },
		{ archetype = "ImperialCommando", count = 3, zone = "Graveyard" },
		{ archetype = "BountyHunter", count = 3, zone = "Fissure" },
	},
	pointsOfInterest = {
		{
			id = "AurekBase",
			displayName = "Aurek Base",
			kind = "Base",
			description = "A Republic salvage operation in tunnels cut through the glacier. The only warm place on the planet.",
			zone = "Base",
		},
		{
			id = "AurekHangar",
			displayName = "Aurek Hangar",
			kind = "Spaceport",
			description = "Recovery sleds on standby and a permanent smell of hot metal.",
			zone = "Hangar",
		},
		{
			id = "TheGraveyard",
			displayName = "The Graveyard",
			kind = "Ruin",
			landmark = "Ruin",
			description = "Hulls the size of city blocks, on their sides in the snow. You do not cross it, you climb it.",
			zone = "Graveyard",
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
	groundColor = Palette.NabooGrass,
	rockColor = Palette.NabooStone,
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

	zones = {
		{ id = "Temple", distance = 0 },
		{ id = "Village", distance = 0.4 },
		{ id = "Spaceport", distance = 0.8 },
		-- The Gnarls are wilderness, and the only hostile ground on the planet.
		{ id = "Gnarls", distance = 1.7 },
		{ id = "ForgeRidge", distance = 2.3 },
	},
	spawns = {
		{ archetype = "JediKnight", count = 10, zone = "Temple" },
		{ archetype = "Civilian", count = 24, zone = "Village" },
		{ archetype = "Merchant", count = 5, zone = "Village" },
		{ archetype = "ProtocolDroid", count = 6, zone = "Temple" },
		{ archetype = "RepublicSecurity", count = 10, zone = "Spaceport" },
		{ archetype = "RepublicVeteran", count = 6, zone = "Gnarls" },
		-- Nothing here is fortified, and the Empire has noticed. Patrols probe
		-- the Gnarls; the Order calls it a training opportunity.
		{ archetype = "ImperialTrooper", count = 10, zone = "Gnarls" },
	},
	pointsOfInterest = {
		{
			id = "TythonTemple",
			displayName = "The Temple",
			kind = "Temple",
			description = "Archives, terraces and a council chamber with no doors on it. Either faith or denial.",
			zone = "Temple",
		},
		{
			id = "KalikoriVillage",
			displayName = "Kalikori Village",
			kind = "Market",
			description = "A Twi'lek settlement that was here first and is repeatedly reminded that it was not asked.",
			zone = "Village",
		},
		{
			id = "TythonSpaceport",
			displayName = "Tython Landing",
			kind = "Spaceport",
			description = "One pad, one clerk, and a list of everyone who has ever come down it.",
			zone = "Spaceport",
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
	groundColor = Palette.WornSteel,
	rockColor = Palette.DarkMetal,
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

	zones = {
		{ id = "Camp", distance = 0 },
		{ id = "Dig", distance = 0.5 },
		{ id = "SinkingSector", distance = 1.2 },
		{ id = "Lot9", distance = 1.8 },
		{ id = "Undercity", distance = 2.4 },
	},
	spawns = {
		{ archetype = "Civilian", count = 22, zone = "Camp" },
		{ archetype = "RepublicTrooper", count = 6, zone = "Camp" },
		{ archetype = "Merchant", count = 3, zone = "Camp" },
		{ archetype = "Jawa", count = 8, zone = "Dig" },
		{ archetype = "Researcher", count = 6, zone = "Dig" },
		{ archetype = "ProtocolDroid", count = 4, zone = "Dig" },
		{ archetype = "Smuggler", count = 8, zone = "SinkingSector" },
		-- Czerka's security, which is a euphemism.
		{ archetype = "WarDroid", count = 10, zone = "Lot9" },
		{ archetype = "CartelEnforcer", count = 6, zone = "Undercity" },
		{ archetype = "ImperialCommando", count = 4, zone = "Undercity" },
	},
	pointsOfInterest = {
		{
			id = "ResettlementCamp",
			displayName = "Resettlement Camp",
			kind = "Outpost",
			description = "The Republic's optimistic little colony. Prefab huts, one water plant, and a sign with a slogan on it.",
			zone = "Camp",
		},
		{
			id = "TheDig",
			displayName = "The Dig",
			kind = "Ruin",
			description = "Salvage cranes over a spoil heap the size of a hill. Everything anyone here owns came out of it.",
			zone = "Dig",
		},
		{
			id = "SinkingSector",
			displayName = "The Sinking Sector",
			kind = "Ruin",
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
	groundColor = Palette.ZabrakRust,
	rockColor = Palette.MustafarBasalt,
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

	zones = {
		{ id = "Academy", distance = 0 },
		{ id = "Dreshdae", distance = 0.6 },
		{ id = "Valley", distance = 1.4 },
		{ id = "Tombs", distance = 2.0 },
		{ id = "Wastes", distance = 2.6 },
	},
	spawns = {
		{ archetype = "SithAcolyte", count = 18, zone = "Academy" },
		{ archetype = "ImperialTrooper", count = 10, zone = "Academy" },
		{ archetype = "Civilian", count = 16, zone = "Dreshdae" },
		{ archetype = "Merchant", count = 4, zone = "Dreshdae" },
		{ archetype = "Researcher", count = 4, zone = "Dreshdae" },
		{ archetype = "SithHonourGuard", count = 8, zone = "Valley" },
		{ archetype = "SithLord", count = 1, zone = "Tombs" },
		{ archetype = "ImperialCommando", count = 6, zone = "Tombs" },
		-- Stand-ins for tuk'ata and shyracks until the game has a non-humanoid
		-- rig. Same job: the thing in the wastes that kills you.
		{ archetype = "WarDroid", count = 14, zone = "Wastes" },
	},
	pointsOfInterest = {
		{
			id = "SithAcademy",
			displayName = "The Academy",
			kind = "Base",
			description = "Dormitories, training pits, and an Overseer who has been keeping notes for thirty years.",
			zone = "Academy",
		},
		{
			id = "Dreshdae",
			displayName = "Dreshdae",
			kind = "Market",
			description = "The one settlement. A Czerka office, a cantina, and the only vendor on the planet.",
			zone = "Dreshdae",
		},
		{
			id = "ValleyOfTheDarkLords",
			displayName = "Valley of the Dark Lords",
			kind = "Temple",
			landmark = "Temple",
			description = "Four tomb facades cut into the cliffs. The Academy teaches students not to go in.",
			zone = "Valley",
		},
		{
			id = "TombOfTulakHord",
			displayName = "Tomb of Tulak Hord",
			kind = "Ruin",
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
	groundColor = Palette.CoruscantPlate,
	rockColor = Palette.DarkMetal,
	skyTint = Color3.fromRGB(126, 96, 138),
	fogColor = Color3.fromRGB(72, 58, 82),
	fogStart = 200,
	fogEnd = 2200,
	ambientLight = Color3.fromRGB(72, 60, 84),
	outdoorAmbient = Color3.fromRGB(110, 96, 126),
	dayLength = 0.3,

	hasWalkableGround = true,
	verticalCity = true,
	flightCeiling = 1100,

	controllingFaction = "Hutt",
	minLevel = 12,
	maxLevel = 45,
	lawLevel = 0.0, -- nobody is coming to help you

	zones = {
		{ id = "Promenade", distance = 0 },
		{ id = "Market", distance = 0.35 },
		{ id = "Docks", distance = 0.8 },
		{ id = "Refuge", distance = 1.4 },
	},
	spawns = {
		{ archetype = "Civilian", count = 26, zone = "Promenade" },
		{ archetype = "Smuggler", count = 16, zone = "Docks" },
		{ archetype = "Merchant", count = 10, zone = "Market" },
		{ archetype = "CartelEnforcer", count = 18, zone = "Promenade" },
		{ archetype = "BountyHunter", count = 10, zone = "Docks" },
		{ archetype = "ProtocolDroid", count = 6, zone = "Market" },
		-- The Empire has no writ on a Hutt moon, which is exactly why it keeps
		-- a garrison at the docks -- and why there is a standing bounty on the
		-- uniform. Without them the open contract counts nothing.
		{ archetype = "ImperialTrooper", count = 16, zone = "Docks" },
		-- The refugee sector needs somebody living in it, or the mission that
		-- sends you there is a walk to an empty marker.
		{ archetype = "Jawa", count = 6, zone = "Refuge" },
		{ archetype = "Civilian", count = 14, zone = "Refuge" },
	},
	pointsOfInterest = {
		{
			id = "Promenade",
			displayName = "The Promenade",
			kind = "Market",
			description = "Neon over neon. Buy anything, and be bought if you are careless.",
			zone = "Promenade",
		},
		{
			id = "RefugeeSector",
			displayName = "Refugee Sector",
			kind = "Ruin",
			description = "Where the moon puts the people it has finished with.",
			zone = "Refuge",
		},
		{
			id = "NarDocks",
			displayName = "Docking Bay 41",
			kind = "Spaceport",
			description = "No manifests, no inspections, double the docking fee.",
			zone = "Docks",
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
	groundColor = Color3.fromRGB(88, 84, 62),
	rockColor = Palette.SmugglerBrown,
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

	zones = {
		{ id = "Garrison", distance = 0 },
		{ id = "Village", distance = 0.5 },
		{ id = "Fields", distance = 1.3 },
		{ id = "Wilds", distance = 2.0 },
	},
	spawns = {
		{ archetype = "RepublicTrooper", count = 20, zone = "Garrison" },
		{ archetype = "RepublicVeteran", count = 6, zone = "Garrison" },
		{ archetype = "ProtocolDroid", count = 3, zone = "Garrison" },
		{ archetype = "Merchant", count = 2, zone = "Village" },
		-- Frightened, and not grateful. They have been liberated three times.
		{ archetype = "Civilian", count = 18, zone = "Village" },
		-- Stand-in for the Separatist Militia archetype, which does not exist
		-- yet: poorly armed irregulars are the closest thing the roster has.
		{ archetype = "Smuggler", count = 14, zone = "Fields" },
		{ archetype = "Smuggler", count = 8, zone = "Wilds" },
	},
	pointsOfInterest = {
		{
			id = "FortGarnik",
			displayName = "Fort Garnik",
			kind = "Base",
			description = "Barracks, an armoury, and a sergeant who has stopped pretending this is going anywhere.",
			zone = "Garrison",
		},
		{
			id = "DrelliadVillage",
			displayName = "Drelliad Village",
			kind = "Market",
			description = "Liberated three times. Nobody here waves at the column any more.",
			zone = "Village",
		},
		{
			id = "SavripFields",
			displayName = "The Savrip Fields",
			kind = "Outpost",
			description = "Trenches, wire and artillery craters, over a hill with no name on any map.",
			zone = "Fields",
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
	groundColor = Color3.fromRGB(52, 58, 48),
	rockColor = Palette.ImperialBlack,
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

	zones = {
		{ id = "KaasCity", distance = 0 },
		{ id = "NexusRoad", distance = 1.1 },
		{ id = "DarkTemple", distance = 1.9 },
	},
	spawns = {
		{ archetype = "ImperialOfficer", count = 12, zone = "KaasCity" },
		{ archetype = "ImperialTrooper", count = 22, zone = "KaasCity" },
		{ archetype = "Civilian", count = 20, zone = "KaasCity" },
		{ archetype = "Merchant", count = 4, zone = "KaasCity" },
		{ archetype = "SithHonourGuard", count = 10, zone = "NexusRoad" },
		{ archetype = "ImperialCommando", count = 8, zone = "NexusRoad" },
		{ archetype = "SithAcolyte", count = 10, zone = "DarkTemple" },
		{ archetype = "SithLord", count = 2, zone = "DarkTemple" },
	},
	pointsOfInterest = {
		{
			id = "KaasCitadel",
			displayName = "The Citadel",
			kind = "Base",
			description = "The Dark Council's antechambers. Everyone here is waiting to be seen by someone worse.",
			zone = "KaasCity",
		},
		{
			id = "NexusRoad",
			displayName = "The Nexus Road",
			kind = "Outpost",
			description = "The road out of the city, guarded the whole way, in both directions.",
			zone = "NexusRoad",
		},
		{
			id = "DarkTempleGrounds",
			displayName = "Dark Temple Grounds",
			kind = "Temple",
			description = "Black walls in the rain, and a household that has kept them for longer than anyone can account for.",
			zone = "DarkTemple",
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
	Cross-checks every planet against the ids it references.

	Zone names are strings written in two places -- the spawn rules and the
	points of interest -- and a typo in either used to produce a district that
	silently did not exist, so its NPCs were placed nowhere in particular.
]]
function Planets.validate(): { string }
	local problems = {}
	for id, p in defs do
		local seen: { [string]: boolean } = {}
		for _, zone in p.zones do
			if seen[zone.id] then
				table.insert(problems, `{id}: duplicate zone "{zone.id}"`)
			end
			seen[zone.id] = true
			if zone.distance < 0 then
				table.insert(problems, `{id}: zone "{zone.id}" has negative distance`)
			end
		end
		for _, rule in p.spawns do
			if rule.zone and not seen[rule.zone] then
				table.insert(problems, `{id}: spawn "{rule.archetype}" names undeclared zone "{rule.zone}"`)
			end
		end
		for _, poi in p.pointsOfInterest do
			if poi.zone and not seen[poi.zone] then
				table.insert(problems, `{id}: POI "{poi.id}" names undeclared zone "{poi.zone}"`)
			end
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

return Planets
