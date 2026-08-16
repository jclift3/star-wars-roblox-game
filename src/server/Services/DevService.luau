--!strict
--[[
	DevService.luau

	Cheat codes, so the game can be looked at without being played first.

	WHY THIS EXISTS
	Most of what has been built is behind a level gate or a price tag, which is
	correct for a player and useless for an author. Seeing whether Hoth reads as
	cold currently costs about four hours of Tatooine. This is the skeleton key.

	WHO CAN USE IT
	Studio, or the account that owns the place. Nobody else, ever -- a code
	that hands out 10,000 credits is an economy with a hole in it the moment a
	stranger learns the word. The gate is checked per message rather than once
	at join, because it is one comparison and the failure mode of caching it
	wrongly is the entire problem.

	THE ORIGIN CODES ARE THE POINT
	`thereisnocow` is the convenient one, but `iamacolyte` and friends are the
	ones that actually test something. Until the creation screen exists every
	character is a Scoundrel, which means the four travel profiles -- the whole
	reason origins were built -- cannot be seen at all. These make them visible.
	They are derived from `Origins.ids()`, so a fifth origin gets a code for
	free and a renamed one cannot leave a dead code behind.

	THE PRINTING CODES ARE THE TEST SUITE
	`greedisgood`, `iseedeadpeople` and `showmethemoney` exist because there is
	no way to run Luau outside Roblox, and the three things this game generates
	-- rarity, affix rolls and radiant missions -- are all things you cannot
	check by reading the tables they came from. One hands you a drop of every
	rarity, one samples five thousand kills, one prints every generated
	mission. Between them they cover what a unit test would, for a fraction of
	the harness.

	`strengthandhonor` is there for the opposite reason: reputation is not hard
	to read, it is just too slow to reach by playing to test what hangs off it.

	HOW YOU ENTER ONE
	Type it in the normal Roblox chat. `Player.Chatted` still fires server-side
	under TextChatService, and using it means this feature needs no client code,
	no remote and no UI. The message stays visible in the chat window -- there
	is no server-side way to unsend it -- which does not matter for a tool only
	its author can use.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Inventory = require(Shared.Core.Inventory)
local Affixes = require(Shared.Config.Affixes)
local Loot = require(Shared.Config.Loot)
local Origins = require(Shared.Config.Origins)
local Factions = require(Shared.Config.Factions)
local Planets = require(Shared.Config.Planets)
local Progression = require(Shared.Config.Progression)
local Radiant = require(Shared.Config.Radiant)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type PlayerProfile = Types.PlayerProfile

local DevService = {
	name = "DevService",
	-- Last. It only listens, and everything it calls belongs to someone else.
	priority = 90,
}

--- The level `thereisnocow` lifts you to: past every world's minLevel - 4 grace
--- except the Core and the deep Outer Rim, which is the point of the code.
local BOOST_LEVEL = 12
local BOOST_CREDITS = 10000

-- Separate from CombatService's loot rng purely so that hammering a cheat code
-- cannot shift the sequence real drops come out of.
local devRng = Random.new()

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

local function tell(player: Player, message: string, kind: string?)
	Net.fireClient(Net.Event.Notify, player, message, kind or "Reward")
end

--------------------------------------------------------------------------------
-- Who is allowed
--------------------------------------------------------------------------------

--[[
	True in Studio, true for the account that owns the place, false for everyone.

	A group-owned place reports the *group* id as `game.CreatorId` and so never
	matches a UserId -- deliberately not handled. Every API for asking "does this
	player own that group" is deprecated, and if this place ever moves to a
	group the codes still work in Studio, which is where they are used anyway.
]]
local function mayCheat(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

--------------------------------------------------------------------------------
-- The codes
--------------------------------------------------------------------------------

--[[
	Raises the player to at least `level`, through the normal XP path.

	Setting `profile.level` directly would skip the skill points and the
	level-up toast, leaving a level 12 character with one skill point and no
	idea it happened. Awarding the difference in cumulative XP lets
	`awardXp` do all of it.
]]
local function liftToLevel(player: Player, level: number)
	local profile = data().get(player)
	if not profile then
		return
	end
	local target = Progression.totalXpForLevel(math.min(level, Progression.MAX_LEVEL))
	local current = Progression.totalXpForLevel(profile.level) + profile.xp
	if target > current then
		progression().awardXp(player, target - current)
	end
end

local codes: { [string]: (Player) -> () } = {}

codes.thereisnocow = function(player: Player)
	-- Raw, because the Scavenger multiplier turning 10,000 into 11,500 would
	-- make the one number in this file that should be predictable unpredictable.
	progression().awardCredits(player, BOOST_CREDITS, true)
	liftToLevel(player, BOOST_LEVEL)
	tell(player, `The cow says nothing. +{BOOST_CREDITS} cr, level {BOOST_LEVEL}.`)
end

--[[
	One drop of every rarity, at the player's own level.

	Rarity is a long tail -- Legendary is weight 1 against Common's 100, and
	only about one kill in seven drops anything at all, which puts a Legendary
	somewhere past a thousand kills. The colours, the four-affix names and the
	panel's layout at maximum rolls are all unreachable by playing. This makes
	them one line of chat.
]]
codes.greedisgood = function(player: Player)
	local profile = data().get(player)
	if not profile then
		return
	end

	local given = 0
	for count = 1, Affixes.MAX_AFFIXES do
		local drop = Loot.forceDrop(devRng, profile.level, count)
		if drop then
			local taken = false
			data().update(player, function(p: PlayerProfile)
				taken = Inventory.add(p.inventory, drop.id, 1, drop.rolls) ~= nil
			end)
			if not taken then
				-- The cheat is subject to the cap like anything else. Lifting
				-- it here would mean the one easy way to reach a full bag is
				-- also the one way that cannot show what a full bag does.
				tell(player, `Bag full at {Inventory.MAX_ROLLED}. Sell something.`, "Error")
				break
			end
			given += 1
			tell(player, `{Affixes.rarityAt(count).name}: {Loot.nameOf(drop)}`, Affixes.rarityAt(count).name)
		end
	end
	tell(player, `{given} items, one of each rarity. Open your bag.`)
end

--[[
	Promotes you with whoever runs the world you are standing on.

	Reputation is the slowest thing in the game to move by playing -- a rank is
	several missions, and the hostile end is only reachable by murdering your
	way through a garrison. That makes everything hanging off it (the stipend,
	the galaxy map's standing line, who opens fire) effectively untestable.

	It deliberately goes through `awardRep` rather than writing the number, so
	one code exercises the whole chain: spillover pushes the local faction's
	enemies *down* as it pushes the locals up, which is the half you would
	otherwise never see, and the promotion pays out on the way past.
]]
local REP_STEP = 2000

codes.strengthandhonor = function(player: Player)
	local profile = data().get(player)
	if not profile then
		return
	end
	local faction = Planets.get(profile.currentPlanet).controllingFaction
	progression().awardRep(player, faction, REP_STEP)
	tell(player, `+{REP_STEP} with the {Factions.get(faction).displayName}, and their enemies noticed.`)
end

--[[
	Rolls a great many drops and prints what came out.

	The closest thing to a test this project can run. There is no way to
	execute Luau offline, so the alternative to a sampling loop is reading the
	weights and hoping. It answers the two questions reading cannot: what the
	real drop rate is once "Common means nothing" is applied, and whether an
	affix can roll an absurd number at the top of the level range.

	Prints rather than toasts, because a histogram does not fit in a toast and
	the Studio output window is where the author already is.
]]
local SAMPLES = 5000

codes.iseedeadpeople = function(player: Player)
	local profile = data().get(player)
	local level = profile and profile.level or 1

	local drops = 0
	local byRarity: { [number]: number } = {}
	local low: { [string]: number } = {}
	local high: { [string]: number } = {}

	for _ = 1, SAMPLES do
		local drop = Loot.rollDrop(devRng, level)
		if not drop then
			continue
		end
		drops += 1
		local n = Affixes.rarityOf(drop.rolls).affixes
		byRarity[n] = (byRarity[n] or 0) + 1
		for stat, value in drop.rolls do
			low[stat] = math.min(low[stat] or value, value)
			high[stat] = math.max(high[stat] or value, value)
		end
	end

	print(`\n=== loot sample: {SAMPLES} kills at level {level} ===`)
	print(`drops: {drops}  ({string.format("%.1f", drops / SAMPLES * 100)}% of kills)`)
	for count = 1, Affixes.MAX_AFFIXES do
		local n = byRarity[count] or 0
		local rarity = Affixes.rarityAt(count)
		print(
			`  {rarity.name}: {n}  ({string.format("%.2f", n / SAMPLES * 100)}% of kills,`
				.. ` 1 in {if n > 0 then math.floor(SAMPLES / n) else "never"})`
		)
	end
	print("affix ranges seen:")
	-- Sorted so two runs can be diffed by eye.
	local stats: { string } = {}
	for stat in low do
		table.insert(stats, stat)
	end
	table.sort(stats)
	for _, stat in stats do
		print(`  {stat}: {string.format("%.3f", low[stat])} .. {string.format("%.3f", high[stat])}`)
	end

	tell(player, `{drops} drops in {SAMPLES} kills at level {level}. See the output window.`)
end

--[[
	Every generated mission, planet by planet, and which are posted today.

	Same reasoning as `iseedeadpeople`. `Radiant` composes its missions out of
	the spawn tables, the points of interest and the level bands, and the only
	way to find out what nine planets' worth of that actually reads like -- a
	Jawa issuing Republic bounties, a district with nothing to do in it, a
	Survey of somewhere three studs from the giver -- is to make it print.

	`Missions.validate` already catches the ids that do not resolve. This
	catches the ones that resolve to something silly, which nothing can.
]]
codes.showmethemoney = function(player: Player)
	local now = os.time()
	local total = 0
	print(`\n=== radiant missions (day {math.floor(now / Radiant.DAY)}) ===`)
	for _, planetId in Planets.ids() do
		local posted: { [string]: boolean } = {}
		for _, id in Radiant.postedOn(planetId, now) do
			posted[id] = true
		end

		-- Sorted, so two runs -- or the server and a client -- diff by eye.
		local ids: { string } = {}
		for id, m in Radiant.all() do
			if m.planet == planetId then
				table.insert(ids, id)
			end
		end
		table.sort(ids)

		print(`{planetId}: {#ids} generated, {#Radiant.postedOn(planetId, now)} posted`)
		total += #ids
		for _, id in ids do
			local m = Radiant.all()[id]
			print(`  {if posted[id] then "*" else " "} lv{m.minLevel} {m.displayName}  <- {m.giver}`)
			for _, obj in m.objectives do
				print(`      {obj.description}`)
			end
		end
	end
	print(`total: {total}`)

	tell(player, `{total} radiant missions across {#Planets.ids()} worlds. See the output window.`)
end

-- One per origin: `iamacolyte`, `iamconscript`, `iamscoundrel`, `iamscrapper`.
for _, id in Origins.ids() do
	codes[`iam{string.lower(id)}`] = function(player: Player)
		data().update(player, function(profile: PlayerProfile)
			profile.origin = id
			-- Otherwise the old origin's cooldown is still running against the
			-- new one, which reads as the code having done nothing.
			profile.lastTravelAt = 0
		end)
		local def = Origins.get(id)
		tell(player, `You are a {def.displayName} now. {def.travelBlurb}`)
	end
end

--------------------------------------------------------------------------------
-- Entry
--------------------------------------------------------------------------------

--- Chat text reduced to the letters, so casing and stray punctuation cannot
--- make a working code look broken.
local function normalise(message: string): string
	return (string.gsub(string.lower(message), "[^%a]", ""))
end

function DevService.start()
	local function listen(player: Player)
		player.Chatted:Connect(function(message: string)
			local code = codes[normalise(message)]
			if not code then
				return
			end
			if not mayCheat(player) then
				-- Deliberately silent. Telling a stranger they typed a real
				-- code and were refused is an invitation to keep guessing.
				return
			end
			code(player)
		end)
	end

	for _, player in Players:GetPlayers() do
		listen(player)
	end
	Players.PlayerAdded:Connect(listen)
end

return DevService
