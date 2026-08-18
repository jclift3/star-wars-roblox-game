--!strict
--[[
	CrowdController.luau

	Fills the middle distance of a district with people who are only a picture.

	WHY THERE IS A SECOND CROWD
	Every district's population is already authored, and it already varies:
	Coruscant's Plaza spawns sixty-five people and Ord Mantell's Market spawns
	four, and `PlanetBuilder` sizes each district's ring off that number. What
	it cannot do is spawn more. `NPCService` holds a hard ceiling of 260 NPCs
	across the whole galaxy, and every one of them is a rig with a Humanoid, a
	brain ticking at 8Hz, a name, a level and a proximity prompt. That is the
	right price for someone you can talk to, rob or shoot, and a ruinous one
	for a silhouette crossing a plaza two hundred studs away.

	So the real crowd stays exactly as it is and this draws a second one behind
	it: bodies with no Humanoid, no brain, no prompt and no collision, whose
	position is a function of the clock. A plaza reads as a city because two
	hundred people are moving in it, and sixty-five of them are real.

	WHY DESPAWNING THE REAL ONES WAS NOT AN OPTION
	The obvious version of "crowd density" is to thin the actual population
	after dark. It is unshippable here, and the receipts are in `Missions.luau`:
	`giver = "ProtocolDroid"`, `giver = "MoistureFarmer"`, and three separate
	`TalkTo target = "Civilian"` objectives. Removing anonymous people removes
	mission givers, which is the *finished but unreachable* failure this project
	has already shipped twice. `NPCArchetypes.Shift` says the same thing in its
	own header: it does not despawn anybody.

	A body that was never real can be removed freely, which is how the crowd
	gets to thin out at night here without a single mission breaking.

	THE SAME CROWD ON BOTH SCREENS
	Straight out of SkyTrafficController, for the same reason: the boys play in
	one room and notice when two screens disagree. Every figure is seeded off
	the planet and zone ids and walked off `Workspace:GetServerTimeNow()`, so
	two clients compute the same crowd without a remote, a replicated model or
	a service on the server.

	They live under `Workspace.CurrentCamera` rather than in Workspace, which is
	the trick that makes the whole thing safe: nothing that walks Workspace
	looking for people -- ShopService's vendor sweep, VendorController, the
	NPC placement raycasts, combat targeting -- can find one, because they are
	not there. It also means they cannot be replicated, saved or pathed around.

	NOBODY IS EVER WITHIN REACH
	A figure you can walk up to is a bug report: it has no name, it does not
	answer, and it does not bleed. So they are faded out over the fifty studs
	before the player could arrive at one, and the district's real people are
	standing exactly where the picture thins. What is left is a crowd that gets
	sparser as you push into it, which is what a crowd does anyway.

	WHAT DECIDES HOW MANY
	Nothing new. `NPCArchetypes.crowdIn` reads the district's own spawn rules,
	so a district gains a background crowd by gaining people the ordinary way,
	and the two can never drift apart. A `ZoneDef.crowdDensity` field would say
	a second time what the spawn table already says, and this codebase's
	recurring failure is config that nothing reads or that quietly disagrees
	with the thing it duplicates.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Costumes = require(Shared.Config.Costumes)
local NPCArchetypes = require(Shared.Config.NPCArchetypes)
local Planets = require(Shared.Config.Planets)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Species = require(Shared.Config.Species)
local WorldClock = require(Shared.Core.WorldClock)

local CrowdController = {
	name = "CrowdController",
	-- Beside the other two scenery controllers, Atmosphere (50) and
	-- SkyTraffic (52). Nothing depends on the order.
	priority = 53,
}

--[[
	Background bodies per real inhabitant, and the ceiling on the total.

	Two-for-one is the point where Anchorhead's main street stops reading as
	twenty-two people who all know each other. The ceiling is what stops
	Coruscant's Plaza, which alone spawns fifty-two of the everyday sort, from
	turning that into a hundred and four models on a fourteen-year-old's
	laptop. Only the planet the player is standing on is ever drawn.
]]
local PER_REAL = 2
local MAX_FIGURES = 80

--- Walking pace, studs/sec. The real archetypes walk 10-14; a crowd that all
--- moves at one speed is a conveyor belt, so this straddles it.
local SPEED = NumberRange.new(7, 13)

--[[
	The near fade, in studs.

	Gone by 55 and solid by 105. The far end has to be past the distance at
	which a figure stops being convincing -- no face, no animation cycle, four
	parts -- and the near end has to be far enough that nobody arrives at one
	while it is still visible. A player walks about 16 studs a second, so the
	band is a little over three seconds wide.
]]
local NEAR_GONE = 55
local NEAR_SOLID = 105

--- The far fade. Every world's atmosphere has closed in well before this;
--- it exists so nothing pops rather than to be seen happening.
local FAR_SOLID = 260
local FAR_GONE = 340

--[[
	How much of the crowd is still out at the dead of night.

	Not zero. An empty street at 02:00 is correct and unusable: the district's
	real people are all still standing there, so a crowd that goes to nothing
	makes the survivors look like the odd ones out rather than making the hour
	feel late.
]]
local NIGHT_SHARE = 0.3
--- Ranks within this of the cutoff are half-faded, so people leave one at a
--- time over the evening instead of the street blinking.
local RANK_FADE = 0.12

--- Only written when it moves by more than this. A transparency write per
--- part per frame is the one genuinely expensive thing in here.
local ALPHA_STEP = 0.04

local SKIN_FALLBACK = Color3.fromRGB(198, 160, 128)
local CLOTH_FALLBACK = Color3.fromRGB(96, 92, 84)

type Figure = {
	model: Model,
	parts: { BasePart },
	--- The loop this one walks, in world space, at foot level.
	route: { Vector3 },
	--- Distance along the loop at the end of each leg, so `place` can find
	--- the current leg with one scan and no per-frame arithmetic.
	marks: { number },
	length: number,
	speed: number,
	phase: number,
	--[[
		Where this figure stands in the queue to go home, 0..1.

		Fixed at build time, so the same people leave in the same order every
		night and on both clients, and nobody flickers as the hour ticks.
	]]
	rank: number,
	alpha: number,
}

local figures: { Figure } = {}
local folder: Folder? = nil
local currentPlanet: string? = nil
--- Bumped on every rebuild so a retry that was waiting for a planet's zones
--- to replicate does not build them onto a planet the player has since left.
local generation = 0

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- A stable seed from a string. Same job as SkyTrafficController's, and
--- deliberately the same five lines rather than a shared helper: it only has
--- to agree with itself across clients, never with the server's world seed.
local function seedFrom(id: string): number
	local seed = 11
	for i = 1, #id do
		seed = (seed * 31 + string.byte(id, i)) % 2147483647
	end
	return seed
end

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
		-- Respawning replaces the camera and takes its children with it.
		existing:Destroy()
	end

	local f = Instance.new("Folder")
	f.Name = "Crowd"
	f.Parent = camera
	folder = f
	return f
end

local function clear()
	for _, figure in figures do
		figure.model:Destroy()
	end
	table.clear(figures)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

--- The first colour a costume puts on a limb whose name contains `limbMatch`.
local function costumeColour(costumeId: string, limbMatch: string, fallback: Color3): Color3
	if not Costumes.exists(costumeId) then
		return fallback
	end
	for _, spec in Costumes.get(costumeId) do
		if spec.color and string.find(spec.limb, limbMatch) then
			return spec.color
		end
	end
	return fallback
end

local function piece(
	model: Model,
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	ball: boolean
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = if ball then Enum.PartType.Ball else Enum.PartType.Block
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(offset)
	part.Parent = model
	return part
end

--[[
	One body: legs, torso, head, and an empty root at its feet.

	Four parts because a person is a vertical stack of three tones -- trousers,
	coat, face -- and past a hundred studs that stack is the whole of what the
	eye is reading. A fifth part would be an arm nobody can see.

	The species' own proportions are applied because they are what makes a
	Wookiee not a Jawa at range: `heightScale` and `widthScale` are the same
	numbers RigBuilder feeds a HumanoidDescription for the real ones, so the
	silhouettes agree even though nothing else about the two models does.
]]
local function buildFigure(archetypeId: string, speciesId: string, rng: Random): (Model, { BasePart })
	local archetype = NPCArchetypes.get(archetypeId)
	local def = Species.get(speciesId)

	local skin = if #def.skinTones > 0
		then def.skinTones[rng:NextInteger(1, #def.skinTones)]
		else SKIN_FALLBACK
	local coat = costumeColour(archetype.costume, "Torso", CLOTH_FALLBACK)
	local trousers = costumeColour(archetype.costume, "Leg", coat)

	-- A little spread on top of the species scale, so a street is not one
	-- person printed forty times.
	local height = def.heightScale * rng:NextNumber(0.94, 1.06)
	local width = def.widthScale

	local model = Instance.new("Model")
	model.Name = "Figure"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local parts = {
		piece(
			model,
			"Legs",
			Vector3.new(1.2 * width, 2.6 * height, 0.9 * width),
			Vector3.new(0, 1.3 * height, 0),
			trousers,
			false
		),
		piece(
			model,
			"Torso",
			Vector3.new(1.8 * width, 2.1 * height, 1.0 * width),
			Vector3.new(0, 3.65 * height, 0),
			coat,
			false
		),
		piece(
			model,
			"Head",
			Vector3.one * (1.1 * def.headScale),
			Vector3.new(0, 5.3 * height, 0),
			skin,
			true
		),
	}

	return model, parts
end

--[[
	The loop one figure walks.

	Every district publishes its standing room as parts under `Workspace.Zones`
	-- the same points NPCService reads as a patrol route -- so a background
	body walks where the real ones walk without anyone placing a waypoint for
	it. Each gets the points in its own order and its own scatter inside each
	one, because forty figures sharing a route is a procession.

	The marker's footprint is its `Size`, which is authored: a point on an
	authored town's paving is one cell wide and a point on open ground is
	sixty studs, and scattering by it puts the crowd on the street rather than
	through the wall behind it.
]]
local function routeFor(points: { BasePart }, rng: Random): ({ Vector3 }, { number }, number)
	local order = table.clone(points)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end

	local route: { Vector3 } = {}
	for _, point in order do
		local halfX = point.Size.X * 0.4
		local halfZ = point.Size.Z * 0.4
		local at = point.Position
			+ Vector3.new(rng:NextNumber(-halfX, halfX), 0, rng:NextNumber(-halfZ, halfZ))

		-- Where the ground under that actually is. The markers float a fixed
		-- lift above it, but that lift is PlanetBuilder's and PlanetBuilder is
		-- server-only -- a private copy of it here is a crowd walking three
		-- studs under the pavement the day somebody changes it.
		local hit = Workspace:Raycast(at + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), groundParams)
		table.insert(route, if hit then hit.Position else at)
	end

	local marks: { number } = {}
	local total = 0
	for i, at in route do
		local nextAt = route[if i == #route then 1 else i + 1]
		total += (nextAt - at).Magnitude
		marks[i] = total
	end

	return route, marks, total
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

--- How many background bodies each district gets, and who they look like.
type Allocation = { zone: string, count: number, cast: { { archetype: string, count: number } } }

local function allocate(planetId: string): { Allocation }
	local spawns = Planets.get(planetId).spawns
	local out: { Allocation } = {}
	local total = 0

	for _, def in Planets.get(planetId).zones do
		local cast = NPCArchetypes.crowdIn(spawns, def.id)
		local people = 0
		for _, entry in cast do
			people += entry.count
		end
		if people > 0 then
			table.insert(out, { zone = def.id, count = people, cast = cast })
			total += people
		end
	end

	-- Scaled down together rather than filled in declaration order, so a
	-- planet over the ceiling loses people evenly instead of leaving its last
	-- district empty. Coruscant is the only one that reaches it.
	local wanted = math.min(MAX_FIGURES, total * PER_REAL)
	for _, entry in out do
		entry.count = math.max(1, math.round(entry.count / total * wanted))
	end
	return out
end

--- Picks an archetype in proportion to how many of them really stand here.
local function pickArchetype(cast: { { archetype: string, count: number } }, rng: Random): string
	local total = 0
	for _, entry in cast do
		total += entry.count
	end

	local roll = rng:NextNumber(0, total)
	for _, entry in cast do
		roll -= entry.count
		if roll <= 0 then
			return entry.archetype
		end
	end
	return cast[#cast].archetype
end

local function pickSpecies(archetypeId: string, rng: Random): string
	local pool = NPCArchetypes.get(archetypeId).speciesPool
	local total = 0
	for _, entry in pool do
		total += entry.weight
	end

	local roll = rng:NextNumber(0, total)
	for _, entry in pool do
		roll -= entry.weight
		if roll <= 0 then
			return entry.species
		end
	end
	return pool[#pool].species
end

local function build(planetId: string, parent: Folder)
	local zones = Workspace:FindFirstChild("Zones")
	local planetZones = zones and zones:FindFirstChild(planetId)
	if not planetZones then
		return
	end

	-- Neither the markers nor anyone standing on them is ground, and a route
	-- point resolved through the player's own feet would put one figure on a
	-- pedestal for the rest of the session. The crowd itself is under the
	-- camera and so was never in the way.
	local exclude: { Instance } = { planetZones }
	local npcs = Workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(exclude, npcs)
	end
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(exclude, character)
	end
	groundParams.FilterDescendantsInstances = exclude

	for _, allocation in allocate(planetId) do
		local zoneFolder = planetZones:FindFirstChild(allocation.zone)
		if not zoneFolder then
			continue
		end

		local points: { BasePart } = {}
		for _, child in zoneFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(points, child)
			end
		end
		-- A loop needs somewhere to go and somewhere to come back from.
		if #points < 2 then
			continue
		end

		local rng = Random.new(seedFrom(planetId .. allocation.zone))
		for index = 1, allocation.count do
			local archetypeId = pickArchetype(allocation.cast, rng)
			local model, parts = buildFigure(archetypeId, pickSpecies(archetypeId, rng), rng)
			local route, marks, length = routeFor(points, rng)
			if length <= 0 then
				model:Destroy()
				continue
			end

			model.Parent = parent
			table.insert(figures, {
				model = model,
				parts = parts,
				route = route,
				marks = marks,
				length = length,
				speed = rng:NextNumber(SPEED.Min, SPEED.Max),
				phase = rng:NextNumber(0, length),
				-- Spread evenly rather than rolled, so the number still out
				-- at a given hour is the number intended and not a sample.
				rank = (index - 0.5) / allocation.count,
				alpha = 1,
			})

			for _, part in parts do
				part.Transparency = 1
			end
		end
	end
end

--[[
	Lays out the crowd for a planet, waiting for its districts to arrive.

	The server builds a world when somebody lands on it, so on the first
	arrival the zone folders are still on their way down when ClientState
	changes. Retried rather than deferred by a fixed sleep: the wait is a
	replication race, and a race has no honest constant.
]]
local function rebuild(planetId: string?)
	clear()
	generation += 1

	if not planetId or not Planets.exists(planetId) then
		return
	end

	local mine = generation
	task.spawn(function()
		for _ = 1, 20 do
			if generation ~= mine then
				return
			end
			local parent = container()
			if parent then
				build(planetId, parent)
				if #figures > 0 then
					return
				end
				-- `build` parents nothing when the zones have not landed yet,
				-- so an empty result is the signal to wait rather than a
				-- planet with no crowd. Districts with no everyday people
				-- allocate none and cost one more second of waiting.
			end
			task.wait(1)
		end
	end)
end

--------------------------------------------------------------------------------
-- Per-frame
--------------------------------------------------------------------------------

--- How much of the crowd is out at this hour, 0..1. Noon is everybody.
local function densityAt(hour: number): number
	-- Peaks at 13:00 and bottoms at 01:00, which is a working day rather than
	-- a solar one: the street is fullest in the early afternoon and emptiest
	-- an hour after midnight.
	local daylight = 0.5 - 0.5 * math.cos((hour - 1) / 24 * math.pi * 2)
	return NIGHT_SHARE + (1 - NIGHT_SHARE) * daylight
end

--- Where along its loop this figure is, and which way it is facing.
local function place(figure: Figure, now: number): (Vector3, Vector3)
	local along = (figure.phase + now * figure.speed) % figure.length

	local leg = #figure.route
	for i, mark in figure.marks do
		if along <= mark then
			leg = i
			break
		end
	end

	local from = figure.route[leg]
	local to = figure.route[if leg == #figure.route then 1 else leg + 1]
	local started = if leg == 1 then 0 else figure.marks[leg - 1]
	local span = figure.marks[leg] - started

	local at = if span > 0 then from:Lerp(to, (along - started) / span) else from
	local heading = to - from
	if heading.Magnitude < 0.01 then
		heading = Vector3.new(0, 0, 1)
	end
	return at, heading
end

local function update()
	if #figures == 0 then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	-- The camera is replaced on respawn, taking the whole crowd with it.
	if folder and folder.Parent ~= camera then
		rebuild(currentPlanet)
		return
	end

	local now = Workspace:GetServerTimeNow()
	local eye = camera.CFrame.Position
	local cutoff = densityAt(WorldClock.hourOn(currentPlanet or ""))

	for _, figure in figures do
		local at, heading = place(figure, now)

		local distance = (at - eye).Magnitude
		local near = math.clamp((distance - NEAR_GONE) / (NEAR_SOLID - NEAR_GONE), 0, 1)
		local far = math.clamp((FAR_GONE - distance) / (FAR_GONE - FAR_SOLID), 0, 1)
		local shift = math.clamp((cutoff - figure.rank) / RANK_FADE, 0, 1)
		local alpha = 1 - near * far * shift

		if math.abs(alpha - figure.alpha) > ALPHA_STEP or (alpha >= 1) ~= (figure.alpha >= 1) then
			figure.alpha = alpha
			for _, part in figure.parts do
				part.Transparency = alpha
			end
		end

		-- Invisible figures are still walked, because their position is a
		-- function of the time and not an accumulation -- there is nothing to
		-- keep up to date. They are just not moved.
		if alpha < 1 then
			-- Half a stride of bob. No legs swing, and at this distance the
			-- rise and fall is what the eye reads as walking anyway.
			local bob = math.abs(math.sin(now * figure.speed * 0.55)) * 0.14
			local stand = at + Vector3.new(0, bob, 0)
			figure.model:PivotTo(CFrame.lookAt(stand, stand + Vector3.new(heading.X, 0, heading.Z)))
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CrowdController.start()
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

	RunService.Heartbeat:Connect(update)
end

return CrowdController
