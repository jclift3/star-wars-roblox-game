--!strict
--[[
	JournalController.luau

	The record of what happened. Opens with J.

	WHY THIS EXISTS AND WHY IT IS NOT THE MISSION BOARD
	The board (M) answers "what can I do here, now". It cannot answer "what
	have I found out", because the moment a mission is turned in it leaves the
	board entirely -- so the game's only mystery was told to the player once,
	in a briefing they clicked past, and then erased. A story the player cannot
	re-read is a story they have to have been paying attention to.

	This reads `Config/Acts.luau` down the left and, for the act selected, the
	missions of it that this character has actually done, with the debriefing
	they were given and the decisions they made along the way.

	IT COSTS NO SERVER WORK
	`DataService.clientView` already replicates `missions.completed` and
	`flags` in full, and every `MissionDef` is in Shared. There is no remote
	here and no new state: the journal is a *view*, and it is honest for free
	because it can only render what the profile already says.

	WHAT IT REFUSES TO SHOW
	An act you have not entered shows its name and "Not begun" -- enough to
	know the campaign continues, not enough to spoil it. Inside an act the
	missions you have not reached are one grey line saying how many are left,
	rather than a list of their titles. `Acts.parallel` chains are filtered to
	your own origin, the same way `boardFor` filters them.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Acts = require(Shared.Config.Acts)
local Flags = require(Shared.Config.Flags)
local Missions = require(Shared.Config.Missions)
local Palette = require(Shared.Config.Palette)
local Panels = require(Shared.Core.Panels)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Types = require(Shared.Types)

local JournalController = {
	name = "JournalController",
	priority = 47,
}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(14, 16, 20)
local ROW = Color3.fromRGB(26, 30, 37)
local ROW_SELECTED = Color3.fromRGB(44, 52, 64)
local ACCENT = Palette.RebelOrange
local TEXT = Color3.fromRGB(232, 236, 242)
local DIM = Color3.fromRGB(150, 158, 170)
local FAINT = Color3.fromRGB(104, 111, 122)
local GOOD = Color3.fromRGB(96, 190, 120)

local TOGGLE_KEY = Panels.toggleKey("JournalController")

local screen: ScreenGui
local subtitleLabel: TextLabel
local listFrame: ScrollingFrame
local pageFrame: ScrollingFrame

local open = false
local selectedAct: string? = nil

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

--[[
	A wrapped line on the page.

	`AutomaticSize` rather than a measured height: the debriefings are authored
	prose of no fixed length, and a page laid out with hardcoded offsets would
	clip the long ones -- which are precisely the ones worth reading.
]]
local function line(order: number, size: number, colour: Color3, body: string, font: Enum.Font?): TextLabel
	local l = text(`Line{order}`, pageFrame, size, colour)
	l.LayoutOrder = order
	l.Font = font or Enum.Font.Gotham
	l.Size = UDim2.new(1, -16, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.Text = body
	return l
end

local function spacer(order: number, height: number)
	local f = Instance.new("Frame")
	f.Name = `Gap{order}`
	f.LayoutOrder = order
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, height)
	f.Parent = pageFrame
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "JournalGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 10
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
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
	title.Text = "JOURNAL"
	title.Position = UDim2.fromOffset(18, 16)
	title.Size = UDim2.fromOffset(300, 26)

	subtitleLabel = text("Subtitle", root, 13, DIM)
	subtitleLabel.Position = UDim2.fromOffset(18, 40)
	subtitleLabel.Size = UDim2.new(1, -70, 0, 18)

	local close = button("Close", root, "X")
	close.Position = UDim2.new(1, -42, 0, 16)
	close.Size = UDim2.fromOffset(28, 28)
	close.Activated:Connect(function()
		JournalController.setOpen(false)
	end)

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "Acts"
	listFrame.Position = UDim2.fromOffset(16, 72)
	listFrame.Size = UDim2.new(0, 250, 1, -88)
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

	pageFrame = Instance.new("ScrollingFrame")
	pageFrame.Name = "Page"
	pageFrame.Position = UDim2.fromOffset(280, 72)
	pageFrame.Size = UDim2.new(1, -296, 1, -88)
	pageFrame.BackgroundColor3 = ROW
	pageFrame.BackgroundTransparency = 0.4
	pageFrame.BorderSizePixel = 0
	pageFrame.ScrollBarThickness = 4
	pageFrame.CanvasSize = UDim2.new()
	pageFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pageFrame.Parent = root
	corner(pageFrame, 5)

	local pageLayout = Instance.new("UIListLayout")
	pageLayout.Padding = UDim.new(0, 4)
	pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pageLayout.Parent = pageFrame

	local pagePadding = Instance.new("UIPadding")
	pagePadding.PaddingTop = UDim.new(0, 14)
	pagePadding.PaddingLeft = UDim.new(0, 14)
	pagePadding.PaddingBottom = UDim.new(0, 14)
	pagePadding.Parent = pageFrame
end

--------------------------------------------------------------------------------
-- Data shaping
--------------------------------------------------------------------------------

--[[
	The missions of `actId` this character could ever see.

	An origin-gated mission belongs to somebody else's story, and listing it
	would make every journal four fifths grey. `boardFor` hides an origin
	refusal for the same reason.
]]
local function missionsOf(actId: string, profile: Types.PlayerProfile?): { string }
	local out: { string } = {}
	for _, missionId in Acts.get(actId).missions do
		if not Missions.exists(missionId) then
			continue
		end
		local origin = Missions.get(missionId).origin
		if origin and profile and origin ~= profile.origin then
			continue
		end
		table.insert(out, missionId)
	end
	return out
end

--- How many of an act's missions are done, and how many there are to do.
local function progressOf(actId: string, profile: Types.PlayerProfile?): (number, number)
	local ids = missionsOf(actId, profile)
	if not profile then
		return 0, #ids
	end
	local done = 0
	for _, missionId in ids do
		if (profile.missions.completed[missionId] or 0) > 0 then
			done += 1
		end
	end
	return done, #ids
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local render: () -> ()

local function renderPage()
	for _, child in pageFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local actId = selectedAct
	if not actId or not Acts.exists(actId) then
		line(1, 13, DIM, "Nothing selected.")
		return
	end

	local act = Acts.get(actId)
	local profile = state().get()
	local done, total = progressOf(actId, profile)
	local order = 0
	local function at(): number
		order += 1
		return order
	end

	local heading = line(at(), 17, ACCENT, act.name, Enum.Font.GothamBold)
	heading.Size = UDim2.new(1, -16, 0, 22)
	heading.AutomaticSize = Enum.AutomaticSize.None

	if done == 0 then
		line(at(), 13, DIM, if act.parallel then "Your own work. Not begun." else "Not begun.")
		return
	end

	line(at(), 13, DIM, act.subtitle)
	spacer(at(), 8)

	local remaining = 0
	for _, missionId in missionsOf(actId, profile) do
		local mission = Missions.get(missionId)
		local finished = profile ~= nil and (profile.missions.completed[missionId] or 0) > 0
		local active = profile ~= nil and profile.missions.active[missionId] ~= nil

		if finished then
			line(at(), 14, TEXT, mission.displayName, Enum.Font.GothamBold)
			line(at(), 13, DIM, mission.debriefing or mission.summary)
			spacer(at(), 8)
		elseif active then
			line(at(), 14, ACCENT, `{mission.displayName}  ·  in hand`, Enum.Font.GothamBold)
			line(at(), 13, DIM, mission.summary)
			spacer(at(), 8)
		else
			remaining += 1
		end
	end

	--[[
		The unreached ones as a count, not as titles. A journal that lists what
		is coming is a table of contents, and this is meant to read as a record
		of what a character has been through.
	]]
	if remaining > 0 then
		line(at(), 13, FAINT, `{remaining} more still ahead of you.`)
		spacer(at(), 8)
	end

	local decisions: { string } = {}
	for _, flag in Flags.journalFor(actId) do
		if profile and profile.flags[flag.id] and flag.journal then
			table.insert(decisions, `  · {flag.journal}`)
		end
	end
	if #decisions > 0 then
		line(at(), 14, GOOD, "What you chose", Enum.Font.GothamBold)
		line(at(), 13, DIM, table.concat(decisions, "\n"))
	end

	if done >= total then
		spacer(at(), 4)
		line(at(), 12, FAINT, "This chapter is closed.")
	end
end

local function renderList()
	for _, child in listFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local profile = state().get()
	for index, actId in Acts.ids() do
		local act = Acts.get(actId)
		local done, total = progressOf(actId, profile)

		local row = button(actId, listFrame, "")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -8, 0, 46)
		row.Text = ""
		row.BackgroundColor3 = if selectedAct == actId then ROW_SELECTED else ROW
		row.BackgroundTransparency = 0.25

		local name = text("Name", row, 14, if done > 0 then TEXT else FAINT)
		name.Font = Enum.Font.GothamBold
		name.Position = UDim2.fromOffset(12, 7)
		name.Size = UDim2.new(1, -24, 0, 18)
		-- Parallel acts are not numbered: they run beside the spine, and a "5"
		-- next to one would tell the player to leave their own story for last.
		name.Text = if act.parallel then act.name else `{act.order}.  {act.name}`

		local status = text("Status", row, 12, DIM)
		status.Position = UDim2.fromOffset(12, 25)
		status.Size = UDim2.new(1, -24, 0, 16)
		if done == 0 then
			status.Text = "Not begun"
			status.TextColor3 = FAINT
		elseif done >= total then
			status.Text = `Complete  ·  {done}/{total}`
			status.TextColor3 = GOOD
		else
			status.Text = `{done}/{total}`
			status.TextColor3 = ACCENT
		end

		row.Activated:Connect(function()
			selectedAct = actId
			render()
		end)
	end
end

function render()
	local profile = state().get()
	if not profile then
		subtitleLabel.Text = "Loading..."
	else
		local done = 0
		local total = 0
		for _, actId in Acts.ids() do
			local d, t = progressOf(actId, profile)
			done += d
			total += t
		end
		subtitleLabel.Text = `{done} of {total} recorded`
	end

	-- Default to the last act with anything in it, so opening the journal
	-- lands on where the story currently is rather than on the prologue.
	if not selectedAct or not Acts.exists(selectedAct) then
		local ids = Acts.ids()
		selectedAct = ids[1]
		for _, actId in ids do
			local done = progressOf(actId, profile)
			if done > 0 then
				selectedAct = actId
			end
		end
	end

	renderList()
	renderPage()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function JournalController.isOpen(): boolean
	return open
end

function JournalController.setOpen(value: boolean)
	if open == value then
		return
	end
	open = value
	screen.Enabled = value
	if value then
		Panels.closeAllExcept(JournalController.name)
		render()
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function JournalController.init()
	build()
end

function JournalController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			JournalController.setOpen(not open)
		elseif input.KeyCode == Enum.KeyCode.Escape and open then
			JournalController.setOpen(false)
		end
	end)

	-- Turning a mission in while the journal is up should write the entry in
	-- front of you. It cannot happen from inside the panel, but it can from a
	-- kill that lands on the last objective.
	state().changed:connect(function()
		if open then
			render()
		end
	end)
end

return JournalController
