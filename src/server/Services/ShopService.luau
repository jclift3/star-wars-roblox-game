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
	id: string,
	displayName: string,
	description: string,
	tier: number,
	requiredLevel: number,
	price: number, -- what this player would actually pay, right now
	owned: boolean,
	equipped: boolean,
	forSale: boolean, -- stocked by the vendor the player is standing at
	stats: { { label: string, value: string } },
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

	local seenOutfit: { [string]: boolean } = {}
	local function addOutfit(id: string)
		if seenOutfit[id] or not Outfits.exists(id) then
			return
		end
		seenOutfit[id] = true
		local def = Outfits.get(id)
		table.insert(entries, {
			kind = "Outfit",
			id = id,
			displayName = def.displayName,
			description = def.description,
			tier = def.tier,
			requiredLevel = def.requiredLevel,
			price = progression().priceFor(player, def.cost * markup),
			owned = (profile.inventory[id] or 0) > 0 or id == Outfits.DEFAULT,
			equipped = profile.equipped.outfit == id,
			forSale = stockedOutfits[id] == true,
			stats = outfitStatLines(id),
		})
	end

	local seenWeapon: { [string]: boolean } = {}
	local function addWeapon(id: string)
		if seenWeapon[id] or not Weapons.exists(id) then
			return
		end
		seenWeapon[id] = true
		local def = Weapons.get(id)
		table.insert(entries, {
			kind = "Weapon",
			id = id,
			displayName = def.displayName,
			description = def.description,
			tier = def.tier,
			requiredLevel = def.requiredLevel,
			price = progression().priceFor(player, def.cost * markup),
			owned = (profile.inventory[id] or 0) > 0 or id == Weapons.DEFAULT,
			equipped = profile.equipped.weapon == id,
			forSale = stockedWeapons[id] == true,
			stats = weaponStatLines(def),
		})
	end

	-- Owned first, so the list is stable as you walk in and out of range of a
	-- vendor: the same things stay in the same order, with stock appended.
	addOutfit(Outfits.DEFAULT)
	for id in profile.inventory do
		addOutfit(id)
		addWeapon(id)
	end
	if shop then
		for _, id in shop.outfits do
			addOutfit(id)
		end
		for _, id in shop.weapons do
			addWeapon(id)
		end
	end

	table.sort(entries, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.displayName < b.displayName
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

	if (profile.inventory[id] or 0) > 0 then
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
		p.inventory[id] = (p.inventory[id] or 0) + 1
	end)

	notify(player, `Bought {displayName} for {price} cr`, "Success")
	return true, nil
end

--- Wears an owned outfit. Returns false and a reason the player can be shown.
function ShopService.equipOutfit(player: Player, id: string): (boolean, string?)
	if not Outfits.exists(id) then
		return false, "Unknown outfit"
	end
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	-- The starting outfit is always available, the same way fists always are.
	if id ~= Outfits.DEFAULT and (profile.inventory[id] or 0) < 1 then
		return false, "You do not own that"
	end
	if profile.equipped.outfit == id then
		return true, nil
	end

	data().update(player, function(p: PlayerProfile)
		p.equipped.outfit = id
	end)
	ServiceLoader.get("PlayerService").refreshOutfit(player)

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
