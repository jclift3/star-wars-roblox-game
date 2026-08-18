--!strict
--[[
	WorldClock.luau

	What time it is on a given planet.

	ONE CLOCK, NOT ONE PER MACHINE
	This is a pure function of `Workspace:GetServerTimeNow()` and the planet's
	own `dayLength`. It holds no state, ticks nothing, and is never told
	anything -- so the server and every client that asks get the same number to
	the frame, without a remote, a replicated value or a service to start.

	That is the whole reason it exists. Before this, `AtmosphereController` kept
	a private accumulator seeded to 09:00 whenever you landed, which meant two
	people standing next to each other on Tatooine were in different hours of
	the same afternoon if they had arrived five minutes apart. Nobody had
	noticed because nothing but the sky read the clock. The moment NPCs started
	going home at dusk, that stopped being a curiosity and became one brother
	watching a market close while the other watched it stay open.

	`SkyTrafficController` had already reached the same conclusion on its own
	and seeded itself off `GetServerTimeNow()`; this is that idea with a name.

	EACH WORLD KEEPS ITS OWN TIME
	Nine planets on one server, each with its own `dayLength`, and an offset
	derived from the planet id -- so it is not simultaneously noon everywhere,
	and Korriban's night is Korriban's rather than a global one. There is no
	continuity between worlds and there should not be: a jump takes an
	unspecified while, and the alternative is a galaxy that shares one sunset.
]]

local Workspace = game:GetService("Workspace")

local Planets = require(script.Parent.Parent.Config.Planets)

local WorldClock = {}

--[[
	The four hours that matter, as boundaries on a 24 hour clock.

	Dawn and dusk are wide (two hours each) because they are the interesting
	part: an NPC that changes what it is doing exactly at 06:00:00 reads as a
	switch being thrown, and the shift pass in NPCService deliberately does not
	run during them -- whoever is going home has that whole window to walk.
]]
local DAWN_START = 5
local DAY_START = 7
local DUSK_START = 18
local NIGHT_START = 20

export type Phase = "Night" | "Dawn" | "Day" | "Dusk"

--- A stable 0..1 offset for a planet, so no two worlds share a sunrise.
local function offsetFor(planetId: string): number
	-- Sum of bytes rather than anything clever: it only has to be stable
	-- across machines and spread nine ids out, and this is both. A hash that
	-- differed between server and client would reintroduce the exact bug this
	-- file exists to fix, so the arithmetic stays trivially inspectable.
	local total = 0
	for i = 1, #planetId do
		total += string.byte(planetId, i) * i
	end
	return (total % 997) / 997
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	The hour on `planetId`, 0..24, as a float.

	Unknown ids get noon rather than an error. This is read from a render loop
	and from the NPC tick; a bad planet id should make the sky boring, not
	throw sixty times a second.
]]
function WorldClock.hourOn(planetId: string): number
	if not Planets.exists(planetId) then
		return 12
	end
	-- `dayLength` is in hours of real time. The floor keeps a typo'd 0 from
	-- turning into a division by zero and a day that lasts one frame.
	local secondsPerDay = math.max(60, Planets.get(planetId).dayLength * 3600)
	local turns = Workspace:GetServerTimeNow() / secondsPerDay + offsetFor(planetId)
	return (turns % 1) * 24
end

function WorldClock.phaseAt(hour: number): Phase
	if hour < DAWN_START or hour >= NIGHT_START then
		return "Night"
	elseif hour < DAY_START then
		return "Dawn"
	elseif hour < DUSK_START then
		return "Day"
	end
	return "Dusk"
end

function WorldClock.phaseOn(planetId: string): Phase
	return WorldClock.phaseAt(WorldClock.hourOn(planetId))
end

--[[
	24 hour time as a string, for the HUD.

	Padded by hand: Luau's string interpolation has no format spec, so `{m}`
	on a single-digit minute would read "7:5".
]]
function WorldClock.label(planetId: string): string
	local hour = WorldClock.hourOn(planetId)
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60)
	return `{if h < 10 then "0" else ""}{h}:{if m < 10 then "0" else ""}{m}`
end

return WorldClock
