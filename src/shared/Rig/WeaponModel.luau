--!strict
--[[
	WeaponModel.luau

	Turns a WeaponDef's part list into a physical model and puts it in a hand.

	The grip sits at the model's origin and the barrel points down -Z, matching
	the convention declared in Weapons.luau. That is the whole reason weapon
	geometry uses absolute studs while costume geometry uses limb-relative
	scale: a weapon has to line up with a muzzle flash and a bolt direction,
	and those are world measurements, not body measurements.

	Everything here is cosmetic. Damage is resolved by CombatService from the
	character's root, never from this model, so a missing or mis-welded weapon
	can look wrong but cannot make an NPC harmless or a player invincible.
]]

local Weapons = require(script.Parent.Parent.Config.Weapons)

local WeaponModel = {}

--[[
	Where the grip sits relative to the R15 right hand.

	In the default R15 rest pose the hand part's axes are aligned with the
	torso, so the weapon's -Z already points where the character is facing and
	no rotation is needed -- only a small drop and forward nudge to move the
	grip from the wrist into the palm.
]]
local GRIP_C0 = CFrame.new(0, -0.55, -0.15)

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

local function buildPart(spec: Weapons.WeaponPart, origin: CFrame): BasePart
	local shapeType, isWedge = resolveShape(spec.shape)

	local p: BasePart
	if isWedge then
		p = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		block.Shape = shapeType
		p = block
	end

	p.Name = spec.name
	p.Size = spec.size
	p.Color = spec.color or Color3.fromRGB(60, 60, 65)
	p.Material = spec.material or Enum.Material.Metal
	p.Transparency = spec.transparency or 0
	p.Reflectance = spec.reflectance or 0
	p.CanCollide = false
	p.CanQuery = false -- must not block combat raycasts fired from the owner
	p.CanTouch = false
	p.Massless = true

	local rot = spec.rot or Vector3.zero
	p.CFrame = origin
		* CFrame.new(spec.offset)
		* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))

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

--[[
	Builds an unparented, unpositioned weapon model.

	The Handle is invisible and sits at the grip, so callers can weld to it
	without caring which visible part happens to be biggest.
]]
function WeaponModel.build(weaponId: string): Model
	local def = Weapons.get(weaponId)

	local model = Instance.new("Model")
	model.Name = weaponId

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 0.3)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = model
	model.PrimaryPart = handle

	local specs = table.clone(def.parts)
	if def.blade then
		table.insert(specs, def.blade)
	end

	for _, spec in specs do
		local p = buildPart(spec, handle.CFrame)
		p.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
	end

	-- Muzzle is an Attachment rather than a part so effects can be parented to
	-- it directly and inherit the weapon's motion for free.
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = CFrame.new(def.muzzleOffset)
	muzzle.Parent = handle

	return model
end

--- The weapon currently held by `character`, if any.
function WeaponModel.equipped(character: Model): Model?
	local held = character:FindFirstChild("EquippedWeapon")
	return if held and held:IsA("Model") then held else nil
end

--[[
	Puts `weaponId` in the character's right hand, replacing whatever was there.

	Returns nil when the rig has no RightHand (some species deliberately omit
	limbs) or when the weapon has no geometry at all, which is how "Fists"
	works -- unarmed is a real weapon to the combat code and nothing to look at.
]]
function WeaponModel.equip(character: Model, weaponId: string): Model?
	WeaponModel.unequip(character)

	local def = Weapons.get(weaponId)
	if #def.parts == 0 and not def.blade then
		return nil
	end

	local hand = character:FindFirstChild("RightHand")
	if not (hand and hand:IsA("BasePart")) then
		return nil
	end

	local model = WeaponModel.build(weaponId)
	local handle = model.PrimaryPart :: BasePart

	model.Name = "EquippedWeapon"
	model:SetAttribute("WeaponId", weaponId)
	model:PivotTo(hand.CFrame * GRIP_C0)
	model.Parent = character

	-- A Weld (not WeldConstraint) because the offset above must survive the
	-- hand being animated between now and the next physics step.
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = GRIP_C0
	weld.Parent = handle

	return model
end

function WeaponModel.unequip(character: Model)
	local existing = character:FindFirstChild("EquippedWeapon")
	if existing then
		existing:Destroy()
	end
end

--- World position of the muzzle, for effects that need to start at the barrel.
function WeaponModel.muzzlePosition(character: Model): Vector3?
	local model = WeaponModel.equipped(character)
	local handle = model and model.PrimaryPart
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return nil
end

return WeaponModel
