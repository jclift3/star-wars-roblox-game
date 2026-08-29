--!strict
--[[
	GalaxyMapController.luau

	The galaxy map. Opens with G.

	WHY THIS EXISTS
	Nine worlds were authored and one was reachable. `PlayerService.travelTo`
	could move a player between them and nothing ever called it -- the same gap
	the mission board filled for missions. This is the entry point, not a new
	system.

	IT SHOWS THE PRICE AND IT SHOWS WHY
	The interesting part of travel here is not the destination, it is the fare,
	because the fare is different for every origin: an Acolyte flies Imperial
	space for nothing and pays double everywhere else, a Scrapper works passage
	for almost nothing and waits three minutes to do it. A number alone would
	just read as a tax, so every quote carries the server's one-line reason and
	the panel prints it under the price.

	THE SERVER OWNS THE ANSWER
	`GetGalaxy` returns the fare, the lock reason and the cooldown already
	computed. Travelling sends nothing but a planet id, and TravelService
	re-derives the price from config before charging it -- so a tampered client
	can render a lie but cannot act on one.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)

local Theme = require(script.Parent.Parent.UI.Theme)

local GalaxyMapController = {
	name = "GalaxyMapController",
	priority = 44,
}

local player = Players.LocalPlayer

local PANEL = Theme.PANEL
local ROW = Theme.ROW
local ROW_SELECTED = Theme.ROW_SELECTED
local ACCENT = Theme.ACCENT
local TEXT = Theme.TEXT
local DIM = Theme.DIM
local GOOD = Theme.GOOD
local BAD = Theme.BAD

local TOGGLE_KEY = Panels.toggleKey("GalaxyMapController")

--- Where the player stands with whoever runs the world. See TravelService.
type Standing = {
	faction: string,
	rank: string,
	attitude: string,
	rep: number,
	nextRank: string?,
	nextAt: number?,
}

--- One destination, exactly as TravelService.Destination describes it.
type Destination = {
	id: string,
	displayName: string,
	description: string,
	region: string,
	standing: Standing,
	minLevel: number,
	maxLevel: number,
	credits: number,
	free: boolean,
	note: string,
	current: boolean,
	locked: string?,
}

type Galaxy = {
	credits: number,
	level: number,
	currentPlanet: string,
	originName: string,
	originNote: string,
	cooldownLeft: number,
	--- True when the player is at the controls of their own starship, which
	--- turns the button from a ticket into a heading.
	canFly: boolean,
	destinations: { Destination },
}

local screen: ScreenGui
local subtitleLabel: TextLabel
local listFrame: ScrollingFrame
local detailTitle: TextLabel
local detailRegion: TextLabel
local detailBody: TextLabel
local detailStanding: TextLabel
local detailFare: TextLabel
local detailNote: TextLabel
local actionButton: TextButton

local open = false
local galaxy: Galaxy? = nil
local selected: string? = nil

-- Guards two refreshes racing: `invokeServer` yields, so travelling and
-- reopening can return replies out of order.
local refreshToken = 0

--------------------------------------------------------------------------------
-- Construction helpers
--------------------------------------------------------------------------------

local corner = Theme.corner
local text = Theme.text
local button = Theme.button

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

	detailRegion = text("Region", pane, 12, DIM)
	detailRegion.Position = UDim2.fromOffset(0, 26)
	detailRegion.Size = UDim2.new(1, 0, 0, 16)

	detailBody = text("Body", pane, 13, DIM)
	detailBody.Position = UDim2.fromOffset(0, 52)
	detailBody.Size = UDim2.new(1, 0, 0, 104)
	detailBody.TextWrapped = true

	-- Takes the line the level band used to have; the band moved up to join the
	-- region, since both are facts about the place and this one is about you.
	detailStanding = text("Standing", pane, 13, TEXT)
	detailStanding.Position = UDim2.fromOffset(0, 164)
	detailStanding.Size = UDim2.new(1, 0, 0, 20)

	detailFare = text("Fare", pane, 15, GOOD)
	detailFare.Font = Enum.Font.GothamBold
	detailFare.Position = UDim2.fromOffset(0, 190)
	detailFare.Size = UDim2.new(1, 0, 0, 22)

	-- The whole point of the feature: not what it costs, but why it costs that
	-- for *this* character.
	detailNote = text("Note", pane, 12, DIM)
	detailNote.Position = UDim2.fromOffset(0, 214)
	detailNote.Size = UDim2.new(1, 0, 0, 54)
	detailNote.TextWrapped = true

	actionButton = button("Action", pane, "")
	actionButton.Position = UDim2.new(0, 0, 1, -58)
	actionButton.Size = UDim2.new(1, 0, 0, 40)
	actionButton.TextSize = 14
end

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "GalaxyMapGui"
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
	title.Text = "GALAXY"
	title.Position = UDim2.fromOffset(18, 16)
	title.Size = UDim2.fromOffset(300, 26)

	subtitleLabel = text("Subtitle", root, 13, DIM)
	subtitleLabel.Position = UDim2.fromOffset(18, 40)
	subtitleLabel.Size = UDim2.new(1, -70, 0, 18)

	local close = button("Close", root, "X")
	close.Position = UDim2.new(1, -42, 0, 16)
	close.Size = UDim2.fromOffset(28, 28)
	close.Activated:Connect(function()
		GalaxyMapController.setOpen(false)
	end)

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
-- Rendering
--------------------------------------------------------------------------------

local render: () -> ()

local function find(planetId: string?): Destination?
	if not planetId or not galaxy then
		return nil
	end
	for _, dest in galaxy.destinations do
		if dest.id == planetId then
			return dest
		end
	end
	return nil
end

local function renderDetail()
	local dest = find(selected)
	if not dest then
		detailTitle.Text = "Nothing selected"
		detailRegion.Text = ""
		detailBody.Text = ""
		detailStanding.Text = ""
		detailFare.Text = ""
		detailNote.Text = ""
		actionButton.Visible = false
		return
	end

	detailTitle.Text = dest.displayName
	detailRegion.Text = `{dest.region}  ·  Levels {dest.minLevel}-{dest.maxLevel}`
	detailBody.Text = dest.description

	-- Attitude is spelled out only when it is not Neutral: the useful signal is
	-- "they will shoot you" or "they will deal with you", and printing Neutral
	-- on eight worlds out of nine would bury both.
	local standing = dest.standing
	local ladder = if standing.nextAt then `  ·  {standing.rep}/{standing.nextAt}` else ""
	local mood = if standing.attitude == "Neutral" then "" else `  ·  {string.upper(standing.attitude)}`
	detailStanding.Text = `{standing.faction}: {standing.rank}{mood}{ladder}`
	detailStanding.TextColor3 = if standing.attitude == "Hostile"
		then BAD
		elseif standing.attitude == "Friendly" then GOOD
		else TEXT

	if dest.current then
		detailFare.Text = "You are here"
		detailFare.TextColor3 = ACCENT
		detailNote.Text = ""
		actionButton.Visible = false
		return
	end

	detailFare.Text = if dest.free then "No fare" else `{dest.credits} credits`
	detailFare.TextColor3 = if dest.free then GOOD else TEXT
	detailNote.Text = dest.note

	actionButton.Visible = true
	if dest.locked then
		actionButton.Text = string.upper(dest.locked)
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = BAD
		actionButton.Active = false
	else
		--[[
			The one word that says which of the two travel systems you are
			about to use.

			DEPART is a ticket: you arrive. SET COURSE is a heading: the
			fuel comes off, the lane is laid in, and you still have to fly
			it. A player at the controls of their own ship is never given
			the ticket, because the ship is the reason they are up there.
		]]
		local flying = galaxy ~= nil and (galaxy :: Galaxy).canFly
		actionButton.Text = if flying then "SET COURSE" else "DEPART"
		actionButton.BackgroundColor3 = ACCENT
		actionButton.TextColor3 = Color3.new(0, 0, 0)
		actionButton.Active = true
	end
end

local function renderList()
	for _, child in listFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not galaxy then
		return
	end

	for index, dest in galaxy.destinations do
		local row = button(dest.id, listFrame, "")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -8, 0, 46)
		row.Text = ""
		row.BackgroundColor3 = if selected == dest.id then ROW_SELECTED else ROW
		row.BackgroundTransparency = 0.25

		local name = text("Name", row, 14, TEXT)
		name.Font = Enum.Font.GothamBold
		name.Position = UDim2.fromOffset(12, 7)
		name.Size = UDim2.new(1, -120, 0, 18)
		name.Text = dest.displayName

		local tag = text("Tag", row, 12, DIM)
		tag.Position = UDim2.fromOffset(12, 25)
		tag.Size = UDim2.new(1, -120, 0, 16)
		local mood = if dest.standing.attitude == "Neutral"
			then ""
			else `  ·  {string.upper(dest.standing.attitude)}`
		tag.Text = `{dest.region}  ·  Levels {dest.minLevel}-{dest.maxLevel}{mood}`

		local status = text("Status", row, 13, DIM)
		status.TextXAlignment = Enum.TextXAlignment.Right
		status.AnchorPoint = Vector2.new(1, 0)
		status.Position = UDim2.new(1, -12, 0, 14)
		status.Size = UDim2.fromOffset(104, 18)

		if dest.current then
			status.Text = "HERE"
			status.TextColor3 = ACCENT
		elseif dest.locked then
			status.Text = "LOCKED"
			status.TextColor3 = BAD
		elseif dest.free then
			status.Text = "FREE"
			status.TextColor3 = GOOD
		else
			status.Text = `{dest.credits} cr`
			status.TextColor3 = GOOD
		end

		row.Activated:Connect(function()
			selected = dest.id
			render()
		end)
	end
end

function render()
	if not galaxy then
		subtitleLabel.Text = "Loading..."
		renderList()
		renderDetail()
		return
	end
	local g = galaxy :: Galaxy

	local waiting = if g.cooldownLeft > 0
		then `  ·  next berth in {math.ceil(g.cooldownLeft / 60)} min`
		else ""
	subtitleLabel.Text = `{g.originName}  ·  {g.credits} cr{waiting}  --  {g.originNote}`

	-- Never open on a blank detail pane, and drop a selection that no longer
	-- exists rather than describing a stale world.
	if not find(selected) then
		selected = if #g.destinations > 0 then g.destinations[1].id else nil
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

	local result = Net.invokeServer(Net.Function.GetGalaxy) :: Galaxy?
	if token ~= refreshToken then
		return
	end
	galaxy = result
	render()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Whether the panel is showing. Read by InputController so booking passage
--- does not also fire a blaster through whoever is selling it.
function GalaxyMapController.isOpen(): boolean
	return open
end

function GalaxyMapController.setOpen(value: boolean)
	if open == value then
		return
	end
	open = value
	screen.Enabled = value
	if value then
		-- See the matching note in MissionBoardController.setOpen.
		Panels.closeAllExcept(GalaxyMapController.name)
		task.spawn(refresh)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function GalaxyMapController.init()
	build()
end

function GalaxyMapController.start()
	actionButton.Activated:Connect(function()
		local dest = find(selected)
		if not (dest and not dest.current and not dest.locked) then
			return
		end
		if galaxy and (galaxy :: Galaxy).canFly then
			Net.fireServer(Net.Event.SetCourse, dest.id)
			-- Closed here rather than on a reply, because the next thing the
			-- player needs is the view: the course they have just bought is
			-- flown by hand and the panel is over the windscreen.
			GalaxyMapController.setOpen(false)
		else
			Net.fireServer(Net.Event.TravelTo, dest.id)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			GalaxyMapController.setOpen(not open)
		elseif input.KeyCode == Enum.KeyCode.Escape and open then
			GalaxyMapController.setOpen(false)
		end
	end)

	--[[
		Arriving closes the map. Leaving it open over a world you have just
		landed on would show every fare quoted from where you used to be, and
		the character respawn underneath it is disorienting enough already.
	]]
	Net.onClientEvent(Net.Event.Travelled, function()
		GalaxyMapController.setOpen(false)
	end)
end

return GalaxyMapController
