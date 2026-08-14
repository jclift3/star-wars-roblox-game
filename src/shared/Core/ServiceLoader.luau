--!strict
--[[
	ServiceLoader.luau

	Two-phase bootstrap for the game's services.

	A "service" is a ModuleScript returning a table that may define:
	  name     -- optional; defaults to the ModuleScript's name
	  priority -- optional; lower numbers initialise first (default 100)
	  init()   -- phase 1: set up state, register remotes. No cross-service calls.
	  start()  -- phase 2: everything is registered, so cross-service calls are safe.

	The two phases exist to kill load-order bugs. If NPCService needs
	DataService during setup, a single-phase loader forces you to care which
	file loads first. Here, `init` may only touch itself and `start` may touch
	anything, so order stops mattering.

	FAILURE POLICY
	The previous version of this project wrapped every require in a pcall that
	discarded the error. Its NPC module raised at require time, became nil, and
	no NPC ever spawned -- silently, for a year. So: failures here are caught
	(one broken service should not take the server down) but they are recorded
	and reported loudly at the end of boot, and `get()` on a failed service
	raises with the original error rather than handing back a nil.
]]

local ServiceLoader = {}

export type Service = {
	name: string?,
	priority: number?,
	init: (() -> ())?,
	start: (() -> ())?,
	[any]: any,
}

type Entry = {
	name: string,
	service: Service,
	priority: number,
	source: ModuleScript,
}

local registry: { [string]: Service } = {}
local failures: { [string]: string } = {}
local entries: { Entry } = {}
local started = false

local DEFAULT_PRIORITY = 100

--[[
	Loads every ModuleScript directly under `container`.

	Descendants are deliberately not scanned: services keep helper modules in
	child folders, and auto-loading those as services would run them twice.
]]
function ServiceLoader.addFrom(container: Instance)
	assert(not started, "ServiceLoader.addFrom: cannot add services after start()")

	for _, child in container:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, child)
		if not ok then
			failures[child.Name] = tostring(result)
			warn(`[ServiceLoader] failed to require {child:GetFullName()}: {result}`)
			continue
		end
		if type(result) ~= "table" then
			failures[child.Name] = `expected a table, got {type(result)}`
			warn(`[ServiceLoader] {child.Name} did not return a table`)
			continue
		end

		local service = result :: Service
		local name = service.name or child.Name
		if registry[name] then
			failures[name] = "duplicate service name"
			warn(`[ServiceLoader] duplicate service name "{name}" at {child:GetFullName()}`)
			continue
		end

		registry[name] = service
		table.insert(entries, {
			name = name,
			service = service,
			priority = service.priority or DEFAULT_PRIORITY,
			source = child,
		})
	end
end

local function runPhase(phase: string)
	for _, entry in entries do
		local fn = entry.service[phase]
		if type(fn) ~= "function" then
			continue
		end
		local startedAt = os.clock()
		local ok, err = pcall(fn)
		if ok then
			local elapsed = (os.clock() - startedAt) * 1000
			-- Slow phases block every later service, so surface them.
			if elapsed > 100 then
				warn(`[ServiceLoader] {entry.name}.{phase}() took {math.floor(elapsed)}ms`)
			end
		else
			failures[entry.name] = `{phase}(): {err}`
			registry[entry.name] = nil
			warn(`[ServiceLoader] {entry.name}.{phase}() errored: {err}`)
		end
	end
end

--- Runs init() on everything, then start() on everything. Safe to call once.
function ServiceLoader.start()
	assert(not started, "ServiceLoader.start: already started")
	started = true

	table.sort(entries, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.name < b.name
	end)

	runPhase("init")
	runPhase("start")

	local failed = 0
	for _ in failures do
		failed += 1
	end
	if failed == 0 then
		print(`[ServiceLoader] {#entries} services started.`)
	else
		-- A banner, because a single warn line gets lost in Studio's output.
		warn(`[ServiceLoader] {failed} SERVICE(S) FAILED -- the game is running degraded:`)
		for name, reason in failures do
			warn(`  - {name}: {reason}`)
		end
	end
end

--[[
	Fetches a started service by name.

	Raises rather than returning nil. A missing service is a programming error,
	and surfacing it at the call site with a real message beats a nil-index
	crash three frames later in unrelated code.
]]
function ServiceLoader.get(name: string): Service
	local service = registry[name]
	if service then
		return service
	end
	local reason = failures[name]
	if reason then
		error(`ServiceLoader.get("{name}"): service failed to load -- {reason}`, 2)
	end
	error(`ServiceLoader.get("{name}"): no such service`, 2)
end

--- Non-raising lookup, for genuinely optional dependencies.
function ServiceLoader.find(name: string): Service?
	return registry[name]
end

function ServiceLoader.isHealthy(): boolean
	return next(failures) == nil
end

return ServiceLoader
