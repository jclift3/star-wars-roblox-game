--!strict
--[[
	WaypointController.luau

	Points at wherever the current objective is.

	WHY
	The mission board can hand you "Find the sandcrawler in the wastes" and the
	map gives no clue which direction the wastes are. A 3000-stud planet with no
	navigation is not an open world, it is a place to get lost in.

	TWO PARTS
	  - A beacon over the target, drawn through terrain and buildings, with a
	    live distance readout. Tells you where it is once you are facing it.
	  - An arrow pinned to the edge of the screen while the target is off it.
	    Tells you which way to turn to face it in the first place.

	WHAT IT POINTS AT
	The first incomplete objective of the first active mission that resolves to
	somewhere in the world. Reach and Deliver name a point of interest directly;
	Kill resolves through the archetype's spawn zone, which is the closest thing
	to "where those things live" the config knows. Objectives that resolve to
	nowhere (Collect, TalkTo) are skipped rather than guessed at -- a confidently
	wrong arrow is worse than no arrow.

	Deliberately read-only: everything here comes from the replicated profile and
	the world markers the server already built. Nothing is asked of the server.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Missions = require(Shared.Config.Missions)
local Palette = require(Shared.Config.Palette)
local Planets = require(Shared.Config.Planets)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local WaypointController = {
	name = "WaypointController",
	priority = 47,
}

local player = Players.LocalPlayer

local ACCENT = Palette.RebelOrange
local TEXT = Color3.fromRGB(232, 236, 242)

-- How far in from the screen edge the off-screen arrow sits.
local EDGE_MARGIN = 64
-- Re-resolving which objective is current is cheap but not free, and the
-- answer only changes when the profile does. The beacon position still
-- updates every frame.
local RESOLVE_INTERVAL = 0.5

local beaconGui: BillboardGui
local beaconLabel: TextLabel
local beaconDistance: TextLabel
local arrowGui: ScreenGui
local arrowLabel: TextLabel
local arrowText: TextLabel

--- The part the beacon is currently pinned to, and what to call it.
local targetPart: BasePart? = nil
local targetLabel = ""
local sinceResolve = 0

local function state()
	return ServiceLoader.get("ClientState")
end

--------------------------------------------------------------------------------
-- Resolving an objective to a place
--------------------------------------------------------------------------------

--- A named point of interest marker, if the world builder made one.
local function poiPart(planetId: string, poiId: string): BasePart?
	local root = Workspace:FindFirstChild("POI")
	local planetFolder = root and root:FindFirstChild(planetId)
	local part = planetFolder and planetFolder:FindFirstChild(poiId)
	return if part and part:IsA("BasePart") then part else nil
end

--- The first patrol point of a named zone.
local function zonePart(planetId: string, zoneName: string): BasePart?
	local root = Workspace:FindFirstChild("Zones")
	local planetFolder = root and root:FindFirstChild(planetId)
	local zone = planetFolder and planetFolder:FindFirstChild(zoneName)
	if not zone then
		return nil
	end
	for _, child in zone:GetChildren() do
		if child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

--- Where an archetype is spawned on this planet, if the planet places it.
local function zoneForArchetype(planetId: string, archetype: string): string?
	if not Planets.exists(planetId) then
		return nil
	end
	for _, rule in Planets.get(planetId).spawns do
		if rule.archetype == archetype then
			return rule.zone
		end
	end
	return nil
end

local function partForObjective(planetId: string, obj: Missions.ObjectiveDef): BasePart?
	local kind = obj.kind
	if kind == Missions.Objective.Reach and obj.target then
		return poiPart(planetId, obj.target)
	end
	if kind == Missions.Objective.Deliver and obj.destination then
		return poiPart(planetId, obj.destination)
	end
	if kind == Missions.Objective.Kill and obj.target then
		local zone = zoneForArchetype(planetId, obj.target)
		return if zone then zonePart(planetId, zone) else nil
	end
	return nil
end

--[[
	Picks the objective to point at, and pins the beacon to it.

	Missions are walked in id order so the choice is stable frame to frame --
	`profile.missions.active` is a hash map, and iterating it directly would let
	the arrow flip between two missions at random.
]]
local function resolveTarget()
	targetPart = nil
	targetLabel = ""

	local profile = state().get()
	if not profile then
		return
	end

	local ids: { string } = {}
	for missionId in profile.missions.active do
		if Missions.exists(missionId) then
			table.insert(ids, missionId)
		end
	end
	table.sort(ids)

	for _, missionId in ids do
		local mission = Missions.get(missionId)
		local entry = profile.missions.active[missionId]
		for index, obj in mission.objectives do
			local done = entry.objectives[index] or 0
			if done >= Missions.objectiveTarget(obj) then
				continue
			end
			-- Hidden objectives are not revealed yet; pointing at one would
			-- spoil the mission the tracker is carefully not spoiling.
			if obj.hidden and done == 0 then
				continue
			end
			local part = partForObjective(profile.currentPlanet, obj)
			if part then
				targetPart = part
				targetLabel = obj.description
				return
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function build()
	local gui = player:WaitForChild("PlayerGui")

	beaconGui = Instance.new("BillboardGui")
	beaconGui.Name = "ObjectiveBeacon"
	-- The whole point: readable through the building between you and it.
	beaconGui.AlwaysOnTop = true
	beaconGui.Size = UDim2.fromOffset(220, 58)
	beaconGui.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	beaconGui.ResetOnSpawn = false
	beaconGui.Enabled = false
	beaconGui.Parent = gui

	local marker = Instance.new("TextLabel")
	marker.Name = "Marker"
	marker.BackgroundTransparency = 1
	marker.Font = Enum.Font.GothamBold
	marker.TextSize = 26
	marker.TextColor3 = ACCENT
	marker.TextStrokeTransparency = 0.4
	marker.Text = "V"
	marker.Position = UDim2.fromOffset(0, 30)
	marker.Size = UDim2.new(1, 0, 0, 28)
	marker.Parent = beaconGui

	beaconLabel = Instance.new("TextLabel")
	beaconLabel.Name = "Label"
	beaconLabel.BackgroundTransparency = 1
	beaconLabel.Font = Enum.Font.GothamBold
	beaconLabel.TextSize = 14
	beaconLabel.TextColor3 = TEXT
	beaconLabel.TextStrokeTransparency = 0.4
	beaconLabel.TextWrapped = true
	beaconLabel.Size = UDim2.new(1, 0, 0, 18)
	beaconLabel.Parent = beaconGui

	beaconDistance = Instance.new("TextLabel")
	beaconDistance.Name = "Distance"
	beaconDistance.BackgroundTransparency = 1
	beaconDistance.Font = Enum.Font.Gotham
	beaconDistance.TextSize = 13
	beaconDistance.TextColor3 = ACCENT
	beaconDistance.TextStrokeTransparency = 0.5
	beaconDistance.Position = UDim2.fromOffset(0, 16)
	beaconDistance.Size = UDim2.new(1, 0, 0, 16)
	beaconDistance.Parent = beaconGui

	arrowGui = Instance.new("ScreenGui")
	arrowGui.Name = "ObjectiveArrow"
	arrowGui.ResetOnSpawn = false
	arrowGui.IgnoreGuiInset = true
	-- Under the panels: an arrow over an open shop would be noise.
	arrowGui.DisplayOrder = 5
	arrowGui.Enabled = false
	arrowGui.Parent = gui

	arrowLabel = Instance.new("TextLabel")
	arrowLabel.Name = "Arrow"
	arrowLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Font = Enum.Font.GothamBold
	arrowLabel.TextSize = 40
	arrowLabel.TextColor3 = ACCENT
	arrowLabel.TextStrokeTransparency = 0.4
	-- A glyph rather than an image, so this stays self-contained -- no asset
	-- ids, same as the rigs.
	arrowLabel.Text = "^"
	arrowLabel.Size = UDim2.fromOffset(48, 48)
	arrowLabel.Parent = arrowGui

	arrowText = Instance.new("TextLabel")
	arrowText.Name = "ArrowLabel"
	arrowText.AnchorPoint = Vector2.new(0.5, 0.5)
	arrowText.BackgroundTransparency = 1
	arrowText.Font = Enum.Font.Gotham
	arrowText.TextSize = 13
	arrowText.TextColor3 = TEXT
	arrowText.TextStrokeTransparency = 0.5
	arrowText.Size = UDim2.fromOffset(240, 18)
	arrowText.Parent = arrowGui
end

--------------------------------------------------------------------------------
-- Per-frame update
--------------------------------------------------------------------------------

local function hide()
	beaconGui.Enabled = false
	arrowGui.Enabled = false
end

local function update(dt: number)
	sinceResolve += dt
	if sinceResolve >= RESOLVE_INTERVAL then
		sinceResolve = 0
		resolveTarget()
	end

	local part = targetPart
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not part or not part.Parent or not camera or not root or not root:IsA("BasePart") then
		hide()
		return
	end

	-- A panel has the screen; a waypoint over it is clutter.
	local panel = ServiceLoader.find("InventoryController")
	local boardPanel = ServiceLoader.find("MissionBoardController")
	if (panel and panel.isOpen()) or (boardPanel and boardPanel.isOpen()) then
		hide()
		return
	end

	local distance = (part.Position - root.Position).Magnitude

	beaconGui.Adornee = part
	beaconGui.Enabled = true
	beaconLabel.Text = targetLabel
	beaconDistance.Text = `{math.floor(distance)} studs`

	local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
	if onScreen then
		arrowGui.Enabled = false
		return
	end

	local viewport = camera.ViewportSize
	local centre = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
	local direction = Vector2.new(screenPos.X, screenPos.Y) - centre
	-- Behind the camera, WorldToViewportPoint mirrors the point through the
	-- centre. Without this the arrow points exactly the wrong way whenever the
	-- objective is at your back, which is precisely when it matters.
	if screenPos.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, -1)
	end
	direction = direction.Unit

	local limitX = centre.X - EDGE_MARGIN
	local limitY = centre.Y - EDGE_MARGIN
	-- Scale the ray out to whichever edge it meets first, so the arrow rides
	-- the border rather than an inscribed circle.
	local scale = math.min(
		if math.abs(direction.X) > 1e-4 then limitX / math.abs(direction.X) else math.huge,
		if math.abs(direction.Y) > 1e-4 then limitY / math.abs(direction.Y) else math.huge
	)
	local edge = centre + direction * scale

	arrowGui.Enabled = true
	arrowLabel.Position = UDim2.fromOffset(edge.X, edge.Y)
	-- The glyph points up, so rotate from -Y round to the direction vector.
	arrowLabel.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90

	-- Keep the caption inboard of the arrow so it never runs off the edge.
	local captionOffset = 34
	arrowText.Position =
		UDim2.fromOffset(edge.X - direction.X * captionOffset, edge.Y - direction.Y * captionOffset)
	arrowText.Text = `{targetLabel}  ({math.floor(distance)})`
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function WaypointController.init()
	build()
end

function WaypointController.start()
	-- Accepting or abandoning changes the answer immediately; waiting up to
	-- RESOLVE_INTERVAL would leave the old objective's arrow on screen.
	state().changed:connect(function()
		sinceResolve = RESOLVE_INTERVAL
	end)

	RunService.RenderStepped:Connect(update)
end

return WaypointController
