--!strict
--[[
	Shops.luau

	What each kind of vendor has on the shelf.

	Stock is listed explicitly rather than derived from a tier range, because
	the interesting thing about a vendor is what they *don't* carry. A Jawa
	selling you Imperial commando plate would be absurd, and a rule like "tier <= 2"
	has no way to express that. Explicit lists are longer and worth it.

	`priceMult` is the vendor's own markup, applied before the player's Bargaining
	skill. A Jawa is cheap because everything they sell fell off something.

	Vendors are attached to NPCs through `NPCArchetypes.shop`, so placing a shop
	in the world means spawning the archetype that owns it -- there is no
	separate shop-placement system to keep in sync.
]]

local Shops = {}

--[[
	How close you have to stand to trade.

	Close enough to be obviously talking to them, far enough that you do not
	have to stand on their toes. Shared rather than private to ShopService
	because the client draws the "you can trade here" cue and the server
	enforces the sale -- two copies of this number would drift, and the visible
	symptom would be a prompt that lies.
]]
Shops.VENDOR_RANGE = 30

--[[
	What a vendor pays, as a fraction of what the thing is worth.

	The spread is the whole reason a shop is a shop, and it has to be wide
	enough that buying something and selling it straight back is an obvious
	loss -- otherwise the vendor is a bank. Divided by the vendor's own
	`priceMult` at the till, so the trader who charges the most also offers the
	least, and the Jawa who is cheap to buy from also pays well. That is what
	"it all fell off something" ought to mean in both directions.
]]
Shops.SELL_FRACTION = 0.3

export type ShopDef = {
	id: string,
	displayName: string,
	greeting: string,
	priceMult: number,
	outfits: { string }, -- Outfits ids
	weapons: { string }, -- Weapons ids
	--[[
		Ships ids.

		Sold from the same counter as everything else rather than from a new
		kind of vendor with a new archetype and a new spawn entry. A speeder
		yard would be a better shop and a worse feature: it would exist on
		whichever planets got one, and the point of a speeder is that the
		walk you are sick of is the one you are standing in right now.
	]]
	speeders: { string },
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
		"RepublicTrooper",
		"RepublicPilot",
		"RepublicSecurity",
		"ImperialTrooper",
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
	speeders = {
		"HoverSled",
		"SaddleBike",
		"FlareSpeeder",
		"AssaultSpeeder",
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
	-- No landspeeder: a Jawa sells what fell off something, and what falls
	-- off a swoop gang is a swoop.
	speeders = {
		"HoverSled",
		"SaddleBike",
		"SwoopRacer",
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
function Shops.validate(
	outfitExists: (string) -> boolean,
	weaponExists: (string) -> boolean,
	speederExists: (string) -> boolean
): { string }
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
		for _, speederId in shop.speeders do
			if not speederExists(speederId) then
				table.insert(problems, `Shops: "{id}" stocks unknown speeder "{speederId}"`)
			end
		end
	end
	table.sort(problems)
	return problems
end

return Shops
