--!strict
--[[
	AbilityBarController.luau

	The four slots along the bottom of the screen, and the keys that fire them.

	WHAT IT IS ALLOWED TO DECIDE
	Nothing. It sends an ability id and where the camera is pointing; the server
	decides whether that happens. The cooldown sweep drawn here is a *guess*,
	started on the key press so the button responds in the same frame -- and
	cleared the moment the server says no. A bar that waited for a round trip
	before greying out would feel broken on any connection worse than a LAN.

	IT DRAWS WHAT THE SKILL TREE UNLOCKED
	The slots are `Abilities.unlockedBy(profile.skills)`, so buying a rank of
	Force Push is the same event as a button appearing. There is no separate
	"equip an ability" step, because with five abilities and four slots there is
	nothing to choose between yet, and a loadout screen for a list that fits on
	screen is a menu standing where a feature should be.

	NUMBER KEYS ARE SHARED
	`DialogueController` answers with 1-4 as well. Every press here is refused
	while any panel or a conversation is open -- see `Panels.anyOpen`.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)
local Palette = require(Shared.Config.Palette)
local Abilities = require(Shared.Config.Abilities)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local AbilityBarController = {
	name = "AbilityBarController",
	priority = 41,
}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(14, 16, 20)
local ACCENT = Palette.RebelOrange
local TEXT = Color3.fromRGB(232, 236, 242)
local DIM = Color3.fromRGB(150, 158, 170)
local FORCE = Color3.fromRGB(96, 160, 236)

local SLOT_SIZE = 58
local SLOT_GAP = 8

--- Four, because there are four number keys the bar can have without taking
--- one off a conversation. A fifth ability will need a real loadout screen.
local MAX_SLOTS = 4

local ONE_KEY = Enum.KeyCode.One.Value

type Slot = {
	button: TextButton,
	sweep: Frame,
	key: TextLabel,
	name: TextLabel,
	abilityId: string?,
}

local screen: ScreenGui
local row: Frame
local slots: { Slot } = {}
local forceTrack: Frame
local forceFill: Frame
local forceLabel: TextLabel

--- os.clock() at which each ability is predicted to be usable again.
local readyAt: { [string]: number } = {}

local function state()
	return ServiceLoader.get("ClientState")
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function buildSlot(index: number): Slot
	local button = Instance.new("TextButton")
	button.Name = `Slot{index}`
	button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	button.BackgroundColor3 = PANEL
	button.BackgroundTransparency = 0.2
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.LayoutOrder = index
	button.Visible = false
	button.Parent = row
	corner(button, 6)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(52, 58, 68)
	stroke.Thickness = 1
	stroke.Parent = button

	--[[
		Anchored to the bottom and shrunk upwards, so a cooldown reads as a
		glass filling rather than a bar sliding. Drawn over the label but
		mostly transparent -- the player still has to be able to tell which
		slot is which while it is recharging.
	]]
	local sweep = Instance.new("Frame")
	sweep.Name = "Sweep"
	sweep.AnchorPoint = Vector2.new(0, 1)
	sweep.Position = UDim2.fromScale(0, 1)
	sweep.Size = UDim2.fromScale(1, 0)
	sweep.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	sweep.BackgroundTransparency = 0.45
	sweep.BorderSizePixel = 0
	sweep.ZIndex = 3
	sweep.Parent = button
	corner(sweep, 6)

	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.BackgroundTransparency = 1
	key.Font = Enum.Font.GothamBold
	key.TextSize = 12
	key.TextColor3 = ACCENT
	key.Position = UDim2.fromOffset(6, 4)
	key.Size = UDim2.fromOffset(16, 14)
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.ZIndex = 4
	key.Text = tostring(index)
	key.Parent = button

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.Gotham
	name.TextSize = 11
	name.TextColor3 = TEXT
	name.TextWrapped = true
	name.Position = UDim2.fromOffset(4, 18)
	name.Size = UDim2.new(1, -8, 1, -22)
	name.ZIndex = 4
	name.Text = ""
	name.Parent = button

	return { button = button, sweep = sweep, key = key, name = name, abilityId = nil }
end

local function build()
	--[[
		Bottom centre, and clear of the status panel in the bottom-left corner
		(300 wide at x = 16). Centring rather than tucking it next to the
		status panel keeps it under the crosshair, which is where the eye
		already is in a fight.
	]]
	row = Instance.new("Frame")
	row.Name = "AbilityBar"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -16)
	row.Size = UDim2.fromOffset(MAX_SLOTS * SLOT_SIZE + (MAX_SLOTS - 1) * SLOT_GAP, SLOT_SIZE)
	row.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.Parent = row

	for index = 1, MAX_SLOTS do
		slots[index] = buildSlot(index)
	end

	-- Above the slots. Hidden entirely for a character with no Force at all,
	-- because an empty meter that can never fill is worse than no meter.
	forceTrack = Instance.new("Frame")
	forceTrack.Name = "Force"
	forceTrack.AnchorPoint = Vector2.new(0.5, 1)
	forceTrack.Position = UDim2.new(0.5, 0, 1, -(16 + SLOT_SIZE + 6))
	forceTrack.Size = UDim2.fromOffset(MAX_SLOTS * SLOT_SIZE + (MAX_SLOTS - 1) * SLOT_GAP, 10)
	forceTrack.BackgroundColor3 = Color3.fromRGB(40, 44, 52)
	forceTrack.BorderSizePixel = 0
	forceTrack.Visible = false
	forceTrack.Parent = screen
	corner(forceTrack, 4)

	forceFill = Instance.new("Frame")
	forceFill.Name = "Fill"
	forceFill.Size = UDim2.fromScale(1, 1)
	forceFill.BackgroundColor3 = FORCE
	forceFill.BorderSizePixel = 0
	forceFill.Parent = forceTrack
	corner(forceFill, 4)

	forceLabel = Instance.new("TextLabel")
	forceLabel.Name = "Text"
	forceLabel.BackgroundTransparency = 1
	forceLabel.Font = Enum.Font.Gotham
	forceLabel.TextSize = 10
	forceLabel.TextColor3 = TEXT
	forceLabel.Size = UDim2.fromScale(1, 1)
	forceLabel.ZIndex = 2
	forceLabel.Text = ""
	forceLabel.Parent = forceTrack
end

--------------------------------------------------------------------------------
-- Contents
--------------------------------------------------------------------------------

--- Re-reads what the tree has unlocked. Cheap, and called on every profile
--- change, because a skill purchase is the only thing that moves it.
local function refresh()
	local profile = state().get()
	local unlocked = if profile then Abilities.unlockedBy(profile.skills) else {}

	for index, slot in slots do
		local abilityId = unlocked[index]
		slot.abilityId = abilityId
		slot.button.Visible = abilityId ~= nil
		if abilityId then
			slot.name.Text = Abilities.get(abilityId).displayName
		end
	end

	row.Visible = #unlocked > 0
end

local function drawSweeps()
	local now = os.clock()
	for _, slot in slots do
		local abilityId = slot.abilityId
		if not abilityId or not slot.button.Visible then
			continue
		end
		local left = (readyAt[abilityId] or 0) - now
		if left <= 0 then
			slot.sweep.Size = UDim2.fromScale(1, 0)
			slot.name.TextColor3 = TEXT
		else
			local cooldown = Abilities.get(abilityId).cooldown
			slot.sweep.Size = UDim2.fromScale(1, math.clamp(left / cooldown, 0, 1))
			slot.name.TextColor3 = DIM
		end
	end
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local function press(index: number)
	local slot = slots[index]
	if not slot or not slot.abilityId or not slot.button.Visible then
		return
	end
	local abilityId = slot.abilityId

	-- The server checks this again with its own clock. This copy only stops
	-- the bar from spamming a remote it already knows will be refused.
	local now = os.clock()
	if now < (readyAt[abilityId] or 0) then
		return
	end
	readyAt[abilityId] = now + Abilities.get(abilityId).cooldown

	local camera = Workspace.CurrentCamera
	local direction = if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
	Net.fireServer(Net.Event.UseAbility, abilityId, direction)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function AbilityBarController.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "AbilityBar"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")

	build()

	for index, slot in slots do
		slot.button.MouseButton1Click:Connect(function()
			press(index)
		end)
	end

	Net.onClientEvent(Net.Event.AbilityRefused, function(abilityId: string, reason: string)
		-- The prediction was wrong, so drop it rather than leave the slot dark
		-- for a cooldown that never started.
		readyAt[abilityId] = 0
		ServiceLoader.get("HudController").toast(reason, "Error")
	end)

	Net.onClientEvent(Net.Event.ForceChanged, function(current: number, max: number)
		forceTrack.Visible = max > 0
		if max <= 0 then
			return
		end
		forceFill.Size = UDim2.fromScale(math.clamp(current / max, 0, 1), 1)
		forceLabel.Text = `FORCE  {current} / {max}`
	end)
end

function AbilityBarController.start()
	state().changed:connect(refresh)
	refresh()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		-- A conversation and every panel own the number keys while they are
		-- up. Answering a Hutt should not also throw a grenade at him.
		if Panels.anyOpen() then
			return
		end
		local index = input.KeyCode.Value - ONE_KEY + 1
		if index >= 1 and index <= MAX_SLOTS then
			press(index)
		end
	end)

	RunService.RenderStepped:Connect(drawSweeps)
end

return AbilityBarController
