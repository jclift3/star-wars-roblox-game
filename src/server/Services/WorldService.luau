--!strict
--[[
	WorldService.luau

	Owns the physical existence of the planets.

	PlanetBuilder knows how to make a world; this decides when. The rule is
	simple: a planet is built the first time somebody needs to stand on it, and
	then it stays. Building is not free, but it is a one-off, and tearing a
	world down to save parts would mean paying that cost again every time a
	player flew back -- exactly the moment you least want a hitch.

	That is deliberately different from NPCService, which does depopulate empty
	worlds. Crowds cost every frame; geometry costs once.

	The starting planet is built during init(), before any player can join, so
	the very first spawn already has ground under it.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Affixes = require(Shared.Config.Affixes)
local Crystals = require(Shared.Config.Crystals)
local Factions = require(Shared.Config.Factions)
local Orbit = require(Shared.Config.Orbit)
local Origins = require(Shared.Config.Origins)
local Planets = require(Shared.Config.Planets)
local Progression = require(Shared.Config.Progression)
local Weapons = require(Shared.Config.Weapons)
local Bindings = require(Shared.Core.Bindings)
local PlanetBuilder = require(script.Parent.Parent.World.PlanetBuilder)

local WorldService = {
	name = "WorldService",
	-- Ahead of PlayerService (20), because a character is repositioned onto
	-- this service's spawn markers the moment it loads.
	priority = 5,
}

local built: { [string]: boolean } = {}

--[[
	Guarantees `planetId` exists in Workspace before anyone is placed on it.

	Cheap to call on every spawn and every arrival -- the second call onward is
	a table lookup.
]]
function WorldService.ensure(planetId: string)
	if built[planetId] or not Planets.exists(planetId) then
		return
	end
	built[planetId] = true

	-- Marked built even on failure, and deliberately not retried: generation is
	-- deterministic, so a second attempt with the same seed fails identically.
	-- Retrying would only turn one warning into one per spawn.
	local ok, err = pcall(PlanetBuilder.build :: any, planetId)
	if not ok then
		warn(`[WorldService] failed to build "{planetId}": {err}`)
	end
end

function WorldService.init()
	-- Before anything is built: a district named by a spawn rule but never
	-- declared puts its NPCs nowhere in particular, and nothing downstream can
	-- tell that from a district that is simply empty.
	for _, problem in
		Planets.validate(
			PlanetBuilder.prefabExists,
			PlanetBuilder.prefabHasRoom,
			PlanetBuilder.landmarkExists
		)
	do
		warn(`[WorldService] planet config: {problem}`)
	end

	-- What is above the planets, checked in the same breath as the planets.
	-- A cloud deck tuned above the flight ceiling means the sky turns black
	-- while the ship is still inside the weather, which is invisible from the
	-- ground, invisible in Studio, and the whole point of the climb.
	for _, problem in Orbit.validate() do
		warn(`[WorldService] orbit config: {problem}`)
	end

	-- Two things on one key is not an error Roblox reports: it is both
	-- handlers firing, or one quietly losing, and from the player's side it
	-- looks like the game ignoring them.
	for _, problem in Bindings.validate() do
		warn(`[WorldService] key bindings: {problem}`)
	end

	-- Checked here rather than in a faction service because this is where the
	-- planet list lives: a faction whose capital was deleted is a travel
	-- destination that silently does not exist.
	for _, problem in Factions.validate(Planets.exists) do
		warn(`[WorldService] faction config: {problem}`)
	end

	-- An origin names a home world, a faction and a skill tree, and its travel
	-- rules are read every time anybody opens the galaxy map.
	for _, problem in Origins.validate(Progression.hasTree) do
		warn(`[WorldService] origin config: {problem}`)
	end

	-- The rule from ROADMAP B5, checked rather than remembered: a skill that
	-- takes a point and moves a stat nothing reads is the worst kind of dead
	-- system, because the player pays for it.
	for _, problem in Progression.validate() do
		warn(`[WorldService] skill config: {problem}`)
	end

	-- The same rule, one system over: an affix whose stat nothing reads is a
	-- drop that shows the player a number and then does nothing with it.
	for _, problem in Affixes.validate(Progression.LIVE_STATS, Weapons.classes()) do
		warn(`[WorldService] affix config: {problem}`)
	end

	-- And the same rule once more, tightened. A crystal has to clear a bar an
	-- affix does not: not merely "something reads this stat" but "something
	-- reads it on the kind of item this crystal is sitting in". A cooldown
	-- crystal in a lightsaber passes every check above and does nothing at all.
	for _, problem in Crystals.validate(Progression.LIVE_STATS) do
		warn(`[WorldService] crystal config: {problem}`)
	end

	WorldService.ensure(Planets.STARTING_PLANET)
end

return WorldService
