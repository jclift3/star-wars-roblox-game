--!strict
--[[
	NPCService.luau

	Owns the population: who exists, where, and when they think.

	ONE LOOP, NOT HUNDREDS
	Every brain is stepped from a single Heartbeat accumulator here. The
	previous version gave each NPC its own `while true do task.wait() end`,
	which turns a crowd into hundreds of independent schedulers. Worse, a
	single error inside one of those loops kills that NPC silently forever.
	Centrally, an erroring brain is visible and the rest keep running.

	LEVEL OF DETAIL
	Distance decides how much thinking an NPC gets. Close by: full sensing.
	Middle distance: movement only, since nothing is within sight range
	anyway. Far away: a slow heartbeat so patrols still drift and the world
	is not obviously frozen when you arrive.

	LAZY PER-PLANET POPULATION
	Eight worlds share one server. Populating all of them would cost eight
	times what any player can see. A planet is populated when someone is on
	it and released a while after the last player leaves -- the delay matters
	because a player hopping to a vendor and back should not rebuild a city.

	MAP CONTRACT
	Spawn zones are read from Workspace/Zones/<PlanetId>/<ZoneName>, which
	holds one or more parts. A zone with several parts also doubles as a
	patrol route. If a planet has no zones the service falls back to
	scattering around its spawn points, so an unfinished map still shows a
	living world instead of nothing at all.

	Parts are handed out emptiest-first rather than at random. That is what
	makes a part able to mean somewhere in particular -- the inside of a shop,
	a landmark's back room -- instead of only a slice of a patrol ring, and it
	is why a district with rooms in it needs about as many people as it has
	places rather than as many as it looks like it needs.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cast = require(Shared.Config.Cast)
local NPCArchetypes = require(Shared.Config.NPCArchetypes)
local NPCNames = require(Shared.Config.NPCNames)
local Planets = require(Shared.Config.Planets)
local RigBuilder = require(Shared.Rig.RigBuilder)
local WeaponModel = require(Shared.Rig.WeaponModel)
local Signal = require(Shared.Core.Signal)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local NPCBrain = require(script.Parent.Parent.NPC.NPCBrain)

local NPCService = {
	name = "NPCService",
	priority = 40,
}

-- How often the brain pass runs. 8Hz is well under the animation rate and far
-- more than a walking NPC needs to make decisions.
local TICK_INTERVAL = 0.125
-- Within this range of a player an NPC senses as well as moves.
local FULL_DISTANCE = 220
-- Beyond this an NPC drops to a slow heartbeat.
local ACTIVE_DISTANCE = 520
local DORMANT_INTERVAL = 1.5

-- Hard ceiling across all planets. A safety net, not a design target.
local MAX_NPCS = 260

local DEATH_FADE = 2.5
local DEATH_LINGER = 6
local RESPAWN_DELAY_MIN = 25
local RESPAWN_DELAY_MAX = 55

-- How long a planet keeps its population after its last player leaves.
local DEPOPULATE_GRACE = 90
local POPULATION_CHECK_INTERVAL = 5

-- Radius around a spawn point used when a planet has no zone folders.
local FALLBACK_SCATTER = 70

type SpawnRule = Planets.SpawnRule

type Record = {
	model: Model,
	brain: NPCBrain.Brain,
	root: BasePart,
	planetId: string,
	rule: SpawnRule,
	--- The zone part this one was placed on, so it can be given back on death.
	stand: BasePart?,
	nextStepAt: number,
}

type PendingSpawn = {
	planetId: string,
	rule: SpawnRule,
	at: number,
}

local records: { [Model]: Record } = {}
local liveCount = 0
local pending: { PendingSpawn } = {}

local populated: { [string]: boolean } = {}
local emptySince: { [string]: number } = {}
local warnedMissingZones: { [string]: boolean } = {}

local rng = Random.new()
local variantCache: { [string]: NPCArchetypes.Archetype } = {}

--[[
	How many living NPCs each zone part is currently holding.

	Placement used to be a uniform roll over a zone's parts, which clumps: with
	nine places and nine people the odds of every place being used are about
	one in a thousand. That was invisible while every part was a slice of the
	same patrol ring -- three traders on one spoke and none on the next is a
	crowd either way -- and stopped being invisible the moment a part meant the
	inside of a particular shop. A shop with nobody in it is the thing the
	interiors work exists to avoid.
]]
local standing: { [BasePart]: number } = {}

--- Fired when a player triggers an NPC's proximity prompt. DialogueService and
--- the shop system listen here rather than owning their own prompts.
NPCService.interacted = Signal.new()

local function data()
	return ServiceLoader.get("DataService")
end

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------

local function npcFolder(planetId: string): Folder
	local root = Workspace:FindFirstChild("NPCs")
	if not root then
		local f = Instance.new("Folder")
		f.Name = "NPCs"
		f.Parent = Workspace
		root = f
	end

	local sub = root:FindFirstChild(planetId)
	if not sub then
		local f = Instance.new("Folder")
		f.Name = planetId
		f.Parent = root
		sub = f
	end
	return sub :: Folder
end

--- The parts making up a named zone, sorted so patrol routes are deterministic.
local function zoneParts(planetId: string, zoneName: string?): { BasePart }
	local zones = Workspace:FindFirstChild("Zones")
	local planetZones = zones and zones:FindFirstChild(planetId)
	if not planetZones then
		return {}
	end

	local folder = if zoneName then planetZones:FindFirstChild(zoneName) else planetZones
	if not folder then
		return {}
	end

	local out: { BasePart } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(out, child)
		end
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

--- Spawn points, used when a planet has no zone folders yet.
local function fallbackParts(planetId: string): { BasePart }
	local spawns = Workspace:FindFirstChild("Spawns")
	local folder = spawns and spawns:FindFirstChild(planetId)
	if not folder then
		return {}
	end

	local out: { BasePart } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(out, child)
		end
	end
	return out
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false

--[[
	Picks a standing position somewhere on `part`.

	The downward raycast is what keeps a zone usable as a rough volume rather
	than a precisely-placed pad: a builder can drop a big box over a market and
	the NPCs still end up on the floor of it.
]]
local function pointOn(part: BasePart, scatter: number?): CFrame
	local spread = scatter or 0
	local halfX = part.Size.X * 0.5 + spread
	local halfZ = part.Size.Z * 0.5 + spread

	local local_ = Vector3.new(rng:NextNumber(-halfX, halfX), 0, rng:NextNumber(-halfZ, halfZ))
	-- CFrame * Vector3 is already a world-space Vector3, not a CFrame.
	local surface = part.CFrame * (local_ + Vector3.new(0, part.Size.Y * 0.5, 0))

	-- Ignore the crowd itself, or later NPCs end up standing on earlier ones.
	local crowd = Workspace:FindFirstChild("NPCs")
	groundParams.FilterDescendantsInstances = if crowd then { crowd } else {}

	local hit = Workspace:Raycast(surface + Vector3.new(0, 12, 0), Vector3.new(0, -400, 0), groundParams)

	local position = if hit then hit.Position + Vector3.new(0, 3.5, 0) else surface + Vector3.new(0, 3.5, 0)
	return CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
end

--[[
	The emptiest of `parts`, ties broken at random.

	Least-used rather than round-robin because a respawn has to fall back into
	the gap the death left: a merchant killed in his own shop returns to it,
	instead of the whole district shuffling one place along every time anybody
	dies.
]]
local function leastUsed(parts: { BasePart }): BasePart
	local best: { BasePart } = {}
	local fewest = math.huge

	for _, part in parts do
		local used = standing[part] or 0
		if used < fewest then
			fewest = used
			best = { part }
		elseif used == fewest then
			table.insert(best, part)
		end
	end

	return best[rng:NextInteger(1, #best)]
end

--- Gives a place back: on death, or on a rig that failed to finish building.
local function release(stand: BasePart?)
	if stand then
		standing[stand] = math.max(0, (standing[stand] or 0) - 1)
	end
end

--- Where one NPC of `rule` should stand, plus a patrol route if the zone has one.
local function placementFor(planetId: string, rule: SpawnRule): (CFrame?, { Vector3 }, BasePart?)
	local parts = zoneParts(planetId, rule.zone)
	local scatter: number? = nil

	if #parts == 0 then
		parts = fallbackParts(planetId)
		scatter = FALLBACK_SCATTER
		if #parts > 0 and not warnedMissingZones[planetId] then
			warnedMissingZones[planetId] = true
			warn(`[NPCService] no Zones folder for "{planetId}"; scattering around spawn points`)
		end
	end

	if #parts == 0 then
		return nil, {}, nil
	end

	local stand = leastUsed(parts)
	standing[stand] = (standing[stand] or 0) + 1
	local home = pointOn(stand, scatter)

	local route: { Vector3 } = {}
	if #parts > 1 and not scatter then
		for _, p in parts do
			table.insert(route, p.Position)
		end
	end

	return home, route, stand
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------

--[[
	A per-spawn copy of an archetype, for NPCs that failed their `weaponChance`
	roll or whose spawn rule overrides the default behaviour.

	Swapping the brain's whole archetype reference (rather than just its state)
	matters because the brain returns to `archetype.behavior` when it leaves
	combat. Overriding only the current state would quietly revert the first
	time the NPC was shot at.
]]
local function variantFor(archetypeId: string, armed: boolean, behavior: string?): NPCArchetypes.Archetype
	local base = NPCArchetypes.get(archetypeId)
	if armed and not behavior then
		return base
	end

	local key = `{archetypeId}|{armed}|{behavior or "-"}`
	local cached = variantCache[key]
	if cached then
		return cached
	end

	local variant = table.clone(base)
	if not armed then
		variant.weapon = nil
	end
	if behavior then
		variant.behavior = behavior
	end
	variantCache[key] = variant
	return variant
end

local function addPrompt(
	model: Model,
	root: BasePart,
	archetype: NPCArchetypes.Archetype,
	displayName: string
)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Interact"
	prompt.ActionText = if archetype.shop then "Trade" else "Talk"
	prompt.ObjectText = displayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	prompt.Triggered:Connect(function(player: Player)
		NPCService.interacted:fire(player, model, archetype.id)
	end)
end

local function scheduleRespawn(planetId: string, rule: SpawnRule)
	table.insert(pending, {
		planetId = planetId,
		rule = rule,
		at = os.clock() + rng:NextNumber(RESPAWN_DELAY_MIN, RESPAWN_DELAY_MAX),
	})
end

--[[
	Fades a corpse out and removes it.

	Bodies stay long enough to read as a consequence, then leave. Letting them
	pile up is both a memory leak and a raycast cost on every later shot.
]]
local function retireCorpse(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = false
		end
	end

	task.delay(DEATH_LINGER - DEATH_FADE, function()
		if not model.Parent then
			return
		end
		local info = TweenInfo.new(DEATH_FADE, Enum.EasingStyle.Linear)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				TweenService:Create(d, info, { Transparency = 1 }):Play()
			end
		end
	end)

	Debris:AddItem(model, DEATH_LINGER)
end

local function despawn(record: Record, respawn: boolean)
	if not records[record.model] then
		return
	end
	records[record.model] = nil
	liveCount -= 1

	release(record.stand)
	record.brain:destroy()

	if respawn then
		scheduleRespawn(record.planetId, record.rule)
	end
end

--- Builds and places one NPC. Returns nil when the map gives it nowhere to go.
local function spawnOne(planetId: string, rule: SpawnRule): Record?
	if liveCount >= MAX_NPCS then
		return nil
	end
	if not NPCArchetypes.exists(rule.archetype) then
		warn(`[NPCService] planet "{planetId}" references unknown archetype "{rule.archetype}"`)
		return nil
	end

	local home, route, stand = placementFor(planetId, rule)
	if not home then
		return nil
	end

	local archetype = NPCArchetypes.get(rule.archetype)

	--[[
		A named character overrides the two things that make a crowd a crowd.

		A rolled name and a district-derived level are right for the eleventh
		Cartel enforcer and wrong for Overseer Vashk, who has one name and is
		the same man whichever district the map happens to put him in.
	]]
	local cast = if rule.cast and Cast.exists(rule.cast) then Cast.get(rule.cast) else nil
	-- A spawn rule that names no zone is planet-wide, and so is its band.
	local level = if cast
		then cast.level
		else NPCArchetypes.rollLevel(rule.archetype, rng, Planets.bandFor(planetId, rule.zone or ""))
	local displayName = if cast then cast.displayName else NPCNames.generate(archetype.nameStyle, rng)

	local model = RigBuilder.build({
		species = NPCArchetypes.rollSpecies(rule.archetype, rng),
		costume = archetype.costume,
		sizeVariant = RigBuilder.randomSizeVariant(),
		displayName = displayName,
	})

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not (root and root:IsA("BasePart")) then
		release(stand)
		model:Destroy()
		return nil
	end

	local health = NPCArchetypes.healthFor(rule.archetype, level)
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.DisplayName = displayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 60
	humanoid.HealthDisplayDistance = 60

	-- CombatService reads these when the NPC dies, to decide what the killer
	-- earned and how the faction feels about it.
	model:SetAttribute("Archetype", rule.archetype)
	model:SetAttribute("Faction", archetype.faction)
	model:SetAttribute("Level", level)
	model:SetAttribute("Planet", planetId)
	-- How DialogueService knows to open this character's own tree instead of
	-- the archetype's. Set on the model rather than passed through the
	-- `interacted` signal so nothing else has to learn a new signature.
	if cast then
		model:SetAttribute("Cast", cast.id)
	end

	local carriesWeapon = archetype.weapon ~= nil
		and (archetype.weaponChance == nil or rng:NextNumber() < archetype.weaponChance)
	if carriesWeapon then
		WeaponModel.equip(model, archetype.weapon :: string)
	end

	model:PivotTo(home)
	model.Parent = npcFolder(planetId)

	local brain = NPCBrain.new(model, rule.archetype, level, home)
	if not brain then
		release(stand)
		model:Destroy()
		return nil
	end
	local variant = variantFor(rule.archetype, carriesWeapon, rule.behavior)
	if variant ~= archetype then
		brain.archetype = variant
		brain:setState(variant.behavior)
	end
	if #route > 0 then
		brain:setPatrolRoute(route)
	end

	-- A cast member is always interactable: the archetype they borrowed may be
	-- a Sith Lord, and being unable to talk to the man who raised you because
	-- his costume normally shoots people is not a rule worth respecting.
	if archetype.interactable or cast then
		addPrompt(model, root, archetype, displayName)
	end

	local record: Record = {
		model = model,
		brain = brain,
		root = root,
		planetId = planetId,
		rule = rule,
		stand = stand,
		nextStepAt = 0,
	}

	humanoid.Died:Connect(function()
		despawn(record, true)
		retireCorpse(model)
	end)

	records[model] = record
	liveCount += 1
	return record
end

--------------------------------------------------------------------------------
-- Population
--------------------------------------------------------------------------------

--[[
	Spawns a planet's whole roster.

	Spread over frames rather than done in one go: building forty rigs in a
	single step is a visible hitch even when every template is already cached.
]]
local function populate(planetId: string)
	if populated[planetId] then
		return
	end
	populated[planetId] = true

	task.spawn(function()
		-- The cast go first. MAX_NPCS is a real ceiling, and if a planet ever
		-- reaches it the thing that gets left out should not be the one
		-- person on it a mission can name.
		local rules = Cast.spawnRules(planetId)
		for _, rule in Planets.get(planetId).spawns do
			table.insert(rules, rule)
		end

		for _, rule in rules do
			for _ = 1, rule.count do
				if not populated[planetId] then
					return -- the last player left mid-build
				end
				spawnOne(planetId, rule)
				task.wait()
			end
		end
	end)
end

local function depopulate(planetId: string)
	if not populated[planetId] then
		return
	end
	populated[planetId] = false

	for model, record in records do
		if record.planetId == planetId then
			despawn(record, false)
			model:Destroy()
		end
	end

	for i = #pending, 1, -1 do
		if pending[i].planetId == planetId then
			table.remove(pending, i)
		end
	end
end

--- Which planets currently have at least one player standing on them.
local function occupiedPlanets(): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local profile = data().get(player)
		if profile then
			out[profile.currentPlanet] = true
		end
	end
	return out
end

local function reviewPopulation()
	local occupied = occupiedPlanets()
	local now = os.clock()

	for _, planetId in Planets.ids() do
		if occupied[planetId] then
			emptySince[planetId] = nil
			populate(planetId)
		elseif populated[planetId] then
			local since = emptySince[planetId]
			if not since then
				emptySince[planetId] = now
			elseif now - since >= DEPOPULATE_GRACE then
				emptySince[planetId] = nil
				depopulate(planetId)
			end
		end
	end
end

local function flushPending()
	local now = os.clock()
	for i = #pending, 1, -1 do
		local entry = pending[i]
		if now >= entry.at then
			table.remove(pending, i)
			if populated[entry.planetId] then
				spawnOne(entry.planetId, entry.rule)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	Pulls nearby allies into a fight.

	Only NPCs not already fighting are provoked, which is what stops the
	cascade from looping: each one shouts exactly once, on the transition into
	combat, and a shout that reaches an NPC already in combat dies there.
]]
function NPCService.alertNear(position: Vector3, radius: number, faction: string, target: Model, exclude: any)
	for _, record in records do
		local brain = record.brain
		if brain == exclude or brain.destroyed or brain.state == "Combat" then
			continue
		end
		if brain.faction ~= faction or not brain.archetype.weapon then
			continue
		end
		if (brain.root.Position - position).Magnitude > radius then
			continue
		end
		brain:provoke(target)
	end
end

--------------------------------------------------------------------------------
-- Tick
--------------------------------------------------------------------------------

local function playerPositions(): { Vector3 }
	local out: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(out, root.Position)
		end
	end
	return out
end

local function nearestDistance(position: Vector3, positions: { Vector3 }): number
	local best = math.huge
	for _, p in positions do
		local d = (p - position).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end

local function tick()
	local positions = playerPositions()
	if #positions == 0 then
		return -- nobody to perform for
	end

	local now = os.clock()

	for model, record in records do
		if record.brain.destroyed then
			continue
		end
		if not model.Parent then
			-- Removed by something else (streaming, a cleanup script). Drop it
			-- rather than stepping a brain whose body is gone.
			despawn(record, false)
			continue
		end

		local distance = nearestDistance(record.root.Position, positions)
		if distance <= FULL_DISTANCE then
			record.brain:step(true)
		elseif distance <= ACTIVE_DISTANCE then
			record.brain:step(false)
		elseif now >= record.nextStepAt then
			record.nextStepAt = now + DORMANT_INTERVAL
			record.brain:step(false)
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function NPCService.init()
	local problems = NPCArchetypes.validate()
	for _, problem in problems do
		warn(`[NPCService] archetype config: {problem}`)
	end
end

function NPCService.start()
	local combat = ServiceLoader.get("CombatService")

	-- Being shot is the one thing that overrides an NPC's disposition. A
	-- farmer who takes a bolt reacts to it whatever the reputation table says.
	combat.damaged:connect(function(target: Model, info: any)
		local record = records[target]
		if not record then
			return
		end
		local source = info.source
		if typeof(source) == "Instance" and source:IsA("Model") and source ~= target then
			record.brain:provoke(source)
		end
	end)

	local accumulator = 0
	local sinceReview = 0

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		accumulator = 0

		-- One brain erroring must not stop every other NPC on the server.
		-- The cast is only to satisfy Luau: it types pcall of a void function
		-- as returning the success flag alone, hiding the error message.
		local ok, err = pcall(tick :: any)
		if not ok then
			warn(`[NPCService] tick error: {err}`)
		end

		flushPending()

		sinceReview += TICK_INTERVAL
		if sinceReview >= POPULATION_CHECK_INTERVAL then
			sinceReview = 0
			reviewPopulation()
		end
	end)
end

return NPCService
