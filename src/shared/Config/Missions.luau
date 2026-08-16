--!strict
--[[
	Missions.luau

	Every mission in the game, plus the rules for who can see and take it.

	SHAPE OF A MISSION
	A mission is a list of objectives and a reward. Objectives are matched
	against gameplay events by `kind` and `target` -- MissionService listens for
	"NPC died" and asks every active mission whether it cares, rather than each
	mission wiring up its own listeners. That keeps missions as pure data, which
	is what makes them safe to hot-edit and cheap to add.

	Objective kinds come from `Objective` below and nowhere else. Same reasoning
	as NPC behaviours: a free-string objective type is a silent no-op waiting to
	happen.

	CHAINS
	`next` links a mission to its follow-up. Chains are how a sandbox gets a
	spine without railroading -- the player can ignore one entirely, but if they
	follow it there is a story at the end.
]]

local Factions = require(script.Parent.Factions)
local Flags = require(script.Parent.Flags)
local Items = require(script.Parent.Items)
local MissionKinds = require(script.Parent.MissionKinds)
local Planets = require(script.Parent.Planets)
local NPCArchetypes = require(script.Parent.NPCArchetypes)
-- Required outright rather than passed into `validate` the way Progression is:
-- Origins is small, and it already requires Planets and Factions, both of
-- which this file requires too, so there is no cycle to break.
local Origins = require(script.Parent.Origins)
local Radiant = require(script.Parent.Radiant)
local Weapons = require(script.Parent.Weapons)

local Missions = {}

-- The shape of a mission lives in MissionKinds so that Radiant can name it
-- without requiring this file back. Re-exported here because this is where
-- everything already looks for it.
local Objective = MissionKinds.Objective
local VALID_KINDS = MissionKinds.VALID_KINDS
Missions.Objective = Objective

export type ObjectiveDef = MissionKinds.ObjectiveDef
export type Rewards = MissionKinds.Rewards
export type MissionDef = MissionKinds.MissionDef

local defs: { [string]: MissionDef } = {}

local function def(m: MissionDef): MissionDef
	defs[m.id] = m
	return m
end

--------------------------------------------------------------------------------
-- Origin prologues -- one per origin, on that origin's home world
--------------------------------------------------------------------------------

--[[
	The first thing any character does, and the only content gated on `origin`.

	FOUR SHORT ONES RATHER THAN ONE BRANCHING ONE
	Each is written for somebody the author knows everything about: where they
	woke up, who raised them, what they owe. That is the whole reason the
	creation screen was worth building -- a choice that changes the first hour
	is a choice; a choice that changes a line of stat text is a menu.

	They are deliberately the smallest missions in the file. Three objectives,
	no combat, level 1, and each hands off to the world's existing opening
	chain where there is one. A prologue that outstays its welcome is the
	thing every player of the second character will resent.

	`boardFor` hides the other three rather than greying them out: an origin
	is answered once and never again, so the refusal would never stop being
	true. See `canAccept`.
]]

def({
	id = "KorTheEmptyBunk",
	displayName = "The Empty Bunk",
	summary = "Sennat's bed has been reassigned and nobody will say his name. Find out who cleared it.",
	briefing = "You are the acolyte who keeps asking. Fine -- ask properly. The intake records are in the Academy and they are not guarded, because nobody has ever wanted them. Bring me what is written about the bunk in the third dormitory, and I will tell you what is not.",
	debriefing = "He was not expelled and he did not die. He was collected, and the form for it already existed, which means he was not the first. You may go now. Come back when you are strong enough for the answer to be any use to you.",
	kind = "Story",
	faction = "Empire",
	planet = "Korriban",
	giver = "Researcher",
	origin = "Acolyte",
	minLevel = 1,
	objectives = {
		{
			kind = Objective.Collect,
			target = "ResearchData",
			at = "SithAcademy",
			count = 3,
			description = "Take the intake records from the Academy",
		},
		{
			kind = Objective.TalkTo,
			target = "Civilian",
			count = 3,
			description = "Ask in Dreshdae who empties a bunk",
		},
		{
			kind = Objective.Deliver,
			target = "ResearchData",
			destination = "Dreshdae",
			description = "Bring the records back to Dreshdae",
		},
	},
	rewards = {
		xp = 150,
		credits = 180,
		rep = { Empire = 40 },
		items = { StimPack = 2 },
		--[[
			No alignment. All four prologues end in a discovery rather than a
			decision, and moving the axis for something the player was only
			shown would teach them it drifts on its own.

			The flag is the point: this is the first loose thread of The Quiet,
			and from here the world can say one careful line to the character
			who pulled it. See Config/Flags.luau.
		]]
		flags = { "SawTheIntakeForm" },
	},
})

def({
	id = "OrdTheOtherCopy",
	displayName = "The Other Copy",
	summary = "Your enlistment file says you volunteered. Go and find the block it says you volunteered from.",
	briefing = "New ones always want their file. Here is what is in it: you signed, you were fifteen, and the block was cleared lawfully. Here is what I will tell you once and not again -- there were two copies of that form, and the village kept theirs. Walk down and read it before somebody tidier than me does.",
	debriefing = "Now you have seen both. Neither is a lie exactly, which is the part that will keep you up. Draw your kit. You are a soldier this morning whatever you were last year.",
	kind = "Story",
	faction = "Republic",
	planet = "OrdMantell",
	giver = "RepublicVeteran",
	origin = "Conscript",
	minLevel = 1,
	objectives = {
		{
			kind = Objective.Collect,
			target = "ResearchData",
			at = "FortGarnik",
			count = 2,
			description = "Pull your enlistment file from the fort",
		},
		{
			kind = Objective.Reach,
			target = "DrelliadVillage",
			planet = "OrdMantell",
			description = "Walk down to the village the block was cleared for",
		},
		{
			kind = Objective.TalkTo,
			target = "Civilian",
			count = 3,
			description = "Ask who else signed that year",
		},
	},
	rewards = {
		xp = 150,
		credits = 180,
		rep = { Republic = 40 },
		items = { StimPack = 2 },
		flags = { "SawBothCopies" },
	},
	next = "OrdPayAndRations",
})

def({
	id = "TatTheManifest",
	displayName = "The Manifest",
	summary = "Two crates came off the freighter that are not on the paperwork. Move them before anyone counts.",
	briefing = "You read the manifest. I know, because you have not stopped looking at the door since. Here is the useful half of that talent: there are two crates on the field that nobody wrote down, and the man they belong to is on Nar Shaddaa and does not know yet. Get them to the Dry Well and you are a person who does me favours instead of a person who owes me one.",
	debriefing = "Clean. No names, no receipt, and the crates were never there. Your parents' debt is still your parents' debt -- but this planet does not know your family, and that is worth more than it sounds.",
	kind = "Story",
	faction = "Independent",
	planet = "Tatooine",
	giver = "Smuggler",
	origin = "Scoundrel",
	minLevel = 1,
	objectives = {
		{
			kind = Objective.Collect,
			target = "SpiceCrate",
			at = "Anchorhead",
			count = 2,
			description = "Take the two crates that are not on the manifest",
		},
		{
			kind = Objective.Reach,
			target = "DuneCantina",
			planet = "Tatooine",
			description = "Get across town to the Dry Well",
		},
		{
			kind = Objective.Deliver,
			target = "SpiceCrate",
			destination = "DuneCantina",
			description = "Hand the crates over and stay for one drink",
		},
	},
	rewards = {
		xp = 150,
		credits = 180,
		rep = { Independent = 40 },
		items = { StimPack = 2 },
		flags = { "OwesNobody" },
	},
	next = "TatDustAndDroids",
})

def({
	id = "TarTheSealedCrate",
	displayName = "The Sealed Crate",
	summary = "Ordo-9 remembers delivering containers like yours. Get enough power into him to finish the sentence.",
	briefing = "MEMORY SECTOR NINE IS INTACT AND UNPOWERED. I HAVE CARRIED THIS SHAPE BEFORE. I HAVE CARRIED FOURTEEN OF THIS SHAPE BEFORE. THE REST OF THE SENTENCE REQUIRES TWO COUPLINGS FROM THE DIG AND I WOULD LIKE YOU TO WANT TO HEAR IT.",
	debriefing = "FOURTEEN, AND ALL OF THEM TO THE SAME BUYER, AND NONE OF THEM CAME BACK. I HAVE ALSO RECOVERED THE PART WHERE I DID NOT ASK WHAT WAS INSIDE. I AM SORRY. I AM TOLD THAT IS THE CORRECT THING TO SAY AND I FIND THAT I MEAN IT.",
	kind = "Story",
	faction = "Independent",
	planet = "Taris",
	giver = "ProtocolDroid",
	origin = "Scrapper",
	minLevel = 1,
	objectives = {
		{
			kind = Objective.Collect,
			target = "PowerCoupling",
			at = "TheDig",
			count = 2,
			description = "Salvage two couplings out of the spoil heap",
		},
		{
			kind = Objective.TalkTo,
			target = "ProtocolDroid",
			description = "Let Ordo-9 finish the sentence",
		},
		{
			kind = Objective.Reach,
			target = "ResettlementCamp",
			planet = "Taris",
			description = "Take what he said back to the camp",
		},
	},
	rewards = {
		xp = 150,
		credits = 180,
		rep = { Independent = 40 },
		items = { StimPack = 2 },
		flags = { "HeardNineRemember" },
	},
})

--------------------------------------------------------------------------------
-- Tatooine -- the opening chain
--------------------------------------------------------------------------------

def({
	id = "TatDustAndDroids",
	displayName = "Dust and Droids",
	summary = "Recover a farmer's stolen astromech from the Jawas.",
	briefing = "Jawas took my astromech in the night. I need it back before the harvest, and I am too old to go out there after it.",
	debriefing = "You found him. Thank you. Take this -- it is not much, but out here nothing is.",
	kind = "Story",
	faction = "Independent",
	planet = "Tatooine",
	giver = "MoistureFarmer",
	minLevel = 1,
	objectives = {
		{
			kind = Objective.Reach,
			target = "SandcrawlerWreck",
			planet = "Tatooine",
			description = "Find the sandcrawler in the wastes",
		},
		--[[
			Talking, not killing. This was four dead Jawas under a description
			that promised a conversation -- and the Jawa is an unarmed Wander
			archetype with a Trade prompt, so the only way to move the counter
			was to open fire on peaceful traders. TalkTo says what it means.
		]]
		{
			kind = Objective.TalkTo,
			target = "Jawa",
			count = 4,
			description = "Ask the Jawas at the crawler about it",
		},
		{
			kind = Objective.Collect,
			target = "AstromechDroid",
			at = "SandcrawlerWreck",
			count = 1,
			description = "Recover the astromech",
		},
		{
			kind = Objective.Deliver,
			target = "AstromechDroid",
			destination = "MoistureFarm",
			description = "Return the droid to the farm",
		},
	},
	rewards = {
		xp = 220,
		credits = 350,
		rep = { Independent = 60 },
		items = { StimPack = 3 },
	},
	next = "TatUnwelcomeAttention",
})

def({
	id = "TatUnwelcomeAttention",
	displayName = "Unwelcome Attention",
	summary = "The Empire noticed you asking questions. Deal with the patrol.",
	briefing = "Word travels in Anchorhead. A patrol has been asking after the offworlder who went into the Dune Sea. That is you.",
	debriefing = "They will send more. They always do. But you have bought yourself some room.",
	kind = "Story",
	faction = "Independent",
	planet = "Tatooine",
	giver = "Smuggler",
	minLevel = 3,
	requires = { "TatDustAndDroids" },
	objectives = {
		{
			kind = Objective.Kill,
			target = "ImperialTrooper",
			count = 6,
			description = "Break up the Imperial patrol",
		},
		-- A place, so Reach. This was a TalkTo aimed at a point of interest,
		-- which matches against archetype ids and so matched nothing at all.
		{
			kind = Objective.Reach,
			target = "DuneCantina",
			planet = "Tatooine",
			description = "Lie low in the Dry Well",
		},
	},
	rewards = {
		xp = 400,
		credits = 600,
		rep = { Republic = 120, Empire = -180 },
		weapon = "DH17",
	},
	next = "TatTheHuttsFavour",
})

def({
	id = "TatTheHuttsFavour",
	displayName = "The Hutt's Favour",
	summary = "The Hutt's people have a job, and refusing is its own kind of answer.",
	briefing = "The Great Nagurra has heard of you. He does not extend invitations twice. Bring him the spice a courier lost in the wastes.",
	debriefing = "The Hutt is satisfied. That is worth more on this rock than credits.",
	kind = "Story",
	faction = "Hutt",
	planet = "Tatooine",
	giver = "CartelEnforcer",
	minLevel = 6,
	requires = { "TatUnwelcomeAttention" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "DuneSeaWreck",
			planet = "Tatooine",
			description = "Find the courier's wreck",
		},
		{ kind = Objective.Kill, target = "TuskenRaider", count = 8, description = "Clear the Tusken camp" },
		{
			kind = Objective.Collect,
			target = "SpiceCrate",
			at = "DuneSeaWreck",
			count = 3,
			description = "Recover the spice",
		},
		{
			kind = Objective.Deliver,
			target = "SpiceCrate",
			destination = "HuttEstate",
			description = "Deliver the spice to Nagurra's estate",
		},
		{
			kind = Objective.Kill,
			target = "BountyHunter",
			count = 1,
			hidden = true,
			description = "Survive the double-cross",
		},
	},
	rewards = {
		xp = 900,
		credits = 1800,
		rep = { Hutt = 300 },
		items = { StimPack = 5 },
		skillPoints = 1,
	},
})

def({
	id = "TatBountyBoard",
	displayName = "Bounty: Tusken Raiders",
	summary = "The town is paying per raider. No questions about method.",
	briefing = "Raiders hit the eastern farms again. The town pays by the head and does not ask how.",
	kind = "Repeatable",
	faction = "Independent",
	planet = "Tatooine",
	giver = "Merchant",
	minLevel = 4,
	objectives = {
		{ kind = Objective.Kill, target = "TuskenRaider", count = 10, description = "Kill Tusken Raiders" },
	},
	rewards = {
		xp = 180,
		credits = 400,
		rep = { Independent = 25 },
	},
	repeatable = true,
	cooldown = 1800,
})

--------------------------------------------------------------------------------
-- Coruscant -- Imperial and underworld
--------------------------------------------------------------------------------

def({
	id = "CorPaperTrail",
	displayName = "Paper Trail",
	summary = "Slice a Senate District terminal without tripping the alarm.",
	briefing = "There is a manifest on a terminal in the Senate District. I want a copy, and I want the Empire to keep believing nobody has one.",
	debriefing = "Clean work. The manifest names three worlds we did not know they were stripping.",
	kind = "Story",
	faction = "Republic",
	planet = "Coruscant",
	giver = "Smuggler",
	minLevel = 10,
	objectives = {
		{
			kind = Objective.Reach,
			target = "SenateDistrict",
			planet = "Coruscant",
			description = "Reach the Senate District",
		},
		{ kind = Objective.Slice, target = "SenateTerminal", description = "Slice the archive terminal" },
		{
			kind = Objective.Survive,
			target = "SenateDistrict",
			count = 90,
			description = "Survive the security response",
		},
		{
			kind = Objective.Reach,
			target = "Underlevels",
			planet = "Coruscant",
			description = "Escape to the Underlevels",
		},
	},
	rewards = {
		xp = 1200,
		credits = 2200,
		rep = { Republic = 400, Empire = -300 },
		skillPoints = 1,
		flags = { "HasTheManifest" },
	},
	timeLimit = 600,
	next = "CorTheLongFall",
})

def({
	id = "CorTheLongFall",
	displayName = "The Long Fall",
	summary = "An informant is being moved between towers. Take them off the skybridge.",
	briefing = "They are transferring a contact across a skybridge at level 4000. If that transport reaches the Imperial embassy in the Works, treaty immunity closes over them and we lose them for good.",
	debriefing = "They are shaken, but they are ours. And they know what Czerka is holding on Taris.",
	kind = "Story",
	faction = "Republic",
	planet = "Coruscant",
	giver = "RepublicPilot",
	minLevel = 14,
	requires = { "CorPaperTrail" },
	objectives = {
		{
			kind = Objective.Kill,
			target = "ImperialTrooper",
			count = 10,
			description = "Clear the skybridge escort",
		},
		{
			kind = Objective.Kill,
			target = "ImperialCommando",
			count = 2,
			description = "Eliminate the commando detail",
		},
		{
			kind = Objective.Escort,
			target = "Informant",
			destination = "CoruscantSpaceport",
			description = "Escort the informant to Skydock Seven",
		},
	},
	rewards = {
		xp = 2000,
		credits = 3500,
		rep = { Republic = 600, Empire = -450 },
		weapon = "DC15A",
		skillPoints = 1,
		-- The first alignment in the game that is not a dialogue choice: this
		-- mission ends with a frightened person alive who would not have been.
		-- Small, because it was also a job somebody paid you for.
		alignment = 60,
		flags = { "InformantSaved" },
	},
	next = "TarWhatTheyKept",
})

--[[
	THE UNDERLEVELS FORK

	The first place in the game where taking one job deletes another.

	Both start from the same fact -- an Imperial officer is paying for names
	out of the Underlevels -- and each forbids the other's flag, so whichever
	the player does first is the one that happened. Neither is presented as
	the correct answer and neither is locked behind alignment: this is where
	alignment comes FROM.

	Deliberately at level 12, well inside the first evening. A consequence
	system the player meets in the fortieth hour is a consequence system they
	will never find out they have.
]]

def({
	id = "CorLoyaltyCheck",
	displayName = "Loyalty Check",
	summary = "An officer wants dissidents in the Underlevels made quiet.",
	briefing = "There is sedition growing under the plate. The Empire rewards those who prune it early. Eight names, and I do not need them written down.",
	debriefing = "Efficient. The Empire notices efficiency. It notices very little else, which you may find is the useful part.",
	kind = "Side",
	faction = "Empire",
	planet = "Coruscant",
	giver = "ImperialOfficer",
	minLevel = 12,
	requiredRep = 200,
	forbidsFlag = { "WarnedTheUnderlevels" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "Underlevels",
			planet = "Coruscant",
			description = "Descend to the Underlevels",
		},
		{ kind = Objective.Kill, target = "Smuggler", count = 8, description = "Silence the dissidents" },
	},
	rewards = {
		xp = 900,
		credits = 1600,
		rep = { Empire = 350 },
		items = { StimPack = 4 },
		-- Larger than The Long Fall's +60 is negative, and it should be. That
		-- one saved a stranger as a side effect of a job; this one is eight
		-- people killed for a list, on purpose, for money.
		alignment = -220,
		flags = { "PrunedTheUnderlevels" },
	},
})

def({
	id = "CorTheWarning",
	displayName = "The Warning",
	summary = "The same officer is buying names. Get under the plate first and tell them.",
	briefing = "You heard him same as I did. He is paying by the head and there are people down there who still think the treaty means something. I cannot go -- half the Underlevels owe me money and the other half know my face. Go down, tell them, and be somewhere else when his people arrive. They will arrive.",
	debriefing = "Four families out before the commandos came through, and they came through. You will not get paid for this by anyone who matters. I am telling you now so you are not waiting for it.",
	kind = "Side",
	faction = "Republic",
	planet = "Coruscant",
	giver = "Smuggler",
	minLevel = 12,
	forbidsFlag = { "PrunedTheUnderlevels" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "Underlevels",
			planet = "Coruscant",
			description = "Descend to the Underlevels",
		},
		{
			kind = Objective.TalkTo,
			target = "Civilian",
			count = 4,
			description = "Warn four households before the list is bought",
		},
		{
			kind = Objective.Kill,
			target = "ImperialCommando",
			count = 3,
			description = "Hold the stairwell while they clear out",
		},
	},
	rewards = {
		-- Worse paid than Loyalty Check and worth more XP, which is the whole
		-- argument: the right thing costs money and teaches you something.
		xp = 1100,
		credits = 700,
		rep = { Republic = 250, Empire = -400 },
		items = { StimPack = 4 },
		alignment = 220,
		flags = { "WarnedTheUnderlevels" },
	},
})

def({
	id = "CorSkylanePatrol",
	displayName = "Skylane Patrol",
	summary = "Fly a standing patrol route over the Senate District.",
	briefing = "Traffic control wants a visible presence on the upper skylanes. Fly the route, report anything unregistered.",
	kind = "Repeatable",
	faction = "Empire",
	planet = "Coruscant",
	giver = "ImperialOfficer",
	minLevel = 8,
	objectives = {
		{
			kind = Objective.Reach,
			target = "SkylaneAlpha",
			planet = "Coruscant",
			description = "Fly to waypoint Alpha",
		},
		{
			kind = Objective.Reach,
			target = "SkylaneBeta",
			planet = "Coruscant",
			description = "Fly to waypoint Beta",
		},
		{
			kind = Objective.Reach,
			target = "SkylaneGamma",
			planet = "Coruscant",
			description = "Fly to waypoint Gamma",
		},
	},
	rewards = {
		xp = 250,
		credits = 500,
		rep = { Empire = 60 },
	},
	repeatable = true,
	cooldown = 1200,
})

--------------------------------------------------------------------------------
-- Hoth
--------------------------------------------------------------------------------

def({
	id = "HothColdOpen",
	displayName = "Cold Open",
	summary = "Echo Base needs a downed sensor array back online before the next sweep.",
	briefing = "A sensor tower went dark in the north ravine. If we are blind when the next probe comes through, we are finished.",
	debriefing = "Array is live. You have bought this base another week.",
	kind = "Side",
	faction = "Republic",
	planet = "Hoth",
	giver = "RepublicTrooper",
	minLevel = 12,
	objectives = {
		{
			kind = Objective.Reach,
			target = "NorthRavine",
			planet = "Hoth",
			description = "Reach the north ravine",
		},
		{
			kind = Objective.Collect,
			target = "PowerCoupling",
			at = "NorthRavine",
			count = 2,
			description = "Salvage power couplings",
		},
		{
			kind = Objective.Slice,
			target = "SensorArray",
			description = "Bring the sensor array back online",
		},
	},
	rewards = {
		xp = 1000,
		credits = 1400,
		rep = { Republic = 300 },
		items = { StimPack = 4 },
	},
})

def({
	id = "HothProbeHunt",
	displayName = "Probe Hunt",
	summary = "Imperial probe droids are mapping the glacier. Destroy them.",
	briefing = "Probes are seeding the ice. Every one we miss is a coordinate on an Imperial chart.",
	kind = "Repeatable",
	faction = "Republic",
	planet = "Hoth",
	giver = "RepublicPilot",
	minLevel = 14,
	objectives = {
		{
			kind = Objective.Destroy,
			target = "ProbeDroid",
			count = 6,
			description = "Destroy Imperial probe droids",
		},
	},
	rewards = {
		xp = 320,
		credits = 650,
		rep = { Republic = 80, Empire = -60 },
	},
	repeatable = true,
	cooldown = 1500,
})

--------------------------------------------------------------------------------
-- Tython -- the Force chain
--------------------------------------------------------------------------------

def({
	id = "TytQuietOrder",
	displayName = "A Quiet Order",
	summary = "Someone in Kalikori Village is asking about the Temple. Find out who.",
	briefing = "A stranger has been asking after the Order in the wrong village. Either they are looking for us, or someone is looking for them.",
	debriefing = "You have a steady hand and you did not draw first. That is rarer than the Force.",
	kind = "Story",
	faction = "Jedi",
	planet = "Tython",
	giver = "RepublicSecurity",
	minLevel = 10,
	objectives = {
		--[[
			`TheedInformant` was not an archetype, so this could never tick.
			The protocol droid is the informant now: on Tython it spawns only
			in the Temple zone, so the objective is still tied to a place the
			player can be pointed at.
		]]
		{
			kind = Objective.TalkTo,
			target = "ProtocolDroid",
			description = "Ask the Temple's droids what they have heard",
		},
		{
			kind = Objective.Reach,
			target = "TythonTemple",
			planet = "Tython",
			description = "Follow the trail to the Temple",
		},
		{ kind = Objective.TalkTo, target = "JediKnight", description = "Speak with the Jedi" },
	},
	rewards = {
		xp = 1100,
		credits = 900,
		rep = { Jedi = 350 },
	},
	next = "TytTrialOfPatience",
})

def({
	id = "TytTrialOfPatience",
	displayName = "The Trial of Patience",
	summary = "The Jedi will teach you -- after you prove you can hold a line without breaking it.",
	briefing = "An Imperial patrol will come up out of the Gnarls within the hour. Hold the approach. Do not pursue them. Holding is the lesson.",
	debriefing = "You held. Now take this hilt. What you put in it is your own business.",
	kind = "Story",
	faction = "Jedi",
	planet = "Tython",
	giver = "JediKnight",
	minLevel = 14,
	requires = { "TytQuietOrder" },
	objectives = {
		{
			kind = Objective.Survive,
			target = "TempleApproach",
			count = 180,
			description = "Hold the temple approach",
		},
		{
			kind = Objective.Kill,
			target = "ImperialTrooper",
			count = 12,
			description = "Repel the Imperial assault",
		},
	},
	rewards = {
		xp = 2400,
		credits = 1200,
		rep = { Jedi = 700, Empire = -400 },
		weapon = "SaberBlue",
		skillPoints = 2,
	},
	timeLimit = 900,
})

--------------------------------------------------------------------------------
-- Taris / Nar Shaddaa / Korriban -- late game
--------------------------------------------------------------------------------

def({
	id = "TarWhatTheyKept",
	displayName = "What They Kept",
	summary = "The informant's coordinates point at a Czerka warehouse on a planet nobody audits.",
	briefing = "Czerka says Lot 9 is empty and scheduled for demolition. The power draw disagrees. Find out what is still running.",
	debriefing = "Whatever they are storing in there, they wanted it somewhere no inspector would ever have cause to land.",
	kind = "Story",
	faction = "Republic",
	planet = "Taris",
	giver = "Researcher",
	minLevel = 20,
	requires = { "CorTheLongFall" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "CzerkaLot9",
			planet = "Taris",
			description = "Reach Czerka Lot 9",
		},
		{ kind = Objective.Slice, target = "LabTerminal", description = "Slice the warehouse records" },
		{
			kind = Objective.Kill,
			target = "WarDroid",
			count = 6,
			description = "Fight past the security droids",
		},
		{
			kind = Objective.Collect,
			target = "ResearchData",
			at = "CzerkaLot9",
			count = 1,
			description = "Extract the manifests",
		},
	},
	rewards = {
		xp = 4000,
		credits = 6000,
		rep = { Republic = 800, Empire = -600 },
		skillPoints = 2,
		flags = { "SawLot9" },
	},
	next = "KorTheTomb",
})

def({
	id = "NarDebtCollection",
	displayName = "Debt Collection",
	summary = "Someone on the Promenade owes the Cartel and has stopped answering.",
	briefing = "A dealer has missed three payments and changed docking bays twice. Remind him the moon is not that big.",
	kind = "Side",
	faction = "Hutt",
	planet = "NarShaddaa",
	giver = "CartelEnforcer",
	minLevel = 16,
	requiredRep = 150,
	objectives = {
		-- Was `DelinquentDealer`, which is not an archetype. Jawas are the only
		-- thing Nar Shaddaa puts in the Refuge zone, so a Jawa dealer keeps the
		-- objective where the description says it is.
		{
			kind = Objective.TalkTo,
			target = "Jawa",
			description = "Find the Jawa dealer in the Refugee Sector",
		},
		{ kind = Objective.Kill, target = "Smuggler", count = 5, description = "Deal with his hired help" },
		{
			kind = Objective.Collect,
			target = "CreditChit",
			at = "RefugeeSector",
			count = 1,
			description = "Collect what he owes",
		},
		{
			kind = Objective.Deliver,
			target = "CreditChit",
			destination = "Promenade",
			description = "Return the chit to the Cartel",
		},
	},
	rewards = {
		xp = 1800,
		credits = 3000,
		rep = { Hutt = 400 },
		weapon = "DL44",
	},
})

def({
	id = "NarOpenContract",
	displayName = "Open Contract",
	summary = "A standing bounty on anyone wearing Imperial white.",
	briefing = "The moon has an open contract. Empire uniforms, paid by the piece, no paperwork.",
	kind = "Bounty",
	faction = "Hutt",
	planet = "NarShaddaa",
	giver = "BountyHunter",
	minLevel = 18,
	objectives = {
		{
			kind = Objective.Kill,
			target = "ImperialTrooper",
			count = 15,
			description = "Collect on the Imperial contract",
		},
	},
	rewards = {
		xp = 700,
		credits = 1600,
		rep = { Hutt = 100, Empire = -200 },
	},
	repeatable = true,
	cooldown = 2400,
})

--[[
	The finale is given by a Researcher in Dreshdae, the same archetype that
	handed over the Taris lead -- an Academy archivist quietly passing notes
	off-world. It is also the only interactable that stands on Korriban at all,
	so a Republic officer here would be a giver the player could never reach.
]]
def({
	id = "KorTheTomb",
	displayName = "The Tomb",
	summary = "The trail ends on Korriban, behind a sealed door and a Sith Lord.",
	briefing = "Everything Czerka warehoused on Taris was requisitioned by one man, and he has not come out of Tulak Hord's tomb in a decade. Go and ask him why.",
	debriefing = "It is finished. The galaxy is not fixed -- but it is lighter by one very heavy thing.",
	kind = "Story",
	faction = "Republic",
	planet = "Korriban",
	giver = "Researcher",
	minLevel = 32,
	requires = { "TarWhatTheyKept" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "TombOfTulakHord",
			planet = "Korriban",
			description = "Break the seal on the tomb",
		},
		{
			kind = Objective.Kill,
			target = "SithHonourGuard",
			count = 4,
			description = "Cut through the Valley guard",
		},
		{
			kind = Objective.Kill,
			target = "ImperialCommando",
			count = 6,
			description = "Clear the commandos posted inside",
		},
		{ kind = Objective.Kill, target = "SithLord", count = 1, description = "Confront the Sith Lord" },
	},
	rewards = {
		xp = 12000,
		credits = 20000,
		rep = { Republic = 2000, Jedi = 800, Empire = -1500 },
		weapon = "SaberPurple",
		skillPoints = 3,
		-- The largest single swing in the game so far, and it should be: this
		-- is the end of the spine, and what was in that tomb had been eating
		-- people for a decade.
		alignment = 200,
		flags = { "TombOpened" },
	},
})

def({
	id = "KorDigContract",
	displayName = "Dig Contract",
	summary = "Czerka pays by the crate for anyone willing to work the Wastes.",
	briefing = "Half the dig crew walked off and the rest will not go past the ridge. The ore does not stop coming and the droids do not stop failing.",
	kind = "Repeatable",
	-- Czerka is a corporation, not a faction, so the standing goes to the
	-- Independents: this is the one job on Korriban that does not care whose
	-- side you are on.
	faction = "Independent",
	planet = "Korriban",
	giver = "Merchant",
	minLevel = 28,
	objectives = {
		{
			kind = Objective.Collect,
			target = "RawOre",
			at = "KorribanWastes",
			count = 12,
			description = "Collect raw ore",
		},
		{
			kind = Objective.Kill,
			target = "WarDroid",
			count = 8,
			description = "Clear malfunctioning droids",
		},
	},
	rewards = {
		xp = 1400,
		credits = 3200,
		rep = { Independent = 120 },
	},
	repeatable = true,
	cooldown = 2400,
})

--------------------------------------------------------------------------------
-- Ord Mantell -- the garrison chain
--------------------------------------------------------------------------------

--[[
	The Conscript's prologue, and the whole planet: levels 1-6, three story
	missions and one bounty. Ord Mantell shipped with nothing at all, so a
	world reachable from the galaxy map answered "no work going on this planet
	right now" -- the same silent emptiness as a POI nobody points at.

	Two authoring constraints this planet makes obvious.

	**The giver has to stand here.** `giver` is matched against the archetype
	id of whoever you are talking to, so a mission whose giver never spawns on
	its own planet can only be taken from the board. Sergeant Marr is written
	in the briefings but is a `RepublicVeteran` in the data, because named NPCs
	do not exist yet and a giver the player cannot reach is worse than an
	unnamed one.

	**The militia are Smugglers.** Ord Mantell's separatists have no archetype
	of their own -- `Planets.luau` already spawns Smugglers in the Fields and
	the Wilds as the stand-in, and the Kill objectives follow that rather than
	inventing a target that never spawns.

	The beat the data cannot carry yet is the one the story turns on: the Jedi
	liaison who goes hollow mid-firefight. No Jedi spawns on this world, so it
	lives in the briefing and debriefing text until origins can gate content
	(CAMPAIGN §6.1). That is the honest place for it -- better prose than a
	fake objective.
]]

def({
	id = "OrdPayAndRations",
	displayName = "Pay and Rations",
	summary = "Carry the garrison's requisition payment down to Drelliad Village.",
	briefing = "You are new, so you get the errand. The village is owed for three months of grain we took at gunpoint and called a requisition. Walk it down there and hand it over. Try to look like an army.",
	debriefing = "They took it. They did not thank you. Nobody here has thanked a soldier in two years, and if you understand why, you will last longer than most.",
	kind = "Story",
	faction = "Republic",
	planet = "OrdMantell",
	giver = "RepublicVeteran",
	minLevel = 1,
	objectives = {
		{
			kind = Objective.Collect,
			target = "CreditChit",
			at = "FortGarnik",
			count = 3,
			description = "Draw the pay chits from the fort",
		},
		{
			kind = Objective.Reach,
			target = "DrelliadVillage",
			planet = "OrdMantell",
			description = "Walk down to Drelliad Village",
		},
		{
			kind = Objective.Deliver,
			target = "CreditChit",
			destination = "DrelliadVillage",
			description = "Hand the payment over",
		},
		{
			kind = Objective.TalkTo,
			target = "Civilian",
			count = 3,
			description = "Ask the villagers what else they need",
		},
	},
	rewards = {
		xp = 200,
		credits = 300,
		rep = { Republic = 60 },
		items = { StimPack = 3 },
	},
	next = "OrdTheHillWithNoName",
})

def({
	id = "OrdTheHillWithNoName",
	displayName = "The Hill With No Name",
	summary = "Take the Savrip Fields position and get the relay working again.",
	briefing = "We have taken that hill four times. Today we take it a fifth. It has no name, it is worth nothing, and the separatists want it because we want it. Push through the wire and get our relay talking to the fort.",
	debriefing = "The hill is ours. Command has already stopped mentioning it. Get some rest -- you did the part they will not put in a report.",
	kind = "Story",
	faction = "Republic",
	planet = "OrdMantell",
	giver = "RepublicVeteran",
	minLevel = 3,
	requires = { "OrdPayAndRations" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "SavripFields",
			planet = "OrdMantell",
			description = "Reach the trenches on the Savrip Fields",
		},
		{
			kind = Objective.Kill,
			target = "Smuggler",
			count = 8,
			description = "Clear the separatist irregulars off the hill",
		},
		{
			kind = Objective.Collect,
			target = "PowerCoupling",
			at = "SavripFields",
			count = 2,
			description = "Salvage couplings for the relay",
		},
		{
			kind = Objective.Deliver,
			target = "PowerCoupling",
			destination = "FortGarnik",
			description = "Get the couplings back to Fort Garnik",
		},
	},
	rewards = {
		xp = 380,
		credits = 550,
		rep = { Republic = 140 },
		weapon = "DH17",
	},
	next = "OrdFiledAsFatigue",
})

def({
	id = "OrdFiledAsFatigue",
	displayName = "Filed as Fatigue",
	summary = "Recover the field record from the wreck in the Jagged Wilds -- and watch what command does with it.",
	briefing = "Our liaison went down in the swamp and did not come back the way she went in. There is a medical record on that wreck and I want it in my hand before anyone else touches it. Do not read it out loud.",
	debriefing = "The adjutant has entered it as combat fatigue and ordered you not to write it down. Keep your copy. One day someone is going to ask, and you will be the only one who can answer.",
	kind = "Story",
	faction = "Republic",
	planet = "OrdMantell",
	giver = "RepublicVeteran",
	minLevel = 5,
	requires = { "OrdTheHillWithNoName" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "JaggedWilds",
			planet = "OrdMantell",
			description = "Find the wreck in the Jagged Wilds",
		},
		{
			kind = Objective.Kill,
			target = "Smuggler",
			count = 10,
			description = "Fight through the separatist camps",
		},
		{
			kind = Objective.Collect,
			target = "ResearchData",
			at = "JaggedWilds",
			count = 1,
			description = "Recover the field record",
		},
		{
			kind = Objective.Deliver,
			target = "ResearchData",
			destination = "FortGarnik",
			description = "Carry it back to Fort Garnik",
		},
		{
			kind = Objective.TalkTo,
			target = "ProtocolDroid",
			hidden = true,
			description = "Hear what the adjutant files it as",
		},
	},
	rewards = {
		xp = 820,
		credits = 1400,
		rep = { Republic = 300 },
		items = { StimPack = 5 },
		skillPoints = 1,
	},
})

def({
	id = "OrdSeparatistBounty",
	displayName = "Bounty: Separatist Irregulars",
	summary = "The village pays per head, quietly, and would rather the fort did not know.",
	briefing = "The fort has its war. We have men coming out of the fields at night taking what is left. We pay in coin and we do not write your name anywhere.",
	kind = "Repeatable",
	-- Not a Republic job. The village is paying to be left alone, by both
	-- sides, which is the only politics anyone here has left.
	faction = "Independent",
	planet = "OrdMantell",
	giver = "Merchant",
	minLevel = 2,
	objectives = {
		{
			kind = Objective.Kill,
			target = "Smuggler",
			count = 10,
			description = "Kill separatist irregulars",
		},
	},
	rewards = {
		xp = 160,
		credits = 340,
		rep = { Independent = 25 },
	},
	repeatable = true,
	cooldown = 1800,
})

--------------------------------------------------------------------------------

--[[
	Fold in the generated missions.

	Merged into `defs` rather than resolved on demand so that every reader
	downstream -- `boardFor`, `validate`, `Missions.ids`, and through that
	`PickupService`'s spawn table -- treats them as missions and needs to know
	nothing. Generation is pure, so this table is identical on the server and
	on every client, which is what lets the board be sent as bare ids.
]]
local loadProblems: { string } = {}
for id, m in Radiant.all() do
	-- An authored mission that took a generated id would be replaced here
	-- without a word, and `boardFor`'s rotation would then hide it most days.
	-- Reported through `validate` rather than thrown, like every other config
	-- fault: a bad mission should not stop the game booting.
	if defs[id] then
		table.insert(loadProblems, `{id}: authored id collides with a generated one`)
	end
	defs[id] = m
end

Missions.defs = defs

function Missions.get(id: string): MissionDef
	local m = defs[id]
	assert(m, `Missions.get: unknown mission "{id}"`)
	return m
end

function Missions.exists(id: string): boolean
	return defs[id] ~= nil
end

-- Compared by `boardFor`, so it is a constant rather than a literal written
-- twice. See the check itself for why this refusal is the one that hides.
local NOT_YOUR_ORIGIN = "Not your story"

-- Stands in for an absent `requiresFlag`/`forbidsFlag` so the loops below do
-- not need a nil check each. Never written to.
local EMPTY_FLAGS: { string } = {}

--[[
	Whether a player may take a mission right now.

	Returns ok plus a reason, so the mission board can grey an entry out and say
	why instead of just hiding it -- a locked mission the player can see is a
	goal; a hidden one is nothing.
]]
function Missions.canAccept(
	missionId: string,
	profile: {
		level: number,
		origin: string,
		alignment: number,
		flags: { [string]: boolean },
		factionRep: { [string]: number },
		missions: {
			active: { [string]: any },
			completed: { [string]: number },
			lastCompleted: { [string]: number },
		},
	},
	now: number
): (boolean, string?)
	local m = defs[missionId]
	if not m then
		return false, "Unknown mission"
	end
	if profile.missions.active[missionId] then
		return false, "Already active"
	end

	local completedCount = profile.missions.completed[missionId]
	if completedCount and not m.repeatable then
		return false, "Already completed"
	end

	--[[
		Checked before level, because it is the one refusal that will never
		stop being true. Everything below this is a lock the player can pick
		by playing; an origin is answered once at creation and never again,
		so `boardFor` hides these rather than greying them out.
	]]
	if m.origin and m.origin ~= profile.origin then
		return false, NOT_YOUR_ORIGIN
	end

	if profile.level < m.minLevel then
		return false, `Requires level {m.minLevel}`
	end

	if m.requiredRep then
		local rep = profile.factionRep[m.faction] or 0
		if rep < m.requiredRep then
			local faction = Factions.defs[m.faction]
			local label = if faction then faction.displayName else m.faction
			return false, `Requires standing with the {label}`
		end
	end

	if m.requires then
		for _, prereq in m.requires do
			if not profile.missions.completed[prereq] then
				local prereqDef = defs[prereq]
				return false, `Requires "{prereqDef and prereqDef.displayName or prereq}"`
			end
		end
	end

	--[[
		Grouped under one reason on purpose.

		"Requires: you warned the Underlevels" would tell a player who pruned
		them that the fork existed and that they took the other road, which is
		the one thing a consequence should never announce. `boardFor` still
		greys these out rather than hiding them -- a door you can see is shut
		is a story; a door that was never drawn is nothing -- but what is
		behind it stays behind it.
	]]
	local function pathClosed(): boolean
		for _, flagId in m.requiresFlag or EMPTY_FLAGS do
			if not profile.flags[flagId] then
				return true
			end
		end
		for _, flagId in m.forbidsFlag or EMPTY_FLAGS do
			if profile.flags[flagId] then
				return true
			end
		end
		return false
	end
	if pathClosed() then
		return false, "Not the road you took"
	end

	if m.minAlignment and profile.alignment < m.minAlignment then
		return false, "You are not the person this needs"
	end
	if m.maxAlignment and profile.alignment > m.maxAlignment then
		return false, "You are not the person this needs"
	end

	if m.repeatable and m.cooldown and completedCount then
		local lastAt = profile.missions.lastCompleted[missionId]
		if lastAt and now - lastAt < m.cooldown then
			local remaining = math.ceil((m.cooldown - (now - lastAt)) / 60)
			return false, `Available again in {remaining} min`
		end
	end

	return true, nil
end

--- Every mission offered on `planet` that the player could see on a board.
function Missions.boardFor(
	planet: string,
	profile: any,
	now: number
): { { mission: MissionDef, locked: boolean, reason: string? } }
	-- Every generated mission for this planet exists all the time; only a few
	-- are pinned up on any given day. Without this the authored missions --
	-- the actual story -- would be a handful of entries under a wall of
	-- bounties.
	local posted: { [string]: boolean } = {}
	for _, id in Radiant.postedOn(planet, now) do
		posted[id] = true
	end

	local out = {}
	for _, m in defs do
		if m.planet ~= planet then
			continue
		end
		if Radiant.isRadiant(m.id) and not posted[m.id] then
			continue
		end
		local ok, reason = Missions.canAccept(m.id, profile, now)
		-- Two refusals are worth hiding rather than greying out: a finished
		-- one-shot is clutter, and another origin's story is a goal this
		-- character can never reach.
		if ok or (reason ~= "Already completed" and reason ~= NOT_YOUR_ORIGIN) then
			table.insert(out, { mission = m, locked = not ok, reason = reason })
		end
	end
	table.sort(out, function(a, b)
		if a.locked ~= b.locked then
			return not a.locked
		end
		if a.mission.minLevel ~= b.mission.minLevel then
			return a.mission.minLevel < b.mission.minLevel
		end
		return a.mission.displayName < b.mission.displayName
	end)
	return out
end

--- How many of an objective's `count` are needed. Defaults to 1.
function Missions.objectiveTarget(obj: ObjectiveDef): number
	return obj.count or 1
end

function Missions.isComplete(missionId: string, progress: { [number]: number }): boolean
	local m = Missions.get(missionId)
	for i, obj in m.objectives do
		if obj.optional then
			continue
		end
		if (progress[i] or 0) < Missions.objectiveTarget(obj) then
			return false
		end
	end
	return true
end

--- Rewards scaled by the player's level, so an old mission is not worthless.
function Missions.scaledRewards(missionId: string, playerLevel: number, creditMult: number?): Rewards
	local m = Missions.get(missionId)
	local r = m.rewards
	-- Cap the bonus: outlevelling content should not turn low missions into a
	-- better credit farm than the content built for your level.
	local levelBonus = 1 + math.clamp((playerLevel - m.minLevel) * 0.02, 0, 0.5)
	return {
		xp = math.floor(r.xp * levelBonus),
		credits = math.floor(r.credits * levelBonus * (creditMult or 1)),
		rep = r.rep,
		items = r.items,
		weapon = r.weapon,
		skillPoints = r.skillPoints,
		-- Passed straight through. Scaling a consequence by how long the
		-- player took to get to it would be nonsense.
		alignment = r.alignment,
		flags = r.flags,
	}
end

--[[
	Cross-checks every mission against the configs it references.

	Same reasoning as NPCArchetypes.validate: a mission pointing at an archetype
	that no longer exists becomes an objective that can never complete, and the
	player has no way to tell that from a hard one.
]]
function Missions.validate(): { string }
	local problems = table.clone(loadProblems)
	for id, m in defs do
		if not Planets.exists(m.planet) then
			table.insert(problems, `{id}: unknown planet "{m.planet}"`)
		end
		if not Factions.exists(m.faction) then
			table.insert(problems, `{id}: unknown faction "{m.faction}"`)
		end
		if m.rewards.weapon and not Weapons.exists(m.rewards.weapon) then
			table.insert(problems, `{id}: reward weapon "{m.rewards.weapon}" does not exist`)
		end
		--[[
			The giver is matched against the archetype id of whoever the
			player is talking to (DialogueService.offersFor), so a giver who
			does not stand on the mission's own planet makes the mission
			board the only way to take it -- and the conversation the mission
			was written for never happens. Checked here rather than trusted,
			because nothing errors when it is wrong.
		]]
		if not NPCArchetypes.exists(m.giver) then
			table.insert(problems, `{id}: unknown giver archetype "{m.giver}"`)
		elseif not NPCArchetypes.get(m.giver).interactable then
			table.insert(problems, `{id}: giver "{m.giver}" is not interactable`)
		elseif not Planets.spawnsArchetype(m.planet, m.giver) then
			table.insert(problems, `{id}: giver "{m.giver}" does not spawn on {m.planet}`)
		end
		--[[
			An origin nobody can be is a mission nobody can take, and
			`boardFor` hides exactly this refusal -- so a typo here does not
			grey an entry out, it deletes the mission from the game with no
			error anywhere.
		]]
		if m.origin and not Origins.exists(m.origin) then
			table.insert(problems, `{id}: unknown origin "{m.origin}"`)
		end
		if m.next and not defs[m.next] then
			table.insert(problems, `{id}: next mission "{m.next}" does not exist`)
		end
		if m.requires then
			for _, prereq in m.requires do
				if not defs[prereq] then
					table.insert(problems, `{id}: prerequisite "{prereq}" does not exist`)
				end
			end
		end
		--[[
			An undeclared flag is worse here than in a conversation: on a gate
			it silently deletes the mission for everybody (`requiresFlag`) or
			for nobody (`forbidsFlag`), and as a reward it writes a key no
			condition can ever match. Three lists, one check.
		]]
		local flagLists: { { list: { string }?, role: string } } = {
			{ list = m.requiresFlag, role = "requires" },
			{ list = m.forbidsFlag, role = "forbids" },
			{ list = m.rewards.flags, role = "sets" },
		}
		for _, entry in flagLists do
			for _, flagId in entry.list or EMPTY_FLAGS do
				if not Flags.exists(flagId) then
					table.insert(problems, `{id}: {entry.role} undeclared flag "{flagId}"`)
				end
			end
		end
		if #m.objectives == 0 then
			table.insert(problems, `{id}: no objectives`)
		end
		for i, obj in m.objectives do
			if not VALID_KINDS[obj.kind] then
				table.insert(problems, `{id}: objective {i} has unknown kind "{obj.kind}"`)
			end
			if obj.kind == Objective.Kill and obj.target and not NPCArchetypes.exists(obj.target) then
				table.insert(problems, `{id}: objective {i} targets unknown archetype "{obj.target}"`)
			end
			--[[
				TalkTo is matched against the archetype id of whoever the
				player just spoke to, so its target has to be an archetype.
				Three shipped naming characters that were never written --
				`TheedInformant`, `DelinquentDealer` -- and one naming a point
				of interest, and all four were objectives that could be
				accepted and never completed.
			]]
			if obj.kind == Objective.TalkTo then
				if not obj.target then
					table.insert(problems, `{id}: objective {i} talks to nobody in particular`)
				elseif not NPCArchetypes.exists(obj.target) then
					table.insert(problems, `{id}: objective {i} talks to unknown archetype "{obj.target}"`)
				elseif not NPCArchetypes.get(obj.target).interactable then
					table.insert(
						problems,
						`{id}: objective {i} talks to "{obj.target}", which is not interactable`
					)
				end
			end
			--[[
				Reach and Deliver resolve their target against the planet's
				points of interest, and MissionService silently skips one it
				cannot find. Six objectives shipped pointing at POIs that were
				never defined, so four missions could be accepted and never
				finished, with nothing on screen to say why.
			]]
			if obj.kind == Objective.Reach and obj.target and not Planets.hasPOI(m.planet, obj.target) then
				table.insert(problems, `{id}: objective {i} reaches unknown POI "{obj.target}" on {m.planet}`)
			end
			if
				obj.kind == Objective.Deliver
				and obj.destination
				and not Planets.hasPOI(m.planet, obj.destination)
			then
				table.insert(
					problems,
					`{id}: objective {i} delivers to unknown POI "{obj.destination}" on {m.planet}`
				)
			end
			--[[
				A Collect objective is the spawn table: PickupService reads
				`at` to decide where the items go, so one without it puts
				nothing in the world and can never be finished.
			]]
			if obj.kind == Objective.Collect then
				if not obj.at then
					table.insert(problems, `{id}: objective {i} collects but has no "at" point of interest`)
				elseif not Planets.hasPOI(m.planet, obj.at) then
					table.insert(
						problems,
						`{id}: objective {i} collects at unknown POI "{obj.at}" on {m.planet}`
					)
				end
			end
			if
				(obj.kind == Objective.Collect or obj.kind == Objective.Deliver)
				and obj.target
				and not Items.exists(obj.target)
			then
				table.insert(problems, `{id}: objective {i} handles unknown item "{obj.target}"`)
			end
			if m.rewards.rep then
				for factionId in m.rewards.rep do
					if not Factions.exists(factionId) then
						table.insert(problems, `{id}: reward rep for unknown faction "{factionId}"`)
					end
				end
			end
		end
	end
	table.sort(problems)
	return problems
end

function Missions.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

return Missions
