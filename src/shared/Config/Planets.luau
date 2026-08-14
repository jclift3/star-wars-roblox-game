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

export type PointOfInterest = {
	id: string,
	displayName: string,
	kind: string, -- "Spaceport" | "Cantina" | "Market" | "Base" | "Temple" | "Ruin" | "Outpost"
	description: string,
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

	spawns = {
		{ archetype = "Jawa", count = 14, zone = "Wastes" },
		{ archetype = "MoistureFarmer", count = 8, zone = "Farmstead" },
		{ archetype = "Civilian", count = 22, zone = "Town" },
		{ archetype = "Merchant", count = 5, zone = "Market" },
		{ archetype = "Smuggler", count = 8, zone = "Cantina" },
		{ archetype = "TuskenRaider", count = 12, zone = "Wastes" },
		{ archetype = "Stormtrooper", count = 10, zone = "Town" },
		{ archetype = "CartelEnforcer", count = 6, zone = "Palace" },
		{ archetype = "BountyHunter", count = 3, zone = "Cantina" },
	},
	pointsOfInterest = {
		{
			id = "MosEisley",
			displayName = "Mos Eisley",
			kind = "Spaceport",
			description = "You will never find a more wretched hive. Watch your step and your credits.",
		},
		{
			id = "ChalmunsCantina",
			displayName = "Chalmun's Cantina",
			kind = "Cantina",
			description = "Music, smugglers, and a strict no-droids policy.",
		},
		{
			id = "JabbasPalace",
			displayName = "Jabba's Palace",
			kind = "Base",
			description = "Cartel headquarters. You get in by invitation or by force.",
		},
		{
			id = "LarsHomestead",
			displayName = "Lars Homestead",
			kind = "Outpost",
			description = "A moisture farm on the edge of the Dune Sea.",
		},
	},
})

def({
	id = "Coruscant",
	displayName = "Coruscant",
	description = "A single city wrapped around an entire world. The ground is a thousand levels down, and nobody goes there.",
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
	ambientLight = Color3.fromRGB(70, 76, 92),
	outdoorAmbient = Color3.fromRGB(118, 128, 150),
	dayLength = 0.3,

	-- The headline feature of this planet: no walkable ground anywhere. You
	-- move between towers on platforms and skybridges, or you fly.
	hasWalkableGround = false,
	verticalCity = true,
	flightCeiling = 1400,

	controllingFaction = "Empire",
	minLevel = 5,
	maxLevel = 50,
	lawLevel = 1.0,

	spawns = {
		{ archetype = "Civilian", count = 40, zone = "Plaza" },
		{ archetype = "ProtocolDroid", count = 12, zone = "Plaza" },
		{ archetype = "Merchant", count = 8, zone = "Market" },
		{ archetype = "Stormtrooper", count = 24, zone = "Skybridge" },
		{ archetype = "ImperialOfficer", count = 6, zone = "Palace" },
		{ archetype = "RoyalGuard", count = 4, zone = "Palace" },
		{ archetype = "DeathTrooper", count = 6, zone = "Palace" },
		{ archetype = "SithAcolyte", count = 3, zone = "Palace" },
		{ archetype = "Smuggler", count = 6, zone = "Underlevels" },
	},
	pointsOfInterest = {
		{
			id = "ImperialPalace",
			displayName = "Imperial Palace",
			kind = "Base",
			description = "The seat of the Empire, built over the bones of the Jedi Temple.",
		},
		{
			id = "SenateDistrict",
			displayName = "Senate District",
			kind = "Market",
			description = "Polished towers, patrolled skylanes, and very expensive shops.",
		},
		{
			id = "Underlevels",
			displayName = "The Underlevels",
			kind = "Cantina",
			description = "Level 1313. No sunlight, no patrols, no questions.",
		},
		{
			id = "CoruscantSpaceport",
			displayName = "Skydock Seven",
			kind = "Spaceport",
			description = "Landing platform for anyone the Empire has cleared to land.",
		},
	},
})

def({
	id = "Hoth",
	displayName = "Hoth",
	description = "Ice, wind, and a Rebel base that everyone insists is not there.",
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
	controllingFaction = "Rebellion",
	minLevel = 10,
	maxLevel = 30,
	lawLevel = 0.6,

	spawns = {
		{ archetype = "RebelTrooper", count = 26, zone = "Base" },
		{ archetype = "RebelPilot", count = 8, zone = "Hangar" },
		{ archetype = "Civilian", count = 10, zone = "Base" },
		{ archetype = "ProtocolDroid", count = 4, zone = "Hangar" },
		{ archetype = "Stormtrooper", count = 14, zone = "Surface" },
		{ archetype = "DeathTrooper", count = 3, zone = "Surface" },
	},
	pointsOfInterest = {
		{
			id = "EchoBase",
			displayName = "Echo Base",
			kind = "Base",
			description = "Tunnels cut into the glacier. Cold, cramped, and the safest place for light-years.",
		},
		{
			id = "EchoHangar",
			displayName = "Echo Hangar",
			kind = "Spaceport",
			description = "Snowspeeders on standby and a permanent smell of hot metal.",
		},
		{
			id = "WampaCaves",
			displayName = "Wampa Caves",
			kind = "Ruin",
			description = "Do not go in alone. Do not go in armed only with a blaster.",
		},
	},
})

def({
	id = "Naboo",
	displayName = "Naboo",
	description = "Green hills, domed cities, and an old order still breathing quietly under the surface.",
	coords = V3(-320, -80, -560),
	region = "Mid Rim",

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
	controllingFaction = "Republic",
	minLevel = 5,
	maxLevel = 35,
	lawLevel = 0.8,

	spawns = {
		{ archetype = "Civilian", count = 28, zone = "City" },
		{ archetype = "NabooGuard", count = 16, zone = "City" },
		{ archetype = "Merchant", count = 6, zone = "Market" },
		{ archetype = "JediSurvivor", count = 3, zone = "Temple" },
		{ archetype = "CloneVeteran", count = 6, zone = "Temple" },
		{ archetype = "ProtocolDroid", count = 6, zone = "City" },
		{ archetype = "Stormtrooper", count = 8, zone = "Spaceport" },
	},
	pointsOfInterest = {
		{
			id = "Theed",
			displayName = "Theed",
			kind = "Market",
			description = "Waterfalls under the palace and a plaza that has seen two wars.",
		},
		{
			id = "HiddenTemple",
			displayName = "The Hidden Temple",
			kind = "Temple",
			description = "What is left of the Order, and the only place to learn a saber form.",
		},
		{
			id = "TheedHangar",
			displayName = "Theed Hangar",
			kind = "Spaceport",
			description = "Chrome N-1 starfighters kept flight-ready out of sheer stubbornness.",
		},
	},
})

def({
	id = "Kamino",
	displayName = "Kamino",
	description = "One endless ocean and a handful of stilt cities. It has been raining for a very long time.",
	coords = V3(1180, 260, -880),
	region = "Outer Rim",

	gravity = 168, -- low; the platform jumps are the point
	terrain = "Ocean",
	groundColor = Palette.KaminoSea,
	rockColor = Palette.HullWhite,
	skyTint = Color3.fromRGB(120, 138, 156),
	fogColor = Color3.fromRGB(126, 146, 162),
	fogStart = 120,
	fogEnd = 1400,
	ambientLight = Color3.fromRGB(78, 88, 100),
	outdoorAmbient = Color3.fromRGB(122, 138, 154),
	dayLength = 0.5,
	windSpeed = 55,

	-- The sea is not walkable; everything happens on the platforms.
	hasWalkableGround = false,
	flightCeiling = 900,

	controllingFaction = "Independent",
	minLevel = 15,
	maxLevel = 40,
	lawLevel = 0.5,

	spawns = {
		{ archetype = "Scientist", count = 10, zone = "Labs" },
		{ archetype = "CloneVeteran", count = 14, zone = "Barracks" },
		{ archetype = "ProtocolDroid", count = 8, zone = "Labs" },
		{ archetype = "Civilian", count = 8, zone = "Platform" },
		{ archetype = "DeathTrooper", count = 6, zone = "Platform" },
		{ archetype = "BountyHunter", count = 4, zone = "Platform" },
	},
	pointsOfInterest = {
		{
			id = "TipocaCity",
			displayName = "Tipoca City",
			kind = "Base",
			description = "White corridors, endless windows, and rows of things best not asked about.",
		},
		{
			id = "CloningLabs",
			displayName = "Cloning Facility",
			kind = "Ruin",
			description = "Officially decommissioned. The lights are still on.",
		},
	},
})

def({
	id = "Mustafar",
	displayName = "Mustafar",
	description = "Rivers of fire and mining platforms bolted over them. Nothing here is safe, including the ground.",
	coords = V3(1420, -180, 340),
	region = "Outer Rim",

	gravity = 202,
	terrain = "Volcanic",
	groundColor = Palette.MustafarBasalt,
	rockColor = Palette.MustafarLava,
	skyTint = Color3.fromRGB(255, 128, 62),
	fogColor = Color3.fromRGB(122, 52, 30),
	fogStart = 150,
	fogEnd = 1800,
	ambientLight = Color3.fromRGB(96, 48, 32),
	outdoorAmbient = Color3.fromRGB(148, 82, 54),
	dayLength = 0.45,
	windSpeed = 20,

	hasWalkableGround = true,
	controllingFaction = "Empire",
	minLevel = 28,
	maxLevel = 50,
	lawLevel = 0.9,

	spawns = {
		{ archetype = "DeathTrooper", count = 16, zone = "Fortress" },
		{ archetype = "RoyalGuard", count = 8, zone = "Fortress" },
		{ archetype = "SithAcolyte", count = 8, zone = "Fortress" },
		{ archetype = "SithLord", count = 1, zone = "Fortress" },
		{ archetype = "BattleDroid", count = 14, zone = "Mines" },
		{ archetype = "CartelEnforcer", count = 8, zone = "Mines" },
		{ archetype = "ImperialOfficer", count = 4, zone = "Fortress" },
	},
	pointsOfInterest = {
		{
			id = "Fortress",
			displayName = "The Fortress",
			kind = "Base",
			description = "Black stone over a lava flow. Whatever it was built to contain is still in there.",
		},
		{
			id = "MiningComplex",
			displayName = "Mining Complex",
			kind = "Outpost",
			description = "Cartel-run, Empire-taxed, and one bad shift from falling into the river.",
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

	spawns = {
		{ archetype = "Civilian", count = 26, zone = "Promenade" },
		{ archetype = "Smuggler", count = 16, zone = "Docks" },
		{ archetype = "Merchant", count = 10, zone = "Market" },
		{ archetype = "CartelEnforcer", count = 18, zone = "Promenade" },
		{ archetype = "BountyHunter", count = 10, zone = "Docks" },
		{ archetype = "ProtocolDroid", count = 6, zone = "Market" },
		{ archetype = "Jawa", count = 6, zone = "Market" },
	},
	pointsOfInterest = {
		{
			id = "Promenade",
			displayName = "The Promenade",
			kind = "Market",
			description = "Neon over neon. Buy anything, and be bought if you are careless.",
		},
		{
			id = "RefugeeSector",
			displayName = "Refugee Sector",
			kind = "Ruin",
			description = "Where the moon puts the people it has finished with.",
		},
		{
			id = "NarDocks",
			displayName = "Docking Bay 41",
			kind = "Spaceport",
			description = "No manifests, no inspections, double the docking fee.",
		},
	},
})

def({
	id = "Endor",
	displayName = "Endor",
	description = "A forest moon with a shield generator hidden in it and something small watching from the canopy.",
	coords = V3(-1240, -60, -140),
	region = "Outer Rim",

	gravity = 172,
	terrain = "Forest",
	groundColor = Color3.fromRGB(86, 104, 62),
	rockColor = Palette.SmugglerBrown,
	skyTint = Color3.fromRGB(176, 196, 158),
	fogColor = Color3.fromRGB(112, 132, 96),
	fogStart = 80,
	fogEnd = 1200,
	ambientLight = Color3.fromRGB(72, 84, 60),
	outdoorAmbient = Color3.fromRGB(118, 132, 104),
	dayLength = 0.35,
	windSpeed = 10,

	hasWalkableGround = true,
	controllingFaction = "Empire",
	minLevel = 18,
	maxLevel = 40,
	lawLevel = 0.7,

	spawns = {
		{ archetype = "Stormtrooper", count = 22, zone = "Bunker" },
		{ archetype = "ImperialOfficer", count = 4, zone = "Bunker" },
		{ archetype = "DeathTrooper", count = 6, zone = "Bunker" },
		{ archetype = "RebelTrooper", count = 14, zone = "Camp" },
		{ archetype = "RebelPilot", count = 4, zone = "Camp" },
	},
	pointsOfInterest = {
		{
			id = "ShieldBunker",
			displayName = "Shield Generator Bunker",
			kind = "Base",
			description = "Concrete, blast doors, and far more guards than a forest needs.",
		},
		{
			id = "RebelCamp",
			displayName = "Strike Team Camp",
			kind = "Outpost",
			description = "Hidden under the roots. Cold rations and quiet voices.",
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

--- Planets appropriate for a player of `level`, nearest first from `origin`.
function Planets.suggestedFor(level: number, origin: string): { PlanetDef }
	local out = {}
	for _, p in defs do
		if level + 4 >= p.minLevel then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a, b)
		return Planets.distance(origin, a.id) < Planets.distance(origin, b.id)
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
