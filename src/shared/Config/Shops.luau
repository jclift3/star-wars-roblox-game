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

--[[
	What a vendor charges to cut a crystal back out of an item, as a fraction
	of what the crystal cost.

	The crystal is destroyed either way, so this is not a refund and not a
	trade -- it is a fee for undoing a decision. High enough that fitting a
	Perfect crystal is worth thinking about first, low enough that a mistake
	made at level 12 is not permanent.

	Multiplied by the vendor's `priceMult` rather than divided by it, unlike
	`SELL_FRACTION`: the player is buying a service here, so the expensive
	trader is expensive in the ordinary direction.
]]
Shops.EXTRACT_FRACTION = 0.5

export type ShopDef = {
	id: string,
	displayName: string,
	greeting: string,
	priceMult: number,
	outfits: { string }, -- Outfits ids
	weapons: { string }, -- Weapons ids
	--[[
		Ships ids -- both classes, but never from the same counter.

		A SPEEDER IS SOLD WHERE YOU ARE STANDING
		Every general trader carries them, because the point of a speeder is
		that the walk you are sick of is the one you are in the middle of
		right now. Selling them out of a garage district would mean walking
		to the garage, which is the joke that writes itself.

		A STARSHIP IS SOLD AT A SPACEPORT
		The hulls used to sit on the same shelf, and the argument for it was
		always thin -- a General Goods counter that hands you a hyperdrive
		between the ration packs and the blaster charges. They now live with
		`ShipYard`, which spawns only in a spaceport district, and that costs
		nothing the player had: `Ships.PAD_TAG` already meant a hull could
		only ever be *called down* at a spaceport, so the one thing this
		changes is that you can no longer buy something you could not use
		without first walking to where it works.
	]]
	ships: { string },
	--[[
		Furnishings ids -- the things that go inside a starship.

		Stocked by the counter that sells the hull, and by that counter only:
		a chandler who sells you a bunk but not the ship to put it in is a
		shop whose entire stock is unusable to most of the people standing in
		front of it. That rule is why these followed the starships out to the
		spaceport rather than staying behind on the general shelf.
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
	-- Groundcars only. The hulls are two districts away at the spaceport,
	-- which is also the only place you could have landed one.
	ships = {
		"HoverSled",
		"SaddleBike",
		"FlareSpeeder",
		"AssaultSpeeder",
	},
	furnishings = {},
})

def({
	id = "ShipYard",
	displayName = "Hangar Row",
	greeting = "Hulls, berths and everything that bolts into one. Cash, no questions.",
	-- A broker's markup. He knows there is no second yard on this rock, and
	-- so does the player, who walked here past a general trader who does not
	-- stock a single thing on these shelves.
	priceMult = 1.1,
	-- Nothing to wear and nothing to shoot with. A yard that also sold you a
	-- coat would be the general counter again under a different sign, and the
	-- whole point of the split is that a shop is a reason to go somewhere.
	outfits = {},
	weapons = {},
	--[[
		All three hulls, and no speeder.

		A yard on a landing field selling repulsor sleds would undo the other
		half of the split -- the speeder has to stay where the walking is, and
		this is the one district you did not walk to.
	]]
	ships = {
		"SkipjackCourier",
		"LonghaulFreighter",
		"DaggerInterceptor",
	},
	-- The whole catalogue. Twelve pieces across four slots is a shelf, not a
	-- warehouse, and the level gates already stage them out over the game --
	-- listing a subset here would only mean a slot the player can never fill
	-- on the one world they trade on.
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
		-- The best thing on this cart by a wide margin, and the only vendor
		-- in the game that could plausibly be holding it: a revolver frame
		-- with a suppressor bolted on and sixteen visible screws is exactly
		-- what "mostly works" means. Level 5 and 1,400, so a character who
		-- has just found the Jawas can leave with it rather than noting it
		-- down for later.
		"NN14",
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
