-- GameManager.lua
-- Main game management script for STAR WARS: GALACTIC EMPIRE

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameManager = {}
GameManager.__index = GameManager

-- Game Configuration
local GAME_CONFIG = {
    MAX_PLAYERS = 100,
    PLANET_TRANSITION_TIME = 3,
    SPAWN_HEALTH = 100,
    SPAWN_CREDITS = 1000,
    AUTO_SAVE_INTERVAL = 60, -- seconds
    FACTION_CHANGE_COOLDOWN = 300 -- seconds
}

-- Planet Data
local PLANETS = {
    Coruscant = {
        name = "Coruscant",
        description = "The capital of the Galactic Empire",
        faction = "Empire",
        spawnPoint = Vector3.new(0, 100, 0),
        atmosphere = "Urban",
        gravity = 1.0,
        weather = "Clear",
        resources = {"Credits", "Technology", "Information"},
        npcCount = 50,
        dangerLevel = "Low"
    },
    Tatooine = {
        name = "Tatooine",
        description = "A harsh desert world",
        faction = "Neutral",
        spawnPoint = Vector3.new(1000, 50, 1000),
        atmosphere = "Desert",
        gravity = 0.8,
        weather = "Hot",
        resources = {"Water", "Spice", "Junk"},
        npcCount = 30,
        dangerLevel = "Medium"
    },
    Hoth = {
        name = "Hoth",
        description = "Frozen rebel base world",
        faction = "Rebel",
        spawnPoint = Vector3.new(-1000, 50, -1000),
        atmosphere = "Ice",
        gravity = 1.2,
        weather = "Cold",
        resources = {"Ice", "Minerals", "Technology"},
        npcCount = 25,
        dangerLevel = "High"
    }
}

function GameManager.new()
    local self = setmetatable({}, GameManager)
    
    self.players = {}
    self.factions = {
        Empire = {members = {}, territory = {}, influence = 100},
        Rebel = {members = {}, territory = {}, influence = 100},
        Neutral = {members = {}, territory = {}, influence = 100}
    }
    self.currentPlanet = "Coruscant"
    self.gameTime = 0
    self.events = {}
    
    return self
end

function GameManager:Initialize()
    print("🚀 Initializing STAR WARS: GALACTIC EMPIRE...")
    
    -- Set up player joining
    Players.PlayerAdded:Connect(function(player)
        self:PlayerJoined(player)
    end)
    
    -- Set up player leaving
    Players.PlayerRemoving:Connect(function(player)
        self:PlayerLeft(player)
    end)
    
    -- Start game loop
    self:StartGameLoop()
    
    -- Initialize planets
    self:InitializePlanets()
    
    print("✅ Game initialization complete!")
end

function GameManager:PlayerJoined(player)
    print("👤 Player joined: " .. player.Name)
    
    -- Create player data
    local playerData = {
        player = player,
        health = GAME_CONFIG.SPAWN_HEALTH,
        credits = 50000, -- Give players plenty of credits for testing
        faction = "Neutral",
        rank = 1,
        experience = 0,
        currentPlanet = "Coruscant",
        lastFactionChange = 0,
        inventory = {},
        skills = {
            combat = 1,
            piloting = 1,
            engineering = 1,
            diplomacy = 1
        }
    }
    
    self.players[player.UserId] = playerData
    
    -- Spawn player
    self:SpawnPlayer(player, "Coruscant")
    
    -- Send welcome message
    self:SendWelcomeMessage(player)
    
    -- Set player attributes for easy access
    player:SetAttribute("Credits", playerData.credits)
    player:SetAttribute("Faction", playerData.faction)
    player:SetAttribute("Rank", playerData.rank)
    
    print("💰 " .. player.Name .. " starts with " .. playerData.credits .. " credits for testing!")
end

function GameManager:PlayerLeft(player)
    print("👋 Player left: " .. player.Name)
    
    -- Save player data
    self:SavePlayerData(player)
    
    -- Remove from players list
    self.players[player.UserId] = nil
    
    -- Remove from faction
    local playerData = self.players[player.UserId]
    if playerData and playerData.faction then
        self:RemovePlayerFromFaction(player, playerData.faction)
    end
end

function GameManager:SpawnPlayer(player, planetName)
    local planet = PLANETS[planetName]
    if not planet then
        planetName = "Coruscant"
        planet = PLANETS[planetName]
    end
    
    local spawnPoint = planet.spawnPoint
    local character = player.Character or player.CharacterAdded:Wait()
    
    if character and character:FindFirstChild("HumanoidRootPart") then
        character.HumanoidRootPart.CFrame = CFrame.new(spawnPoint)
        
        -- Set player stats based on planet
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.Health = GAME_CONFIG.SPAWN_HEALTH
            humanoid.WalkSpeed = 16 * (1 / planet.gravity)
            humanoid.JumpPower = 50 * (1 / planet.gravity)
        end
        
        -- Update current planet
        if self.players[player.UserId] then
            self.players[player.UserId].currentPlanet = planetName
        end
        
        print("📍 Spawned " .. player.Name .. " on " .. planetName)
    end
end

function GameManager:SendWelcomeMessage(player)
    local message = [[
🌟 Welcome to STAR WARS: GALACTIC EMPIRE! 🌟

You are now a citizen of the galaxy. Choose your path:
⚔️ Join the Galactic Empire
🛡️ Fight for the Rebel Alliance  
🎭 Remain neutral as a bounty hunter or trader

Use /help for commands, /factions for faction info.
May the Force be with you!
    ]]
    
    -- This would be sent through a RemoteEvent to the client
    print("📨 Welcome message sent to " .. player.Name)
end

function GameManager:InitializePlanets()
    print("🌍 Initializing planets...")
    
    for planetName, planetData in pairs(PLANETS) do
        print("  - " .. planetName .. ": " .. planetData.description)
        -- Here you would create the actual planet terrain and structures
    end
end

function GameManager:StartGameLoop()
    RunService.Heartbeat:Connect(function(deltaTime)
        self.gameTime = self.gameTime + deltaTime
        
        -- Auto-save every interval
        if self.gameTime % GAME_CONFIG.AUTO_SAVE_INTERVAL < deltaTime then
            self:AutoSave()
        end
        
        -- Update world events
        self:UpdateWorldEvents(deltaTime)
        
        -- Update faction influence
        self:UpdateFactionInfluence(deltaTime)
    end)
end

function GameManager:UpdateWorldEvents(deltaTime)
    -- Dynamic world events would be implemented here
    -- Such as random encounters, faction invasions, etc.
end

function GameManager:UpdateFactionInfluence(deltaTime)
    -- Faction influence would change based on player actions
    -- Territory control, successful missions, etc.
end

function GameManager:AutoSave()
    print("💾 Auto-saving game data...")
    
    for userId, playerData in pairs(self.players) do
        self:SavePlayerData(playerData.player)
    end
end

function GameManager:SavePlayerData(player)
    -- Player data saving would be implemented here
    -- Using DataStore service for persistence
end

function GameManager:RemovePlayerFromFaction(player, factionName)
    local faction = self.factions[factionName]
    if faction then
        for i, member in ipairs(faction.members) do
            if member == player.UserId then
                table.remove(faction.members, i)
                break
            end
        end
    end
end

-- Return the GameManager class
return GameManager 