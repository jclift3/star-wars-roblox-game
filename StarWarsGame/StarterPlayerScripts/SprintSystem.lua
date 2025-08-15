-- Sprint System for STAR WARS: GALACTIC EMPIRE
-- Client script for sprint functionality

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = nil
local humanoid = nil

-- Sprint configuration
local SPRINT_SPEED_MULTIPLIER = 2.0
local NORMAL_SPEED = 16
local SPRINT_SPEED = NORMAL_SPEED * SPRINT_SPEED_MULTIPLIER

local isSprinting = false

-- Function to handle sprint
local function HandleSprint(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        if input.State == Enum.UserInputState.Begin then
            -- Start sprinting
            if humanoid then
                isSprinting = true
                humanoid.WalkSpeed = SPRINT_SPEED
                print("🏃 Sprint activated! Speed: " .. SPRINT_SPEED)
            end
        elseif input.State == Enum.UserInputState.End then
            -- Stop sprinting
            if humanoid then
                isSprinting = false
                humanoid.WalkSpeed = NORMAL_SPEED
                print("🚶 Sprint deactivated! Speed: " .. NORMAL_SPEED)
            end
        end
    end
end

-- Function to setup character
local function SetupCharacter(newCharacter)
    character = newCharacter
    humanoid = character:WaitForChild("Humanoid")
    
    -- Reset sprint state
    isSprinting = false
    humanoid.WalkSpeed = NORMAL_SPEED
    
    print("🔄 Character loaded - Sprint system ready!")
end

-- Connect input events
UserInputService.InputBegan:Connect(HandleSprint)
UserInputService.InputEnded:Connect(HandleSprint)

-- Handle character respawning
player.CharacterAdded:Connect(SetupCharacter)

-- Setup initial character if it already exists
if player.Character then
    SetupCharacter(player.Character)
end

-- Initialize sprint system
print("🏃 Sprint System loaded! Hold SHIFT to sprint!")
print("💡 Sprint speed: " .. SPRINT_SPEED .. " (Normal: " .. NORMAL_SPEED .. ")")

-- Test sprint system
wait(2)
print("🧪 Sprint system test: Press SHIFT while moving to test sprint!") 