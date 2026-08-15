--!strict
--[[
	MissionService.luau

	Accepting, tracking, completing and failing missions.

	ONE ENTRY POINT FOR PROGRESS
	Everything that could advance a mission -- a kill, a conversation, walking
	into a place -- funnels through `report`. Combat does not know what a
	mission is; it fires `killed` and this service decides whether that mattered.
	The alternative, letting each system poke at mission state, is how objective
	trackers end up disagreeing with each other.

	STAGED OBJECTIVES
	A hidden objective accepts no progress until everything before it is done.
	That is what makes "find the datapad" -> "now get out" read as a sequence
	rather than as two boxes the player can tick in either order.

	TURN-IN IS AUTOMATIC
	Finishing the last objective completes the mission. Walking back to a
	quest giver is only interesting when the giver has something to say, and
	when they do, the mission simply ends with a TalkTo objective instead.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Signal = require(Shared.Core.Signal)
local Items = require(Shared.Config.Items)
local Missions = require(Shared.Config.Missions)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type PlayerProfile = Types.PlayerProfile
type MissionProgress = Types.MissionProgress

local MissionService = {
	name = "MissionService",
	priority = 50,
}

local Objective = Missions.Objective

-- How often timed missions and location objectives are checked. Walking into
-- a place is not a reflex test, so a second and a half is imperceptible.
local SWEEP_INTERVAL = 1.5

-- How close counts as "reached" for a point of interest.
local REACH_RADIUS = 28

MissionService.missionCompleted = Signal.new()

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

local function notify(player: Player, message: string, kind: string?)
	Net.fireClient(Net.Event.Notify, player, message, kind or "Mission")
end

local function push(player: Player, missionId: string, status: string, progress: { [number]: number }?)
	Net.fireClient(Net.Event.MissionUpdated, player, missionId, status, progress or {})
end

--------------------------------------------------------------------------------
-- Rewards
--------------------------------------------------------------------------------

local function grantRewards(player: Player, missionId: string)
	local profile = data().get(player)
	if not profile then
		return
	end

	local stats = progression().getStats(player)
	local rewards = Missions.scaledRewards(missionId, profile.level, stats.CreditMult)

	progression().awardXp(player, rewards.xp)
	-- `raw` because scaledRewards has already applied the credit multiplier;
	-- awarding normally would apply Scavenger twice.
	progression().awardCredits(player, rewards.credits, true)

	if rewards.rep then
		for factionId, delta in rewards.rep do
			progression().awardRep(player, factionId, delta)
		end
	end

	data().update(player, function(p: PlayerProfile)
		if rewards.items then
			for itemId, count in rewards.items do
				p.inventory[itemId] = (p.inventory[itemId] or 0) + count
			end
		end
		if rewards.weapon then
			p.inventory[rewards.weapon] = (p.inventory[rewards.weapon] or 0) + 1
		end
		if rewards.skillPoints then
			p.skillPoints += rewards.skillPoints
		end
	end)

	if rewards.weapon then
		notify(player, `Received: {rewards.weapon}`, "Reward")
	end
	notify(player, `+{rewards.xp} XP, +{rewards.credits} credits`, "Reward")
end

--------------------------------------------------------------------------------
-- State changes
--------------------------------------------------------------------------------

local function complete(player: Player, missionId: string)
	local mission = Missions.get(missionId)

	data().update(player, function(p: PlayerProfile)
		p.missions.active[missionId] = nil
		p.missions.completed[missionId] = (p.missions.completed[missionId] or 0) + 1
		p.missions.lastCompleted[missionId] = os.time()
		p.stats.missionsCompleted += 1
	end)

	grantRewards(player, missionId)

	notify(player, `Mission complete: {mission.displayName}`, "MissionComplete")
	if mission.debriefing then
		notify(player, mission.debriefing, "Debrief")
	end
	if mission.next and Missions.exists(mission.next) then
		notify(player, `New lead available: {Missions.get(mission.next).displayName}`, "Mission")
	end

	push(player, missionId, "Completed")
	MissionService.missionCompleted:fire(player, missionId)
end

local function fail(player: Player, missionId: string, reason: string)
	local mission = Missions.get(missionId)
	data().update(player, function(p: PlayerProfile)
		p.missions.active[missionId] = nil
	end)
	notify(player, `Failed: {mission.displayName} -- {reason}`, "MissionFailed")
	push(player, missionId, "Failed")
end

function MissionService.accept(player: Player, missionId: string): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local ok, reason = Missions.canAccept(missionId, profile, os.time())
	if not ok then
		return false, reason
	end

	local mission = Missions.get(missionId)
	--[[
		A zero for every objective, rather than an empty table that grows a key
		as each one is worked on.

		Progress used to be recorded sparsely, so finishing objective 3 before
		objective 2 left `{ [1] = 1, [3] = 1 }` -- an array with a hole in it.
		Roblox does not replicate the part of such a table past the hole, and
		JSONEncode turns its indices into strings on the way to a DataStore, so
		the objective ticked on the server and stayed unticked everywhere the
		player could see it. Starting dense means there is never a hole.
	]]
	local blank: { [number]: number } = table.create(#mission.objectives, 0)
	data().update(player, function(p: PlayerProfile)
		p.missions.active[missionId] = {
			missionId = missionId,
			startedAt = os.time(),
			objectives = blank,
			stage = 1,
		} :: MissionProgress
	end)

	notify(player, `Accepted: {mission.displayName}`, "Mission")
	notify(player, mission.briefing, "Briefing")
	push(player, missionId, "Accepted", {})
	return true, nil
end

function MissionService.abandon(player: Player, missionId: string): boolean
	local profile = data().get(player)
	if not profile or not profile.missions.active[missionId] then
		return false
	end
	data().update(player, function(p: PlayerProfile)
		p.missions.active[missionId] = nil
	end)
	push(player, missionId, "Abandoned")
	return true
end

--------------------------------------------------------------------------------
-- Progress
--------------------------------------------------------------------------------

--[[
	Whether objective `index` is currently accepting progress.

	Hidden objectives wait for the ones before them. Visible objectives do not,
	so a mission that lists three independent errands stays three errands the
	player can do in whatever order they like.
]]
local function isAvailable(
	mission: Missions.MissionDef,
	index: number,
	progress: { [number]: number }
): boolean
	local obj = mission.objectives[index]
	if not obj.hidden then
		return true
	end
	for i = 1, index - 1 do
		local earlier = mission.objectives[i]
		if not earlier.optional and (progress[i] or 0) < Missions.objectiveTarget(earlier) then
			return false
		end
	end
	return true
end

--[[
	Records `amount` progress toward every matching objective the player has.

	`target` is matched loosely: an objective with no target counts any event of
	the right kind, which is how "kill 5 of anything hostile" is expressed.
]]
function MissionService.report(player: Player, kind: string, target: string?, amount: number?)
	local profile = data().get(player)
	if not profile then
		return
	end
	local step = amount or 1
	if step <= 0 then
		return
	end

	local currentPlanet = profile.currentPlanet
	local finished: { string } = {}
	local touched: { [string]: boolean } = {}

	data().update(player, function(p: PlayerProfile)
		for missionId, entry in p.missions.active do
			if not Missions.exists(missionId) then
				continue
			end
			local mission = Missions.get(missionId)

			for index, obj in mission.objectives do
				if obj.kind ~= kind then
					continue
				end
				if obj.target and obj.target ~= target then
					continue
				end
				if obj.planet and obj.planet ~= currentPlanet then
					continue
				end
				if not isAvailable(mission, index, entry.objectives) then
					continue
				end

				local needed = Missions.objectiveTarget(obj)
				local have = entry.objectives[index] or 0
				if have >= needed then
					continue
				end

				entry.objectives[index] = math.min(needed, have + step)
				touched[missionId] = true
			end

			if touched[missionId] and Missions.isComplete(missionId, entry.objectives) then
				table.insert(finished, missionId)
			end
		end
	end)

	local updated = data().get(player)
	for missionId in touched do
		local entry = updated and updated.missions.active[missionId]
		if entry then
			push(player, missionId, "Progress", entry.objectives)
		end
	end

	for _, missionId in finished do
		complete(player, missionId)
	end
end

--------------------------------------------------------------------------------
-- Location and time sweep
--------------------------------------------------------------------------------

--- The part marking a point of interest, if the map defines one.
local function poiPart(planetId: string, poiId: string): BasePart?
	local root = Workspace:FindFirstChild("POI")
	local planetFolder = root and root:FindFirstChild(planetId)
	local part = planetFolder and planetFolder:FindFirstChild(poiId)
	return if part and part:IsA("BasePart") then part else nil
end

local function sweepPlayer(player: Player, now: number)
	local profile = data().get(player)
	if not profile then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else nil

	local expired: { string } = {}
	local reached: { string } = {}
	--- Items handed over this sweep: { item, how many }.
	local delivered: { { item: string, count: number } } = {}

	for missionId, entry in profile.missions.active do
		if not Missions.exists(missionId) then
			continue
		end
		local mission = Missions.get(missionId)

		if mission.timeLimit and now - entry.startedAt > mission.timeLimit then
			table.insert(expired, missionId)
			continue
		end

		if not position then
			continue
		end
		for index, obj in mission.objectives do
			if (entry.objectives[index] or 0) >= Missions.objectiveTarget(obj) then
				continue
			end

			if obj.kind == Objective.Reach and obj.target then
				local part = poiPart(profile.currentPlanet, obj.target)
				if part and (part.Position - position).Magnitude <= REACH_RADIUS then
					table.insert(reached, obj.target)
				end
			elseif obj.kind == Objective.Deliver and obj.target and obj.destination then
				--[[
					Delivery is standing at the destination holding the goods.

					Both halves are checked here rather than trusting the
					Collect objective to have run: a player can be given the
					item as a mission reward, or drop the mission and retake
					it, and either way carrying it is what counts.
				]]
				local part = poiPart(profile.currentPlanet, obj.destination)
				local carried = profile.inventory[obj.target] or 0
				local needed = Missions.objectiveTarget(obj)
				if part and carried >= needed and (part.Position - position).Magnitude <= REACH_RADIUS then
					table.insert(delivered, { item = obj.target, count = needed })
				end
			end
		end
	end

	for _, missionId in expired do
		fail(player, missionId, "out of time")
	end
	for _, target in reached do
		MissionService.report(player, Objective.Reach, target, 1)
	end
	for _, hand in delivered do
		--[[
			Spend first, credit second, and only credit what was actually
			spent. Two missions can want the same item delivered to the same
			place, and both were tested against the inventory as it stood at
			the top of the sweep -- so the goods have to be taken under a
			fresh read or the player hands over one crate and gets paid twice.
		]]
		local spent = 0
		data().update(player, function(p: PlayerProfile)
			local held = p.inventory[hand.item] or 0
			spent = math.min(held, hand.count)
			if spent <= 0 then
				return
			end
			local left = held - spent
			if left > 0 then
				p.inventory[hand.item] = left
			else
				-- Cleared rather than left at zero, so a spent quest item
				-- does not sit in the save forever as an empty stack.
				p.inventory[hand.item] = nil
			end
		end)
		if spent > 0 then
			notify(player, `Delivered: {Items.nameOf(hand.item)} x{spent}`, "Reward")
			MissionService.report(player, Objective.Deliver, hand.item, spent)
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MissionService.init()
	for _, problem in Missions.validate() do
		warn(`[MissionService] mission config: {problem}`)
	end

	Net.onServerEvent(Net.Event.AcceptMission, function(player: Player, missionId: string)
		local ok, reason = MissionService.accept(player, missionId)
		if not ok and reason then
			notify(player, reason, "Error")
		end
	end, {
		rateLimit = 4,
		validate = Net.args(Net.check.string(64)),
	})

	Net.onServerEvent(Net.Event.AbandonMission, function(player: Player, missionId: string)
		MissionService.abandon(player, missionId)
	end, {
		rateLimit = 4,
		validate = Net.args(Net.check.string(64)),
	})

	Net.onServerInvoke(Net.Function.GetMissionBoard, function(player: Player)
		local profile = data().get(player)
		if not profile then
			return {}
		end

		-- Config tables are sent by id only. Shipping the whole MissionDef
		-- would replicate text the client already has in Shared.
		local out = {}
		for _, entry in Missions.boardFor(profile.currentPlanet, profile, os.time()) do
			table.insert(out, {
				id = entry.mission.id,
				locked = entry.locked,
				reason = entry.reason,
			})
		end
		return out
	end, { rateLimit = 4 })
end

function MissionService.start()
	local combat = ServiceLoader.get("CombatService")
	local npcs = ServiceLoader.get("NPCService")

	combat.killed:connect(function(target: Model, info: any)
		local killer = info.attacker
		if not killer or not killer:IsDescendantOf(Players) then
			return
		end
		local archetypeId = target:GetAttribute("Archetype")
		if typeof(archetypeId) == "string" then
			MissionService.report(killer, Objective.Kill, archetypeId, 1)
		end
	end)

	--[[
		Who each player has already spoken to.

		"Talk to four Jawas" is a fake objective if pressing E four times at the
		same Jawa finishes it, so a given NPC only ever counts once. Weak keys
		on both levels: NPCs die and respawn constantly and players leave, and
		neither should be kept alive by a bookkeeping table.
	]]
	local spokenTo: { [Player]: { [Model]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

	npcs.interacted:connect(function(player: Player, model: Model, archetypeId: string)
		local seen = spokenTo[player]
		if not seen then
			seen = setmetatable({}, { __mode = "k" }) :: any
			spokenTo[player] = seen
		end
		if seen[model] then
			return
		end
		seen[model] = true
		MissionService.report(player, Objective.TalkTo, archetypeId, 1)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < SWEEP_INTERVAL then
			return
		end
		accumulator = 0

		local now = os.time()
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(sweepPlayer :: any, player, now)
			if not ok then
				warn(`[MissionService] sweep error for {player.Name}: {err}`)
			end
		end
	end)
end

return MissionService
