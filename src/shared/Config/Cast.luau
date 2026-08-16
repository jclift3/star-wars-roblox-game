--!strict
--[[
	Cast.luau

	The six people the campaign is actually about, and where to find them.

	WHY THEY NEEDED A FILE
	CAMPAIGN.md §7 names a recurring cast and the mission text refers to them by
	name -- Vashk signed the order, Nine remembers the deliveries, Kadar owns
	the debt. None of them existed. A story whose characters are only ever
	mentioned in briefing text is a story the player reads *about* rather than
	one they are in, and that is most of what "I'm left wanting more character
	development" was describing.

	WHY NOT JUST ANOTHER ARCHETYPE
	An archetype is a *kind* of person, deliberately: `NPCService` rolls a level
	from the district band, a name from a pool, and a species from a weighted
	table, because eighteen Cartel enforcers should not be identical. Every one
	of those is wrong for a named character. Overseer Vashk is not a Sith Lord
	whose level depends on which zone he happened to spawn in.

	So a cast member borrows an archetype for its *body* -- costume, faction,
	the rig it builds -- and overrides everything that makes a crowd a crowd:
	one of them exists, at a declared level, in a declared district, with a
	declared name and their own conversation. Behaviour is forced to QuestGiver
	whatever the archetype does, which is what lets Vashk wear a Sith Lord's
	armour without attacking the Acolyte he raised.

	WHAT THEY ARE FOR
	They are the only NPCs whose conversation is allowed to assume it has met
	you before. Everything the flags system exists to do -- the world knowing
	which way a thing went -- lands hardest on the person who was there.
]]

local NPCArchetypes = require(script.Parent.NPCArchetypes)
local Planets = require(script.Parent.Planets)

local Cast = {}

export type CastDef = {
	id: string,
	-- The name over their head and in the conversation. Never generated.
	displayName: string,
	-- The line under it: what they are, where a crowd NPC shows its archetype.
	title: string,
	--[[
		Whose body they wear. Costume, species, faction and the rig itself all
		come from here; level, name, behaviour and dialogue do not.
	]]
	archetype: string,
	planet: string,
	zone: string,
	--[[
		Fixed, not rolled from the district band.

		These are mostly high, and deliberately: a story character standing in
		a level 3 town who can be shot to death by a level 3 player is a story
		character the boys will shoot to death by lunchtime.
	]]
	level: number,
	dialogue: string, -- Dialogue tree id
	-- Who they are and which origin they belong to. See CAMPAIGN.md §7.
	note: string,
}

local defs: { [string]: CastDef } = {}

local function def(c: CastDef): CastDef
	defs[c.id] = c
	return c
end

--------------------------------------------------------------------------------
-- The mentors, one per origin
--------------------------------------------------------------------------------

def({
	id = "Vashk",
	displayName = "Overseer Vashk",
	title = "Sith Overseer",
	archetype = "SithLord",
	planet = "Korriban",
	-- The Academy, which Planets.validate keeps peaceful: it is where the
	-- Acolyte opens their eyes, and the man who raised them stands in it.
	zone = "Academy",
	level = 45,
	dialogue = "CastVashk",
	note = "Acolyte's mentor. Signed the disposal order and is not lying to you about it.",
})

def({
	id = "TolenMarr",
	displayName = "Sergeant Tolen Marr",
	title = "Republic Army",
	archetype = "RepublicVeteran",
	planet = "OrdMantell",
	zone = "Garrison",
	level = 30,
	dialogue = "CastTolenMarr",
	note = "Conscript's sergeant. Twenty years in, working a case nobody assigned him.",
})

def({
	id = "VessKadar",
	displayName = "Vess Kadar",
	title = "Fixer",
	archetype = "Smuggler",
	planet = "NarShaddaa",
	zone = "Promenade",
	level = 32,
	dialogue = "CastVessKadar",
	note = "Scoundrel's creditor. Owns the debt, is fond of you, and both are true at once.",
})

def({
	id = "Ordo9",
	displayName = "Ordo-9",
	title = "HK-series Droid",
	archetype = "WarDroid",
	planet = "Taris",
	-- The Camp, not the Dig: the Dig is where the Scrapper prologue happens
	-- and Nine should be standing somewhere you come back to.
	zone = "Camp",
	level = 28,
	dialogue = "CastOrdo9",
	note = "Scrapper's companion. Polite, capable, and missing almost everything he used to be.",
})

--------------------------------------------------------------------------------
-- The two who belong to nobody
--------------------------------------------------------------------------------

--[[
	Solaa and Corr are introduced identically to all four origins, which is the
	point of them: the ally and the antagonist are the same for everyone, so
	four players who agree on nothing else can still be in one conversation.
]]

def({
	id = "RynSolaa",
	displayName = "Master Ryn Solaa",
	title = "Jedi Order",
	archetype = "JediKnight",
	planet = "Tython",
	zone = "Temple",
	level = 42,
	dialogue = "CastRynSolaa",
	note = "The shared ally. The first person to name the Quiet out loud and be glad you came.",
})

def({
	id = "AnethCorr",
	displayName = "Doctor Aneth Corr",
	title = "Czerka Procurement",
	archetype = "Researcher",
	planet = "Taris",
	-- Lot 9, the warehouse. She is not hiding; she has a contract.
	zone = "Lot9",
	level = 26,
	dialogue = "CastAnethCorr",
	note = "The shared antagonist. Not a sadist -- a budget, a quota, and a client she has never met.",
})

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

Cast.defs = defs

function Cast.exists(id: string): boolean
	return defs[id] ~= nil
end

function Cast.get(id: string): CastDef
	local c = defs[id]
	assert(c, `Cast.get: unknown cast member "{id}"`)
	return c
end

function Cast.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

--[[
	Everyone who stands on this planet, in a stable order.

	Sorted because `NPCService.populate` spawns them before the crowd and
	`MAX_NPCS` is a real ceiling: if the galaxy is ever full, which of the six
	got left out should not depend on table iteration order.
]]
function Cast.onPlanet(planetId: string): { CastDef }
	local out: { CastDef } = {}
	for _, id in Cast.ids() do
		local c = defs[id]
		if c.planet == planetId then
			table.insert(out, c)
		end
	end
	return out
end

--[[
	This planet's cast, as spawn rules NPCService can feed to its normal path.

	Behaviour is forced to QuestGiver here rather than trusted to the borrowed
	archetype: four of the six wear the body of something that would otherwise
	open fire, and a mentor who kills you on sight is not a mentor.
]]
function Cast.spawnRules(planetId: string): { Planets.SpawnRule }
	local out: { Planets.SpawnRule } = {}
	for _, c in Cast.onPlanet(planetId) do
		table.insert(out, {
			archetype = c.archetype,
			count = 1,
			zone = c.zone,
			behavior = NPCArchetypes.Behavior.QuestGiver,
			cast = c.id,
		})
	end
	return out
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

--[[
	`dialogueExists` is passed in rather than required.

	Dialogue is the one config that would close a cycle: its trees are written
	against the cast, and the cast names its trees. DialogueService passes the
	function, exactly as it already does for missions, origins and flags.
]]
function Cast.validate(dialogueExists: (string) -> boolean): { string }
	local problems: { string } = {}

	for id, c in defs do
		if c.id ~= id then
			table.insert(problems, `{id}: id field says "{c.id}"`)
		end

		if not NPCArchetypes.exists(c.archetype) then
			table.insert(problems, `{id}: unknown archetype "{c.archetype}"`)
		end

		if not Planets.exists(c.planet) then
			table.insert(problems, `{id}: unknown planet "{c.planet}"`)
		elseif not Planets.hasZone(c.planet, c.zone) then
			table.insert(problems, `{id}: {c.planet} has no zone "{c.zone}"`)
		end

		if not dialogueExists(c.dialogue) then
			table.insert(problems, `{id}: unknown dialogue tree "{c.dialogue}"`)
		end
	end

	return problems
end

return Cast
