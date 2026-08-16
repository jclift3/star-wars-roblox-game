--!strict
--[[
	PickupService.luau

	Puts the quest items in the world, and hands them over when you take one.

	WHY THIS EXISTS
	`Collect` objectives were authored, validated and tracked, but nothing in
	the game ever reported one -- there was no such thing as an item lying on
	the ground. Every mission with a Collect step could be accepted and never
	finished. This is the missing producer, the mirror of CombatService's
	kill reporting.

	SHARED, NOT PER-PLAYER
	Pickups belong to the world rather than to whoever has the mission. One set
	spawns per planet and anyone may take from it, which is how loot behaves in
	almost every co-op game and avoids six invisible copies of the same crate
	stacked on one another. Taken pickups come back after RESPAWN_DELAY, so a
	repeatable mission stays repeatable and two players are never in a race.

	WHERE THEY GO
	From the objective's `at` point of interest, scattered around it and dropped
	onto whatever ground is underneath. Nothing here invents a location: an
	objective with no `at` is a config bug, and Missions.validate says so.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Missions = require(Shared.Config.Missions)
local Net = require(Shared.Core.Net)
local Inventory = require(Shared.Core.Inventory)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Types = require(Shared.Types)

type PlayerProfile = Types.PlayerProfile

local PickupService = {
	name = "PickupService",
	-- After MissionService (50): every pickup reports progress to it.
	priority = 55,
}

-- How long a taken pickup stays gone.
local RESPAWN_DELAY = 45
-- How far from the point of interest pickups scatter.
local SCATTER = 26
-- How far off the name tag is legible. Comfortably past SCATTER plus the
-- widest landmark's skirt, so a crate is named from the moment you arrive at
-- the landmark rather than once you are on top of it.
local TAG_DISTANCE = 140
-- Reach of the prompt. Generous on purpose: these lie in rubble and under
-- overhangs, and hunting for the exact stud that lights the prompt up is not
-- the game.
local PROMPT_DISTANCE = 18
-- Spare copies beyond what the objective asks for, so two players collecting
-- at once do not have to wait on the respawn timer.
local SPARES = 2
-- Planets are only checked for missing pickups this often; the answer changes
-- when someone travels, not between frames.
local SWEEP_INTERVAL = 4

--- One thing that should exist somewhere in the world.
type SpawnRule = {
	planet: string,
	poi: string,
	item: string,
	count: number,
}

--[[
	A pickup on the ground.

	`base` is its resting position and its own orientation. The idle animation
	rebuilds the CFrame from scratch every frame, so anything baked into the
	part's rotation at spawn -- an upright cylinder, say -- has to be kept here
	or the first frame flattens it.
]]
type Live = {
	part: BasePart,
	base: CFrame,
	phase: number,
}

local rules: { SpawnRule } = {}
-- Pickups currently on the ground, so the idle loop has something to walk
-- without searching Workspace every frame.
local live: { Live } = {}

local function data()
	return ServiceLoader.get("DataService")
end

local function missions()
	return ServiceLoader.get("MissionService")
end

--------------------------------------------------------------------------------
-- What exists where
--------------------------------------------------------------------------------

--[[
	Derives the spawn table from the missions themselves.

	Deliberately not a second hand-written config: a list of "items that exist
	in the world" maintained alongside the objectives that need them is a list
	that goes stale, and the failure is silent -- exactly the bug that left six
	Reach objectives pointing at points of interest nobody had defined.
]]
local function buildRules()
	local merged: { [string]: SpawnRule } = {}
	for _, missionId in Missions.ids() do
		local mission = Missions.get(missionId)
		for _, obj in mission.objectives do
			if obj.kind ~= Missions.Objective.Collect or not obj.target or not obj.at then
				continue
			end
			local needed = Missions.objectiveTarget(obj)
			local key = `{mission.planet}|{obj.at}|{obj.target}`
			local existing = merged[key]
			-- Two missions wanting the same item in the same place share one
			-- pile, sized for whichever asks for more.
			if existing then
				existing.count = math.max(existing.count, needed)
			else
				merged[key] = {
					planet = mission.planet,
					poi = obj.at,
					item = obj.target,
					count = needed,
				}
			end
		end
	end

	table.clear(rules)
	for _, rule in merged do
		table.insert(rules, rule)
	end
	table.sort(rules, function(a, b)
		return `{a.planet}{a.poi}{a.item}` < `{b.planet}{b.poi}{b.item}`
	end)
end

--------------------------------------------------------------------------------
-- World model
--------------------------------------------------------------------------------

local SHAPES: { [string]: Enum.PartType } = {
	Crate = Enum.PartType.Block,
	Slab = Enum.PartType.Block,
	Droid = Enum.PartType.Cylinder,
	Ore = Enum.PartType.Ball,
}

local function poiPart(planetId: string, poiId: string): BasePart?
	local root = Workspace:FindFirstChild("POI")
	local planetFolder = root and root:FindFirstChild(planetId)
	local part = planetFolder and planetFolder:FindFirstChild(poiId)
	return if part and part:IsA("BasePart") then part else nil
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

--- Drops `position` onto whatever solid ground is under it.
local function onGround(position: Vector3, folder: Instance): Vector3
	groundParams.FilterDescendantsInstances = { folder }
	local hit = Workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -300, 0), groundParams)
	return if hit then hit.Position + Vector3.new(0, 2, 0) else position
end

local function makePickup(rule: SpawnRule, parent: Folder, anchor: BasePart, rng: Random): BasePart
	local item = Items.get(rule.item)

	local part = Instance.new("Part")
	part.Name = rule.item
	part.Anchored = true
	part.CanCollide = false
	part.Shape = SHAPES[item.shape] or Enum.PartType.Block
	part.Size = item.size
	part.Color = item.colour
	part.Material = if item.shape == "Slab" then Enum.Material.Neon else Enum.Material.Metal
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	--[[
		A ring around the landmark rather than a disc over it.

		The marker is as wide as the building standing on it, and that building
		is solid: scattering inside the radius drops crates on the roof of the
		sandcrawler, or under its floor, where the raycast lands them out of
		reach either way.
	]]
	local skirt = math.max(anchor.Size.X, anchor.Size.Z) * 0.5
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = skirt + rng:NextNumber(SCATTER * 0.25, SCATTER)
	local spot = anchor.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

	-- Roblox cylinders lie along X, so a droid needs standing up before it
	-- reads as a droid rather than a barrel someone dropped.
	local orientation = if item.shape == "Droid" then CFrame.Angles(0, 0, math.pi / 2) else CFrame.identity
	local base = CFrame.new(onGround(spot, parent)) * orientation
	part.CFrame = base
	part.Parent = parent

	-- Visible from a distance in a featureless desert. The whole reason a
	-- player can find these at all is that they glow and turn.
	local light = Instance.new("PointLight")
	light.Color = item.colour
	light.Brightness = 1.6
	light.Range = 16
	light.Parent = part

	--[[
		A name over it, drawn through whatever it is lying under.

		The glow only reaches 16 studs and the prompt only 12, so a crate in
		the shadow of a rubble slab was invisible until you were already
		standing on it -- the 2026-08-16 playtest report was "I went to the
		way point but doesn't instruct me what I should be doing". A tag that
		draws through geometry is what turns "somewhere near here" into a
		thing you can walk at.
	]]
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.AlwaysOnTop = true
	tag.Size = UDim2.fromOffset(160, 18)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	tag.MaxDistance = TAG_DISTANCE
	tag.Parent = part

	local tagLabel = Instance.new("TextLabel")
	tagLabel.BackgroundTransparency = 1
	tagLabel.Font = Enum.Font.GothamBold
	tagLabel.TextSize = 13
	tagLabel.TextColor3 = item.colour
	tagLabel.TextStrokeTransparency = 0.4
	tagLabel.Text = item.displayName
	tagLabel.Size = UDim2.fromScale(1, 1)
	tagLabel.Parent = tag

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = item.verb
	prompt.ObjectText = item.displayName
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		PickupService.take(player, part, rule)
	end)

	-- Staggered so a pile of crates does not pulse in lockstep.
	local entry: Live = { part = part, base = base, phase = rng:NextNumber(0, math.pi * 2) }
	table.insert(live, entry)
	return part
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------

local function folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function folderFor(planetId: string): Folder
	return folder(planetId, folder("Pickups", Workspace))
end

--[[
	Makes sure every pickup this planet should have is on the ground.

	Idempotent: it counts what is already there and tops up the difference, so
	the same call both seeds a fresh planet and refills one that players have
	been looting.
]]
local function ensure(planetId: string)
	local parent = folderFor(planetId)
	-- Seeded from the planet id so a given world lays its items out the same
	-- way every session, matching how PlanetBuilder generates the terrain.
	local rng = Random.new(#planetId * 7919)

	for _, rule in rules do
		if rule.planet ~= planetId then
			continue
		end
		local anchor = poiPart(planetId, rule.poi)
		if not anchor then
			-- The planet has not been built yet. Nothing to do but wait for
			-- the next sweep; WorldService builds on demand.
			continue
		end

		local present = 0
		for _, child in parent:GetChildren() do
			if child.Name == rule.item then
				present += 1
			end
		end

		local wanted = rule.count + SPARES
		for _ = present + 1, wanted do
			makePickup(rule, parent, anchor, rng)
		end
	end
end

--------------------------------------------------------------------------------
-- Taking
--------------------------------------------------------------------------------

--- Hands `part` to `player`: into the bag, onto the objective, off the ground.
function PickupService.take(player: Player, part: BasePart, rule: SpawnRule)
	-- Two prompts can fire on the same part before either finishes. Reparenting
	-- first makes the second trigger a no-op rather than a duplicate grant.
	if not part.Parent then
		return
	end
	local parent = part.Parent
	local profile = data().get(player)
	if not profile then
		return
	end

	part.Parent = nil

	for i, entry in live do
		if entry.part == part then
			table.remove(live, i)
			break
		end
	end

	data().update(player, function(p: PlayerProfile)
		Inventory.add(p.inventory, rule.item, 1)
	end)

	missions().report(player, Missions.Objective.Collect, rule.item, 1)
	Net.fireClient(Net.Event.Notify, player, `Picked up: {Items.nameOf(rule.item)}`, "Reward")

	task.delay(RESPAWN_DELAY, function()
		part:Destroy()
		local anchor = poiPart(rule.planet, rule.poi)
		if anchor and parent and parent.Parent then
			makePickup(rule, parent :: Folder, anchor, Random.new(os.clock() * 1000))
		end
	end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function PickupService.init()
	buildRules()
end

function PickupService.start()
	local sweepAccumulator = 0
	local spinAccumulator = 0

	RunService.Heartbeat:Connect(function(dt: number)
		sweepAccumulator += dt
		if sweepAccumulator >= SWEEP_INTERVAL then
			sweepAccumulator = 0
			local planets: { [string]: boolean } = {}
			for _, player in Players:GetPlayers() do
				local profile = data().get(player)
				if profile then
					planets[profile.currentPlanet] = true
				end
			end
			for planetId in planets do
				-- Re-run even on an already-stocked planet: this is what
				-- refills the pile after the respawn timer, and it is a cheap
				-- count of existing children.
				local ok, err = pcall(ensure :: any, planetId)
				if not ok then
					warn(`[PickupService] failed to place pickups on "{planetId}": {err}`)
				end
			end
		end

		-- Bob and turn, so a crate reads as loot rather than scenery.
		spinAccumulator += dt
		for _, entry in live do
			if not entry.part.Parent then
				continue
			end
			local bob = math.sin(spinAccumulator * 2 + entry.phase) * 0.4
			entry.part.CFrame = CFrame.new(entry.base.Position + Vector3.new(0, bob, 0))
				* CFrame.Angles(0, spinAccumulator * 1.2, 0)
				* entry.base.Rotation
		end
	end)
end

return PickupService
