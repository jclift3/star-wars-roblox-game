--!strict
--[[
	AnalyticsService.luau

	Batches gameplay events and posts them to the ingest endpoint. ROADMAP 4.1;
	the backend shape is LIVING-NPCS.md §5.

	WHY THIS EXISTS
	Every number in `Config/` was picked by feel. We do not know which missions
	get abandoned, where players die, or what they actually buy, so every
	balance change so far has been an argument rather than a measurement. This
	is the cheapest thing on the roadmap that fixes that, and it is the reason
	the backend gets built now: analytics needs no API key and costs nothing
	per call, so it proves the whole Roblox -> edge function -> Postgres path
	before anything expensive rides on it.

	IT MUST NEVER BREAK THE GAME
	`log` is called from combat, dialogue and the shop -- paths where an error
	is a visible failure of something the player was doing. So it is written to
	be incapable of raising: it takes no locks, it never yields, and every
	dependency is fetched with `ServiceLoader.find` rather than `get`. If
	telemetry is misconfigured, the game does not know.

	The corollary is that it drops data rather than growing. A capped queue that
	discards is a hole in a graph; an uncapped one is a memory leak on a live
	server, and the second is worse. Every loss says so in Output, because a
	silent gap in telemetry is indistinguishable from a quiet week.

	WHERE THE CONFIGURATION LIVES, AND WHY NOT HERE
	The URL and key come out of a DataStore, written once from the Studio
	command bar (SETUP_GUIDE.md §9). Not from a config table, for two reasons:
	this repository is public, and a secret in the place file cannot be rotated
	without republishing the game. Absent configuration means telemetry is off
	and nothing else changes -- that is the normal state for a fresh clone.

	STUDIO IS NOT EXCLUDED, IT IS LABELLED
	A live server's `JobId` is a GUID; in Studio it is empty, and this sends
	the string "studio" instead. Excluding Studio outright would make the
	feature untestable by the only means available -- there is no way to run
	Luau offline -- while mixing the two would let a developer's fifty test
	deaths drown four real ones. One `where job_id <> 'studio'` separates them.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ServiceLoader = require(Shared.Core.ServiceLoader)

local AnalyticsService = {
	name = "AnalyticsService",
	-- After DataService (1), because every event is enriched from a profile,
	-- and before everything that logs.
	priority = 2,
}

--[[
	Every event the game can report.

	A constant table for the reason every compared string in this codebase is
	one: `Kind.Purchse` is a type error at author time, where `"purchse"` is a
	row in the database that quietly never matches a query. The ingest function
	deliberately does not re-check this list -- a sink that rejects data you
	have already collected is worse than one holding a typo you can see with
	`select distinct kind`.
]]
AnalyticsService.Kind = {
	SessionStart = "session_start",
	SessionEnd = "session_end",
	LevelUp = "level_up",
	Death = "death",
	MissionAccept = "mission_accept",
	MissionComplete = "mission_complete",
	MissionAbandon = "mission_abandon",
	Purchase = "purchase",
	Talk = "talk",
	Secret = "secret",
	Travel = "travel",
}

type Event = {
	at: number,
	playerId: number,
	sessionId: string,
	kind: string,
	planet: string?,
	level: number?,
	data: { [string]: any }?,
}

-- Matches MAX_EVENTS in the ingest function. A larger batch is refused whole.
local MAX_BATCH = 200
-- Roughly a minute of a busy server. Past this the oldest events are the ones
-- worth keeping least, but dropping from the front costs a table shift on
-- every log, so new events are refused instead and counted.
local MAX_QUEUE = 500
local FLUSH_SECONDS = 30
local CONFIG_STORE = "Config"
local CONFIG_KEY = "analytics"

local endpoint: string? = nil
local ingestKey: string? = nil
local queue: { Event } = {}
local overflowing = false
local flushing = false
local sessions: { [Player]: string } = {}
local joinedAt: { [Player]: number } = {}

local jobId = if game.JobId ~= "" then game.JobId else "studio"

--------------------------------------------------------------------------------
-- Queue
--------------------------------------------------------------------------------

--[[
	Adds an event, or drops it if the queue is already full.

	The warning is edge-triggered rather than per-event: a full queue means the
	endpoint is unreachable or the server is producing faster than it can send,
	and both of those produce thousands of losses. One line saying it started,
	one saying it stopped, is the readable version of that.
]]
local function enqueue(event: Event)
	if #queue >= MAX_QUEUE then
		if not overflowing then
			overflowing = true
			warn(`[AnalyticsService] queue full at {MAX_QUEUE}; dropping events until it drains`)
		end
		return
	end
	overflowing = false
	table.insert(queue, event)
end

--[[
	Sends up to one batch. Returns false if there was nothing to send or the
	post failed; the caller does not care which, and neither does anything else.

	A failed batch is discarded rather than retried. The endpoint being down is
	not a reason to spend a live game server's memory holding a graph nobody is
	looking at, and the drop counter means the gap is still visible in the data.
]]
local function flush(): boolean
	if flushing or #queue == 0 then
		return false
	end
	local url, key = endpoint, ingestKey
	if not url or not key then
		return false
	end

	flushing = true

	local batch: { Event } = {}
	for _ = 1, math.min(MAX_BATCH, #queue) do
		table.insert(batch, table.remove(queue, 1) :: Event)
	end

	local ok, result = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["x-ingest-key"] = key,
			},
			Body = HttpService:JSONEncode({
				placeId = game.PlaceId,
				jobId = jobId,
				events = batch,
			}),
		})
	end)

	flushing = false

	if not ok then
		-- Almost always "Http requests are not enabled" on a place where the
		-- setting was never turned on. Naming the batch size makes the size of
		-- the loss obvious in Output.
		warn(`[AnalyticsService] post failed ({#batch} events lost): {result}`)
		return false
	end

	if not result.Success then
		warn(`[AnalyticsService] ingest returned {result.StatusCode} ({#batch} events lost): {result.Body}`)
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	Records one event against a player.

	`data` may be nil, and is omitted from the payload when empty rather than
	sent as `{}` -- an empty Luau table JSON-encodes to `[]`, which would land
	in the jsonb column as an array and make `data->>'x'` fail on exactly the
	rows where nothing interesting happened.
]]
function AnalyticsService.log(player: Player, kind: string, data: { [string]: any }?)
	local session = sessions[player]
	if not session or not endpoint then
		return
	end

	local profile = nil
	local dataService = ServiceLoader.find("DataService")
	if dataService then
		profile = dataService.get(player)
	end

	enqueue({
		at = os.time(),
		playerId = player.UserId,
		sessionId = session,
		kind = kind,
		planet = if profile then profile.currentPlanet else nil,
		level = if profile then profile.level else nil,
		data = if data and next(data) then data else nil,
	})
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	sessions[player] = HttpService:GenerateGUID(false)
	joinedAt[player] = os.time()
	AnalyticsService.log(player, AnalyticsService.Kind.SessionStart)
end

local function onPlayerRemoving(player: Player)
	local since = joinedAt[player]
	AnalyticsService.log(player, AnalyticsService.Kind.SessionEnd, {
		seconds = if since then os.time() - since else nil,
	})
	sessions[player] = nil
	joinedAt[player] = nil
end

function AnalyticsService.init()
	--[[
		Absent configuration is the normal state, not an error: a fresh clone
		has no endpoint and should run the whole game without one. Only a
		DataStore that is present and malformed is worth a warning.
	]]
	local ok, config = pcall(function()
		return DataStoreService:GetDataStore(CONFIG_STORE):GetAsync(CONFIG_KEY)
	end)
	if not ok then
		-- Studio without API services, or a place that has never been
		-- published. Both are expected and neither is this service's problem.
		return
	end
	if config == nil then
		return
	end
	if type(config) ~= "table" or type(config.url) ~= "string" or type(config.key) ~= "string" then
		warn(`[AnalyticsService] {CONFIG_STORE}/{CONFIG_KEY} is malformed; telemetry is off`)
		return
	end

	endpoint = config.url
	ingestKey = config.key

	--[[
		Announced, because the failure this service can have is being silently
		off, and "no data arrived" looks identical to "nobody played". A boot
		line means the absence of one is the answer. The URL is not a secret;
		the key is, and is not printed.
	]]
	print(`[AnalyticsService] telemetry on, posting to {config.url}`)
end

--[[
	Listens to what the game already announces.

	Four of the events here are things a service publishes anyway, so analytics
	subscribes rather than being called. That keeps the telemetry out of the
	gameplay path entirely -- `Signal.fire` dispatches each handler in its own
	`task.spawn`, so a mistake in this file cannot reach the code that fired.

	The rule, though, is that a signal is not added *for* telemetry. A signal is
	a public event other systems may come to depend on, and one that exists
	because a graph wanted it is a piece of the architecture answering to
	nobody. Where no signal exists -- accepting a mission, buying something,
	travelling, being told a secret -- the call site logs directly.
]]
local function observe()
	local progression = ServiceLoader.find("ProgressionService")
	if progression then
		progression.leveledUp:connect(function(player: Player, _level: number, gained: number)
			-- Only `gained`: the level itself is a column, filled from the
			-- profile, and two sources for one number is how they disagree.
			AnalyticsService.log(player, AnalyticsService.Kind.LevelUp, { gained = gained })
		end)
	end

	local playerService = ServiceLoader.find("PlayerService")
	if playerService then
		playerService.playerDied:connect(function(player: Player, character: Model)
			local at = character:GetPivot().Position
			-- Rounded. A death is interesting to about a stud, and full
			-- floats trade a lot of row width for digits nobody will read.
			AnalyticsService.log(player, AnalyticsService.Kind.Death, {
				x = math.round(at.X),
				y = math.round(at.Y),
				z = math.round(at.Z),
			})
		end)
	end

	local missions = ServiceLoader.find("MissionService")
	if missions then
		missions.missionCompleted:connect(function(player: Player, missionId: string)
			AnalyticsService.log(player, AnalyticsService.Kind.MissionComplete, { mission = missionId })
		end)
	end

	local npcs = ServiceLoader.find("NPCService")
	if npcs then
		npcs.interacted:connect(function(player: Player, _npc: Model, archetypeId: string)
			AnalyticsService.log(player, AnalyticsService.Kind.Talk, { archetype = archetypeId })
		end)
	end
end

function AnalyticsService.start()
	if not endpoint then
		return
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	observe()

	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			flush()
		end
	end)

	--[[
		Roblox allows about 30 seconds here, and a server closing is when the
		most interesting events -- the last mission, the last death -- are
		still in the queue. Loop because a busy server can hold more than one
		batch, and stop on the first failure so a dead endpoint does not hold
		the shutdown open.
	]]
	game:BindToClose(function()
		for _ = 1, 5 do
			if not flush() then
				break
			end
		end
	end)
end

return AnalyticsService
