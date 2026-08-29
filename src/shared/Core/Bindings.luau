--!strict
--[[
	Bindings.luau

	Every key the game binds, in one list, so two of them cannot be the same.

	WHY THIS EXISTS
	2026-08-29: the hyperdrive was given **H**, which had been the cabin door
	since the ship got an inside. The key was chosen by reading the on-screen
	legend for a free letter -- and the legend is built by walking `Panels.ALL`
	plus five hand-written rows, so the one binding that had not yet been
	added to it was invisible to exactly the check that would have caught it.
	It shipped, and it was found by a fourteen-year-old pressing H in a ship.

	That is the same shape as `Flags.luau` and `Progression.LIVE_STATS`: a
	registry exists so that a mistake nobody can see becomes a line in the
	output at boot. It is not a binding system and it does not own the keys --
	`Ships`, `Furnishings` and `Panels` still declare their own, next to the
	behaviour they belong to. This only reads them back and counts.

	ADDING A KEY
	Declare it where it belongs, then add one line to `collect` below. If you
	forget, nothing breaks and nothing checks it, which is the honest cost of
	a registry that cannot enumerate what it does not know about.
]]

local Furnishings = require(script.Parent.Parent.Config.Furnishings)
local Ships = require(script.Parent.Parent.Config.Ships)
local Panels = require(script.Parent.Panels)

local Bindings = {}

export type Binding = {
	key: Enum.KeyCode,
	--- What the player is told it does. Doubles as the legend caption.
	hint: string,
	--- Where it is declared, so a collision names two files rather than two
	--- letters and leaves you to find them.
	source: string,
}

local function collect(): { Binding }
	local all: { Binding } = {
		{ key = Ships.SUMMON_KEY, hint = Ships.SUMMON_HINT, source = "Ships.SUMMON_KEY" },
		{ key = Ships.PITCH_UP_KEY, hint = Ships.PITCH_UP_HINT, source = "Ships.PITCH_UP_KEY" },
		{ key = Ships.PITCH_DOWN_KEY, hint = Ships.PITCH_DOWN_HINT, source = "Ships.PITCH_DOWN_KEY" },
		{ key = Ships.ENGAGE_KEY, hint = Ships.ENGAGE_HINT, source = "Ships.ENGAGE_KEY" },
		{ key = Furnishings.BOARD_KEY, hint = Furnishings.BOARD_HINT, source = "Furnishings.BOARD_KEY" },
		{ key = Panels.MENU_KEY, hint = Panels.MENU_HINT, source = "Panels.MENU_KEY" },
	}

	for _, def in Panels.ALL do
		local toggle = def.toggle
		if toggle then
			table.insert(all, { key = toggle.key, hint = toggle.hint, source = `Panels.{def.name}` })
		end
	end

	return all
end

Bindings.ALL = collect()

--[[
	Boot check, warned by whoever calls it.

	Two bindings on one key is not a crash and not a warning from Roblox: it
	is both handlers firing, or one of them silently losing, depending on
	which listener was connected first. From the cockpit it looks like the
	game ignoring you.
]]
function Bindings.validate(): { string }
	local problems = {}
	local seen: { [Enum.KeyCode]: Binding } = {}

	for _, binding in Bindings.ALL do
		local clash = seen[binding.key]
		if clash then
			table.insert(
				problems,
				`{binding.key.Name} is bound twice: {clash.source} ({clash.hint}) and {binding.source} ({binding.hint})`
			)
		else
			seen[binding.key] = binding
		end
	end

	return problems
end

return Bindings
