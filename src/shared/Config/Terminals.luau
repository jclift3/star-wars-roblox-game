--!strict
--[[
	Terminals.luau

	The locked things in the galaxy, and what it takes to open one.

	WHY THIS EXISTS
	`Slicer` has been in the Engineering tree since the tree was written, five
	ranks deep, describing itself as "unlocks slicing terminals and locked
	doors" -- and there has never been a terminal. It was marked
	`unimplemented` and honest about it, which is better than lying, but a
	skill that costs five points and does nothing is still a skill nobody can
	build a character around. This is the world it was always describing.

	It is also the answer to a narrower question the skill trees keep asking:
	every other live stat makes a fight shorter. `SliceTier` is the first that
	changes what is *there* -- a Scrapper walks past a security console at the
	spaceport and can open it, and a Sith Acolyte standing in the same spot
	cannot. That asymmetry is the point, and it is why the tier is shown on
	the console rather than only in the refusal.

	NOTHING HERE IS AUTHORED
	There is no list of terminals. A point of interest carries one if its
	`kind` is somewhere that would plausibly be locked, and the tier comes
	from the level band of the district it stands in. So a planet added
	tomorrow is sliceable tomorrow, and it is impossible for this file to name
	a place that does not exist -- the same bargain `Loot` makes with the
	weapon catalogue and `Radiant` makes with the spawn tables.

	The cost of that bargain is that a terminal cannot be put somewhere
	special by hand. That is the right trade today: the alternative shipped
	four missions whose kill targets never spawned.
]]

local Planets = require(script.Parent.Planets)

local Terminals = {}

--[[
	The highest tier a lock can have, which is also `Slicer`'s `maxRank`.

	The two must agree or one end of the skill is unreachable: a tier 6 lock
	nobody could ever open, or a fifth rank that opens nothing new. Asserted
	in `Terminals.validate`.
]]
Terminals.MAX_TIER = 5

--[[
	How long a cracked terminal stays cracked.

	Long, and shared by everyone on the server rather than tracked per player.
	The two brothers play in one room: a console one of them has already
	opened must read as open to the other, or the world is not a place they
	are both standing in. It also means there is no per-player set of opened
	terminals to carry in a profile forever.

	Ten minutes is long enough that camping one console is worse than playing
	the game -- see `creditsFor` -- and short enough that a district is not
	permanently spent for whoever walks in second.
]]
Terminals.COOLDOWN = 600

--[[
	Which kinds of place keep something locked, and what the lock is called.

	Cantinas and markets are deliberately absent. A market stall with a
	security console in it is a slot machine, not a place; the locked things
	belong where there is something worth locking up, and the flavour name is
	how the player tells a spaceport's manifest terminal from a tomb's
	seal without reading a tooltip.
]]
local SECURED: { [string]: string } = {
	Spaceport = "Docking Manifest",
	Base = "Security Console",
	Outpost = "Supply Locker",
	Ruin = "Derelict Datacore",
	Temple = "Sealed Vault",
}

export type TerminalDef = {
	planet: string,
	--[[
		The point of interest this stands at, which is also the terminal's id.

		One per place, so a `Slice` objective names the POI and there is no
		second namespace of terminal ids to keep in step with the first. It
		is the same id `Reach` already uses, which is what lets
		`Missions.validate` check a Slice target with the machinery already
		there.
	]]
	poi: string,
	displayName: string,
	kind: string,
	tier: number,
	--[[
		The level of the district, not of whoever is standing in it.

		The payout is what the place is worth. A level 30 character slicing a
		starter world's supply locker should be looting a starter world, the
		same reasoning `Loot.rollDrop` uses for the level of a kill.
	]]
	level: number,
}

--[[
	The highest level any world in the galaxy goes to.

	Measured rather than declared, and measured against the *planets* rather
	than `Progression.MAX_LEVEL`: the cap is 50 and no world bands past 30, so
	dividing the character cap into five would put every lock in the galaxy in
	the bottom three tiers and leave two ranks of Slicer with nothing to open.
	Deriving it from the map means the tiers stay spread across whatever the
	map actually is.
]]
local CEILING = (function(): number
	local top = 1
	for _, id in Planets.ids() do
		top = math.max(top, Planets.get(id).maxLevel)
	end
	return top
end)()

--[[
	The tier of a lock in a district whose band starts at `bandMin`.

	Straight off the level band, so difficulty and remoteness carry the lock
	with them and no district has to declare one. Rank 1 of Slicer -- which
	cannot be bought before level 6 -- opens everything on the starter worlds,
	and the fifth rank is for the far end of the map.
]]
local function tierFor(bandMin: number): number
	local slice = CEILING / Terminals.MAX_TIER
	return math.clamp(math.ceil(bandMin / slice), 1, Terminals.MAX_TIER)
end

--- The terminal at `poiId`, or nil if that place keeps nothing locked.
function Terminals.at(planetId: string, poiId: string): TerminalDef?
	if not Planets.exists(planetId) then
		return nil
	end
	-- Coruscant is skyline and traffic lanes with no ground under them. A
	-- console there is a console nobody can walk up to.
	if not Planets.get(planetId).hasWalkableGround then
		return nil
	end
	local poi = Planets.getPOI(planetId, poiId)
	if not poi then
		return nil
	end
	local lockName = SECURED[poi.kind]
	if not lockName then
		return nil
	end
	--[[
		A point of interest with no district has no band, and `bandFor` would
		hand back the whole planet's range -- which would make the lock as
		hard as the planet's worst corner for no stated reason. Planets
		already warns about a POI with no zone; here it simply has no lock.
	]]
	local zoneId = poi.zone
	if not zoneId then
		return nil
	end
	local band = Planets.bandFor(planetId, zoneId)
	return {
		planet = planetId,
		poi = poiId,
		displayName = `{poi.displayName} {lockName}`,
		kind = poi.kind,
		tier = tierFor(band.min),
		level = band.max,
	}
end

--- Every terminal on one world, in the order its points of interest are declared.
function Terminals.forPlanet(planetId: string): { TerminalDef }
	local out: { TerminalDef } = {}
	if not Planets.exists(planetId) then
		return out
	end
	for _, poi in Planets.get(planetId).pointsOfInterest do
		local def = Terminals.at(planetId, poi.id)
		if def then
			table.insert(out, def)
		end
	end
	return out
end

--[[
	What cracking one pays.

	Deliberately modest, and deliberately not a loot table. The reward for
	slicing is *access* -- a mission step nobody else can take, a line the
	shopkeeper only says to someone who could open his back room -- and if the
	credits were good enough to farm, the access would become the side effect.
	At the shipped cooldown a tier 5 console pays less per hour than fighting
	the things standing next to it.
]]
function Terminals.creditsFor(def: TerminalDef): number
	return 40 + def.level * 12 + def.tier * 25
end

function Terminals.xpFor(def: TerminalDef): number
	return 15 + def.level * 6
end

--[[
	Cross-checks the derivation against the skill that is supposed to satisfy it.

	Two ways this can silently break, and neither raises anything at runtime:
	`Slicer` growing a sixth rank that opens nothing, and the galaxy's hardest
	lock falling short of its last rank. Either leaves a skill the player pays
	points for and can never finish spending.

	It does *not* complain about a gap in the middle. A tier nothing happens to
	use is a tuning accident and costs the player one rank on the way past;
	a top rank that opens nothing anywhere is the skill lying again, which is
	the thing this whole file was written to stop.
]]
function Terminals.validate(slicerMaxRank: number): { string }
	local problems = {}
	if slicerMaxRank ~= Terminals.MAX_TIER then
		table.insert(problems, `Slicer has {slicerMaxRank} ranks but locks go to tier {Terminals.MAX_TIER}`)
	end

	local hardest = 0
	local total = 0
	for _, planetId in Planets.ids() do
		for _, def in Terminals.forPlanet(planetId) do
			hardest = math.max(hardest, def.tier)
			total += 1
		end
	end
	if total == 0 then
		table.insert(problems, "no point of interest in the galaxy carries a terminal")
	elseif hardest < Terminals.MAX_TIER then
		table.insert(
			problems,
			`the hardest lock in the galaxy is tier {hardest}, so Slicer ranks {hardest + 1}-{Terminals.MAX_TIER} open nothing`
		)
	end

	table.sort(problems)
	return problems
end

return Terminals
