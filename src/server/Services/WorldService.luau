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
local Factions = require(Shared.Config.Factions)
local Planets = require(Shared.Config.Planets)
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
	for _, problem in Planets.validate() do
		warn(`[WorldService] planet config: {problem}`)
	end

	-- Checked here rather than in a faction service because this is where the
	-- planet list lives: a faction whose capital was deleted is a travel
	-- destination that silently does not exist.
	for _, problem in Factions.validate(Planets.exists) do
		warn(`[WorldService] faction config: {problem}`)
	end

	WorldService.ensure(Planets.STARTING_PLANET)
end

return WorldService
