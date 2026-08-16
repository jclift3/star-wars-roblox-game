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

local Flags = {}

export type FlagDef = {
	id: string,
	-- Who sets it, who reads it, and what it means. See the header.
	note: string,
}

local defs: { [string]: FlagDef } = {}

local function def(id: string, note: string)
	defs[id] = { id = id, note = note }
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
def(
	"SawTheIntakeForm",
	"KorTheEmptyBunk: the Academy has a form for collecting acolytes. Read by Korriban dialogue."
)
def("SawBothCopies", "OrdTheOtherCopy: your enlistment was lawful and the village's copy says otherwise.")
def(
	"OwesNobody",
	"TatTheManifest: you did Vess Kadar a favour instead of taking one. Read by Tatooine dialogue."
)
def("HeardNineRemember", "TarTheSealedCrate: Ordo-9 recovered fourteen deliveries to one buyer.")

--------------------------------------------------------------------------------
-- The spine
--------------------------------------------------------------------------------

def("HasTheManifest", "CorPaperTrail: you hold a copy of the Imperial stripping manifest.")
def("InformantSaved", "CorTheLongFall: the informant came off the skybridge alive.")
def("SawLot9", "TarWhatTheyKept: you have been inside the Czerka warehouse and seen what draws the power.")
def("TombOpened", "KorTheTomb: the seal on Tulak Hord's tomb is broken and the man behind it is dead.")

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
def("NamedTheQuiet", "CastRynSolaa: a Jedi Master named the thing. Read by Vashk, Tolen Marr and Aneth Corr.")

--------------------------------------------------------------------------------
-- Choices with a price
--------------------------------------------------------------------------------

def("PrunedTheUnderlevels", "CorLoyaltyCheck: you killed dissidents under the plate for an Imperial officer.")
def(
	"WarnedTheUnderlevels",
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
def("PaidTheStrangersDebt", "Covered a stranger's Cartel debt out of your own pocket.")
def("LetThemBreakHisHands", "Watched the Cartel collect, and were pleasant about it.")

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

return Flags
