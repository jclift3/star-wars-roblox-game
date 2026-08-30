--!strict
--[[
	Costumes.luau

	Every outfit in the game, described as procedural parts welded onto an R15
	rig. No mesh or texture asset IDs anywhere -- the whole wardrobe ships inside
	this repo and works the moment you sync.

	All geometry uses the shared CosmeticPart schema (see Types.luau):
	  scale   multiple of the limb's own size
	  offset  limb-local, as a fraction of limb size
	  rot     limb-local euler degrees

	Because everything is relative, one costume definition fits a 0.6x Jawa and a
	1.3x Wookiee without a single special case.

	Roblox convention reminder: characters face -Z, so offset.Z = -0.5 is the
	FRONT face of a limb and +0.5 is the back.
]]

local Types = require(script.Parent.Parent.Types)
local Palette = require(script.Parent.Palette)

type CosmeticPart = Types.CosmeticPart

local ARMS = { "LeftUpperArm", "RightUpperArm" }
local LOWER_ARMS = { "LeftLowerArm", "RightLowerArm" }
local UPPER_LEGS = { "LeftUpperLeg", "RightUpperLeg" }
local LOWER_LEGS = { "LeftLowerLeg", "RightLowerLeg" }
local FEET = { "LeftFoot", "RightFoot" }

--------------------------------------------------------------------------------
-- Small builders. Each returns a list of parts so costumes read as a recipe.
--------------------------------------------------------------------------------

local function part(p: CosmeticPart): CosmeticPart
	return p
end

-- Applies the same piece to several limbs at once (both arms, both legs...).
local function mirror(limbs: { string }, name: string, p: CosmeticPart): { CosmeticPart }
	local out = {}
	for i, limb in limbs do
		local copy: CosmeticPart = table.clone(p)
		copy.name = `{name}{i}`
		copy.limb = limb
		table.insert(out, copy)
	end
	return out
end

local function extend(dest: { CosmeticPart }, src: { CosmeticPart })
	for _, v in src do
		table.insert(dest, v)
	end
end

-- Assembles a costume from any mix of single parts and part-lists.
local function compose(...: any): { CosmeticPart }
	local out: { CosmeticPart } = {}
	for _, chunk in { ... } do
		if chunk.name then
			table.insert(out, chunk)
		else
			extend(out, chunk)
		end
	end
	return out
end

--- Full-coverage plated armour: chest, abdomen, shoulder bells, thighs, shins.
local function armourSuit(color: Color3, material: Enum.Material?): { CosmeticPart }
	local mat = material or Enum.Material.SmoothPlastic
	return compose(
		part({
			name = "ChestPlate",
			limb = "UpperTorso",
			scale = Vector3.new(1.1, 1.02, 1.24),
			offset = Vector3.new(0, 0.02, 0),
			color = color,
			material = mat,
		}),
		part({
			name = "AbPlate",
			limb = "LowerTorso",
			scale = Vector3.new(1.06, 1.15, 1.2),
			color = color,
			material = mat,
		}),
		mirror(ARMS, "ShoulderBell", {
			name = "",
			limb = "",
			scale = Vector3.new(1.32, 0.5, 1.32),
			offset = Vector3.new(0, 0.3, 0),
			color = color,
			material = mat,
		}),
		mirror(ARMS, "Bicep", {
			name = "",
			limb = "",
			scale = Vector3.new(1.16, 0.62, 1.16),
			offset = Vector3.new(0, -0.18, 0),
			color = color,
			material = mat,
		}),
		mirror(LOWER_ARMS, "Forearm", {
			name = "",
			limb = "",
			scale = Vector3.new(1.18, 0.92, 1.18),
			color = color,
			material = mat,
		}),
		mirror(UPPER_LEGS, "Thigh", {
			name = "",
			limb = "",
			scale = Vector3.new(1.16, 0.86, 1.16),
			offset = Vector3.new(0, 0.02, 0),
			color = color,
			material = mat,
		}),
		mirror(LOWER_LEGS, "Shin", {
			name = "",
			limb = "",
			scale = Vector3.new(1.18, 0.9, 1.2),
			color = color,
			material = mat,
		})
	)
end

--- Heavy boots. Slightly oversized so they read as separate from the leg.
local function boots(color: Color3): { CosmeticPart }
	return mirror(FEET, "Boot", {
		name = "",
		limb = "",
		scale = Vector3.new(1.24, 1.5, 1.22),
		offset = Vector3.new(0, -0.1, -0.06),
		color = color,
		material = Enum.Material.SmoothPlastic,
	})
end

--- Utility belt with a centre buckle.
local function belt(color: Color3, buckle: Color3?): { CosmeticPart }
	return compose(
		part({
			name = "Belt",
			limb = "LowerTorso",
			scale = Vector3.new(1.18, 0.7, 1.3),
			offset = Vector3.new(0, -0.28, 0),
			color = color,
			material = Enum.Material.Fabric,
		}),
		part({
			name = "Buckle",
			limb = "LowerTorso",
			scale = Vector3.new(0.34, 0.5, 0.3),
			offset = Vector3.new(0, -0.28, -0.55),
			color = buckle or Palette.Gunmetal,
			material = Enum.Material.Metal,
			reflectance = 0.15,
		})
	)
end

--- Full enclosing helmet with a dark visor band. The base for troopers.
local function helmetShell(color: Color3, visor: Color3?): { CosmeticPart }
	return compose(
		part({
			name = "Helmet",
			limb = "Head",
			scale = Vector3.new(1.2, 1.24, 1.24),
			offset = Vector3.new(0, 0.06, 0.02),
			color = color,
			material = Enum.Material.SmoothPlastic,
		}),
		part({
			name = "Visor",
			limb = "Head",
			scale = Vector3.new(1.02, 0.42, 0.3),
			offset = Vector3.new(0, 0.06, -0.62),
			color = visor or Palette.StormtrooperLens,
			material = Enum.Material.Glass,
			reflectance = 0.35,
		})
	)
end

--- Hooded robe: cowl, shoulder drape, and a skirt that hangs off the hips.
local function robe(cloth: Color3, hoodUp: boolean): { CosmeticPart }
	local pieces = compose(
		part({
			name = "RobeTorso",
			limb = "UpperTorso",
			scale = Vector3.new(1.16, 1.06, 1.3),
			color = cloth,
			material = Enum.Material.Fabric,
		}),
		part({
			name = "RobeSkirt",
			limb = "LowerTorso",
			scale = Vector3.new(1.3, 3.4, 1.4),
			offset = Vector3.new(0, -1.5, 0),
			color = cloth,
			material = Enum.Material.Fabric,
		}),
		mirror(ARMS, "Sleeve", {
			name = "",
			limb = "",
			scale = Vector3.new(1.35, 1.05, 1.35),
			color = cloth,
			material = Enum.Material.Fabric,
		}),
		mirror(LOWER_ARMS, "Cuff", {
			name = "",
			limb = "",
			scale = Vector3.new(1.42, 0.7, 1.42),
			offset = Vector3.new(0, 0.16, 0),
			color = cloth,
			material = Enum.Material.Fabric,
		})
	)
	if hoodUp then
		extend(pieces, {
			part({
				name = "Hood",
				limb = "Head",
				scale = Vector3.new(1.34, 1.3, 1.36),
				offset = Vector3.new(0, 0.12, 0.14),
				color = cloth,
				material = Enum.Material.Fabric,
			}),
			-- Brow ridge that casts the face into shadow.
			part({
				name = "HoodBrow",
				limb = "Head",
				scale = Vector3.new(1.36, 0.36, 0.5),
				offset = Vector3.new(0, 0.42, -0.4),
				rot = Vector3.new(-14, 0, 0),
				color = cloth,
				material = Enum.Material.Fabric,
			}),
		})
	end
	return pieces
end

--- Cape hanging from the shoulders. Two segments so it reads as cloth.
local function cape(color: Color3): { CosmeticPart }
	return compose(
		part({
			name = "CapeUpper",
			limb = "UpperTorso",
			scale = Vector3.new(1.2, 1.1, 0.16),
			offset = Vector3.new(0, 0, 0.62),
			color = color,
			material = Enum.Material.Fabric,
		}),
		part({
			name = "CapeLower",
			limb = "LowerTorso",
			scale = Vector3.new(1.24, 4.2, 0.16),
			offset = Vector3.new(0, -1.9, 0.7),
			rot = Vector3.new(4, 0, 0),
			color = color,
			material = Enum.Material.Fabric,
		})
	)
end

--- Officer's peaked cap.
local function peakedCap(color: Color3): { CosmeticPart }
	return compose(
		part({
			name = "Cap",
			limb = "Head",
			scale = Vector3.new(1.14, 0.5, 1.1),
			offset = Vector3.new(0, 0.56, 0.04),
			color = color,
			material = Enum.Material.Fabric,
		}),
		part({
			name = "CapBrim",
			limb = "Head",
			scale = Vector3.new(1.1, 0.1, 0.6),
			offset = Vector3.new(0, 0.36, -0.52),
			rot = Vector3.new(-8, 0, 0),
			color = Palette.ImperialBlack,
			material = Enum.Material.SmoothPlastic,
		}),
		part({
			name = "CapDisc",
			limb = "Head",
			scale = Vector3.new(0.24, 0.12, 0.2),
			offset = Vector3.new(0, 0.56, -0.5),
			color = Palette.DroidSilver,
			material = Enum.Material.Metal,
			reflectance = 0.3,
		})
	)
end

--- Coloured rank squares on the left chest -- the Imperial officer signature.
local function rankBadge(colors: { Color3 }): { CosmeticPart }
	local out = {}
	for i, c in colors do
		table.insert(
			out,
			part({
				name = `Rank{i}`,
				limb = "UpperTorso",
				scale = Vector3.new(0.07, 0.09, 0.02),
				offset = Vector3.new(-0.2 + (i - 1) * 0.09, 0.06, -0.53),
				color = c,
				material = Enum.Material.Neon,
			})
		)
	end
	return out
end

--- Angled shoulder pauldron (sandtroopers, bounty hunters).
local function pauldron(color: Color3, side: string): { CosmeticPart }
	local limb = side == "Left" and "LeftUpperArm" or "RightUpperArm"
	return {
		part({
			name = "Pauldron",
			limb = limb,
			scale = Vector3.new(1.5, 0.9, 1.45),
			offset = Vector3.new(0, 0.16, 0),
			color = color,
			material = Enum.Material.Fabric,
		}),
	}
end

--- Backpack / life-support box worn on the spine.
local function backpack(color: Color3, accent: Color3?): { CosmeticPart }
	return compose(
		part({
			name = "Backpack",
			limb = "UpperTorso",
			scale = Vector3.new(0.72, 0.86, 0.5),
			offset = Vector3.new(0, 0.02, 0.68),
			color = color,
			material = Enum.Material.Metal,
		}),
		part({
			name = "BackpackVent",
			limb = "UpperTorso",
			scale = Vector3.new(0.5, 0.16, 0.14),
			offset = Vector3.new(0, 0.34, 0.9),
			color = accent or Palette.DarkMetal,
			material = Enum.Material.DiamondPlate,
		})
	)
end

--------------------------------------------------------------------------------
-- Costume definitions
--------------------------------------------------------------------------------

local Costumes = {}

local defs: { [string]: { CosmeticPart } } = {}

-- The flagship model. Worth the extra detail: the helmet silhouette is the most
-- recognisable shape in the franchise, so it gets a brow, frown vents and
-- separate ear cups rather than a plain box.
defs.ImperialTrooper = compose(
	armourSuit(Palette.StormtrooperWhite),
	boots(Palette.StormtrooperWhite),
	belt(Palette.StormtrooperWhite, Palette.ImperialBlack),
	part({
		name = "Helmet",
		limb = "Head",
		scale = Vector3.new(1.18, 1.22, 1.22),
		offset = Vector3.new(0, 0.08, 0.02),
		color = Palette.StormtrooperWhite,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "HelmetBrow",
		limb = "Head",
		scale = Vector3.new(1.2, 0.3, 0.42),
		offset = Vector3.new(0, 0.4, -0.5),
		rot = Vector3.new(-10, 0, 0),
		color = Palette.StormtrooperShadow,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "EyeLensL",
		limb = "Head",
		scale = Vector3.new(0.34, 0.28, 0.16),
		offset = Vector3.new(-0.28, 0.12, -0.6),
		color = Palette.StormtrooperLens,
		material = Enum.Material.Glass,
		reflectance = 0.3,
	}),
	part({
		name = "EyeLensR",
		limb = "Head",
		scale = Vector3.new(0.34, 0.28, 0.16),
		offset = Vector3.new(0.28, 0.12, -0.6),
		color = Palette.StormtrooperLens,
		material = Enum.Material.Glass,
		reflectance = 0.3,
	}),
	-- The "frown" grille under the mouth.
	part({
		name = "Frown",
		limb = "Head",
		scale = Vector3.new(0.42, 0.14, 0.14),
		offset = Vector3.new(0, -0.3, -0.6),
		color = Palette.ImperialBlack,
		material = Enum.Material.DiamondPlate,
	}),
	part({
		name = "Breather",
		limb = "Head",
		scale = Vector3.new(0.56, 0.22, 0.18),
		offset = Vector3.new(0, -0.12, -0.58),
		color = Palette.StormtrooperShadow,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "EarCupL",
		limb = "Head",
		scale = Vector3.new(0.16, 0.4, 0.4),
		offset = Vector3.new(-0.6, 0.02, 0.02),
		color = Palette.StormtrooperShadow,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "EarCupR",
		limb = "Head",
		scale = Vector3.new(0.16, 0.4, 0.4),
		offset = Vector3.new(0.6, 0.02, 0.02),
		color = Palette.StormtrooperShadow,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "ChestVent",
		limb = "UpperTorso",
		scale = Vector3.new(0.5, 0.18, 0.06),
		offset = Vector3.new(0, 0.3, -0.62),
		color = Palette.ImperialBlack,
		material = Enum.Material.DiamondPlate,
	})
)

defs.ImperialScout = compose(
	armourSuit(Palette.SandtrooperTan),
	boots(Palette.SandtrooperTan),
	belt(Palette.SandtrooperTan, Palette.ImperialBlack),
	helmetShell(Palette.SandtrooperTan),
	pauldron(Palette.RebelOrange, "Right"),
	backpack(Palette.SandtrooperTan)
)

defs.ImperialCommando = compose(
	armourSuit(Palette.DeathTrooperBlack),
	boots(Palette.DeathTrooperBlack),
	belt(Palette.DeathTrooperBlack),
	helmetShell(Palette.DeathTrooperBlack, Palette.SaberRed),
	part({
		name = "VisorGlow",
		limb = "Head",
		scale = Vector3.new(0.9, 0.1, 0.1),
		offset = Vector3.new(0, 0.1, -0.66),
		color = Palette.SaberRed,
		material = Enum.Material.Neon,
		light = { color = Palette.SaberRed, range = 6, brightness = 1 },
	}),
	pauldron(Palette.DeathTrooperBlack, "Left")
)

defs.ImperialOfficer = compose(
	peakedCap(Palette.ImperialGrey),
	rankBadge({ Palette.SaberRed, Palette.SaberBlue, Palette.SaberBlue }),
	boots(Palette.ImperialBlack),
	belt(Palette.ImperialBlack),
	part({
		name = "Tunic",
		limb = "UpperTorso",
		scale = Vector3.new(1.08, 1.04, 1.16),
		color = Palette.ImperialGrey,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "TunicSkirt",
		limb = "LowerTorso",
		scale = Vector3.new(1.1, 2.2, 1.18),
		offset = Vector3.new(0, -0.7, 0),
		color = Palette.ImperialGrey,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "Sleeve", {
		name = "",
		limb = "",
		scale = Vector3.new(1.12, 1.04, 1.12),
		color = Palette.ImperialGrey,
		material = Enum.Material.Fabric,
	}),
	mirror(LOWER_ARMS, "Cuff", {
		name = "",
		limb = "",
		scale = Vector3.new(1.14, 1.02, 1.14),
		color = Palette.ImperialGrey,
		material = Enum.Material.Fabric,
	}),
	mirror(UPPER_LEGS, "Trouser", {
		name = "",
		limb = "",
		scale = Vector3.new(1.1, 1.02, 1.1),
		color = Palette.ImperialGrey,
		material = Enum.Material.Fabric,
	})
)

defs.SithHonourGuard = compose(
	robe(Palette.RoyalGuardRed, true),
	boots(Palette.RoyalGuardRed),
	part({
		name = "GuardHelm",
		limb = "Head",
		scale = Vector3.new(1.16, 1.5, 1.16),
		offset = Vector3.new(0, 0.3, 0.02),
		color = Palette.RoyalGuardRed,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "GuardSlit",
		limb = "Head",
		scale = Vector3.new(0.26, 0.6, 0.1),
		offset = Vector3.new(0, 0.1, -0.6),
		color = Palette.ImperialBlack,
		material = Enum.Material.SmoothPlastic,
	})
)

defs.RepublicTrooper = compose(
	boots(Palette.RebelOlive),
	belt(Palette.RebelTan),
	part({
		name = "Vest",
		limb = "UpperTorso",
		scale = Vector3.new(1.14, 1.0, 1.24),
		color = Palette.RebelTan,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "Shirt",
		limb = "LowerTorso",
		scale = Vector3.new(1.06, 1.1, 1.14),
		color = Palette.RebelOlive,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "Sleeve", {
		name = "",
		limb = "",
		scale = Vector3.new(1.1, 1.02, 1.1),
		color = Palette.RebelOlive,
		material = Enum.Material.Fabric,
	}),
	mirror(UPPER_LEGS, "Trouser", {
		name = "",
		limb = "",
		scale = Vector3.new(1.08, 1.02, 1.08),
		color = Palette.RebelOlive,
		material = Enum.Material.Fabric,
	}),
	-- The distinctive ridged "turtle shell" helmet.
	part({
		name = "RebelHelm",
		limb = "Head",
		scale = Vector3.new(1.16, 0.9, 1.24),
		offset = Vector3.new(0, 0.3, 0.04),
		color = Palette.RebelTan,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "HelmRidge",
		limb = "Head",
		scale = Vector3.new(0.18, 0.24, 1.3),
		offset = Vector3.new(0, 0.58, 0.04),
		color = Palette.RebelOlive,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "ChinStrap",
		limb = "Head",
		scale = Vector3.new(1.0, 0.2, 0.2),
		offset = Vector3.new(0, -0.34, -0.34),
		color = Palette.RebelOlive,
		material = Enum.Material.Fabric,
	})
)

defs.RepublicPilot = compose(
	boots(Palette.ImperialBlack),
	belt(Palette.RebelTan),
	part({
		name = "FlightSuit",
		limb = "UpperTorso",
		scale = Vector3.new(1.1, 1.04, 1.18),
		color = Palette.RebelOrange,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "FlightSuitLower",
		limb = "LowerTorso",
		scale = Vector3.new(1.08, 1.1, 1.16),
		color = Palette.RebelOrange,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "Sleeve", {
		name = "",
		limb = "",
		scale = Vector3.new(1.12, 1.02, 1.12),
		color = Palette.RebelOrange,
		material = Enum.Material.Fabric,
	}),
	mirror(UPPER_LEGS, "SuitLeg", {
		name = "",
		limb = "",
		scale = Vector3.new(1.1, 1.02, 1.1),
		color = Palette.RebelOrange,
		material = Enum.Material.Fabric,
	}),
	mirror(LOWER_LEGS, "SuitShin", {
		name = "",
		limb = "",
		scale = Vector3.new(1.1, 1.02, 1.1),
		color = Palette.RebelOrange,
		material = Enum.Material.Fabric,
	}),
	-- Chest life-support box, the pilot's most identifiable feature.
	part({
		name = "ChestBox",
		limb = "UpperTorso",
		scale = Vector3.new(0.42, 0.4, 0.16),
		offset = Vector3.new(0, -0.05, -0.6),
		color = Palette.HullWhite,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "ChestBoxLight",
		limb = "UpperTorso",
		scale = Vector3.new(0.1, 0.06, 0.06),
		offset = Vector3.new(-0.1, 0.02, -0.68),
		color = Palette.BlasterGreen,
		material = Enum.Material.Neon,
	}),
	part({
		name = "PilotHelm",
		limb = "Head",
		scale = Vector3.new(1.2, 1.16, 1.22),
		offset = Vector3.new(0, 0.16, 0.02),
		color = Palette.HullWhite,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "HelmStripe",
		limb = "Head",
		scale = Vector3.new(0.2, 1.2, 1.24),
		offset = Vector3.new(0, 0.16, 0.02),
		color = Palette.RebelOrange,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "PilotVisor",
		limb = "Head",
		scale = Vector3.new(1.0, 0.36, 0.3),
		offset = Vector3.new(0, 0.12, -0.6),
		color = Palette.ImperialBlack,
		material = Enum.Material.Glass,
		reflectance = 0.4,
	}),
	part({
		name = "Respirator",
		limb = "Head",
		scale = Vector3.new(0.5, 0.34, 0.3),
		offset = Vector3.new(0, -0.28, -0.54),
		color = Palette.WornSteel,
		material = Enum.Material.Metal,
	})
)

defs.RepublicVeteran = compose(
	armourSuit(Palette.CloneWhite),
	boots(Palette.CloneWhite),
	belt(Palette.CloneWhite),
	part({
		name = "CloneHelm",
		limb = "Head",
		scale = Vector3.new(1.18, 1.24, 1.26),
		offset = Vector3.new(0, 0.08, 0.02),
		color = Palette.CloneWhite,
		material = Enum.Material.SmoothPlastic,
	}),
	-- Phase II fin along the crown.
	part({
		name = "CloneFin",
		limb = "Head",
		scale = Vector3.new(0.14, 0.34, 1.0),
		offset = Vector3.new(0, 0.6, 0.06),
		color = Palette.CloneBlue,
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "CloneVisorL",
		limb = "Head",
		scale = Vector3.new(0.3, 0.34, 0.16),
		offset = Vector3.new(-0.28, 0.1, -0.62),
		rot = Vector3.new(0, 0, -12),
		color = Palette.ImperialBlack,
		material = Enum.Material.Glass,
	}),
	part({
		name = "CloneVisorR",
		limb = "Head",
		scale = Vector3.new(0.3, 0.34, 0.16),
		offset = Vector3.new(0.28, 0.1, -0.62),
		rot = Vector3.new(0, 0, 12),
		color = Palette.ImperialBlack,
		material = Enum.Material.Glass,
	}),
	part({
		name = "CloneMarkingL",
		limb = "LeftUpperArm",
		scale = Vector3.new(1.2, 0.3, 1.2),
		offset = Vector3.new(0, 0.05, 0),
		color = Palette.CloneBlue,
		material = Enum.Material.SmoothPlastic,
	})
)

defs.Jedi = compose(
	robe(Palette.JediBrown, true),
	boots(Palette.SmugglerBrown),
	belt(Palette.SmugglerBrown, Palette.CopperTrim),
	-- Cream tabards over the robe, crossing at the chest.
	part({
		name = "TabardL",
		limb = "UpperTorso",
		scale = Vector3.new(0.22, 1.1, 1.34),
		offset = Vector3.new(-0.26, 0, 0),
		color = Palette.JediCream,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "TabardR",
		limb = "UpperTorso",
		scale = Vector3.new(0.22, 1.1, 1.34),
		offset = Vector3.new(0.26, 0, 0),
		color = Palette.JediCream,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "Obi",
		limb = "LowerTorso",
		scale = Vector3.new(1.24, 1.3, 1.34),
		offset = Vector3.new(0, 0.05, 0),
		color = Palette.JediCream,
		material = Enum.Material.Fabric,
	})
)

defs.JediHoodDown = compose(
	robe(Palette.JediBrown, false),
	boots(Palette.SmugglerBrown),
	belt(Palette.SmugglerBrown, Palette.CopperTrim),
	part({
		name = "Collar",
		limb = "UpperTorso",
		scale = Vector3.new(1.2, 0.3, 1.36),
		offset = Vector3.new(0, 0.42, 0.1),
		color = Palette.JediBrown,
		material = Enum.Material.Fabric,
	})
)

defs.Sith = compose(
	robe(Palette.SithBlack, true),
	boots(Palette.SithBlack),
	belt(Palette.SithBlack),
	cape(Palette.SithBlack),
	-- Deep shadow inside the cowl instead of a visible face.
	part({
		name = "CowlShadow",
		limb = "Head",
		scale = Vector3.new(0.9, 0.8, 0.2),
		offset = Vector3.new(0, 0.05, -0.48),
		color = Color3.fromRGB(6, 6, 8),
		material = Enum.Material.SmoothPlastic,
	})
)

defs.SithLordArmoured = compose(
	armourSuit(Palette.SithBlack, Enum.Material.Metal),
	boots(Palette.SithBlack),
	cape(Palette.SithBlack),
	part({
		name = "Mask",
		limb = "Head",
		scale = Vector3.new(1.2, 1.3, 1.28),
		offset = Vector3.new(0, 0.06, 0.02),
		color = Palette.SithBlack,
		material = Enum.Material.Metal,
		reflectance = 0.25,
	}),
	part({
		name = "MaskLensL",
		limb = "Head",
		scale = Vector3.new(0.3, 0.26, 0.14),
		offset = Vector3.new(-0.26, 0.16, -0.64),
		color = Palette.SaberRed,
		material = Enum.Material.Neon,
	}),
	part({
		name = "MaskLensR",
		limb = "Head",
		scale = Vector3.new(0.3, 0.26, 0.14),
		offset = Vector3.new(0.26, 0.16, -0.64),
		color = Palette.SaberRed,
		material = Enum.Material.Neon,
	}),
	part({
		name = "MaskGrille",
		limb = "Head",
		scale = Vector3.new(0.44, 0.3, 0.2),
		offset = Vector3.new(0, -0.24, -0.6),
		color = Palette.DarkMetal,
		material = Enum.Material.DiamondPlate,
	}),
	part({
		name = "ChestPanel",
		limb = "UpperTorso",
		scale = Vector3.new(0.44, 0.36, 0.14),
		offset = Vector3.new(0, 0.02, -0.64),
		color = Palette.DarkMetal,
		material = Enum.Material.DiamondPlate,
	}),
	part({
		name = "PanelLight",
		limb = "UpperTorso",
		scale = Vector3.new(0.08, 0.06, 0.06),
		offset = Vector3.new(-0.12, 0.1, -0.7),
		color = Palette.SaberRed,
		material = Enum.Material.Neon,
	})
)

defs.BountyHunter = compose(
	armourSuit(Palette.RebelOlive, Enum.Material.Metal),
	boots(Palette.Gunmetal),
	belt(Palette.SmugglerBrown),
	backpack(Palette.Gunmetal, Palette.RebelOrange),
	pauldron(Palette.Gunmetal, "Right"),
	-- Mandalorian T-visor.
	part({
		name = "MandoHelm",
		limb = "Head",
		scale = Vector3.new(1.16, 1.26, 1.2),
		offset = Vector3.new(0, 0.1, 0.02),
		color = Palette.WornSteel,
		material = Enum.Material.Metal,
		reflectance = 0.2,
	}),
	part({
		name = "VisorBar",
		limb = "Head",
		scale = Vector3.new(0.88, 0.22, 0.16),
		offset = Vector3.new(0, 0.2, -0.62),
		color = Palette.ImperialBlack,
		material = Enum.Material.Glass,
		reflectance = 0.4,
	}),
	part({
		name = "VisorStem",
		limb = "Head",
		scale = Vector3.new(0.22, 0.5, 0.16),
		offset = Vector3.new(0, -0.05, -0.62),
		color = Palette.ImperialBlack,
		material = Enum.Material.Glass,
		reflectance = 0.4,
	}),
	part({
		name = "RangeFinder",
		limb = "Head",
		scale = Vector3.new(0.12, 0.6, 0.12),
		offset = Vector3.new(0.52, 0.6, 0.05),
		color = Palette.Gunmetal,
		material = Enum.Material.Metal,
	})
)

defs.Smuggler = compose(
	boots(Palette.SmugglerBrown),
	belt(Palette.SmugglerBrown, Palette.CopperTrim),
	part({
		name = "Shirt",
		limb = "UpperTorso",
		scale = Vector3.new(1.06, 1.04, 1.14),
		color = Palette.HullWhite,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "Vest",
		limb = "UpperTorso",
		scale = Vector3.new(1.16, 0.96, 1.1),
		color = Palette.ImperialBlack,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "Sleeve", {
		name = "",
		limb = "",
		scale = Vector3.new(1.08, 1.02, 1.08),
		color = Palette.HullWhite,
		material = Enum.Material.Fabric,
	}),
	mirror(UPPER_LEGS, "Trouser", {
		name = "",
		limb = "",
		scale = Vector3.new(1.08, 1.02, 1.08),
		color = Palette.RebelBlue,
		material = Enum.Material.Fabric,
	}),
	-- Bloodstripe down the outer seam.
	part({
		name = "BloodstripeL",
		limb = "LeftUpperLeg",
		scale = Vector3.new(0.12, 1.04, 0.1),
		offset = Vector3.new(-0.5, 0, 0),
		color = Palette.SaberRed,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "BloodstripeR",
		limb = "RightUpperLeg",
		scale = Vector3.new(0.12, 1.04, 0.1),
		offset = Vector3.new(0.5, 0, 0),
		color = Palette.SaberRed,
		material = Enum.Material.Fabric,
	}),
	-- Low-slung holster on the right thigh.
	part({
		name = "Holster",
		limb = "RightUpperLeg",
		scale = Vector3.new(0.5, 0.55, 0.5),
		offset = Vector3.new(0.42, -0.2, 0.1),
		color = Palette.SmugglerBrown,
		material = Enum.Material.Fabric,
	})
)

defs.Jawa = compose(
	part({
		name = "JawaRobe",
		limb = "UpperTorso",
		scale = Vector3.new(1.3, 1.15, 1.35),
		color = Palette.JawaBrown,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "JawaSkirt",
		limb = "LowerTorso",
		scale = Vector3.new(1.4, 4.5, 1.45),
		offset = Vector3.new(0, -2.0, 0),
		color = Palette.JawaBrown,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "JawaHood",
		limb = "Head",
		scale = Vector3.new(1.45, 1.4, 1.45),
		offset = Vector3.new(0, 0.16, 0.1),
		color = Palette.JawaBrown,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "HoodPeak",
		limb = "Head",
		scale = Vector3.new(1.3, 0.5, 0.5),
		offset = Vector3.new(0, 0.5, -0.4),
		rot = Vector3.new(-24, 0, 0),
		color = Palette.JawaBrown,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "FaceVoid",
		limb = "Head",
		scale = Vector3.new(0.8, 0.7, 0.2),
		offset = Vector3.new(0, 0.02, -0.5),
		color = Color3.fromRGB(8, 6, 6),
		material = Enum.Material.SmoothPlastic,
	}),
	part({
		name = "Bandolier",
		limb = "UpperTorso",
		scale = Vector3.new(1.36, 0.24, 1.4),
		offset = Vector3.new(0, 0.05, 0),
		rot = Vector3.new(0, 0, 24),
		color = Palette.SmugglerBrown,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "Sleeve", {
		name = "",
		limb = "",
		scale = Vector3.new(1.3, 1.05, 1.3),
		color = Palette.JawaBrown,
		material = Enum.Material.Fabric,
	})
)

defs.TuskenRaider = compose(
	boots(Palette.TuskenWrap),
	part({
		name = "Wraps",
		limb = "UpperTorso",
		scale = Vector3.new(1.16, 1.06, 1.24),
		color = Palette.TuskenWrap,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "WrapSkirt",
		limb = "LowerTorso",
		scale = Vector3.new(1.2, 2.6, 1.28),
		offset = Vector3.new(0, -0.9, 0),
		color = Palette.TuskenWrap,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "ArmWrap", {
		name = "",
		limb = "",
		scale = Vector3.new(1.22, 1.04, 1.22),
		color = Palette.TuskenWrap,
		material = Enum.Material.Fabric,
	}),
	mirror(LOWER_ARMS, "ForearmWrap", {
		name = "",
		limb = "",
		scale = Vector3.new(1.24, 1.02, 1.24),
		color = Palette.SmugglerBrown,
		material = Enum.Material.Fabric,
	}),
	mirror(UPPER_LEGS, "LegWrap", {
		name = "",
		limb = "",
		scale = Vector3.new(1.16, 1.02, 1.16),
		color = Palette.TuskenWrap,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "Mask",
		limb = "Head",
		scale = Vector3.new(1.22, 1.26, 1.24),
		offset = Vector3.new(0, 0.06, 0.02),
		color = Palette.TuskenWrap,
		material = Enum.Material.Fabric,
	}),
	-- Twin eye lenses and the breathing tube grille.
	part({
		name = "GoggleL",
		limb = "Head",
		scale = Vector3.new(0.26, 0.26, 0.24),
		offset = Vector3.new(-0.26, 0.16, -0.62),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	}),
	part({
		name = "GoggleR",
		limb = "Head",
		scale = Vector3.new(0.26, 0.26, 0.24),
		offset = Vector3.new(0.26, 0.16, -0.62),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	}),
	part({
		name = "Mouthpiece",
		limb = "Head",
		scale = Vector3.new(0.36, 0.3, 0.3),
		offset = Vector3.new(0, -0.26, -0.6),
		color = Palette.WornSteel,
		material = Enum.Material.Metal,
	}),
	part({
		name = "TubeL",
		limb = "Head",
		scale = Vector3.new(0.1, 0.5, 0.1),
		offset = Vector3.new(-0.42, -0.3, -0.4),
		rot = Vector3.new(0, 0, 30),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	}),
	part({
		name = "TubeR",
		limb = "Head",
		scale = Vector3.new(0.1, 0.5, 0.1),
		offset = Vector3.new(0.42, -0.3, -0.4),
		rot = Vector3.new(0, 0, -30),
		color = Palette.DarkMetal,
		material = Enum.Material.Metal,
	})
)

defs.MoistureFarmer = compose(
	boots(Palette.SmugglerBrown),
	belt(Palette.SmugglerBrown),
	part({
		name = "Tunic",
		limb = "UpperTorso",
		scale = Vector3.new(1.12, 1.04, 1.2),
		color = Palette.RebelTan,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "TunicSkirt",
		limb = "LowerTorso",
		scale = Vector3.new(1.14, 2.0, 1.22),
		offset = Vector3.new(0, -0.6, 0),
		color = Palette.RebelTan,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "Sleeve", {
		name = "",
		limb = "",
		scale = Vector3.new(1.14, 1.02, 1.14),
		color = Palette.RebelTan,
		material = Enum.Material.Fabric,
	}),
	mirror(UPPER_LEGS, "Trouser", {
		name = "",
		limb = "",
		scale = Vector3.new(1.08, 1.02, 1.08),
		color = Palette.TuskenWrap,
		material = Enum.Material.Fabric,
	})
)

defs.Civilian = compose(
	boots(Palette.SmugglerBrown),
	belt(Palette.SmugglerBrown),
	part({
		name = "Tunic",
		limb = "UpperTorso",
		scale = Vector3.new(1.08, 1.04, 1.16),
		color = Palette.RebelBlue,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "TunicLower",
		limb = "LowerTorso",
		scale = Vector3.new(1.08, 1.1, 1.16),
		color = Palette.RebelBlue,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "Sleeve", {
		name = "",
		limb = "",
		scale = Vector3.new(1.1, 1.02, 1.1),
		color = Palette.RebelBlue,
		material = Enum.Material.Fabric,
	}),
	mirror(UPPER_LEGS, "Trouser", {
		name = "",
		limb = "",
		scale = Vector3.new(1.08, 1.02, 1.08),
		color = Palette.ImperialGrey,
		material = Enum.Material.Fabric,
	})
)

--[[
	Not an outfit so much as what is left of one.

	The Underlevels mutants were people, and the story only lands if you can
	see that -- so they are still wearing the scraps of somebody's work clothes
	over a body that has stopped fitting them. Deliberately thin: the species'
	proportions are the silhouette, and burying them under fabric would undo
	the one thing that makes these read as monsters at fifty studs.
]]
defs.Mutant = compose(
	part({
		name = "Rag",
		limb = "UpperTorso",
		scale = Vector3.new(1.04, 0.62, 1.1),
		offset = Vector3.new(0, -0.18, 0),
		color = Palette.JawaBrown,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "Wrap",
		limb = "LowerTorso",
		scale = Vector3.new(1.08, 0.9, 1.12),
		color = Palette.SmugglerBrown,
		material = Enum.Material.Fabric,
	}),
	mirror(LOWER_ARMS, "Binding", {
		name = "",
		limb = "",
		scale = Vector3.new(1.14, 0.5, 1.14),
		offset = Vector3.new(0, 0.2, 0),
		color = Palette.TuskenWrap,
		material = Enum.Material.Fabric,
	})
)

defs.Merchant = compose(
	robe(Palette.NabooRoyal, false),
	boots(Palette.SmugglerBrown),
	belt(Palette.CopperTrim, Palette.DroidGold),
	part({
		name = "Sash",
		limb = "UpperTorso",
		scale = Vector3.new(1.24, 0.3, 1.34),
		offset = Vector3.new(0, 0.1, 0),
		rot = Vector3.new(0, 0, 20),
		color = Palette.DroidGold,
		material = Enum.Material.Fabric,
	})
)

defs.RepublicSecurity = compose(
	boots(Palette.SmugglerBrown),
	belt(Palette.SmugglerBrown),
	part({
		name = "Coat",
		limb = "UpperTorso",
		scale = Vector3.new(1.12, 1.05, 1.2),
		color = Palette.NabooRoyal,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "CoatSkirt",
		limb = "LowerTorso",
		scale = Vector3.new(1.16, 2.6, 1.24),
		offset = Vector3.new(0, -0.95, 0),
		color = Palette.NabooRoyal,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "Sleeve", {
		name = "",
		limb = "",
		scale = Vector3.new(1.12, 1.02, 1.12),
		color = Palette.NabooRoyal,
		material = Enum.Material.Fabric,
	}),
	-- Tall brimmed helmet.
	part({
		name = "GuardHat",
		limb = "Head",
		scale = Vector3.new(1.1, 0.9, 1.1),
		offset = Vector3.new(0, 0.5, 0.02),
		color = Palette.SmugglerBrown,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "HatBrim",
		limb = "Head",
		scale = Vector3.new(1.5, 0.1, 1.5),
		offset = Vector3.new(0, 0.2, 0.02),
		color = Palette.SmugglerBrown,
		material = Enum.Material.Fabric,
	})
)

defs.Researcher = compose(
	part({
		name = "LabRobe",
		limb = "UpperTorso",
		scale = Vector3.new(1.14, 1.06, 1.22),
		color = Palette.HullWhite,
		material = Enum.Material.Fabric,
	}),
	part({
		name = "LabSkirt",
		limb = "LowerTorso",
		scale = Vector3.new(1.2, 3.6, 1.3),
		offset = Vector3.new(0, -1.6, 0),
		color = Palette.HullWhite,
		material = Enum.Material.Fabric,
	}),
	mirror(ARMS, "Sleeve", {
		name = "",
		limb = "",
		scale = Vector3.new(1.2, 1.04, 1.2),
		color = Palette.HullWhite,
		material = Enum.Material.Fabric,
	})
)

defs.ProtocolDroid = compose(
	armourSuit(Palette.DroidGold, Enum.Material.Metal),
	boots(Palette.DroidGold),
	part({
		name = "DroidSkull",
		limb = "Head",
		scale = Vector3.new(1.14, 1.18, 1.16),
		offset = Vector3.new(0, 0.06, 0.02),
		color = Palette.DroidGold,
		material = Enum.Material.Metal,
		reflectance = 0.35,
	}),
	part({
		name = "PhotoreceptorL",
		limb = "Head",
		scale = Vector3.new(0.26, 0.26, 0.2),
		offset = Vector3.new(-0.24, 0.16, -0.6),
		color = Color3.fromRGB(255, 240, 190),
		material = Enum.Material.Neon,
		light = { color = Color3.fromRGB(255, 235, 180), range = 6, brightness = 0.8 },
	}),
	part({
		name = "PhotoreceptorR",
		limb = "Head",
		scale = Vector3.new(0.26, 0.26, 0.2),
		offset = Vector3.new(0.24, 0.16, -0.6),
		color = Color3.fromRGB(255, 240, 190),
		material = Enum.Material.Neon,
	}),
	part({
		name = "Mouthplate",
		limb = "Head",
		scale = Vector3.new(0.44, 0.24, 0.18),
		offset = Vector3.new(0, -0.26, -0.58),
		color = Palette.DarkMetal,
		material = Enum.Material.DiamondPlate,
	}),
	-- Exposed wiring at the midriff, a nice bit of visual grit.
	part({
		name = "Wiring",
		limb = "LowerTorso",
		scale = Vector3.new(0.9, 0.5, 0.9),
		offset = Vector3.new(0, 0.3, 0),
		color = Palette.DarkMetal,
		material = Enum.Material.DiamondPlate,
	})
)

defs.WarDroid = compose(
	part({
		name = "DroidTorso",
		limb = "UpperTorso",
		scale = Vector3.new(0.9, 1.04, 0.8),
		color = Palette.BattleDroidTan,
		material = Enum.Material.Metal,
	}),
	part({
		name = "DroidAb",
		limb = "LowerTorso",
		scale = Vector3.new(0.8, 1.1, 0.8),
		color = Palette.BattleDroidTan,
		material = Enum.Material.Metal,
	}),
	mirror(ARMS, "DroidArm", {
		name = "",
		limb = "",
		scale = Vector3.new(0.6, 1.06, 0.6),
		color = Palette.BattleDroidTan,
		material = Enum.Material.Metal,
	}),
	mirror(LOWER_ARMS, "DroidForearm", {
		name = "",
		limb = "",
		scale = Vector3.new(0.55, 1.06, 0.55),
		color = Palette.BattleDroidTan,
		material = Enum.Material.Metal,
	}),
	mirror(UPPER_LEGS, "DroidThigh", {
		name = "",
		limb = "",
		scale = Vector3.new(0.6, 1.04, 0.6),
		color = Palette.BattleDroidTan,
		material = Enum.Material.Metal,
	}),
	mirror(LOWER_LEGS, "DroidShin", {
		name = "",
		limb = "",
		scale = Vector3.new(0.55, 1.04, 0.55),
		color = Palette.BattleDroidTan,
		material = Enum.Material.Metal,
	}),
	part({
		name = "DroidSkull",
		limb = "Head",
		scale = Vector3.new(0.7, 1.0, 0.7),
		offset = Vector3.new(0, 0.1, 0.05),
		color = Palette.BattleDroidTan,
		material = Enum.Material.Metal,
	}),
	part({
		name = "OpticL",
		limb = "Head",
		scale = Vector3.new(0.12, 0.12, 0.1),
		offset = Vector3.new(-0.16, 0.24, -0.4),
		color = Palette.SaberRed,
		material = Enum.Material.Neon,
	}),
	part({
		name = "OpticR",
		limb = "Head",
		scale = Vector3.new(0.12, 0.12, 0.1),
		offset = Vector3.new(0.16, 0.24, -0.4),
		color = Palette.SaberRed,
		material = Enum.Material.Neon,
	})
)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Costumes.get(name: string): { CosmeticPart }
	local def = defs[name]
	assert(def, `Costumes.get: unknown costume "{name}"`)
	return def
end

function Costumes.exists(name: string): boolean
	return defs[name] ~= nil
end

function Costumes.all(): { [string]: { CosmeticPart } }
	return defs
end

-- Exposed so other modules (ships, props) can reuse the same builders.
Costumes.builders = {
	armourSuit = armourSuit,
	boots = boots,
	belt = belt,
	helmetShell = helmetShell,
	robe = robe,
	cape = cape,
	peakedCap = peakedCap,
	rankBadge = rankBadge,
	pauldron = pauldron,
	backpack = backpack,
	mirror = mirror,
	compose = compose,
}

return Costumes
