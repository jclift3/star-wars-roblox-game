--!strict
--[[
	NPCBrain.luau

	One NPC's mind: sensing, deciding, and moving.

	SHAPE
	A small state machine, ticked by NPCService rather than owning its own loop.
	Central ticking is what makes a crowd affordable -- a few hundred NPCs each
	running their own `while true do task.wait()` is how the previous version's
	NPC code was written, and it is why it would not have scaled even if it had
	run at all.

	SENSING IS THROTTLED
	Line-of-sight raycasts are the expensive part, so they run on their own
	slower clock than movement. An NPC noticing you 300ms late is invisible; an
	NPC raycasting at 60Hz is a server budget spent on nothing.

	NPCs ALERT EACH OTHER
	When one enters combat it shouts, and allies within earshot join. That
	single behaviour is most of what makes a guard patrol read as a squad rather
	than as a row of independent turrets.
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NPCArchetypes = require(Shared.Config.NPCArchetypes)
local Weapons = require(Shared.Config.Weapons)
local Factions = require(Shared.Config.Factions)
local RigAnimator = require(Shared.Rig.RigAnimator)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local Behavior = NPCArchetypes.Behavior

local NPCBrain = {}
NPCBrain.__index = NPCBrain

-- Sensing cadence, in seconds. Deliberately slower than the movement tick.
local SENSE_INTERVAL = 0.35
-- How long an NPC keeps hunting after losing sight of its target.
local MEMORY_DURATION = 8
-- Radius within which an NPC's alert reaches its allies.
local ALERT_RADIUS = 70
-- Fraction of `attackRange` a shooter tries to hold. Closing all the way makes
-- ranged NPCs walk into melee, which looks broken.
local PREFERRED_RANGE_FACTOR = 0.65
-- Below this the NPC backs off rather than shooting from inside the target.
local TOO_CLOSE_FACTOR = 0.3

local WANDER_RADIUS = 45
local WANDER_PAUSE_MIN = 2
local WANDER_PAUSE_MAX = 7
-- Paths further than this are recomputed rather than followed to the end.
local REPATH_DISTANCE = 12

export type Brain = typeof(setmetatable(
	{} :: {
		model: Model,
		humanoid: Humanoid,
		root: BasePart,
		archetypeId: string,
		archetype: NPCArchetypes.Archetype,
		level: number,
		faction: string,

		state: string,
		stateSince: number,
		home: CFrame,
		patrolPoints: { Vector3 },
		patrolIndex: number,

		target: Model?,
		lastSawTarget: number,
		alertedAt: number,
		nextSenseAt: number,
		nextActionAt: number,
		nextAttackAt: number,
		nextIdleAt: number,

		waypoints: { PathWaypoint },
		waypointIndex: number,
		pathPending: boolean,
		nextRepathAt: number,

		animator: any,
		rng: Random,
		destroyed: boolean,
	},
	NPCBrain
))

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function NPCBrain.new(model: Model, archetypeId: string, level: number, home: CFrame): Brain?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not (root and root:IsA("BasePart")) then
		return nil
	end

	local archetype = NPCArchetypes.get(archetypeId)
	local now = os.clock()

	local self = setmetatable({
		model = model,
		humanoid = humanoid,
		root = root,
		archetypeId = archetypeId,
		archetype = archetype,
		level = level,
		faction = archetype.faction,

		state = archetype.behavior,
		stateSince = now,
		home = home,
		patrolPoints = {},
		patrolIndex = 1,

		target = nil,
		lastSawTarget = 0,
		alertedAt = 0,
		nextSenseAt = now + math.random() * SENSE_INTERVAL,
		nextActionAt = now,
		nextAttackAt = now,
		nextIdleAt = now,

		waypoints = {},
		waypointIndex = 1,
		pathPending = false,
		nextRepathAt = 0,

		animator = RigAnimator.new(model),
		rng = Random.new(),
		destroyed = false,
	}, NPCBrain)

	humanoid.WalkSpeed = archetype.walkSpeed

	return self
end

--- Assigns a patrol route. Without one, Patrol behaves as Guard.
function NPCBrain.setPatrolRoute(self: Brain, points: { Vector3 })
	self.patrolPoints = points
	self.patrolIndex = 1
end

--------------------------------------------------------------------------------
-- Movement
--------------------------------------------------------------------------------

local function clearPath(self: Brain)
	table.clear(self.waypoints)
	self.waypointIndex = 1
end

--[[
	Computes a path to `goal` and stores its waypoints.

	ComputeAsync yields, so this runs in its own coroutine and sets a flag while
	in flight. Without the flag a chasing NPC would queue a new path every tick
	and never actually follow one.
]]
local function requestPath(self: Brain, goal: Vector3)
	if self.pathPending or self.destroyed then
		return
	end
	self.pathPending = true

	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2.5,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 6,
		})

		local ok = pcall(function()
			path:ComputeAsync(self.root.Position, goal)
		end)

		if self.destroyed then
			return
		end

		if ok and path.Status == Enum.PathStatus.Success then
			self.waypoints = path:GetWaypoints()
			self.waypointIndex = 2 -- waypoint 1 is where we already are
		else
			-- No route. Walk directly and let the Humanoid bump into things --
			-- better than freezing in place, which reads as broken.
			clearPath(self)
			self.humanoid:MoveTo(goal)
		end
		self.pathPending = false
	end)
end

--- Advances along the current path. Returns true while still travelling.
local function followPath(self: Brain): boolean
	if self.waypointIndex > #self.waypoints then
		return false
	end

	local waypoint = self.waypoints[self.waypointIndex]
	local flat = Vector3.new(waypoint.Position.X, self.root.Position.Y, waypoint.Position.Z)

	if (self.root.Position - flat).Magnitude < 4 then
		self.waypointIndex += 1
		if self.waypointIndex > #self.waypoints then
			return false
		end
		waypoint = self.waypoints[self.waypointIndex]
	end

	if waypoint.Action == Enum.PathWaypointAction.Jump then
		self.humanoid.Jump = true
	end
	self.humanoid:MoveTo(waypoint.Position)
	return true
end

--- Moves toward `goal`, pathfinding when far and walking directly when near.
local function moveTo(self: Brain, goal: Vector3, running: boolean)
	local archetype = self.archetype
	self.humanoid.WalkSpeed = if running
		then (archetype.runSpeed or archetype.walkSpeed)
		else archetype.walkSpeed

	local distance = (goal - self.root.Position).Magnitude
	if distance < 15 then
		-- Close enough that pathfinding costs more than it is worth.
		clearPath(self)
		self.humanoid:MoveTo(goal)
		return
	end

	local now = os.clock()
	if #self.waypoints == 0 or now >= self.nextRepathAt then
		local last = self.waypoints[#self.waypoints]
		if not last or (last.Position - goal).Magnitude > REPATH_DISTANCE then
			requestPath(self, goal)
			self.nextRepathAt = now + 1.5
		end
	end

	if not followPath(self) then
		self.humanoid:MoveTo(goal)
	end
end

local function stopMoving(self: Brain)
	clearPath(self)
	self.humanoid:MoveTo(self.root.Position)
end

local function faceTowards(self: Brain, position: Vector3)
	local flat = Vector3.new(position.X, self.root.Position.Y, position.Z)
	if (flat - self.root.Position).Magnitude < 0.5 then
		return
	end
	self.root.CFrame = CFrame.lookAt(self.root.Position, flat)
end

--------------------------------------------------------------------------------
-- Sensing
--------------------------------------------------------------------------------

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

local function hasLineOfSight(self: Brain, targetRoot: BasePart): boolean
	local from = self.root.Position + Vector3.new(0, 2, 0)
	local to = targetRoot.Position + Vector3.new(0, 1, 0)
	losParams.FilterDescendantsInstances = { self.model, targetRoot.Parent :: Instance }

	local result = Workspace:Raycast(from, to - from, losParams)
	-- Nothing in between means a clear view; anything else is cover.
	return result == nil
end

--[[
	Decides whether this NPC considers a player an enemy.

	Reputation drives it, so the same stormtrooper is a threat to a Rebel hero
	and scenery to an Imperial loyalist without needing two archetypes.
]]
local function isEnemy(self: Brain, player: Player): boolean
	if self.archetype.behavior == Behavior.Aggressive then
		local ok, profile = pcall(function()
			return ServiceLoader.get("DataService").get(player)
		end)
		if not ok or not profile then
			return true
		end
		return Factions.attitudeToward(self.faction, profile.factionRep) ~= "Friendly"
	end

	local ok, profile = pcall(function()
		return ServiceLoader.get("DataService").get(player)
	end)
	if not ok or not profile then
		return false
	end
	return Factions.attitudeToward(self.faction, profile.factionRep) == "Hostile"
end

--- Nearest visible enemy within sight range, or nil.
local function findTarget(self: Brain): Model?
	local range = self.archetype.sightRange or 120
	local best: Model? = nil
	local bestDistance = range

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local targetRoot = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not (targetRoot and targetRoot:IsA("BasePart")) then
			continue
		end

		local distance = (targetRoot.Position - self.root.Position).Magnitude
		if distance >= bestDistance then
			continue
		end
		if not isEnemy(self, player) then
			continue
		end
		if not hasLineOfSight(self, targetRoot) then
			continue
		end

		best = character
		bestDistance = distance
	end

	return best
end

--- Tells nearby allies about a target, so a squad reacts together.
local function shout(self: Brain)
	local target = self.target
	if not target then
		return
	end
	local npcService = ServiceLoader.find("NPCService")
	if not npcService then
		return
	end
	npcService.alertNear(self.root.Position, ALERT_RADIUS, self.faction, target, self)
end

--[[
	Forces this NPC into combat with `attacker`.

	Called when it is shot. Being shot bypasses the reputation check entirely --
	a neutral farmer who takes a blaster bolt fights or runs, regardless of how
	the shooter's paperwork looks.
]]
function NPCBrain.provoke(self: Brain, attacker: Model)
	if self.destroyed or self.humanoid.Health <= 0 then
		return
	end
	self.target = attacker
	self.lastSawTarget = os.clock()

	if self.archetype.behavior == Behavior.Flee or not self.archetype.weapon then
		self:setState(Behavior.Flee)
	else
		self:setState("Combat")
		shout(self)
	end
end

function NPCBrain.setState(self: Brain, state: string)
	if self.state == state then
		return
	end
	self.state = state
	self.stateSince = os.clock()
	clearPath(self)
end

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

local states: { [string]: (Brain, number) -> () } = {}

states[Behavior.Idle] = function(self, now)
	if now < self.nextIdleAt then
		return
	end
	self.nextIdleAt = now + self.rng:NextNumber(3, 8)

	-- Turn to watch the nearest player. Cheap, and it is the single strongest
	-- signal that a background NPC is alive rather than a statue.
	local nearest: BasePart? = nil
	local nearestDistance = 40
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
		if targetRoot and targetRoot:IsA("BasePart") then
			local distance = (targetRoot.Position - self.root.Position).Magnitude
			if distance < nearestDistance then
				nearest = targetRoot
				nearestDistance = distance
			end
		end
	end
	if nearest then
		faceTowards(self, nearest.Position)
	end
end

states[Behavior.Wander] = function(self, now)
	if now < self.nextActionAt then
		return
	end

	local goal = self.home.Position
		+ Vector3.new(
			self.rng:NextNumber(-WANDER_RADIUS, WANDER_RADIUS),
			0,
			self.rng:NextNumber(-WANDER_RADIUS, WANDER_RADIUS)
		)

	moveTo(self, goal, false)
	-- Wander points are far enough apart that this doubles as the pause: the
	-- NPC arrives, stands for a moment, then picks somewhere new.
	self.nextActionAt = now + self.rng:NextNumber(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX) + 4
end

states[Behavior.Patrol] = function(self, now)
	if #self.patrolPoints == 0 then
		-- No route assigned; hold position instead of standing in a T-pose.
		states[Behavior.Guard](self, now)
		return
	end

	local goal = self.patrolPoints[self.patrolIndex]
	if (goal - self.root.Position).Magnitude < 8 then
		self.patrolIndex += 1
		if self.patrolIndex > #self.patrolPoints then
			self.patrolIndex = 1
		end
		-- A beat at each waypoint, so patrols do not look like conveyor belts.
		self.nextActionAt = now + self.rng:NextNumber(1, 3)
		return
	end

	if now >= self.nextActionAt then
		moveTo(self, goal, false)
	end
end

states[Behavior.Guard] = function(self, now)
	local drift = (self.root.Position - self.home.Position).Magnitude
	if drift > 6 then
		moveTo(self, self.home.Position, false)
	else
		stopMoving(self)
		if now >= self.nextIdleAt then
			self.nextIdleAt = now + self.rng:NextNumber(4, 10)
			faceTowards(self, self.home.Position + self.home.LookVector * 10)
		end
	end
end

-- Vendors and quest givers hold their post and face whoever approaches.
states[Behavior.Vendor] = states[Behavior.Idle]
states[Behavior.QuestGiver] = states[Behavior.Idle]

states[Behavior.Aggressive] = function(self, now)
	-- Nothing to hunt right now; drift around the spawn until something shows.
	states[Behavior.Wander](self, now)
end

states[Behavior.Flee] = function(self, now)
	local target = self.target
	local threat = target and target:FindFirstChild("HumanoidRootPart")

	if not (threat and threat:IsA("BasePart")) then
		-- Danger gone. Go home and calm down.
		if (self.root.Position - self.home.Position).Magnitude > 10 then
			moveTo(self, self.home.Position, false)
		else
			self:setState(self.archetype.behavior)
		end
		return
	end

	local away = (self.root.Position - threat.Position)
	if away.Magnitude > 120 then
		self.target = nil
		return
	end

	if now >= self.nextActionAt then
		self.nextActionAt = now + 0.8
		moveTo(self, self.root.Position + away.Unit * 40, true)
	end
end

--[[
	Combat. Holds a preferred range, fires on the weapon's clock, and gives up
	after MEMORY_DURATION without a sighting.
]]
states.Combat = function(self, now)
	local target = self.target
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")

	if
		not target
		or not (targetRoot and targetRoot:IsA("BasePart"))
		or not targetHumanoid
		or targetHumanoid.Health <= 0
	then
		self.target = nil
		self:setState(self.archetype.behavior)
		return
	end

	local distance = (targetRoot.Position - self.root.Position).Magnitude
	local visible = hasLineOfSight(self, targetRoot)
	if visible then
		self.lastSawTarget = now
	elseif now - self.lastSawTarget > MEMORY_DURATION then
		-- Lost them. Return to the post rather than hunting forever.
		self.target = nil
		self:setState(self.archetype.behavior)
		return
	end

	local weaponId = self.archetype.weapon
	if not weaponId then
		self:setState(Behavior.Flee)
		return
	end
	local weapon = Weapons.get(weaponId)
	local attackRange = self.archetype.attackRange or weapon.range

	-- Positioning.
	if weapon.class == "Blaster" then
		local preferred = attackRange * PREFERRED_RANGE_FACTOR
		local tooClose = attackRange * TOO_CLOSE_FACTOR
		if distance > preferred or not visible then
			moveTo(self, targetRoot.Position, true)
		elseif distance < tooClose and not self.archetype.holdsGround then
			local away = (self.root.Position - targetRoot.Position).Unit
			moveTo(self, self.root.Position + away * 20, true)
		else
			stopMoving(self)
			faceTowards(self, targetRoot.Position)
		end
	else
		if distance > attackRange * 0.6 then
			moveTo(self, targetRoot.Position, true)
		else
			stopMoving(self)
			faceTowards(self, targetRoot.Position)
		end
	end

	-- Attacking.
	if not visible or distance > attackRange or now < self.nextAttackAt then
		return
	end

	local rate = weapon.fireRate * (self.archetype.fireRateMult or 1)
	self.nextAttackAt = now + 1 / math.max(0.1, rate)

	local combat = ServiceLoader.find("CombatService")
	if not combat then
		return
	end
	if weapon.class == "Blaster" then
		combat.npcFire(
			self.model,
			weaponId,
			targetRoot.Position + Vector3.new(0, 1, 0),
			self.archetype.spreadMult
		)
	else
		combat.npcMelee(self.model, weaponId)
	end
end

--------------------------------------------------------------------------------
-- Tick
--------------------------------------------------------------------------------

--[[
	One update. `full` is false for distant NPCs, which skip sensing entirely --
	an NPC nobody can see does not need to look for anybody.
]]
function NPCBrain.step(self: Brain, full: boolean)
	if self.destroyed then
		return
	end
	if self.humanoid.Health <= 0 then
		self:destroy()
		return
	end

	local now = os.clock()

	if full and now >= self.nextSenseAt then
		self.nextSenseAt = now + SENSE_INTERVAL

		if self.state ~= "Combat" and self.state ~= Behavior.Flee then
			local found = findTarget(self)
			if found then
				self.target = found
				self.lastSawTarget = now
				if self.archetype.weapon then
					-- Reaction time is applied as a delay on the first shot,
					-- not on the state change, so the NPC visibly turns and
					-- braces before firing instead of snapping onto target.
					self.nextAttackAt = now + (self.archetype.reactionTime or 0.5)
					self:setState("Combat")
					shout(self)
				else
					self:setState(Behavior.Flee)
				end
			end
		end
	end

	local handler = states[self.state]
	if handler then
		handler(self, now)
	end
end

function NPCBrain.destroy(self: Brain)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.animator then
		self.animator:destroy()
		self.animator = nil
	end
	clearPath(self)
	self.target = nil
end

return NPCBrain
