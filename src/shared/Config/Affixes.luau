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

	RARITY IS DERIVED, NOT STORED.
	An item's rarity is just how many affixes it rolled, so `ItemStack` needs no
	extra field and the two can never disagree. `Inventory.ItemStack.rolls` is
	`{ [stat]: value }`, and since an item never rolls the same stat twice, the
	stat is also the affix's identity -- which is why nothing has to store
	affix ids either.
]]

local Affixes = {}

--------------------------------------------------------------------------------
-- Which stats are real
--------------------------------------------------------------------------------

--[[
	Stats with a live reader, and where that reader is.

	Checked against `Progression.baseStats` in `validate()`, so a typo here is a
	startup error. Verified 2026-08-16; if a reader is deleted, delete the
	entry, and any affix using it will then fail validation loudly.
]]
local LIVE_STATS: { [string]: string } = {
	BlasterDamageMult = "CombatService.resolveShot",
	BlasterCooldownMult = "CombatService (fire-rate cooldown)",
	BonusHealth = "ProgressionService.maxHealthFor",
	HealthRegen = "PlayerService (regen loop)",
	CritChance = "CombatService.resolveShot / onSaberSwing",
	SaberDamageMult = "CombatService.onSaberSwing",
	MoveSpeedMult = "PlayerService (humanoid.WalkSpeed)",
	CreditMult = "ProgressionService.awardCredits",
	PriceMult = "ProgressionService.priceFor / TravelService",
	DamageReduction = "CombatService.applyDamage",
}

--------------------------------------------------------------------------------
-- Rarity
--------------------------------------------------------------------------------

export type RarityDef = {
	name: string,
	affixes: number,
	color: Color3,
	-- Relative chance of rolling this rarity on a drop, before level scaling.
	weight: number,
}

--[[
	Indexed by affix count, so `RARITY[#affixes]` is the rarity. Ordered worst
	to best and it must stay contiguous from 0 -- `rarityOf` indexes it
	directly.
]]
local RARITY: { [number]: RarityDef } = {
	[0] = { name = "Common", affixes = 0, color = Color3.fromRGB(178, 184, 194), weight = 100 },
	[1] = { name = "Uncommon", affixes = 1, color = Color3.fromRGB(104, 190, 122), weight = 46 },
	[2] = { name = "Rare", affixes = 2, color = Color3.fromRGB(88, 150, 226), weight = 18 },
	[3] = { name = "Epic", affixes = 3, color = Color3.fromRGB(166, 110, 226), weight = 6 },
	[4] = { name = "Legendary", affixes = 4, color = Color3.fromRGB(226, 152, 62), weight = 1 },
}

Affixes.MAX_AFFIXES = 4

--------------------------------------------------------------------------------
-- The affixes
--------------------------------------------------------------------------------

export type AffixDef = {
	stat: string,
	-- Shown in the item's detail pane.
	label: string,
	-- "Weapon", "Outfit", or "Any". A blaster has no business rolling armour.
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

-- Weapons -------------------------------------------------------------------

def({
	stat = "BlasterDamageMult",
	label = "Blaster damage",
	slot = "Weapon",
	min = 0.04,
	max = 0.09,
	perLevel = 0.0015,
	percent = true,
	word = "Vicious",
	suffix = false,
})

-- Negative on purpose: the stat is a cooldown multiplier, so less is faster.
def({
	stat = "BlasterCooldownMult",
	label = "Fire rate",
	slot = "Weapon",
	min = -0.09,
	max = -0.03,
	perLevel = -0.0015,
	percent = true,
	word = "Rapid",
	suffix = false,
})

def({
	stat = "SaberDamageMult",
	label = "Saber damage",
	slot = "Weapon",
	min = 0.04,
	max = 0.09,
	perLevel = 0.0015,
	percent = true,
	word = "Honed",
	suffix = false,
})

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

--- The affixes that may appear on a given slot ("Weapon" or "Outfit"), sorted.
function Affixes.forSlot(slot: string): { AffixDef }
	local out: { AffixDef } = {}
	for _, a in defs do
		if a.slot == slot or a.slot == "Any" then
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
	Rolls a full set of modifiers for one dropped item.

	Returns nil for a Common drop rather than an empty table, because that is
	what `ItemStack.rolls` expects -- an item with no rolls is a plain item and
	must stack with other plain ones.
]]
function Affixes.roll(rng: Random, slot: string, itemLevel: number): { [string]: number }?
	local pool = Affixes.forSlot(slot)
	local wanted = math.min(Affixes.rollRarity(rng, itemLevel), #pool)
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

	`baseStats` is passed in rather than required, because Progression.luau is
	the heavier module and a cycle between two config files is not worth the
	convenience.
]]
function Affixes.validate(baseStats: { [string]: number }): { string }
	local problems: { string } = {}

	for stat, reader in LIVE_STATS do
		if baseStats[stat] == nil then
			table.insert(problems, `LIVE_STATS names "{stat}" ({reader}), which is not a stat`)
		end
	end

	for stat, a in defs do
		if not LIVE_STATS[stat] then
			table.insert(problems, `"{stat}" has no live reader, so rolling it would do nothing`)
		end
		if a.slot ~= "Weapon" and a.slot ~= "Outfit" and a.slot ~= "Any" then
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

	-- Both slots must be able to fill a Legendary, or the top rarity is
	-- unreachable for one of them and the drop table quietly lies.
	for _, slot in { "Weapon", "Outfit" } do
		local pool = #Affixes.forSlot(slot)
		if pool < Affixes.MAX_AFFIXES then
			table.insert(problems, `only {pool} affixes can roll on {slot}, so it can never be Legendary`)
		end
	end

	table.sort(problems)
	return problems
end

return Affixes
