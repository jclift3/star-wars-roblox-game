-- NPCManager.lua
-- Manages all NPCs (Non-Player Characters) across all planets

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local NPCManager = {}
NPCManager.__index = NPCManager

-- NPC configurations for each planet
local NPC_CONFIGS = {
    Coruscant = {
        npcs = {
            {type = "Stormtrooper", count = 15, behavior = "Patrol"},
            {type = "ImperialOfficer", count = 8, behavior = "Stand"},
            {type = "Civilian", count = 25, behavior = "Wander"},
            {type = "Droid", count = 12, behavior = "Work"},
            {type = "Jedi", count = 3, behavior = "Meditate"}
        },
        spawnRadius = 800,
        maxNPCs = 63
    },
    
    Tatooine = {
        npcs = {
            {type = "Jawa", count = 8, behavior = "Scavenge"},
            {type = "TuskenRaider", count = 6, behavior = "Patrol"},
            {type = "MoistureFarmer", count = 10, behavior = "Work"},
            {type = "Smuggler", count = 5, behavior = "Trade"},
            {type = "BountyHunter", count = 3, behavior = "Hunt"}
        },
        spawnRadius = 600,
        maxNPCs = 32
    },
    
    Hoth = {
        npcs = {
            {type = "RebelTrooper", count = 12, behavior = "Patrol"},
            {type = "RebelPilot", count = 6, behavior = "Work"},
            {type = "Wampa", count = 4, behavior = "Hunt"},
            {type = "Tauntaun", count = 8, behavior = "Wander"},
            {type = "MedicalDroid", count = 3, behavior = "Work"}
        },
        spawnRadius = 500,
        maxNPCs = 33
    },
    
    Naboo = {
        npcs = {
            {type = "RoyalGuard", count = 10, behavior = "Patrol"},
            {type = "NabooCitizen", count = 20, behavior = "Wander"},
            {type = "Gungan", count = 8, behavior = "Trade"},
            {type = "Artist", count = 6, behavior = "Work"},
            {type = "Merchant", count = 8, behavior = "Trade"}
        },
        spawnRadius = 400,
        maxNPCs = 52
    },
    
    Mustafar = {
        npcs = {
            {type = "MiningDroid", count = 15, behavior = "Work"},
            {type = "ImperialGuard", count = 8, behavior = "Patrol"},
            {type = "Miner", count = 10, behavior = "Work"},
            {type = "SecurityDroid", count = 6, behavior = "Patrol"},
            {type = "Sith", count = 2, behavior = "Meditate"}
        },
        spawnRadius = 350,
        maxNPCs = 41
    },
    
    Kamino = {
        npcs = {
            {type = "CloneTrooper", count = 20, behavior = "Train"},
            {type = "Kaminoan", count = 8, behavior = "Work"},
            {type = "TrainingDroid", count = 12, behavior = "Train"},
            {type = "MedicalDroid", count = 6, behavior = "Work"},
            {type = "Scientist", count = 5, behavior = "Research"}
        },
        spawnRadius = 250,
        maxNPCs = 51
    }
}

-- NPC type definitions
local NPC_TYPES = {
    -- Imperial Forces
    Stormtrooper = {
        model = "Stormtrooper",
        size = Vector3.new(2, 6, 2),
        color = BrickColor.new("White"),
        health = 100,
        speed = 16,
        weapon = "Blaster",
        faction = "Empire",
        responses = {
            "For the Empire! Move along, citizen.",
            "The Empire brings order to the galaxy. How may I assist you?",
            "Move along, Rebel scum!",
            "The Empire is watching you."
        }
    },
    
    ImperialOfficer = {
        model = "ImperialOfficer",
        size = Vector3.new(2, 6, 2),
        color = BrickColor.new("Dark stone grey"),
        health = 80,
        speed = 14,
        weapon = "Blaster",
        faction = "Empire",
        responses = {
            "The Empire brings order to the galaxy. How may I assist you?",
            "Move along, Rebel scum!",
            "The Empire is watching you."
        }
    },
    
    -- Rebel Forces
    RebelTrooper = {
        model = "RebelTrooper",
        size = Vector3.new(2, 6, 2),
        color = BrickColor.new("Bright blue"),
        health = 100,
        speed = 16,
        weapon = "Blaster",
        faction = "Rebel",
        responses = {
            "The Rebellion needs brave fighters like you. Join us!",
            "Move along, Imperial scum!",
            "The Empire is watching you."
        }
    },
    
    RebelPilot = {
        model = "RebelPilot",
        size = Vector3.new(2, 6, 2),
        color = BrickColor.new("Bright orange"),
        health = 90,
        speed = 18,
        weapon = "Blaster",
        faction = "Rebel",
        responses = {
            "The Rebellion needs brave fighters like you. Join us!",
            "Move along, Imperial scum!",
            "The Empire is watching you."
        }
    },
    
    -- Civilians
    Civilian = {
        model = "Civilian",
        size = Vector3.new(2, 6, 2),
        color = BrickColor.new("Bright green"),
        health = 50,
        speed = 12,
        weapon = "None",
        faction = "Neutral",
        responses = {
            "Welcome to " .. planetName .. "! Business is good these days.",
            "Move along, Rebel scum!",
            "The Empire is watching you."
        }
    },
    
    NabooCitizen = {
        model = "NabooCitizen",
        size = Vector3.new(2, 6, 2),
        color = BrickColor.new("Bright yellow"),
        health = 50,
        speed = 12,
        weapon = "None",
        faction = "Neutral",
        responses = {
            "Welcome to " .. planetName .. "! Business is good these days.",
            "Move along, Rebel scum!",
            "The Empire is watching you."
        }
    },
    
    -- Creatures
    Wampa = {
        model = "Wampa",
        size = Vector3.new(4, 8, 4),
        color = BrickColor.new("White"),
        health = 200,
        speed = 20,
        weapon = "Claws",
        faction = "Neutral",
        responses = {
            "Move along, Rebel scum!",
            "The Empire is watching you."
        }
    },
    
    Tauntaun = {
        model = "Tauntaun",
        size = Vector3.new(3, 6, 3),
        color = BrickColor.new("Light brown"),
        health = 150,
        speed = 25,
        weapon = "Horns",
        faction = "Neutral",
        responses = {
            "Move along, Rebel scum!",
            "The Empire is watching you."
        }
    },
    
    -- Droids
    Droid = {
        model = "Droid",
        size = Vector3.new(2, 4, 2),
        color = BrickColor.new("Dark stone grey"),
        health = 80,
        speed = 10,
        weapon = "Tools",
        faction = "Neutral",
        responses = {
            "Beep boop. I am programmed to assist visitors.",
            "Move along, Rebel scum!",
            "The Empire is watching you."
        }
    },
    
    -- Special Characters
    Jedi = {
        model = "Jedi",
        size = Vector3.new(2, 6, 2),
        color = BrickColor.new("Brown"),
        health = 150,
        speed = 20,
        weapon = "Lightsaber",
        faction = "Rebel",
        responses = {
            "May the Force be with you, young one. The light side calls to you.",
            "Move along, Rebel scum!",
            "The Empire is watching you."
        }
    },
    
    Sith = {
        model = "Sith",
        size = Vector3.new(2, 6, 2),
        color = BrickColor.new("Black"),
        health = 200,
        speed = 22,
        weapon = "Lightsaber",
        faction = "Empire",
        responses = {
            "Power is the only truth. Embrace the dark side.",
            "Move along, Rebel scum!",
            "The Empire is watching you."
        }
    }
}

function NPCManager.new()
    local self = setmetatable({}, NPCManager)
    
    self.activeNPCs = {}
    self.npcFolders = {}
    
    return self
end

function NPCManager:Initialize()
    print("👥 Initializing NPC Manager System...")
    
    -- Create main NPC folder
    self.npcsFolder = Instance.new("Folder")
    self.npcsFolder.Name = "NPCs"
    self.npcsFolder.Parent = Workspace
    
    -- Create planet-specific NPC folders
    self:CreatePlanetNPCFolders()
    
    -- Spawn NPCs for all planets
    self:SpawnAllPlanetNPCs()
    
    -- Start NPC behavior loops
    self:StartNPCBehaviorLoops()
    
    print("✅ NPC Manager System initialized!")
end

function NPCManager:CreatePlanetNPCFolders()
    for planetName, _ in pairs(NPC_CONFIGS) do
        local planetFolder = Instance.new("Folder")
        planetFolder.Name = planetName .. "_NPCs"
        planetFolder.Parent = self.npcsFolder
        
        self.npcFolders[planetName] = planetFolder
    end
end

function NPCManager:SpawnAllPlanetNPCs()
    -- Wait for planets to be generated first
    local maxWaitTime = 30 -- Maximum wait time in seconds
    local waitTime = 0
    
    while waitTime < maxWaitTime do
        local planetFolder = Workspace:FindFirstChild("Planets")
        if planetFolder then
            -- Check if at least one planet exists
            local hasPlanets = false
            for _, child in pairs(planetFolder:GetChildren()) do
                if child:IsA("Folder") then
                    hasPlanets = true
                    break
                end
            end
            
            if hasPlanets then
                print("✅ Planets found! Spawning NPCs...")
                break
            end
        end
        
        wait(1)
        waitTime = waitTime + 1
        print("⏳ Waiting for planets to generate... (" .. waitTime .. "/" .. maxWaitTime .. "s)")
    end
    
    if waitTime >= maxWaitTime then
        warn("❌ Timeout waiting for planets! NPCs may not spawn correctly.")
        return
    end
    
    -- Now spawn NPCs
    for planetName, config in pairs(NPC_CONFIGS) do
        print("👥 Spawning NPCs for " .. planetName .. "...")
        self:SpawnPlanetNPCs(planetName, config)
    end
end

function NPCManager:SpawnPlanetNPCs(planetName, config)
    local planetFolder = self.npcFolders[planetName]
    if not planetFolder then return end
    
    local planetPositions = {
        Coruscant = Vector3.new(0, 0, 0),
        Tatooine = Vector3.new(1000, 0, 1000),
        Hoth = Vector3.new(-1000, 0, -1000),
        Naboo = Vector3.new(0, 0, 2000),
        Mustafar = Vector3.new(2000, 0, 0),
        Kamino = Vector3.new(0, 0, -2000)
    }
    
    local planetPos = planetPositions[planetName] or Vector3.new(0, 0, 0)
    
    print("🌍 Spawning NPCs for " .. planetName .. " at position: " .. tostring(planetPos))
    
    for _, npcConfig in ipairs(config.npcs) do
        for i = 1, npcConfig.count do
            local npc = self:CreateNPC(npcConfig.type, planetName, planetPos)
            if npc then
                npc.Parent = planetFolder
                
                -- Store NPC data
                table.insert(self.activeNPCs, {
                    npc = npc,
                    planet = planetName,
                    type = npcConfig.type,
                    behavior = npcConfig.behavior,
                    spawnTime = tick()
                })
                
                print("🤖 Created NPC: " .. npc.Name .. " at " .. tostring(npc.PrimaryPart.Position))
            end
            
            wait(0.1) -- Small delay between spawns
        end
    end
    
    print("✅ Spawned " .. #config.npcs .. " NPC types for " .. planetName)
end

function NPCManager:CreateNPC(npcType, planetName, planetPos)
    local npcData = NPC_TYPES[npcType]
    if not npcData then return end
    
    -- Create NPC model based on type
    local npc
    if npcType == "Stormtrooper" then
        npc = self:CreateStormtrooperModel()
    elseif npcType == "ImperialOfficer" then
        npc = self:CreateImperialOfficerModel()
    elseif npcType == "RebelTrooper" then
        npc = self:CreateRebelTrooperModel()
    elseif npcType == "Jedi" then
        npc = self:CreateJediModel()
    elseif npcType == "Sith" then
        npc = self:CreateSithModel()
    elseif npcType == "Civilian" then
        npc = self:CreateCivilianModel()
    elseif npcType == "Droid" then
        npc = self:CreateDroidModel()
    else
        npc = self:CreateBasicNPCModel()
    end
    
    if not npc then return end
    
    -- Position NPC on the planet
    local spawnRadius = planetPos.Magnitude * 0.3  -- Spawn within 30% of planet radius
    local spawnAngle = math.random() * math.pi * 2
    local spawnDistance = math.random() * spawnRadius
    
    local spawnPos = Vector3.new(
        planetPos.X + math.cos(spawnAngle) * spawnDistance,
        planetPos.Y + 5,  -- Lower Y position for ground-level spawning
        planetPos.Z + math.sin(spawnAngle) * spawnDistance
    )
    
    npc:SetPrimaryPartCFrame(CFrame.new(spawnPos))
    
    -- Add interaction prompt for NPCs
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "TalkToNPC"
    prompt.ObjectText = npcType
    prompt.ActionText = "Talk"
    prompt.MaxActivationDistance = 8
    prompt.HoldDuration = 0.5
    prompt.Parent = npc.PrimaryPart
    
    -- Connect prompt to NPC interaction
    prompt.Triggered:Connect(function(player)
        self:HandleNPCInteraction(player, npc, npcData, planetName)
    end)
    
    -- Add behavior script
    self:AddNPCBehavior(npc, npcData.behavior)
    
    print("🤖 Created NPC " .. npc.Name .. " at position " .. tostring(npc.PrimaryPart.Position))
    return npc
end

function NPCManager:CreateStormtrooperModel()
    local npc = Instance.new("Model")
    npc.Name = "Stormtrooper_" .. tick()
    
    -- Create main body (this will be the primary part)
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(2, 3, 1)
    body.Material = Enum.Material.Plastic
    body.Color = Color3.fromRGB(255, 255, 255)
    body.Anchored = false  -- IMPORTANT: Must be false for welding to work
    body.Parent = npc
    
    -- Create helmet
    local helmet = Instance.new("Part")
    helmet.Name = "Helmet"
    helmet.Size = Vector3.new(2.2, 1.5, 1.2)
    helmet.Material = Enum.Material.Plastic
    helmet.Color = Color3.fromRGB(255, 255, 255)
    helmet.Anchored = false  -- Must be false for welding
    helmet.Parent = npc
    
    -- Create arms
    local leftArm = Instance.new("Part")
    leftArm.Name = "LeftArm"
    leftArm.Size = Vector3.new(0.8, 2.5, 0.8)
    leftArm.Material = Enum.Material.Plastic
    leftArm.Color = Color3.fromRGB(255, 255, 255)
    leftArm.Anchored = false  -- Must be false for welding
    leftArm.Parent = npc
    
    local rightArm = Instance.new("Part")
    rightArm.Name = "RightArm"
    rightArm.Size = Vector3.new(0.8, 2.5, 0.8)
    rightArm.Material = Enum.Material.Plastic
    rightArm.Color = Color3.fromRGB(255, 255, 255)
    rightArm.Anchored = false  -- Must be false for welding
    rightArm.Parent = npc
    
    -- Create legs
    local leftLeg = Instance.new("Part")
    leftLeg.Name = "LeftLeg"
    leftLeg.Size = Vector3.new(1, 2.5, 1)
    leftLeg.Material = Enum.Material.Plastic
    leftLeg.Color = Color3.fromRGB(255, 255, 255)
    leftLeg.Anchored = false  -- Must be false for welding
    leftLeg.Parent = npc
    
    local rightLeg = Instance.new("Part")
    rightLeg.Name = "RightLeg"
    rightLeg.Size = Vector3.new(1, 2.5, 1)
    rightLeg.Material = Enum.Material.Plastic
    rightLeg.Color = Color3.fromRGB(255, 255, 255)
    rightLeg.Anchored = false  -- Must be false for welding
    rightLeg.Parent = npc
    
    -- WELD ALL PARTS TOGETHER USING PROPER ROBOX WELD SYSTEM
    -- Create Weld objects (not WeldConstraint) to connect parts
    local helmetWeld = Instance.new("Weld")
    helmetWeld.Part0 = body
    helmetWeld.Part1 = helmet
    helmetWeld.C0 = CFrame.new(0, 2.5, 0)
    helmetWeld.Parent = body
    
    local leftArmWeld = Instance.new("Weld")
    leftArmWeld.Part0 = body
    leftArmWeld.Part1 = leftArm
    leftArmWeld.C0 = CFrame.new(-1.75, 0, 0)
    leftArmWeld.Parent = body
    
    local rightArmWeld = Instance.new("Weld")
    rightArmWeld.Part0 = body
    rightArmWeld.Part1 = rightArm
    rightArmWeld.C0 = CFrame.new(1.75, 0, 0)
    rightArmWeld.Parent = body
    
    local leftLegWeld = Instance.new("Weld")
    leftLegWeld.Part0 = body
    leftLegWeld.Part1 = leftLeg
    leftLegWeld.C0 = CFrame.new(-0.5, -2.75, 0)
    leftLegWeld.Parent = body
    
    local rightLegWeld = Instance.new("Weld")
    rightLegWeld.Part0 = body
    rightLegWeld.Part1 = rightLeg
    rightLegWeld.C0 = CFrame.new(0.5, -2.75, 0)
    rightLegWeld.Parent = body
    
    -- Set body as primary part
    npc.PrimaryPart = body
    
    print("✅ Stormtrooper created with " .. #npc:GetChildren() .. " properly welded parts")
    return npc
end

function NPCManager:CreateImperialOfficerModel()
    -- Create Imperial Officer uniform
    local uniform = Instance.new("Part")
    uniform.Name = "Uniform"
    uniform.Size = Vector3.new(2, 3, 1)
    uniform.BrickColor = BrickColor.new("Dark stone grey")
    uniform.Material = Enum.Material.Plastic
    uniform.Anchored = true
    uniform.Parent = nil -- Will be parented later
    
    -- Create officer head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(1.5, 2, 1.5)
    head.Shape = Enum.PartType.Ball
    head.BrickColor = BrickColor.new("Dark stone grey")
    head.Material = Enum.Material.Plastic
    head.Anchored = true
    head.Position = uniform.Position + Vector3.new(0, 2, 0)
    head.Parent = nil -- Will be parented later
    
    -- Create officer arms
    local leftArm = Instance.new("Part")
    leftArm.Name = "LeftArm"
    leftArm.Size = Vector3.new(1, 2, 1)
    leftArm.BrickColor = BrickColor.new("Dark stone grey")
    leftArm.Material = Enum.Material.Plastic
    leftArm.Anchored = true
    leftArm.Position = uniform.Position + Vector3.new(-1, 0, 0)
    leftArm.Parent = nil -- Will be parented later
    
    local rightArm = Instance.new("Part")
    rightArm.Name = "RightArm"
    rightArm.Size = Vector3.new(1, 2, 1)
    rightArm.BrickColor = BrickColor.new("Dark stone grey")
    rightArm.Material = Enum.Material.Plastic
    rightArm.Anchored = true
    rightArm.Position = uniform.Position + Vector3.new(1, 0, 0)
    rightArm.Parent = nil -- Will be parented later
    
    -- Create officer legs
    local leftLeg = Instance.new("Part")
    leftLeg.Name = "LeftLeg"
    leftLeg.Size = Vector3.new(1, 2, 1)
    leftLeg.BrickColor = BrickColor.new("Dark stone grey")
    leftLeg.Material = Enum.Material.Plastic
    leftLeg.Anchored = true
    leftLeg.Position = uniform.Position + Vector3.new(-0.5, -1, 0)
    leftLeg.Parent = nil -- Will be parented later
    
    local rightLeg = Instance.new("Part")
    rightLeg.Name = "RightLeg"
    rightLeg.Size = Vector3.new(1, 2, 1)
    rightLeg.BrickColor = BrickColor.new("Dark stone grey")
    rightLeg.Material = Enum.Material.Plastic
    rightLeg.Anchored = true
    rightLeg.Position = uniform.Position + Vector3.new(0.5, -1, 0)
    rightLeg.Parent = nil -- Will be parented later
    
    -- Set primary part
    npc.PrimaryPart = uniform
    return npc
end

function NPCManager:CreateRebelTrooperModel()
    -- Create Rebel Trooper uniform
    local uniform = Instance.new("Part")
    uniform.Name = "Uniform"
    uniform.Size = Vector3.new(2, 3, 1)
    uniform.BrickColor = BrickColor.new("Bright blue")
    uniform.Material = Enum.Material.Plastic
    uniform.Anchored = true
    uniform.Parent = nil -- Will be parented later
    
    -- Create trooper head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(1.5, 2, 1.5)
    head.Shape = Enum.PartType.Ball
    head.BrickColor = BrickColor.new("Bright blue")
    head.Material = Enum.Material.Plastic
    head.Anchored = true
    head.Position = uniform.Position + Vector3.new(0, 2, 0)
    head.Parent = nil -- Will be parented later
    
    -- Create trooper arms
    local leftArm = Instance.new("Part")
    leftArm.Name = "LeftArm"
    leftArm.Size = Vector3.new(1, 2, 1)
    leftArm.BrickColor = BrickColor.new("Bright blue")
    leftArm.Material = Enum.Material.Plastic
    leftArm.Anchored = true
    leftArm.Position = uniform.Position + Vector3.new(-1, 0, 0)
    leftArm.Parent = nil -- Will be parented later
    
    local rightArm = Instance.new("Part")
    rightArm.Name = "RightArm"
    rightArm.Size = Vector3.new(1, 2, 1)
    rightArm.BrickColor = BrickColor.new("Bright blue")
    rightArm.Material = Enum.Material.Plastic
    rightArm.Anchored = true
    rightArm.Position = uniform.Position + Vector3.new(1, 0, 0)
    rightArm.Parent = nil -- Will be parented later
    
    -- Create trooper legs
    local leftLeg = Instance.new("Part")
    leftLeg.Name = "LeftLeg"
    leftLeg.Size = Vector3.new(1, 2, 1)
    leftLeg.BrickColor = BrickColor.new("Bright blue")
    leftLeg.Material = Enum.Material.Plastic
    leftLeg.Anchored = true
    leftLeg.Position = uniform.Position + Vector3.new(-0.5, -1, 0)
    leftLeg.Parent = nil -- Will be parented later
    
    local rightLeg = Instance.new("Part")
    rightLeg.Name = "RightLeg"
    rightLeg.Size = Vector3.new(1, 2, 1)
    rightLeg.BrickColor = BrickColor.new("Bright blue")
    rightLeg.Material = Enum.Material.Plastic
    rightLeg.Anchored = true
    rightLeg.Position = uniform.Position + Vector3.new(0.5, -1, 0)
    rightLeg.Parent = nil -- Will be parented later
    
    -- Set primary part
    npc.PrimaryPart = uniform
    return npc
end

function NPCManager:CreateJediModel()
    -- Create Jedi robe body
    local robe = Instance.new("Part")
    robe.Name = "Robe"
    robe.Size = Vector3.new(2.5, 4, 2)
    robe.BrickColor = BrickColor.new("Brown")
    robe.Material = Enum.Material.Fabric
    robe.Anchored = true
    robe.Parent = nil -- Will be parented later
    
    -- Create Jedi head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(2, 2, 2)
    head.Shape = Enum.PartType.Ball
    head.BrickColor = BrickColor.new("Light brown")
    head.Material = Enum.Material.Plastic
    head.Anchored = true
    head.Position = robe.Position + Vector3.new(0, 3, 0)
    head.Parent = nil -- Will be parented later
    
    -- Create lightsaber hilt
    local lightsaber = Instance.new("Part")
    lightsaber.Name = "Lightsaber"
    lightsaber.Size = Vector3.new(0.5, 0.5, 3)
    lightsaber.BrickColor = BrickColor.new("Dark stone grey")
    lightsaber.Material = Enum.Material.Metal
    lightsaber.Anchored = true
    lightsaber.Position = robe.Position + Vector3.new(1.5, 1, 0)
    lightsaber.Parent = nil -- Will be parented later
    
    -- Add lightsaber blade (glowing)
    local blade = Instance.new("Part")
    blade.Name = "Blade"
    blade.Size = Vector3.new(0.3, 0.3, 4)
    blade.BrickColor = BrickColor.new("Bright blue")
    blade.Material = Enum.Material.Neon
    blade.Anchored = true
    blade.Position = lightsaber.Position + Vector3.new(0, 0, 3.5)
    blade.Parent = nil -- Will be parented later
    
    -- Add blade glow
    local bladeLight = Instance.new("PointLight")
    bladeLight.Color = Color3.fromRGB(0, 150, 255)
    bladeLight.Range = 20
    bladeLight.Brightness = 1
    bladeLight.Parent = nil -- Will be parented later
    
    -- Set primary part
    npc.PrimaryPart = robe
    return npc
end

function NPCManager:CreateSithModel()
    -- Create Sith robe body
    local robe = Instance.new("Part")
    robe.Name = "Robe"
    robe.Size = Vector3.new(2.5, 4, 2)
    robe.BrickColor = BrickColor.new("Black")
    robe.Material = Enum.Material.Fabric
    robe.Anchored = true
    robe.Parent = nil -- Will be parented later
    
    -- Create Sith head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(2, 2, 2)
    head.Shape = Enum.PartType.Ball
    head.BrickColor = BrickColor.new("Black")
    head.Material = Enum.Material.Plastic
    head.Anchored = true
    head.Position = robe.Position + Vector3.new(0, 3, 0)
    head.Parent = nil -- Will be parented later
    
    -- Create lightsaber hilt
    local lightsaber = Instance.new("Part")
    lightsaber.Name = "Lightsaber"
    lightsaber.Size = Vector3.new(0.5, 0.5, 3)
    lightsaber.BrickColor = BrickColor.new("Dark stone grey")
    lightsaber.Material = Enum.Material.Metal
    lightsaber.Anchored = true
    lightsaber.Position = robe.Position + Vector3.new(1.5, 1, 0)
    lightsaber.Parent = nil -- Will be parented later
    
    -- Add lightsaber blade (glowing)
    local blade = Instance.new("Part")
    blade.Name = "Blade"
    blade.Size = Vector3.new(0.3, 0.3, 4)
    blade.BrickColor = BrickColor.new("Bright blue")
    blade.Material = Enum.Material.Neon
    blade.Anchored = true
    blade.Position = lightsaber.Position + Vector3.new(0, 0, 3.5)
    blade.Parent = nil -- Will be parented later
    
    -- Add blade glow
    local bladeLight = Instance.new("PointLight")
    bladeLight.Color = Color3.fromRGB(0, 150, 255)
    bladeLight.Range = 20
    bladeLight.Brightness = 1
    bladeLight.Parent = nil -- Will be parented later
    
    -- Set primary part
    npc.PrimaryPart = robe
    return npc
end

function NPCManager:CreateCivilianModel()
    -- Create Civilian outfit
    local outfit = Instance.new("Part")
    outfit.Name = "Outfit"
    outfit.Size = Vector3.new(2, 3, 1)
    outfit.BrickColor = BrickColor.new("Bright green")
    outfit.Material = Enum.Material.Plastic
    outfit.Anchored = true
    outfit.Parent = nil -- Will be parented later
    
    -- Create civilian head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(1.5, 2, 1.5)
    head.Shape = Enum.PartType.Ball
    head.BrickColor = BrickColor.new("Bright green")
    head.Material = Enum.Material.Plastic
    head.Anchored = true
    head.Position = outfit.Position + Vector3.new(0, 2, 0)
    head.Parent = nil -- Will be parented later
    
    -- Create civilian arms
    local leftArm = Instance.new("Part")
    leftArm.Name = "LeftArm"
    leftArm.Size = Vector3.new(1, 2, 1)
    leftArm.BrickColor = BrickColor.new("Bright green")
    leftArm.Material = Enum.Material.Plastic
    leftArm.Anchored = true
    leftArm.Position = outfit.Position + Vector3.new(-1, 0, 0)
    leftArm.Parent = nil -- Will be parented later
    
    local rightArm = Instance.new("Part")
    rightArm.Name = "RightArm"
    rightArm.Size = Vector3.new(1, 2, 1)
    rightArm.BrickColor = BrickColor.new("Bright green")
    rightArm.Material = Enum.Material.Plastic
    rightArm.Anchored = true
    rightArm.Position = outfit.Position + Vector3.new(1, 0, 0)
    rightArm.Parent = nil -- Will be parented later
    
    -- Create civilian legs
    local leftLeg = Instance.new("Part")
    leftLeg.Name = "LeftLeg"
    leftLeg.Size = Vector3.new(1, 2, 1)
    leftLeg.BrickColor = BrickColor.new("Bright green")
    leftLeg.Material = Enum.Material.Plastic
    leftLeg.Anchored = true
    leftLeg.Position = outfit.Position + Vector3.new(-0.5, -1, 0)
    leftLeg.Parent = nil -- Will be parented later
    
    local rightLeg = Instance.new("Part")
    rightLeg.Name = "RightLeg"
    rightLeg.Size = Vector3.new(1, 2, 1)
    rightLeg.BrickColor = BrickColor.new("Bright green")
    rightLeg.Material = Enum.Material.Plastic
    rightLeg.Anchored = true
    rightLeg.Position = outfit.Position + Vector3.new(0.5, -1, 0)
    rightLeg.Parent = nil -- Will be parented later
    
    -- Set primary part
    npc.PrimaryPart = outfit
    return npc
end

function NPCManager:CreateDroidModel()
    -- Create Droid body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(2, 4, 2)
    body.BrickColor = BrickColor.new("Dark stone grey")
    body.Material = Enum.Material.Plastic
    body.Anchored = true
    body.Parent = nil -- Will be parented later
    
    -- Create Droid head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(1, 2, 1)
    head.Shape = Enum.PartType.Ball
    head.BrickColor = BrickColor.new("Dark stone grey")
    head.Material = Enum.Material.Plastic
    head.Anchored = true
    head.Position = body.Position + Vector3.new(0, 2, 0)
    head.Parent = nil -- Will be parented later
    
    -- Create Droid arms
    local leftArm = Instance.new("Part")
    leftArm.Name = "LeftArm"
    leftArm.Size = Vector3.new(1, 2, 1)
    leftArm.BrickColor = BrickColor.new("Dark stone grey")
    leftArm.Material = Enum.Material.Plastic
    leftArm.Anchored = true
    leftArm.Position = body.Position + Vector3.new(-1, 0, 0)
    leftArm.Parent = nil -- Will be parented later
    
    local rightArm = Instance.new("Part")
    rightArm.Name = "RightArm"
    rightArm.Size = Vector3.new(1, 2, 1)
    rightArm.BrickColor = BrickColor.new("Dark stone grey")
    rightArm.Material = Enum.Material.Plastic
    rightArm.Anchored = true
    rightArm.Position = body.Position + Vector3.new(1, 0, 0)
    rightArm.Parent = nil -- Will be parented later
    
    -- Create Droid legs
    local leftLeg = Instance.new("Part")
    leftLeg.Name = "LeftLeg"
    leftLeg.Size = Vector3.new(1, 2, 1)
    leftLeg.BrickColor = BrickColor.new("Dark stone grey")
    leftLeg.Material = Enum.Material.Plastic
    leftLeg.Anchored = true
    leftLeg.Position = body.Position + Vector3.new(-0.5, -1, 0)
    leftLeg.Parent = nil -- Will be parented later
    
    local rightLeg = Instance.new("Part")
    rightLeg.Name = "RightLeg"
    rightLeg.Size = Vector3.new(1, 2, 1)
    rightLeg.BrickColor = BrickColor.new("Dark stone grey")
    rightLeg.Material = Enum.Material.Plastic
    rightLeg.Anchored = true
    rightLeg.Position = body.Position + Vector3.new(0.5, -1, 0)
    rightLeg.Parent = nil -- Will be parented later
    
    -- Set primary part
    npc.PrimaryPart = body
    return npc
end

function NPCManager:CreateBasicNPCModel()
    -- Create basic NPC body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(2, 3, 1) -- Default size for basic NPC
    body.BrickColor = BrickColor.new("White") -- Default color
    body.Material = Enum.Material.Plastic
    body.Anchored = true
    body.Parent = nil -- Will be parented later
    
    -- Set primary part
    npc.PrimaryPart = body
    return npc
end

function NPCManager:AddNPCBehavior(npc, behavior)
    if not npc or not npc.PrimaryPart then return end
    
    local behaviorType = behavior or "WANDER"
    print("🎭 Adding " .. behaviorType .. " behavior to NPC: " .. npc.Name)
    
    if behaviorType == "PATROL" then
        spawn(function()
            while npc and npc.PrimaryPart and npc.PrimaryPart.Parent do
                local targetPos = npc.PrimaryPart.Position + Vector3.new(
                    math.random(-20, 20),
                    0,
                    math.random(-20, 20)
                )
                
                -- Move to target position
                local bodyVelocity = Instance.new("BodyVelocity")
                bodyVelocity.Velocity = (targetPos - npc.PrimaryPart.Position).Unit * 5
                bodyVelocity.MaxForce = Vector3.new(1000, 0, 1000)
                bodyVelocity.Parent = npc.PrimaryPart
                
                wait(3)
                
                if bodyVelocity and bodyVelocity.Parent then
                    bodyVelocity:Destroy()
                end
                
                wait(2)
            end
        end)
        
    elseif behaviorType == "WANDER" then
        spawn(function()
            while npc and npc.PrimaryPart and npc.PrimaryPart.Parent do
                local targetPos = npc.PrimaryPart.Position + Vector3.new(
                    math.random(-15, 15),
                    0,
                    math.random(-15, 15)
                )
                
                -- Move to target position
                local bodyVelocity = Instance.new("BodyVelocity")
                bodyVelocity.Velocity = (targetPos - npc.PrimaryPart.Position).Unit * 3
                bodyVelocity.MaxForce = Vector3.new(1000, 0, 1000)
                bodyVelocity.Parent = npc.PrimaryPart
                
                wait(2)
                
                if bodyVelocity and bodyVelocity.Parent then
                    bodyVelocity:Destroy()
                end
                
                wait(1)
            end
        end)
        
    elseif behaviorType == "WORK" then
        spawn(function()
            while npc and npc.PrimaryPart and npc.PrimaryPart.Parent do
                -- Simulate working by moving in small circles
                local centerPos = npc.PrimaryPart.Position
                local angle = math.random() * math.pi * 2
                local radius = 3
                local targetPos = centerPos + Vector3.new(
                    math.cos(angle) * radius,
                    0,
                    math.sin(angle) * radius
                )
                
                local bodyVelocity = Instance.new("BodyVelocity")
                bodyVelocity.Velocity = (targetPos - npc.PrimaryPart.Position).Unit * 2
                bodyVelocity.MaxForce = Vector3.new(1000, 0, 1000)
                bodyVelocity.Parent = npc.PrimaryPart
                
                wait(1.5)
                
                if bodyVelocity and bodyVelocity.Parent then
                    bodyVelocity:Destroy()
                end
                
                wait(0.5)
            end
        end)
        
    elseif behaviorType == "STAND" then
        spawn(function()
            while npc and npc.PrimaryPart and npc.PrimaryPart.Parent do
                -- Occasionally move slightly
                if math.random() < 0.3 then
                    local targetPos = npc.PrimaryPart.Position + Vector3.new(
                        math.random(-5, 5),
                        0,
                        math.random(-5, 5)
                    )
                    
                    local bodyVelocity = Instance.new("BodyVelocity")
                    bodyVelocity.Velocity = (targetPos - npc.PrimaryPart.Position).Unit * 1
                    bodyVelocity.MaxForce = Vector3.new(1000, 0, 1000)
                    bodyVelocity.Parent = npc.PrimaryPart
                    
                    wait(1)
                    
                    if bodyVelocity and bodyVelocity.Parent then
                        bodyVelocity:Destroy()
                    end
                end
                
                wait(3)
            end
        end)
    end
    
    print("✅ Added " .. behaviorType .. " behavior to " .. npc.Name)
end

function NPCManager:HandleNPCInteraction(player, npc, npcData, planetName)
    -- Create chat bubble response
    local response = npcData.responses and npcData.responses[math.random(1, #npcData.responses)] or "Hello there!"
    
    -- Create chat bubble above NPC
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Name = "NPCChatBubble"
    billboardGui.Size = UDim2.new(0, 200, 0, 100)
    billboardGui.StudsOffset = Vector3.new(0, 8, 0)
    billboardGui.Parent = npc.PrimaryPart
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(0, 0, 0)
    frame.Parent = billboardGui
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = response
    textLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.SourceSans
    textLabel.Parent = frame
    
    -- Auto-destroy chat bubble after 5 seconds
    spawn(function()
        wait(5)
        if billboardGui and billboardGui.Parent then
            billboardGui:Destroy()
        end
    end)
    
    -- Give player credits for interaction
    local credits = math.random(10, 50)
    if player:FindFirstChild("Credits") then
        player.Credits.Value = player.Credits.Value + credits
    end
    
    -- Show credit reward in chat bubble
    local rewardGui = Instance.new("BillboardGui")
    rewardGui.Name = "CreditReward"
    rewardGui.Size = UDim2.new(0, 150, 0, 50)
    rewardGui.StudsOffset = Vector3.new(0, 6, 0)
    rewardGui.Parent = npc.PrimaryPart
    
    local rewardFrame = Instance.new("Frame")
    rewardFrame.Size = UDim2.new(1, 0, 1, 0)
    rewardFrame.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    rewardFrame.BorderSizePixel = 1
    rewardFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
    rewardFrame.Parent = rewardGui
    
    local rewardText = Instance.new("TextLabel")
    rewardText.Size = UDim2.new(1, 0, 1, 0)
    rewardText.BackgroundTransparency = 1
    rewardText.Text = "+" .. credits .. " Credits!"
    rewardText.TextColor3 = Color3.fromRGB(0, 0, 0)
    rewardText.TextScaled = true
    rewardText.Font = Enum.Font.SourceSansBold
    rewardText.Parent = rewardFrame
    
    -- Auto-destroy reward after 3 seconds
    spawn(function()
        wait(3)
        if rewardGui and rewardGui.Parent then
            rewardGui:Destroy()
        end
    end)
    
    print("💬 " .. player.Name .. " talked to " .. npc.Name .. " and got " .. credits .. " credits")
end

function NPCManager:StartNPCBehaviorLoops()
    -- Start behavior updates
    spawn(function()
        while true do
            wait(10) -- Update every 10 seconds
            
            -- Update NPC behaviors
            self:UpdateNPCBehaviors()
            
            -- Clean up inactive NPCs
            self:CleanupInactiveNPCs()
        end
    end)
end

function NPCManager:UpdateNPCBehaviors()
    for _, npcData in ipairs(self.activeNPCs) do
        if npcData.npc and npcData.npc.Parent then
            -- Update behavior based on time of day, events, etc.
            -- This could include faction wars, special events, etc.
        end
    end
end

function NPCManager:CleanupInactiveNPCs()
    local currentTime = tick()
    local npcsToRemove = {}
    
    for i, npcData in ipairs(self.activeNPCs) do
        -- Remove NPCs that have been inactive for too long
        if currentTime - npcData.spawnTime > 3600 then -- 1 hour
            if npcData.npc and npcData.npc.Parent then
                npcData.npc:Destroy()
            end
            table.insert(npcsToRemove, i)
        end
    end
    
    -- Remove from table (in reverse order)
    for i = #npcsToRemove, 1, -1 do
        table.remove(self.activeNPCs, npcsToRemove[i])
    end
end

function NPCManager:GetNPCsOnPlanet(planetName)
    local planetNPCs = {}
    
    for _, npcData in ipairs(self.activeNPCs) do
        if npcData.planet == planetName then
            table.insert(planetNPCs, npcData)
        end
    end
    
    return planetNPCs
end

function NPCManager:GetAllNPCs()
    return self.activeNPCs
end

function NPCManager:ClearAllNPCs()
    for _, npcData in ipairs(self.activeNPCs) do
        if npcData.npc and npcData.npc.Parent then
            npcData.npc:Destroy()
        end
    end
    
    self.activeNPCs = {}
    print("🗑️ All NPCs cleared")
end

function NPCManager:ClearNPCsOnPlanet(planetName)
    local npcsToRemove = {}
    
    for i, npcData in ipairs(self.activeNPCs) do
        if npcData.planet == planetName then
            if npcData.npc and npcData.npc.Parent then
                npcData.npc:Destroy()
            end
            table.insert(npcsToRemove, i)
        end
    end
    
    -- Remove from table (in reverse order)
    for i = #npcsToRemove, 1, -1 do
        table.remove(self.activeNPCs, npcsToRemove[i])
    end
    
    print("🗑️ Cleared NPCs on " .. planetName)
end

-- Return the NPCManager class
return NPCManager
