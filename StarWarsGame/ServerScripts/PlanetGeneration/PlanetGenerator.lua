-- PlanetGenerator.lua
-- Automatically generates all planet environments for STAR WARS: GALACTIC EMPIRE

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PlanetGenerator = {}
PlanetGenerator.__index = PlanetGenerator

-- Planet Generation Configuration
local PLANET_CONFIGS = {
    Coruscant = {
        position = Vector3.new(0, 0, 0),
        size = Vector3.new(2000, 100, 2000),
        terrainType = "Urban",
        buildings = {
            {type = "Skyscraper", count = 25, height = {150, 300}},
            {type = "LandingPad", count = 8, height = {20, 30}},
            {type = "ImperialPalace", count = 1, height = {400, 400}},
            {type = "CommercialDistrict", count = 15, height = {80, 150}},
            {type = "ResidentialTower", count = 20, height = {100, 200}}
        },
        atmosphere = {
            skyColor = Color3.fromRGB(135, 206, 235),
            fogColor = Color3.fromRGB(200, 200, 200),
            fogStart = 100,
            fogEnd = 1000
        },
        resources = {"Credits", "Technology", "Information"},
        spawnPoint = Vector3.new(0, 150, 0)
    },
    
    Tatooine = {
        position = Vector3.new(1000, 0, 1000),
        size = Vector3.new(1500, 80, 1500),
        terrainType = "Desert",
        buildings = {
            {type = "MoistureFarm", count = 12, height = {15, 25}},
            {type = "Cantina", count = 3, height = {20, 30}},
            {type = "TradingPost", count = 5, height = {25, 35}},
            {type = "Sandcrawler", count = 2, height = {40, 50}},
            {type = "DesertOutpost", count = 8, height = {20, 30}}
        },
        atmosphere = {
            skyColor = Color3.fromRGB(255, 165, 0),
            fogColor = Color3.fromRGB(255, 200, 150),
            fogStart = 50,
            fogEnd = 800
        },
        resources = {"Water", "Spice", "Junk"},
        spawnPoint = Vector3.new(1000, 100, 1000)
    },
    
    Hoth = {
        position = Vector3.new(-1000, 0, -1000),
        size = Vector3.new(1200, 120, 1200),
        terrainType = "Ice",
        buildings = {
            {type = "RebelBase", count = 1, height = {60, 80}},
            {type = "IceCave", count = 5, height = {30, 50}},
            {type = "SensorTower", count = 3, height = {40, 60}},
            {type = "Hangar", count = 2, height = {25, 35}},
            {type = "CommandCenter", count = 1, height = {45, 55}}
        },
        atmosphere = {
            skyColor = Color3.fromRGB(240, 248, 255),
            fogColor = Color3.fromRGB(220, 220, 255),
            fogStart = 80,
            fogEnd = 600
        },
        resources = {"Ice", "Minerals", "Technology"},
        spawnPoint = Vector3.new(-1000, 120, -1000)
    },
    
    Naboo = {
        position = Vector3.new(0, 0, 2000),
        size = Vector3.new(1000, 60, 1000),
        terrainType = "Beautiful",
        buildings = {
            {type = "Palace", count = 1, height = {80, 100}},
            {type = "UnderwaterCity", count = 3, height = {40, 60}},
            {type = "Garden", count = 8, height = {10, 20}},
            {type = "Marketplace", count = 6, height = {25, 35}},
            {type = "ResidentialArea", count = 12, height = {30, 50}}
        },
        atmosphere = {
            skyColor = Color3.fromRGB(173, 216, 230),
            fogColor = Color3.fromRGB(200, 230, 255),
            fogStart = 60,
            fogEnd = 700
        },
        resources = {"Art", "Culture", "Trade"},
        spawnPoint = Vector3.new(0, 80, 2000)
    },
    
    Mustafar = {
        position = Vector3.new(2000, 0, 0),
        size = Vector3.new(800, 100, 800),
        terrainType = "Volcanic",
        buildings = {
            {type = "MiningFacility", count = 4, height = {40, 60}},
            {type = "LavaRefinery", count = 2, height = {50, 70}},
            {type = "CommandTower", count = 1, height = {80, 100}},
            {type = "StorageDepot", count = 6, height = {25, 35}},
            {type = "SecurityOutpost", count = 3, height = {30, 40}}
        },
        atmosphere = {
            skyColor = Color3.fromRGB(139, 69, 19),
            fogColor = Color3.fromRGB(255, 100, 0),
            fogStart = 40,
            fogEnd = 500
        },
        resources = {"Lava", "Minerals", "Energy"},
        spawnPoint = Vector3.new(2000, 120, 0)
    },
    
    Kamino = {
        position = Vector3.new(0, 0, -2000),
        size = Vector3.new(600, 80, 600),
        terrainType = "Ocean",
        buildings = {
            {type = "CloningFacility", count = 2, height = {70, 90}},
            {type = "ResearchLab", count = 4, height = {45, 65}},
            {type = "TrainingCenter", count = 3, height = {35, 55}},
            {type = "Administrative", count = 2, height = {50, 70}},
            {type = "DockingBay", count = 5, height = {30, 40}}
        },
        atmosphere = {
            skyColor = Color3.fromRGB(70, 130, 180),
            fogColor = Color3.fromRGB(100, 150, 200),
            fogStart = 70,
            fogEnd = 600
        },
        resources = {"Clones", "Technology", "Research"},
        spawnPoint = Vector3.new(0, 100, -2000)
    }
}

function PlanetGenerator.new()
    local self = setmetatable({}, PlanetGenerator)
    
    self.generatedPlanets = {}
    self.planetFolders = {}
    
    return self
end

function PlanetGenerator:Initialize()
    print("🌍 Initializing Planet Generation System...")
    
    -- Create main planets folder
    self.planetsFolder = Instance.new("Folder")
    self.planetsFolder.Name = "Planets"
    self.planetsFolder.Parent = Workspace
    
    -- Generate all planets
    self:GenerateAllPlanets()
    
    print("✅ Planet Generation System initialized!")
end

function PlanetGenerator:GenerateAllPlanets()
    for planetName, config in pairs(PLANET_CONFIGS) do
        print("🏗️ Generating " .. planetName .. "...")
        self:GeneratePlanet(planetName, config)
    end
end

function PlanetGenerator:GeneratePlanet(planetName, config)
    -- Create planet folder
    local planetFolder = Instance.new("Folder")
    planetFolder.Name = planetName
    planetFolder.Parent = self.planetsFolder
    
    -- Generate terrain
    self:GenerateTerrain(planetFolder, planetName, config)
    
    -- Generate buildings
    self:GenerateBuildings(planetFolder, planetName, config)
    
    -- Generate atmosphere effects
    self:GenerateAtmosphere(planetFolder, planetName, config)
    
    -- Generate resources and spawn points
    self:GenerateResources(planetFolder, planetName, config)
    
    -- Store generated planet
    self.generatedPlanets[planetName] = planetFolder
    self.planetFolders[planetName] = planetFolder
    
    print("✅ " .. planetName .. " generated successfully!")
end

function PlanetGenerator:GenerateTerrain(planetFolder, planetName, config)
    local terrainFolder = Instance.new("Folder")
    terrainFolder.Name = "Terrain"
    terrainFolder.Parent = planetFolder
    
    if config.terrainType == "Urban" then
        self:GenerateUrbanTerrain(terrainFolder, config)
    elseif config.terrainType == "Desert" then
        self:GenerateDesertTerrain(terrainFolder, config)
    elseif config.terrainType == "Ice" then
        self:GenerateIceTerrain(terrainFolder, config)
    elseif config.terrainType == "Beautiful" then
        self:GenerateBeautifulTerrain(terrainFolder, config)
    elseif config.terrainType == "Volcanic" then
        self:GenerateVolcanicTerrain(terrainFolder, config)
    elseif config.terrainType == "Ocean" then
        self:GenerateOceanTerrain(terrainFolder, config)
    end
end

function PlanetGenerator:GenerateUrbanTerrain(terrainFolder, config)
    -- Create base platform
    local base = Instance.new("Part")
    base.Name = "UrbanBase"
    base.Size = config.size
    base.Position = config.position + Vector3.new(0, -config.size.Y/2, 0)
    base.BrickColor = BrickColor.new("Dark stone grey")
    base.Material = Enum.Material.Concrete
    base.Anchored = true
    base.Parent = terrainFolder
    
    -- Create roads
    for i = 1, 5 do
        local road = Instance.new("Part")
        road.Name = "Road" .. i
        road.Size = Vector3.new(config.size.X, 1, 20)
        road.Position = config.position + Vector3.new(0, 1, (i-3) * 200)
        road.BrickColor = BrickColor.new("Black")
        road.Material = Enum.Material.Asphalt
        road.Anchored = true
        road.Parent = terrainFolder
        
        -- Add road markings
        local marking = Instance.new("Part")
        marking.Name = "RoadMarking" .. i
        marking.Size = Vector3.new(config.size.X, 0.1, 2)
        marking.Position = road.Position + Vector3.new(0, 0.6, 0)
        marking.BrickColor = BrickColor.new("Bright yellow")
        marking.Material = Enum.Material.Neon
        marking.Anchored = true
        marking.Parent = terrainFolder
    end
end

function PlanetGenerator:GenerateDesertTerrain(terrainFolder, config)
    -- Create desert base
    local base = Instance.new("Part")
    base.Name = "DesertBase"
    base.Size = config.size
    base.Position = config.position + Vector3.new(0, -config.size.Y/2, 0)
    base.BrickColor = BrickColor.new("Sand red")
    base.Material = Enum.Material.Sand
    base.Anchored = true
    base.Parent = terrainFolder
    
    -- Create sand dunes
    for i = 1, 20 do
        local dune = Instance.new("Part")
        dune.Name = "SandDune" .. i
        dune.Shape = Enum.PartType.Ball
        dune.Size = Vector3.new(math.random(50, 150), math.random(20, 40), math.random(50, 150))
        dune.Position = config.position + Vector3.new(
            math.random(-config.size.X/3, config.size.X/3),
            dune.Size.Y/2,
            math.random(-config.size.Z/3, config.size.Z/3)
        )
        dune.BrickColor = BrickColor.new("Sand red")
        dune.Material = Enum.Material.Sand
        dune.Anchored = true
        dune.Parent = terrainFolder
    end
end

function PlanetGenerator:GenerateIceTerrain(terrainFolder, config)
    -- Create ice base
    local base = Instance.new("Part")
    base.Name = "IceBase"
    base.Size = config.size
    base.Position = config.position + Vector3.new(0, -config.size.Y/2, 0)
    base.BrickColor = BrickColor.new("Light blue")
    base.Material = Enum.Material.Ice
    base.Anchored = true
    base.Parent = terrainFolder
    
    -- Create ice mountains
    for i = 1, 15 do
        local mountain = Instance.new("Part")
        mountain.Name = "IceMountain" .. i
        mountain.Shape = Enum.PartType.Ball
        mountain.Size = Vector3.new(math.random(80, 200), math.random(60, 120), math.random(80, 200))
        mountain.Position = config.position + Vector3.new(
            math.random(-config.size.X/3, config.size.X/3),
            mountain.Size.Y/2,
            math.random(-config.size.Z/3, config.size.Z/3)
        )
        mountain.BrickColor = BrickColor.new("Light blue")
        mountain.Material = Enum.Material.Ice
        mountain.Anchored = true
        mountain.Parent = terrainFolder
    end
end

function PlanetGenerator:GenerateBeautifulTerrain(terrainFolder, config)
    -- Create beautiful base
    local base = Instance.new("Part")
    base.Name = "BeautifulBase"
    base.Size = config.size
    base.Position = config.position + Vector3.new(0, -config.size.Y/2, 0)
    base.BrickColor = BrickColor.new("Bright green")
    base.Material = Enum.Material.Grass
    base.Anchored = true
    base.Parent = terrainFolder
    
    -- Create gardens and water features
    for i = 1, 10 do
        local garden = Instance.new("Part")
        garden.Name = "Garden" .. i
        garden.Shape = Enum.PartType.Cylinder
        garden.Size = Vector3.new(math.random(30, 80), math.random(10, 20), math.random(30, 80))
        garden.Position = config.position + Vector3.new(
            math.random(-config.size.X/3, config.size.X/3),
            garden.Size.Y/2,
            math.random(-config.size.Z/3, config.size.Z/3)
        )
        garden.BrickColor = BrickColor.new("Bright green")
        garden.Material = Enum.Material.Grass
        garden.Anchored = true
        garden.Parent = terrainFolder
    end
end

function PlanetGenerator:GenerateVolcanicTerrain(terrainFolder, config)
    -- Create volcanic base
    local base = Instance.new("Part")
    base.Name = "VolcanicBase"
    base.Size = config.size
    base.Position = config.position + Vector3.new(0, -config.size.Y/2, 0)
    base.BrickColor = BrickColor.new("Dark stone grey")
    base.Material = Enum.Material.Rock
    base.Anchored = true
    base.Parent = terrainFolder
    
    -- Create lava pools
    for i = 1, 8 do
        local lava = Instance.new("Part")
        lava.Name = "LavaPool" .. i
        lava.Shape = Enum.PartType.Cylinder
        lava.Size = Vector3.new(math.random(40, 100), math.random(5, 15), math.random(40, 100))
        lava.Position = config.position + Vector3.new(
            math.random(-config.size.X/3, config.size.X/3),
            lava.Size.Y/2,
            math.random(-config.size.Z/3, config.size.Z/3)
        )
        lava.BrickColor = BrickColor.new("Really red")
        lava.Material = Enum.Material.Neon
        lava.Anchored = true
        lava.Parent = terrainFolder
        
        -- Add lava glow effect
        local pointLight = Instance.new("PointLight")
        pointLight.Color = Color3.fromRGB(255, 100, 0)
        pointLight.Range = 50
        pointLight.Brightness = 2
        pointLight.Parent = lava
    end
end

function PlanetGenerator:GenerateOceanTerrain(terrainFolder, config)
    -- Create ocean base
    local base = Instance.new("Part")
    base.Name = "OceanBase"
    base.Size = config.size
    base.Position = config.position + Vector3.new(0, -config.size.Y/2, 0)
    base.BrickColor = BrickColor.new("Deep blue")
    base.Material = Enum.Material.Water
    base.Anchored = true
    base.Parent = terrainFolder
    
    -- Create underwater terrain
    for i = 1, 12 do
        local underwater = Instance.new("Part")
        underwater.Name = "UnderwaterTerrain" .. i
        underwater.Shape = Enum.PartType.Ball
        underwater.Size = Vector3.new(math.random(60, 120), math.random(30, 60), math.random(60, 120))
        underwater.Position = config.position + Vector3.new(
            math.random(-config.size.X/3, config.size.X/3),
            -math.random(20, 60),
            math.random(-config.size.Z/3, config.size.Z/3)
        )
        underwater.BrickColor = BrickColor.new("Deep blue")
        underwater.Material = Enum.Material.Water
        underwater.Anchored = true
        underwater.Parent = terrainFolder
    end
end

function PlanetGenerator:GenerateBuildings(planetFolder, planetName, config)
    local buildingsFolder = Instance.new("Folder")
    buildingsFolder.Name = "Buildings"
    buildingsFolder.Parent = planetFolder
    
    for _, buildingType in ipairs(config.buildings) do
        for i = 1, buildingType.count do
            self:GenerateBuilding(buildingsFolder, buildingType.type, buildingType.height, config)
        end
    end
end

function PlanetGenerator:GenerateBuilding(folder, buildingType, heightRange, config)
    local building = Instance.new("Model")
    building.Name = buildingType .. "_" .. tick()
    
    -- Create building base
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(math.random(20, 60), heightRange[1] + math.random(0, heightRange[2] - heightRange[1]), math.random(20, 60))
    base.Position = config.position + Vector3.new(
        math.random(-config.size.X/3, config.size.X/3),
        base.Size.Y/2,
        math.random(-config.size.Z/3, config.size.Z/3)
    )
    
    -- Set building appearance based on type
    if buildingType == "Skyscraper" then
        base.BrickColor = BrickColor.new("Dark stone grey")
        base.Material = Enum.Material.Metal
    elseif buildingType == "LandingPad" then
        base.BrickColor = BrickColor.new("Bright blue")
        base.Material = Enum.Material.Concrete
    elseif buildingType == "ImperialPalace" then
        base.BrickColor = BrickColor.new("Gold")
        base.Material = Enum.Material.Marble
    elseif buildingType == "Cantina" then
        base.BrickColor = BrickColor.new("Sand red")
        base.Material = Enum.Material.Wood
    elseif buildingType == "RebelBase" then
        base.BrickColor = BrickColor.new("Dark stone grey")
        base.Material = Enum.Material.Metal
    else
        base.BrickColor = BrickColor.new("Dark stone grey")
        base.Material = Enum.Material.Metal
    end
    
    base.Anchored = true
    base.Parent = building
    
    -- Set primary part
    building.PrimaryPart = base
    
    -- Add building to folder
    building.Parent = folder
end

function PlanetGenerator:GenerateAtmosphere(planetFolder, planetName, config)
    local atmosphereFolder = Instance.new("Folder")
    atmosphereFolder.Name = "Atmosphere"
    atmosphereFolder.Parent = planetFolder
    
    -- Create sky effect
    local sky = Instance.new("Sky")
    sky.SkyboxBk = "rbxassetid://6444884337"
    sky.SkyboxDn = "rbxassetid://6444884337"
    sky.SkyboxFt = "rbxassetid://6444884337"
    sky.SkyboxLf = "rbxassetid://6444884337"
    sky.SkyboxRt = "rbxassetid://6444884337"
    sky.SkyboxUp = "rbxassetid://6444884337"
    sky.Parent = atmosphereFolder
    
    -- Create lighting effects
    local lighting = Instance.new("PointLight")
    lighting.Color = config.atmosphere.skyColor
    lighting.Range = 1000
    lighting.Brightness = 0.5
    -- PointLight doesn't have Position property, so we'll parent it to a part
    local lightPart = Instance.new("Part")
    lightPart.Size = Vector3.new(1, 1, 1)
    lightPart.Position = config.position + Vector3.new(0, 200, 0)
    lightPart.Transparency = 1
    lightPart.CanCollide = false
    lightPart.Anchored = true
    lightPart.Parent = atmosphereFolder
    
    lighting.Parent = lightPart
end

function PlanetGenerator:GenerateResources(planetFolder, planetName, config)
    local resourcesFolder = Instance.new("Folder")
    resourcesFolder.Name = "Resources"
    resourcesFolder.Parent = planetFolder
    
    -- Create resource nodes
    for i = 1, math.random(5, 10) do
        local resource = Instance.new("Part")
        resource.Name = "ResourceNode" .. i
        resource.Shape = Enum.PartType.Ball
        resource.Size = Vector3.new(math.random(10, 30), math.random(10, 30), math.random(10, 30))
        resource.Position = config.position + Vector3.new(
            math.random(-config.size.X/3, config.size.X/3),
            resource.Size.Y/2,
            math.random(-config.size.Z/3, config.size.Z/3)
        )
        resource.BrickColor = BrickColor.new("Bright yellow")
        resource.Material = Enum.Material.Neon
        resource.Anchored = true
        resource.Parent = resourcesFolder
        
        -- Add resource glow
        local pointLight = Instance.new("PointLight")
        pointLight.Color = Color3.fromRGB(255, 255, 0)
        pointLight.Range = 20
        pointLight.Brightness = 1
        pointLight.Parent = resource
    end
    
    -- Create spawn point
    local spawnPoint = Instance.new("Part")
    spawnPoint.Name = "SpawnPoint"
    spawnPoint.Size = Vector3.new(20, 1, 20)
    spawnPoint.Position = config.spawnPoint
    spawnPoint.BrickColor = BrickColor.new("Bright green")
    spawnPoint.Material = Enum.Material.Neon
    spawnPoint.Anchored = true
    spawnPoint.CanCollide = false
    spawnPoint.Transparency = 0.5
    spawnPoint.Parent = resourcesFolder
end

function PlanetGenerator:GetPlanetFolder(planetName)
    return self.planetFolders[planetName]
end

function PlanetGenerator:GetAllPlanetFolders()
    return self.planetFolders
end

function PlanetGenerator:RegeneratePlanet(planetName)
    if self.generatedPlanets[planetName] then
        self.generatedPlanets[planetName]:Destroy()
        self.generatedPlanets[planetName] = nil
        self.planetFolders[planetName] = nil
    end
    
    local config = PLANET_CONFIGS[planetName]
    if config then
        self:GeneratePlanet(planetName, config)
    end
end

-- Return the PlanetGenerator class
return PlanetGenerator 