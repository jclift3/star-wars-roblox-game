--!strict
--[[
	Ships.luau

	Every vehicle a player can own: how it handles, what it costs, and the
	part list that builds it. Plus, at the bottom, the hulls nobody owns --
	the ambient traffic, which is geometry and nothing else.

	TWO CLASSES, ONE FILE
	Speeders shipped first (ROADMAP 2b) because the expensive half of "ships"
	is a space scene and the half that was actually costing the player their
	evening was ground travel. That entry predicted this one almost exactly:
	"when a starship lands it will be a second class in this same file,
	sharing the economy, the ownership record and the part builder, and only
	its physics will differ."

	It does. A starship is a speeder that stopped looking for the ground.
	`ShipModel` builds both from the same part list, `VehicleService` spawns
	both, `VehicleController` drives both, and the only branch anywhere is on
	`class`: a speeder holds `hoverHeight` over whatever is beneath it, a
	starship goes where its nose is pointed and `hoverHeight` becomes the
	height of its landing gear.

	WHAT A STARSHIP IS FOR, WHICH IS NOT FLYING
	Flying is the fun part and it is not the point. The point is that the
	Piloting tree -- one of four, and the one the *default* origin is built
	around -- had four nodes and all four were `unimplemented`. A Scoundrel
	could reach level 50 and every skill on their own sheet would still be an
	advertisement. Starships give three of those four something to read:
	`ShipSpeedMult` and `ShipTurnMult` in the flight loop, `FuelCostMult` in
	the fare. `Planets.fuelCost` has existed, unused, since the config was
	written, waiting for exactly this.

	WHERE THEY LAUNCH FROM
	Off a landing pad, not out of thin air beside you. Five of the nine
	worlds already have a `Spaceport` POI and `buildSpaceport` already draws
	three 68-stud pads at each -- the geometry has been standing there since
	the first planet was generated with nothing to land on it. Requiring the
	pad costs the player a walk they would otherwise never take, and buys the
	spaceport a reason to exist.

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
	--[[
		"Speeder" or "Starship". The only thing anything branches on.

		A string rather than an enum because it crosses into `Shops` stock
		filters and a validator below, and both want to say the word.
	]]
	class: string,

	-- Handling ---------------------------------------------------------
	speed: number, -- studs/sec flat out; a sprinting character does ~32
	acceleration: number, -- studs/sec^2, how fast it reaches `speed`
	turnSpeed: number, -- degrees/sec of yaw at full lock
	--[[
		Studs from the ground to the hull centre.

		A speeder holds this height for as long as it is switched on. A
		starship only uses it twice -- once when it is set down on a pad and
		once as the floor it will not sink through -- which is why the field
		is shared instead of a starship growing a `gearHeight` that means the
		same thing and can disagree with it.
	]]
	hoverHeight: number,
	bank: number, -- degrees of roll into a full-lock turn; pure showmanship
	--[[
		Starships only: multiplier on the fuel bill for a jump.

		The one number that separates two hulls over a whole campaign rather
		than over one flight. A cheap hull is thirsty and an expensive one is
		not, so the upgrade keeps paying after the novelty of the handling
		has worn off.

		Deliberately a multiplier on `Planets.fuelCost` rather than a tank
		with a gauge. A tank that can run dry between worlds is a stranding,
		and Origins.luau already settled that argument for travel: "a
		weakness that can strand you is not a weakness, it is a dead end."
	]]
	fuelMult: number?,

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
-- Starships
--
-- Numbered by tier alongside the speeders rather than restarting at 1, because
-- `tier` is what a vendor stocks by and a shop that carried "tier 1" would have
-- to know which kind of tier 1 it meant. A starship is simply the expensive end
-- of the same ladder: the cheapest one costs more than the best speeder, and
-- the gap is the point at which a player stops walking anywhere ever again.
--------------------------------------------------------------------------------

--[[
	A sublight engine: the same cylinder as `turbine`, glowing at the back.

	Not a flag on `turbine`, because the two differ in more than which end is
	lit -- a repulsorlift intake faces the direction of travel and pulls, a
	thruster faces away from it and pushes, and a helper that did both would
	spend most of its body deciding which one it was.
]]
local function thruster(name: string, at: Vector3, length: number, radius: number, glow: Color3): { ShipPart }
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
			name = name .. "Flame",
			shape = "Cylinder",
			-- Nose is -Z, so the flame hangs off the +Z face.
			size = V3(0.4, radius * 1.7, radius * 1.7),
			offset = at + V3(0, 0, length * 0.5 + 0.15),
			rot = V3(0, 90, 0),
			color = glow,
			material = Enum.Material.Neon,
			light = { color = glow, range = 18, brightness = 2 },
		},
	}
end

--[[
	Three legs and nothing else.

	Every starship needs them and they are the one part of a hull that is
	pure arithmetic: `hoverHeight` is measured to the hull centre, so the
	legs have to reach exactly that far down or the ship rests in the pad.
	Written once so the three hulls cannot disagree about it.
]]
local function gear(drop: number, spread: number, forward: number): { ShipPart }
	local out: { ShipPart } = {}
	local at =
		{ V3(0, -drop * 0.5, -forward), V3(-spread, -drop * 0.5, forward), V3(spread, -drop * 0.5, forward) }
	for index, offset in at do
		table.insert(out, {
			name = `Gear{index}`,
			size = V3(0.7, drop, 0.7),
			offset = offset,
			color = Palette.DarkMetal,
			material = Enum.Material.Metal,
		})
		table.insert(out, {
			name = `Foot{index}`,
			shape = "Cylinder",
			size = V3(0.5, 2.2, 2.2),
			offset = offset + V3(0, -drop * 0.5, 0),
			rot = V3(0, 0, 90),
			color = Palette.WornSteel,
			material = Enum.Material.Metal,
		})
	end
	return out
end

--------------------------------------------------------------------------------
-- Tier 6 -- the first hull of your own
--------------------------------------------------------------------------------

local courierParts: { ShipPart } = {
	{
		name = "Hull",
		size = V3(6, 2.2, 14),
		offset = V3(0, 0, 0),
		color = Palette.HullWhite,
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.05,
	},
	{
		name = "Prow",
		shape = "Wedge",
		size = V3(5, 1.8, 5),
		offset = V3(0, -0.2, -9),
		rot = V3(0, 180, 0),
		color = Palette.HullWhite,
		material = Enum.Material.SmoothPlastic,
	},
	{
		name = "CanopyFrame",
		size = V3(4, 0.5, 5.2),
		offset = V3(0, 1.2, -2.6),
		color = Palette.Gunmetal,
		material = Enum.Material.Metal,
	},
	{
		name = "Canopy",
		size = V3(3.6, 2.6, 4.8),
		offset = V3(0, 2.6, -2.6),
		color = Palette.CockpitGlass,
		material = Enum.Material.Glass,
		transparency = 0.45,
	},
	{
		name = "WingLeft",
		size = V3(5.5, 0.5, 6),
		offset = V3(-5.4, -0.3, 2),
		rot = V3(0, 0, -7),
		color = Palette.HullWhite,
		material = Enum.Material.SmoothPlastic,
	},
	{
		name = "WingRight",
		size = V3(5.5, 0.5, 6),
		offset = V3(5.4, -0.3, 2),
		rot = V3(0, 0, 7),
		color = Palette.HullWhite,
		material = Enum.Material.SmoothPlastic,
	},
	{
		name = "FinLeft",
		size = V3(0.5, 3.4, 3.2),
		offset = V3(-7.6, 1.2, 3.4),
		rot = V3(0, 0, -14),
		color = Palette.CopperTrim,
		material = Enum.Material.Metal,
	},
	{
		name = "FinRight",
		size = V3(0.5, 3.4, 3.2),
		offset = V3(7.6, 1.2, 3.4),
		rot = V3(0, 0, 14),
		color = Palette.CopperTrim,
		material = Enum.Material.Metal,
	},
}
add(courierParts, gear(2.6, 3.4, 5))
add(courierParts, thruster("EngineLeft", V3(-2.2, -0.1, 6.6), 5, 1.1, Palette.BlasterBlue))
add(courierParts, thruster("EngineRight", V3(2.2, -0.1, 6.6), 5, 1.1, Palette.BlasterBlue))

def({
	id = "SkipjackCourier",
	displayName = "Corellian Skipjack",
	description = "A parcel runner with the cargo hold torn out and two seats put in. It is nobody's idea of a warship and it is the first thing you have ever owned that leaves atmosphere.",
	class = "Starship",
	speed = 240,
	acceleration = 90,
	turnSpeed = 105,
	-- `gear(2.6, ...)` reaches 2.85 down once the footpads are counted, so
	-- this is the leg length plus the half stud `validate` insists on. Set
	-- it much higher and the ship rests on nothing, visibly.
	hoverHeight = 3.4,
	bank = 26,
	-- Thirsty. The cheap hull costs you on every jump for the rest of the
	-- campaign, which is the whole reason to want the next one.
	fuelMult = 1.6,
	tier = 6,
	cost = 30000,
	requiredLevel = 16,
	seatSize = V3(1.4, 0.4, 2),
	seatOffset = V3(-0.9, 0.6, -2.4),
	passengerOffsets = { V3(0.9, 0.6, -2.4) },
	parts = courierParts,
})

--------------------------------------------------------------------------------
-- Tier 7 -- the one the whole party fits in
--------------------------------------------------------------------------------

--[[
	Built as a floor with two walls rather than as a solid block.

	The bay behind the cockpit is where the passenger seats are, and a seat
	inside an opaque part is a player who has vanished. An open-topped hold
	costs three parts instead of one and means the people you brought along
	can see out and be seen.
]]
local haulerParts: { ShipPart } = {
	{
		name = "Keel",
		size = V3(12, 1.6, 22),
		offset = V3(0, -1.6, 0),
		color = Palette.ImperialGrey,
		material = Enum.Material.DiamondPlate,
	},
	{
		name = "HoldWallLeft",
		size = V3(1.6, 3.2, 22),
		offset = V3(-5.2, 0.8, 0),
		color = Palette.ImperialGrey,
		material = Enum.Material.Metal,
	},
	{
		name = "HoldWallRight",
		size = V3(1.6, 3.2, 22),
		offset = V3(5.2, 0.8, 0),
		color = Palette.ImperialGrey,
		material = Enum.Material.Metal,
	},
	{
		name = "Foredeck",
		size = V3(12, 1.2, 8),
		offset = V3(0, 2.4, -7),
		color = Palette.ImperialGrey,
		material = Enum.Material.Metal,
	},
	{
		name = "Prow",
		shape = "Wedge",
		size = V3(10, 3.2, 5),
		offset = V3(0, -0.8, -13.5),
		rot = V3(0, 180, 0),
		color = Palette.ImperialGrey,
		material = Enum.Material.DiamondPlate,
	},
	-- Offset to port, which is the one silhouette cue that says "freighter"
	-- from a distance without a single decal.
	{
		name = "Cockpit",
		size = V3(5, 2.6, 5.4),
		offset = V3(-3.4, 4.2, -8),
		color = Palette.WornSteel,
		material = Enum.Material.Metal,
	},
	{
		name = "Viewport",
		size = V3(5.2, 1.6, 3),
		offset = V3(-3.4, 4.4, -9.8),
		color = Palette.CockpitGlass,
		material = Enum.Material.Glass,
		transparency = 0.4,
	},
	{
		name = "MandibleLeft",
		size = V3(2, 2.4, 9),
		offset = V3(-6.4, -0.4, -12),
		color = Palette.ImperialGrey,
		material = Enum.Material.Metal,
	},
	{
		name = "MandibleRight",
		size = V3(2, 2.4, 9),
		offset = V3(6.4, -0.4, -12),
		color = Palette.ImperialGrey,
		material = Enum.Material.Metal,
	},
	{
		name = "TurretRing",
		shape = "Cylinder",
		size = V3(1.4, 3.4, 3.4),
		offset = V3(0, 3, 5.4),
		rot = V3(0, 0, 90),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	{
		name = "SensorDish",
		shape = "Cylinder",
		size = V3(0.5, 4, 4),
		offset = V3(3.4, 3.6, -2),
		rot = V3(0, 0, 74),
		color = Palette.WornSteel,
		material = Enum.Material.Metal,
	},
}
add(haulerParts, gear(3.6, 4.6, 8))
add(haulerParts, thruster("EngineLeft", V3(-4, 0.2, 11.4), 6, 1.6, Palette.BlasterBlue))
add(haulerParts, thruster("EngineCentre", V3(0, 0.2, 11.4), 6, 1.6, Palette.BlasterBlue))
add(haulerParts, thruster("EngineRight", V3(4, 0.2, 11.4), 6, 1.6, Palette.BlasterBlue))

def({
	id = "LonghaulFreighter",
	displayName = "Rendili Longhaul",
	description = "Slow, ugly, forty years old and the only hull on the field with room for everyone you know. The previous owner left the hold smelling of something he would not name.",
	class = "Starship",
	speed = 195,
	acceleration = 58,
	turnSpeed = 62,
	hoverHeight = 4.4,
	bank = 12,
	fuelMult = 1,
	tier = 7,
	cost = 85000,
	requiredLevel = 26,
	seatSize = V3(1.6, 0.4, 2),
	seatOffset = V3(-3.4, 3.4, -8.2),
	passengerOffsets = { V3(-2, 0.2, -1), V3(2, 0.2, -1), V3(0, 0.2, 4) },
	parts = haulerParts,
})

--------------------------------------------------------------------------------
-- Tier 8 -- the one that is only fast
--------------------------------------------------------------------------------

local daggerParts: { ShipPart } = {
	{
		name = "Spine",
		size = V3(2.6, 2, 16),
		offset = V3(0, 0, 0),
		color = Palette.ImperialBlack,
		material = Enum.Material.Metal,
		reflectance = 0.06,
	},
	{
		name = "Prow",
		shape = "Wedge",
		size = V3(2.4, 1.6, 6),
		offset = V3(0, -0.2, -11),
		rot = V3(0, 180, 0),
		color = Palette.NabooRoyal,
		material = Enum.Material.Metal,
	},
	{
		name = "WingLeft",
		size = V3(7, 0.5, 5),
		offset = V3(-4.2, -0.2, 1.6),
		rot = V3(0, -18, 0),
		color = Palette.ImperialBlack,
		material = Enum.Material.Metal,
	},
	{
		name = "WingRight",
		size = V3(7, 0.5, 5),
		offset = V3(4.2, -0.2, 1.6),
		rot = V3(0, 18, 0),
		color = Palette.ImperialBlack,
		material = Enum.Material.Metal,
	},
	{
		name = "StrakeLeft",
		size = V3(0.4, 1.8, 4),
		offset = V3(-7.2, 0.6, 2.6),
		rot = V3(0, -18, 0),
		color = Palette.NabooRoyal,
		material = Enum.Material.Metal,
	},
	{
		name = "StrakeRight",
		size = V3(0.4, 1.8, 4),
		offset = V3(7.2, 0.6, 2.6),
		rot = V3(0, 18, 0),
		color = Palette.NabooRoyal,
		material = Enum.Material.Metal,
	},
	{
		name = "Canopy",
		size = V3(2.4, 2.2, 6.4),
		offset = V3(0, 1.6, -2),
		color = Palette.CockpitGlass,
		material = Enum.Material.Glass,
		transparency = 0.35,
	},
	{
		name = "CannonLeft",
		shape = "Cylinder",
		size = V3(7, 0.55, 0.55),
		offset = V3(-6, -0.5, -3),
		rot = V3(0, 90, 0),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	{
		name = "CannonRight",
		shape = "Cylinder",
		size = V3(7, 0.55, 0.55),
		offset = V3(6, -0.5, -3),
		rot = V3(0, 90, 0),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	{
		name = "Tailfin",
		size = V3(0.5, 3.2, 3.6),
		offset = V3(0, 2.4, 6),
		color = Palette.NabooRoyal,
		material = Enum.Material.Metal,
	},
}
add(daggerParts, gear(2.4, 3, 5))
add(daggerParts, thruster("EngineLeft", V3(-1.5, 0, 8.6), 5.4, 1.2, Palette.BlasterRed))
add(daggerParts, thruster("EngineRight", V3(1.5, 0, 8.6), 5.4, 1.2, Palette.BlasterRed))

def({
	id = "DaggerInterceptor",
	displayName = "Czerka Dagger",
	description = "Two seats in tandem behind an engine that was never meant to push this little. Czerka sells them with the cannons deactivated and a form saying you understand that.",
	class = "Starship",
	speed = 340,
	acceleration = 150,
	turnSpeed = 145,
	hoverHeight = 3.2,
	bank = 45,
	-- Half the bill of the courier, forever. The reason this is the last
	-- thing you buy rather than the first thing you skip to.
	fuelMult = 0.55,
	tier = 8,
	cost = 175000,
	requiredLevel = 36,
	seatSize = V3(1.4, 0.4, 2),
	seatOffset = V3(0, 0.6, -3),
	passengerOffsets = { V3(0, 0.6, 0.6) },
	parts = daggerParts,
})

--------------------------------------------------------------------------------
-- Ambient traffic
--------------------------------------------------------------------------------

--[[
	The hulls that fly past, which nobody owns and nobody is flying.

	Scenery, and deliberately not `ShipDef`s. A traffic hull has no price, no
	level gate, no seats and no handling, because none of those questions can
	be asked of it: you cannot buy one, board one, or make one stop. Giving
	it a `ShipDef` anyway would mean five fields of fiction and a permanent
	risk of a `Ships.get` somewhere handing a shopkeeper an airbus.

	What it does share is `ShipPart`, and that is the whole reason these live
	here rather than in the controller that flies them: the geometry
	vocabulary, the palette and the -Z nose convention are all already in
	this file, and a second private part format on the client would be the
	same job done twice and wrong once.

	Part counts are small on purpose -- these exist by the dozen, they are
	never closer than a hundred studs, and at that range a silhouette and a
	light are the entire read. Lights, though, are not optional: Coruscant's
	day is eighteen minutes long, and unlit traffic simply vanishes at dusk.
]]
export type TrafficHull = {
	id: string,
	parts: { ShipPart },
}

--[[
	A running light: Neon, and deliberately without a `light`.

	A PointLight on a player's speeder throws a pool onto the road in front
	of them, which is the point of it. Two hundred studs up and four hundred
	away, the same light illuminates nothing at all and still costs the
	renderer a light -- twenty-six times over. Neon plus the bloom the
	AtmosphereController already runs is the entire read at that range.
]]
local function lamp(name: string, at: Vector3, colour: Color3, size: number?): ShipPart
	local s = size or 0.7
	return {
		name = name,
		shape = "Ball",
		size = V3(s, s, s),
		offset = at,
		color = colour,
		material = Enum.Material.Neon,
	}
end

--- An airbus: the commuter traffic, and most of what is in the air.
local busParts: { ShipPart } = {
	{
		name = "Hull",
		size = V3(3.4, 2.2, 13),
		offset = V3(0, 0, 0),
		color = Palette.HullGrey,
		material = Enum.Material.Metal,
	},
	{
		name = "Nose",
		shape = "Wedge",
		size = V3(3.4, 1.6, 3),
		offset = V3(0, -0.3, -8),
		rot = V3(0, 180, 0),
		color = Palette.HullGrey,
		material = Enum.Material.Metal,
	},
	-- One band down each side rather than windows: at the distance these are
	-- seen from, a lit stripe is a full row of passengers.
	{
		name = "Windows",
		size = V3(3.5, 0.8, 9),
		offset = V3(0, 0.4, -0.5),
		color = Palette.CoruscantLight,
		material = Enum.Material.Neon,
	},
	lamp("TailLamp", V3(0, 0.6, 6.6), Palette.BlasterRed),
	lamp("NoseLamp", V3(0, -0.2, -9.2), Palette.CoruscantLight),
}

--- A freight barge: slow, long, and the thing you look up at.
local bargeParts: { ShipPart } = {
	{
		name = "Hull",
		size = V3(9, 3.4, 30),
		offset = V3(0, 0, 0),
		color = Palette.Gunmetal,
		material = Enum.Material.DiamondPlate,
	},
	{
		name = "Cab",
		size = V3(6, 2.6, 5),
		offset = V3(0, 2.6, -11),
		color = Palette.WornSteel,
		material = Enum.Material.Metal,
	},
	{
		name = "Pane",
		size = V3(5.2, 1.2, 0.4),
		offset = V3(0, 2.8, -13.6),
		color = Palette.CockpitGlass,
		material = Enum.Material.Neon,
	},
	{
		name = "Container",
		size = V3(7.5, 4, 11),
		offset = V3(0, 3.6, 4),
		color = Palette.CopperTrim,
		material = Enum.Material.CorrodedMetal,
	},
	lamp("PortLamp", V3(-4.8, 0, -8), Palette.BlasterRed, 0.9),
	lamp("StarboardLamp", V3(4.8, 0, -8), Palette.BlasterGreen, 0.9),
	lamp("TailLamp", V3(0, 1.4, 15.4), Palette.BlasterRed, 0.9),
}
add(bargeParts, turbine("EngineLeft", V3(-3.4, -1.2, 12), 7, 1.6, Palette.BlasterBlue))
add(bargeParts, turbine("EngineRight", V3(3.4, -1.2, 12), 7, 1.6, Palette.BlasterBlue))

--- A patrol skiff. Republic blue on Coruscant, Hutt muscle on Nar Shaddaa,
--- and the player never gets close enough to ask which.
local patrolParts: { ShipPart } = {
	{
		name = "Hull",
		size = V3(3, 1.4, 11),
		offset = V3(0, 0, 0),
		color = Palette.ImperialGrey,
		material = Enum.Material.Metal,
	},
	{
		name = "Nose",
		shape = "Wedge",
		size = V3(3, 1.2, 4),
		offset = V3(0, 0, -7.5),
		rot = V3(0, 180, 0),
		color = Palette.ImperialGrey,
		material = Enum.Material.Metal,
	},
	{
		name = "Fin",
		size = V3(0.4, 2.4, 3),
		offset = V3(0, 1.6, 4.4),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	},
	lamp("Beacon", V3(0, 1.2, -1), Palette.BlasterBlue, 1.1),
	lamp("TailLamp", V3(0, 0.2, 5.8), Palette.BlasterRed),
}
add(patrolParts, turbine("Engine", V3(0, -0.9, 4.4), 5, 1.1, Palette.BlasterBlue))

local airbus: TrafficHull = { id = "Airbus", parts = busParts }
local barge: TrafficHull = { id = "Barge", parts = bargeParts }
local patrol: TrafficHull = { id = "Patrol", parts = patrolParts }

--[[
	The mix, weighted by repetition rather than by a weight field.

	A lane picks one of these uniformly, so the list is the odds: four
	commuters to one barge to one patrol. A weight field would be a second
	number to keep in step with a table anyone can already count, and a sky
	that is one-third freight is a sky nobody commutes in.
]]
Ships.TRAFFIC = { airbus, airbus, airbus, airbus, barge, patrol }

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
-- Not "SPEEDER". The same key calls in whichever hull you have selected, and
-- a legend that says SPEEDER to somebody flying a freighter is a legend that
-- has to be re-read every time it is wrong.
Ships.SUMMON_HINT = "VEHICLE"

--- The two values of `ShipDef.class`, so no caller has to spell them.
Ships.SPEEDER = "Speeder"
Ships.STARSHIP = "Starship"

--[[
	The CollectionService tag on every landing pad `PlanetBuilder` draws.

	A tag rather than a registry because the pads are built and the built
	world is already the record of where they are -- a second list kept
	alongside it could only ever be the same facts, later and wrong. And a
	tag rather than a name search because `Workspace:GetDescendants()` on a
	planet is tens of thousands of parts to answer a question asked on a
	keypress.

	Declared here rather than in PlanetBuilder because a shared name that
	only one side can see is how the two sides come to disagree about it.
]]
Ships.PAD_TAG = "LandingPad"

--[[
	How near a pad you must be to call a starship down onto it.

	`buildSpaceport` draws pads 68 studs across, so this is comfortably
	"standing on one" without demanding you find its exact centre.
]]
Ships.PAD_RANGE = 60

--[[
	Height above the ground at which a starship is out of the world.

	Crossing it opens the star map, which is the only thing that happens: the
	fare, the ownership check and the jump all still belong to the server.
	High enough that you cannot brush it flying over a Coruscant spire, low
	enough to reach in a few seconds of climbing.
]]
Ships.CEILING = 900

--- How far a starship's nose may be lifted or dropped, in degrees.
--- Past about here the horizon leaves the screen and the player is flying
--- a shape they can no longer see the front of.
Ships.MAX_PITCH = 60

--[[
	Climb and dive. The one axis a `VehicleSeat` does not give you.

	`Throttle` and `Steer` are the only two the seat reports, which is enough
	for something that stays on the ground and one short of something that
	does not. The obvious third axis is the camera's elevation -- point where
	you want to go -- and it was rejected: Roblox's default camera only turns
	with the mouse while the right button is held, so a player who does not
	know that flies dead level forever, never finds the ceiling, and reports
	that flight is broken. This project has already shipped that bug twice
	under a different name (2026-08-17: "finished but unreachable is not
	finished").

	Two keys are cruder and cannot fail to be found, which here is worth more
	than elegance. Space is free the moment you sit down -- there is nothing
	to jump off -- and LeftControl is not bound to anything.
]]
Ships.PITCH_UP_KEY = Enum.KeyCode.Space
Ships.PITCH_DOWN_KEY = Enum.KeyCode.LeftControl

function Ships.get(id: string): ShipDef
	local d = defs[id]
	assert(d, `Ships.get: unknown ship "{id}"`)
	return d
end

function Ships.exists(id: string): boolean
	return defs[id] ~= nil
end

--- True if `id` is a hull that leaves the ground. Unknown ids are not,
--- so a caller holding a bad id gets the ordinary path and its refusal
--- rather than the pad check and a message about spaceports.
function Ships.isStarship(id: string): boolean
	local d = defs[id]
	return d ~= nil and d.class == Ships.STARSHIP
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
			`class` and `fuelMult` have to agree, in both directions.

			A starship without a fuel multiplier flies perfectly and is
			billed as though it were the middle of the range, which is not
			an error anywhere and is wrong on every jump. A speeder *with*
			one has had a number typed into it that nothing will ever read,
			which is the same lie told the other way round: somebody chose
			it, and the tooltip would not be showing it.
		]]
		if d.class ~= Ships.SPEEDER and d.class ~= Ships.STARSHIP then
			table.insert(problems, `Ships: "{id}" has unknown class "{d.class}"`)
		elseif d.class == Ships.STARSHIP then
			if not d.fuelMult or d.fuelMult <= 0 then
				table.insert(problems, `Ships: starship "{id}" needs a positive fuelMult`)
			end
		elseif d.fuelMult then
			table.insert(problems, `Ships: speeder "{id}" has a fuelMult, which only starships burn`)
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

	-- Traffic gets one check and it is the one that matters: an empty part
	-- list flies a perfectly correct nothing down the lane, and the only
	-- symptom is a city that still looks dead.
	if #Ships.TRAFFIC == 0 then
		table.insert(problems, "Ships: TRAFFIC is empty, so no world can have a sky")
	end
	for _, hull in Ships.TRAFFIC do
		if #hull.parts == 0 then
			table.insert(problems, `Ships: traffic hull "{hull.id}" has no parts and would be invisible`)
		end
	end

	table.sort(problems)
	return problems
end

return Ships
