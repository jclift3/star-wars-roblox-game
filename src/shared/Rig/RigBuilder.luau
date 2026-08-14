--!strict
--[[
	RigBuilder.luau

	Turns a Species + Costume pair into a finished, animatable R15 character.

	The important decision here is that we do NOT hand-build the skeleton.
	Players:CreateHumanoidModelFromDescription() returns a properly rigged R15
	Humanoid with correct Motor6D joints and attachments, which means Roblox's
	own animations and PathfindingService work on our NPCs for free. Hand-rigging
	is where the previous version of this project went wrong -- it produced welded
	boxes that could never animate or navigate.

	On top of that base rig we weld procedural cosmetics from Costumes.luau.

	PERFORMANCE
	CreateHumanoidModelFromDescription yields and is far too slow to call once per
	NPC in a crowd. We build one template per (species, costume, size) and clone
	it thereafter. Per-individual variety comes from post-clone recolouring, which
	is cheap. See `getTemplate`.
]]

local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local Species = require(script.Parent.Parent.Config.Species)
local Costumes = require(script.Parent.Parent.Config.Costumes)

type CosmeticPart = Types.CosmeticPart

local RigBuilder = {}

-- Every R15 limb, in the order Roblox names them.
local R15_LIMBS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

-- Height buckets. Baking scale into the template (rather than jittering it after
-- cloning) keeps welded cosmetics correctly fitted, since post-clone scaling only
-- moves the official body parts and would leave armour floating.
local SIZE_VARIANTS: { [string]: number } = {
	S = 0.94,
	M = 1.0,
	L = 1.07,
}

export type RigConfig = {
	species: string,
	costume: string?,
	sizeVariant: string?, -- "S" | "M" | "L"
	skinTone: Color3?, -- overrides the species' random roll
	displayName: string?,
}

local templateCache: { [string]: Model } = {}
local templateFolder: Folder? = nil

local function getTemplateFolder(): Folder
	if templateFolder and templateFolder.Parent then
		return templateFolder
	end
	local f = Instance.new("Folder")
	f.Name = "RigTemplates"
	-- ServerStorage is not replicated, so templates cost clients nothing.
	f.Parent = game:GetService("ServerStorage")
	templateFolder = f
	return f
end

--------------------------------------------------------------------------------
-- Cosmetic welding
--------------------------------------------------------------------------------

local function resolveShape(shape: string?): (Enum.PartType, boolean)
	if shape == "Ball" then
		return Enum.PartType.Ball, false
	elseif shape == "Cylinder" then
		return Enum.PartType.Cylinder, false
	elseif shape == "Wedge" then
		return Enum.PartType.Block, true
	end
	return Enum.PartType.Block, false
end

--[[
	Builds one cosmetic and welds it to its limb.

	`scale` and `offset` are fractions of the limb's own size, which is what lets
	a single costume definition fit every body plan without special cases.
]]
local function weldCosmetic(rig: Model, spec: CosmeticPart): BasePart?
	local limb = rig:FindFirstChild(spec.limb)
	if not (limb and limb:IsA("BasePart")) then
		-- Missing limbs are not fatal: some species intentionally omit parts.
		return nil
	end

	local shapeType, isWedge = resolveShape(spec.shape)
	local p: BasePart
	if isWedge then
		p = Instance.new("WedgePart")
	else
		local pp = Instance.new("Part")
		pp.Shape = shapeType
		p = pp
	end

	p.Name = spec.name
	p.Size = if spec.size then spec.size else limb.Size * (spec.scale or Vector3.one)
	p.Color = spec.color or Color3.fromRGB(200, 200, 200)
	p.Material = spec.material or Enum.Material.SmoothPlastic
	p.Transparency = spec.transparency or 0
	p.Reflectance = spec.reflectance or 0
	p.CanCollide = spec.canCollide or false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true

	local offsetStuds = (spec.offset or Vector3.zero) * limb.Size
	local rot = spec.rot or Vector3.zero
	p.CFrame = limb.CFrame
		* CFrame.new(offsetStuds)
		* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))

	p.Parent = rig

	-- WeldConstraint locks in whatever relative offset exists right now, so the
	-- CFrame above must be set before the weld is created.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = limb
	weld.Part1 = p
	weld.Parent = p

	if spec.light then
		local light = Instance.new("PointLight")
		light.Color = spec.light.color
		light.Range = spec.light.range
		light.Brightness = spec.light.brightness
		light.Shadows = false
		light.Parent = p
	end

	return p
end

--------------------------------------------------------------------------------
-- Template construction
--------------------------------------------------------------------------------

local function buildDescription(def: Species.SpeciesDef, tone: Color3, sizeMul: number): HumanoidDescription
	local d = Instance.new("HumanoidDescription")

	d.HeightScale = def.heightScale * sizeMul
	d.WidthScale = def.widthScale
	d.HeadScale = def.headScale
	d.DepthScale = def.depthScale
	d.BodyTypeScale = 0.3
	d.ProportionScale = def.proportionScale

	d.HeadColor = tone
	d.TorsoColor = tone
	d.LeftArmColor = tone
	d.RightArmColor = tone
	d.LeftLegColor = tone
	d.RightLegColor = tone

	return d
end

--- Welds a list of cosmetics, returning the parts that were actually created.
--- Specs targeting a limb this species does not have are skipped, so the
--- result can be shorter than the input.
local function applyCosmetics(rig: Model, specs: { CosmeticPart }): { BasePart }
	local made: { BasePart } = {}
	for _, spec in specs do
		local part = weldCosmetic(rig, spec)
		if part then
			table.insert(made, part)
		end
	end
	return made
end

local function hideBody(rig: Model)
	for _, limbName in R15_LIMBS do
		local limb = rig:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			limb.Transparency = 1
		end
	end
	local head = rig:FindFirstChild("Head")
	if head then
		local face = head:FindFirstChildWhichIsA("Decal")
		if face then
			face:Destroy()
		end
	end
end

--[[
	Builds (or returns a cached) template rig. Templates live in ServerStorage,
	are Archivable, and are cloned per NPC.
]]
local function getTemplate(speciesName: string, costumeName: string?, sizeVariant: string): Model
	local key = `{speciesName}|{costumeName or "none"}|{sizeVariant}`
	local cached = templateCache[key]
	if cached then
		return cached
	end

	local def = Species.get(speciesName)
	local sizeMul = SIZE_VARIANTS[sizeVariant] or 1
	local tone = def.skinTones[1] or Color3.fromRGB(200, 170, 150)

	local desc = buildDescription(def, tone, sizeMul)
	local rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	rig.Name = key

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "CreateHumanoidModelFromDescription returned a rig with no Humanoid")

	humanoid.WalkSpeed = def.baseWalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false

	-- Roblox ships a default "Animate" LocalScript in some rigs; NPCs are driven
	-- by our own server-side animator instead, so strip it to avoid conflicts.
	local stockAnimate = rig:FindFirstChild("Animate")
	if stockAnimate then
		stockAnimate:Destroy()
	end

	if def.hideBody then
		hideBody(rig)
	end

	-- Species anatomy first, so costume pieces layer on top of it.
	if def.features then
		applyCosmetics(rig, def.features)
	end
	if speciesName == "Twilek" then
		applyCosmetics(rig, Species.getLekku(tone))
	end
	if costumeName then
		applyCosmetics(rig, Costumes.get(costumeName))
	end

	rig.Parent = getTemplateFolder()
	templateCache[key] = rig
	return rig
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	Recolours the bare skin of an already-built rig. Used to give a crowd of the
	same species distinct individuals without rebuilding the template.
]]
local function recolourSkin(rig: Model, tone: Color3)
	for _, limbName in R15_LIMBS do
		local limb = rig:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") and limb.Transparency < 1 then
			limb.Color = tone
		end
	end
end

--[[
	Produces a ready-to-parent character model.

	The returned rig is NOT parented and NOT positioned -- callers decide where it
	goes, which keeps this module free of any world knowledge.
]]
function RigBuilder.build(config: RigConfig): Model
	local speciesName = config.species
	local def = Species.get(speciesName)
	local variant = config.sizeVariant or "M"

	local template = getTemplate(speciesName, config.costume, variant)
	local rig = template:Clone()
	rig.Name = config.displayName or def.displayName

	local tone = config.skinTone
	if not tone and #def.skinTones > 1 then
		tone = def.skinTones[math.random(1, #def.skinTones)]
	end
	if tone then
		recolourSkin(rig, tone)
		-- Lekku and snouts are skin-coloured too, so keep them in sync.
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") and (d.Name:match("^Lekku") or d.Name == "Snout" or d.Name == "Muzzle") then
				d.Color = tone
			end
		end
	end

	return rig
end

--- Picks a random size bucket. Exposed so crowd spawners get free variety.
function RigBuilder.randomSizeVariant(): string
	local roll = math.random()
	if roll < 0.25 then
		return "S"
	elseif roll < 0.8 then
		return "M"
	end
	return "L"
end

--- Welds extra cosmetics onto an already-built rig (equipment, rank insignia).
--- Returns the created parts so callers that need to take them off again --
--- changing outfit without respawning -- can find them without guessing names.
function RigBuilder.attach(rig: Model, specs: { CosmeticPart }): { BasePart }
	return applyCosmetics(rig, specs)
end

--- Warms the cache ahead of time so the first NPC of a type doesn't hitch.
function RigBuilder.precache(combos: { { species: string, costume: string? } })
	for _, combo in combos do
		for variant in SIZE_VARIANTS do
			getTemplate(combo.species, combo.costume, variant)
		end
	end
end

RigBuilder.R15_LIMBS = R15_LIMBS

return RigBuilder
