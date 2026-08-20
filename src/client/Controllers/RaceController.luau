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

	AND SO DO THE RIVALS, FOR THE SAME REASON AND ONE MORE
	A rival holds a fixed speed round a fixed polyline, so where it is at
	time t is `t * speed` along the route -- arithmetic this file can do from
	the route and the speeds it was handed once. That is the same trade as
	the clock: five hulls' positions sixty times a second, or two arrays.

	The extra reason is that a server-built rival would be a rival *both*
	brothers can see. They start their laps whenever they cross the line, so
	the grid one of them is racing is halfway round the circuit while the
	other is still on the start line, and putting both fields in the world at
	once means six ghosts on the road and no way to tell whose are whose.
	A ghost drawn by the client racing it is only ever in one race.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Palette = require(Shared.Config.Palette)
local Races = require(Shared.Config.Races)
local Ships = require(Shared.Config.Ships)
local ShipModel = require(Shared.Rig.ShipModel)

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
	--- The gate ring at road level, in order and closed implicitly.
	route: { Vector3 },
	rivals: { Races.Rival },
}

local current: State? = nil

local screen: ScreenGui
local timeLabel: TextLabel
local placeLabel: TextLabel
local lapLabel: TextLabel
local gateLabel: TextLabel
local parLabel: TextLabel
local bestLabel: TextLabel

--- Adorns whichever gate is next. Reparented rather than rebuilt, so there is
--- exactly one of these however many gates a circuit turns out to have.
local highlight: Highlight

--------------------------------------------------------------------------------
-- The route, resolved once per run
--------------------------------------------------------------------------------

--- How see-through a rival is. Enough to read as a ghost from behind at
--- speed, not so much that it stops being a shape you can follow.
local GHOST_TRANSPARENCY = 0.55

type Leg = {
	from: Vector3,
	--- Unit vector along this leg, used both to walk it and to aim the hull.
	direction: Vector3,
	length: number,
	--- Distance from the start line to the beginning of this leg.
	start: number,
}

type Ghost = {
	model: Model,
	speed: number,
	hover: number,
}

local legs: { Leg } = {}
--- One lap in studs. Zero means no route has arrived yet.
local lapLength = 0
--- Distance from the start line to the *arrival* at gate `i`. Gate 1 is the
--- lap line rather than the origin, so it is a whole lap, not nothing.
local reach: { number } = {}

local ghosts: { Ghost } = {}
local ghostFolder: Folder? = nil

--- Rebuilds `legs`, `lapLength` and `reach` from a route the server sent.
local function measure(route: { Vector3 })
	legs = {}
	reach = {}
	lapLength = 0
	local count = #route
	if count < 2 then
		return
	end
	for i, from in route do
		local to = route[if i == count then 1 else i + 1]
		local span = to - from
		local length = span.Magnitude
		table.insert(legs, {
			from = from,
			direction = if length > 0 then span.Unit else Vector3.new(0, 0, 1),
			length = length,
			start = lapLength,
		})
		lapLength += length
		-- Leg `i` runs from gate `i` to gate `i + 1`, so its end is the
		-- distance at which gate `i + 1` is reached.
		reach[if i == count then 1 else i + 1] = lapLength
	end
end

--- Where `distance` studs round the lap is, and which way that is facing.
--- Wraps, so a rival on its second lap needs no special case.
local function pointAt(distance: number): (Vector3, Vector3)
	local d = distance % lapLength
	for _, leg in legs do
		if d <= leg.start + leg.length then
			return leg.from + leg.direction * (d - leg.start), leg.direction
		end
	end
	local last = legs[#legs]
	return last.from + last.direction * last.length, last.direction
end

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
	card.Size = UDim2.fromOffset(240, 126)
	card.Parent = screen
	Theme.corner(card, 6)
	Theme.stroke(card, Theme.ACCENT, 0.55)

	timeLabel = Theme.text("Time", card, 34, Theme.TEXT)
	timeLabel.Font = Theme.FONT_BOLD
	timeLabel.TextXAlignment = Enum.TextXAlignment.Center
	timeLabel.Position = UDim2.fromOffset(0, 8)
	timeLabel.Size = UDim2.new(1, 0, 0, 38)

	--[[
		The standing gets its own line and the accent colour, because it is
		the thing the rest of the card is in service of. A clock alone is a
		time trial; a clock next to "P2/6" is a race, and the number that
		changes when a ghost goes past is the one worth reading.
	]]
	placeLabel = Theme.text("Place", card, 15, Theme.ACCENT)
	placeLabel.Font = Theme.FONT_BOLD
	placeLabel.TextXAlignment = Enum.TextXAlignment.Center
	placeLabel.Position = UDim2.fromOffset(0, 48)
	placeLabel.Size = UDim2.new(1, 0, 0, 19)

	lapLabel = Theme.text("Lap", card, 14, Theme.TEXT)
	lapLabel.Font = Theme.FONT_BOLD
	lapLabel.TextXAlignment = Enum.TextXAlignment.Center
	lapLabel.Position = UDim2.fromOffset(0, 68)
	lapLabel.Size = UDim2.new(0.5, 0, 0, 18)

	gateLabel = Theme.text("Gate", card, 14, Theme.DIM)
	gateLabel.TextXAlignment = Enum.TextXAlignment.Center
	gateLabel.Position = UDim2.new(0.5, 0, 0, 68)
	gateLabel.Size = UDim2.new(0.5, 0, 0, 18)

	parLabel = Theme.text("Par", card, 12, Theme.FAINT)
	parLabel.TextXAlignment = Enum.TextXAlignment.Center
	parLabel.Position = UDim2.fromOffset(0, 88)
	parLabel.Size = UDim2.new(0.5, 0, 0, 16)

	bestLabel = Theme.text("Best", card, 12, Theme.FAINT)
	bestLabel.TextXAlignment = Enum.TextXAlignment.Center
	bestLabel.Position = UDim2.new(0.5, 0, 0, 88)
	bestLabel.Size = UDim2.new(0.5, 0, 0, 16)

	local hint = Theme.text("Hint", card, 11, Theme.DIM)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Position = UDim2.fromOffset(0, 106)
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
-- The grid
--------------------------------------------------------------------------------

local function clearGhosts()
	local existing = ghostFolder
	if existing then
		existing:Destroy()
	end
	ghostFolder = nil
	ghosts = {}
end

--[[
	Stands the field up: one translucent hull per rival, named.

	The nameplate is not decoration. This game has five speeders whose only
	distinguishing feature to a fourteen-year-old is that some of them look
	longer, and the whole point of racing them is to learn which is which --
	"the thing that just went past me was an Aratech Saddle-Bike" is the
	sentence that turns a shop list into a decision. It is the same lesson
	the 2026-08-17 report taught about the panels: a system nobody is told
	about is not a system.
]]
local function buildGhosts(rivals: { Races.Rival })
	clearGhosts()
	if #rivals == 0 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "RaceGhosts"
	folder.Parent = Workspace
	ghostFolder = folder

	for _, rival in rivals do
		if not Ships.exists(rival.ship) then
			continue
		end
		local def = Ships.get(rival.ship)
		local model = ShipModel.buildGhost(rival.ship, GHOST_TRANSPARENCY)
		model.Parent = folder

		local root = model.PrimaryPart
		if root then
			local plate = Instance.new("BillboardGui")
			plate.Name = "Plate"
			plate.AlwaysOnTop = true
			plate.Size = UDim2.fromOffset(200, 20)
			plate.StudsOffset = Vector3.new(0, def.hoverHeight + 4, 0)
			plate.MaxDistance = 500
			plate.Adornee = root
			plate.Parent = model

			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.GothamBold
			name.TextSize = 13
			name.TextColor3 = Palette.SaberBlue
			name.TextStrokeTransparency = 0.35
			name.Text = def.displayName
			name.Size = UDim2.fromScale(1, 1)
			name.Parent = plate
		end

		table.insert(ghosts, { model = model, speed = rival.speed, hover = def.hoverHeight })
	end
end

--- How far round the circuit a rival is at `elapsed`, stopped at the flag.
local function rivalProgress(ghost: Ghost, elapsed: number, laps: number): number
	return math.min(elapsed * ghost.speed, lapLength * laps)
end

--[[
	How far round the circuit the player is.

	Built from the last gate the *server* credited plus the straight line
	still to run to the next one, rather than from anything this client
	decided on its own. It only drives the HUD -- the finishing position is
	worked out again on the server from the clock -- but a readout that
	disagrees with the toast at the flag is worse than no readout.
]]
local function playerProgress(state: State, here: Vector3): number
	local target = reach[state.gateIndex]
	if not target then
		return 0
	end
	local remaining = (Vector3.new(here.X, 0, here.Z) - Vector3.new(
		state.gatePosition.X,
		0,
		state.gatePosition.Z
	)).Magnitude
	return (state.lap - 1) * lapLength + math.max(target - remaining, 0)
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
	local previous = current
	current = state
	screen.Enabled = state ~= nil
	if not state then
		highlight.Enabled = false
		highlight.Adornee = nil
		clearGhosts()
		return
	end

	-- The route and the grid arrive with every push and only change between
	-- runs, so the field is stood up once, on the push that has no run
	-- before it. Rebuilding six models at every gate would be a stutter at
	-- exactly the moment the player is looking at something else.
	if not previous or previous.startedAt ~= state.startedAt then
		measure(state.route)
		buildGhosts(state.rivals)
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

	if lapLength <= 0 then
		return
	end

	--[[
		Drive the field, then read the standings off it.

		One `PivotTo` per rival per frame, on anchored models with no
		constraints and nothing to collide with, which is what `staticHull`
		exists to make cheap. There is no simulation to run because there is
		nothing to simulate: a rival's distance is `elapsed * speed` and its
		heading is the leg it is on.
	]]
	local ahead, behind = math.huge, math.huge
	local place = 1
	local mine = if root and root:IsA("BasePart") then playerProgress(state, root.Position) else 0

	for _, ghost in ghosts do
		local distance = rivalProgress(ghost, elapsed, state.laps)
		local at, facing = pointAt(distance)
		ghost.model:PivotTo(CFrame.lookAt(at + Vector3.new(0, ghost.hover, 0), at + facing))

		local gap = distance - mine
		if gap > 0 then
			place += 1
			ahead = math.min(ahead, gap)
		else
			behind = math.min(behind, -gap)
		end
	end

	--[[
		The gap is signed, and the sign is the whole message: minus means
		somebody is in front of you, plus means somebody is behind. Showing
		the car ahead while you are chasing and the car behind while you are
		leading is the only pair that is always about the position you could
		next lose or gain.
	]]
	local gap = if place > 1
		then `  -{math.floor(ahead)}m`
		elseif behind < math.huge then `  +{math.floor(behind)}m`
		else ""
	placeLabel.Text = `P{place}/{#ghosts + 1}{gap}`
	placeLabel.TextColor3 = if place == 1 then Theme.GOOD else Theme.ACCENT
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
