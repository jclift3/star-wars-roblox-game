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
	for _, id in Planets.ids() do
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
