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

	EVERY DROP IS ROLLED, OR DRILLED
	`Affixes.roll` returns nil for a Common result and this used to treat that
	as "no drop": a plain blaster identical to the one on the vendor's shelf is
	not loot, it is clutter, and because plain stacks merge by catalogue id a
	second one would not even be a second item in the bag.

	Sockets changed that, and are the reason a Common is worth picking up at
	all now. An item survives if it rolled affixes *or* dropped with holes in
	it, because a plain blaster with three sockets is a blank the player fills
	in, and that is a different object from the one on the shelf.
]]

local Affixes = require(script.Parent.Affixes)
local Crystals = require(script.Parent.Crystals)
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
	kind: string, -- "Weapon" | "Outfit" | "Crystal", the inventory kind
	id: string,
	-- nil on a Common that survived on its sockets alone, and on a crystal.
	rolls: Inventory.Rolls?,
	sockets: number?,
}

--[[
	How often a drop is a crystal rather than a piece of gear.

	Well above the affix rates on purpose: a socket is worth nothing until
	there is a stone to put in it, and an item arriving with three empty holes
	the player cannot fill is a worse outcome than no drop at all.
]]
local CRYSTAL_SHARE = 0.4

--[[
	`slot` is what the item draws affixes from, and it is NOT `kind`. A weapon's
	slot is its `WeaponDef.class`, so a lightsaber cannot roll blaster damage --
	see the note at the top of Affixes.luau for the bug that came of the two
	being the same field.
]]
type Candidate = { kind: string, slot: string, id: string, requiredLevel: number }

local function gather(itemLevel: number): { Candidate }
	local eligible: { Candidate } = {}
	local best = 1

	-- `cost <= 0` is the catalogue's way of saying "not a thing you acquire":
	-- fists, and the outfit every character already starts in.
	for _, id in Weapons.ids() do
		local w = Weapons.get(id)
		if w.cost > 0 and w.requiredLevel <= itemLevel then
			table.insert(
				eligible,
				{ kind = "Weapon", slot = w.class, id = id, requiredLevel = w.requiredLevel }
			)
			best = math.max(best, w.requiredLevel)
		end
	end
	for _, id in Outfits.ids() do
		local o = Outfits.get(id)
		if o.cost > 0 and o.requiredLevel <= itemLevel then
			table.insert(
				eligible,
				{ kind = "Outfit", slot = "Outfit", id = id, requiredLevel = o.requiredLevel }
			)
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
	One item from the pool `level` opens up, with exactly `count` affixes and
	`sockets` holes.

	Nil when it would be indistinguishable from vendor stock -- no affixes and
	no sockets. That is the "every drop is rolled, or drilled" rule at the top,
	and it is the only place it is enforced.
]]
local function draw(rng: Random, level: number, count: number, sockets: number): Drop?
	local pool = gather(level)
	if #pool == 0 then
		return nil
	end
	local pick = pool[rng:NextInteger(1, #pool)]
	local rolls = Affixes.rollExactly(rng, pick.slot, level, count)
	local holes = math.clamp(math.floor(sockets), 0, Crystals.MAX_SOCKETS)
	if not rolls and holes <= 0 then
		return nil
	end
	return { kind = pick.kind, id = pick.id, rolls = rolls, sockets = holes }
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
	if rng:NextNumber() < CRYSTAL_SHARE then
		return { kind = "Crystal", id = Crystals.rollDrop(rng, level), rolls = nil, sockets = nil }
	end
	return draw(rng, level, Affixes.rollRarity(rng, level), Crystals.rollSockets(rng, level))
end

--[[
	A guaranteed drop of a chosen rarity. For DevService only.

	Skips both the drop-chance gate and the rarity weights, which is the only
	way to look at a Legendary without playing for a week.
]]
function Loot.forceDrop(rng: Random, itemLevel: number, affixCount: number, sockets: number?): Drop?
	return draw(rng, math.max(1, math.floor(itemLevel)), affixCount, sockets or 0)
end

--[[
	Re-rolls affixes that cannot do anything on the item carrying them.

	A migration, and the only one in the game. Until 2026-08-18 an affix's slot
	was just Weapon or Outfit, so a lightsaber could roll blaster damage: a real
	number, shown in the panel, counted toward the item's rarity, read by
	nothing. Fixing the roller stopped new ones being made and did nothing at
	all for the saves that already had them -- and "your Vicious Lightsaber is
	lying to you, sorry" is not a thing to tell a player who earned it.

	IT REPLACES, IT DOES NOT STRIP. Rarity is derived from how many affixes an
	item has, so deleting the dead ones would demote a Legendary to a Common and
	take away something that was won fairly, on the strength of a bug that was
	ours. Each dead stat becomes a live one drawn from the item's real pool, and
	the count -- so the rarity, the name and the sale price -- is unchanged.

	There is always room. The smallest pool is five (Melee, since
	`MeleeDamageMult` landed) against four affixes at most, and every stat that
	survives is one fewer to replace, so the pool can never run out mid-item and
	silently hand back a worse thing than it was given.

	Rolled at the item's `requiredLevel` because that is the only level the item
	itself carries -- what it dropped at was never stored. It errs low, which is
	the right direction for a rewrite nobody can audit: this must not be able to
	produce an item better than the one the player actually found.

	Returns how many stacks were changed. Safe to run on anything: a bag with no
	dead rolls is untouched, and an id no catalogue knows is left exactly alone
	rather than guessed at.
]]
function Loot.repair(rng: Random, inv: Inventory.Inventory): number
	local changed = 0

	for _, stack in inv do
		local rolls = stack.rolls
		if not rolls then
			continue
		end

		local slot, level
		if Weapons.exists(stack.id) then
			local w = Weapons.get(stack.id)
			slot, level = w.class, w.requiredLevel
		elseif Outfits.exists(stack.id) then
			slot, level = "Outfit", Outfits.get(stack.id).requiredLevel
		else
			continue
		end

		local legal = Affixes.statsForSlot(slot)

		local kept: { [string]: number } = {}
		local dead = 0
		for stat, value in rolls do
			if legal[stat] then
				kept[stat] = value
			else
				dead += 1
			end
		end
		if dead == 0 then
			continue
		end

		local fresh = Affixes.rollExactly(rng, slot, math.max(1, level), dead, kept)
		if fresh then
			for stat, value in fresh do
				kept[stat] = value
			end
		end
		stack.rolls = kept
		changed += 1
	end

	return changed
end

--- The dropped item's decorated name, for the pickup message.
function Loot.nameOf(drop: Drop): string
	if drop.kind == "Crystal" then
		return Crystals.get(drop.id).displayName
	end
	local base = if drop.kind == "Weapon"
		then Weapons.get(drop.id).displayName
		else Outfits.get(drop.id).displayName
	local name = Affixes.nameFor(base, drop.rolls)
	local holes = drop.sockets or 0
	return if holes > 0 then `{name} ({holes} socket{if holes == 1 then "" else "s"})` else name
end

--[[
	How good the drop is, as an affix count -- so the pickup toast, the panel's
	pips and the rarity colour all come from `Affixes.rarityAt` and cannot
	disagree.

	A crystal has no affixes; its grade *is* a rarity, which is why the grade
	ladder and the rarity ladder were made the same five steps rather than two
	parallel ideas the UI would then have to hold both of.
]]
function Loot.rarityOf(drop: Drop): number
	if drop.kind == "Crystal" then
		return Crystals.get(drop.id).rarity
	end
	return Affixes.rarityOf(drop.rolls).affixes
end

return Loot
