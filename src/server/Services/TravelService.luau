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
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Origins = require(Shared.Config.Origins)
local Planets = require(Shared.Config.Planets)
local ServiceLoader = require(Shared.Core.ServiceLoader)

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

--------------------------------------------------------------------------------
-- Quotes
--------------------------------------------------------------------------------

export type Destination = {
	id: string,
	displayName: string,
	description: string,
	region: string,
	controllingFaction: string,
	minLevel: number,
	maxLevel: number,
	credits: number,
	free: boolean,
	note: string,
	current: boolean,
	--- Nil when the player may go. Otherwise the reason they may not.
	locked: string?,
}

--- Seconds left before this profile may travel again.
local function cooldownLeft(profile: PlayerProfile, now: number): number
	local access = Origins.get(profile.origin).travel
	local elapsed = now - profile.lastTravelAt
	return math.max(0, access.cooldown - elapsed)
end

--[[
	Everything the galaxy map draws, for one player.

	Locked worlds are included rather than hidden, for the same reason
	`Missions.boardFor` keeps locked missions: a destination you can see and
	cannot afford is a goal, and one you cannot see is nothing.
]]
local function galaxyFor(player: Player, profile: PlayerProfile): { Destination }
	local now = os.time()
	local waiting = cooldownLeft(profile, now)
	local priceMult = progression().getStats(player).PriceMult or 1

	local out: { Destination } = {}
	for _, id in Planets.ids() do
		local planet = Planets.get(id)
		local passage = Origins.passageFor(profile.origin, profile.currentPlanet, id, priceMult)

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
			controllingFaction = planet.controllingFaction,
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

	local now = os.time()
	local waiting = cooldownLeft(profile, now)
	if waiting > 0 then
		return false, `No berth for another {math.ceil(waiting / 60)} min`
	end

	-- Recomputed from config, never taken from the client.
	local priceMult = progression().getStats(player).PriceMult or 1
	local passage = Origins.passageFor(profile.origin, profile.currentPlanet, planetId, priceMult)
	if passage.credits > 0 and not progression().spendCredits(player, passage.credits) then
		return false, `Passage costs {passage.credits} cr`
	end

	-- Stamped before the jump, because `travelTo` respawns the character and
	-- anything after that is racing the character-added handler.
	data().update(player, function(p: PlayerProfile)
		p.lastTravelAt = now
	end)

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
			else `Arrived at {planet.displayName} -- {passage.credits} cr`,
		"Success"
	)
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
		return {
			credits = profile.credits,
			level = profile.level,
			currentPlanet = profile.currentPlanet,
			originName = origin.displayName,
			originNote = origin.travelBlurb,
			cooldownLeft = cooldownLeft(profile, os.time()),
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
end

return TravelService
