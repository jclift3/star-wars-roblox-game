--!strict
--[[
	DialogueController.luau

	The conversation panel. Opens when you talk to somebody, not on a key.

	NOT A FULL-SCREEN PANEL
	The inventory, the board and the skill tree all own the whole screen,
	because reading them is the activity. A conversation is not: you are still
	standing in front of a person, in a place, and the panel should let you see
	both. So this sits across the bottom third and leaves the world visible.

	It still takes input focus -- InputController checks `isOpen` before firing
	a weapon, and picking a reply should not also empty a magazine into the
	person you are picking it from.

	THE CLIENT KNOWS NOTHING
	It renders the text the server sent and answers with the index of the button
	that was pressed. It does not know the node graph, cannot navigate it, and
	holds no state between nodes beyond what is on screen. Everything about who
	said what and which replies were allowed lives in DialogueService.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local Theme = require(script.Parent.Parent.UI.Theme)

local DialogueController = {
	name = "DialogueController",
	priority = 48,
}

local player = Players.LocalPlayer

local PANEL = Theme.PANEL
local ROW = Theme.ROW
local ACCENT = Theme.ACCENT
local TEXT = Theme.TEXT
local DIM = Theme.DIM

local WIDTH = 760
local HEIGHT = 250
local CHOICE_HEIGHT = 30

local ONE_KEY = Enum.KeyCode.One.Value

--[[
	The longest question the box will take.

	The server and the edge function both enforce the same number. This copy
	is the courteous one -- it stops a sentence at the point it would have been
	rejected instead of letting somebody type a paragraph and lose it.
]]
local MAX_SAID = 300

--[[
	Required, throughout the interaction, by Roblox's policy on generative AI.

	Not a nicety and not a one-time toast: it is on screen for every frame the
	box is, and it is drawn *only* in ask mode. A notice shown above an
	authored `Dialogue.luau` tree would be false, and a notice shown
	everywhere is a notice nobody reads.
]]
local AI_NOTICE = "AI-generated conversation, not a real person. It may make mistakes."

--- A node as the server describes it. Choices are answered by index.
type Payload = {
	speaker: string,
	title: string,
	text: string,
	choices: { { text: string, kind: string? } },
	-- Free-form. Draws the box and the notice; see AI_NOTICE.
	ask: boolean?,
}

local screen: ScreenGui
local root: Frame
local speakerLabel: TextLabel
local titleLabel: TextLabel
local bodyLabel: TextLabel
local choiceFrame: Frame
local askNote: TextLabel
local askBox: TextBox

local open = false
-- How many replies are on screen, so the number keys cannot select a button
-- that is not there.
local choiceCount = 0
-- Whether the box is up, so the number keys stay out of the way of typing.
local asking = false

-- How much of the panel the box and its notice take when they are shown.
local ASK_HEIGHT = 58

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local corner = Theme.corner

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "Dialogue"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")

	root = Instance.new("Frame")
	root.Name = "Panel"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -28)
	root.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	root.BackgroundColor3 = PANEL
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Parent = screen
	corner(root, 8)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.Parent = root

	speakerLabel = Instance.new("TextLabel")
	speakerLabel.Name = "Speaker"
	speakerLabel.BackgroundTransparency = 1
	speakerLabel.Font = Enum.Font.GothamBold
	speakerLabel.TextSize = 18
	speakerLabel.TextColor3 = ACCENT
	speakerLabel.TextXAlignment = Enum.TextXAlignment.Left
	speakerLabel.Size = UDim2.new(1, 0, 0, 22)
	speakerLabel.Text = ""
	speakerLabel.Parent = root

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.Gotham
	titleLabel.TextSize = 12
	titleLabel.TextColor3 = DIM
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Position = UDim2.fromOffset(0, 23)
	titleLabel.Size = UDim2.new(1, 0, 0, 15)
	titleLabel.Text = ""
	titleLabel.Parent = root

	bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Font = Enum.Font.Gotham
	bodyLabel.TextSize = 15
	bodyLabel.TextColor3 = TEXT
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.TextWrapped = true
	bodyLabel.Position = UDim2.fromOffset(0, 48)
	bodyLabel.Size = UDim2.new(1, 0, 0, 58)
	bodyLabel.Text = ""
	bodyLabel.Parent = root

	choiceFrame = Instance.new("Frame")
	choiceFrame.Name = "Choices"
	choiceFrame.BackgroundTransparency = 1
	choiceFrame.Position = UDim2.fromOffset(0, 112)
	choiceFrame.Size = UDim2.new(1, 0, 1, -112)
	choiceFrame.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = choiceFrame

	askNote = Instance.new("TextLabel")
	askNote.Name = "AiNotice"
	askNote.BackgroundTransparency = 1
	askNote.Font = Enum.Font.Gotham
	askNote.TextSize = 11
	askNote.TextColor3 = DIM
	askNote.TextXAlignment = Enum.TextXAlignment.Left
	askNote.AnchorPoint = Vector2.new(0, 1)
	askNote.Position = UDim2.new(0, 0, 1, -38)
	askNote.Size = UDim2.new(1, 0, 0, 14)
	askNote.Text = AI_NOTICE
	askNote.Visible = false
	askNote.Parent = root

	askBox = Instance.new("TextBox")
	askBox.Name = "Ask"
	askBox.AnchorPoint = Vector2.new(0, 1)
	askBox.Position = UDim2.new(0, 0, 1, 0)
	askBox.Size = UDim2.new(1, 0, 0, 34)
	askBox.BackgroundColor3 = ROW
	askBox.BackgroundTransparency = 0.1
	askBox.BorderSizePixel = 0
	askBox.Font = Enum.Font.Gotham
	askBox.TextSize = 14
	askBox.TextColor3 = TEXT
	askBox.PlaceholderText = "  Say something, then press Enter"
	askBox.PlaceholderColor3 = DIM
	askBox.TextXAlignment = Enum.TextXAlignment.Left
	askBox.ClearTextOnFocus = false
	askBox.Text = ""
	askBox.Visible = false
	askBox.Parent = root
	corner(askBox, 4)

	local boxPadding = Instance.new("UIPadding")
	boxPadding.PaddingLeft = UDim.new(0, 10)
	boxPadding.PaddingRight = UDim.new(0, 10)
	boxPadding.Parent = askBox
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function clearChoices()
	choiceCount = 0
	for _, child in choiceFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

--[[
	Takes the box away and gives the keyboard back.

	`ReleaseFocus` matters more than the two Visible flags: a hidden TextBox
	that still holds focus eats every keypress, so the player would walk away
	from the conversation and find that W no longer moved them.
]]
local function hideAsk()
	asking = false
	askNote.Visible = false
	askBox.Visible = false
	askBox.Text = ""
	askBox:ReleaseFocus(false)
end

--- Sends a reply. Shared by the buttons and the number keys.
local function choose(index: number)
	if index >= 1 and index <= choiceCount then
		Net.fireServer(Net.Event.DialogueChoice, index)
	end
end

--[[
	Draws one reply.

	`kind` is the action the server attached, used only for colour: taking a
	mission and walking into a shop are the two replies with consequences, and
	they should not look like "tell me about the weather".
]]
local function addChoice(index: number, entry: { text: string, kind: string? })
	local b = Instance.new("TextButton")
	b.Name = `Choice{index}`
	b.LayoutOrder = index
	b.AutoButtonColor = true
	b.BackgroundColor3 = ROW
	b.BackgroundTransparency = 0.2
	b.BorderSizePixel = 0
	b.Size = UDim2.new(1, 0, 0, CHOICE_HEIGHT)
	b.Font = Enum.Font.Gotham
	b.TextSize = 14
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextColor3 = if entry.kind == "Accept" or entry.kind == "Shop" then ACCENT else TEXT
	-- Numbered so the list reads as a menu rather than as a stack of buttons.
	b.Text = `  {index}.  {entry.text}`
	b.Parent = choiceFrame
	corner(b, 4)

	b.Activated:Connect(function()
		choose(index)
	end)
end

local function render(payload: Payload)
	speakerLabel.Text = payload.speaker
	titleLabel.Text = payload.title
	bodyLabel.Text = payload.text

	clearChoices()
	for index, entry in payload.choices do
		addChoice(index, entry)
	end
	choiceCount = #payload.choices

	local wantsBox = payload.ask == true
	-- The replies give up the bottom of the panel rather than the panel
	-- growing: a box that appears by pushing the whole conversation upward
	-- moves the line the player is in the middle of reading.
	choiceFrame.Size = UDim2.new(1, 0, 1, if wantsBox then -112 - ASK_HEIGHT else -112)

	if not wantsBox then
		hideAsk()
		return
	end

	asking = true
	askNote.Visible = true
	askBox.Visible = true
	askBox.Text = ""
	-- Focused for them. The box only ever appears because they asked for it,
	-- so making them click it as well is a step with no decision in it.
	askBox:CaptureFocus()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Whether a conversation is on screen. Read by InputController.
function DialogueController.isOpen(): boolean
	return open
end

--[[
	Shows or hides the panel.

	Closing tells the server, because the session lives there: without this a
	player who walked away would still be "in" a conversation and their next
	proximity prompt would land on a stale one.
]]
function DialogueController.setOpen(value: boolean)
	if open == value then
		return
	end
	open = value
	screen.Enabled = value
	if not value then
		clearChoices()
		hideAsk()
		Net.fireServer(Net.Event.EndDialogue)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function DialogueController.init()
	build()

	--[[
		Cuts the question off where the server would have rejected it.

		Roblox has no maximum-length property on a TextBox, so this is the
		only place it can be done, and doing it as they type is much better
		than the alternative -- a player writing four hundred characters and
		being told afterwards that none of them arrived.
	]]
	askBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #askBox.Text > MAX_SAID then
			askBox.Text = string.sub(askBox.Text, 1, MAX_SAID)
		end
	end)

	--[[
		Enter sends. Losing focus any other way -- clicking off, pressing
		Escape -- leaves what was typed alone rather than firing it, because
		a half-written question sent by a stray click is a turn spent.
	]]
	askBox.FocusLost:Connect(function(enterPressed: boolean)
		if not enterPressed or not asking then
			return
		end
		local said = askBox.Text
		askBox.Text = ""
		if string.match(said, "%S") then
			Net.fireServer(Net.Event.DialogueSay, said)
		else
			askBox:CaptureFocus()
		end
	end)
end

function DialogueController.start()
	--[[
		Carries every node, not only the first. The client has no node graph to
		walk, so each step of a conversation arrives the same way the opening
		line did and is drawn by the same code.
	]]
	Net.onClientEvent(Net.Event.StartDialogue, function(payload: Payload)
		if not open then
			-- Starting a conversation clears the screen of everything else.
			Panels.closeAllExcept(DialogueController.name)
			open = true
			screen.Enabled = true
		end
		render(payload)
	end)

	Net.onClientEvent(Net.Event.EndDialogue, function(reason: string?)
		-- Set directly rather than through setOpen: the server already knows
		-- the session is over, and telling it again would be a wasted remote.
		open = false
		screen.Enabled = false
		clearChoices()
		hideAsk()

		-- "Let me see what you have" ends the conversation and opens the till.
		-- ShopService re-checks proximity when anything is actually bought, so
		-- the panel opening here grants nothing on its own.
		if reason == "Shop" then
			local inventory = ServiceLoader.find("InventoryController")
			if inventory then
				inventory.setOpen(true)
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not open then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			DialogueController.setOpen(false)
			return
		end
		--[[
			The replies are numbered on screen, so the numbers should work.

			By value rather than by name: the KeyCode for "1" is called `One`,
			so there is nothing to parse out of the name, but the values of
			Zero through Nine are their ASCII codes and are contiguous.
		]]
		local code = input.KeyCode.Value
		if code >= ONE_KEY and code <= ONE_KEY + 8 then
			choose(code - ONE_KEY + 1)
		end
	end)
end

return DialogueController
