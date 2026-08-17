--!strict
--[[
	CreationController.luau

	The one screen with no key to open it: who you were before the game.

	WHY IT IS MODAL
	Every other panel is something you may look at. This one is a question the
	profile cannot answer, and until it is answered the character is
	`Origins.DEFAULT` -- the placeholder that made four travel profiles, four
	home worlds and four factions dead config. So there is no toggle key, no
	Escape, and `setOpen(false)` refuses while the choice is outstanding. It
	sits at a higher DisplayOrder than the 760x470 panels for the same reason:
	another panel opening behind it is harmless, in front of it is not.

	IT READS THE CONFIG DIRECTLY
	Unlike the galaxy map, which asks the server because a fare is computed per
	character, everything here is static: names, blurbs and the trade-off each
	origin advertises are all in `Shared/Config/Origins.luau`, which the client
	can require. A remote to send four constants across would be one more thing
	to keep in sync with the table it copies.

	IT IS TWO PAGES, NOT ONE
	The question, and then the answer read back: who you turned out to be, who
	is waiting for you, and which two keys the rest of it is behind. The second
	page replaced a four-second toast, and the reasoning is on `buildCard`.

	THE TRADE-OFF IS STATED BEFORE THE PICK
	`travelBlurb` exists so the Acolyte knows the Empire flies them free and
	everyone else charges double *before* they are a Sith with no money on
	Tatooine. A choice this permanent that hides its cost is a trap.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Factions = require(Shared.Config.Factions)
local Origins = require(Shared.Config.Origins)
local Palette = require(Shared.Config.Palette)
local Planets = require(Shared.Config.Planets)
local Panels = require(Shared.Core.Panels)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local CreationController = {
	name = "CreationController",
	priority = 45,
}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(14, 16, 20)
local ROW = Color3.fromRGB(26, 30, 37)
local ROW_SELECTED = Color3.fromRGB(44, 52, 64)
local ACCENT = Palette.RebelOrange
local TEXT = Color3.fromRGB(232, 236, 242)
local DIM = Color3.fromRGB(150, 158, 170)

local screen: ScreenGui
local pickerRoot: Frame
local listFrame: Frame
local detailTitle: TextLabel
local detailFacts: TextLabel
local detailBody: TextLabel
local detailTravel: TextLabel
local confirmButton: TextButton

local cardRoot: Frame
local cardTitle: TextLabel
local cardWhere: TextLabel
local cardBody: TextLabel
local cardNext: TextLabel

local open = false
local chosen = false
local selected: string = Origins.ids()[1]

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

local render: () -> ()

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

	-- Where you wake up, whose flag you wear, which tree you were built
	-- around. All three are decided here and none of them again.
	detailFacts = text("Facts", pane, 12, DIM)
	detailFacts.Position = UDim2.fromOffset(0, 26)
	detailFacts.Size = UDim2.new(1, 0, 0, 16)

	detailBody = text("Body", pane, 13, TEXT)
	detailBody.Position = UDim2.fromOffset(0, 52)
	detailBody.Size = UDim2.new(1, 0, 0, 126)
	detailBody.TextWrapped = true

	detailTravel = text("Travel", pane, 12, DIM)
	detailTravel.Position = UDim2.fromOffset(0, 186)
	detailTravel.Size = UDim2.new(1, 0, 0, 90)
	detailTravel.TextWrapped = true

	confirmButton = button("Confirm", pane, "BEGIN")
	confirmButton.Position = UDim2.new(0, 0, 1, -58)
	confirmButton.Size = UDim2.new(1, 0, 0, 40)
	confirmButton.TextSize = 14
	confirmButton.BackgroundColor3 = ACCENT
	confirmButton.TextColor3 = Color3.new(0, 0, 0)
end

--[[
	The page that replaces the question once it has been answered.

	WHY IT IS HERE AND NOT A TOAST
	The choice used to be acknowledged by a four-second `Notify`: a line of text
	in the corner of a screen the player was, at that exact moment, seeing for
	the first time. From the 2026-08-17 playtest: "I still don't know what's
	going on, who I am." Four seconds is not a briefing.

	WHY IT LIVES IN THIS ScreenGui
	It reuses the picker's scrim and DisplayOrder rather than being its own
	panel, and `open` stays true until its button is pressed. A Frame does not
	swallow mouse input on its own -- `Panels.anyOpen()` is what stops
	`InputController` firing a weapon through a panel -- so a card drawn while
	the game considers everything closed would be a card the player shoots past.

	Nothing here is stored. The card is the same profile fields the Journal's
	"Who you are" page draws from, which is the point: it is the first page of
	something the player can go back to, not a thing they had one chance to read.
]]
local function buildCard()
	cardRoot = Instance.new("Frame")
	cardRoot.Name = "Card"
	cardRoot.AnchorPoint = Vector2.new(0.5, 0.5)
	cardRoot.Position = UDim2.fromScale(0.5, 0.5)
	cardRoot.Size = UDim2.fromOffset(560, 420)
	cardRoot.BackgroundColor3 = PANEL
	cardRoot.BackgroundTransparency = 0.06
	cardRoot.BorderSizePixel = 0
	cardRoot.Visible = false
	cardRoot.Parent = screen
	corner(cardRoot, 8)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 26)
	padding.PaddingLeft = UDim.new(0, 28)
	padding.PaddingRight = UDim.new(0, 28)
	padding.Parent = cardRoot

	cardTitle = text("Title", cardRoot, 24, ACCENT)
	cardTitle.Font = Enum.Font.GothamBold
	cardTitle.Size = UDim2.new(1, 0, 0, 30)

	cardWhere = text("Where", cardRoot, 13, DIM)
	cardWhere.Position = UDim2.fromOffset(0, 34)
	cardWhere.Size = UDim2.new(1, 0, 0, 18)

	cardBody = text("Body", cardRoot, 14, TEXT)
	cardBody.Position = UDim2.fromOffset(0, 66)
	cardBody.Size = UDim2.new(1, 0, 0, 196)
	cardBody.TextWrapped = true

	cardNext = text("Next", cardRoot, 13, DIM)
	cardNext.Position = UDim2.fromOffset(0, 270)
	cardNext.Size = UDim2.new(1, 0, 0, 66)
	cardNext.TextWrapped = true

	local go = button("Go", cardRoot, "GO")
	go.Position = UDim2.new(0, 0, 1, -74)
	go.Size = UDim2.new(1, 0, 0, 42)
	go.TextSize = 14
	go.BackgroundColor3 = ACCENT
	go.TextColor3 = Color3.new(0, 0, 0)
	go.Activated:Connect(function()
		CreationController.setOpen(false)
	end)
end

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "CreationGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- Above the other panels rather than among them: this one cannot be
	-- dismissed, so anything that opens has to open behind it.
	screen.DisplayOrder = 20
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")

	--[[
		An opaque sheet over the whole viewport, behind the panel.

		The character is spawned and standing on a planet before this screen
		is answered -- it has to be, because the answer is what decides which
		planet to move them to. So the first thing a new player saw was
		Tatooine behind the question "who were you", which both spoils the
		Scoundrel's answer and makes the other three look wrong. Reported
		from the 2026-08-16 playtest.
	]]
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 0
	scrim.BorderSizePixel = 0
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.ZIndex = 0
	scrim.Parent = screen

	pickerRoot = Instance.new("Frame")
	local root = pickerRoot
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
	title.Text = "WHO WERE YOU"
	title.Position = UDim2.fromOffset(18, 16)
	title.Size = UDim2.fromOffset(400, 26)

	-- No close button, deliberately. There is nothing behind this yet.
	local subtitle = text("Subtitle", root, 13, DIM)
	subtitle.Position = UDim2.fromOffset(18, 40)
	subtitle.Size = UDim2.new(1, -36, 0, 18)
	subtitle.Text = "This decides where you wake up and who will fly you. It is not asked twice."

	listFrame = Instance.new("Frame")
	listFrame.Name = "List"
	listFrame.Position = UDim2.fromOffset(16, 96)
	listFrame.Size = UDim2.new(0, 344, 1, -112)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame

	for index, id in Origins.ids() do
		local origin = Origins.get(id)
		local row = button(id, listFrame, "")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -8, 0, 58)
		row.Text = ""
		row.BackgroundTransparency = 0.25

		local name = text("Name", row, 15, TEXT)
		name.Font = Enum.Font.GothamBold
		name.Position = UDim2.fromOffset(12, 10)
		name.Size = UDim2.new(1, -24, 0, 20)
		name.Text = origin.displayName

		local tag = text("Tag", row, 12, DIM)
		tag.Position = UDim2.fromOffset(12, 30)
		tag.Size = UDim2.new(1, -24, 0, 16)
		tag.Text = `{origin.tree}  ·  {Planets.get(origin.homePlanet).displayName}`

		row.Activated:Connect(function()
			selected = id
			render()
		end)
	end

	buildDetailPane(root)
	buildCard()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

function render()
	local origin = Origins.get(selected)

	for _, child in listFrame:GetChildren() do
		if child:IsA("TextButton") then
			child.BackgroundColor3 = if child.Name == selected then ROW_SELECTED else ROW
		end
	end

	detailTitle.Text = origin.displayName
	detailFacts.Text =
		`{Planets.get(origin.homePlanet).displayName}  ·  {Factions.get(origin.faction).displayName}  ·  {origin.tree}`
	detailBody.Text = origin.blurb
	detailTravel.Text = origin.travelBlurb
	confirmButton.Text = `BEGIN AS {string.upper(origin.displayName)}`
end

--[[
	The letter that opens `panel`, read from the registry rather than typed.

	Telling someone to press the wrong key is worse than telling them nothing,
	and a card that spelled the letters out itself would keep saying M after a
	rebind with nothing to catch it. "?" for a panel with no key never appears:
	both named below have one.
]]
local function keyOf(panel: string): string
	local key = Panels.toggleKey(panel)
	return if key then key.Name else "?"
end

local function showCard()
	local origin = Origins.get(selected)
	local missions = keyOf("MissionBoardController")
	local journal = keyOf("JournalController")

	cardTitle.Text = origin.displayName
	cardWhere.Text =
		`{Planets.get(origin.homePlanet).displayName}  ·  {Factions.get(origin.faction).displayName}  ·  {origin.tree}`
	-- The mentor is named because they are the one person in the galaxy who
	-- currently knows this character exists, and "go and find someone" is a
	-- worse first instruction than "go and find Vashk".
	cardBody.Text = `{origin.blurb}\n\n{origin.mentor} is expecting you.`
	cardNext.Text = `Press {missions} for work that needs doing, and {journal} for who you are and what you have`
		.. ` learned so far. All of this is on the journal's first page -- you are not meant to remember it.`

	pickerRoot.Visible = false
	cardRoot.Visible = true
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Whether the panel is showing. Read by InputController through Panels.
function CreationController.isOpen(): boolean
	return open
end

function CreationController.setOpen(value: boolean)
	--[[
		The refusal is the modality.

		`Panels.closeAllExcept` is called by every panel as it opens, so
		without this, pressing M would dismiss a question the profile still
		has no answer to and the screen would never come back this session.
	]]
	if not value and not chosen then
		return
	end
	if open == value then
		return
	end
	open = value
	screen.Enabled = value
	if value then
		Panels.closeAllExcept(CreationController.name)
		pickerRoot.Visible = true
		cardRoot.Visible = false
		render()
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CreationController.init()
	build()
end

function CreationController.start()
	confirmButton.Activated:Connect(function()
		--[[
			Deliberately not disabled while the reply is in flight.

			A refusal comes back as a toast, not as a profile, so a button
			disabled on send and re-enabled on the reply would stay dead
			forever on the one path where the player needs to press it again.
			Pressing twice is harmless: the server refuses a second choice on
			`originChosen`, and `chosen` stops it here once the answer lands.
		]]
		if chosen then
			return
		end
		Net.fireServer(Net.Event.ChooseOrigin, selected)
	end)

	local state = ServiceLoader.get("ClientState")

	--[[
		The card is shown on the transition, not on the state.

		On a rejoin the very first profile that arrives already has
		`originChosen` set and `chosen` still starts false, so reading the flag
		alone would replay the briefing at every login -- an introduction to a
		character the player has been playing for a week. `sawFirstProfile` is
		what separates "this just happened" from "this happened once, before".
	]]
	local sawFirstProfile = false

	local function sync(profile: any)
		local first = not sawFirstProfile
		sawFirstProfile = true

		if not profile.originChosen then
			CreationController.setOpen(true)
			return
		end

		local justChose = not chosen and not first
		chosen = true
		selected = profile.origin

		if justChose then
			-- Deliberately still open. `open` is what makes the screen take
			-- input focus, and a card the player can shoot past is a card they
			-- will shoot past.
			showCard()
		else
			CreationController.setOpen(false)
		end
	end

	state.changed:connect(sync)

	-- The profile may already have arrived: ClientState loads at priority 1
	-- and this is 45.
	local existing = state.get()
	if existing then
		sync(existing)
	end
end

return CreationController
