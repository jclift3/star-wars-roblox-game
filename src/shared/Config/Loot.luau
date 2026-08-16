--!strict
--[[
	Loot.luau

	What falls off a dead NPC.

	Deliberately has no drop table of its own. The pool is *derived* from the
	Weapons and Outfits catalogues by level, so a weapon added tomorrow drops
	tomorrow, and it is impossible for this file to name an item that does not
	exist. That last part is not hypothetical: naming ids in a second place is
	how this project shipped four missions whose kill targets never spawned.

	There is no `validate` here for the same reason -- nothing is authored, so
	there is nothing that can be wrong.

	EVERY DROP IS ROLLED
	`Affixes.roll` returns nil for a Common result and this treats that as "no
	drop". A plain blaster identical to the one on the vendor's shelf is not
	loot, it is clutter -- and because plain stacks merge by catalogue id, a
	second one would not even be a second item in the bag.
]]

local Affixes = require(script.Parent.Affixes)
local Inventory = require(script.Parent.Parent.Core.Inventory)
local Outfits = require(script.Parent.Outfits)
local Weapons = require(script.Parent.Weapons)

local Loot = {}

--[[
	How often a kill is even considered for a drop.

	The real rate is lower than this, because a Common roll drops nothing --
	see the note above. At the shipped affix weights roughly two in five
	considered drops survive, so this is about one item per seven kills.
]]
Loot.DROP_CHANCE = 0.35

--[[
	How far below the best item the NPC's level unlocks the pool reaches.

	Without a floor a level 30 kill almost always hands back a starter pistol,
	simply because there are many more cheap items than expensive ones. The
	band keeps drops roughly current without making them a fixed tier.
]]
local LEVEL_BAND = 6

export type Drop = {
	kind: string, -- "Weapon" | "Outfit", and also the affix slot
	id: string,
	rolls: Inventory.Rolls,
}

type Candidate = { kind: string, id: string, requiredLevel: number }

local function gather(itemLevel: number): { Candidate }
	local eligible: { Candidate } = {}
	local best = 1

	-- `cost <= 0` is the catalogue's way of saying "not a thing you acquire":
	-- fists, and the outfit every character already starts in.
	for _, id in Weapons.ids() do
		local w = Weapons.get(id)
		if w.cost > 0 and w.requiredLevel <= itemLevel then
			table.insert(eligible, { kind = "Weapon", id = id, requiredLevel = w.requiredLevel })
			best = math.max(best, w.requiredLevel)
		end
	end
	for _, id in Outfits.ids() do
		local o = Outfits.get(id)
		if o.cost > 0 and o.requiredLevel <= itemLevel then
			table.insert(eligible, { kind = "Outfit", id = id, requiredLevel = o.requiredLevel })
			best = math.max(best, o.requiredLevel)
		end
	end

	local floorLevel = best - LEVEL_BAND
	local out: { Candidate } = {}
	for _, c in eligible do
		if c.requiredLevel >= floorLevel then
			table.insert(out, c)
		end
	end
	return out
end

--[[
	Rolls one kill's worth of loot. Returns nil far more often than not.

	`itemLevel` is the NPC's level, not the killer's: a mook is worth what the
	mook is worth, and levelling past a zone should stop it being a source of
	upgrades rather than keep pace with you.
]]
function Loot.rollDrop(rng: Random, itemLevel: number): Drop?
	if rng:NextNumber() > Loot.DROP_CHANCE then
		return nil
	end

	local level = math.max(1, math.floor(itemLevel))
	local pool = gather(level)
	if #pool == 0 then
		return nil
	end

	local pick = pool[rng:NextInteger(1, #pool)]
	local rolls = Affixes.roll(rng, pick.kind, level)
	if not rolls then
		return nil
	end
	return { kind = pick.kind, id = pick.id, rolls = rolls }
end

--- The dropped item's decorated name, for the pickup message.
function Loot.nameOf(drop: Drop): string
	local base = if drop.kind == "Weapon"
		then Weapons.get(drop.id).displayName
		else Outfits.get(drop.id).displayName
	return Affixes.nameFor(base, drop.rolls)
end

return Loot
