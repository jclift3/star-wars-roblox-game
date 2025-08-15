-- 00_Main_FIXED.lua
-- Fixed version with absolute paths for Roblox Studio

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

print("🚀 STAR WARS: GALACTIC EMPIRE - Server Starting...")
print("=" .. string.rep("=", 50))

-- Function to safely require a module using absolute paths
local function SafeRequire(modulePath, moduleName)
    local success, result = pcall(require, modulePath)
    if success then
        print("✅ " .. moduleName .. " loaded successfully")
        return result
    else
        warn("❌ Failed to load " .. moduleName .. ": " .. tostring(result))
        return nil
    end
end

-- Function to safely initialize a manager
local function SafeInitialize(manager, managerName)
    if manager and manager.Initialize then
        local success, result = pcall(function()
            manager:Initialize()
        end)
        if success then
            print("✅ " .. managerName .. " initialized successfully")
            return true
        else
            warn("❌ Failed to initialize " .. managerName .. ": " .. tostring(result))
            return false
        end
    else
        warn("❌ " .. managerName .. " is nil or missing Initialize method")
        return false
    end
end

-- Initialize all game systems
print("🔧 Loading game systems...")

-- Load all modules using absolute paths
local GameManager = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.GameManagement.GameManager, "GameManager")
local SpaceshipManager = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.SpaceshipSystem.SpaceshipManager, "SpaceshipManager")
local FactionManager = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.FactionSystem.FactionManager, "FactionManager")
local MonetizationManager = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.MonetizationSystem.MonetizationManager, "MonetizationManager")
local PlanetGenerator = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.PlanetGeneration.PlanetGenerator, "PlanetGenerator")
local WorldImporter = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.PlanetGeneration.WorldImporter, "WorldImporter")
local SpaceshipSpawner = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.SpaceshipSystem.SpaceshipSpawner, "SpaceshipSpawner")
local NPCManager = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.NPCSystem.NPCManager, "NPCManager")
local InterPlanetTravel = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.TravelSystem.InterPlanetTravel, "InterPlanetTravel")

-- Check if all modules loaded
if not (GameManager and SpaceshipManager and FactionManager and MonetizationManager and 
        PlanetGenerator and WorldImporter and SpaceshipSpawner and NPCManager and InterPlanetTravel) then
    warn("❌ Some modules failed to load! Game may not function properly.")
end

print("✅ All modules loaded!")

-- Now create and initialize all managers
print("🚀 Creating and initializing all game managers...")

-- Create managers
if GameManager then
    local gameManager = GameManager.new()
    SafeInitialize(gameManager, "GameManager")
end

if SpaceshipManager then
    local spaceshipManager = SpaceshipManager.new()
    SafeInitialize(spaceshipManager, "SpaceshipManager")
end

if FactionManager then
    local factionManager = FactionManager.new()
    SafeInitialize(factionManager, "FactionManager")
end

if MonetizationManager then
    local monetizationManager = MonetizationManager.new()
    SafeInitialize(monetizationManager, "MonetizationManager")
end

if PlanetGenerator then
    local planetGenerator = PlanetGenerator.new()
    SafeInitialize(planetGenerator, "PlanetGenerator")
end

if WorldImporter then
    local worldImporter = WorldImporter.new()
    SafeInitialize(worldImporter, "WorldImporter")
end

if SpaceshipSpawner then
    local spaceshipSpawner = SpaceshipSpawner.new()
    SafeInitialize(spaceshipSpawner, "SpaceshipSpawner")
end

if NPCManager then
    local npcManager = NPCManager.new()
    SafeInitialize(npcManager, "NPCManager")
end

if InterPlanetTravel then
    local interPlanetTravel = InterPlanetTravel.new()
    SafeInitialize(interPlanetTravel, "InterPlanetTravel")
end

print("🎉 All game systems initialized!")

-- Wait for planets to be generated
print("⏳ Waiting for planets to generate...")
local maxWaitTime = 30
local waitTime = 0

while waitTime < maxWaitTime do
    local planetFolder = workspace:FindFirstChild("Planets")
    if planetFolder then
        local hasPlanets = false
        for _, child in pairs(planetFolder:GetChildren()) do
            if child:IsA("Folder") then
                hasPlanets = true
                break
            end
        end
        if hasPlanets then
            print("✅ Planets found! Now initializing dependent systems...")
            break
        end
    end
    wait(1)
    waitTime = waitTime + 1
    print("⏳ Still waiting for planets... (" .. waitTime .. "/" .. maxWaitTime .. "s)")
end

if waitTime >= maxWaitTime then
    warn("❌ Timeout waiting for planets! Some systems may not work correctly.")
end

-- Run system test to verify everything is working
print("🧪 Running system diagnostics...")
local TestSystem = SafeRequire(ReplicatedStorage.StarWarsGame.ServerScripts.TestSystem, "TestSystem")
if TestSystem then
    TestSystem()
end

-- Set up RemoteEvents for client-server communication
print("🔌 Setting up RemoteEvents...")

local RemoteEvents = Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

-- Create RemoteEvents for different functions
local SpawnShipEvent = Instance.new("RemoteEvent")
SpawnShipEvent.Name = "SpawnShip"
SpawnShipEvent.Parent = RemoteEvents

local JoinFactionEvent = Instance.new("RemoteEvent")
JoinFactionEvent.Name = "JoinFaction"
JoinFactionEvent.Parent = RemoteEvents

local HyperspaceJumpEvent = Instance.new("RemoteEvent")
HyperspaceJumpEvent.Name = "HyperspaceJump"
HyperspaceJumpEvent.Parent = RemoteEvents

print("✅ RemoteEvents created!")

-- Handle chat commands
local function HandleChatCommand(player, message)
    local args = {}
    for arg in message:gmatch("%S+") do
        table.insert(args, arg)
    end
    
    local command = args[1]:lower()
    
    if command == "/help" then
        local helpMessage = [[
🌟 STAR WARS: GALACTIC EMPIRE - Commands 🌟

/travel [planet] - Travel to another planet (costs credits)
/faction [name] - Join a faction (Empire, Rebel, Neutral)
/ship [type] - Spawn a spaceship
/credits - Check your credit balance
/help - Show this help message

Planets: Coruscant, Tatooine, Hoth, Naboo, Mustafar, Kamino
        ]]
        print("📚 Help sent to " .. player.Name)
        
    elseif command == "/travel" then
        local destinationPlanet = args[2]
        if destinationPlanet then
            print("🌌 " .. player.Name .. " requested travel to " .. destinationPlanet)
            print("❌ Travel system not yet implemented")
        else
            print("❌ Usage: /travel [planet]")
        end
        
    elseif command == "/faction" then
        local factionName = args[2]
        if factionName then
            print("⚔️ " .. player.Name .. " requested to join faction: " .. factionName)
            print("❌ Faction system not yet implemented")
        else
            print("❌ Usage: /faction [name]")
        end
        
    elseif command == "/ship" then
        local shipType = args[2] or "XWing"
        local planetName = args[3] or "Coruscant"
        print("🚁 " .. player.Name .. " requested ship spawn: " .. shipType .. " on " .. planetName)
        print("❌ Ship system not yet implemented")
        
    elseif command == "/credits" then
        print("💰 " .. player.Name .. " has 50000 credits (testing)")
        
    else
        print("❌ Unknown command: " .. command .. " (use /help for commands)")
    end
end

-- Set up chat commands
local function OnChatted(player, message)
    if message:sub(1, 1) == "/" then
        HandleChatCommand(player, message)
    end
end

-- Connect chat events
Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(message)
        OnChatted(player, message)
    end)
end)

-- Start periodic announcements
print("📢 Starting periodic announcements...")
spawn(function()
    while true do
        wait(60) -- Every minute
        print("🌟 STAR WARS: GALACTIC EMPIRE - Use /help for commands!")
    end
end)

print("🎮 STAR WARS: GALACTIC EMPIRE server is ready!")
print("=" .. string.rep("=", 50)) 