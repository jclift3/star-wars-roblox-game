--!strict
--[[
	NPCNames.luau

	Name generators for the crowd.

	A city of NPCs all called "Civilian" reads as scenery. Give each one a name
	and players start treating them as people -- which is the whole point of
	putting basic AI on them. Names are generated from small syllable pools
	rather than a fixed list so a hundred NPCs on Coruscant do not repeat.

	Styles are referenced by `nameStyle` on NPCArchetypes.
]]

local NPCNames = {}

type Generator = (rng: Random) -> string

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

--------------------------------------------------------------------------------
-- Syllable pools
--------------------------------------------------------------------------------

local FIRST = {
	"Kael",
	"Dorn",
	"Sera",
	"Mira",
	"Tavi",
	"Ryn",
	"Jess",
	"Bren",
	"Cass",
	"Vel",
	"Anik",
	"Dara",
	"Oren",
	"Talia",
	"Corin",
	"Nessa",
	"Rook",
	"Lyra",
	"Fen",
	"Sabé",
	"Garr",
	"Ilva",
	"Jonn",
	"Kira",
	"Loden",
	"Maro",
	"Nyx",
	"Perrin",
	"Quell",
	"Rell",
	"Sarn",
	"Tem",
	"Uvar",
	"Vona",
	"Wex",
	"Yarn",
	"Zeb",
	"Elin",
	"Hask",
	"Ivo",
}

local LAST = {
	"Vane",
	"Korr",
	"Dax",
	"Solari",
	"Ferrin",
	"Ostrand",
	"Bellek",
	"Marn",
	"Quarrow",
	"Draven",
	"Selk",
	"Tarn",
	"Vosk",
	"Renn",
	"Halcyon",
	"Kestrel",
	"Varo",
	"Nardo",
	"Cael",
	"Ondros",
	"Grath",
	"Silvane",
	"Torr",
	"Wren",
	"Zhao",
	"Rhen",
	"Ilaran",
}

local UNDERWORLD_FIRST = {
	"Sludge",
	"Nix",
	"Crank",
	"Vex",
	"Roach",
	"Slick",
	"Hex",
	"Grease",
	"Tally",
	"Bolt",
	"Ash",
	"Skiv",
	"Doc",
	"Wire",
	"Rat",
	"Prax",
	"Numb",
	"Chit",
}

local UNDERWORLD_LAST = {
	"the Knife",
	"Two-Credits",
	"Sunday",
	"the Quiet",
	"Half-Hand",
	"Ninefingers",
	"the Debt",
	"Coldstart",
	"the Ledger",
	"No-Ship",
	"Blacklung",
	"the Fence",
}

local JEDI_FIRST = {
	"Aven",
	"Cerra",
	"Ilos",
	"Numa",
	"Ryndal",
	"Sha'ka",
	"Tesh",
	"Ulric",
	"Vanda",
	"Ossa",
	"Kaidan",
	"Mirel",
	"Thane",
	"Ravi",
}

local JEDI_LAST = {
	"Anor",
	"Belan",
	"Cadros",
	"Deyn",
	"Eskol",
	"Farro",
	"Ghal",
	"Haden",
	"Iselle",
	"Joran",
	"Kryn",
	"Lomar",
	"Mekel",
	"Norr",
}

local SITH_TITLES = {
	"Darth",
	"Lord",
	"Adept",
	"Inquisitor",
	"Acolyte",
}

local SITH_NAMES = {
	"Vhaeros",
	"Malith",
	"Krayn",
	"Occlus",
	"Serevin",
	"Nihilus",
	"Andrik",
	"Zhaal",
	"Corvax",
	"Ruin",
	"Thessa",
	"Vorn",
	"Kaleth",
	"Ashkar",
}

local JAWA_SYLLABLES = { "Ut", "Ini", "Nya", "Kuz", "Zeek", "Tha", "Wat", "Ma", "Do" }

--------------------------------------------------------------------------------
-- Generators
--------------------------------------------------------------------------------

local generators: { [string]: Generator } = {}

generators.Common = function(rng)
	return `{pick(rng, FIRST)} {pick(rng, LAST)}`
end

generators.Underworld = function(rng)
	-- Half get a proper surname, half get a street name. The mix is what makes
	-- the crowd feel like it came from somewhere rather than one generator.
	if rng:NextNumber() < 0.5 then
		return `{pick(rng, UNDERWORLD_FIRST)} {pick(rng, UNDERWORLD_LAST)}`
	end
	return `{pick(rng, UNDERWORLD_FIRST)} {pick(rng, LAST)}`
end

generators.ImperialHuman = function(rng)
	local ranks = { "Lieutenant", "Captain", "Commander", "Major", "Colonel" }
	return `{pick(rng, ranks)} {pick(rng, LAST)}`
end

--- Imperial line infantry get serials, not names. That is the point of them.
generators.ImperialSerial = function(rng)
	local letters = "ABCDEFGHJKLMNPRSTVXZ"
	local i = rng:NextInteger(1, #letters)
	local prefix = string.sub(letters, i, i)
	return `{prefix}{rng:NextInteger(1, 9)}-{rng:NextInteger(1000, 9999)}`
end

generators.Jedi = function(rng)
	return `{pick(rng, JEDI_FIRST)} {pick(rng, JEDI_LAST)}`
end

generators.Sith = function(rng)
	return `{pick(rng, SITH_TITLES)} {pick(rng, SITH_NAMES)}`
end

generators.Jawa = function(rng)
	local n = rng:NextInteger(2, 3)
	local out = ""
	for _ = 1, n do
		out ..= pick(rng, JAWA_SYLLABLES)
	end
	return out
end

generators.DroidDesignation = function(rng)
	local letters = "ABCDEFGHJKLMNPQRSTUVWXZ"
	local function letter(): string
		local i = rng:NextInteger(1, #letters)
		return string.sub(letters, i, i)
	end
	return `{letter()}{rng:NextInteger(1, 9)}-{letter()}{rng:NextInteger(10, 99)}`
end

--- Explicit "this NPC has no name" -- Tuskens and Royal Guards do not give one.
generators.None = function()
	return ""
end

NPCNames.generators = generators

--[[
	Generates a name for the given style.

	Falls back to Common rather than erroring: an NPC with a slightly wrong name
	is a cosmetic problem, and killing a spawn over it is not a trade worth
	making at runtime.
]]
function NPCNames.generate(style: string?, rng: Random?): string
	local r = rng or Random.new()
	local gen = generators[style or "Common"] or generators.Common
	return gen(r)
end

function NPCNames.styles(): { string }
	local out = {}
	for style in generators do
		table.insert(out, style)
	end
	table.sort(out)
	return out
end

return NPCNames
