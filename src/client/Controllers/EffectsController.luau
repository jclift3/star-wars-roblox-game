--!strict
--[[
	EffectsController.luau

	Everything you see when something is shot.

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
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Palette = require(Shared.Config.Palette)
local Weapons = require(Shared.Config.Weapons)

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
]]
function EffectsController.spawnBolt(weaponId: string, origin: Vector3, direction: Vector3)
	local weapon = Weapons.get(weaponId)
	local color = weapon.boltColor or Palette.BlasterRed
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
	Net.onClientEvent(Net.Event.WeaponEffect, function(weaponId: string, origin: Vector3, direction: Vector3)
		if not Weapons.exists(weaponId) then
			return
		end
		if Weapons.get(weaponId).class == "Blaster" then
			EffectsController.spawnBolt(weaponId, origin, direction)
		end
	end)

	Net.onClientEvent(Net.Event.DamageDealt, function(amount: number, isCritical: boolean, position: Vector3?)
		if position then
			spawnDamageLabel(position, amount, isCritical == true)
		end
	end)
end

return EffectsController
