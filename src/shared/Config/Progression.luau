--!strict
--[[
	Progression.luau

	The RPG backbone: XP curve, levels, skill trees and gear tiers.

	Design intent -- every level should feel like it bought something. A level
	grants a skill point, and each skill node changes a concrete number the player
	can feel (damage, speed, ship handling, prices), rather than an abstract stat.
]]

local Types = require(script.Parent.Parent.Types)

type SkillId = Types.SkillId

local Progression = {}

Progression.MAX_LEVEL = 50
Progression.SKILL_POINTS_PER_LEVEL = 1
Progression.MAX_NODE_RANK = 5

--[[
	XP required to advance FROM `level` to level+1.

	Cheap early so the first hour is generous, steepening toward the cap. Level
	2 costs 100, level 10 about 1.9k, level 50 about 17k, and the whole climb
	from 1 to 50 costs a little under 380,000.

	THIS NUMBER IS A BUDGET, NOT A FEEL

	The old curve was `100 * level^1.6 + 50 * level`, and its own docstring
	claimed level 50 cost 90k when it actually cost 53k and the full climb cost
	1,040,647. Nobody noticed because nothing compared it to anything. What the
	galaxy actually pays is roughly 100,000 XP for killing every hostile in it
	once, plus 33,000 for all 25 authored missions -- so the old cap was about
	ten clearances of the entire galaxy past the end of the story, which is the
	arithmetic behind the playtest note that levelling did not feel logical.

	This one costs about seventeen. `Planets.validate` now checks the two
	against each other at boot, per level band, so the curve cannot quietly
	outrun the content again -- see the XP budget check over there.
]]
function Progression.xpForNextLevel(level: number): number
	if level >= Progression.MAX_LEVEL then
		return math.huge
	end
	return math.floor(30 * (level ^ 1.6) + 70 * level)
end

--- Total cumulative XP needed to reach `level` from scratch.
function Progression.totalXpForLevel(level: number): number
	local total = 0
	for i = 1, level - 1 do
		total += Progression.xpForNextLevel(i)
	end
	return total
end

--------------------------------------------------------------------------------
-- Skill trees
--------------------------------------------------------------------------------

export type SkillNode = {
	id: string,
	tree: SkillId,
	displayName: string,
	description: string,
	maxRank: number,
	requiredLevel: number,
	-- Node ids that must have at least 1 rank before this unlocks.
	requires: { string }?,
	--[[
		Per-rank effect. Read by the systems that care; see `Progression.effect`.

		Absent on a node that is purely a gate -- one whose worth is the
		nodes it unlocks, not a number it moves. `ForceSensitive` is the only
		one, and it is that way because it used to claim `+20 Force energy`
		out of a pool nothing has ever spent.
	]]
	effect: { stat: string, perRank: number }?,
	--[[
		Set when nothing in the game reads `effect.stat` yet.

		The 2026-08-15 playtest found seven skills -- the whole Piloting tree
		among them -- that were purchasable and did nothing, because the
		systems they multiply do not exist. Points spent on those were simply
		gone. `canPurchase` refuses these, and the UI shows this string as the
		reason, so the tree can keep advertising what is coming without
		charging for it.

		**A skill does not go in this file without either a reader for its
		stat or this field.**
	]]
	unimplemented: string?,
}

local nodes: { [string]: SkillNode } = {}

local function node(n: SkillNode): SkillNode
	nodes[n.id] = n
	return n
end

-- Combat ----------------------------------------------------------------------
node({
	id = "Marksmanship",
	tree = "Combat",
	displayName = "Marksmanship",
	description = "+6% blaster damage per rank.",
	maxRank = 5,
	requiredLevel = 1,
	effect = { stat = "BlasterDamageMult", perRank = 0.06 },
})
node({
	id = "RapidCycling",
	tree = "Combat",
	displayName = "Rapid Cycling",
	description = "-7% blaster cooldown per rank.",
	maxRank = 5,
	requiredLevel = 3,
	requires = { "Marksmanship" },
	effect = { stat = "BlasterCooldownMult", perRank = -0.07 },
})
node({
	id = "Toughness",
	tree = "Combat",
	displayName = "Toughness",
	description = "+15 maximum health per rank.",
	maxRank = 5,
	requiredLevel = 1,
	effect = { stat = "BonusHealth", perRank = 15 },
})
node({
	id = "CombatMedic",
	tree = "Combat",
	displayName = "Combat Medic",
	description = "+0.4 health regenerated per second, per rank.",
	maxRank = 5,
	requiredLevel = 8,
	requires = { "Toughness" },
	effect = { stat = "HealthRegen", perRank = 0.4 },
})
node({
	id = "Deadeye",
	tree = "Combat",
	displayName = "Deadeye",
	description = "+4% critical hit chance per rank.",
	maxRank = 5,
	requiredLevel = 12,
	requires = { "RapidCycling" },
	effect = { stat = "CritChance", perRank = 0.04 },
})

--[[
	Piloting ------------------------------------------------------------------

	The whole tree is `unimplemented` until ships exist (ROADMAP 2b/2c). Travel
	is currently priced as a fare rather than fuel, so even Navigator has
	nothing to reduce.
]]
local NO_SHIPS = "Needs starships — not in the game yet"

node({
	id = "Throttle",
	tree = "Piloting",
	displayName = "Throttle Control",
	description = "+8% ship top speed per rank.",
	maxRank = 5,
	requiredLevel = 1,
	effect = { stat = "ShipSpeedMult", perRank = 0.08 },
	unimplemented = NO_SHIPS,
})
node({
	id = "Maneuvering",
	tree = "Piloting",
	displayName = "Manoeuvring",
	description = "+10% ship turn rate per rank.",
	maxRank = 5,
	requiredLevel = 4,
	requires = { "Throttle" },
	effect = { stat = "ShipTurnMult", perRank = 0.1 },
	unimplemented = NO_SHIPS,
})
node({
	id = "ShieldHarmonics",
	tree = "Piloting",
	displayName = "Shield Harmonics",
	description = "+25 ship shield capacity per rank.",
	maxRank = 5,
	requiredLevel = 6,
	effect = { stat = "ShipShield", perRank = 25 },
	unimplemented = NO_SHIPS,
})
node({
	id = "Navigator",
	tree = "Piloting",
	displayName = "Navigator",
	description = "-10% hyperspace fuel cost per rank.",
	maxRank = 5,
	requiredLevel = 10,
	requires = { "Maneuvering" },
	effect = { stat = "FuelCostMult", perRank = -0.1 },
	unimplemented = NO_SHIPS,
})

-- Force -----------------------------------------------------------------------
--[[
	A gate, and only a gate.

	This used to read "+20 Force energy per rank" over five ranks, against a
	`MaxForce` pool that no ability has ever drawn on -- so four of its five
	ranks were points spent on nothing, and the fifth was the tree opening.
	ROADMAP B5 caught seven skills like this and missed two; this is one.

	Rather than mark it `unimplemented`, which would lock the Force tree
	behind a node nobody can buy, it now charges one point for what it
	actually sells. The four ranks that bought nothing are freed for skills
	that do. `MaxForce` stays in `baseStats` for when a power spends it.
]]
node({
	id = "ForceSensitive",
	tree = "Force",
	displayName = "Force Sensitive",
	description = "Opens the Force tree. Required for all Force powers.",
	maxRank = 1,
	requiredLevel = 5,
})
node({
	id = "SaberForm",
	tree = "Force",
	displayName = "Lightsaber Form",
	description = "+8% lightsaber damage per rank.",
	maxRank = 5,
	requiredLevel = 7,
	requires = { "ForceSensitive" },
	effect = { stat = "SaberDamageMult", perRank = 0.08 },
})
node({
	id = "SaberDeflect",
	tree = "Force",
	displayName = "Deflection",
	description = "+9% chance to deflect incoming blaster bolts per rank.",
	maxRank = 5,
	requiredLevel = 11,
	requires = { "SaberForm" },
	effect = { stat = "DeflectChance", perRank = 0.09 },
})
node({
	id = "ForcePush",
	tree = "Force",
	displayName = "Force Push",
	description = "Unlocks Force Push. +15% knockback per rank.",
	maxRank = 5,
	requiredLevel = 9,
	requires = { "ForceSensitive" },
	effect = { stat = "PushPower", perRank = 0.15 },
	-- The power itself has never existed. Unlocking it needs the ability
	-- system in ROADMAP 4.3, which is where the rest of the verbs go too.
	unimplemented = "Needs the ability system — not in the game yet",
})
node({
	id = "ForceSpeed",
	tree = "Force",
	displayName = "Force Speed",
	description = "+6% movement speed per rank.",
	maxRank = 5,
	requiredLevel = 14,
	requires = { "ForceSensitive" },
	effect = { stat = "MoveSpeedMult", perRank = 0.06 },
})

-- Engineering -----------------------------------------------------------------
node({
	id = "Scavenger",
	tree = "Engineering",
	displayName = "Scavenger",
	description = "+10% credits from all sources per rank.",
	maxRank = 5,
	requiredLevel = 1,
	effect = { stat = "CreditMult", perRank = 0.1 },
})
node({
	id = "Haggler",
	tree = "Engineering",
	displayName = "Haggler",
	description = "-6% vendor prices per rank.",
	maxRank = 5,
	requiredLevel = 3,
	requires = { "Scavenger" },
	effect = { stat = "PriceMult", perRank = -0.06 },
})
node({
	id = "Slicer",
	tree = "Engineering",
	displayName = "Slicer",
	description = "Unlocks slicing terminals and locked doors. +1 tier per rank.",
	maxRank = 5,
	requiredLevel = 6,
	effect = { stat = "SliceTier", perRank = 1 },
	-- Nothing in the world is sliceable yet; terminals and locked doors come
	-- with the interiors in ROADMAP 3.1.
	unimplemented = "Needs sliceable terminals — not in the game yet",
})
node({
	id = "FieldRepair",
	tree = "Engineering",
	displayName = "Field Repair",
	description = "+12% ship hull repair rate per rank.",
	maxRank = 5,
	requiredLevel = 9,
	requires = { "Slicer" },
	effect = { stat = "RepairMult", perRank = 0.12 },
	unimplemented = NO_SHIPS,
})

Progression.nodes = nodes

--- Base values for every stat a skill node can modify.
Progression.baseStats = {
	BlasterDamageMult = 1,
	BlasterCooldownMult = 1,
	BonusHealth = 0,
	HealthRegen = 0.5,
	CritChance = 0.05,
	ShipSpeedMult = 1,
	ShipTurnMult = 1,
	ShipShield = 100,
	FuelCostMult = 1,
	MaxForce = 0,
	SaberDamageMult = 1,
	DeflectChance = 0,
	PushPower = 1,
	MoveSpeedMult = 1,
	CreditMult = 1,
	PriceMult = 1,
	-- Fraction of incoming damage ignored. Comes from armour rather than
	-- skills today, but lives here so there is one definition of what the
	-- stat means and one place that clamps it.
	DamageReduction = 0,
	SliceTier = 0,
	RepairMult = 1,
}

--[[
	The stats something actually reads, and what reads them.

	This is the whole of "does this skill do anything", written down. Skills
	and affixes are both checked against it -- see `validate` below and
	`Affixes.validate` -- so a stat with no entry here cannot quietly ship
	attached to something a player pays for.

	If a reader is deleted, delete the entry: whatever was riding on it will
	then fail validation loudly, which is the point. Everything absent from
	this list is in `baseStats` waiting for the system that will spend it.
	Verified 2026-08-16.
]]
-- Annotated, not inferred: an inferred literal is a sealed table of exactly
-- these keys, and looking an unknown stat up in one is a type error rather
-- than the nil the checks below are asking for.
local LIVE_STATS: { [string]: string } = {
	BlasterDamageMult = "CombatService.resolveShot",
	BlasterCooldownMult = "CombatService (fire-rate cooldown)",
	BonusHealth = "ProgressionService.maxHealthFor",
	HealthRegen = "PlayerService (regen loop)",
	CritChance = "CombatService.resolveShot / onSaberSwing",
	SaberDamageMult = "CombatService.onSaberSwing",
	DeflectChance = "CombatService.applyDamage",
	MoveSpeedMult = "PlayerService (humanoid.WalkSpeed)",
	CreditMult = "ProgressionService.awardCredits",
	PriceMult = "ProgressionService.priceFor / TravelService",
	DamageReduction = "CombatService.applyDamage",
}

Progression.LIVE_STATS = LIVE_STATS

--[[
	Folds a player's purchased skill ranks into a flat stat table.

	Multiplier stats (name ends in "Mult") accumulate additively around 1.0, so
	three ranks of +6% is +18%, not 1.06^3. Additive stacking is easier for
	players to reason about and keeps the numbers from running away at high rank.

	`extra` folds in modifiers from outside the skill tree -- currently the
	equipped outfit. It stacks the same additive way and is clamped by the same
	rules below, so gear can never sidestep a cap that skills respect.
]]
function Progression.computeStats(
	skills: { [string]: number },
	extra: { [string]: number }?
): { [string]: number }
	local stats = table.clone(Progression.baseStats)
	for nodeId, rank in skills do
		local def = nodes[nodeId]
		local effect = def and def.effect
		if def and effect and rank > 0 then
			local clamped = math.min(rank, def.maxRank)
			stats[effect.stat] = (stats[effect.stat] or 0) + effect.perRank * clamped
		end
	end
	if extra then
		for stat, delta in extra do
			stats[stat] = (stats[stat] or 0) + delta
		end
	end
	-- Never let a cooldown or price multiplier reach zero or go negative.
	stats.BlasterCooldownMult = math.max(0.25, stats.BlasterCooldownMult)
	stats.FuelCostMult = math.max(0.2, stats.FuelCostMult)
	stats.PriceMult = math.max(0.4, stats.PriceMult)
	-- Armour must never make a player untouchable, however it is stacked.
	stats.DamageReduction = math.clamp(stats.DamageReduction, 0, 0.75)
	stats.MoveSpeedMult = math.max(0.5, stats.MoveSpeedMult)
	return stats
end

--- Health a player should have at a given level, before skill bonuses.
function Progression.baseHealthForLevel(level: number): number
	return 100 + (level - 1) * 4
end

--[[
	Validates a skill purchase. Returns ok, plus a reason string when refused so
	the UI can explain the refusal instead of silently doing nothing.
]]
function Progression.canPurchase(
	nodeId: string,
	currentSkills: { [string]: number },
	level: number,
	skillPoints: number
): (boolean, string?)
	local def = nodes[nodeId]
	if not def then
		return false, "Unknown skill"
	end
	-- Checked before skill points so the reason is the honest one: you are not
	-- short of points, there is nothing here to buy yet.
	if def.unimplemented then
		return false, def.unimplemented
	end
	if skillPoints < 1 then
		return false, "No skill points available"
	end

	local current = currentSkills[nodeId] or 0
	if current >= def.maxRank then
		return false, "Already at maximum rank"
	end
	if level < def.requiredLevel then
		return false, `Requires level {def.requiredLevel}`
	end
	if def.requires then
		for _, prereq in def.requires do
			if (currentSkills[prereq] or 0) < 1 then
				local prereqDef = nodes[prereq]
				return false, `Requires {prereqDef and prereqDef.displayName or prereq}`
			end
		end
	end
	return true, nil
end

--- All nodes belonging to one tree, sorted by required level then name.
function Progression.nodesInTree(tree: SkillId): { SkillNode }
	local out = {}
	for _, def in nodes do
		if def.tree == tree then
			table.insert(out, def)
		end
	end
	table.sort(out, function(a, b)
		if a.requiredLevel ~= b.requiredLevel then
			return a.requiredLevel < b.requiredLevel
		end
		return a.displayName < b.displayName
	end)
	return out
end

Progression.TREES = { "Combat", "Piloting", "Force", "Engineering" } :: { SkillId }

function Progression.hasTree(tree: string): boolean
	for _, id in Progression.TREES do
		if id == tree then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

--[[
	Reports every skill that would take a point and do nothing.

	THE RULE THIS ENFORCES
	A skill does not enter this file without either a reader for its stat or
	an `unimplemented` string. That rule was written after the 2026-08-15
	playtest found seven purchasable skills that did nothing -- the entire
	Piloting tree among them -- and it was applied by hand, which is why it
	then missed two more. A rule nobody checks decays into a comment.

	The state a node must be in is exactly one of three:
	  * an effect whose stat is in `LIVE_STATS` -- it works;
	  * an effect whose stat is not, plus `unimplemented` -- the tree can
	    advertise what is coming without charging for it;
	  * no effect at all -- a gate, worth what it unlocks.
	Anything else is a player paying for nothing, so it is reported.
]]
function Progression.validate(): { string }
	local problems: { string } = {}

	for stat, reader in LIVE_STATS do
		if Progression.baseStats[stat] == nil then
			table.insert(problems, `LIVE_STATS names "{stat}" ({reader}), which is not a stat`)
		end
	end

	for id, def in nodes do
		if not Progression.hasTree(def.tree) then
			table.insert(problems, `{id}: unknown tree "{def.tree}"`)
		end
		if def.maxRank < 1 then
			table.insert(problems, `{id}: maxRank is {def.maxRank}, so it can never be bought`)
		end

		-- A prerequisite that does not exist can never reach rank 1, which
		-- makes everything behind it unreachable and nothing says so.
		local requires = def.requires
		if requires then
			for _, req in requires do
				if not nodes[req] then
					table.insert(problems, `{id}: requires "{req}", which is not a skill`)
				end
			end
		end

		local effect = def.effect
		if not effect then
			if def.unimplemented then
				table.insert(problems, `{id}: has no effect, so "unimplemented" says nothing`)
			end
			continue
		end
		if Progression.baseStats[effect.stat] == nil then
			table.insert(problems, `{id}: "{effect.stat}" has no entry in baseStats`)
		end
		if LIVE_STATS[effect.stat] then
			if def.unimplemented then
				table.insert(
					problems,
					`{id}: "{effect.stat}" is read by {LIVE_STATS[effect.stat]}, so it is not unimplemented`
				)
			end
		elseif not def.unimplemented then
			table.insert(
				problems,
				`{id}: nothing reads "{effect.stat}" -- give it a reader, or an "unimplemented" reason`
			)
		end
	end

	return problems
end

return Progression
