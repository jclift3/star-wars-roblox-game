--!strict
--[[
	InventoryController.luau

	The wardrobe and the shop counter, in one panel. Opens with B.

	ONE PANEL, TWO MODES
	Away from a vendor this is an inventory: everything you own, and a button to
	wear or equip it. Standing next to a trader the same list grows their stock
	and the buttons start offering to sell. Building these as two screens would
	have meant two layouts, two refresh paths and two places for the "can I
	actually use this" logic to drift apart.

	THE SERVER OWNS THE ANSWER
	Every price, ownership flag and level check shown here came from
	ShopService, and pressing Buy sends nothing but a kind and an id. This
	panel can be lied to and it still cannot lie back -- the worst a tampered
	client achieves is a wrong number on its own screen.

	Like the HUD, built entirely in code. See the note at the top of
	HudController for why.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Affixes = require(Shared.Config.Affixes)
local Palette = require(Shared.Config.Palette)
local Panels = require(Shared.Core.Panels)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local InventoryController = {
	name = "InventoryController",
	priority = 45,
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

local TOGGLE_KEY = Panels.toggleKey("InventoryController")

type StatLine = { label: string, value: string }

--[[
	Mirrors `ShopService.ItemEntry`.

	A row is one *stack*, so `uid` and not `id` is what identifies it: two rolls
	of the same blaster are two rows, and picking the wrong key would select
	both and equip whichever the server saw first. `id` is still what a
	purchase names, because you buy a catalogue entry, not somebody's stack.
]]
type ItemEntry = {
	kind: string,
	uid: string,
	id: string,
	displayName: string,
	description: string,
	tier: number,
	requiredLevel: number,
	price: number,
	owned: boolean,
	equipped: boolean,
	forSale: boolean,
	rarity: number,
	affixes: { string },
	stats: { StatLine },
	carried: boolean,
	sellValue: number,
}

type Snapshot = {
	credits: number,
	level: number,
	equippedOutfit: string?,
	equippedWeapon: string?,
	vendor: { shopId: string, displayName: string, greeting: string, vendorName: string }?,
	rolled: number,
	maxRolled: number,
	items: { ItemEntry },
}

local screen: ScreenGui
local root: Frame
local titleLabel: TextLabel
local creditsLabel: TextLabel
local vendorLabel: TextLabel
local listFrame: ScrollingFrame
local detailTitle: TextLabel
local detailBody: TextLabel
local detailStats: TextLabel
local actionButton: TextButton
local disposeButton: TextButton
local tabButtons: { [string]: TextButton } = {}

local open = false
local activeTab = "Outfit"
local selected: { [string]: string? } = { Outfit = nil, Weapon = nil }
local snapshot: Snapshot? = nil

--[[
	The uid whose DISCARD has been pressed once.

	Throwing away a Legendary is the only unrecoverable thing this panel can
	do, and it sits directly under a button people press repeatedly. Asking
	twice is the whole safeguard -- cleared whenever the selection moves, so
	the second press is always about the item the first one was.
]]
local confirmingDiscard: string? = nil

-- Guards against two refreshes racing. `invokeServer` yields, so a fast
-- sequence of buys can return replies out of order and paint a stale list.
local refreshToken = 0

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
	detailBody.Size = UDim2.new(1, 0, 0, 80)
	detailBody.TextWrapped = true

	detailStats = text("Stats", pane, 14, TEXT)
	detailStats.Position = UDim2.fromOffset(0, 116)
	detailStats.Size = UDim2.new(1, 0, 0, 90)

	actionButton = button("Action", pane, "")
	actionButton.Position = UDim2.new(0, 0, 1, -104)
	actionButton.Size = UDim2.new(1, 0, 0, 40)
	actionButton.TextSize = 14

	-- Below the action, and deliberately plainer: equipping is what you came
	-- here to do, getting rid of something is what you do when the bag is full.
	disposeButton = button("Dispose", pane, "")
	disposeButton.Position = UDim2.new(0, 0, 1, -58)
	disposeButton.Size = UDim2.new(1, 0, 0, 40)
	disposeButton.TextSize = 13
end

local function buildTabs(parent: Frame)
	local kinds = { { id = "Outfit", label = "OUTFITS" }, { id = "Weapon", label = "WEAPONS" } }
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
	screen.Name = "InventoryGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- Above the HUD, which is what a modal panel should be.
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

	titleLabel = text("Title", root, 20, TEXT)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "INVENTORY"
	titleLabel.Position = UDim2.fromOffset(18, 16)
	titleLabel.Size = UDim2.fromOffset(360, 26)

	creditsLabel = text("Credits", root, 16, ACCENT)
	creditsLabel.Font = Enum.Font.GothamBold
	creditsLabel.TextXAlignment = Enum.TextXAlignment.Right
	creditsLabel.AnchorPoint = Vector2.new(1, 0)
	creditsLabel.Position = UDim2.new(1, -52, 0, 18)
	creditsLabel.Size = UDim2.fromOffset(220, 24)

	vendorLabel = text("Vendor", root, 13, DIM)
	vendorLabel.Position = UDim2.fromOffset(18, 40)
	vendorLabel.Size = UDim2.new(1, -70, 0, 18)

	local close = button("Close", root, "X")
	close.Position = UDim2.new(1, -42, 0, 16)
	close.Size = UDim2.fromOffset(28, 28)
	close.Activated:Connect(function()
		InventoryController.setOpen(false)
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
-- Rendering
--------------------------------------------------------------------------------

local function entriesFor(kind: string): { ItemEntry }
	local snap = snapshot
	if not snap then
		return {}
	end
	local out: { ItemEntry } = {}
	for _, item in snap.items do
		if item.kind == kind then
			table.insert(out, item)
		end
	end
	return out
end

local function selectedEntry(): ItemEntry?
	local uid = selected[activeTab]
	if not uid then
		return nil
	end
	for _, item in entriesFor(activeTab) do
		if item.uid == uid then
			return item
		end
	end
	return nil
end

local render: () -> ()

local function renderDetail()
	local snap = snapshot
	local item = selectedEntry()

	if not item or not snap then
		detailTitle.Text = "Nothing selected"
		detailBody.Text = ""
		detailStats.Text = ""
		actionButton.Visible = false
		disposeButton.Visible = false
		return
	end

	local rarity = Affixes.rarityAt(item.rarity)
	detailTitle.Text = item.displayName
	-- Coloured by rarity rather than the panel accent, because the colour is
	-- the fastest read in the whole panel: orange means stop and look.
	detailTitle.TextColor3 = if item.rarity > 0 then rarity.color else ACCENT
	detailBody.Text = item.description

	local lines: { string } = {}
	for _, stat in item.stats do
		table.insert(lines, `{stat.label}:  {stat.value}`)
	end
	if #item.affixes > 0 then
		-- Separated from the base stats: what the item *is* above the line,
		-- what this particular one rolled below it.
		table.insert(lines, "")
		for _, line in item.affixes do
			table.insert(lines, line)
		end
	end
	if item.requiredLevel > 1 then
		table.insert(lines, "")
		table.insert(lines, `Requires level {item.requiredLevel}`)
	end
	detailStats.Text = table.concat(lines, "\n")

	actionButton.Visible = true

	local underLevelled = snap.level < item.requiredLevel

	if item.equipped then
		actionButton.Text = "EQUIPPED"
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = DIM
		actionButton.Active = false
	elseif item.owned then
		actionButton.Text = if item.kind == "Outfit" then "WEAR" else "EQUIP"
		actionButton.BackgroundColor3 = ACCENT
		actionButton.TextColor3 = Color3.new(0, 0, 0)
		actionButton.Active = true
	elseif not item.forSale then
		-- Owned-by-nobody and not stocked: this is a shop entry the player is
		-- seeing because they walked away from the vendor mid-browse.
		actionButton.Text = "NOT SOLD HERE"
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = DIM
		actionButton.Active = false
	elseif underLevelled then
		actionButton.Text = `NEEDS LEVEL {item.requiredLevel}`
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = BAD
		actionButton.Active = false
	elseif snap.credits < item.price then
		actionButton.Text = `{item.price} CR — NOT ENOUGH`
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = BAD
		actionButton.Active = false
	else
		actionButton.Text = `BUY — {item.price} CR`
		actionButton.BackgroundColor3 = GOOD
		actionButton.TextColor3 = Color3.new(0, 0, 0)
		actionButton.Active = true
	end

	--[[
		Only things really in the bag can leave it, and not while worn.

		Hidden rather than greyed out in those cases: shop stock and the
		starting outfit are never going to become sellable by waiting, and a
		permanently dead button is just clutter. An equipped item does show a
		disabled button, because that one the player can act on.
	]]
	if not item.carried then
		disposeButton.Visible = false
	elseif item.equipped then
		disposeButton.Visible = true
		disposeButton.Text = "UNEQUIP TO SELL OR DISCARD"
		disposeButton.BackgroundColor3 = ROW
		disposeButton.TextColor3 = DIM
		disposeButton.Active = false
	elseif item.sellValue > 0 then
		-- One button, and the vendor decides which action it is: standing at
		-- a counter there is never a reason to throw away something that can
		-- be sold, and out in the field there is never a vendor to sell to.
		disposeButton.Visible = true
		disposeButton.Text = `SELL — {item.sellValue} CR`
		disposeButton.BackgroundColor3 = ROW
		disposeButton.TextColor3 = GOOD
		disposeButton.Active = true
	else
		disposeButton.Visible = true
		disposeButton.Text = if confirmingDiscard == item.uid then "DISCARD — PRESS AGAIN" else "DISCARD"
		disposeButton.BackgroundColor3 = ROW
		disposeButton.TextColor3 = BAD
		disposeButton.Active = true
	end
end

local function renderHeader(label: string, order: number, colour: Color3)
	local h = text(`Header{order}`, listFrame, 11, colour)
	h.Font = Enum.Font.GothamBold
	h.LayoutOrder = order
	h.Size = UDim2.new(1, -8, 0, 22)
	h.TextYAlignment = Enum.TextYAlignment.Bottom
	h.Text = label
end

local function renderRow(item: ItemEntry, order: number)
	local row = button(item.uid, listFrame, "")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -8, 0, 46)
	row.Text = ""
	row.BackgroundColor3 = if selected[activeTab] == item.uid then ROW_SELECTED else ROW
	row.BackgroundTransparency = 0.25

	local name = text("Name", row, 14, TEXT)
	name.Font = Enum.Font.GothamBold
	name.Position = UDim2.fromOffset(12, 7)
	name.Size = UDim2.new(1, -120, 0, 18)

	local tag = text("Tag", row, 12, DIM)
	tag.Position = UDim2.fromOffset(12, 25)
	tag.Size = UDim2.new(1, -120, 0, 16)

	local price = text("Price", row, 13, DIM)
	price.TextXAlignment = Enum.TextXAlignment.Right
	price.AnchorPoint = Vector2.new(1, 0)
	price.Position = UDim2.new(1, -12, 0, 14)
	price.Size = UDim2.fromOffset(104, 18)

	local rarity = Affixes.rarityAt(item.rarity)
	name.Text = item.displayName
	if item.rarity > 0 then
		name.TextColor3 = rarity.color
		tag.Text = `Tier {item.tier}  ·  {rarity.name}`
	else
		tag.Text = `Tier {item.tier}`
	end

	if item.equipped then
		price.Text = "EQUIPPED"
		price.TextColor3 = ACCENT
	elseif item.owned then
		price.Text = "OWNED"
		price.TextColor3 = GOOD
	elseif item.forSale then
		price.Text = `{item.price} cr`
		price.TextColor3 = TEXT
	else
		price.Text = "—"
		price.TextColor3 = DIM
	end

	row.Activated:Connect(function()
		selected[activeTab] = item.uid
		-- Moving the selection cancels a half-pressed discard, so the
		-- confirm can never be inherited by a different item.
		confirmingDiscard = nil
		render()
	end)
end

--[[
	YOUR THINGS ABOVE THEIR THINGS

	Reported from play, 2026-08-17: *"I should have an inventory screen where I
	can see and equip my items."* The player was looking at one. Standing at a
	vendor, though, the panel had every catalogue entry the shop stocked mixed
	in with the four things actually in the bag, sorted by nothing in
	particular, so an inventory read as a price list -- and the fact that the
	rows the player owned had an EQUIP button behind them was invisible.

	`ItemEntry.carried` has always been on the wire and has always been the
	honest answer to "is this mine", so nothing new is needed to split them.
	Headers only appear when there is something to distinguish: away from a
	vendor every row is carried, and labelling a list of four things CARRIED
	when there is nothing else it could be is noise.
]]
local function renderList()
	for _, child in listFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local mine: { ItemEntry } = {}
	local theirs: { ItemEntry } = {}
	for _, item in entriesFor(activeTab) do
		table.insert(if item.carried then mine else theirs, item)
	end

	local order = 0

	if #theirs > 0 then
		order += 1
		renderHeader("CARRIED", order, ACCENT)
	end

	for _, item in mine do
		order += 1
		renderRow(item, order)
	end

	if #mine == 0 then
		order += 1
		local empty = text("Empty", listFrame, 13, DIM)
		empty.LayoutOrder = order
		empty.Size = UDim2.new(1, -8, 0, 40)
		empty.Text = if activeTab == "Outfit"
			then "You are carrying no outfits. Find a trader to buy some."
			else "You are carrying no weapons. Find a trader to buy some."
	end

	if #theirs > 0 then
		local snap = snapshot
		local vendor = if snap then snap.vendor else nil
		order += 1
		-- Named, because the difference between "mine" and "his" is the whole
		-- point of the split and a generic FOR SALE does not say whose.
		renderHeader(
			if vendor then `{string.upper(vendor.vendorName)} SELLS` else "NOT SOLD HERE",
			order,
			DIM
		)
		for _, item in theirs do
			order += 1
			renderRow(item, order)
		end
	end
end

function render()
	local snap = snapshot

	creditsLabel.Text = if snap then `{snap.credits} cr` else "—"

	-- Counts rolled items only, which is what the cap counts. Shown at all
	-- times rather than only when full, so the first time a drop is refused
	-- is not the first time the player hears there is a limit.
	if snap then
		titleLabel.Text = `INVENTORY   {snap.rolled}/{snap.maxRolled}`
		titleLabel.TextColor3 = if snap.rolled >= snap.maxRolled then BAD else TEXT
	else
		titleLabel.Text = "INVENTORY"
		titleLabel.TextColor3 = TEXT
	end

	if snap and snap.vendor then
		vendorLabel.Text = `{snap.vendor.displayName} — "{snap.vendor.greeting}"`
		vendorLabel.TextColor3 = ACCENT
	else
		vendorLabel.Text = "Not near a vendor. Find a trader to buy or sell."
		vendorLabel.TextColor3 = DIM
	end

	for kind, b in tabButtons do
		local active = kind == activeTab
		b.BackgroundColor3 = if active then ACCENT else ROW
		b.TextColor3 = if active then Color3.new(0, 0, 0) else DIM
	end

	-- Default the selection so the detail pane is never blank on open. Tested
	-- by resolving it rather than by its presence, which also catches a
	-- selection that has just gone away: selling or discarding deletes the
	-- very row the player was looking at.
	if not selectedEntry() then
		selected[activeTab] = nil
		local items = entriesFor(activeTab)
		-- Something carried, if there is one: the panel opens showing the
		-- player their own gear, not the first thing the shopkeeper happens to
		-- stock. Falls back to the top of the list so it is still never blank.
		for _, item in items do
			if item.carried then
				selected[activeTab] = item.uid
				break
			end
		end
		if not selected[activeTab] and #items > 0 then
			selected[activeTab] = items[1].uid
		end
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

	local result = Net.invokeServer(Net.Function.GetInventory) :: Snapshot?
	-- A newer request landed while this one was in flight, or the panel closed.
	if token ~= refreshToken then
		return
	end
	snapshot = result
	render()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Whether the panel is showing. Read by InputController so browsing a shop
--- does not also empty a magazine into the shopkeeper.
function InventoryController.isOpen(): boolean
	return open
end

function InventoryController.setOpen(value: boolean)
	if open == value then
		return
	end
	open = value
	screen.Enabled = value
	confirmingDiscard = nil
	if value then
		-- See the matching note in MissionBoardController.setOpen.
		Panels.closeAllExcept(InventoryController.name)
		task.spawn(refresh)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function InventoryController.init()
	build()
end

function InventoryController.start()
	actionButton.Activated:Connect(function()
		local item = selectedEntry()
		if not item or not actionButton.Active then
			return
		end
		if item.equipped then
			return
		elseif item.owned then
			-- Equipping names the stack, buying names the catalogue entry.
			if item.kind == "Outfit" then
				Net.fireServer(Net.Event.EquipOutfit, item.uid)
			else
				Net.fireServer(Net.Event.EquipWeapon, item.uid)
			end
		else
			Net.fireServer(Net.Event.PurchaseItem, item.kind, item.id)
		end
	end)

	disposeButton.Activated:Connect(function()
		local item = selectedEntry()
		if not item or not disposeButton.Active or not item.carried or item.equipped then
			return
		end
		if item.sellValue > 0 then
			Net.fireServer(Net.Event.SellItem, item.uid)
			return
		end
		if confirmingDiscard ~= item.uid then
			confirmingDiscard = item.uid
			renderDetail()
			return
		end
		confirmingDiscard = nil
		Net.fireServer(Net.Event.DiscardItem, item.uid)
	end)

	for kind, b in tabButtons do
		b.Activated:Connect(function()
			activeTab = kind
			confirmingDiscard = nil
			render()
		end)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			InventoryController.setOpen(not open)
		elseif input.KeyCode == Enum.KeyCode.Escape and open then
			InventoryController.setOpen(false)
		end
	end)

	-- Buying and equipping both land as profile changes. Re-asking the server
	-- rather than patching the local snapshot means the panel shows the same
	-- thing a fresh open would, including the credits the purchase actually
	-- cost rather than the price this client predicted.
	ServiceLoader.get("ClientState").changed:connect(function()
		if open then
			task.spawn(refresh)
		end
	end)
end

return InventoryController
