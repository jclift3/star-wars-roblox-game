--!strict
--[[
	DataService.luau

	Owns every player's saved profile: loading, session locking, autosaving and
	migration.

	WHY SESSION LOCKING
	Roblox can run the same player on two servers at once (a bad teleport, a
	rejoin during shutdown). Without a lock, both servers load the same profile
	and the last one to save wins -- which is how credits and items get
	duplicated. We take a lock in the datastore before handing out the profile,
	and refuse to load if another live server holds it.

	WHY THIS IS NOT THE OLD VERSION
	The previous project called SetAsync on join and never called GetAsync at
	all, so every session started from defaults and every save was overwritten.
	Loading is therefore the part of this file most worth reading carefully.

	STUDIO
	DataStores are unavailable in Studio unless API access is enabled. Rather
	than erroring or silently losing data, we detect the failure once and fall
	back to an in-memory profile, so the game is fully playable in Studio and
	the developer is told exactly why nothing is persisting.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Core.Signal)
local Net = require(Shared.Core.Net)
local Inventory = require(Shared.Core.Inventory)
local Alignment = require(Shared.Config.Alignment)
local Factions = require(Shared.Config.Factions)
local Flags = require(Shared.Config.Flags)
local Furnishings = require(Shared.Config.Furnishings)
local Origins = require(Shared.Config.Origins)
local Planets = require(Shared.Config.Planets)
local Progression = require(Shared.Config.Progression)
local Ships = require(Shared.Config.Ships)

type PlayerProfile = Types.PlayerProfile

local DataService = {
	name = "DataService",
	-- Everything else depends on profiles existing, so this goes first.
	priority = 1,
}

-- 2: `inventory` became stacks keyed by uid rather than a bag of counts.
-- Nothing branches on this -- `migrate` works field by field so a save from a
-- half-deployed build still loads -- it is a record of what the shape is.
local PROFILE_VERSION = 2
local STORE_NAME = "PlayerProfiles_v1"
local AUTOSAVE_INTERVAL = 90

-- A lock older than this is assumed to belong to a server that crashed. Long
-- enough that a live server always refreshes it first (it autosaves every 90s),
-- short enough that a genuine crash does not lock a player out for long.
local LOCK_STALE_AFTER = 300

local RETRY_ATTEMPTS = 4
local RETRY_BASE_DELAY = 1

--[[
	Resolved on first use, never at require time.

	`GetDataStore` throws outright in an unpublished place ("You must publish
	this place to the web to access DataStore"). Calling it at module scope made
	that a require-time error, which took down this service and every service
	that depends on it -- so the memory-only fallback below, whose entire job is
	to survive exactly this situation, could never run.
]]
local store: GlobalDataStore? = nil

local function getStore(): GlobalDataStore
	if not store then
		store = DataStoreService:GetDataStore(STORE_NAME)
	end
	return store :: GlobalDataStore
end

local profiles: { [Player]: PlayerProfile } = {}
local loading: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
-- Set once if the datastore is unreachable (Studio without API access).
local datastoreAvailable = true

DataService.profileLoaded = Signal.new()
DataService.profileChanged = Signal.new()

--------------------------------------------------------------------------------
-- Defaults and migration
--------------------------------------------------------------------------------

local function defaultProfile(): PlayerProfile
	local rep = {}
	local paid = {}
	for _, id in Factions.ids() do
		rep[id] = 0
		-- Rank 1 is the bottom of every ladder and pays nothing, so starting
		-- here means the first real promotion is the first payout.
		paid[id] = 1
	end

	return {
		version = PROFILE_VERSION,
		credits = 250,
		level = 1,
		xp = 0,
		skillPoints = Progression.STARTING_SKILL_POINTS,
		skills = {},
		-- A placeholder until the player picks. It is deliberately the origin
		-- with no patron and no restrictions, so a character who somehow never
		-- chooses is never one that cannot get somewhere.
		origin = Origins.DEFAULT,
		originChosen = false,
		alignment = Alignment.START,
		flags = {},
		faction = Factions.DEFAULT,
		factionRep = rep,
		factionRankPaid = paid,
		homePlanet = Planets.STARTING_PLANET,
		currentPlanet = Planets.STARTING_PLANET,
		lastTravelAt = 0,
		-- The starting kit has to be *owned*, not merely equipped: every equip
		-- path checks the inventory, so a weapon you begin holding but do not
		-- own is one you can put down exactly once.
		inventory = Inventory.load({ StimPack = 2, DH17 = 1, Smuggler = 1 }),
		equipped = { weapon = "DH17", offhand = nil, outfit = "Smuggler", ship = nil },
		-- Empty, and it used to say `{ "Skiff" }` -- an id no config has ever
		-- defined, which nothing read and so nothing complained about. A
		-- speeder is the first real thing to save up for; being handed one
		-- would have taken that away.
		unlockedShips = {},
		-- Empty for the same reason, and one step stronger: a cabin you were
		-- handed furnished is a room you never chose anything about.
		unlockedFurnishings = {},
		cabin = {},
		missions = {
			active = {},
			completed = {},
			lastCompleted = {},
		},
		stats = {
			playtime = 0,
			kills = 0,
			deaths = 0,
			missionsCompleted = 0,
			lightYearsTravelled = 0,
		},
		createdAt = os.time(),
		lastSeen = os.time(),
	}
end

DataService.defaultProfile = defaultProfile

--[[
	Brings an older saved profile up to the current schema.

	Runs field-by-field rather than by version number so a profile saved by a
	half-deployed build still ends up valid. Adding a field to PlayerProfile
	means adding a line here.
]]
local function migrate(saved: any): PlayerProfile
	local base = defaultProfile()
	if type(saved) ~= "table" then
		return base
	end

	local function take(key: string)
		if saved[key] ~= nil then
			(base :: any)[key] = saved[key]
		end
	end

	for _, key in
		{
			"credits",
			"level",
			"xp",
			"skillPoints",
			"origin",
			"faction",
			"homePlanet",
			"currentPlanet",
			"lastTravelAt",
			"createdAt",
		}
	do
		take(key)
	end

	if type(saved.skills) == "table" then
		base.skills = saved.skills
	end
	-- Always through `Inventory.load`, never taken as-is: profiles saved before
	-- stacks existed hold `{ [itemId]: count }`, and that is where it is turned
	-- back into something the rest of the game can read.
	if saved.inventory ~= nil then
		base.inventory = Inventory.load(saved.inventory)
	end
	if type(saved.equipped) == "table" then
		base.equipped = saved.equipped
	end
	-- Clamped on the way in rather than trusted: the bounds have moved once
	-- already in this project's life and a saved value outside them would put
	-- the player in a band `Alignment.bandFor` cannot name.
	if type(saved.alignment) == "number" then
		base.alignment = Alignment.clamp(saved.alignment)
	end
	--[[
		Copied key by key, skipping any flag that is no longer declared.

		Taking the table wholesale would keep a retired flag alive forever in
		every old save, so `Flags.validate`-style checks would pass while the
		data disagreed. A flag deleted from Config is a flag that stops being
		true, which is the only reading that matches what the author did.
	]]
	if type(saved.flags) == "table" then
		for id, value in saved.flags do
			if value == true and Flags.exists(id) then
				base.flags[id] = true
			end
		end
	end
	-- Filtered for the same reason flags are, and with a live example: every
	-- profile saved before speeders existed holds `{ "Skiff" }`, a ship id
	-- that no config has ever defined.
	if type(saved.unlockedShips) == "table" then
		for _, id in saved.unlockedShips do
			if type(id) == "string" and Ships.exists(id) then
				table.insert(base.unlockedShips, id)
			end
		end
	end

	if type(saved.unlockedFurnishings) == "table" then
		for _, id in saved.unlockedFurnishings do
			if type(id) == "string" and Furnishings.exists(id) then
				table.insert(base.unlockedFurnishings, id)
			end
		end
	end
	--[[
		A placed furnishing has to survive two filters, not one.

		It must still exist, and it must still belong to the slot it is
		filed under -- moving a piece from Trophy to Console in config would
		otherwise leave it standing in an old profile at coordinates
		`Furnishings.validate` has never measured it against.
	]]
	if type(saved.cabin) == "table" then
		for slotId, id in saved.cabin do
			if
				type(slotId) == "string"
				and type(id) == "string"
				and Furnishings.exists(id)
				and Furnishings.get(id).slot == slotId
			then
				base.cabin[slotId] = id
			end
		end
	end

	-- Reputation is merged rather than replaced, so a faction added after this
	-- profile was saved starts at 0 instead of being missing entirely.
	if type(saved.factionRep) == "table" then
		for id, value in saved.factionRep do
			if type(value) == "number" and Factions.exists(id) then
				base.factionRep[id] = value
			end
		end
	end

	-- Seeded from the rep that was just merged, not from the bottom of the
	-- ladder: a profile saved before stipends existed already holds its ranks,
	-- and paying it for all of them on the next login would be a windfall for
	-- standing it earned under the old rules.
	for id, value in base.factionRep do
		base.factionRankPaid[id] = Factions.rankIndexFor(id, value)
	end
	if type(saved.factionRankPaid) == "table" then
		for id, value in saved.factionRankPaid do
			if type(value) == "number" and Factions.exists(id) then
				base.factionRankPaid[id] = value
			end
		end
	end

	if type(saved.missions) == "table" then
		base.missions.active = saved.missions.active or {}
		base.missions.completed = saved.missions.completed or {}
		base.missions.lastCompleted = saved.missions.lastCompleted or {}
	end
	if type(saved.stats) == "table" then
		for key, value in saved.stats do
			if type(value) == "number" then
				(base.stats :: any)[key] = value
			end
		end
	end

	-- A planet that has been removed from the game would strand the player.
	if not Planets.exists(base.currentPlanet) then
		base.currentPlanet = Planets.STARTING_PLANET
	end
	if not Planets.exists(base.homePlanet) then
		base.homePlanet = Planets.STARTING_PLANET
	end
	if not Factions.exists(base.faction) then
		base.faction = Factions.DEFAULT
	end
	-- Every profile saved before origins existed comes back without one, which
	-- is the same case as an origin that was later renamed.
	if not Origins.exists(base.origin) then
		base.origin = Origins.DEFAULT
	end
	--[[
		Deliberately NOT inferred from `origin` being present.

		Every profile saved before the creation screen carries
		`origin = Origins.DEFAULT`, written by `defaultProfile` rather than
		chosen by anybody -- which is the gap the screen exists to close. So
		an old save falls through to `false` and gets asked once, and only a
		save that recorded the answer skips it.
	]]
	if type(saved.originChosen) == "boolean" then
		base.originChosen = saved.originChosen
	end

	base.version = PROFILE_VERSION
	return base
end

--------------------------------------------------------------------------------
-- Datastore plumbing
--------------------------------------------------------------------------------

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

--[[
	Retries a datastore call with exponential backoff.

	Roblox throttles datastore traffic and returns errors rather than queueing,
	so a single failed attempt means nothing. Persistent failure sets
	`datastoreAvailable = false` once, which flips the whole service into
	memory-only mode instead of spamming the log on every subsequent call.
]]
local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	-- Already known unreachable. Without this every join and every autosave
	-- would spend the full backoff again on a failure that cannot recover
	-- within the session.
	if not datastoreAvailable then
		return false, nil
	end

	local lastErr: any
	for attempt = 1, RETRY_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < RETRY_ATTEMPTS then
			task.wait(RETRY_BASE_DELAY * 2 ^ (attempt - 1))
		end
	end

	if datastoreAvailable then
		datastoreAvailable = false
		warn(`[DataService] {label} failed after {RETRY_ATTEMPTS} attempts: {lastErr}`)
		if RunService:IsStudio() then
			warn("[DataService] Running in Studio without DataStore access.")
			warn("[DataService] Profiles will work but WILL NOT SAVE.")
			warn("[DataService] Enable Game Settings > Security > Studio Access to API Services to persist.")
		end
	end
	return false, nil
end

type Stored = {
	data: PlayerProfile?,
	lockJobId: string?,
	lockedAt: number?,
}

--[[
	Acquires the session lock and returns the stored profile in one UpdateAsync.

	Doing both in a single transaction is what makes the lock meaningful: a
	separate read-then-write would leave a window where two servers both see the
	profile unlocked.
]]
local function acquireAndLoad(player: Player): PlayerProfile?
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	local now = os.time()
	local blocked = false

	local ok, result = retry(`load {player.Name}`, function()
		return getStore():UpdateAsync(keyFor(player), function(old: Stored?): Stored?
			-- Reset per attempt: an earlier attempt may have thrown before
			-- reaching the lock check, and a stale flag would deny a valid load.
			blocked = false
			local stored: Stored = old or {}

			local heldBy = stored.lockJobId
			local heldAt = stored.lockedAt or 0
			if heldBy and heldBy ~= jobId and (now - heldAt) < LOCK_STALE_AFTER then
				-- Another live server owns this profile. Abort the write by
				-- returning nil, and tell the caller outside the transaction.
				blocked = true
				return nil
			end

			stored.lockJobId = jobId
			stored.lockedAt = now
			return stored
		end)
	end)

	if blocked then
		return nil
	end
	if not ok then
		-- Datastore is unreachable; hand back a fresh profile so the player can
		-- still play. Saving is already disabled at this point.
		return defaultProfile()
	end

	local stored = result :: Stored?
	return migrate(stored and stored.data)
end

--- Writes the profile back, optionally refreshing or releasing the lock.
local function writeProfile(player: Player, profile: PlayerProfile, release: boolean): boolean
	if not datastoreAvailable then
		return false
	end

	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	profile.lastSeen = os.time()
	local lostLock = false

	local ok = retry(`save {player.Name}`, function()
		return getStore():UpdateAsync(keyFor(player), function(old: Stored?): Stored?
			lostLock = false
			local stored: Stored = old or {}

			-- Refuse to overwrite a profile another server has taken over. This
			-- is the second half of the lock: without it, a server that lost the
			-- lock would still clobber the new session on its next autosave.
			if stored.lockJobId and stored.lockJobId ~= jobId then
				lostLock = true
				return nil
			end

			stored.data = profile
			if release then
				stored.lockJobId = nil
				stored.lockedAt = nil
			else
				stored.lockedAt = os.time()
			end
			return stored
		end)
	end)

	if lostLock then
		-- Another server owns this session now. Anything we hold is stale, so
		-- report failure rather than letting the caller clear its dirty flag.
		warn(`[DataService] lost session lock for {player.Name}; save discarded`)
		return false
	end
	return ok
end

--------------------------------------------------------------------------------
-- Replication
--------------------------------------------------------------------------------

--[[
	The slice of the profile the client is allowed to see.

	Sent wholesale rather than diffed: a profile is small, and a correct full
	replacement beats a clever patch that can drift out of sync.
]]
local function clientView(profile: PlayerProfile)
	return {
		credits = profile.credits,
		level = profile.level,
		xp = profile.xp,
		skillPoints = profile.skillPoints,
		skills = profile.skills,
		origin = profile.origin,
		originChosen = profile.originChosen,
		alignment = profile.alignment,
		flags = profile.flags,
		faction = profile.faction,
		factionRep = profile.factionRep,
		currentPlanet = profile.currentPlanet,
		homePlanet = profile.homePlanet,
		inventory = profile.inventory,
		equipped = profile.equipped,
		unlockedShips = profile.unlockedShips,
		unlockedFurnishings = profile.unlockedFurnishings,
		cabin = profile.cabin,
		missions = profile.missions,
		stats = profile.stats,
	}
end

local function replicate(player: Player)
	local profile = profiles[player]
	if profile then
		Net.fireClient(Net.Event.ProfileUpdated, player, clientView(profile))
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- The player's profile, or nil if it is still loading or failed to load.
function DataService.get(player: Player): PlayerProfile?
	return profiles[player]
end

--[[
	Waits for a profile, up to `timeout` seconds.

	Services that run on CharacterAdded need this: the character can spawn
	before the datastore round-trip finishes.
]]
function DataService.await(player: Player, timeout: number?): PlayerProfile?
	local deadline = os.clock() + (timeout or 20)
	while os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			return profile
		end
		if not loading[player] and not player:IsDescendantOf(Players) then
			return nil
		end
		task.wait(0.1)
	end
	return profiles[player]
end

--[[
	The only sanctioned way to change a profile.

	Takes a mutator so every write goes through one place that marks the profile
	dirty and replicates it. Direct mutation of the table returned by `get` will
	appear to work and then quietly fail to save, so don't.
]]
function DataService.update(player: Player, mutate: (PlayerProfile) -> ()): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	mutate(profile)
	dirty[player] = true
	replicate(player)
	DataService.profileChanged:fire(player, profile)
	return true
end

--- Forces a save now. Returns false if there was nothing to save.
function DataService.save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local ok = writeProfile(player, profile, release == true)
	if ok then
		dirty[player] = false
	end
	return ok
end

function DataService.isPersisting(): boolean
	return datastoreAvailable
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	loading[player] = true

	local profile = acquireAndLoad(player)

	-- The player may have left during the datastore round-trip.
	if not player:IsDescendantOf(Players) then
		loading[player] = nil
		if profile then
			writeProfile(player, profile, true)
		end
		return
	end

	loading[player] = nil

	if not profile then
		player:Kick("Your save is still active on another server. Please wait about a minute and rejoin.")
		return
	end

	profiles[player] = profile
	replicate(player)
	DataService.profileLoaded:fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	dirty[player] = nil
	Net.clearPlayer(player)

	if profile then
		-- Release the lock on the way out so a fast rejoin is not blocked.
		writeProfile(player, profile, true)
	end
end

function DataService.init()
	Net.onServerInvoke(Net.Function.GetProfile, function(player: Player)
		local profile = profiles[player]
		return profile and clientView(profile) or nil
	end, { rateLimit = 2, validate = Net.check.none })
end

function DataService.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Autosave loop. Staggered per player inside the loop would be tidier, but
	-- profiles are small and the write budget is per-key, not per-server.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				profile.stats.playtime += AUTOSAVE_INTERVAL
				if dirty[player] then
					-- Not released: this server still owns the session.
					if writeProfile(player, profile, false) then
						dirty[player] = false
					end
				else
					-- Nothing changed, but the lock still needs refreshing or
					-- another server will consider it stale and steal it.
					writeProfile(player, profile, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				writeProfile(player, profile, true)
				pending -= 1
			end)
		end
		-- Roblox gives roughly 30 seconds on shutdown; use what we need of it.
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return DataService
