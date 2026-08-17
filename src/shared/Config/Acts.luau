--!strict
--[[
	Acts.luau

	The campaign, written down as a shape rather than as a pile of missions.

	WHY THE MEMBERSHIP IS HERE AND NOT AN `act` FIELD ON EACH MISSION
	It could be either. A field on `MissionDef` would put the act next to the
	mission that belongs to it, which is normally the right instinct -- but
	Missions.luau is 2,900 lines and an act spread across it as thirty-odd
	one-word lines is not something anyone can read. The question this file
	answers is *what order does the story happen in*, and that question has
	exactly one useful answer shape: an ordered list of acts, each an ordered
	list of missions. You can see the whole campaign in one screen.

	`Missions` applies these onto `MissionDef.act` at require time, so every
	reader downstream still just asks a mission what act it is in.

	WHAT AN ACT IS FOR
	Two things:

	- **The journal.** The mission board is a list of work available *now*;
	  it cannot show what happened, in what order, or what is still to come.
	  A mystery needs a record, and a record needs chapters.
	- **A validation anchor.** `Missions.validate` can now check that a
	  mission does not require one from a later act -- an ordering bug that
	  was previously invisible until a player got stuck.

	SIDE MISSIONS MAY BE IN AN ACT
	Membership is declared, not derived from `kind`. The Coruscant fork is
	`kind = "Side"` and is the most consequential decision in the first
	fifteen levels; a bounty board posting is `kind = "Bounty"` and belongs in
	nobody's journal. Only `Story` missions are *required* to be placed.

	NOTHING HERE IS A GATE
	An act does not lock anything. `requires`, `minLevel`, `requiresFlag` and
	`requiredRep` already do that, and they do it per mission, which is finer
	than per act and is what `boardFor` already reads. An act that also gated
	would be a second source of truth about the same question.
]]

local Acts = {}

export type ActDef = {
	id: string,
	--- Position in the campaign. Contiguous from 1; checked by `validate`.
	order: number,
	name: string,
	--[[
		One line, shown in the journal *only once the act has been entered*.

		They are allowed to say what the act was about, because the journal
		hides them until the player has finished something in it. An act you
		have not reached shows its name and "Not begun" -- enough to know
		there is more, not enough to spoil it.
	]]
	subtitle: string,
	--[[
		True for an act that runs *alongside* the numbered spine rather than
		after it.

		The four signature chains all start at level 12, in the middle of
		act 3, and finish at 34, after act 4. Listing them as act 5 without
		saying so would tell the player to put their own story last.
	]]
	parallel: boolean?,
	--[[
		The act's missions, in the order they are meant to be played.

		Order matters: it is what the journal lists by. Sorting by `minLevel`
		instead would interleave the four signature chains into a single
		unreadable ladder, and would put a fork's two halves in an arbitrary
		order relative to each other.
	]]
	missions: { string },
}

local defs: { [string]: ActDef } = {}
local order: { string } = {}

local function def(a: ActDef): ActDef
	defs[a.id] = a
	table.insert(order, a.id)
	return a
end

--------------------------------------------------------------------------------

def({
	id = "Beginnings",
	order = 1,
	name = "Beginnings",
	subtitle = "Four people who have not met, each holding one corner of the same document.",
	-- Only ever one of these is yours. They are listed together because the
	-- point of the four is that they are the same story, and the journal of a
	-- second character should show that in the same place.
	missions = {
		"KorTheEmptyBunk",
		"OrdTheOtherCopy",
		"TatTheManifest",
		"TarTheSealedCrate",
	},
})

def({
	id = "SmallWork",
	order = 2,
	name = "Small Work",
	subtitle = "Errands, badly paid, and the first thing that does not add up.",
	--[[
		Four planets, because there are four origins.

		This act was six missions on two worlds, and the two worlds were the
		Scoundrel's and the Conscript's. An Acolyte or a Scrapper finished
		their prologue at level 2 and act 2 contained nothing they could
		reach -- so half the game's characters went from the first hour to
		their signature chain at level 12 with a hole in between. The four
		chains are listed home world by home world rather than interleaved by
		level: they are alternatives, not a sequence.
	]]
	missions = {
		"KorTheDuellingPits",
		"KorTheRequisitionNumber",

		"TarWhatTheCratesWere",
		"TarTheOtherName",

		"TatDustAndDroids",
		"TatUnwelcomeAttention",
		"TatTheHuttsFavour",

		"OrdPayAndRations",
		"OrdTheHillWithNoName",
		"OrdFiledAsFatigue",
	},
})

def({
	id = "PaperTrail",
	order = 3,
	name = "The Paper Trail",
	subtitle = "Somebody is keeping records. That is the frightening part.",
	missions = {
		"CorPaperTrail",
		"CorLoyaltyCheck",
		"CorTheWarning",
		"HothColdOpen",
		"TytQuietOrder",
		"TytTrialOfPatience",
		"CorTheLongFall",
	},
})

def({
	id = "WhatTheyKept",
	order = 4,
	name = "What They Kept",
	subtitle = "A warehouse nobody has a key for, and a seal that was broken from the inside.",
	missions = {
		"NarDebtCollection",
		"NarOpenContract",
		"TarWhatTheyKept",
		"KorTheTomb",
	},
})

def({
	id = "WhatYouCarry",
	order = 5,
	parallel = true,
	name = "What You Carry",
	subtitle = "Your own work, which nobody assigned you and nobody can take.",
	--[[
		All four chains, and a character only ever sees one: every mission
		here is `origin`-gated, and the journal filters on that the same way
		`boardFor` does.

		Kept in one act rather than four because they are the same act -- the
		answer to "why specialize?" -- told four times, and four acts numbered
		5a-5d would imply an ordering between stories that never meet.
	]]
	missions = {
		"AcoTheHilt",
		"AcoLensAndCell",
		"AcoTheCrystal",
		"AcoForgeBled",
		"AcoForgeRefused",
		"AcoForgePure",
		"AcoTheFirstCut",

		"ConSponsorship",
		"ConHuntPromenade",
		"ConHuntWorks",
		"ConHuntFissure",
		"ConBeskarVengeance",
		"ConBeskarDuty",

		"ScoDebtBought",
		"ScoDebtWorked",
		"ScoTheHull",
		"ScoTheDrive",
		"ScoMakingItFly",
		"ScoTheName",

		"ScrTheChassis",
		"ScrMemoryCore",
		"ScrThePowerPlant",
		"ScrTheVoice",
		"ScrRestore",
		"ScrLeaveHim",
	},
})

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

Acts.defs = defs

--- Act ids in campaign order. Do not sort the result; it is already correct.
function Acts.ids(): { string }
	return table.clone(order)
end

function Acts.exists(id: string): boolean
	return defs[id] ~= nil
end

function Acts.get(id: string): ActDef
	local a = defs[id]
	assert(a, `Acts.get: unknown act "{id}"`)
	return a
end

--- The act a mission belongs to, or nil for the ones that are just work.
function Acts.actOf(missionId: string): string?
	for _, actId in order do
		for _, id in defs[actId].missions do
			if id == missionId then
				return actId
			end
		end
	end
	return nil
end

--[[
	Faults in this file alone. Cross-checking against Missions is done by
	`Missions.validate`, which is the side that can see both.
]]
function Acts.validate(): { string }
	local problems: { string } = {}

	local seen: { [string]: string } = {}
	for index, actId in order do
		local a = defs[actId]
		if a.order ~= index then
			table.insert(problems, `{actId}: order {a.order} but declared {index}th`)
		end
		if #a.missions == 0 then
			table.insert(problems, `{actId}: has no missions`)
		end
		for _, missionId in a.missions do
			local owner = seen[missionId]
			if owner then
				table.insert(problems, `{missionId}: in both {owner} and {actId}`)
			else
				seen[missionId] = actId
			end
		end
	end

	return problems
end

return Acts
