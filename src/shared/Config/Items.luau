--!strict
--[[
	Items.luau

	Quest items: the things you pick up off the ground.

	Deliberately separate from Weapons and Outfits, which are gear you own and
	equip. These exist to be carried from one place to another and then spent by
	a Deliver objective, so they need a look and a name and nothing else.

	`size` and `colour` are all PickupService needs to build the world model, so
	nothing here reaches for a marketplace asset -- same rule as the rigs.
]]

local Palette = require(script.Parent.Palette)

local Items = {}

export type ItemDef = {
	id: string,
	displayName: string,
	-- Shown on the pickup prompt, so it reads as a thing rather than an id.
	verb: string,
	colour: Color3,
	size: Vector3,
	-- Rough shape of the world model. Crates are boxes, data is a small
	-- glowing slab, droids stand taller than they are wide.
	shape: string, -- "Crate" | "Slab" | "Droid" | "Ore"
}

local defs: { [string]: ItemDef } = {}

local function def(i: ItemDef): ItemDef
	defs[i.id] = i
	return i
end

def({
	id = "AstromechDroid",
	displayName = "Astromech Droid",
	verb = "Recover",
	colour = Palette.AstromechBlue,
	size = Vector3.new(2.6, 3.4, 2.6),
	shape = "Droid",
})

def({
	id = "SpiceCrate",
	displayName = "Spice Crate",
	verb = "Take",
	colour = Palette.SmugglerBrown,
	size = Vector3.new(3, 2.2, 2.2),
	shape = "Crate",
})

def({
	id = "PowerCoupling",
	displayName = "Power Coupling",
	verb = "Salvage",
	colour = Palette.WornSteel,
	size = Vector3.new(1.8, 1.8, 3),
	shape = "Crate",
})

def({
	id = "ResearchData",
	displayName = "Research Data",
	verb = "Extract",
	colour = Palette.SaberBlue,
	size = Vector3.new(1.6, 2, 0.4),
	shape = "Slab",
})

def({
	id = "CreditChit",
	displayName = "Credit Chit",
	verb = "Take",
	colour = Palette.DroidGold,
	size = Vector3.new(1.2, 1.6, 0.3),
	shape = "Slab",
})

def({
	id = "RawOre",
	displayName = "Raw Ore",
	verb = "Mine",
	colour = Palette.ZabrakRust,
	size = Vector3.new(2, 1.6, 2),
	shape = "Ore",
})

--[[
	One entry to one race, and the only item here that is *spent* by
	something other than a mission.

	It exists so that being broke is not the same as being locked out. A
	circuit charges credits at the line, and a fourteen-year-old who has just
	put everything he owns into a lightsaber would otherwise be told he
	cannot race until he has farmed for an hour -- which is the opposite of
	what a race is for. A pass falls off a corpse like anything else, so the
	answer to "I have no money" is the answer the rest of the game already
	gives: go and kill something.

	No vendor stocks it, deliberately. A pass you can buy is credits with
	extra steps, and it would undo the one thing the pass is for.
]]
def({
	id = "RacePass",
	displayName = "Race Pass",
	verb = "Take",
	colour = Palette.RebelOrange,
	size = Vector3.new(1.4, 0.9, 0.12),
	shape = "Slab",
})

--------------------------------------------------------------------------------
-- Signature chain components
--------------------------------------------------------------------------------

--[[
	The parts the four signature chains are assembled out of.

	These are the only items in the file that are not interchangeable with each
	other. A Spice Crate is a Spice Crate wherever it turns up, and three
	missions can share one; a Focusing Lens exists because exactly one mission
	needs a lens, and it is worth its own entry for the same reason the chains
	are worth building at all -- the object is the reward, and an object called
	"Research Data" is not an object.

	Nothing here is consumed by a Deliver objective. A component you hand in is
	a component you no longer have, and every one of these is meant to still be
	in the bag at the end of the chain. The chains close on a Reach instead.
]]

def({
	id = "SaberHilt",
	displayName = "Lightsaber Hilt",
	verb = "Take",
	colour = Palette.WornSteel,
	size = Vector3.new(0.5, 1.4, 0.5),
	shape = "Slab",
})

def({
	id = "FocusingLens",
	displayName = "Focusing Lens",
	verb = "Take",
	colour = Palette.SaberBlue,
	size = Vector3.new(0.9, 0.9, 0.3),
	shape = "Slab",
})

def({
	id = "RawCrystal",
	displayName = "Uncut Crystal",
	-- Not "Take". You are not picking it up so much as being allowed to.
	verb = "Lift",
	colour = Palette.SaberWhite,
	size = Vector3.new(0.8, 1.1, 0.8),
	shape = "Ore",
})

def({
	id = "HuntWrit",
	displayName = "Hunt Writ",
	verb = "Take",
	colour = Palette.DroidGold,
	size = Vector3.new(1.3, 1.7, 0.2),
	shape = "Slab",
})

def({
	id = "BeskarIngot",
	displayName = "Beskar Ingot",
	verb = "Take",
	colour = Palette.DarkMetal,
	size = Vector3.new(1.8, 0.9, 0.9),
	shape = "Ore",
})

def({
	id = "HullPlate",
	displayName = "Hull Plating",
	verb = "Salvage",
	colour = Palette.HullGrey,
	size = Vector3.new(4.2, 0.6, 3),
	shape = "Crate",
})

def({
	id = "HyperdriveCore",
	displayName = "Hyperdrive Core",
	verb = "Salvage",
	colour = Palette.SaberBlue,
	size = Vector3.new(2.4, 2.4, 3.2),
	shape = "Crate",
})

def({
	id = "DroidPlating",
	displayName = "War-Surplus Plating",
	verb = "Salvage",
	colour = Palette.Gunmetal,
	size = Vector3.new(3, 1.8, 1.2),
	shape = "Crate",
})

def({
	id = "MemoryCore",
	displayName = "Memory Core",
	verb = "Extract",
	colour = Palette.SaberRed,
	size = Vector3.new(1.1, 1.5, 0.5),
	shape = "Slab",
})

def({
	id = "VoiceModule",
	displayName = "Vocabulator",
	verb = "Salvage",
	colour = Palette.DroidGold,
	size = Vector3.new(1, 0.8, 0.6),
	shape = "Slab",
})

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Items.get(id: string): ItemDef
	local i = defs[id]
	assert(i, `Items.get: unknown item "{id}"`)
	return i
end

function Items.exists(id: string): boolean
	return defs[id] ~= nil
end

--- Display name if it is a known item, otherwise the raw id.
function Items.nameOf(id: string): string
	local i = defs[id]
	return if i then i.displayName else id
end

function Items.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

return Items
