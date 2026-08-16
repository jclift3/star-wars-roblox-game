--!strict
--[[
	ShopService.luau

	Owns the wardrobe and the till: what a player owns, what they are wearing,
	and what the vendor in front of them will sell.

	INVENTORY ANYWHERE, PURCHASES AT A VENDOR
	Opening your bag and changing clothes works on any planet, in any field --
	being unable to swap loadout in the field is miserable on a world the size
	of Tatooine. Buying does not: it requires standing next to an NPC whose
	archetype declares a `shop`. That is what stops towns being scenery.

	THE CLIENT IS NEVER TRUSTED WITH A PRICE
	The client asks "what is in this shop" and gets prices back, but those are
	for display. `purchase` recomputes the price from config at the moment of
	sale and charges that. A client that lies about the cost is charged the
	real one; a client that lies about being near a vendor is refused, because
	proximity is measured here against the server's own NPC positions.
]]

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Inventory = require(Shared.Core.Inventory)
local Affixes = require(Shared.Config.Affixes)
local Outfits = require(Shared.Config.Outfits)
local Costumes = require(Shared.Config.Costumes)
local Shops = require(Shared.Config.Shops)
local Weapons = require(Shared.Config.Weapons)
local NPCArchetypes = require(Shared.Config.NPCArchetypes)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type PlayerProfile = Types.PlayerProfile

local ShopService = {
	name = "ShopService",
	priority = 35,
}

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

local function notify(player: Player, message: string, kind: string)
	Net.fireClient(Net.Event.Notify, player, message, kind)
end

--------------------------------------------------------------------------------
-- Vendors
--------------------------------------------------------------------------------

export type VendorInfo = {
	shopId: string,
	displayName: string,
	greeting: string,
	vendorName: string,
}

--[[
	The shop the player is standing next to, if any.

	Walks the live NPC folder rather than a registry of vendor positions,
	because vendors wander: the Vendor behaviour keeps them near their post but
	does not pin them to a coordinate. Reading the actual model means the range
	check is against where the NPC really is.
]]
local function vendorNear(player: Player): VendorInfo?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end

	local crowd = Workspace:FindFirstChild("NPCs")
	if not crowd then
		return nil
	end

	local best: VendorInfo? = nil
	local bestDistance = Shops.VENDOR_RANGE

	for _, model in crowd:GetDescendants() do
		if not model:IsA("Model") then
			continue
		end
		local archetypeId = model:GetAttribute("Archetype") :: string?
		if not archetypeId or not NPCArchetypes.exists(archetypeId) then
			continue
		end
		local shopId = NPCArchetypes.get(archetypeId).shop
		if not shopId or not Shops.exists(shopId) then
			continue
		end

		local npcRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not npcRoot or not humanoid or humanoid.Health <= 0 then
			continue -- a dead shopkeeper is not open for business
		end

		local distance = (npcRoot.Position - root.Position).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			local shop = Shops.get(shopId)
			best = {
				shopId = shopId,
				displayName = shop.displayName,
				greeting = shop.greeting,
				vendorName = model.Name,
			}
		end
	end

	return best
end

--------------------------------------------------------------------------------
-- Catalogue
--------------------------------------------------------------------------------

export type ItemEntry = {
	kind: string, -- "Outfit" | "Weapon"
	--[[
		The stack this row is, not the catalogue entry it came from.

		Rows are per stack, so two rolls of the same blaster are two rows and
		only one of them is worn. Everything that acts on a row -- equipping,
		comparing against `profile.equipped` -- keys off this. Shop stock the
		player does not own has no stack, and uses the catalogue id, which is
		exactly the uid it will have once bought.
	]]
	uid: string,
	id: string,
	displayName: string,
	description: string,
	tier: number,
	requiredLevel: number,
	price: number, -- what this player would actually pay, right now
	owned: boolean,
	equipped: boolean,
	forSale: boolean, -- stocked by the vendor the player is standing at
	-- Affix count, 0..4. The client turns it into a colour and a word.
	rarity: number,
	-- Already-formatted roll lines. Empty for anything Common.
	affixes: { string },
	stats: { { label: string, value: string } },
	--[[
		Really in the bag, as opposed to merely usable.

		`owned` is true for fists and the starting outfit, which nobody carries
		and so nobody can sell or throw away. This is the flag those two
		actions key off.
	]]
	carried: boolean,
	-- What the vendor in front of the player would pay. Zero away from a
	-- vendor, and zero for anything they will not take.
	sellValue: number,
}

--- Human-readable stat lines for an outfit, for the detail pane.
local function outfitStatLines(id: string): { { label: string, value: string } }
	local lines: { { label: string, value: string } } = {}
	for stat, value in Outfits.statsFor(id) do
		if stat == "DamageReduction" then
			table.insert(lines, { label = "Armour", value = `{math.floor(value * 100 + 0.5)}%` })
		elseif stat == "MoveSpeedMult" then
			local pct = math.floor(value * 100 + 0.5)
			table.insert(lines, { label = "Speed", value = `{if pct >= 0 then "+" else ""}{pct}%` })
		elseif stat == "PriceMult" then
			table.insert(lines, { label = "Prices", value = `{math.floor(value * 100 + 0.5)}%` })
		end
	end
	table.sort(lines, function(a, b)
		return a.label < b.label
	end)
	return lines
end

local function weaponStatLines(def: Weapons.WeaponDef): { { label: string, value: string } }
	return {
		{ label = "Damage", value = tostring(math.floor(def.damage + 0.5)) },
		{ label = "Rate", value = `{string.format("%.1f", def.fireRate)}/s` },
		{ label = "Range", value = tostring(math.floor(def.range + 0.5)) },
	}
end

--[[
	What the catalogue says one of these is worth, before anyone's markup.

	Nil for anything that is not a purchasable item, and zero is meaningful:
	fists and the starting outfit cost nothing because they are given, and a
	thing that was never bought is not worth selling either.
]]
local function baseCost(id: string): number?
	if Weapons.exists(id) then
		return Weapons.get(id).cost
	elseif Outfits.exists(id) then
		return Outfits.get(id).cost
	end
	return nil
end

--[[
	What to call one stack in a message.

	Falls back to the raw id rather than asserting, because the bag can hold
	things this file knows nothing about -- mission pickups are neither a
	weapon nor an outfit, and they are discardable like anything else.
]]
local function displayNameOf(stack: Inventory.ItemStack): string
	local base = stack.id
	if Weapons.exists(stack.id) then
		base = Weapons.get(stack.id).displayName
	elseif Outfits.exists(stack.id) then
		base = Outfits.get(stack.id).displayName
	end
	return Affixes.nameFor(base, stack.rolls)
end

--[[
	What the vendor in front of the player would pay for one stack.

	Rolls are paid for -- `RarityDef.value` -- because otherwise the only thing
	you could do with a Legendary you cannot use is throw it away, and a drop
	that is worth nothing is not a reward.

	Divided by the vendor's own `priceMult`, so the vendor who charges the most
	also offers the least. Away from a vendor this is zero, which is the flag
	the client reads to grey the button out.
]]
local function sellValue(stack: Inventory.ItemStack, shop: Shops.ShopDef?): number
	if not shop then
		return 0
	end
	local cost = baseCost(stack.id)
	if not cost or cost <= 0 then
		return 0
	end
	local each = cost * Affixes.rarityOf(stack.rolls).value * Shops.SELL_FRACTION / shop.priceMult
	return math.max(1, math.floor(each)) * stack.count
end

--[[
	Builds the list the client renders.

	Includes everything the player owns plus everything the vendor in front of
	them stocks, which is what makes one panel work as both an inventory and a
	shop. Away from a vendor the stocked half is simply empty.
]]
local function buildCatalogue(player: Player, profile: PlayerProfile, vendor: VendorInfo?): { ItemEntry }
	local shop = if vendor then Shops.get(vendor.shopId) else nil
	local entries: { ItemEntry } = {}

	local stockedOutfits: { [string]: boolean } = {}
	local stockedWeapons: { [string]: boolean } = {}
	if shop then
		for _, id in shop.outfits do
			stockedOutfits[id] = true
		end
		for _, id in shop.weapons do
			stockedWeapons[id] = true
		end
	end

	local markup = if shop then shop.priceMult else 1

	local inv = profile.inventory
	local seen: { [string]: boolean } = {}

	local function addOutfit(uid: string, id: string)
		if seen[uid] or not Outfits.exists(id) then
			return
		end
		seen[uid] = true
		local def = Outfits.get(id)
		local stack = inv[uid]
		local rolls = stack and stack.rolls
		table.insert(entries, {
			kind = "Outfit",
			uid = uid,
			id = id,
			displayName = Affixes.nameFor(def.displayName, rolls),
			description = def.description,
			tier = def.tier,
			requiredLevel = def.requiredLevel,
			price = progression().priceFor(player, def.cost * markup),
			owned = inv[uid] ~= nil or id == Outfits.DEFAULT,
			equipped = profile.equipped.outfit == uid,
			-- Only the plain stack is the thing on the shelf; a rolled one is
			-- the player's own and the vendor has never seen it.
			forSale = uid == id and stockedOutfits[id] == true,
			rarity = Affixes.rarityOf(rolls).affixes,
			affixes = Affixes.describe(rolls),
			stats = outfitStatLines(id),
			carried = stack ~= nil,
			sellValue = if stack then sellValue(stack, shop) else 0,
		})
	end

	local function addWeapon(uid: string, id: string)
		if seen[uid] or not Weapons.exists(id) then
			return
		end
		seen[uid] = true
		local def = Weapons.get(id)
		local stack = inv[uid]
		local rolls = stack and stack.rolls
		table.insert(entries, {
			kind = "Weapon",
			uid = uid,
			id = id,
			displayName = Affixes.nameFor(def.displayName, rolls),
			description = def.description,
			tier = def.tier,
			requiredLevel = def.requiredLevel,
			price = progression().priceFor(player, def.cost * markup),
			owned = inv[uid] ~= nil or id == Weapons.DEFAULT,
			equipped = profile.equipped.weapon == uid,
			forSale = uid == id and stockedWeapons[id] == true,
			rarity = Affixes.rarityOf(rolls).affixes,
			affixes = Affixes.describe(rolls),
			stats = weaponStatLines(def),
			carried = stack ~= nil,
			sellValue = if stack then sellValue(stack, shop) else 0,
		})
	end

	-- Owned first, so the list is stable as you walk in and out of range of a
	-- vendor: the same things stay in the same order, with stock appended.
	addOutfit(Outfits.DEFAULT, Outfits.DEFAULT)
	for _, stack in inv do
		addOutfit(stack.uid, stack.id)
		addWeapon(stack.uid, stack.id)
	end
	if shop then
		for _, id in shop.outfits do
			addOutfit(id, id)
		end
		for _, id in shop.weapons do
			addWeapon(id, id)
		end
	end

	table.sort(entries, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		if a.displayName ~= b.displayName then
			return a.displayName < b.displayName
		end
		-- Two rolls of one blaster share a name until they are decorated
		-- differently. The uid is the only thing guaranteed to differ, and the
		-- sort has to be a strict order or table.sort throws.
		return a.uid < b.uid
	end)

	return entries
end

--------------------------------------------------------------------------------
-- Transactions
--------------------------------------------------------------------------------

--- Buys one item. Returns false and a reason the player can be shown.
function ShopService.purchase(player: Player, kind: string, id: string): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local vendor = vendorNear(player)
	if not vendor then
		return false, "No vendor nearby"
	end
	local shop = Shops.get(vendor.shopId)

	local stocked = false
	-- Annotated because Luau types the if-expression as `{string} | {string}`
	-- and then refuses to iterate the union.
	local list: { string } = if kind == "Outfit" then shop.outfits else shop.weapons
	for _, stockId in list do
		if stockId == id then
			stocked = true
			break
		end
	end
	if not stocked then
		return false, `{shop.displayName} does not sell that`
	end

	local cost: number
	local requiredLevel: number
	local displayName: string
	if kind == "Outfit" then
		if not Outfits.exists(id) then
			return false, "Unknown item"
		end
		local def = Outfits.get(id)
		cost, requiredLevel, displayName = def.cost, def.requiredLevel, def.displayName
	elseif kind == "Weapon" then
		if not Weapons.exists(id) then
			return false, "Unknown item"
		end
		local def = Weapons.get(id)
		cost, requiredLevel, displayName = def.cost, def.requiredLevel, def.displayName
	else
		return false, "Unknown item"
	end

	-- Against the plain stack specifically, not the catalogue id: owning a
	-- rolled DH17 is no reason to be refused an ordinary one off the shelf.
	if profile.inventory[id] then
		return false, "You already own that"
	end
	if profile.level < requiredLevel then
		return false, `Requires level {requiredLevel}`
	end

	-- Recomputed from config, never taken from the client.
	local price = progression().priceFor(player, cost * shop.priceMult)
	if not progression().spendCredits(player, price) then
		return false, "Not enough credits"
	end

	data().update(player, function(p: PlayerProfile)
		Inventory.add(p.inventory, id, 1)
	end)

	notify(player, `Bought {displayName} for {price} cr`, "Success")
	return true, nil
end

--[[
	Wears an owned outfit. Returns false and a reason the player can be shown.

	Takes an inventory uid, so the player can pick out one particular rolled
	robe rather than the catalogue entry it was cut from.
]]
function ShopService.equipOutfit(player: Player, uid: string): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	local id = Inventory.idOf(profile.inventory, uid)
	if not id or not Outfits.exists(id) then
		return false, "Unknown outfit"
	end
	-- The starting outfit is always available, the same way fists always are.
	if uid ~= Outfits.DEFAULT and not profile.inventory[uid] then
		return false, "You do not own that"
	end
	if profile.equipped.outfit == uid then
		return true, nil
	end

	data().update(player, function(p: PlayerProfile)
		p.equipped.outfit = uid
	end)
	ServiceLoader.get("PlayerService").refreshOutfit(player)

	return true, nil
end

--[[
	The stack a sell or discard would act on, or a reason it cannot.

	Both actions refuse the same three things and for the same reasons, so the
	checks live together: what is not carried cannot leave the bag (fists and
	the starting outfit are `owned` without ever being in it), and what is worn
	cannot leave at all, because `profile.equipped` would go on naming a uid
	that no longer exists and the next respawn would hand the player nothing.
]]
local function removable(profile: PlayerProfile, uid: string): (Inventory.ItemStack?, string?)
	local stack = profile.inventory[uid]
	if not stack then
		return nil, "You are not carrying that"
	end
	if profile.equipped.outfit == uid or profile.equipped.weapon == uid then
		return nil, "Unequip it first"
	end
	return stack, nil
end

--[[
	Sells one stack to the vendor the player is standing at.

	The whole stack goes at once. A rolled item is a stack of one anyway, and
	those are what this exists for -- splitting a pile of five stimpacks would
	be a quantity widget in service of nothing.
]]
function ShopService.sell(player: Player, uid: string): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local vendor = vendorNear(player)
	if not vendor then
		return false, "No vendor nearby"
	end

	local stack, reason = removable(profile, uid)
	if not stack then
		return false, reason
	end

	-- Recomputed here rather than trusted from the row the client clicked,
	-- for the same reason `purchase` recomputes the price.
	local value = sellValue(stack, Shops.get(vendor.shopId))
	if value <= 0 then
		return false, `{vendor.displayName} will not take that`
	end

	local name = displayNameOf(stack)

	-- Taken before it is paid for. If the write somehow failed after the
	-- credits landed the player would have both, which is the one direction
	-- this must never fail in.
	data().update(player, function(p: PlayerProfile)
		Inventory.take(p.inventory, uid)
	end)
	-- Raw: the Scavenger multiplier is for what the world gives you, and the
	-- vendor spread is already the whole economics of a sale.
	progression().awardCredits(player, value, true)

	notify(player, `Sold {name} for {value} cr`, "Success")
	return true, nil
end

--[[
	Throws one stack away. No vendor, no payment, no undo.

	The bag is capped (see `Inventory.MAX_ROLLED`) and vendors are in towns, so
	without this a full bag miles from anywhere means no more drops until you
	walk home. The client asks twice before calling it.
]]
function ShopService.discard(player: Player, uid: string): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local stack, reason = removable(profile, uid)
	if not stack then
		return false, reason
	end

	local name = displayNameOf(stack)

	data().update(player, function(p: PlayerProfile)
		Inventory.take(p.inventory, uid)
	end)

	notify(player, `Discarded {name}`, "Info")
	return true, nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ShopService.init()
	Net.onServerInvoke(Net.Function.GetInventory, function(player: Player)
		local profile = data().get(player)
		if not profile then
			return nil
		end
		local vendor = vendorNear(player)
		return {
			credits = profile.credits,
			level = profile.level,
			equippedOutfit = profile.equipped.outfit,
			equippedWeapon = profile.equipped.weapon,
			vendor = vendor,
			-- How full the bag is. Only rolled items count against it; see
			-- Inventory.MAX_ROLLED for why the rest need no ceiling.
			rolled = Inventory.rolled(profile.inventory),
			maxRolled = Inventory.MAX_ROLLED,
			items = buildCatalogue(player, profile, vendor),
		}
	end, {
		rateLimit = 4,
		validate = Net.check.none,
	})

	Net.onServerEvent(Net.Event.PurchaseItem, function(player: Player, kind: string, id: string)
		local ok, reason = ShopService.purchase(player, kind, id)
		if not ok and reason then
			notify(player, reason, "Error")
		end
	end, {
		rateLimit = 4,
		validate = Net.args(Net.check.oneOf({ "Outfit", "Weapon" }), Net.check.string(64)),
	})

	Net.onServerEvent(Net.Event.EquipOutfit, function(player: Player, id: string)
		local ok, reason = ShopService.equipOutfit(player, id)
		if not ok and reason then
			notify(player, reason, "Error")
		end
	end, {
		rateLimit = 4,
		validate = Net.args(Net.check.string(64)),
	})

	Net.onServerEvent(Net.Event.SellItem, function(player: Player, uid: string)
		local ok, reason = ShopService.sell(player, uid)
		if not ok and reason then
			notify(player, reason, "Error")
		end
	end, {
		rateLimit = 4,
		validate = Net.args(Net.check.string(64)),
	})

	Net.onServerEvent(Net.Event.DiscardItem, function(player: Player, uid: string)
		local ok, reason = ShopService.discard(player, uid)
		if not ok and reason then
			notify(player, reason, "Error")
		end
	end, {
		rateLimit = 4,
		validate = Net.args(Net.check.string(64)),
	})
end

function ShopService.start()
	-- Config errors surface at boot rather than at the moment of sale.
	for _, problem in Shops.validate(Outfits.exists, Weapons.exists) do
		warn(`[ShopService] {problem}`)
	end
	for _, problem in Outfits.validate(Costumes.exists) do
		warn(`[ShopService] {problem}`)
	end
end

return ShopService
