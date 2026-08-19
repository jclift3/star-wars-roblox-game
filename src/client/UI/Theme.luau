--!strict
--[[
	Theme.luau

	The colours and the four widgets every panel in this game is made of.

	WHY THIS EXISTS
	Seven controllers had each declared the same eight colour constants and
	pasted the same `corner` / `text` / `button` helpers -- about ninety
	duplicated lines, and, more to the point, eight numbers that had to be
	retyped identically in seven files to keep the game looking like one game.
	They had already drifted once: `VendorController`'s DIM was
	`(150, 154, 162)` where everyone else's was `(150, 158, 170)`, which is
	invisible in isolation and exactly the sort of thing that makes a UI feel
	assembled rather than designed.

	NO IMAGE ASSETS, HERE OR ANYWHERE
	This project has never referenced an asset id and is not going to start for
	a shop panel. Everything below is `Instance.new` and geometry: a gradient
	is a `UIGradient`, an icon is a Unicode glyph in a `TextLabel`, and an item
	preview is a real model in a `ViewportFrame`. That constraint is why the
	panels look the way they do, and it is also why they cost nothing to
	change -- there is no art pipeline standing between an idea and a commit.

	WHAT IS NOT HERE
	Layout. Every panel is 760x470 (see `Panels.luau`) but where its list ends
	and its detail pane begins is that panel's own business, and a shared
	layout would be a framework -- the thing that turns "move this 8 pixels
	left" into an argument with an abstraction.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Config.Palette)

local Theme = {}

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------

--- The panel body. Nearly black, so rarity colours read against it.
Theme.PANEL = Color3.fromRGB(14, 16, 20)
--- A row, a tab, or a button at rest.
Theme.ROW = Color3.fromRGB(26, 30, 37)
--- The row the player is looking at.
Theme.ROW_SELECTED = Color3.fromRGB(44, 52, 64)
--[[
	The one colour the whole UI is built around.

	Deliberately the same orange the HUD and the waypoints use: a panel that
	introduced its own accent would be a second brand inside the same game.
]]
Theme.ACCENT = Palette.RebelOrange
--- Body copy.
Theme.TEXT = Color3.fromRGB(232, 236, 242)
--- Labels, units, and anything the eye should skip on the way somewhere.
Theme.DIM = Color3.fromRGB(150, 158, 170)
--- Dimmer still: timestamps, and text that is present only for completeness.
Theme.FAINT = Color3.fromRGB(104, 111, 122)
--- Money coming in, a stat going up, a thing that worked.
Theme.GOOD = Color3.fromRGB(96, 190, 120)
--- Money going out, a stat going down, a thing that will not work.
Theme.BAD = Color3.fromRGB(198, 78, 78)
--- "This is allowed but you should think about it." Never an error.
Theme.WARN = Color3.fromRGB(214, 168, 74)

Theme.FONT = Enum.Font.Gotham
Theme.FONT_BOLD = Enum.Font.GothamBold

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

function Theme.corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

--[[
	A hairline border.

	`ApplyStrokeMode.Border` rather than the default, so the line sits outside
	the frame and a one-pixel outline does not eat a pixel of a 46-stud row.
]]
function Theme.stroke(parent: Instance, colour: Color3, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = 1
	s.Transparency = transparency or 0.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

--[[
	A vertical wash from `top` to `bottom`.

	The cheapest way to make a flat rectangle look lit, and the only way
	available without an image. Rotation is fixed at 90 degrees because every
	use in this game is a light-from-above cue, and a parameter for it would
	be a knob nobody turns.
]]
function Theme.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
	return g
end

function Theme.text(name: string, parent: Instance, size: number, colour: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Theme.FONT
	l.TextSize = size
	l.TextColor3 = colour or Theme.TEXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Text = ""
	l.Parent = parent
	return l
end

function Theme.button(name: string, parent: Instance, label: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = true
	b.BackgroundColor3 = Theme.ROW
	b.BorderSizePixel = 0
	b.Font = Theme.FONT_BOLD
	b.TextSize = 13
	b.TextColor3 = Theme.TEXT
	b.Text = label
	b.Parent = parent
	Theme.corner(b, 4)
	return b
end

export type Bar = {
	track: Frame,
	fill: Frame,
}

--[[
	A track with a fill in it, for showing a number as a length.

	Returned as both halves rather than as a `setValue` closure, because the
	callers want to colour the fill differently (a stat bar is accent, a
	health bar is red) and a closure that took a colour as well as a fraction
	would be the same two lines with more ceremony.

	The track is not transparent: an empty bar has to be visibly an empty bar
	and not a gap in the layout, or a stat of zero looks like a missing row.
]]
function Theme.bar(name: string, parent: Instance): Bar
	local track = Instance.new("Frame")
	track.Name = name
	track.BackgroundColor3 = Theme.PANEL
	track.BorderSizePixel = 0
	track.Parent = parent
	Theme.corner(track, 3)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.ACCENT
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	Theme.corner(fill, 3)
	Theme.gradient(fill, Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))

	return { track = track, fill = fill }
end

--[[
	`◆◆◆◇` -- a count drawn as filled and empty diamonds.

	Rarity is already a colour, and a colour alone cannot be counted: "is that
	Epic purple or Rare blue" is a question the player asks across a dark
	panel, and four pips answers it without them having to remember a legend.
	Glyphs rather than four small Frames because this goes inside a row that is
	already laid out by pixel offsets, and one `TextLabel` cannot fight with a
	`UIListLayout`.
]]
function Theme.pips(filled: number, total: number): string
	local out = ""
	for i = 1, total do
		out ..= if i <= filled then "◆" else "◇"
	end
	return out
end

return Theme
