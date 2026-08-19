--!strict
--[[
	Outfits.luau

	What every costume costs, who may wear it, and what it does for you.

	SPLIT FROM Costumes.luau ON PURPOSE
	Costumes.luau is a thousand lines of geometry: where the pauldron sits, how
	wide the helmet is. None of that changes when a price does. Keeping the
	economy in its own file means balancing gear is a small readable diff rather
	than a needle in a haystack of Vector3s, and it means a costume can exist
	for NPCs without ever being something a player can buy -- an NPC wears
	`Costumes.Jawa` whether or not `Outfits.Jawa` exists.

	`id` is the Costumes key. That is the whole binding between the two files,
	and `validate()` below enforces it, so a typo is a startup error rather
	than a player buying an outfit that turns out to be invisible.

	STATS ARE DELIBERATELY SMALL
	The heaviest armour in the game is 20% damage reduction. Outfits are meant
	to be a real choice, not the choice -- if plate armour trivialised combat
	then every player would converge on the same look and the wardrobe would be
	pointless. Speed and price modifiers give the light outfits a reason to
	exist alongside the heavy ones.
]]

local Outfits = {}

export type OutfitDef = {
	id: string, -- must match a key in Costumes.luau
	displayName: string,
	description: string,

	tier: number, -- 1..5, drives vendor stocking and loot tables
	cost: number,
	requiredLevel: number,

	--[[
		Stat modifiers, folded in alongside skills by Progression.computeStats.

		Uses the same stat names the skill tree uses, so a stat only ever has
		one meaning and one place it is applied. `DamageReduction` is a
		fraction (0.1 = take 10% less), `MoveSpeedMult` and `PriceMult` are
		deltas around 1.0 to match how skills stack.
	]]
	stats: { [string]: number }?,
}

local defs: { [string]: OutfitDef } = {}

local function def(o: OutfitDef): OutfitDef
	defs[o.id] = o
	return o
end

--------------------------------------------------------------------------------
-- Civilian
--------------------------------------------------------------------------------

def({
	id = "Civilian",
	displayName = "Spacer's Clothes",
	description = "Plain, cheap and forgettable. Nobody looks twice, which is worth something.",
	tier = 1,
	cost = 120,
	requiredLevel = 1,
})

def({
	id = "MoistureFarmer",
	displayName = "Moisture Farmer's Tunic",
	description = "Sun-bleached homespun cut for long days in the Jundland wastes.",
	tier = 1,
	cost = 220,
	requiredLevel = 1,
	stats = { MoveSpeedMult = 0.02 },
})

def({
	id = "Smuggler",
	displayName = "Smuggler's Vest",
	description = "Hard-wearing, plenty of pockets, and the holster rides right. The freelancer's uniform.",
	tier = 2,
	cost = 400,
	requiredLevel = 1,
	stats = { MoveSpeedMult = 0.04 },
})

def({
	id = "Merchant",
	displayName = "Trader's Robes",
	description = "Dress like a dealer and the dealers quote you their real prices.",
	tier = 2,
	cost = 350,
	requiredLevel = 3,
	stats = { PriceMult = -0.06 },
})

def({
	id = "Jawa",
	displayName = "Scavenger's Cowl",
	description = "A hood deep enough to hide a face and a smell strong enough to hide the rest.",
	tier = 2,
	cost = 480,
	requiredLevel = 4,
	stats = { PriceMult = -0.04, MoveSpeedMult = 0.02 },
})

def({
	id = "TuskenRaider",
	displayName = "Tusken Wrappings",
	description = "Bandages, goggles and a gaffi stick's worth of menace. Sand does not get through.",
	tier = 3,
	cost = 900,
	requiredLevel = 8,
	stats = { DamageReduction = 0.05, MoveSpeedMult = 0.03 },
})

--------------------------------------------------------------------------------
-- Military
--------------------------------------------------------------------------------

def({
	id = "RepublicTrooper",
	displayName = "Republic Fatigues",
	description = "Standard issue. Light flak weave under the jacket, and a helmet that does less than it looks.",
	tier = 3,
	cost = 1100,
	requiredLevel = 6,
	stats = { DamageReduction = 0.07 },
})

def({
	id = "RepublicPilot",
	displayName = "Republic Flight Suit",
	description = "Orange, unmistakable, and built for a cockpit rather than a firefight.",
	tier = 3,
	cost = 1250,
	requiredLevel = 8,
	stats = { DamageReduction = 0.04, MoveSpeedMult = 0.05 },
})

def({
	id = "RepublicSecurity",
	displayName = "Republic Security Uniform",
	description = "Ceremonial on the outside, genuinely armoured underneath.",
	tier = 3,
	cost = 1400,
	requiredLevel = 9,
	stats = { DamageReduction = 0.09 },
})

def({
	id = "ImperialTrooper",
	displayName = "Imperial Trooper Armour",
	description = "Plastoid plate over a black bodyglove. Stops a glancing bolt; the helmet costs you some peripheral vision.",
	tier = 4,
	cost = 1900,
	requiredLevel = 12,
	stats = { DamageReduction = 0.12, MoveSpeedMult = -0.02 },
})

def({
	id = "ImperialScout",
	displayName = "Imperial Scout Kit",
	description = "The same plate with a cooling pack and a pauldron. Desert deployment, no loss of speed.",
	tier = 4,
	cost = 2200,
	requiredLevel = 14,
	stats = { DamageReduction = 0.12 },
})

def({
	id = "RepublicVeteran",
	displayName = "Veteran's Plate",
	description = "Pre-treaty issue, worn by people who were at the Sacking. Better than most of what replaced it.",
	tier = 4,
	cost = 2600,
	requiredLevel = 15,
	stats = { DamageReduction = 0.14 },
})

def({
	id = "ImperialOfficer",
	displayName = "Imperial Officer's Uniform",
	description = "No armour at all. The protection is the rank cylinder on your chest.",
	tier = 4,
	cost = 2000,
	requiredLevel = 13,
	stats = { PriceMult = -0.1 },
})

--------------------------------------------------------------------------------
-- Elite
--------------------------------------------------------------------------------

def({
	id = "BountyHunter",
	displayName = "Hunter's Beskar Kit",
	description = "Mismatched plate collected off people who no longer needed it. Heavy, fast, and expensive.",
	tier = 5,
	cost = 4200,
	requiredLevel = 18,
	stats = { DamageReduction = 0.16, MoveSpeedMult = 0.03 },
})

def({
	id = "ImperialCommando",
	displayName = "Imperial Commando Armour",
	description = "Black specialist plate. Everything the standard kit should have been.",
	tier = 5,
	cost = 6800,
	requiredLevel = 24,
	stats = { DamageReduction = 0.18 },
})

def({
	id = "SithHonourGuard",
	displayName = "Honour Guard Regalia",
	description = "Crimson from head to heel. The heaviest thing anyone walks around in, and it walks slowly.",
	tier = 5,
	cost = 7500,
	requiredLevel = 26,
	stats = { DamageReduction = 0.2, MoveSpeedMult = -0.05 },
})

def({
	id = "Jedi",
	displayName = "Jedi Robes",
	description = "Rough-woven and unremarkable, which was always the point.",
	tier = 5,
	cost = 5500,
	requiredLevel = 20,
	stats = { DamageReduction = 0.05, MoveSpeedMult = 0.08 },
})

def({
	id = "JediHoodDown",
	displayName = "Jedi Robes (Hood Down)",
	description = "The same robes, worn by someone who is not trying to go unrecognised.",
	tier = 5,
	cost = 5500,
	requiredLevel = 20,
	stats = { DamageReduction = 0.05, MoveSpeedMult = 0.08 },
})

def({
	id = "Sith",
	displayName = "Sith Robes",
	description = "Black on black. Cut to conceal a hilt and to be seen doing it.",
	tier = 5,
	cost = 6200,
	requiredLevel = 22,
	stats = { DamageReduction = 0.06, MoveSpeedMult = 0.08 },
})

def({
	id = "SithLordArmoured",
	displayName = "Sith Lord's Armour",
	description = "Life support and plate, welded around someone who no longer has the option of taking it off.",
	tier = 5,
	cost = 9000,
	requiredLevel = 30,
	stats = { DamageReduction = 0.19, MoveSpeedMult = -0.03 },
})

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- The outfit every new character starts in, and can always fall back to.
Outfits.DEFAULT = "Smuggler"

function Outfits.get(id: string): OutfitDef
	local d = defs[id]
	assert(d, `Outfits.get: unknown outfit "{id}"`)
	return d
end

function Outfits.exists(id: string): boolean
	return defs[id] ~= nil
end

function Outfits.all(): { [string]: OutfitDef }
	return defs
end

function Outfits.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

--- The stat table an outfit contributes, or an empty one. Never nil, so
--- callers can fold it in without a branch.
function Outfits.statsFor(id: string?): { [string]: number }
	if not id then
		return {}
	end
	local d = defs[id]
	return (d and d.stats) or {}
end

local maxima: { [string]: number }? = nil

--[[
	The largest each outfit stat gets anywhere in the wardrobe.

	The counterpart of `Weapons.maxima`, and derived for the same reason: the
	panel draws these as bars and a bar needs a full length. Absolute value,
	because `PriceMult` is a discount and reads as -0.15 -- the bar is showing
	how big the effect is, and the sign is already in the printed number.
]]
function Outfits.maxima(): { [string]: number }
	if maxima then
		return maxima
	end
	local m: { [string]: number } = {}
	for _, d in defs do
		for stat, value in d.stats or {} :: { [string]: number } do
			m[stat] = math.max(m[stat] or 0, math.abs(value))
		end
	end
	maxima = m
	return m
end

--[[
	Checks every outfit names a costume that actually exists.

	Called at boot. The failure this prevents is silent and awful: a mistyped
	id sells fine, equips fine, and leaves the player standing there in their
	underwear wondering what they paid for.
]]
function Outfits.validate(costumeExists: (string) -> boolean): { string }
	local problems: { string } = {}
	for id, d in defs do
		if not costumeExists(id) then
			table.insert(problems, `Outfits: "{id}" has no matching costume in Costumes.luau`)
		end
		if d.cost < 0 then
			table.insert(problems, `Outfits: "{id}" has a negative cost`)
		end
	end
	if not defs[Outfits.DEFAULT] then
		table.insert(problems, `Outfits: DEFAULT "{Outfits.DEFAULT}" is not a defined outfit`)
	end
	table.sort(problems)
	return problems
end

return Outfits
