--!strict
--[[
	EffectsController.luau

	Everything you see when something is shot or swung.

	Bolts are purely cosmetic. Damage was already resolved on the server by an
	instant raycast before this bolt was drawn, which is the standard trick:
	hitscan for fairness, a travelling bolt for the look. If the visual and the
	damage ever disagree, the damage is right.

	Because they are cosmetic, bolts live on the client that can see them and
	are never replicated. A server-created bolt part costs every client memory
	and network traffic for something that lasts a third of a second.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Palette = require(Shared.Config.Palette)
local Weapons = require(Shared.Config.Weapons)
local Abilities = require(Shared.Config.Abilities)
local WeaponModel = require(Shared.Rig.WeaponModel)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local EffectsController = {
	name = "EffectsController",
	priority = 30,
}

local player = Players.LocalPlayer

local BOLT_LENGTH = 4
local BOLT_THICKNESS = 0.18
local IMPACT_LIFETIME = 0.35
local DAMAGE_LABEL_LIFETIME = 0.9

local effectsFolder: Folder? = nil

local boltParams = RaycastParams.new()
boltParams.FilterType = Enum.RaycastFilterType.Exclude
boltParams.IgnoreWater = true

local function container(): Folder
	if effectsFolder and effectsFolder.Parent then
		return effectsFolder
	end
	local f = Instance.new("Folder")
	f.Name = "ClientEffects"
	f.Parent = Workspace
	effectsFolder = f
	return f
end

--------------------------------------------------------------------------------
-- Impacts
--------------------------------------------------------------------------------

local function spawnImpact(position: Vector3, normal: Vector3, color: Color3)
	local flash = Instance.new("Part")
	flash.Name = "Impact"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.6, 0.6, 0.6)
	flash.Position = position
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Color = color
	flash.Material = Enum.Material.Neon
	flash.Parent = container()

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 3
	light.Shadows = false
	light.Parent = flash

	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(color)
	sparks.Size = NumberSequence.new(0.12)
	sparks.Lifetime = NumberRange.new(0.15, 0.3)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(50, 50)
	sparks.Rate = 0
	sparks.LightEmission = 1
	sparks.Parent = flash
	sparks:Emit(8)

	-- Nudged along the surface normal so sparks are not born inside the wall.
	flash.Position = position + normal * 0.2

	TweenService:Create(flash, TweenInfo.new(IMPACT_LIFETIME), {
		Size = Vector3.new(0.05, 0.05, 0.05),
		Transparency = 1,
	}):Play()

	Debris:AddItem(flash, IMPACT_LIFETIME + 0.4)
end

--------------------------------------------------------------------------------
-- Bolts
--------------------------------------------------------------------------------

--[[
	Draws a blaster bolt travelling from `origin` along `direction`.

	The client raycasts only to decide where the bolt stops. That result never
	leaves this machine, so a tampered raycast changes nothing but this
	player's own view of a shot that has already been resolved.

	`tint` overrides the weapon's own bolt colour and comes from the crystal in
	the shooter's blaster. Read off the replicated weapon model rather than
	sent per shot -- see the note where `WeaponModel.equip` writes it.
]]
function EffectsController.spawnBolt(weaponId: string, origin: Vector3, direction: Vector3, tint: Color3?)
	local weapon = Weapons.get(weaponId)
	local color = tint or weapon.boltColor or Palette.BlasterRed
	local range = weapon.range
	local dir = direction.Unit

	local ignore: { Instance } = { container() }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	boltParams.FilterDescendantsInstances = ignore

	local hit = Workspace:Raycast(origin, dir * range, boltParams)
	local finish = if hit then hit.Position else origin + dir * range
	local travel = (finish - origin).Magnitude

	local bolt = Instance.new("Part")
	bolt.Name = "Bolt"
	bolt.Size = Vector3.new(BOLT_THICKNESS, BOLT_THICKNESS, BOLT_LENGTH)
	bolt.CFrame = CFrame.lookAt(origin, origin + dir)
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.CanTouch = false
	bolt.Color = color
	bolt.Material = Enum.Material.Neon
	bolt.CastShadow = false
	bolt.Parent = container()

	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 10
	glow.Brightness = 2
	glow.Shadows = false
	glow.Parent = bolt

	local speed = weapon.projectileSpeed or 600
	local duration = math.max(0.02, travel / speed)

	local tween = TweenService:Create(bolt, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(finish, finish + dir),
	})
	tween:Play()

	tween.Completed:Connect(function()
		if hit then
			spawnImpact(hit.Position, hit.Normal, color)
		end
		bolt:Destroy()
	end)

	Debris:AddItem(bolt, duration + 0.5)
end

--------------------------------------------------------------------------------
-- Melee swings
--------------------------------------------------------------------------------

--[[
	MAKING A SWING VISIBLE

	Reported from play, 2026-08-17: *"I have this ridiculously long lightsaber
	but I have no way to actually swing it."*

	The swing worked. `CombatService.swingMelee` has always swept an arc from
	the character's root and dealt damage on a left click, and the server has
	always broadcast a `WeaponEffect` for it. What was missing was any part of
	that reaching the screen: the arm never moved, the blade never moved, and
	`EffectsController` dropped every `WeaponEffect` that was not a blaster on
	the floor. Yet another thing that was finished and unreachable.

	WHY MOTOR6D AND NOT AN ANIMATION
	The rigs are built by `Players:CreateHumanoidModelFromDescription`, so they
	are genuine R15 Humanoids and could play a real Animation -- but an
	`Animation` is an *asset id*, which means uploading one, which is exactly
	the marketplace dependency this project refuses to take. Writing `C0` on
	the shoulder and elbow joints costs nothing, ships in the repo, and
	composes with whatever walk cycle Roblox's own animator is running, because
	the animator writes `Transform` and this writes `C0`.

	WHY IT IS DRAWN ON EVERY CLIENT SEPARATELY
	`C0` changes do not replicate. That is a feature here: the server tells
	every machine *that* a swing happened, and every machine draws it locally
	from the same weapon definition -- so this is cosmetic in the same way the
	bolts above are, and a tampered swing animation hurts nobody.
]]

--- Fractions of the swing spent raising the weapon and bringing it down. The
--- remainder is the recovery back to rest.
local WINDUP = 0.3
local STRIKE = 0.32

--[[
	The two swings, alternating, so a held button reads as a combo rather than
	the same twitch over and over.

	Euler angles in degrees, applied to the joint's resting `C0`. The first is
	an overhead diagonal from the character's right down across to its left;
	the second is its mirror, starting across the body and opening out. X
	pitches the arm forward and back, Z swings it away from the torso.
]]
type Pose = { shoulder: Vector3, elbow: Vector3 }
local SWINGS: { { windup: Pose, strike: Pose } } = {
	{
		windup = { shoulder = Vector3.new(-150, 0, 55), elbow = Vector3.new(-35, 0, 0) },
		strike = { shoulder = Vector3.new(-40, 0, -55), elbow = Vector3.new(-5, 0, 0) },
	},
	{
		windup = { shoulder = Vector3.new(-140, 0, -45), elbow = Vector3.new(-35, 0, 0) },
		strike = { shoulder = Vector3.new(-40, 0, 65), elbow = Vector3.new(-5, 0, 0) },
	},
}

type SwingState = {
	index: number,
	--- Bumped by every swing. A running swing that finds it changed gives up,
	--- which is how the second half of a combo interrupts the first.
	token: number,
	restShoulder: CFrame?,
	restElbow: CFrame?,
}

-- Weak keys: a character is destroyed on respawn and this must not be the
-- reason it stays in memory. Alternation surviving between swings is the
-- whole point, so the entries cannot simply be deleted when a swing ends.
local swings: { [Model]: SwingState } = {}
setmetatable(swings :: any, { __mode = "k" })

local warnedNoArm = false

--[[
	THE ARC IS DRAWN FROM THE ROOT, NOT FROM THE ARM

	Reported from play, 2026-08-19: *"I'm still not able to swing my
	lightsaber. To shoot, I click -- is it different for the light saber?"*
	Asked what happens on screen: **nothing at all moves.**

	The 2026-08-17 fix put the whole swing on the character's shoulder joint,
	and everything below this comment still does. What that quietly assumed is
	that the player is standing in a rig this code recognises -- and the
	player is not wearing a `RigBuilder` rig. NPCs are; a *player* keeps
	Roblox's own avatar, which `PlayerService` dresses but does not rebuild
	(hence the R15 check it warns about at `PlayerService.luau:179`). So the
	one thing the swing had to say was said through a joint the game does not
	own, on a body it did not build, and if that joint is not there the swing
	is silent -- while still dealing full damage. That is the same "finished
	but unreachable" shape as last time, one level further down.

	So the swing gets a second visual that cannot be withheld: a blade-shaped
	sliver swept through the air in front of the character, from the root
	part, which every character has by definition. The arm arc stays -- it is
	free and it is better when it works -- but it is no longer the only
	evidence a swing happened.

	IT IS THE REAL REACH, NOT A NICE-LOOKING LENGTH
	`CombatService.swingMelee` sweeps a sphere of `range * 0.7` centred
	`range * 0.4` ahead of the root, so the blade can kill about `range * 1.1`
	away and that is exactly how long this is drawn. The reticle is derived
	from `spread` and the stat bars from `maxima` for the same reason: a
	drawing that disagrees with the rule it depicts teaches the player
	something false, and they will trust it over the rule.
]]
local ARC_DEGREES = 150
local ARC_RISE = 35 -- degrees above level at the top of the cut

local function swingColour(character: Model, def: Weapons.WeaponDef): Color3
	-- The crystal first, for the same reason the bolts read it: what the
	-- player fitted is what the player should see cut the air.
	local tint = WeaponModel.tintOf(character)
	if tint then
		return tint
	end
	if def.blade then
		return def.blade.color or Palette.SaberBlue
	end
	-- Steel has no colour of its own to show, so it gets a pale highlight.
	return Color3.fromRGB(214, 220, 236)
end

local function sweepArc(character: Model, def: Weapons.WeaponDef, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end

	local lit = def.blade ~= nil
	local colour = swingColour(character, def)
	local reach = def.range * 1.1
	local half = math.rad(ARC_DEGREES) * 0.5

	local blade = Instance.new("Part")
	blade.Name = "SwingArc"
	blade.Size = Vector3.new(0.1, 0.1, reach)
	blade.Anchored = true
	blade.CanCollide = false
	blade.CanQuery = false
	blade.CanTouch = false
	blade.CastShadow = false
	blade.Color = colour
	blade.Material = Enum.Material.Neon
	-- Invisible until the cut starts. The wind-up is the blade going *up*,
	-- and drawing that would put an arc above the player's head every time
	-- they swing at nothing.
	blade.Transparency = 1
	blade.CFrame = root.CFrame * CFrame.new(0, 0.5, -reach * 0.5)
	blade.Parent = container()
	-- Backstop: a character destroyed mid-swing must not leave this behind.
	Debris:AddItem(blade, duration + 1)

	local tip = Instance.new("Attachment")
	tip.Position = Vector3.new(0, 0, -reach * 0.5)
	tip.Parent = blade

	local hilt = Instance.new("Attachment")
	hilt.Position = Vector3.new(0, 0, reach * 0.5)
	hilt.Parent = blade

	local trail = Instance.new("Trail")
	trail.Attachment0 = tip
	trail.Attachment1 = hilt
	trail.Color = ColorSequence.new(colour)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if lit then 0.25 else 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.28
	trail.LightEmission = if lit then 1 else 0.35
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = blade

	task.spawn(function()
		task.wait(duration * WINDUP)
		if not (blade.Parent and root.Parent) then
			return
		end
		blade.Transparency = if lit then 0.35 else 0.6
		trail.Enabled = true

		local started = os.clock()
		local span = duration * STRIKE
		while true do
			local a = (os.clock() - started) / span
			if a >= 1 or not root.Parent then
				break
			end
			-- The same easing curve the arm uses, so on a rig where both are
			-- drawn the blade and the hand are in the same place.
			local eased = a ^ 0.55
			blade.CFrame = root.CFrame
				* CFrame.Angles(0, half - eased * half * 2, 0)
				* CFrame.Angles(math.rad(ARC_RISE) * (1 - eased * 2), 0, 0)
				* CFrame.new(0, 0.5, -reach * 0.5)
			RunService.RenderStepped:Wait()
		end

		-- The part goes now, the streak it laid down fades on its own for
		-- another `Lifetime` -- so the arc hangs in the air off a blade that
		-- has already finished, which is what makes it read as a cut.
		trail.Enabled = false
		blade.Transparency = 1
		Debris:AddItem(blade, trail.Lifetime + 0.1)
	end)
end

local function motor(character: Model, limb: string, joint: string): Motor6D?
	local part = character:FindFirstChild(limb)
	local found = if part then part:FindFirstChild(joint) else nil
	return if found and found:IsA("Motor6D") then found else nil
end

local function angles(degrees: Vector3): CFrame
	return CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
end

--[[
	Plays one swing of `weaponId` on `character`.

	Safe to call for a weapon that has no blade, a rig with no right arm, or a
	character that is destroyed halfway through: each of those simply draws
	less, and none of them is worth refusing a swing the server has already
	resolved.
]]
function EffectsController.swing(character: Model, weaponId: string)
	if not Weapons.exists(weaponId) then
		return
	end
	local def = Weapons.get(weaponId)
	-- Slightly quicker than the weapon can be swung again, so the arm is back
	-- at rest before the next one starts rather than snapping there.
	local duration = math.max(0.18, Weapons.cooldown(weaponId) * 0.85)

	-- First, and unconditionally: the arc is the one part of the swing that
	-- does not need the rig's cooperation. Everything below it does.
	sweepArc(character, def, duration)

	local shoulder = motor(character, "RightUpperArm", "RightShoulder")
	if not shoulder then
		--[[
			Said out loud, once. The arc above already went out, so this is no
			longer the difference between a visible swing and an invisible one
			-- it is the difference between a swing and a good one, and it is
			still worth knowing about.

			`RightUpperArm` is an R15 part name. The likeliest reason it is
			missing is an R6 avatar, which `PlayerService` also refuses to dress
			-- so if this fires, check the output for its warning too and set
			Avatar Type to R15 in Game Settings.
		]]
		if not warnedNoArm then
			warnedNoArm = true
			warn(`[EffectsController] no RightUpperArm/RightShoulder on {character.Name}; arm swing skipped`)
		end
		return
	end
	local elbow = motor(character, "RightLowerArm", "RightElbow")

	local state = swings[character]
	if not state then
		state = { index = 0, token = 0 }
		swings[character] = state
	end
	-- Captured on the first swing, not on every swing: a swing interrupted
	-- mid-arc leaves `C0` somewhere in the middle, and reading it then would
	-- make that the new rest pose for good.
	if not state.restShoulder then
		state.restShoulder = shoulder.C0
	end
	if elbow and not state.restElbow then
		state.restElbow = elbow.C0
	end
	local restShoulder = state.restShoulder :: CFrame
	local restElbow = state.restElbow

	state.index += 1
	state.token += 1
	local token = state.token
	local swing = SWINGS[(state.index % #SWINGS) + 1]
	local trail = WeaponModel.trail(character)

	task.spawn(function()
		local started = os.clock()
		while true do
			local t = (os.clock() - started) / duration
			if state.token ~= token or not character.Parent or t >= 1 then
				break
			end

			local shoulderTo: CFrame
			local elbowTo: CFrame?
			if t < WINDUP then
				-- Eased out, so the wind-up decelerates into the top of the
				-- arc and the strike has something to fall from.
				local a = 1 - (1 - t / WINDUP) ^ 2
				shoulderTo = restShoulder:Lerp(restShoulder * angles(swing.windup.shoulder), a)
				elbowTo = if restElbow then restElbow:Lerp(restElbow * angles(swing.windup.elbow), a) else nil
				if trail then
					trail.Enabled = false
				end
			elseif t < WINDUP + STRIKE then
				-- Eased in: almost all of the travel happens in the first
				-- third of the strike, which is what makes it read as a cut
				-- rather than a wave.
				local a = ((t - WINDUP) / STRIKE) ^ 0.55
				local from = restShoulder * angles(swing.windup.shoulder)
				shoulderTo = from:Lerp(restShoulder * angles(swing.strike.shoulder), a)
				elbowTo = if restElbow
					then (restElbow * angles(swing.windup.elbow)):Lerp(
						restElbow * angles(swing.strike.elbow),
						a
					)
					else nil
				if trail then
					trail.Enabled = true
				end
			else
				local a = (t - WINDUP - STRIKE) / (1 - WINDUP - STRIKE)
				shoulderTo = (restShoulder * angles(swing.strike.shoulder)):Lerp(restShoulder, a)
				elbowTo = if restElbow
					then (restElbow * angles(swing.strike.elbow)):Lerp(restElbow, a)
					else nil
				-- Switched off at the start of the recovery, not the end: a
				-- Trail keeps drawing what it already laid down for its own
				-- `Lifetime`, so the arc fades out of a blade that has
				-- stopped moving instead of following it back up.
				if trail then
					trail.Enabled = false
				end
			end

			shoulder.C0 = shoulderTo
			if elbow and elbowTo then
				elbow.C0 = elbowTo
			end

			RunService.RenderStepped:Wait()
		end

		-- Only the most recent swing puts the arm down. An interrupted one
		-- returning to rest would yank the arm out of the swing that replaced
		-- it.
		if state.token == token then
			shoulder.C0 = restShoulder
			if elbow and restElbow then
				elbow.C0 = restElbow
			end
			if trail then
				trail.Enabled = false
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Abilities
--------------------------------------------------------------------------------

--[[
	Draws an ability going off, from its *shape* rather than its id.

	Three shapes and no per-ability branch, exactly like `AbilityService`: a
	sixth ability should get a visual for free, and a client that had to be
	edited alongside every new power is a client that will eventually be one
	power behind the server.

	Cosmetic, like the bolts above, and drawn from the same replicated
	`Abilities` table the server resolved the effect from -- so the flash is
	the right size for the thing that actually happened.
]]
local ABILITY_LIFETIME = 0.45

local function spawnAbilityEffect(abilityId: string, origin: Vector3, direction: Vector3)
	local def = Abilities.get(abilityId)
	-- Still the shape that decides the geometry; this only picks a colour, and
	-- it is worth a branch because "the thing I painted" and "the thing I hurt"
	-- have to look different from the moment they leave the barrel.
	local colour = if def.heal
		then Palette.SaberGreen
		elseif def.mark then Palette.SaberYellow
		elseif def.damageType == "Explosive" then Palette.RebelOrange
		else Palette.SaberBlue

	local part = Instance.new("Part")
	part.Name = "AbilityEffect"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = colour
	part.Material = Enum.Material.Neon
	part.Transparency = 0.55
	part.CastShadow = false

	local grown: Vector3
	if def.shape == Abilities.Shape.Cone then
		-- A flat slab down the middle of the cone. A real cone mesh would be
		-- more honest and much more work for something on screen for a third
		-- of a second; what the player needs to read is the direction.
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(1, 1, def.range)
		part.CFrame = CFrame.lookAt(origin + direction * (def.range * 0.5), origin + direction * def.range)
		grown = Vector3.new(def.range * 0.5, 1, def.range)
	else
		part.Shape = Enum.PartType.Ball
		local radius = def.radius or 8
		part.Size = Vector3.new(1, 1, 1)
		-- `origin` is already the resolved spot for a Point and the caster for
		-- an Aura -- the server sends whichever one this shape happens on, so
		-- the client never has to re-derive a landing point it could get wrong.
		part.Position = origin
		grown = Vector3.new(radius, radius, radius) * 2
	end

	part.Parent = container()

	local light = Instance.new("PointLight")
	light.Color = colour
	light.Range = 18
	light.Brightness = 3
	light.Shadows = false
	light.Parent = part

	-- A Point ability is drawn when it *lands*, so the flash waits out the
	-- fuse: showing the bang at the moment of the throw would teach players to
	-- dodge at the wrong time.
	task.delay(def.fuse or 0, function()
		if not part.Parent then
			return
		end
		TweenService:Create(part, TweenInfo.new(ABILITY_LIFETIME, Enum.EasingStyle.Quad), {
			Size = grown,
			Transparency = 1,
		}):Play()
	end)

	Debris:AddItem(part, (def.fuse or 0) + ABILITY_LIFETIME + 0.2)
end

--------------------------------------------------------------------------------
-- Damage numbers
--------------------------------------------------------------------------------

--[[
	Floats a damage number where the hit landed.

	Feedback like this is what makes a weapon upgrade legible: without it, the
	only evidence that a DL-44 hits harder than a DH-17 is that enemies die
	slightly sooner.
]]
local function spawnDamageLabel(position: Vector3, amount: number, isCritical: boolean)
	local anchor = Instance.new("Part")
	anchor.Name = "DamageNumber"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = container()

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 30)
	gui.AlwaysOnTop = true
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = if isCritical then `{math.floor(amount)}!` else tostring(math.floor(amount))
	label.TextColor3 = if isCritical then Palette.SaberYellow else Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.35
	label.Parent = gui

	TweenService:Create(anchor, TweenInfo.new(DAMAGE_LABEL_LIFETIME, Enum.EasingStyle.Quad), {
		Position = position + Vector3.new(0, 4, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(DAMAGE_LABEL_LIFETIME, Enum.EasingStyle.Quad), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	Debris:AddItem(anchor, DAMAGE_LABEL_LIFETIME + 0.1)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function EffectsController.init()
	Net.onClientEvent(
		Net.Event.WeaponEffect,
		function(weaponId: string, origin: Vector3, direction: Vector3, source: Model?)
			if not Weapons.exists(weaponId) then
				return
			end
			if Weapons.get(weaponId).class == "Blaster" then
				-- `source` is the shooter, and the only thing this needs it
				-- for is the crystal colour on the weapon in its hand. A shot
				-- from a character that has already been cleaned up still
				-- draws -- in the weapon's own colour, which is correct.
				EffectsController.spawnBolt(weaponId, origin, direction, WeaponModel.tintOf(source))
			elseif source then
				-- A melee swing is drawn on the body that swung, so the server
				-- has to say whose it was.
				EffectsController.swing(source, weaponId)
			end
		end
	)

	Net.onClientEvent(Net.Event.AbilityUsed, function(abilityId: string, origin: Vector3, direction: Vector3)
		if Abilities.exists(abilityId) then
			spawnAbilityEffect(abilityId, origin, direction)
		end
	end)

	Net.onClientEvent(Net.Event.DamageDealt, function(amount: number, isCritical: boolean, position: Vector3?)
		if not position then
			return
		end
		spawnDamageLabel(position, amount, isCritical == true)

		-- A blade that lands throws sparks. Drawn off the damage report rather
		-- than off the swing, so it happens where the server says the hit was
		-- -- the client never has to guess at a contact point, and a swing
		-- that connects with nothing correctly produces nothing.
		local weaponId = ServiceLoader.get("ClientState").equippedWeapon()
		if not weaponId or not Weapons.exists(weaponId) then
			return
		end
		local weapon = Weapons.get(weaponId)
		if weapon.class ~= "Blaster" then
			local tint = WeaponModel.tintOf(player.Character)
			spawnImpact(position, Vector3.new(0, 1, 0), tint or weapon.boltColor or Palette.SaberBlue)
		end
	end)
end

return EffectsController
