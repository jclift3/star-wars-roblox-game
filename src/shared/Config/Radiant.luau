--!strict
--[[
	Radiant.luau

	Missions composed from the world instead of written by hand.

	WHY
	There are 15 authored missions across 9 planets, and 4 of those planets have
	none at all. Writing 100 more is not the answer -- the world already says
	where the trouble is (`PlanetDef.spawns`), where the places are
	(`pointsOfInterest`) and how hard each district is (`Planets.bandFor`).
	A mission is those three facts and a verb. So take them.

	These are the filler between the story beats, and they are priced like it:
	`REWARD_SCALE` per template is deliberately under what an authored mission
	pays, so grinding the board never beats following the spine.

	PURE, AND WHY THAT MATTERS
	Generation runs once at require time and depends on nothing but the other
	Config tables, so the server and every client build byte-identical
	definitions. That is load-bearing: `MissionService` sends the board as a
	list of *ids* and the client resolves each one out of `Missions` itself. A
	generator that consulted the clock or a Random would hand the client an id
	it could not look up.

	Ids are `@r:<planet>:<zone>:<template>`. Prefixed because `profile.missions
	.completed` is keyed by id and outlives any change here; bounded and stable
	because a save full of `@r:Tatooine:DuneSea:Cull` entries stays meaningful,
	whereas one keyed by date would grow forever and mean nothing.

	Which of them are *posted* is the only time-dependent part, and it lives in
	`postedOn` -- see the note there about why rotation is per-day and not per
	player.
]]

local Items = require(script.Parent.Items)
local MissionKinds = require(script.Parent.MissionKinds)
local NPCArchetypes = require(script.Parent.NPCArchetypes)
local Planets = require(script.Parent.Planets)

type MissionDef = MissionKinds.MissionDef

local Radiant = {}

local Objective = MissionKinds.Objective

--- Marks an id as generated. Authored ids may not start with it.
Radiant.PREFIX = "@r:"

--- How many generated missions a planet's board shows at once.
Radiant.POSTED_PER_DAY = 3
Radiant.DAY = 86400
--- Long enough that a radiant mission is a thing you did, not a lever.
Radiant.COOLDOWN = 3600

local CULL_COUNT = 6
local SALVAGE_COUNT = 4

--- Fraction of the standard payout each template earns, by how much work it is.
local REWARD_SCALE: { [string]: number } = {
	Cull = 1,
	Salvage = 0.9,
	Survey = 0.45,
}

--[[
	Only wilderness gets a Survey.

	`ZoneDef.distance` is a multiple of the settlement radius, so 1 is the edge
	of town -- and "walk to the market" is not a mission.
]]
local SURVEY_MIN_DISTANCE = 1

--- What you dig out of a given kind of place. Defaults to `RawOre`.
local SALVAGE_ITEM: { [string]: string } = {
	Spaceport = "PowerCoupling",
	Cantina = "SpiceCrate",
	Market = "SpiceCrate",
	Base = "PowerCoupling",
	Temple = "ResearchData",
	Ruin = "PowerCoupling",
	Outpost = "RawOre",
}

--------------------------------------------------------------------------------
-- Reading the world
--------------------------------------------------------------------------------

--- "DuneSea" -> "Dune Sea". A zone id is the only name a district has.
local function prettify(id: string): string
	return (id:gsub("(%l)(%u)", "%1 %2"))
end

--[[
	Whoever hands these out on `planet`.

	`DialogueService.offersFor` matches the giver against the archetype of
	whoever you are talking to, so this is not cosmetic: it decides who in the
	world will actually hand the mission over rather than it living only on the
	board. Hence the preference order -- someone who stands where you left them
	beats someone who wanders off. Only four archetypes are QuestGivers, so
	without the vendor tier most planets would land on whoever their first
	spawn rule happened to name, and Tatooine's bounties would be issued by a
	Jawa halfway out into the Wastes.

	Returns nil when the planet has nobody interactable at all, and it then
	gets no radiant missions -- they would be unturninable.
]]
local GIVER_RANK: { [string]: number } = {
	QuestGiver = 3,
	Vendor = 2,
}

local function giverFor(p: Planets.PlanetDef): string?
	local best: string? = nil
	local bestRank = -1
	for _, rule in p.spawns do
		if not NPCArchetypes.exists(rule.archetype) then
			continue
		end
		local a = NPCArchetypes.get(rule.archetype)
		if not a.interactable then
			continue
		end
		local rank = GIVER_RANK[a.behavior] or 1
		if rank > bestRank then
			best, bestRank = a.id, rank
		end
	end
	return best
end

local function poiIn(p: Planets.PlanetDef, zoneId: string): Planets.PointOfInterest?
	for _, poi in p.pointsOfInterest do
		if poi.zone == zoneId then
			return poi
		end
	end
	return nil
end

--[[
	Where deliveries go: the point of interest nearest the middle of town.

	`zones` is declared centre-outward, so the first one with a place in it is
	the most central place on the planet -- and hauling salvage inward is the
	direction that reads as coming home.
]]
local function hubFor(p: Planets.PlanetDef): Planets.PointOfInterest?
	for _, zone in p.zones do
		local poi = poiIn(p, zone.id)
		if poi then
			return poi
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local defs: { [string]: MissionDef } = {}
--- Radiant ids per planet, sorted, so `postedOn` rotates a stable list.
local byPlanet: { [string]: { string } } = {}

local function rewards(template: string, level: number): MissionKinds.Rewards
	local scale = REWARD_SCALE[template] or 1
	return {
		xp = math.floor((40 + level * 10) * scale),
		credits = math.floor((55 + level * 16) * scale),
	}
end

local function add(m: MissionDef)
	defs[m.id] = m
	local list = byPlanet[m.planet]
	if not list then
		list = {}
		byPlanet[m.planet] = list
	end
	table.insert(list, m.id)
end

local function buildPlanet(p: Planets.PlanetDef)
	local giver = giverFor(p)
	if not giver then
		return
	end
	local giverName = NPCArchetypes.get(giver).displayName
	local hub = hubFor(p)

	for _, zone in p.zones do
		local where = prettify(zone.id)
		local band = Planets.bandFor(p.id, zone.id)
		local poi = poiIn(p, zone.id)
		local id = `{Radiant.PREFIX}{p.id}:{zone.id}:`

		local hostile = NPCArchetypes.hostileIn(p.spawns, zone.id)
		if hostile then
			local enemy = NPCArchetypes.get(hostile).displayName
			add({
				id = id .. "Cull",
				displayName = `Thinning the {where}`,
				summary = `Kill {CULL_COUNT} {enemy} in the {where}.`,
				briefing = `Nobody works the {where} while that lot hold it. Bring the number down and we can start again.`,
				debriefing = "That will hold for a while. It never holds for long.",
				kind = "Bounty",
				faction = p.controllingFaction,
				planet = p.id,
				giver = giver,
				minLevel = band.min,
				objectives = {
					{
						kind = Objective.Kill,
						target = hostile,
						count = CULL_COUNT,
						planet = p.id,
						description = `Kill {CULL_COUNT} {enemy} in the {where}`,
					},
				},
				rewards = rewards("Cull", band.min),
				repeatable = true,
				cooldown = Radiant.COOLDOWN,
			})
		end

		-- Salvage needs somewhere to dig and somewhere else to carry it to.
		-- The hub's own district is where the cargo ends up, so it cannot
		-- also be where it starts.
		if poi and hub and hub.id ~= poi.id then
			local item = SALVAGE_ITEM[poi.kind] or "RawOre"
			local itemName = Items.nameOf(item)
			add({
				id = id .. "Salvage",
				displayName = `Salvage from {poi.displayName}`,
				summary = `Recover {SALVAGE_COUNT} {itemName} from {poi.displayName} and bring them to {hub.displayName}.`,
				briefing = `There is still good cargo sitting at {poi.displayName}. It is not going to walk back here on its own.`,
				debriefing = "Good haul. Same rate next time, if you are still standing.",
				kind = "Delivery",
				faction = p.controllingFaction,
				planet = p.id,
				giver = giver,
				minLevel = band.min,
				objectives = {
					{
						kind = Objective.Collect,
						target = item,
						at = poi.id,
						count = SALVAGE_COUNT,
						planet = p.id,
						description = `Recover {SALVAGE_COUNT} {itemName} from {poi.displayName}`,
					},
					{
						kind = Objective.Deliver,
						target = item,
						destination = hub.id,
						count = SALVAGE_COUNT,
						planet = p.id,
						description = `Carry them to {hub.displayName}`,
					},
				},
				rewards = rewards("Salvage", band.min),
				repeatable = true,
				cooldown = Radiant.COOLDOWN,
			})
		end

		if poi and zone.distance >= SURVEY_MIN_DISTANCE then
			add({
				id = id .. "Survey",
				displayName = `Survey: {poi.displayName}`,
				summary = `Travel out to {poi.displayName} in the {where} and report what is there.`,
				briefing = `{giverName} wants eyes on {poi.displayName}. Nobody has been out that far in a while, and that is usually how bad news starts.`,
				debriefing = "Good. Now we know what is out there.",
				kind = "Side",
				faction = p.controllingFaction,
				planet = p.id,
				giver = giver,
				minLevel = band.min,
				objectives = {
					{
						kind = Objective.Reach,
						target = poi.id,
						planet = p.id,
						description = `Reach {poi.displayName}`,
					},
				},
				rewards = rewards("Survey", band.min),
				repeatable = true,
				cooldown = Radiant.COOLDOWN,
			})
		end
	end
end

for _, planetId in Planets.ids() do
	buildPlanet(Planets.get(planetId))
end
for _, list in byPlanet do
	table.sort(list)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Radiant.isRadiant(id: string): boolean
	return id:sub(1, #Radiant.PREFIX) == Radiant.PREFIX
end

--- Every generated mission, for `Missions` to fold in alongside the authored ones.
function Radiant.all(): { [string]: MissionDef }
	return defs
end

--[[
	The generated missions posted on `planetId` on the day containing `now`.

	Rotation is by day and not per player on purpose. A mission board is a
	place in the world -- two players standing at the same one and reading
	different postings is a bug however it got there, and it makes "go and take
	the bounty I just took" impossible to say out loud. Which matters here
	specifically, because this game is played by two brothers in the same room.

	The window advances by one a day rather than a whole page, so the board is
	recognisable from yesterday and still eventually shows everything -- a
	stride of `POSTED_PER_DAY` would cycle through a fraction of the list and
	never reach the rest.
]]
function Radiant.postedOn(planetId: string, now: number): { string }
	local list = byPlanet[planetId]
	if not list or #list <= Radiant.POSTED_PER_DAY then
		return if list then table.clone(list) else {}
	end
	local day = math.floor(now / Radiant.DAY)
	local out = {}
	for i = 0, Radiant.POSTED_PER_DAY - 1 do
		table.insert(out, list[(day + i) % #list + 1])
	end
	return out
end

return Radiant
