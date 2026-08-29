--!strict
--[[
	TravelService.luau

	Decides whether you may leave, and what it costs you to.

	WHY THIS IS NOT IN PlayerService
	`PlayerService.travelTo` already existed and already worked -- it moves the
	profile's `currentPlanet` and respawns you at the destination's spawn
	marker. What it had was no caller, which is this codebase's oldest failure
	mode: a complete server system with no way in.

	It also had no policy. Anyone could go anywhere for nothing, which makes
	eight of the nine worlds either a shortcut or a death trap. So the
	mechanical jump stays in PlayerService and the *rules* live here:

		can you afford it        Origins.passageFor, recomputed server-side
		have you waited          a per-origin cooldown on the profile
		will you survive it      the destination's own minLevel

	THE PRICE IS NEVER TAKEN FROM THE CLIENT
	Same rule as ShopService. The galaxy map quotes a fare because a button
	that will not say what it costs is useless, but `travelTo` recomputes it
	from config at the moment of the jump and charges that. Both sides call the
	same pure `Origins.passageFor`, so the quote and the charge cannot drift.

	THE COOLDOWN IS STORED, NOT TIMED
	It lives on the profile as `lastTravelAt` rather than in a table here,
	because an in-memory timer is cleared by rejoining -- and "leave and come
	back" would be a strictly better way to travel than travelling.

	A HULL OF YOUR OWN IS A DIFFERENT PRICE LIST
	Every rule above describes buying a seat on somebody else's ship. Sitting
	at the controls of a starship you own is not that: there is no broker
	taking a cut, no patron doing you a favour and no berth to wait for.
	`fuelFor` below prices those jumps out of `Planets.fuelCost` instead, and
	that one branch is the whole reason to buy a starship -- ROADMAP 2c gave
	the Piloting tree a hull to fly, and this gives the hull somewhere to go.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Factions = require(Shared.Config.Factions)
local Origins = require(Shared.Config.Origins)
local Planets = require(Shared.Config.Planets)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Ships = require(Shared.Config.Ships)

type PlayerProfile = Types.PlayerProfile

local TravelService = {
	name = "TravelService",
	-- After ProgressionService (25), whose credits and Haggler multiplier this
	-- reads on every quote.
	priority = 38,
}

--[[
	How far under a world's own minimum level you may still land there.

	Matches `Planets.suggestedFor`, which offers a world at minLevel - 4, so the
	list the map shows as reachable is the list the server will actually accept.
	This is a refusal rather than the roadmap's "underlevelled warning" on
	purpose: a warning works at a zone boundary you can walk back out of, and
	fast travel has no back-out -- you arrive in the middle of it.
]]
local LEVEL_GRACE = 4

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

local function analytics()
	return ServiceLoader.get("AnalyticsService")
end

--------------------------------------------------------------------------------
-- Quotes
--------------------------------------------------------------------------------

--[[
	Where the player stands with the faction that runs a world.

	Reputation decided three things -- who opens fire (`NPCBrain.isEnemy`),
	which missions are on the board (`Missions.canAccept`) and how an NPC
	greets you (`DialogueService`) -- and the player could see none of it. The
	galaxy map is where it belongs rather than in a screen of its own: a
	standing is only ever a reason to go somewhere or stay away.
]]
export type Standing = {
	faction: string, -- display name, not the id
	rank: string,
	--- Hostile / Neutral / Friendly, as `NPCBrain` will read it on arrival.
	attitude: string,
	rep: number,
	--- Both nil at the top of the ladder.
	nextRank: string?,
	nextAt: number?,
}

export type Destination = {
	id: string,
	displayName: string,
	description: string,
	region: string,
	standing: Standing,
	minLevel: number,
	maxLevel: number,
	credits: number,
	free: boolean,
	note: string,
	current: boolean,
	--- Nil when the player may go. Otherwise the reason they may not.
	locked: string?,
}

local function standingFor(profile: PlayerProfile, factionId: string): Standing
	local def = Factions.get(factionId)
	local rep = profile.factionRep[factionId] or 0
	local index = Factions.rankIndexFor(factionId, rep)
	local ahead = def.ranks[index + 1]
	return {
		faction = def.displayName,
		rank = def.ranks[index].name,
		attitude = Factions.attitudeToward(factionId, profile.factionRep),
		rep = rep,
		nextRank = if ahead then ahead.name else nil,
		nextAt = if ahead then ahead.repRequired else nil,
	}
end

--- Seconds left before this profile may travel again.
local function cooldownLeft(profile: PlayerProfile, now: number): number
	local access = Origins.get(profile.origin).travel
	local elapsed = now - profile.lastTravelAt
	return math.max(0, access.cooldown - elapsed)
end

--[[
	The starship this player is at the controls of, or nil.

	Resolved through the loader rather than required, because the dependency
	only runs one way: travel is a rule and a summoned hull is a fact, and a
	fact should not have to know which rules read it. It also keeps a service
	that failed to load from taking the star map down with it -- without
	VehicleService you are simply a passenger, which is what every character
	was before this commit.
]]
local function ownHull(player: Player): Ships.ShipDef?
	local vehicles = ServiceLoader.find("VehicleService")
	if not vehicles then
		return nil
	end
	local shipId: string? = vehicles.pilotedStarship(player)
	return if shipId then Ships.get(shipId) else nil
end

--[[
	What a jump costs when you are flying it yourself.

	Shaped as an `Origins.Passage` so it can be returned from the same slot
	as a fare and nothing downstream has to branch: the map prints a number
	and a note either way, and the note is the only place the difference
	shows. That matters more than it looks -- `Destination` is replicated to
	the client, and a second field for "is this fuel" would be a second thing
	the two sides could disagree about.

	Three substitutions, and every one of them is the point:

		Planets.fuelCost      not fastTravelCost -- roughly a seventieth
		stats.FuelCostMult    Navigator, not Haggler
		def.fuelMult          the hull, not the origin's broker

	`FUEL_PER_UNIT` was written long before anything could fly and has been
	dead ever since. It is used here exactly as it was defined, so the
	balance it was tuned against is the balance it gets.
]]
local function fuelFor(def: Ships.ShipDef, from: string, to: string, fuelCostMult: number): Origins.Passage
	local credits = math.floor(Planets.fuelCost(from, to, fuelCostMult) * (def.fuelMult or 1) + 0.5)
	return {
		credits = credits,
		-- No cooldown. The origin's is the wait for somebody else's ship to
		-- have a berth free, and your own ship is already on the pad.
		cooldown = 0,
		free = credits <= 0,
		note = `Your {def.displayName}. Fuel only.`,
	}
end

--[[
	Everything the galaxy map draws, for one player.

	Locked worlds are included rather than hidden, for the same reason
	`Missions.boardFor` keeps locked missions: a destination you can see and
	cannot afford is a goal, and one you cannot see is nothing.
]]
local function galaxyFor(player: Player, profile: PlayerProfile): { Destination }
	local now = os.time()
	local stats = progression().getStats(player)
	-- Resolved once, not per destination: it is one seat lookup, and nine of
	-- them would say the same thing.
	local hull = ownHull(player)
	local waiting = if hull then 0 else cooldownLeft(profile, now)
	local priceMult = stats.PriceMult or 1
	local fuelMult = stats.FuelCostMult or 1

	local out: { Destination } = {}
	for _, id in Planets.ids() do
		local planet = Planets.get(id)
		local passage = if hull and id ~= profile.currentPlanet
			then fuelFor(hull, profile.currentPlanet, id, fuelMult)
			else Origins.passageFor(profile.origin, profile.currentPlanet, id, priceMult)

		local locked: string? = nil
		if id == profile.currentPlanet then
			locked = nil
		elseif profile.level + LEVEL_GRACE < planet.minLevel then
			locked = `Requires level {planet.minLevel - LEVEL_GRACE}`
		elseif waiting > 0 then
			locked = `No berth for {math.ceil(waiting / 60)} min`
		elseif profile.credits < passage.credits then
			locked = `Needs {passage.credits} cr`
		end

		table.insert(out, {
			id = id,
			displayName = planet.displayName,
			description = planet.description,
			region = planet.region,
			standing = standingFor(profile, planet.controllingFaction),
			minLevel = planet.minLevel,
			maxLevel = planet.maxLevel,
			credits = passage.credits,
			free = passage.free,
			note = passage.note,
			current = id == profile.currentPlanet,
			locked = locked,
		})
	end

	-- Current world first, then by the level band it is built for: the map
	-- reads as a route through the campaign rather than an alphabet.
	table.sort(out, function(a: Destination, b: Destination)
		if a.current ~= b.current then
			return a.current
		end
		if a.minLevel ~= b.minLevel then
			return a.minLevel < b.minLevel
		end
		return a.displayName < b.displayName
	end)
	return out
end

--------------------------------------------------------------------------------
-- The jump
--------------------------------------------------------------------------------

--- Books passage and goes. Returns false and a reason the player can be shown.
function TravelService.travelTo(player: Player, planetId: string): (boolean, string?)
	if not Planets.exists(planetId) then
		return false, "Unknown destination"
	end
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	if profile.currentPlanet == planetId then
		return false, "You are already here"
	end

	local planet = Planets.get(planetId)
	if profile.level + LEVEL_GRACE < planet.minLevel then
		return false, `{planet.displayName} is beyond you. Requires level {planet.minLevel - LEVEL_GRACE}`
	end

	-- Asked again here rather than trusted from the quote, for the reason the
	-- header gives: this is the side that takes the money. A player who left
	-- the cockpit between opening the map and pressing the button pays a fare.
	local hull = ownHull(player)

	-- Read before the jump. `travelTo` rewrites `currentPlanet`, and the
	-- telemetry below runs after it, so this is the only point at which the
	-- origin of the route still exists.
	local from = profile.currentPlanet

	local now = os.time()
	if not hull then
		local waiting = cooldownLeft(profile, now)
		if waiting > 0 then
			return false, `No berth for another {math.ceil(waiting / 60)} min`
		end
	end

	-- Recomputed from config, never taken from the client.
	local stats = progression().getStats(player)
	local passage = if hull
		then fuelFor(hull, profile.currentPlanet, planetId, stats.FuelCostMult or 1)
		else Origins.passageFor(profile.origin, profile.currentPlanet, planetId, stats.PriceMult or 1)
	if passage.credits > 0 and not progression().spendCredits(player, passage.credits) then
		return false,
			if hull
				then `Fuel for that jump costs {passage.credits} cr`
				else `Passage costs {passage.credits} cr`
	end

	-- Stamped before the jump, because `travelTo` respawns the character and
	-- anything after that is racing the character-added handler. Not stamped
	-- at all when you flew it: the clock counts the wait for a berth, and
	-- charging a Scrapper three minutes of it for using his own ship would
	-- make the ship worse than not having one.
	if not hull then
		data().update(player, function(p: PlayerProfile)
			p.lastTravelAt = now
		end)
	end

	local ok, reason = ServiceLoader.get("PlayerService").travelTo(player, planetId)
	if not ok then
		-- The jump failed after the fare was taken. Refund rather than leave
		-- the player poorer and in the same place.
		if passage.credits > 0 then
			progression().awardCredits(player, passage.credits, true)
		end
		return false, reason
	end

	Net.fireClient(Net.Event.Travelled, player, planetId)
	Net.fireClient(
		Net.Event.Notify,
		player,
		if passage.free
			then `Arrived at {planet.displayName}`
			elseif hull then `Arrived at {planet.displayName} -- {passage.credits} cr of fuel`
			else `Arrived at {planet.displayName} -- {passage.credits} cr`,
		"Success"
	)

	-- The destination is the `planet` column, filled from the profile that
	-- `travelTo` has just updated, so only the origin needs carrying.
	local telemetry = analytics()
	telemetry.log(player, telemetry.Kind.Travel, {
		from = from,
		credits = passage.credits,
		flown = hull ~= nil,
	})
	return true, nil
end

--[[
	Buys the fuel for a crossing the player is going to fly themselves.

	The same trip as `travelTo` and the same gate, minus the arrival: this
	takes the money and names the lane, and the ship covers the twelve
	thousand studs under its own power. Nothing here moves anybody.

	No `lastTravelAt` stamp, for the reason `travelTo` gives -- the cooldown
	is the wait for somebody else's berth, and a pilot has his own.

	The world is built **now**, at the button, not on arrival.
	`PlanetBuilder.build` is fully synchronous -- there is not a single yield
	in six thousand lines -- so raising a world costs one visible hitch
	wherever it is put. Putting it here spends it under the flash of a jump
	the player has just chosen, instead of in the middle of a descent.
]]
function TravelService.setCourse(player: Player, planetId: string): (boolean, string?)
	if not Planets.exists(planetId) then
		return false, "Unknown destination"
	end
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	if profile.currentPlanet == planetId then
		return false, "You are already here"
	end

	local planet = Planets.get(planetId)
	if profile.level + LEVEL_GRACE < planet.minLevel then
		return false, `{planet.displayName} is beyond you. Requires level {planet.minLevel - LEVEL_GRACE}`
	end

	-- Asked here rather than trusted from the quote, exactly as `travelTo`
	-- does: this is the side that takes the money.
	local hull = ownHull(player)
	if not hull then
		local vehicles = ServiceLoader.find("VehicleService")
		return false, if vehicles then vehicles.starshipHint(player) else "Not at the controls of a starship"
	end

	local stats = progression().getStats(player)
	local passage = fuelFor(hull, profile.currentPlanet, planetId, stats.FuelCostMult or 1)
	if passage.credits > 0 and not progression().spendCredits(player, passage.credits) then
		return false, `Fuel for that jump costs {passage.credits} cr`
	end

	ServiceLoader.get("WorldService").ensure(planetId)

	--[[
		The client owns the course from here, and holds no authority by
		holding it. Where the ship ends up is decided by VehicleService's
		position sweep, which reads the hull's actual coordinates once a
		second and has never taken the client's word for anything. A course
		is a heading and a line of text; the fuel for it is already spent.
	]]
	Net.fireClient(Net.Event.CourseSet, player, planetId)
	Net.fireClient(
		Net.Event.Notify,
		player,
		`Course laid in for {planet.displayName}. Reach orbit, then hold {Ships.ENGAGE_CAP}.`,
		"Success"
	)

	local telemetry = analytics()
	telemetry.log(player, telemetry.Kind.Travel, {
		from = profile.currentPlanet,
		credits = passage.credits,
		flown = true,
	})
	return true, nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function TravelService.init()
	Net.onServerInvoke(Net.Function.GetGalaxy, function(player: Player)
		local profile = data().get(player)
		if not profile then
			return nil
		end
		local origin = Origins.get(profile.origin)
		-- The header line names whoever is actually carrying you. Sitting in
		-- your own cockpit, that is the ship -- and the origin's blurb about
		-- begging a ride off the Empire would be a lie at that moment.
		local hull = ownHull(player)
		return {
			credits = profile.credits,
			level = profile.level,
			currentPlanet = profile.currentPlanet,
			originName = if hull then hull.displayName else origin.displayName,
			originNote = if hull
				then "You are at the controls. Jumps cost fuel and nothing else."
				else origin.travelBlurb,
			cooldownLeft = if hull then 0 else cooldownLeft(profile, os.time()),
			-- Whether the button on each row says SET COURSE or TRAVEL. The
			-- star map's instant jump stays for everyone without a hull:
			-- three of the four origins do not start with one, and gating the
			-- galaxy behind 30,000 credits would strand them. Owning a
			-- starship changes *how* you travel, not whether you can.
			canFly = hull ~= nil,
			destinations = galaxyFor(player, profile),
		}
	end, {
		rateLimit = 4,
		validate = Net.check.none,
	})

	Net.onServerEvent(Net.Event.TravelTo, function(player: Player, planetId: string)
		local ok, reason = TravelService.travelTo(player, planetId)
		if not ok and reason then
			Net.fireClient(Net.Event.Notify, player, reason, "Error")
		end
	end, {
		-- Deliberately slower than the shop's 4/s: this respawns a character
		-- and can build a world.
		rateLimit = 1,
		validate = Net.args(Net.check.string(64)),
	})

	Net.onServerEvent(Net.Event.SetCourse, function(player: Player, planetId: string)
		local ok, reason = TravelService.setCourse(player, planetId)
		if not ok and reason then
			Net.fireClient(Net.Event.Notify, player, reason, "Error")
		end
	end, {
		-- Same rate as a jump, for the same reason: it can build a world.
		rateLimit = 1,
		validate = Net.args(Net.check.string(64)),
	})
end

return TravelService
