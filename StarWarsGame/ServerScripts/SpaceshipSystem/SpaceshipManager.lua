-- SpaceshipManager.lua
-- Manages all spaceship-related functionality in STAR WARS: GALACTIC EMPIRE

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local SpaceshipManager = {}
SpaceshipManager.__index = SpaceshipManager

-- Spaceship Types and Stats
local SHIP_TYPES = {
    XWing = {
        name = "X-Wing Fighter",
        faction = "Rebel",
        health = 200,
        speed = 120,
        agility = 0.9,
        weapons = {"Laser Cannons", "Proton Torpedoes"},
        cost = 5000,
        model = "XWingModel",
        description = "Classic Rebel starfighter with excellent maneuverability"
    },
    TIE = {
        name = "TIE Fighter",
        faction = "Empire",
        health = 150,
        speed = 130,
        agility = 0.8,
        weapons = {"Laser Cannons"},
        cost = 4000,
        model = "TIEModel",
        description = "Fast Imperial fighter with twin ion engines"
    },
    MillenniumFalcon = {
        name = "YT-1300 Freighter",
        faction = "Neutral",
        health = 400,
        speed = 100,
        agility = 0.7,
        weapons = {"Quad Laser Cannons", "Concussion Missiles"},
        cost = 15000,
        model = "FalconModel",
        description = "Legendary smuggling ship with hidden compartments"
    },
    StarDestroyer = {
        name = "Imperial Star Destroyer",
        faction = "Empire",
        health = 2000,
        speed = 60,
        agility = 0.3,
        weapons = {"Heavy Turbolasers", "Ion Cannons", "TIE Fighter Squadrons"},
        cost = 50000,
        model = "StarDestroyerModel",
        description = "Massive Imperial capital ship with overwhelming firepower"
    }
}

-- Hyperspace Routes
local HYPERSPACE_ROUTES = {
    Coruscant = {
        Tatooine = {time = 5, cost = 100},
        Hoth = {time = 8, cost = 150},
        Naboo = {time = 3, cost = 75}
    },
    Tatooine = {
        Coruscant = {time = 5, cost = 100},
        Hoth = {time = 10, cost = 200},
        Naboo = {time = 7, cost = 125}
    },
    Hoth = {
        Coruscant = {time = 8, cost = 150},
        Tatooine = {time = 10, cost = 200},
        Naboo = {time = 12, cost = 250}
    }
}

function SpaceshipManager.new()
    local self = setmetatable({}, SpaceshipManager)
    
    self.activeShips = {}
    self.shipQueue = {}
    self.combatInstances = {}
    self.hyperspaceJumps = {}
    
    return self
end

function SpaceshipManager:Initialize()
    print("🚁 Initializing Spaceship System...")
    
    -- Set up ship spawning
    self:SetupShipSpawning()
    
    -- Start physics update loop
    self:StartPhysicsLoop()
    
    print("✅ Spaceship System initialized!")
end

function SpaceshipManager:SetupShipSpawning()
    -- Create ship spawn points on each planet
    for planetName, _ in pairs(HYPERSPACE_ROUTES) do
        self:CreateShipSpawnPoint(planetName)
    end
end

function SpaceshipManager:CreateShipSpawnPoint(planetName)
    local spawnPoint = Instance.new("Part")
    spawnPoint.Name = planetName .. "ShipSpawn"
    spawnPoint.Size = Vector3.new(20, 1, 20)
    spawnPoint.Position = Vector3.new(0, 200, 0) -- Above planet surface
    spawnPoint.Anchored = true
    spawnPoint.CanCollide = false
    spawnPoint.Transparency = 0.5
    spawnPoint.BrickColor = BrickColor.new("Bright blue")
    
    -- Add spawn point to workspace
    spawnPoint.Parent = workspace
    
    print("📍 Created ship spawn point for " .. planetName)
end

function SpaceshipManager:SpawnShip(player, shipType, planetName)
    local shipData = SHIP_TYPES[shipType]
    if not shipData then
        warn("Invalid ship type: " .. tostring(shipType))
        return nil
    end
    
    -- Check if player can afford the ship
    local playerData = self:GetPlayerData(player)
    if playerData.credits < shipData.cost then
        self:SendMessage(player, "❌ Insufficient credits! You need " .. shipData.cost .. " credits.")
        return nil
    end
    
    -- Create ship model (this would be a detailed 3D model in practice)
    local ship = self:CreateShipModel(shipType, shipData)
    
    -- Position ship at spawn point
    local spawnPoint = workspace:FindFirstChild(planetName .. "ShipSpawn")
    if spawnPoint then
        ship:PivotTo(spawnPoint.CFrame + Vector3.new(0, 10, 0))
    end
    
    -- Set up ship physics
    self:SetupShipPhysics(ship, shipData)
    
    -- Assign ship to player
    ship:SetAttribute("Owner", player.UserId)
    ship:SetAttribute("ShipType", shipType)
    ship:SetAttribute("Health", shipData.health)
    ship:SetAttribute("MaxHealth", shipData.health)
    
    -- Add to active ships
    self.activeShips[ship] = {
        owner = player.UserId,
        shipType = shipType,
        planet = planetName,
        lastUpdate = tick()
    }
    
    -- Deduct credits from player
    self:DeductCredits(player, shipData.cost)
    
    print("🚁 Spawned " .. shipType .. " for " .. player.Name .. " on " .. planetName)
    
    return ship
end

function SpaceshipManager:CreateShipModel(shipType, shipData)
    local ship = Instance.new("Model")
    ship.Name = shipType .. "_" .. tick()
    
    -- Create basic ship body (in practice, this would be a detailed 3D model)
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(10, 2, 15)
    body.BrickColor = BrickColor.new("Dark stone grey")
    body.Material = Enum.Material.Metal
    body.Parent = ship
    
    -- Create wings
    local leftWing = Instance.new("Part")
    leftWing.Name = "LeftWing"
    leftWing.Size = Vector3.new(8, 0.5, 6)
    leftWing.BrickColor = BrickColor.new("Dark stone grey")
    leftWing.Material = Enum.Material.Metal
    leftWing.CFrame = body.CFrame * CFrame.new(-6, 0, 0)
    leftWing.Parent = ship
    
    local rightWing = Instance.new("Part")
    rightWing.Name = "RightWing"
    rightWing.Size = Vector3.new(8, 0.5, 6)
    rightWing.BrickColor = BrickColor.new("Dark stone grey")
    rightWing.Material = Enum.Material.Metal
    rightWing.CFrame = body.CFrame * CFrame.new(6, 0, 0)
    rightWing.Parent = ship
    
    -- Create cockpit
    local cockpit = Instance.new("Part")
    cockpit.Name = "Cockpit"
    cockpit.Shape = Enum.PartType.Ball
    cockpit.Size = Vector3.new(3, 3, 3)
    cockpit.BrickColor = BrickColor.new("Bright blue")
    cockpit.Material = Enum.Material.Glass
    cockpit.CFrame = body.CFrame * CFrame.new(0, 1, 5)
    cockpit.Parent = ship
    
    -- Create primary part
    ship.PrimaryPart = body
    
    -- Add to workspace
    ship.Parent = workspace
    
    return ship
end

function SpaceshipManager:SetupShipPhysics(ship, shipData)
    -- Add physics properties
    local body = ship.PrimaryPart
    if body then
        -- Set up ship movement
        body:SetAttribute("Speed", shipData.speed)
        body:SetAttribute("Agility", shipData.agility)
        body:SetAttribute("MaxHealth", shipData.health)
        body:SetAttribute("CurrentHealth", shipData.health)
        
        -- Make ship flyable
        self:MakeShipFlyable(ship, shipData)
    end
end

function SpaceshipManager:MakeShipFlyable(ship, shipData)
    -- This would implement the actual flight controls
    -- For now, we'll set up the basic structure
    
    local body = ship.PrimaryPart
    if not body then return end
    
    -- Add flight script to the ship
    local flightScript = Instance.new("Script")
    flightScript.Name = "FlightScript"
    flightScript.Parent = ship
    
    -- Create a LocalScript for client-side flight controls
    local clientFlightScript = Instance.new("LocalScript")
    clientFlightScript.Name = "ClientFlightScript"
    clientFlightScript.Parent = ship
    
    -- Set up ship physics
    body:SetAttribute("Speed", shipData.speed)
    body:SetAttribute("Agility", shipData.agility)
    body:SetAttribute("MaxHealth", shipData.health)
    body:SetAttribute("CurrentHealth", shipData.health)
    body:SetAttribute("IsFlyable", true)
    
    -- Make ship enterable
    self:MakeShipEnterable(ship, shipData)
    
    print("✈️ Made " .. ship.Name .. " flyable and enterable")
end

function SpaceshipManager:MakeShipEnterable(ship, shipData)
    local body = ship.PrimaryPart
    if not body then return end
    
    -- Create a seat for the pilot
    local pilotSeat = Instance.new("Seat")
    pilotSeat.Name = "PilotSeat"
    pilotSeat.Size = Vector3.new(2, 1, 2)
    pilotSeat.Position = body.Position + Vector3.new(0, 2, 5)
    pilotSeat.BrickColor = BrickColor.new("Bright blue")
    pilotSeat.Material = Enum.Material.Plastic
    pilotSeat.Parent = ship
    
    -- Add interaction prompt for entering ship
    local enterPrompt = Instance.new("ProximityPrompt")
    enterPrompt.Name = "EnterShipPrompt"
    enterPrompt.ObjectText = shipData.name
    enterPrompt.ActionText = "Enter Ship"
    enterPrompt.MaxActivationDistance = 8
    enterPrompt.HoldDuration = 0.5
    enterPrompt.Parent = pilotSeat
    
    -- Connect prompt to ship entry
    enterPrompt.Triggered:Connect(function(player)
        self:PlayerEnterShip(player, ship)
    end)
    
    -- Add exit prompt
    local exitPrompt = Instance.new("ProximityPrompt")
    exitPrompt.Name = "ExitShipPrompt"
    exitPrompt.ObjectText = shipData.name
    exitPrompt.ActionText = "Exit Ship"
    exitPrompt.MaxActivationDistance = 8
    exitPrompt.HoldDuration = 0.5
    exitPrompt.Parent = pilotSeat
    exitPrompt.RequiresLineOfSight = false
    
    -- Connect exit prompt
    exitPrompt.Triggered:Connect(function(player)
        self:PlayerExitShip(player, ship)
    end)
    
    -- Store ship data
    ship:SetAttribute("PilotSeat", pilotSeat)
    ship:SetAttribute("ShipType", shipData.name)
    ship:SetAttribute("MaxSpeed", shipData.speed)
    ship:SetAttribute("Agility", shipData.agility)
end

function SpaceshipManager:PlayerEnterShip(player, ship)
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    local pilotSeat = ship:GetAttribute("PilotSeat")
    if not pilotSeat then return end
    
    -- Sit the player in the ship
    humanoid.Sit = true
    pilotSeat:Sit(humanoid)
    
    -- Store that player is piloting this ship
    ship:SetAttribute("Pilot", player.UserId)
    
    -- Enable ship controls
    self:EnableShipControls(player, ship)
    
    print("👨‍✈️ " .. player.Name .. " entered " .. ship.Name)
end

function SpaceshipManager:PlayerExitShip(player, ship)
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    -- Remove player from ship
    humanoid.Sit = false
    
    -- Clear pilot attribute
    ship:SetAttribute("Pilot", nil)
    
    -- Disable ship controls
    self:DisableShipControls(player, ship)
    
    print("👋 " .. player.Name .. " exited " .. ship.Name)
end

function SpaceshipManager:EnableShipControls(player, ship)
    -- Create a LocalScript for ship controls
    local controlsScript = Instance.new("LocalScript")
    controlsScript.Name = "ShipControls"
    controlsScript.Parent = ship
    
    -- Set up the controls script
    controlsScript.Source = [[
        local Players = game:GetService("Players")
        local UserInputService = game:GetService("UserInputService")
        local RunService = game:GetService("RunService")
        
        local player = Players.LocalPlayer
        local ship = script.Parent
        local body = ship.PrimaryPart
        
        if not body then return end
        
        -- Ship control variables
        local isFlying = false
        local currentSpeed = 0
        local maxSpeed = ship:GetAttribute("MaxSpeed") or 100
        local agility = ship:GetAttribute("Agility") or 0.8
        
        -- Control functions
        local function handleInput(input, gameProcessed)
            if gameProcessed then return end
            
            if input.KeyCode == Enum.KeyCode.W then
                -- Forward
                currentSpeed = math.min(maxSpeed, currentSpeed + 5)
            elseif input.KeyCode == Enum.KeyCode.S then
                -- Backward
                currentSpeed = math.max(-maxSpeed/2, currentSpeed - 5)
            elseif input.KeyCode == Enum.KeyCode.A then
                -- Turn left
                body.CFrame = body.CFrame * CFrame.Angles(0, math.rad(2), 0)
            elseif input.KeyCode == Enum.KeyCode.D then
                -- Turn right
                body.CFrame = body.CFrame * CFrame.Angles(0, math.rad(-2), 0)
            elseif input.KeyCode == Enum.KeyCode.Space then
                -- Up
                body.CFrame = body.CFrame + Vector3.new(0, 2, 0)
            elseif input.KeyCode == Enum.KeyCode.LeftShift then
                -- Down
                body.CFrame = body.CFrame + Vector3.new(0, -2, 0)
            elseif input.KeyCode == Enum.KeyCode.Q then
                -- Roll left
                body.CFrame = body.CFrame * CFrame.Angles(0, 0, math.rad(2))
            elseif input.KeyCode == Enum.KeyCode.E then
                -- Roll right
                body.CFrame = body.CFrame * CFrame.Angles(0, 0, math.rad(-2))
            end
        end
        
        -- Connect input events
        UserInputService.InputBegan:Connect(handleInput)
        
        -- Flight loop
        RunService.Heartbeat:Connect(function(deltaTime)
            if currentSpeed ~= 0 then
                -- Move ship forward
                local forward = body.CFrame.LookVector
                body.CFrame = body.CFrame + forward * currentSpeed * deltaTime
                
                -- Apply drag
                currentSpeed = currentSpeed * 0.95
                
                -- Stop if speed is very low
                if math.abs(currentSpeed) < 0.1 then
                    currentSpeed = 0
                end
            end
        end)
        
        print("🚁 Ship controls enabled for " .. player.Name)
        print("Controls: WASD to move, Space/Shift for up/down, QE for roll")
    ]]
    
    print("🎮 Ship controls enabled for " .. player.Name)
end

function SpaceshipManager:DisableShipControls(player, ship)
    local controlsScript = ship:FindFirstChild("ShipControls")
    if controlsScript then
        controlsScript:Destroy()
    end
    
    print("🎮 Ship controls disabled for " .. player.Name)
end

function SpaceshipManager:StartHyperspaceJump(player, ship, destinationPlanet)
    local currentPlanet = self.activeShips[ship].planet
    local route = HYPERSPACE_ROUTES[currentPlanet] and HYPERSPACE_ROUTES[currentPlanet][destinationPlanet]
    
    if not route then
        self:SendMessage(player, "❌ No hyperspace route to " .. destinationPlanet)
        return false
    end
    
    -- Check if player can afford the jump
    local playerData = self:GetPlayerData(player)
    if playerData.credits < route.cost then
        self:SendMessage(player, "❌ Insufficient credits for hyperspace jump!")
        return false
    end
    
    -- Start hyperspace sequence
    self:BeginHyperspaceSequence(ship, destinationPlanet, route)
    
    -- Deduct credits
    self:DeductCredits(player, route.cost)
    
    return true
end

function SpaceshipManager:BeginHyperspaceSequence(ship, destinationPlanet, route)
    print("🌌 Starting hyperspace jump to " .. destinationPlanet)
    
    -- Create hyperspace effect
    local hyperspaceEffect = Instance.new("Part")
    hyperspaceEffect.Name = "HyperspaceEffect"
    hyperspaceEffect.Size = Vector3.new(50, 50, 50)
    hyperspaceEffect.Position = ship.PrimaryPart.Position
    hyperspaceEffect.Anchored = true
    hyperspaceEffect.CanCollide = false
    hyperspaceEffect.Transparency = 0.3
    hyperspaceEffect.BrickColor = BrickColor.new("Bright blue")
    hyperspaceEffect.Material = Enum.Material.Neon
    hyperspaceEffect.Parent = workspace
    
    -- Animate hyperspace effect
    local tween = TweenService:Create(hyperspaceEffect, TweenInfo.new(route.time), {
        Size = Vector3.new(200, 200, 200),
        Transparency = 1
    })
    
    tween:Play()
    
    -- Move ship to destination after delay
    local connection
    connection = tween.Completed:Connect(function()
        self:CompleteHyperspaceJump(ship, destinationPlanet)
        hyperspaceEffect:Destroy()
        connection:Disconnect()
    end)
    
    -- Store hyperspace jump info
    self.hyperspaceJumps[ship] = {
        destination = destinationPlanet,
        startTime = tick(),
        duration = route.time
    }
end

function SpaceshipManager:CompleteHyperspaceJump(ship, destinationPlanet)
    print("🌌 Hyperspace jump completed to " .. destinationPlanet)
    
    -- Update ship location
    if self.activeShips[ship] then
        self.activeShips[ship].planet = destinationPlanet
    end
    
    -- Position ship at destination spawn point
    local spawnPoint = workspace:FindFirstChild(destinationPlanet .. "ShipSpawn")
    if spawnPoint then
        ship:PivotTo(spawnPoint.CFrame + Vector3.new(0, 10, 0))
    end
    
    -- Remove from hyperspace jumps
    self.hyperspaceJumps[ship] = nil
    
    -- Notify owner
    local ownerId = ship:GetAttribute("Owner")
    local owner = Players:GetPlayerByUserId(ownerId)
    if owner then
        self:SendMessage(owner, "✅ Hyperspace jump completed! Welcome to " .. destinationPlanet)
    end
end

function SpaceshipManager:StartPhysicsLoop()
    RunService.Heartbeat:Connect(function(deltaTime)
        self:UpdateShipPhysics(deltaTime)
    end)
end

function SpaceshipManager:UpdateShipPhysics(deltaTime)
    for ship, shipData in pairs(self.activeShips) do
        if ship and ship.PrimaryPart then
            -- Update ship physics here
            -- This would include gravity, drag, engine effects, etc.
            
            shipData.lastUpdate = tick()
        end
    end
end

function SpaceshipManager:GetPlayerData(player)
    -- This would get player data from the main game manager
    -- For now, return a basic structure
    return {
        credits = 1000,
        faction = "Neutral"
    }
end

function SpaceshipManager:DeductCredits(player, amount)
    -- This would deduct credits from the player's account
    print("💰 Deducted " .. amount .. " credits from " .. player.Name)
end

function SpaceshipManager:SendMessage(player, message)
    -- This would send a message to the player
    print("📨 [" .. player.Name .. "] " .. message)
end

-- Return the SpaceshipManager class
return SpaceshipManager 