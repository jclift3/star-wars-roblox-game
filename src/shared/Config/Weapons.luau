--!strict
--[[
	Weapons.luau

	Every blaster, lightsaber and melee weapon in the game: its stats AND the
	part list that builds its model.

	Two things worth knowing before editing this file:

	1. Geometry here uses ABSOLUTE studs, unlike the cosmetics in Costumes.luau
	   which are sized relative to the limb they sit on. A DL-44 is the same
	   physical size in a Wookiee's hand as in a Jawa's, so relative sizing
	   would be wrong. `WeaponPart` is therefore its own type rather than a
	   reuse of `Types.CosmeticPart` -- overloading `offset` to mean stud in one
	   file and fraction in another is exactly the kind of quiet inconsistency
	   that produces weapons floating a foot from the hand.

	2. The grip sits at the origin. The barrel points down -Z (the direction a
	   Roblox character faces), the magazine hangs toward -Y. Muzzle position is
	   declared explicitly rather than inferred, because bolts must originate at
	   the barrel tip and eyeballing that from the part list gets it wrong.
]]

local Palette = require(script.Parent.Palette)

local Weapons = {}

export type WeaponPart = {
	name: string,
	shape: string?, -- "Block" | "Cylinder" | "Ball" | "Wedge"
	size: Vector3,
	offset: Vector3, -- studs, relative to the grip
	rot: Vector3?, -- euler degrees
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	light: { color: Color3, range: number, brightness: number }?,
}

--[[
	A weapon whose geometry was modelled elsewhere and imported, instead of
	being written as a part list.

	THE PART LIST IS STILL THE DEFAULT AND STILL THE RIGHT ANSWER. Building
	out of `Instance.new` is what lets the inventory panel draw a live
	`ViewportFrame` of the real weapon, lets a crystal recolour whatever is
	emitting, and keeps the game free of asset ids owned by somebody else.
	Nothing about any of that changes.

	This is the exception, and it exists because one of the boys modelled a
	blaster in Blender and no part list would honour that. The `.rbxmx` lives
	at `assets/Weapons/` and `asset` is a child of
	`ReplicatedStorage.Assets.Weapons` by that name.

	IT IS NOT SYNCED, AND CANNOT BE, 2026-08-30
	`assets/` was mounted at `ReplicatedStorage.Assets` in
	`default.project.json` for one day. Rojo built the twenty-six MeshParts
	and then failed to write a single `MeshId`, because that is one of the
	few properties Roblox refuses a plugin -- twenty-six meshes, "26 changes
	failed to apply", and a gun made of blank cubes. The mount is gone. The
	file is inserted into the place by hand, once, and saved with it.

	That is why `buildImported` returns a boolean and this weapon still
	declares a `parts` list: on any machine where the folder was never
	inserted, the fallback is the difference between a scavenged pistol and
	an empty hand.

	WHAT AN IMPORTED MESH COSTS
	A MeshPart's `.rbxmx` stores an `rbxassetid://` per mesh rather than the
	geometry itself, so this weapon renders only while those uploads exist and
	are readable by whoever is running the place -- which means they have to
	have been uploaded by the account that owns the game, not by whichever
	account was open in Studio when the model was made. That is a dependency
	the other eighteen weapons do not have, and it is why this is one optional
	field rather than a second pipeline: if the meshes ever stop loading, the
	`model` line comes out and the weapon is a part list again.

	MEASURED OFF THE MODEL, NOT OFF THE MODEL'S PIVOT, 2026-08-30
	This first shipped as a raw `scale` and a stud `offset` applied to
	`Model:PivotTo`, and the gun came out floating beside the character:
	*"the gun is weirdly positioned. not in his hand."*

	A `Model`'s pivot is not a property of the geometry, it is whatever
	Blender's world origin happened to be. This one is at (4.37, 1.00, 5.08)
	while the geometry occupies X 2.8-6.1, Y 2.1-13.9, Z 7.8-35.2 -- so the
	pivot is a stud below the model and nearly three behind it, and both
	`ScaleTo` (which scales *about* the pivot) and `PivotTo` (which places
	it) were working off a point that is not on the gun. No value of
	`offset` fixes that in general, because the error moves when `scale`
	does.

	So both numbers are now measured against the model's own **bounding
	box**, which is a fact about the geometry:

	- `length` is how long the weapon should be, in studs, along its longest
	  axis. The scale factor is derived. "A heavy pistol is about two and a
	  quarter studs" is a thing you can decide; "Blender was in centimetres,
	  so 0.1" is a thing you can only discover.
	- `grip` is where the hand holds it, as a **fraction of the box** on each
	  axis -- (0.5, 0.3, 0.88) is centred across, low down, near the back.
	  Fractions rather than studs so it survives a re-export at a different
	  size, and so it can be read off a screenshot: the gun is sitting too
	  far forward, so raise Z.

	`rot` is still authored, because nothing derivable says which end of the
	long axis is the muzzle.
]]
export type ModelSource = {
	--- A child of `ReplicatedStorage.Assets.Weapons`, i.e. the file stem.
	asset: string,
	--- End-to-end length in studs. The scale factor is derived from this.
	length: number,
	--- Where the hand holds it, as a fraction of the bounding box per axis.
	grip: Vector3,
	--- Euler degrees. The barrel has to end up pointing down -Z.
	rot: Vector3?,
}

export type WeaponDef = {
	id: string,
	displayName: string,
	class: string, -- "Blaster" | "Saber" | "Melee" | "Thrown"
	description: string,

	-- Combat -----------------------------------------------------------
	damage: number,
	fireRate: number, -- attacks per second
	range: number, -- studs; damage falls off past `falloffStart`
	falloffStart: number?,
	falloffMin: number?, -- damage multiplier at max range
	mode: string?, -- "Semi" | "Auto" | "Burst" | "Charge"
	burstCount: number?,
	chargeTime: number?, -- for Charge mode
	spread: number, -- degrees of cone at the muzzle
	projectileSpeed: number?, -- studs/sec; nil for melee
	magazine: number?, -- nil = no reload (blasters with gas cells)
	reloadTime: number?,
	critMultiplier: number?,
	pierce: number?, -- extra targets a bolt can pass through

	-- Handling ---------------------------------------------------------
	handedness: string, -- "OneHand" | "TwoHand"
	moveSpeedMult: number?, -- while equipped
	aimZoom: number?,

	-- Economy ----------------------------------------------------------
	tier: number, -- 1..5, drives vendor stocking and loot tables
	cost: number,
	requiredLevel: number,
	factions: { string }?, -- vendors that stock it; nil = anyone

	-- Presentation ------------------------------------------------------
	boltColor: Color3?,
	muzzleOffset: Vector3, -- studs from the grip to the barrel tip
	parts: { WeaponPart },
	blade: WeaponPart?, -- sabers only; animated on ignition
	--- Imported geometry instead of `parts`. See `ModelSource`; almost always nil.
	model: ModelSource?,
}

local defs: { [string]: WeaponDef } = {}

local function def(w: WeaponDef): WeaponDef
	defs[w.id] = w
	return w
end

--------------------------------------------------------------------------------
-- Shared part builders
--------------------------------------------------------------------------------

local V3 = Vector3.new

--- The pistol-grip block every hand weapon shares, angled back like a real grip.
local function grip(color: Color3?): WeaponPart
	return {
		name = "Grip",
		size = V3(0.28, 0.85, 0.42),
		offset = V3(0, -0.3, 0.1),
		rot = V3(-12, 0, 0),
		color = color or Palette.DarkMetal,
		material = Enum.Material.Metal,
	}
end

local function receiver(length: number, color: Color3?): WeaponPart
	return {
		name = "Receiver",
		size = V3(0.34, 0.42, length),
		offset = V3(0, 0.16, -length * 0.5 + 0.3),
		color = color or Palette.Gunmetal,
		material = Enum.Material.Metal,
	}
end

local function barrel(length: number, radius: number, z: number, color: Color3?): WeaponPart
	return {
		name = "Barrel",
		shape = "Cylinder",
		size = V3(length, radius * 2, radius * 2),
		offset = V3(0, 0.16, z),
		-- Cylinders extend along X, so yaw 90 degrees to point down -Z.
		rot = V3(0, 90, 0),
		color = color or Palette.DarkMetal,
		material = Enum.Material.Metal,
	}
end

local function scope(z: number, len: number): WeaponPart
	return {
		name = "Scope",
		shape = "Cylinder",
		size = V3(len, 0.22, 0.22),
		offset = V3(0, 0.46, z),
		rot = V3(0, 90, 0),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	}
end

local function stock(z: number): WeaponPart
	return {
		name = "Stock",
		size = V3(0.24, 0.38, 1.0),
		offset = V3(0, 0.1, z),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	}
end

--- Sight rail / iron sights, the small detail that stops a gun reading as a box.
local function sight(z: number): WeaponPart
	return {
		name = "Sight",
		size = V3(0.1, 0.16, 0.3),
		offset = V3(0, 0.42, z),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	}
end

local function powerCell(z: number, color: Color3): WeaponPart
	return {
		name = "PowerCell",
		size = V3(0.2, 0.16, 0.34),
		offset = V3(0, -0.05, z),
		color = color,
		material = Enum.Material.Neon,
		light = { color = color, range = 5, brightness = 0.8 },
	}
end

--------------------------------------------------------------------------------
-- Blasters
--------------------------------------------------------------------------------

def({
	id = "E11",
	displayName = "E-11 Blaster Rifle",
	class = "Blaster",
	description = "Imperial standard issue. Compact, reliable, and famously inaccurate in the hands of a stormtrooper.",
	damage = 12,
	fireRate = 4,
	range = 260,
	falloffStart = 140,
	falloffMin = 0.55,
	mode = "Auto",
	spread = 2.4,
	projectileSpeed = 420,
	magazine = 30,
	reloadTime = 1.9,
	critMultiplier = 1.8,
	handedness = "TwoHand",
	moveSpeedMult = 0.96,
	tier = 1,
	cost = 900,
	requiredLevel = 1,
	factions = { "Empire" },
	boltColor = Palette.BlasterRed,
	muzzleOffset = V3(0, 0.16, -2.5),
	parts = {
		grip(),
		receiver(1.9, Palette.Gunmetal),
		barrel(1.5, 0.11, -1.85),
		sight(-1.0),
		scope(-0.55, 0.7),
		stock(0.95),
		{
			name = "Magazine",
			size = V3(0.2, 0.6, 0.3),
			offset = V3(0, -0.24, -0.5),
			rot = V3(10, 0, 0),
			color = Palette.DarkMetal,
			material = Enum.Material.Metal,
		},
		{
			name = "Foregrip",
			size = V3(0.16, 0.34, 0.22),
			offset = V3(0, -0.14, -1.35),
			color = Palette.ImperialBlack,
			material = Enum.Material.Metal,
		},
	},
})

def({
	id = "DH17",
	displayName = "DH-17 Blaster Pistol",
	class = "Blaster",
	description = "Republic sidearm. Short range, but it cycles fast enough to matter in a corridor.",
	damage = 10,
	fireRate = 5,
	range = 170,
	falloffStart = 80,
	falloffMin = 0.5,
	mode = "Semi",
	spread = 1.8,
	projectileSpeed = 400,
	magazine = 20,
	reloadTime = 1.5,
	critMultiplier = 1.8,
	handedness = "OneHand",
	tier = 1,
	cost = 550,
	requiredLevel = 1,
	factions = { "Republic", "Independent" },
	boltColor = Palette.BlasterBlue,
	muzzleOffset = V3(0, 0.16, -1.5),
	parts = {
		grip(),
		receiver(1.1, Palette.WornSteel),
		barrel(0.9, 0.09, -1.1),
		sight(-0.7),
		powerCell(0.35, Palette.BlasterBlue),
	},
})

def({
	id = "DL44",
	displayName = "DL-44 Heavy Blaster",
	class = "Blaster",
	description = "Modified, illegal, and worth every credit. Hits like a rifle from a pistol frame.",
	damage = 26,
	fireRate = 1.9,
	range = 220,
	falloffStart = 110,
	falloffMin = 0.6,
	mode = "Semi",
	spread = 1.2,
	projectileSpeed = 440,
	magazine = 10,
	reloadTime = 1.7,
	critMultiplier = 2.2,
	handedness = "OneHand",
	tier = 3,
	cost = 4200,
	requiredLevel = 8,
	boltColor = Palette.BlasterRed,
	muzzleOffset = V3(0, 0.16, -1.7),
	parts = {
		grip(Palette.SmugglerBrown),
		receiver(1.3, Palette.DarkMetal),
		barrel(1.2, 0.12, -1.25),
		scope(-0.6, 0.75),
		{
			name = "MuzzleShroud",
			shape = "Cylinder",
			size = V3(0.4, 0.3, 0.3),
			offset = V3(0, 0.16, -1.62),
			rot = V3(0, 90, 0),
			color = Palette.Gunmetal,
			material = Enum.Material.Metal,
		},
	},
})

--[[
	THE ONE WEAPON IN THE GAME THAT WAS NOT WRITTEN, 2026-08-29

	Modelled in Blender by one of the boys and imported as twenty-six
	MeshParts; see `ModelSource` for what that costs and why it is allowed
	here and nowhere else yet.

	The part list below is not decoration. `WeaponModel.build` draws it only
	when the imported model cannot be found, so this weapon degrades into an
	ordinary scavenged pistol rather than into an empty hand -- which is the
	failure mode that matters, because the meshes live on somebody's account
	and this file cannot check that they are still there.

	Sold by the Jawas, which is the only vendor it could belong to: it is a
	revolver frame with a suppressor bolted to it and sixteen visible screws,
	and "mostly works" is already their greeting.

	PRICED TO BE OWNED, 2026-08-29
	It first went in at tier 3, level 10 and 3,100 credits -- the reasoning
	being that the best thing on a scavenger's cart should be a reason to walk
	out to the Wastes. That reasoning was about the shelf and not about the
	gun. This is the one weapon in the game somebody in this house made, and a
	gate that means it is not in your hand for the first several hours is the
	wrong gate whatever it does for the curve. Tier 2, level 5, 1,400.

	Tier moved with the level rather than staying at 3, because the panel
	sorts the shelf by tier and prints it on the row: a tier-3 badge on a
	level-5 weapon is both a lie and the reason it was sitting below the fold
	where nobody found it.
]]
def({
	id = "NN14",
	displayName = "NN-14 Scavenger's Blaster",
	class = "Blaster",
	description = "Somebody built this out of three other guns and it shoots straighter than any of them did.",
	--[[
		Left where it was when the level came down, and that is a real
		decision rather than an oversight: at 19 this outguns the SE-14C
		(11, and 700 credits dearer) so completely that the Jawa's other
		pistol stops having a reason to exist, and the DL-44 at level 8 is a
		smaller step up than it used to be.

		Worth it. The alternative is a gun that is exciting to own and
		disappointing to fire, and "the thing I built is actually good" is
		the entire point of it being in here. If it flattens the first hour
		in a play test, this number is the knob -- 14 restores the curve and
		still beats the SE-14C.
	]]
	damage = 19,
	fireRate = 2.1,
	range = 180,
	falloffStart = 90,
	falloffMin = 0.55,
	mode = "Semi",
	spread = 1.6,
	projectileSpeed = 400,
	magazine = 8,
	reloadTime = 1.9,
	critMultiplier = 2.0,
	handedness = "OneHand",
	tier = 2,
	cost = 1400,
	requiredLevel = 5,
	boltColor = Palette.BlasterRed,
	muzzleOffset = V3(0, 0.18, -1.6),
	--[[
		Two and a quarter studs end to end, which is a heavy pistol in a
		character's hand. The raw export is 27.4 studs on its longest axis;
		Blender was working in something other than studs, as it always is.

		No `rot`, and that is measured rather than hoped for. Reading the
		twenty-six part extents out of the `.rbxmx`: the suppressor occupies
		Z 7.8-17.2 and the grip screws Z 32.9-34.3 at the lowest Y in the
		model, so the muzzle is already at -Z and +Y is already up. This
		export happens to arrive in Roblox's own convention.

		`grip` puts the hand on the grip rather than at Blender's origin --
		centred across the frame, low on the butt, near the back.
	]]
	model = {
		asset = "reysblaster",
		length = 2.25,
		grip = V3(0.5, 0.3, 0.88),
	},
	parts = {
		grip(Palette.SmugglerBrown),
		receiver(1.15, Palette.WornSteel),
		barrel(1.0, 0.11, -1.15),
	},
})

def({
	id = "SE14C",
	displayName = "SE-14C Blaster",
	class = "Blaster",
	description = "Imperial officer's sidearm. Fires in tight bursts and looks expensive doing it.",
	damage = 11,
	fireRate = 2.4,
	range = 190,
	falloffStart = 95,
	falloffMin = 0.55,
	mode = "Burst",
	burstCount = 3,
	spread = 2.0,
	projectileSpeed = 410,
	magazine = 21,
	reloadTime = 1.6,
	critMultiplier = 1.9,
	handedness = "OneHand",
	tier = 2,
	cost = 2100,
	requiredLevel = 5,
	factions = { "Empire" },
	boltColor = Palette.BlasterRed,
	muzzleOffset = V3(0, 0.16, -1.6),
	parts = {
		grip(),
		receiver(1.2, Palette.Gunmetal),
		barrel(1.1, 0.09, -1.2),
		sight(-0.75),
		{
			name = "CoolingVane",
			size = V3(0.3, 0.1, 0.7),
			offset = V3(0, 0.4, -0.9),
			color = Palette.DarkMetal,
			material = Enum.Material.DiamondPlate,
		},
	},
})

def({
	id = "DC15A",
	displayName = "DC-15A Service Rifle",
	class = "Blaster",
	description = "Pre-treaty hardware. Heavy, accurate, and still deadly a war after the one it was built for.",
	damage = 16,
	fireRate = 3.2,
	range = 320,
	falloffStart = 190,
	falloffMin = 0.65,
	mode = "Auto",
	spread = 1.6,
	projectileSpeed = 480,
	magazine = 40,
	reloadTime = 2.2,
	critMultiplier = 1.9,
	handedness = "TwoHand",
	moveSpeedMult = 0.93,
	tier = 3,
	cost = 5200,
	requiredLevel = 12,
	factions = { "Jedi", "Republic" },
	boltColor = Palette.BlasterBlue,
	muzzleOffset = V3(0, 0.16, -3.2),
	parts = {
		grip(),
		receiver(2.2, Palette.HullWhite),
		barrel(2.2, 0.1, -2.3),
		scope(-0.7, 0.9),
		stock(1.1),
		{
			name = "BarrelShroud",
			shape = "Cylinder",
			size = V3(1.0, 0.34, 0.34),
			offset = V3(0, 0.16, -1.7),
			rot = V3(0, 90, 0),
			color = Palette.HullWhite,
			material = Enum.Material.Metal,
		},
	},
})

def({
	id = "T21",
	displayName = "T-21 Light Repeater",
	class = "Blaster",
	description = "Imperial heavy weapon. Slow, loud, and it does not care what you are standing behind.",
	damage = 38,
	fireRate = 1.1,
	range = 300,
	falloffStart = 170,
	falloffMin = 0.7,
	mode = "Semi",
	spread = 1.0,
	projectileSpeed = 520,
	magazine = 8,
	reloadTime = 2.8,
	critMultiplier = 2.0,
	pierce = 1,
	handedness = "TwoHand",
	moveSpeedMult = 0.88,
	tier = 4,
	cost = 8500,
	requiredLevel = 18,
	factions = { "Empire" },
	boltColor = Palette.BlasterRed,
	muzzleOffset = V3(0, 0.16, -3.6),
	parts = {
		grip(),
		receiver(2.4, Palette.Gunmetal),
		barrel(2.6, 0.16, -2.6),
		stock(1.2),
		scope(-0.6, 1.0),
		{
			name = "HeatSink",
			shape = "Cylinder",
			size = V3(0.9, 0.44, 0.44),
			offset = V3(0, 0.16, -1.5),
			rot = V3(0, 90, 0),
			color = Palette.DarkMetal,
			material = Enum.Material.DiamondPlate,
		},
		{
			name = "Bipod",
			size = V3(0.5, 0.1, 0.1),
			offset = V3(0, -0.15, -2.6),
			color = Palette.DarkMetal,
			material = Enum.Material.Metal,
		},
	},
})

def({
	id = "DLT20A",
	displayName = "DLT-20A Longblaster",
	class = "Blaster",
	description = "A marksman's weapon. One clean shot, then find new cover.",
	damage = 62,
	fireRate = 0.75,
	range = 600,
	falloffStart = 500,
	falloffMin = 0.85,
	mode = "Semi",
	spread = 0.15,
	projectileSpeed = 750,
	magazine = 6,
	reloadTime = 2.6,
	critMultiplier = 2.6,
	handedness = "TwoHand",
	moveSpeedMult = 0.9,
	aimZoom = 2.5,
	tier = 4,
	cost = 9800,
	requiredLevel = 20,
	boltColor = Palette.BlasterRed,
	muzzleOffset = V3(0, 0.16, -4.0),
	parts = {
		grip(),
		receiver(2.6, Palette.Gunmetal),
		barrel(3.2, 0.09, -2.9),
		stock(1.3),
		scope(-0.8, 1.4),
		{
			name = "ScopeLens",
			shape = "Cylinder",
			size = V3(0.08, 0.24, 0.24),
			offset = V3(0, 0.46, -1.5),
			rot = V3(0, 90, 0),
			color = Palette.BlasterBlue,
			material = Enum.Material.Neon,
		},
	},
})

def({
	id = "Bowcaster",
	displayName = "Wookiee Bowcaster",
	class = "Blaster",
	description = "Hand-built, hand-cocked, and devastating. Charge it fully or do not bother.",
	damage = 48,
	fireRate = 0.7,
	range = 280,
	falloffStart = 150,
	falloffMin = 0.6,
	mode = "Charge",
	chargeTime = 1.1,
	spread = 1.4,
	projectileSpeed = 380,
	magazine = 5,
	reloadTime = 3.0,
	critMultiplier = 2.1,
	pierce = 2,
	handedness = "TwoHand",
	moveSpeedMult = 0.9,
	tier = 4,
	cost = 11000,
	requiredLevel = 22,
	boltColor = Palette.BlasterGreen,
	muzzleOffset = V3(0, 0.16, -2.2),
	parts = {
		grip(Palette.WookieeBrown),
		receiver(1.6, Palette.SmugglerBrown),
		barrel(1.4, 0.13, -1.6),
		{
			name = "LimbLeft",
			size = V3(0.14, 1.9, 0.3),
			offset = V3(-0.5, 0.3, -1.1),
			rot = V3(0, 0, 28),
			color = Palette.CopperTrim,
			material = Enum.Material.Metal,
		},
		{
			name = "LimbRight",
			size = V3(0.14, 1.9, 0.3),
			offset = V3(0.5, 0.3, -1.1),
			rot = V3(0, 0, -28),
			color = Palette.CopperTrim,
			material = Enum.Material.Metal,
		},
		{
			name = "Quarrel",
			shape = "Cylinder",
			size = V3(0.7, 0.14, 0.14),
			offset = V3(0, 0.42, -1.2),
			rot = V3(0, 90, 0),
			color = Palette.BlasterGreen,
			material = Enum.Material.Neon,
			light = { color = Palette.BlasterGreen, range = 7, brightness = 1.2 },
		},
	},
})

def({
	id = "E5",
	displayName = "E-5 Droid Blaster",
	class = "Blaster",
	description = "Mass-produced for hands that never flinch and never aim well either.",
	damage = 9,
	fireRate = 3.0,
	range = 200,
	falloffStart = 100,
	falloffMin = 0.5,
	mode = "Auto",
	spread = 3.6,
	projectileSpeed = 380,
	magazine = 25,
	reloadTime = 2.0,
	critMultiplier = 1.5,
	handedness = "TwoHand",
	tier = 1,
	cost = 400,
	requiredLevel = 1,
	boltColor = Palette.BlasterRed,
	muzzleOffset = V3(0, 0.16, -2.2),
	parts = {
		grip(Palette.BattleDroidTan),
		receiver(1.7, Palette.BattleDroidTan),
		barrel(1.3, 0.09, -1.7),
		{
			name = "Magazine",
			size = V3(0.16, 0.55, 0.26),
			offset = V3(0, -0.22, -0.4),
			color = Palette.DroidRust,
			material = Enum.Material.Metal,
		},
	},
})

def({
	id = "DisruptorPistol",
	displayName = "Dis-2 Disruptor",
	class = "Blaster",
	description = "Outlawed in most systems. Ignores armour entirely -- which is rather the point.",
	damage = 40,
	fireRate = 1.4,
	range = 150,
	falloffStart = 70,
	falloffMin = 0.4,
	mode = "Semi",
	spread = 2.0,
	projectileSpeed = 300,
	magazine = 6,
	reloadTime = 2.4,
	critMultiplier = 2.4,
	handedness = "OneHand",
	tier = 5,
	cost = 16000,
	requiredLevel = 28,
	factions = { "Hutt" },
	boltColor = Palette.SaberPurple,
	muzzleOffset = V3(0, 0.16, -1.6),
	parts = {
		grip(Palette.SithBlack),
		receiver(1.2, Palette.DarkMetal),
		barrel(1.1, 0.14, -1.2),
		powerCell(0.35, Palette.SaberPurple),
		{
			name = "Emitter",
			shape = "Cylinder",
			size = V3(0.16, 0.34, 0.34),
			offset = V3(0, 0.16, -1.68),
			rot = V3(0, 90, 0),
			color = Palette.SaberPurple,
			material = Enum.Material.Neon,
			light = { color = Palette.SaberPurple, range = 8, brightness = 1.5 },
		},
	},
})

--------------------------------------------------------------------------------
-- Lightsabers
--------------------------------------------------------------------------------

--[[
	Saber hilts share a silhouette (emitter, grip, pommel) and differ by trim.
	The blade is declared separately so the combat system can scale it from zero
	on ignition -- storing it in `parts` would build every saber pre-lit.
]]
local function hilt(length: number, trim: Color3, body: Color3?): { WeaponPart }
	local bodyColor = body or Palette.WornSteel
	return {
		{
			name = "Hilt",
			shape = "Cylinder",
			size = V3(length, 0.32, 0.32),
			offset = V3(0, 0, 0),
			rot = V3(0, 90, 0),
			color = bodyColor,
			material = Enum.Material.Metal,
			reflectance = 0.15,
		},
		{
			name = "Emitter",
			shape = "Cylinder",
			size = V3(0.22, 0.36, 0.36),
			offset = V3(0, 0, -length * 0.5 - 0.08),
			rot = V3(0, 90, 0),
			color = trim,
			material = Enum.Material.Metal,
			reflectance = 0.2,
		},
		{
			name = "Pommel",
			shape = "Cylinder",
			size = V3(0.16, 0.3, 0.3),
			offset = V3(0, 0, length * 0.5 + 0.06),
			rot = V3(0, 90, 0),
			color = trim,
			material = Enum.Material.Metal,
		},
		{
			name = "Ridge",
			size = V3(0.36, 0.1, 0.5),
			offset = V3(0, 0, 0.1),
			color = trim,
			material = Enum.Material.Metal,
		},
		{
			name = "Switch",
			size = V3(0.12, 0.12, 0.18),
			offset = V3(0, 0.18, -0.3),
			color = Palette.SaberRed,
			material = Enum.Material.Neon,
		},
	}
end

--[[
	HOW LONG A LIGHTSABER IS

	Reported from play, 2026-08-17: *"I have this ridiculously long
	lightsaber."* It was 8.5 studs. An R15 character is about 5.7 studs tall,
	so the blade was half as long again as the person holding it -- a pike,
	not a sword, and it read as one in every screenshot.

	The films put a standard blade at roughly a metre, against a person of
	about 1.8, so `DEFAULT_BLADE` is that same fraction of a rig: a hair under
	three quarters of the character's height. Every other blade in the file is
	scaled off it rather than re-guessed, so this one number moves them all.

	The *reach* of a swing is `WeaponDef.range` and is set alongside these --
	see the note there. Shortening the blade without shortening the reach
	would only have moved the lie: enemies dying three studs past the tip.
]]
local DEFAULT_BLADE = 4.2

local function blade(bladeColor: Color3, length: number, thickness: number?): WeaponPart
	local t = thickness or 0.34
	return {
		name = "Blade",
		shape = "Cylinder",
		size = V3(length, t, t),
		offset = V3(0, 0, -length * 0.5 - 0.6),
		rot = V3(0, 90, 0),
		color = bladeColor,
		material = Enum.Material.Neon,
		light = { color = bladeColor, range = 18, brightness = 2.4 },
	}
end

local function saber(
	id: string,
	displayName: string,
	description: string,
	bladeColor: Color3,
	trim: Color3,
	stats: {
		damage: number,
		fireRate: number,
		tier: number,
		cost: number,
		requiredLevel: number,
		bladeLength: number?,
		factions: { string }?,
		handedness: string?,
		critMultiplier: number?,
	}
): WeaponDef
	return def({
		id = id,
		displayName = displayName,
		class = "Saber",
		description = description,
		damage = stats.damage,
		fireRate = stats.fireRate,
		-- Reach, not projectile range: the arc the swing hitbox sweeps.
		-- `swingMelee` sweeps a sphere of `range * 0.7` centred `range * 0.4`
		-- ahead of the root, so this is about 1.4 times the distance a hit can
		-- land. Hand to blade tip is roughly 5 studs and the hand leads the
		-- root by about 1, so 7 puts the edge of the hitbox where the edge of
		-- the blade is, give or take the target's own width.
		range = 7,
		spread = 0,
		critMultiplier = stats.critMultiplier or 2.5,
		handedness = stats.handedness or "TwoHand",
		moveSpeedMult = 1.02,
		tier = stats.tier,
		cost = stats.cost,
		requiredLevel = stats.requiredLevel,
		factions = stats.factions,
		boltColor = bladeColor,
		muzzleOffset = V3(0, 0, -1.2),
		parts = hilt(1.35, trim),
		blade = blade(bladeColor, stats.bladeLength or DEFAULT_BLADE),
	})
end

--[[
	HOW HARD A LIGHTSABER HITS -- raised across the board, 2026-08-29

	Reported from play: *"lightsaber needs to be more deadly."* Doing the
	arithmetic first, because "it feels weak" and "it is weak" are different
	complaints with different fixes, and the numbers said it was the second
	one.

	Damage times fire rate put the blue sabre at 63 a second against the
	DL-44's 49 and the DC-15A's 51 -- a 25% edge, for a weapon that can only
	be used from seven studs away. That is the whole problem in one figure.
	The blaster kites; the sabre has to cross the room while being shot, and
	then stand still inside a firing line for as long as the kill takes.
	Twenty-five per cent does not buy that. It is not a premium, it is a
	rounding error.

	What it bought in practice: a level-20 Sand Raider carries 260 health, so
	the blue sabre needed **seven swings**, just under five seconds of standing
	in the open. Seven swings is not a lightsaber, it is a bat. Roughly 1.75x
	across every blade puts that at four, and four is what the word "deadly"
	is describing.

	The ordering between the blades is untouched -- green quicker and lighter,
	red heaviest, shoto weakest per swing -- because none of that was wrong.
	Only the scale was.

	IF THIS OVERSHOOTS, THIS COMMENT IS THE KNOB. Halve the increase, not the
	fire rates: rate is what makes each blade feel different from the others,
	and it is the one thing here that has already been tuned against play.

	Deliberately NOT raised with them: `Gaderffii`, `VibroBlade` and
	`ElectroStaff`. They pay the same closing cost and have the same case, and
	the honest answer is that they probably need it too -- but nobody has
	reported it, a gaffi stick beating a DL-44 is a claim about the setting as
	much as the maths, and a lightsaber ought to be *the* reason to walk into
	arm's reach. One change, one report, one thing to watch in the next test.
]]
saber(
	"SaberBlue",
	"Lightsaber (Blue)",
	"A Guardian's blade. Balanced, honest, and it deflects blaster bolts if you have the training.",
	Palette.SaberBlue,
	Palette.WornSteel,
	{
		damage = 74,
		fireRate = 1.5,
		tier = 3,
		cost = 7500,
		requiredLevel = 10,
		factions = { "Jedi", "Republic" },
	}
)

saber(
	"SaberGreen",
	"Lightsaber (Green)",
	"A Consular's blade. Slightly faster in the hand, favoured by those who talk first.",
	Palette.SaberGreen,
	Palette.CopperTrim,
	{ damage = 66, fireRate = 1.75, tier = 3, cost = 7500, requiredLevel = 10, factions = { "Jedi" } }
)

saber(
	"SaberPurple",
	"Lightsaber (Purple)",
	"Neither side of the line. A rare crystal for a rarer temperament.",
	Palette.SaberPurple,
	Palette.DarkMetal,
	{ damage = 82, fireRate = 1.5, tier = 4, cost = 14000, requiredLevel = 24 }
)

saber(
	"SaberRed",
	"Sith Lightsaber",
	"A bled crystal screams inside the blade. It hits harder because it is meant to.",
	Palette.SaberRed,
	Palette.SithBlack,
	{ damage = 92, fireRate = 1.4, tier = 4, cost = 15000, requiredLevel = 24, factions = { "Empire" } }
)

saber(
	"SaberShoto",
	"Shoto Lightsaber",
	"A short blade for the off hand. Quick, but you give up reach for it.",
	Palette.SaberYellow,
	Palette.DroidGold,
	{
		damage = 44,
		fireRate = 2.4,
		tier = 3,
		cost = 6000,
		requiredLevel = 14,
		-- Two thirds of a standard blade. The description says you give up
		-- reach for the speed, and this is where that is actually true.
		bladeLength = DEFAULT_BLADE * 0.65,
		handedness = "OneHand",
	}
)

def({
	id = "SaberDoubleRed",
	displayName = "Double-Bladed Lightsaber",
	class = "Saber",
	description = "Twice the blade, twice the ways to lose a hand. Sith discipline required.",
	-- Raised by less than the other five (1.55x rather than 1.75x). It was
	-- already the highest damage-per-second in the game before this pass, on
	-- the longest reach, so the full multiplier would have made every other
	-- blade a stepping stone to it rather than a choice. Level 34 and 26,000
	-- credits is late enough that it should be the best; it should not be the
	-- only one.
	damage = 68,
	fireRate = 2.0,
	-- Two studs longer than a single blade's reach, because it is swung from
	-- the middle of a hilt twice as long. Same arithmetic as `saber`'s note.
	range = 9,
	spread = 0,
	critMultiplier = 2.4,
	handedness = "TwoHand",
	moveSpeedMult = 1.02,
	tier = 5,
	cost = 26000,
	requiredLevel = 34,
	factions = { "Empire" },
	boltColor = Palette.SaberRed,
	muzzleOffset = V3(0, 0, -1.2),
	parts = hilt(2.6, Palette.SithBlack, Palette.DarkMetal),
	blade = blade(Palette.SaberRed, DEFAULT_BLADE),
	-- The second blade is mirrored by the saber system from `blade`, so it
	-- inherits colour and length automatically.
})

--------------------------------------------------------------------------------
-- Melee
--------------------------------------------------------------------------------

def({
	id = "Gaderffii",
	displayName = "Gaderffii Stick",
	class = "Melee",
	description = "Tusken gaffi stick. Scrap metal, bone and spite, and it will still ruin your day.",
	damage = 28,
	fireRate = 1.2,
	range = 8,
	spread = 0,
	critMultiplier = 2.0,
	handedness = "TwoHand",
	tier = 2,
	cost = 1200,
	requiredLevel = 4,
	muzzleOffset = V3(0, 0, -2.5),
	parts = {
		{
			name = "Shaft",
			shape = "Cylinder",
			size = V3(4.5, 0.22, 0.22),
			offset = V3(0, 0, -1.4),
			rot = V3(0, 90, 0),
			color = Palette.SmugglerBrown,
			material = Enum.Material.Wood,
		},
		{
			name = "Head",
			size = V3(0.5, 0.7, 0.3),
			offset = V3(0, 0, -3.4),
			color = Palette.WornSteel,
			material = Enum.Material.CorrodedMetal,
		},
		{
			name = "Spike",
			size = V3(0.16, 0.16, 0.9),
			offset = V3(0, 0, -3.9),
			color = Palette.WornSteel,
			material = Enum.Material.CorrodedMetal,
		},
		{
			name = "Club",
			size = V3(0.44, 0.44, 0.7),
			offset = V3(0, 0, 0.9),
			color = Palette.DarkMetal,
			material = Enum.Material.CorrodedMetal,
		},
	},
})

def({
	id = "VibroBlade",
	displayName = "Vibroblade",
	class = "Melee",
	description = "An ultrasonic edge that cuts armour like cloth. Silent, which is often the point.",
	damage = 24,
	fireRate = 2.2,
	range = 7,
	spread = 0,
	critMultiplier = 2.8,
	handedness = "OneHand",
	moveSpeedMult = 1.04,
	tier = 2,
	cost = 2400,
	requiredLevel = 6,
	muzzleOffset = V3(0, 0, -1.8),
	parts = {
		{
			name = "Handle",
			size = V3(0.22, 0.22, 0.7),
			offset = V3(0, 0, 0.25),
			color = Palette.SithBlack,
			material = Enum.Material.Fabric,
		},
		{
			name = "Guard",
			size = V3(0.6, 0.12, 0.12),
			offset = V3(0, 0, -0.15),
			color = Palette.Gunmetal,
			material = Enum.Material.Metal,
		},
		{
			name = "Blade",
			size = V3(0.06, 0.34, 2.2),
			offset = V3(0, 0, -1.3),
			color = Palette.WornSteel,
			material = Enum.Material.Metal,
			reflectance = 0.35,
		},
	},
})

def({
	id = "ElectroStaff",
	displayName = "Electrostaff",
	class = "Melee",
	description = "Royal Guard issue. Phrik alloy, so a lightsaber will not cut it -- and it knows.",
	damage = 34,
	fireRate = 1.5,
	range = 10,
	spread = 0,
	critMultiplier = 2.2,
	handedness = "TwoHand",
	tier = 4,
	cost = 9000,
	requiredLevel = 20,
	factions = { "Empire" },
	muzzleOffset = V3(0, 0, -3.0),
	parts = {
		{
			name = "Shaft",
			shape = "Cylinder",
			size = V3(6.0, 0.2, 0.2),
			offset = V3(0, 0, -1.6),
			rot = V3(0, 90, 0),
			color = Palette.DarkMetal,
			material = Enum.Material.Metal,
		},
		{
			name = "TipFront",
			shape = "Cylinder",
			size = V3(0.6, 0.3, 0.3),
			offset = V3(0, 0, -4.4),
			rot = V3(0, 90, 0),
			color = Palette.BlasterBlue,
			material = Enum.Material.Neon,
			light = { color = Palette.BlasterBlue, range = 10, brightness = 1.6 },
		},
		{
			name = "TipBack",
			shape = "Cylinder",
			size = V3(0.6, 0.3, 0.3),
			offset = V3(0, 0, 1.2),
			rot = V3(0, 90, 0),
			color = Palette.BlasterBlue,
			material = Enum.Material.Neon,
			light = { color = Palette.BlasterBlue, range = 10, brightness = 1.6 },
		},
	},
})

def({
	id = "Fists",
	displayName = "Bare Hands",
	class = "Melee",
	description = "Better than nothing. Marginally.",
	damage = 8,
	fireRate = 1.8,
	range = 5,
	spread = 0,
	critMultiplier = 1.5,
	handedness = "OneHand",
	tier = 1,
	cost = 0,
	requiredLevel = 1,
	muzzleOffset = V3(0, 0, -1),
	parts = {},
})

--------------------------------------------------------------------------------

Weapons.defs = defs
Weapons.DEFAULT = "Fists"

function Weapons.get(id: string): WeaponDef
	local w = defs[id]
	assert(w, `Weapons.get: unknown weapon "{id}"`)
	return w
end

function Weapons.exists(id: string): boolean
	return defs[id] ~= nil
end

function Weapons.isSaber(id: string): boolean
	local w = defs[id]
	return w ~= nil and w.class == "Saber"
end

function Weapons.isRanged(id: string): boolean
	local w = defs[id]
	return w ~= nil and w.class == "Blaster"
end

--[[
	Damage a hit should do at `distance` studs.

	Blasters keep full damage out to `falloffStart`, then decay linearly to
	`falloffMin` at max range. Past max range they do nothing at all -- the
	combat system should not have spawned the bolt that far out anyway, but
	returning 0 makes the boundary explicit rather than relying on that.
]]
function Weapons.damageAtRange(id: string, distance: number): number
	local w = Weapons.get(id)
	local start = w.falloffStart
	if not start or distance <= start then
		return w.damage
	end
	if distance >= w.range then
		return w.class == "Blaster" and 0 or w.damage
	end
	local minMult = w.falloffMin or 1
	local t = (distance - start) / (w.range - start)
	return w.damage * (1 - t * (1 - minMult))
end

--- Sustained damage per second, accounting for reloads. Used for vendor sorting.
function Weapons.dps(id: string): number
	local w = Weapons.get(id)
	local shotsPerSecond = w.fireRate
	if w.mode == "Burst" and w.burstCount then
		shotsPerSecond = w.fireRate * w.burstCount
	end
	local raw = w.damage * shotsPerSecond
	if not w.magazine or not w.reloadTime then
		return raw
	end
	-- Weight by the fraction of time actually spent firing rather than reloading.
	local firingTime = w.magazine / shotsPerSecond
	return raw * (firingTime / (firingTime + w.reloadTime))
end

--- Seconds between attacks, after skill modifiers.
function Weapons.cooldown(id: string, cooldownMult: number?): number
	local w = Weapons.get(id)
	return (1 / w.fireRate) * (cooldownMult or 1)
end

--- Everything a vendor of `factionId` will stock for a player of `level`.
function Weapons.stockFor(factionId: string, level: number): { WeaponDef }
	local out = {}
	for _, w in defs do
		if w.cost <= 0 then
			continue
		end
		-- Show one tier above the player so there is always something to want.
		if w.requiredLevel > level + 6 then
			continue
		end
		local allowed = true
		if w.factions then
			allowed = false
			for _, f in w.factions do
				if f == factionId then
					allowed = true
					break
				end
			end
		end
		if allowed then
			table.insert(out, w)
		end
	end
	table.sort(out, function(a, b)
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.cost < b.cost
	end)
	return out
end

function Weapons.ids(): { string }
	local out = {}
	for id in defs do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

--[[
	The distinct classes a weapon in the catalogue can be, sorted.

	Derived rather than listed because `WeaponDef.class` is also the affix slot
	a weapon draws from (`Affixes.forSlot`), and a class with no affixes written
	for it is a silent gap. Reading the catalogue means adding one weapon of a
	new class makes `Affixes.validate` say so at boot.
]]
export type Maxima = {
	damage: number,
	fireRate: number,
	range: number,
}

local maxima: Maxima? = nil

--[[
	The largest damage, rate and range anywhere in the catalogue.

	Exists so the inventory panel can draw a stat as a bar, which needs a full
	length to divide by. Derived and memoised rather than authored for the same
	reason `classes` is: an authored `MAX_DAMAGE = 60` is a number that is
	correct on the day it is typed and silently wrong the first time somebody
	adds a heavier rifle -- and the symptom, a bar that sits at 100% for two
	different weapons, is exactly the sort of thing nobody reports.

	It follows that some weapon always fills each bar completely. That is the
	honest reading: the bar means "against the best in the game", not "against
	an arbitrary ceiling".
]]
function Weapons.maxima(): Maxima
	if maxima then
		return maxima
	end
	local m: Maxima = { damage = 0, fireRate = 0, range = 0 }
	for _, w in defs do
		m.damage = math.max(m.damage, w.damage)
		m.fireRate = math.max(m.fireRate, w.fireRate)
		m.range = math.max(m.range, w.range)
	end
	maxima = m
	return m
end

function Weapons.classes(): { string }
	local seen: { [string]: boolean } = {}
	local out = {}
	for _, w in defs do
		if not seen[w.class] then
			seen[w.class] = true
			table.insert(out, w.class)
		end
	end
	table.sort(out)
	return out
end

return Weapons
