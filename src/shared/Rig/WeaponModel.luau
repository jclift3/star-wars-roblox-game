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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

--[[
	HOW A BLASTER IS HELD, 2026-08-30

	Reported with a screenshot: the gun hangs at the character's hip, because
	the arm is in Roblox's idle pose and nothing had ever told it otherwise.
	A weapon that is welded correctly to a hand that is by its owner's side
	is still a weapon nobody is holding.

	WRITTEN TO `C0`, WHICH IS WHY THIS COSTS NOTHING PER FRAME
	A joint's final position is `C0 * Transform * C1:Inverse()`, and the
	`Animator` writes only `Transform`. So an offset written once into `C0`
	*composes* with whatever animation is playing rather than fighting it:
	the character keeps Roblox's walk, run and idle cycles and performs all
	of them with the gun up. The alternative -- re-writing `Transform` every
	frame after the animation step -- is the usual way this is done and it
	buys nothing here, at the cost of a `RenderStepped` loop per character.

	AND IT IS SET ON THE SERVER, SO IT IS SET ONCE FOR EVERYONE
	`Motor6D.C0` replicates. Posing here, where the weapon is already being
	built and welded, covers players and the ~160 NPCs by the same three
	lines, and means no client has to be told a character is armed. The two
	brothers see each other holding the same gun the same way, which is the
	standing requirement for anything they can both look at.

	THE NUMBERS ARE READ OFF THE SWING TABLE, NOT GUESSED
	`EffectsController.SWINGS` has been through a play test and establishes
	the convention: on the shoulder, X pitches the arm forward as it goes
	*negative* (-40 is forward and down, -150 is overhead and back), and Z
	swings it away from the torso. So -62 is a relaxed forward carry, and the
	small negative Z brings the muzzle in towards the character's centre line
	rather than leaving it out by the hip. A bent elbow, because a straight
	arm reads as pointing rather than holding.

	Blasters only. A vibroblade at low ready would be a second pose and a
	second set of numbers, and melee already has the whole swing arc to say
	that it is armed.
]]
local HOLD_SHOULDER = Vector3.new(-62, 0, -10)
local HOLD_ELBOW = Vector3.new(-20, 0, 0)

--- The right arm's two joints, either of which a species may legitimately lack.
local function armMotors(character: Model): (Motor6D?, Motor6D?)
	local upper = character:FindFirstChild("RightUpperArm")
	local lower = character:FindFirstChild("RightLowerArm")
	local shoulder = if upper then upper:FindFirstChild("RightShoulder") else nil
	local elbow = if lower then lower:FindFirstChild("RightElbow") else nil
	return (if shoulder and shoulder:IsA("Motor6D") then shoulder else nil),
		(if elbow and elbow:IsA("Motor6D") then elbow else nil)
end

--[[
	Rotates a joint away from its rest pose, remembering the rest pose once.

	Stored as an attribute on the joint rather than in a table keyed by
	character: the rig is the thing that owns this, a rig can be destroyed at
	any moment, and an attribute cannot leak or go stale after it is. Read
	back on the first call only, so a pose interrupted by a second pose can
	never become the new rest.
]]
local function poseJoint(joint: Motor6D?, degrees: Vector3)
	if not joint then
		return
	end
	local rest = joint:GetAttribute("RestC0")
	if typeof(rest) ~= "CFrame" then
		rest = joint.C0
		joint:SetAttribute("RestC0", rest)
	end
	joint.C0 = (rest :: CFrame) * CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
end

local function relaxJoint(joint: Motor6D?)
	local rest = if joint then joint:GetAttribute("RestC0") else nil
	if joint and typeof(rest) == "CFrame" then
		joint.C0 = rest
	end
end

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
	WHAT A CRYSTAL RECOLOURS, AND WHY IT IS NOT A NEW FIELD

	A focusing crystal turns the blade its own colour, which needs an answer to
	"which part is the blade". `WeaponDef.blade` names one on a lightsaber, but
	the electrostaff's glowing tips are ordinary entries in `parts` and there
	are two of them -- so a rule that reads `def.blade` would leave the staff
	half-tinted and the vibroblade untouched.

	The derivable rule is better: **a part that carries a `light` is a part
	that is emitting**, and a part that is emitting is what the crystal is
	feeding. No `WeaponPart.tintable` flag to author, nothing to keep in sync,
	and a weapon added next year is covered the day it is written.

	Steel is left alone by design. A vibroblade has no lit part, so a crystal
	in one shows up in its swing trail and its numbers and not in its edge --
	which is the honest answer, because nothing is powering that edge.
]]
local function tinted(spec: Weapons.WeaponPart, tint: Color3?): Color3?
	if tint and spec.light then
		return tint
	end
	return spec.color
end

local function buildPart(spec: Weapons.WeaponPart, origin: CFrame, tint: Color3?): BasePart
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
	p.Color = tinted(spec, tint) or Color3.fromRGB(60, 60, 65)
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
		light.Color = tint or spec.light.color
		light.Range = spec.light.range
		light.Brightness = spec.light.brightness
		light.Shadows = false
		light.Parent = p
	end

	return p
end

--[[
	Hangs a disabled `Trail` between the two ends of a blade.

	Reported from play, 2026-08-17: *"I have no way to actually swing it."* The
	swing was real -- `CombatService.swingMelee` has always swept an arc and
	dealt damage -- but nothing moved and nothing lit up, so the only evidence
	a swing had happened was that something else eventually fell over.

	A `Trail` between the tip and the base is Roblox's own answer to "draw
	where this thing has been", and it costs nothing while `Enabled` is false.
	Built here rather than by the client that wants to draw a swing, because
	the weapon model is made on the server and replicated: putting the trail in
	the model means every machine that can see the character can already see
	the arc, and switching it on is one property.

	IT IS NOT ONLY FOR LIT BLADES
	This first shipped gated on `WeaponDef.blade`, which meant a lightsaber
	drew an arc and a vibroblade drew nothing -- and a vibroblade is the
	weapon most likely to be in a low-level character's hand. Reported
	immediately: *"I just tried using my sword (vibroblade) but there doesn't
	seem to be any animation."* A steel edge leaves a streak too; it is just
	pale and short instead of glowing.

	THE LONG AXIS IS FOUND, NOT ASSUMED
	A lit blade is a Cylinder rotated so its length runs along X. The
	vibroblade's blade is a plain block 2.2 studs long on **Z**, and the
	gaderffii's shaft is a cylinder on X again. Reading `size.X` -- which is
	what the lightsaber-only version did -- would have put both attachments
	inside a 0.06-stud edge and drawn a trail with no width at all.
]]
local function buildTrail(part: BasePart, spec: Weapons.WeaponPart, lit: boolean, tint: Color3?)
	local size = spec.size
	local half = math.max(size.X, size.Y, size.Z) * 0.5
	local along = if size.X >= size.Y and size.X >= size.Z
		then Vector3.xAxis
		elseif size.Y >= size.Z then Vector3.yAxis
		else Vector3.zAxis

	local tip = Instance.new("Attachment")
	tip.Name = "TrailTip"
	tip.Position = along * half
	tip.Parent = part

	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = along * -half
	base.Parent = part

	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = tip
	trail.Attachment1 = base
	-- Tinted whether or not the part is lit, unlike the part itself: the arc is
	-- the swing, and a crystal that changed a lightsaber's streak but not a
	-- vibroblade's would make the same fitting mean different things.
	trail.Color = ColorSequence.new(tint or spec.color or Color3.new(1, 1, 1))
	-- Solid at the leading edge, gone at the tail, so the arc reads as a
	-- direction rather than a smear. An unlit edge starts fainter: steel
	-- catches the light, it does not emit any.
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if lit then 0.3 else 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = if lit then 0.22 else 0.14
	trail.LightEmission = if lit then 1 else 0.35
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = part
end

--[[
	The part whose sweep is worth drawing: the blade, or the longest thing the
	weapon is made of.

	"Longest" rather than a part called "Blade", because the thing that carves
	the arc on a gaderffii and an electrostaff is the shaft, and neither has a
	part by that name. It is also the honest general answer -- whatever sticks
	out furthest is what an onlooker watches.
]]
local function trailSpec(def: Weapons.WeaponDef): Weapons.WeaponPart?
	if def.blade then
		return def.blade
	end
	if def.class ~= "Melee" then
		return nil
	end
	local best: Weapons.WeaponPart? = nil
	local bestLength = 1.0 -- shorter than this is a fitting, not a business end
	for _, spec in def.parts do
		local length = math.max(spec.size.X, spec.size.Y, spec.size.Z)
		if length > bestLength then
			best, bestLength = spec, length
		end
	end
	return best
end

--[[
	Hangs imported geometry off the handle, or reports that it could not.

	RETURNING FALSE IS THE POINT OF THE SIGNATURE
	Every other weapon in the game is built out of `Instance.new` and cannot
	fail. This one depends on mesh uploads that live on somebody's Roblox
	account, and the honest failure -- the account is gone, the place was
	published by someone without access, Rojo was never told about `assets/`
	-- is that `ReplicatedStorage.Assets.Weapons.<name>` is simply not there.
	Silently building nothing would put an empty hand on a character and read
	as a bug in equipping. So the caller falls back to the `parts` list, which
	is why an imported weapon still declares one.

	MOVE THE PIVOT ONTO THE GRIP FIRST, THEN SCALE, THEN PLACE, THEN WELD
	Both of the operations below act on the model's *pivot*, and an imported
	model's pivot is Blender's world origin, which is not on the gun --
	see `ModelSource` for the measurements that proved it and the report
	that prompted them. So the pivot is moved onto the grip before either
	one runs, using the bounding box, which is the only frame of reference
	the geometry actually supplies.

	`ScaleTo` scales *about* the pivot and leaves it where it is, so with
	the pivot already on the grip the gun shrinks around the hand instead of
	sliding away from it -- which is also why this cannot be done in the
	other order. Welds go on last because a `WeldConstraint` freezes the
	offset it was created with, and every move above is still to come.
]]
local function buildImported(model: Model, handle: BasePart, source: Weapons.ModelSource): boolean
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local shelf = assets and assets:FindFirstChild("Weapons")
	local template = shelf and shelf:FindFirstChild(source.asset)
	if not (template and template:IsA("Model")) then
		warn(`WeaponModel: no imported model "{source.asset}" under ReplicatedStorage.Assets.Weapons`)
		return false
	end

	local clone = template:Clone()
	clone.Name = "Imported"

	local box, size = clone:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest <= 0 then
		warn(`WeaponModel: imported model "{source.asset}" has no geometry`)
		clone:Destroy()
		return false
	end

	-- `box` is centred, so a grip fraction of 0.5 on an axis is no shift at
	-- all and 0 and 1 are the two faces.
	clone.WorldPivot = box * CFrame.new((source.grip - Vector3.one * 0.5) * size)
	clone:ScaleTo(source.length / longest)

	local rot = source.rot or Vector3.zero
	clone:PivotTo(handle.CFrame * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z)))
	clone.Parent = model

	for _, part in clone:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		-- The same four flags every built weapon part carries. `CanQuery` is
		-- the one that matters: a mesh left queryable sits directly in front
		-- of the owner's own combat raycast and eats every shot they fire.
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end

	return true
end

--[[
	Builds an unparented, unpositioned weapon model.

	The Handle is invisible and sits at the grip, so callers can weld to it
	without caring which visible part happens to be biggest.

	`tint` is the colour of the crystal in the weapon's first filled socket,
	and is applied *here* rather than by mutating the `WeaponDef`. The config
	tables are shared by every weapon of that id in the game -- recolouring
	`def.blade.color` to serve one player would repaint every lightsaber on
	the server, which is a bug two people in the same room would find in a
	minute.
]]
function WeaponModel.build(weaponId: string, tint: Color3?): Model
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

	--[[
		An imported model replaces the part list rather than joining it.

		Drawing both would put a procedural blaster inside a modelled one --
		two guns in one hand, roughly the same size, clipping through each
		other. So `parts` on an imported weapon is what you get when the mesh
		does not load, and `buildImported` says which happened.
	]]
	local source = def.model
	local imported = source ~= nil and buildImported(model, handle, source)

	if not imported then
		local specs = table.clone(def.parts)
		if def.blade then
			table.insert(specs, def.blade)
		end

		local wantsTrail = trailSpec(def)
		local trailPart: BasePart? = nil
		for _, spec in specs do
			local p = buildPart(spec, handle.CFrame, tint)
			p.Parent = model
			if spec == wantsTrail then
				trailPart = p
			end

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = p
			weld.Parent = p
		end

		if trailPart and wantsTrail then
			buildTrail(trailPart, wantsTrail, def.blade ~= nil, tint)
		end
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
function WeaponModel.equip(character: Model, weaponId: string, tint: Color3?): Model?
	WeaponModel.unequip(character)

	local def = Weapons.get(weaponId)
	if #def.parts == 0 and not def.blade and not def.model then
		return nil
	end

	local hand = character:FindFirstChild("RightHand")
	if not (hand and hand:IsA("BasePart")) then
		return nil
	end

	local model = WeaponModel.build(weaponId, tint)
	local handle = model.PrimaryPart :: BasePart

	model.Name = "EquippedWeapon"
	model:SetAttribute("WeaponId", weaponId)
	--[[
		Recorded on the model so the bolts can find it.

		A blaster bolt is drawn on every client from the weapon id alone, and
		its colour now depends on a socket -- which is inventory, which is
		server-only. Rather than widen the `WeaponEffect` message with a
		colour, the tint is written here, on a model the server built and
		Roblox already replicates to everyone who can see the character. The
		shooter's own client and the four watching it read the same
		server-authored value, so nobody's screen can disagree, and a hacked
		client can only recolour a bolt on its own machine.
	]]
	model:SetAttribute("Tint", tint)
	model:PivotTo(hand.CFrame * GRIP_C0)
	model.Parent = character

	-- A Weld (not WeldConstraint) because the offset above must survive the
	-- hand being animated between now and the next physics step.
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = GRIP_C0
	weld.Parent = handle

	local shoulder, elbow = armMotors(character)
	if def.class == "Blaster" then
		poseJoint(shoulder, HOLD_SHOULDER)
		poseJoint(elbow, HOLD_ELBOW)
	else
		relaxJoint(shoulder)
		relaxJoint(elbow)
	end

	return model
end

function WeaponModel.unequip(character: Model)
	local existing = character:FindFirstChild("EquippedWeapon")
	if existing then
		existing:Destroy()
	end

	-- Unconditionally, because the arm has to come down even if the weapon
	-- model was already gone -- a respawn, a death, a swapped rig.
	local shoulder, elbow = armMotors(character)
	relaxJoint(shoulder)
	relaxJoint(elbow)
end

--[[
	The swing trail on the weapon `character` is holding, if it has one.

	Searched by name rather than by walking to a known part, because which part
	carries it depends on the weapon: a lit blade for a lightsaber, the shaft
	for a staff, the blade for a vibroblade. A blaster has none.
]]
function WeaponModel.trail(character: Model): Trail?
	local model = WeaponModel.equipped(character)
	local found = if model then model:FindFirstChild("SwingTrail", true) else nil
	return if found and found:IsA("Trail") then found else nil
end

--[[
	The crystal colour of the weapon `character` is holding, if it has one.

	Nil means "no crystal" and every caller falls back to the weapon's own
	`boltColor`, which is also the right answer for an NPC and for anything
	built before crystals existed.
]]
function WeaponModel.tintOf(character: Model?): Color3?
	local model = if character then WeaponModel.equipped(character) else nil
	local tint = model and model:GetAttribute("Tint")
	return if typeof(tint) == "Color3" then tint else nil
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
