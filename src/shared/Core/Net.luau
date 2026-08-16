--!strict
--[[
	Net.luau

	Thin, safe wrapper over RemoteEvent / RemoteFunction.

	The old version of this project trusted the client completely -- sprint speed
	was set client-side with no server check, and purchases were accepted on the
	client's word. Everything here is built on the opposite assumption: a remote
	is a hostile input until proven otherwise.

	Every server handler registered through this module gets:
	  - automatic per-player rate limiting
	  - an argument validator that runs before your handler ever sees the data
	  - errors contained to the offending call

	Remotes are created lazily and live under ReplicatedStorage/Shared/Remotes.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()

local Net = {}

local remotesFolder: Folder? = nil

local function getRemotesFolder(): Folder
	local cached = remotesFolder
	if cached and cached.Parent then
		return cached
	end

	local folder: Folder
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing and existing:IsA("Folder") then
			folder = existing
		else
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
	else
		-- A timed WaitForChild can return nil. If it does the client is
		-- unrecoverable anyway, so fail here with a message that says why
		-- rather than nil-indexing somewhere further along.
		local found = ReplicatedStorage:WaitForChild("Remotes", 30) :: Folder?
		folder = assert(found, "[Net] Remotes folder never replicated")
	end

	remotesFolder = folder
	return folder
end

local function getRemote(name: string, className: string): Instance
	local folder = getRemotesFolder()
	if IS_SERVER then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local r = Instance.new(className)
		r.Name = name
		r.Parent = folder
		return r
	end
	return assert(folder:WaitForChild(name, 30), `[Net] remote "{name}" never replicated`)
end

--------------------------------------------------------------------------------
-- Rate limiting
--------------------------------------------------------------------------------

type Bucket = { tokens: number, lastRefill: number }

local buckets: { [string]: { [Player]: Bucket } } = {}

--[[
	Token bucket per (remote, player). Returns false when the caller is over
	budget. Burst equals `perSecond`, so normal bursty UI traffic passes but a
	spam loop is throttled.
]]
local function consumeToken(remoteName: string, player: Player, perSecond: number): boolean
	local perRemote = buckets[remoteName]
	if not perRemote then
		perRemote = {}
		buckets[remoteName] = perRemote
	end

	local now = os.clock()
	local bucket = perRemote[player]
	if not bucket then
		bucket = { tokens = perSecond, lastRefill = now }
		perRemote[player] = bucket
	end

	bucket.tokens = math.min(perSecond, bucket.tokens + (now - bucket.lastRefill) * perSecond)
	bucket.lastRefill = now

	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Net.clearPlayer(player: Player)
	for _, perRemote in buckets do
		perRemote[player] = nil
	end
end

--------------------------------------------------------------------------------
-- Validators
--------------------------------------------------------------------------------

export type Validator = (...any) -> boolean

Net.check = {}

function Net.check.none(...: any): boolean
	return select("#", ...) == 0
end

function Net.check.string(maxLen: number?): Validator
	return function(v: any): boolean
		return type(v) == "string" and #v <= (maxLen or 200)
	end
end

function Net.check.number(min: number?, max: number?): Validator
	return function(v: any): boolean
		if type(v) ~= "number" or v ~= v then -- reject NaN
			return false
		end
		if min and v < min then
			return false
		end
		if max and v > max then
			return false
		end
		return true
	end
end

function Net.check.integer(min: number?, max: number?): Validator
	local numCheck = Net.check.number(min, max)
	return function(v: any): boolean
		return numCheck(v) and v % 1 == 0
	end
end

function Net.check.instanceOf(className: string): Validator
	return function(v: any): boolean
		return typeof(v) == "Instance" and v:IsA(className)
	end
end

function Net.check.vector3(maxMagnitude: number?): Validator
	return function(v: any): boolean
		if typeof(v) ~= "Vector3" then
			return false
		end
		-- Reject NaN/inf, which can be used to corrupt physics state.
		if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
			return false
		end
		if maxMagnitude and v.Magnitude > maxMagnitude then
			return false
		end
		return true
	end
end

function Net.check.optional(inner: Validator): Validator
	return function(v: any): boolean
		return v == nil or inner(v)
	end
end

function Net.check.oneOf(allowed: { string }): Validator
	local set = {}
	for _, a in allowed do
		set[a] = true
	end
	return function(v: any): boolean
		return type(v) == "string" and set[v] == true
	end
end

--- Builds a validator for a fixed argument list.
function Net.args(...: Validator): Validator
	local validators = { ... }
	return function(...: any): boolean
		if select("#", ...) > #validators then
			return false
		end
		local values = table.pack(...)
		for i, validate in validators do
			if not validate(values[i]) then
				return false
			end
		end
		return true
	end
end

--------------------------------------------------------------------------------
-- Server API
--------------------------------------------------------------------------------

export type HandlerOptions = {
	rateLimit: number?, -- calls per second, default 10
	validate: Validator?,
}

--[[
	Registers a server-side handler for a RemoteEvent.

	The handler is only invoked if the caller is within its rate limit AND the
	arguments pass validation, so handler bodies can assume clean input.
]]
function Net.onServerEvent(name: string, handler: (Player, ...any) -> (), options: HandlerOptions?)
	assert(IS_SERVER, "Net.onServerEvent can only be called on the server")
	local opts: HandlerOptions = options or {}
	local limit = opts.rateLimit or 10
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent

	remote.OnServerEvent:Connect(function(player: Player, ...)
		if not consumeToken(name, player, limit) then
			return
		end
		if opts.validate and not opts.validate(...) then
			warn(`[Net] rejected malformed "{name}" from {player.Name}`)
			return
		end
		local ok, err = pcall(handler :: any, player, ...)
		if not ok then
			warn(`[Net] handler "{name}" errored: {err}`)
		end
	end)
end

--[[
	Registers a server-side handler for a RemoteFunction.

	Returns nil to the client on rate-limit, validation failure, or handler error,
	so a misbehaving client never learns why it was rejected.
]]
function Net.onServerInvoke(name: string, handler: (Player, ...any) -> any, options: HandlerOptions?)
	assert(IS_SERVER, "Net.onServerInvoke can only be called on the server")
	local opts: HandlerOptions = options or {}
	local limit = opts.rateLimit or 5
	local remote = getRemote(name, "RemoteFunction") :: RemoteFunction

	remote.OnServerInvoke = function(player: Player, ...)
		if not consumeToken(name, player, limit) then
			return nil
		end
		if opts.validate and not opts.validate(...) then
			warn(`[Net] rejected malformed "{name}" from {player.Name}`)
			return nil
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(`[Net] invoke "{name}" errored: {result}`)
			return nil
		end
		return result
	end
end

function Net.fireClient(name: string, player: Player, ...: any)
	assert(IS_SERVER, "Net.fireClient can only be called on the server")
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent
	remote:FireClient(player, ...)
end

function Net.fireAllClients(name: string, ...: any)
	assert(IS_SERVER, "Net.fireAllClients can only be called on the server")
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent
	remote:FireAllClients(...)
end

--- Fires to every player except one -- used for effects the actor already saw locally.
function Net.fireAllExcept(name: string, except: Player, ...: any)
	assert(IS_SERVER, "Net.fireAllExcept can only be called on the server")
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent
	for _, p in game:GetService("Players"):GetPlayers() do
		if p ~= except then
			remote:FireClient(p, ...)
		end
	end
end

--------------------------------------------------------------------------------
-- Client API
--------------------------------------------------------------------------------

function Net.fireServer(name: string, ...: any)
	assert(not IS_SERVER, "Net.fireServer can only be called on the client")
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent
	remote:FireServer(...)
end

function Net.invokeServer(name: string, ...: any): any
	assert(not IS_SERVER, "Net.invokeServer can only be called on the client")
	local remote = getRemote(name, "RemoteFunction") :: RemoteFunction
	local ok, result = pcall(function(...)
		return remote:InvokeServer(...)
	end, ...)
	if not ok then
		warn(`[Net] invokeServer "{name}" failed: {result}`)
		return nil
	end
	return result
end

function Net.onClientEvent(name: string, handler: (...any) -> ()): RBXScriptConnection
	assert(not IS_SERVER, "Net.onClientEvent can only be called on the client")
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent
	return remote.OnClientEvent:Connect(function(...)
		local ok, err = pcall(handler :: any, ...)
		if not ok then
			warn(`[Net] client handler "{name}" errored: {err}`)
		end
	end)
end

--- Every remote name used in the game, so typos become load-time errors.
Net.Event = {
	-- Progression / data
	ProfileUpdated = "ProfileUpdated",
	Notify = "Notify",
	SpendSkillPoint = "SpendSkillPoint",
	-- Combat
	FireWeapon = "FireWeapon",
	WeaponEffect = "WeaponEffect",
	EquipWeapon = "EquipWeapon",
	ToggleSaber = "ToggleSaber",
	SaberSwing = "SaberSwing",
	DamageDealt = "DamageDealt",
	-- Missions
	MissionUpdated = "MissionUpdated",
	AcceptMission = "AcceptMission",
	AbandonMission = "AbandonMission",
	TrackMission = "TrackMission",
	-- Shop / inventory
	PurchaseItem = "PurchaseItem",
	SellItem = "SellItem",
	DiscardItem = "DiscardItem",
	EquipOutfit = "EquipOutfit",
	-- Travel
	TravelTo = "TravelTo",
	Travelled = "Travelled",
	-- Dialogue
	StartDialogue = "StartDialogue",
	DialogueChoice = "DialogueChoice",
	EndDialogue = "EndDialogue",
	-- Sprint (server-authoritative, unlike the old client-only version)
	SetSprinting = "SetSprinting",
} :: { [string]: string }

Net.Function = {
	GetProfile = "GetProfile",
	GetMissionBoard = "GetMissionBoard",
	GetInventory = "GetInventory",
	GetGalaxy = "GetGalaxy",
} :: { [string]: string }

--[[
	Creates every declared remote up front. Server-only, called once at boot.

	Without this, a remote only exists after the server first uses it -- so a
	client listening for a rare event (a mission update, a level-up notice)
	would sit in WaitForChild until the first one happened, and time out if it
	never did. Creating them all is cheap and removes the whole class of bug.
]]
function Net.ensureRemotes()
	assert(IS_SERVER, "Net.ensureRemotes can only be called on the server")
	for _, name in Net.Event do
		getRemote(name, "RemoteEvent")
	end
	for _, name in Net.Function do
		getRemote(name, "RemoteFunction")
	end
end

return Net
