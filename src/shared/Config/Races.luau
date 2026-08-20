--!strict
--[[
	Races.luau

	The rules of a circuit. Not the circuits themselves -- those are composed
	from the world at runtime by RaceService, for a reason worth stating up
	front because the plan said otherwise.

	WHY THE ROUTE IS NOT IN THIS FILE
	ROADMAP 4.6 said circuits would compose here at require time, the way
	`Radiant` composes its missions. They cannot. A checkpoint is a *place*,
	and a place on one of these planets does not exist until `PlanetBuilder`
	has run: POI markers are emitted into `Workspace/POI/<Planet>` at
	positions that fall out of the generator's seed, the district fan and the
	authored street grid. Re-deriving those coordinates here would mean a
	second copy of the generator's arithmetic, correct until the day somebody
	moves a landmark and silently wrong after it.

	So the split is: **the world owns the distances, this file owns every
	number that turns a distance into a race.** Nothing here reads the world,
	and nothing here is authored per planet.

	NOTHING IN THIS FILE IS A TIME
	Par is a function of route length and of the hulls that actually exist,
	both of which the game already knows. An authored par is a number that is
	right on the day it is written and a lie the first time somebody retunes
	a speeder -- the failure `Weapons.maxima` and `Planets.bandFor` were both
	built to avoid. The same goes for the floor time below the finish line:
	it is what the fastest hull in the game could physically do, so it moves
	when the catalogue moves.
]]

local Items = require(script.Parent.Items)
local Ships = require(script.Parent.Ships)

local Races = {}

export type Medal = {
	id: string,
	--- Multiple of par at or under which this medal is awarded.
	scale: number,
	colour: Color3,
	--- Multiple of the entry fee this medal pays back on a winning run. See
	--- `Races.prizeFor`; it lives on the medal so there is one table rather
	--- than a second one keyed by medal id that could drift out of step.
	prize: number,
}

--------------------------------------------------------------------------------
-- Shape of a circuit
--------------------------------------------------------------------------------

--- Two, not one. A single lap is a commute; two is the first number at which
--- knowing the corners is worth more than knowing the way.
Races.LAPS = 2

--[[
	Fewer gates than this is not a lap, it is a there-and-back.

	A planet that cannot field four spread-out landmarks simply has no
	circuit, and RaceService says so once at boot rather than drawing a
	degenerate one. Korriban and the Taris dig are deliberately quiet worlds;
	quiet worlds not having a racetrack is the right answer.
]]
Races.MIN_CHECKPOINTS = 4

--[[
	How close the hull has to get to a gate for it to count.

	Generous on purpose. A gate you can miss at 180 studs a second while
	looking at the horizon is a gate that fails the player rather than tests
	them, and the ordering rule below is what stops a wide gate becoming a
	shortcut.
]]
Races.GATE_RADIUS = 26

--- Two landmarks closer together than this are one corner, not two, so only
--- the first of them becomes a gate.
Races.MIN_GATE_SPACING = 220

--[[
	The fraction of a hull's top speed actually held around a circuit.

	Nobody drives a lap flat out: `VehicleController` ramps through
	`acceleration` out of every corner and `REVERSE_FRACTION` punishes
	overshooting one. Sixty-two hundredths is the figure that makes par feel
	like a good clean lap in a middling speeder -- beatable, but not by
	accident, which is the only property par has to have.
]]
local PACE = 0.62

--- A run this far past par has been abandoned, whatever the player thinks.
Races.ABANDON_MULT = 3

--[[
	The fraction of its own hull's top speed a rival holds.

	Lower than `PACE` on purpose, and the gap between the two is the entire
	difficulty of the field. A rival drives the gate polyline exactly: the
	shortest legal line round the circuit, taken without ever overshooting a
	corner or lifting for one. A human cannot do that, so a rival held at the
	same fraction a human is credited with would be unbeatable in the same
	hull, and "unbeatable in the same hull" makes the whole grid scenery.

	At 0.56 against par's 0.62 the shape comes out right on today's
	catalogue: a player who hits par finishes second, behind the Swoop
	Racer's ghost and ahead of everything else. That is the two things the
	field has to say at once -- *drive better* and *buy a better speeder*.

	THERE IS NO RUBBER-BANDING AND THERE WILL NOT BE
	A rival's position is a pure function of elapsed time and its own hull's
	speed. It does not know where the player is and cannot be told. Catch-up
	logic is the thing that makes a win feel unearned, and the two players
	this is being built for are fourteen years old and share a room: a field
	that is being polite to them is a field they will have worked out inside
	three races, and every race after that is worth nothing.
]]
local RIVAL_PACE = 0.56

--[[
	Bands, not a leaderboard.

	A server-wide table would mean an `OrderedDataStore` -- a subsystem this
	project has never used -- in order to rank two brothers. Medals give the
	same thing a leaderboard gives (a reason to run it again) without a
	second player having to exist.
]]
local MEDALS: { Medal } = {
	{ id = "Gold", scale = 0.9, colour = Color3.fromRGB(214, 176, 72), prize = 3 },
	{ id = "Silver", scale = 1.0, colour = Color3.fromRGB(196, 202, 212), prize = 2 },
	{ id = "Bronze", scale = 1.18, colour = Color3.fromRGB(186, 124, 74), prize = 1.5 },
}
Races.MEDALS = MEDALS

--------------------------------------------------------------------------------
-- What the catalogue of hulls implies
--------------------------------------------------------------------------------

--[[
	The speeds a race can actually be run at, resolved once from `Ships`.

	Starships are excluded, and not as a technicality: a hull that has
	stopped looking for the ground can fly the straight line between two
	gates at altitude, which is not the game being played. Ground racing is
	the only racing, so a starship is the wrong reference for par and the
	wrong reference for the floor.
]]
local function speederSpeeds(): { number }
	local out: { number } = {}
	for _, id in Ships.ids() do
		if not Ships.isStarship(id) then
			table.insert(out, Ships.get(id).speed)
		end
	end
	table.sort(out)
	return out
end

local SPEEDS = speederSpeeds()

--- Median rather than mean: one outlier hull should move par by nothing.
local MEDIAN_SPEED = if #SPEEDS > 0 then SPEEDS[math.ceil(#SPEEDS / 2)] else 1
local TOP_SPEED = if #SPEEDS > 0 then SPEEDS[#SPEEDS] else 1

--------------------------------------------------------------------------------
-- The grid
--------------------------------------------------------------------------------

export type Rival = {
	--- The hull it is a ghost of. Also its name on the nameplate.
	ship: string,
	--- Studs per second, held for the whole race. See `RIVAL_PACE`.
	speed: number,
}

--[[
	The field: one rival per speeder in the catalogue, slowest first.

	Not a count, not a difficulty setting and not a roster anybody typed.
	The grid *is* the catalogue, which buys three things at once.

	It fills itself. Adding a sixth speeder to `Ships.luau` puts a sixth
	speeder on the grid, which is the only way a derived system stays true --
	the same argument `Weapons.maxima` and `Planets.bandFor` are built on.

	It makes a finishing position mean something specific. Beating the
	Aratech means you went round faster than an Aratech goes round, so
	"third of six in a Hover-Sled" is a real sentence about a real thing,
	which "third of six" against an invented field is not.

	And it includes a ghost of the hull the player is driving, deliberately.
	That one is the benchmark the whole feature exists for: this game has
	fourteen tuned handling numbers per speeder and has never once asked
	whether a player could get more out of them than the numbers alone give.
	Beating your own ghost is that question, asked directly.
]]
function Races.rivals(): { Rival }
	local out: { Rival } = {}
	for _, id in Ships.ids() do
		if not Ships.isStarship(id) then
			table.insert(out, { ship = id, speed = Ships.get(id).speed * RIVAL_PACE })
		end
	end
	table.sort(out, function(a: Rival, b: Rival): boolean
		return a.speed < b.speed
	end)
	return out
end

--- What a rival finishes `laps` of a `length`-stud circuit in. Analytic,
--- because a rival never slows down, so there is nothing to simulate.
function Races.rivalTime(speed: number, length: number, laps: number): number
	return (length * laps) / speed
end

--- Where a finish of `time` places in the field. 1 is a win.
function Races.placeFor(time: number, length: number, laps: number, rivals: { Rival }): number
	local ahead = 0
	for _, rival in rivals do
		if Races.rivalTime(rival.speed, length, laps) < time then
			ahead += 1
		end
	end
	return ahead + 1
end

--------------------------------------------------------------------------------
-- Derived times
--------------------------------------------------------------------------------

--- Seconds a good clean lap of `length` studs should take, `laps` times over.
function Races.parFor(length: number, laps: number): number
	return (length * laps) / (MEDIAN_SPEED * PACE)
end

--[[
	Seconds below which a finish is not physically possible.

	The fastest hull in the game, held at its top speed, in a straight line,
	for the whole route -- which no corner allows and no acceleration curve
	reaches. This is not anti-cheat and is not pretending to be: the driver
	simulates their own vehicle (`VehicleService` says so in writing), so a
	modified client can be quick. It is a floor under the absurd, and it is
	derived so that adding a faster speeder moves it rather than breaking it.
]]
function Races.floorFor(length: number, laps: number): number
	return (length * laps) / TOP_SPEED
end

--- The best medal `time` earns against `par`, or nil for a finish outside
--- the bands. Walks in order, so the table's order is the ranking.
function Races.medalFor(time: number, par: number): Medal?
	for _, medal in Races.MEDALS do
		if time <= par * medal.scale then
			return medal
		end
	end
	return nil
end

--[[
	`m:ss.hh`, and it lives here so that the HUD, the toast and the record
	the profile keeps cannot disagree about what a time looks like.

	`string.format` rather than interpolation: Luau's `{}` has no format
	spec, so an interpolated time is however many decimal places the float
	felt like today.
]]
function Races.format(seconds: number): string
	local whole = math.floor(seconds)
	return string.format("%d:%02d.%02d", whole // 60, whole % 60, math.floor((seconds - whole) * 100))
end

--------------------------------------------------------------------------------
-- The money
--------------------------------------------------------------------------------

--[[
	What entry costs, if you are paying in credits.

	Derived from the cheapest speeder in the catalogue, because owning a
	speeder is the actual prerequisite for racing and so the cheapest one is
	the only honest unit to price entry in. A tenth of it means "you can
	enter ten times for the price of the sled you are driving", which is a
	sentence a fourteen-year-old can hold in his head, and it moves on its
	own if the sled is ever repriced.
]]
local ENTRY_FRACTION = 0.1

local function cheapestSpeeder(): number
	local best = math.huge
	for _, id in Ships.ids() do
		local def = Ships.get(id)
		if not Ships.isStarship(id) and def.cost > 0 then
			best = math.min(best, def.cost)
		end
	end
	return if best < math.huge then best else 0
end

--[[
	Flat across every planet, and that is a decision rather than an oversight.

	Charging by the length of the circuit would make the shortest circuit the
	efficient one to farm, and a game with nine planets where one of them is
	the correct answer is a game with one planet. A long circuit already
	costs more -- it costs more of the evening, and there are more corners on
	which to lose your own hull's ghost.
]]
Races.ENTRY_FEE = math.max(1, math.floor(cheapestSpeeder() * ENTRY_FRACTION))

--- The inventory id of a ticket. A plain merging stack, so a bag holds any
--- number of them in one row and none of them is unique.
Races.PASS_ITEM = "RacePass"

--[[
	The time to beat: what a ghost of the hull you are actually driving does.

	THIS, AND NOT THE FINISHING POSITION, IS WHAT PAYS.

	Position cannot be the test. The grid is the whole catalogue, so first
	place means beating the Swoop Racer's ghost, which in practice means
	owning a Swoop Racer -- and a purse only a fourteen-thousand-credit hull
	can win is a purse the boy who has not got one pays into and never takes
	out. Medals cannot be the test either, for the same reason one step down:
	par is the *median* hull's pace, so a Hover Sled cannot earn one however
	well it is driven.

	Your own hull's ghost is the one benchmark that is equally hard in every
	speeder, because it is scaled by the thing being tested. It is also
	exactly the question commit 2 built the grid to ask: are you worth more
	than your hull's numbers alone? Being paid for the answer is the point.

	Nil for anything that cannot race -- a starship, or an id no catalogue
	knows -- so the caller has to decide what a run in one of those is worth
	rather than being handed a number that pretends it is comparable.
]]
function Races.ghostTime(shipId: string, length: number, laps: number): number?
	if not Ships.exists(shipId) or Ships.isStarship(shipId) then
		return nil
	end
	return Races.rivalTime(Ships.get(shipId).speed * RIVAL_PACE, length, laps)
end

--[[
	The prize paid on top of the purse, as a multiple of the entry fee.

	A win with no medal returns the stake exactly, so beating your own ghost
	in a slow hull always gets your money back and never more. Everything
	above that is the medal, which is where the expensive hull is allowed to
	be worth its price.

	The consequence is worth stating plainly, because it is the whole shape
	of the economy this adds: **the only new credits a race mints are the
	medal, and everything else in the purse came out of somebody's pocket.**
	You make money off your own excellence or off somebody else's failed
	entry, and never off having shown up.
]]
function Races.prizeFor(medal: Medal?): number
	return math.floor(Races.ENTRY_FEE * (if medal then medal.prize else 1))
end

--------------------------------------------------------------------------------
-- Boot check
--------------------------------------------------------------------------------

--[[
	Everything above is derived, which is exactly why it needs checking: a
	derived number has no author to notice it has gone strange.
]]
function Races.validate(): { string }
	local problems: { string } = {}

	if #SPEEDS == 0 then
		table.insert(problems, "no non-starship hulls exist, so par and the floor are meaningless")
		return problems
	end
	if MEDIAN_SPEED <= 0 or TOP_SPEED <= 0 then
		table.insert(problems, `hull speeds resolved to {MEDIAN_SPEED} / {TOP_SPEED}`)
	end
	if TOP_SPEED < MEDIAN_SPEED then
		table.insert(problems, "the fastest speeder is slower than the median one")
	end
	if PACE <= 0 or PACE > 1 then
		table.insert(problems, `PACE is {PACE}, which is not a fraction of top speed`)
	end
	if RIVAL_PACE <= 0 or RIVAL_PACE > 1 then
		table.insert(problems, `RIVAL_PACE is {RIVAL_PACE}, which is not a fraction of top speed`)
	end
	--[[
		A rival driving the perfect line at the pace par credits a human with
		is a rival nobody in the same hull can beat, and a grid nobody can
		beat is scenery. This is the one number the field's difficulty is,
		so it is the one number worth a boot check.
	]]
	if RIVAL_PACE >= PACE then
		table.insert(problems, "rivals hold at least the pace par assumes, so no hull can beat its own ghost")
	end
	if #Races.rivals() == 0 then
		table.insert(problems, "the grid is empty, so every race is won by default")
	end

	-- A floor at or above par means every clean lap is rejected as impossible.
	local sample = 4000
	if Races.floorFor(sample, Races.LAPS) >= Races.parFor(sample, Races.LAPS) then
		table.insert(problems, "the floor time is not below par, so no finish would ever count")
	end

	local previous = 0
	local previousPrize = math.huge
	for _, medal in Races.MEDALS do
		if medal.scale <= previous then
			table.insert(problems, `medal "{medal.id}" is not looser than the one before it`)
		end
		--[[
			The table runs best to worst, so the prizes have to run down it.
			A Silver worth more than a Gold would pay a player for driving
			slower, which is not a bug anybody would notice from the outside
			and is exactly the kind of thing two brothers would find.
		]]
		if medal.prize >= previousPrize then
			table.insert(problems, `medal "{medal.id}" pays at least as much as a better one`)
		end
		if medal.prize < 1 then
			table.insert(problems, `medal "{medal.id}" pays back less than the entry fee`)
		end
		previous = medal.scale
		previousPrize = medal.prize
	end

	if Races.ENTRY_FEE <= 0 then
		table.insert(problems, "entry is free, so the purse can never contain anything")
	end
	-- The fee is derived from the catalogue and the pass is a catalogue id,
	-- so both are exactly the kind of thing that goes quietly wrong when
	-- somebody renames an item -- the failure `Flags` and `Missions` were
	-- both given a declared registry to stop.
	if not Items.exists(Races.PASS_ITEM) then
		table.insert(problems, `the entry ticket "{Races.PASS_ITEM}" is not an item`)
	end

	if Races.MIN_CHECKPOINTS < 3 then
		table.insert(problems, "a circuit of fewer than three gates has no shape")
	end
	if Races.GATE_RADIUS * 2 >= Races.MIN_GATE_SPACING then
		table.insert(problems, "gates are wider apart than they are spaced, so one could satisfy two")
	end

	return problems
end

return Races
