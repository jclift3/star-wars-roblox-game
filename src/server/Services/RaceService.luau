--!strict
--[[
	RaceService.luau

	Puts a circuit round every world that can field one, and times anybody who
	drives through the start gantry.

	WHY THIS EXISTS
	`Config/Ships.luau` holds fourteen tuned numbers -- `speed`, `acceleration`,
	`turnSpeed`, `hoverHeight` and the rest -- across five speeders, and until
	now nothing in the game ever asked whether any of them were right. There
	was no reason to prefer the Swoop Racer to the Hover Sled except the price
	tag, because the only thing a speeder did was shorten a walk, and every
	speeder shortens a walk. A lap against a clock is the first thing this game
	has ever built that a fast hull is *better at*.

	THE CIRCUIT IS COMPOSED, NOT AUTHORED
	Nine hand-written routes would be nine lists of coordinates that are
	correct until somebody moves a landmark, and then silently wrong -- the
	failure `Radiant.luau` and `Terminals.luau` were both built to avoid. So a
	circuit here is derived from the world that exists: the points of interest
	on the planet, sorted into a ring around the world's own origin, thinned
	so two landmarks that are really one corner do not become two gates, and
	rejected outright if fewer than `Races.MIN_CHECKPOINTS` survive.

	That rejection is a feature. Korriban and the Taris dig are deliberately
	quiet worlds and quiet worlds should not have a racetrack; a planet with
	three spread-out landmarks gets no circuit and no gantry, and nothing warns
	about it because nothing is wrong.

	WHAT THIS FILE OWNS AND WHAT `Config/Races.luau` OWNS
	The world owns the distances -- a checkpoint is a *place*, and a place on
	one of these planets does not exist until `PlanetBuilder` has run. The
	config owns every number that turns a distance into a race: how many laps,
	how wide a gate is, what par is, and which medal a time earns. Nothing here
	is a tuning number and nothing there reads the world.

	YOU START A RACE BY DRIVING THROUGH THE START LINE
	Not by pressing a key at a prompt, and that is not a stylistic choice: as
	of 2026-08-19 `VehicleController` switches `ProximityPromptService.Enabled`
	off for anybody sitting in a ship, precisely so the boarding prompt stops
	following the driver around. A prompt is for somebody standing on their own
	feet. A start line is for somebody already moving, which is the only state
	you can begin a race in anyway.

	THE GRID IS THE CATALOGUE, AND IT DOES NOT KNOW YOU ARE THERE
	Every speeder in `Ships.luau` fields a rival, including the one the
	player is driving, and each holds a fixed fraction of its own hull's top
	speed for the whole race. So a rival's position is a pure function of
	elapsed time -- it cannot see the player, has nowhere to put the
	information if it could, and is therefore incapable of the one thing
	that would ruin it. See `Races.RIVAL_PACE` for why that matters more
	here than it would in a game with strangers in it.

	The rivals are also *ghosts*, drawn by the client that is racing them.
	Both of those are deliberate and both are argued in `ShipModel.buildGhost`
	and in `push` below.

	THE PURSE IS THE ONLY PLACE TWO PLAYERS HAVE TO MEET
	Entry costs a fee, in credits or in a `RacePass` off a corpse, and every
	fee goes into a pot held per planet. A run that beats a ghost of the hull
	it was driven in takes the whole pot; a run that does not leaves its
	stake in it. So the pot is a record of everybody's failed attempts, and
	the next person to drive well takes them all.

	That is what "the boys race each other" is built out of, and it is
	deliberately *not* built out of a countdown, a lobby or a shared start
	line. Two brothers do not have to be on the grid at the same moment to be
	competing: they are paying into one pot on one planet, and whichever of
	them is first to beat his own hull is the one who walks off with the
	other's money. A lobby would have been a new state machine, a new set of
	remotes and a new way for one of them to be left waiting; the pot is a
	number.

	THIS IS NOT ANTI-CHEAT
	`VehicleService` says in writing that the driver simulates their own
	vehicle, so a modified client can be quick, and no amount of server timing
	changes that. `Races.floorFor` rejects the physically absurd and nothing
	more. The real answer is the one the whole project runs on: the two players
	are brothers in one room, and the fastest way to settle it is to race.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Config.Palette)
local Planets = require(Shared.Config.Planets)
local Races = require(Shared.Config.Races)
local Ships = require(Shared.Config.Ships)
local Inventory = require(Shared.Core.Inventory)
local Net = require(Shared.Core.Net)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Types = require(Shared.Types)

type PlayerProfile = Types.PlayerProfile

local RaceService = {
	name = "RaceService",
	-- After SecretService (58) and with the rest of the world-dressing block.
	-- Nothing depends on this and this depends on nothing at boot: the first
	-- circuit is composed lazily, the first time somebody stands on a planet
	-- that has been built.
	priority = 59,
}

--------------------------------------------------------------------------------
-- Shape
--------------------------------------------------------------------------------

type Gate = {
	index: number,
	poi: string,
	--- The landmark's marker, which is where the gate *counts*.
	position: Vector3,
	--- The same place dropped onto the road, which is where the gantry is
	--- built and the line a rival drives. Resolved once, here, rather than
	--- by a raycast per rival per frame.
	ground: Vector3,
}

type Circuit = {
	planet: string,
	gates: { Gate },
	--- One lap, closed: the last gate back round to the first is included.
	length: number,
	par: number,
	floor: number,
	--- The grid, in the order `Races.rivals` returns it. One per speeder in
	--- the catalogue, so it is the same field on every planet and only the
	--- distance changes.
	rivals: { Races.Rival },
	--- The gantry's second line, kept so the purse on it can be rewritten
	--- when it changes. Nil until the circuit has been drawn.
	sign: TextLabel?,
	--- The gantry's last line: the fastest lap anyone anywhere has driven
	--- here. Nil until the circuit has been drawn, hidden until there is one.
	record: TextLabel?,
}

type Session = {
	circuit: Circuit,
	--- `Workspace:GetServerTimeNow()` when the start line was crossed. The
	--- client is sent this rather than an elapsed time, so it can run its own
	--- clock at its own frame rate off a number both machines agree on.
	startedAt: number,
	--- Gates crossed since the start line. `laps * #gates` of them is a finish.
	hits: number,
	--[[
		The hull this run was started in, captured at the line.

		Read here rather than at the flag because it is what the payout is
		measured against, and `profile.equipped.ship` can be changed mid-run.
		A player who could swap to a Hover Sled on the last straight would be
		paid for beating a Hover Sled's ghost in a Swoop Racer.
	]]
	ship: string,
	--[[
		And what was bolted to it, captured at the same moment and for the
		same reason.

		The ghost is scaled by the fitted engine -- see `Races.ghostTime` --
		so a run started bare and finished with a Mk V would otherwise be
		paid against the slower ghost. That is not reachable today, since
		there is no vendor on a circuit, but "the hull cannot change mid-run"
		and "its parts can" is not a pair of rules worth holding in a file
		that already explains why the first one exists.
	]]
	fitted: { [string]: string }?,
}

--- Circuits already composed, keyed by planet.
local circuits: { [string]: Circuit } = {}
--[[
	Worlds that have been looked at, whether or not they yielded a circuit.

	A second table rather than a `Circuit | false` in the first one, because
	"checked and has no circuit" has to be distinguishable from "not looked at
	yet" -- Korriban is meant to come back empty, and without this the sweep
	would re-walk its landmarks every four seconds forever.
]]
local checked: { [string]: boolean } = {}
local sessions: { [Player]: Session } = {}

--[[
	Who is standing clear of a start line, and so may cross one.

	Without this, finishing a race would immediately begin another one --
	you are, by definition, sitting on the start line at the moment you cross
	it -- and so would rolling to a stop under the gantry. A player is armed
	only after they have been more than a gate's width away from gate one.
]]
local armed: { [Player]: boolean } = {}

--[[
	What is staked on each planet's circuit, by planet id.

	Server memory, not a DataStore. A shared pot is the one piece of state in
	this game that belongs to nobody, and persisting it would mean a global
	key and a write path that no other system here has -- for a number whose
	only job is to make the next race worth more than the last one. A restart
	empties it, and nobody's balance moves when it does: those credits were
	spent at the moment they were staked. The most a restart can cost anybody
	is a bigger prize they had not won yet.
]]
local purses: { [string]: number } = {}

--- How often the world is checked for planets that need a gantry drawing.
--- The answer changes when somebody travels, not between frames.
local SWEEP_INTERVAL = 4

local START_COLOUR = Palette.RebelOrange
local GATE_COLOUR = Palette.SaberBlue

local function data()
	return ServiceLoader.get("DataService")
end

local function global()
	return ServiceLoader.get("GlobalService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

--------------------------------------------------------------------------------
-- Composing a circuit from the world
--------------------------------------------------------------------------------

local function folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

--- Drops `position` onto whatever solid ground is under it.
local function onGround(position: Vector3): Vector3
	local drawn = Workspace:FindFirstChild("Races")
	groundParams.FilterDescendantsInstances = if drawn then { drawn } else {}
	local hit = Workspace:Raycast(position + Vector3.new(0, 80, 0), Vector3.new(0, -400, 0), groundParams)
	return if hit then hit.Position else position
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

--[[
	The circuit this planet's landmarks add up to, or nil if they do not add
	up to one.

	Sorted by bearing around the world's own origin rather than by any
	shortest-path search. A travelling-salesman route through nine landmarks
	would be a better *route* and a worse *circuit*: it can cross itself, and
	a lap that crosses itself is a lap where the gate you want and the gate
	you want next are both in front of you. A ring cannot do that.
]]
local function compose(planetId: string): Circuit?
	local def = Planets.get(planetId)
	-- Coruscant has no ground to race on, and `hasWalkableGround` is the one
	-- switch that says so. A skylane circuit is a different game.
	if not def.hasWalkableGround then
		return nil
	end

	local root = Workspace:FindFirstChild("POI")
	local planetFolder = root and root:FindFirstChild(planetId)
	if not planetFolder then
		-- The world has not been built yet. The sweep will come back.
		return nil
	end

	local origin = Planets.originFor(planetId)
	type Candidate = { poi: string, position: Vector3, bearing: number }
	local candidates: { Candidate } = {}
	for _, poi in def.pointsOfInterest do
		local marker = planetFolder:FindFirstChild(poi.id)
		if not (marker and marker:IsA("BasePart")) then
			continue
		end
		local offset = flat(marker.Position - origin)
		if offset.Magnitude < 1 then
			continue
		end
		table.insert(candidates, {
			poi = poi.id,
			position = marker.Position,
			bearing = math.atan2(offset.Z, offset.X),
		})
	end

	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return a.bearing < b.bearing
	end)

	--[[
		Two landmarks closer together than `MIN_GATE_SPACING` are one corner.

		Walked forwards keeping the first of each cluster, then the last
		survivor is measured against the first as well -- because the route
		is a loop, and without that check a planet whose first and last
		landmarks sit on the same bearing would close the lap with two gates
		on top of each other.
	]]
	local kept: { Candidate } = {}
	for _, candidate in candidates do
		local previous = kept[#kept]
		if previous and (flat(candidate.position - previous.position)).Magnitude < Races.MIN_GATE_SPACING then
			continue
		end
		table.insert(kept, candidate)
	end
	if #kept > 1 then
		local first, last = kept[1], kept[#kept]
		if (flat(last.position - first.position)).Magnitude < Races.MIN_GATE_SPACING then
			table.remove(kept)
		end
	end

	if #kept < Races.MIN_CHECKPOINTS then
		return nil
	end

	local gates: { Gate } = {}
	local length = 0
	for i, candidate in kept do
		table.insert(gates, {
			index = i,
			poi = candidate.poi,
			position = candidate.position,
			ground = onGround(candidate.position),
		})
		local nextOne = kept[if i == #kept then 1 else i + 1]
		length += (flat(nextOne.position - candidate.position)).Magnitude
	end

	return {
		planet = planetId,
		gates = gates,
		length = length,
		par = Races.parFor(length, Races.LAPS),
		floor = Races.floorFor(length, Races.LAPS),
		rivals = Races.rivals(),
	}
end

--------------------------------------------------------------------------------
-- Drawing a gate
--------------------------------------------------------------------------------

local function pylon(name: string, parent: Instance, cframe: CFrame, size: Vector3, colour: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	-- Nothing about a gate is solid. It is a place, not a wall, and a wall at
	-- the apex of a corner is a way to lose a race to the scenery.
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = size
	part.Color = colour
	part.Material = Enum.Material.Neon
	part.CFrame = cframe
	part.Parent = parent
	return part
end

--[[
	Stands one gate in the world.

	`across` is the direction the gate is *wide* in -- perpendicular to the
	line the racer is travelling as they arrive, so the two posts frame the
	route rather than standing along it.
]]
local function drawGate(gate: Gate, across: Vector3, parent: Folder, circuit: Circuit)
	local model = Instance.new("Model")
	model.Name = `Gate{gate.index}`
	model.Parent = parent

	local start = gate.index == 1
	local colour = if start then START_COLOUR else GATE_COLOUR
	local ground = gate.ground
	local reach = across * Races.GATE_RADIUS
	local height = if start then 30 else 22

	local left = pylon(
		"Left",
		model,
		CFrame.new(ground + reach + Vector3.new(0, height * 0.5, 0)),
		Vector3.new(2.4, height, 2.4),
		colour
	)
	pylon(
		"Right",
		model,
		CFrame.new(ground - reach + Vector3.new(0, height * 0.5, 0)),
		Vector3.new(2.4, height, 2.4),
		colour
	)
	pylon(
		"Bar",
		model,
		CFrame.lookAt(
			ground + Vector3.new(0, height - 1.2, 0),
			ground + across + Vector3.new(0, height - 1.2, 0)
		),
		Vector3.new(2, 2, Races.GATE_RADIUS * 2),
		colour
	)
	model.PrimaryPart = left

	--[[
		The gantry says what it is, and it says par.

		The lesson from the 2026-08-17 report: a system the player is never
		told about does not exist. Six panels were finished and bound to
		letters nobody had been told. A start line with no sign on it is a
		strange blue arch somebody drove past.
	]]
	if not start then
		return
	end

	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.AlwaysOnTop = true
	sign.Size = UDim2.fromOffset(300, 82)
	sign.StudsOffset = Vector3.new(0, 5, 0)
	sign.MaxDistance = 600
	sign.Adornee = left
	sign.Parent = model

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = START_COLOUR
	title.TextStrokeTransparency = 0.3
	title.Text = `{Planets.get(circuit.planet).displayName} Circuit  --  START`
	title.Size = UDim2.new(1, 0, 0, 26)
	title.Parent = sign

	--[[
		Two lines, not one, and the split is by what changes.

		The shape of the race -- laps, field, par -- is fixed for the life of
		the world and written once. The price and the pot move while you are
		standing there, and that is the line worth re-reading. Sixty-odd
		characters on one row at 13px would also have run off a 300px sign.
	]]
	local shape = Instance.new("TextLabel")
	shape.BackgroundTransparency = 1
	shape.Font = Enum.Font.Gotham
	shape.TextSize = 13
	shape.TextColor3 = Color3.fromRGB(220, 226, 234)
	shape.TextStrokeTransparency = 0.4
	shape.Position = UDim2.fromOffset(0, 26)
	shape.Size = UDim2.new(1, 0, 0, 18)
	shape.Text = `{Races.LAPS} laps  --  {#circuit.rivals} rivals  --  par {Races.format(circuit.par)}`
	shape.Parent = sign

	local money = Instance.new("TextLabel")
	money.BackgroundTransparency = 1
	money.Font = Enum.Font.GothamBold
	money.TextSize = 13
	money.TextColor3 = Palette.SaberYellow
	money.TextStrokeTransparency = 0.4
	money.Position = UDim2.fromOffset(0, 44)
	money.Size = UDim2.new(1, 0, 0, 18)
	money.Parent = sign
	circuit.sign = money

	--[[
		The fourth row, and the only thing on this arch that is not about you.

		A lap time was, until now, a number one player could see in one HUD.
		This is the same number claimed out loud, across every server the game
		will ever run, and it is on the arch rather than in a panel for the
		reason the purse is: it has to be readable in the seconds before you
		decide to go, because it is the thing you are deciding to go after.

		Hidden rather than blanked when there is no record. "RECORD --" reads
		as a board that is broken; a row that is not there reads as a record
		that has not been set, which is a thing a player can do something
		about.
	]]
	local record = Instance.new("TextLabel")
	record.BackgroundTransparency = 1
	record.Font = Enum.Font.Gotham
	record.TextSize = 13
	record.TextColor3 = GATE_COLOUR
	record.TextStrokeTransparency = 0.4
	record.Position = UDim2.fromOffset(0, 62)
	record.Size = UDim2.new(1, 0, 0, 18)
	record.Visible = false
	record.Parent = sign
	circuit.record = record
end

--[[
	Rewrites the gantry's second line.

	The purse is on the arch rather than only in the HUD because it is the
	one number that has to be readable *before* you commit to paying. A pot
	you can only see once you are racing for it is a pot nobody chose to race
	for, and the 2026-08-17 lesson was that a thing the player is never told
	about does not exist.
]]
local function refreshSign(circuit: Circuit)
	local label = circuit.sign
	if not label then
		return
	end
	local purse = purses[circuit.planet] or 0
	label.Text = `ENTRY {Races.ENTRY_FEE} cr  --  PURSE {purse} cr`

	--[[
		`best` never yields and never blocks -- it answers from cache and goes
		and fetches in the background when that is stale. Which is why this is
		called from the four-second sweep as well as from the two moments the
		purse moves: the first read after a server boots is always nil, and a
		record that only appeared once somebody paid to race would be a record
		nobody could see before deciding whether to.
	]]
	local row = circuit.record
	if not row then
		return
	end
	local top = global().best(Races.boardFor(circuit.planet))
	row.Visible = top ~= nil
	if top then
		row.Text = `RECORD  {Races.format(Races.fromBoardValue(top.value))}  --  {top.name}`
	end
end

--- Draws every gate of a circuit, once. Idempotent, like `PickupService.ensure`.
local function drawCircuit(circuit: Circuit)
	local parent = folder(circuit.planet, folder("Races", Workspace))
	if #parent:GetChildren() > 0 then
		return
	end
	local gates = circuit.gates
	for i, gate in gates do
		local previous = gates[if i == 1 then #gates else i - 1]
		local nextOne = gates[if i == #gates then 1 else i + 1]
		local along = flat(nextOne.position - previous.position)
		-- Two gates on top of each other cannot happen (`MIN_GATE_SPACING`),
		-- but a three-gate circuit where the neighbours are symmetric about
		-- this one can still give a zero-length line. Fall back to the
		-- bearing out of town, which is never zero.
		if along.Magnitude < 1 then
			along = flat(gate.position - Planets.originFor(circuit.planet))
		end
		local direction = along.Unit
		drawGate(gate, Vector3.new(-direction.Z, 0, direction.X), parent, circuit)
	end
	refreshSign(circuit)
end

--------------------------------------------------------------------------------
-- Lookups
--------------------------------------------------------------------------------

--- The circuit for a planet, composing and drawing it on first ask.
local function circuitFor(planetId: string): Circuit?
	if checked[planetId] then
		return circuits[planetId]
	end
	local built = compose(planetId)
	--[[
		A planet with no POI folder yet is *not* marked checked: the world is
		built lazily by `WorldService.ensure`, so the first sweep after
		somebody lands can legitimately find nothing there. `compose` returns
		nil for both "not built yet" and "not enough landmarks", so the
		cheap, correct discriminator is whether the folder exists at all.
	]]
	local root = Workspace:FindFirstChild("POI")
	if not (root and root:FindFirstChild(planetId)) then
		return nil
	end
	checked[planetId] = true
	if built then
		circuits[planetId] = built
		drawCircuit(built)
	end
	return built
end

--- The line a rival drives: the gate ring at road level, closed implicitly
--- by the client that walks it. Road level rather than marker level because
--- a marker floats three studs up and a speeder does not.
local function route(circuit: Circuit): { Vector3 }
	local out: { Vector3 } = {}
	for _, gate in circuit.gates do
		table.insert(out, gate.ground)
	end
	return out
end

--- Where a player is right now, or nil if they have no body.
local function positionOf(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

--[[
	Whether this player is aboard something that can race.

	A racer has to be *driving*, not riding: a passenger in their brother's
	speeder would otherwise post a time for a lap somebody else drove. Only
	the pilot's seat is a `VehicleSeat` -- see `ShipModel` -- so this is the
	whole test.
]]
local function driving(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	local seat = humanoid.SeatPart
	return seat ~= nil and seat:IsA("VehicleSeat")
end

--------------------------------------------------------------------------------
-- Running a race
--------------------------------------------------------------------------------

--[[
	What the client is told, or nil when there is nothing to tell.

	`startedAt` rather than an elapsed time: both machines can read
	`GetServerTimeNow`, so the client runs the clock itself at its own frame
	rate and this event only has to fire when something actually changes --
	a gate, a lap, the end. A per-frame time remote would be sixty packets a
	second to save one subtraction.
]]
local function push(player: Player, session: Session?)
	if not session then
		Net.fireClient(Net.Event.RaceState, player, nil)
		return
	end
	local circuit = session.circuit
	local count = #circuit.gates
	local target = circuit.gates[(session.hits + 1) % count + 1]
	local profile = data().get(player)

	--[[
		THE ROUTE AND THE GRID GO OVER THE WIRE, THE RIVALS' POSITIONS DO NOT

		A rival's position is `elapsed * speed` along this polyline, and the
		client already has `startedAt`. Sending the route and the speeds once
		per gate is a handful of numbers; sending six hulls' positions every
		frame is a remote firing sixty times a second to deliver something
		the receiver could have worked out from what it was already told.
		Same argument as the clock, one field up.

		It also means the *drawing* of the rivals is client work -- see
		`RaceController`. Two brothers racing the same circuit at different
		moments each see their own grid, instead of two overlapping fields of
		ghosts belonging to somebody else's lap.
	]]
	Net.fireClient(Net.Event.RaceState, player, {
		planet = circuit.planet,
		startedAt = session.startedAt,
		par = circuit.par,
		laps = Races.LAPS,
		lap = math.min(session.hits // count + 1, Races.LAPS),
		gateCount = count,
		gateIndex = target.index,
		gatePosition = target.position,
		best = profile and profile.raceBests[circuit.planet],
		route = route(circuit),
		rivals = circuit.rivals,
		--[[
			The two numbers the money is made of, sent because the player is
			currently spending an evening on them.

			`target` is what a ghost of the hull under them does, which is
			the time that has to be beaten to be paid -- see
			`Races.ghostTime` for why it is that and not the finishing
			position. The HUD shows both, because "am I winning" and "am I
			getting paid" are genuinely different questions here.
		]]
		purse = purses[circuit.planet] or 0,
		target = Races.ghostTime(session.ship, circuit.length, Races.LAPS, session.fitted),
	})
end

local function abandon(player: Player, reason: string)
	if not sessions[player] then
		return
	end
	sessions[player] = nil
	push(player, nil)
	Net.fireClient(Net.Event.Notify, player, `Run abandoned -- {reason}`, "MissionFailed")
end

--[[
	Takes the entry fee. Returns what it was paid in, or nil if it could not
	be paid at all.

	A pass first, always. It is worth exactly one entry and nothing else, so
	spending credits while holding one would be spending the more useful of
	the two -- and the player would have to notice that themselves, every
	time, at a start line they are already driving through.
]]
local function chargeEntry(player: Player): string?
	local paid = false
	data().update(player, function(profile: PlayerProfile)
		-- Against what `remove` actually took, never against what was asked
		-- for. The standing rule for this API, and the one place it could
		-- silently hand out a free race.
		paid = Inventory.remove(profile.inventory, Races.PASS_ITEM, 1) == 1
	end)
	if paid then
		return "pass"
	end
	if progression().spendCredits(player, Races.ENTRY_FEE) then
		return "credits"
	end
	return nil
end

local function begin(player: Player, circuit: Circuit, ship: string, paidWith: string)
	local entrant = data().get(player)
	sessions[player] = {
		circuit = circuit,
		startedAt = Workspace:GetServerTimeNow(),
		hits = 0,
		ship = ship,
		fitted = if entrant then entrant.shipParts[ship] else nil,
	}
	armed[player] = false

	--[[
		A pass stakes the same as credits do, and that is the one place a
		race mints anything into the pot that nobody paid for.

		The alternative -- a pass entering for free -- is worse in the way
		that matters here: it would make the pass a free shot at money other
		people put in, so the correct play would be to farm passes and never
		spend a credit. Two brothers in one room find that in an afternoon.
		"Credits or a pass" has to mean the two are worth the same thing, and
		the drop rate is what bounds the faucet.
	]]
	purses[circuit.planet] = (purses[circuit.planet] or 0) + Races.ENTRY_FEE
	refreshSign(circuit)

	push(player, sessions[player])
	local cost = if paidWith == "pass" then "1 Race Pass" else `{Races.ENTRY_FEE} cr`
	Net.fireClient(
		Net.Event.Notify,
		player,
		`{Planets.get(circuit.planet).displayName} Circuit  --  {cost} staked, purse {purses[circuit.planet]} cr`,
		"Reward"
	)
end

local function finish(player: Player, session: Session)
	local circuit = session.circuit
	local time = Workspace:GetServerTimeNow() - session.startedAt
	sessions[player] = nil
	armed[player] = false
	push(player, nil)

	--[[
		A time under the floor is thrown away rather than argued with.

		`Races.floorFor` is the fastest hull in the game held flat out in a
		straight line for the whole route, which no corner allows. Anything
		quicker did not happen, and the honest thing to do with a number that
		did not happen is not record it.
	]]
	if time < circuit.floor then
		Net.fireClient(
			Net.Event.Notify,
			player,
			`Run discarded -- {Races.format(time)} is not possible`,
			"Error"
		)
		return
	end

	local medal = Races.medalFor(time, circuit.par)
	local improved = false
	data().update(player, function(profile: PlayerProfile)
		local best = profile.raceBests[circuit.planet]
		if not best or time < best then
			profile.raceBests[circuit.planet] = time
			improved = true
		end
	end)

	--[[
		The finishing position is worked out here, from the same arithmetic
		the client drew the ghosts with, and never read back off the client.
		A number the client reports is a number the client chooses, and this
		one now has money on it.
	]]
	local place = Races.placeFor(time, circuit.length, Races.LAPS, circuit.rivals)
	local field = #circuit.rivals + 1

	--[[
		Beating a ghost of your own hull is what pays, and `Races.ghostTime`
		argues at length why it is that rather than the position or the
		medal. Both of those are won by owning a faster speeder; this one is
		the same difficulty in all five.
	]]
	local target = Races.ghostTime(session.ship, circuit.length, Races.LAPS, session.fitted)
	local won = target ~= nil and time <= target
	local payout = 0
	if won then
		--[[
			`raw`, so the Scavenger multiplier does not touch it. Most of
			this is other players' entry fees, and a stat that mints a
			percentage on top of somebody else's money would make the pot
			bigger coming out than it was going in.
		]]
		payout = (purses[circuit.planet] or 0) + Races.prizeFor(medal)
		purses[circuit.planet] = 0
		refreshSign(circuit)
		progression().awardCredits(player, payout, true)
	end

	local headline = if medal
		then `P{place}/{field}  --  {medal.id}  --  {Races.format(time)}`
		else `P{place}/{field}  --  {Races.format(time)}`
	if improved then
		headline ..= "  --  personal best"
	end
	--[[
		A losing run says what it lost to, by name and by how much.

		"You did not win" is a `warn()` aimed at a fourteen-year-old, and the
		2026-08-19 note on that is explicit. The hull's own ghost is a thing
		he can picture, and the gap to it is the thing he will try to close.
	]]
	if won then
		headline ..= `  --  purse {payout} cr`
	elseif target then
		local name = if Ships.exists(session.ship) then Ships.get(session.ship).displayName else session.ship
		headline ..= `  --  no purse, {name} ghost by {Races.format(time - target)}`
	end
	Net.fireClient(Net.Event.Notify, player, headline, if medal then medal.id else "Reward")

	--[[
		And last, the galaxy board. In a `task.spawn` because posting yields on
		a DataStore, and everything above it is the part the player is waiting
		for: a flag that hung for a second on a throttled web call would make
		the network's bad afternoon look like the race's.

		Posted after the floor check, never before it -- the one number this
		game keeps forever must not be one it has already decided did not
		happen.
	]]
	task.spawn(function()
		global().post(Races.boardFor(circuit.planet), player, Races.toBoardValue(time), true)
		refreshSign(circuit)
	end)
end

--[[
	One frame of every live run, plus the check that starts one.

	Every frame rather than on a sweep: the Swoop Racer does 205 studs a
	second, so a check even a tenth of a second apart would let a gate pass
	between two samples. The work is one distance test per player.
]]
local function step()
	for player, session in sessions do
		local here = positionOf(player)
		if not here then
			continue
		end
		if not driving(player) then
			abandon(player, "you are on foot")
			continue
		end
		if Workspace:GetServerTimeNow() - session.startedAt > session.circuit.par * Races.ABANDON_MULT then
			abandon(player, "out of time")
			continue
		end

		local circuit = session.circuit
		local count = #circuit.gates
		local target = circuit.gates[(session.hits + 1) % count + 1]
		if (flat(here - target.position)).Magnitude > Races.GATE_RADIUS then
			continue
		end

		session.hits += 1
		if session.hits >= count * Races.LAPS then
			finish(player, session)
		else
			push(player, session)
		end
	end

	for _, player in Players:GetPlayers() do
		if sessions[player] then
			continue
		end
		local profile = data().get(player)
		local here = positionOf(player)
		if not (profile and here) then
			continue
		end
		local circuit = circuitFor(profile.currentPlanet)
		if not circuit then
			continue
		end
		local toStart = (flat(here - circuit.gates[1].position)).Magnitude
		if toStart > Races.GATE_RADIUS then
			armed[player] = true
		elseif armed[player] and driving(player) then
			--[[
				A refusal disarms as well as explaining itself.

				This runs every Heartbeat, so a player sitting under the
				gantry with no money would otherwise be told sixty times a
				second that he has no money. Clearing `armed` means the
				message arrives once and does not come back until he has
				driven a gate's width away and had another go, which is also
				the only action that could have changed the answer.
			]]
			local ship = profile.equipped.ship
			if not (ship and Ships.exists(ship)) then
				armed[player] = false
				Net.fireClient(Net.Event.Notify, player, "You need a speeder to race", "Error")
			elseif Ships.isStarship(ship) then
				-- A hull that has stopped looking for the ground can fly the
				-- straight line between two gates, so there is no field to
				-- put it in and no ghost of it to beat. Refused at the line
				-- rather than at the flag, where it would already have paid.
				armed[player] = false
				Net.fireClient(Net.Event.Notify, player, "A starship cannot enter -- take a speeder", "Error")
			else
				local paidWith = chargeEntry(player)
				if paidWith then
					begin(player, circuit, ship, paidWith)
				else
					armed[player] = false
					Net.fireClient(
						Net.Event.Notify,
						player,
						`Entry is {Races.ENTRY_FEE} cr or a Race Pass -- you have neither`,
						"Error"
					)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RaceService.init()
	for _, problem in Races.validate() do
		warn(`[RaceService] race config: {problem}`)
	end
end

function RaceService.start()
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
		armed[player] = nil
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		step()

		accumulator += dt
		if accumulator < SWEEP_INTERVAL then
			return
		end
		accumulator = 0

		-- Composing is what draws the gantry, so a world nobody has raced on
		-- yet still has its circuit standing by the time somebody wanders
		-- out to it.
		for _, player in Players:GetPlayers() do
			local profile = data().get(player)
			if profile then
				local ok, err = pcall(circuitFor :: any, profile.currentPlanet)
				if not ok then
					warn(`[RaceService] failed to compose "{profile.currentPlanet}": {err}`)
				end
			end
		end

		-- And redraw the arches, which is how the galaxy record gets onto a
		-- sign that was built before the first board read came back. Cheap:
		-- `best` is a table lookup and there are at most nine circuits.
		for _, circuit in circuits do
			refreshSign(circuit)
		end
	end)
end

return RaceService
