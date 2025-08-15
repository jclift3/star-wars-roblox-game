-- FactionManager.lua
-- Manages all faction-related functionality in STAR WARS: GALACTIC EMPIRE

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FactionManager = {}
FactionManager.__index = FactionManager

-- Faction Definitions
local FACTIONS = {
    Empire = {
        name = "Galactic Empire",
        description = "Order through strength and discipline",
        color = Color3.fromRGB(255, 0, 0),
        leader = "Emperor Palpatine",
        headquarters = "Coruscant",
        benefits = {
            "Access to Imperial technology",
            "Stormtrooper armor and weapons",
            "Imperial ship discounts",
            "Government contracts and missions",
            "Access to restricted areas"
        },
        ranks = {
            {name = "Recruit", level = 1, benefits = {"Basic Imperial gear"}},
            {name = "Trooper", level = 5, benefits = {"Stormtrooper armor", "Blaster rifle"}},
            {name = "Sergeant", level = 10, benefits = {"Command abilities", "Better weapons"}},
            {name = "Lieutenant", level = 20, benefits = {"Officer uniform", "Command ship access"}},
            {name = "Captain", level = 35, benefits = {"Capital ship command", "Territory control"}},
            {name = "Commander", level = 50, benefits = {"Fleet command", "VIP areas"}},
            {name = "Admiral", level = 75, benefits = {"Full fleet control", "Imperial Council access"}},
            {name = "Grand Admiral", level = 100, benefits = {"Supreme command", "Emperor's favor"}}
        },
        territories = {"Coruscant", "Mustafar", "Kamino"},
        influence = 100,
        maxMembers = 1000
    },
    
    Rebel = {
        name = "Rebel Alliance",
        description = "Freedom and justice for all",
        color = Color3.fromRGB(0, 100, 255),
        leader = "General Leia Organa",
        headquarters = "Hoth",
        benefits = {
            "Access to Rebel technology",
            "Jedi training opportunities",
            "Smuggler connections",
            "Underground missions",
            "Freedom fighter gear"
        },
        ranks = {
            {name = "Recruit", level = 1, benefits = {"Basic Rebel gear"}},
            {name = "Soldier", level = 5, benefits = {"Rebel armor", "Blaster pistol"}},
            {name = "Sergeant", level = 10, benefits = {"Command abilities", "Better weapons"}},
            {name = "Lieutenant", level = 20, benefits = {"Officer uniform", "Mission planning"}},
            {name = "Captain", level = 35, benefits = {"Squad command", "Territory control"}},
            {name = "Commander", level = 50, benefits = {"Base command", "VIP areas"}},
            {name = "General", level = 75, benefits = {"Army command", "Rebel Council access"}},
            {name = "High General", level = 100, benefits = {"Supreme command", "Leia's trust"}}
        },
        territories = {"Hoth", "Naboo", "Yavin 4"},
        influence = 100,
        maxMembers = 1000
    },
    
    Neutral = {
        name = "Independent Factions",
        description = "Profit and survival above all",
        color = Color3.fromRGB(255, 255, 0),
        leader = "Various",
        headquarters = "Tatooine",
        benefits = {
            "Trading opportunities",
            "Bounty hunting contracts",
            "Smuggling routes",
            "Neutral territory access",
            "Flexible alliances"
        },
        ranks = {
            {name = "Freelancer", level = 1, benefits = {"Basic equipment"}},
            {name = "Trader", level = 5, benefits = {"Trading license", "Market access"}},
            {name = "Smuggler", level = 10, benefits = {"Hidden compartments", "Stealth gear"}},
            {name = "Bounty Hunter", level = 20, benefits = {"Tracking equipment", "Bounty contracts"}},
            {name = "Gang Leader", level = 35, benefits = {"Territory control", "Gang members"}},
            {name = "Crime Lord", level = 50, benefits = {"Criminal empire", "VIP areas"}},
            {name = "Underworld King", level = 75, benefits = {"Full control", "Council access"}},
            {name = "Shadow Emperor", level = 100, benefits = {"Supreme power", "Galaxy's fear"}}
        },
        territories = {"Tatooine", "Nar Shaddaa", "Ord Mantell"},
        influence = 100,
        maxMembers = 1000
    }
}

-- Territory Control System
local TERRITORIES = {
    Coruscant = {
        name = "Coruscant",
        owner = "Empire",
        influence = 100,
        resources = {"Credits", "Technology", "Information"},
        strategicValue = 10,
        controlPoints = {},
        lastContested = 0
    },
    Tatooine = {
        name = "Tatooine",
        owner = "Neutral",
        influence = 100,
        resources = {"Water", "Spice", "Junk"},
        strategicValue = 5,
        controlPoints = {},
        lastContested = 0
    },
    Hoth = {
        name = "Hoth",
        owner = "Rebel",
        influence = 100,
        resources = {"Ice", "Minerals", "Technology"},
        strategicValue = 7,
        controlPoints = {},
        lastContested = 0
    }
}

function FactionManager.new()
    local self = setmetatable({}, FactionManager)
    
    self.factionMembers = {}
    self.factionData = {}
    self.territoryControl = {}
    self.factionWars = {}
    self.rankProgress = {}
    
    -- Initialize faction data
    for factionName, factionData in pairs(FACTIONS) do
        self.factionData[factionName] = {
            members = {},
            influence = factionData.influence,
            territories = {},
            treasury = 10000,
            lastUpdate = tick()
        }
    end
    
    return self
end

function FactionManager:Initialize()
    print("⚔️ Initializing Faction System...")
    
    -- Set up territory control
    self:InitializeTerritories()
    
    -- Set up faction events
    self:SetupFactionEvents()
    
    -- Start faction update loop
    self:StartFactionLoop()
    
    print("✅ Faction System initialized!")
end

function FactionManager:InitializeTerritories()
    for territoryName, territoryData in pairs(TERRITORIES) do
        self.territoryControl[territoryName] = {
            owner = territoryData.owner,
            influence = territoryData.influence,
            controlPoints = {},
            lastContested = 0
        }
        
        -- Add territory to faction
        if self.factionData[territoryData.owner] then
            table.insert(self.factionData[territoryData.owner].territories, territoryName)
        end
    end
end

function FactionManager:SetupFactionEvents()
    -- Set up player joining factions
    Players.PlayerAdded:Connect(function(player)
        self:InitializePlayerFaction(player)
    end)
    
    -- Set up player leaving
    Players.PlayerRemoving:Connect(function(player)
        self:PlayerLeftFaction(player)
    end)
end

function FactionManager:InitializePlayerFaction(player)
    self.factionMembers[player.UserId] = {
        faction = "Neutral",
        rank = 1,
        experience = 0,
        joinDate = tick(),
        lastActivity = tick(),
        contributions = 0
    }
    
    self.rankProgress[player.UserId] = {
        combat = 0,
        missions = 0,
        territory = 0,
        social = 0
    }
    
    print("👤 Initialized faction data for " .. player.Name)
end

function FactionManager:JoinFaction(player, factionName)
    local faction = FACTIONS[factionName]
    if not faction then
        return false, "Invalid faction"
    end
    
    local playerData = self.factionMembers[player.UserId]
    if not playerData then
        return false, "Player not initialized"
    end
    
    -- Check if player is already in this faction
    if playerData.faction == factionName then
        return false, "Already in this faction"
    end
    
    -- Check faction capacity
    if #self.factionData[factionName].members >= faction.maxMembers then
        return false, "Faction is full"
    end
    
    -- Remove from current faction
    if playerData.faction ~= "Neutral" then
        self:RemovePlayerFromFaction(player, playerData.faction)
    end
    
    -- Add to new faction
    playerData.faction = factionName
    playerData.rank = 1
    playerData.experience = 0
    playerData.joinDate = tick()
    
    table.insert(self.factionData[factionName].members, player.UserId)
    
    -- Apply faction benefits
    self:ApplyFactionBenefits(player, factionName, 1)
    
    print("✅ " .. player.Name .. " joined " .. factionName)
    
    -- Send welcome message
    self:SendFactionWelcome(player, factionName)
    
    return true, "Successfully joined " .. factionName
end

function FactionManager:RemovePlayerFromFaction(player, factionName)
    local faction = self.factionData[factionName]
    if not faction then return end
    
    -- Remove player from faction members
    for i, memberId in ipairs(faction.members) do
        if memberId == player.UserId then
            table.remove(faction.members, i)
            break
        end
    end
    
    -- Reset player faction data
    local playerData = self.factionMembers[player.UserId]
    if playerData then
        playerData.faction = "Neutral"
        playerData.rank = 1
        playerData.experience = 0
    end
    
    print("👋 " .. player.Name .. " left " .. factionName)
end

function FactionManager:ApplyFactionBenefits(player, factionName, rank)
    local faction = FACTIONS[factionName]
    if not faction then return end
    
    local rankData = faction.ranks[rank]
    if not rankData then return end
    
    print("🎁 Applying " .. factionName .. " rank " .. rank .. " benefits to " .. player.Name)
    
    -- Apply rank-specific benefits
    for _, benefit in ipairs(rankData.benefits) do
        self:GrantBenefit(player, benefit, factionName)
    end
end

function FactionManager:GrantBenefit(player, benefit, factionName)
    -- This would grant the actual benefit to the player
    -- Such as items, abilities, access, etc.
    print("  - Granted: " .. benefit)
end

function FactionManager:SendFactionWelcome(player, factionName)
    local faction = FACTIONS[factionName]
    if not faction then return end
    
    local message = [[
🌟 Welcome to the ]] .. faction.name .. [[! 🌟

]] .. faction.description .. [[

Your journey begins now. Rise through the ranks and prove your worth!
    ]]
    
    print("📨 Faction welcome sent to " .. player.Name)
end

function FactionManager:AddExperience(player, amount, category)
    local playerData = self.factionMembers[player.UserId]
    if not playerData then return end
    
    playerData.experience = playerData.experience + amount
    
    -- Update rank progress
    if self.rankProgress[player.UserId] then
        self.rankProgress[player.UserId][category] = (self.rankProgress[player.UserId][category] or 0) + amount
    end
    
    -- Check for rank up
    self:CheckRankUp(player)
    
    print("⭐ " .. player.Name .. " gained " .. amount .. " " .. category .. " experience")
end

function FactionManager:CheckRankUp(player)
    local playerData = self.factionMembers[player.UserId]
    if not playerData then return end
    
    local faction = FACTIONS[playerData.faction]
    if not faction then return end
    
    local currentRank = playerData.rank
    local nextRank = currentRank + 1
    
    if faction.ranks[nextRank] then
        local requiredExp = faction.ranks[nextRank].level * 100 -- Simple level requirement
        
        if playerData.experience >= requiredExp then
            playerData.rank = nextRank
            playerData.experience = playerData.experience - requiredExp
            
            -- Apply new rank benefits
            self:ApplyFactionBenefits(player, playerData.faction, nextRank)
            
            print("🎉 " .. player.Name .. " ranked up to " .. faction.ranks[nextRank].name .. "!")
            
            -- Send rank up notification
            self:SendRankUpNotification(player, nextRank)
        end
    end
end

function FactionManager:SendRankUpNotification(player, newRank)
    local playerData = self.factionMembers[player.UserId]
    if not playerData then return end
    
    local faction = FACTIONS[playerData.faction]
    if not faction then return end
    
    local rankData = faction.ranks[newRank]
    if not rankData then return end
    
    local message = [[
🎉 CONGRATULATIONS! 🎉

You have been promoted to ]] .. rankData.name .. [[!

New benefits unlocked:
    ]]
    
    for _, benefit in ipairs(rankData.benefits) do
        message = message .. "• " .. benefit .. "\n"
    end
    
    print("📨 Rank up notification sent to " .. player.Name)
end

function FactionManager:StartFactionLoop()
    RunService.Heartbeat:Connect(function(deltaTime)
        self:UpdateFactionInfluence(deltaTime)
        self:UpdateTerritoryControl(deltaTime)
        self:CheckFactionWars(deltaTime)
    end)
end

function FactionManager:UpdateFactionInfluence(deltaTime)
    -- Update faction influence based on various factors
    for factionName, factionData in pairs(self.factionData) do
        local memberCount = #factionData.members
        local territoryCount = #factionData.territories
        
        -- Influence increases with members and territories
        local influenceGain = (memberCount * 0.1) + (territoryCount * 5)
        factionData.influence = math.min(100, factionData.influence + influenceGain * deltaTime)
        
        factionData.lastUpdate = tick()
    end
end

function FactionManager:UpdateTerritoryControl(deltaTime)
    -- Update territory control and influence
    for territoryName, territoryData in pairs(self.territoryControl) do
        local owner = territoryData.owner
        local faction = self.factionData[owner]
        
        if faction then
            -- Territory influence increases for owner faction
            territoryData.influence = math.min(100, territoryData.influence + 0.1 * deltaTime)
        end
    end
end

function FactionManager:CheckFactionWars(deltaTime)
    -- Check for faction war conditions
    -- This would trigger territory battles, special events, etc.
end

function FactionManager:GetPlayerFaction(player)
    local playerData = self.factionMembers[player.UserId]
    if playerData then
        return playerData.faction
    end
    return "Neutral"
end

function FactionManager:GetPlayerRank(player)
    local playerData = self.factionMembers[player.UserId]
    if playerData then
        return playerData.rank
    end
    return 1
end

function FactionManager:PlayerLeftFaction(player)
    local playerData = self.factionMembers[player.UserId]
    if playerData and playerData.faction ~= "Neutral" then
        self:RemovePlayerFromFaction(player, playerData.faction)
    end
    
    -- Clean up player data
    self.factionMembers[player.UserId] = nil
    self.rankProgress[player.UserId] = nil
end

-- Return the FactionManager class
return FactionManager 