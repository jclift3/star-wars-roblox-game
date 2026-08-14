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
