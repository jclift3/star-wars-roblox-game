--!strict
--[[
	HudController.luau

	The heads-up display: health, level, XP, credits, the mission tracker and
	notifications.

	BUILT IN CODE, NOT IN STUDIO
	Every element here is constructed at runtime. A HUD assembled by hand in
	StarterGui is invisible to version control, impossible to review, and the
	single most common source of "it works in my Studio" bugs. This costs a few
	hundred lines once and is diffable forever.

	READS, NEVER WRITES
	The HUD renders ClientState and the local Humanoid. It never computes a
	value the server also computes -- the XP bar shows the server's numbers
	even when they disagree with what the client expected, because the server
	is what the player will still have tomorrow.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)
local Affixes = require(Shared.Config.Affixes)
local Palette = require(Shared.Config.Palette)
local Weapons = require(Shared.Config.Weapons)
local Missions = require(Shared.Config.Missions)
local Planets = require(Shared.Config.Planets)
local Progression = require(Shared.Config.Progression)
local Races = require(Shared.Config.Races)
local Ships = require(Shared.Config.Ships)
local Furnishings = require(Shared.Config.Furnishings)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local WorldClock = require(Shared.Core.WorldClock)

local Theme = require(script.Parent.Parent.UI.Theme)

local HudController = {
	name = "HudController",
	priority = 40,
}

local player = Players.LocalPlayer

local PANEL = Theme.PANEL
local ACCENT = Theme.ACCENT
local TEXT = Theme.TEXT
local DIM = Theme.DIM

local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TOAST_LIFETIME = 4
local MAX_TOASTS = 4

local screen: ScreenGui
local healthFill: Frame
local healthText: TextLabel
local xpFill: Frame
local levelLabel: TextLabel
local creditsLabel: TextLabel
local planetLabel: TextLabel
local weaponLabel: TextLabel
local trackerList: Frame
local toastList: Frame

local toasts: { Frame } = {}
local toastOrder = 0

local function state()
	return ServiceLoader.get("ClientState")
end

--------------------------------------------------------------------------------
-- Construction helpers
--------------------------------------------------------------------------------

local corner = Theme.corner

local function panel(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, 6)
	return f
end

--[[
	Deliberately not `Theme.text`.

	The panels' version pins `TextYAlignment` to Top, because a panel label sits
	at the top of a box that is taller than one line. Every label on the HUD is
	exactly one line inside a box exactly its own height, and centred is the
	right answer there -- so this is one line shorter than the shared helper on
	purpose, and not a copy that drifted.
]]
local function text(name: string, parent: Instance, size: number, colour: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Theme.FONT
	l.TextSize = size
	l.TextColor3 = colour or TEXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = parent
	return l
end

--- A bar with a background track and a coloured fill. Returns both.
local function bar(name: string, parent: Instance, colour: Color3): (Frame, Frame)
	local track = Instance.new("Frame")
	track.Name = name
	track.BackgroundColor3 = Color3.fromRGB(40, 44, 52)
	track.BorderSizePixel = 0
	track.Parent = parent
	corner(track, 4)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = colour
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 4)

	return track, fill
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function buildStatusPanel()
	local root = panel("Status", screen)
	root.Position = UDim2.new(0, 16, 1, -16)
	root.Size = UDim2.fromOffset(300, 92)
	root.AnchorPoint = Vector2.new(0, 1)

	levelLabel = text("Level", root, 15, ACCENT)
	levelLabel.Position = UDim2.fromOffset(12, 8)
	levelLabel.Size = UDim2.fromOffset(120, 18)
	levelLabel.Font = Enum.Font.GothamBold

	creditsLabel = text("Credits", root, 14, TEXT)
	creditsLabel.Position = UDim2.new(1, -12, 0, 8)
	creditsLabel.Size = UDim2.fromOffset(160, 18)
	creditsLabel.TextXAlignment = Enum.TextXAlignment.Right
	creditsLabel.AnchorPoint = Vector2.new(1, 0)

	local healthTrack, hFill = bar("Health", root, Color3.fromRGB(205, 62, 62))
	healthTrack.Position = UDim2.fromOffset(12, 32)
	healthTrack.Size = UDim2.new(1, -24, 0, 14)
	healthFill = hFill

	healthText = text("HealthText", healthTrack, 11, TEXT)
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.TextXAlignment = Enum.TextXAlignment.Center
	healthText.ZIndex = 2

	local xpTrack, xFill = bar("Xp", root, ACCENT)
	xpTrack.Position = UDim2.fromOffset(12, 52)
	xpTrack.Size = UDim2.new(1, -24, 0, 6)
	xpFill = xFill

	planetLabel = text("Planet", root, 12, DIM)
	planetLabel.Position = UDim2.fromOffset(12, 64)
	planetLabel.Size = UDim2.fromOffset(180, 18)

	weaponLabel = text("Weapon", root, 12, DIM)
	weaponLabel.Position = UDim2.new(1, -12, 0, 64)
	weaponLabel.Size = UDim2.fromOffset(160, 18)
	weaponLabel.TextXAlignment = Enum.TextXAlignment.Right
	weaponLabel.AnchorPoint = Vector2.new(1, 0)
end

--[[
	The altimeter, bottom right. Only while flying something that can climb.

	There was no altitude readout anywhere, and no speed one either -- which
	was survivable while the sky was empty and stopped being so the moment
	there was a height worth reaching. Flying blind towards an invisible
	threshold is the "finished but unreachable" failure this project has now
	shipped twice under other names, and the cost of avoiding it here is one
	bar and a number.

	The scale runs a quarter past the ceiling rather than up to it, so the
	ceiling can be drawn as a *line on the gauge* with sky above it. A bar
	that simply fills up tells you that you are climbing; a marked line tells
	you how much further, which is the only question the player has.

	Never shown on a speeder. A permanent zero is worse than nothing: it
	invites the player to try to move it.
]]
local altimeter: Frame
local altimeterFill: Frame
local altimeterLabel: TextLabel

--- How far past the ceiling the gauge reads, as a multiple of it.
local ALTIMETER_HEADROOM = 1.25

local function buildAltimeter()
	local root = panel("Altimeter", screen)
	root.Position = UDim2.new(1, -16, 1, -16)
	root.Size = UDim2.fromOffset(58, 186)
	root.AnchorPoint = Vector2.new(1, 1)
	root.Visible = false
	altimeter = root

	local caption = text("Caption", root, 10, DIM)
	caption.Position = UDim2.fromOffset(0, 8)
	caption.Size = UDim2.new(1, 0, 0, 12)
	caption.TextXAlignment = Enum.TextXAlignment.Center
	caption.Text = "ALTITUDE"

	local track, fill = bar("Track", root, ACCENT)
	track.Position = UDim2.fromOffset(20, 26)
	track.Size = UDim2.fromOffset(18, 132)
	altimeterFill = fill
	-- Grown from the bottom edge: this is the one bar on the HUD that is not
	-- a fraction spent but a height reached.
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)

	local ceiling = Instance.new("Frame")
	ceiling.Name = "CeilingMark"
	ceiling.BackgroundColor3 = TEXT
	ceiling.BorderSizePixel = 0
	ceiling.AnchorPoint = Vector2.new(0.5, 0.5)
	ceiling.Position = UDim2.fromScale(0.5, 1 - 1 / ALTIMETER_HEADROOM)
	ceiling.Size = UDim2.new(1, 8, 0, 1)
	ceiling.ZIndex = 3
	ceiling.Parent = track

	altimeterLabel = text("Readout", root, 11, TEXT)
	altimeterLabel.Position = UDim2.new(0, 0, 1, -20)
	altimeterLabel.Size = UDim2.new(1, 0, 0, 14)
	altimeterLabel.TextXAlignment = Enum.TextXAlignment.Center
end

--[[
	Puts a height on the gauge, or nil to put the gauge away.

	Public for the same reason `toast` is: the only thing that knows how high
	a ship is, is the flight loop that is holding it up, and the alternative
	was the HUD raycasting the world every frame to find out something
	another controller already had.
]]
function HudController.setAltitude(altitude: number?, ceiling: number?, inSpace: boolean?)
	if not altimeter then
		return
	end
	if not (altitude and ceiling) then
		altimeter.Visible = false
		return
	end

	altimeter.Visible = true
	-- Scaled to the ceiling it is given rather than to `Ships.CEILING`, so
	-- the marked line is where space actually is on *this* world.
	local top = ceiling * ALTIMETER_HEADROOM
	altimeterFill.Size = UDim2.fromScale(1, math.clamp(altitude / top, 0, 1))
	altimeterFill.BackgroundColor3 = if inSpace then Theme.GOOD else ACCENT
	-- The word, not the number, once the number has stopped being the point.
	altimeterLabel.Text = if inSpace then "ORBIT" else `{math.floor(altitude)}`
	altimeterLabel.TextColor3 = if inSpace then Theme.GOOD else TEXT
end

--[[
	A named place and how far off it is, sitting above the altimeter.

	The altimeter answers "how high", and out between the worlds that has no
	answer -- there is no ground beneath a ship in deep space and no ceiling
	over it, and its Y is a number about nothing. The question that replaces
	it is *which way is home*, so this line names a world and its distance.

	Wide where the altimeter is narrow, because the whole content is a proper
	noun and "Dromund Kaas" does not fit in a gauge 58 pixels across.
]]
local bearing: Frame
local bearingCaption: TextLabel
local bearingValue: TextLabel

local function buildBearing()
	local root = panel("Bearing", screen)
	root.AnchorPoint = Vector2.new(1, 1)
	-- Clear of the altimeter's own 186 by its own 16 again.
	root.Position = UDim2.new(1, -16, 1, -16 - 186 - 8)
	root.Size = UDim2.fromOffset(178, 44)
	root.Visible = false
	bearing = root

	bearingCaption = text("Caption", root, 10, DIM)
	bearingCaption.Position = UDim2.fromOffset(10, 7)
	bearingCaption.Size = UDim2.new(1, -20, 0, 12)

	bearingValue = text("Value", root, 13, TEXT)
	bearingValue.Position = UDim2.fromOffset(10, 21)
	bearingValue.Size = UDim2.new(1, -20, 0, 16)
end

--[[
	The hull's condition, above the bearing line.

	Bottom right with the other two flight readouts, and hidden with them,
	because it answers a question that only exists while you are sitting in
	something: a speeder standing in a yard has a condition, and nobody is
	asking about it.

	A bar rather than a number, and the colour is the whole message. A pilot
	who has just hit a gantry at full throttle is not reading "412/620"; they
	are seeing whether the thing under them went red.
]]
local integrity: Frame
local integrityFill: Frame
local integrityLabel: TextLabel

local function buildIntegrity()
	local root = panel("Integrity", screen)
	root.AnchorPoint = Vector2.new(1, 1)
	-- Above the bearing line, clear of it by the same 8 it clears the
	-- altimeter by. Its own 44 and 8 more.
	root.Position = UDim2.new(1, -16, 1, -16 - 186 - 8 - 44 - 8)
	root.Size = UDim2.fromOffset(178, 38)
	root.Visible = false
	integrity = root

	local caption = text("Caption", root, 10, DIM)
	caption.Position = UDim2.fromOffset(10, 6)
	caption.Size = UDim2.new(1, -20, 0, 12)
	caption.Text = "HULL"

	local track, fill = bar("Track", root, Theme.GOOD)
	track.Position = UDim2.fromOffset(10, 21)
	track.Size = UDim2.new(1, -20, 0, 8)
	integrityFill = fill

	integrityLabel = text("Readout", root, 10, TEXT)
	integrityLabel.AnchorPoint = Vector2.new(1, 0)
	integrityLabel.Position = UDim2.new(1, -10, 0, 6)
	integrityLabel.Size = UDim2.fromOffset(90, 12)
	integrityLabel.TextXAlignment = Enum.TextXAlignment.Right
end

--- Shows a hull's condition, or nil to put the gauge away.
function HudController.setIntegrity(current: number?, max: number?)
	if not integrity then
		return
	end
	if not (current and max and max > 0) then
		integrity.Visible = false
		return
	end

	integrity.Visible = true
	local fraction = math.clamp(current / max, 0, 1)
	integrityFill.Size = UDim2.fromScale(fraction, 1)
	-- Three bands, not a gradient: a gradient tells you the number twice and
	-- a colour change is the thing that catches an eye that is on the road.
	integrityFill.BackgroundColor3 = if fraction <= 0.25
		then Theme.BAD
		elseif fraction <= 0.6 then Theme.WARN
		else Theme.GOOD
	integrityLabel.Text = if current <= 0 then "WRECKED" else `{math.floor(current)} / {math.floor(max)}`
	integrityLabel.TextColor3 = if current <= 0 then Theme.BAD else TEXT
end

--- Shows `caption` over `value`, or nil to put the line away.
function HudController.setBearing(caption: string?, value: string?)
	if not bearing then
		return
	end
	if not (caption and value) then
		bearing.Visible = false
		return
	end
	bearing.Visible = true
	bearingCaption.Text = caption
	bearingValue.Text = value
end

--[[
	Keeps a top-anchored frame clear of Roblox's own topbar.

	This `ScreenGui` sets `IgnoreGuiInset`, so y = 0 is the very top of the
	screen -- which is where the unibar and the player list are. Reported from
	play, 2026-08-17: *"I cant see the shortcuts as they are partially hidden
	by the other menu."*

	`GuiService.TopbarInset` is the region Roblox has reserved, and it is not
	a constant: it changes with platform, and it changes when the player
	expands the unibar. So it is read *and then watched*, rather than baked in
	as the 36 that happens to be true on a desktop today.
]]
--[[
	Hangs something from the top edge, under whatever Roblox has put there.

	This is the only vertical adjustment the top row makes. It used to make a
	second one -- see `moveChatOut` below for why that was wrong.
]]
local belowTopbar: (frame: GuiObject, x: UDim) -> ()
do
	local anchored: { { frame: GuiObject, x: UDim } } = {}

	local function place()
		local top = GuiService.TopbarInset.Max.Y + 10
		for _, held in anchored do
			held.frame.Position = UDim2.new(held.x.Scale, held.x.Offset, 0, top)
		end
	end

	function belowTopbar(frame: GuiObject, x: UDim)
		table.insert(anchored, { frame = frame, x = x })
		place()
	end

	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
end

--[[
	Sends Roblox's chat window to the bottom right, because the top left is
	the game's.

	MOVE THE OBSTACLE, NOT THE THING BEHIND IT
	Reported 2026-08-29: Roblox's chat lands on the first three legend rows.
	The fix then was to drop the legend below the chat, measured off
	`ChatWindowConfiguration.AbsolutePosition + AbsoluteSize` and capped at
	96px so a big window could not drag it to the middle of the screen.

	Reported again 2026-08-30, with a screenshot: *"The key is still way to
	centered. it needs to be at the top."* The cap was not the fix, it was a
	bound on how wrong the fix could get. Those two properties describe the
	rect the chat *reserves*, which exists from join to logout whether or not
	a word has ever been said in it, and is comfortably taller than 96px on
	every screen. So the dodge never lifted: the legend was pinned 96px down
	permanently, and the cap is why it stopped there instead of lower.

	A dodge that always applies is not a dodge, it is just a lower position.

	So the legend goes back to the top and stays there, and the chat moves
	instead. `ChatWindowConfiguration` will take an alignment, which is a
	thing this codebase learned the hard way it should look for: the mistake
	both times was treating Roblox's furniture as immovable and rearranging
	our own around it.

	Bottom right is the one corner where a 400px window costs nothing. The
	status panel is bottom left, the ability bar bottom centre, the tracker
	top right, toasts top centre; the only residents of bottom right are the
	altimeter and the bearing readout, and both are `Visible = false` unless
	you are at a ship's controls -- which is the one time nobody is reading
	chat.
]]
local function moveChatOut()
	local chat = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if not chat then
		return
	end
	chat.HorizontalAlignment = Enum.HorizontalAlignment.Right
	chat.VerticalAlignment = Enum.VerticalAlignment.Bottom
end

local function buildTracker()
	local root = panel("Tracker", screen)
	root.Size = UDim2.fromOffset(280, 0)
	root.AnchorPoint = Vector2.new(1, 0)
	belowTopbar(root, UDim.new(1, -16))
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Visible = false

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = root

	trackerList = root
end

local function buildToasts()
	local root = Instance.new("Frame")
	root.Name = "Toasts"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Size = UDim2.fromOffset(420, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Parent = screen
	belowTopbar(root, UDim.new(0.5, 0))

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = root

	toastList = root
end

--[[
	The key legend, top left.

	Five finished panels the player has no way to find are five features that
	do not exist. Reported from play, 2026-08-17: "I'm unsure how to use
	powers, where we see the skills tree" -- from someone who had played long
	enough to finish a mission. Nothing in the game had ever said a letter out
	loud, and a keyboard has twenty-six of them.

	Read from `Panels.ALL` rather than written out, so this cannot drift from
	what the keys actually do; a panel that declares a `toggle` is advertised
	by declaring it, and one that does not is silently skipped. That is the
	same bargain the registry already makes for input focus and mutual close.

	Top left because it is the only corner with nothing in it -- status is
	bottom left, the tracker is top right, toasts are top centre and the
	ability bar is bottom centre -- and because a reference card should not
	sit where the eye goes during a fight.

	It is visible by default -- see the collapse note below, which came
	later. An always-visible legend is a small permanent cost against a
	player who does not know the game has a skill tree, and the two brothers
	play in one room: whichever of them reads it first tells the other.

	It sits under `belowTopbar` for the reason documented there: the unibar
	was covering the first two entries, which is the whole legend for a
	player who reads left to right and stops.

	AND THE CHAT IS NOT ALLOWED TO SIT ON IT
	Seen in play 2026-08-29: Roblox's own "automatically translates supported
	languages in chat" notice fires on join, for everybody, and lands square
	on top of the first three entries -- LMB, SHIFT and 1-6. Those are the
	three written by hand below precisely because nothing in the game had
	ever said them out loud, they are first because they are the only rows
	true of a character who has unlocked nothing, and being first is exactly
	what put them under the chat. So the one minute they exist for was the
	one minute they could not be read.

	The legend does not move for that. `moveChatOut` does -- see the second
	report there, which is the record of what happens when you concede a
	corner you own.

	IT HIDES NOW, AND IT ONLY SHOWS WHAT IS TRUE RIGHT NOW
	Reported 2026-08-29: *"we should be able to minimize mostly and then
	maximize it. also if it makes sense to have less hot keys that's ok."*
	Both halves were fair. The row had grown to eleven entries and was
	telling a player standing in a desert about the hyperdrive.

	So, three cuts. A chevron collapses the whole thing to a single chip.
	The flight rows move into a second group that only appears while
	somebody is at a starship's controls. And the five panel letters become
	one `TAB` row, because `MenuController` now opens all five and prints
	their letters on the tabs.

	That is eleven entries down to six, five of which are true of a
	character who has unlocked nothing. Collapsing is remembered for the
	session but never saved -- a player who hides the legend on Tuesday and
	forgets the keys by Friday is worse off than one who hides it twice.
]]
local legendRows: Frame
local legendFlight: Frame
local legendOpen = true

--- Shows or hides the flight rows. Called by `VehicleController` when a
--- pilot takes or leaves a starship's controls, because it is the only
--- thing that knows.
function HudController.setFlightKeys(visible: boolean)
	if legendFlight then
		legendFlight.Visible = visible
	end
end

local function buildLegend()
	local root = Instance.new("Frame")
	root.Name = "Legend"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(0, 20)
	root.AutomaticSize = Enum.AutomaticSize.X
	root.Parent = screen
	belowTopbar(root, UDim.new(0, 16))

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = root

	--[[
		The collapse control.

		A chevron rather than a word, and it stays put when the rows go, so
		the thing you press to get the legend back is in the same place as
		the thing you pressed to send it away. It is deliberately the only
		part of the HUD that is clickable: everything else here is a
		readout, and a player hunting for a button should find exactly one.
	]]
	local chip = panel("Toggle", root)
	chip.Size = UDim2.fromOffset(18, 18)
	chip.LayoutOrder = 0

	local chevron = text("Chevron", chip, 11, ACCENT)
	chevron.Font = Enum.Font.GothamBold
	chevron.Size = UDim2.fromScale(1, 1)
	chevron.TextXAlignment = Enum.TextXAlignment.Center
	chevron.Text = "<"

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.Parent = chip

	legendRows = Instance.new("Frame")
	legendRows.Name = "Rows"
	legendRows.BackgroundTransparency = 1
	legendRows.Size = UDim2.fromOffset(0, 20)
	legendRows.AutomaticSize = Enum.AutomaticSize.X
	legendRows.LayoutOrder = 1
	legendRows.Parent = root

	local rowLayout = layout:Clone()
	rowLayout.Parent = legendRows

	hit.Activated:Connect(function()
		legendOpen = not legendOpen
		legendRows.Visible = legendOpen
		chevron.Text = if legendOpen then "<" else ">"
	end)

	local order = 0
	local function entryIn(parent: Frame, cap: string, hint: string)
		order += 1

		local holder = Instance.new("Frame")
		holder.Name = cap
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(0, 20)
		holder.AutomaticSize = Enum.AutomaticSize.X
		holder.LayoutOrder = order
		holder.Parent = parent

		local inner = Instance.new("UIListLayout")
		inner.FillDirection = Enum.FillDirection.Horizontal
		inner.SortOrder = Enum.SortOrder.LayoutOrder
		inner.VerticalAlignment = Enum.VerticalAlignment.Center
		inner.Padding = UDim.new(0, 5)
		inner.Parent = holder

		local key = panel("Key", holder)
		-- Three widths, not two: every panel key is a single letter, but the
		-- hand-written rows below spell out whole words, and "SHIFT" in a box
		-- cut for "1-6" is a legend that has to be guessed at.
		key.Size = UDim2.fromOffset(if #cap > 3 then 44 elseif #cap > 1 then 34 else 18, 18)
		key.LayoutOrder = 1

		local letter = text("Letter", key, 11, ACCENT)
		letter.Font = Enum.Font.GothamBold
		letter.Size = UDim2.fromScale(1, 1)
		letter.TextXAlignment = Enum.TextXAlignment.Center
		letter.Text = cap

		local label = text("Hint", holder, 11, DIM)
		label.Size = UDim2.fromOffset(0, 18)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.LayoutOrder = 2
		label.Text = hint
	end

	--[[
		The two verbs a player has before they have anything else, and the two
		the game never said out loud.

		This is an action RPG whose whole loop is swinging at something, and
		until now nothing anywhere -- not the legend, not the creation card,
		not a mission -- stated that the mouse button is how you swing. It was
		left to be discovered, which works for the boy who has played one of
		these before and not for the one who hasn't. Sprint is the same
		omission one rank down: the walk between two markers is the most
		common complaint about the game and the fix was already bound.

		They go first because they are the only two rows that are true of a
		character who has unlocked nothing.
	]]
	entryIn(legendRows, "LMB", "ATTACK")
	-- Aim is the third. `AimController` has bound the right button to a
	-- shoulder camera and a spread reticle since 2026-08-17, in answer to a
	-- complaint about shooting, and then never said so -- which is the same
	-- failure as the two rows above it, one system over.
	entryIn(legendRows, "RMB", "AIM")
	entryIn(legendRows, "SHIFT", "SPRINT")

	--[[
		The number keys are not a panel, so they are written by hand too. They
		are also the answer to the half of the report that was about powers,
		and they go early: the bar itself is invisible until the tree has
		unlocked something, so before that this row is the only thing on
		screen that says abilities exist at all.
	]]
	entryIn(legendRows, "1-6", "POWERS")

	--[[
		The summon key is the other hand-written line, for the same reason: a
		speeder is not a panel. It is listed before the player owns one on
		purpose -- the legend is also the advertisement, and a player who
		never learns the game has vehicles never walks into the shop to buy
		one, which leaves them doing the walk they are complaining about.
	]]
	entryIn(legendRows, Ships.SUMMON_KEY.Name, Ships.SUMMON_HINT)

	--[[
		One row where there used to be five.

		B, M, J, K and G each earned their place here in 2026-08-17, when the
		complaint was that finished panels had no advertised way in. They
		fixed that and created the next problem: five unrelated letters to
		memorise before the interface is usable, which is what
		`MenuController` now answers. The letters still work and are printed
		on the tabs themselves, so this row is the only thing a player has to
		read to reach all five.
	]]
	entryIn(legendRows, Panels.MENU_CAP, Panels.MENU_HINT)

	--[[
		The flight group, which is off until somebody is flying.

		Climb, dive, jump and the cabin door are four rows that are false of
		every player on foot, and there is one of those for every minute of
		play spent in a cockpit. Worse, they were false in a way that reads
		as broken: a boy standing in Anchorhead pressing SPACE because the
		legend says CLIMB gets a jump, and concludes the legend lies.

		It is a group rather than four hidden rows so that its own layout
		order is independent -- the flight keys appear together, at the end,
		in the order you need them, whatever the panel registry grows to.
	]]
	legendFlight = Instance.new("Frame")
	legendFlight.Name = "Flight"
	legendFlight.BackgroundTransparency = 1
	legendFlight.Size = UDim2.fromOffset(0, 20)
	legendFlight.AutomaticSize = Enum.AutomaticSize.X
	legendFlight.LayoutOrder = 99
	legendFlight.Visible = false
	legendFlight.Parent = legendRows

	local flightLayout = layout:Clone()
	flightLayout.Parent = legendFlight

	-- Climb and dive, which are the only two controls in the game that have
	-- never been stated anywhere -- not here, not in the shop that sells the
	-- ship, not on the pad it launches from. A starship that flies dead level
	-- forever is a starship that cannot reach orbit, and the player would
	-- have no way of knowing that was their doing rather than the game's.
	entryIn(legendFlight, Ships.PITCH_UP_CAP, Ships.PITCH_UP_HINT)
	entryIn(legendFlight, Ships.PITCH_DOWN_CAP, Ships.PITCH_DOWN_HINT)

	-- And the hyperdrive, which is the only key in the game that is *held*
	-- rather than pressed. The legend cannot say so in one column, so the
	-- refusal does: pressing it with no course names the star map instead.
	entryIn(legendFlight, Ships.ENGAGE_CAP, Ships.ENGAGE_HINT)
	entryIn(legendFlight, Ships.EXIT_CAP, Ships.EXIT_HINT)

	-- And the cabin door, for exactly the same reason as the summon key: a
	-- room is not a panel, and a starship whose inside nobody knows about is
	-- a starship with no inside.
	entryIn(legendFlight, Furnishings.BOARD_KEY.Name, Furnishings.BOARD_HINT)
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

local function setBar(fill: Frame, fraction: number)
	TweenService:Create(fill, BAR_TWEEN, { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1) }):Play()
end

local function bindHumanoid(humanoid: Humanoid)
	local function refresh()
		setBar(healthFill, humanoid.Health / math.max(1, humanoid.MaxHealth))
		healthText.Text = `{math.floor(humanoid.Health + 0.5)} / {math.floor(humanoid.MaxHealth)}`
	end
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	refresh()
end

--[[
	Rebuilds the mission tracker.

	Rebuilt wholesale rather than diffed: there are at most a handful of active
	missions, and a rebuild cannot leave a stale objective on screen the way an
	incremental update can.
]]
local function refreshTracker()
	local profile = state().get()
	if not profile then
		return
	end

	for _, child in trackerList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local order = 0
	for missionId, entry in profile.missions.active do
		if not Missions.exists(missionId) then
			continue
		end
		local mission = Missions.get(missionId)

		order += 1
		local title = text("Title", trackerList, 14, ACCENT)
		title.Font = Enum.Font.GothamBold
		title.Size = UDim2.new(1, 0, 0, 18)
		title.LayoutOrder = order
		title.Text = mission.displayName

		for index, obj in mission.objectives do
			local done = entry.objectives[index] or 0
			local needed = Missions.objectiveTarget(obj)
			-- Hidden objectives stay hidden until they can actually be worked
			-- on, so the tracker does not spoil the mission's own reveal.
			if obj.hidden and done == 0 then
				continue
			end

			order += 1
			local line = text("Objective", trackerList, 13, if done >= needed then DIM else TEXT)
			line.Size = UDim2.new(1, 0, 0, 16)
			line.LayoutOrder = order
			line.TextWrapped = true
			line.AutomaticSize = Enum.AutomaticSize.Y
			line.Text = if needed > 1
				then `  {obj.description}  ({done}/{needed})`
				else `  {if done >= needed then "[x]" else "[ ]"} {obj.description}`
		end
	end

	--[[
		The empty state, which is the first thing a new character ever sees
		here and used to be nothing at all.

		`Visible = order > 0` meant that a player who had just dismissed the
		creation card had an entirely blank top-right corner, and the only
		thing on screen pointing at the mission board was one row of an 11pt
		legend in the opposite corner. That is the 2026-08-17 finding --
		finished but unreachable -- reproduced for the single most important
		click in the game: the one that gives you something to do.

		So the tracker is now always up, and when it has nothing to track it
		says where work comes from. This is deliberately not a tutorial, a
		popup or a first-run flag: it is the honest contents of a box that
		lists your contracts when you have none, so it is equally correct on
		minute one and after you hand in your last mission at level 40.
	]]
	if order == 0 then
		local title = text("Title", trackerList, 14, DIM)
		title.Font = Enum.Font.GothamBold
		title.Size = UDim2.new(1, 0, 0, 18)
		title.LayoutOrder = 1
		title.Text = "NO CONTRACT"

		local key = Panels.toggleKey("MissionBoardController")
		local line = text("Objective", trackerList, 13, TEXT)
		line.Size = UDim2.new(1, 0, 0, 16)
		line.LayoutOrder = 2
		line.TextWrapped = true
		line.AutomaticSize = Enum.AutomaticSize.Y
		-- Read out of `Panels` rather than written as "M", for the same reason
		-- the legend does: the key lives in one place and rebinding it must
		-- not leave a line of the HUD lying.
		line.Text = if key then `  Press {key.Name} for the mission board` else "  See the mission board"
	end

	trackerList.Visible = true
end

--[[
	The planet and its local time, on one line.

	Separate from `refreshProfile` because it is the one thing on the HUD that
	changes without the profile doing anything, and rebuilding the mission
	tracker once a second to move a clock would be a waste and a flicker.

	The clock is here at all because as of the day/night schedules it decides
	something: who is out on the street. Without a number on screen the only
	reading of a market that has gone still is that the NPCs are broken -- and
	a tester asked to "wait for dusk" has nothing to wait on.
]]
local function refreshClock()
	local profile = state().get()
	if not profile then
		return
	end
	local planetId = profile.currentPlanet
	local displayName = if Planets.exists(planetId) then Planets.get(planetId).displayName else planetId
	planetLabel.Text = `{displayName}  {WorldClock.label(planetId)}`
end

local function refreshProfile()
	local profile = state().get()
	if not profile then
		return
	end

	levelLabel.Text = `LEVEL {profile.level}`
	creditsLabel.Text = `{profile.credits} cr`

	local needed = Progression.xpForNextLevel(profile.level)
	setBar(xpFill, if needed > 0 then profile.xp / needed else 1)

	refreshClock()

	-- Not `equipped.weapon` itself: that is a stack uid, and a rolled blaster's
	-- uid is `DH17#2`. The player is holding a Vicious DH-17, so say so.
	local weaponId = state().equippedWeapon()
	if weaponId and Weapons.exists(weaponId) then
		local rolls = state().equippedWeaponRolls()
		weaponLabel.Text = Affixes.nameFor(Weapons.get(weaponId).displayName, rolls)
		weaponLabel.TextColor3 = if rolls then Affixes.rarityOf(rolls).color else DIM
	else
		weaponLabel.Text = "Unarmed"
		weaponLabel.TextColor3 = DIM
	end

	refreshTracker()
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------

local KIND_COLOURS: { [string]: Color3 } = {
	Error = Color3.fromRGB(220, 90, 90),
	LevelUp = Palette.SaberYellow,
	Promotion = Palette.SaberGreen,
	Demotion = Color3.fromRGB(220, 120, 90),
	Reward = Palette.DroidGold,
	MissionComplete = Palette.SaberGreen,
	MissionFailed = Color3.fromRGB(220, 90, 90),
}

-- A loot toast names its rarity as its kind, so the colours come from the
-- rarity table rather than being written out a second time here.
for count = 1, Affixes.MAX_AFFIXES do
	local rarity = Affixes.rarityAt(count)
	KIND_COLOURS[rarity.name] = rarity.color
end

-- And a finish toast names its medal, read from the same table `RaceService`
-- awards it from, for exactly the same reason.
for _, medal in Races.MEDALS do
	KIND_COLOURS[medal.id] = medal.colour
end

--[[
	Puts a message in the toast stack.

	Public because a refused ability has to say why, and the alternative was a
	second round trip: the server would have to send both a refusal the bar can
	act on and a `Notify` the HUD can draw, for one press of a key that did
	nothing. There is one toast stack; this is how you reach it.
]]
function HudController.toast(message: string, kind: string?)
	local frame = panel("Toast", toastList)
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	toastOrder += 1
	frame.LayoutOrder = toastOrder

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	local label = text("Message", frame, 14, KIND_COLOURS[kind or "Info"] or TEXT)
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = message

	table.insert(toasts, frame)
	-- Oldest first: a level-up notice should not be pushed off by chatter.
	while #toasts > MAX_TOASTS do
		local oldest = table.remove(toasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	task.delay(TOAST_LIFETIME, function()
		local index = table.find(toasts, frame)
		if index then
			table.remove(toasts, index)
		end
		if frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			for _, d in frame:GetDescendants() do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				end
			end
			task.delay(0.35, function()
				frame:Destroy()
			end)
		end
	end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HudController.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "HUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")

	buildStatusPanel()
	buildAltimeter()
	buildBearing()
	buildIntegrity()
	buildTracker()
	buildToasts()
	buildLegend()
	moveChatOut()
	-- No crosshair here. There used to be a permanent white dot in the middle
	-- of the screen, and it was a lie by omission: shots do go through the
	-- centre, but nothing about a free mouse and a character facing wherever
	-- it last walked gave the player any reason to believe that. The reticle
	-- now belongs to `AimController`, which only draws it while the player is
	-- actually holding the aim button and the claim is actually true.

	Net.onClientEvent(Net.Event.Notify, function(message: string, kind: string?)
		HudController.toast(message, kind)
	end)

	-- MissionUpdated is a nudge, not data: the authoritative copy arrives with
	-- the profile, so the tracker just redraws from whatever it now holds.
	Net.onClientEvent(Net.Event.MissionUpdated, function()
		refreshTracker()
	end)
end

function HudController.start()
	state().changed:connect(refreshProfile)
	refreshProfile()

	local function hookCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			bindHumanoid(humanoid)
		end
	end

	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(hookCharacter, character)
	end)

	-- The clock moves without the profile changing, and a shortest day is
	-- fifteen real minutes, so a minute of planet time is under a second here.
	task.spawn(function()
		while true do
			task.wait(1)
			refreshClock()
		end
	end)
end

return HudController
