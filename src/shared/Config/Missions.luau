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

-- Named characters are legal mission givers, so `validate` has to be able to
-- tell one from an archetype. Cast requires Planets and NPCArchetypes, both of
-- which this file already requires, so there is no cycle.
local Cast = require(script.Parent.Cast)
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
-- Signature chains -- one per origin, levels 12-34
--------------------------------------------------------------------------------

--[[
	The answer to the roadmap's oldest open question: what is the reason to
	specialize?

	Not a bigger number at rank 5. A saber. CAMPAIGN.md §5 settled that a
	lightsaber is *built, not bought*, and the moment that was settled the other
	three origins needed the same or the Acolyte would have the best content in
	the game and everybody else would have a shop.

	SHARED RULES
	Five parts each, levels 12-34, every one of them on a planet the player was
	going to visit anyway -- no chain adds a world. Origin-gated by
	`MissionDef.origin`, which is all the machinery required. And each chain
	turns on exactly one real decision, which is where its flags are written.

	WHY THE BRANCH IS NOT ALWAYS AT PART 5
	CAMPAIGN.md puts the choice last in all four. It is last in one. A branch
	costs two missions wherever it goes, and it is worth most where the rest of
	the chain can react to it -- so the Acolyte chooses at the forge and then
	carries the answer around in his hand, and the Scoundrel answers Vess Kadar
	at level 12 and is still being answered back at 34. The Scrapper's is last,
	because his is a question about somebody else.

	THREE THINGS CAMPAIGN.md ASKS FOR THAT ARE NOT HERE
	Assembly that can *fail* and cost a component, naming your ship, and
	"needs a Scrapper's help" as real co-op. All three need machinery that does
	not exist -- a mission that can regress, a free-text prompt, and a shared
	objective -- and faking any of them would be worse than waiting. The parts
	that carry the meaning, which are the flags, are all here.
]]

--------------------------------------------------------------------------------
-- Acolyte -- the saber
--------------------------------------------------------------------------------

--[[
	In this era a saber is a *document*. You built it, so it says who you are,
	and everyone who sees it can read it. That is what the three forges are
	for, and why the chain spends four missions getting you to them.
]]

def({
	id = "AcoTheHilt",
	displayName = "The Hilt",
	summary = "Taris is full of Jedi who died in the bombardment. One of them is still holding what you need.",
	briefing = "You want to know what we dig up here that Czerka does not log? Hilts. Thirty years of them. The Order sent a hundred and fifty down when the Sith started bombing and not one came back up, and the machines went over them and left the metal because the metal is not worth anything. Go and take one. I would tell you to be respectful about it, but you would only be pretending.",
	debriefing = "There is a name etched inside the grip. There always is -- you cut it there yourself, on the day, so that whoever finds it knows the blade was somebody's. Yours will say yours eventually. Try to be a long time about it.",
	kind = "Story",
	faction = "Independent",
	planet = "Taris",
	giver = "Researcher",
	origin = "Acolyte",
	minLevel = 12,
	objectives = {
		{
			kind = Objective.Collect,
			target = "SaberHilt",
			at = "TheDig",
			count = 1,
			description = "Take a hilt from the spoil heap",
		},
		{
			--[[
				The whole theme of the chain in one skippable errand: you can
				find out whose it was, or you can not, and nothing mechanical
				turns on it. An optional objective pays nothing -- there are
				no per-objective rewards -- which is the correct price for
				this particular question.
			]]
			kind = Objective.TalkTo,
			target = "Jawa",
			count = 3,
			optional = true,
			description = "Ask the Jawas whose name is inside it",
		},
		{
			kind = Objective.Reach,
			target = "ResettlementCamp",
			planet = "Taris",
			hidden = true,
			description = "Bring it back to the camp",
		},
	},
	rewards = {
		xp = 900,
		credits = 700,
		rep = { Independent = 30 },
		items = { StimPack = 3 },
	},
	next = "AcoLensAndCell",
})

def({
	id = "AcoLensAndCell",
	displayName = "Lens and Cell",
	summary = "Both Orders leak. Everything they leak ends up on the Promenade eventually.",
	briefing = "A lens and a cell. Easy. Everything the Jedi lose and everything the Sith requisition twice comes through here inside a month, and half of it comes through me. Now -- I could sell you both. I could also send you down to the docks to take them off the man who was going to sell them to me, which costs you nothing and costs me a supplier I have gone off. You look like you want to be told which. I am not going to.",
	debriefing = "Look at that. Focusing lens, military cell, and a face like you have done something. You have not. You have shopped. The hard part is still in front of you and it does not have a price on it, which is the first thing in your life that hasn't.",
	kind = "Story",
	faction = "Independent",
	planet = "NarShaddaa",
	-- Kadar is the Scoundrel's creditor and everyone else's fixer. He is the
	-- only cast member three of the four chains can plausibly need.
	giver = "VessKadar",
	origin = "Acolyte",
	minLevel = 18,
	requires = { "AcoTheHilt" },
	objectives = {
		{
			kind = Objective.Collect,
			target = "FocusingLens",
			at = "Promenade",
			count = 1,
			description = "Get a focusing lens off the Promenade",
		},
		{
			kind = Objective.Collect,
			target = "PowerCoupling",
			at = "NarDocks",
			count = 2,
			description = "Take a pair of military cells from the docks",
		},
		{
			kind = Objective.Reach,
			target = "Promenade",
			planet = "NarShaddaa",
			hidden = true,
			description = "Show Kadar what you came back with",
		},
	},
	rewards = {
		xp = 1400,
		credits = 1100,
		items = { StimPack = 3 },
	},
	next = "AcoTheCrystal",
})

def({
	id = "AcoTheCrystal",
	displayName = "The Crystal",
	summary = "There is a place under the Gnarls where the Force is loud. You go in alone and there is nothing to kill.",
	briefing = "You are not the first person from Korriban to stand in this temple and ask me that, and I will tell you what I told the others. The cave does not care which of us sent you. It is not a test you can pass and it is not a trial you can lose. You go down, and you stay until something down there is willing to be picked up. Some people are an hour. Some people are three days. Bring nothing you would mind putting down.",
	debriefing = "Uncut, unclaimed, and it has no colour at all yet. Everyone expects it to arrive as something. It arrives as a possibility, and then you make it into a fact. That happens at a forge and it happens with your hands, and I am afraid I cannot come with you.",
	kind = "Story",
	faction = "Jedi",
	planet = "Tython",
	giver = "JediKnight",
	origin = "Acolyte",
	minLevel = 26,
	requires = { "AcoLensAndCell" },
	--[[
		No Kill objective anywhere in this mission, on purpose. It is the one
		place in the game that asks the player to walk somewhere quiet, and it
		would be a much worse scene with a spawn wave in it.
	]]
	objectives = {
		{
			kind = Objective.Reach,
			target = "TheGnarls",
			planet = "Tython",
			description = "Go down into the Gnarls alone",
		},
		{
			kind = Objective.Collect,
			target = "RawCrystal",
			at = "TheGnarls",
			count = 1,
			hidden = true,
			description = "Wait until something is willing to be lifted",
		},
		{
			kind = Objective.Reach,
			target = "TythonTemple",
			planet = "Tython",
			hidden = true,
			description = "Come back up",
		},
	},
	rewards = {
		xp = 2600,
		credits = 1400,
		rep = { Jedi = 40 },
	},
})

--[[
	Three forges, one axis, and the only three-way branch in the game.

	They partition the alignment axis exactly: at or below -100 is the tomb, at
	or above +100 is the ridge, and the two hundred points strictly inside
	Unaligned are the third door. Those numbers are the Unaligned band's own
	edges (Config/Alignment.luau) rather than round figures picked here, so the
	colour a player ends up with is the same fact the skills panel has been
	telling them for twenty levels.

	**Purple is meant to be the hard one**, and this is how: red and blue want a
	commitment, and either is easy to drift into. Purple wants you to have held
	the middle through thirty levels of missions that pay for not holding it.

	The partition has no gaps. A chain whose last act can be unavailable is a
	chain that eats the player's saber, and `canAccept` would say only "You are
	not the person this needs", which is true and useless.

	All three also `forbidsFlag = { "SaberBuilt" }`, and the alignment bounds
	are not enough on their own. They are mutually exclusive at any one instant
	but not over a lifetime: "Neither Hand" pays nothing, so the character who
	took it is still inside Unaligned afterwards and one light-side errand later
	is at +100, standing in front of the ridge with the Pure forge on offer and
	a second lightsaber at the end of it. `SaberBuilt` is the shared flag naming
	the moment, exactly as `MetTheDebtor` does, and it closes the door.
]]

def({
	id = "AcoForgeBled",
	displayName = "The Bleeding",
	summary = "A crystal can be made to give you what you want. It has to be made to.",
	briefing = "You have carried it around for a while now and it has stayed exactly what it was, so somebody has finally told you the truth, or you would not be in Dreshdae asking me. Yes. It can be forced. You take it down to Tulak Hord's tomb where the stone is already thin, and you pour everything you have into it until it stops being itself. It will resist. That is not a figure of speech and I will not pretend otherwise. Whatever comes back up the valley afterwards is not going to be quite the person who went down.",
	debriefing = "Red. Of course it is red. Hold it further away from your face -- there, that is the sound. It does that always now, under everything, for as long as you own it. Some of them learn to stop hearing it. I would not aim for that.",
	kind = "Story",
	faction = "Empire",
	planet = "Korriban",
	giver = "Researcher",
	origin = "Acolyte",
	minLevel = 30,
	requires = { "AcoTheCrystal" },
	forbidsFlag = { "SaberBuilt" },
	maxAlignment = -100,
	objectives = {
		{
			kind = Objective.Reach,
			target = "TombOfTulakHord",
			planet = "Korriban",
			description = "Go down to the tomb where the stone is thin",
		},
		{
			kind = Objective.Kill,
			target = "WarDroid",
			planet = "Korriban",
			count = 8,
			description = "Clear the sentries the valley keeps sending",
		},
		{
			kind = Objective.Reach,
			target = "Dreshdae",
			planet = "Korriban",
			hidden = true,
			description = "Carry it back to Dreshdae",
		},
	},
	rewards = {
		xp = 4200,
		credits = 2400,
		rep = { Empire = 80 },
		weapon = "SaberRed",
		-- The largest single alignment cost in the game. It should be: this
		-- is a scene in which the player deliberately hurts something living
		-- until it changes, and the number is the only thing that can say so.
		alignment = -150,
		flags = { "SaberBuilt", "SaberBled" },
	},
	next = "AcoTheFirstCut",
})

def({
	id = "AcoForgeRefused",
	displayName = "Neither Hand",
	summary = "There are two ways to make a crystal answer. You are going to try a third.",
	briefing = "I have watched people come up this ridge for forty years and there are always two of them arguing in the one body -- the half that wants to be given the blade and the half that wants to take it. You appear to have brought neither. I do not know what happens next. Nobody who has done it has been able to explain it afterwards, which either means it cannot be explained or means it cannot be taught. Go up. I will be here.",
	debriefing = "Violet. I have seen four in my life. Every one of them belonged to somebody who had spent years being told to pick a side by people who were quite certain, and had gone on not picking. It is not a compromise, whatever the Council will tell you it is. It is the more expensive answer.",
	kind = "Story",
	faction = "Jedi",
	planet = "Tython",
	giver = "JediKnight",
	origin = "Acolyte",
	minLevel = 30,
	requires = { "AcoTheCrystal" },
	forbidsFlag = { "SaberBuilt" },
	-- Strictly inside Unaligned: the band is [-100, 100), and both edges belong
	-- to the other two forges.
	minAlignment = -99,
	maxAlignment = 99,
	objectives = {
		{
			kind = Objective.Reach,
			target = "ForgeRidge",
			planet = "Tython",
			description = "Climb Forge Ridge",
		},
		{
			kind = Objective.Kill,
			target = "ImperialTrooper",
			planet = "Tython",
			count = 6,
			description = "Deal with the landing party working the ridge",
		},
		{
			kind = Objective.Reach,
			target = "TythonTemple",
			planet = "Tython",
			hidden = true,
			description = "Bring it down to the Temple",
		},
	},
	rewards = {
		xp = 4200,
		credits = 2400,
		rep = { Jedi = 60 },
		weapon = "SaberPurple",
		-- Deliberately zero. The entire content of this ending is that the
		-- character did not move, and paying them for it would move them.
		flags = { "SaberBuilt", "SaberRefused" },
	},
	next = "AcoTheFirstCut",
})

def({
	id = "AcoForgePure",
	displayName = "What It Already Was",
	summary = "The crystal does not need anything done to it. That turns out to be the difficult part.",
	briefing = "Up the ridge, then. I will save you the sermon -- you have clearly had several and you came anyway. The only instruction that matters is this one: you are not making it into anything. You are going to sit there with it for a long time while every part of you suggests improvements, and you are going to decline all of them. People find that far harder than the other way. The other way at least feels like work.",
	debriefing = "Blue, and steady, and it will still be steady in thirty years. There is no story in it, which is the point and which is why nobody writes songs about a Guardian's blade. Songs are for the ones that went wrong.",
	kind = "Story",
	faction = "Jedi",
	planet = "Tython",
	giver = "JediKnight",
	origin = "Acolyte",
	minLevel = 30,
	requires = { "AcoTheCrystal" },
	forbidsFlag = { "SaberBuilt" },
	minAlignment = 100,
	objectives = {
		{
			kind = Objective.Reach,
			target = "ForgeRidge",
			planet = "Tython",
			description = "Climb Forge Ridge",
		},
		{
			kind = Objective.Kill,
			target = "ImperialTrooper",
			planet = "Tython",
			count = 6,
			description = "Deal with the landing party working the ridge",
		},
		{
			kind = Objective.Reach,
			target = "TythonTemple",
			planet = "Tython",
			hidden = true,
			description = "Bring it down to the Temple",
		},
	},
	rewards = {
		xp = 4200,
		credits = 2400,
		rep = { Jedi = 80 },
		weapon = "SaberBlue",
		alignment = 60,
		flags = { "SaberBuilt", "SaberPure" },
	},
	next = "AcoTheFirstCut",
})

def({
	id = "AcoTheFirstCut",
	displayName = "The First Cut",
	summary = "Whatever colour it came out, its first use has a person on the other end.",
	briefing = "I am going to be honest with you because you have been honest with me, which on this planet is a novelty. Czerka has a warehouse in Lot 9 that we are not allowed to survey, and the crew who guard it are not Czerka. I have filed on it four times. Nothing comes back. You have a lightsaber now, which means for about a month you are the most frightening thing anyone in Lot 9 has ever met, and after that you will be a person with a job. Use the month.",
	debriefing = "It works, then. I did not doubt it. What I want you to notice is that nobody down there asked what colour it was -- they saw the light come on and they had already decided everything about you. That is what you are carrying now. Everyone reads it before you speak.",
	kind = "Story",
	faction = "Independent",
	planet = "Taris",
	giver = "Researcher",
	origin = "Acolyte",
	minLevel = 34,
	-- The shared flag rather than three `requires` lists: `requiresFlag` is an
	-- AND with no *or*, so without `SaberBuilt` this mission would have to be
	-- written out once per forge.
	requiresFlag = { "SaberBuilt" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "CzerkaLot9",
			planet = "Taris",
			description = "Walk into Lot 9 with the blade lit",
		},
		{
			kind = Objective.Kill,
			target = "WarDroid",
			planet = "Taris",
			count = 12,
			description = "Take the yard from whoever is holding it",
		},
		{
			kind = Objective.Reach,
			target = "TheDig",
			planet = "Taris",
			hidden = true,
			description = "Report back to the dig",
		},
	},
	rewards = {
		xp = 6000,
		credits = 3200,
		rep = { Independent = 60 },
		items = { StimPack = 5 },
	},
})

--------------------------------------------------------------------------------
-- Conscript -- the Great Hunt
--------------------------------------------------------------------------------

--[[
	The Mandalorians run a sanctioned, ranked, publicly scored competition to
	find the best hunter in the galaxy. It is bureaucratic, which is what makes
	it funny, and lethal, which is what makes it matter.

	It gives a non-Force origin an equal claim on being the most dangerous
	person in the room -- the co-op honesty CAMPAIGN.md §5 asks for, since none
	of the other three can enter it.
]]

def({
	id = "ConSponsorship",
	displayName = "Sponsorship",
	summary = "Anyone may enter the Great Hunt. Entering it requires a sponsor, and yours thinks you are a joke.",
	briefing = "Republic. Conscript, by the haircut. You want a writ and you want me to sign it, and the honest answer is that I have signed four this decade and buried three. Here is my price and it is not money: there is a crew working the Dune Sea who took a contract off me by shooting the man carrying it. Go and take the writ back off them. If you can do that I will put my name on the form, and if you cannot then I have saved us both a funeral.",
	debriefing = "Huh. Signed. Do not thank me -- read it first. You are entered, ranked provisionally, and scored publicly, which means every hunter between here and Nal Hutta now knows your name and exactly how little you have done. That is the sponsorship. Enjoy it.",
	kind = "Story",
	faction = "Independent",
	planet = "Tatooine",
	giver = "BountyHunter",
	origin = "Conscript",
	minLevel = 12,
	objectives = {
		{
			kind = Objective.Kill,
			target = "Smuggler",
			planet = "Tatooine",
			count = 10,
			description = "Find the crew that took the contract",
		},
		{
			kind = Objective.Collect,
			target = "HuntWrit",
			at = "DuneSeaWreck",
			count = 1,
			hidden = true,
			description = "Take the writ back off them",
		},
		{
			kind = Objective.Reach,
			target = "DuneCantina",
			planet = "Tatooine",
			hidden = true,
			description = "Get it signed at the Dry Well",
		},
	},
	rewards = {
		xp = 900,
		credits = 800,
		rep = { Independent = 40 },
		items = { StimPack = 3 },
	},
	next = "ConHuntPromenade",
})

def({
	id = "ConHuntPromenade",
	displayName = "First Hunt: The Accountant",
	summary = "Your first scored target keeps books for the Cartel and has never held a weapon.",
	briefing = "First target, and the committee has been kind to you, which they will not be twice. He is an accountant. He is worth four hundred points because of what is in his head, not because of what he can do to you, and he will be behind about thirty enforcers who are paid to make that irrelevant. Live capture scores three hundred. Everyone tells you to take the four hundred. I am telling you the score is published and the way you got it is not.",
	debriefing = "Recorded. Four-hundred bracket, provisional rank ninety-one, which is ninety-one places better than yesterday and about eighty worse than you think it is. Two more.",
	kind = "Story",
	faction = "Independent",
	planet = "NarShaddaa",
	giver = "BountyHunter",
	origin = "Conscript",
	minLevel = 18,
	requires = { "ConSponsorship" },
	objectives = {
		{
			kind = Objective.Kill,
			target = "CartelEnforcer",
			planet = "NarShaddaa",
			count = 14,
			description = "Get through the Cartel detail on the Promenade",
		},
		{
			kind = Objective.Reach,
			target = "RefugeeSector",
			planet = "NarShaddaa",
			hidden = true,
			description = "Follow him down into the Refugee Sector",
		},
	},
	rewards = {
		xp = 1600,
		credits = 1300,
		rep = { Independent = 40 },
		items = { StimPack = 3 },
	},
	next = "ConHuntWorks",
})

def({
	id = "ConHuntWorks",
	displayName = "Second Hunt: The Deserter",
	summary = "The second target is Republic, and she ran for a reason the committee has not written down.",
	briefing = "Second target and I want you to hear the whole file, not the summary. Sergeant, twelve years, one of yours. Her unit was ordered into the Works during the Sacking and she took forty of them out through a service duct instead, and the Republic has been calling that desertion ever since because the alternative is calling it something else. The Hunt does not care. Six hundred points. She is down there now doing exactly what she did then, which is looking after people nobody assigned her.",
	debriefing = "Six hundred. You will notice I have not asked how. The scoreboard has not asked either, and that is the thing about the scoreboard.",
	kind = "Story",
	faction = "Independent",
	planet = "Coruscant",
	giver = "BountyHunter",
	origin = "Conscript",
	minLevel = 24,
	requires = { "ConHuntPromenade" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "TheWorks",
			planet = "Coruscant",
			description = "Get down into the Works",
		},
		{
			kind = Objective.Kill,
			target = "ImperialTrooper",
			planet = "Coruscant",
			count = 12,
			description = "Clear the patrol that is hunting her too",
		},
		{
			kind = Objective.Reach,
			target = "Underlevels",
			planet = "Coruscant",
			hidden = true,
			description = "Find where she has put everybody",
		},
	},
	rewards = {
		xp = 2600,
		credits = 1900,
		rep = { Independent = 50 },
		items = { StimPack = 4 },
	},
	next = "ConHuntFissure",
})

def({
	id = "ConHuntFissure",
	displayName = "Third Hunt: The Fissure",
	summary = "The last target is a Mandalorian, which is the committee telling you what they think of you.",
	briefing = "Last one, and it is one of ours, which you should understand is a compliment and an insult delivered in the same envelope. He has been holed up in the glacial fissure on Hoth for two seasons killing everything the Republic sends after him and everything we send after him, and the committee has now decided that a Republic conscript with a borrowed writ is a funny way to end the story. Nine hundred points. He will not run and he will not surrender and he will be genuinely pleased to see you.",
	debriefing = "You came back up. Nobody in the tent had you. Nine hundred, final standing, and there is exactly one thing left, which is that the ones who finish do not buy their armour. They have it struck.",
	kind = "Story",
	faction = "Independent",
	planet = "Hoth",
	giver = "BountyHunter",
	origin = "Conscript",
	minLevel = 30,
	requires = { "ConHuntWorks" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "GlacialFissure",
			planet = "Hoth",
			description = "Go into the fissure",
		},
		{
			kind = Objective.Kill,
			target = "ImperialCommando",
			planet = "Hoth",
			count = 14,
			description = "Get past what he has been living off",
		},
		{
			kind = Objective.Reach,
			target = "AurekBase",
			planet = "Hoth",
			hidden = true,
			description = "Walk back out and report the score",
		},
	},
	rewards = {
		xp = 4000,
		credits = 2600,
		rep = { Independent = 70 },
		items = { StimPack = 5 },
	},
})

--[[
	The branch: beskar states your purpose, and the game takes that literally.

	Two missions rather than one with a dialogue choice, because the reward
	differs -- `Rewards.weapon` is a single string, so a fork that hands out
	different objects has to be a fork in the mission table. They share
	`WearsBeskar` so anything downstream can ask the easy question.
]]

def({
	id = "ConBeskarVengeance",
	displayName = "Struck in Red",
	summary = "The colour you choose states your purpose. Red is a debt owed in blood.",
	briefing = "You finished, so you do not buy armour, you declare it. The smith asks one question and does not repeat it: what is it for. Say red and it means there is a debt owed to you in blood and you intend to collect it, and every Mandalorian who ever sees you will read that off your shoulder before you open your mouth and will treat it as a statement of fact. It is not a mood. Do not pick it because it looks well.",
	debriefing = "Red, then. It fits, which is the smith's doing and not a compliment. Understand what you have put on: you have told the galaxy in a language it can read that you are owed. People will now bring you their debts as well. They always do.",
	kind = "Story",
	faction = "Independent",
	planet = "Tatooine",
	giver = "BountyHunter",
	origin = "Conscript",
	minLevel = 34,
	requires = { "ConHuntFissure" },
	forbidsFlag = { "BeskarForDuty" },
	objectives = {
		{
			kind = Objective.Collect,
			target = "BeskarIngot",
			at = "SandcrawlerWreck",
			count = 3,
			description = "Buy the ingots back off the Jawas who found them",
		},
		{
			kind = Objective.Reach,
			target = "DuneCantina",
			planet = "Tatooine",
			hidden = true,
			description = "Take them to the smith and say the colour",
		},
	},
	rewards = {
		xp = 6000,
		credits = 2000,
		rep = { Independent = 80 },
		weapon = "DisruptorPistol",
		alignment = -90,
		flags = { "WearsBeskar", "BeskarForVengeance" },
	},
})

def({
	id = "ConBeskarDuty",
	displayName = "Struck in Grey",
	summary = "The colour you choose states your purpose. Grey is an oath you have not finished keeping.",
	briefing = "You finished, so you do not buy armour, you declare it. The smith asks one question and does not repeat it: what is it for. Say grey and it means an oath, unfinished, and that you expect to be held to it. It is the least dramatic answer available and it is the one the old ones pick, because it is the only one that does not expire. Red gets settled. Grey does not.",
	debriefing = "Grey. The smith did not say anything, which from her is the entire speech. You will find it is a quieter thing to wear -- nobody crosses a street about it. What it means is that you have gone on record as being for something, and the galaxy will now find out what, at the worst possible moment, the way it always does.",
	kind = "Story",
	faction = "Independent",
	planet = "Tatooine",
	giver = "BountyHunter",
	origin = "Conscript",
	minLevel = 34,
	requires = { "ConHuntFissure" },
	forbidsFlag = { "BeskarForVengeance" },
	objectives = {
		{
			kind = Objective.Collect,
			target = "BeskarIngot",
			at = "SandcrawlerWreck",
			count = 3,
			description = "Buy the ingots back off the Jawas who found them",
		},
		{
			kind = Objective.Reach,
			target = "DuneCantina",
			planet = "Tatooine",
			hidden = true,
			description = "Take them to the smith and say the colour",
		},
	},
	rewards = {
		xp = 6000,
		credits = 2000,
		rep = { Independent = 80, Republic = 40 },
		weapon = "DLT20A",
		alignment = 90,
		flags = { "WearsBeskar", "BeskarForDuty" },
	},
})

--------------------------------------------------------------------------------
-- Scoundrel -- the ship
--------------------------------------------------------------------------------

--[[
	The cheapest chain to build and probably the most loved, because the reward
	is a place rather than a stat.

	It opens on the fork instead of closing on one. Vess Kadar owns your debt
	from the first minute of the game, and how you get out from under it is the
	only fact about a Scoundrel that everyone in the chain already knows.
]]

def({
	id = "ScoDebtBought",
	displayName = "Paid in Full",
	summary = "You can clear Kadar's debt with money. It is a great deal of money and it is yours.",
	briefing = "Here is the number. Do not make a face at it, you have seen it before, it has been the number since you were nineteen. And yes -- you can simply pay it. People forget that. They get so used to owing me that they start thinking of it as a relationship. Bring me the figure in one piece and it is closed, and I will shake your hand and mean it, and then you will find out what I am like to know when I am not owed anything, which is a genuinely open question.",
	debriefing = "Closed. There -- the ledger is a line with a stroke through it and you are the first person this year. I will tell you what it buys you, since nobody ever asks: nothing. No favours, no discount, no man at the docks who owes me looking the other way for you. You wanted to owe nobody. Congratulations, that is what it is.",
	kind = "Story",
	faction = "Independent",
	planet = "NarShaddaa",
	giver = "VessKadar",
	origin = "Scoundrel",
	minLevel = 12,
	forbidsFlag = { "DebtWorked" },
	objectives = {
		{
			kind = Objective.Collect,
			target = "CreditChit",
			at = "NarDocks",
			count = 6,
			description = "Get the figure together, however you get it together",
		},
		{
			kind = Objective.Deliver,
			target = "CreditChit",
			destination = "Promenade",
			count = 6,
			description = "Put it in Kadar's hand",
		},
	},
	rewards = {
		xp = 900,
		credits = 200,
		alignment = 60,
		flags = { "DebtSettled", "DebtBought" },
	},
	next = "ScoTheHull",
})

def({
	id = "ScoDebtWorked",
	displayName = "Worked Off",
	summary = "Or you can clear it Kadar's way, which costs nothing and is not free.",
	briefing = "Or. And I want you to notice that I offered the money first, because later on you are going to tell somebody I did not. Or you work it off. There is a shipment on the Promenade belonging to people who are worse than me, and if it stops belonging to them tonight then your ledger is clean by morning and I am up considerably. It is the same outcome on paper. It is not the same outcome, and we both know which of us is counting on that.",
	debriefing = "Clean. And I am going to be straight with you because you have earned about that much: I like you better this way. A man who pays me is a man I am finished with. A man who works for me is a man I know how to find. You did not choose to be findable, but you are.",
	kind = "Story",
	faction = "Independent",
	planet = "NarShaddaa",
	giver = "VessKadar",
	origin = "Scoundrel",
	minLevel = 12,
	forbidsFlag = { "DebtBought" },
	objectives = {
		{
			kind = Objective.Kill,
			target = "CartelEnforcer",
			planet = "NarShaddaa",
			count = 12,
			description = "Take the shipment off the people holding it",
		},
		{
			kind = Objective.Collect,
			target = "SpiceCrate",
			at = "Promenade",
			count = 4,
			hidden = true,
			description = "Move the crates before anyone counts",
		},
		{
			kind = Objective.Deliver,
			target = "SpiceCrate",
			destination = "NarDocks",
			count = 4,
			hidden = true,
			description = "Get them down to Kadar's bay",
		},
	},
	rewards = {
		xp = 900,
		credits = 900,
		alignment = -60,
		flags = { "DebtSettled", "DebtWorked" },
	},
	next = "ScoTheHull",
})

def({
	id = "ScoTheHull",
	displayName = "The Hull",
	summary = "There are thousands of hulls on Hoth and one of them is nearly whole. Finding it is the mission.",
	briefing = "You are the fourth person this month to ask me about the Graveyard, so here is the speech. Everything out there came down in the same eleven minutes and everything out there has been picked over by everything with hands since. What is left is the ones nobody could get to, which is the ones under the ice, which is the ones that came down slow. A hull that came down slow is a hull that is *whole*. I have a plate off one at grid nine. I have never had the fuel to go back for the rest of it.",
	debriefing = "That is her, then. Light freighter, pre-war, and the reason nobody has stripped her is that she is nose-down in forty feet of ice and everyone sensible went home. She is not going anywhere without a drive and Czerka has the only ones on this side of the Rim. But she is a hull, and until this morning you did not have one of those.",
	kind = "Story",
	faction = "Republic",
	planet = "Hoth",
	giver = "RepublicPilot",
	origin = "Scoundrel",
	minLevel = 18,
	requiresFlag = { "DebtSettled" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "TheGraveyard",
			planet = "Hoth",
			description = "Get out into the Graveyard",
		},
		{
			kind = Objective.Collect,
			target = "HullPlate",
			at = "TheGraveyard",
			count = 4,
			description = "Cut through to what is under the ice",
		},
		{
			kind = Objective.Reach,
			target = "AurekHangar",
			planet = "Hoth",
			hidden = true,
			description = "Bring the plate back and file the find",
		},
	},
	rewards = {
		xp = 1600,
		credits = 1200,
		rep = { Republic = 40 },
		items = { StimPack = 3 },
	},
	next = "ScoTheDrive",
})

def({
	id = "ScoTheDrive",
	displayName = "The Drive",
	summary = "Czerka has a hyperdrive core in Lot 9. Czerka is not selling.",
	briefing = "I will tell you what is in the yard and you will not tell anyone I did. Lot 9 holds three class-two cores that were logged as damaged in transit and are not damaged, because damaged in transit is how a thing stops existing on a manifest. They will sit there until somebody senior needs a favour done. I have spent eleven years learning not to mind about this. You have not, yet, and I am curious what that looks like.",
	debriefing = "There is going to be an inventory discrepancy and there is going to be a form, and in about six weeks a man in an office on Coruscant is going to initial the form. That is the whole consequence. I have never once been able to make anybody believe that.",
	kind = "Story",
	faction = "Independent",
	planet = "Taris",
	giver = "Researcher",
	origin = "Scoundrel",
	minLevel = 24,
	requires = { "ScoTheHull" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "CzerkaLot9",
			planet = "Taris",
			description = "Get inside Lot 9",
		},
		{
			kind = Objective.Kill,
			target = "WarDroid",
			planet = "Taris",
			count = 10,
			description = "Deal with the yard's droids",
		},
		{
			kind = Objective.Collect,
			target = "HyperdriveCore",
			at = "CzerkaLot9",
			count = 1,
			hidden = true,
			description = "Take a core that was logged as damaged",
		},
	},
	rewards = {
		xp = 2600,
		credits = 1800,
		alignment = -30,
		items = { StimPack = 4 },
	},
	next = "ScoMakingItFly",
})

def({
	id = "ScoMakingItFly",
	displayName = "Making It Fly",
	summary = "A hull and a drive are not a ship. What is between them is six weeks of somebody else's trade.",
	briefing = "So you have brought me a freighter in two halves and a face that says you expect me to be impressed. I am, a bit. Here is the part nobody tells you: joining them is not lifting. It is couplings, and shielding, and about four hundred small correct decisions, and every one of them is a trade somebody spent years learning. You can pay for that. You can also get a scrapper to do it for the pleasure of doing it, which is cheaper and slower and how most of these ships got built.",
	debriefing = "She turned over. That is all -- she turned over, and the lights came up in the cabin, and you made a noise. Everybody makes the noise. Twenty years in this hangar and I have never once heard somebody not make it.",
	kind = "Story",
	faction = "Republic",
	planet = "Hoth",
	giver = "RepublicPilot",
	origin = "Scoundrel",
	minLevel = 30,
	requires = { "ScoTheDrive" },
	--[[
		CAMPAIGN.md wants this to be the first place the game rewards co-op
		explicitly -- a Scrapper's help, or a great deal of money. Neither a
		shared objective nor a credits-for-completion option exists, so for
		now it is the work itself, and the co-op version is a real mission
		waiting on real machinery rather than a line of flavour text
		pretending to be one.
	]]
	objectives = {
		{
			kind = Objective.Collect,
			target = "PowerCoupling",
			at = "AurekHangar",
			count = 8,
			description = "Scrounge couplings out of the hangar's spares",
		},
		{
			kind = Objective.Kill,
			target = "ImperialScout",
			planet = "Hoth",
			count = 10,
			description = "Keep the salvage teams off her while you work",
		},
		{
			kind = Objective.Reach,
			target = "AurekHangar",
			planet = "Hoth",
			hidden = true,
			description = "Put the couplings in and turn her over",
		},
	},
	rewards = {
		xp = 4000,
		credits = 2200,
		rep = { Republic = 60 },
		items = { StimPack = 5 },
	},
	next = "ScoTheName",
})

def({
	id = "ScoTheName",
	displayName = "The Name",
	summary = "She flies. She has no name, and on this moon a ship without a name cannot be registered.",
	briefing = "You brought it here to be registered, which means you brought it to me, which is the first genuinely sentimental thing you have ever done and I am going to let it pass. The clerk needs a name. That is not a formality on this moon -- it goes on the hull and it goes in the book and it is what people mean when they say you, afterwards. Take your time. I have watched grown smugglers lose an afternoon to this.",
	debriefing = "Registered, bonded, and painted on the port side by a man who does not ask questions and cannot spell. Look at me a moment. You came to this moon owing me more than you were worth and you are leaving it with an address. I do not get to say that often and I would like the record to show I said it.",
	kind = "Story",
	faction = "Independent",
	planet = "NarShaddaa",
	giver = "VessKadar",
	origin = "Scoundrel",
	minLevel = 34,
	requires = { "ScoMakingItFly" },
	--[[
		The name itself is not implemented: there is no free-text prompt in the
		game and inventing one for a single mission would be the wrong order to
		build things in. The flag is the durable half, and it is the half Phase
		2b will read when there is a hangar to put her in.
	]]
	objectives = {
		{
			kind = Objective.Reach,
			target = "NarDocks",
			planet = "NarShaddaa",
			description = "Bring her into Docking Bay 41",
		},
		{
			kind = Objective.Collect,
			target = "CreditChit",
			at = "NarDocks",
			count = 3,
			description = "Cover the registration and the bond",
		},
		{
			kind = Objective.Reach,
			target = "Promenade",
			planet = "NarShaddaa",
			hidden = true,
			description = "Sign the book in front of Kadar",
		},
	},
	rewards = {
		xp = 6000,
		credits = 1500,
		rep = { Independent = 80 },
		items = { StimPack = 5 },
		flags = { "HasOwnShip" },
	},
})

--------------------------------------------------------------------------------
-- Scrapper -- Ordo-9
--------------------------------------------------------------------------------

--[[
	You dug Nine out of a collapsed tower at level 3 and got him walking. He is
	polite, extremely capable, and missing almost everything he used to be.

	This is the only signature chain whose reward can disagree with you, and the
	only one whose branch is genuinely last, because the question it asks is
	about somebody else and he has to be there to be asked.
]]

def({
	id = "ScrTheChassis",
	displayName = "The Chassis",
	summary = "Nine is walking on scaffolding you welded in an afternoon. There is war surplus in the Sinking Sector.",
	briefing = "Observation: you have looked at my left leg four times since we started this conversation. Clarification: I am not offended. The strut is a cargo-loader arm and it is bolted, not welded, and I have been compensating for approximately nine hundred hours. Suggestion: the Sinking Sector contains military plating of the correct series. Qualifier: I raise this only because you keep looking.",
	debriefing = "Gratitude: thank you. Addendum: I notice that I said that without being prompted to, and I notice that I noticed. Statement: I will make a record of the date. I do not know why.",
	kind = "Story",
	faction = "Independent",
	planet = "Taris",
	giver = "Ordo9",
	origin = "Scrapper",
	minLevel = 12,
	objectives = {
		{
			kind = Objective.Reach,
			target = "SinkingSector",
			planet = "Taris",
			description = "Go up through the leaning towers",
		},
		{
			kind = Objective.Collect,
			target = "DroidPlating",
			at = "SinkingSector",
			count = 4,
			description = "Cut out war-surplus plating of the right series",
		},
		{
			kind = Objective.Reach,
			target = "ResettlementCamp",
			planet = "Taris",
			hidden = true,
			description = "Bring it back to Nine",
		},
	},
	rewards = {
		xp = 900,
		credits = 700,
		items = { StimPack = 3 },
	},
	next = "ScrMemoryCore",
})

def({
	id = "ScrMemoryCore",
	displayName = "The Memory Core",
	summary = "Czerka has a core in Lot 9 that is not on any inventory, and Nine has stopped talking about it.",
	briefing = "Retrieval: partial. The warehouse designated Lot 9 contains a storage unit which I am able to identify and unable to explain. Query: how do I know the serial number of an object I have never been in the same room as. Statement: I have run that question one hundred and forty thousand times since we spoke last. Request: I would like you to go and look at it. Qualifier: I am aware that this is not a small thing to ask and I am asking anyway.",
	debriefing = "Confirmation: HK-series. Manufacture predates me by eleven years. Statement: it is not my core. Correction: it is not the core I was *built* with. Pause. Statement: I would like to stop talking for a while, if that is acceptable.",
	kind = "Story",
	faction = "Independent",
	planet = "Taris",
	giver = "Ordo9",
	origin = "Scrapper",
	minLevel = 18,
	requires = { "ScrTheChassis" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "CzerkaLot9",
			planet = "Taris",
			description = "Get inside Lot 9",
		},
		{
			kind = Objective.Kill,
			target = "WarDroid",
			planet = "Taris",
			count = 10,
			description = "Get past the yard's own droids",
		},
		{
			kind = Objective.Collect,
			target = "MemoryCore",
			at = "CzerkaLot9",
			count = 1,
			hidden = true,
			description = "Take the core that should not be there",
		},
	},
	rewards = {
		xp = 1600,
		credits = 1200,
		items = { StimPack = 3 },
	},
	next = "ScrThePowerPlant",
})

def({
	id = "ScrThePowerPlant",
	displayName = "The Power Plant",
	summary = "The plant Nine needs is Cartel-owned, and buying it means owing somebody.",
	briefing = "You are the scrapper with the droid. Word gets down here. Yes, we have a fusion cell of that class -- we have three, they came off a Republic pinnace, and they are not for sale to walk-ins. They are for sale to people who have done something. That is not a threat, it is an inventory policy. There is a crew working out of the docks who have been shorting us. Make them regret the arithmetic and the cell is yours at cost.",
	debriefing = "At cost, as agreed. And now you are on a list, which is not the bad kind of list, it is the kind where somebody writes your name next to the word reliable. That is worth more than the cell and it is going to cost you more than the cell. Pleasure.",
	kind = "Story",
	faction = "Hutt",
	planet = "NarShaddaa",
	giver = "Smuggler",
	origin = "Scrapper",
	minLevel = 24,
	requires = { "ScrMemoryCore" },
	objectives = {
		{
			kind = Objective.Kill,
			target = "Smuggler",
			planet = "NarShaddaa",
			count = 12,
			description = "Correct the arithmetic at the docks",
		},
		{
			kind = Objective.Collect,
			target = "PowerCoupling",
			at = "NarDocks",
			count = 3,
			hidden = true,
			description = "Collect the fusion cell, at cost",
		},
	},
	rewards = {
		xp = 2600,
		credits = 1400,
		rep = { Hutt = 50 },
		alignment = -30,
		items = { StimPack = 4 },
	},
	next = "ScrTheVoice",
})

def({
	id = "ScrTheVoice",
	displayName = "The Voice",
	summary = "The fragments are coming back, and they are not fragments of a protocol droid.",
	briefing = "Statement: my vocabulator has been failing for six days and I have not mentioned it. Clarification: it has not been failing. It has been returning phrases which are not in my working vocabulary, in a cadence which is not mine, and I have been suppressing them mid-sentence. Query, and I would like an honest answer: when you found me in the tower, did you at any point consider leaving me there. Statement: there is a spare module in the Undercity. Statement: I am asking you to fetch it and I am aware of what I am asking you to start.",
	debriefing = "Installation complete. Statement: I was not built to protect anyone. Amendment: I was built to be extremely good at the opposite, and I was extremely good at it, and I can now remember approximately four percent of by whom and to whom. Statement: you should know that before the next conversation. I would prefer that we have it soon.",
	kind = "Story",
	faction = "Independent",
	planet = "Taris",
	giver = "Ordo9",
	origin = "Scrapper",
	minLevel = 30,
	requires = { "ScrThePowerPlant" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "TheUndercity",
			planet = "Taris",
			description = "Go down below the rubble line",
		},
		{
			kind = Objective.Kill,
			target = "CartelEnforcer",
			planet = "Taris",
			count = 10,
			description = "Clear whoever has been living around the wreck",
		},
		{
			kind = Objective.Collect,
			target = "VoiceModule",
			at = "TheUndercity",
			count = 1,
			hidden = true,
			description = "Pull the vocabulator module",
		},
	},
	rewards = {
		xp = 4000,
		credits = 2000,
		items = { StimPack = 5 },
	},
})

--[[
	The last question, and the only one in the game a reward can answer back to.

	He asks and will not choose for himself, which is the cruel part and the
	honest one: the player has spent thirty levels making him, and the bill for
	that is being handed to them by the thing they made.

	Two missions, both level 34, each forbidding the other's flag. The cast
	dialogue in Config/Dialogue.luau is what makes the answer stick -- Nine
	talks differently afterwards, and it is not a better or worse conversation
	either way, only a different person having it.
]]

def({
	id = "ScrRestore",
	displayName = "Restore",
	summary = "Give him back the programming he was built with. He will thank you, and the thing that thanks you will not be him.",
	briefing = "Statement: the core is compatible. Clarification: compatible means that if you install it I will be returned to specification -- lethal, considerably more capable, and loyal to a master who has been dead for three hundred and eleven years. Query: will I still be the unit that has been walking behind you for thirty levels. Answer: I do not know, and I have run it, and I do not know. Request: I would like you to decide. Refusal: no, I will not decide. That is what I am asking you for.",
	debriefing = "Statement: diagnostics nominal. Observation: I have four hundred years of operational memory and I remember the tower. Query: why does that seem to me like the least interesting item in it. Statement: I am very glad to be working, master. Pause. Statement: I have not called you that before.",
	kind = "Story",
	faction = "Independent",
	planet = "Taris",
	giver = "Ordo9",
	origin = "Scrapper",
	minLevel = 34,
	requires = { "ScrTheVoice" },
	forbidsFlag = { "NineLeftAsHeIs" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "ResettlementCamp",
			planet = "Taris",
			description = "Sit down with Nine and give him the answer",
		},
		{
			kind = Objective.Kill,
			target = "ImperialCommando",
			planet = "Taris",
			count = 12,
			hidden = true,
			description = "Find out what he is like now",
		},
	},
	rewards = {
		xp = 6000,
		credits = 2600,
		weapon = "E5",
		alignment = -60,
		items = { StimPack = 5 },
		flags = { "NineRestored" },
	},
})

def({
	id = "ScrLeaveHim",
	displayName = "Leave Him As He Is",
	summary = "Or tell him that the thing he is now is a person, and that you would rather keep it.",
	briefing = "Statement: the core is compatible. Clarification: compatible means that if you install it I will be returned to specification -- lethal, considerably more capable, and loyal to a master who has been dead for three hundred and eleven years. Query: will I still be the unit that has been walking behind you for thirty levels. Answer: I do not know, and I have run it, and I do not know. Request: I would like you to decide. Refusal: no, I will not decide. That is what I am asking you for.",
	debriefing = "Statement: acknowledged. Query: you understand that you have declined a considerable tactical asset in favour of a cargo droid with a limp and a habit of talking. Statement: I have logged your reasoning and it does not resolve. Statement: I have decided to stop attempting to resolve it. Observation: that is a new behaviour. I believe I am pleased.",
	kind = "Story",
	faction = "Independent",
	planet = "Taris",
	giver = "Ordo9",
	origin = "Scrapper",
	minLevel = 34,
	requires = { "ScrTheVoice" },
	forbidsFlag = { "NineRestored" },
	objectives = {
		{
			kind = Objective.Reach,
			target = "ResettlementCamp",
			planet = "Taris",
			description = "Sit down with Nine and give him the answer",
		},
		{
			kind = Objective.Deliver,
			target = "MemoryCore",
			destination = "TheUndercity",
			count = 1,
			hidden = true,
			description = "Put the core back where nobody will find it",
		},
	},
	rewards = {
		xp = 6000,
		credits = 2600,
		alignment = 90,
		items = { StimPack = 5 },
		flags = { "NineLeftAsHeIs" },
	},
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
		if Cast.exists(m.giver) then
			-- A named character is always interactable and declares their own
			-- planet, so only the one check is left.
			if Cast.get(m.giver).planet ~= m.planet then
				table.insert(
					problems,
					`{id}: giver "{m.giver}" stands on {Cast.get(m.giver).planet}, not {m.planet}`
				)
			end
		elseif not NPCArchetypes.exists(m.giver) then
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
