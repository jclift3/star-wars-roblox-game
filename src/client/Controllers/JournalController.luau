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
local Alignment = require(Shared.Config.Alignment)
local Factions = require(Shared.Config.Factions)
local Flags = require(Shared.Config.Flags)
local Missions = require(Shared.Config.Missions)
local Origins = require(Shared.Config.Origins)
local Panels = require(Shared.Core.Panels)
local Planets = require(Shared.Config.Planets)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Parent.UI.Theme)

local JournalController = {
	name = "JournalController",
	priority = 47,
}

local player = Players.LocalPlayer

local PANEL = Theme.PANEL
local ROW = Theme.ROW
local ROW_SELECTED = Theme.ROW_SELECTED
local ACCENT = Theme.ACCENT
local TEXT = Theme.TEXT
local DIM = Theme.DIM
local FAINT = Theme.FAINT
local GOOD = Theme.GOOD

local TOGGLE_KEY = Panels.toggleKey("JournalController")

local screen: ScreenGui
local subtitleLabel: TextLabel
local listFrame: ScrollingFrame
local pageFrame: ScrollingFrame

--[[
	The pinned first page, which is not an act.

	Kept as a value of `selectedAct` rather than as a separate boolean because
	the left rail is a single column of mutually exclusive rows -- two pieces
	of state for one selection is two pieces of state that can disagree. It
	starts with a NUL so that no act id can ever collide with it.
]]
local SELF_PAGE = "\0Self"

local open = false
local selectedAct: string? = nil

local function state()
	return ServiceLoader.get("ClientState")
end

--------------------------------------------------------------------------------
-- Construction helpers
--------------------------------------------------------------------------------

local corner = Theme.corner
local text = Theme.text
local button = Theme.button

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

--[[
	Where this character sits on the one axis they cannot buy their way along.

	Reported 2026-08-29: *"there needs to be an option to see what your
	alignment is somehow."* It was already here, and on the skills panel, and
	toasted on every change -- as a band NAME. That is the bug. A name is a
	label, and a label answers "what am I called" while the player is asking
	"how far gone am I, and which way have I been going." Neither of those is
	a word, so neither of them was on the screen.

	Drawn rather than written for the same reason: the useful facts are
	distance to an end and room remaining, and a sentence can show neither.
	The number goes on it too, because `Progression.canPurchase` refuses the
	Force fork with "you have not been the kind of person this answers to" --
	deliberately vague, which is right at the moment of refusal and useless
	afterwards if there is nowhere at all to go and check.
]]
local function alignmentBar(order: number, alignment: number)
	local band = Alignment.bandFor(alignment)

	local holder = Instance.new("Frame")
	holder.Name = `Alignment{order}`
	holder.LayoutOrder = order
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -16, 0, 34)
	holder.Parent = pageFrame

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(0, 5)
	track.Size = UDim2.new(1, 0, 0, 6)
	track.BackgroundColor3 = FAINT
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = holder
	corner(track, 3)

	--[[
		Clamped even though the server clamps it.

		`profile.alignment` cannot legally leave -1000..1000, but a marker at
		a scale outside 0..1 draws outside the panel it lives in, and a layout
		that a single bad number can push off its own frame is one that
		eventually will be.
	]]
	local t = math.clamp((alignment - Alignment.MIN) / (Alignment.MAX - Alignment.MIN), 0, 1)

	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0)
	marker.Position = UDim2.new(t, 0, 0, 0)
	marker.Size = UDim2.fromOffset(4, 16)
	marker.BackgroundColor3 = band.colour
	marker.BorderSizePixel = 0
	marker.Parent = holder
	corner(marker, 2)

	-- The ends are read off `Alignment.BANDS` rather than typed, so renaming
	-- a band renames it here as well. Two spellings of "Merciless" is exactly
	-- the sort of drift that makes a player think there are two scales.
	local left = text("Dark", holder, 11, FAINT)
	left.Position = UDim2.fromOffset(0, 19)
	left.Size = UDim2.fromOffset(200, 14)
	left.Text = Alignment.titleFor(Alignment.MIN)

	local right = text("Light", holder, 11, FAINT)
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, 0, 0, 19)
	right.Size = UDim2.fromOffset(200, 14)
	right.TextXAlignment = Enum.TextXAlignment.Right
	right.Text = Alignment.titleFor(Alignment.MAX)
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

--[[
	WHO YOU ARE

	Reported from play, 2026-08-17: *"I still don't know what's going on, who I
	am."* Everything on this page already existed and every word of it had
	already been shown to the player -- once, on the creation screen, in a
	modal they dismissed to start playing, and then never again. The game knew
	who the character was; the character's own player did not.

	So this is a *view* like the rest of the journal: not one new field on the
	profile, not one new remote. `profile.origin` names an `OriginDef` that has
	been carrying the blurb and the mentor since the day origins were built,
	and the flags below are the ones the prologues already set.

	Pinned above the acts because it is the only page that is true at level 1.
]]
local function renderSelf()
	local profile = state().get()
	local order = 0
	local function at(): number
		order += 1
		return order
	end

	if not profile then
		line(at(), 13, DIM, "Loading...")
		return
	end

	local origin = if Origins.exists(profile.origin) then Origins.get(profile.origin) else nil
	local heading =
		line(at(), 17, ACCENT, if origin then origin.displayName else profile.origin, Enum.Font.GothamBold)
	heading.Size = UDim2.new(1, -16, 0, 22)
	heading.AutomaticSize = Enum.AutomaticSize.None

	local band = Alignment.bandFor(profile.alignment)
	line(
		at(),
		13,
		band.colour,
		string.format("Level %d  ·  %s  (%+d)", profile.level, band.name, profile.alignment)
	)
	alignmentBar(at(), profile.alignment)
	spacer(at(), 6)

	if origin then
		line(at(), 13, TEXT, origin.blurb)
		spacer(at(), 10)
	end

	--[[
		The facts, one per line and each of them a name the player is going to
		hear said out loud by somebody. The mentor especially: an origin's
		mentor is the person its prologue hands you to, and a player who has
		forgotten the name cannot tell a summons from a stranger.
	]]
	local facts: { string } = {}
	if origin then
		table.insert(facts, `Taught by  ·  {origin.mentor}`)
	end
	if Factions.exists(profile.faction) then
		local faction = Factions.get(profile.faction)
		local rank = Factions.rankFor(profile.faction, profile.factionRep[profile.faction] or 0)
		table.insert(facts, `Standing with {faction.displayName}  ·  {rank.name}`)
	end
	if Planets.exists(profile.homePlanet) then
		table.insert(facts, `Home  ·  {Planets.get(profile.homePlanet).displayName}`)
	end
	if Planets.exists(profile.currentPlanet) then
		table.insert(facts, `Currently on  ·  {Planets.get(profile.currentPlanet).displayName}`)
	end
	line(at(), 13, DIM, table.concat(facts, "\n"))
	spacer(at(), 12)

	--[[
		The spine, told only as far as this character has actually got.

		Three states, and the middle one is the point: a player who has done
		their prologue has seen one loose thread and does not yet know it is a
		thread. Saying "there is something here" without saying what keeps the
		mystery a mystery while making it clear the game has one -- which is
		the half that was missing.
	]]
	line(at(), 14, TEXT, "What is going on", Enum.Font.GothamBold)
	if profile.flags.NamedTheQuiet then
		line(
			at(),
			13,
			DIM,
			"It is called The Quiet. Something is taking the Force out of people and leaving the people behind. It is old, it does not care which side you are on, and it cannot touch anyone who never had the Force to lose."
		)
	elseif
		profile.flags.SawTheIntakeForm
		or profile.flags.SawBothCopies
		or profile.flags.OwesNobody
		or profile.flags.HeardNineRemember
	then
		line(
			at(),
			13,
			DIM,
			"Something you saw at the start of this does not add up, and nobody you have asked will say why. Keep pulling on it."
		)
	else
		line(at(), 13, FAINT, "Nothing yet. Finish where you started and see what it leaves you holding.")
	end
end

local function renderPage()
	for _, child in pageFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if selectedAct == SELF_PAGE then
		renderSelf()
		return
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

	-- Pinned above the acts, and not numbered with them: it is not a chapter,
	-- it is the front matter.
	do
		local row = button("Self", listFrame, "")
		row.LayoutOrder = 0
		row.Size = UDim2.new(1, -8, 0, 46)
		row.Text = ""
		row.BackgroundColor3 = if selectedAct == SELF_PAGE then ROW_SELECTED else ROW
		row.BackgroundTransparency = 0.25

		local name = text("Name", row, 14, TEXT)
		name.Font = Enum.Font.GothamBold
		name.Position = UDim2.fromOffset(12, 7)
		name.Size = UDim2.new(1, -24, 0, 18)
		name.Text = "Who you are"

		local status = text("Status", row, 12, ACCENT)
		status.Position = UDim2.fromOffset(12, 25)
		status.Size = UDim2.new(1, -24, 0, 16)
		local origin = if profile and Origins.exists(profile.origin) then Origins.get(profile.origin) else nil
		status.Text = if origin then origin.displayName else "—"

		row.Activated:Connect(function()
			selectedAct = SELF_PAGE
			render()
		end)
	end

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
	-- lands on where the story currently is rather than on the prologue. A
	-- character who has finished nothing lands on "Who you are" instead: for
	-- them every act page says "Not begun", and the one page that does have
	-- something to say is the one they need.
	if selectedAct ~= SELF_PAGE and (not selectedAct or not Acts.exists(selectedAct)) then
		local ids = Acts.ids()
		selectedAct = SELF_PAGE
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
