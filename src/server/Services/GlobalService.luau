--!strict
--[[
	GlobalService.luau

	The two facts that belong to the universe rather than to a player or to a
	server: who got somewhere first, and who is fastest.

	WHY THERE IS NO BACKEND HERE
	ROADMAP 5.2 was written assuming this needed the Supabase project 4.1
	stood up, on the reasoning that "one of a kind" is a claim about the whole
	player base and therefore needs a database. The claim is right and the
	conclusion was wrong: Roblox already ships that database, and it is the
	one this game has been saving into since day one.

	A DataStore belongs to the *universe*, not the server -- which is exactly
	the fact that made SETUP_GUIDE 3 impossible before the first publish. So
	`UpdateAsync` on a shared key is an atomic read-modify-write across every
	running server at once, and `OrderedDataStore` is a sorted index over one.
	Those are precisely the two primitives 5.2 asked for. Routing them through
	HTTP to Postgres would add a second project at $10 a month, an ingest key
	that can leak, a network hop that can fail, and a second source of truth
	that can disagree with the profile -- to arrive back at read-modify-write
	on a shared key.

	The backend still earns its place at 4.1, and for the reason backend.md
	gives: analytics wants to *query* history in ways no DataStore can. Nothing
	here wants to query anything. It wants one row.

	WHY BOTH HALVES LIVE IN ONE FILE
	They are the same idea twice -- a fact about the whole player base, written
	once, read by anyone -- and they share every hard part: a store that throws
	in an unpublished place, a call that yields, a name that has to be looked
	up for a user id who is not here, and a rate limit that means neither can
	be read on a whim. Two services would have solved all of that twice.

	EVERYTHING HERE IS OPTIONAL AT RUNTIME
	Same discipline as AnalyticsService. In Studio without API services, and in
	a place that has never been published, every call fails and every call is
	supposed to: `claim` says nobody has it, `best` says there is no record,
	and the game plays exactly as it did before this file existed. A feature
	that takes the world down when the network is having a bad afternoon is
	worse than no feature.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local GlobalService = {
	name = "GlobalService",
	-- Infrastructure, like DataService (1) and AnalyticsService (2), and
	-- before anything that would ask it a question.
	priority = 3,
}

--[[
	Versioned, because a claim is permanent and permanence is the thing you
	cannot take back. If the shape of what is stored under a key ever has to
	change, the honest move is a new store and a fresh galaxy, not a migration
	that quietly rewrites who was first.
]]
local CLAIM_STORE = "Firsts_v1"
local BOARD_PREFIX = "Board_v1_"

--[[
	How long a leaderboard read is reused.

	`GetSortedAsync` is one of the most tightly throttled calls in the API, and
	the thing reading it here is a sign on a start line that a player is
	standing in front of. A record that is up to two minutes stale is a record;
	a sign that stopped updating because the budget ran out is a bug.
]]
local BOARD_TTL = 120

type Record = {
	userId: number,
	name: string,
	value: number,
}

local claimStore: GlobalDataStore? = nil
local boards: { [string]: OrderedDataStore } = {}

--- Cached top entry per board, plus when it was fetched.
local topOf: { [string]: Record } = {}
local fetchedAt: { [string]: number } = {}
--- Guards against two callers fetching the same board at once, since the
--- call yields and a sign refresh can be triggered by either brother.
local fetching: { [string]: boolean } = {}

--- User id -> display name, for holders who are not on this server.
local names: { [number]: string } = {}

--------------------------------------------------------------------------------
-- Stores
--------------------------------------------------------------------------------

--[[
	Resolved on first use and never at require time, for the reason DataService
	documents at length: `GetDataStore` throws outright in an unpublished
	place, and doing it at module scope turns that into a require-time error
	that takes the service down instead of letting it degrade.
]]
local function claims(): GlobalDataStore?
	if not claimStore then
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore(CLAIM_STORE)
		end)
		if not ok then
			return nil
		end
		claimStore = store
	end
	return claimStore
end

local function board(id: string): OrderedDataStore?
	local existing = boards[id]
	if existing then
		return existing
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(BOARD_PREFIX .. id)
	end)
	if not ok then
		return nil
	end
	boards[id] = store
	return store
end

--[[
	The name behind a user id.

	Checked against this server first, because the common case by a distance is
	that the record holder is the brother standing next to you. Only a stranger
	costs a web call, and only once.
]]
local function nameFor(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end

	local here = Players:GetPlayerByUserId(userId)
	if here then
		names[userId] = here.DisplayName
		return here.DisplayName
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	-- Not cached on failure: a name that could not be fetched once is worth
	-- asking about again, whereas caching the fallback would make a transient
	-- outage permanent.
	if not ok or type(name) ~= "string" then
		return "someone"
	end
	names[userId] = name
	return name
end

--------------------------------------------------------------------------------
-- Firsts
--------------------------------------------------------------------------------

--[[
	Tries to be the first player in the whole game to take `id`.

	Returns whether this player won it, and the name of whoever holds it --
	which is this player on a win, and the person who beat them otherwise.

	THE ATOMICITY IS THE ENTIRE POINT
	`UpdateAsync` serialises against every other server in the universe, and a
	transform that returns nil cancels the write. So of every player who ever
	calls this with the same `id`, exactly one runs the second branch. There is
	no window, no check-then-set, and no version where both brothers can be
	told they were first because they clicked in the same second -- which is
	the failure this would have had if it were a Get followed by a Set, and
	the failure two players in one room would find on the first try.

	Yields. Call it off the gameplay path.
]]
function GlobalService.claim(id: string, player: Player): (boolean, string?)
	local store = claims()
	if not store then
		-- No store means no galaxy to be first in. Nobody wins, so a caller
		-- that pays out on a win pays out nothing, and the ordinary reward
		-- it was decorating still happens.
		return false, nil
	end

	--[[
		Set inside the transform rather than read from the return value.
		`UpdateAsync` may run the transform more than once when it loses a
		race and retries, and only the last run is the one that decided, so
		the answer has to be whatever that run saw.
	]]
	local heldBy: number? = nil
	local ok = pcall(function()
		store:UpdateAsync(id, function(old: any): any
			if type(old) == "table" and type(old.userId) == "number" then
				heldBy = old.userId
				return nil
			end
			heldBy = nil
			return { userId = player.UserId, at = os.time() }
		end)
	end)

	if not ok then
		return false, nil
	end
	local holder = heldBy
	if holder then
		return false, nameFor(holder)
	end
	names[player.UserId] = player.DisplayName
	return true, player.DisplayName
end

--------------------------------------------------------------------------------
-- Boards
--------------------------------------------------------------------------------

--[[
	Posts a score, keeping only the better of it and what is already there.

	`lowerIsBetter` because the first board in the game is lap times, and the
	alternative -- storing the negation so bigger always wins -- makes every
	value in the store a lie that one caller remembers to undo.

	`value` is rounded to an integer because an OrderedDataStore stores nothing
	else; the caller decides the unit. Lap times go in as hundredths, which
	keeps every distinction a stopwatch on screen can show.

	Yields.
]]
function GlobalService.post(id: string, player: Player, value: number, lowerIsBetter: boolean)
	local store = board(id)
	if not store then
		return
	end

	local rounded = math.floor(value + 0.5)
	local key = tostring(player.UserId)
	local ok = pcall(function()
		store:UpdateAsync(key, function(old: any): any
			if type(old) == "number" then
				local better = if lowerIsBetter then rounded < old else rounded > old
				if not better then
					return nil
				end
			end
			return rounded
		end)
	end)
	if not ok then
		return
	end

	--[[
		The cache is dropped rather than updated, even though the new value is
		right here. Whether this run is the *galaxy* record depends on every
		other player's entry, which this server does not have -- so guessing
		would put a name on the sign that the board disagrees with, and the
		one thing a record has to be is true.
	]]
	fetchedAt[id] = 0
end

--[[
	The best entry on a board, or nil if there is none yet.

	Never yields and never touches the network. It answers out of the cache and
	kicks off a refresh in the background when that cache is stale, because
	every caller so far is a sign being redrawn while somebody stands in front
	of it -- and a redraw that blocks on a throttled web call is a redraw that
	freezes the thing it is decorating.

	The consequence, stated plainly: the first read after a server starts
	returns nil and the second one, a moment later, returns the record. A sign
	that gains a line a second after you walk up is fine. A sign that hangs the
	frame is not.
]]
function GlobalService.best(id: string): Record?
	local age = os.clock() - (fetchedAt[id] or 0)
	if age > BOARD_TTL and not fetching[id] then
		fetching[id] = true
		task.spawn(function()
			local store = board(id)
			if store then
				local ok, page = pcall(function()
					-- Ascending, so the first row is the smallest number, which
					-- for a lap time is the fastest. A board where bigger wins
					-- would ask for descending here and nowhere else.
					return store:GetSortedAsync(true, 1):GetCurrentPage()
				end)
				if ok and type(page) == "table" and page[1] then
					local entry = page[1]
					local userId = tonumber(entry.key)
					local value = entry.value
					if userId and type(value) == "number" then
						topOf[id] = { userId = userId, name = nameFor(userId), value = value }
					end
				end
			end
			-- Stamped even on failure, so a place with no API access retries
			-- once every BOARD_TTL rather than on every single redraw.
			fetchedAt[id] = os.clock()
			fetching[id] = false
		end)
	end
	return topOf[id]
end

return GlobalService
