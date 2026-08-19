--!strict
--[[
	Crystals.luau

	Focusing crystals: the stones a player sockets into gear.

	Affixes are the half of the loot loop the game plays for you -- a drop
	either rolled well or it did not, and there is nothing to decide. This is
	the other half, and the one Diablo is actually remembered for: a socket is
	an empty slot that the *player* fills, so a piece of gear becomes something
	built rather than something won. It is also the only place in the economy
	where credits are spent on a decision instead of a price tag.

	WHAT A CRYSTAL DOES DEPENDS ON WHAT IT IS IN.
	The one property worth stealing wholesale. A crimson crystal is damage in a
	weapon and armour in an outfit; an amber one is credits found on a weapon
	and cheaper prices on an outfit. It maps exactly onto the slot split
	`Affixes` already makes (`Blaster`/`Saber`/`Melee`/`Outfit`), which is why
	there is no new axis here to keep in sync with anything.

	NOTHING NUMERIC IS AUTHORED IN THIS FILE.
	A crystal's value is the midpoint of the affix that moves the same stat,
	times its grade. That is deliberate and it is the whole reason the table
	below is only names: the project has one balance curve per stat, in
	`Affixes`, and a second one here would drift from it silently and forever.
	Retune an affix and the crystals that grant it follow in the same commit.

	FOUR COLOURS, NOT FIVE.
	The twelve assignments below are very nearly the complete set of stats that
	are legal on their slots -- nothing repeats except `CritChance`, which is
	the only tempo stat a swung weapon has (`onSaberSwing` calls
	`Weapons.cooldown(id)` with no multiplier at all, so a "faster saber"
	crystal would be the 2026-08-18 bug again). A fifth colour would have to
	either duplicate a line or invent a stat, and inventing a stat is four
	edits ending in a real reader -- a separate change, not one smuggled in
	here to round the table out.
]]

local Affixes = require(script.Parent.Affixes)
local Palette = require(script.Parent.Palette)

local Crystals = {}

--[[
	How many crystals one item can hold.

	Three, because `Progression.computeStats` folds gear in additively: three
	Perfect damage crystals are +43%, which is a build, and a fourth would
	start to out-weigh the item carrying them.
]]
Crystals.MAX_SOCKETS = 3

--------------------------------------------------------------------------------
-- Grades
--------------------------------------------------------------------------------

export type GradeDef = {
	-- Name fragment. The middle grade has none: a plain "Crimson Crystal".
	word: string,
	-- Multiplier on the affix midpoint this crystal's stat is derived from.
	scale: number,
	cost: number,
	--[[
		Which `Affixes` rarity a crystal of this grade *is*, 0..4.

		Not a parallel concept: the grade ladder and the rarity ladder are the
		same five steps, so a crystal borrows the rarity's colour, its drop
		weight and its pips, and the panel needs no second vocabulary for
		"how good is this". Chipped is Common; Perfect is Legendary and about
		as rare.
	]]
	rarity: number,
}

--- Worst to best. Index is `rarity + 1`; `rollGrade` relies on that.
local GRADES: { GradeDef } = {
	{ word = "Chipped", scale = 0.4, cost = 250, rarity = 0 },
	{ word = "Flawed", scale = 0.7, cost = 700, rarity = 1 },
	{ word = "", scale = 1, cost = 1800, rarity = 2 },
	{ word = "Flawless", scale = 1.5, cost = 4500, rarity = 3 },
	{ word = "Perfect", scale = 2.2, cost = 11000, rarity = 4 },
}

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------

export type ColourDef = {
	id: string,
	name: string,
	color: Color3,
	-- One line of flavour, and the promise the four stats below have to keep.
	theme: string,
	--[[
		The stat this colour grants, per `Affixes.ITEM_SLOTS`. Every slot must
		be present -- a crystal that does nothing in a lightsaber is a crystal
		a player will socket into a lightsaber. `validate` says so at boot.
	]]
	stats: { [string]: string },
}

local COLOURS: { ColourDef } = {
	{
		id = "Crimson",
		name = "Crimson",
		color = Palette.SaberRed,
		theme = "Harm, and the refusal of it",
		stats = {
			Blaster = "BlasterDamageMult",
			Saber = "SaberDamageMult",
			Melee = "MeleeDamageMult",
			Outfit = "DamageReduction",
		},
	},
	{
		id = "Azure",
		name = "Azure",
		color = Palette.SaberBlue,
		theme = "Speed of hand and foot",
		stats = {
			Blaster = "BlasterCooldownMult",
			Saber = "CritChance",
			Melee = "CritChance",
			Outfit = "MoveSpeedMult",
		},
	},
	{
		id = "Verdant",
		name = "Verdant",
		color = Palette.SaberGreen,
		theme = "Staying alive long enough to matter",
		stats = {
			Blaster = "BonusHealth",
			Saber = "BonusHealth",
			Melee = "BonusHealth",
			Outfit = "HealthRegen",
		},
	},
	{
		id = "Amber",
		name = "Amber",
		color = Palette.SaberYellow,
		theme = "What the galaxy owes you",
		stats = {
			Blaster = "CreditMult",
			Saber = "CreditMult",
			Melee = "CreditMult",
			Outfit = "PriceMult",
		},
	},
}

--------------------------------------------------------------------------------
-- The catalogue, composed at require time
--------------------------------------------------------------------------------

export type CrystalDef = {
	id: string,
	colour: ColourDef,
	grade: GradeDef,
	displayName: string,
	description: string,
	color: Color3,
	rarity: number,
	cost: number,
}

local defs: { [string]: CrystalDef } = {}
local ids: { string } = {}

--[[
	Composed rather than written out, the way `Radiant` composes its missions.

	Twenty hand-authored entries would be twenty chances to paste the wrong
	colour into the wrong grade, and every one of them would look right.
]]
for _, colour in COLOURS do
	for _, grade in GRADES do
		local id = colour.id .. grade.word
		local displayName = if grade.word == ""
			then `{colour.name} Crystal`
			else `{grade.word} {colour.name} Crystal`
		defs[id] = {
			id = id,
			colour = colour,
			grade = grade,
			displayName = displayName,
			description = colour.theme,
			color = colour.color,
			rarity = grade.rarity,
			cost = grade.cost,
		}
		table.insert(ids, id)
	end
end
table.sort(ids)

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

function Crystals.exists(id: string): boolean
	return defs[id] ~= nil
end

function Crystals.get(id: string): CrystalDef
	local d = defs[id]
	assert(d, `Crystals.get: no crystal "{id}"`)
	return d
end

--- Every crystal id, sorted.
function Crystals.ids(): { string }
	return table.clone(ids)
end

--- Every colour, in the order they are declared above.
function Crystals.colours(): { ColourDef }
	return table.clone(COLOURS)
end

--- Rounds to 4 decimals, so a stat line reads "+6.2%" and not "+6.19999%".
local function tidy(value: number): number
	return math.floor(value * 10000 + 0.5) / 10000
end

--[[
	What this crystal is worth in this kind of item, as a rolls table.

	Deliberately the same shape `ItemStack.rolls` and
	`Progression.computeStats` already speak, so a socketed crystal needs no
	reader of its own and `Affixes.describe` can format it unchanged.

	The value is the affix midpoint at item level 1 scaled by the grade -- see
	the note at the top. Negative affixes (fire rate, vendor prices) come out
	negative without any special case, because less of those is better and the
	affix already says so.
]]
function Crystals.statsFor(id: string, slot: string): { [string]: number }
	local d = defs[id]
	if not d then
		return {}
	end
	local stat = d.colour.stats[slot]
	if not stat or not Affixes.exists(stat) then
		return {}
	end
	local a = Affixes.get(stat)
	return { [stat] = tidy((a.min + a.max) / 2 * d.grade.scale) }
end

--[[
	The colour a set of socketed crystals paints the item.

	The lowest filled socket wins. A rule the player can see and act on beats
	blending four colours into mud, and "the first stone sets the blade" is one
	sentence in the panel.
]]
function Crystals.tintOf(socketed: { [string]: string }?): Color3?
	if not socketed then
		return nil
	end
	for i = 1, Crystals.MAX_SOCKETS do
		local id = socketed[tostring(i)]
		local d = if id then defs[id] else nil
		if d then
			return d.color
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Rolling
--------------------------------------------------------------------------------

--[[
	Which grade a crystal that has just dropped is.

	Weighted by the rarity table it shares, so a Perfect crystal is as rare as
	a Legendary item and lifts with level for the same reason.
]]
function Crystals.rollDrop(rng: Random, itemLevel: number): string
	local grade = GRADES[Affixes.rollRarity(rng, itemLevel) + 1] or GRADES[1]
	local colour = COLOURS[rng:NextInteger(1, #COLOURS)]
	return colour.id .. grade.word
end

--[[
	How many sockets a dropped item has.

	Independent of its affixes on purpose. It is what finally gives a Common
	drop a reason to exist -- until now `Loot` threw those away, because a
	plain blaster identical to the vendor's was clutter. A plain blaster with
	two holes in it is not.
]]
function Crystals.rollSockets(rng: Random, itemLevel: number): number
	local reach = math.min(Crystals.MAX_SOCKETS, 1 + math.floor(itemLevel / 12))
	local n = 0
	for _ = 1, reach do
		if rng:NextNumber() < 0.3 then
			n += 1
		end
	end
	return n
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

--[[
	Reports every crystal that would do nothing, at boot.

	The rule is stricter than the affixes' and on purpose: a granted stat must
	not merely have a live reader, it must be one an affix on that same slot
	could roll. Asked through `Affixes.statsForSlot`, so the two files cannot
	hold different opinions about what a lightsaber is allowed to care about.

	That is the exact bug reported on 2026-08-18 -- a "Vicious Lightsaber" that
	validated, printed a number, priced it into its rarity, and did nothing --
	made impossible here rather than merely avoided.
]]
function Crystals.validate(liveStats: { [string]: string }): { string }
	local problems: { string } = {}

	local legal: { [string]: { [string]: boolean } } = {}
	for _, slot in Affixes.ITEM_SLOTS do
		legal[slot] = Affixes.statsForSlot(slot)
	end

	for _, colour in COLOURS do
		for _, slot in Affixes.ITEM_SLOTS do
			local stat = colour.stats[slot]
			if not stat then
				table.insert(problems, `{colour.id}: grants nothing in a {slot}`)
			elseif not liveStats[stat] then
				table.insert(problems, `{colour.id}: grants "{stat}", which has no live reader`)
			elseif not legal[slot][stat] then
				table.insert(problems, `{colour.id}: grants "{stat}" in a {slot}, where nothing reads it`)
			end
		end
		for slot in colour.stats do
			if not legal[slot] then
				table.insert(problems, `{colour.id}: names slot "{slot}", which is not an item slot`)
			end
		end
	end

	for i, grade in GRADES do
		if grade.rarity ~= i - 1 then
			table.insert(problems, `grade "{grade.word}" is at index {i} but claims rarity {grade.rarity}`)
		end
		if grade.scale <= 0 or grade.cost <= 0 then
			table.insert(problems, `grade "{grade.word}" has a scale or cost of zero`)
		end
	end
	if #GRADES ~= Affixes.MAX_AFFIXES + 1 then
		table.insert(problems, `{#GRADES} grades against {Affixes.MAX_AFFIXES + 1} rarities`)
	end

	table.sort(problems)
	return problems
end

return Crystals
