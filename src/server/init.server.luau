--!strict
--[[
	Server entry point.

	Deliberately tiny. Everything the game does lives in a service under
	Services/, and the only job here is to hand that folder to the loader and
	let it run the two boot phases in priority order.

	The one thing this file does own is pre-warming the rig templates. Building
	a HumanoidDescription rig yields, so the first stormtrooper on an unwarmed
	server costs a visible hitch; doing it before anyone can join moves that
	cost to a moment when nobody is watching.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local NPCArchetypes = require(Shared.Config.NPCArchetypes)
local Planets = require(Shared.Config.Planets)
local RigBuilder = require(Shared.Rig.RigBuilder)
local ServiceLoader = require(Shared.Core.ServiceLoader)

--[[
	Builds templates for every archetype that can appear on `planetId`.

	Only the starting planet is warmed at boot. Warming all eight would build
	over a hundred templates for worlds nobody has travelled to yet.
]]
local function precachePlanet(planetId: string)
	local combos: { { species: string, costume: string? } } = {}
	local seen: { [string]: boolean } = {}

	for _, rule in Planets.get(planetId).spawns do
		if not NPCArchetypes.exists(rule.archetype) then
			continue
		end
		local archetype = NPCArchetypes.get(rule.archetype)
		for _, entry in archetype.speciesPool do
			local key = `{entry.species}|{archetype.costume}`
			if not seen[key] then
				seen[key] = true
				table.insert(combos, { species = entry.species, costume = archetype.costume })
			end
		end
	end

	RigBuilder.precache(combos)
end

-- Before any service registers a handler, so no client can be left waiting on
-- a remote that does not exist yet.
Net.ensureRemotes()

ServiceLoader.addFrom(script.Services)
ServiceLoader.start()

task.spawn(precachePlanet, Planets.STARTING_PLANET)
