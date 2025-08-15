-- MonetizationManager.lua
-- Manages all monetization features in STAR WARS: GALACTIC EMPIRE

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

local MonetizationManager = {}
MonetizationManager.__index = MonetizationManager

-- VIP Pass Configuration
local VIP_PASSES = {
    BasicVIP = {
        id = 123456789, -- Replace with actual product ID
        name = "Basic VIP",
        price = 100, -- Robux
        duration = 30, -- days
        benefits = {
            "2x Experience gain",
            "Access to VIP areas",
            "Custom character colors",
            "Daily VIP bonus (100 credits)",
            "Faster hyperspace travel"
        },
        icon = "🌟"
    },
    PremiumVIP = {
        id = 123456790,
        name = "Premium VIP",
        price = 250,
        duration = 30,
        benefits = {
            "3x Experience gain",
            "Access to all VIP areas",
            "Premium character customization",
            "Daily VIP bonus (250 credits)",
            "Instant hyperspace travel",
            "Exclusive ship skins",
            "Priority server access"
        },
        icon = "💎"
    },
    UltimateVIP = {
        id = 123456791,
        name = "Ultimate VIP",
        price = 500,
        duration = 30,
        benefits = {
            "5x Experience gain",
            "Access to all areas",
            "Ultimate character customization",
            "Daily VIP bonus (500 credits)",
            "Instant everything",
            "All exclusive content",
            "VIP server access",
            "Personal assistant droid"
        },
        icon = "👑"
    }
}

-- Battle Pass Configuration
local BATTLE_PASS = {
    id = 123456792,
    name = "Season 1: Rise of the Empire",
    price = 150,
    duration = 90, -- days
    tiers = 100,
    freeRewards = {
        [5] = {type = "Credits", amount = 100},
        [10] = {type = "ShipSkin", item = "Rustic Paint Job"},
        [15] = {type = "Credits", amount = 200},
        [20] = {type = "Weapon", item = "Basic Blaster"},
        [25] = {type = "Credits", amount = 300},
        [30] = {type = "CharacterSkin", item = "Scavenger Outfit"},
        [35] = {type = "Credits", amount = 400},
        [40] = {type = "ShipSkin", item = "Battle Worn"},
        [45] = {type = "Credits", amount = 500},
        [50] = {type = "Weapon", item = "Heavy Blaster"},
        [75] = {type = "CharacterSkin", item = "Elite Armor"},
        [100] = {type = "LegendaryShip", item = "Millennium Falcon"}
    },
    premiumRewards = {
        [1] = {type = "VIPStatus", duration = 7},
        [5] = {type = "Credits", amount = 500},
        [10] = {type = "ExclusiveShipSkin", item = "Imperial Gold"},
        [15] = {type = "Credits", amount = 750},
        [20] = {type = "PremiumWeapon", item = "Lightsaber"},
        [25] = {type = "Credits", amount = 1000},
        [30] = {type = "ExclusiveCharacterSkin", item = "Sith Lord"},
        [35] = {type = "Credits", amount = 1250},
        [40] = {type = "ExclusiveShipSkin", item = "Rebel Blue"},
        [45] = {type = "Credits", amount = 1500},
        [50] = {type = "PremiumWeapon", item = "Heavy Turbolaser"},
        [75] = {type = "ExclusiveCharacterSkin", item = "Jedi Master"},
        [100] = {type = "LegendaryShip", item = "Death Star"}
    }
}

-- Premium Currency (Galactic Credits)
local PREMIUM_CURRENCY = {
    name = "Galactic Credits",
    symbol = "GC",
    exchangeRate = 10, -- 1 Robux = 10 Galactic Credits
    packages = {
        {id = 123456793, name = "Starter Pack", price = 50, amount = 500},
        {id = 123456794, name = "Standard Pack", price = 100, amount = 1200},
        {id = 123456795, name = "Premium Pack", price = 250, amount = 3500},
        {id = 123456796, name = "Ultimate Pack", price = 500, amount = 8000}
    }
}

-- In-Game Store Items
local STORE_ITEMS = {
    -- Character Customization
    CharacterSkins = {
        {id = "stormtrooper", name = "Stormtrooper Armor", price = 100, category = "Empire"},
        {id = "jedi", name = "Jedi Robes", price = 150, category = "Rebel"},
        {id = "bountyhunter", name = "Bounty Hunter Gear", price = 200, category = "Neutral"},
        {id = "sith", name = "Sith Armor", price = 300, category = "Empire"},
        {id = "smuggler", name = "Smuggler Outfit", price = 120, category = "Neutral"}
    },
    
    -- Ship Skins
    ShipSkins = {
        {id = "empire_gold", name = "Imperial Gold", price = 250, category = "Empire"},
        {id = "rebel_blue", name = "Rebel Blue", price = 250, category = "Rebel"},
        {id = "neutral_rust", name = "Rustic", price = 200, category = "Neutral"},
        {id = "chrome", name = "Chrome Finish", price = 500, category = "All"},
        {id = "neon", name = "Neon Accents", price = 400, category = "All"}
    },
    
    -- Weapons
    Weapons = {
        {id = "blaster_pistol", name = "Blaster Pistol", price = 150, category = "All"},
        {id = "blaster_rifle", name = "Blaster Rifle", price = 300, category = "All"},
        {id = "lightsaber", name = "Lightsaber", price = 1000, category = "Force Users"},
        {id = "heavy_blaster", name = "Heavy Blaster", price = 500, category = "All"},
        {id = "sniper_rifle", name = "Sniper Rifle", price = 400, category = "All"}
    },
    
    -- Boosters
    Boosters = {
        {id = "xp_2x", name = "2x Experience (1 hour)", price = 50, duration = 3600},
        {id = "xp_3x", name = "3x Experience (1 hour)", price = 100, duration = 3600},
        {id = "credits_2x", name = "2x Credits (1 hour)", price = 75, duration = 3600},
        {id = "speed_boost", name = "Speed Boost (30 min)", price = 25, duration = 1800}
    }
}

function MonetizationManager.new()
    local self = setmetatable({}, MonetizationManager)
    
    self.vipPlayers = {}
    self.battlePassOwners = {}
    self.playerCurrencies = {}
    self.purchaseHistory = {}
    self.dailyRewards = {}
    
    -- Initialize data store
    self.dataStore = DataStoreService:GetDataStore("StarWarsMonetization")
    
    return self
end

function MonetizationManager:Initialize()
    print("💰 Initializing Monetization System...")
    
    -- Set up marketplace processing
    self:SetupMarketplaceProcessing()
    
    -- Set up daily rewards
    self:SetupDailyRewards()
    
    -- Set up battle pass progression
    self:SetupBattlePass()
    
    -- Start monetization loop
    self:StartMonetizationLoop()
    
    print("✅ Monetization System initialized!")
end

function MonetizationManager:SetupMarketplaceProcessing()
    -- Process VIP pass purchases
    for passId, passData in pairs(VIP_PASSES) do
        MarketplaceService.PromptProductPurchaseFinished:Connect(function(player, productId, wasPurchased)
            if wasPurchased and productId == passData.id then
                self:ProcessVIPPurchase(player, passData)
            end
        end)
    end
    
    -- Process battle pass purchase
    MarketplaceService.PromptProductPurchaseFinished:Connect(function(player, productId, wasPurchased)
        if wasPurchased and productId == BATTLE_PASS.id then
            self:ProcessBattlePassPurchase(player)
        end
    end)
    
    -- Process premium currency purchases
    for _, package in ipairs(PREMIUM_CURRENCY.packages) do
        MarketplaceService.PromptProductPurchaseFinished:Connect(function(player, productId, wasPurchased)
            if wasPurchased and productId == package.id then
                self:ProcessPremiumCurrencyPurchase(player, package)
            end
        end)
    end
end

function MonetizationManager:ProcessVIPPurchase(player, passData)
    print("🎉 " .. player.Name .. " purchased " .. passData.name .. "!")
    
    -- Grant VIP status
    self:GrantVIPStatus(player, passData)
    
    -- Send confirmation
    self:SendPurchaseConfirmation(player, passData.name, passData.benefits)
    
    -- Track purchase
    self:TrackPurchase(player, "VIP", passData.name, passData.price)
end

function MonetizationManager:GrantVIPStatus(player, passData)
    local playerId = player.UserId
    
    self.vipPlayers[playerId] = {
        passType = passData.name,
        benefits = passData.benefits,
        startDate = tick(),
        endDate = tick() + (passData.duration * 24 * 60 * 60), -- Convert days to seconds
        active = true
    }
    
    -- Apply VIP benefits
    self:ApplyVIPBenefits(player, passData)
    
    -- Save to data store
    self:SaveVIPData(player)
    
    print("🌟 VIP status granted to " .. player.Name .. " for " .. passData.duration .. " days")
end

function MonetizationManager:ApplyVIPBenefits(player, passData)
    -- Apply experience multipliers
    if string.find(passData.name, "Basic") then
        player:SetAttribute("XP_Multiplier", 2)
    elseif string.find(passData.name, "Premium") then
        player:SetAttribute("XP_Multiplier", 3)
    elseif string.find(passData.name, "Ultimate") then
        player:SetAttribute("XP_Multiplier", 5)
    end
    
    -- Grant access to VIP areas
    self:GrantVIPAccess(player, passData)
    
    -- Apply other benefits
    for _, benefit in ipairs(passData.benefits) do
        self:ApplyBenefit(player, benefit)
    end
end

function MonetizationManager:GrantVIPAccess(player, passData)
    -- This would grant access to VIP areas based on pass level
    local accessLevel = 1
    if string.find(passData.name, "Premium") then
        accessLevel = 2
    elseif string.find(passData.name, "Ultimate") then
        accessLevel = 3
    end
    
    player:SetAttribute("VIP_Access_Level", accessLevel)
end

function MonetizationManager:ApplyBenefit(player, benefit)
    -- Apply specific benefits
    if string.find(benefit, "Daily VIP bonus") then
        local amount = tonumber(string.match(benefit, "%d+"))
        if amount then
            self:GrantDailyVIPBonus(player, amount)
        end
    elseif string.find(benefit, "Custom character colors") then
        player:SetAttribute("Custom_Colors", true)
    elseif string.find(benefit, "Exclusive ship skins") then
        player:SetAttribute("Exclusive_Skins", true)
    end
end

function MonetizationManager:ProcessBattlePassPurchase(player)
    print("🎮 " .. player.Name .. " purchased Battle Pass!")
    
    local playerId = player.UserId
    
    self.battlePassOwners[playerId] = {
        startDate = tick(),
        endDate = tick() + (BATTLE_PASS.duration * 24 * 60 * 60),
        currentTier = 1,
        experience = 0,
        active = true
    }
    
    -- Grant immediate premium rewards
    self:GrantBattlePassReward(player, 1, true)
    
    -- Save to data store
    self:SaveBattlePassData(player)
    
    print("🎮 Battle Pass activated for " .. player.Name)
end

function MonetizationManager:GrantBattlePassReward(player, tier, isPremium)
    local rewards = isPremium and BATTLE_PASS.premiumRewards or BATTLE_PASS.freeRewards
    local reward = rewards[tier]
    
    if reward then
        print("🎁 Granting Battle Pass reward: " .. reward.type .. " - " .. (reward.item or reward.amount))
        
        -- Grant the actual reward
        if reward.type == "Credits" then
            self:GrantCredits(player, reward.amount)
        elseif reward.type == "ShipSkin" then
            self:GrantShipSkin(player, reward.item)
        elseif reward.type == "CharacterSkin" then
            self:GrantCharacterSkin(player, reward.item)
        elseif reward.type == "Weapon" then
            self:GrantWeapon(player, reward.item)
        elseif reward.type == "VIPStatus" then
            self:GrantTemporaryVIP(player, reward.duration)
        end
    end
end

function MonetizationManager:ProcessPremiumCurrencyPurchase(player, package)
    print("💎 " .. player.Name .. " purchased " .. package.name .. "!")
    
    local amount = package.amount
    self:GrantPremiumCurrency(player, amount)
    
    -- Send confirmation
    self:SendPurchaseConfirmation(player, package.name, {"+" .. amount .. " Galactic Credits"})
    
    -- Track purchase
    self:TrackPurchase(player, "PremiumCurrency", package.name, package.price)
end

function MonetizationManager:GrantPremiumCurrency(player, amount)
    local playerId = player.UserId
    
    if not self.playerCurrencies[playerId] then
        self.playerCurrencies[playerId] = {
            credits = 0,
            galacticCredits = 0
        }
    end
    
    self.playerCurrencies[playerId].galacticCredits = self.playerCurrencies[playerId].galacticCredits + amount
    
    -- Save to data store
    self:SaveCurrencyData(player)
    
    print("💎 Granted " .. amount .. " Galactic Credits to " .. player.Name)
end

function MonetizationManager:SetupDailyRewards()
    -- Set up daily reward system
    Players.PlayerAdded:Connect(function(player)
        self:InitializeDailyRewards(player)
    end)
end

function MonetizationManager:InitializeDailyRewards(player)
    local playerId = player.UserId
    
    self.dailyRewards[playerId] = {
        lastClaim = 0,
        streak = 0,
        nextReward = 100 -- credits
    }
    
    -- Check if player can claim daily reward
    self:CheckDailyReward(player)
end

function MonetizationManager:CheckDailyReward(player)
    local playerId = player.UserId
    local rewardData = self.dailyRewards[playerId]
    
    if not rewardData then return end
    
    local currentTime = tick()
    local timeSinceLastClaim = currentTime - rewardData.lastClaim
    local dayInSeconds = 24 * 60 * 60
    
    if timeSinceLastClaim >= dayInSeconds then
        -- Player can claim daily reward
        self:OfferDailyReward(player, rewardData)
    end
end

function MonetizationManager:OfferDailyReward(player, rewardData)
    local message = [[
🎁 Daily Reward Available! 🎁

Claim your daily reward to continue your streak!
Current streak: ]] .. rewardData.streak .. [[ days

Click to claim: ]] .. rewardData.nextReward .. [[ credits
    ]]
    
    print("🎁 Daily reward offered to " .. player.Name)
    
    -- This would show a UI prompt to the player
    -- For now, just grant the reward
    self:ClaimDailyReward(player)
end

function MonetizationManager:ClaimDailyReward(player)
    local playerId = player.UserId
    local rewardData = self.dailyRewards[playerId]
    
    if not rewardData then return end
    
    -- Grant credits
    self:GrantCredits(player, rewardData.nextReward)
    
    -- Update streak
    rewardData.streak = rewardData.streak + 1
    rewardData.lastClaim = tick()
    
    -- Increase next reward
    rewardData.nextReward = math.min(1000, rewardData.nextReward + 50)
    
    print("🎁 Daily reward claimed by " .. player.Name .. " (Streak: " .. rewardData.streak .. ")")
end

function MonetizationManager:GrantCredits(player, amount)
    local playerId = player.UserId
    
    if not self.playerCurrencies[playerId] then
        self.playerCurrencies[playerId] = {
            credits = 0,
            galacticCredits = 0
        }
    end
    
    self.playerCurrencies[playerId].credits = self.playerCurrencies[playerId].credits + amount
    
    -- Save to data store
    self:SaveCurrencyData(player)
    
    print("💰 Granted " .. amount .. " credits to " .. player.Name)
end

function MonetizationManager:GrantShipSkin(player, skinName)
    -- This would grant a ship skin to the player
    print("🎨 Granted ship skin: " .. skinName .. " to " .. player.Name)
end

function MonetizationManager:GrantCharacterSkin(player, skinName)
    -- This would grant a character skin to the player
    print("👕 Granted character skin: " .. skinName .. " to " .. player.Name)
end

function MonetizationManager:GrantWeapon(player, weaponName)
    -- This would grant a weapon to the player
    print("🔫 Granted weapon: " .. weaponName .. " to " .. player.Name)
end

function MonetizationManager:GrantTemporaryVIP(player, duration)
    -- This would grant temporary VIP status
    print("🌟 Granted temporary VIP status to " .. player.Name .. " for " .. duration .. " days")
end

function MonetizationManager:SetupBattlePass()
    -- Set up battle pass progression system
    RunService.Heartbeat:Connect(function(deltaTime)
        self:UpdateBattlePassProgression(deltaTime)
    end)
end

function MonetizationManager:UpdateBattlePassProgression(deltaTime)
    -- Update battle pass progression for all owners
    for playerId, passData in pairs(self.battlePassOwners) do
        if passData.active then
            local player = Players:GetPlayerByUserId(playerId)
            if player then
                -- Check for experience gains and tier ups
                self:CheckBattlePassTierUp(player, passData)
            end
        end
    end
end

function MonetizationManager:CheckBattlePassTierUp(player, passData)
    -- This would check if the player has gained enough experience for the next tier
    -- For now, just a placeholder
end

function MonetizationManager:StartMonetizationLoop()
    RunService.Heartbeat:Connect(function(deltaTime)
        self:UpdateVIPStatus(deltaTime)
        self:UpdateBattlePassExpiry(deltaTime)
    end)
end

function MonetizationManager:UpdateVIPStatus(deltaTime)
    local currentTime = tick()
    
    for playerId, vipData in pairs(self.vipPlayers) do
        if vipData.active and currentTime >= vipData.endDate then
            -- VIP status expired
            self:ExpireVIPStatus(playerId)
        end
    end
end

function MonetizationManager:ExpireVIPStatus(playerId)
    local player = Players:GetPlayerByUserId(playerId)
    if player then
        print("⏰ VIP status expired for " .. player.Name)
        
        -- Remove VIP benefits
        player:SetAttribute("XP_Multiplier", 1)
        player:SetAttribute("VIP_Access_Level", 0)
        player:SetAttribute("Custom_Colors", false)
        player:SetAttribute("Exclusive_Skins", false)
        
        -- Send expiration notification
        self:SendVIPExpirationNotification(player)
    end
    
    -- Remove from VIP players
    self.vipPlayers[playerId] = nil
end

function MonetizationManager:UpdateBattlePassExpiry(deltaTime)
    local currentTime = tick()
    
    for playerId, passData in pairs(self.battlePassOwners) do
        if passData.active and currentTime >= passData.endDate then
            -- Battle pass expired
            self:ExpireBattlePass(playerId)
        end
    end
end

function MonetizationManager:ExpireBattlePass(playerId)
    local player = Players:GetPlayerByUserId(playerId)
    if player then
        print("⏰ Battle Pass expired for " .. player.Name)
        
        -- Send expiration notification
        self:SendBattlePassExpirationNotification(player)
    end
    
    -- Remove from battle pass owners
    self.battlePassOwners[playerId] = nil
end

function MonetizationManager:SendPurchaseConfirmation(player, itemName, benefits)
    local message = [[
✅ Purchase Successful! ✅

Item: ]] .. itemName .. [[

Benefits:
    ]]
    
    for _, benefit in ipairs(benefits) do
        message = message .. "• " .. benefit .. "\n"
    end
    
    print("📨 Purchase confirmation sent to " .. player.Name)
end

function MonetizationManager:SendVIPExpirationNotification(player)
    local message = [[
⏰ VIP Status Expired ⏰

Your VIP benefits have expired.
Renew now to continue enjoying exclusive perks!
    ]]
    
    print("📨 VIP expiration notification sent to " .. player.Name)
end

function MonetizationManager:SendBattlePassExpirationNotification(player)
    local message = [[
⏰ Battle Pass Expired ⏰

Your Battle Pass has expired.
Purchase the new season to continue your journey!
    ]]
    
    print("📨 Battle Pass expiration notification sent to " .. player.Name)
end

function MonetizationManager:TrackPurchase(player, category, itemName, price)
    local playerId = player.UserId
    
    if not self.purchaseHistory[playerId] then
        self.purchaseHistory[playerId] = {}
    end
    
    table.insert(self.purchaseHistory[playerId], {
        category = category,
        item = itemName,
        price = price,
        timestamp = tick()
    })
    
    print("📊 Purchase tracked: " .. category .. " - " .. itemName .. " for " .. price .. " Robux")
end

-- Data persistence functions
function MonetizationManager:SaveVIPData(player)
    -- Save VIP data to data store
    local success, err = pcall(function()
        self.dataStore:SetAsync("VIP_" .. player.UserId, self.vipPlayers[player.UserId])
    end)
    
    if not success then
        warn("Failed to save VIP data for " .. player.Name .. ": " .. err)
    end
end

function MonetizationManager:SaveBattlePassData(player)
    -- Save battle pass data to data store
    local success, err = pcall(function()
        self.dataStore:SetAsync("BattlePass_" .. player.UserId, self.battlePassOwners[player.UserId])
    end)
    
    if not success then
        warn("Failed to save Battle Pass data for " .. player.Name .. ": " .. err)
    end
end

function MonetizationManager:SaveCurrencyData(player)
    -- Save currency data to data store
    local success, err = pcall(function()
        self.dataStore:SetAsync("Currency_" .. player.UserId, self.playerCurrencies[player.UserId])
    end)
    
    if not success then
        warn("Failed to save currency data for " .. player.Name .. ": " .. err)
    end
end

-- Return the MonetizationManager class
return MonetizationManager 