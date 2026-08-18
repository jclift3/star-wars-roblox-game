--!strict
--[[
	Ships.luau

	Every vehicle a player can own: how it handles, what it costs, and the
	part list that builds it.

	WHY GROUND SPEEDERS AND NOT STARSHIPS
	The roadmap's Phase 2b is "ships", and the expensive half of that is a
	space scene: a second place, a docking flow, flight in six degrees of
	freedom, and something to *do* once you are out there. The cheap half is
	the half that actually hurts right now. A district is roughly a minute
	across on foot and a planet is several, so every mission is bracketed by
	a walk that is not gameplay. A speeder fixes that with the world we
	already have, and it does it without inventing a single new place.

	So `class` exists and every entry says "Speeder". When a starship lands
	it will be a second class in this same file, sharing the economy, the
	ownership record and the part builder, and only its physics will differ.

	GEOMETRY IS IN ABSOLUTE STUDS
	Same convention as Weapons.luau, and for the same reason: a speeder has
	to line up with the ground and with a seated rig, and both of those are
	world measurements. `ShipPart` is deliberately its own type rather than a
	reuse of `WeaponPart` -- they happen to have the same fields today, and
	binding a vehicle's geometry to the weapon config so that widening one
	silently changes the other is a trade with no upside.

	THE ORIGIN IS THE HULL CENTRE AND THE NOSE POINTS -Z
	-Z is the direction a Roblox character faces, which means a seated rig
	faces the way the speeder is going without a correction anywhere. `+Y` is
	up; `hoverHeight` is measured from the ground to this origin, so a part
	at `offset.Y = -1` sits one stud below the hover line.
]]

local Palette = require(script.Parent.Palette)

local Ships = {}

export type ShipPart = {
	name: string,
	shape: string?, -- "Block" | "Cylinder" | "Ball" | "Wedge"
	size: Vector3,
	offset: Vector3, -- studs, relative to the hull centre
	rot: Vector3?, -- euler degrees
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	light: { color: Color3, range: number, brightness: number }?,
}

export type ShipDef = {
	id: string,
	displayName: string,
	description: string,
	class: string, -- "Speeder" today; "Starship" when Phase 2b's other half lands

	-- Handling ---------------------------------------------------------
	speed: number, -- studs/sec flat out; a sprinting character does ~32
	acceleration: number, -- studs/sec^2, how fast it reaches `speed`
	turnSpeed: number, -- degrees/sec of yaw at full lock
	hoverHeight: number, -- studs from the ground to the hull centre
	bank: number, -- degrees of roll into a full-lock turn; pure showmanship

	-- Economy ----------------------------------------------------------
	tier: number, -- 1..5, drives vendor stocking
	cost: number,
	requiredLevel: number,

	-- Geometry ---------------------------------------------------------
	seatSize: Vector3,
	seatOffset: Vector3, -- the driver's seat
	passengerOffsets: { Vector3 }, -- empty for a one-seater
	parts: { ShipPart },
}

local defs: { [string]: ShipDef } = {}

local function def(s: ShipDef): ShipDef
	defs[s.id] = s
	return s
end

local V3 = Vector3.new

--[[
	A repulsorlift turbine: a cylinder lying along Z with a glowing intake.

	Returned as two parts because the glow has to be its own part to be Neon
	while the housing stays Metal -- material is per-part, and a turbine that
	glows all over reads as a lightsaber rather than an engine.
]]
local function turbine(name: string, at: Vector3, length: number, radius: number, glow: Color3): { ShipPart }
	return {
		{
			name = name,
			shape = "Cylinder",
			size = V3(length, radius * 2, radius * 2),
			offset = at,
			rot = V3(0, 90, 0),
			color = Palette.Gunmetal,
			material = Enum.Material.Metal,
		},
		{
			name = name .. "Intake",
			shape = "Cylinder",
			size = V3(0.3, radius * 1.55, radius * 1.55),
			offset = at + V3(0, 0, -length * 0.5 - 0.1),
			rot = V3(0, 90, 0),
			color = glow,
			material = Enum.Material.Neon,
			light = { color = glow, range = 10, brightness = 1.2 },
		},
	}
end

--- Appends `extra` to `into` in place. Purely to keep the part lists readable.
local function add(into: { ShipPart }, extra: { ShipPart })
	for _, p in extra do
		table.insert(into, p)
	end
end

--------------------------------------------------------------------------------
-- Tier 1 -- the thing you can actually afford first
--------------------------------------------------------------------------------

local sledParts: { ShipPart } = {
	{
		name = "Deck",
		size = V3(5, 0.5, 9),
		offset = V3(0, -0.7, 0),
		color = Palette.WornSteel,
		material = Enum.Material.DiamondPlate,
	},
	{
		name = "Prow",
		shape = "Wedge",
		size = V3(4.2, 0.9, 2),
		offset = V3(0, -0.25, -5.2),
		rot = V3(0, 180, 0),
		color = Palette.WornSteel,
		material = Enum.Material.DiamondPlate,
	},
	{
		name = "RailLeft",
		size = V3(0.3, 1, 8),
		offset = V3(-2.4, 0, 0.4),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	{
		name = "RailRight",
		size = V3(0.3, 1, 8),
		offset = V3(2.4, 0, 0.4),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	{
		name = "Console",
		size = V3(2.2, 0.9, 0.5),
		offset = V3(0, 0.1, -3.4),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
}
add(sledParts, turbine("PodLeft", V3(-1.8, -1.2, 2.2), 4.4, 0.7, Palette.BlasterBlue))
add(sledParts, turbine("PodRight", V3(1.8, -1.2, 2.2), 4.4, 0.7, Palette.BlasterBlue))

def({
	id = "HoverSled",
	displayName = "Ubrikkian Hover-Sled",
	description = "A cargo pallet with a steering column bolted to it. It is slow, it is ugly, and it is the difference between a mission and a hike.",
	class = "Speeder",
	speed = 74,
	acceleration = 42,
	turnSpeed = 95,
	hoverHeight = 3.4,
	bank = 6,
	tier = 1,
	cost = 900,
	requiredLevel = 1,
	seatSize = V3(2.2, 0.4, 2),
	seatOffset = V3(0, -0.2, -1.2),
	passengerOffsets = { V3(0, -0.2, 2.2) },
	parts = sledParts,
})

--------------------------------------------------------------------------------
-- Tier 2 -- the first thing that feels like a vehicle
--------------------------------------------------------------------------------

local bikeParts: { ShipPart } = {
	{
		name = "Fuselage",
		size = V3(1.2, 1, 10),
		offset = V3(0, -0.4, 0),
		color = Palette.Gunmetal,
		material = Enum.Material.Metal,
	},
	{
		name = "NoseCone",
		shape = "Cylinder",
		size = V3(2.4, 1, 1),
		offset = V3(0, -0.4, -5.8),
		rot = V3(0, 90, 0),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	{
		name = "VaneLeft",
		size = V3(0.25, 1.5, 2.4),
		offset = V3(-1.1, 0, -3.6),
		rot = V3(0, -14, 0),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	{
		name = "VaneRight",
		size = V3(0.25, 1.5, 2.4),
		offset = V3(1.1, 0, -3.6),
		rot = V3(0, 14, 0),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	{
		name = "Handlebars",
		shape = "Cylinder",
		size = V3(2.6, 0.24, 0.24),
		offset = V3(0, 0.55, -1.7),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	{
		name = "Cowl",
		size = V3(1.4, 0.9, 2.2),
		offset = V3(0, 0.25, -2.6),
		color = Palette.CopperTrim,
		material = Enum.Material.Metal,
	},
	{
		name = "Exhaust",
		shape = "Cylinder",
		size = V3(0.4, 0.9, 0.9),
		offset = V3(0, -0.4, 5.2),
		rot = V3(0, 90, 0),
		color = Palette.BlasterRed,
		material = Enum.Material.Neon,
		light = { color = Palette.BlasterRed, range = 12, brightness = 1.4 },
	},
}
add(bikeParts, turbine("OutriggerLeft", V3(-1, -0.9, 1.4), 3.6, 0.55, Palette.BlasterBlue))
add(bikeParts, turbine("OutriggerRight", V3(1, -0.9, 1.4), 3.6, 0.55, Palette.BlasterBlue))

def({
	id = "SaddleBike",
	displayName = "Aratech Saddle-Bike",
	description = "Two metres of engine with somewhere to sit behind it. Riders are advised to lean, and are not issued helmets.",
	class = "Speeder",
	speed = 118,
	acceleration = 70,
	turnSpeed = 130,
	hoverHeight = 3.2,
	bank = 22,
	tier = 2,
	cost = 2400,
	requiredLevel = 5,
	seatSize = V3(1.2, 0.4, 2),
	seatOffset = V3(0, 0.35, 0.3),
	passengerOffsets = {},
	parts = bikeParts,
})

--------------------------------------------------------------------------------
-- Tier 3 -- the one you take a friend in
--------------------------------------------------------------------------------

local flareParts: { ShipPart } = {
	{
		name = "Hull",
		size = V3(5.4, 1.2, 11),
		offset = V3(0, -0.3, 0),
		color = Palette.HullWhite,
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.05,
	},
	{
		name = "Bonnet",
		size = V3(4.6, 0.7, 4),
		offset = V3(0, 0.45, -3.4),
		color = Palette.HullWhite,
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.05,
	},
	{
		name = "Prow",
		shape = "Wedge",
		size = V3(4.2, 0.9, 2.4),
		offset = V3(0, 0.15, -6.2),
		rot = V3(0, 180, 0),
		color = Palette.CopperTrim,
		material = Enum.Material.Metal,
	},
	{
		name = "Windscreen",
		size = V3(3.8, 1.3, 0.25),
		offset = V3(0, 1.05, -1.7),
		rot = V3(-25, 0, 0),
		color = Palette.CockpitGlass,
		material = Enum.Material.Glass,
		transparency = 0.55,
	},
	{
		name = "Spine",
		size = V3(0.7, 0.7, 5),
		offset = V3(0, 0.5, 2.6),
		color = Palette.CopperTrim,
		material = Enum.Material.Metal,
	},
}
add(flareParts, turbine("TurbineLeft", V3(-3, -0.2, -1.4), 5.2, 0.95, Palette.BlasterBlue))
add(flareParts, turbine("TurbineRight", V3(3, -0.2, -1.4), 5.2, 0.95, Palette.BlasterBlue))
add(flareParts, turbine("TurbineRear", V3(0, -0.2, 4.6), 4.2, 0.95, Palette.BlasterBlue))

def({
	id = "FlareSpeeder",
	displayName = "Mobquet Flare-S Landspeeder",
	description = "An open two-seater with a lacquered shell and three turbines it does not strictly need. People will look, which is the point.",
	class = "Speeder",
	speed = 142,
	acceleration = 62,
	turnSpeed = 100,
	hoverHeight = 3.8,
	bank = 14,
	tier = 3,
	cost = 6800,
	requiredLevel = 12,
	seatSize = V3(1.6, 0.4, 2),
	seatOffset = V3(-1.1, 0.55, 0.9),
	passengerOffsets = { V3(1.1, 0.55, 0.9) },
	parts = flareParts,
})

--------------------------------------------------------------------------------
-- Tier 4 -- fast enough to be a mistake
--------------------------------------------------------------------------------

local swoopParts: { ShipPart } = {
	{
		name = "Fuselage",
		size = V3(1, 0.9, 13),
		offset = V3(0, -0.3, 0),
		color = Palette.ImperialBlack,
		material = Enum.Material.Metal,
	},
	{
		name = "EngineBlock",
		size = V3(2.6, 2, 4.6),
		offset = V3(0, 0.1, -4.4),
		color = Palette.NabooRoyal,
		material = Enum.Material.Metal,
		reflectance = 0.08,
	},
	{
		name = "VaneLeft",
		size = V3(0.2, 2.6, 3),
		offset = V3(-1.9, -0.2, -2.6),
		rot = V3(0, -10, 0),
		color = Palette.ImperialBlack,
		material = Enum.Material.Metal,
	},
	{
		name = "VaneRight",
		size = V3(0.2, 2.6, 3),
		offset = V3(1.9, -0.2, -2.6),
		rot = V3(0, 10, 0),
		color = Palette.ImperialBlack,
		material = Enum.Material.Metal,
	},
	{
		name = "Fairing",
		size = V3(1.6, 1, 3),
		offset = V3(0, 0.5, -0.6),
		color = Palette.NabooRoyal,
		material = Enum.Material.Metal,
	},
	{
		name = "ThrusterLeft",
		shape = "Cylinder",
		size = V3(0.5, 1, 1),
		offset = V3(-0.65, -0.3, 6.4),
		rot = V3(0, 90, 0),
		color = Palette.BlasterBlue,
		material = Enum.Material.Neon,
		light = { color = Palette.BlasterBlue, range = 14, brightness = 1.6 },
	},
	{
		name = "ThrusterRight",
		shape = "Cylinder",
		size = V3(0.5, 1, 1),
		offset = V3(0.65, -0.3, 6.4),
		rot = V3(0, 90, 0),
		color = Palette.BlasterBlue,
		material = Enum.Material.Neon,
		light = { color = Palette.BlasterBlue, range = 14, brightness = 1.6 },
	},
}
add(swoopParts, turbine("Intake", V3(0, 0.1, -6.9), 1.2, 1.05, Palette.BlasterRed))

def({
	id = "SwoopRacer",
	displayName = "Nubian Swoop Racer",
	description = "A repulsorlift engine with a saddle welded on and every safety interlock removed at the factory. Swoop gangs buy these. So do people who wish they were in one.",
	class = "Speeder",
	speed = 205,
	acceleration = 105,
	turnSpeed = 165,
	hoverHeight = 3.2,
	bank = 32,
	tier = 4,
	cost = 14000,
	requiredLevel = 20,
	seatSize = V3(1.2, 0.4, 2),
	seatOffset = V3(0, 0.5, 2),
	passengerOffsets = {},
	parts = swoopParts,
})

--------------------------------------------------------------------------------
-- Tier 5 -- the one that survives being shot at
--------------------------------------------------------------------------------

local assaultParts: { ShipPart } = {
	{
		name = "Hull",
		size = V3(6.2, 2, 12),
		offset = V3(0, -0.2, 0),
		color = Palette.ImperialGrey,
		material = Enum.Material.DiamondPlate,
	},
	{
		name = "Glacis",
		shape = "Wedge",
		size = V3(5.6, 1.8, 3.2),
		offset = V3(0, 0.5, -6.6),
		rot = V3(0, 180, 0),
		color = Palette.ImperialGrey,
		material = Enum.Material.DiamondPlate,
	},
	{
		name = "SkirtLeft",
		size = V3(0.6, 1.6, 10),
		offset = V3(-3.3, -0.7, 0.4),
		color = Palette.ImperialBlack,
		material = Enum.Material.Metal,
	},
	{
		name = "SkirtRight",
		size = V3(0.6, 1.6, 10),
		offset = V3(3.3, -0.7, 0.4),
		color = Palette.ImperialBlack,
		material = Enum.Material.Metal,
	},
	{
		name = "Casemate",
		size = V3(4.4, 1.4, 4.4),
		offset = V3(0, 1.5, -1.4),
		color = Palette.ImperialGrey,
		material = Enum.Material.DiamondPlate,
	},
	{
		name = "ViewSlit",
		size = V3(3.4, 0.35, 0.25),
		offset = V3(0, 1.7, -3.65),
		color = Palette.CockpitGlass,
		material = Enum.Material.Glass,
		transparency = 0.35,
	},
	{
		name = "EmptyMount",
		shape = "Cylinder",
		size = V3(0.6, 2.2, 2.2),
		offset = V3(0, 2.5, 1),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
}
add(assaultParts, turbine("TurbineLeft", V3(-2.4, -1, 2), 6, 1.2, Palette.BlasterRed))
add(assaultParts, turbine("TurbineRight", V3(2.4, -1, 2), 6, 1.2, Palette.BlasterRed))

def({
	id = "AssaultSpeeder",
	displayName = "Czerka Assault Speeder",
	description = "Surplus, resprayed, and sold to civilians with the weapon mount left bare -- Czerka charges separately for what goes on it, and has not yet quoted you.",
	class = "Speeder",
	speed = 126,
	acceleration = 48,
	turnSpeed = 82,
	hoverHeight = 4.2,
	bank = 8,
	tier = 5,
	cost = 26000,
	requiredLevel = 28,
	seatSize = V3(1.6, 0.4, 2),
	seatOffset = V3(-1.1, 0.75, 0.9),
	passengerOffsets = { V3(1.1, 0.75, 0.9), V3(0, 0.75, 4) },
	parts = assaultParts,
})

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	How far a summoned speeder is placed in front of its owner.

	Far enough that it does not spawn inside them (which would launch both),
	close enough to be an obvious two-step walk. Shared because the client
	draws nothing at this distance today but the moment it does, a second
	copy of the number would drift.
]]
Ships.SUMMON_DISTANCE = 14

--[[
	The key that calls a speeder in, and puts it away again.

	Declared here rather than in either of the two files that need it, for
	exactly the reason `Panels` holds the panel keys: the client binds it and
	the HUD legend advertises it, and a summon key nobody was told about is a
	speeder nobody can ride. V because W A S D are taken by walking, the
	number row by abilities, and B/G/J/K/M by the panels.
]]
Ships.SUMMON_KEY = Enum.KeyCode.V
Ships.SUMMON_HINT = "SPEEDER"

function Ships.get(id: string): ShipDef
	local d = defs[id]
	assert(d, `Ships.get: unknown ship "{id}"`)
	return d
end

function Ships.exists(id: string): boolean
	return defs[id] ~= nil
end

function Ships.all(): { [string]: ShipDef }
	return defs
end

function Ships.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

--- Every seat offset, driver first. Never empty, so callers can index [1].
function Ships.seatOffsets(id: string): { Vector3 }
	local d = Ships.get(id)
	local out = { d.seatOffset }
	for _, p in d.passengerOffsets do
		table.insert(out, p)
	end
	return out
end

--[[
	Checks nothing here is quietly unusable.

	Called at boot with the other config validators. The failures worth
	catching are the ones a playtest reports as a feeling rather than a bug:
	a speeder that hovers below its own hull grinds along the floor, and one
	with no acceleration never reaches the speed on its label.
]]
function Ships.validate(): { string }
	local problems: { string } = {}
	for id, d in defs do
		if d.speed <= 32 then
			-- 32 is roughly a sprinting character. Slower than that and the
			-- vehicle is a downgrade you paid for.
			table.insert(problems, `Ships: "{id}" is no faster than running`)
		end
		if d.acceleration <= 0 or d.turnSpeed <= 0 then
			table.insert(problems, `Ships: "{id}" has a non-positive acceleration or turnSpeed`)
		end
		if d.cost < 0 then
			table.insert(problems, `Ships: "{id}" has a negative cost`)
		end
		if #d.parts == 0 then
			table.insert(problems, `Ships: "{id}" has no parts and would be invisible`)
		end

		--[[
			The lowest point of the hull must clear the ground it hovers over.

			The vertical half-extent has to be computed through the part's
			rotation, not read off `size.Y`. Every turbine in this file is a
			cylinder lying on its side -- a `rot` of 90 degrees about Y --
			so its length is on X and reading `size.Y` would understate a
			landspeeder's clearance by three studs.
		]]
		local lowest = 0
		for _, p in d.parts do
			local r = p.rot or Vector3.zero
			local cf = CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
			local halfY = math.abs(cf.RightVector.Y) * p.size.X * 0.5
				+ math.abs(cf.UpVector.Y) * p.size.Y * 0.5
				+ math.abs(cf.LookVector.Y) * p.size.Z * 0.5
			lowest = math.min(lowest, p.offset.Y - halfY)
		end
		if d.hoverHeight + lowest < 0.5 then
			table.insert(problems, `Ships: "{id}" hovers at {d.hoverHeight} but reaches down to {lowest}`)
		end
	end
	table.sort(problems)
	return problems
end

return Ships
