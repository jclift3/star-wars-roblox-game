--!strict
--[[
	InventoryController.luau

	The wardrobe, the workbench and the shop counter, in one panel. Opens with B.

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

	WHY IT LOOKS LIKE THIS
	Reported 2026-08-19: *"we need better visuals, infographics, designs in
	these menus."* The old panel was a list of grey rows and a block of
	`label:  value` text, and it was unreadable for one specific reason -- every
	number in it was an absolute with nothing to measure against. "Damage 42"
	answers nothing; "42, and the bar is three-quarters full, and that is seven
	more than what you are holding" answers the only question the player has.
	So: a bar per stat, an arrow against the equipped item, rarity as pips as
	well as colour, and a real rotating model of the thing.

	The preview is a `ViewportFrame` containing the same `WeaponModel` /
	`ShipModel` / `RigBuilder` output the world uses, in its real colours,
	including the tint of whatever crystal is in its first socket. Not a
	rendered icon: this project has never referenced an image asset id, and a
	panel is the last place to start -- the geometry is already here and it is
	already correct.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Affixes = require(Shared.Config.Affixes)
local Costumes = require(Shared.Config.Costumes)
local Crystals = require(Shared.Config.Crystals)
local Furnishings = require(Shared.Config.Furnishings)
local Ships = require(Shared.Config.Ships)
local Weapons = require(Shared.Config.Weapons)
local Panels = require(Shared.Core.Panels)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local RigBuilder = require(Shared.Rig.RigBuilder)
local ShipModel = require(Shared.Rig.ShipModel)
local WeaponModel = require(Shared.Rig.WeaponModel)

local Theme = require(script.Parent.Parent.UI.Theme)

local InventoryController = {
	name = "InventoryController",
	priority = 45,
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
local BAD = Theme.BAD

local corner = Theme.corner
local text = Theme.text
local button = Theme.button

local TOGGLE_KEY = Panels.toggleKey("InventoryController")

--- A filled socket, and an empty one. See the note on `Theme.pips`.
local DOT_FULL = "⬤"
local DOT_EMPTY = "◯"

type StatLine = {
	label: string,
	value: string,
	raw: number?,
	max: number?,
}

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
	sockets: number,
	socketed: { [string]: string },
	slot: string,
	extractCosts: { [string]: number },
}

type Snapshot = {
	credits: number,
	level: number,
	equippedOutfit: string?,
	equippedWeapon: string?,
	equippedShip: string?,
	vendor: { shopId: string, displayName: string, greeting: string, vendorName: string }?,
	rolled: number,
	maxRolled: number,
	items: { ItemEntry },
}

--- The tabs, left to right. Order is the order the player thinks in: what you
--- wear, what you shoot with, what goes in them, what you fly, where you live.
local TABS = {
	{ id = "Outfit", label = "OUTFITS" },
	{ id = "Weapon", label = "WEAPONS" },
	{ id = "Crystal", label = "CRYSTALS" },
	{ id = "Vehicle", label = "SHIPS" },
	{ id = "Furnishing", label = "CABIN" },
}

local screen: ScreenGui
local root: Frame
local titleLabel: TextLabel
local creditsLabel: TextLabel
local vendorLabel: TextLabel
local listFrame: ScrollingFrame
local viewport: ViewportFrame
local viewportWorld: WorldModel
local viewportCamera: Camera
local detailTitle: TextLabel
local detailPips: TextLabel
local detailRarity: TextLabel
local detailBody: TextLabel
local detailScroll: ScrollingFrame
local actionButton: TextButton
local disposeButton: TextButton
local pickerFrame: Frame
local pickerList: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}

local open = false
local activeTab = "Outfit"
local selected: { [string]: string? } = {}
local snapshot: Snapshot? = nil

--- The model currently in the viewport, and how far round it has turned.
local preview: Model? = nil
local previewPivot = CFrame.identity
local previewDistance = 0
local previewAngle = 0

--- Which socket index the crystal picker is filling, or nil when it is shut.
local pickingSocket: number? = nil

--[[
	The uid whose DISCARD has been pressed once.

	Throwing away a Legendary is the only unrecoverable thing this panel can
	do, and it sits directly under a button people press repeatedly. Asking
	twice is the whole safeguard -- cleared whenever the selection moves, so
	the second press is always about the item the first one was.
]]
local confirmingDiscard: string? = nil

--[[
	The socket whose REMOVE has been pressed once.

	Same rule as the discard above, and for a stronger reason: extraction
	destroys the crystal *and* charges for the privilege, so a misclick costs
	twice. Keyed by index rather than by a boolean because two sockets sit a
	few pixels apart.
]]
local confirmingExtract: number? = nil

-- Guards against two refreshes racing. `invokeServer` yields, so a fast
-- sequence of buys can return replies out of order and paint a stale list.
local refreshToken = 0

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

--[[
	Sets up the viewport once. Only its contents change afterwards.

	`WorldModel` rather than parenting parts straight to the `ViewportFrame`:
	without one, a `Model` inside a viewport draws but has no world to be
	positioned in, and `GetBoundingBox` -- which is how the camera works out
	how far back to stand -- has nothing to measure.
]]
local function buildViewport(parent: Frame)
	viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundColor3 = PANEL
	viewport.BackgroundTransparency = 0.15
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.fromOffset(132, 132)
	viewport.Parent = parent
	corner(viewport, 5)
	Theme.stroke(viewport, ACCENT, 0.75)

	-- Light from the front-left, which is where the camera is. Without this
	-- every non-Neon part in the viewport renders as a flat silhouette.
	viewport.Ambient = Color3.fromRGB(120, 124, 134)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)

	viewportWorld = Instance.new("WorldModel")
	viewportWorld.Parent = viewport

	viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 32
	viewportCamera.Parent = viewport
	viewport.CurrentCamera = viewportCamera
end

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

	buildViewport(pane)

	detailTitle = text("Title", pane, 16, ACCENT)
	detailTitle.Font = Theme.FONT_BOLD
	detailTitle.Position = UDim2.fromOffset(144, 0)
	detailTitle.Size = UDim2.new(1, -144, 0, 38)
	detailTitle.TextWrapped = true

	detailPips = text("Pips", pane, 13, ACCENT)
	detailPips.Position = UDim2.fromOffset(144, 40)
	detailPips.Size = UDim2.new(1, -144, 0, 16)

	detailRarity = text("Rarity", pane, 11, DIM)
	detailRarity.Font = Theme.FONT_BOLD
	detailRarity.Position = UDim2.fromOffset(144, 58)
	detailRarity.Size = UDim2.new(1, -144, 0, 14)

	detailBody = text("Body", pane, 11, DIM)
	detailBody.Position = UDim2.fromOffset(144, 76)
	detailBody.Size = UDim2.new(1, -144, 0, 56)
	detailBody.TextWrapped = true

	--[[
		Everything below the header scrolls.

		A Legendary outfit is three stat bars, four affix lines, a level
		requirement and three sockets, and a Common blaster is three bars. One
		scrolling column with a list layout fits both without the pane having
		to guess a height, and without the socket row -- the one thing here
		that is clickable -- ever being pushed off the bottom edge.
	]]
	detailScroll = Instance.new("ScrollingFrame")
	detailScroll.Name = "Facts"
	detailScroll.Position = UDim2.fromOffset(0, 144)
	detailScroll.Size = UDim2.new(1, 0, 1, -252)
	detailScroll.BackgroundTransparency = 1
	detailScroll.BorderSizePixel = 0
	detailScroll.ScrollBarThickness = 3
	detailScroll.CanvasSize = UDim2.new()
	detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailScroll.Parent = pane

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = detailScroll

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

	--[[
		The crystal picker, over the detail pane rather than beside it.

		Choosing a stone is a modal question -- there is nothing else to do
		while it is up -- and a popup can be dismissed by clicking away, which
		a third column cannot.
	]]
	pickerFrame = Instance.new("Frame")
	pickerFrame.Name = "Picker"
	pickerFrame.BackgroundColor3 = PANEL
	pickerFrame.BorderSizePixel = 0
	pickerFrame.Position = UDim2.fromOffset(0, 0)
	pickerFrame.Size = UDim2.new(1, 0, 1, -14)
	pickerFrame.Visible = false
	pickerFrame.ZIndex = 5
	pickerFrame.Parent = pane
	corner(pickerFrame, 5)
	Theme.stroke(pickerFrame, ACCENT, 0.3)

	local pickerTitle = text("Title", pickerFrame, 13, ACCENT)
	pickerTitle.Font = Theme.FONT_BOLD
	pickerTitle.ZIndex = 6
	pickerTitle.Position = UDim2.fromOffset(12, 10)
	pickerTitle.Size = UDim2.new(1, -24, 0, 18)
	pickerTitle.Text = "FIT A CRYSTAL"

	pickerList = Instance.new("ScrollingFrame")
	pickerList.Name = "List"
	pickerList.Position = UDim2.fromOffset(12, 34)
	pickerList.Size = UDim2.new(1, -24, 1, -84)
	pickerList.BackgroundTransparency = 1
	pickerList.BorderSizePixel = 0
	pickerList.ScrollBarThickness = 3
	pickerList.CanvasSize = UDim2.new()
	pickerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pickerList.ZIndex = 6
	pickerList.Parent = pickerFrame

	local pickerLayout = Instance.new("UIListLayout")
	pickerLayout.Padding = UDim.new(0, 4)
	pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pickerLayout.Parent = pickerList

	local cancel = button("Cancel", pickerFrame, "CANCEL")
	cancel.ZIndex = 6
	cancel.Position = UDim2.new(0, 12, 1, -40)
	cancel.Size = UDim2.new(1, -24, 0, 30)
	cancel.TextColor3 = DIM
	cancel.Activated:Connect(function()
		pickingSocket = nil
		pickerFrame.Visible = false
	end)
end

local function buildTabs(parent: Frame)
	for index, tab in TABS do
		local b = button(tab.id, parent, tab.label)
		b.Position = UDim2.fromOffset(16 + (index - 1) * 96, 60)
		b.Size = UDim2.fromOffset(88, 28)
		b.TextSize = 12
		tabButtons[tab.id] = b
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
	-- A hairline of the game's own orange, so the panel reads as a lit object
	-- on the screen rather than a hole cut in it.
	Theme.stroke(root, ACCENT, 0.7)

	titleLabel = text("Title", root, 20, TEXT)
	titleLabel.Font = Theme.FONT_BOLD
	titleLabel.Text = "INVENTORY"
	titleLabel.Position = UDim2.fromOffset(18, 16)
	titleLabel.Size = UDim2.fromOffset(360, 26)

	creditsLabel = text("Credits", root, 16, ACCENT)
	creditsLabel.Font = Theme.FONT_BOLD
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
-- The preview
--------------------------------------------------------------------------------

--[[
	A loose crystal, as a shard of its own colour.

	The one thing in the panel with no model anywhere else in the game, because
	a crystal in the world is only ever a colour on somebody's blade. Two
	crossed Neon blocks and a light: enough to read as a gemstone at 132
	pixels, and still not an asset id.
]]
local function crystalModel(color: Color3): Model
	local model = Instance.new("Model")
	for i, spec in { Vector3.new(0.5, 1.8, 0.5), Vector3.new(1.1, 0.9, 1.1) } do
		local shard = Instance.new("Part")
		shard.Name = `Shard{i}`
		shard.Size = spec
		shard.Anchored = true
		shard.CanCollide = false
		shard.Material = Enum.Material.Neon
		shard.Color = color
		shard.Transparency = if i == 1 then 0 else 0.45
		shard.CFrame = CFrame.Angles(0, 0, math.rad(if i == 1 then 12 else -20))
		shard.Parent = model
	end
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Brightness = 4
	glow.Range = 8
	glow.Parent = model:FindFirstChild("Shard1")
	return model
end

--- The real geometry for a row, or nil for a kind that has none.
local function previewFor(item: ItemEntry): Model?
	if item.kind == "Weapon" and Weapons.exists(item.id) then
		-- Tinted, so the preview shows the crystal the player just fitted and
		-- not the blade colour the catalogue ships with.
		return WeaponModel.build(item.id, Crystals.tintOf(item.socketed))
	elseif item.kind == "Vehicle" and Ships.exists(item.id) then
		return ShipModel.build(item.id)
	elseif item.kind == "Outfit" and Costumes.exists(item.id) then
		-- An `OutfitDef.id` is a `Costumes` key by construction -- see
		-- `Outfits.validate` -- so this is the same rig the world builds.
		return RigBuilder.build({ species = "Human", costume = item.id })
	elseif item.kind == "Crystal" and Crystals.exists(item.id) then
		return crystalModel(Crystals.get(item.id).color)
	end
	return nil
end

--[[
	Makes a world model safe to put in a picture frame.

	A rig arrives with a Humanoid that will try to stand up and a stock
	`Animate` script that will try to play animations at it. Neither has
	anything to do inside a viewport, and both cost frames.
]]
local function inert(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		elseif d:IsA("Humanoid") or d:IsA("BaseScript") then
			d:Destroy()
		end
	end
end

local function setPreview(item: ItemEntry?)
	if preview then
		preview:Destroy()
		preview = nil
	end

	local model = if item then previewFor(item) else nil
	if not model then
		viewport.Visible = false
		return
	end

	inert(model)
	model.Parent = viewportWorld
	viewport.Visible = true
	preview = model

	local pivot, size = model:GetBoundingBox()
	previewPivot = pivot
	-- Far enough back that the whole bounding sphere is inside the frustum,
	-- plus a margin so nothing touches the edge. Derived from the model rather
	-- than tuned per kind, because a hold-out blaster and a freighter differ
	-- by two orders of magnitude and one number cannot suit both.
	local radius = math.max(size.Magnitude * 0.5, 0.5)
	previewDistance = radius / math.tan(math.rad(viewportCamera.FieldOfView * 0.5)) * 1.2
	previewAngle = 0
end

--- One degree of turn per frame-ish. Slow enough to read, fast enough to be
--- obviously alive rather than a still that failed to load.
local SPIN_RATE = math.rad(45)

local function spinPreview(delta: number)
	if not preview or not open then
		return
	end
	previewAngle += SPIN_RATE * delta
	local orbit = previewPivot
		* CFrame.Angles(0, previewAngle, 0)
		-- Slightly above the middle, looking down: a weapon seen exactly
		-- edge-on for half of every rotation is a weapon that vanishes.
		* CFrame.new(0, previewDistance * 0.22, previewDistance)
	viewportCamera.CFrame = CFrame.lookAt(orbit.Position, previewPivot.Position)
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

--- The item of this kind the player is actually using, for the delta arrows.
local function equippedEntry(kind: string): ItemEntry?
	for _, item in entriesFor(kind) do
		if item.equipped then
			return item
		end
	end
	return nil
end

local render: () -> ()

--[[
	A signed number in the same units as the stat it belongs to.

	One decimal place, trimmed, because the stats being compared are a whole
	number of damage and a fire rate of 1.4 a second, and "+7.0" is noise while
	"+0" for a real difference of 0.4 is a lie.
]]
local function signed(delta: number): string
	local body = string.format("%.1f", math.abs(delta))
	if string.sub(body, -2) == ".0" then
		body = string.sub(body, 1, -3)
	end
	return body
end

--------------------------------------------------------------------------------
-- The detail pane
--------------------------------------------------------------------------------

local factOrder = 0

--- Adds a full-width row to the scrolling half of the detail pane.
local function fact(name: string, height: number): Frame
	factOrder += 1
	local f = Instance.new("Frame")
	f.Name = `{name}{factOrder}`
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.LayoutOrder = factOrder
	f.Size = UDim2.new(1, -6, 0, height)
	f.Parent = detailScroll
	return f
end

--[[
	One stat, as a label, a bar, a number and an arrow.

	The arrow is the whole point. A player comparing two blasters is asking
	"is this better than what I have", and the panel is the only thing that
	knows both answers at once -- so it should do the subtraction rather than
	make them hold 42 in their head while they click the other row.
]]
local function renderStat(line: StatLine, against: StatLine?)
	local row = fact("Stat", 20)

	local label = text("Label", row, 11, DIM)
	label.Font = Theme.FONT_BOLD
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Size = UDim2.fromOffset(64, 20)
	label.Text = string.upper(line.label)

	local value = text("Value", row, 12, TEXT)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextYAlignment = Enum.TextYAlignment.Center
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -44, 0, 0)
	value.Size = UDim2.fromOffset(58, 20)
	value.Text = line.value

	local raw, max = line.raw, line.max
	if raw and max and max > 0 then
		local bar = Theme.bar("Bar", row)
		bar.track.Position = UDim2.fromOffset(68, 6)
		bar.track.Size = UDim2.new(1, -180, 0, 8)
		bar.fill.Size = UDim2.fromScale(math.clamp(math.abs(raw) / max, 0, 1), 1)
	end

	local other = against and against.raw
	if raw and other and math.abs(raw - other) > 1e-4 then
		local arrow = text("Delta", row, 11, if raw > other then GOOD else BAD)
		arrow.Font = Theme.FONT_BOLD
		arrow.TextXAlignment = Enum.TextXAlignment.Right
		arrow.TextYAlignment = Enum.TextYAlignment.Center
		arrow.AnchorPoint = Vector2.new(1, 0)
		arrow.Position = UDim2.new(1, 0, 0, 0)
		arrow.Size = UDim2.fromOffset(42, 20)
		arrow.Text = `{if raw > other then "▲" else "▼"}{signed(raw - other)}`
	end
end

local function renderNote(body: string, colour: Color3)
	local row = fact("Note", 16)
	local l = text("Text", row, 11, colour)
	l.Size = UDim2.new(1, 0, 1, 0)
	l.Text = body
end

local function openPicker(index: number)
	pickingSocket = index
	for _, child in pickerList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local item = selectedEntry()
	local order = 0
	for _, entry in entriesFor("Crystal") do
		if not entry.carried then
			continue
		end
		order += 1
		local def = Crystals.get(entry.id)
		local b = button(entry.uid, pickerList, "")
		b.LayoutOrder = order
		b.ZIndex = 6
		b.Size = UDim2.new(1, -6, 0, 34)
		b.TextXAlignment = Enum.TextXAlignment.Left

		local dot = text("Dot", b, 15, def.color)
		dot.ZIndex = 6
		dot.TextYAlignment = Enum.TextYAlignment.Center
		dot.Position = UDim2.fromOffset(10, 0)
		dot.Size = UDim2.fromOffset(18, 34)
		dot.Text = DOT_FULL

		local name = text("Name", b, 12, def.color)
		name.ZIndex = 6
		name.Font = Theme.FONT_BOLD
		name.Position = UDim2.fromOffset(32, 5)
		name.Size = UDim2.new(1, -42, 0, 14)
		name.Text = def.displayName

		--[[
			What it does *in this item*, not in general.

			A crimson crystal is damage in a blaster and armour in a robe, and
			the list of all four is what the crystal's own detail pane is for.
			At the moment of choosing, the player is filling one specific hole.
		]]
		local effect = text("Effect", b, 11, DIM)
		effect.ZIndex = 6
		effect.Position = UDim2.fromOffset(32, 18)
		effect.Size = UDim2.new(1, -42, 0, 13)
		local described = Affixes.describe(Crystals.statsFor(entry.id, if item then item.slot else ""))
		effect.Text = described[1] or "No effect here"

		b.Activated:Connect(function()
			local target = selectedEntry()
			pickingSocket = nil
			pickerFrame.Visible = false
			if target then
				Net.fireServer(Net.Event.SocketCrystal, target.uid, index, entry.id)
			end
		end)
	end

	if order == 0 then
		local empty = text("Empty", pickerList, 12, DIM)
		empty.Size = UDim2.new(1, -6, 0, 48)
		empty.TextWrapped = true
		empty.Text = "You are carrying no crystals. They drop from kills."
	end

	pickerFrame.Visible = true
end

--[[
	The socket row: one clickable dot per hole.

	Empty dots are the invitation and filled ones are the receipt, so both are
	the same control in the same place. Extraction is priced and vendor-only,
	which the server enforces -- `extractCosts` arrives empty away from a
	counter, and that emptiness is what hides the price rather than a second
	"am I near a vendor" flag the client could get wrong.
]]
local function renderSockets(item: ItemEntry)
	if item.sockets <= 0 then
		return
	end

	local row = fact("Sockets", 26)

	local label = text("Label", row, 11, DIM)
	label.Font = Theme.FONT_BOLD
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Size = UDim2.fromOffset(64, 26)
	label.Text = "SOCKETS"

	for index = 1, item.sockets do
		local key = tostring(index)
		local crystalId = item.socketed[key]
		local colour = if crystalId and Crystals.exists(crystalId)
			then Crystals.get(crystalId).color
			else FAINT

		local dot = button(`Socket{index}`, row, if crystalId then DOT_FULL else DOT_EMPTY)
		dot.BackgroundTransparency = 1
		dot.Font = Theme.FONT
		dot.TextSize = 18
		dot.TextColor3 = colour
		dot.Position = UDim2.fromOffset(68 + (index - 1) * 26, 0)
		dot.Size = UDim2.fromOffset(24, 26)

		dot.Activated:Connect(function()
			if not crystalId then
				confirmingExtract = nil
				openPicker(index)
			elseif confirmingExtract ~= index then
				confirmingExtract = index
				render()
			else
				confirmingExtract = nil
				Net.fireServer(Net.Event.UnsocketCrystal, item.uid, index)
			end
		end)
	end

	local hint = text("Hint", row, 10, DIM)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextYAlignment = Enum.TextYAlignment.Center
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(1, 0, 0, 0)
	hint.Size = UDim2.new(1, -(68 + item.sockets * 26 + 8), 0, 26)

	local pending = confirmingExtract
	local cost = pending and item.extractCosts[tostring(pending)]
	if pending and cost then
		hint.Text = `TAP AGAIN — {cost} CR, DESTROYS IT`
		hint.TextColor3 = BAD
	elseif next(item.extractCosts) ~= nil then
		hint.Text = "tap a stone to remove it"
		hint.TextColor3 = DIM
	elseif next(item.socketed) ~= nil then
		-- Filled, but nowhere to have it taken out. Said plainly, because
		-- otherwise a dead-looking dot reads as the panel being broken.
		hint.Text = "removal needs a vendor"
		hint.TextColor3 = FAINT
	else
		hint.Text = "tap to fit a crystal"
		hint.TextColor3 = DIM
	end
end

local function renderDetail()
	local snap = snapshot
	local item = selectedEntry()

	factOrder = 0
	for _, child in detailScroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if not item or not snap then
		detailTitle.Text = "Nothing selected"
		detailTitle.TextColor3 = ACCENT
		detailPips.Text = ""
		detailRarity.Text = ""
		detailBody.Text = ""
		actionButton.Visible = false
		disposeButton.Visible = false
		return
	end

	local rarity = Affixes.rarityAt(item.rarity)
	-- Coloured by rarity rather than the panel accent, because the colour is
	-- the fastest read in the whole panel: orange means stop and look.
	local rarityColour = if item.rarity > 0 then rarity.color else ACCENT

	detailTitle.Text = item.displayName
	detailTitle.TextColor3 = rarityColour
	-- Pips as well as the colour: a colour cannot be counted, and "is that
	-- Epic purple or Rare blue" is a question four diamonds answer outright.
	detailPips.Text = Theme.pips(item.rarity, Affixes.MAX_AFFIXES)
	detailPips.TextColor3 = rarityColour
	detailRarity.Text = `{string.upper(rarity.name)}  ·  TIER {item.tier}`
	detailRarity.TextColor3 = rarityColour
	detailBody.Text = item.description

	local against = if item.equipped then nil else equippedEntry(item.kind)
	for _, line in item.stats do
		local match: StatLine? = nil
		if against then
			for _, other in against.stats do
				if other.label == line.label then
					match = other
					break
				end
			end
		end
		renderStat(line, match)
	end

	-- Separated from the base stats: what the item *is* above, what this
	-- particular one rolled below.
	for _, line in item.affixes do
		renderNote(line, ACCENT)
	end
	if item.requiredLevel > 1 then
		renderNote(
			`Requires level {item.requiredLevel}`,
			if snap.level < item.requiredLevel then BAD else DIM
		)
	end

	renderSockets(item)

	actionButton.Visible = true

	local underLevelled = snap.level < item.requiredLevel

	if item.kind == "Crystal" then
		-- A crystal is never equipped; it is fitted into something else. The
		-- button says where to go rather than pretending to be an action,
		-- because a greyed-out EQUIP would read as a bug.
		actionButton.Text = "FIT FROM A WEAPON OR OUTFIT"
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = DIM
		actionButton.Active = false
	elseif item.equipped and item.kind == "Furnishing" then
		-- The one "already in use" state that is still a button. Emptying a
		-- slot is the only way to have a bare wall, and without this the
		-- server's own clear path would be code no player can reach --
		-- which this project has shipped twice and does not intend to again.
		actionButton.Text = `REMOVE — PRESS {Furnishings.BOARD_KEY.Name} TO LOOK`
		actionButton.BackgroundColor3 = ACCENT
		actionButton.TextColor3 = Color3.new(0, 0, 0)
		actionButton.Active = true
	elseif item.equipped then
		actionButton.Text = if item.kind == "Vehicle"
			then `SELECTED — PRESS {Ships.SUMMON_KEY.Name}`
			else "EQUIPPED"
		actionButton.BackgroundColor3 = ROW
		actionButton.TextColor3 = DIM
		actionButton.Active = false
	elseif item.owned then
		-- "SELECT", not "EQUIP": choosing a speeder does not call it in, and a
		-- button that said EQUIP and then left the world unchanged would read
		-- as a failure.
		actionButton.Text = if item.kind == "Outfit"
			then "WEAR"
			elseif item.kind == "Vehicle" then `SELECT — PRESS {Ships.SUMMON_KEY.Name} TO CALL`
			elseif item.kind == "Furnishing" then "FIT TO CABIN"
			else "EQUIP"
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

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function renderHeader(label: string, order: number, colour: Color3)
	local h = text(`Header{order}`, listFrame, 11, colour)
	h.Font = Theme.FONT_BOLD
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
	row.ClipsDescendants = true

	local rarity = Affixes.rarityAt(item.rarity)
	local rarityColour = if item.rarity > 0 then rarity.color else DIM

	--[[
		A stripe of the rarity colour down the left edge.

		The colour used to live only in the item's name, which meant scanning
		for a Legendary was reading thirty words. A stripe is the same fact at
		the same place in every row, so the eye finds it without reading.
	]]
	local stripe = Instance.new("Frame")
	stripe.Name = "Rarity"
	stripe.BackgroundColor3 = rarityColour
	stripe.BorderSizePixel = 0
	stripe.Size = UDim2.new(0, 3, 1, 0)
	stripe.Parent = row
	Theme.gradient(stripe, rarityColour, rarityColour:Lerp(PANEL, 0.55))

	local name = text("Name", row, 14, TEXT)
	name.Font = Theme.FONT_BOLD
	name.Position = UDim2.fromOffset(12, 6)
	name.Size = UDim2.new(1, -120, 0, 18)
	name.Text = item.displayName
	if item.rarity > 0 then
		name.TextColor3 = rarity.color
	end

	local pips = text("Pips", row, 11, rarityColour)
	pips.Position = UDim2.fromOffset(12, 25)
	pips.Size = UDim2.fromOffset(60, 16)
	pips.Text = Theme.pips(item.rarity, Affixes.MAX_AFFIXES)

	local tag = text("Tag", row, 11, DIM)
	tag.Position = UDim2.fromOffset(74, 25)
	tag.Size = UDim2.new(1, -190, 0, 16)
	tag.Text = if item.rarity > 0 then `T{item.tier}  ·  {rarity.name}` else `Tier {item.tier}`

	--[[
		Socket dots, as Frames rather than glyphs.

		`Theme.pips` can draw a count in one label because every diamond is the
		same colour. These are not: each dot is the colour of the stone in it,
		and one `TextLabel` cannot hold three colours.
	]]
	for index = 1, item.sockets do
		local crystalId = item.socketed[tostring(index)]
		local filled = crystalId ~= nil and Crystals.exists(crystalId)
		local dot = Instance.new("Frame")
		dot.Name = `Socket{index}`
		dot.BackgroundColor3 = if filled then Crystals.get(crystalId).color else PANEL
		dot.BorderSizePixel = 0
		dot.AnchorPoint = Vector2.new(1, 0)
		dot.Position = UDim2.new(1, -12 - (item.sockets - index) * 14, 0, 26)
		dot.Size = UDim2.fromOffset(10, 10)
		dot.Parent = row
		corner(dot, 5)
		if not filled then
			Theme.stroke(dot, DIM, 0.4)
		end
	end

	local price = text("Price", row, 13, DIM)
	price.TextXAlignment = Enum.TextXAlignment.Right
	price.AnchorPoint = Vector2.new(1, 0)
	price.Position = UDim2.new(1, -12, 0, 6)
	price.Size = UDim2.fromOffset(104, 18)

	if item.equipped then
		price.Text = if item.kind == "Vehicle"
			then "SELECTED"
			elseif item.kind == "Furnishing" then "FITTED"
			else "EQUIPPED"
		price.TextColor3 = ACCENT
	elseif item.kind == "Crystal" then
		price.Text = "CARRIED"
		price.TextColor3 = DIM
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
		-- Moving the selection cancels a half-pressed discard or extraction,
		-- so a confirm can never be inherited by a different item.
		confirmingDiscard = nil
		confirmingExtract = nil
		pickingSocket = nil
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
		-- A vehicle is `owned` and never `carried`: it lives in the profile's
		-- `unlockedShips`, not in the bag, precisely so that it cannot be sold
		-- or take up a slot. Splitting on `carried` alone would therefore file
		-- the speeder you just bought under the shopkeeper's stock.
		local yours = item.carried or ((item.kind == "Vehicle" or item.kind == "Furnishing") and item.owned)
		table.insert(if yours then mine else theirs, item)
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
		empty.TextWrapped = true
		empty.Text = if activeTab == "Outfit"
			then "You are carrying no outfits. Find a trader to buy some."
			elseif activeTab == "Vehicle" then "You own no speeders or ships. A trader will sell you one."
			elseif
				activeTab == "Crystal"
			then "You have no focusing crystals. They drop from kills, and go in the sockets of weapons and outfits."
			elseif
				activeTab == "Furnishing"
			then `Your cabin is bare. Buy a fitting, then stand by your starship and press {Furnishings.BOARD_KEY.Name}.`
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
	setPreview(selectedEntry())
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
	confirmingExtract = nil
	pickingSocket = nil
	pickerFrame.Visible = false
	if value then
		-- See the matching note in MissionBoardController.setOpen.
		Panels.closeAllExcept(InventoryController.name)
		task.spawn(refresh)
	else
		-- A rig in a viewport is a few dozen parts. Nothing renders them while
		-- the panel is shut, but nothing collects them either.
		setPreview(nil)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function InventoryController.init()
	build()
end

function InventoryController.start()
	RunService.RenderStepped:Connect(spinPreview)

	actionButton.Activated:Connect(function()
		local item = selectedEntry()
		if not item or not actionButton.Active then
			return
		end
		-- A fitted furnishing is the one row whose action is still live: the
		-- button reads REMOVE, and nil is how the server empties a slot.
		if item.kind == "Furnishing" and item.owned then
			local slot = Furnishings.get(item.id).slot
			Net.fireServer(Net.Event.PlaceFurnishing, slot, if item.equipped then nil else item.id)
			return
		end

		if item.equipped then
			return
		elseif item.owned then
			-- Equipping names the stack, buying names the catalogue entry.
			-- A vehicle has no stack, so for that one kind they are the same
			-- string -- see the note on `unlockedShips` in Types.luau.
			if item.kind == "Outfit" then
				Net.fireServer(Net.Event.EquipOutfit, item.uid)
			elseif item.kind == "Vehicle" then
				Net.fireServer(Net.Event.EquipShip, item.id)
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
			confirmingExtract = nil
			pickingSocket = nil
			pickerFrame.Visible = false
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
			-- Escape backs out of the picker first. Closing the whole panel
			-- from inside a sub-choice loses the player their place.
			if pickingSocket then
				pickingSocket = nil
				pickerFrame.Visible = false
			else
				InventoryController.setOpen(false)
			end
		end
	end)

	-- Buying, equipping and socketing all land as profile changes. Re-asking
	-- the server rather than patching the local snapshot means the panel shows
	-- the same thing a fresh open would, including the credits the purchase
	-- actually cost rather than the price this client predicted.
	ServiceLoader.get("ClientState").changed:connect(function()
		if open then
			task.spawn(refresh)
		end
	end)
end

return InventoryController
