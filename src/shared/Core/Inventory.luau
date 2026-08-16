--!strict
--[[
	Inventory.luau

	What a player is carrying, and the only sanctioned way to change it.

	The old model was `{ [itemId]: count }` -- a bag of counts. It cannot hold
	two different rolls of the same blaster, so it blocked both rolled loot and
	player-to-player trading. This replaces it with a map of *stacks* keyed by a
	uid, where a stack optionally carries the rolls that make it one particular
	blaster rather than the idea of a blaster.

	A map, not an array. A profile is serialised to a DataStore and replicated
	to the client, and neither survives a sparse array: one hole and the tail of
	the list silently disappears. Keying by uid also makes "remove exactly this
	item" -- which is what equipping and trading need -- a single lookup.

	The uid scheme is deliberately readable in a raw save:
	  * a plain catalogue item uses its own id, so `StimPack` stays `StimPack`
	    and there is exactly one stack of it, which is what stacking means;
	  * a rolled item gets `DH17#2`, `DH17#3`, ... , the lowest free suffix.
	Uids only have to be unique inside one profile. A traded item is a stack
	moving between two inventories, and it is re-keyed on arrival.
]]

--[[
	Rolled modifiers, as stat name -> value.

	Deliberately the same vocabulary `Progression.computeStats` already speaks,
	so an affix that reads `{ DamageMult = 0.08 }` needs no new reader.
]]
export type Rolls = { [string]: number }

export type ItemStack = {
	-- Unique within one inventory. See the uid scheme above.
	uid: string,
	-- Catalogue id: a Weapons / Outfits / Items key.
	id: string,
	-- Stackables only. A rolled item is always a stack of one, because two of
	-- them are by definition not interchangeable.
	count: number,
	rolls: Rolls?,
}

export type Inventory = { [string]: ItemStack }

local Inventory = {}

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--- How many of a catalogue id are carried, across every stack of it.
function Inventory.count(inv: Inventory, id: string): number
	local total = 0
	for _, stack in inv do
		if stack.id == id then
			total += stack.count
		end
	end
	return total
end

--- Whether at least `n` (default 1) of a catalogue id are carried.
function Inventory.has(inv: Inventory, id: string, n: number?): boolean
	return Inventory.count(inv, id) >= (n or 1)
end

--[[
	The distinct catalogue ids carried, sorted.

	Sorted because callers render it: an inventory panel whose rows reshuffle
	every time it opens is one nobody can use. Iteration order over a map is
	not defined.
]]
function Inventory.ids(inv: Inventory): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, stack in inv do
		if not seen[stack.id] then
			seen[stack.id] = true
			table.insert(out, stack.id)
		end
	end
	table.sort(out)
	return out
end

--- Every uid, sorted, so operations over the whole bag are deterministic.
local function uids(inv: Inventory): { string }
	local out: { string } = {}
	for uid in inv do
		table.insert(out, uid)
	end
	table.sort(out)
	return out
end

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------

--[[
	Puts items in. Returns the uid of the stack they went into.

	Plain items merge into the single stack named after their id. Rolled ones
	never merge -- each is its own stack, and `count` is ignored for them,
	because a roll is a property of one object.
]]
function Inventory.add(inv: Inventory, id: string, count: number?, rolls: Rolls?): string
	if rolls then
		local suffix = 2
		while inv[`{id}#{suffix}`] do
			suffix += 1
		end
		local uid = `{id}#{suffix}`
		inv[uid] = { uid = uid, id = id, count = 1, rolls = rolls }
		return uid
	end

	local n = math.max(1, math.floor(count or 1))
	local existing = inv[id]
	if existing then
		existing.count += n
	else
		inv[id] = { uid = id, id = id, count = n, rolls = nil }
	end
	return id
end

--[[
	Takes items out. Returns how many actually came out, which may be fewer
	than asked for -- callers must pay out against the return value, not the
	request, or a player hands over one crate and gets paid for two.

	Plain stacks go first so that spending a quest item does not consume a
	rolled one that happens to share its catalogue id.
]]
function Inventory.remove(inv: Inventory, id: string, count: number): number
	local wanted = math.floor(count)
	if wanted <= 0 then
		return 0
	end

	local order = uids(inv)
	local taken = 0

	local function drain(pass: number)
		for _, uid in order do
			if taken >= wanted then
				return
			end
			local stack = inv[uid]
			if not stack or stack.id ~= id then
				continue
			end
			-- Pass 1 is the plain stacks, pass 2 the rolled ones.
			local plain = stack.rolls == nil
			if (pass == 1) ~= plain then
				continue
			end
			local from = math.min(stack.count, wanted - taken)
			taken += from
			stack.count -= from
			if stack.count <= 0 then
				-- Cleared rather than left at zero, so a spent item does not
				-- sit in the save forever as an empty stack.
				inv[uid] = nil
			end
		end
	end

	drain(1)
	drain(2)
	return taken
end

--- Takes one specific stack out, by uid. Returns it, or nil if it is not there.
function Inventory.take(inv: Inventory, uid: string): ItemStack?
	local stack = inv[uid]
	inv[uid] = nil
	return stack
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

--[[
	Reads whatever a save actually contains.

	Handles three cases, because profiles written by every past build have to
	come back as something playable:
	  * the current map of stacks;
	  * the old `{ [itemId]: count }` bag of counts;
	  * anything else, which becomes an empty inventory rather than an error.
]]
function Inventory.load(saved: any): Inventory
	local out: Inventory = {}
	if type(saved) ~= "table" then
		return out
	end

	for key, value in saved do
		if type(key) ~= "string" then
			continue
		end
		if type(value) == "number" then
			-- Old shape: the key was the catalogue id and the value the count.
			if value > 0 then
				Inventory.add(out, key, value)
			end
		elseif type(value) == "table" and type(value.id) == "string" then
			local count = if type(value.count) == "number" then math.floor(value.count) else 1
			if count <= 0 then
				continue
			end
			local rolls: Rolls? = nil
			if type(value.rolls) == "table" then
				local cleaned: Rolls = {}
				local any = false
				for stat, amount in value.rolls do
					if type(stat) == "string" and type(amount) == "number" then
						cleaned[stat] = amount
						any = true
					end
				end
				rolls = if any then cleaned else nil
			end
			-- Re-keyed through `add` rather than trusting the saved uid, so a
			-- save hand-edited into two stacks with the same key cannot make
			-- one of them vanish on the next write.
			Inventory.add(out, value.id, count, rolls)
		end
	end

	return out
end

return Inventory
