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
	-- How many crystals this item can hold, 0..`Crystals.MAX_SOCKETS`. Rolled
	-- once when it drops and never changed: emptying a socket returns the hole,
	-- not the stone.
	sockets: number?,
	--[[
		What is in those holes, as socket index -> crystal id.

		A map keyed by the index written out as a string, and never an array.
		Socket 2 can be full while socket 1 is empty, and a sparse array
		survives neither a DataStore round trip nor replication -- the same
		reason `profile.inventory` and `flags` are maps. One hole and the tail
		of a list disappears without an error anywhere.
	]]
	socketed: { [string]: string }?,
}

export type Inventory = { [string]: ItemStack }

local Inventory = {}

--[[
	How many *unmergeable* items a bag holds.

	Only these are capped, because only they are unbounded. Plain stacks merge
	by catalogue id, so the catalogue itself is their ceiling -- a few dozen
	rows however long anyone plays. An item that rolled affixes, or that
	dropped with sockets in it, never merges: it arrives as its own stack about
	every seven kills and until the shop learned to sell and discard, nothing
	ever took one back out. That is the only leak there is, so it is the only
	thing worth a limit.

	Being over the cap is legal. `load` never refuses, so a bag that grew
	before the cap existed comes back whole and simply cannot take another drop
	until something is sold or thrown away.
]]
Inventory.MAX_UNIQUE = 30

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--[[
	Whether a stack is one particular object rather than a count of a kind.

	Affixes were the original answer; sockets are the second, and they had to
	join it rather than get a rule of their own. A DH-17 with two holes drilled
	in it is not interchangeable with the one on the vendor's shelf, so merging
	them would silently destroy whichever was socketed.
]]
local function isUnique(stack: ItemStack): boolean
	return stack.rolls ~= nil or (stack.sockets ~= nil and stack.sockets > 0)
end

--- How many unmergeable items are carried. See MAX_UNIQUE.
function Inventory.unique(inv: Inventory): number
	local n = 0
	for _, stack in inv do
		if isUnique(stack) then
			n += 1
		end
	end
	return n
end

--- Whether another unmergeable item would fit.
function Inventory.full(inv: Inventory): boolean
	return Inventory.unique(inv) >= Inventory.MAX_UNIQUE
end

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
	The catalogue id behind a uid -- what `profile.equipped` holds.

	Falls back to the uid itself when no stack matches, which is correct rather
	than lenient: a plain item's uid *is* its catalogue id, and fists are
	equipped without ever being owned, so there is nothing to look up.
]]
function Inventory.idOf(inv: Inventory, uid: string?): string?
	if not uid then
		return nil
	end
	local stack = inv[uid]
	return if stack then stack.id else uid
end

--- What a specific carried item rolled, if anything.
function Inventory.rollsOf(inv: Inventory, uid: string?): Rolls?
	if not uid then
		return nil
	end
	local stack = inv[uid]
	return stack and stack.rolls
end

--- How many crystal sockets a specific carried item has.
function Inventory.socketsOf(inv: Inventory, uid: string?): number
	if not uid then
		return 0
	end
	local stack = inv[uid]
	return if stack then (stack.sockets or 0) else 0
end

--- What is in those sockets, as index-string -> crystal id.
function Inventory.socketedOf(inv: Inventory, uid: string?): { [string]: string }?
	if not uid then
		return nil
	end
	local stack = inv[uid]
	return stack and stack.socketed
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

--- The unconditional insert. `add` is this plus the cap; `load` needs it
--- without, so that a save is never quietly truncated on its way back in.
local function insert(
	inv: Inventory,
	id: string,
	count: number?,
	rolls: Rolls?,
	sockets: number?,
	socketed: { [string]: string }?
): string
	local holes = if sockets and sockets > 0 then math.floor(sockets) else nil
	if rolls or holes then
		local suffix = 2
		while inv[`{id}#{suffix}`] do
			suffix += 1
		end
		local uid = `{id}#{suffix}`
		inv[uid] = { uid = uid, id = id, count = 1, rolls = rolls, sockets = holes, socketed = socketed }
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
	Puts items in. Returns the uid of the stack they went into, or nil if the
	bag would not take them.

	Plain items merge into the single stack named after their id. Rolled or
	socketed ones never merge -- each is its own stack, and `count` is ignored
	for them, because a roll and a drilled hole are both properties of one
	object rather than of a kind of object.

	**Only an unmergeable item can be refused.** Purchases, mission rewards and
	pickups are all plain and so cannot fail here; the one caller that has to
	read the return is the loot drop. See MAX_UNIQUE.
]]
function Inventory.add(inv: Inventory, id: string, count: number?, rolls: Rolls?, sockets: number?): string?
	if (rolls or (sockets and sockets > 0)) and Inventory.full(inv) then
		return nil
	end
	return insert(inv, id, count, rolls, sockets)
end

--[[
	Takes items out. Returns how many actually came out, which may be fewer
	than asked for -- callers must pay out against the return value, not the
	request, or a player hands over one crate and gets paid for two.

	Plain stacks go first so that spending a quest item does not consume a
	rolled or socketed one that happens to share its catalogue id.
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
			-- Pass 1 is the plain stacks, pass 2 the unmergeable ones.
			local plain = not isUnique(stack)
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

--[[
	Puts a crystal in one hole. True if it went in.

	Refuses a hole this item does not have and a hole that is already full --
	the second is not paranoia but the shape of the UI: two clicks on the same
	socket dot arrive as two calls, and the second must not overwrite a stone
	the player just paid for and cannot get back.

	Consuming the crystal from the bag is the caller's job, because only the
	caller knows whether it is spending one or moving one.
]]
function Inventory.socket(inv: Inventory, uid: string, index: number, crystalId: string): boolean
	local stack = inv[uid]
	if not stack or index < 1 or index > (stack.sockets or 0) then
		return false
	end
	local filled = stack.socketed or {}
	local key = tostring(math.floor(index))
	if filled[key] then
		return false
	end
	filled[key] = crystalId
	stack.socketed = filled
	return true
end

--- Empties one hole and returns what was in it. The hole stays.
function Inventory.unsocket(inv: Inventory, uid: string, index: number): string?
	local stack = inv[uid]
	local filled = stack and stack.socketed
	if not filled then
		return nil
	end
	local key = tostring(math.floor(index))
	local id = filled[key]
	filled[key] = nil
	if id and next(filled) == nil then
		-- Cleared rather than left as an empty table, so a save does not
		-- accumulate `socketed = {}` on every item anybody ever fiddled with.
		stack.socketed = nil
	end
	return id
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
				insert(out, key, value)
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

			--[[
				Sockets need no migration: a profile written before they
				existed simply has neither field, and nil is already the right
				answer for "no holes". What is read back is clamped rather than
				trusted, so a hand-edited save cannot mint a fourth socket.
			]]
			local sockets: number? = nil
			if type(value.sockets) == "number" then
				local n = math.clamp(math.floor(value.sockets), 0, 8)
				sockets = if n > 0 then n else nil
			end
			local socketed: { [string]: string }? = nil
			if sockets and type(value.socketed) == "table" then
				local filled: { [string]: string } = {}
				local any = false
				for i = 1, sockets do
					local hole = tostring(i)
					if type(value.socketed[hole]) == "string" then
						filled[hole] = value.socketed[hole]
						any = true
					end
				end
				socketed = if any then filled else nil
			end

			-- Re-keyed rather than trusting the saved uid, so a save
			-- hand-edited into two stacks with the same key cannot make one of
			-- them vanish on the next write. Uncapped on purpose: a bag that
			-- is over the limit has to come back as it was, not shorter.
			insert(out, value.id, count, rolls, sockets, socketed)
		end
	end

	return out
end

return Inventory
