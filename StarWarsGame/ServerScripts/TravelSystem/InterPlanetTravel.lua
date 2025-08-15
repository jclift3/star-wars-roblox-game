-- InterPlanetTravel.lua
-- Manages travel between planets using hyperspace portals

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local InterPlanetTravel = {}
InterPlanetTravel.__index = InterPlanetTravel

-- Travel routes between planets
local TRAVEL_ROUTES = {
    Coruscant = {
        {destination = "Tatooine", cost = 1000, time = 30},
        {destination = "Hoth", cost = 1500, time = 45},
        {destination = "Naboo", cost = 800, time = 25},
        {destination = "Mustafar", cost = 1200, time = 35},
        {destination = "Kamino", cost = 900, time = 28}
    },
    Tatooine = {
        {destination = "Coruscant", cost = 1000, time = 30},
        {destination = "Hoth", cost = 1800, time = 55},
        {destination = "Naboo", cost = 1400, time = 40},
        {destination = "Mustafar", cost = 1600, time = 48},
        {destination = "Kamino", cost = 1200, time = 35}
    },
    Hoth = {
        {destination = "Coruscant", cost = 1500, time = 45},
        {destination = "Tatooine", cost = 1800, time = 55},
        {destination = "Naboo", cost = 2000, time = 60},
        {destination = "Mustafar", cost = 2500, time = 75},
        {destination = "Kamino", cost = 2200, time = 65}
    },
    Naboo = {
        {destination = "Coruscant", cost = 800, time = 25},
        {destination = "Tatooine", cost = 1400, time = 40},
        {destination = "Hoth", cost = 2000, time = 60},
        {destination = "Mustafar", cost = 1800, time = 50},
        {destination = "Kamino", cost = 1100, time = 32}
    },
    Mustafar = {
        {destination = "Coruscant", cost = 1200, time = 35},
        {destination = "Tatooine", cost = 1600, time = 48},
        {destination = "Hoth", cost = 2500, time = 75},
        {destination = "Naboo", cost = 1800, time = 50},
        {destination = "Kamino", cost = 1500, time = 42}
    },
    Kamino = {
        {destination = "Coruscant", cost = 900, time = 28},
        {destination = "Tatooine", cost = 1200, time = 35},
        {destination = "Hoth", cost = 2200, time = 65},
        {destination = "Naboo", cost = 1100, time = 32},
        {destination = "Mustafar", cost = 1500, time = 42}
    }
}

function InterPlanetTravel.new()
    local self = setmetatable({}, InterPlanetTravel)
    
    self.spaceEnvironment = nil
    
    return self
end

function InterPlanetTravel:Initialize()
    print("🌌 Initializing Inter-Planet Travel System...")
    
    -- Create organized transport hubs
    self:CreateOrganizedTransportHubs()
    
    -- Create space environment
    self:CreateSpaceEnvironment()
    
    print("✅ Inter-Planet Travel System initialized!")
end

function InterPlanetTravel:CreateOrganizedTransportHubs()
    print("🌌 Creating organized transport hubs...")
    
    -- Wait for planets to exist
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
                print("✅ Planets found! Creating transport hubs...")
                break
            end
        end
        wait(1)
        waitTime = waitTime + 1
        print("⏳ Still waiting for planets... (" .. waitTime .. "/" .. maxWaitTime .. "s)")
    end
    
    if waitTime >= maxWaitTime then
        warn("❌ Timeout waiting for planets! Transport hubs may not work correctly.")
        return
    end
    
    -- Create transport hub on each planet
    for planetName, _ in pairs(TRAVEL_ROUTES) do
        self:CreatePlanetTransportHub(planetName)
    end
    
    print("✅ All planet transport hubs created!")
end

function InterPlanetTravel:CreatePlanetTransportHub(planetName)
    print("🏗️ Creating transport hub on " .. planetName)
    
    -- Find the planet folder
    local planetFolder = Workspace:FindFirstChild("Planets")
    if not planetFolder then return end
    
    local planet = planetFolder:FindFirstChild(planetName)
    if not planet then return end
    
    -- Create transport hub folder
    local hubFolder = Instance.new("Folder")
    hubFolder.Name = "TransportHub"
    hubFolder.Parent = planet
    
    -- Create transport hub building
    local hubBuilding = Instance.new("Part")
    hubBuilding.Name = "HubBuilding"
    hubBuilding.Size = Vector3.new(50, 20, 60)
    hubBuilding.Position = self:GetPlanetSpawnPoint(planetName) + Vector3.new(0, 10, 40)
    hubBuilding.BrickColor = BrickColor.new("Bright blue")
    hubBuilding.Material = Enum.Material.Metal
    hubBuilding.Anchored = true
    hubBuilding.Parent = hubFolder
    
    -- Create hub roof
    local hubRoof = Instance.new("Part")
    hubRoof.Name = "HubRoof"
    hubRoof.Size = Vector3.new(60, 5, 70)
    hubRoof.Position = hubBuilding.Position + Vector3.new(0, 12.5, 0)
    hubRoof.BrickColor = BrickColor.new("Bright blue")
    hubRoof.Material = Enum.Material.Metal
    hubRoof.Anchored = true
    hubRoof.Parent = hubFolder
    
    -- Create access ramp
    local ramp = Instance.new("Part")
    ramp.Name = "AccessRamp"
    ramp.Size = Vector3.new(15, 2, 30)
    ramp.Position = hubBuilding.Position + Vector3.new(0, 1, -15)
    ramp.BrickColor = BrickColor.new("Bright blue")
    ramp.Material = Enum.Material.Metal
    ramp.Anchored = true
    ramp.Parent = hubFolder
    
    -- Create stairs
    for i = 1, 3 do
        local step = Instance.new("Part")
        step.Name = "Step" .. i
        step.Size = Vector3.new(15, 1, 6)
        step.Position = ramp.Position + Vector3.new(0, -i * 1, -i * 4)
        step.BrickColor = BrickColor.new("Bright blue")
        step.Material = Enum.Material.Metal
        step.Anchored = true
        step.Parent = hubFolder
    end
    
    -- Create destination signs
    local routeData = TRAVEL_ROUTES[planetName]
    if routeData then
        self:CreateDestinationSigns(hubFolder, planetName, routeData)
    end
    
    -- Create waiting area
    self:CreateWaitingArea(hubFolder, planetName)
    
    -- Create transport manager NPC
    local manager = self:CreateTransportManager(hubFolder, planetName)
    
    -- Add manager behavior
    self:AddManagerBehavior(manager, planetName)
    
    -- Create a large, visible sign above the transport hub
    local sign = Instance.new("Part")
    sign.Name = "TransportSign"
    sign.Size = Vector3.new(20, 4, 1)
    sign.BrickColor = BrickColor.new("Bright blue")
    sign.Material = Enum.Material.Neon
    sign.Anchored = true
    sign.Position = hubBuilding.Position + Vector3.new(0, 20, 0)
    sign.Parent = hubFolder
    
    -- Add text to the sign
    local surfaceGui = Instance.new("SurfaceGui")
    surfaceGui.Name = "SignText"
    surfaceGui.Face = Enum.NormalId.Front
    surfaceGui.Parent = sign
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = "🌌 TRANSPORT HUB 🌌"
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Parent = surfaceGui
    
    -- Add a point light to make the sign glow
    local signLight = Instance.new("PointLight")
    signLight.Color = Color3.fromRGB(0, 150, 255)
    signLight.Range = 50
    signLight.Brightness = 0.5
    signLight.Parent = sign
    
    print("✅ Transport hub created on " .. planetName)
end

function InterPlanetTravel:CreateDestinationSigns(hubFolder, planetName, routeData)
    local signsFolder = Instance.new("Folder")
    signsFolder.Name = "DestinationSigns"
    signsFolder.Parent = hubFolder
    
    for i, route in ipairs(routeData) do
        local sign = Instance.new("Part")
        sign.Name = "Sign_" .. route.destination
        sign.Size = Vector3.new(8, 3, 1)
        sign.BrickColor = BrickColor.new("Bright yellow")
        sign.Material = Enum.Material.Neon
        sign.Anchored = true
        sign.Position = hubFolder.HubBuilding.Position + Vector3.new(-20 + (i * 10), 5, 30)
        sign.Parent = signsFolder
        
        -- Add text to sign
        local surfaceGui = Instance.new("SurfaceGui")
        surfaceGui.Name = "SignText"
        surfaceGui.Face = Enum.NormalId.Front
        surfaceGui.Parent = sign
        
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = route.destination .. "\n" .. route.cost .. " credits\n" .. route.time .. "s"
        textLabel.TextColor3 = Color3.new(0, 0, 0)
        textLabel.TextScaled = true
        textLabel.Font = Enum.Font.GothamBold
        textLabel.Parent = surfaceGui
    end
end

function InterPlanetTravel:CreateWaitingArea(hubFolder, planetName)
    local waitingArea = Instance.new("Part")
    waitingArea.Name = "WaitingArea"
    waitingArea.Size = Vector3.new(40, 1, 20)
    waitingArea.Position = hubFolder.HubBuilding.Position + Vector3.new(0, 0.5, -10)
    waitingArea.BrickColor = BrickColor.new("Bright blue")
    waitingArea.Material = Enum.Material.Metal
    waitingArea.Transparency = 0.5
    waitingArea.Anchored = true
    waitingArea.Parent = hubFolder
    
    -- Add waiting area label
    local label = Instance.new("Part")
    label.Name = "WaitingLabel"
    label.Size = Vector3.new(30, 2, 1)
    label.Position = waitingArea.Position + Vector3.new(0, 3, 0)
    label.BrickColor = BrickColor.new("Bright yellow")
    label.Material = Enum.Material.Neon
    label.Anchored = true
    label.Parent = hubFolder
    
    local surfaceGui = Instance.new("SurfaceGui")
    surfaceGui.Name = "LabelText"
    surfaceGui.Face = Enum.NormalId.Front
    surfaceGui.Parent = label
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = "WAITING AREA - Use transport manager to travel"
    textLabel.TextColor3 = Color3.new(0, 0, 0)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Parent = surfaceGui
end

function InterPlanetTravel:CreateTransportManager(hubFolder, planetName)
    print("👨‍💼 Creating transport manager on " .. planetName)
    
    -- Create NPC model
    local npc = Instance.new("Model")
    npc.Name = "TransportManager"
    npc.Parent = hubFolder
    
    -- Create NPC body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(2, 4, 1)
    body.Position = hubFolder.HubBuilding.Position + Vector3.new(0, 2, 25)
    body.BrickColor = BrickColor.new("Bright blue")
    body.Material = Enum.Material.Plastic
    body.Anchored = true
    body.Parent = npc
    
    -- Create NPC head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Shape = Enum.PartType.Ball
    head.Size = Vector3.new(2, 2, 2)
    head.Position = body.Position + Vector3.new(0, 3, 0)
    head.BrickColor = BrickColor.new("Bright yellow")
    head.Material = Enum.Material.Plastic
    head.Anchored = true
    head.Parent = npc
    
    -- Set primary part
    npc.PrimaryPart = body
    
    -- Add interaction prompt
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "TravelPrompt"
    prompt.ObjectText = "Transport Manager"
    prompt.ActionText = "Travel"
    prompt.MaxActivationDistance = 10
    prompt.HoldDuration = 0.5
    prompt.Parent = body
    
    -- Connect prompt to travel menu
    prompt.Triggered:Connect(function(player)
        self:ShowTravelMenu(player, planetName)
    end)
    
    return npc
end

function InterPlanetTravel:AddManagerBehavior(npc, planetName)
    local body = npc.PrimaryPart
    if not body then return end
    
    -- Add behavior using a different approach
    local behaviorScript = Instance.new("Script")
    behaviorScript.Name = "TransportManagerBehaviorScript"
    behaviorScript.Parent = body
    
    -- Use spawn function instead of script source
    spawn(function()
        local startPos = body.Position
        local rotationSpeed = 0.3
        
        print("👨‍💼 Transport manager " .. planetName .. " behavior started")
        
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
        
        print("👨‍💼 Transport manager " .. planetName .. " behavior ended")
    end)
end

function InterPlanetTravel:ShowTravelMenu(player, planetName)
    print("🌌 " .. player.Name .. " accessing travel menu on " .. planetName)
    
    local destinations = self:GetDestinationsFromPlanet(planetName)
    local message = "🌌 Available destinations from " .. planetName .. ":\n\n"
    
    for _, route in ipairs(destinations) do
        message = message .. "• " .. route.destination .. " - " .. route.cost .. " credits (" .. route.time .. "s)\n"
    end
    
    message = message .. "\nUse the transport manager to begin travel!"
    
    -- Send message to player
    self:SendMessage(player, message)
    
    -- Offer to start travel
    local startTravel = Instance.new("Message")
    startTravel.Text = "🌌 Would you like to travel? Click on the transport manager again to confirm your destination."
    startTravel.Parent = workspace
    wait(8)
    startTravel:Destroy()
end

function InterPlanetTravel:GetDestinationsFromPlanet(planetName)
    return TRAVEL_ROUTES[planetName] or {}
end

function InterPlanetTravel:StartHyperspaceJump(player, destinationPlanet)
    print("🌌 " .. player.Name .. " starting hyperspace jump to " .. destinationPlanet)
    
    -- Check if player has enough credits
    local currentCredits = self:GetPlayerCredits(player)
    local route = self:FindRoute(player, destinationPlanet)
    
    if not route then
        self:SendMessage(player, "❌ No route found to " .. destinationPlanet)
        return
    end
    
    if currentCredits < route.cost then
        self:SendMessage(player, "❌ Not enough credits! You need " .. route.cost .. " credits.")
        return
    end
    
    -- Deduct credits
    self:DeductPlayerCredits(player, route.cost)
    
    -- Begin hyperspace sequence
    self:BeginHyperspaceSequence(player, destinationPlanet, route)
end

function InterPlanetTravel:FindRoute(player, destinationPlanet)
    local currentPlanet = self:GetPlayerCurrentPlanet(player)
    if not currentPlanet then return nil end
    
    local routes = TRAVEL_ROUTES[currentPlanet]
    if not routes then return nil end
    
    for _, route in ipairs(routes) do
        if route.destination == destinationPlanet then
            return route
        end
    end
    
    return nil
end

function InterPlanetTravel:BeginHyperspaceSequence(player, destinationPlanet, route)
    print("🌌 Beginning hyperspace sequence for " .. player.Name)
    
    -- Create hyperspace effect
    local hyperspaceEffect = Instance.new("Part")
    hyperspaceEffect.Name = "HyperspacePortal"
    hyperspaceEffect.Size = Vector3.new(10, 10, 10)
    hyperspaceEffect.Shape = Enum.PartType.Ball
    hyperspaceEffect.BrickColor = BrickColor.new("Bright blue")
    hyperspaceEffect.Material = Enum.Material.Neon
    hyperspaceEffect.Anchored = true
    hyperspaceEffect.Position = player.Character.HumanoidRootPart.Position
    hyperspaceEffect.Parent = workspace
    
    -- Add point light
    local pointLight = Instance.new("PointLight")
    pointLight.Color = Color3.fromRGB(0, 150, 255)
    pointLight.Range = 50
    pointLight.Brightness = 2
    pointLight.Parent = hyperspaceEffect
    
    -- Send message
    self:SendMessage(player, "🌌 Hyperspace jump initiated! Travel time: " .. route.time .. " seconds")
    
    -- Wait for travel time
    wait(route.time)
    
    -- Complete jump
    self:CompleteHyperspaceJump(player, destinationPlanet)
    
    -- Clean up effect
    hyperspaceEffect:Destroy()
end

function InterPlanetTravel:CompleteHyperspaceJump(player, destinationPlanet)
    print("🌌 " .. player.Name .. " completed hyperspace jump to " .. destinationPlanet)
    
    -- Get destination spawn point
    local destinationPos = self:GetPlanetSpawnPoint(destinationPlanet)
    
    -- Teleport player
    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        player.Character.HumanoidRootPart.Position = destinationPos + Vector3.new(0, 10, 0)
    end
    
    -- Update player's current planet
    self:UpdatePlayerCurrentPlanet(player, destinationPlanet)
    
    -- Send arrival message
    self:SendMessage(player, "🌌 Welcome to " .. destinationPlanet .. "! Hyperspace jump complete.")
end

function InterPlanetTravel:GetPlayerCurrentPlanet(player)
    -- For now, return a default planet
    -- In a real implementation, this would be stored in player data
    return "Coruscant"
end

function InterPlanetTravel:UpdatePlayerCurrentPlanet(player, planetName)
    -- In a real implementation, this would update player data
    print("🌌 Updated " .. player.Name .. "'s current planet to " .. planetName)
end

function InterPlanetTravel:GetPlayerCredits(player)
    -- For testing, return 50000 credits
    return 50000
end

function InterPlanetTravel:DeductPlayerCredits(player, amount)
    -- In a real implementation, this would deduct from player's actual credits
    print("💰 Deducted " .. amount .. " credits from " .. player.Name)
end

function InterPlanetTravel:SendMessage(player, message)
    -- Send message to player
    local messageObj = Instance.new("Message")
    messageObj.Text = message
    messageObj.Parent = workspace
    wait(8)
    messageObj:Destroy()
end

function InterPlanetTravel:GetPlanetSpawnPoint(planetName)
    local planetConfigs = {
        Coruscant = Vector3.new(0, 5, 0),
        Tatooine = Vector3.new(1000, 5, 1000),
        Hoth = Vector3.new(-1000, 5, -1000),
        Naboo = Vector3.new(0, 5, 2000),
        Mustafar = Vector3.new(2000, 5, 0),
        Kamino = Vector3.new(0, 5, -2000)
    }
    
    return planetConfigs[planetName] or Vector3.new(0, 5, 0)
end

function InterPlanetTravel:CreateSpaceEnvironment()
    print("🌌 Creating space environment...")
    
    -- Create stars
    self:CreateStars()
    
    -- Create space stations
    self:CreateSpaceStations()
    
    -- Create asteroid fields
    self:CreateAsteroidFields()
    
    print("✅ Space environment created!")
end

function InterPlanetTravel:CreateStars()
    print("⭐ Creating stars in space...")
    
    for i = 1, 1000 do
        local star = Instance.new("Part")
        star.Name = "Star_" .. i
        star.Size = Vector3.new(1, 1, 1)
        star.Shape = Enum.PartType.Ball
        star.BrickColor = BrickColor.new("Bright yellow")
        star.Material = Enum.Material.Neon
        star.Anchored = true
        star.Parent = Workspace
        
        -- Random position in space
        local x = math.random(-5000, 5000)
        local y = math.random(200, 1000)
        local z = math.random(-5000, 5000)
        star.Position = Vector3.new(x, y, z)
        
        -- Random brightness
        local brightness = math.random(0.5, 2.0)
        local pointLight = Instance.new("PointLight")
        pointLight.Color = Color3.fromRGB(255, 255, 200)
        pointLight.Range = math.random(10, 50)
        pointLight.Brightness = brightness
        pointLight.Parent = star
    end
    
    print("⭐ Created 1000 stars in space")
end

function InterPlanetTravel:CreateSpaceStations()
    print("🌌 Creating space stations...")
    
    local stations = {"Coruscant", "Tatooine", "Hoth", "Naboo", "Mustafar", "Kamino"}
    
    for i, stationName in ipairs(stations) do
        local station = Instance.new("Part")
        station.Name = stationName .. "Station"
        station.Size = Vector3.new(100, 50, 100)
        station.BrickColor = BrickColor.new("Dark stone grey")
        station.Material = Enum.Material.Metal
        station.Anchored = true
        station.Parent = Workspace
        
        -- Position station in space above the planet
        local planetPos = self:GetPlanetSpawnPoint(stationName)
        station.Position = planetPos + Vector3.new(0, 300, 0)
        
        -- Add docking bay
        local dockingBay = Instance.new("Part")
        dockingBay.Name = "DockingBay"
        dockingBay.Size = Vector3.new(20, 10, 20)
        dockingBay.BrickColor = BrickColor.new("Bright blue")
        dockingBay.Material = Enum.Material.Neon
        dockingBay.Anchored = true
        dockingBay.Position = station.Position + Vector3.new(0, 0, 60)
        dockingBay.Parent = station
        
        -- Add interaction prompt
        local prompt = Instance.new("ProximityPrompt")
        prompt.Name = "DockingPrompt"
        prompt.ObjectText = stationName .. " Station"
        prompt.ActionText = "Dock"
        prompt.MaxActivationDistance = 20
        prompt.HoldDuration = 1.0
        prompt.Parent = dockingBay
        
        print("🌌 Created " .. stationName .. " Station")
    end
end

function InterPlanetTravel:CreateAsteroidFields()
    print("☄️ Creating asteroid fields...")
    
    for fieldNum = 1, 5 do
        local fieldCenter = Vector3.new(
            math.random(-3000, 3000),
            math.random(100, 500),
            math.random(-3000, 3000)
        )
        
        local asteroidCount = math.random(50, 100)
        
        for i = 1, asteroidCount do
            local asteroid = Instance.new("Part")
            asteroid.Name = "Asteroid_" .. fieldNum .. "_" .. i
            asteroid.Size = Vector3.new(
                math.random(5, 20),
                math.random(5, 20),
                math.random(5, 20)
            )
            asteroid.Shape = Enum.PartType.Ball
            asteroid.BrickColor = BrickColor.new("Dark stone grey")
            asteroid.Material = Enum.Material.Rock
            asteroid.Anchored = true
            asteroid.Parent = Workspace
            
            -- Random position within field
            local offset = Vector3.new(
                math.random(-200, 200),
                math.random(-50, 50),
                math.random(-200, 200)
            )
            asteroid.Position = fieldCenter + offset
        end
        
        print("☄️ Created asteroid field " .. fieldNum .. " with " .. asteroidCount .. " asteroids")
    end
end

-- Return the InterPlanetTravel class
return InterPlanetTravel 