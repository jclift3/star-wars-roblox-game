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
	The point you already have before you have done anything.

	A character is created holding one, so the tree has something in it to
	answer on the first visit rather than being a locked diagram. It lives
	here rather than as a literal in `DataService.defaultProfile` for two
	reasons: the budget check at the bottom of this file was counting only
	the 49 points that levelling grants and so understated a level-50
	character by one, and the client cannot see the server's default profile
	-- `CreationController` needs this number to tell a new player that the
	point exists at all.
]]
Progression.STARTING_SKILL_POINTS = 1

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
		Alignment bounds, inclusive, from `Config/Alignment.luau`.

		This is the fork the Force tree is *for*: lightning is bought by
		somebody who has been cruel and healing by somebody who has not, and
		neither can buy the other. It is a purchase gate rather than a
		use-time gate on purpose -- an ability that refuses when pressed is a
		skill point already spent on nothing, which is precisely the failure
		`validate` below exists to catch.

		Nothing lowers alignment back the way it came quickly, so this is a
		commitment rather than a costume. It does not un-buy a node if the
		character later drifts across the line: taking away something a
		player paid for is worse than the inconsistency.
	]]
	minAlignment: number?,
	maxAlignment: number?,
	--[[
		Nodes this one locks out, and which lock it out in turn.

		The other half of "a tree should contain decisions". `requires` builds
		ladders, and a ladder has no decisions in it -- there is never a reason
		to stop climbing, so every character eventually holds every rung and
		two players at level 40 differ only in what order they bought things.
		An exclusion is the first thing in the tree a player can get *wrong*,
		which is what makes the rest of it a choice.

		**Symmetry is enforced by `validate`.** A one-way exclusion is a trap:
		buy A then B and you have both, buy B then A and you are refused, and
		which one you own comes down to the order you happened to click. Both
		nodes must name each other.

		Like the alignment bounds, this is checked at purchase and never
		un-buys anything. There is no respec, so `SkillTreeController` says
		what a point will close off *before* it is spent.
	]]
	excludes: { string }?,
	--[[
		Ranks that must already be spent in this node's own tree, for a
		capstone -- the node you can only reach by having committed.

		Counted in ranks rather than distinct nodes so it cannot be satisfied
		by dabbling: five different trees' worth of rank 1s is not a
		commitment, and the number is meant to be most of a tree.

		This, not `requiredLevel`, is what stops a character from holding every
		capstone in the game. Levels arrive on their own; points do not.
	]]
	requiresPointsInTree: number?,
	--[[
		Per-rank effect. Read by the systems that care; see `Progression.effect`.

		Absent on a node that is purely a gate -- one whose worth is the
		nodes it unlocks, not a number it moves. `ForceSensitive` is the only
		one, and it is that way because it used to claim `+20 Force energy`
		out of a pool nothing has ever spent.
	]]
	effect: { stat: string, perRank: number }?,
	--[[
		The ability this node unlocks at rank 1, from `Config/Abilities.luau`.

		Written here as well as over there because the two questions are
		different: `Abilities` asks "what unlocks me", which it needs to check
		a request, and the skill panel asks "what does this point buy", which
		it cannot answer by scanning every ability. `Abilities.validate`
		checks the pair agree.
	]]
	ability: string?,
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
--[[
	The Combat tree's verb, and the one every origin can reach.

	Force Push and the two branches behind it are gated on a tree three of the
	four origins have no reason to open. Without this, "abilities" would mean
	"the Force", and a Conscript's whole progression would still be
	percentages.
]]
node({
	id = "Grenadier",
	tree = "Combat",
	displayName = "Grenadier",
	description = "Unlocks the Frag Grenade. +10% explosive damage per rank.",
	maxRank = 5,
	requiredLevel = 6,
	requires = { "Marksmanship" },
	effect = { stat = "ExplosiveDamageMult", perRank = 0.1 },
	ability = "FragGrenade",
})
--[[
	The Combat tree's answer to "why bring a second person", and ROADMAP 4.3's
	fourth target.

	Every other node in this file makes *you* better, so two players were
	worth exactly two players. A mark is worth the party's damage rather than
	the caster's, which means the same point buys more the more people are
	shooting -- and the boys play in the same room.

	It sits in Combat rather than the Force tree on purpose: three of the four
	origins never open Force, and a co-op mechanic only one origin can bring
	is a co-op mechanic that mostly does not happen. The Force half of the
	pair (`ForceBarrier`) is the side that protects.
]]
node({
	id = "Spotter",
	tree = "Combat",
	displayName = "Spotter",
	description = "Unlocks Mark Target: everyone does more damage to what you paint. +6% per rank.",
	maxRank = 5,
	requiredLevel = 10,
	requires = { "Marksmanship" },
	effect = { stat = "MarkPower", perRank = 0.06 },
	ability = "MarkTarget",
})
--[[
	The Combat tree's fork: one target or several.

	Deadeye is the answer to a boss and Overcharge is the answer to a corridor,
	and neither is better -- which is the test a real choice has to pass. Note
	the rank counts differ on purpose: three ranks of Overcharge is four bodies
	per bolt, and a fourth rank would only matter in a room that does not exist.
]]
node({
	id = "Deadeye",
	tree = "Combat",
	displayName = "Deadeye",
	description = "+4% critical hit chance per rank. Closes off Overcharge.",
	maxRank = 5,
	requiredLevel = 12,
	requires = { "RapidCycling" },
	excludes = { "Overcharge" },
	effect = { stat = "CritChance", perRank = 0.04 },
})
node({
	id = "Overcharge",
	tree = "Combat",
	displayName = "Overcharge",
	description = "Your bolts punch through one more body per rank. Closes off Deadeye.",
	maxRank = 3,
	requiredLevel = 12,
	requires = { "RapidCycling" },
	excludes = { "Deadeye" },
	effect = { stat = "BonusPierce", perRank = 1 },
})
--[[
	Combat's capstone, and the reason to have taken Deadeye.

	One rank, because a capstone that can be bought a little is not a capstone.
	It is deliberately the *only* thing in the game that touches the crit
	multiplier, so a crit build stops being "+4% five times" and becomes a
	different way of killing things.
]]
node({
	id = "Executioner",
	tree = "Combat",
	displayName = "Executioner",
	description = "Critical hits do far more: the multiplier rises from 2x to 3.5x.",
	maxRank = 1,
	requiredLevel = 24,
	requires = { "Deadeye" },
	requiresPointsInTree = 18,
	effect = { stat = "CritDamageBonus", perRank = 1.5 },
})

--[[
	Piloting ------------------------------------------------------------------

	Every node in this tree was `unimplemented` until ROADMAP 2c, which made it
	the worst thing in the game: the Scoundrel is built on this tree and is the
	*default* origin, so a character could be created, played to level 50, and
	every skill on their own sheet would still have been an advertisement.

	Three of the four now read. Speed and turn rate apply to speeders as well
	as starships -- deliberately, so a rank bought at level 1 does something at
	level 1 on the Hover-Sled you can already afford, instead of waiting
	fifteen levels for a hull. Fuel is the starship-only one, and it is the
	only skill in the game that changes the *price* on the star map.

	Shields stay unimplemented, alone and honestly: nothing shoots at a ship
	yet, so a shield has nothing to absorb.
]]

node({
	id = "Throttle",
	tree = "Piloting",
	displayName = "Throttle Control",
	description = "+8% top speed on anything you fly, from a sled to a starship.",
	maxRank = 5,
	requiredLevel = 1,
	effect = { stat = "ShipSpeedMult", perRank = 0.08 },
})
node({
	id = "Maneuvering",
	tree = "Piloting",
	displayName = "Manoeuvring",
	description = "+10% turn rate on anything you fly.",
	maxRank = 5,
	requiredLevel = 4,
	requires = { "Throttle" },
	effect = { stat = "ShipTurnMult", perRank = 0.1 },
})
node({
	id = "ShieldHarmonics",
	tree = "Piloting",
	displayName = "Shield Harmonics",
	description = "+25 ship shield capacity per rank.",
	maxRank = 5,
	requiredLevel = 6,
	effect = { stat = "ShipShield", perRank = 25 },
	unimplemented = "Nothing shoots at a ship yet",
})
node({
	id = "Navigator",
	tree = "Piloting",
	displayName = "Navigator",
	description = "-10% fuel burned flying your own hull between worlds, per rank.",
	maxRank = 5,
	requiredLevel = 10,
	requires = { "Maneuvering" },
	effect = { stat = "FuelCostMult", perRank = -0.1 },
})

-- Force -----------------------------------------------------------------------
--[[
	The tree gate, and now also the pool every power in it spends.

	This used to read "+20 Force energy per rank" over five ranks, against a
	`MaxForce` pool that no ability had ever drawn on -- so four of its five
	ranks were points spent on nothing, and the fifth was the tree opening.
	ROADMAP B5 caught seven skills like this and missed two; this was one. It
	became a one-rank gate with no effect at all, which was the honest state
	while nothing spent Force.

	Something spends it now (`AbilityService`), so it grants the pool again --
	but still at one rank. A second rank would be "more of a resource you
	rarely run out of", and the point it costs is worth more as Lightning.
]]
node({
	id = "ForceSensitive",
	tree = "Force",
	displayName = "Force Sensitive",
	description = "Opens the Force tree, and gives you 100 Force to spend.",
	maxRank = 1,
	requiredLevel = 5,
	effect = { stat = "MaxForce", perRank = 100 },
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
--[[
	The Force tree's fork, and the trade the roadmap asked for by name:
	defence or damage, out of the same lightsaber.

	Deflection answers the ranged enemies that make up most of the world;
	Focus answers the ones that survive being shot. They are the same level
	and the same prerequisite so the choice is never made for you by which
	one you could afford first.
]]
node({
	id = "SaberDeflect",
	tree = "Force",
	displayName = "Deflection",
	description = "+9% chance to deflect incoming blaster bolts per rank. Closes off Juyo Focus.",
	maxRank = 5,
	requiredLevel = 11,
	requires = { "SaberForm" },
	excludes = { "SaberFocus" },
	effect = { stat = "DeflectChance", perRank = 0.09 },
})
node({
	id = "SaberFocus",
	tree = "Force",
	displayName = "Juyo Focus",
	description = "+12% lightsaber damage per rank, on top of your form. Closes off Deflection.",
	maxRank = 5,
	requiredLevel = 11,
	requires = { "SaberForm" },
	excludes = { "SaberDeflect" },
	effect = { stat = "SaberDamageMult", perRank = 0.12 },
})
--[[
	The first node in the game that buys a verb rather than a percentage.

	It claimed to unlock a power from the day it was written and was marked
	`unimplemented` for it, because there was nowhere for a power to live.
	`Config/Abilities.luau` and `AbilityService` are that place.
]]
node({
	id = "ForcePush",
	tree = "Force",
	displayName = "Force Push",
	description = "Unlocks Force Push. +15% force and damage per rank.",
	maxRank = 5,
	requiredLevel = 9,
	requires = { "ForceSensitive" },
	effect = { stat = "PushPower", perRank = 0.15 },
	ability = "ForcePush",
})

--[[
	The fork. Two nodes, same level, same prerequisite, and no character can
	hold both -- the bounds are the Unaligned band's own edges, so they do not
	overlap and do not leave a gap.

	This is what ROADMAP 3b.2's alignment axis was built to pay for: until now
	it moved and nothing in the tree read it. Deliberately at level 16, a few
	levels after the first real fork in the campaign (level 12), so the
	character has already been asked once in prose before being asked in
	points.

	They also exclude each other explicitly, which is not redundant with the
	alignment bounds: alignment moves, and the bounds are only read at the
	moment of purchase. Without this a player could buy Lightning at -200,
	spend a few missions being decent, and buy Mend at +200 -- ending with
	both halves of a fork that exists to be a choice.
]]
node({
	id = "ForceLightning",
	tree = "Force",
	displayName = "Force Lightning",
	description = "Unlocks Force Lightning. +10% Force damage per rank. Cruel characters only.",
	maxRank = 5,
	requiredLevel = 16,
	requires = { "ForceSensitive" },
	maxAlignment = -100,
	excludes = { "ForceMend" },
	effect = { stat = "ForceDamageMult", perRank = 0.1 },
	ability = "ForceLightning",
})
node({
	id = "ForceMend",
	tree = "Force",
	displayName = "Force Mend",
	description = "Unlocks Force Mend. +12% healing per rank. Decent characters only.",
	maxRank = 5,
	requiredLevel = 16,
	requires = { "ForceSensitive" },
	minAlignment = 100,
	excludes = { "ForceLightning" },
	effect = { stat = "HealPower", perRank = 0.12 },
	ability = "ForceMend",
})
--[[
	The Force half of the co-op pair, and the only power in this tree with no
	side.

	Lightning and Mend are the fork; this is deliberately outside it, because
	the alternative is that two brothers can only cover each other if they
	made the same choice about a question the campaign spends thirty levels
	insisting is theirs alone. Sheltering the person beside you is not a moral
	position -- a Sith keeps his apprentice breathing for his own reasons.

	Below the fork's level so it is reachable before the character has been
	asked to pick, and above Push so the tree's first ability is still the
	one that gets you out of a corner.
]]
node({
	id = "ForceBarrier",
	tree = "Force",
	displayName = "Force Barrier",
	description = "Unlocks Force Barrier: soaks damage for you and everyone near you. +12% per rank.",
	maxRank = 5,
	requiredLevel = 13,
	requires = { "ForceSensitive" },
	effect = { stat = "ShieldPower", perRank = 0.12 },
	ability = "ForceBarrier",
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
--[[
	Force's capstone. It does not make any one power stronger -- it makes the
	pool go further, which is the thing a Force character actually runs out
	of. A percentage on top of Lightning would have been another rank of
	Lightning; this changes how often you get to press anything at all.
]]
node({
	id = "ForceAttunement",
	tree = "Force",
	displayName = "Attunement",
	description = "Force powers cost 40% less.",
	maxRank = 1,
	requiredLevel = 24,
	requires = { "ForceSensitive" },
	requiresPointsInTree = 18,
	effect = { stat = "ForceCostMult", perRank = -0.4 },
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
	description = "Opens tier 1 security locks, +1 tier per rank. Every rank opens places the others cannot go.",
	maxRank = 5,
	requiredLevel = 6,
	effect = { stat = "SliceTier", perRank = 1 },
})
--[[
	A heal with no Force behind it, and the only one three of the four origins
	will ever have.

	It shares `HealPower` with `ForceMend` on purpose: they are the same verb
	bought two ways, and a character who somehow has both should not have two
	independent healing budgets.
]]
node({
	id = "FieldStim",
	tree = "Engineering",
	displayName = "Field Stim",
	description = "Unlocks the Field Stim, which heals you and anyone beside you. +10% healing per rank.",
	maxRank = 5,
	requiredLevel = 8,
	requires = { "Scavenger" },
	effect = { stat = "HealPower", perRank = 0.1 },
	ability = "FieldStim",
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
	-- Ships fly now, but nothing damages one: a hull has no health to
	-- repair. Same honest reason as ShieldHarmonics, and both go live the
	-- day either of them has something to shoot at.
	unimplemented = "Nothing damages a ship yet",
})
--[[
	Engineering's capstone, and the only cross-tree one.

	It shortens the cooldown on *every* ability, Force powers included, so a
	saber character has a reason to spend twelve points somewhere he would
	otherwise never look -- and those twelve points are twelve he cannot put
	into Attunement. That tension is the whole point of the capstones: 18 for
	Executioner, 18 for Attunement, 12 here, and 49 points at the cap, so no
	character can hold all three.

	Engineering's requirement is the lowest of the three because it is the
	only tree with a dead node in it, and charging 18 would mean buying a
	skill that does nothing to reach it. It was two dead nodes until
	`TerminalService` gave Slicer something to open; Field Repair is still
	waiting on ships, so this stays at 12.
]]
node({
	id = "KitDiscipline",
	tree = "Engineering",
	displayName = "Kit Discipline",
	description = "Every ability you have comes back 35% sooner.",
	maxRank = 1,
	requiredLevel = 24,
	requires = { "Scavenger" },
	requiresPointsInTree = 12,
	effect = { stat = "AbilityCooldownMult", perRank = -0.35 },
})

Progression.nodes = nodes

--- Base values for every stat a skill node can modify.
Progression.baseStats = {
	BlasterDamageMult = 1,
	BlasterCooldownMult = 1,
	BonusHealth = 0,
	HealthRegen = 0.5,
	CritChance = 0.05,
	-- Added to the weapon's own crit multiplier, not multiplied into it, so
	-- one capstone cannot be worth more on a rifle than on a pistol.
	CritDamageBonus = 0,
	-- Extra bodies a bolt passes through, on top of the weapon's own pierce.
	BonusPierce = 0,
	ShipSpeedMult = 1,
	ShipTurnMult = 1,
	ShipShield = 100,
	FuelCostMult = 1,
	-- Zero until `ForceSensitive` is bought, which is what makes that node a
	-- real gate: no pool, no Force ability can be paid for.
	MaxForce = 0,
	-- Force per second, flat rather than bought. A regeneration skill would
	-- be a percentage node on a tree this file is trying to get away from,
	-- and the cooldowns are the real limiter anyway.
	ForceRegen = 5,
	-- What a Force ability's `forceCost` is multiplied by.
	ForceCostMult = 1,
	-- What every ability's `cooldown` is multiplied by, Force or not.
	AbilityCooldownMult = 1,
	SaberDamageMult = 1,
	MeleeDamageMult = 1,
	DeflectChance = 0,
	PushPower = 1,
	ForceDamageMult = 1,
	ExplosiveDamageMult = 1,
	HealPower = 1,
	-- The two co-op stats. Both are multipliers on something that happens to
	-- somebody else, which is why neither has a solo equivalent to stack with.
	MarkPower = 1,
	ShieldPower = 1,
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
	CritDamageBonus = "CombatService.resolveShot / swingMelee",
	BonusPierce = "CombatService.resolveShot",
	SaberDamageMult = "CombatService.onSaberSwing",
	-- Same reader as above -- `onSaberSwing` handles both swung classes, and
	-- picks which of the two multipliers applies off `WeaponDef.class`.
	MeleeDamageMult = "CombatService.onSaberSwing",
	DeflectChance = "CombatService.applyDamage",
	MoveSpeedMult = "PlayerService (humanoid.WalkSpeed)",
	CreditMult = "ProgressionService.awardCredits",
	PriceMult = "ProgressionService.priceFor / TravelService",
	-- Read on the client, uniquely. The driver already simulates their own
	-- vehicle (see VehicleService's header), so the flight loop is where the
	-- speed and turn rate live and there is nowhere else for these to be.
	ShipSpeedMult = "VehicleController.onStep (top speed)",
	ShipTurnMult = "VehicleController.onStep (yaw and pitch rate)",
	FuelCostMult = "TravelService.galaxyFor / travelTo (your own hull)",
	DamageReduction = "CombatService.applyDamage",
	MaxForce = "AbilityService (Force pool)",
	ForceRegen = "AbilityService (Force pool)",
	ForceCostMult = "AbilityService.refusalFor (Force cost)",
	AbilityCooldownMult = "AbilityService.onUseAbility (cooldown)",
	PushPower = "AbilityService.use (ForcePush)",
	ForceDamageMult = "AbilityService.use (ForceLightning)",
	ExplosiveDamageMult = "AbilityService.use (FragGrenade)",
	HealPower = "AbilityService.use (ForceMend / FieldStim)",
	MarkPower = "AbilityService.strike (MarkTarget) -> CombatService.mark",
	ShieldPower = "AbilityService.cast (ForceBarrier) -> CombatService.shield",
	-- The only stat in this table that does not change a number in a fight.
	-- It decides whether a console in the world will open at all, and whether
	-- a shopkeeper has a back room he will mention.
	SliceTier = "TerminalService.slice (lock tier) / DialogueService (minStat)",
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
	-- A free ability is one you hold down. Both floors are well under what
	-- the game can currently reach, and exist so a future source stacking on
	-- top of a capstone cannot take the cost to nothing.
	stats.ForceCostMult = math.max(0.3, stats.ForceCostMult)
	stats.AbilityCooldownMult = math.max(0.3, stats.AbilityCooldownMult)
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
	Ranks a player has spent inside one tree.

	Ranks, not nodes: a capstone that counted distinct nodes could be reached by
	buying rank 1 of everything, which is the opposite of the commitment it is
	supposed to be evidence of.
]]
function Progression.pointsInTree(currentSkills: { [string]: number }, tree: SkillId): number
	local total = 0
	for nodeId, rank in currentSkills do
		local def = nodes[nodeId]
		if def and def.tree == tree then
			total += rank
		end
	end
	return total
end

--[[
	The already-bought node, if any, that stops `nodeId` from ever being bought.

	Separate from `canPurchase` because the skill panel asks a different
	question: not "may I buy this now" but "what would buying *that* cost me",
	which it has to answer while the player is still hovering over the other
	node. There is no respec, so this is the one refusal worth showing early.
]]
function Progression.blockedBy(nodeId: string, currentSkills: { [string]: number }): string?
	local def = nodes[nodeId]
	if not def or not def.excludes then
		return nil
	end
	for _, other in def.excludes do
		if (currentSkills[other] or 0) >= 1 then
			return other
		end
	end
	return nil
end

--[[
	Validates a skill purchase. Returns ok, plus a reason string when refused so
	the UI can explain the refusal instead of silently doing nothing.
]]
function Progression.canPurchase(
	nodeId: string,
	currentSkills: { [string]: number },
	level: number,
	skillPoints: number,
	alignment: number
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

	--[[
		Checked against `current` so it only ever refuses the *first* rank.
		A player who already owns rank 1 has made the choice; refusing rank 2
		because of it would be the tree taking back a node it sold.
	]]
	if current < 1 then
		local blocker = Progression.blockedBy(nodeId, currentSkills)
		if blocker then
			local blockerDef = nodes[blocker]
			return false, `Closed off by {blockerDef and blockerDef.displayName or blocker}`
		end
	end

	if def.requiresPointsInTree then
		local spent = Progression.pointsInTree(currentSkills, def.tree)
		if spent < def.requiresPointsInTree then
			return false, `Requires {def.requiresPointsInTree} points in {def.tree} -- you have {spent}`
		end
	end

	-- Deliberately vague about the number. The player is never shown their
	-- alignment as a figure anywhere else and starting here would turn a
	-- record of what they did into a bar to fill.
	if def.minAlignment and alignment < def.minAlignment then
		return false, "You have not been the kind of person this answers to"
	end
	if def.maxAlignment and alignment > def.maxAlignment then
		return false, "You have not been the kind of person this answers to"
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

--[[
	The same nodes, arranged as the tree they actually are.

	Reported from play, 2026-08-17: *"what do you mean by force tree? I'm not
	seeing a tree anywhere."* Which was fair. `requires` has always been real
	-- eight of the Force tree's ten nodes hang off Force Sensitive, and Juyo
	and Ataru hang off Lightsaber Form -- but `nodesInTree` sorts by level and
	then name, so the panel drew a ladder. The structure existed and the
	player was the only person who could not see it.

	Depth-first from the roots, so a node's children are the rows directly
	underneath it and `depth` is how far to indent. Siblings keep the level-
	then-name order `nodesInTree` establishes, so the ladder reading survives
	inside each branch.

	A node with two prerequisites is filed under the first of them, and a
	prerequisite cycle would drop nodes off the end entirely. `validate`
	already rejects a cycle, and nothing in the game has two prerequisites --
	if either changes this is where it shows up.
]]
function Progression.treeRows(tree: SkillId): { { def: SkillNode, depth: number } }
	local children: { [string]: { SkillNode } } = {}
	local roots: { SkillNode } = {}

	for _, def in Progression.nodesInTree(tree) do
		local parent = if def.requires then def.requires[1] else nil
		local parentDef = if parent then nodes[parent] else nil
		if parent and parentDef and parentDef.tree == tree then
			local bucket = children[parent]
			if not bucket then
				bucket = {}
				children[parent] = bucket
			end
			table.insert(bucket, def)
		else
			table.insert(roots, def)
		end
	end

	local out: { { def: SkillNode, depth: number } } = {}
	local function walk(def: SkillNode, depth: number)
		table.insert(out, { def = def, depth = depth })
		local bucket = children[def.id]
		if bucket then
			for _, child in bucket do
				walk(child, depth + 1)
			end
		end
	end
	for _, root in roots do
		walk(root, 0)
	end
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
--[[
	The most ranks one character could ever hold in a tree.

	Dead nodes do not count -- `canPurchase` refuses them, so a capstone
	priced against them would be unreachable. Neither does the smaller half
	of each exclusive pair, since holding both is the one thing `excludes`
	exists to prevent. `ignore` drops the capstone doing the asking, which
	cannot pay for itself.
]]
local function reachableRanksInTree(tree: string, ignore: string?): number
	local total = 0
	for id, def in nodes do
		if def.tree == tree and id ~= ignore and not def.unimplemented then
			total += def.maxRank
		end
	end
	-- Each pair is seen twice (symmetry is enforced below), so charge half
	-- the smaller side each time and let the two visits add up to one.
	for _, def in nodes do
		if def.tree ~= tree or def.unimplemented or not def.excludes then
			continue
		end
		for _, otherId in def.excludes do
			local other = nodes[otherId]
			if other and other.tree == tree and not other.unimplemented then
				total -= math.min(def.maxRank, other.maxRank) / 2
			end
		end
	end
	return total
end

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

		--[[
			An exclusion is a promise that two builds are different, so all
			four of these are bugs the player would pay for:

			  * naming a node that does not exist -- an exclusion that never
			    fires, and a description that lies about a cost;
			  * excluding yourself -- rank 1 would close off rank 1;
			  * a one-way exclusion -- which of the two you can still buy
			    would depend on the order you clicked them in;
			  * excluding across trees -- the panel shows one tree at a
			    time, so the player cannot see what they just lost.
		]]
		local excludes = def.excludes
		if excludes then
			for _, other in excludes do
				local otherDef = nodes[other]
				if other == id then
					table.insert(problems, `{id}: excludes itself`)
				elseif not otherDef then
					table.insert(problems, `{id}: excludes "{other}", which is not a skill`)
				else
					if otherDef.tree ~= def.tree then
						table.insert(
							problems,
							`{id}: excludes "{other}", which is in the {otherDef.tree} tree`
						)
					end
					local back = false
					local mutuals = otherDef.excludes
					if mutuals then
						for _, mutual in mutuals do
							back = back or mutual == id
						end
					end
					if not back then
						table.insert(
							problems,
							`{id}: excludes "{other}", but "{other}" does not exclude it back`
						)
					end
				end
			end
		end

		-- A capstone priced above what its tree can hold is one no character
		-- can ever buy, and the panel would show it greyed out forever with
		-- a number that looks like a target.
		local needed = def.requiresPointsInTree
		if needed then
			local reachable = reachableRanksInTree(def.tree, id)
			if needed > reachable then
				table.insert(
					problems,
					`{id}: wants {needed} points in {def.tree}, which holds at most {reachable}`
				)
			end
		end

		-- A window with nothing in it. `canPurchase` would refuse every
		-- character on the game's only alignment axis, which reads to the
		-- player as a bug in the button rather than a bound they can meet.
		if def.minAlignment and def.maxAlignment and def.minAlignment > def.maxAlignment then
			table.insert(
				problems,
				`{id}: wants alignment above {def.minAlignment} and below {def.maxAlignment}, which is nobody`
			)
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

	--[[
		The tree only asks a question while points are scarce.

		If a level-50 character can buy everything that works, then every
		build converges and the forks and capstones above are decoration.
		This is the one property of the tree that a single new node can
		quietly destroy, and it is invisible when you are looking at that
		node -- so it is checked here rather than remembered.
	]]
	local points = Progression.STARTING_SKILL_POINTS
		+ (Progression.MAX_LEVEL - 1) * Progression.SKILL_POINTS_PER_LEVEL
	local buyable = 0
	for _, tree in Progression.TREES do
		buyable += reachableRanksInTree(tree, nil)
	end
	if buyable <= points then
		table.insert(
			problems,
			`{buyable} buyable ranks against {points} points at level {Progression.MAX_LEVEL}: `
				.. `every character can afford the whole tree`
		)
	end

	return problems
end

return Progression
