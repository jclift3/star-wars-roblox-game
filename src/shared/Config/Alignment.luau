--!strict
--[[
	Alignment.luau

	The one axis this game measures a character on that is not a number they
	bought: -1000 (merciless) to +1000 (selfless).

	WHY THIS IS NOT REPUTATION
	`factionRep` is what an organisation thinks of you and it is transactional
	-- run enough Imperial errands and the Empire likes you regardless of what
	you did on the way. Alignment is what you actually did. Keeping them
	separate is the whole point of the setting decision: a Sith at +800 is a
	legitimate and interesting character, and a Republic hero at -600 is the
	other one. Collapsing them into one bar deletes both.

	WHY IT DOES NOT MOVE ON KILLS
	It is moved by dialogue choices and mission resolutions only. An alignment
	that counts corpses is a resource the player farms; an alignment that
	counts decisions is a record of them. Killing things is what the entire
	rest of the game already is, so it is the one input that would carry no
	information.

	It has no mechanical effect yet -- that arrives with the deep Force nodes
	and the saber crystal. What it has from today is a name the player can see,
	because a hidden value that quietly gates content later is how you get a
	player who never understands why a door is shut.
]]

local Alignment = {}

Alignment.MIN = -1000
Alignment.MAX = 1000

-- Where a character starts: uncommitted, not neutral-by-conviction. Everything
-- interesting is a departure from here.
Alignment.START = 0

export type Band = {
	-- Lowest alignment in this band. Bands are contiguous and ordered by this.
	min: number,
	name: string,
	colour: Color3,
}

--[[
	Ordered low to high, so `bandFor` can walk down and take the first match.

	Seven rather than three: the middle of the axis is where most characters
	will actually live, and a scale that reads "Dark / Neutral / Light" tells a
	player at +90 nothing about which way they have been drifting.
]]
local BANDS: { Band } = {
	{ min = -1000, name = "Merciless", colour = Color3.fromRGB(200, 62, 62) },
	{ min = -700, name = "Cruel", colour = Color3.fromRGB(196, 96, 76) },
	{ min = -350, name = "Callous", colour = Color3.fromRGB(190, 138, 96) },
	{ min = -100, name = "Unaligned", colour = Color3.fromRGB(168, 172, 180) },
	{ min = 100, name = "Decent", colour = Color3.fromRGB(140, 186, 150) },
	{ min = 350, name = "Compassionate", colour = Color3.fromRGB(104, 190, 160) },
	{ min = 700, name = "Selfless", colour = Color3.fromRGB(96, 176, 214) },
}
Alignment.BANDS = BANDS

function Alignment.clamp(value: number): number
	return math.clamp(value, Alignment.MIN, Alignment.MAX)
end

--- The band `value` falls in. Never nil: the lowest band starts at MIN.
function Alignment.bandFor(value: number): Band
	local found = BANDS[1]
	for _, band in BANDS do
		if value >= band.min then
			found = band
		end
	end
	return found
end

--- What to call a character at `value`, for the panel that shows it.
function Alignment.titleFor(value: number): string
	return Alignment.bandFor(value).name
end

return Alignment
