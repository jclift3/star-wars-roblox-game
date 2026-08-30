--!strict
--[[
	Species.luau

	Body plans. Every entry here becomes a HumanoidDescription, which is what
	CreateHumanoidModelFromDescription uses to build a correctly rigged R15
	character. The scale fields are the reason a Kaminoan reads as tall and
	spindly and a Jawa reads as a hooded toddler, without any custom meshes.

	Scale reference (1.0 == default Roblox R15 proportions):
	  heightScale     overall stature
	  widthScale      limb + torso girth
	  headScale       skull size -- the single biggest cue for "alien"
	  depthScale      front-to-back thickness
	  proportionScale 0 = stocky blocky limbs, 1 = long slender limbs

	`features` are extra procedural parts (lekku, snouts, horns) welded on by
	RigBuilder after the base rig exists. They use the shared CosmeticPart
	schema, so all sizes are relative to the limb and survive body scaling.
]]

local Types = require(script.Parent.Parent.Types)
local Palette = require(script.Parent.Palette)

type CosmeticPart = Types.CosmeticPart

export type SpeciesDef = {
	displayName: string,
	heightScale: number,
	widthScale: number,
	headScale: number,
	depthScale: number,
	proportionScale: number,
	skinTones: { Color3 },
	baseWalkSpeed: number,
	-- Whether the body itself should be hidden (droids are fully plated).
	hideBody: boolean?,
	features: { CosmeticPart }?,
}

local BLACK = Color3.fromRGB(20, 20, 24)
local HORN = Color3.fromRGB(40, 32, 28)

local Species = {}

local defs: { [string]: SpeciesDef } = {}

defs.Human = {
	displayName = "Human",
	heightScale = 1,
	widthScale = 1,
	headScale = 1,
	depthScale = 1,
	proportionScale = 0.5,
	skinTones = {
		Palette.SkinPale,
		Palette.SkinLight,
		Palette.SkinMid,
		Palette.SkinDeep,
		Palette.SkinDark,
	},
	baseWalkSpeed = 14,
}

defs.Twilek = {
	displayName = "Twi'lek",
	heightScale = 1.03,
	widthScale = 0.94,
	headScale = 0.98,
	depthScale = 1,
	proportionScale = 0.75,
	skinTones = { Palette.TwilekBlue, Palette.TwilekRed, Palette.TwilekGreen },
	baseWalkSpeed = 14,
	-- Lekku are generated per-NPC in getLekku() so they match the rolled skin tone.
}

defs.Rodian = {
	displayName = "Rodian",
	heightScale = 0.97,
	widthScale = 0.92,
	headScale = 1.08,
	depthScale = 1,
	proportionScale = 0.7,
	skinTones = { Palette.RodianGreen },
	baseWalkSpeed = 14,
	features = {
		{
			name = "Snout",
			limb = "Head",
			scale = Vector3.new(0.4, 0.4, 0.6),
			offset = Vector3.new(0, -0.1, -0.62),
			color = Palette.RodianGreen,
		},
		{
			name = "AntennaL",
			limb = "Head",
			scale = Vector3.new(0.09, 0.5, 0.09),
			offset = Vector3.new(-0.22, 0.62, 0.1),
			color = Palette.RodianGreen,
		},
		{
			name = "AntennaR",
			limb = "Head",
			scale = Vector3.new(0.09, 0.5, 0.09),
			offset = Vector3.new(0.22, 0.62, 0.1),
			color = Palette.RodianGreen,
		},
		{
			name = "EyeL",
			limb = "Head",
			shape = "Ball",
			scale = Vector3.new(0.34, 0.5, 0.34),
			offset = Vector3.new(-0.2, 0.18, -0.42),
			color = BLACK,
			reflectance = 0.3,
		},
		{
			name = "EyeR",
			limb = "Head",
			shape = "Ball",
			scale = Vector3.new(0.34, 0.5, 0.34),
			offset = Vector3.new(0.2, 0.18, -0.42),
			color = BLACK,
			reflectance = 0.3,
		},
	},
}

defs.Kaminoan = {
	displayName = "Kaminoan",
	heightScale = 1.38,
	widthScale = 0.72,
	headScale = 0.88,
	depthScale = 0.85,
	proportionScale = 1,
	skinTones = { Palette.KaminoanGrey },
	baseWalkSpeed = 12,
	features = {
		-- The long S-curved neck is the entire silhouette for this species.
		{
			name = "NeckLower",
			limb = "UpperTorso",
			scale = Vector3.new(0.22, 0.7, 0.22),
			offset = Vector3.new(0, 0.62, 0.06),
			color = Palette.KaminoanGrey,
		},
		{
			name = "NeckUpper",
			limb = "Head",
			scale = Vector3.new(0.3, 0.9, 0.3),
			offset = Vector3.new(0, -0.8, 0.04),
			color = Palette.KaminoanGrey,
		},
		{
			name = "Cranium",
			limb = "Head",
			shape = "Ball",
			scale = Vector3.new(0.9, 0.75, 1.35),
			offset = Vector3.new(0, 0.3, 0.22),
			color = Palette.KaminoanGrey,
		},
	},
}

defs.Jawa = {
	displayName = "Jawa",
	heightScale = 0.6,
	widthScale = 1.08,
	headScale = 1.15,
	depthScale = 1.05,
	proportionScale = 0.15,
	skinTones = { Palette.JawaBrown },
	baseWalkSpeed = 13,
	features = {
		-- A Jawa's face is never seen: just shadow and two glowing points.
		{
			name = "EyeGlowL",
			limb = "Head",
			shape = "Ball",
			scale = Vector3.new(0.16, 0.16, 0.16),
			offset = Vector3.new(-0.18, 0.02, -0.46),
			color = Color3.fromRGB(255, 220, 90),
			material = Enum.Material.Neon,
			light = { color = Color3.fromRGB(255, 210, 80), range = 5, brightness = 1.2 },
		},
		{
			name = "EyeGlowR",
			limb = "Head",
			shape = "Ball",
			scale = Vector3.new(0.16, 0.16, 0.16),
			offset = Vector3.new(0.18, 0.02, -0.46),
			color = Color3.fromRGB(255, 220, 90),
			material = Enum.Material.Neon,
			light = { color = Color3.fromRGB(255, 210, 80), range = 5, brightness = 1.2 },
		},
	},
}

defs.Wookiee = {
	displayName = "Wookiee",
	heightScale = 1.28,
	widthScale = 1.3,
	headScale = 1.05,
	depthScale = 1.25,
	proportionScale = 0.35,
	skinTones = { Palette.WookieeBrown },
	baseWalkSpeed = 15,
	features = {
		{
			name = "FurTorso",
			limb = "UpperTorso",
			scale = Vector3.new(1.12, 1.06, 1.3),
			color = Palette.WookieeBrown,
			material = Enum.Material.Fabric,
		},
		{
			name = "FurArmL",
			limb = "LeftUpperArm",
			scale = Vector3.new(1.3, 1.05, 1.3),
			color = Palette.WookieeBrown,
			material = Enum.Material.Fabric,
		},
		{
			name = "FurArmR",
			limb = "RightUpperArm",
			scale = Vector3.new(1.3, 1.05, 1.3),
			color = Palette.WookieeBrown,
			material = Enum.Material.Fabric,
		},
		{
			name = "Muzzle",
			limb = "Head",
			scale = Vector3.new(0.5, 0.42, 0.42),
			offset = Vector3.new(0, -0.16, -0.55),
			color = Color3.fromRGB(58, 40, 28),
			material = Enum.Material.Fabric,
		},
	},
}

defs.Trandoshan = {
	displayName = "Trandoshan",
	heightScale = 1.16,
	widthScale = 1.18,
	headScale = 1.02,
	depthScale = 1.15,
	proportionScale = 0.4,
	skinTones = { Palette.TrandoshanScale },
	baseWalkSpeed = 14,
	features = {
		{
			name = "Snout",
			limb = "Head",
			scale = Vector3.new(0.55, 0.42, 0.6),
			offset = Vector3.new(0, -0.18, -0.55),
			color = Palette.TrandoshanScale,
		},
	},
}

defs.Gungan = {
	displayName = "Gungan",
	heightScale = 1.12,
	widthScale = 0.9,
	headScale = 1.12,
	depthScale = 0.95,
	proportionScale = 0.85,
	skinTones = { Palette.GunganTan },
	baseWalkSpeed = 14,
	features = {
		{
			name = "Bill",
			limb = "Head",
			scale = Vector3.new(0.6, 0.24, 0.66),
			offset = Vector3.new(0, -0.26, -0.5),
			color = Palette.GunganTan,
		},
		{
			name = "HaillusL",
			limb = "Head",
			scale = Vector3.new(0.2, 1.25, 0.3),
			offset = Vector3.new(-0.44, -0.5, 0.18),
			color = Palette.GunganTan,
		},
		{
			name = "HaillusR",
			limb = "Head",
			scale = Vector3.new(0.2, 1.25, 0.3),
			offset = Vector3.new(0.44, -0.5, 0.18),
			color = Palette.GunganTan,
		},
	},
}

defs.Zabrak = {
	displayName = "Zabrak",
	heightScale = 1.04,
	widthScale = 1.02,
	headScale = 1,
	depthScale = 1,
	proportionScale = 0.5,
	skinTones = { Palette.ZabrakRust, Palette.SkinMid },
	baseWalkSpeed = 14,
	features = {},
}

-- Crown of horns, laid out as a ring around the skull.
do
	local horns = {}
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		table.insert(
			horns,
			{
				name = `Horn{i}`,
				limb = "Head",
				scale = Vector3.new(0.07, 0.3, 0.07),
				offset = Vector3.new(math.sin(a) * 0.3, 0.6, math.cos(a) * 0.3),
				color = HORN,
				material = Enum.Material.Slate,
			} :: CosmeticPart
		)
	end
	defs.Zabrak.features = horns
end

--[[
	The Underlevels.

	*"There is also mutant monsters in the lower levels"* -- Landon, and the
	only reason this is a species rather than a costume is that a monster is
	a silhouette. Coruscant's bottom deck is 440 studs under the Senate, sealed
	on every side, with no sun and no patrols; what lives down there has been
	down there long enough to stop reading as a person from across a street.

	So the scale fields do all the work: shorter than a human but half again
	as wide and thick, `proportionScale` at 0 for short blocky limbs, and an
	oversized skull -- the file's own note says head size is the single
	biggest cue for "alien", and it is right. Two colours, both sunless. The
	claws are on the hands rather than in them, which is what makes the
	`Claws` weapon draw nothing and still land.
]]
defs.Mutant = {
	displayName = "Undercity Mutant",
	heightScale = 0.92,
	widthScale = 1.44,
	headScale = 1.3,
	depthScale = 1.28,
	proportionScale = 0,
	skinTones = { Palette.MutantFlesh, Palette.MutantPallor },
	-- Slower than anything else on two legs. What makes it frightening is
	-- that there are six of them and the deck is sealed.
	baseWalkSpeed = 11,
	features = {
		-- A brow heavy enough to lose the eyes under, which is most of it.
		{
			name = "Brow",
			limb = "Head",
			scale = Vector3.new(1.08, 0.26, 0.5),
			offset = Vector3.new(0, 0.22, -0.3),
			color = Palette.MutantClaw,
			material = Enum.Material.Slate,
		},
		{
			name = "Jaw",
			limb = "Head",
			scale = Vector3.new(0.8, 0.34, 0.5),
			offset = Vector3.new(0, -0.34, -0.28),
			color = Palette.MutantFlesh,
			material = Enum.Material.Slate,
		},
		-- The hunch. A slab across the shoulders reads as stooped without
		-- touching the rig, which cannot be bent without breaking every
		-- animation the R15 gets for free.
		{
			name = "Hunch",
			limb = "UpperTorso",
			scale = Vector3.new(1.18, 0.5, 1.3),
			offset = Vector3.new(0, 0.34, 0.16),
			color = Palette.MutantFlesh,
			material = Enum.Material.Slate,
		},
	},
}

-- Claws, three to a hand. Generated rather than typed because six near-
-- identical records is six places for a number to drift.
do
	local claws = {}
	for _, side in { { limb = "LeftHand", sign = -1 }, { limb = "RightHand", sign = 1 } } do
		local limb, sign = side.limb, side.sign
		for i = -1, 1 do
			table.insert(
				claws,
				{
					name = `Claw{limb}{i}`,
					limb = limb,
					scale = Vector3.new(0.16, 0.16, 0.9),
					offset = Vector3.new(i * 0.26, -0.1, -0.55),
					rot = Vector3.new(-18, sign * i * 8, 0),
					color = Palette.MutantClaw,
					material = Enum.Material.Slate,
				} :: CosmeticPart
			)
		end
	end
	for _, claw in claws do
		table.insert(defs.Mutant.features :: { CosmeticPart }, claw)
	end
end

defs.ProtocolDroid = {
	displayName = "Protocol Droid",
	heightScale = 1.02,
	widthScale = 1,
	headScale = 1,
	depthScale = 1,
	proportionScale = 0.55,
	skinTones = { Palette.DroidGold },
	baseWalkSpeed = 11,
	hideBody = true,
}

defs.WarDroid = {
	displayName = "Battle Droid",
	heightScale = 1.2,
	widthScale = 0.68,
	headScale = 0.85,
	depthScale = 0.75,
	proportionScale = 1,
	skinTones = { Palette.BattleDroidTan },
	baseWalkSpeed = 13,
	hideBody = true,
	features = {
		{
			name = "Snout",
			limb = "Head",
			scale = Vector3.new(0.3, 0.3, 0.9),
			offset = Vector3.new(0, -0.22, -0.5),
			color = Palette.BattleDroidTan,
			material = Enum.Material.Metal,
		},
		{
			name = "Backpack",
			limb = "UpperTorso",
			scale = Vector3.new(0.45, 0.7, 0.4),
			offset = Vector3.new(0, 0.1, 0.6),
			color = Palette.BattleDroidTan,
			material = Enum.Material.Metal,
		},
	},
}

--[[
	Twi'lek head-tails, built as a two-segment taper per side so they drape down
	the back instead of sticking out like rods. Generated per-NPC because they
	must match whichever skin tone was rolled for that individual.
]]
function Species.getLekku(tone: Color3): { CosmeticPart }
	local out: { CosmeticPart } = {}
	for _, side in { -1, 1 } do
		local tag = side > 0 and "R" or "L"
		table.insert(out, {
			name = `Lekku{tag}Upper`,
			limb = "Head",
			scale = Vector3.new(0.26, 0.26, 1.0),
			offset = Vector3.new(0.3 * side, -0.16, 0.45),
			rot = Vector3.new(-16, 0, 0),
			color = tone,
			material = Enum.Material.SmoothPlastic,
		})
		table.insert(out, {
			name = `Lekku{tag}Lower`,
			limb = "Head",
			scale = Vector3.new(0.2, 0.2, 1.1),
			offset = Vector3.new(0.34 * side, -0.85, 0.9),
			rot = Vector3.new(-38, 0, 0),
			color = tone,
			material = Enum.Material.SmoothPlastic,
		})
	end
	return out
end

function Species.get(name: string): SpeciesDef
	local def = defs[name]
	assert(def, `Species.get: unknown species "{name}"`)
	return def
end

function Species.exists(name: string): boolean
	return defs[name] ~= nil
end

function Species.all(): { [string]: SpeciesDef }
	return defs
end

return Species
