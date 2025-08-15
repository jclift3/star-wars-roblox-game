-- 00_Main.lua
-- Fixed version with correct paths for ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

print("🚀 STAR WARS: GALACTIC EMPIRE - Server Starting...")
print("=" .. string.rep("=", 50))

-- DEBUG: Let's see what's actually in script.Parent
print("🔍 DEBUG: script.Parent = " .. tostring(script.Parent))
print("🔍 DEBUG: script.Parent.Name = " .. tostring(script.Parent.Name))
print("🔍 DEBUG: script.Parent.Parent = " .. tostring(script.Parent.Parent))
print("🔍 DEBUG: script.Parent.Parent.Name = " .. tostring(script.Parent.Parent.Name))

-- List all children of script.Parent to see what's actually there
print("🔍 DEBUG: Contents of script.Parent:")
for _, child in pairs(script.Parent:GetChildren()) do
    print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
end

-- Function to safely require a module using correct paths
local function SafeRequire(modulePath, moduleName)
    print("🔍 DEBUG: Attempting to require: " .. tostring(modulePath))
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

-- DEBUG: Let's see what's actually in each folder
print("🔍 DEBUG: Checking contents of each folder:")
print("🔍 GameManagement folder contents:")
if script.Parent.GameManagement then
    for _, child in pairs(script.Parent.GameManagement:GetChildren()) do
        print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
    end
else
    print("  ❌ GameManagement folder not found!")
end

print("🔍 SpaceshipSystem folder contents:")
if script.Parent.SpaceshipSystem then
    for _, child in pairs(script.Parent.SpaceshipSystem:GetChildren()) do
        print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
    end
else
    print("  ❌ SpaceshipSystem folder not found!")
end

print("🔍 FactionSystem folder contents:")
if script.Parent.FactionSystem then
    for _, child in pairs(script.Parent.FactionSystem:GetChildren()) do
        print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
    end
else
    print("  ❌ FactionSystem folder not found!")
end

-- Load all modules using CORRECT paths to the actual ModuleScripts
local GameManager = SafeRequire(script.Parent.GameManagement.GameManager, "GameManager")
local SpaceshipManager = SafeRequire(script.Parent.SpaceshipSystem.SpaceshipManager, "SpaceshipManager")
local FactionManager = SafeRequire(script.Parent.FactionSystem.FactionManager, "FactionManager")
local MonetizationManager = SafeRequire(script.Parent.MonetizationSystem.MonetizationManager, "MonetizationManager")
local PlanetGenerator = SafeRequire(script.Parent.PlanetGeneration.PlanetGenerator, "PlanetGenerator")
local WorldImporter = SafeRequire(script.Parent.PlanetGeneration.WorldImporter, "WorldImporter")
local SpaceshipSpawner = SafeRequire(script.Parent.SpaceshipSystem.SpaceshipSpawner, "SpaceshipSpawner")
local NPCManager = SafeRequire(script.Parent.NPCSystem.NPCManager, "NPCManager")
local InterPlanetTravel = SafeRequire(script.Parent.TravelSystem.InterPlanetTravel, "InterPlanetTravel")

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
local TestSystem = SafeRequire(script.Parent.TestSystem, "TestSystem")
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

-- Set up reliable chat command system using player.Chatted
print("🔧 Setting up reliable chat command system...")

-- Function to handle chat commands
local function HandleChatCommand(player, message)
    print("🔍 Chat command received: " .. message .. " from " .. player.Name)
    
    local args = {}
    for arg in message:gmatch("%S+") do
        table.insert(args, arg)
    end
    
    local command = args[1]:lower()
    
    if command == "/help" then
        local messageObj = Instance.new("Message")
        messageObj.Text = "🌟 STAR WARS: GALACTIC EMPIRE - HELP 🌟\n\nUse these commands in chat:\n/travel [planet] - Travel between planets\n/faction [name] - Join factions\n/ship [type] - Get spaceships\n/credits - Check balance\n/planets - View all planets\n/npcs - View NPC population"
        messageObj.Parent = workspace
        wait(8)
        messageObj:Destroy()
        
        print("📚 Help sent to " .. player.Name)
        
    elseif command == "/travel" then
        local destinationPlanet = args[2]
        if destinationPlanet then
            -- Actually perform travel
            local character = player.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                local planetPositions = {
                    Coruscant = Vector3.new(0, 5, 0),
                    Tatooine = Vector3.new(1000, 5, 1000),
                    Hoth = Vector3.new(-1000, 5, -1000),
                    Naboo = Vector3.new(0, 5, 2000),
                    Mustafar = Vector3.new(2000, 5, 0),
                    Kamino = Vector3.new(0, 5, -2000)
                }
                
                local destination = planetPositions[destinationPlanet]
                if destination then
                    -- Check if player has enough credits
                    local playerCredits = player:GetAttribute("Credits") or 50000
                    local travelCost = 1000
                    
                    if playerCredits >= travelCost then
                        -- Deduct credits and teleport
                        player:SetAttribute("Credits", playerCredits - travelCost)
                        
                        -- Teleport player
                        character.HumanoidRootPart.CFrame = CFrame.new(destination)
                        
                        local messageObj = Instance.new("Message")
                        messageObj.Text = "🌌 Traveling to " .. destinationPlanet .. "! Cost: " .. travelCost .. " credits. New balance: " .. (playerCredits - travelCost) .. " credits."
                        messageObj.Parent = workspace
                        wait(8)
                        messageObj:Destroy()
                        
                        print("🌌 " .. player.Name .. " traveled to " .. destinationPlanet)
                    else
                        local messageObj = Instance.new("Message")
                        messageObj.Text = "❌ Insufficient credits! You need " .. travelCost .. " credits to travel. You have: " .. playerCredits .. " credits."
                        messageObj.Parent = workspace
                        wait(8)
                        messageObj:Destroy()
                    end
                else
                    local messageObj = Instance.new("Message")
                    messageObj.Text = "❌ Unknown planet: " .. destinationPlanet .. " - Available planets: Coruscant, Tatooine, Hoth, Naboo, Mustafar, Kamino"
                    messageObj.Parent = workspace
                    wait(8)
                    messageObj:Destroy()
                end
            end
        else
            local messageObj = Instance.new("Message")
            messageObj.Text = "❌ Usage: /travel [planet] - Available planets: Coruscant, Tatooine, Hoth, Naboo, Mustafar, Kamino"
            messageObj.Parent = workspace
            wait(8)
            messageObj:Destroy()
        end
        
    elseif command == "/faction" then
        local factionName = args[2]
        if factionName then
            local validFactions = {"Empire", "Rebel", "Neutral"}
            local isValid = false
            for _, faction in ipairs(validFactions) do
                if faction:lower() == factionName:lower() then
                    isValid = true
                    break
                end
            end
            
            if isValid then
                -- Actually join faction
                player:SetAttribute("Faction", factionName)
                
                local messageObj = Instance.new("Message")
                messageObj.Text = "⚔️ " .. player.Name .. " has joined the " .. factionName .. " faction! Welcome to the cause!"
                messageObj.Parent = workspace
                wait(8)
                messageObj:Destroy()
                
                print("⚔️ " .. player.Name .. " joined faction: " .. factionName)
            else
                local messageObj = Instance.new("Message")
                messageObj.Text = "❌ Invalid faction: " .. factionName .. " - Available factions: Empire, Rebel, Neutral"
                messageObj.Parent = workspace
                wait(8)
                messageObj:Destroy()
            end
        else
            local messageObj = Instance.new("Message")
            messageObj.Text = "❌ Usage: /faction [name] - Available factions: Empire, Rebel, Neutral"
            messageObj.Parent = workspace
            wait(8)
            messageObj:Destroy()
        end
        
    elseif command == "ship" then
        local shipType = args[1] or "xwing"
        if shipType == "xwing" then
            -- Redirect to hangar manager instead of creating ship directly
            local message = Instance.new("Message")
            message.Text = "🚀 Visit a hangar manager to get your X-Wing! Use /travel to find planets with hangars."
            message.Parent = player
            wait(8)
            message:Destroy()
        else
            local message = Instance.new("Message")
            message.Text = "🚀 Available ships: xwing. Visit a hangar manager to get one!"
            message.Parent = player
            wait(8)
            message:Destroy()
        end
        
    elseif command == "/credits" then
        local messageObj = Instance.new("Message")
        messageObj.Text = "💰 " .. player.Name .. " has 50000 credits (testing mode)"
        messageObj.Parent = workspace
        wait(8)
        messageObj:Destroy()
        
        print("💰 Credits check by " .. player.Name)
        
    elseif command == "/planets" then
        local messageObj = Instance.new("Message")
        messageObj.Text = "🌍 Available planets: Coruscant, Tatooine, Hoth, Naboo, Mustafar, Kamino - Use /travel [planet] to visit!"
        messageObj.Parent = workspace
        wait(8)
        messageObj:Destroy()
        
        print("🌍 Planets info requested by " .. player.Name)
        
    elseif command == "/npcs" then
        local messageObj = Instance.new("Message")
        messageObj.Text = "👥 NPCs are spawning across all planets! Look for moving characters with different colors."
        messageObj.Parent = workspace
        wait(8)
        messageObj:Destroy()
        
        print("👥 NPCs info requested by " .. player.Name)
        
        -- Actually show NPCs near the player
        local character = player.Character
        if character and character:FindFirstChild("HumanoidRootPart") then
            local playerPos = character.HumanoidRootPart.Position
            
            -- Find NPCs folder
            local npcsFolder = workspace:FindFirstChild("NPCs")
            if npcsFolder then
                local nearbyNPCs = 0
                
                -- Look through all planet NPC folders
                for _, planetFolder in pairs(npcsFolder:GetChildren()) do
                    if planetFolder:IsA("Folder") then
                        for _, npc in pairs(planetFolder:GetChildren()) do
                            if npc:IsA("Model") and npc.PrimaryPart then
                                local distance = (npc.PrimaryPart.Position - playerPos).Magnitude
                                if distance < 500 then -- Within 500 studs
                                    nearbyNPCs = nearbyNPCs + 1
                                    
                                    -- Make NPC more visible by adding a temporary glow
                                    local tempGlow = Instance.new("PointLight")
                                    tempGlow.Color = Color3.fromRGB(255, 255, 0)
                                    tempGlow.Range = 30
                                    tempGlow.Brightness = 1
                                    tempGlow.Parent = npc.PrimaryPart
                                    
                                    -- Remove glow after 10 seconds
                                    spawn(function()
                                        wait(10)
                                        if tempGlow and tempGlow.Parent then
                                            tempGlow:Destroy()
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
                
                -- Show count of nearby NPCs
                local countMessage = Instance.new("Message")
                countMessage.Text = "👥 Found " .. nearbyNPCs .. " NPCs nearby! Look for the glowing yellow indicators above them."
                countMessage.Parent = workspace
                wait(8)
                countMessage:Destroy()
                
                print("👥 Found " .. nearbyNPCs .. " NPCs near " .. player.Name)
            else
                local errorMessage = Instance.new("Message")
                errorMessage.Text = "❌ NPC system not found! Please wait for the game to fully load."
                errorMessage.Parent = workspace
                wait(8)
                errorMessage:Destroy()
            end
        end
    else
        local messageObj = Instance.new("Message")
        messageObj.Text = "❌ Unknown command: " .. command .. " (use /help for commands)"
        messageObj.Parent = workspace
        wait(8)
        messageObj:Destroy()
        
        print("❌ Unknown command: " .. command .. " from " .. player.Name)
    end
end

-- Function to set up chat for a player
local function SetupPlayerChat(player)
    print("🔧 Setting up chat for " .. player.Name)
    
    -- Connect to player's chat events
    player.Chatted:Connect(function(message)
        if message:sub(1, 1) == "/" then
            HandleChatCommand(player, message)
        end
    end)
    
    print("✅ Chat system set up for " .. player.Name)
end

-- Connect to player joining
Players.PlayerAdded:Connect(SetupPlayerChat)

-- Set up chat for existing players (in case script runs after players join)
for _, player in pairs(Players:GetPlayers()) do
    SetupPlayerChat(player)
end

print("✅ Reliable chat command system created!")

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