--!strict
--[[
	InputController.luau

	Turns key and mouse input into requests to the server.

	WHAT THIS SENDS
	An origin and a direction, and nothing else. Not a target, not a hit, not a
	damage number. The server re-derives all of that from the player's actual
	equipped weapon (see CombatService). This controller cannot make the player
	stronger, only more responsive.

	WHY IT AIMS WITH A RAYCAST
	Firing straight down the camera's look vector makes shots miss what the
	crosshair is on, because the muzzle is not where the camera is. So the
	client first finds what the crosshair points at, then aims the muzzle at
	that point. The server bounds-checks the origin against the character's
	root, so a fabricated muzzle position buys nothing.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Weapons = require(Shared.Config.Weapons)
local WeaponModel = require(Shared.Rig.WeaponModel)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local InputController = {
	name = "InputController",
	priority = 20,
}

local player = Players.LocalPlayer

-- Fire slightly faster than the weapon allows and the server drops the extra
-- shots. Fire slightly slower and the weapon feels worse than it is. This
-- matches CombatService's grace so the two agree.
local FIRE_RATE_GRACE = 0.06

local holdingFire = false
local sprinting = false
local lastFireAt = 0

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

local function state()
	return ServiceLoader.get("ClientState")
end

local function effects()
	return ServiceLoader.get("EffectsController")
end

--- Where the crosshair is pointing, at most `range` studs away.
local function aimPoint(range: number): Vector3
	local camera = Workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end

	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)

	aimParams.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * range, aimParams)
	return if hit then hit.Position else ray.Origin + ray.Direction * range
end

--- The muzzle, falling back to a point in front of the chest for bare hands.
local function muzzleOrigin(character: Model): Vector3?
	local fromWeapon = WeaponModel.muzzlePosition(character)
	if fromWeapon then
		return fromWeapon
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 0.5, 0)
	end
	return nil
end

local function tryAttack()
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local weaponId = state().equippedWeapon()
	if not weaponId or not Weapons.exists(weaponId) then
		return
	end
	local weapon = Weapons.get(weaponId)

	local now = os.clock()
	if now - lastFireAt < Weapons.cooldown(weaponId) - FIRE_RATE_GRACE then
		return
	end
	lastFireAt = now

	if weapon.class ~= "Blaster" then
		Net.fireServer(Net.Event.SaberSwing)
		return
	end

	local origin = muzzleOrigin(character)
	if not origin then
		return
	end
	local direction = (aimPoint(weapon.range) - origin).Unit

	Net.fireServer(Net.Event.FireWeapon, origin, direction)
	-- Drawn locally on input rather than waiting for the round trip. The server
	-- sends this same effect to everyone else.
	effects().spawnBolt(weaponId, origin, direction)
end

local function setSprinting(on: boolean)
	if sprinting == on then
		return
	end
	sprinting = on
	-- The server decides what sprinting is worth; this is a request only.
	Net.fireServer(Net.Event.SetSprinting, on)
end

function InputController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			holdingFire = true
			tryAttack()
		elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			setSprinting(true)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			holdingFire = false
		elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			setSprinting(false)
		end
	end)

	-- Held input repeats for automatic weapons and for melee, where a held
	-- button reads as a combo. Semi-autos need a fresh click per shot, which
	-- is most of what makes a DL-44 feel different from an E-11.
	RunService.Heartbeat:Connect(function()
		if not holdingFire then
			return
		end
		local weaponId = state().equippedWeapon()
		if not weaponId or not Weapons.exists(weaponId) then
			return
		end
		local weapon = Weapons.get(weaponId)
		if weapon.class ~= "Blaster" or weapon.mode == "Auto" then
			tryAttack()
		end
	end)

	-- Sprinting must not survive death, or the server and client disagree
	-- about the new character's speed.
	player.CharacterAdded:Connect(function()
		holdingFire = false
		if sprinting then
			sprinting = false
			Net.fireServer(Net.Event.SetSprinting, false)
		end
	end)
end

return InputController
