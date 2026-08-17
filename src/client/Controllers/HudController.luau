--!strict
--[[
	HudController.luau

	The heads-up display: health, level, XP, credits, the mission tracker and
	notifications.

	BUILT IN CODE, NOT IN STUDIO
	Every element here is constructed at runtime. A HUD assembled by hand in
	StarterGui is invisible to version control, impossible to review, and the
	single most common source of "it works in my Studio" bugs. This costs a few
	hundred lines once and is diffable forever.

	READS, NEVER WRITES
	The HUD renders ClientState and the local Humanoid. It never computes a
	value the server also computes -- the XP bar shows the server's numbers
	even when they disagree with what the client expected, because the server
	is what the player will still have tomorrow.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Affixes = require(Shared.Config.Affixes)
local Palette = require(Shared.Config.Palette)
local Weapons = require(Shared.Config.Weapons)
local Missions = require(Shared.Config.Missions)
local Planets = require(Shared.Config.Planets)
local Progression = require(Shared.Config.Progression)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local HudController = {
	name = "HudController",
	priority = 40,
}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(14, 16, 20)
local ACCENT = Palette.RebelOrange
local TEXT = Color3.fromRGB(232, 236, 242)
local DIM = Color3.fromRGB(150, 158, 170)

local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TOAST_LIFETIME = 4
local MAX_TOASTS = 4

local screen: ScreenGui
local healthFill: Frame
local healthText: TextLabel
local xpFill: Frame
local levelLabel: TextLabel
local creditsLabel: TextLabel
local planetLabel: TextLabel
local weaponLabel: TextLabel
local trackerList: Frame
local toastList: Frame

local toasts: { Frame } = {}
local toastOrder = 0

local function state()
	return ServiceLoader.get("ClientState")
end

--------------------------------------------------------------------------------
-- Construction helpers
--------------------------------------------------------------------------------

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function panel(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, 6)
	return f
end

local function text(name: string, parent: Instance, size: number, colour: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = colour or TEXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = parent
	return l
end

--- A bar with a background track and a coloured fill. Returns both.
local function bar(name: string, parent: Instance, colour: Color3): (Frame, Frame)
	local track = Instance.new("Frame")
	track.Name = name
	track.BackgroundColor3 = Color3.fromRGB(40, 44, 52)
	track.BorderSizePixel = 0
	track.Parent = parent
	corner(track, 4)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = colour
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 4)

	return track, fill
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function buildStatusPanel()
	local root = panel("Status", screen)
	root.Position = UDim2.new(0, 16, 1, -16)
	root.Size = UDim2.fromOffset(300, 92)
	root.AnchorPoint = Vector2.new(0, 1)

	levelLabel = text("Level", root, 15, ACCENT)
	levelLabel.Position = UDim2.fromOffset(12, 8)
	levelLabel.Size = UDim2.fromOffset(120, 18)
	levelLabel.Font = Enum.Font.GothamBold

	creditsLabel = text("Credits", root, 14, TEXT)
	creditsLabel.Position = UDim2.new(1, -12, 0, 8)
	creditsLabel.Size = UDim2.fromOffset(160, 18)
	creditsLabel.TextXAlignment = Enum.TextXAlignment.Right
	creditsLabel.AnchorPoint = Vector2.new(1, 0)

	local healthTrack, hFill = bar("Health", root, Color3.fromRGB(205, 62, 62))
	healthTrack.Position = UDim2.fromOffset(12, 32)
	healthTrack.Size = UDim2.new(1, -24, 0, 14)
	healthFill = hFill

	healthText = text("HealthText", healthTrack, 11, TEXT)
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.TextXAlignment = Enum.TextXAlignment.Center
	healthText.ZIndex = 2

	local xpTrack, xFill = bar("Xp", root, ACCENT)
	xpTrack.Position = UDim2.fromOffset(12, 52)
	xpTrack.Size = UDim2.new(1, -24, 0, 6)
	xpFill = xFill

	planetLabel = text("Planet", root, 12, DIM)
	planetLabel.Position = UDim2.fromOffset(12, 64)
	planetLabel.Size = UDim2.fromOffset(180, 18)

	weaponLabel = text("Weapon", root, 12, DIM)
	weaponLabel.Position = UDim2.new(1, -12, 0, 64)
	weaponLabel.Size = UDim2.fromOffset(160, 18)
	weaponLabel.TextXAlignment = Enum.TextXAlignment.Right
	weaponLabel.AnchorPoint = Vector2.new(1, 0)
end

local function buildTracker()
	local root = panel("Tracker", screen)
	root.Position = UDim2.new(1, -16, 0, 16)
	root.Size = UDim2.fromOffset(280, 0)
	root.AnchorPoint = Vector2.new(1, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Visible = false

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = root

	trackerList = root
end

local function buildToasts()
	local root = Instance.new("Frame")
	root.Name = "Toasts"
	root.BackgroundTransparency = 1
	root.Position = UDim2.new(0.5, 0, 0, 24)
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Size = UDim2.fromOffset(420, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = root

	toastList = root
end

local function buildCrosshair()
	local dot = Instance.new("Frame")
	dot.Name = "Crosshair"
	dot.Size = UDim2.fromOffset(4, 4)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dot.BackgroundTransparency = 0.25
	dot.BorderSizePixel = 0
	dot.Parent = screen
	corner(dot, 2)
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

local function setBar(fill: Frame, fraction: number)
	TweenService:Create(fill, BAR_TWEEN, { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1) }):Play()
end

local function bindHumanoid(humanoid: Humanoid)
	local function refresh()
		setBar(healthFill, humanoid.Health / math.max(1, humanoid.MaxHealth))
		healthText.Text = `{math.floor(humanoid.Health + 0.5)} / {math.floor(humanoid.MaxHealth)}`
	end
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	refresh()
end

--[[
	Rebuilds the mission tracker.

	Rebuilt wholesale rather than diffed: there are at most a handful of active
	missions, and a rebuild cannot leave a stale objective on screen the way an
	incremental update can.
]]
local function refreshTracker()
	local profile = state().get()
	if not profile then
		return
	end

	for _, child in trackerList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local order = 0
	for missionId, entry in profile.missions.active do
		if not Missions.exists(missionId) then
			continue
		end
		local mission = Missions.get(missionId)

		order += 1
		local title = text("Title", trackerList, 14, ACCENT)
		title.Font = Enum.Font.GothamBold
		title.Size = UDim2.new(1, 0, 0, 18)
		title.LayoutOrder = order
		title.Text = mission.displayName

		for index, obj in mission.objectives do
			local done = entry.objectives[index] or 0
			local needed = Missions.objectiveTarget(obj)
			-- Hidden objectives stay hidden until they can actually be worked
			-- on, so the tracker does not spoil the mission's own reveal.
			if obj.hidden and done == 0 then
				continue
			end

			order += 1
			local line = text("Objective", trackerList, 13, if done >= needed then DIM else TEXT)
			line.Size = UDim2.new(1, 0, 0, 16)
			line.LayoutOrder = order
			line.TextWrapped = true
			line.AutomaticSize = Enum.AutomaticSize.Y
			line.Text = if needed > 1
				then `  {obj.description}  ({done}/{needed})`
				else `  {if done >= needed then "[x]" else "[ ]"} {obj.description}`
		end
	end

	trackerList.Visible = order > 0
end

local function refreshProfile()
	local profile = state().get()
	if not profile then
		return
	end

	levelLabel.Text = `LEVEL {profile.level}`
	creditsLabel.Text = `{profile.credits} cr`

	local needed = Progression.xpForNextLevel(profile.level)
	setBar(xpFill, if needed > 0 then profile.xp / needed else 1)

	planetLabel.Text = if Planets.exists(profile.currentPlanet)
		then Planets.get(profile.currentPlanet).displayName
		else profile.currentPlanet

	-- Not `equipped.weapon` itself: that is a stack uid, and a rolled blaster's
	-- uid is `DH17#2`. The player is holding a Vicious DH-17, so say so.
	local weaponId = state().equippedWeapon()
	if weaponId and Weapons.exists(weaponId) then
		local rolls = state().equippedWeaponRolls()
		weaponLabel.Text = Affixes.nameFor(Weapons.get(weaponId).displayName, rolls)
		weaponLabel.TextColor3 = if rolls then Affixes.rarityOf(rolls).color else DIM
	else
		weaponLabel.Text = "Unarmed"
		weaponLabel.TextColor3 = DIM
	end

	refreshTracker()
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------

local KIND_COLOURS: { [string]: Color3 } = {
	Error = Color3.fromRGB(220, 90, 90),
	LevelUp = Palette.SaberYellow,
	Promotion = Palette.SaberGreen,
	Demotion = Color3.fromRGB(220, 120, 90),
	Reward = Palette.DroidGold,
	MissionComplete = Palette.SaberGreen,
	MissionFailed = Color3.fromRGB(220, 90, 90),
}

-- A loot toast names its rarity as its kind, so the colours come from the
-- rarity table rather than being written out a second time here.
for count = 1, Affixes.MAX_AFFIXES do
	local rarity = Affixes.rarityAt(count)
	KIND_COLOURS[rarity.name] = rarity.color
end

--[[
	Puts a message in the toast stack.

	Public because a refused ability has to say why, and the alternative was a
	second round trip: the server would have to send both a refusal the bar can
	act on and a `Notify` the HUD can draw, for one press of a key that did
	nothing. There is one toast stack; this is how you reach it.
]]
function HudController.toast(message: string, kind: string?)
	local frame = panel("Toast", toastList)
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	toastOrder += 1
	frame.LayoutOrder = toastOrder

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	local label = text("Message", frame, 14, KIND_COLOURS[kind or "Info"] or TEXT)
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = message

	table.insert(toasts, frame)
	-- Oldest first: a level-up notice should not be pushed off by chatter.
	while #toasts > MAX_TOASTS do
		local oldest = table.remove(toasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	task.delay(TOAST_LIFETIME, function()
		local index = table.find(toasts, frame)
		if index then
			table.remove(toasts, index)
		end
		if frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			for _, d in frame:GetDescendants() do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				end
			end
			task.delay(0.35, function()
				frame:Destroy()
			end)
		end
	end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HudController.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "HUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")

	buildStatusPanel()
	buildTracker()
	buildToasts()
	buildCrosshair()

	Net.onClientEvent(Net.Event.Notify, function(message: string, kind: string?)
		HudController.toast(message, kind)
	end)

	-- MissionUpdated is a nudge, not data: the authoritative copy arrives with
	-- the profile, so the tracker just redraws from whatever it now holds.
	Net.onClientEvent(Net.Event.MissionUpdated, function()
		refreshTracker()
	end)
end

function HudController.start()
	state().changed:connect(refreshProfile)
	refreshProfile()

	local function hookCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			bindHumanoid(humanoid)
		end
	end

	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(hookCharacter, character)
	end)
end

return HudController
