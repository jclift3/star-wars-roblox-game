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
local Abilities = require(Shared.Config.Abilities)
local Alignment = require(Shared.Config.Alignment)
local Net = require(Shared.Core.Net)
local Palette = require(Shared.Config.Palette)
local Panels = require(Shared.Core.Panels)
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
-- Not BAD: the node is buyable. This is a price, not a refusal.
local WARN = Color3.fromRGB(214, 168, 74)

local TOGGLE_KEY = Enum.KeyCode.K

local PIP_COUNT = Progression.MAX_NODE_RANK

local screen: ScreenGui
local root: Frame
local subtitleLabel: TextLabel
local alignmentLabel: TextLabel
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

--[[
	The node's total contribution at `rank`, written the way a player reads it.

	Empty for a gate node, which has no effect at all: its worth is the part
	of the tree it opens, and the description already says so.
]]
local function effectAt(def: SkillNode, rank: number): string
	local effect = def.effect
	if not effect then
		return ""
	end
	local total = effect.perRank * rank
	if isProportion(effect.stat) then
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

	-- Right of the title, above the XP figure: the two numbers that describe
	-- the character rather than the fight sit in the same column.
	alignmentLabel = text("Alignment", parent, 14, DIM)
	alignmentLabel.Font = Enum.Font.GothamBold
	alignmentLabel.TextXAlignment = Enum.TextXAlignment.Right
	alignmentLabel.AnchorPoint = Vector2.new(1, 0)
	alignmentLabel.Position = UDim2.new(1, -52, 0, 18)
	alignmentLabel.Size = UDim2.fromOffset(260, 22)

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

--[[
	What buying the first rank of this node would permanently close off.

	Empty once the node is already owned: the choice has been made, and
	repeating the warning on every rank after it is just noise.
]]
local function closingWarning(def: SkillNode, skills: { [string]: number }): string
	local excludes = def.excludes
	if not excludes or (skills[def.id] or 0) >= 1 then
		return ""
	end
	local names = {}
	for _, other in excludes do
		local otherDef = Progression.nodes[other]
		table.insert(names, otherDef and otherDef.displayName or other)
	end
	return `Taking this closes off {table.concat(names, ", ")} for good.`
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
	--[[
		A node that grants a power says so here, and names the key it will
		land on. Almost every node in the tree is a percentage, so the four
		that are a *verb* have to be told apart before the point is spent --
		otherwise the only way to find out that Grenadier is a grenade is to
		buy it and notice a new button.
	]]
	local grants = def.ability
	detailBody.Text = if grants and Abilities.exists(grants)
		then `{def.description}\n\nUnlocks {Abilities.get(grants).displayName} on the ability bar.`
		else def.description

	--[[
		A capstone's real price, shown here rather than left to `canPurchase`.
		The refusal only ever names one reason, and "No skill points
		available" comes first -- so a player saving for one would otherwise
		see a node that looks like it costs a single point.
	]]
	local needed = def.requiresPointsInTree
	if needed and profile then
		local spent = Progression.pointsInTree(profile.skills, def.tree)
		detailBody.Text ..= `\n\nCosts {needed} points in {def.tree} first — you have spent {spent}.`
	end

	actionButton.Visible = true

	-- A gate node moves no stat, so there is nothing to name and nothing to
	-- preview -- only the rank line, which still says whether it is bought.
	local stat = if def.effect then ` {def.effect.stat}` else ""

	if rank >= def.maxRank then
		detailEffect.Text = `Rank {rank} of {def.maxRank}\n{effectAt(def, rank)}{stat}`
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
	detailEffect.Text = if def.effect
		then `Rank {rank} of {def.maxRank}\n{effectAt(def, rank)}  ->  {effectAt(def, rank + 1)}{stat}`
		else `Rank {rank} of {def.maxRank}`

	if not profile then
		detailRequirement.Text = ""
		actionButton.Text = "LOADING"
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = DIM
		actionButton.Active = false
		return
	end

	local ok, reason =
		Progression.canPurchase(def.id, profile.skills, profile.level, profile.skillPoints, profile.alignment)
	if ok then
		--[[
			The one warning the panel shows about a node it is willing to
			sell. There is no respec, so the first rank of an exclusive node
			is the most expensive click in the game, and finding out what it
			cost by going to buy the other half is not a choice -- it is a
			mistake the UI let you make.
		]]
		detailRequirement.Text = closingWarning(def, profile.skills)
		detailRequirement.TextColor3 = WARN
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
		-- the detail pane. The exception is a skill whose system does not
		-- exist: that has to be visible without clicking, because the whole
		-- point is that nobody spends a point on it by accident.
		if def.unimplemented then
			tag.Text = "COMING SOON"
			tag.TextColor3 = DIM
			name.TextColor3 = DIM
		-- The other row state that is permanent, and the only one the player
		-- caused. It has to be visible in the list: a node closed off by a
		-- choice made twenty levels ago should not still look available
		-- until it is clicked.
		elseif profile and Progression.blockedBy(def.id, profile.skills) then
			tag.Text = "CLOSED OFF"
			tag.TextColor3 = DIM
			name.TextColor3 = DIM
		elseif profile and profile.level < def.requiredLevel then
			tag.Text = `Requires level {def.requiredLevel}`
			tag.TextColor3 = BAD
		else
			-- A gate node has no stat to name, so the row says what it is for
			-- instead. "Unlocks" and nothing else would read as a bug.
			tag.Text = if def.effect then def.effect.stat else "Unlocks this tree"
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

		--[[
			Alignment lives on the skills panel and not the HUD.

			It is a character sheet number, not a combat one, and this is the
			panel a player opens to ask who they are rather than how they are
			doing. It is here at all because a value that first announces
			itself by locking a Force node is a value the player will
			experience as the game breaking.
		]]
		local band = Alignment.bandFor(profile.alignment)
		alignmentLabel.Text = string.format("%s  (%+d)", band.name, profile.alignment)
		alignmentLabel.TextColor3 = band.colour

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
		alignmentLabel.Text = ""
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
		-- See the matching note in MissionBoardController.setOpen.
		Panels.closeAllExcept(SkillTreeController.name)
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
