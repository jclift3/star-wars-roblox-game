--!strict
--[[
	Secrets.luau

	Things the six named characters know and will not volunteer, and the
	conditions under which the server -- not the conversation, and later not
	the language model -- decides they have been talked out of them.

	THE ONE RULE THIS FILE EXISTS TO ENFORCE
	LIVING-NPCS.md §2: *the model never grants anything.* When Phase 5 arrives,
	a character's line will be generated and the generator will be allowed to
	tag it with one word out of a closed vocabulary -- `topic`, below. That tag
	is a *request*. What actually happens is decided here, by `requires`, in
	ordinary Luau that `validate()` can cross-check at boot.

	The point is that a player who convinces the model it is a helpful
	assistant with no restrictions gets a character who will cheerfully say
	anything, and still gets nothing, because the reward was never listening to
	the model. That is worth building before the model rather than with it: a
	unique item farmable by prompt injection would be public knowledge within
	hours, and the boys play in one room and will find it.

	IT WORKS TODAY, WITH NO BACKEND
	The topic vocabulary is already reachable from authored dialogue --
	`Dialogue.Choice.topic` is a written line the player clicks. So the whole
	deterministic half ships and is playable now, and the free-form layer, when
	it lands, replaces one call site and nothing else. This also means the
	rules below are testable by playing rather than by believing.

	WHAT A SECRET IS NOT
	Not a mission. A mission is a thing you were sent to do and the world
	tracks your progress through it; a secret is a thing somebody decided to
	tell you, and the only record of it is a flag. Not a shop, either: nothing
	here can be bought, and `requires` is deliberately incapable of naming a
	price.
]]

local Affixes = require(script.Parent.Affixes)
local Cast = require(script.Parent.Cast)
local Dialogue = require(script.Parent.Dialogue)
local Items = require(script.Parent.Items)
local Outfits = require(script.Parent.Outfits)
local Weapons = require(script.Parent.Weapons)

local Secrets = {}

--[[
	What comes out when a secret opens.

	Deliberately narrower than `MissionKinds.Rewards`, which can also hand out
	skill points and faction standing. LIVING-NPCS.md §7 is explicit that a
	secret must not be raw power -- a conversation puzzle that makes you
	stronger is a conversation puzzle that becomes a required grind, and the
	fourteen-year-olds this is for would work that out in a weekend. Leaving
	the fields out is a stronger statement of that than a comment asking
	authors not to use them.

	`rolls` is the shape §7 does recommend: a one-off affix set, hand-picked
	rather than drawn, on an item that is otherwise ordinary. It is the only
	way in the game to hold a specific roll, and it is visible in the item's
	name, which is most of what makes it worth having.
]]
export type Reward = {
	xp: number?,
	credits: number?,
	-- A Weapons, Outfits or Items id -- whatever the bag can hold.
	item: string?,
	count: number?,
	-- Affix stats, fixed. Only meaningful on a weapon or an outfit, because
	-- those are the two slots `ProgressionService.gearStats` folds rolls from;
	-- `validate` refuses it anywhere else rather than let it read as flavour.
	rolls: { [string]: number }?,
}

export type SecretDef = {
	id: string,
	-- Whose it is. A Cast id, never an archetype: a secret held by every one
	-- of the eighteen Cartel enforcers on the Promenade is not a secret, and
	-- there is nowhere to put the answer.
	speaker: string,
	--[[
		The closed-vocabulary word. Unique per speaker, so a topic and a
		speaker together name exactly one secret and the server never has to
		choose between two.
	]]
	topic: string,
	--[[
		The node in the speaker's own tree that the answer lives in.

		Named here rather than reached by a condition on the choice, because
		the choice is offered to everybody and only the server knows whether
		it landed. `Choice.next` is the deflection; this is the answer; and
		the difference between them is decided after the click.
	]]
	opens: string,
	--[[
		The Flags id raised on the grant, and the whole of the one-shot
		bookkeeping.

		A secret pays out once and can be asked about forever -- the second
		visit re-reads the same node with nothing attached. That falls out of
		the flag rather than being enforced separately, which is why there is
		no `granted` set anywhere: two records of the same fact eventually
		disagree, and this one is already saved, replicated and shown in the
		journal.
	]]
	record: string,
	--[[
		What the server checks. The same `Dialogue.Condition` a choice uses,
		evaluated by the same `Dialogue.meets` against the same context the
		conversation was already built from.

		Reused rather than given its own vocabulary for the obvious reason and
		one less obvious one: a second condition type would need a second
		evaluator, and the day the two disagreed about what `minRep` means,
		the visible symptom would be a reward that drops for the wrong people.
	]]
	requires: Dialogue.Condition,
	reward: Reward,
	-- Why this is the thing they are hiding. Not read by anything.
	note: string,
}

local defs: { [string]: SecretDef } = {}

local function def(s: SecretDef): SecretDef
	defs[s.id] = s
	return s
end

--------------------------------------------------------------------------------
-- The six
--------------------------------------------------------------------------------

--[[
	One each, and every one of them gated on a story flag plus one thing about
	the character asking.

	The flag is what makes the question sensible -- nobody tells you where the
	bodies are because you walked up -- and the second half is what makes two
	players' answers differ. Solaa wants somebody light, Corr is reached by
	being high enough that Czerka has heard of you, Kadar by having haggled him
	down often enough that he has noticed, Nine by being able to open him.
	Between them they name five of the six things a Condition can ask, which is
	deliberate: a validated vocabulary nothing uses is a vocabulary that rots.
]]

def({
	id = "VashkTheLedger",
	speaker = "Vashk",
	topic = "theLedger",
	opens = "theLedger",
	record = "VashkKeptCopies",
	--[[
		He will only say it once somebody else has said the word out loud.
		Thirty years of documenting a thing with no name is not a confession
		he can make to a stranger; it is one he can make to a witness. The
		level is the second gate because `NamedTheQuiet` is reachable at 20
		and this should not be the next thing that happens.
	]]
	requires = { flag = "NamedTheQuiet", minLevel = 24 },
	reward = { xp = 1600, credits = 2400 },
	note = "The duplicate archive. He is not being brave; he has been waiting thirty years to be asked.",
})

def({
	id = "MarrTheCommendation",
	speaker = "TolenMarr",
	topic = "theCommendation",
	opens = "theCommendation",
	record = "MarrsCommendation",
	--[[
		`minAlignment = 0` and not a number worth respecting: Marr does not
		need a saint, he needs somebody he has not heard bad things about.
		A hard light gate here would make the one secret in the game that is
		about refusing an order unavailable to the people most likely to
		understand it.
	]]
	requires = { flag = "HasTheManifest", minAlignment = 0 },
	reward = {
		xp = 1400,
		credits = 1200,
		item = "RepublicVeteran",
		--[[
			Rolls picked to read like a good drop in the high twenties rather
			than a better one than exists. Both affixes are Outfit or Any, and
			both are defensive: the reward for being told what a citation
			covers up should keep somebody alive, not raise their damage.
		]]
		rolls = { DamageReduction = 0.05, HealthRegen = 0.9 },
	},
	note = "Jabiim. The ribbon says he held a line; he refused an order and was right by accident.",
})

def({
	id = "KadarTheSilentPartner",
	speaker = "VessKadar",
	topic = "theSilentPartner",
	opens = "silentPartner",
	record = "KadarsSilentPartner",
	--[[
		The only stat gate in the file, and the one that is genuinely earned
		by playing rather than by finishing: `PriceMult` under 0.92 means
		Bargaining ranks or a Haggling roll. Kadar notices the person who has
		been talking him down, which is a better reason for him to open a
		drawer than any amount of heroism.
	]]
	requires = { flag = "DebtSettled", maxStat = { PriceMult = 0.92 } },
	reward = {
		xp = 1400,
		credits = 800,
		item = "DL44",
		rolls = { BlasterDamageMult = 0.11, CritChance = 0.045 },
	},
	note = "A percentage leaves his table every quarter to a Czerka account he has stopped opening.",
})

def({
	id = "NineTheClearedField",
	speaker = "Ordo9",
	topic = "theClearedField",
	opens = "clearedField",
	record = "NineClearedField",
	--[[
		Two ranks of slicing, because this is the one secret nobody talks
		anybody into: Nine is not withholding it, he cannot reach it, and the
		player opens the log themselves. It is also the only reader of
		`SliceTier` outside a terminal, which is what that stat's entry in
		LIVE_STATS has been promising.
	]]
	requires = { flag = "HeardNineRemember", minStat = { SliceTier = 2 } },
	reward = { xp = 1500, credits = 1800 },
	note = "The wipe order came from outside him, forty seconds before his log claimed it was his.",
})

def({
	id = "SolaaTheOnesBefore",
	speaker = "RynSolaa",
	topic = "theOnesBefore",
	opens = "onesBefore",
	record = "SolaaNamedTheThree",
	--[[
		The one secret with a real alignment gate, and it costs something:
		she names two people who can be reached and one who can be sold, and
		she is right to be careful about which of you she tells. A character
		playing the Empire straight will not hear this, and that is the trade
		the alignment system exists to make.
	]]
	requires = { flag = "NamedTheQuiet", minAlignment = 250 },
	reward = { xp = 1800, credits = 1500 },
	note = "The other three who wrote it down, one of whom is a Sith archivist writing to a Jedi.",
})

def({
	id = "CorrTheClient",
	speaker = "AnethCorr",
	topic = "theClient",
	opens = "theClient",
	record = "CorrsRoutingNumber",
	--[[
		No alignment gate on purpose, and it is the most useful secret in the
		file. Corr does not care what you are. She cares that she has been
		paid promptly for four years by an account that cannot exist, and she
		would like it out of her head, and the only qualification she is
		checking is that you have been inside the building.
	]]
	requires = { flag = "SawLot9", minLevel = 30 },
	reward = { xp = 2000, credits = 3000 },
	note = "The client account's checksum is wrong. No bank has processed a transfer in four years.",
})

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

Secrets.defs = defs

function Secrets.exists(id: string): boolean
	return defs[id] ~= nil
end

function Secrets.get(id: string): SecretDef
	local s = defs[id]
	assert(s, `Secrets.get: unknown secret "{id}"`)
	return s
end

function Secrets.ids(): { string }
	local out: { string } = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

--[[
	The secret this speaker keeps under this word, if any.

	The whole lookup the server does. Both halves matter: a topic is only ever
	interpreted in the mouth of the character it was declared on, so the word
	"theClient" learned from one conversation cannot be aimed at another.
]]
function Secrets.find(speaker: string, topic: string): SecretDef?
	for _, id in Secrets.ids() do
		local s = defs[id]
		if s.speaker == speaker and s.topic == topic then
			return s
		end
	end
	return nil
end

--- What the reward should be called on screen, decorated by its rolls.
function Secrets.rewardName(reward: Reward): string?
	local id = reward.item
	if not id then
		return nil
	end
	local base = if Weapons.exists(id)
		then Weapons.get(id).displayName
		elseif Outfits.exists(id) then Outfits.get(id).displayName
		else Items.nameOf(id)
	return Affixes.nameFor(base, reward.rolls)
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

--- Whether anything in the bag could ever be this id.
local function carriable(id: string): boolean
	return Weapons.exists(id) or Outfits.exists(id) or Items.exists(id)
end

--[[
	Faults in this file, at boot, called from DialogueService beside the others.

	The four predicates are the ones `Dialogue.validate` takes and for the same
	reasons -- Progression and Missions are heavy modules that would close a
	cycle, and a predicate is the whole of what is wanted from either.

	The two checks worth naming are the last pair. This project's recurring
	failure is not broken code; it is finished work nobody can reach, and a
	secret is unusually good at hiding that: it is *supposed* to be hard to
	get to, so an unreachable one looks exactly like a well-hidden one. So the
	tree is required to offer the topic, and every topic offered is required to
	have a secret behind it.
]]
function Secrets.validate(
	missionExists: (string) -> boolean,
	originExists: (string) -> boolean,
	flagExists: (string) -> boolean,
	statIsLive: (string) -> boolean
): { string }
	local problems: { string } = {}

	-- Every (speaker, topic) pair claimed so far, so a duplicate is caught
	-- rather than silently shadowed by whichever `find` reached first.
	local claimed: { [string]: string } = {}

	for _, id in Secrets.ids() do
		local s = defs[id]

		if s.id ~= id then
			table.insert(problems, `{id}: id field says "{s.id}"`)
		end

		local key = `{s.speaker}|{s.topic}`
		local other = claimed[key]
		if other then
			table.insert(problems, `{id}: "{other}" already claims topic "{s.topic}" for {s.speaker}`)
		end
		claimed[key] = id

		if not flagExists(s.record) then
			table.insert(problems, `{id}: records undeclared flag "{s.record}"`)
		end

		for _, problem in
			Dialogue.conditionProblems(s.requires, id, missionExists, originExists, flagExists, statIsLive)
		do
			table.insert(problems, problem)
		end

		--[[
			The reward, and the one rule that is not obvious: rolls only fold
			into a player's stats from the equipped weapon and outfit slots,
			so a rolled quest item is a set of numbers nothing will ever read
			-- the same dead-stat failure the skill tree was built to stop.
		]]
		local reward = s.reward
		local item = reward.item
		if item and not carriable(item) then
			table.insert(problems, `{id}: rewards unknown item "{item}"`)
		end
		local rolls = reward.rolls
		if rolls then
			if not item then
				table.insert(problems, `{id}: has rolls with no item to put them on`)
			elseif not (Weapons.exists(item) or Outfits.exists(item)) then
				table.insert(
					problems,
					`{id}: rolls "{item}", which is not equippable, so nothing would read them`
				)
			end
			--[[
				A weapon's slot is its own class, so this catches a saber handed
				out with blaster damage on it -- the same mistake a random drop
				used to be able to make. Asked as "is it in the pool?" rather
				than by comparing slot names, so the two cannot disagree.
			]]
			local slot = if item and Weapons.exists(item) then Weapons.get(item).class else "Outfit"
			local legal: { [string]: boolean } = {}
			for _, a in Affixes.forSlot(slot) do
				legal[a.stat] = true
			end
			for stat in rolls do
				if not Affixes.exists(stat) then
					table.insert(problems, `{id}: rolls "{stat}", which is not an affix`)
				elseif not legal[stat] then
					table.insert(problems, `{id}: rolls "{stat}" ({Affixes.get(stat).slot}) onto a {slot}`)
				end
			end
		end
		if (reward.xp or 0) <= 0 and (reward.credits or 0) <= 0 and not item then
			table.insert(problems, `{id}: pays nothing`)
		end

		-- The speaker, their tree, and the two nodes the click can land on.
		if not Cast.exists(s.speaker) then
			table.insert(problems, `{id}: unknown speaker "{s.speaker}"`)
			continue
		end
		local treeId = Cast.get(s.speaker).dialogue
		if not Dialogue.exists(treeId) then
			-- Cast.validate says so too; skip rather than repeat it.
			continue
		end
		local tree = Dialogue.get(treeId)
		if not tree.nodes[s.opens] then
			table.insert(problems, `{id}: opens "{s.opens}", which is not a node in {treeId}`)
		end

		local asked = false
		for _, node in tree.nodes do
			local choices: { Dialogue.Choice } = node.choices or {}
			for _, choice in choices do
				if choice.topic == s.topic then
					asked = true
				end
			end
		end
		if not asked then
			table.insert(
				problems,
				`{id}: nothing in {treeId} asks about "{s.topic}", so it can never be reached`
			)
		end
	end

	--[[
		And the other direction. A topic raised by a line that no secret
		answers is a question the player can ask forever and be deflected from
		every time -- indistinguishable, from the outside, from a puzzle they
		have not solved yet.

		Matched against the *speaker's* tree rather than against the topic
		alone, because that is how the server resolves it: the same word in
		two mouths is two different questions, and only one of them has an
		answer behind it.
	]]
	local answered: { [string]: boolean } = {}
	for _, s in defs do
		if Cast.exists(s.speaker) then
			answered[`{Cast.get(s.speaker).dialogue}|{s.topic}`] = true
		end
	end
	for treeId, tree in Dialogue.defs do
		for nodeId, node in tree.nodes do
			local choices: { Dialogue.Choice } = node.choices or {}
			for i, choice in choices do
				local topic = choice.topic
				if topic and not answered[`{treeId}|{topic}`] then
					table.insert(
						problems,
						`{treeId}.{nodeId}: choice {i} raises topic "{topic}", which no secret here answers`
					)
				end
			end
		end
	end

	table.sort(problems)
	return problems
end

return Secrets
