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
}

type Session = {
	circuit: Circuit,
	--- `Workspace:GetServerTimeNow()` when the start line was crossed. The
	--- client is sent this rather than an elapsed time, so it can run its own
	--- clock at its own frame rate off a number both machines agree on.
	startedAt: number,
	--- Gates crossed since the start line. `laps * #gates` of them is a finish.
	hits: number,
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

--- How often the world is checked for planets that need a gantry drawing.
--- The answer changes when somebody travels, not between frames.
local SWEEP_INTERVAL = 4

local START_COLOUR = Palette.RebelOrange
local GATE_COLOUR = Palette.SaberBlue

local function data()
	return ServiceLoader.get("DataService")
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
	sign.Size = UDim2.fromOffset(300, 46)
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
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.Parent = sign

	local detail = Instance.new("TextLabel")
	detail.BackgroundTransparency = 1
	detail.Font = Enum.Font.Gotham
	detail.TextSize = 13
	detail.TextColor3 = Color3.fromRGB(220, 226, 234)
	detail.TextStrokeTransparency = 0.4
	detail.Text =
		`Drive through to start  --  {Races.LAPS} laps, {#circuit.gates} gates, {#circuit.rivals} rivals, par {Races.format(
			circuit.par
		)}`
	detail.Position = UDim2.fromScale(0, 0.55)
	detail.Size = UDim2.new(1, 0, 0.45, 0)
	detail.Parent = sign
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

local function begin(player: Player, circuit: Circuit)
	sessions[player] = {
		circuit = circuit,
		startedAt = Workspace:GetServerTimeNow(),
		hits = 0,
	}
	armed[player] = false
	push(player, sessions[player])
	Net.fireClient(
		Net.Event.Notify,
		player,
		`{Planets.get(circuit.planet).displayName} Circuit  --  {Races.LAPS} laps against {#circuit.rivals}, par {Races.format(
			circuit.par
		)}`,
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

		Nothing pays out yet -- that is commit 3 -- but a purse is going to
		be settled on this number, and a number the client reports is a
		number the client chooses. It costs one loop over five rivals to
		never have to revisit that.
	]]
	local place = Races.placeFor(time, circuit.length, Races.LAPS, circuit.rivals)
	local field = #circuit.rivals + 1

	local headline = if medal
		then `P{place}/{field}  --  {medal.id}  --  {Races.format(time)}`
		else `P{place}/{field}  --  {Races.format(time)}`
	if improved then
		headline ..= "  --  personal best"
	end
	Net.fireClient(Net.Event.Notify, player, headline, if medal then medal.id else "Reward")
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
			begin(player, circuit)
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
	end)
end

return RaceService
