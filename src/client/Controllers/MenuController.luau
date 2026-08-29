--!strict
--[[
	MenuController.luau

	One key that opens the game's five panels, and a strip of tabs to move
	between them once you are in.

	WHY THIS EXISTS
	Reported from play 2026-08-29, looking at the HUD: *"if it makes sense to
	have less hot keys that's ok too as long as people can easily navigate."*

	It made sense. The legend had grown to eleven entries, five of which were
	single letters -- B, M, J, K, G -- that a player has to memorise before
	the interface is usable at all. Worse, they are unrelated letters: there
	is no rule connecting J to the journal that also connects K to the skill
	tree, so knowing four of them does not help you guess the fifth. Every
	one of those five was added for the same good reason (a panel nobody can
	open is a panel that does not exist, 2026-08-17), and together they became
	the problem that fix was solving.

	So: **TAB opens the menu**, and once it is open the five panels are tabs
	along the top. That is one thing to learn instead of five, and it is the
	thing every game the boys already play does.

	THE LETTERS STILL WORK, THEY JUST STOP BEING THE ONLY WAY IN
	Nothing about the panels changes. Each controller still binds its own key
	through `Panels.toggleKey`, so a player who has learned B keeps it, and
	B from inside the star map still swaps to the inventory exactly as it did
	-- `setOpen` already calls `Panels.closeAllExcept`. What changes is that
	the letters leave the legend and move onto the tabs, where they are shown
	next to the panel they open. Learning them becomes a thing that happens to
	you while you use the menu rather than a thing you do first.

	WHY A STRIP OVER THE PANELS RATHER THAN A CONTAINER AROUND THEM
	The obvious build is a tabbed frame that owns the five panel bodies. That
	is a rewrite of five controllers, each of which builds its own `ScreenGui`
	at `DisplayOrder = 10` and positions its own 760x470 body, and there is no
	way to execute Luau offline to find out what broke.

	This is a sixth `ScreenGui` at `DisplayOrder = 11` that draws a row of
	buttons where a tab bar goes and calls the same `setOpen` the letter keys
	call. The panels do not know it exists. It reads their state through
	`Panels.ALL` on a heartbeat rather than being told, which costs five table
	lookups a frame and means it cannot fall out of sync with a panel opened
	some other way -- by a letter, by a vendor, by the star map opening itself
	when a ship strays.

	It stays *below* `CreationController` (20) on purpose. That one is modal
	and refuses to close until the character has an origin; a tab strip over
	it would be a row of buttons that appear not to work.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Panels = require(Shared.Core.Panels)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local Theme = require(script.Parent.Parent.UI.Theme)

local MenuController = {
	name = "MenuController",
	-- After the panels it drives, so `ServiceLoader.find` resolves on the
	-- first heartbeat rather than the second.
	priority = 55,
}

local player = Players.LocalPlayer

local PANEL = Theme.PANEL
local ROW = Theme.ROW
local ROW_SELECTED = Theme.ROW_SELECTED
local ACCENT = Theme.ACCENT
local TEXT = Theme.TEXT
local FAINT = Theme.FAINT

--- Half the panel body's height, so the strip can sit on its top edge. The
--- 760x470 size is documented in `Panels.luau` and shared by all five.
local PANEL_HALF_HEIGHT = 235
local TAB_HEIGHT = 30
local TAB_GAP = 8

local screen: ScreenGui
--- One button per keyed panel, in `Panels.ALL` order, keyed by controller name.
local tabs: { [string]: TextButton } = {}

--[[
	Which panel TAB opens when nothing is open.

	Remembered for the session and never saved. A player who was last in the
	star map is probably going back to the star map; a player who was last in
	the star map three days ago is not, and would rather have the default.
]]
local lastOpened: string? = nil

--[[
	The keyed panels, in declaration order, filtered once.

	The two without a key are opened by walking up to something, so they are
	not places you navigate to. Computed at require time rather than on
	demand because `sync` reads it every frame and `Panels.ALL` never
	changes -- a filter that allocates a table sixty times a second to
	produce the same five entries is the cheapest kind of waste to not do.
]]
local KEYED: { Panels.PanelDef } = (function()
	local out: { Panels.PanelDef } = {}
	for _, def in Panels.ALL do
		if def.toggle then
			table.insert(out, def)
		end
	end
	return out
end)()

--- The open panel's name, or nil. Only ever one, because `setOpen(true)`
--- closes the others.
local function currentlyOpen(): string?
	for _, def in KEYED do
		local panel = ServiceLoader.find(def.name)
		if panel and panel.isOpen() == true then
			return def.name
		end
	end
	return nil
end

local function show(name: string?)
	for _, def in KEYED do
		local panel = ServiceLoader.find(def.name)
		if panel then
			panel.setOpen(def.name == name)
		end
	end
	if name then
		lastOpened = name
	end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "MenuGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- One above the panels, so the strip sits on the body rather than under
	-- it; below the creation modal, which nothing may cover.
	screen.DisplayOrder = 11
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Tabs"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 0.5, -PANEL_HALF_HEIGHT - TAB_GAP)
	root.Size = UDim2.fromOffset(0, TAB_HEIGHT)
	root.AutomaticSize = Enum.AutomaticSize.X
	root.BackgroundColor3 = PANEL
	root.BackgroundTransparency = 0.06
	root.BorderSizePixel = 0
	root.Parent = screen
	Theme.corner(root, 6)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = root

	for order, def in KEYED do
		local toggle = def.toggle
		if not toggle then
			continue
		end

		local tab = Theme.button(def.name, root, "")
		tab.LayoutOrder = order
		tab.Size = UDim2.fromOffset(0, TAB_HEIGHT - 8)
		tab.AutomaticSize = Enum.AutomaticSize.X
		tab.AutoButtonColor = false

		local inner = Instance.new("UIPadding")
		inner.PaddingLeft = UDim.new(0, 10)
		inner.PaddingRight = UDim.new(0, 10)
		inner.Parent = tab

		local strip = Instance.new("UIListLayout")
		strip.FillDirection = Enum.FillDirection.Horizontal
		strip.SortOrder = Enum.SortOrder.LayoutOrder
		strip.VerticalAlignment = Enum.VerticalAlignment.Center
		strip.Padding = UDim.new(0, 6)
		strip.Parent = tab

		local label = Theme.text("Label", tab, 13, TEXT)
		label.Font = Theme.FONT_BOLD
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Size = UDim2.fromOffset(0, TAB_HEIGHT - 8)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.LayoutOrder = 1
		label.Text = toggle.hint

		-- The shortcut, shown on the thing it is a shortcut for. This is the
		-- whole of how a player learns the letters now that the legend has
		-- stopped listing them: it is next to the word it opens, at the
		-- moment they are looking at that word.
		local key = Theme.text("Key", tab, 11, FAINT)
		key.TextYAlignment = Enum.TextYAlignment.Center
		key.Size = UDim2.fromOffset(0, TAB_HEIGHT - 8)
		key.AutomaticSize = Enum.AutomaticSize.X
		key.LayoutOrder = 2
		key.Text = toggle.key.Name

		tab.Activated:Connect(function()
			show(def.name)
		end)

		tabs[def.name] = tab
	end
end

--------------------------------------------------------------------------------
-- Sync
--------------------------------------------------------------------------------

--[[
	Follows the panels rather than leading them.

	A letter key, a vendor, and the star map raising itself when a ship
	strays are all ways a panel opens without this controller hearing about
	it. Reading the state every frame is five table lookups and cannot drift;
	being told would need five signals that five controllers would have to
	remember to fire.
]]
local function sync()
	local open = currentlyOpen()
	screen.Enabled = open ~= nil
	if not open then
		return
	end
	for name, tab in tabs do
		local selected = name == open
		tab.BackgroundColor3 = if selected then ROW_SELECTED else ROW
		local label = tab:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.TextColor3 = if selected then ACCENT else TEXT
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MenuController.start()
	build()
	RunService.Heartbeat:Connect(sync)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.KeyCode ~= Panels.MENU_KEY then
			return
		end

		-- The creation modal owns the screen until an origin is chosen, and
		-- opening a panel behind it would put a menu the player cannot reach
		-- under a card they cannot dismiss.
		local creation = ServiceLoader.find("CreationController")
		if creation and creation.isOpen() == true then
			return
		end

		local open = currentlyOpen()
		if open then
			show(nil)
		else
			-- Whatever they were last in, or the first tab. Not a stored
			-- default constant: the order in `Panels.ALL` is the order of
			-- the strip, so "the first one" is a thing the player can see.
			local first = KEYED[1]
			show(lastOpened or (if first then first.name else nil))
		end
	end)
end

return MenuController
