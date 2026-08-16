--!strict
--[[
	Panels.luau

	The list of interface panels, written down once.

	WHY THIS EXISTS
	Adding the galaxy map meant typing "GalaxyMapController" into six unrelated
	files: the input focus check, the waypoint's hide test, the vendor sign's
	hide test, and the mutual-close list inside each of the other four panels.
	Every one of those is a plain string in a plain array, so forgetting one
	does not fail to compile, does not warn, and does not error at runtime. It
	produces a specific and confusing symptom instead -- a panel you can shoot
	through, or a quest marker drawn on top of the map that is meant to replace
	it -- and you get to guess which of the six it was.

	The duplication was also quadratic: each new panel had to be added to every
	existing panel's close list *and* needed a close list of its own naming all
	the others.

	So the registry is the source of truth and the checks are derived from it.
	Declaring a panel here is the whole of registering it.

	WHY IT LIVES IN Shared/Core RATHER THAN WITH THE CONTROLLERS
	Nothing on the server has panels. But `src/client/Controllers` is scanned by
	`ServiceLoader.addFrom`, which expects every module in it to be a service,
	and this is a lookup table rather than something with a lifecycle. Sitting
	next to the loader it wraps also keeps the require path the same as every
	other cross-cutting module.

	IT HOLDS NAMES, NOT PANELS
	Everything is resolved through `ServiceLoader.find` at the moment it is
	needed, and a panel that is missing is skipped rather than raising. A
	controller that failed to load should cost you that one panel, not the
	ability to shoot.
]]

local ServiceLoader = require(script.Parent.ServiceLoader)

local Panels = {}

export type PanelDef = {
	--- The controller's `name`, as `ServiceLoader` knows it.
	name: string,
	--[[
		Whether it covers the world.

		Full-screen panels are the 760x470 ones, and while any of them is up
		there is nothing behind it worth drawing -- waypoints and vendor signs
		hide. A panel that leaves the world visible sets this false and stays
		out of those checks, while still taking input focus.
	]]
	fullScreen: boolean,
}

local ALL: { PanelDef } = {
	-- Modal, and the only one with no key: it refuses `setOpen(false)` until
	-- the character has an origin. Registered here anyway so it takes input
	-- focus and hides the world behind it like the rest.
	{ name = "CreationController", fullScreen = true },
	{ name = "InventoryController", fullScreen = true },
	{ name = "MissionBoardController", fullScreen = true },
	{ name = "SkillTreeController", fullScreen = true },
	{ name = "GalaxyMapController", fullScreen = true },
	-- 760x250 along the bottom: you keep seeing the person you are talking to,
	-- so nothing hides for it. Picking a reply is still a click on a button in
	-- front of someone, which is why it takes focus like the rest.
	{ name = "DialogueController", fullScreen = false },
}

Panels.ALL = ALL

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

local function isOpen(def: PanelDef): boolean
	local panel = ServiceLoader.find(def.name)
	return panel ~= nil and panel.isOpen() == true
end

--[[
	True while any panel has the player's attention.

	Used to swallow clicks: pressing a Buy button should not also put a bolt
	through the shopkeeper standing behind it.
]]
function Panels.anyOpen(): boolean
	for _, def in ALL do
		if isOpen(def) then
			return true
		end
	end
	return false
end

--- True while the world is covered, so anything drawn in it can be skipped.
function Panels.anyFullScreenOpen(): boolean
	for _, def in ALL do
		if def.fullScreen and isOpen(def) then
			return true
		end
	end
	return false
end

--[[
	Closes every panel except `keep`.

	Called by a panel as it opens, so the caller names only itself and never
	has to know what else exists. Passing a name that is not a panel is
	harmless and closes everything, which is the useful behaviour for anything
	that wants a clear screen.
]]
function Panels.closeAllExcept(keep: string)
	for _, def in ALL do
		if def.name == keep then
			continue
		end
		local panel = ServiceLoader.find(def.name)
		if panel then
			panel.setOpen(false)
		end
	end
end

return Panels
