-- SpaceshipSpawner.lua
-- Automatically spawns and manages spaceships on all planets

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SpaceshipSpawner = {}
SpaceshipSpawner.__index = SpaceshipSpawner

-- Spaceship spawn configurations
local SHIP_SPAWN_CONFIGS = {
    Coruscant = {
        spawnPoints = 8,
        shipTypes = {"XWing", "TIE", "MillenniumFalcon", "StarDestroyer"},
        spawnHeight = 200,
        maxShips = 20
    },
    Tatooine = {
        spawnPoints = 5,
        shipTypes = {"XWing", "TIE", "Sandcrawler", "Speeder"},
        spawnHeight = 150,
        maxShips = 15
    },
    Hoth = {
        spawnPoints = 3,
        shipTypes = {"XWing", "Snowspeeder", "RebelTransport"},
        spawnHeight = 180,
        maxShips = 12
    },
    Naboo = {
        spawnPoints = 6,
        shipTypes = {"NabooFighter", "RoyalShip", "TradeFederation"},
        spawnHeight = 160,
        maxShips = 18
    },
    Mustafar = {
        spawnPoints = 4,
        shipTypes = {"TIE", "ImperialShuttle", "MiningVessel"},
        spawnHeight = 170,
        maxShips = 14
    },
    Kamino = {
        spawnPoints = 5,
        shipTypes = {"CloneShip", "RepublicCruiser", "MedicalVessel"},
        spawnHeight = 140,
        maxShips = 16
    }
}

function SpaceshipSpawner.new()
    local self = setmetatable({}, SpaceshipSpawner)
    
    self.activeShips = {}
    self.spawnPoints = {}
    
    return self
end

function SpaceshipSpawner:Initialize()
    print("🚁 Initializing Spaceship Spawner System...")
    
    -- Create spaceship folder
    self.shipsFolder = Instance.new("Folder")
    self.shipsFolder.Name = "ActiveSpaceships"
    self.shipsFolder.Parent = Workspace
    
    -- Set up spawn points for all planets
    self:SetupAllPlanetSpawnPoints()
    
    -- Start spawning ships
    self:StartShipSpawning()
    
    print("✅ Spaceship Spawner System initialized!")
end

function SpaceshipSpawner:SetupAllPlanetSpawnPoints()
    print("🏗️ Setting up hangars for all planets...")
    
    -- Wait for planets to be generated first
    local maxWaitTime = 30
    local waitTime = 0
    
    while waitTime < maxWaitTime do
        local planetFolder = Workspace:FindFirstChild("Planets")
        if planetFolder then
            local hasPlanets = false
            for _, child in pairs(planetFolder:GetChildren()) do
                if child:IsA("Folder") then
                    hasPlanets = true
                    break
                end
            end
            
            if hasPlanets then
                print("✅ Planets found! Creating hangars...")
                break
            end
        end
        
        wait(1)
        waitTime = waitTime + 1
        print("⏳ Waiting for planets to generate... (" .. waitTime .. "/" .. maxWaitTime .. "s)")
    end
    
    if waitTime >= maxWaitTime then
        warn("❌ Timeout waiting for planets! Hangars may not be created correctly.")
        return
    end
    
    -- Create hangars for each planet
    local planetPositions = {
        Coruscant = Vector3.new(0, 0, 0),
        Tatooine = Vector3.new(1000, 0, 1000),
        Hoth = Vector3.new(-1000, 0, -1000),
        Naboo = Vector3.new(0, 0, 2000),
        Mustafar = Vector3.new(2000, 0, 0),
        Kamino = Vector3.new(0, 0, -2000)
    }
    
    for planetName, planetPos in pairs(planetPositions) do
        print("🏗️ Creating hangar for " .. planetName .. " at " .. tostring(planetPos))
        
        -- Create hangar at a specific offset from planet center
        local hangarOffset = Vector3.new(100, 0, 100) -- Offset from planet center
        local hangarPos = planetPos + hangarOffset
        
        local hangar = self:CreatePlanetHangar(planetName, hangarPos)
        if hangar then
            hangar.Parent = Workspace
            print("✅ Hangar created for " .. planetName .. " at " .. tostring(hangarPos))
        else
            warn("❌ Failed to create hangar for " .. planetName)
        end
        
        wait(0.5) -- Small delay between hangar creation
    end
    
    print("🎉 All planet hangars created!")
end

function SpaceshipSpawner:CreatePlanetHangar(planetName, planetPos)
    local hangar = Instance.new("Model")
    hangar.Name = planetName .. "_Hangar"
    
    -- Create a simple outdoor hangar structure
    local hangarFloor = Instance.new("Part")
    hangarFloor.Name = "Floor"
    hangarFloor.Size = Vector3.new(40, 2, 40)
    hangarFloor.Position = Vector3.new(planetPos.X, planetPos.Y + 1, planetPos.Z)
    hangarFloor.Anchored = true
    hangarFloor.Material = Enum.Material.Metal
    hangarFloor.Color = Color3.fromRGB(100, 100, 100)
    hangarFloor.Parent = hangar
    
    -- Add some support posts
    for i = 1, 4 do
        local post = Instance.new("Part")
        post.Name = "Post" .. i
        post.Size = Vector3.new(2, 15, 2)
        local angle = (i - 1) * math.pi / 2
        local radius = 18
        post.Position = Vector3.new(
            planetPos.X + radius * math.cos(angle),
            planetPos.Y + 8,
            planetPos.Z + radius * math.sin(angle)
        )
        post.Anchored = true
        post.Material = Enum.Material.Metal
        post.Color = Color3.fromRGB(80, 80, 80)
        post.Parent = hangar
    end
    
    -- Add a roof
    local hangarRoof = Instance.new("Part")
    hangarRoof.Name = "Roof"
    hangarRoof.Size = Vector3.new(42, 1, 42)
    hangarRoof.Position = Vector3.new(planetPos.X, planetPos.Y + 15, planetPos.Z)
    hangarRoof.Anchored = true
    hangarRoof.Material = Enum.Material.Metal
    hangarRoof.Color = Color3.fromRGB(120, 120, 120)
    hangarRoof.Parent = hangar
    
    -- Add lighting
    local hangarLight = Instance.new("PointLight")
    hangarLight.Name = "HangarLight"
    hangarLight.Color = Color3.fromRGB(255, 255, 200)
    hangarLight.Range = 50
    hangarLight.Brightness = 2
    hangarLight.Parent = hangarFloor
    
    -- Create landing pads
    local landingPad1 = Instance.new("Part")
    landingPad1.Name = "LandingPad1"
    landingPad1.Size = Vector3.new(15, 0.5, 15)
    landingPad1.Position = Vector3.new(planetPos.X - 10, planetPos.Y + 1.5, planetPos.Z - 10)
    landingPad1.Anchored = true
    landingPad1.Material = Enum.Material.Metal
    landingPad1.Color = Color3.fromRGB(50, 50, 50)
    landingPad1.Parent = hangar
    
    local landingPad2 = Instance.new("Part")
    landingPad2.Name = "LandingPad2"
    landingPad2.Size = Vector3.new(15, 0.5, 15)
    landingPad2.Position = Vector3.new(planetPos.X + 10, planetPos.Y + 1.5, planetPos.Z + 10)
    landingPad2.Anchored = true
    landingPad2.Material = Enum.Material.Metal
    landingPad2.Color = Color3.fromRGB(50, 50, 50)
    landingPad2.Parent = hangar
    
    -- Create hangar manager NPC
    local hangarManager = Instance.new("Part")
    hangarManager.Name = "HangarManager"
    hangarManager.Size = Vector3.new(2, 4, 2)
    hangarManager.Position = Vector3.new(planetPos.X, planetPos.Y + 3, planetPos.Z + 20)
    hangarManager.Anchored = true
    hangarManager.Material = Enum.Material.Neon
    hangarManager.Color = Color3.fromRGB(0, 255, 255)
    hangarManager.Parent = hangar
    
    -- Add ProximityPrompt for hangar manager
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "HangarPrompt"
    prompt.ObjectText = "Hangar Manager"
    prompt.ActionText = "Talk"
    prompt.MaxActivationDistance = 8
    prompt.Parent = hangarManager
    
    -- Add hangar sign
    local hangarSign = Instance.new("Part")
    hangarSign.Name = "HangarSign"
    hangarSign.Size = Vector3.new(8, 3, 1)
    hangarSign.Position = Vector3.new(planetPos.X, planetPos.Y + 12, planetPos.Z + 25)
    hangarSign.Anchored = true
    hangarSign.Material = Enum.Material.Neon
    hangarSign.Color = Color3.fromRGB(255, 255, 0)
    hangarSign.Parent = hangar
    
    -- Add text to sign
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Name = "SignText"
    billboardGui.Size = UDim2.new(0, 200, 0, 100)
    billboardGui.StudsOffset = Vector3.new(0, 2, 0)
    billboardGui.Parent = hangarSign
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = "HANGAR\n" .. planetName
    textLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.SourceSansBold
    textLabel.Parent = billboardGui
    
    -- Set primary part and store in hangars table
    hangar.PrimaryPart = hangarFloor
    self.hangars[planetName] = hangar
    
    -- Connect hangar manager prompt to ship spawning
    prompt.Triggered:Connect(function(player)
        self:ShowShipMenu(player, planetName)
    end)
    
    print("✅ Created hangar for " .. planetName)
    return hangar
end

function SpaceshipSpawner:CreateHangarManager(position)
    local manager = Instance.new("Model")
    manager.Name = "HangarManager"
    
    -- Create manager body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(2, 4, 2)
    body.BrickColor = BrickColor.new("Bright orange")
    body.Material = Enum.Material.Plastic
    body.Anchored = true
    body.Position = position
    body.Parent = manager
    
    -- Create manager head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(1.5, 1.5, 1.5)
    head.Shape = Enum.PartType.Ball
    head.BrickColor = BrickColor.new("Bright yellow")
    head.Material = Enum.Material.Plastic
    head.Anchored = true
    head.Position = body.Position + Vector3.new(0, 2.75, 0)
    head.Parent = manager
    
    -- Add manager glow
    local managerLight = Instance.new("PointLight")
    managerLight.Color = Color3.fromRGB(255, 255, 0)
    managerLight.Range = 15
    managerLight.Brightness = 0.8
    managerLight.Parent = body
    
    -- Add interaction prompt
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "TalkToManager"
    prompt.ObjectText = "Hangar Manager"
    prompt.ActionText = "Talk"
    prompt.MaxActivationDistance = 10
    prompt.HoldDuration = 0.5
    prompt.Parent = body
    
    -- Connect prompt to manager interaction
    prompt.Triggered:Connect(function(player)
        self:ShowShipServicesMenu(player, self:GetPlanetNameFromManager(manager))
    end)
    
    -- Set primary part
    manager.PrimaryPart = body
    
    return manager
end

function SpaceshipSpawner:GetPlanetNameFromManager(manager)
    -- Find which planet this manager belongs to
    local hangar = manager.Parent
    if hangar and hangar.Name then
        local planetName = hangar.Name:gsub("_Hangar", "")
        return planetName
    end
    return "Coruscant" -- Default
end

function SpaceshipSpawner:ShowShipSpawnMenu(player, planetName, padNumber)
    print("🚁 " .. player.Name .. " wants to spawn a ship on " .. planetName .. " pad " .. padNumber)
    
    local message = "🚁 Available ships for " .. planetName .. ":\n\n"
    
    for shipType, shipData in pairs(SHIP_SPAWN_CONFIGS) do
        message = message .. "• " .. shipData.shipTypes[1] .. " - " .. shipData.maxShips .. " ships\n" -- Simplified for now
        message = message .. "  " .. "Max " .. shipData.maxShips .. " ships\n\n"
    end
    
    message = message .. "Use /ship [type] [planet] to spawn a ship!"
    
    self:SendMessage(player, message)
end

function SpaceshipSpawner:ShowShipServicesMenu(player, planetName)
    print("🔧 " .. player.Name .. " accessing ship services on " .. planetName)
    
    local message = Instance.new("Message")
    message.Text = "🔧 Ship Services on " .. planetName .. ":\n\n• Ship spawning and customization\n• Ship repairs and upgrades\n• Fuel and supplies\n• Flight training\n\nVisit a landing pad to spawn ships!"
    message.Parent = workspace
    wait(8)
    message:Destroy()
    
    -- Actually spawn a ship for the player
    self:SpawnShipForPlayer(player, planetName)
end

function SpaceshipSpawner:SpawnShipForPlayer(player, planetName)
    print("🚁 Spawning ship for " .. player.Name .. " on " .. planetName)
    
    -- Get available ship types for this planet
    local config = SHIP_SPAWN_CONFIGS[planetName]
    if not config then return end
    
    -- Select a random ship type
    local shipType = config.shipTypes[math.random(1, #config.shipTypes)]
    
    -- Get spawn position near the player
    local character = player.Character
    if not character then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    
    local spawnPos = rootPart.Position + Vector3.new(0, 10, 20) -- Above and behind player
    
    -- Create the ship
    local ship = self:CreateShip(shipType, spawnPos)
    if ship then
        ship.Parent = self.shipsFolder
        
        -- Make ship flyable
        self:MakeShipFlyable(ship, player)
        
        -- Store ship data
        table.insert(self.activeShips, {
            ship = ship,
            planet = planetName,
            type = shipType,
            spawnTime = tick(),
            owner = player
        })
        
        -- Send success message
        local message = Instance.new("Message")
        message.Text = "🚁 Ship spawned! " .. shipType .. " is now available for you to fly!"
        message.Parent = workspace
        wait(8)
        message:Destroy()
        
        print("✅ Spawned " .. shipType .. " for " .. player.Name .. " on " .. planetName)
    end
end

function SpaceshipSpawner:MakeShipFlyable(ship, player)
    local body = ship.PrimaryPart
    if not body then return end
    
    -- Create a SINGLE VehicleSeat (not regular Seat)
    local vehicleSeat = Instance.new("VehicleSeat")
    vehicleSeat.Name = "PilotSeat"
    vehicleSeat.Size = Vector3.new(2, 1, 2)
    vehicleSeat.Position = body.Position + Vector3.new(0, 5, 0)
    vehicleSeat.BrickColor = BrickColor.new("Bright blue")
    vehicleSeat.Material = Enum.Material.Neon
    vehicleSeat.Anchored = false
    vehicleSeat.Parent = ship
    
    -- Configure VehicleSeat for spaceship flight
    vehicleSeat.MaxSpeed = 100
    vehicleSeat.Torque = 100000
    vehicleSeat.MaxTorque = Vector3.new(100000, 100000, 100000)
    vehicleSeat.TurnSpeed = 3
    
    -- Add interaction prompt
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "EnterShip"
    prompt.ObjectText = "Enter X-Wing"
    prompt.ActionText = "Pilot"
    prompt.MaxActivationDistance = 10
    prompt.HoldDuration = 0.5
    prompt.Parent = vehicleSeat
    
    -- Connect prompt to ship entry
    prompt.Triggered:Connect(function(player)
        self:PlayerEnterShip(player, ship)
        prompt.Enabled = false
    end)
    
    -- Monitor when player sits in seat
    vehicleSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
        local occupant = vehicleSeat.Occupant
        if occupant then
            -- Player is in the seat, enable flight mode
            self:EnableFlightMode(ship, player)
            prompt.Enabled = false
        else
            -- Player left the seat, show prompt again
            prompt.Enabled = true
        end
    end)
    
    -- Set the VehicleSeat as the ship's primary part for proper physics
    ship.PrimaryPart = vehicleSeat
    
    print("✅ VehicleSeat created for " .. ship.Name)
end

function SpaceshipSpawner:PlayerEnterShip(player, ship)
    print("🚁 " .. player.Name .. " entered ship")
    
    local message = Instance.new("Message")
    message.Text = "🚁 Welcome to your X-Wing! Use WASD to move, R/F for vertical, Q/E for roll"
    message.Parent = workspace
    wait(8)
    message:Destroy()
    
    -- Enable flight mode
    self:EnableFlightMode(ship, player)
end

function SpaceshipSpawner:EnableFlightMode(ship, player)
    local vehicleSeat = ship:FindFirstChild("PilotSeat")
    if not vehicleSeat then return end
    
    -- Make ship physics-based for flight
    local shipBody = ship.PrimaryPart
    if shipBody then
        shipBody.Anchored = false
    end
    
    -- Add BodyVelocity for smooth movement
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Name = "FlightVelocity"
    bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
    bodyVelocity.Velocity = Vector3.new(0, 0, 0)
    bodyVelocity.Parent = vehicleSeat
    
    -- Add BodyGyro for rotation control
    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.Name = "FlightGyro"
    bodyGyro.MaxTorque = Vector3.new(100000, 100000, 100000)
    bodyGyro.D = 100
    bodyGyro.P = 2000
    bodyGyro.Parent = vehicleSeat
    
    -- Create flight control LocalScript
    local flightScript = Instance.new("LocalScript")
    flightScript.Name = "FlightControls"
    flightScript.Parent = vehicleSeat
    
    -- Flight control logic
    flightScript.Source = [[
        local UserInputService = game:GetService("UserInputService")
        local RunService = game:GetService("RunService")
        local Players = game:GetService("Players")
        
        local player = Players.LocalPlayer
        local character = player.Character
        local humanoid = character and character:FindFirstChild("Humanoid")
        
        if not (character and humanoid) then return end
        
        local ship = script.Parent.Parent
        local vehicleSeat = script.Parent
        local shipBody = ship.PrimaryPart
        if not shipBody then return end
        
        -- Flight variables
        local velocity = Vector3.new(0, 0, 0)
        local rotation = Vector3.new(0, 0, 0)
        local maxSpeed = 80
        local acceleration = 8
        local turnSpeed = 3
        
        -- Input handling
        local input = {
            forward = false,
            backward = false,
            left = false,
            right = false,
            up = false,
            down = false,
            rollLeft = false,
            rollRight = false
        }
        
        -- Key press events
        UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
            if gameProcessed then return end
            
            if inputObject.KeyCode == Enum.KeyCode.W then
                input.forward = true
            elseif inputObject.KeyCode == Enum.KeyCode.S then
                input.backward = true
            elseif inputObject.KeyCode == Enum.KeyCode.A then
                input.left = true
            elseif inputObject.KeyCode == Enum.KeyCode.D then
                input.right = true
            elseif inputObject.KeyCode == Enum.KeyCode.R then
                input.up = true
            elseif inputObject.KeyCode == Enum.KeyCode.F then
                input.down = true
            elseif inputObject.KeyCode == Enum.KeyCode.Q then
                input.rollLeft = true
            elseif inputObject.KeyCode == Enum.KeyCode.E then
                input.rollRight = true
            end
        end)
        
        -- Key release events
        UserInputService.InputEnded:Connect(function(inputObject, gameProcessed)
            if gameProcessed then return end
            
            if inputObject.KeyCode == Enum.KeyCode.W then
                input.forward = false
            elseif inputObject.KeyCode == Enum.KeyCode.S then
                input.backward = false
            elseif inputObject.KeyCode == Enum.KeyCode.A then
                input.left = false
            elseif inputObject.KeyCode == Enum.KeyCode.D then
                input.right = false
            elseif inputObject.KeyCode == Enum.KeyCode.R then
                input.up = false
            elseif inputObject.KeyCode == Enum.KeyCode.F then
                input.down = false
            elseif inputObject.KeyCode == Enum.KeyCode.Q then
                input.rollLeft = false
            elseif inputObject.KeyCode == Enum.KeyCode.E then
                input.rollRight = false
            end
        end)
        
        -- Check if player is in the seat
        local function isPlayerInSeat()
            return vehicleSeat.Occupant == humanoid
        end
        
        -- Flight physics update
        RunService.Heartbeat:Connect(function(deltaTime)
            if not isPlayerInSeat() then return end
            
            -- Handle input and update velocity
            if input.forward then
                velocity = velocity + (shipBody.CFrame.LookVector * acceleration * deltaTime)
            elseif input.backward then
                velocity = velocity + (shipBody.CFrame.LookVector * -acceleration * deltaTime)
            end
            
            if input.left then
                velocity = velocity + (shipBody.CFrame.RightVector * -acceleration * deltaTime)
            elseif input.right then
                velocity = velocity + (shipBody.CFrame.RightVector * acceleration * deltaTime)
            end
            
            if input.up then
                velocity = velocity + (Vector3.new(0, 1, 0) * acceleration * deltaTime)
            elseif input.down then
                velocity = velocity + (Vector3.new(0, -1, 0) * acceleration * deltaTime)
            end
            
            -- Handle rotation
            if input.rollLeft then
                rotation = rotation + Vector3.new(0, 0, turnSpeed * deltaTime)
            elseif input.rollRight then
                rotation = rotation + Vector3.new(0, 0, -turnSpeed * deltaTime)
            end
            
            -- Apply rotation to ship
            if rotation.Magnitude > 0 then
                local currentCFrame = shipBody.CFrame
                local newCFrame = currentCFrame * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
                shipBody.CFrame = newCFrame
                rotation = Vector3.new(0, 0, 0) -- Reset rotation
            end
            
            -- Apply velocity to ship position
            if velocity.Magnitude > 0 then
                local newPosition = shipBody.Position + (velocity * deltaTime)
                shipBody.CFrame = CFrame.new(newPosition) * shipBody.CFrame.Rotation
                
                -- Apply drag to slow down
                velocity = velocity * 0.92
            end
            
            -- Limit maximum speed
            if velocity.Magnitude > maxSpeed then
                velocity = velocity.Unit * maxSpeed
            end
        end)
        
        -- Show flight instructions
        local message = Instance.new("Message")
        message.Text = "🚁 FLIGHT CONTROLS:\nW/S - Forward/Backward\nA/D - Left/Right\nR/F - Up/Down\nQ/E - Roll Left/Right\n\nYou're now flying!"
        message.Parent = workspace
        wait(6)
        message:Destroy()
    ]]
    
    print("✅ Flight mode enabled for " .. ship.Name)
end

function SpaceshipSpawner:AddHangarManagerBehavior(npc, planetName)
    local body = npc.PrimaryPart
    if not body then return end
    
    -- Add behavior using a different approach
    local behaviorScript = Instance.new("Script")
    behaviorScript.Name = "HangarManagerBehaviorScript"
    behaviorScript.Parent = body
    
    -- Use spawn function instead of script source
    spawn(function()
        local startPos = body.Position
        local rotationSpeed = 0.3
        
        print("👨‍💼 Hangar manager " .. planetName .. " behavior started")
        
        while body and body.Parent do
            wait(0.1)
            
            if body and body.Parent then
                -- Gentle rotation to make NPC look alive
                local time = tick() * rotationSpeed
                local rotation = CFrame.Angles(0, time * 0.1, 0)
                body.CFrame = CFrame.new(body.Position) * rotation
            else
                break
            end
        end
        
        print("👨‍💼 Hangar manager " .. planetName .. " behavior ended")
    end)
end

function SpaceshipSpawner:GetPlanetSpawnPoint(planetName)
    local planetConfigs = {
        Coruscant = Vector3.new(0, 5, 0),       -- Much lower - almost ground level
        Tatooine = Vector3.new(1000, 5, 1000),   -- Much lower - almost ground level
        Hoth = Vector3.new(-1000, 5, -1000),     -- Much lower - almost ground level
        Naboo = Vector3.new(0, 5, 2000),         -- Much lower - almost ground level
        Mustafar = Vector3.new(2000, 5, 0),      -- Much lower - almost ground level
        Kamino = Vector3.new(0, 5, -2000)        -- Much lower - almost ground level
    }
    
    return planetConfigs[planetName] or Vector3.new(0, 5, 0)
end

function SpaceshipSpawner:SendMessage(player, message)
    -- This would send a message to the player's client
    -- For now, just print to console
    print("📨 [" .. player.Name .. "] " .. message)
end

function SpaceshipSpawner:StartShipSpawning()
    -- Spawn initial ships
    self:SpawnInitialShips()
    
    -- Set up continuous spawning
    spawn(function()
        while true do
            wait(30) -- Spawn new ships every 30 seconds
            self:MaintainShipPopulation()
        end
    end)
end

function SpaceshipSpawner:SpawnInitialShips()
    for planetName, config in pairs(SHIP_SPAWN_CONFIGS) do
        local initialShips = math.floor(config.maxShips * 0.3) -- Start with 30% capacity
        for i = 1, initialShips do
            self:SpawnRandomShip(planetName)
            wait(1) -- Small delay between spawns
        end
    end
end

function SpaceshipSpawner:MaintainShipPopulation()
    for planetName, config in pairs(SHIP_SPAWN_CONFIGS) do
        local currentShips = self:GetShipsOnPlanet(planetName)
        local targetShips = config.maxShips
        
        if currentShips < targetShips then
            local shipsToSpawn = math.min(3, targetShips - currentShips) -- Spawn up to 3 at once
            for i = 1, shipsToSpawn do
                self:SpawnRandomShip(planetName)
                wait(2)
            end
        end
    end
end

function SpaceshipSpawner:SpawnRandomShip(planetName)
    local config = SHIP_SPAWN_CONFIGS[planetName]
    if not config then return end
    
    -- Select random ship type
    local shipType = config.shipTypes[math.random(1, #config.shipTypes)]
    
    -- Get random spawn point
    local spawnPoints = self:GetSpawnPointsForPlanet(planetName)
    if #spawnPoints == 0 then return end
    
    local spawnPoint = spawnPoints[math.random(1, #spawnPoints)]
    
    -- Create ship
    local ship = self:CreateShip(shipType, spawnPoint.Position)
    if ship then
        ship.Parent = self.shipsFolder
        
        -- Store ship data
        table.insert(self.activeShips, {
            ship = ship,
            planet = planetName,
            type = shipType,
            spawnTime = tick()
        })
        
        -- Add ship behavior
        self:AddShipBehavior(ship, planetName)
        
        print("🚁 Spawned " .. shipType .. " on " .. planetName)
    end
end

function SpaceshipSpawner:CreateShip(shipType, position)
    local ship = Instance.new("Model")
    ship.Name = shipType .. "_" .. tick()
    
    -- Create ship based on type with realistic models
    if shipType == "XWing" then
        self:CreateXWingModel(ship, position)
    elseif shipType == "TIE" then
        self:CreateTIEModel(ship, position)
    elseif shipType == "MillenniumFalcon" then
        self:CreateFalconModel(ship, position)
    elseif shipType == "StarDestroyer" then
        self:CreateStarDestroyerModel(ship, position)
    elseif shipType == "Snowspeeder" then
        self:CreateSnowspeederModel(ship, position)
    elseif shipType == "NabooFighter" then
        self:CreateNabooFighterModel(ship, position)
    else
        -- Fallback to basic ship
        self:CreateBasicShipModel(ship, shipType, position)
    end
    
    -- Add ship glow
    local pointLight = Instance.new("PointLight")
    pointLight.Color = Color3.fromRGB(255, 255, 255)
    pointLight.Range = 30
    pointLight.Brightness = 0.5
    pointLight.Parent = ship.PrimaryPart
    
    return ship
end

function SpaceshipSpawner:CreateXWingModel(ship, position)
    -- Create X-Wing body (main fuselage) - movie-accurate proportions
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(4, 2, 20) -- Much more accurate proportions
    body.BrickColor = BrickColor.new("White")
    body.Material = Enum.Material.Metal
    body.Anchored = true
    body.Position = position
    body.Parent = ship
    
    -- Set the body as primary part FIRST
    ship.PrimaryPart = body
    
    -- Create detailed cockpit with proper X-Wing shape
    local cockpit = Instance.new("Part")
    cockpit.Name = "Cockpit"
    cockpit.Size = Vector3.new(3.5, 2.2, 4.5)
    cockpit.Shape = Enum.PartType.Ball
    cockpit.BrickColor = BrickColor.new("Bright blue")
    cockpit.Material = Enum.Material.Metal
    cockpit.Anchored = true
    cockpit.Position = body.Position + Vector3.new(0, 1.5, 7)
    cockpit.Parent = ship
    
    -- Add cockpit glass effect with proper transparency
    local cockpitGlass = Instance.new("Part")
    cockpitGlass.Name = "CockpitGlass"
    cockpitGlass.Size = Vector3.new(3, 2, 4)
    cockpitGlass.Shape = Enum.PartType.Ball
    cockpitGlass.BrickColor = BrickColor.new("Bright blue")
    cockpitGlass.Material = Enum.Material.Glass
    cockpitGlass.Transparency = 0.4
    cockpitGlass.Anchored = true
    cockpitGlass.Position = cockpit.Position + Vector3.new(0, 0, 0.5)
    cockpitGlass.Parent = ship
    
    -- Create movie-accurate X-Wing wings with proper angles and details
    local wingPositions = {
        {x = -18, z = 3, rotation = 45, size = Vector3.new(28, 0.6, 10)},     -- Left front wing
        {x = 18, z = 3, rotation = -45, size = Vector3.new(28, 0.6, 10)},    -- Right front wing
        {x = -18, z = -7, rotation = -45, size = Vector3.new(28, 0.6, 10)},  -- Left back wing
        {x = 18, z = -7, rotation = 45, size = Vector3.new(28, 0.6, 10)}     -- Right back wing
    }
    
    for i, wingPos in ipairs(wingPositions) do
        local wing = Instance.new("Part")
        wing.Name = "Wing" .. i
        wing.Size = wingPos.size
        wing.BrickColor = BrickColor.new("White")
        wing.Material = Enum.Material.Metal
        wing.Anchored = true
        wing.Position = body.Position + Vector3.new(wingPos.x, 0, wingPos.z)
        wing.Parent = ship
        
        -- Rotate wing to proper X-Wing position
        wing.CFrame = CFrame.new(wing.Position) * CFrame.Angles(0, math.rad(wingPos.rotation), 0)
        
        -- Add detailed wing features - laser cannons
        local laserCannon = Instance.new("Part")
        laserCannon.Name = "LaserCannon" .. i
        laserCannon.Size = Vector3.new(0.4, 0.4, 10)
        laserCannon.BrickColor = BrickColor.new("Dark stone grey")
        laserCannon.Material = Enum.Material.Metal
        laserCannon.Anchored = true
        laserCannon.Position = wing.Position + Vector3.new(0, 0.8, 0)
        laserCannon.Parent = ship
        
        -- Add laser cannon glow with red color
        local laserLight = Instance.new("PointLight")
        laserLight.Color = Color3.fromRGB(255, 0, 0)
        laserLight.Range = 12
        laserLight.Brightness = 1
        laserLight.Parent = laserCannon
        
        -- Add wing tip details
        local wingTip = Instance.new("Part")
        wingTip.Name = "WingTip" .. i
        wingTip.Size = Vector3.new(1, 0.8, 2)
        wingTip.BrickColor = BrickColor.new("Bright yellow")
        wingTip.Material = Enum.Material.Neon
        wingTip.Anchored = true
        wingTip.Position = wing.Position + Vector3.new(0, 0.4, 5)
        wingTip.Parent = ship
        
        -- Add wing tip glow
        local tipLight = Instance.new("PointLight")
        tipLight.Color = Color3.fromRGB(255, 255, 0)
        tipLight.Range = 8
        tipLight.Brightness = 0.6
        tipLight.Parent = wingTip
        
        -- Add wing surface details
        for j = 1, 5 do
            local surfaceDetail = Instance.new("Part")
            surfaceDetail.Name = "WingDetail" .. i .. "_" .. j
            surfaceDetail.Size = Vector3.new(0.2, 0.1, 2)
            surfaceDetail.BrickColor = BrickColor.new("Light grey")
            surfaceDetail.Material = Enum.Material.Metal
            surfaceDetail.Anchored = true
            surfaceDetail.Position = wing.Position + Vector3.new(0, 0.4, (j - 3) * 2)
            surfaceDetail.Parent = ship
        end
    end
    
    -- Create detailed engine exhausts with proper positioning
    local engine1 = Instance.new("Part")
    engine1.Name = "Engine1"
    engine1.Size = Vector3.new(1.2, 1.2, 5)
    engine1.BrickColor = BrickColor.new("Dark stone grey")
    engine1.Material = Enum.Material.Metal
    engine1.Anchored = true
    engine1.Position = body.Position + Vector3.new(-1.2, 0, -10)
    engine1.Parent = ship
    
    local engine2 = Instance.new("Part")
    engine2.Name = "Engine2"
    engine2.Size = Vector3.new(1.2, 1.2, 5)
    engine2.BrickColor = BrickColor.new("Dark stone grey")
    engine2.Material = Enum.Material.Metal
    engine2.Anchored = true
    engine2.Position = body.Position + Vector3.new(1.2, 0, -10)
    engine2.Parent = ship
    
    -- Add detailed engine glow with multiple colors
    local engineLight1 = Instance.new("PointLight")
    engineLight1.Color = Color3.fromRGB(255, 100, 0)
    engineLight1.Range = 25
    engineLight1.Brightness = 2
    engineLight1.Parent = engine1
    
    local engineLight2 = Instance.new("PointLight")
    engineLight2.Color = Color3.fromRGB(255, 100, 0)
    engineLight2.Range = 25
    engineLight2.Brightness = 2
    engineLight2.Parent = engine2
    
    -- Add engine exhaust particles effect
    local exhaust1 = Instance.new("Part")
    exhaust1.Name = "Exhaust1"
    exhaust1.Size = Vector3.new(0.4, 0.4, 3)
    exhaust1.BrickColor = BrickColor.new("Bright orange")
    exhaust1.Material = Enum.Material.Neon
    exhaust1.Anchored = true
    exhaust1.Position = engine1.Position + Vector3.new(0, 0, -4)
    exhaust1.Parent = ship
    
    local exhaust2 = Instance.new("Part")
    exhaust2.Name = "Exhaust2"
    exhaust2.Size = Vector3.new(0.4, 0.4, 3)
    exhaust2.BrickColor = BrickColor.new("Bright orange")
    exhaust2.Material = Enum.Material.Neon
    exhaust2.Anchored = true
    exhaust2.Position = engine2.Position + Vector3.new(0, 0, -4)
    exhaust2.Parent = ship
    
    -- Add nose cone with proper X-Wing shape
    local noseCone = Instance.new("Part")
    noseCone.Name = "NoseCone"
    noseCone.Size = Vector3.new(2.5, 1.8, 5)
    noseCone.Shape = Enum.PartType.Ball
    noseCone.BrickColor = BrickColor.new("White")
    noseCone.Material = Enum.Material.Metal
    noseCone.Anchored = true
    noseCone.Position = body.Position + Vector3.new(0, 0, 12.5)
    noseCone.Parent = ship
    
    -- Add R2-D2 unit on top with proper positioning
    local r2Unit = Instance.new("Part")
    r2Unit.Name = "R2Unit"
    r2Unit.Size = Vector3.new(1.8, 1.8, 1.8)
    r2Unit.Shape = Enum.PartType.Ball
    r2Unit.BrickColor = BrickColor.new("Bright blue")
    r2Unit.Material = Enum.Material.Metal
    r2Unit.Anchored = true
    r2Unit.Position = body.Position + Vector3.new(0, 2.5, 0)
    r2Unit.Parent = ship
    
    -- Add R2 unit details - the iconic eye
    local r2Eye = Instance.new("Part")
    r2Eye.Name = "R2Eye"
    r2Eye.Size = Vector3.new(0.4, 0.4, 0.4)
    r2Eye.Shape = Enum.PartType.Ball
    r2Eye.BrickColor = BrickColor.new("Bright yellow")
    r2Eye.Material = Enum.Material.Neon
    r2Eye.Anchored = true
    r2Eye.Position = r2Unit.Position + Vector3.new(0, 0.5, 0.8)
    r2Eye.Parent = ship
    
    -- Add R2 eye glow
    local r2Light = Instance.new("PointLight")
    r2Light.Color = Color3.fromRGB(255, 255, 0)
    r2Light.Range = 10
    r2Light.Brightness = 0.8
    r2Light.Parent = r2Eye
    
    -- Add landing gear with proper X-Wing design
    local landingGear1 = Instance.new("Part")
    landingGear1.Name = "LandingGear1"
    landingGear1.Size = Vector3.new(0.4, 4, 0.4)
    landingGear1.BrickColor = BrickColor.new("Dark stone grey")
    landingGear1.Material = Enum.Material.Metal
    landingGear1.Anchored = true
    landingGear1.Position = body.Position + Vector3.new(-1.5, -1, 0)
    landingGear1.Parent = ship
    
    local landingGear2 = Instance.new("Part")
    landingGear2.Name = "LandingGear2"
    landingGear2.Size = Vector3.new(0.4, 4, 0.4)
    landingGear2.BrickColor = BrickColor.new("Dark stone grey")
    landingGear2.Material = Enum.Material.Metal
    landingGear2.Anchored = true
    landingGear2.Position = body.Position + Vector3.new(1.5, -1, 0)
    landingGear2.Parent = ship
    
    -- Add landing gear feet
    local gearFoot1 = Instance.new("Part")
    gearFoot1.Name = "GearFoot1"
    gearFoot1.Size = Vector3.new(1.5, 0.3, 1.5)
    gearFoot1.BrickColor = BrickColor.new("Dark stone grey")
    gearFoot1.Material = Enum.Material.Metal
    gearFoot1.Anchored = true
    gearFoot1.Position = landingGear1.Position + Vector3.new(0, -2, 0)
    gearFoot1.Parent = ship
    
    local gearFoot2 = Instance.new("Part")
    gearFoot2.Name = "GearFoot2"
    gearFoot2.Size = Vector3.new(1.5, 0.3, 1.5)
    gearFoot2.BrickColor = BrickColor.new("Dark stone grey")
    gearFoot2.Material = Enum.Material.Metal
    gearFoot2.Anchored = true
    gearFoot2.Position = landingGear2.Position + Vector3.new(0, -2, 0)
    gearFoot2.Parent = ship
    
    -- Add wing fold mechanism details
    local wingFold1 = Instance.new("Part")
    wingFold1.Name = "WingFold1"
    wingFold1.Size = Vector3.new(1, 1, 1)
    wingFold1.BrickColor = BrickColor.new("Dark stone grey")
    wingFold1.Material = Enum.Material.Metal
    wingFold1.Anchored = true
    wingFold1.Position = body.Position + Vector3.new(-2, 0, 0)
    wingFold1.Parent = ship
    
    local wingFold2 = Instance.new("Part")
    wingFold2.Name = "WingFold2"
    wingFold2.Size = Vector3.new(1, 1, 1)
    wingFold2.BrickColor = BrickColor.new("Dark stone grey")
    wingFold2.Material = Enum.Material.Metal
    wingFold2.Anchored = true
    wingFold2.Position = body.Position + Vector3.new(2, 0, 0)
    wingFold2.Parent = ship
    
    -- Add proton torpedo launcher
    local torpedoLauncher = Instance.new("Part")
    torpedoLauncher.Name = "TorpedoLauncher"
    torpedoLauncher.Size = Vector3.new(0.8, 0.8, 3)
    torpedoLauncher.BrickColor = BrickColor.new("Dark stone grey")
    torpedoLauncher.Material = Enum.Material.Metal
    torpedoLauncher.Anchored = true
    torpedoLauncher.Position = body.Position + Vector3.new(0, 0, -12)
    torpedoLauncher.Parent = ship
    
    -- Add torpedo launcher glow
    local torpedoLight = Instance.new("PointLight")
    torpedoLight.Color = Color3.fromRGB(0, 150, 255)
    torpedoLight.Range = 15
    torpedoLight.Brightness = 0.8
    torpedoLight.Parent = torpedoLauncher
    
    -- Add hundreds of surface detail parts for movie-quality appearance
    for i = 1, 20 do
        -- Add surface panels
        local panel = Instance.new("Part")
        panel.Name = "SurfacePanel" .. i
        panel.Size = Vector3.new(0.1, 0.1, math.random(1, 3))
        panel.BrickColor = BrickColor.new("Light grey")
        panel.Material = Enum.Material.Metal
        panel.Anchored = true
        panel.Position = body.Position + Vector3.new(
            math.random(-1.5, 1.5),
            math.random(-0.5, 0.5),
            math.random(-8, 8)
        )
        panel.Parent = ship
        
        -- Add surface rivets
        local rivet = Instance.new("Part")
        rivet.Name = "Rivet" .. i
        rivet.Size = Vector3.new(0.2, 0.2, 0.2)
        rivet.Shape = Enum.PartType.Ball
        rivet.BrickColor = BrickColor.new("Dark stone grey")
        rivet.Material = Enum.Material.Metal
        rivet.Anchored = true
        rivet.Position = body.Position + Vector3.new(
            math.random(-1.8, 1.8),
            math.random(-0.8, 0.8),
            math.random(-9, 9)
        )
        rivet.Parent = ship
    end
    
    -- Add engine cooling fins
    for i = 1, 8 do
        local coolingFin = Instance.new("Part")
        coolingFin.Name = "CoolingFin" .. i
        coolingFin.Size = Vector3.new(0.1, 0.8, 2)
        coolingFin.BrickColor = BrickColor.new("Dark stone grey")
        coolingFin.Material = Enum.Material.Metal
        coolingFin.Anchored = true
        coolingFin.Position = engine1.Position + Vector3.new(
            math.random(-0.5, 0.5),
            math.random(-0.3, 0.3),
            math.random(-2, 2)
        )
        coolingFin.Parent = ship
        
        local coolingFin2 = Instance.new("Part")
        coolingFin2.Name = "CoolingFin2_" .. i
        coolingFin2.Size = Vector3.new(0.1, 0.8, 2)
        coolingFin2.BrickColor = BrickColor.new("Dark stone grey")
        coolingFin2.Material = Enum.Material.Metal
        coolingFin2.Anchored = true
        coolingFin2.Position = engine2.Position + Vector3.new(
            math.random(-0.5, 0.5),
            math.random(-0.3, 0.3),
            math.random(-2, 2)
        )
        coolingFin2.Parent = ship
    end
    
    -- IMPORTANT: Keep the body as PrimaryPart for now - MakeShipFlyable will change it to VehicleSeat
    print("✅ X-Wing model created with " .. #ship:GetChildren() .. " parts")
end

function SpaceshipSpawner:CreateTIEModel(ship, position)
    -- Create TIE Fighter central sphere
    local center = Instance.new("Part")
    center.Name = "Center"
    center.Size = Vector3.new(6, 6, 6)
    center.Shape = Enum.PartType.Ball
    center.BrickColor = BrickColor.new("Dark stone grey")
    center.Material = Enum.Material.Metal
    center.Anchored = true
    center.Position = position
    center.Parent = ship
    
    -- Create TIE Fighter wings
    local leftWing = Instance.new("Part")
    leftWing.Name = "LeftWing"
    leftWing.Size = Vector3.new(25, 0.5, 25)
    leftWing.Shape = Enum.PartType.Ball
    leftWing.BrickColor = BrickColor.new("Dark stone grey")
    leftWing.Material = Enum.Material.Metal
    leftWing.Anchored = true
    leftWing.Position = center.Position + Vector3.new(-15, 0, 0)
    leftWing.Parent = ship
    
    local rightWing = Instance.new("Part")
    rightWing.Name = "RightWing"
    rightWing.Size = Vector3.new(25, 0.5, 25)
    rightWing.Shape = Enum.PartType.Ball
    rightWing.BrickColor = BrickColor.new("Dark stone grey")
    rightWing.Material = Enum.Material.Metal
    rightWing.Anchored = true
    rightWing.Position = center.Position + Vector3.new(15, 0, 0)
    rightWing.Parent = ship
    
    -- Create cockpit
    local cockpit = Instance.new("Part")
    cockpit.Name = "Cockpit"
    cockpit.Size = Vector3.new(4, 4, 4)
    cockpit.Shape = Enum.PartType.Ball
    cockpit.BrickColor = BrickColor.new("Bright blue")
    cockpit.Material = Enum.Material.Metal
    cockpit.Anchored = true
    cockpit.Position = center.Position + Vector3.new(0, 0, 2)
    cockpit.Parent = ship
    
    -- Set primary part
    ship.PrimaryPart = center
end

function SpaceshipSpawner:CreateBasicShipModel(ship, shipType, position)
    -- Create basic ship body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = self:GetShipSize(shipType)
    body.BrickColor = self:GetShipColor(shipType)
    body.Material = Enum.Material.Metal
    body.Anchored = true
    body.Position = position
    body.Parent = ship
    
    -- Set primary part
    ship.PrimaryPart = body
end

function SpaceshipSpawner:GetShipSize(shipType)
    local sizes = {
        XWing = Vector3.new(20, 8, 15),
        TIE = Vector3.new(25, 10, 20),
        MillenniumFalcon = Vector3.new(40, 15, 30),
        StarDestroyer = Vector3.new(100, 30, 60),
        Snowspeeder = Vector3.new(18, 6, 12),
        NabooFighter = Vector3.new(22, 7, 16),
        ImperialShuttle = Vector3.new(35, 12, 25)
    }
    
    return sizes[shipType] or Vector3.new(20, 8, 15)
end

function SpaceshipSpawner:GetShipColor(shipType)
    local colors = {
        XWing = BrickColor.new("White"),
        TIE = BrickColor.new("Dark stone grey"),
        MillenniumFalcon = BrickColor.new("Dark orange"),
        StarDestroyer = BrickColor.new("Dark stone grey"),
        Snowspeeder = BrickColor.new("White"),
        NabooFighter = BrickColor.new("Bright blue"),
        ImperialShuttle = BrickColor.new("Dark stone grey")
    }
    
    return colors[shipType] or BrickColor.new("Dark stone grey")
end

function SpaceshipSpawner:CreateXWingWings(ship, body)
    -- Create X-Wing style wings
    for i = 1, 4 do
        local wing = Instance.new("Part")
        wing.Name = "Wing" .. i
        wing.Size = Vector3.new(25, 1, 8)
        wing.BrickColor = BrickColor.new("White")
        wing.Material = Enum.Material.Metal
        wing.Anchored = true
        wing.Parent = ship
        
        -- Position wings
        local angle = (i - 1) * 90
        local distance = 15
        local x = math.cos(math.rad(angle)) * distance
        local z = math.sin(math.rad(angle)) * distance
        wing.Position = body.Position + Vector3.new(x, 0, z)
    end
end

function SpaceshipSpawner:CreateTIEWings(ship, body)
    -- Create TIE Fighter style wings
    for i = 1, 2 do
        local wing = Instance.new("Part")
        wing.Name = "Wing" .. i
        wing.Size = Vector3.new(30, 1, 30)
        wing.Shape = Enum.PartType.Ball
        wing.BrickColor = BrickColor.new("Dark stone grey")
        wing.Material = Enum.Material.Metal
        wing.Anchored = true
        wing.Parent = ship
        
        -- Position wings on sides
        local x = (i == 1) and -20 or 20
        wing.Position = body.Position + Vector3.new(x, 0, 0)
    end
end

function SpaceshipSpawner:CreateFalconDetails(ship, body)
    -- Create Millennium Falcon details
    local cockpit = Instance.new("Part")
    cockpit.Name = "Cockpit"
    cockpit.Size = Vector3.new(15, 8, 15)
    cockpit.Shape = Enum.PartType.Ball
    cockpit.BrickColor = BrickColor.new("Bright blue")
    cockpit.Material = Enum.Material.Metal
    cockpit.Anchored = true
    cockpit.Position = body.Position + Vector3.new(0, 5, 0)
    cockpit.Parent = ship
end

function SpaceshipSpawner:AddShipBehavior(ship, planetName)
    -- Make ship flyable
    local body = ship.PrimaryPart
    if not body then return end
    
    -- Add flight script using a different approach
    local flightScript = Instance.new("LocalScript")
    flightScript.Name = "FlightScript"
    flightScript.Parent = body
    
    -- Use a simple behavior instead of complex script source
    spawn(function()
        local startPos = body.Position
        local flightRadius = 200
        local flightHeight = 100
        local speed = 0.5
        
        while body and body.Parent do
            wait(0.1)
            
            -- Create circular flight pattern
            local time = tick() * speed
            local x = startPos.X + math.cos(time) * flightRadius
            local z = startPos.Z + math.sin(time) * flightRadius
            local y = startPos.Y + math.sin(time * 2) * flightHeight
            
            if body and body.Parent then
                body.Position = Vector3.new(x, y, z)
            else
                break
            end
        end
    end)
end

function SpaceshipSpawner:GetSpawnPointsForPlanet(planetName)
    local planetSpawnPoints = {}
    
    for _, spawnData in ipairs(self.spawnPoints) do
        if spawnData.planet == planetName then
            table.insert(planetSpawnPoints, spawnData.point)
        end
    end
    
    return planetSpawnPoints
end

function SpaceshipSpawner:GetShipsOnPlanet(planetName)
    local count = 0
    
    for _, shipData in ipairs(self.activeShips) do
        if shipData.planet == planetName then
            count = count + 1
        end
    end
    
    return count
end

function SpaceshipSpawner:GetAllShips()
    return self.activeShips
end

function SpaceshipSpawner:ClearAllShips()
    for _, shipData in ipairs(self.activeShips) do
        if shipData.ship and shipData.ship.Parent then
            shipData.ship:Destroy()
        end
    end
    
    self.activeShips = {}
    print("🗑️ All ships cleared")
end

-- Return the SpaceshipSpawner class
return SpaceshipSpawner 