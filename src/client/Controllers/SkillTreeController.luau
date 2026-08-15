--!strict
--[[
	SkillTreeController.luau

	The skill tree. Opens with K.

	WHY THIS EXISTS
	Every level awards a skill point, ProgressionService has always been able to
	spend one, and Progression.canPurchase was written to hand back a refusal
	reason "so the UI can explain the refusal" -- but no UI ever fired
	SpendSkillPoint. Points have been piling up unspendable since the first
	kill. This is the missing entry point, the same shape of gap the mission
	board filled.

	FOUR TREES, ONE PANEL
	A tab per tree, a row per node, one detail pane. Rows show the rank a node
	is at; the pane explains what the next rank buys and, when the answer is
	"nothing yet", why not -- straight from `canPurchase`, so the panel and the
	server can never disagree about whether a purchase is legal.

	THE SERVER OWNS THE ANSWER
	Spending sends a node id and nothing else. ProgressionService re-checks
	`canPurchase` on arrival, so a client that renders an unlocked node it has
	no right to still cannot buy it.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Palette = require(Shared.Config.Palette)
local Progression = require(Shared.Config.Progression)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Types = require(Shared.Types)

type SkillId = Types.SkillId
type SkillNode = Progression.SkillNode

local SkillTreeController = {
	name = "SkillTreeController",
	priority = 47,
}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(14, 16, 20)
local ROW = Color3.fromRGB(26, 30, 37)
local ROW_SELECTED = Color3.fromRGB(44, 52, 64)
local ACCENT = Palette.RebelOrange
local TEXT = Color3.fromRGB(232, 236, 242)
local DIM = Color3.fromRGB(150, 158, 170)
local GOOD = Color3.fromRGB(96, 190, 120)
local BAD = Color3.fromRGB(198, 78, 78)

local TOGGLE_KEY = Enum.KeyCode.K

-- Panels that own the whole screen. Opening one closes the rest.
local OTHER_PANELS = { "InventoryController", "MissionBoardController", "DialogueController" }

local PIP_COUNT = Progression.MAX_NODE_RANK

local screen: ScreenGui
local root: Frame
local subtitleLabel: TextLabel
local xpFill: Frame
local xpLabel: TextLabel
local listFrame: ScrollingFrame
local detailTitle: TextLabel
local detailBody: TextLabel
local detailEffect: TextLabel
local detailRequirement: TextLabel
local actionButton: TextButton
-- `id` is a plain string rather than a SkillId because a table literal widens
-- singleton types, so the record can never be built as the narrower one.
local tabButtons: { { id: string, button: TextButton } } = {}

local open = false
local activeTab: SkillId = "Combat"
local selected: { [string]: string? } = {}

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

local function text(name: string, parent: Instance, size: number, colour: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = colour or TEXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Text = ""
	l.Parent = parent
	return l
end

local function button(name: string, parent: Instance, label: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = true
	b.BackgroundColor3 = ROW
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = TEXT
	b.Text = label
	b.Parent = parent
	corner(b, 4)
	return b
end

--------------------------------------------------------------------------------
-- Numbers as prose
--------------------------------------------------------------------------------

--[[
	Whether a stat is a fraction of something rather than a flat amount.

	The naming convention in Progression.baseStats carries this: everything
	ending in Mult or Chance is a proportion and reads as a percentage, and
	everything else (BonusHealth, MaxForce, SliceTier) is a raw number. That
	covers every stat a skill node touches, so no per-node formatting data is
	needed.
]]
local function isProportion(stat: string): boolean
	return string.match(stat, "Mult$") ~= nil or string.match(stat, "Chance$") ~= nil
end

--- The node's total contribution at `rank`, written the way a player reads it.
local function effectAt(def: SkillNode, rank: number): string
	local total = def.effect.perRank * rank
	if isProportion(def.effect.stat) then
		return string.format("%+d%%", math.round(total * 100))
	end
	local rounded = math.round(total * 10) / 10
	if rounded == math.floor(rounded) then
		return string.format("%+d", rounded)
	end
	return string.format("%+.1f", rounded)
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function buildDetailPane(parent: Frame)
	local pane = Instance.new("Frame")
	pane.Name = "Detail"
	pane.BackgroundColor3 = ROW
	pane.BackgroundTransparency = 0.4
	pane.BorderSizePixel = 0
	pane.Position = UDim2.new(0, 372, 0, 116)
	pane.Size = UDim2.new(1, -388, 1, -132)
	pane.Parent = parent
	corner(pane, 5)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = pane

	detailTitle = text("Title", pane, 17, ACCENT)
	detailTitle.Font = Enum.Font.GothamBold
	detailTitle.Size = UDim2.new(1, 0, 0, 24)

	detailBody = text("Body", pane, 13, DIM)
	detailBody.Position = UDim2.fromOffset(0, 32)
	detailBody.Size = UDim2.new(1, 0, 0, 80)
	detailBody.TextWrapped = true

	detailEffect = text("Effect", pane, 14, TEXT)
	detailEffect.Font = Enum.Font.GothamBold
	detailEffect.Position = UDim2.fromOffset(0, 120)
	detailEffect.Size = UDim2.new(1, 0, 0, 44)
	detailEffect.TextWrapped = true

	detailRequirement = text("Requirement", pane, 13, DIM)
	detailRequirement.Position = UDim2.fromOffset(0, 172)
	detailRequirement.Size = UDim2.new(1, 0, 0, 54)
	detailRequirement.TextWrapped = true

	actionButton = button("Action", pane, "")
	actionButton.Position = UDim2.new(0, 0, 1, -58)
	actionButton.Size = UDim2.new(1, 0, 0, 40)
	actionButton.TextSize = 14
end

local function buildTabs(parent: Frame)
	for index, tree in Progression.TREES do
		local b = button(tree, parent, string.upper(tree))
		b.Position = UDim2.fromOffset(16 + (index - 1) * 86, 80)
		b.Size = UDim2.fromOffset(80, 28)
		b.TextSize = 11
		table.insert(tabButtons, { id = tree, button = b })
	end
end

local function buildHeader(parent: Frame)
	local title = text("Title", parent, 20, TEXT)
	title.Font = Enum.Font.GothamBold
	title.Text = "SKILLS"
	title.Position = UDim2.fromOffset(18, 16)
	title.Size = UDim2.fromOffset(300, 26)

	subtitleLabel = text("Subtitle", parent, 13, DIM)
	subtitleLabel.Position = UDim2.fromOffset(18, 40)
	subtitleLabel.Size = UDim2.new(1, -70, 0, 18)

	local track = Instance.new("Frame")
	track.Name = "XpTrack"
	track.BackgroundColor3 = ROW
	track.BorderSizePixel = 0
	track.Position = UDim2.fromOffset(18, 64)
	track.Size = UDim2.new(1, -36, 0, 6)
	track.Parent = parent
	corner(track, 3)

	xpFill = Instance.new("Frame")
	xpFill.Name = "XpFill"
	xpFill.BackgroundColor3 = ACCENT
	xpFill.BorderSizePixel = 0
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.Parent = track
	corner(xpFill, 3)

	xpLabel = text("Xp", parent, 12, DIM)
	xpLabel.TextXAlignment = Enum.TextXAlignment.Right
	xpLabel.AnchorPoint = Vector2.new(1, 0)
	xpLabel.Position = UDim2.new(1, -52, 0, 40)
	xpLabel.Size = UDim2.fromOffset(220, 18)
end

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "SkillTreeGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 10
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")

	root = Instance.new("Frame")
	root.Name = "Panel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(760, 470)
	root.BackgroundColor3 = PANEL
	root.BackgroundTransparency = 0.06
	root.BorderSizePixel = 0
	root.Parent = screen
	corner(root, 8)

	buildHeader(root)

	local close = button("Close", root, "X")
	close.Position = UDim2.new(1, -42, 0, 16)
	close.Size = UDim2.fromOffset(28, 28)
	close.Activated:Connect(function()
		SkillTreeController.setOpen(false)
	end)

	buildTabs(root)

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "List"
	listFrame.Position = UDim2.fromOffset(16, 116)
	listFrame.Size = UDim2.new(0, 344, 1, -132)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 4
	listFrame.CanvasSize = UDim2.new()
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame

	buildDetailPane(root)
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local render: () -> ()

--- Five lamps, lit up to `rank`. Reading a build at a glance beats reading "3/5".
local function pips(parent: GuiObject, rank: number, max: number)
	local strip = Instance.new("Frame")
	strip.Name = "Pips"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(1, 0.5)
	strip.Position = UDim2.new(1, -12, 0.5, 0)
	strip.Size = UDim2.fromOffset(PIP_COUNT * 12 + (PIP_COUNT - 1) * 4, 8)
	strip.Parent = parent

	for i = 1, PIP_COUNT do
		local pip = Instance.new("Frame")
		pip.Name = `Pip{i}`
		pip.BorderSizePixel = 0
		pip.Position = UDim2.fromOffset((i - 1) * 16, 0)
		pip.Size = UDim2.fromOffset(12, 8)
		-- Ranks a node does not have at all are dimmer still than ranks it has
		-- yet to buy, so a 3-rank node does not look like a maxed 5-rank one.
		if i > max then
			pip.BackgroundColor3 = PANEL
			pip.BackgroundTransparency = 0.4
		elseif i <= rank then
			pip.BackgroundColor3 = ACCENT
		else
			pip.BackgroundColor3 = ROW_SELECTED
		end
		pip.Parent = strip
		corner(pip, 2)
	end
end

local function renderDetail()
	local nodeId = selected[activeTab]
	local def = if nodeId then Progression.nodes[nodeId] else nil
	if not def then
		detailTitle.Text = "Nothing selected"
		detailBody.Text = ""
		detailEffect.Text = ""
		detailRequirement.Text = ""
		actionButton.Visible = false
		return
	end

	local profile = state().get()
	local rank = if profile then profile.skills[def.id] or 0 else 0

	detailTitle.Text = def.displayName
	detailBody.Text = def.description
	actionButton.Visible = true

	if rank >= def.maxRank then
		detailEffect.Text = `Rank {rank} of {def.maxRank}\n{effectAt(def, rank)} {def.effect.stat}`
		detailRequirement.Text = ""
		actionButton.Text = "MAXED"
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = GOOD
		actionButton.Active = false
		return
	end

	-- What the point actually buys, before it is spent. The whole reason to
	-- show a preview rather than the description alone is that "+6% per rank"
	-- does not tell a player at rank 3 what they are about to have.
	detailEffect.Text =
		`Rank {rank} of {def.maxRank}\n{effectAt(def, rank)}  ->  {effectAt(def, rank + 1)} {def.effect.stat}`

	if not profile then
		detailRequirement.Text = ""
		actionButton.Text = "LOADING"
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = DIM
		actionButton.Active = false
		return
	end

	local ok, reason = Progression.canPurchase(def.id, profile.skills, profile.level, profile.skillPoints)
	if ok then
		detailRequirement.Text = ""
		actionButton.Text = "SPEND 1 POINT"
		actionButton.BackgroundColor3 = ACCENT
		actionButton.TextColor3 = Color3.new(0, 0, 0)
		actionButton.Active = true
		return
	end

	detailRequirement.Text = reason or ""
	detailRequirement.TextColor3 = BAD
	actionButton.Text = string.upper(reason or "LOCKED")
	actionButton.BackgroundColor3 = ROW
	actionButton.TextColor3 = BAD
	actionButton.Active = false
end

local function renderList()
	for _, child in listFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local profile = state().get()

	for index, def in Progression.nodesInTree(activeTab) do
		local rank = if profile then profile.skills[def.id] or 0 else 0

		local row = button(def.id, listFrame, "")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -8, 0, 46)
		row.Text = ""
		row.BackgroundColor3 = if selected[activeTab] == def.id then ROW_SELECTED else ROW
		row.BackgroundTransparency = 0.25

		local name = text("Name", row, 14, if rank > 0 then TEXT else DIM)
		name.Font = Enum.Font.GothamBold
		name.Position = UDim2.fromOffset(12, 7)
		name.Size = UDim2.new(1, -110, 0, 18)
		name.Text = def.displayName

		local tag = text("Tag", row, 12, DIM)
		tag.Position = UDim2.fromOffset(12, 25)
		tag.Size = UDim2.new(1, -110, 0, 16)

		-- The level gate is the only thing on a row that can be a hard no, so
		-- it is the only requirement worth the space; everything else is in
		-- the detail pane.
		if profile and profile.level < def.requiredLevel then
			tag.Text = `Requires level {def.requiredLevel}`
			tag.TextColor3 = BAD
		else
			tag.Text = def.effect.stat
		end

		pips(row, rank, def.maxRank)

		row.Activated:Connect(function()
			selected[activeTab] = def.id
			render()
		end)
	end
end

function render()
	local profile = state().get()

	if profile then
		local points = profile.skillPoints
		local plural = if points == 1 then "" else "s"
		subtitleLabel.Text = `Level {profile.level}  ·  {points} skill point{plural}`
		subtitleLabel.TextColor3 = if points > 0 then ACCENT else DIM

		local needed = Progression.xpForNextLevel(profile.level)
		if needed == math.huge then
			xpFill.Size = UDim2.fromScale(1, 1)
			xpLabel.Text = "Maximum level"
		else
			xpFill.Size = UDim2.fromScale(math.clamp(profile.xp / needed, 0, 1), 1)
			xpLabel.Text = `{profile.xp} / {needed} XP to level {profile.level + 1}`
		end
	else
		subtitleLabel.Text = "Loading..."
		xpLabel.Text = ""
		xpFill.Size = UDim2.fromScale(0, 1)
	end

	for _, tab in tabButtons do
		local active = tab.id == activeTab
		tab.button.BackgroundColor3 = if active then ACCENT else ROW
		tab.button.TextColor3 = if active then Color3.new(0, 0, 0) else DIM
	end

	-- Never leave the detail pane blank on open: default to the first node of
	-- the tree, which is also the cheapest one to reach.
	if selected[activeTab] == nil then
		local first = Progression.nodesInTree(activeTab)[1]
		selected[activeTab] = if first then first.id else nil
	end

	renderList()
	renderDetail()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Whether the panel is showing. Read by InputController so clicking a skill
--- does not also put a bolt through whoever is standing in front of you.
function SkillTreeController.isOpen(): boolean
	return open
end

function SkillTreeController.setOpen(value: boolean)
	if open == value then
		return
	end
	open = value
	screen.Enabled = value
	if value then
		-- Every full-screen panel is the same size in the same place. `find`
		-- rather than `get` so a broken inventory costs an overlapping panel,
		-- not a skill tree that refuses to open.
		for _, name in OTHER_PANELS do
			local panel = ServiceLoader.find(name)
			if panel then
				panel.setOpen(false)
			end
		end
		render()
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function SkillTreeController.init()
	build()
end

function SkillTreeController.start()
	actionButton.Activated:Connect(function()
		local nodeId = selected[activeTab]
		if nodeId then
			Net.fireServer(Net.Event.SpendSkillPoint, nodeId)
		end
	end)

	for _, tab in tabButtons do
		tab.button.Activated:Connect(function()
			-- Safe: every id came out of Progression.TREES.
			activeTab = tab.id :: SkillId
			render()
		end)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			SkillTreeController.setOpen(not open)
		elseif input.KeyCode == Enum.KeyCode.Escape and open then
			SkillTreeController.setOpen(false)
		end
	end)

	-- A purchase lands as a profile change, and so does the level that granted
	-- the point. Re-rendering from the new profile is what makes the button
	-- turn over from SPEND to MAXED without the player closing anything.
	state().changed:connect(function()
		if open then
			render()
		end
	end)
end

return SkillTreeController
