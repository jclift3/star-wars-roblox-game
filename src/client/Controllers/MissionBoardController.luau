--!strict
--[[
	MissionBoardController.luau

	The mission board. Opens with M.

	WHY THIS EXISTS
	MissionService could already accept, abandon and track missions, and the HUD
	could already draw the objectives of anything active -- but nothing on the
	client ever fired AcceptMission, so every authored mission in the game was
	unreachable. This panel is the missing entry point, not a new system.

	TWO LISTS, ONE PANEL
	Available work and accepted work are the same shape (a mission, a state, a
	button) so they share a row renderer and a detail pane. The tab only decides
	which set of ids gets rendered.

	THE SERVER OWNS THE ANSWER
	`GetMissionBoard` returns ids plus a locked flag and a reason; the prose
	lives in Shared.Config.Missions, which the client already has. Accepting
	sends nothing but an id, and MissionService re-checks `canAccept` on the way
	in -- so a tampered client can render a lie but cannot act on one.

	Built entirely in code, like the HUD and the inventory. See the note at the
	top of HudController for why.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Missions = require(Shared.Config.Missions)
local Net = require(Shared.Core.Net)
local Palette = require(Shared.Config.Palette)
local Panels = require(Shared.Core.Panels)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local MissionBoardController = {
	name = "MissionBoardController",
	priority = 46,
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

local TOGGLE_KEY = Panels.toggleKey("MissionBoardController")

local TAB_AVAILABLE = "Available"
local TAB_ACTIVE = "Active"

--- One row of the board as the server describes it.
type BoardEntry = {
	id: string,
	locked: boolean,
	reason: string?,
}

local screen: ScreenGui
local root: Frame
local subtitleLabel: TextLabel
local listFrame: ScrollingFrame
local detailTitle: TextLabel
local detailBody: TextLabel
local detailObjectives: TextLabel
local detailRewards: TextLabel
local actionButton: TextButton
local tabButtons: { [string]: TextButton } = {}

local open = false
local activeTab = TAB_AVAILABLE
local selected: { [string]: string? } = { [TAB_AVAILABLE] = nil, [TAB_ACTIVE] = nil }
local board: { BoardEntry } = {}

-- Guards against two refreshes racing. `invokeServer` yields, so accepting a
-- mission and immediately reopening can return replies out of order.
local refreshToken = 0

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
-- Layout
--------------------------------------------------------------------------------

local function buildDetailPane(parent: Frame)
	local pane = Instance.new("Frame")
	pane.Name = "Detail"
	pane.BackgroundColor3 = ROW
	pane.BackgroundTransparency = 0.4
	pane.BorderSizePixel = 0
	pane.Position = UDim2.new(0, 372, 0, 96)
	pane.Size = UDim2.new(1, -388, 1, -112)
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
	detailBody.Position = UDim2.fromOffset(0, 30)
	detailBody.Size = UDim2.new(1, 0, 0, 88)
	detailBody.TextWrapped = true

	detailObjectives = text("Objectives", pane, 13, TEXT)
	detailObjectives.Position = UDim2.fromOffset(0, 124)
	detailObjectives.Size = UDim2.new(1, 0, 0, 108)
	detailObjectives.TextWrapped = true

	detailRewards = text("Rewards", pane, 13, GOOD)
	detailRewards.Position = UDim2.fromOffset(0, 238)
	detailRewards.Size = UDim2.new(1, 0, 0, 54)

	actionButton = button("Action", pane, "")
	actionButton.Position = UDim2.new(0, 0, 1, -58)
	actionButton.Size = UDim2.new(1, 0, 0, 40)
	actionButton.TextSize = 14
end

local function buildTabs(parent: Frame)
	local kinds = {
		{ id = TAB_AVAILABLE, label = "AVAILABLE" },
		{ id = TAB_ACTIVE, label = "ACTIVE" },
	}
	for index, kind in kinds do
		local b = button(kind.id, parent, kind.label)
		b.Position = UDim2.fromOffset(16 + (index - 1) * 122, 60)
		b.Size = UDim2.fromOffset(114, 28)
		b.TextSize = 12
		tabButtons[kind.id] = b
	end
end

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "MissionBoardGui"
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

	local title = text("Title", root, 20, TEXT)
	title.Font = Enum.Font.GothamBold
	title.Text = "MISSIONS"
	title.Position = UDim2.fromOffset(18, 16)
	title.Size = UDim2.fromOffset(300, 26)

	subtitleLabel = text("Subtitle", root, 13, DIM)
	subtitleLabel.Position = UDim2.fromOffset(18, 40)
	subtitleLabel.Size = UDim2.new(1, -70, 0, 18)

	local close = button("Close", root, "X")
	close.Position = UDim2.new(1, -42, 0, 16)
	close.Size = UDim2.fromOffset(28, 28)
	close.Activated:Connect(function()
		MissionBoardController.setOpen(false)
	end)

	buildTabs(root)

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "List"
	listFrame.Position = UDim2.fromOffset(16, 96)
	listFrame.Size = UDim2.new(0, 344, 1, -112)
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
-- Data shaping
--------------------------------------------------------------------------------

--- Mission ids the player has accepted and not yet finished.
local function activeIds(): { string }
	local profile = state().get()
	if not profile then
		return {}
	end
	local out: { string } = {}
	for missionId in profile.missions.active do
		if Missions.exists(missionId) then
			table.insert(out, missionId)
		end
	end
	table.sort(out)
	return out
end

--[[
	The board minus anything already accepted.

	The server does not filter these out -- `boardFor` reports what exists on
	the planet -- so an accepted mission would otherwise sit in both tabs with
	an Accept button that could only ever be refused.
]]
local function availableEntries(): { BoardEntry }
	local profile = state().get()
	local out: { BoardEntry } = {}
	for _, entry in board do
		if not Missions.exists(entry.id) then
			continue
		end
		if profile and profile.missions.active[entry.id] then
			continue
		end
		table.insert(out, entry)
	end
	return out
end

local function entryFor(missionId: string): BoardEntry?
	for _, entry in board do
		if entry.id == missionId then
			return entry
		end
	end
	return nil
end

local function idsFor(tab: string): { string }
	if tab == TAB_ACTIVE then
		return activeIds()
	end
	local out: { string } = {}
	for _, entry in availableEntries() do
		table.insert(out, entry.id)
	end
	return out
end

--- Reward lines, in the order a player cares about them.
local function rewardLines(mission: Missions.MissionDef): { string }
	local rewards = mission.rewards
	local lines = { `{rewards.xp} XP`, `{rewards.credits} credits` }
	if rewards.weapon then
		table.insert(lines, rewards.weapon)
	end
	if rewards.skillPoints then
		table.insert(lines, `{rewards.skillPoints} skill point{if rewards.skillPoints > 1 then "s" else ""}`)
	end
	if rewards.items then
		for itemId, count in rewards.items do
			table.insert(lines, `{itemId} x{count}`)
		end
	end
	return lines
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local render: () -> ()

local function renderDetail()
	local missionId = selected[activeTab]
	if not missionId or not Missions.exists(missionId) then
		detailTitle.Text = "Nothing selected"
		detailBody.Text = ""
		detailObjectives.Text = ""
		detailRewards.Text = ""
		actionButton.Visible = false
		return
	end

	local mission = Missions.get(missionId)
	local profile = state().get()
	local progress = if profile then profile.missions.active[missionId] else nil

	detailTitle.Text = mission.displayName
	detailBody.Text = if progress then mission.summary else mission.briefing

	local lines: { string } = {}
	for index, obj in mission.objectives do
		local done = if progress then progress.objectives[index] or 0 else 0
		local needed = Missions.objectiveTarget(obj)
		-- Hidden objectives stay hidden until they can be worked on, so
		-- reading the board does not spoil a mission's own reveal.
		if obj.hidden and done == 0 then
			continue
		end
		local suffix = if obj.optional then "  (optional)" else ""
		if needed > 1 then
			table.insert(lines, `  {obj.description}  ({done}/{needed}){suffix}`)
		else
			table.insert(lines, `  {if done >= needed then "[x]" else "[ ]"} {obj.description}{suffix}`)
		end
	end
	detailObjectives.Text = table.concat(lines, "\n")

	detailRewards.Text = `Reward: {table.concat(rewardLines(mission), ", ")}`

	actionButton.Visible = true

	if progress then
		actionButton.Text = "ABANDON"
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = BAD
		actionButton.Active = true
		return
	end

	local entry = entryFor(missionId)
	if entry and entry.locked then
		actionButton.Text = string.upper(entry.reason or "LOCKED")
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = BAD
		actionButton.Active = false
		return
	end

	actionButton.Text = "ACCEPT"
	actionButton.BackgroundColor3 = ACCENT
	actionButton.TextColor3 = Color3.new(0, 0, 0)
	actionButton.Active = true
end

local function renderList()
	for _, child in listFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local ids = idsFor(activeTab)
	for index, missionId in ids do
		local mission = Missions.get(missionId)
		local entry = entryFor(missionId)

		local row = button(missionId, listFrame, "")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -8, 0, 46)
		row.Text = ""
		row.BackgroundColor3 = if selected[activeTab] == missionId then ROW_SELECTED else ROW
		row.BackgroundTransparency = 0.25

		local name = text("Name", row, 14, TEXT)
		name.Font = Enum.Font.GothamBold
		name.Position = UDim2.fromOffset(12, 7)
		name.Size = UDim2.new(1, -120, 0, 18)
		name.Text = mission.displayName

		local tag = text("Tag", row, 12, DIM)
		tag.Position = UDim2.fromOffset(12, 25)
		tag.Size = UDim2.new(1, -120, 0, 16)
		tag.Text = `{mission.kind}  ·  Level {mission.minLevel}`

		local status = text("Status", row, 13, DIM)
		status.TextXAlignment = Enum.TextXAlignment.Right
		status.AnchorPoint = Vector2.new(1, 0)
		status.Position = UDim2.new(1, -12, 0, 14)
		status.Size = UDim2.fromOffset(104, 18)

		if activeTab == TAB_ACTIVE then
			status.Text = "ACTIVE"
			status.TextColor3 = ACCENT
		elseif entry and entry.locked then
			status.Text = "LOCKED"
			status.TextColor3 = BAD
		else
			status.Text = `{mission.rewards.credits} cr`
			status.TextColor3 = GOOD
		end

		row.Activated:Connect(function()
			selected[activeTab] = missionId
			render()
		end)
	end

	if #ids == 0 then
		local empty = text("Empty", listFrame, 13, DIM)
		empty.Size = UDim2.new(1, -8, 0, 56)
		empty.TextWrapped = true
		empty.Text = if activeTab == TAB_ACTIVE
			then "No active missions. Take one from the Available tab."
			else "No work going on this planet right now."
	end
end

function render()
	local profile = state().get()
	local activeCount = #activeIds()
	subtitleLabel.Text = if profile then `{profile.currentPlanet}  ·  {activeCount} active` else "Loading..."

	for kind, b in tabButtons do
		local active = kind == activeTab
		b.BackgroundColor3 = if active then ACCENT else ROW
		b.TextColor3 = if active then Color3.new(0, 0, 0) else DIM
	end

	-- Default the selection so the detail pane is never blank on open, and
	-- clear one that no longer exists in this tab (just accepted, just
	-- abandoned) rather than leaving the pane describing a stale row.
	local ids = idsFor(activeTab)
	local stillPresent = false
	for _, missionId in ids do
		if missionId == selected[activeTab] then
			stillPresent = true
			break
		end
	end
	if not stillPresent then
		selected[activeTab] = if #ids > 0 then ids[1] else nil
	end

	renderList()
	renderDetail()
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

local function refresh()
	refreshToken += 1
	local token = refreshToken

	local result = Net.invokeServer(Net.Function.GetMissionBoard) :: { BoardEntry }?
	-- A newer request landed while this one was in flight, or the panel closed.
	if token ~= refreshToken then
		return
	end
	board = result or {}
	render()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Whether the panel is showing. Read by InputController so reading a briefing
--- does not also empty a magazine into whoever is standing in front of you.
function MissionBoardController.isOpen(): boolean
	return open
end

function MissionBoardController.setOpen(value: boolean)
	if open == value then
		return
	end
	open = value
	screen.Enabled = value
	if value then
		-- Every full-screen panel is the same size in the same place, so only
		-- one may be up. Naming only ourselves means a new panel never has to
		-- be added here.
		Panels.closeAllExcept(MissionBoardController.name)
		task.spawn(refresh)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MissionBoardController.init()
	build()
end

function MissionBoardController.start()
	actionButton.Activated:Connect(function()
		local missionId = selected[activeTab]
		if not missionId then
			return
		end
		local profile = state().get()
		if profile and profile.missions.active[missionId] then
			Net.fireServer(Net.Event.AbandonMission, missionId)
		else
			Net.fireServer(Net.Event.AcceptMission, missionId)
		end
	end)

	for kind, b in tabButtons do
		b.Activated:Connect(function()
			activeTab = kind
			render()
		end)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			MissionBoardController.setOpen(not open)
		elseif input.KeyCode == Enum.KeyCode.Escape and open then
			MissionBoardController.setOpen(false)
		end
	end)

	--[[
		Accepting and abandoning both land as profile changes, and so does
		completing an objective. Re-rendering from the new profile keeps the
		panel honest while it is open -- including a mission ticking over from
		Available to Active without the player closing anything.

		The board itself is only re-fetched on open: which missions exist on a
		planet does not change while standing still, and `boardFor` is the
		expensive half.
	]]
	state().changed:connect(function()
		if open then
			render()
		end
	end)
end

return MissionBoardController
