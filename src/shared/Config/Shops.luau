--!strict
--[[
	Shops.luau

	What each kind of vendor has on the shelf.

	Stock is listed explicitly rather than derived from a tier range, because
	the interesting thing about a vendor is what they *don't* carry. A Jawa
	selling you Death Trooper plate would be absurd, and a rule like "tier <= 2"
	has no way to express that. Explicit lists are longer and worth it.

	`priceMult` is the vendor's own markup, applied before the player's Bargaining
	skill. A Jawa is cheap because everything they sell fell off something.

	Vendors are attached to NPCs through `NPCArchetypes.shop`, so placing a shop
	in the world means spawning the archetype that owns it -- there is no
	separate shop-placement system to keep in sync.
]]

local Shops = {}

export type ShopDef = {
	id: string,
	displayName: string,
	greeting: string,
	priceMult: number,
	outfits: { string }, -- Outfits ids
	weapons: { string }, -- Weapons ids
}

local defs: { [string]: ShopDef } = {}

local function def(s: ShopDef): ShopDef
	defs[s.id] = s
	return s
end

def({
	id = "GeneralGoods",
	displayName = "General Goods",
	greeting = "Everything an honest spacer needs. And a few things they don't.",
	priceMult = 1,
	outfits = {
		"Civilian",
		"MoistureFarmer",
		"Smuggler",
		"Merchant",
		"RebelTrooper",
		"RebelPilot",
		"NabooGuard",
		"Stormtrooper",
		"ImperialOfficer",
	},
	weapons = {
		"DH17",
		"SE14C",
		"DL44",
		"E11",
		"E5",
		"VibroBlade",
	},
})

def({
	id = "JawaScrap",
	displayName = "Jawa Salvage",
	greeting = "Utinni! Very good price. Mostly works.",
	-- Cheap because it is all scavenged, and the selection shows it.
	priceMult = 0.8,
	outfits = {
		"Jawa",
		"Civilian",
		"MoistureFarmer",
		"TuskenRaider",
	},
	weapons = {
		"DH17",
		"SE14C",
		"Gaderffii",
		"T21",
	},
})

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Shops.get(id: string): ShopDef
	local d = defs[id]
	assert(d, `Shops.get: unknown shop "{id}"`)
	return d
end

function Shops.exists(id: string): boolean
	return defs[id] ~= nil
end

function Shops.all(): { [string]: ShopDef }
	return defs
end

--[[
	Checks every shop stocks things that exist.

	Called at boot alongside the other config validators. A bad id here would
	otherwise surface as an item the player can see in the list, click, pay
	for, and then not receive.
]]
function Shops.validate(outfitExists: (string) -> boolean, weaponExists: (string) -> boolean): { string }
	local problems: { string } = {}
	for id, shop in defs do
		if shop.priceMult <= 0 then
			table.insert(problems, `Shops: "{id}" has a non-positive priceMult`)
		end
		for _, outfitId in shop.outfits do
			if not outfitExists(outfitId) then
				table.insert(problems, `Shops: "{id}" stocks unknown outfit "{outfitId}"`)
			end
		end
		for _, weaponId in shop.weapons do
			if not weaponExists(weaponId) then
				table.insert(problems, `Shops: "{id}" stocks unknown weapon "{weaponId}"`)
			end
		end
	end
	table.sort(problems)
	return problems
end

return Shops
