--!strict
--[[
	Affixes.luau

	The modifiers a dropped item can roll, and how good a roll makes it.

	This is the other half of the Diablo loop: the reason to keep killing
	things is that the next blaster might be *your* blaster. A base item from a
	vendor is the same for everybody; a rolled one is not.

	EVERY AFFIX MUST MOVE A STAT SOMETHING ALREADY READS.
	The skill tree taught this the hard way -- 7 of its 19 stats had no reader
	at all, so players spent points on nothing and the UI cheerfully sold it to
	them. `validate()` below enforces the same rule here, at module load, and
	the LIVE_STATS list names the file that reads each one so the claim can be
	checked rather than believed. When the ship and Force systems land, move
	their stats into that list and the affixes can follow.

	...AND MUST MOVE IT ON THE ITEM IT ROLLED ON.
	Reported from play, 2026-08-18: *"when I'm wielding a lightsaber, seems
	weird to modify blaster power since that's not a thing."* Exactly right,
	and the rule above had been passing it: `BlasterDamageMult` does have a
	live reader, so a "Vicious Lightsaber" cleared validation -- but the reader
	is `CombatService.resolveShot`, which returns early on anything that is not
	`class == "Blaster"`. The number was real, printed, priced into the item's
	rarity, and worth nothing.

	It was not one affix. A saber could roll blaster damage AND fire rate
	("Rapid Lightsaber", on a weapon whose swing cooldown takes no multiplier
	at all), a blaster could roll saber damage, and a Gaderffii could roll
	either. So `slot` is now the weapon's own class rather than the word
	"Weapon", and the only affixes that may say "Weapon" are the ones every
	class really reads. The bug was that the axis was too coarse, not that
	anybody wrote the wrong line.

	RARITY IS DERIVED, NOT STORED.
	An item's rarity is just how many affixes it rolled, so `ItemStack` needs no
	extra field and the two can never disagree. `Inventory.ItemStack.rolls` is
	`{ [stat]: value }`, and since an item never rolls the same stat twice, the
	stat is also the affix's identity -- which is why nothing has to store
	affix ids either.
]]

local Affixes = {}

--------------------------------------------------------------------------------
-- Rarity
--------------------------------------------------------------------------------

export type RarityDef = {
	name: string,
	affixes: number,
	color: Color3,
	-- Relative chance of rolling this rarity on a drop, before level scaling.
	weight: number,
	--[[
		What one is worth, as a multiple of the plain item's catalogue cost.

		Here rather than in the shop because it is a property of the rarity,
		and the rarity is defined here -- a vendor sets its own margin
		(`Shops.SELL_FRACTION`, `priceMult`), not what a Legendary *is*.

		Deliberately far flatter than the weights are steep. A Legendary is
		about one drop in a hundred and seventy; paying a hundred and seventy
		times over for one would make farming and selling strictly better than
		playing, and the point of a drop is to wear it.
	]]
	value: number,
}

--[[
	Indexed by affix count, so `RARITY[#affixes]` is the rarity. Ordered worst
	to best and it must stay contiguous from 0 -- `rarityOf` indexes it
	directly.
]]
local RARITY: { [number]: RarityDef } = {
	[0] = { name = "Common", affixes = 0, color = Color3.fromRGB(178, 184, 194), weight = 100, value = 1 },
	[1] = { name = "Uncommon", affixes = 1, color = Color3.fromRGB(104, 190, 122), weight = 46, value = 1.8 },
	[2] = { name = "Rare", affixes = 2, color = Color3.fromRGB(88, 150, 226), weight = 18, value = 3 },
	[3] = { name = "Epic", affixes = 3, color = Color3.fromRGB(166, 110, 226), weight = 6, value = 5 },
	[4] = { name = "Legendary", affixes = 4, color = Color3.fromRGB(226, 152, 62), weight = 1, value = 8 },
}

Affixes.MAX_AFFIXES = 4

--------------------------------------------------------------------------------
-- The affixes
--------------------------------------------------------------------------------

--[[
	What an item IS, and therefore which pool it draws from. A weapon's is its
	`WeaponDef.class`, passed straight through by `Loot` -- so the two cannot
	drift, and a weapon class added to the catalogue arrives here by itself.
]]
Affixes.ITEM_SLOTS = { "Blaster", "Saber", "Melee", "Outfit" }

local IS_WEAPON: { [string]: boolean } = { Blaster = true, Saber = true, Melee = true }

export type AffixDef = {
	stat: string,
	-- Shown in the item's detail pane.
	label: string,
	--[[
		One of `ITEM_SLOTS` -- or "Weapon" for something every weapon class
		reads, or "Any" for something the wearer reads no matter what it came
		on. A blaster has no business rolling armour, and a lightsaber has
		none rolling fire rate.
	]]
	slot: string,
	--[[
		Roll range at item level 1, widened by `perLevel` for each level above
		that. Both ends move, so a level 30 drop cannot roll level-1 numbers --
		levelling up should make the floor rise, not just the ceiling.
	]]
	min: number,
	max: number,
	perLevel: number,
	-- Rendered as a percentage rather than a raw number.
	percent: boolean,
	--[[
		Naming fragment. A prefix reads "Vicious DH17"; a suffix reads "DH17 of
		Fortune". At most one of each is used, so a four-affix item is not a
		paragraph.
	]]
	word: string,
	suffix: boolean,
}

local defs: { [string]: AffixDef } = {}

local function def(a: AffixDef)
	assert(not defs[a.stat], `Affixes: two affixes roll {a.stat}`)
	defs[a.stat] = a
end

-- Blasters ------------------------------------------------------------------

def({
	stat = "BlasterDamageMult",
	label = "Blaster damage",
	slot = "Blaster",
	min = 0.04,
	max = 0.09,
	perLevel = 0.0015,
	percent = true,
	word = "Vicious",
	suffix = false,
})

--[[
	Negative on purpose: the stat is a cooldown multiplier, so less is faster.

	Blasters only, and not because a fast lightsaber is a silly idea -- because
	`CombatService.onSaberSwing` calls `Weapons.cooldown(weaponId)` with no
	multiplier, so there is nothing on the swing side for this to move. If a
	saber speed stat is ever wired up, it gets its own affix here; borrowing
	this one would be the same mistake in the other direction.
]]
def({
	stat = "BlasterCooldownMult",
	label = "Fire rate",
	slot = "Blaster",
	min = -0.09,
	max = -0.03,
	perLevel = -0.0015,
	percent = true,
	word = "Rapid",
	suffix = false,
})

-- Sabers --------------------------------------------------------------------

def({
	stat = "SaberDamageMult",
	label = "Saber damage",
	slot = "Saber",
	min = 0.04,
	max = 0.09,
	perLevel = 0.0015,
	percent = true,
	word = "Honed",
	suffix = false,
})

-- Melee ---------------------------------------------------------------------

--[[
	The same numbers as the saber affix, on purpose.

	Added 2026-08-19, immediately after the slot split, because the split
	revealed the gap rather than caused it: with blaster and saber affixes
	correctly refusing to roll on a vibroblade, Melee's pool was exactly
	`MAX_AFFIXES` -- so every Legendary melee weapon in the game rolled the
	same four things, and there was no such thing as a melee weapon that hit
	harder than another of its kind.

	Matching `SaberDamageMult` rather than inventing a curve for it: a melee
	weapon is worse than a saber in the catalogue already (`WeaponDef.damage`
	and `range` say so), and paying that difference twice would be balancing
	the class through its affixes, which is not what an affix is for.
]]
def({
	stat = "MeleeDamageMult",
	label = "Melee damage",
	slot = "Melee",
	min = 0.04,
	max = 0.09,
	perLevel = 0.0015,
	percent = true,
	word = "Brutal",
	suffix = false,
})

-- Any weapon ----------------------------------------------------------------

-- The one weapon stat every class really reads: `resolveShot` rolls crit on a
-- bolt and `swingMelee` rolls it on a swing, off this same number.
def({
	stat = "CritChance",
	label = "Critical chance",
	slot = "Weapon",
	min = 0.015,
	max = 0.04,
	perLevel = 0.0006,
	percent = true,
	word = "Keen",
	suffix = false,
})

-- Outfits -------------------------------------------------------------------

--[[
	Deliberately smaller than the affixes above.

	`DamageReduction` is clamped to 0.75 across everything, and the heaviest
	armour in the game is already 0.20 -- so an affix that rolled like a
	weapon's would let four lucky drops out-armour every authored outfit and
	make the wardrobe pointless. Same reasoning as the note in Outfits.luau.
]]
def({
	stat = "DamageReduction",
	label = "Armour",
	slot = "Outfit",
	min = 0.015,
	max = 0.035,
	perLevel = 0.0005,
	percent = true,
	word = "Plated",
	suffix = false,
})

def({
	stat = "MoveSpeedMult",
	label = "Move speed",
	slot = "Outfit",
	min = 0.015,
	max = 0.035,
	perLevel = 0.0005,
	percent = true,
	word = "Swift",
	suffix = false,
})

def({
	stat = "PriceMult",
	label = "Vendor prices",
	slot = "Outfit",
	min = -0.06,
	max = -0.02,
	perLevel = -0.0008,
	percent = true,
	word = "Haggling",
	suffix = true,
})

-- Either ---------------------------------------------------------------------

def({
	stat = "BonusHealth",
	label = "Health",
	slot = "Any",
	min = 8,
	max = 20,
	perLevel = 0.9,
	percent = false,
	word = "the Bantha",
	suffix = true,
})

def({
	stat = "HealthRegen",
	label = "Health regen",
	slot = "Any",
	min = 0.2,
	max = 0.6,
	perLevel = 0.02,
	percent = false,
	word = "Mending",
	suffix = true,
})

def({
	stat = "CreditMult",
	label = "Credits found",
	slot = "Any",
	min = 0.03,
	max = 0.07,
	perLevel = 0.001,
	percent = true,
	word = "Fortune",
	suffix = true,
})

--------------------------------------------------------------------------------
-- Rolling
--------------------------------------------------------------------------------

--- Rounds to 4 decimals so a stat line reads "+6.2%", not "+6.19999999%".
local function tidy(value: number): number
	return math.floor(value * 10000 + 0.5) / 10000
end

--[[
	The affixes that may appear on a given item slot, sorted. `slot` is one of
	`ITEM_SLOTS` -- a weapon's own `WeaponDef.class`, or "Outfit". A weapon slot
	also draws the "Weapon" pool (what every class reads) and everything draws
	"Any".
]]
function Affixes.forSlot(slot: string): { AffixDef }
	local out: { AffixDef } = {}
	local weapon = IS_WEAPON[slot] == true
	for _, a in defs do
		if a.slot == slot or a.slot == "Any" or (weapon and a.slot == "Weapon") then
			table.insert(out, a)
		end
	end
	table.sort(out, function(x, y)
		return x.stat < y.stat
	end)
	return out
end

--[[
	How many affixes a drop rolls.

	Weights are fixed, then nudged by level: `luck` shifts the draw toward the
	rare end so a level 30 kill is meaningfully better than a level 3 one
	without ever making Common impossible.
]]
function Affixes.rollRarity(rng: Random, itemLevel: number): number
	local luck = 1 + math.clamp(itemLevel, 1, 40) / 40
	local total = 0
	local weights: { number } = {}
	for count = 0, Affixes.MAX_AFFIXES do
		local r = RARITY[count]
		-- Only the better-than-Common weights are lifted, so the curve tilts
		-- rather than simply scaling.
		local w = if count == 0 then r.weight else r.weight * luck
		weights[count + 1] = w
		total += w
	end

	local pick = rng:NextNumber() * total
	for count = 0, Affixes.MAX_AFFIXES do
		pick -= weights[count + 1]
		if pick <= 0 then
			return count
		end
	end
	return 0
end

--[[
	Rolls exactly `count` modifiers, ignoring the rarity weights.

	Exists for DevService. A Legendary is about one drop in a hundred and
	seventy, so the only practical way to look at one is to ask for it.
]]
function Affixes.rollExactly(
	rng: Random,
	slot: string,
	itemLevel: number,
	count: number
): { [string]: number }?
	local pool = Affixes.forSlot(slot)
	local wanted = math.min(count, #pool)
	if wanted <= 0 then
		return nil
	end

	-- Drawn without replacement: an item never rolls the same stat twice, which
	-- is what lets the stat stand in for the affix's identity everywhere else.
	local rolls: { [string]: number } = {}
	for _ = 1, wanted do
		local a = table.remove(pool, rng:NextInteger(1, #pool))
		if not a then
			break
		end
		local scale = math.max(0, itemLevel - 1)
		local low = a.min + a.perLevel * scale
		local high = a.max + a.perLevel * scale
		if low > high then
			low, high = high, low
		end
		rolls[a.stat] = tidy(rng:NextNumber(low, high))
	end
	return rolls
end

--[[
	Rolls a full set of modifiers for one dropped item.

	Returns nil for a Common drop rather than an empty table, because that is
	what `ItemStack.rolls` expects -- an item with no rolls is a plain item and
	must stack with other plain ones.
]]
function Affixes.roll(rng: Random, slot: string, itemLevel: number): { [string]: number }?
	return Affixes.rollExactly(rng, slot, itemLevel, Affixes.rollRarity(rng, itemLevel))
end

--------------------------------------------------------------------------------
-- Reading a rolled item
--------------------------------------------------------------------------------

local function affixCount(rolls: { [string]: number }?): number
	if not rolls then
		return 0
	end
	local n = 0
	for _ in rolls do
		n += 1
	end
	return math.min(n, Affixes.MAX_AFFIXES)
end

--[[
	The rarity at an affix count.

	For anything holding the count but not the rolls -- the inventory panel is
	sent `rarity` as a number, because a client that only draws a colour and a
	word has no use for the roll table it came from.
]]
function Affixes.rarityAt(count: number): RarityDef
	return RARITY[math.clamp(math.floor(count), 0, Affixes.MAX_AFFIXES)]
end

--- The rarity of an item with these rolls. Common when there are none.
function Affixes.rarityOf(rolls: { [string]: number }?): RarityDef
	return Affixes.rarityAt(affixCount(rolls))
end

function Affixes.exists(stat: string): boolean
	return defs[stat] ~= nil
end

function Affixes.get(stat: string): AffixDef
	local d = defs[stat]
	assert(d, `Affixes.get: nothing rolls "{stat}"`)
	return d
end

--[[
	The item's name, decorated by what it rolled.

	One prefix and one suffix at most, chosen by the affix whose stat sorts
	first, so the same rolls always produce the same name -- a player who calls
	it "my Vicious DH17" must find it called that next session too.
]]
function Affixes.nameFor(baseName: string, rolls: { [string]: number }?): string
	if not rolls then
		return baseName
	end
	local stats: { string } = {}
	for stat in rolls do
		if defs[stat] then
			table.insert(stats, stat)
		end
	end
	table.sort(stats)

	local prefix: string? = nil
	local suffix: string? = nil
	for _, stat in stats do
		local a = defs[stat]
		if a.suffix then
			suffix = suffix or a.word
		else
			prefix = prefix or a.word
		end
	end

	local name = baseName
	if prefix then
		name = `{prefix} {name}`
	end
	if suffix then
		name = `{name} of {suffix}`
	end
	return name
end

--[[
	The stat lines to show under a rolled item, already formatted and sorted.

	Sorted by stat name for the same reason the name is: a detail pane whose
	rows reorder every time you open it is one you cannot read.
]]
function Affixes.describe(rolls: { [string]: number }?): { string }
	local out: { string } = {}
	if not rolls then
		return out
	end
	local stats: { string } = {}
	for stat in rolls do
		if defs[stat] then
			table.insert(stats, stat)
		end
	end
	table.sort(stats)

	for _, stat in stats do
		local a = defs[stat]
		local value = rolls[stat]
		if a.percent then
			-- Cooldown and price affixes roll negative because less is better;
			-- shown with the sign they were rolled with, so the number on the
			-- sheet matches the number in the save.
			table.insert(
				out,
				`{if value >= 0 then "+" else ""}{string.format("%.1f", value * 100)}%  {a.label}`
			)
		else
			table.insert(out, `{if value >= 0 then "+" else ""}{string.format("%.1f", value)}  {a.label}`)
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

--[[
	Reports every affix that would do nothing, at boot. See the note at the top
	of the file for why this rule exists.

	`liveStats` is `Progression.LIVE_STATS`, passed in rather than required:
	Progression.luau is the heavier module and a cycle between two config files
	is not worth the convenience. It lives there because it describes the stat
	table, which is Progression's, and skills are checked against the same one
	-- two copies of "which stats are real" would drift, and the whole point of
	the table is that it does not.

	`weaponClasses` is `Weapons.classes()` -- the classes that actually exist in
	the catalogue, not a list written here. A `Thrown` weapon added tomorrow
	should make this complain tomorrow, without anyone remembering to come back.
]]
function Affixes.validate(liveStats: { [string]: string }, weaponClasses: { string }): { string }
	local problems: { string } = {}

	local known: { [string]: boolean } = { Weapon = true, Any = true }
	for _, slot in Affixes.ITEM_SLOTS do
		known[slot] = true
	end

	for stat, a in defs do
		if not liveStats[stat] then
			table.insert(problems, `"{stat}" has no live reader, so rolling it would do nothing`)
		end
		if not known[a.slot] then
			table.insert(problems, `"{stat}" has unknown slot "{a.slot}"`)
		end
		if a.min > a.max then
			table.insert(problems, `"{stat}" has min above max`)
		end
	end

	for count = 0, Affixes.MAX_AFFIXES do
		if not RARITY[count] then
			table.insert(problems, `no rarity defined for {count} affixes`)
		end
	end

	--[[
		Every slot a drop can actually land in must be able to fill a Legendary,
		or the top rarity is unreachable there and the drop table quietly lies.

		Checked against the weapon classes in the catalogue rather than a list
		here, because the failure this catches is a *new* class -- one nobody
		wrote affixes for would draw only the "Weapon" and "Any" pools.
	]]
	local slots = table.clone(weaponClasses)
	table.insert(slots, "Outfit")
	for _, slot in slots do
		if not known[slot] then
			table.insert(problems, `weapons have class "{slot}" but no affix slot is named that`)
		end
		local pool = #Affixes.forSlot(slot)
		if pool < Affixes.MAX_AFFIXES then
			table.insert(problems, `only {pool} affixes can roll on {slot}, so it can never be Legendary`)
		end
	end

	table.sort(problems)
	return problems
end

return Affixes
