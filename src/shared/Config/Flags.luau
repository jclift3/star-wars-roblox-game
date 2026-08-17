--!strict
--[[
	Flags.luau

	The declared list of things a character can have done that the world is
	allowed to remember.

	WHY A REGISTRY AND NOT JUST A FREE STRING
	`profile.flags` is a plain `{ [string]: boolean }` and nothing would stop a
	mission writing "SawTheIntakeForm" and a conversation reading
	"SawTheIntakeFrom". The condition would simply never be true, the line
	would never appear, and that is indistinguishable from a line nobody wrote
	-- the exact failure this codebase keeps producing. Declaring them means
	`Missions.validate` and `Dialogue.validate` catch the typo at boot.

	The description is not decoration either. A flag is a promise that some
	other file is going to read it, and writing down who and why is the only
	thing that stops this file becoming forty booleans nobody dares delete.

	WHAT BELONGS HERE
	Things the player *did* that somebody should be able to mention later.
	Not mission completion -- `profile.missions.completed` already records
	that, and a flag duplicating it is a second source of truth that will
	eventually disagree. A flag is for the part of a mission the mission id
	cannot express: which way it went.
]]

local Acts = require(script.Parent.Acts)

local Flags = {}

export type FlagDef = {
	id: string,
	-- Who sets it, who reads it, and what it means. See the header.
	note: string,
	--[[
		What the journal says happened, in the player's own words, or nil for
		a flag that is only bookkeeping.

		The two are genuinely different things. `MetTheDebtor` exists to stop
		a choice being taken twice; nobody wants to read "you had a
		conversation". `PaidTheStrangersDebt` is the decision itself, and it
		is the only record of it anywhere -- a mission id says what you were
		sent to do, and a flag is the only thing that says which way it went.
	]]
	journal: string?,
	--- Which act it is filed under. Present exactly when `journal` is.
	act: string?,
}

local defs: { [string]: FlagDef } = {}

--- A flag that only the code cares about.
local function def(id: string, note: string)
	defs[id] = { id = id, note = note }
end

--[[
	A flag the player should be able to read back.

	Separate constructor rather than two optional arguments on `def`, so that
	which flags are part of the story is visible by skimming the file instead
	of by counting commas.
]]
local function entry(id: string, actId: string, journal: string, note: string)
	defs[id] = { id = id, note = note, journal = journal, act = actId }
end

--------------------------------------------------------------------------------
-- What the prologues taught you
--------------------------------------------------------------------------------

--[[
	One per origin, set by that origin's prologue.

	Each is the first loose thread of The Quiet, seen from four angles: an
	acolyte who was collected, a village cleared on paperwork that exists
	twice, fourteen sealed crates to one buyer, and a debt that came with a
	name. None of the four know they are the same story. The world can now
	say so, one careful line at a time, to the character who saw it.
]]
entry(
	"SawTheIntakeForm",
	"Beginnings",
	"You read the Academy's intake form. There is a printed box for collecting an acolyte, which means Sennat was not the first.",
	"KorTheEmptyBunk: the Academy has a form for collecting acolytes. Read by Korriban dialogue."
)
entry(
	"SawBothCopies",
	"Beginnings",
	"Your enlistment was lawful. The village kept the other copy of the form, and it does not say the same thing.",
	"OrdTheOtherCopy: your enlistment was lawful and the village's copy says otherwise."
)
entry(
	"OwesNobody",
	"Beginnings",
	"You did Vess Kadar a favour instead of taking one, and walked away owing the Cartel nothing.",
	"TatTheManifest: you did Vess Kadar a favour instead of taking one. Read by Tatooine dialogue."
)
entry(
	"HeardNineRemember",
	"Beginnings",
	"A cargo droid remembered fourteen sealed deliveries to a single buyer. Nobody had asked him.",
	"TarTheSealedCrate: Ordo-9 recovered fourteen deliveries to one buyer."
)

--------------------------------------------------------------------------------
-- The spine
--------------------------------------------------------------------------------

entry(
	"HasTheManifest",
	"PaperTrail",
	"You hold a copy of the Imperial stripping manifest. It is a list of places, and one of them is not a place.",
	"CorPaperTrail: you hold a copy of the Imperial stripping manifest."
)
entry(
	"InformantSaved",
	"PaperTrail",
	"The informant came off the skybridge alive.",
	"CorTheLongFall: the informant came off the skybridge alive."
)
entry(
	"SawLot9",
	"WhatTheyKept",
	"You have been inside Lot 9 and seen what the warehouse is drawing that much power for.",
	"TarWhatTheyKept: you have been inside the Czerka warehouse and seen what draws the power."
)
entry(
	"TombOpened",
	"WhatTheyKept",
	"The seal on Tulak Hord's tomb is broken, and the man who broke it is dead.",
	"KorTheTomb: the seal on Tulak Hord's tomb is broken and the man behind it is dead."
)

--[[
	The only flag raised by a conversation rather than by an errand, and the
	one that most earns being a flag at all.

	Master Ryn Solaa says the words out loud. Nothing about the world changes;
	what changes is that three other people -- Vashk, who has been documenting
	it unnamed for thirty years, Marr, whose service filed it as fatigue, and
	Corr, who has been entering it in a column headed attrition -- can now be
	told there is a name for it. Each answers in character, and none of them
	could have unless something recorded that the naming happened.
]]
entry(
	"NamedTheQuiet",
	"WhatTheyKept",
	"Master Ryn Solaa said the words out loud. It is called The Quiet, it is old, and three other people have been describing it for years without a name to put on it.",
	"CastRynSolaa: a Jedi Master named the thing. Read by Vashk, Tolen Marr and Aneth Corr."
)

--------------------------------------------------------------------------------
-- Choices with a price
--------------------------------------------------------------------------------

entry(
	"PrunedTheUnderlevels",
	"PaperTrail",
	"You cleared the Underlevels for an Imperial officer. They were not soldiers, and the officer knew that when he asked.",
	"CorLoyaltyCheck: you killed dissidents under the plate for an Imperial officer."
)
entry(
	"WarnedTheUnderlevels",
	"PaperTrail",
	"You got the Underlevels out ahead of the sweep, and let the officer find an empty floor.",
	"CorTheWarning: you got them out first. The two missions forbid each other's flag."
)

--[[
	The Cartel debt, and why a dialogue choice needs a flag at all.

	`Choice.alignment` with nothing else attached would be a button the player
	can press every time they open the conversation, and there are eighteen
	enforcers on the Nar Shaddaa Promenade. Setting a flag and conditioning
	the same choice on `notFlag` is what makes a decision happen once.
	`Dialogue.validate` now requires that pairing rather than trusting it.
]]
def("MetTheDebtor", "Answered the Cartel enforcer either way. Raised by both branches; closes the moment.")
entry(
	"PaidTheStrangersDebt",
	"PaperTrail",
	"You covered a stranger's Cartel debt out of your own pocket. You do not know his name.",
	"Covered a stranger's Cartel debt out of your own pocket."
)
entry(
	"LetThemBreakHisHands",
	"PaperTrail",
	"You watched the Cartel collect, and were pleasant about it.",
	"Watched the Cartel collect, and were pleasant about it."
)

--------------------------------------------------------------------------------
-- The signature chains
--------------------------------------------------------------------------------

--[[
	Each origin's chain turns on one decision, and this is where it is kept.

	The pattern is the same one the Cartel debt established and for the same
	reason: a branch cannot be expressed by `requires`, which only knows whether
	a mission was finished. So each branch sets its own flag *and* a shared one
	naming the moment, and the rest of the chain gates on the shared flag --
	`requiresFlag` is an AND with no *or*, so without `SaberBuilt` the last part
	of the Acolyte chain would need to be written three times.

	None of these are set by a mission whose only outcome is "you finished it".
	A chain part with no fork writes no flag; `missions.completed` already
	records that, and duplicating it is the second source of truth this file
	exists to prevent.
]]

-- Acolyte: three forges, one axis. Which colour you carry is the most public
-- fact about a character in this era -- everyone who sees the blade reads it.
def("SaberBuilt", "Any of the three forges. Gates AcoTheFirstCut and is read by Vashk and Ryn Solaa.")
entry(
	"SaberBled",
	"WhatYouCarry",
	"You bled the crystal in Tulak Hord's tomb. It burns red, and everyone who sees it will know what you did to it.",
	"AcoForgeBled: you bled the crystal in Tulak Hord's tomb. Red."
)
entry(
	"SaberRefused",
	"WhatYouCarry",
	"You refused both hands. The crystal settled purple, which almost nobody carries, and nobody can read.",
	"AcoForgeRefused: you refused both and the crystal went purple. The rare one."
)
entry(
	"SaberPure",
	"WhatYouCarry",
	"You let the crystal be what it already was. It burns blue.",
	"AcoForgePure: you let it be what it was. Blue."
)

-- Conscript: beskar states your purpose, and Mandalorians take that literally.
def("WearsBeskar", "Either Great Hunt forge. Read by Tolen Marr.")
entry(
	"BeskarForVengeance",
	"WhatYouCarry",
	"Your beskar was struck in the colour that means a debt owed in blood. Mandalorians read armour, and they will read yours.",
	"ConBeskarVengeance: you had it struck in the colour that means a debt owed in blood."
)
entry(
	"BeskarForDuty",
	"WhatYouCarry",
	"Your beskar was struck in the colour that means an oath kept.",
	"ConBeskarDuty: you had it struck in the colour that means an oath kept."
)

-- Scoundrel: the debt is answered at level 12 and Kadar remembers it forever.
def("DebtSettled", "Either debt mission. The moment closed; gates the rest of the ship chain.")
entry(
	"DebtBought",
	"WhatYouCarry",
	"You cleared Vess Kadar's debt with your own money. You owe him nothing, and he has not decided how he feels about that.",
	"ScoDebtBought: you cleared it with your own money and owe him nothing."
)
entry(
	"DebtWorked",
	"WhatYouCarry",
	"You cleared Vess Kadar's debt by doing his work. He liked that better, which is its own problem.",
	"ScoDebtWorked: you cleared it by doing his work, and he liked that better."
)
entry(
	"HasOwnShip",
	"WhatYouCarry",
	"The hull you pulled out of the Hoth graveyard flies, and it is yours, and it has a name.",
	"ScoTheName: the hull out of the Hoth graveyard flies and it is yours."
)

-- Scrapper: the only signature reward that can disagree with you.
entry(
	"NineRestored",
	"WhatYouCarry",
	"You gave Ordo-9 back the programming he was built with. He is lethal, capable, and no longer quite the unit that walked behind you.",
	"ScrRestore: you gave Ordo-9 back the programming he was built with."
)
entry(
	"NineLeftAsHeIs",
	"WhatYouCarry",
	"You left Ordo-9 as the thing you made by accident, and told him so to his face.",
	"ScrLeaveHim: you left him as the thing you made by accident, and told him so."
)

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

Flags.defs = defs

function Flags.exists(id: string): boolean
	return defs[id] ~= nil
end

function Flags.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

--[[
	Journal-bearing flags filed under `actId`, sorted for stability.

	Sorted by id rather than by when it happened, because nothing records
	when: `profile.flags` is a set of booleans and giving it timestamps would
	be a schema change to make a list prettier. Within an act the entries are
	a handful of lines and the order between them carries nothing -- but an
	order that changes between two renders of the same screen is a bug the
	eye catches immediately, so it has to be *some* fixed order.
]]
function Flags.journalFor(actId: string): { FlagDef }
	local out: { FlagDef } = {}
	for _, id in Flags.ids() do
		local f = defs[id]
		if f.journal and f.act == actId then
			table.insert(out, f)
		end
	end
	return out
end

--- Faults in this file. Called from MissionService.init beside the others.
function Flags.validate(): { string }
	local problems: { string } = {}
	for _, id in Flags.ids() do
		local f = defs[id]
		-- Either both or neither. A journal line filed under nothing is a
		-- line the player can never read, which is the failure this whole
		-- file exists to make noisy.
		if (f.journal ~= nil) ~= (f.act ~= nil) then
			table.insert(problems, `{id}: has a journal line or an act but not both`)
		elseif f.act and not Acts.exists(f.act) then
			table.insert(problems, `{id}: filed under unknown act "{f.act}"`)
		end
	end
	return problems
end

return Flags
