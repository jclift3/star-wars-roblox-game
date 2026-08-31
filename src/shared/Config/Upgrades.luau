--!strict
--[[
	Upgrades.luau

	The parts you bolt to a hull you already own.

	THE ASK
	*"They should be able to uplevel their speeders -- speed, durability
	(they are unbreakable currently which shouldn't be the case), weapons,
	etc."*

	Durability landed first, because a hull that cannot be hurt has nothing
	to protect and "tougher" is not a thing you can sell someone. This is the
	next piece: three fitted parts, five grades each, and a hull that is
	yours in a way a bought one is not.

	FITTED TO A SHIP, NOT WORN BY A PILOT
	The decision that shapes the rest of the file. A part lives at
	`profile.shipParts[shipId][slot]` -- keyed by hull, exactly the way
	`profile.shipDamage` already is, and for exactly the same reason: a ship
	is not an `ItemStack` and never has been. So upgrading the Swoop does
	nothing for the Assault, buying a new hull starts it bare, and the old
	speeder in the garage is a thing you built rather than a row in a list
	you have outgrown.

	The alternative was a fifth `Affixes.ITEM_SLOTS` entry, letting existing
	crystals grant `ShipSpeedMult` -- almost no code, since that stat already
	has a live reader. It was rejected because the bonus would follow the
	*pilot*, and then there is no garage, no reason to keep a hull, and
	nothing to be proud of.

	BUYING IS FITTING
	There is no loose part in a bag and no fitting screen. A vendor who sells
	hulls of your ship's class will bolt a part straight onto the hull you
	have equipped, and buying a better one in the same slot replaces what is
	there -- full price, nothing back. The same call `Shops.EXTRACT_FRACTION`
	makes about crystals: undoing a decision costs, and pretending otherwise
	makes the decision free.

	WHERE THE NUMBERS COME FROM
	The gain ladder is authored, the way `Affixes` and `Crystals.GRADES`
	author theirs -- it is a balance curve and there is nothing honest to
	derive it from. **The price is not.** A part costs a fraction of the
	hull's own price, so modding a starter sled is cheap, modding an
	interceptor is not, and the whole economy retunes itself the day a hull's
	`cost` changes.

	That fraction is set so a **full set of Mk V costs more than the next
	hull up**, which is the one economic rule this feature has to keep: if
	maxing out were the cheap way to advance, the ship catalogue would be
	dead the moment this shipped. Upgrading is for the hull you like, not the
	shortcut past the ones you don't.
]]

local Affixes = require(script.Parent.Affixes)
local Ships = require(script.Parent.Ships)

local Upgrades = {}

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------

export type SlotDef = {
	id: string,
	displayName: string,
	--[[
		The `ShipDef` number this slot multiplies.

		Named as a field rather than wired up by hand at each call site so
		that `validate` can prove, at boot, that every slot moves something
		that actually exists on every hull. A slot naming a field nobody has
		is a part the player buys, pays for, and gets nothing from -- the
		2026-08-18 failure again, in a new file.
	]]
	field: string,
	--- One line, shown in the shop. The promise the multiplier has to keep.
	blurb: string,
}

--[[
	Three, and they are the three the ask named.

	Weapons are the fourth and are deliberately not here: a hardpoint is not
	a multiplier on a number the hull already has, it is a new verb, and
	folding it into this table would mean a slot whose `field` is a lie.
]]
local SLOTS: { SlotDef } = {
	{
		id = "Engine",
		displayName = "Engine",
		field = "speed",
		blurb = "More thrust than the frame was drawn for.",
	},
	{
		id = "Gyro",
		displayName = "Gyros",
		field = "turnSpeed",
		blurb = "Turns where you point it instead of where it was going.",
	},
	{
		id = "Plating",
		displayName = "Plating",
		field = "integrity",
		blurb = "Something between you and the wall.",
	},
}

--------------------------------------------------------------------------------
-- Grades
--------------------------------------------------------------------------------

export type GradeDef = {
	--- Name fragment: "Mk III".
	word: string,
	--- Fraction added to the slot's field. 0.18 is +18%.
	gain: number,
	--[[
		Price as a fraction of the hull's own cost.

		Rising much faster than the gain does, and that is the shape of the
		whole feature. Mk I is pocket change on any hull, so everyone fits
		one; Mk V is a whole new ship, so nobody fits three by accident.
	]]
	price: number,
	--[[
		Which `Affixes` rarity this grade *is*, 0..4.

		Borrowed rather than invented, the same trick `Crystals.GRADES`
		plays: the panel already turns a rarity into a colour and a word, and
		a second vocabulary for "how good is this" would be a second thing to
		keep in step.
	]]
	rarity: number,
}

--- Worst to best. Index is `rarity + 1`, and `validate` holds that.
local GRADES: { GradeDef } = {
	{ word = "Mk I", gain = 0.06, price = 0.05, rarity = 0 },
	{ word = "Mk II", gain = 0.12, price = 0.12, rarity = 1 },
	{ word = "Mk III", gain = 0.18, price = 0.25, rarity = 2 },
	{ word = "Mk IV", gain = 0.24, price = 0.45, rarity = 3 },
	--[[
		A Mk V costs what the hull under it cost.

		Not a flourish -- it is the smallest number that satisfies the rule
		below. The tightest step in the ship catalogue is 30,000 to 85,000,
		a factor of 2.83, so three top parts only beat the next hull up once
		each one is worth more than 0.944 of a frame. Rounded to 1, because
		"a full set is three ships" is a thing a player can hold in their
		head and 0.95 is not.
	]]
	{ word = "Mk V", gain = 0.3, price = 1, rarity = 4 },
}

--[[
	The best any one slot can do, which several other files need to reason
	about.

	`Ships.validate` demands `integrity >= speed`, because impact damage is
	the speed the hull lost in the crash and a hull under that line is
	disabled by its first wall. A maxed engine moves the left-hand side of
	that inequality and nothing else does, so the rule the catalogue actually
	has to satisfy is `integrity >= speed * (1 + MAX_GAIN)` -- checked below,
	and the reason three hulls had their integrity raised the day this
	landed.
]]
Upgrades.MAX_GAIN = GRADES[#GRADES].gain

--------------------------------------------------------------------------------
-- The catalogue, composed at require time
--------------------------------------------------------------------------------

export type PartDef = {
	id: string,
	slot: SlotDef,
	grade: GradeDef,
	displayName: string,
	description: string,
	rarity: number,
}

local defs: { [string]: PartDef } = {}
local ids: { string } = {}

--[[
	Fifteen entries composed from three slots and five grades, rather than
	fifteen written out.

	`Radiant` and `Crystals` both do this and the argument has not changed:
	hand-written, every one of them would look right whichever grade had been
	pasted into whichever slot.
]]
for _, slot in SLOTS do
	for _, grade in GRADES do
		local id = slot.id .. string.gsub(grade.word, " ", "")
		defs[id] = {
			id = id,
			slot = slot,
			grade = grade,
			displayName = `{slot.displayName} {grade.word}`,
			description = slot.blurb,
			rarity = grade.rarity,
		}
		table.insert(ids, id)
	end
end
table.sort(ids)

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

function Upgrades.exists(id: string): boolean
	return defs[id] ~= nil
end

function Upgrades.get(id: string): PartDef
	local d = defs[id]
	assert(d, `Upgrades.get: no part "{id}"`)
	return d
end

--- Every part id, sorted.
function Upgrades.ids(): { string }
	return table.clone(ids)
end

--- Every slot, in the order declared above.
function Upgrades.slots(): { SlotDef }
	return table.clone(SLOTS)
end

function Upgrades.slotExists(slotId: string): boolean
	for _, slot in SLOTS do
		if slot.id == slotId then
			return true
		end
	end
	return false
end

--[[
	What a hull's `field` is multiplied by, given what is fitted to it.

	One reader for all three slots, so `VehicleController`'s flight loop and
	`VehicleService.integrity` cannot end up disagreeing about what a Mk III
	is worth. Returns exactly 1 for a bare hull, an unknown part or a slot
	nobody has heard of -- a missing key must never make a ship slower than
	the catalogue says it is.
]]
function Upgrades.multiplier(fitted: { [string]: string }?, slotId: string): number
	if not fitted then
		return 1
	end
	local d = defs[fitted[slotId] or ""]
	if not d or d.slot.id ~= slotId then
		return 1
	end
	return 1 + d.grade.gain
end

--[[
	What this part costs on this hull, before any vendor markup.

	A fraction of what the hull itself cost. `math.ceil` rather than floor so
	nothing is ever free, however cheap the frame it is going on.
]]
function Upgrades.cost(shipId: string, partId: string): number
	local d = defs[partId]
	if not d or not Ships.exists(shipId) then
		return 0
	end
	return math.ceil(Ships.get(shipId).cost * d.grade.price)
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

--[[
	Reports, at boot, every way this table could quietly do nothing.

	Called from `VehicleService.start` beside `Ships.validate`, because every
	failure here is a fact about a hull.
]]
function Upgrades.validate(): { string }
	local problems: { string } = {}

	for _, slot in SLOTS do
		for _, id in Ships.ids() do
			local value = (Ships.get(id) :: any)[slot.field]
			if type(value) ~= "number" then
				table.insert(
					problems,
					`Upgrades: slot "{slot.id}" moves "{slot.field}", which "{id}" has not got`
				)
				break
			end
		end
	end

	for i, grade in GRADES do
		if grade.rarity ~= i - 1 then
			table.insert(
				problems,
				`Upgrades: grade "{grade.word}" is at index {i} but claims rarity {grade.rarity}`
			)
		end
		if i > 1 then
			local below = GRADES[i - 1]
			if grade.gain <= below.gain or grade.price <= below.price then
				table.insert(
					problems,
					`Upgrades: grade "{grade.word}" is no better or no dearer than "{below.word}"`
				)
			end
		end
	end
	if #GRADES ~= Affixes.MAX_AFFIXES + 1 then
		table.insert(problems, `Upgrades: {#GRADES} grades against {Affixes.MAX_AFFIXES + 1} rarities`)
	end

	--[[
		The rule the whole feature has to not break.

		`Ships.validate` already refuses a hull whose integrity is under its
		own top speed -- one flat-out hit has to leave you limping rather
		than walking. A maxed engine raises that top speed, and a player is
		perfectly free to fit one and no plating at all, so the bar the
		catalogue must actually clear is the upgraded one.

		This is not a warning to live with. It caught three hulls the day it
		was written and all three were fixed in `Ships.luau`, which is the
		correct response: the fix is a tougher frame, never a smaller engine.
	]]
	for _, id in Ships.ids() do
		local d = Ships.get(id)
		local top = d.speed * (1 + Upgrades.MAX_GAIN)
		if d.integrity < top then
			table.insert(
				problems,
				`Upgrades: "{id}" has {d.integrity} integrity against a maxed top speed of {math.floor(
					top + 0.5
				)}`
			)
		end
	end

	--[[
		And the economic one.

		A full set of top-grade parts has to cost more than the next hull up,
		or upgrading becomes the cheap way to advance and the ship catalogue
		stops being a catalogue. Checked against the cheapest hull that costs
		more than this one, which is what "the next hull up" means when the
		tiers are not in price order.
	]]
	local fullSet = #SLOTS * GRADES[#GRADES].price
	for _, id in Ships.ids() do
		local d = Ships.get(id)
		local nextUp = math.huge
		for _, other in Ships.ids() do
			local o = Ships.get(other)
			if o.cost > d.cost and o.cost < nextUp then
				nextUp = o.cost
			end
		end
		if nextUp < math.huge and d.cost * fullSet <= nextUp then
			table.insert(
				problems,
				`Upgrades: a full set on "{id}" costs {math.ceil(d.cost * fullSet)}, `
					.. `no more than the {nextUp} hull above it`
			)
		end
	end

	table.sort(problems)
	return problems
end

return Upgrades
