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
local Crystals = require(Shared.Config.Crystals)
local Outfits = require(Shared.Config.Outfits)
local Costumes = require(Shared.Config.Costumes)
local Furnishings = require(Shared.Config.Furnishings)
local Items = require(Shared.Config.Items)
local Races = require(Shared.Config.Races)
local Shops = require(Shared.Config.Shops)
local Ships = require(Shared.Config.Ships)
local Upgrades = require(Shared.Config.Upgrades)
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

local function analytics()
	return ServiceLoader.get("AnalyticsService")
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
	kind: string, -- "Outfit" | "Weapon" | "Vehicle" | "Furnishing" | "Crystal" | "Pass" | "Upgrade"
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
	stats: { StatLine },
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
	--[[
		Crystal holes and what is in them. Zero and empty for everything that
		is not a weapon or an outfit.

		`socketed` is sent as the map it is stored as -- index-as-string ->
		crystal id -- rather than flattened into a list, because a list with a
		gap in it does not survive replication and socket 2 can be full while
		socket 1 is empty.
	]]
	sockets: number,
	socketed: { [string]: string },
	--[[
		Which affix slot this row *is*: a weapon's class, or "Outfit".

		Sent because a crystal's effect depends on it and the client cannot
		work it out from `kind` -- Weapon covers three different pools. Empty
		for rows that cannot be socketed.
	]]
	slot: string,
	-- What emptying each filled socket would cost at this vendor, keyed the
	-- same way `socketed` is. Empty away from a vendor, which is the flag the
	-- client hides the button on.
	extractCosts: { [string]: number },
}

--[[
	One line of the detail pane.

	`value` is the whole answer on its own, with its units and its sign, and
	the client prints it verbatim. `raw` and `max` are the same fact again as
	bare numbers, so the panel can draw a bar of length `raw / max` and an
	arrow against whatever is equipped, without having to parse "1.4/s" back
	into 1.4. Both are absent together, and a line with neither is text only --
	which is the right answer for a ship's seat count and for a loose crystal,
	where "out of the best in the game" is not a question anyone is asking.
]]
type StatLine = {
	label: string,
	value: string,
	raw: number?,
	max: number?,
}

--- Human-readable stat lines for an outfit, for the detail pane.
local function outfitStatLines(id: string): { StatLine }
	local lines: { StatLine } = {}
	local maxima = Outfits.maxima()
	for stat, value in Outfits.statsFor(id) do
		if stat == "DamageReduction" then
			table.insert(lines, {
				label = "Armour",
				value = `{math.floor(value * 100 + 0.5)}%`,
				raw = value,
				max = maxima[stat],
			})
		elseif stat == "MoveSpeedMult" then
			local pct = math.floor(value * 100 + 0.5)
			table.insert(lines, {
				label = "Speed",
				value = `{if pct >= 0 then "+" else ""}{pct}%`,
				raw = value,
				max = maxima[stat],
			})
		elseif stat == "PriceMult" then
			table.insert(lines, {
				label = "Prices",
				value = `{math.floor(value * 100 + 0.5)}%`,
				raw = value,
				max = maxima[stat],
			})
		end
	end
	table.sort(lines, function(a, b)
		return a.label < b.label
	end)
	return lines
end

local function weaponStatLines(def: Weapons.WeaponDef): { StatLine }
	local maxima = Weapons.maxima()
	return {
		{
			label = "Damage",
			value = tostring(math.floor(def.damage + 0.5)),
			raw = def.damage,
			max = maxima.damage,
		},
		{
			label = "Rate",
			value = `{string.format("%.1f", def.fireRate)}/s`,
			raw = def.fireRate,
			max = maxima.fireRate,
		},
		{
			label = "Range",
			value = tostring(math.floor(def.range + 0.5)),
			raw = def.range,
			max = maxima.range,
		},
	}
end

--[[
	Speed as a multiple of running, not as a raw number.

	"205 studs/sec" means nothing to anyone. "6.4x on foot" is the only
	question the player is actually asking, and it stays true if the base
	character speed is ever retuned.
]]
local RUNNING_SPEED = 32

local function shipStatLines(def: Ships.ShipDef): { StatLine }
	return {
		{ label = "Speed", value = `{string.format("%.1f", def.speed / RUNNING_SPEED)}x on foot` },
		{ label = "Handling", value = `{math.floor(def.turnSpeed + 0.5)} deg/s` },
		{ label = "Seats", value = tostring(1 + #def.passengerOffsets) },
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
	elseif Crystals.exists(id) then
		return Crystals.get(id).cost
	end
	return nil
end

--[[
	Which affix pool an item draws from -- a weapon's own class, or "Outfit".

	The one thing a crystal has to be asked alongside its id, because a crimson
	crystal is damage in a blaster and armour in a robe. Empty for anything
	that has no sockets to begin with.
]]
local function slotOf(id: string?): string
	if not id then
		return ""
	elseif Weapons.exists(id) then
		return Weapons.get(id).class
	elseif Outfits.exists(id) then
		return "Outfit"
	end
	return ""
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
	elseif Crystals.exists(stack.id) then
		-- A crystal's grade is already in its display name and it has no
		-- affixes, so it must not go through `nameFor`.
		return Crystals.get(stack.id).displayName
	end
	return Affixes.nameFor(base, stack.rolls)
end

--[[
	What this vendor charges to pull one crystal back out.

	Multiplied by the vendor's markup rather than divided by it -- this is the
	player buying a service, not selling goods, so the expensive trader is
	expensive here too. Zero away from a vendor: socketing is free and can be
	done anywhere, and changing your mind is the part that costs, which is the
	whole reason the decision is worth making carefully.
]]
local function extractCost(crystalId: string, shop: Shops.ShopDef?): number
	if not shop or not Crystals.exists(crystalId) then
		return 0
	end
	return math.max(1, math.floor(Crystals.get(crystalId).cost * Shops.EXTRACT_FRACTION * shop.priceMult))
end

--- What each filled socket would cost to empty, keyed the same way it is stored.
local function extractCosts(socketed: { [string]: string }?, shop: Shops.ShopDef?): { [string]: number }
	local out: { [string]: number } = {}
	if not socketed then
		return out
	end
	for index, crystalId in socketed do
		out[index] = extractCost(crystalId, shop)
	end
	return out
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
	The hull this vendor would bolt a part onto, if there is one.

	Derived rather than declared. A counter that sells hulls of your ship's
	class is a counter with the tools to modify one, so `ShopDef` gains no
	`upgrades` field and a vendor's stock cannot drift out of step with its
	services -- the same argument `Radiant` makes for composing missions out
	of the district instead of listing them.

	Nil, and so no parts anywhere, if the player has no ship equipped, does
	not actually own the one they have equipped, or is standing at a counter
	that deals in the other class. That last one is the interesting case: a
	speeder lot cannot fit a starship engine, which is why the Ship Yard is
	the only place a Dagger gets touched.
]]
local function fittableHull(profile: PlayerProfile, shop: Shops.ShopDef?): string?
	local hull = profile.equipped.ship
	if not shop or not hull or not Ships.exists(hull) then
		return nil
	end
	if not table.find(profile.unlockedShips, hull) then
		return nil
	end
	local class = Ships.get(hull).class
	for _, id in shop.ships do
		if Ships.exists(id) and Ships.get(id).class == class then
			return hull
		end
	end
	return nil
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
			sockets = if stack then (stack.sockets or 0) else 0,
			socketed = (stack and stack.socketed) or {},
			slot = "Outfit",
			extractCosts = extractCosts(stack and stack.socketed, shop),
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
			sockets = if stack then (stack.sockets or 0) else 0,
			socketed = (stack and stack.socketed) or {},
			slot = def.class,
			extractCosts = extractCosts(stack and stack.socketed, shop),
		})
	end

	--[[
		A vehicle is never a stack, so this row is much simpler than the two
		above it: no uid, no rolls, no rarity, nothing to sell back. The uid
		field is the ship id, which is what every other row's uid would be if
		it had never been rolled on.
	]]
	local stockedShips: { [string]: boolean } = {}
	if shop then
		for _, id in shop.ships do
			stockedShips[id] = true
		end
	end

	local function addShip(id: string)
		if seen[id] or not Ships.exists(id) then
			return
		end
		seen[id] = true
		local def = Ships.get(id)
		table.insert(entries, {
			kind = "Vehicle",
			uid = id,
			id = id,
			displayName = def.displayName,
			description = def.description,
			tier = def.tier,
			requiredLevel = def.requiredLevel,
			price = progression().priceFor(player, def.cost * markup),
			owned = table.find(profile.unlockedShips, id) ~= nil,
			equipped = profile.equipped.ship == id,
			forSale = stockedShips[id] == true,
			rarity = 0,
			affixes = {},
			stats = shipStatLines(def),
			carried = false,
			sellValue = 0,
			sockets = 0,
			socketed = {},
			slot = "",
			extractCosts = {},
		})
	end

	--[[
		A furnishing is a vehicle-shaped row: owned or not, no stack, nothing
		to sell back. `equipped` is doing real work here and means "standing
		in the cabin right now", which is the one bit of state the panel
		needs to draw a Place button that reads correctly.
	]]
	local stockedFurnishings: { [string]: boolean } = {}
	if shop then
		for _, id in shop.furnishings do
			stockedFurnishings[id] = true
		end
	end

	local function addFurnishing(id: string)
		if seen[id] or not Furnishings.exists(id) then
			return
		end
		seen[id] = true
		local def = Furnishings.get(id)
		-- Furnishings carry no tier of their own; the level gate is the only
		-- progression they have. Banded into the same 1-3 the rest of the
		-- catalogue uses, so a row reads "Tier 2" rather than "Tier 12" and
		-- the panel's tier sort still lists a slot's three pieces in the
		-- order a player would buy them.
		local tier = if def.requiredLevel <= 5 then 1 elseif def.requiredLevel <= 15 then 2 else 3
		table.insert(entries, {
			kind = "Furnishing",
			uid = id,
			id = id,
			displayName = def.displayName,
			description = def.description,
			tier = tier,
			requiredLevel = def.requiredLevel,
			price = progression().priceFor(player, def.cost * markup),
			owned = table.find(profile.unlockedFurnishings, id) ~= nil,
			equipped = profile.cabin[def.slot] == id,
			forSale = stockedFurnishings[id] == true,
			rarity = 0,
			affixes = {},
			stats = { { label = "Fitting", value = def.slot } },
			carried = false,
			sellValue = 0,
			sockets = 0,
			socketed = {},
			slot = "",
			extractCosts = {},
		})
	end

	--[[
		A crystal row is a stack the player is carrying and nothing else: no
		vendor stocks them, so the only way to have one is to have killed
		something for it.

		`stats` is what it would do in each kind of item, which is the only
		question worth asking about a loose crystal -- it has no effect at all
		until it is in something, and which of the four lines matters depends
		on what the player socketed it into.
	]]
	local function addCrystal(uid: string, id: string)
		if seen[uid] or not Crystals.exists(id) then
			return
		end
		seen[uid] = true
		local def = Crystals.get(id)
		local stack = inv[uid]

		local lines: { StatLine } = {}
		for _, itemSlot in Affixes.ITEM_SLOTS do
			for _, line in Affixes.describe(Crystals.statsFor(id, itemSlot)) do
				table.insert(lines, { label = itemSlot, value = line })
			end
		end

		table.insert(entries, {
			kind = "Crystal",
			uid = uid,
			id = id,
			displayName = def.displayName,
			description = def.description,
			-- Grade stands in for tier, so the list runs Chipped to Perfect.
			tier = def.rarity + 1,
			requiredLevel = 1,
			price = 0,
			owned = stack ~= nil,
			equipped = false,
			forSale = false,
			rarity = def.rarity,
			affixes = {},
			stats = lines,
			carried = stack ~= nil,
			sellValue = if stack then sellValue(stack, shop) else 0,
			sockets = 0,
			socketed = {},
			slot = "",
			extractCosts = {},
		})
	end

	--[[
		A pass row exists so that having passes is a thing the player can
		find out without being at a start line and broke.

		Nothing else in the panel is spent somewhere other than the panel,
		which is why it needs its own row rather than sharing one: the whole
		description of a pass is where to go and what it saves you, and there
		is nowhere else to say it. No vendor stocks them, so `forSale` is
		false always and this row can only ever come from the bag.
	]]
	local function addPass(uid: string, id: string)
		if seen[uid] or id ~= Races.PASS_ITEM then
			return
		end
		seen[uid] = true
		local stack = inv[uid]
		table.insert(entries, {
			kind = "Pass",
			uid = uid,
			id = id,
			displayName = Items.nameOf(id),
			description = `Entry to one race, in place of the {Races.ENTRY_FEE} credit fee. Spent automatically when you drive through a start gantry.`,
			tier = 1,
			requiredLevel = 1,
			price = 0,
			owned = stack ~= nil,
			equipped = false,
			forSale = false,
			rarity = 1,
			affixes = {},
			stats = {
				{ label = "Held", value = tostring(if stack then stack.count else 0) },
				{ label = "Worth", value = `{Races.ENTRY_FEE} cr` },
			},
			carried = stack ~= nil,
			-- Not sellable. A pass you can turn into credits is credits, and
			-- the point of it is being the thing you still have when you have
			-- no credits at all.
			sellValue = 0,
			sockets = 0,
			socketed = {},
			slot = "",
			extractCosts = {},
		})
	end

	--[[
		A part row is priced and described against one particular hull.

		Which is what makes it different from every other row in this file:
		"Engine Mk III" is not a thing with a price, it is a thing that costs
		1,700 credits on a Swoop and 21,250 on a Dagger, and takes that
		Swoop from 205 to 242. So the row is only built at all when there is
		a hull to build it against, and it says the resulting number rather
		than the percentage alone -- a percentage of a number the player
		cannot see is not information.

		All fifteen are listed rather than only the next grade up, because
		the reason to show the ladder is so that somebody can decide to skip
		four rungs and save for the top one.
	]]
	local function addUpgrades(hull: string)
		local def = Ships.get(hull)
		local fitted = profile.shipParts[hull]
		for _, id in Upgrades.ids() do
			if seen[id] then
				continue
			end
			seen[id] = true
			local part = Upgrades.get(id)
			local from = (def :: any)[part.slot.field] :: number
			local to = from * (1 + part.grade.gain)

			local lines: { StatLine } = {
				{ label = part.slot.displayName, value = `+{math.floor(part.grade.gain * 100 + 0.5)}%` },
				{
					label = def.displayName,
					value = `{math.floor(from + 0.5)} → {math.floor(to + 0.5)}`,
				},
			}
			-- The only warning the player gets that buying this throws away
			-- what is in the slot, for nothing back. `Shops.EXTRACT_FRACTION`
			-- makes the same call about crystals; undoing a decision costs.
			local current = fitted and fitted[part.slot.id]
			if current and Upgrades.exists(current) and current ~= id then
				table.insert(lines, { label = "Replaces", value = Upgrades.get(current).displayName })
			end

			table.insert(entries, {
				kind = "Upgrade",
				uid = id,
				id = id,
				displayName = part.displayName,
				description = part.description,
				-- Grade stands in for tier, exactly as it does for crystals,
				-- so the list runs Mk I to Mk V under each slot's name.
				tier = part.rarity + 1,
				-- The hull's own gate, which the player has already cleared by
				-- owning it. A part has no level of its own and inventing one
				-- would be a second number to keep in step with the first.
				requiredLevel = def.requiredLevel,
				price = progression().priceFor(player, Upgrades.cost(hull, id) * markup),
				owned = current == id,
				equipped = current == id,
				forSale = true,
				rarity = part.rarity,
				affixes = {},
				stats = lines,
				carried = false,
				sellValue = 0,
				sockets = 0,
				socketed = {},
				slot = "",
				extractCosts = {},
			})
		end
	end

	-- Owned first, so the list is stable as you walk in and out of range of a
	-- vendor: the same things stay in the same order, with stock appended.
	addOutfit(Outfits.DEFAULT, Outfits.DEFAULT)
	for _, stack in inv do
		addOutfit(stack.uid, stack.id)
		addWeapon(stack.uid, stack.id)
		addCrystal(stack.uid, stack.id)
		addPass(stack.uid, stack.id)
	end
	for _, id in profile.unlockedShips do
		addShip(id)
	end
	for _, id in profile.unlockedFurnishings do
		addFurnishing(id)
	end
	if shop then
		for _, id in shop.outfits do
			addOutfit(id, id)
		end
		for _, id in shop.weapons do
			addWeapon(id, id)
		end
		for _, id in shop.ships do
			addShip(id)
		end
		for _, id in shop.furnishings do
			addFurnishing(id)
		end
		local hull = fittableHull(profile, shop)
		if hull then
			addUpgrades(hull)
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

	--[[
		Parts are stocked by a rule rather than by a list, so they leave
		before the `list` check below rather than pretending to be in one.

		Everything here has to be re-derived server-side: which hull is
		equipped, whether this counter can touch that class, and what the
		part costs on it. The client sends two strings and neither of them is
		a price.
	]]
	if kind == "Upgrade" then
		local hull = fittableHull(profile, shop)
		if not hull then
			return false, `{shop.displayName} does not work on your ship`
		end
		if not Upgrades.exists(id) then
			return false, "Unknown item"
		end
		local part = Upgrades.get(id)
		if (profile.shipParts[hull] or {})[part.slot.id] == id then
			return false, "That is already fitted"
		end

		local price = progression().priceFor(player, Upgrades.cost(hull, id) * shop.priceMult)
		if not progression().spendCredits(player, price) then
			return false, "Not enough credits"
		end

		data().update(player, function(p: PlayerProfile)
			local into = p.shipParts[hull]
			if not into then
				into = {}
				p.shipParts[hull] = into
			end
			-- Replaces outright. There is no loose part and nothing comes
			-- back; see Config/Upgrades.luau on why fitting is buying.
			into[part.slot.id] = id
		end)

		local hullName = Ships.get(hull).displayName
		notify(player, `Fitted {part.displayName} to your {hullName} for {price} cr`, "Success")
		local fitTelemetry = analytics()
		fitTelemetry.log(player, fitTelemetry.Kind.Purchase, {
			kind = kind,
			item = id,
			price = price,
			shop = shop.id,
		})
		return true, nil
	end

	-- Annotated because Luau types the if-expression as `{string} | {string}`
	-- and then refuses to iterate the union.
	local list: { string }
	if kind == "Outfit" then
		list = shop.outfits
	elseif kind == "Weapon" then
		list = shop.weapons
	elseif kind == "Furnishing" then
		list = shop.furnishings
	else
		list = shop.ships
	end

	local stocked = false
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
	local alreadyOwned: boolean
	if kind == "Outfit" then
		if not Outfits.exists(id) then
			return false, "Unknown item"
		end
		local def = Outfits.get(id)
		cost, requiredLevel, displayName = def.cost, def.requiredLevel, def.displayName
		-- Against the plain stack specifically, not the catalogue id: owning
		-- a rolled robe is no reason to be refused an ordinary one.
		alreadyOwned = profile.inventory[id] ~= nil
	elseif kind == "Weapon" then
		if not Weapons.exists(id) then
			return false, "Unknown item"
		end
		local def = Weapons.get(id)
		cost, requiredLevel, displayName = def.cost, def.requiredLevel, def.displayName
		alreadyOwned = profile.inventory[id] ~= nil
	elseif kind == "Vehicle" then
		if not Ships.exists(id) then
			return false, "Unknown item"
		end
		local def = Ships.get(id)
		cost, requiredLevel, displayName = def.cost, def.requiredLevel, def.displayName
		-- Vehicles live in `unlockedShips`, not the bag, and there is nothing
		-- a second copy of one could ever be for.
		alreadyOwned = table.find(profile.unlockedShips, id) ~= nil
	elseif kind == "Furnishing" then
		if not Furnishings.exists(id) then
			return false, "Unknown item"
		end
		local def = Furnishings.get(id)
		cost, requiredLevel, displayName = def.cost, def.requiredLevel, def.displayName
		alreadyOwned = table.find(profile.unlockedFurnishings, id) ~= nil
	else
		return false, "Unknown item"
	end

	if alreadyOwned then
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

	if kind == "Vehicle" then
		ServiceLoader.get("VehicleService").grant(player, id)
	elseif kind == "Furnishing" then
		ServiceLoader.get("InteriorService").grant(player, id)
	else
		data().update(player, function(p: PlayerProfile)
			Inventory.add(p.inventory, id, 1)
		end)
	end

	notify(player, `Bought {displayName} for {price} cr`, "Success")

	-- `price` rather than `cost`: what was actually paid, after the shop's
	-- multiplier and the player's Bargaining. The list price is in config and
	-- can be joined back to; what a given player was charged cannot.
	local telemetry = analytics()
	telemetry.log(player, telemetry.Kind.Purchase, {
		kind = kind,
		item = id,
		price = price,
		shop = shop.id,
	})
	return true, nil
end

--[[
	Chooses which owned vehicle the summon key calls in.

	Takes a ship id rather than a uid, because a vehicle is never a stack --
	see the note on `unlockedShips` in Types.luau. Selecting one does not
	summon it: the two are separate on purpose, so changing your mind in the
	inventory panel does not drop a landspeeder on the shopkeeper.
]]
function ShopService.equipShip(player: Player, id: string): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	if not Ships.exists(id) then
		return false, "Unknown vehicle"
	end
	if not table.find(profile.unlockedShips, id) then
		return false, "You do not own that"
	end
	if profile.equipped.ship == id then
		return true, nil
	end

	data().update(player, function(p: PlayerProfile)
		p.equipped.ship = id
	end)
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

--------------------------------------------------------------------------------
-- Crystals
--------------------------------------------------------------------------------

--[[
	Puts one carried crystal into one hole. Free, and works anywhere.

	Deliberately not a vendor action. Fitting a stone is the decision the whole
	system exists to offer, and gating it behind walking back to town would
	mean the interesting half of a drop cannot be enjoyed where the drop
	happened. Taking one back out is what costs -- see `unsocket`.
]]
function ShopService.socket(player: Player, uid: string, index: number, crystalId: string): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	if not Crystals.exists(crystalId) then
		return false, "Unknown crystal"
	end

	local stack = profile.inventory[uid]
	if not stack then
		return false, "You are not carrying that"
	end
	local slot = slotOf(stack.id)
	if slot == "" then
		return false, "Nothing can be socketed into that"
	end
	index = math.floor(index)
	if index < 1 or index > (stack.sockets or 0) then
		return false, "No such socket"
	end
	if stack.socketed and stack.socketed[tostring(index)] then
		return false, "That socket is already filled"
	end
	if not Inventory.has(profile.inventory, crystalId) then
		return false, "You do not have that crystal"
	end

	--[[
		Taken out of the bag first, and the socket only filled against what
		actually came out. `Inventory.remove` returns how many it really got,
		which is the one number worth trusting -- paying out against the
		request instead is how a player fills three sockets from one stone.
	]]
	local placed = false
	data().update(player, function(p: PlayerProfile)
		if Inventory.remove(p.inventory, crystalId, 1) < 1 then
			return
		end
		placed = Inventory.socket(p.inventory, uid, index, crystalId)
		if not placed then
			-- Put it back rather than eat it. This can only happen if the two
			-- reads above raced, but the failure mode is a destroyed crystal.
			Inventory.add(p.inventory, crystalId, 1)
		end
	end)
	if not placed then
		return false, "Could not fit that crystal"
	end

	-- Sockets on a worn item change the folded stat table, so the cache the
	-- player is being hit with has to go. Weapons too: they carry stats now.
	if profile.equipped.outfit == uid or profile.equipped.weapon == uid then
		progression().invalidate(player)
		if profile.equipped.outfit == uid then
			ServiceLoader.get("PlayerService").refreshOutfit(player)
		else
			-- Rebuilt so the blade is the new colour before the player has
			-- finished closing the panel. The stat change alone would be
			-- invisible until they next died.
			ServiceLoader.get("CombatService").refreshWeapon(player)
		end
	end

	notify(player, `Fitted {Crystals.get(crystalId).displayName}`, "Success")
	return true, nil
end

--[[
	Pulls one crystal back out. Costs credits, at a vendor, and destroys it.

	Diablo's own rule, and it is the right one twice over: it makes fitting a
	stone a real decision rather than a thing you shuffle for free, and it is
	the only sink in the economy at the top end -- past about level 30 there is
	nothing left in the catalogue to want and credits simply pile up.

	The hole stays. What is bought here is the removal, not the socket.
]]
function ShopService.unsocket(player: Player, uid: string, index: number): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local vendor = vendorNear(player)
	if not vendor then
		return false, "No vendor nearby"
	end
	local shop = Shops.get(vendor.shopId)

	local stack = profile.inventory[uid]
	if not stack then
		return false, "You are not carrying that"
	end
	index = math.floor(index)
	local crystalId = stack.socketed and stack.socketed[tostring(index)]
	if not crystalId then
		return false, "That socket is empty"
	end

	-- Recomputed from config at the moment of sale, never taken from the row
	-- the client clicked -- the same rule `purchase` and `sell` follow.
	local price = extractCost(crystalId, shop)
	if not progression().spendCredits(player, price) then
		return false, `Removing that costs {price} cr`
	end

	local removed: string? = nil
	data().update(player, function(p: PlayerProfile)
		removed = Inventory.unsocket(p.inventory, uid, index)
	end)

	if profile.equipped.outfit == uid or profile.equipped.weapon == uid then
		progression().invalidate(player)
		if profile.equipped.outfit == uid then
			ServiceLoader.get("PlayerService").refreshOutfit(player)
		else
			-- Rebuilt so the blade is the new colour before the player has
			-- finished closing the panel. The stat change alone would be
			-- invisible until they next died.
			ServiceLoader.get("CombatService").refreshWeapon(player)
		end
	end

	local name = if removed then Crystals.get(removed).displayName else "the crystal"
	notify(player, `Cut {name} out for {price} cr. It did not survive.`, "Info")
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

	The bag is capped (see `Inventory.MAX_UNIQUE`) and vendors are in towns, so
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
			equippedShip = profile.equipped.ship,
			vendor = vendor,
			-- How full the bag is. Only unmergeable items count against it; see
			-- Inventory.MAX_UNIQUE for why the rest need no ceiling.
			rolled = Inventory.unique(profile.inventory),
			maxRolled = Inventory.MAX_UNIQUE,
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
		validate = Net.args(
			Net.check.oneOf({ "Outfit", "Weapon", "Vehicle", "Furnishing", "Upgrade" }),
			Net.check.string(64)
		),
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

	Net.onServerEvent(Net.Event.EquipShip, function(player: Player, id: string)
		local ok, reason = ShopService.equipShip(player, id)
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

	--[[
		The socket index is bounded here as well as in the transaction.

		`Crystals.MAX_SOCKETS` is the most holes anything can ever have, so a
		message naming socket 900 is a client that has been edited and there is
		no reason to let it reach the profile at all. The transaction still
		checks the index against *this* item's hole count -- this bound is the
		cheap one, not the real one.
	]]
	Net.onServerEvent(
		Net.Event.SocketCrystal,
		function(player: Player, uid: string, index: number, crystalId: string)
			local ok, reason = ShopService.socket(player, uid, index, crystalId)
			if not ok and reason then
				notify(player, reason, "Error")
			end
		end,
		{
			rateLimit = 4,
			validate = Net.args(
				Net.check.string(64),
				Net.check.integer(1, Crystals.MAX_SOCKETS),
				Net.check.string(64)
			),
		}
	)

	Net.onServerEvent(Net.Event.UnsocketCrystal, function(player: Player, uid: string, index: number)
		local ok, reason = ShopService.unsocket(player, uid, index)
		if not ok and reason then
			notify(player, reason, "Error")
		end
	end, {
		rateLimit = 4,
		validate = Net.args(Net.check.string(64), Net.check.integer(1, Crystals.MAX_SOCKETS)),
	})
end

function ShopService.start()
	-- Config errors surface at boot rather than at the moment of sale.
	for _, problem in Shops.validate(Outfits.exists, Weapons.exists, Ships.exists, Furnishings.exists) do
		warn(`[ShopService] {problem}`)
	end
	for _, problem in Outfits.validate(Costumes.exists) do
		warn(`[ShopService] {problem}`)
	end
end

return ShopService
