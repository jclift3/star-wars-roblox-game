--!strict
--[[
	DevService.luau

	Cheat codes, so the game can be looked at without being played first.

	WHY THIS EXISTS
	Most of what has been built is behind a level gate or a price tag, which is
	correct for a player and useless for an author. Seeing whether Hoth reads as
	cold currently costs about four hours of Tatooine. This is the skeleton key.

	WHO CAN USE IT
	**Right now, everyone** -- see `EVERYONE_MAY_CHEAT` below, which is on and
	is not supposed to stay on. The rule underneath it is Studio, the account
	that owns the place, or one of the named accounts in `DEV_USER_IDS`, and
	nobody else ever: a code that hands out 10,000 credits is an economy with a
	hole in it the moment a stranger learns the word. The gate is checked per
	message rather than once at join, because it is one comparison and the
	failure mode of caching it wrongly is the entire problem.

	Reported from play 2026-08-29: the second player typed a code and nothing
	happened, and the natural reading was that the *word* was wrong. It was
	not -- ownership was, and every code in this file was equally silent for
	him. `DEV_USER_IDS` is the durable fix, and it is a list rather than a
	second secret word because there is no word that could have helped: the
	gate never looked at what was typed. It is also empty, because filling it
	in needs two UserIds that have to be collected from a live session, and a
	gate nobody can get through is worse than no gate while the game is still
	being built -- which is what the flag is for.

	THE ORIGIN CODES ARE THE POINT
	`thereisnocow` is the convenient one, but `iamacolyte` and friends are the
	ones that actually test something. The creation screen asks once and then
	never again -- correctly, since the answer hands out a faction and a free
	flight across the galaxy -- so seeing all four travel profiles any other
	way means four characters. These re-roll it in place. They are derived
	from `Origins.ids()`, so a fifth origin gets a code for free and a renamed
	one cannot leave a dead code behind.

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
	`whosyourdaddy` is the same argument about the top of the game: the last
	tier of ships is gated on level 36 and six figures at once, so a code that
	lifts one without the other reaches nothing.

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
local Alignment = require(Shared.Config.Alignment)
local Crystals = require(Shared.Config.Crystals)
local Loot = require(Shared.Config.Loot)
local Origins = require(Shared.Config.Origins)
local Outfits = require(Shared.Config.Outfits)
local Factions = require(Shared.Config.Factions)
local Planets = require(Shared.Config.Planets)
local Progression = require(Shared.Config.Progression)
local Radiant = require(Shared.Config.Radiant)
local Ships = require(Shared.Config.Ships)
local Weapons = require(Shared.Config.Weapons)
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
	OPEN TO EVERYONE. This is temporary and it is meant to be noticed.

	Asked for 2026-08-29, an hour after the allow-list went in: *"I want anyone
	to be able to run codes for now. It is causing too many issues debugging
	atm."* That is the right call while the game is being built by three people
	in one room -- the allow-list needs two UserIds nobody has collected yet,
	and until they are collected it is a gate that stops the authors and stops
	nobody else. A debugging tool the debuggers cannot use is worse than no
	gate at all.

	It is one flag rather than a deleted function so that turning it back is
	one word, and `mayCheat` below still holds the real rule underneath it,
	unchanged and ready. `DevService.start` warns loudly at boot whenever this
	is true outside Studio -- because the failure mode of this line is
	forgetting it, and a forgotten `true` here means the first stranger to
	learn the word "greedisgood" owns the economy.

	FLIP THIS BEFORE THE GAME IS SHOWN TO ANYONE OUTSIDE THE HOUSE.
]]
local EVERYONE_MAY_CHEAT = true

--[[
	The accounts allowed to cheat in a published place besides the owner.

	This is the two boys, and it is meant to stay that size. Everyone in this
	list can hand themselves level 50 and six figures, so it is a list of
	people the game belongs to, not a list of people who asked.

	A UserId is public information on Roblox -- it is the number in a profile
	URL -- so nothing is leaked by it living in a public repo, and nobody who
	reads it gains anything: knowing Landon's id does not make you Landon.
	That is the whole reason this can be a plain table instead of the
	DataStore the analytics credentials need.

	TO FILL ONE IN: have them type any code once while you watch the Output
	window. The refusal line below prints the id that was refused, which is
	exactly the number to paste here. Both of the ids below arrived that way,
	2026-08-29, off three refusal lines in a live session -- which is the one
	thing that trace was written to do.

	Keyed by account name rather than by the boy's name, because the account
	name is the only half of the pair this file can ever check itself against:
	the trace prints `Jeffman8080`, not Logan.
]]
local DEV_USER_IDS: { [number]: string } = {
	[4702145851] = "Jeffman8080",
	[5002107171] = "Coolguy80800",
}

--[[
	True in Studio, true for the account that owns the place, true for the
	named accounts above, false for everyone else -- and, while
	`EVERYONE_MAY_CHEAT` is set, true for everyone.

	A group-owned place reports the *group* id as `game.CreatorId` and so never
	matches a UserId -- deliberately not handled. Every API for asking "does this
	player own that group" is deprecated, and if this place ever moves to a
	group the codes still work in Studio, which is where they are used anyway.
]]
local function mayCheat(player: Player): boolean
	if EVERYONE_MAY_CHEAT then
		return true
	end
	if RunService:IsStudio() then
		return true
	end
	if DEV_USER_IDS[player.UserId] then
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

--- The dearest thing anyone sells, whatever it currently is.
local function topPrice(): number
	local top = 0
	for _, id in Ships.ids() do
		top = math.max(top, Ships.get(id).cost)
	end
	for _, id in Weapons.ids() do
		top = math.max(top, Weapons.get(id).cost)
	end
	for _, id in Outfits.ids() do
		top = math.max(top, Outfits.get(id).cost)
	end
	return top
end

--[[
	The top of the game: max level, and the wallet to shop there with.

	`thereisnocow` stops at 12 on purpose -- it is tuned to open most of the
	map without skipping the levelling the game is about, and moving it would
	cost the one code that gives a *playable* character. But the deep end is
	gated twice over, and level alone does not reach it: reported from play,
	2026-08-18, a Czerka Dagger wants level 36 and 180,950 credits, and the
	only way to see whether a starship flies is to be able to buy one.

	The purse is five times the dearest item rather than a round number, so a
	pricier ship added tomorrow does not quietly make this code useless -- and
	so you can buy the thing, buy the next thing, and still absorb whatever a
	vendor's price multiplier takes.
]]
codes.whosyourdaddy = function(player: Player)
	local credits = topPrice() * 5
	progression().awardCredits(player, credits, true)
	liftToLevel(player, Progression.MAX_LEVEL)
	tell(player, `Level {Progression.MAX_LEVEL}, and {credits} credits. Buy something silly.`)
end

--[[
	Both ends of the alignment axis, one word each.

	Alignment is the only number in this game that cannot be farmed -- it
	moves on dialogue choices and mission resolutions and on nothing else, by
	design, so either end of it is thirty-odd decisions taken in the same
	direction. That is exactly right for a character and useless for checking
	that the thing the axis gates actually works.

	Driven through `awardAlignment` rather than by writing the field, so the
	shift toast and the band-crossing line fire precisely as they do in play.
	Those two messages are usually the thing being tested, and a cheat that
	set the number silently would be exercising a path nothing else uses.

	SWINGING BOTH WAYS DOES NOT BUY BOTH HALVES OF THE FORK, AND THAT IS THE
	POINT. Force Lightning and Force Mend exclude each other by id as well as
	by alignment bound, because bounds are read only at the moment of purchase
	and alignment moves afterwards. That guard was written against a player
	drifting over thirty levels; these two codes are the fastest way there is
	to prove it holds, which is half of why they are worth having.
]]
local function swing(player: Player, target: number)
	local profile = data().get(player)
	if not profile then
		return
	end
	progression().awardAlignment(player, target - profile.alignment)
	tell(player, string.format("%s (%+d)", Alignment.titleFor(target), target), "Alignment")
end

codes.unlimitedpower = function(player: Player)
	swing(player, Alignment.MIN)
end

codes.iamajedi = function(player: Player)
	swing(player, Alignment.MAX)
end

--[[
	Enough skill points to buy the entire tree, whatever the tree currently is.

	Asked for 2026-08-29: *"logan needs a code for more skill points."* The
	reason the ask is reasonable and not just impatience is arithmetic. A
	character earns `STARTING_SKILL_POINTS` plus one per level, so **fifty over
	an entire game**, against a catalogue that is several times that. Missions
	add a handful more. `whosyourdaddy` reaches level 50 in one word and hands
	over fifty points with it -- which is the whole budget, and still not
	enough to see the bottom of one tree, let alone all four.

	So most of the skill tree has never been looked at by anybody, and there is
	no way to look at it: no respec, by design, so a spent point is spent for
	the life of the character and checking what a capstone does costs a
	playthrough.

	Derived rather than typed, like `topPrice`. It totals `maxRank` across
	every node in every tree, so a node added tomorrow is covered without
	anybody remembering this line exists. It is granted in full on every use
	rather than topped up to a target, which means running it twice gives twice
	as much -- harmless, and it keeps the code a single addition with no
	hidden state.

	IT CANNOT BUY EVERYTHING AND IT IS NOT MEANT TO. Level gates, tree-rank
	prerequisites and the three exclusive pairs all still apply -- points were
	never the only thing in the way, they were only the thing you could not
	get more of. A character with a thousand points still cannot hold both
	halves of the Force fork, which is worth checking with it.
]]
local function totalRanks(): number
	local total = 0
	for _, tree in Progression.TREES do
		-- Safe: every id came out of `Progression.TREES`. The annotation on
		-- that table does not survive being read from another module, which
		-- is the same widening the skill panel casts around.
		for _, node in Progression.nodesInTree(tree :: Types.SkillId) do
			total += node.maxRank
		end
	end
	return total
end

codes.whoisjohngalt = function(player: Player)
	local points = totalRanks()
	data().update(player, function(p: PlayerProfile)
		p.skillPoints += points
	end)
	tell(player, `+{points} skill points. Open K and spend them badly.`)
end

--[[
	One drop of every rarity, fully socketed, plus one of every crystal.

	Rarity is a long tail -- Legendary is weight 1 against Common's 100, and
	only about one kill in seven drops anything at all, which puts a Legendary
	somewhere past a thousand kills. The colours, the four-affix names and the
	panel's layout at maximum rolls are all unreachable by playing. This makes
	them one line of chat.

	Every item comes with the maximum sockets and the whole crystal catalogue
	comes with it, because the interesting half of a crystal is what it does in
	a *different* item, and comparing four colours across four slots by playing
	for them is not a thing anybody is going to do.
]]
codes.greedisgood = function(player: Player)
	local profile = data().get(player)
	if not profile then
		return
	end

	local given = 0
	for count = 1, Affixes.MAX_AFFIXES do
		local drop = Loot.forceDrop(devRng, profile.level, count, Crystals.MAX_SOCKETS)
		if drop then
			local taken = false
			data().update(player, function(p: PlayerProfile)
				taken = Inventory.add(p.inventory, drop.id, 1, drop.rolls, drop.sockets) ~= nil
			end)
			if not taken then
				-- The cheat is subject to the cap like anything else. Lifting
				-- it here would mean the one easy way to reach a full bag is
				-- also the one way that cannot show what a full bag does.
				tell(player, `Bag full at {Inventory.MAX_UNIQUE}. Sell something.`, "Error")
				break
			end
			given += 1
			tell(player, `{Affixes.rarityAt(count).name}: {Loot.nameOf(drop)}`, Affixes.rarityAt(count).name)
		end
	end

	-- Crystals are plain stacks, so these merge by id and cannot fill the bag.
	local stones = Crystals.ids()
	data().update(player, function(p: PlayerProfile)
		for _, id in stones do
			Inventory.add(p.inventory, id, 1)
		end
	end)

	tell(player, `{given} socketed items and {#stones} crystals. Open your bag.`)
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
	local crystals = 0
	local drilled = 0
	local holes = 0
	local byRarity: { [number]: number } = {}
	local low: { [string]: number } = {}
	local high: { [string]: number } = {}

	for _ = 1, SAMPLES do
		local drop = Loot.rollDrop(devRng, level)
		if not drop then
			continue
		end
		drops += 1
		if drop.kind == "Crystal" then
			crystals += 1
		end
		local sockets = drop.sockets or 0
		if sockets > 0 then
			drilled += 1
			holes += sockets
		end
		local n = Loot.rarityOf(drop)
		byRarity[n] = (byRarity[n] or 0) + 1
		if drop.rolls then
			for stat, value in drop.rolls do
				low[stat] = math.min(low[stat] or value, value)
				high[stat] = math.max(high[stat] or value, value)
			end
		end
	end

	print(`\n=== loot sample: {SAMPLES} kills at level {level} ===`)
	print(`drops: {drops}  ({string.format("%.1f", drops / SAMPLES * 100)}% of kills)`)
	print(`  crystals: {crystals}  gear: {drops - crystals}`)
	-- Sockets are the reason a Common drop is worth picking up at all, so the
	-- sample has to say how often one actually arrives drilled.
	print(
		`  socketed gear: {drilled}  ({holes} holes, {string.format("%.2f", holes / math.max(1, drilled))} each)`
	)
	-- From zero, unlike before: a Common drop used to mean no drop, and now it
	-- means an unenchanted item with holes in it -- a row that must not vanish.
	for count = 0, Affixes.MAX_AFFIXES do
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
		local def = Origins.get(id)
		data().update(player, function(profile: PlayerProfile)
			profile.origin = id
			profile.faction = def.faction
			-- Marked chosen, or the creation screen reopens on the next
			-- profile push and asks a question the code has just answered.
			profile.originChosen = true
			-- Otherwise the old origin's cooldown is still running against the
			-- new one, which reads as the code having done nothing.
			profile.lastTravelAt = 0
		end)
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

--[[
	Every chat line that reaches this server, one row each.

	Reported from play 2026-08-29: *"whosyourdaddy didnt work."* There are
	three quite different reasons a code can do nothing -- the message never
	reached the server at all (Roblox's moderation can drop one outright, and
	"daddy" is exactly the kind of word that gets dropped), the message arrived
	but `mayCheat` refused it, or the code ran and its effect was invisible
	because the character was already at the ceiling it lifts you to. From the
	cockpit all three look identical, which is why the last fix for this was a
	guess.

	So the server prints what it saw. This goes to the Output window, which no
	player can read, so it gives away nothing that `tell` does not already say
	out loud to the one person allowed to use it.
]]
local function trace(message: string)
	print(`[DevService] {message}`)
end

function DevService.start()
	--[[
		The one line that stops `EVERYONE_MAY_CHEAT` from being permanent.

		A `warn` rather than a `print` so it comes up yellow among the boot
		chatter, and only outside Studio because Studio is where the flag is
		harmless and where the noise would be constant enough to stop being
		read. In a published place it is the whole reminder.
	]]
	if EVERYONE_MAY_CHEAT and not RunService:IsStudio() then
		warn(
			"[DevService] CHEAT CODES ARE OPEN TO EVERY PLAYER. Set EVERYONE_MAY_CHEAT = false before release."
		)
	end

	local function listen(player: Player)
		player.Chatted:Connect(function(message: string)
			local typed = normalise(message)
			local code = codes[typed]
			if not code then
				trace(`{player.Name} said something that is not a code: "{typed}"`)
				return
			end
			if not mayCheat(player) then
				-- Deliberately silent *to the player*. Telling a stranger they
				-- typed a real code and were refused is an invitation to keep
				-- guessing; the console is not a place a stranger can look.
				--
				-- The UserId is here so that this line doubles as the way to
				-- fill in `DEV_USER_IDS`: somebody who should be allowed types
				-- a code once, and the number to add prints itself.
				trace(
					`{player.Name} typed "{typed}" and was refused -- not the owner, not Studio, `
						.. `not in DEV_USER_IDS. UserId is {player.UserId}`
				)
				return
			end
			trace(`{player.Name} ran "{typed}"`)
			code(player)
		end)
	end

	for _, player in Players:GetPlayers() do
		listen(player)
	end
	Players.PlayerAdded:Connect(listen)
end

return DevService
