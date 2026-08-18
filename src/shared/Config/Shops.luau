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
		Ships ids -- both classes, speeders and starships alike.

		Sold from the same counter as everything else rather than from a new
		kind of vendor with a new archetype and a new spawn entry. A speeder
		yard would be a better shop and a worse feature: it would exist on
		whichever planets got one, and the point of a speeder is that the
		walk you are sick of is the one you are standing in right now.

		That argument holds for starships too, but only barely, and the shop
		that carries them says so on the shelf: `GeneralGoods` stocks all
		three hulls and the Jawa stocks none, because a Czerka Dagger is not
		something that falls off anything. The real gate on a starship is
		not who will sell you one -- it is `Ships.PAD_TAG`. You can buy a
		hull on a world with no spaceport; you simply cannot call it down.
	]]
	ships: { string },
	--[[
		Furnishings ids -- the things that go inside a starship.

		Stocked by the same counter that sells the hull, and by that counter
		only: a chandler who sells you a bunk but not the ship to put it in
		is a shop whose entire stock is unusable to most of the people
		standing in front of it. The Jawa carries none for the reason they
		carry no starship.
	]]
	furnishings: { string },
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
	ships = {
		"HoverSled",
		"SaddleBike",
		"FlareSpeeder",
		"AssaultSpeeder",
		-- The starship shelf. Priced and level-gated far above everything
		-- else in this list on purpose: a General Goods counter that can
		-- sell you a hyperdrive at level 16 is only strange if you think a
		-- Longhaul is a luxury. It is a job.
		"SkipjackCourier",
		"LonghaulFreighter",
		"DaggerInterceptor",
	},
	-- The whole catalogue. Twelve pieces across four slots is a shelf, not a
	-- warehouse, and the level gates already stage them out over the game --
	-- listing a subset here would only mean a slot the player can never
	-- fill on the one world they trade on.
	furnishings = {
		"SpacerBunk",
		"MeditationSlab",
		"HuttSilkBerth",
		"CrateTable",
		"SabaccTable",
		"DejarikTable",
		"NavConsole",
		"SliceRig",
		"HolomapPlinth",
		"ToolRack",
		"KraytSkull",
		"AstromechDock",
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
	-- No landspeeder and no starship: a Jawa sells what fell off something,
	-- and what falls off a swoop gang is a swoop.
	ships = {
		"HoverSled",
		"SaddleBike",
		"SwoopRacer",
	},
	furnishings = {},
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
	shipExists: (string) -> boolean,
	furnishingExists: (string) -> boolean
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
		for _, shipId in shop.ships do
			if not shipExists(shipId) then
				table.insert(problems, `Shops: "{id}" stocks unknown ship "{shipId}"`)
			end
		end
		for _, furnishingId in shop.furnishings do
			if not furnishingExists(furnishingId) then
				table.insert(problems, `Shops: "{id}" stocks unknown furnishing "{furnishingId}"`)
			end
		end
	end
	table.sort(problems)
	return problems
end

return Shops
