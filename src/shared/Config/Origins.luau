--!strict
--[[
	Origins.luau

	Who you were before the game started, and -- because of that -- who is
	willing to fly you anywhere.

	WHY TRAVEL LIVES HERE
	Four origins, one per existing skill tree, so the character sheet gains no
	new axis (CAMPAIGN.md §3). The trees already differentiate what you can
	*do*; what they never differentiated is how you get around, which in a
	nine-planet game is most of the moment-to-moment experience.

	So each origin travels by a different mechanism rather than paying a
	different tax:

		Acolyte    the Empire moves you. Free between Imperial worlds, and
		           nobody independent wants a Sith in their hold, so everywhere
		           else is the most expensive fare in the game.
		Conscript  Republic military transport. The largest free network --
		           four worlds -- but it moves on the Army's schedule, so the
		           wait between flights is the longest of the two patrons.
		Scoundrel  you buy passage. No free routes at all, but you know what a
		           fare should cost and you are never waiting long.
		Scrapper   you work passage on freight. Almost free and unrestricted,
		           because you are riding somebody else's manifest -- which
		           means leaving when the cargo leaves, not when you want to.

	THE FALLBACK IS NOT OPTIONAL
	Every origin can charter to every world at some price. A broke Acolyte who
	needs Coruscant for the Act 3 story must not be stuck: a weakness that can
	strand you is not a weakness, it is a dead end. The Acolyte pays through
	the nose and resents it, which is the intended feeling.

	THE HOSTILITY SURCHARGE IS DERIVED, NOT AUTHORED
	"No independent captain will carry a Sith" is not a list in this file. It
	falls out of `Factions.areEnemies(patron, worldsController)`, which already
	exists and is already tuned. One less table to keep in sync, and it stays
	correct automatically if the faction matrix moves.
]]

local Factions = require(script.Parent.Factions)
local Planets = require(script.Parent.Planets)

local Origins = {}

export type TravelAccess = {
	--[[
		The faction whose transport network carries you for nothing.

		A patron flies you if *either* end of the trip is one of its worlds --
		it will send a shuttle to collect its own. Requiring both ends would
		mean an Acolyte who lands on Tatooine in Act 1 has no free route for
		the next twenty levels, so the perk would almost never fire while its
		matching penalty always did.
	]]
	patron: string?,
	--- Multiplier on the charter fare when the patron will not carry you.
	fareMultiplier: number,
	--- Seconds before you can travel again. This is the cost that is not money.
	cooldown: number,
}

export type OriginDef = {
	id: string,
	displayName: string,
	--- The skill tree this origin is built around. One each, no overlap.
	tree: string,
	homePlanet: string,
	faction: string,
	mentor: string,
	--- Two sentences for the creation screen. Who you were, and what you saw.
	blurb: string,
	--- The trade-off, stated before the player picks rather than discovered.
	travelBlurb: string,
	travel: TravelAccess,
}

local defs: { [string]: OriginDef } = {}

local function def(o: OriginDef): OriginDef
	defs[o.id] = o
	return o
end

--------------------------------------------------------------------------------

def({
	id = "Acolyte",
	displayName = "Sith Acolyte",
	tree = "Force",
	homePlanet = "Korriban",
	faction = "Empire",
	mentor = "Overseer Vashk",
	blurb = "Taken as an infant from a world that no longer appears on charts and raised by the Academy, which is to say raised by nobody. You are the only person alive who watched your one friend go hollow and cared.",
	travelBlurb = "The Empire moves you between its own worlds for nothing. Everywhere else you are a Sith looking for a ride, and the price says so.",
	travel = {
		patron = "Empire",
		-- The steepest fare in the game, against the smallest free network:
		-- the Empire holds two of the nine worlds. Deliberate -- the Force
		-- tree is the strongest, and this is what it costs.
		fareMultiplier = 2.0,
		cooldown = 30,
	},
})

def({
	id = "Conscript",
	displayName = "Republic Conscript",
	tree = "Combat",
	homePlanet = "OrdMantell",
	faction = "Republic",
	mentor = "Sergeant Tolen Marr",
	blurb = "Signed up at fifteen out of a resettlement block because the Republic Army fed you. You have an official document saying the thing did not happen and your own memory that it did.",
	travelBlurb = "Republic transport carries you free across four worlds -- more of the galaxy than anyone else gets for nothing. It leaves when the Army says it leaves.",
	travel = {
		patron = "Republic",
		fareMultiplier = 1.4,
		-- The longest wait of the two patrons. A free seat on a troop
		-- transport is a seat you queue for.
		cooldown = 75,
	},
})

def({
	id = "Scoundrel",
	displayName = "Scoundrel",
	tree = "Piloting",
	-- Born on Nar Shaddaa, not still there: that world starts at level 12 and
	-- a character begins at 1. You read the manifest and you left in a hurry,
	-- which is why the blurb is past tense and this is Hutt space you can
	-- survive.
	homePlanet = "Tatooine",
	faction = "Hutt",
	mentor = "Vess Kadar",
	blurb = "Born owing money -- your parents' debt, transferred, with interest, which is legal on Nar Shaddaa. You can read a cargo manifest, and you have read one you were not supposed to.",
	travelBlurb = "Nobody flies you for free and nobody refuses you either. You know what a fare should cost, and you are never the one waiting on the dock.",
	travel = {
		-- No patron on purpose: the Scoundrel's advantage is that no flag
		-- follows them, so there is no world where they are the wrong
		-- passenger. Act 2 hands them a hull of their own (CAMPAIGN.md §5.3),
		-- and from then on this line stops mattering.
		patron = nil,
		fareMultiplier = 0.6,
		cooldown = 20,
	},
})

def({
	id = "Scrapper",
	displayName = "Scrapper",
	tree = "Engineering",
	homePlanet = "Taris",
	faction = "Independent",
	mentor = "Ordo-9",
	blurb = "Raised in a salvage crew picking over a dead planet, talking to machines more comfortably than to people. You have a sealed container built to hold a person, and a droid with fragments of a memory of delivering others like it.",
	travelBlurb = "You work your passage on freight, so it costs almost nothing and no port turns you away. You leave when the cargo leaves.",
	travel = {
		patron = nil,
		-- Near-free, and the cost is the clock: the longest cooldown in the
		-- game. Money is renewable in an action RPG; the moment you want to
		-- be somewhere is not.
		fareMultiplier = 0.2,
		cooldown = 180,
	},
})

--------------------------------------------------------------------------------

Origins.defs = defs
Origins.DEFAULT = "Scoundrel"

--[[
	Extra charged for a world whose controller is at war with your patron.

	Passage has to be arranged through a broker who is taking a risk, and the
	broker prices the risk. This is the concrete form of "a Sith has a harder
	time finding a ride".
]]
Origins.HOSTILE_SURCHARGE = 1.5

export type Passage = {
	credits: number,
	cooldown: number,
	free: boolean,
	--- Why the price is what it is. The galaxy map prints this under the fare.
	note: string,
}

function Origins.get(id: string): OriginDef
	local o = defs[id]
	assert(o, `Origins.get: unknown origin "{id}"`)
	return o
end

function Origins.exists(id: string): boolean
	return defs[id] ~= nil
end

--[[
	What it takes for this character to get from one world to another.

	Pure and shared on purpose: the galaxy map quotes the fare and the server
	charges it, and two implementations of this arithmetic would drift into a
	price tag that lies -- the same reason `Shops.VENDOR_RANGE` is shared.

	`priceMult` is the Haggler skill, passed straight through to
	`Planets.fastTravelCost` so investing in Engineering is visible here too.
]]
function Origins.passageFor(originId: string, from: string, to: string, priceMult: number?): Passage
	local origin = Origins.get(originId)
	local access = origin.travel

	if from == to then
		return { credits = 0, cooldown = 0, free = true, note = "You are already here." }
	end

	local patron = access.patron
	if patron then
		local controller = Planets.get(to).controllingFaction
		if controller == patron or Planets.get(from).controllingFaction == patron then
			local label = Factions.get(patron).displayName
			return {
				credits = 0,
				cooldown = access.cooldown,
				free = true,
				note = `{label} transport. No fare.`,
			}
		end
	end

	local base = Planets.fastTravelCost(from, to, priceMult)
	local credits = base * access.fareMultiplier
	local note = "Chartered passage."

	if patron and Factions.areEnemies(patron, Planets.get(to).controllingFaction) then
		credits *= Origins.HOSTILE_SURCHARGE
		note = "Chartered passage, arranged through a broker. Nobody here wants you aboard."
	elseif access.fareMultiplier <= 0.5 then
		note = "Working passage on a freighter. You leave when the cargo does."
	elseif access.fareMultiplier >= 1.5 then
		note = "Chartered passage. Few captains will carry you, and they know it."
	end

	return {
		credits = math.floor(credits + 0.5),
		cooldown = access.cooldown,
		free = false,
		note = note,
	}
end

--[[
	Cross-checks every origin against the configs it names.

	Takes its existence checks as arguments for the same reason
	`Factions.validate` does: Progression is a much larger module and there is
	no reason for this one to require it.
]]
function Origins.validate(treeExists: (string) -> boolean): { string }
	local problems = {}
	local trees: { [string]: string } = {}
	for id, o in defs do
		if not Planets.exists(o.homePlanet) then
			table.insert(problems, `{id}: home planet "{o.homePlanet}" does not exist`)
		elseif Planets.get(o.homePlanet).minLevel > 1 then
			-- The creation screen puts a brand-new character down here, so a
			-- home world built for anyone above level 1 is a world that kills
			-- them on arrival. Nar Shaddaa was exactly this: era-correct for
			-- the Scoundrel's backstory and a level 12 world.
			table.insert(
				problems,
				`{id}: home planet "{o.homePlanet}" starts at level {Planets.get(o.homePlanet).minLevel}`
			)
		end
		--[[
			SOMEWHERE TO FIGHT ON DAY ONE

			Reported from play, 2026-08-17: *"I don't have any other missions
			I can complete or a means to level up. I should be able to
			discover random tasks or going out of camp to combat raiders."*

			The world was not short of enemies -- Korriban had forty-three of
			them -- it was short of enemies a level 1 Acolyte could reach.
			The nearest aggressive district on his home world banded 19-30,
			and because `Radiant` composes a Cull only for a district holding
			something aggressive, the district he spawns in generated no
			repeatable work either. Two story missions, then a wall.

			So this is checked on home worlds specifically, not on all nine.
			Nar Shaddaa opening at level 12 is correct; Korriban opening at
			level 19 for the character who *starts* there is not.

			`UNDERLEVELLED_BY` is the tolerance because it is already the
			game's own answer to "how far under is too far" -- the same
			number `ZoneController` uses to decide whether to put a TURN BACK
			banner on the screen. A home world that trips this check is a
			home world whose first fight the game itself would warn you off.
		]]
		if Planets.exists(o.homePlanet) then
			local floor = Planets.get(o.homePlanet).minLevel
			local lowest = Planets.lowestHostileLevel(o.homePlanet)
			if not lowest then
				table.insert(problems, `{id}: home planet "{o.homePlanet}" has nothing hostile on it at all`)
			elseif lowest - floor > Planets.UNDERLEVELLED_BY then
				table.insert(
					problems,
					`{id}: home planet "{o.homePlanet}" opens at level {floor} but its weakest enemy is level {lowest}`
				)
			end
		end
		if not Factions.exists(o.faction) then
			table.insert(problems, `{id}: unknown faction "{o.faction}"`)
		end
		if not treeExists(o.tree) then
			table.insert(problems, `{id}: unknown skill tree "{o.tree}"`)
		end
		-- One origin per tree is the entire justification for four origins
		-- adding no new axis. Two sharing a tree quietly breaks that.
		if trees[o.tree] then
			table.insert(problems, `{id}: shares the {o.tree} tree with {trees[o.tree]}`)
		end
		trees[o.tree] = id

		local patron = o.travel.patron
		if patron and not Factions.exists(patron) then
			table.insert(problems, `{id}: unknown travel patron "{patron}"`)
		end
		if o.travel.fareMultiplier <= 0 then
			table.insert(problems, `{id}: fare multiplier must be positive`)
		end
	end
	if not defs[Origins.DEFAULT] then
		table.insert(problems, `DEFAULT names unknown origin "{Origins.DEFAULT}"`)
	end
	table.sort(problems)
	return problems
end

function Origins.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

return Origins
