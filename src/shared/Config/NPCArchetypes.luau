--!strict
--[[
	NPCArchetypes.luau

	Binds everything an NPC needs into one record: what species it might be,
	what it wears, who it fights for, what it carries, and how it behaves.

	Behaviour names come from the `Behavior` table below and nowhere else.
	The previous version of this project stored behaviours as free strings and
	compared "PATROL" against a config that supplied "Patrol", so every NPC
	silently fell through to the default branch. Constants make that a typo the
	type checker catches.

	Species are drawn from a weighted pool rather than fixed, so a Mos Eisley
	crowd is mostly human but reliably has a few Rodians and a Twi'lek in it.
]]

local Species = require(script.Parent.Species)
local Costumes = require(script.Parent.Costumes)
local Weapons = require(script.Parent.Weapons)

local NPCArchetypes = {}

--- Canonical behaviour identifiers. NPCService switches on exactly these.
local Behavior = {
	Idle = "Idle", -- stands still, turns to face nearby players
	Wander = "Wander", -- drifts within a radius of its spawn
	Patrol = "Patrol", -- walks an assigned route
	Guard = "Guard", -- holds a post, engages intruders in range
	Vendor = "Vendor", -- static, opens a shop on interact
	QuestGiver = "QuestGiver", -- static, opens dialogue on interact
	Aggressive = "Aggressive", -- hunts valid targets on sight
	Flee = "Flee", -- runs from danger, never fights
}
NPCArchetypes.Behavior = Behavior

--[[
	When somebody is out.

	A moisture farmer works the vaporators in daylight and a Cartel runner
	does not come out until it is dark, and until now both milled around the
	same square forever. `Shift` is the whole of that: an off-shift NPC is put
	into `Guard`, which walks them back to where they spawned and holds them
	there, and an on-shift one is returned to their archetype's own behaviour.

	WHAT IT DELIBERATELY IS NOT
	It does not despawn anybody. A schedule that removes people would mean a
	vendor, a mission-giver or a cast member who cannot be found at the wrong
	hour, and this project has already learned once that *finished but
	unreachable is not finished* -- a fourteen-year-old who cannot hand in a
	mission at 21:00 has hit a bug, whatever the design document says.

	It is also refused on anything `Aggressive` (see `validate`). Enemies that
	stand down at noon would be free XP on a timer, and the boys play in one
	room and will find it. Combat is identical around the clock; this is
	atmosphere, and it is confined to being atmosphere.
]]
local Shift = {
	Day = "Day",
	Night = "Night",
}
NPCArchetypes.Shift = Shift

export type SpeciesWeight = { species: string, weight: number }

export type Archetype = {
	id: string,
	displayName: string,
	faction: string,
	costume: string,
	speciesPool: { SpeciesWeight },

	behavior: string,
	-- Stands and fights rather than repositioning. Guards and droids hold;
	-- civilians and smugglers break contact.
	holdsGround: boolean?,
	-- One of `Shift`, or nil for somebody who is always about. See `Shift`.
	shift: string?,

	minLevel: number,
	maxLevel: number,
	baseHealth: number,
	healthPerLevel: number?,
	walkSpeed: number,
	runSpeed: number?,

	weapon: string?,
	-- Chance per spawn that this NPC carries `weapon` at all. Civilians in a
	-- rough district are armed sometimes, not always.
	weaponChance: number?,

	--[[
		How far this NPC can notice a player, in studs. Kept at or under 150,
		which is also where `NPCBrain` clamps it: beyond that an NPC starts
		charging before it is a recognisable shape on screen, which is what
		"they all knew I was there the moment I landed" turned out to be.

		This is the best case. Sight also needs line of sight and a target
		roughly in front, so from behind cover or behind the NPC it is zero.
	]]
	sightRange: number?,
	attackRange: number?,
	-- Seconds of "I saw something" before it commits to a target. Keeps NPCs
	-- from snapping around instantly, which reads as aimbot.
	reactionTime: number?,
	-- Accuracy multiplier applied to the weapon's spread cone. Line infantry
	-- are deliberately terrible so a level 3 player survives a squad of them;
	-- commandos are not, so a squad of those is a real problem.
	spreadMult: number?,
	-- Fraction of the weapon's fire rate the NPC actually achieves.
	fireRateMult: number?,

	xpReward: number,
	creditReward: { min: number, max: number }?,
	repOnKill: number?, -- rep change with `faction` when a player kills it

	dialogue: string?, -- DialogueTrees id
	shop: string?, -- Shops id
	nameStyle: string?, -- NPCNames pool id
	interactable: boolean?,
}

local defs: { [string]: Archetype } = {}

local function def(a: Archetype): Archetype
	defs[a.id] = a
	return a
end

--- Shorthand for a weighted species pool: `pool({ Human = 6, Rodian = 1 })`.
local function pool(weights: { [string]: number }): { SpeciesWeight }
	local out = {}
	for species, weight in weights do
		table.insert(out, { species = species, weight = weight })
	end
	table.sort(out, function(a, b)
		return a.species < b.species
	end)
	return out
end

--------------------------------------------------------------------------------
-- Imperial
--------------------------------------------------------------------------------

def({
	id = "ImperialTrooper",
	displayName = "Imperial Trooper",
	faction = "Empire",
	costume = "ImperialTrooper",
	speciesPool = pool({ Human = 1 }),
	behavior = Behavior.Patrol,
	holdsGround = true,
	--[[
		A wide range on purpose, and the reason `rollLevel` narrows by district.

		The same uniform stands in Anchorhead's market and on the Tython ridge
		line, and it used to cap at 12 -- so the Tython patrol spawned eighteen
		levels under the ground it was standing on, and `Planets.validate` now
		says so. One archetype spanning the galaxy is the intended shape: the
		band decides how hard this particular trooper is, not the roster.
	]]
	minLevel = 3,
	maxLevel = 35,
	baseHealth = 90,
	healthPerLevel = 6,
	walkSpeed = 10,
	runSpeed = 17,
	weapon = "E11",
	sightRange = 110,
	attackRange = 130,
	reactionTime = 0.55,
	-- Line infantry with mass-issue rifles and six weeks of training. The
	-- stormtroopers this replaced missed for a joke; these miss because the
	-- Empire buys soldiers by the thousand.
	spreadMult = 2.6,
	fireRateMult = 0.75,
	xpReward = 45,
	creditReward = { min = 20, max = 60 },
	repOnKill = -35,
	nameStyle = "ImperialSerial",
})

def({
	id = "ImperialScout",
	displayName = "Imperial Scout",
	faction = "Empire",
	costume = "ImperialScout",
	speciesPool = pool({ Human = 1 }),
	behavior = Behavior.Patrol,
	holdsGround = true,
	-- Reaches Hoth's Starship Graveyard (28-37), which is the only place they
	-- are posted and was eight levels past their old ceiling.
	minLevel = 8,
	maxLevel = 37,
	baseHealth = 120,
	healthPerLevel = 7,
	walkSpeed = 10,
	runSpeed = 16,
	weapon = "T21",
	sightRange = 150,
	attackRange = 180,
	reactionTime = 0.5,
	spreadMult = 2.0,
	fireRateMult = 0.8,
	xpReward = 80,
	creditReward = { min = 45, max = 110 },
	repOnKill = -45,
	nameStyle = "ImperialSerial",
})

def({
	id = "ImperialCommando",
	displayName = "Imperial Commando",
	faction = "Empire",
	costume = "ImperialCommando",
	speciesPool = pool({ Human = 1 }),
	behavior = Behavior.Guard,
	holdsGround = true,
	minLevel = 20,
	maxLevel = 35,
	baseHealth = 240,
	healthPerLevel = 10,
	walkSpeed = 12,
	runSpeed = 21,
	weapon = "DC15A",
	sightRange = 130,
	attackRange = 200,
	reactionTime = 0.2,
	spreadMult = 0.55, -- these ones can actually shoot
	fireRateMult = 1.0,
	xpReward = 260,
	creditReward = { min = 180, max = 400 },
	repOnKill = -120,
	nameStyle = "ImperialSerial",
})

def({
	id = "ImperialOfficer",
	displayName = "Imperial Officer",
	faction = "Empire",
	costume = "ImperialOfficer",
	speciesPool = pool({ Human = 1 }),
	behavior = Behavior.QuestGiver,
	minLevel = 10,
	maxLevel = 25,
	baseHealth = 110,
	healthPerLevel = 6,
	walkSpeed = 9,
	runSpeed = 14,
	weapon = "SE14C",
	sightRange = 100,
	attackRange = 110,
	reactionTime = 0.7,
	spreadMult = 1.4,
	xpReward = 130,
	creditReward = { min = 120, max = 300 },
	repOnKill = -90,
	dialogue = "ImperialOfficer",
	nameStyle = "ImperialHuman",
	interactable = true,
})

def({
	id = "SithHonourGuard",
	displayName = "Sith Honour Guard",
	faction = "Empire",
	costume = "SithHonourGuard",
	speciesPool = pool({ Human = 1 }),
	behavior = Behavior.Guard,
	holdsGround = true,
	-- Up to the cap: these hold the Nexus Road and the Dark Temple, which band
	-- 47-50, and there is nothing above them to promote the job to.
	minLevel = 28,
	maxLevel = 50,
	baseHealth = 320,
	healthPerLevel = 12,
	walkSpeed = 8,
	runSpeed = 20,
	weapon = "ElectroStaff",
	sightRange = 100,
	attackRange = 12,
	reactionTime = 0.15,
	xpReward = 420,
	creditReward = { min = 300, max = 650 },
	repOnKill = -160,
	nameStyle = "None",
})

def({
	id = "SithAcolyte",
	displayName = "Sith Acolyte",
	faction = "Empire",
	costume = "Sith",
	speciesPool = pool({ Human = 6, Zabrak = 3, Twilek = 1 }),
	behavior = Behavior.Aggressive,
	holdsGround = true,
	--[[
		A student, and priced like one.

		This archetype spawns in exactly one place in the galaxy -- the
		Korriban Academy, which bands 1-12 -- and it was declared 22-38, a
		range with no overlap at all. `rollLevel` clamps into the band, so
		every one of the eighteen came out pinned to one end, and the
		Acolyte's own home district was a wall on the first morning: nothing
		there could be fought, so the origin had no way to reach level 2
		without leaving the planet it had not been told how to leave.

		2-14 is what the fiction already said these people are. The named
		Sith who are supposed to be dangerous are `SithHonourGuard` in the
		Valley and `SithLord` in the Wastes, and neither changed.

		`repOnKill` drops with it. Duelling in the practice yards is what the
		yards are for; -150 an acolyte meant six sparring matches turned the
		Academy hostile to its own student.
	]]
	minLevel = 2,
	maxLevel = 14,
	baseHealth = 110,
	healthPerLevel = 12,
	walkSpeed = 12,
	runSpeed = 23,
	weapon = "SaberRed",
	sightRange = 120,
	attackRange = 9,
	reactionTime = 0.2,
	xpReward = 110,
	creditReward = { min = 15, max = 60 },
	repOnKill = -25,
	dialogue = "SithTaunt",
	nameStyle = "Sith",
})

def({
	id = "SithLord",
	displayName = "Sith Lord",
	faction = "Empire",
	costume = "SithLordArmoured",
	speciesPool = pool({ Human = 1 }),
	behavior = Behavior.Aggressive,
	holdsGround = true,
	minLevel = 40,
	maxLevel = 50,
	baseHealth = 900,
	healthPerLevel = 20,
	walkSpeed = 11,
	runSpeed = 22,
	weapon = "SaberDoubleRed",
	sightRange = 140,
	attackRange = 11,
	reactionTime = 0.1,
	xpReward = 2400,
	creditReward = { min = 1500, max = 3500 },
	repOnKill = -400,
	dialogue = "SithLord",
	nameStyle = "Sith",
})

--------------------------------------------------------------------------------
-- Republic / Jedi
--------------------------------------------------------------------------------

def({
	id = "RepublicTrooper",
	displayName = "Republic Trooper",
	faction = "Republic",
	costume = "RepublicTrooper",
	speciesPool = pool({ Human = 8, Twilek = 2, Rodian = 1, Zabrak = 1 }),
	behavior = Behavior.Patrol,
	holdsGround = true,
	minLevel = 3,
	maxLevel = 14,
	baseHealth = 95,
	healthPerLevel = 6,
	walkSpeed = 11,
	runSpeed = 18,
	weapon = "DH17",
	sightRange = 110,
	attackRange = 120,
	reactionTime = 0.5,
	spreadMult = 1.6,
	fireRateMult = 0.85,
	xpReward = 45,
	creditReward = { min = 20, max = 60 },
	repOnKill = -35,
	dialogue = "RepublicTrooper",
	nameStyle = "Common",
	interactable = true,
})

def({
	id = "RepublicPilot",
	displayName = "Republic Pilot",
	faction = "Republic",
	costume = "RepublicPilot",
	speciesPool = pool({ Human = 8, Twilek = 1, Zabrak = 1 }),
	behavior = Behavior.QuestGiver,
	minLevel = 8,
	maxLevel = 22,
	baseHealth = 100,
	healthPerLevel = 6,
	walkSpeed = 10,
	weapon = "DH17",
	weaponChance = 0.6,
	xpReward = 70,
	creditReward = { min = 40, max = 120 },
	repOnKill = -60,
	dialogue = "RepublicPilot",
	nameStyle = "Common",
	interactable = true,
})

def({
	-- Was a Clone Veteran, which is three and a half thousand years early:
	-- the Kaminoan army does not exist yet. Same role, same numbers -- the
	-- hardened regular the Republic sends when the conscripts are not enough.
	id = "RepublicVeteran",
	displayName = "Republic Veteran",
	faction = "Republic",
	costume = "RepublicVeteran",
	speciesPool = pool({ Human = 1 }),
	behavior = Behavior.Guard,
	holdsGround = true,
	minLevel = 15,
	maxLevel = 30,
	baseHealth = 200,
	healthPerLevel = 9,
	walkSpeed = 11,
	runSpeed = 19,
	weapon = "DC15A",
	sightRange = 130,
	attackRange = 190,
	reactionTime = 0.3,
	spreadMult = 0.8,
	fireRateMult = 0.95,
	xpReward = 200,
	creditReward = { min = 120, max = 280 },
	repOnKill = -100,
	dialogue = "RepublicVeteran",
	nameStyle = "Common",
	interactable = true,
})

def({
	id = "JediKnight",
	displayName = "Jedi Knight",
	faction = "Jedi",
	costume = "Jedi",
	speciesPool = pool({ Human = 6, Twilek = 2, Zabrak = 2, Trandoshan = 1 }),
	behavior = Behavior.QuestGiver,
	holdsGround = true,
	minLevel = 25,
	maxLevel = 45,
	baseHealth = 400,
	healthPerLevel = 14,
	walkSpeed = 12,
	runSpeed = 22,
	weapon = "SaberBlue",
	sightRange = 130,
	attackRange = 9,
	reactionTime = 0.15,
	xpReward = 700,
	creditReward = { min = 200, max = 500 },
	repOnKill = -250,
	dialogue = "JediMaster",
	nameStyle = "Jedi",
	interactable = true,
})

def({
	-- Naboo is not one of this game's nine worlds and its security force is a
	-- prequel institution, so this is now the generic planetside garrison the
	-- Republic leaves behind on a world it does not much care about.
	id = "RepublicSecurity",
	displayName = "Republic Security",
	faction = "Republic",
	costume = "RepublicSecurity",
	speciesPool = pool({ Human = 6, Rodian = 2 }),
	behavior = Behavior.Guard,
	holdsGround = true,
	minLevel = 6,
	maxLevel = 18,
	baseHealth = 130,
	healthPerLevel = 7,
	walkSpeed = 10,
	runSpeed = 16,
	weapon = "DH17",
	sightRange = 100,
	attackRange = 120,
	reactionTime = 0.5,
	spreadMult = 1.5,
	xpReward = 90,
	creditReward = { min = 40, max = 110 },
	repOnKill = -70,
	dialogue = "RepublicSecurity",
	nameStyle = "Common",
	interactable = true,
})

--------------------------------------------------------------------------------
-- Underworld
--------------------------------------------------------------------------------

def({
	id = "BountyHunter",
	displayName = "Bounty Hunter",
	faction = "Hutt",
	costume = "BountyHunter",
	speciesPool = pool({ Human = 5, Trandoshan = 3, Rodian = 2, Zabrak = 2 }),
	--[[
		A hunter works from a list. Aggressive would have him shoot anyone who
		is not an outright friend of the Hutts, which at rep 0 is every new
		player -- and three of these stand in Tatooine's cantina, 260 studs from
		the spawn point, at level 18-36 against a level 1. Guard engages only
		players the Hutts hold Hostile, which is the mark he is actually after.
		The sight range comes down with it: 260 was the longest in the game and
		let him open fire from the next district over.
	]]
	behavior = Behavior.Guard,
	-- Hoth's Fissure and Nar Shaddaa's Refuge both band into the forties, and
	-- a hunter who takes contracts that far out is the whole point of them.
	minLevel = 18,
	maxLevel = 45,
	baseHealth = 260,
	healthPerLevel = 10,
	walkSpeed = 12,
	runSpeed = 22,
	weapon = "DisruptorPistol",
	sightRange = 120,
	attackRange = 140,
	reactionTime = 0.25,
	spreadMult = 0.9,
	fireRateMult = 1.0,
	xpReward = 380,
	creditReward = { min = 300, max = 800 },
	repOnKill = -100,
	dialogue = "BountyHunter",
	nameStyle = "Underworld",
	interactable = true,
})

def({
	id = "Smuggler",
	displayName = "Smuggler",
	faction = "Independent",
	costume = "Smuggler",
	speciesPool = pool({ Human = 6, Twilek = 2, Rodian = 2, Wookiee = 1 }),
	behavior = Behavior.Wander,
	-- The reason a night street is not simply an empty day street.
	shift = Shift.Night,
	-- Down to 3 so the Ord Mantell irregulars -- a level 1-6 world, and the
	-- Conscript's first fight -- are not all pinned to the archetype's floor.
	minLevel = 3,
	maxLevel = 24,
	baseHealth = 140,
	healthPerLevel = 7,
	walkSpeed = 11,
	runSpeed = 20,
	weapon = "DL44",
	weaponChance = 0.8,
	sightRange = 100,
	attackRange = 110,
	reactionTime = 0.4,
	spreadMult = 1.2,
	xpReward = 120,
	creditReward = { min = 80, max = 260 },
	dialogue = "Smuggler",
	nameStyle = "Common",
	interactable = true,
})

def({
	id = "CartelEnforcer",
	displayName = "Cartel Enforcer",
	faction = "Hutt",
	costume = "BountyHunter",
	speciesPool = pool({ Trandoshan = 4, Human = 3, Rodian = 2, Wookiee = 1 }),
	behavior = Behavior.Guard,
	holdsGround = true,
	minLevel = 12,
	maxLevel = 28,
	baseHealth = 190,
	healthPerLevel = 9,
	walkSpeed = 10,
	runSpeed = 18,
	weapon = "VibroBlade",
	sightRange = 120,
	attackRange = 8,
	reactionTime = 0.35,
	xpReward = 180,
	creditReward = { min = 90, max = 240 },
	repOnKill = -80,
	dialogue = "CartelEnforcer",
	nameStyle = "Underworld",
	interactable = true,
})

def({
	id = "Jawa",
	displayName = "Jawa",
	faction = "Independent",
	costume = "Jawa",
	speciesPool = pool({ Jawa = 1 }),
	behavior = Behavior.Wander,
	minLevel = 1,
	maxLevel = 6,
	baseHealth = 45,
	healthPerLevel = 3,
	walkSpeed = 13, -- scurries
	runSpeed = 17,
	xpReward = 15,
	creditReward = { min = 5, max = 40 },
	dialogue = "Jawa",
	shop = "JawaScrap",
	nameStyle = "Jawa",
	interactable = true,
})

def({
	id = "TuskenRaider",
	displayName = "Tusken Raider",
	faction = "Independent",
	costume = "TuskenRaider",
	speciesPool = pool({ Human = 1 }),
	behavior = Behavior.Aggressive,
	holdsGround = true,
	minLevel = 5,
	maxLevel = 16,
	baseHealth = 110,
	healthPerLevel = 6,
	walkSpeed = 11,
	runSpeed = 20,
	weapon = "Gaderffii",
	sightRange = 130,
	attackRange = 8,
	reactionTime = 0.3,
	xpReward = 70,
	creditReward = { min = 10, max = 50 },
	nameStyle = "None",
})

--------------------------------------------------------------------------------
-- Civilians -- the "everyday people with basic AI" layer
--------------------------------------------------------------------------------

def({
	id = "Civilian",
	displayName = "Citizen",
	faction = "Independent",
	costume = "Civilian",
	speciesPool = pool({
		Human = 10,
		Twilek = 3,
		Rodian = 2,
		Zabrak = 2,
		Trandoshan = 1,
		Gungan = 1,
	}),
	behavior = Behavior.Wander,
	-- The archetype this feature is really about: there are more of these in
	-- the game than anything else, so a street that empties after dark is
	-- mostly this one line.
	shift = Shift.Day,
	minLevel = 1,
	maxLevel = 5,
	baseHealth = 60,
	walkSpeed = 9,
	runSpeed = 16,
	xpReward = 5,
	creditReward = { min = 0, max = 15 },
	repOnKill = -20, -- murdering bystanders costs you standing everywhere
	dialogue = "Civilian",
	nameStyle = "Common",
	interactable = true,
})

def({
	id = "MoistureFarmer",
	displayName = "Moisture Farmer",
	faction = "Independent",
	costume = "MoistureFarmer",
	speciesPool = pool({ Human = 8, Twilek = 1 }),
	behavior = Behavior.Wander,
	-- Vaporators are worked in daylight, and there is nowhere on Tatooine
	-- anyone sane is standing around at 02:00.
	shift = Shift.Day,
	minLevel = 1,
	maxLevel = 6,
	baseHealth = 70,
	walkSpeed = 9,
	runSpeed = 15,
	xpReward = 5,
	creditReward = { min = 0, max = 25 },
	repOnKill = -20,
	dialogue = "MoistureFarmer",
	nameStyle = "Common",
	interactable = true,
})

def({
	id = "Merchant",
	displayName = "Merchant",
	faction = "Independent",
	costume = "Merchant",
	speciesPool = pool({ Human = 6, Twilek = 3, Rodian = 2, Trandoshan = 1 }),
	behavior = Behavior.Vendor,
	minLevel = 5,
	maxLevel = 15,
	baseHealth = 80,
	walkSpeed = 8,
	xpReward = 10,
	creditReward = { min = 50, max = 200 },
	repOnKill = -40,
	dialogue = "Merchant",
	shop = "GeneralGoods",
	nameStyle = "Common",
	interactable = true,
})

def({
	--[[
		The only person who will sell you a hull, and he stands on a landing
		field.

		Split out of `Merchant` rather than given a `shop` override on it,
		because the two are not the same job in the fiction or in the spawn
		table: a general trader stands on a street in every town on seven
		worlds, and there are five spaceports in the galaxy. Making this its
		own archetype is what lets the spawn rules put one in each of them
		and nowhere else -- which is the whole feature, since `Ships.PAD_TAG`
		already meant a spaceport is the only place a starship can come down.

		DELIBERATELY NO `shift`
		An off-shift NPC walks home and holds there, and `ShopService` finds
		a vendor by standing within thirty studs of him. A broker who keeps
		hours is a broker the boys will find closed with no way to tell that
		from a bug, on the one errand in the game that costs thirty thousand
		credits.
	]]
	id = "ShipBroker",
	displayName = "Ship Broker",
	faction = "Independent",
	costume = "Merchant",
	speciesPool = pool({ Human = 5, Twilek = 2, Rodian = 2, Trandoshan = 2 }),
	behavior = Behavior.Vendor,
	-- Higher than the general trader because the shelf is: the cheapest hull
	-- he stocks costs more than everything in a General Goods put together.
	minLevel = 10,
	maxLevel = 20,
	baseHealth = 90,
	walkSpeed = 8,
	xpReward = 12,
	creditReward = { min = 120, max = 400 },
	repOnKill = -40,
	dialogue = "Merchant",
	shop = "ShipYard",
	nameStyle = "Common",
	interactable = true,
})

def({
	-- Kaminoans are an old enough species to belong here; Kamino's cloning
	-- industry is not. So the species stays in the pool and the job changes:
	-- Czerka runs research contracts for both governments in this era.
	id = "Researcher",
	displayName = "Czerka Researcher",
	faction = "Independent",
	costume = "Researcher",
	speciesPool = pool({ Human = 5, Kaminoan = 2, Twilek = 1 }),
	behavior = Behavior.QuestGiver,
	minLevel = 10,
	maxLevel = 20,
	baseHealth = 75,
	walkSpeed = 8,
	xpReward = 10,
	repOnKill = -40,
	dialogue = "Researcher",
	nameStyle = "Common",
	interactable = true,
})

--------------------------------------------------------------------------------
-- Droids
--------------------------------------------------------------------------------

def({
	id = "ProtocolDroid",
	displayName = "Protocol Droid",
	faction = "Independent",
	costume = "ProtocolDroid",
	speciesPool = pool({ ProtocolDroid = 1 }),
	behavior = Behavior.Wander,
	minLevel = 1,
	maxLevel = 5,
	baseHealth = 70,
	walkSpeed = 7, -- stiff-legged
	runSpeed = 11,
	xpReward = 10,
	creditReward = { min = 10, max = 40 },
	dialogue = "ProtocolDroid",
	nameStyle = "DroidDesignation",
	interactable = true,
})

def({
	-- The B1 is a Clone Wars machine. This era's equivalent is the war droid
	-- Czerka and the Hutts keep buying second-hand off older battlefields --
	-- same role, same terrible processors, no Trade Federation.
	id = "WarDroid",
	displayName = "War Droid",
	faction = "Independent",
	costume = "WarDroid",
	speciesPool = pool({ WarDroid = 1 }),
	behavior = Behavior.Patrol,
	holdsGround = true,
	-- Czerka's Lot 9 (15-21) and Korriban's Valley (19-30) both run past the
	-- old ceiling of 12, which pinned every droid in them to one number.
	minLevel = 2,
	maxLevel = 24,
	baseHealth = 55,
	healthPerLevel = 4,
	walkSpeed = 10,
	runSpeed = 15,
	weapon = "E5",
	sightRange = 110,
	attackRange = 120,
	reactionTime = 0.8, -- slow processors
	spreadMult = 3.0,
	fireRateMult = 0.7,
	xpReward = 30,
	creditReward = { min = 10, max = 45 },
	nameStyle = "DroidDesignation",
})

--------------------------------------------------------------------------------

NPCArchetypes.defs = defs

function NPCArchetypes.get(id: string): Archetype
	local a = defs[id]
	assert(a, `NPCArchetypes.get: unknown archetype "{id}"`)
	return a
end

function NPCArchetypes.exists(id: string): boolean
	return defs[id] ~= nil
end

--- Weighted species roll for one spawn.
function NPCArchetypes.rollSpecies(id: string, rng: Random?): string
	local a = NPCArchetypes.get(id)
	local total = 0
	for _, entry in a.speciesPool do
		total += entry.weight
	end
	local roll = if rng then rng:NextNumber(0, total) else math.random() * total
	local acc = 0
	for _, entry in a.speciesPool do
		acc += entry.weight
		if roll <= acc then
			return entry.species
		end
	end
	return a.speciesPool[1].species
end

--[[
	What level one of these spawns at.

	`band` is the district's level range (`Planets.bandFor`) and it narrows the
	archetype's own range rather than replacing it: a Jawa in the deep desert
	sits at the top of what a Jawa can be, not at the level of the Tuskens
	around it. Clamping both ends into the archetype's range cannot invert
	them, because `math.clamp` is monotonic.

	Typed structurally rather than as `Planets.Band` so that this config, which
	the planet configs lean on, does not have to require them back.
]]
function NPCArchetypes.rollLevel(id: string, rng: Random?, band: { min: number, max: number }?): number
	local a = NPCArchetypes.get(id)
	local low, high = a.minLevel, a.maxLevel
	if band then
		low = math.clamp(band.min, a.minLevel, a.maxLevel)
		high = math.clamp(band.max, a.minLevel, a.maxLevel)
	end
	if rng then
		return rng:NextInteger(low, high)
	end
	return math.random(low, high)
end

--[[
	The first archetype in `spawns` that will actually attack you in `zoneId`,
	or nil if the district holds nothing hostile at all.

	Lives here because Behavior does, and it is asked by two callers that have
	nothing else in common: Radiant, deciding whether a district can carry a
	Cull mission, and ZoneController, deciding whether a level band is a
	warning or just a fact. A district of Jawas and archaeologists is not
	dangerous however far out of town it sits, and telling a level 1 Scrapper
	to TURN BACK from the dig their own prologue sent them to is the version
	of that mistake the 2026-08-16 playtest actually hit.

	`spawns` is typed structurally rather than as `Planets.SpawnRule` for the
	same reason `rollLevel` takes a bare band: the planet configs lean on this
	file, so it must not require them back. Luau table types are invariant, so
	the shape has to name every field of a SpawnRule even though only three are
	read -- a field added there and not here is a type error at the call sites,
	which is the loud failure and the one we want.
]]
function NPCArchetypes.hostileIn(
	spawns: {
		{
			archetype: string,
			count: number,
			zone: string?,
			behavior: string?,
			cast: string?,
			poi: string?,
		}
	},
	zoneId: string
): string?
	for _, rule in spawns do
		if rule.zone ~= zoneId or not NPCArchetypes.exists(rule.archetype) then
			continue
		end
		-- A rule may override the archetype's default, and the override is
		-- what actually spawns.
		local behavior = rule.behavior or NPCArchetypes.get(rule.archetype).behavior
		if behavior == Behavior.Aggressive then
			return rule.archetype
		end
	end
	return nil
end

--[[
	The everyday people of a district, as archetype ids against head counts.

	"Everyday" is `Behavior.Wander` and unarmed, which comes out as the
	civilians, the moisture farmers, the Jawas and the protocol droids -- and
	deliberately not the troopers standing a beat or anything Aggressive.
	CrowdController draws its background bodies to look like whatever this
	returns, so the rule is really "who could a picture of a person be mistaken
	for without that being a problem": a distant civilian is scenery, and a
	distant Imperial trooper is something the boys will try to shoot.

	Counts come back rather than a set because a district that is nine tenths
	civilians and one tenth Jawas should look like that from across the street.

	Structurally typed for the same reason `hostileIn` is: the planet configs
	require this file, so it must not require them back.
]]
function NPCArchetypes.crowdIn(
	spawns: {
		{
			archetype: string,
			count: number,
			zone: string?,
			behavior: string?,
			cast: string?,
			poi: string?,
		}
	},
	zoneId: string
): { { archetype: string, count: number } }
	local out = {}
	for _, rule in spawns do
		if rule.zone ~= zoneId or rule.cast or not NPCArchetypes.exists(rule.archetype) then
			continue
		end
		local archetype = NPCArchetypes.get(rule.archetype)
		-- The override is what actually spawns, so three districts' Smugglers
		-- are Aggressive here even though the archetype is not.
		local behavior = rule.behavior or archetype.behavior
		if behavior == Behavior.Wander and not archetype.weapon then
			table.insert(out, { archetype = rule.archetype, count = rule.count })
		end
	end
	return out
end

function NPCArchetypes.healthFor(id: string, level: number): number
	local a = NPCArchetypes.get(id)
	return a.baseHealth + (a.healthPerLevel or 0) * math.max(0, level - a.minLevel)
end

--- XP a player earns for the kill, scaled by how far above them the target was.
function NPCArchetypes.xpFor(id: string, npcLevel: number, playerLevel: number): number
	local a = NPCArchetypes.get(id)
	local diff = npcLevel - playerLevel
	-- Grinding trivial enemies at high level should not be a viable strategy,
	-- but never drop to zero or low-level areas become dead space.
	local mult = math.clamp(1 + diff * 0.08, 0.2, 2.0)
	return math.floor(a.xpReward * mult)
end

function NPCArchetypes.rollCredits(id: string, rng: Random?): number
	local a = NPCArchetypes.get(id)
	local r = a.creditReward
	if not r then
		return 0
	end
	if rng then
		return rng:NextInteger(r.min, r.max)
	end
	return math.random(r.min, r.max)
end

--- True if this archetype fights the player on sight given their reputation.
function NPCArchetypes.isHostileByDefault(id: string): boolean
	local a = NPCArchetypes.get(id)
	return a.behavior == Behavior.Aggressive
end

--[[
	Validates every archetype against the configs it references.

	Run once at server start. A bad costume id would otherwise surface as an
	NPC spawning in its underwear halfway through a play session, which is a
	miserable thing to track down.
]]
function NPCArchetypes.validate(): { string }
	local problems = {}
	for id, a in defs do
		if not Costumes.exists(a.costume) then
			table.insert(problems, `{id}: unknown costume "{a.costume}"`)
		end
		if a.weapon and not Weapons.exists(a.weapon) then
			table.insert(problems, `{id}: unknown weapon "{a.weapon}"`)
		end
		if #a.speciesPool == 0 then
			table.insert(problems, `{id}: empty species pool`)
		end
		for _, entry in a.speciesPool do
			if not Species.exists(entry.species) then
				table.insert(problems, `{id}: unknown species "{entry.species}"`)
			end
		end
		if a.maxLevel < a.minLevel then
			table.insert(problems, `{id}: maxLevel < minLevel`)
		end
		local shift = a.shift
		if shift then
			if not Shift[shift] then
				table.insert(problems, `{id}: unknown shift "{shift}"`)
			end
			-- The two refusals that keep a schedule from being a bug. An
			-- enemy that stands down on a timer is free XP; a trader who
			-- does is a shop that is shut and does not say so.
			if a.behavior == Behavior.Aggressive then
				table.insert(problems, `{id}: an Aggressive archetype may not keep a shift`)
			end
			if a.shop then
				table.insert(problems, `{id}: a vendor may not keep a shift`)
			end
		end
	end
	table.sort(problems)
	return problems
end

function NPCArchetypes.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

return NPCArchetypes
