--!strict
--[[
	Factions.luau

	Faction identities, rank ladders and the reputation matrix.

	Reputation is the connective tissue of the sandbox: shooting a stormtrooper
	should make Imperial NPCs hostile AND nudge the Rebels toward friendly. The
	`spillover` table encodes that, so a single reputation change ripples
	sensibly through the galaxy instead of being tracked per-faction by hand.
]]

local Palette = require(script.Parent.Palette)

local Factions = {}

export type Rank = {
	name: string,
	repRequired: number,
	creditStipend: number,
}

export type FactionDef = {
	id: string,
	displayName: string,
	color: Color3,
	description: string,
	ranks: { Rank },
	homePlanet: string,
	-- Reputation change with OTHER factions per +1 with this one.
	spillover: { [string]: number },
}

local defs: { [string]: FactionDef } = {}

defs.Empire = {
	id = "Empire",
	displayName = "Galactic Empire",
	color = Palette.ImperialGrey,
	description = "Order through strength. Well-paid, well-armed, and widely feared.",
	homePlanet = "Coruscant",
	ranks = {
		{ name = "Recruit", repRequired = 0, creditStipend = 0 },
		{ name = "Trooper", repRequired = 250, creditStipend = 100 },
		{ name = "Corporal", repRequired = 750, creditStipend = 250 },
		{ name = "Sergeant", repRequired = 1800, creditStipend = 500 },
		{ name = "Lieutenant", repRequired = 3500, creditStipend = 900 },
		{ name = "Captain", repRequired = 6000, creditStipend = 1500 },
		{ name = "Commander", repRequired = 10000, creditStipend = 2400 },
		{ name = "Admiral", repRequired = 16000, creditStipend = 4000 },
		{ name = "Grand Moff", repRequired = 25000, creditStipend = 7000 },
	},
	spillover = { Rebellion = -0.75, Hutt = -0.1, Republic = -0.5 },
}

defs.Rebellion = {
	id = "Rebellion",
	displayName = "Rebel Alliance",
	color = Palette.RebelOrange,
	description = "Outgunned and outnumbered. Fights for the galaxy it remembers.",
	homePlanet = "Hoth",
	ranks = {
		{ name = "Sympathiser", repRequired = 0, creditStipend = 0 },
		{ name = "Volunteer", repRequired = 250, creditStipend = 100 },
		{ name = "Private", repRequired = 750, creditStipend = 250 },
		{ name = "Corporal", repRequired = 1800, creditStipend = 500 },
		{ name = "Lieutenant", repRequired = 3500, creditStipend = 900 },
		{ name = "Captain", repRequired = 6000, creditStipend = 1500 },
		{ name = "Commander", repRequired = 10000, creditStipend = 2400 },
		{ name = "General", repRequired = 16000, creditStipend = 4000 },
		{ name = "Alliance Hero", repRequired = 25000, creditStipend = 7000 },
	},
	spillover = { Empire = -0.75, Hutt = -0.2, Republic = 0.4 },
}

defs.Hutt = {
	id = "Hutt",
	displayName = "Hutt Cartel",
	color = Palette.DroidGold,
	description = "Smugglers, slavers and spice. Loyalty is priced by the kilo.",
	homePlanet = "Tatooine",
	ranks = {
		{ name = "Nobody", repRequired = 0, creditStipend = 0 },
		{ name = "Runner", repRequired = 300, creditStipend = 150 },
		{ name = "Smuggler", repRequired = 900, creditStipend = 350 },
		{ name = "Fixer", repRequired = 2000, creditStipend = 700 },
		{ name = "Lieutenant", repRequired = 4000, creditStipend = 1200 },
		{ name = "Underboss", repRequired = 7000, creditStipend = 2000 },
		{ name = "Kajidii", repRequired = 12000, creditStipend = 3500 },
	},
	spillover = { Empire = -0.1, Rebellion = -0.2 },
}

defs.Republic = {
	id = "Republic",
	displayName = "Old Republic Remnant",
	color = Palette.SaberBlue,
	description = "Jedi survivors and loyalists keeping the old order alive in hiding.",
	homePlanet = "Naboo",
	ranks = {
		{ name = "Initiate", repRequired = 0, creditStipend = 0 },
		{ name = "Padawan", repRequired = 400, creditStipend = 120 },
		{ name = "Knight", repRequired = 1500, creditStipend = 400 },
		{ name = "Guardian", repRequired = 3500, creditStipend = 850 },
		{ name = "Master", repRequired = 8000, creditStipend = 1800 },
		{ name = "Council Member", repRequired = 15000, creditStipend = 3500 },
	},
	spillover = { Empire = -0.5, Rebellion = 0.4 },
}

defs.Independent = {
	id = "Independent",
	displayName = "Independent",
	color = Palette.WornSteel,
	description = "No flag, no orders, no backup.",
	homePlanet = "Tatooine",
	ranks = {
		{ name = "Drifter", repRequired = 0, creditStipend = 0 },
	},
	spillover = {},
}

--------------------------------------------------------------------------------

Factions.defs = defs
Factions.DEFAULT = "Independent"

-- Reputation thresholds that drive NPC behaviour.
Factions.HOSTILE_BELOW = -500
Factions.FRIENDLY_ABOVE = 500
Factions.REP_MIN = -10000
Factions.REP_MAX = 25000

function Factions.get(id: string): FactionDef
	local def = defs[id]
	assert(def, `Factions.get: unknown faction "{id}"`)
	return def
end

function Factions.exists(id: string): boolean
	return defs[id] ~= nil
end

--- Highest rank whose requirement the given reputation satisfies.
function Factions.rankFor(factionId: string, rep: number): Rank
	local def = Factions.get(factionId)
	local best = def.ranks[1]
	for _, rank in def.ranks do
		if rep >= rank.repRequired then
			best = rank
		end
	end
	return best
end

function Factions.rankIndexFor(factionId: string, rep: number): number
	local def = Factions.get(factionId)
	local index = 1
	for i, rank in def.ranks do
		if rep >= rank.repRequired then
			index = i
		end
	end
	return index
end

--[[
	Applies a reputation change and its knock-on effects.

	Returns a NEW table rather than mutating, so callers can diff before/after to
	detect rank-ups without tracking that separately.
]]
function Factions.applyRepChange(
	current: { [string]: number },
	factionId: string,
	delta: number
): { [string]: number }
	local out = table.clone(current)
	local def = defs[factionId]
	if not def then
		return out
	end

	local function bump(id: string, amount: number)
		local next = (out[id] or 0) + amount
		out[id] = math.clamp(next, Factions.REP_MIN, Factions.REP_MAX)
	end

	bump(factionId, delta)
	for otherId, ratio in def.spillover do
		bump(otherId, delta * ratio)
	end
	return out
end

--- How an NPC of `npcFaction` should treat a player with the given reputation.
function Factions.attitudeToward(npcFaction: string, playerRep: { [string]: number }): string
	if npcFaction == "Independent" then
		return "Neutral"
	end
	local rep = playerRep[npcFaction] or 0
	if rep <= Factions.HOSTILE_BELOW then
		return "Hostile"
	elseif rep >= Factions.FRIENDLY_ABOVE then
		return "Friendly"
	end
	return "Neutral"
end

--- Whether two factions fight each other on sight.
function Factions.areEnemies(a: string, b: string): boolean
	if a == b or a == "Independent" or b == "Independent" then
		return false
	end
	local def = defs[a]
	if not def then
		return false
	end
	return (def.spillover[b] or 0) <= -0.5
end

function Factions.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

return Factions
