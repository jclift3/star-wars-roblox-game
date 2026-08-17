--!strict
--[[
	AimController.luau

	Shoulder aim. Hold the right mouse button.

	WHY THIS EXISTS
	Reported from play, 2026-08-17: *"I'm not a huge fan of the blaster physics
	and options. I'd think we'd have the ability to have a reticle or other /
	better way to fire."*

	`InputController.aimPoint` has always raycast from the centre of the
	screen, which is the correct thing for a shooter to do -- but nothing ever
	made the centre of the screen mean anything. The mouse was free, the
	character faced wherever it last walked, and the HUD drew a permanent white
	dot in the middle that the player had no reason to believe was where their
	shots went. Three things that each made sense alone and had never been
	introduced to each other.

	So this does not change how firing works. It makes the existing rule
	visible: while the button is held the mouse locks to the centre, the
	character turns to face the camera, the camera moves over the right
	shoulder, and a reticle appears whose size *is* the weapon's cone.

	HELD, NOT TOGGLED
	Aim mode is worse than free-look for everything that is not shooting --
	clicking a crate, talking to a shopkeeper, reading a sign. A held button
	means the player never has to remember which mode they are in, because the
	answer is always "whichever one my finger says".

	NO CUSTOM CAMERA
	`Humanoid.CameraOffset` moves Roblox's own camera and keeps its collision
	handling, its occlusion and its controller support. A hand-written camera
	would have to re-earn all three.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Panels = require(Shared.Core.Panels)
local Weapons = require(Shared.Config.Weapons)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local AimController = {
	name = "AimController",
	-- After InputController, which owns firing. Nothing here reads it, but the
	-- two are a pair and the boot order should say so.
	priority = 22,
}

local player = Players.LocalPlayer

--- Right and up from the character's centre, in studs. A right-handed over-
--- the-shoulder view: far enough that the body is not in front of the target,
--- close enough that the reticle is still roughly where the muzzle points.
local SHOULDER = Vector3.new(2.2, 0.6, 0)

--- How fast the camera slides in and out of the shoulder, in studs per second.
--- Snapping it is disorienting; anything slower feels like the game is
--- deciding whether to let you aim.
local OFFSET_SPEED = 14

--- The reticle's four ticks, in pixels.
local TICK_LENGTH = 8
local TICK_THICKNESS = 2

--- Pixels the ticks sit off centre even for a perfectly accurate weapon, so a
--- lightsaber or a T-21 still reads as a reticle rather than a smudge.
local MIN_GAP = 5

local screen: ScreenGui
local reticle: Frame
local dot: Frame
local ticks: { Frame } = {}

local aiming = false
local currentOffset = Vector3.zero

local function state()
	return ServiceLoader.get("ClientState")
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "AimGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- Under the panels, which are DisplayOrder 10: a reticle drawn over an
	-- open inventory would be pointing at a button.
	screen.DisplayOrder = 5
	screen.Parent = player:WaitForChild("PlayerGui")

	reticle = Instance.new("Frame")
	reticle.Name = "Reticle"
	reticle.AnchorPoint = Vector2.new(0.5, 0.5)
	reticle.Position = UDim2.fromScale(0.5, 0.5)
	reticle.Size = UDim2.fromOffset(1, 1)
	reticle.BackgroundTransparency = 1
	reticle.Visible = false
	reticle.Parent = screen

	dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(3, 3)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BackgroundTransparency = 0.2
	dot.BorderSizePixel = 0
	dot.Parent = reticle

	-- Four ticks, one per compass point, positioned in `setGap` below. Built
	-- as a list because all four move together and only their axis differs.
	for i = 1, 4 do
		local tick = Instance.new("Frame")
		tick.Name = `Tick{i}`
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.BackgroundColor3 = Color3.new(1, 1, 1)
		tick.BackgroundTransparency = 0.3
		tick.BorderSizePixel = 0
		local horizontal = i <= 2
		tick.Size = if horizontal
			then UDim2.fromOffset(TICK_LENGTH, TICK_THICKNESS)
			else UDim2.fromOffset(TICK_THICKNESS, TICK_LENGTH)
		tick.Parent = reticle
		table.insert(ticks, tick)
	end
end

--- Moves the four ticks `gap` pixels off centre.
local function setGap(gap: number)
	ticks[1].Position = UDim2.fromOffset(-gap, 0)
	ticks[2].Position = UDim2.fromOffset(gap, 0)
	ticks[3].Position = UDim2.fromOffset(0, -gap)
	ticks[4].Position = UDim2.fromOffset(0, gap)
end

--------------------------------------------------------------------------------
-- The reticle is the cone
--------------------------------------------------------------------------------

--[[
	How far off centre the ticks belong, for the weapon currently held.

	`WeaponDef.spread` is half the cone in degrees and `CombatService` applies
	it to every shot, so the reticle can be *derived* from it rather than
	guessed at: the ticks sit exactly where a maximally unlucky bolt lands.
	That makes the reticle honest about the difference between a DL-44 and a
	scattergun without anybody maintaining a second table of reticle sizes --
	the same rule the rest of this codebase keeps re-learning.

	The camera's `FieldOfView` is the vertical angle it covers, so the viewport
	height divided by it is pixels per degree.
]]
local function gapForWeapon(camera: Camera): number
	local weaponId = state().equippedWeapon()
	if not weaponId or not Weapons.exists(weaponId) then
		return MIN_GAP
	end
	local spread = Weapons.get(weaponId).spread
	local perDegree = camera.ViewportSize.Y / math.max(1, camera.FieldOfView)
	return MIN_GAP + spread * perDegree
end

--------------------------------------------------------------------------------
-- Aim mode
--------------------------------------------------------------------------------

local function setAiming(value: boolean)
	if aiming == value then
		return
	end
	aiming = value
	reticle.Visible = value

	if not value then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			humanoid.AutoRotate = true
		end
	end
end

--[[
	Holds the aim pose for as long as the button is down.

	`MouseBehavior` is re-asserted every frame rather than set once, because
	Roblox's own camera scripts write to it too -- most visibly when the player
	touches shift-lock or opens the Escape menu, either of which silently hands
	the cursor back mid-fight.
]]
local function onRender(delta: number)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	if not camera or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end

	-- A panel opening mid-aim releases it. Otherwise the mouse stays locked
	-- to the centre of an inventory the player cannot click. Polled rather
	-- than signalled because `Panels` has no signals, and adding one for a
	-- consumer that already runs every frame would be the more code.
	if aiming and Panels.anyOpen() then
		setAiming(false)
	end

	local wanted = if aiming then SHOULDER else Vector3.zero
	currentOffset = currentOffset:Lerp(wanted, math.min(1, delta * OFFSET_SPEED))
	humanoid.CameraOffset = currentOffset

	if not aiming then
		return
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	-- Set here rather than in `setAiming` because the button can go down
	-- during a respawn, when there is no humanoid yet to set it on.
	humanoid.AutoRotate = false
	setGap(gapForWeapon(camera))

	-- Yaw only. Taking the camera's pitch as well would tip the character
	-- over backwards every time the player aimed up at a walkway.
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.001 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function AimController.init()
	build()
end

function AimController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton2 then
			return
		end
		-- Right-clicking a shop row should not lock the cursor to the middle
		-- of the screen the player is trying to read.
		if Panels.anyOpen() then
			return
		end
		setAiming(true)
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			setAiming(false)
		end
	end)

	-- Dying with AutoRotate off would respawn a character that cannot turn.
	player.CharacterAdded:Connect(function()
		setAiming(false)
		currentOffset = Vector3.zero
	end)

	RunService.RenderStepped:Connect(onRender)
end

return AimController
