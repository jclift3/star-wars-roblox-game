--!strict
--[[
	RaceController.luau

	The clock, the lap counter, and which arch to aim at.

	WHY THIS EXISTS AT ALL
	`RaceService` composes a circuit out of the world's own landmarks, so the
	gates are somewhere the player has never been told about and no two planets
	put them in the same place. A timed lap where you cannot see the next gate
	is not a race, it is a search; and the 2026-08-17 report's whole lesson was
	that a finished system nobody can find does not exist.

	NOT A PANEL
	`Panels.luau` is for the six full-screen 760x470 things you open with a
	letter and close again. A race clock is the opposite kind of UI: you never
	open it, you cannot close it, and it is only ever on screen while something
	is true. Registering it would put a key in the HUD legend for a window that
	is empty every minute you are not racing.

	THE CLOCK RUNS HERE, NOT ON THE SERVER
	The server sends `startedAt` once, as a reading of `GetServerTimeNow()`,
	and this counts up from it every frame. Both machines can read that clock,
	so the alternative -- a remote firing sixty times a second to deliver a
	number the client could have worked out -- buys nothing. It also means the
	two brothers' clocks agree to the millisecond without either of them ever
	being sent the other's.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Palette = require(Shared.Config.Palette)
local Races = require(Shared.Config.Races)

local Theme = require(script.Parent.Parent.UI.Theme)

local RaceController = {
	name = "RaceController",
	-- Beside the ability bar (41) and the district banner (43): a HUD widget
	-- that appears when the game says so, not a panel the player opens.
	priority = 42,
}

local player = Players.LocalPlayer

--- What `Net.Event.RaceState` carries. Mirrored from `RaceService.push`; the
--- server is the only writer, so this is a description rather than a contract.
type State = {
	planet: string,
	startedAt: number,
	par: number,
	laps: number,
	lap: number,
	gateCount: number,
	gateIndex: number,
	gatePosition: Vector3,
	best: number?,
}

local current: State? = nil

local screen: ScreenGui
local timeLabel: TextLabel
local lapLabel: TextLabel
local gateLabel: TextLabel
local parLabel: TextLabel
local bestLabel: TextLabel

--- Adorns whichever gate is next. Reparented rather than rebuilt, so there is
--- exactly one of these however many gates a circuit turns out to have.
local highlight: Highlight

--------------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------------

local function build()
	local gui = player:WaitForChild("PlayerGui")

	screen = Instance.new("ScreenGui")
	screen.Name = "RaceClock"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- Above the district banner, below the panels: a lap time matters more
	-- than the name of the district you are crossing and less than the shop
	-- you have deliberately opened.
	screen.DisplayOrder = 6
	screen.Enabled = false
	screen.Parent = gui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.BackgroundColor3 = Theme.PANEL
	card.BackgroundTransparency = 0.15
	card.BorderSizePixel = 0
	card.Position = UDim2.new(0.5, 0, 0, 14)
	card.Size = UDim2.fromOffset(240, 108)
	card.Parent = screen
	Theme.corner(card, 6)
	Theme.stroke(card, Theme.ACCENT, 0.55)

	timeLabel = Theme.text("Time", card, 34, Theme.TEXT)
	timeLabel.Font = Theme.FONT_BOLD
	timeLabel.TextXAlignment = Enum.TextXAlignment.Center
	timeLabel.Position = UDim2.fromOffset(0, 8)
	timeLabel.Size = UDim2.new(1, 0, 0, 38)

	lapLabel = Theme.text("Lap", card, 14, Theme.ACCENT)
	lapLabel.Font = Theme.FONT_BOLD
	lapLabel.TextXAlignment = Enum.TextXAlignment.Center
	lapLabel.Position = UDim2.fromOffset(0, 48)
	lapLabel.Size = UDim2.new(0.5, 0, 0, 18)

	gateLabel = Theme.text("Gate", card, 14, Theme.DIM)
	gateLabel.TextXAlignment = Enum.TextXAlignment.Center
	gateLabel.Position = UDim2.new(0.5, 0, 0, 48)
	gateLabel.Size = UDim2.new(0.5, 0, 0, 18)

	parLabel = Theme.text("Par", card, 12, Theme.FAINT)
	parLabel.TextXAlignment = Enum.TextXAlignment.Center
	parLabel.Position = UDim2.fromOffset(0, 70)
	parLabel.Size = UDim2.new(0.5, 0, 0, 16)

	bestLabel = Theme.text("Best", card, 12, Theme.FAINT)
	bestLabel.TextXAlignment = Enum.TextXAlignment.Center
	bestLabel.Position = UDim2.new(0.5, 0, 0, 70)
	bestLabel.Size = UDim2.new(0.5, 0, 0, 16)

	local hint = Theme.text("Hint", card, 11, Theme.DIM)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Position = UDim2.fromOffset(0, 88)
	hint.Size = UDim2.new(1, 0, 0, 14)
	hint.Text = "Leave the seat to give up"

	--[[
		`AlwaysOnTop`, and that is the point of using a Highlight at all.

		The next gate is routinely a landmark's width behind a landmark, and
		on a world with fog it can be past the draw distance -- both of which
		are the "landmark looks missing" checklist from the world-building
		notes. An outline that ignores depth is the one cue that survives
		both, and it costs no geometry.
	]]
	highlight = Instance.new("Highlight")
	highlight.Name = "NextGate"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Palette.RebelOrange
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = Palette.RebelOrange
	highlight.Enabled = false
	highlight.Parent = screen
end

--------------------------------------------------------------------------------
-- Following the run
--------------------------------------------------------------------------------

--- The model `RaceService` drew for a gate, if this client has it yet.
local function gateModel(state: State): Model?
	local root = Workspace:FindFirstChild("Races")
	local planetFolder = root and root:FindFirstChild(state.planet)
	local model = planetFolder and planetFolder:FindFirstChild(`Gate{state.gateIndex}`)
	return if model and model:IsA("Model") then model else nil
end

local function apply(state: State?)
	current = state
	screen.Enabled = state ~= nil
	if not state then
		highlight.Enabled = false
		highlight.Adornee = nil
		return
	end

	lapLabel.Text = `LAP {state.lap}/{state.laps}`
	parLabel.Text = `PAR {Races.format(state.par)}`
	local best = state.best
	bestLabel.Text = if best then `BEST {Races.format(best)}` else "BEST --"

	local model = gateModel(state)
	highlight.Adornee = model
	highlight.Enabled = model ~= nil
end

local function update()
	local state = current
	if not state then
		return
	end

	local elapsed = Workspace:GetServerTimeNow() - state.startedAt
	timeLabel.Text = Races.format(elapsed)
	-- Past par the clock goes red, which is the only feedback in the run that
	-- says the medal has gone without waiting for the finish line to say it.
	timeLabel.TextColor3 = if elapsed > state.par then Theme.BAD else Theme.TEXT

	--[[
		The distance sits next to the gate number rather than replacing it.

		"GATE 3" alone does not tell you where to go on a circuit you have
		never driven, and a distance alone does not tell you how much of the
		lap is left. Both fit on one line.
	]]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local away = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(
			state.gatePosition.X,
			0,
			state.gatePosition.Z
		)).Magnitude
		gateLabel.Text = `GATE {state.gateIndex}  {math.floor(away)}m`
	else
		gateLabel.Text = `GATE {state.gateIndex}`
	end

	-- The world may not have finished replicating the gate when the state
	-- arrived, so this keeps trying rather than leaving the outline off for
	-- the whole leg.
	if not highlight.Enabled then
		local model = gateModel(state)
		if model then
			highlight.Adornee = model
			highlight.Enabled = true
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RaceController.init()
	build()
end

function RaceController.start()
	Net.onClientEvent(Net.Event.RaceState, function(state: any)
		apply(state)
	end)
	RunService.RenderStepped:Connect(update)
end

return RaceController
