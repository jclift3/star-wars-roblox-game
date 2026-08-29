--!strict
--[[
	Orbit.luau

	What is above a planet: the weather you climb through, and the sky you
	come out into.

	WHY THIS EXISTS AT ALL
	Starships have flown in three dimensions since ROADMAP 2c -- pitch,
	climb, a ceiling and a name for being over it. What was missing was
	anywhere to arrive. Crossing `Ships.CEILING` opened the star map, which
	is a panel over the view at the exact moment there is finally something
	to look at.

	THE PROBLEM THIS FILE IS MOSTLY ABOUT
	A world is a plate. `Planets.groundRadius` is 1,240-1,400 studs on most
	of them and the ceiling is 900 studs up, so the moment you "reach space"
	you are two-thirds of a plate-radius above a **flat disc with a visible
	hard edge**, floating in nothing. No starfield fixes that; you would be
	looking straight down at the seam.

	A cloud deck does, and it is the cheapest good thing in the whole
	feature. It hides the plate and its edge, it turns crossing the ceiling
	into a physical event rather than a state change -- you punch up through
	weather and pop out on top of it -- and what is left underneath reads
	honestly as *the planet*, which a disc never will. It also makes every
	world look better from the ground, which was the other half of the same
	playtest report.

	`Terrain.Clouds` was considered and rejected: Roblox renders it at a
	fixed altitude that is not a settable property, so it cannot be put at
	*our* ceiling -- and a cloud layer in the wrong place is worse than none.

	COMPOSED, NOT AUTHORED
	Every table below is built by walking `Planets.ids()` at require time,
	the `Radiant.luau` pattern. There is no per-planet orbit table to keep in
	step with the planet catalogue, and adding a tenth world gets a sky and a
	deck for free. What varies comes from fields `PlanetDef` already carries:
	`terrain` decides the weather, `fogColor` and `skyTint` decide its
	colour, `hasWalkableGround` decides whether there is a plate to hide.
]]

local Planets = require(script.Parent.Planets)
local Ships = require(script.Parent.Ships)

local Orbit = {}

--------------------------------------------------------------------------------
-- Where the atmosphere ends
--------------------------------------------------------------------------------

local ceilings: { [string]: number } = {}

--[[
	How high you must be, over *this* world, to be out of it.

	`Ships.CEILING` on seven of the nine, and the world's own `flightCeiling`
	on the two that stand things up past it. Coruscant's towers reach 1,400
	and Nar Shaddaa's stacks 1,100, so a fixed 900 would put a pilot in orbit
	while still threading the skyline -- black sky, no stars visible past the
	buildings, and nothing to explain it.

	It is a maximum rather than a substitution because `flightCeiling` is a
	fact about the architecture, not a permission: a world that declares a low
	one has not thereby moved space closer.
]]
function Orbit.ceilingFor(planetId: string): number
	return ceilings[planetId] or Ships.CEILING
end

--[[
	How far back down you have to come before you are in the air again.

	A bare threshold is a bare threshold in both directions, and a hull
	holding station at exactly the ceiling crosses it several times a second
	-- each one starting a two-second cross-fade of the entire sky in the
	opposite direction to the last. The result is not a flicker, it is a
	strobe, and it happens at precisely the altitude a player who has just
	arrived wants to sit still and look around at.

	Sixty studs is under a second of ordinary climb, so nobody flying up or
	down will ever notice it exists. That is the whole specification.
]]
Orbit.REENTRY_DROP = 60

--------------------------------------------------------------------------------
-- Where one world's authority ends and the next begins
--------------------------------------------------------------------------------

--[[
	THE FACT THIS WHOLE SECTION IS BUILT ON

	All nine worlds are already in one `Workspace`, at real addresses, on a
	12,000-stud grid -- `Planets.originFor` has laid them out that way since
	the first planet was generated. Tatooine and its neighbour are not two
	scenes that have to be swapped. They are two places you could drive
	between today if anything let you.

	So "fly to another planet" needs no new world, no loading screen and no
	teleport. It needs a way to say which of the nine you are currently at,
	and a name for being at none of them.
]]

--[[
	How far a world's authority reaches.

	Everything the game knows about "where you are" hangs off
	`profile.currentPlanet`: the sky, the weather, which NPCs are spawned,
	which missions are offered, what a zone's level band is, where you come
	back if you die. This radius is the border that flips it.

	It has to clear `Planets.worldRadius` (about 1,700 with the relief ring)
	by enough that leaving the plate is not the same event as leaving the
	system -- otherwise flying a wide circuit round your own world keeps
	handing you back and forth. And it has to be under half of
	`Planets.WORLD_SPACING`, because two systems that touch have a seam where
	the answer depends on rounding.

	3,600 sits between those two with room on both sides, which leaves a real
	void of about 4,800 studs between neighbours. That void is the point: if
	the systems met, there would be no such place as *between* worlds, and
	the crossing would be a border rather than a journey.
]]
Orbit.SYSTEM_RADIUS = 3600

--[[
	How close to the arrival point counts as having got there.

	Deliberately smaller than `SYSTEM_RADIUS`, and that ordering is the
	feature: a ship arriving from outside crosses into the world's authority
	*before* it stops. The sky, the cloud deck and the population are
	therefore already the destination's by the time the pilot can see any of
	them, instead of snapping over a second after they have looked.
]]
Orbit.ARRIVAL_RADIUS = 2400

--- Where the worlds actually sit. Filled by the composition loop below.
local origins: { [string]: Vector3 } = {}

--[[
	Horizontal only.

	A world is a plate with a sky over it and nothing under it, so altitude
	never changes which world you are above -- a hull at six thousand studs
	over Tatooine is still over Tatooine. Comparing in three dimensions would
	make climbing high enough count as leaving, which is exactly the state
	this is supposed to distinguish itself from.
]]
local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

--- Which world's system `position` is in, or nil out in the dark between them.
function Orbit.systemAt(position: Vector3): string?
	for id, origin in origins do
		if flatDistance(position, origin) <= Orbit.SYSTEM_RADIUS then
			return id
		end
	end
	return nil
end

--[[
	The nearest world and how far off it is, for a ship that is nowhere.

	Never nil. There is always a nearest world, and something on screen has
	to be able to name it -- being lost in a place with no landmarks is the
	one way this feature could still strand somebody.
]]
function Orbit.nearestSystem(position: Vector3): (string, number)
	local bestId = Planets.STARTING_PLANET
	local bestAt = math.huge
	for id, origin in origins do
		local away = flatDistance(position, origin)
		if away < bestAt then
			bestId, bestAt = id, away
		end
	end
	return bestId, bestAt
end

--[[
	Where a crossing ends: over the world, above its weather, nose-down.

	Above the ceiling rather than at it, so a ship that has just arrived is
	unambiguously in orbit and not straddling the threshold that decides
	whether the sky is black. Descending from here is ordinary flying, which
	is the whole reason arrival is a place rather than a cutscene.
]]
function Orbit.arrivalPointFor(planetId: string): Vector3
	local origin = origins[planetId] or Vector3.zero
	return origin + Vector3.new(0, Orbit.ceilingFor(planetId) * 1.4, 0)
end

--------------------------------------------------------------------------------
-- The cloud deck
--------------------------------------------------------------------------------

export type Deck = {
	--- Studs above the world's ground, where the middle of the layer sits.
	altitude: number,
	thickness: number,
	--- How far out the layer reaches. Wider than the plate, on purpose.
	spread: number,
	color: Color3,
	--- 0 is opaque. Never fully opaque: a solid lid is a ceiling, not weather.
	transparency: number,
	--- Roughly what fraction of the sky the layer fills, 0..1.
	cover: number,
}

--[[
	Weather per terrain kind.

	`lift` is a fraction of `Orbit.ceilingFor`: where the deck's middle sits on
	the way up. All of them are below 1, and that is load-bearing rather than
	tidy -- the deck has to be something you have already broken through by
	the time the sky turns black, or the transition happens inside the cloud
	and reads as a bug.

	The values are the obvious ones and they are obvious for a reason: a
	desert has a thin high scatter and an ice field has a thick low overcast,
	so `terrain` alone answers this without eight more tuned numbers, exactly
	as it already does for `AtmosphereController`'s haze.
]]
local TERRAIN_DECK: { [string]: { lift: number, thickness: number, cover: number, pale: number } } = {
	Desert = { lift = 0.9, thickness = 26, cover = 0.3, pale = 0.55 },
	Ice = { lift = 0.78, thickness = 90, cover = 0.95, pale = 0.3 },
	Swamp = { lift = 0.76, thickness = 84, cover = 0.9, pale = 0.25 },
	Forest = { lift = 0.84, thickness = 56, cover = 0.7, pale = 0.5 },
	Volcanic = { lift = 0.8, thickness = 72, cover = 0.82, pale = 0.15 },
	Ocean = { lift = 0.82, thickness = 62, cover = 0.85, pale = 0.6 },
	Urban = { lift = 0.86, thickness = 46, cover = 0.6, pale = 0.35 },
}

local DEFAULT_DECK = { lift = 0.84, thickness = 55, cover = 0.7, pale = 0.45 }

--[[
	How far past the edge of the land the cloud has to reach.

	The deck's whole job is that you never see where the ground stops, so it
	has to overhang the plate by more than the height you are looking down
	from. Two and a bit radii puts the nearest gap outside the fog on every
	world, which is the same thing as saying there is no gap.
]]
local SPREAD_FACTOR = 2.4
local MIN_SPREAD = 3200

local decks: { [string]: Deck } = {}

--------------------------------------------------------------------------------
-- The sky above it
--------------------------------------------------------------------------------

export type Sky = {
	ambient: Color3,
	outdoor: Color3,
	--- Fed straight into the Atmosphere. Vacuum has none of any of it.
	density: number,
	haze: number,
	glare: number,
	fog: Color3,
	decay: Color3,
	tint: Color3,
	exposure: number,
	starCount: number,
}

--[[
	Why the ambient light is the number that matters.

	Space does not read as space because it is black overhead -- it reads as
	space because there is no air to bounce light into the shadows. Take
	`Lighting.Ambient` and `OutdoorAmbient` to nearly nothing and the sunlit
	face of a hull goes hard white while the other side goes genuinely dark,
	which is the whole look. Density and haze going to zero is what stops the
	fog from filling that darkness back in.

	Not quite black, and not quite neutral: each world keeps a trace of its
	own colour bounced up off the planet below, so Hoth's orbit is faintly
	blue and Tatooine's faintly warm. It is nearly invisible and it is the
	difference between nine skies and one.
]]
local SPACE_AMBIENT = Color3.fromRGB(7, 8, 12)
local PLANETSHINE = 0.14

--- Sunlight with no air in the way is a hard point source with a wide flare.
local SPACE_GLARE = 0.9

--[[
	Stars.

	3,000 is Roblox's own ceiling for `Sky.StarCount`, and there is no reason
	to want fewer: the whole point of the black is what you can see in it.
]]
local STAR_COUNT = 3000

--- Slightly under-exposed, so the stars are not washed out by the sun's flare.
local SPACE_EXPOSURE = -0.15

local skies: { [string]: Sky } = {}

--------------------------------------------------------------------------------
-- Composition
--------------------------------------------------------------------------------

for _, id in Planets.ids() do
	local planet = Planets.get(id)
	local ceiling = math.max(Ships.CEILING, planet.flightCeiling or 0)
	ceilings[id] = ceiling
	origins[id] = Planets.originFor(id)

	--[[
		A world with no walkable ground gets no deck.

		This is Coruscant, and skipping it is not a shortcut. The deck exists
		to hide a plate, and a vertical city has no plate -- what it has is
		towers standing up through the altitude a deck would occupy, so a
		layer here would slice through the skyline it is meant to sell. The
		one world that does not need this is also the one it would ruin.
	]]
	if planet.hasWalkableGround then
		local spec = TERRAIN_DECK[planet.terrain] or DEFAULT_DECK
		decks[id] = {
			altitude = ceiling * spec.lift,
			thickness = spec.thickness,
			spread = math.max(MIN_SPREAD, Planets.worldRadius(id) * SPREAD_FACTOR),
			-- Lit from above by the same sun that lights the ground, so the
			-- cloud is the planet's own fog colour pushed towards white.
			color = planet.fogColor:Lerp(Color3.new(1, 1, 1), spec.pale),
			transparency = 0.28,
			cover = spec.cover,
		}
	end

	skies[id] = {
		ambient = SPACE_AMBIENT:Lerp(planet.ambientLight, PLANETSHINE),
		outdoor = SPACE_AMBIENT:Lerp(planet.outdoorAmbient, PLANETSHINE),
		density = 0,
		haze = 0,
		glare = SPACE_GLARE,
		fog = planet.fogColor,
		decay = planet.skyTint,
		-- The colour grade goes nearly neutral: in air a world is seen
		-- through its own sky, and in vacuum it simply is not.
		tint = planet.skyTint:Lerp(Color3.new(1, 1, 1), 0.8),
		exposure = SPACE_EXPOSURE,
		starCount = STAR_COUNT,
	}
end

--------------------------------------------------------------------------------
-- Readers
--------------------------------------------------------------------------------

--- This world's cloud layer, or nil where there is no ground to hide.
function Orbit.deckFor(planetId: string): Deck?
	return decks[planetId]
end

--- What Lighting should look like above this world's atmosphere.
function Orbit.skyFor(planetId: string): Sky?
	return skies[planetId]
end

--[[
	Boot check, warned by whoever calls it.

	The failure this is here for is quiet and remote: a deck tuned above the
	ceiling means you reach space *inside* the weather, so the sky turns
	black around you in fog and the one moment the whole feature is built for
	does not happen. Nothing throws, nothing looks broken in Studio, and it
	would be found by a fourteen-year-old flying up and asking why space is
	grey.
]]
function Orbit.validate(): { string }
	local problems = {}

	--[[
		The two ways the map of systems can stop making sense.

		Neither is reachable by editing this file -- they are reachable by
		editing `Planets.WORLD_SPACING`, or by adding a tenth world, or by
		widening a settlement until its relief ring outgrows its own system.
		All three are things somebody will do without ever opening Orbit.luau,
		and the symptom of getting it wrong is a pilot whose sky changes to
		the wrong planet's halfway across the void.
	]]
	if Orbit.SYSTEM_RADIUS * 2 >= Planets.WORLD_SPACING then
		table.insert(
			problems,
			`system radius {Orbit.SYSTEM_RADIUS} overlaps its neighbour at {Planets.WORLD_SPACING} spacing`
		)
	end
	if Orbit.ARRIVAL_RADIUS >= Orbit.SYSTEM_RADIUS then
		table.insert(problems, "arrival radius reaches outside the system it arrives in")
	end

	for _, id in Planets.ids() do
		if Planets.worldRadius(id) >= Orbit.SYSTEM_RADIUS then
			table.insert(problems, `{id}: the world is wider than the system it sits in`)
		end

		local deck = decks[id]
		if deck then
			local ceiling = Orbit.ceilingFor(id)
			local top = deck.altitude + deck.thickness * 0.5
			if top >= ceiling then
				table.insert(
					problems,
					`{id}: cloud deck tops out at {math.floor(top)}, at or above the {ceiling} ceiling`
				)
			end
			if deck.spread <= Planets.worldRadius(id) then
				table.insert(problems, `{id}: cloud deck is narrower than the ground it is meant to hide`)
			end
		elseif Planets.get(id).hasWalkableGround then
			table.insert(problems, `{id}: has ground but no cloud deck`)
		end
	end
	return problems
end

return Orbit
