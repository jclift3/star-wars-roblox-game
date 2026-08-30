--!strict
--[[
	SkyTrafficController.luau

	Puts ships in the sky over the worlds that declare one.

	Coruscant is a hundred and twenty-one towers standing in dead air. The
	geometry has been right since ROADMAP 3.3 and the place still reads as a
	model of a city rather than a city, because nothing in it moves except
	the player -- and there is no ground below to put a crowd on. This is the
	crowd. `PlanetDef.airTraffic` says how many hulls, and eight of the nine
	worlds say nothing, because the Korriban wastes do not have rush hour.

	ENTIRELY CLIENT-SIDE, AND STILL THE SAME SKY FOR EVERYONE
	Nothing here is a fact the server has to hold: no traffic hull can be
	shot, boarded, landed on, collided with or asked for directions, so
	replicating twenty-six moving models to every player would be paying a
	network bill for a decoration. It is drawn on the client instead.

	That would normally mean the boys, who play in the same room, look at
	two different skies -- which is the class of thing they notice and then
	argue about. So the lanes are seeded off the planet id and flown off
	`Workspace:GetServerTimeNow()`, which is the same clock on every client.
	Same seed plus same clock is the same sky, without a single remote.

	A HULL'S POSITION IS A FUNCTION, NOT A SIMULATION
	There is no spawning, no despawning and no per-ship state that changes:
	given the time alone, `place` says where hull `n` is. Reaching the end
	of a lane wraps it back to the start, which is a teleport, and it
	happens one tower row past the last building, in air the atmosphere has
	already turned to haze.

	The lanes are pinned to the *planet*, not to the camera. The obvious
	build follows the player around so traffic is always nearby, and it
	costs a visible sideways jump of a whole grid square every time they
	cross a tower row. It is also unnecessary: the vertical city is 4,080
	studs across in total, so a lane laid over the whole of it is never far
	from anyone standing in it.

	Simulating it properly -- spawn at one end of a lane, fly, destroy --
	is the obvious alternative, and it is strictly more code, more garbage,
	and per-client random unless it is seeded anyway.

	WHY THE LANES ARE WHERE THEY ARE
	`buildVerticalCity` stands its towers on `Planets.TOWER_GRID` and hangs
	their landing platforms on `Planets.SKYLANE_STEP`. A lane is therefore
	half a grid square between two rows of towers, at half a step between
	two platform decks: dead centre of a canyon, and passing under the pad
	the player is standing on rather than through it. Both numbers live in
	config precisely so that this file and the builder cannot disagree; a
	private copy here is a hundred airbuses flying through the Senate.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Planets = require(Shared.Config.Planets)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local ShipModel = require(Shared.Rig.ShipModel)
local Ships = require(Shared.Config.Ships)

local SkyTrafficController = {
	name = "SkyTrafficController",
	-- After AtmosphereController (50), which is the other thing that reacts
	-- to arriving somewhere. Nothing depends on the order; this only keeps
	-- the two scenery controllers together in the boot log.
	priority = 52,
}

--[[
	How long a lane is before it wraps, in studs.

	One tower row longer than the city is wide, and centred on the planet's
	origin, so a hull jumps at 2,160 studs out -- past the last tower at
	1,920, in air the atmosphere has already turned to haze. Every world with
	traffic is an Urban one: Coruscant's own `fogEnd` is 4,000 but its haze
	reduces a hull to nothing at a fraction of that.

	Derived rather than the flat 3,600 it used to be, which was comfortably
	past the old skyline and is now 500 studs *short* of the new one -- hulls
	would have wrapped in plain sight over the middle of the city.
]]
local SPAN = Planets.TOWER_GRID * (Planets.TOWER_REACH * 2 + 2)

--- Cruising speeds, studs/sec, by traffic hull id. A barge and a patrol
--- skiff moving at one speed is a conveyor belt rather than a city.
local SPEEDS: { [string]: NumberRange } = {
	Airbus = NumberRange.new(80, 130),
	Barge = NumberRange.new(40, 65),
	Patrol = NumberRange.new(150, 200),
	-- Slowest thing in the sky, and it has to be: 240 studs of hull crossing
	-- a 240-stud canyon at commuter speed is a flicker, and the whole reason
	-- for building it is that you have time to notice how big it is.
	Capital = NumberRange.new(22, 34),
}
local DEFAULT_SPEED = NumberRange.new(80, 130)

--[[
	How many corridors either side of the planet's origin are flown.

	Was a private 5 here matching a literal 5 in `buildVerticalCity`, on the
	grounds that getting it wrong only looked like weather. It stopped being
	true the moment the grid widened: a lane count left behind at 5 puts every
	airbus in the game inside the middle third of a city three times that
	across, and the outskirts read as abandoned. Same constant as the builder
	now, for the same reason `TOWER_GRID` is.
]]
local LANE_SPREAD = Planets.TOWER_REACH

--- The lowest and highest deck gaps a lane may sit in, counted in
--- `SKYLANE_STEP`s. One is below the tops of the shortest towers; the top is
--- clamped against the planet's own ceiling in `rebuild`.
local MIN_DECK = 1

type Craft = {
	model: Model,
	-- Which world axis the lane runs along. True for X, false for Z: two
	-- bearings only, because the towers are on a square grid and a diagonal
	-- lane is a lane through a building.
	alongX: boolean,
	direction: number, -- +1 or -1 along that axis
	lane: number, -- which canyon, counted out from the planet's origin
	altitude: number,
	speed: number,
	phase: number, -- studs along the lane at time zero
}

local craft: { Craft } = {}
local folder: Folder? = nil
local currentPlanet: string? = nil
local worldOrigin = Vector3.zero

--[[
	A stable seed from a planet id.

	Only has to agree with itself across clients, never with the server's
	world seed -- which is why this is five lines here rather than a shared
	helper hoisted out of PlanetBuilder. Two players on Coruscant get the
	same lanes; Coruscant and Nar Shaddaa do not get the same sky.
]]
local function seedFrom(id: string): number
	local seed = 11
	for i = 1, #id do
		seed = (seed * 31 + string.byte(id, i)) % 2147483647
	end
	return seed
end

--[[
	Where the hulls live: under the camera, not in Workspace.

	The same trick as the companion sun in AtmosphereController. A part
	parented to the camera still renders in world coordinates, but it is
	never replicated, never saved, and never found by anything that walks
	Workspace looking for things to shoot, spawn on or path around -- which
	matters more here than it did there, because a traffic hull is
	ship-shaped and NPC pathfinding would very much like to try.
]]
local function container(): Folder?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local existing = folder
	if existing and existing.Parent == camera then
		return existing
	end
	if existing then
		-- The camera is replaced on respawn, taking its children with it.
		existing:Destroy()
	end

	local f = Instance.new("Folder")
	f.Name = "SkyTraffic"
	f.Parent = camera
	folder = f
	return f
end

local function clear()
	for _, c in craft do
		c.model:Destroy()
	end
	table.clear(craft)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

--- Tears down whatever was in the air and lays out this planet's lanes.
local function rebuild(planetId: string)
	clear()
	if not Planets.exists(planetId) then
		return
	end

	local planet = Planets.get(planetId)
	local count = planet.airTraffic
	if not count or count <= 0 then
		return
	end

	local parent = container()
	if not parent then
		return
	end

	worldOrigin = Planets.originFor(planetId)

	local step = Planets.SKYLANE_STEP
	-- One deck below the ceiling, so nothing cruises through the altitude a
	-- starship's star map opens at.
	local topDeck = math.max(MIN_DECK, math.floor(((planet.flightCeiling or 1400) - step) / step))
	local rng = Random.new(seedFrom(planetId))

	for _ = 1, count do
		local hull = Ships.TRAFFIC[rng:NextInteger(1, #Ships.TRAFFIC)]
		local speeds = SPEEDS[hull.id] or DEFAULT_SPEED

		local model = ShipModel.buildTraffic(hull)
		model.Parent = parent

		table.insert(craft, {
			model = model,
			alongX = rng:NextInteger(0, 1) == 1,
			direction = if rng:NextInteger(0, 1) == 1 then 1 else -1,
			-- One short of the spread on the low side: a canyon lies
			-- *between* two rows of towers, so ten rows make nine gaps.
			lane = rng:NextInteger(-LANE_SPREAD, LANE_SPREAD - 1),
			-- Half a step above a deck: the gap between two platforms, not
			-- the platform.
			altitude = rng:NextInteger(MIN_DECK, topDeck) * step + step * 0.5,
			speed = rng:NextNumber(speeds.Min, speeds.Max),
			phase = rng:NextNumber(0, SPAN),
		})
	end
end

--- `d` folded into [-span/2, span/2), so a lane repeats over the city.
local function wrap(d: number, span: number): number
	return (d + span * 0.5) % span - span * 0.5
end

--- Where this hull is at `now`, which is all it takes.
local function place(c: Craft, now: number)
	local grid = Planets.TOWER_GRID
	-- Half a grid square off the tower rows, which is the middle of a
	-- canyon. Measured from `worldOrigin` because the grid is anchored to
	-- the planet's own patch of Workspace, not to zero.
	local acrossOrigin = if c.alongX then worldOrigin.Z else worldOrigin.X
	local across = acrossOrigin + (c.lane + 0.5) * grid

	local alongOrigin = if c.alongX then worldOrigin.X else worldOrigin.Z
	local along = alongOrigin + wrap(c.phase + now * c.speed * c.direction, SPAN)

	local position = if c.alongX
		then Vector3.new(along, c.altitude, across)
		else Vector3.new(across, c.altitude, along)
	local heading = if c.alongX then Vector3.new(c.direction, 0, 0) else Vector3.new(0, 0, c.direction)

	-- A hull's nose is -Z and that is what `lookAt` orients, so the ship
	-- faces the way it is going without a correction. Same convention the
	-- driveable ships are modelled to.
	c.model:PivotTo(CFrame.lookAt(position, position + heading))
end

function SkyTrafficController.start()
	local state = ServiceLoader.get("ClientState")

	local function follow(profile: any)
		if profile.currentPlanet == currentPlanet then
			return
		end
		currentPlanet = profile.currentPlanet
		rebuild(profile.currentPlanet)
	end

	state.changed:connect(follow)

	local existing = state.get()
	if existing then
		follow(existing)
	end

	RunService.Heartbeat:Connect(function()
		if #craft == 0 then
			return
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		-- Cheap, and the alternative is a sky that disappears the first time
		-- the player dies: respawning replaces the camera these are under.
		if folder and folder.Parent ~= camera then
			local planetId = currentPlanet
			if planetId then
				rebuild(planetId)
			end
			return
		end

		local now = Workspace:GetServerTimeNow()
		for _, c in craft do
			place(c, now)
		end
	end)
end

return SkyTrafficController
