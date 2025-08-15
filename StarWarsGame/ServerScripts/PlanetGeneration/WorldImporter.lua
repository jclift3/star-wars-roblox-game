-- WorldImporter.lua
-- Imports pre-built Roblox models and worlds for enhanced planet designs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local InsertService = game:GetService("InsertService")
local HttpService = game:GetService("HttpService")

local WorldImporter = {}
WorldImporter.__index = WorldImporter

-- Pre-built world models to import
local WORLD_MODELS = {
    -- Urban/Coruscant-style worlds
    UrbanWorlds = {
        {id = 6444884337, name = "Modern City", description = "Futuristic urban landscape"},
        {id = 6444884338, name = "Cyberpunk City", description = "High-tech metropolis"},
        {id = 6444884339, name = "Imperial Palace", description = "Grand imperial architecture"}
    },
    
    -- Desert/Tatooine-style worlds
    DesertWorlds = {
        {id = 6444884340, name = "Desert Outpost", description = "Remote desert settlement"},
        {id = 6444884341, name = "Moisture Farm", description = "Tatooine-style farming complex"},
        {id = 6444884342, name = "Sandcrawler", description = "Jawas mobile fortress"}
    },
    
    -- Ice/Hoth-style worlds
    IceWorlds = {
        {id = 6444884343, name = "Ice Base", description = "Frozen military installation"},
        {id = 6444884344, name = "Snow Cave", description = "Natural ice formations"},
        {id = 6444884345, name = "Rebel Outpost", description = "Hoth-style rebel base"}
    },
    
    -- Beautiful/Naboo-style worlds
    BeautifulWorlds = {
        {id = 6444884346, name = "Palace Gardens", description = "Elegant royal gardens"},
        {id = 6444884347, name = "Underwater City", description = "Submerged metropolis"},
        {id = 6444884348, name = "Floating Islands", description = "Aerial paradise"}
    },
    
    -- Volcanic/Mustafar-style worlds
    VolcanicWorlds = {
        {id = 6444884349, name = "Lava Fields", description = "Molten landscape"},
        {id = 6444884350, name = "Mining Complex", description = "Industrial extraction facility"},
        {id = 6444884351, name = "Volcanic Peak", description = "Active volcano"}
    },
    
    -- Ocean/Kamino-style worlds
    OceanWorlds = {
        {id = 6444884352, name = "Underwater Lab", description = "Deep sea research facility"},
        {id = 6444884353, name = "Floating Platform", description = "Ocean surface base"},
        {id = 6444884354, name = "Coral Reef", description = "Marine ecosystem"}
    }
}

-- Star Wars specific models
local STAR_WARS_MODELS = {
    -- Ships and vehicles
    Ships = {
        {id = 6444884355, name = "X-Wing Fighter", description = "Classic Rebel starfighter"},
        {id = 6444884356, name = "TIE Fighter", description = "Imperial twin-ion fighter"},
        {id = 6444884357, name = "Millennium Falcon", description = "Legendary smuggling ship"},
        {id = 6444884358, name = "Star Destroyer", description = "Massive Imperial capital ship"}
    },
    
    -- Buildings and structures
    Buildings = {
        {id = 6444884359, name = "Death Star", description = "Imperial battle station"},
        {id = 6444884360, name = "Jedi Temple", description = "Ancient Force user sanctuary"},
        {id = 6444884361, name = "Sith Academy", description = "Dark side training facility"},
        {id = 6444884362, name = "Cantina", description = "Mos Eisley-style bar"}
    },
    
    -- Props and decorations
    Props = {
        {id = 6444884363, name = "Lightsaber", description = "Elegant weapon of Jedi"},
        {id = 6444884364, name = "Blaster", description = "Standard blaster weapon"},
        {id = 6444884365, name = "Droid", description = "Various robotic assistants"},
        {id = 6444884366, name = "Holocron", description = "Ancient knowledge storage"}
    }
}

function WorldImporter.new()
    local self = setmetatable({}, WorldImporter)
    
    self.importedWorlds = {}
    self.importedModels = {}
    
    return self
end

function WorldImporter:Initialize()
    print("📦 Initializing World Importer System...")
    
    -- Create import folders
    self:CreateImportFolders()
    
    print("✅ World Importer System initialized!")
end

function WorldImporter:CreateImportFolders()
    -- Create main import folder
    self.importFolder = Instance.new("Folder")
    self.importFolder.Name = "ImportedWorlds"
    self.importFolder.Parent = Workspace
    
    -- Create subfolders for different types
    for category, _ in pairs(WORLD_MODELS) do
        local categoryFolder = Instance.new("Folder")
        categoryFolder.Name = category
        categoryFolder.Parent = self.importFolder
    end
    
    -- Create Star Wars specific folders
    for category, _ in pairs(STAR_WARS_MODELS) do
        local categoryFolder = Instance.new("Folder")
        categoryFolder.Name = "StarWars_" .. category
        categoryFolder.Parent = self.importFolder
    end
end

function WorldImporter:ImportWorldModel(modelId, category, planetName)
    print("📦 Importing world model " .. modelId .. " for " .. planetName)
    
    local success, model = pcall(function()
        return InsertService:LoadAsset(modelId)
    end)
    
    if success and model then
        local modelInstance = model:GetChildren()[1]
        if modelInstance then
            -- Clone the model
            local clonedModel = modelInstance:Clone()
            clonedModel.Name = planetName .. "_" .. modelId
            
            -- Position the model on the planet
            self:PositionModelOnPlanet(clonedModel, planetName)
            
            -- Add to appropriate folder
            local targetFolder = self.importFolder:FindFirstChild(category)
            if targetFolder then
                clonedModel.Parent = targetFolder
            else
                clonedModel.Parent = self.importFolder
            end
            
            -- Store imported model
            table.insert(self.importedModels, {
                id = modelId,
                model = clonedModel,
                planet = planetName,
                category = category
            })
            
            print("✅ Successfully imported " .. modelId .. " for " .. planetName)
            return clonedModel
        else
            warn("❌ No model found in asset " .. modelId)
        end
        
        -- Clean up
        model:Destroy()
    else
        warn("❌ Failed to import model " .. modelId .. ": " .. tostring(model))
    end
    
    return nil
end

function WorldImporter:PositionModelOnPlanet(model, planetName)
    -- Get planet position from planet generator
    local planetConfigs = {
        Coruscant = {position = Vector3.new(0, 0, 0), size = Vector3.new(2000, 100, 2000)},
        Tatooine = {position = Vector3.new(1000, 0, 1000), size = Vector3.new(1500, 80, 1500)},
        Hoth = {position = Vector3.new(-1000, 0, -1000), size = Vector3.new(1200, 120, 1200)},
        Naboo = {position = Vector3.new(0, 0, 2000), size = Vector3.new(1000, 60, 1000)},
        Mustafar = {position = Vector3.new(2000, 0, 0), size = Vector3.new(800, 100, 800)},
        Kamino = {position = Vector3.new(0, 0, -2000), size = Vector3.new(600, 80, 600)}
    }
    
    local planetConfig = planetConfigs[planetName]
    if planetConfig then
        -- Position model randomly within planet bounds
        local randomX = planetConfig.position.X + math.random(-planetConfig.size.X/3, planetConfig.size.X/3)
        local randomZ = planetConfig.position.Z + math.random(-planetConfig.size.Z/3, planetConfig.size.Z/3)
        local yOffset = planetConfig.size.Y/2 + 10 -- Above planet surface
        
        model:PivotTo(CFrame.new(randomX, yOffset, randomZ))
        
        -- Scale model appropriately
        local scale = math.random(50, 150) / 100
        model:Scale(scale, scale, scale)
    end
end

function WorldImporter:ImportStarWarsModel(modelId, category, planetName)
    print("⭐ Importing Star Wars model " .. modelId .. " for " .. planetName)
    
    local success, model = pcall(function()
        return InsertService:LoadAsset(modelId)
    end)
    
    if success and model then
        local modelInstance = model:GetChildren()[1]
        if modelInstance then
            -- Clone the model
            local clonedModel = modelInstance:Clone()
            clonedModel.Name = "StarWars_" .. planetName .. "_" .. modelId
            
            -- Position the model on the planet
            self:PositionModelOnPlanet(clonedModel, planetName)
            
            -- Add to Star Wars folder
            local targetFolder = self.importFolder:FindFirstChild("StarWars_" .. category)
            if targetFolder then
                clonedModel.Parent = targetFolder
            else
                clonedModel.Parent = self.importFolder
            end
            
            -- Store imported model
            table.insert(self.importedModels, {
                id = modelId,
                model = clonedModel,
                planet = planetName,
                category = "StarWars_" .. category
            })
            
            print("✅ Successfully imported Star Wars model " .. modelId .. " for " .. planetName)
            return clonedModel
        else
            warn("❌ No model found in Star Wars asset " .. modelId)
        end
        
        -- Clean up
        model:Destroy()
    else
        warn("❌ Failed to import Star Wars model " .. modelId .. ": " .. tostring(model))
    end
    
    return nil
end

function WorldImporter:ImportRandomWorldsForPlanet(planetName, count)
    print("🎲 Importing " .. count .. " random worlds for " .. planetName)
    
    local importedCount = 0
    
    -- Determine planet type and import appropriate worlds
    if planetName == "Coruscant" then
        importedCount = self:ImportRandomFromCategory("UrbanWorlds", planetName, count)
    elseif planetName == "Tatooine" then
        importedCount = self:ImportRandomFromCategory("DesertWorlds", planetName, count)
    elseif planetName == "Hoth" then
        importedCount = self:ImportRandomFromCategory("IceWorlds", planetName, count)
    elseif planetName == "Naboo" then
        importedCount = self:ImportRandomFromCategory("BeautifulWorlds", planetName, count)
    elseif planetName == "Mustafar" then
        importedCount = self:ImportRandomFromCategory("VolcanicWorlds", planetName, count)
    elseif planetName == "Kamino" then
        importedCount = self:ImportRandomFromCategory("OceanWorlds", planetName, count)
    end
    
    print("✅ Imported " .. importedCount .. " random worlds for " .. planetName)
    return importedCount
end

function WorldImporter:ImportRandomFromCategory(category, planetName, count)
    local models = WORLD_MODELS[category]
    if not models then return 0 end
    
    local importedCount = 0
    local shuffledModels = self:ShuffleTable(models)
    
    for i = 1, math.min(count, #shuffledModels) do
        local model = shuffledModels[i]
        if self:ImportWorldModel(model.id, category, planetName) then
            importedCount = importedCount + 1
        end
    end
    
    return importedCount
end

function WorldImporter:ImportStarWarsModelsForPlanet(planetName, count)
    print("⭐ Importing " .. count .. " Star Wars models for " .. planetName)
    
    local importedCount = 0
    local categories = {"Ships", "Buildings", "Props"}
    
    for _, category in ipairs(categories) do
        local models = STAR_WARS_MODELS[category]
        if models then
            local randomModel = models[math.random(1, #models)]
            if self:ImportStarWarsModel(randomModel.id, category, planetName) then
                importedCount = importedCount + 1
            end
        end
    end
    
    print("✅ Imported " .. importedCount .. " Star Wars models for " .. planetName)
    return importedCount
end

function WorldImporter:ShuffleTable(t)
    local shuffled = {}
    for i = 1, #t do
        shuffled[i] = t[i]
    end
    
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    return shuffled
end

function WorldImporter:GetImportedModels()
    return self.importedModels
end

function WorldImporter:GetImportedModelsForPlanet(planetName)
    local planetModels = {}
    
    for _, modelData in ipairs(self.importedModels) do
        if modelData.planet == planetName then
            table.insert(planetModels, modelData)
        end
    end
    
    return planetModels
end

function WorldImporter:ClearImportedModels()
    print("🗑️ Clearing all imported models...")
    
    for _, modelData in ipairs(self.importedModels) do
        if modelData.model and modelData.model.Parent then
            modelData.model:Destroy()
        end
    end
    
    self.importedModels = {}
    print("✅ All imported models cleared")
end

function WorldImporter:ClearImportedModelsForPlanet(planetName)
    print("🗑️ Clearing imported models for " .. planetName)
    
    local modelsToRemove = {}
    
    for i, modelData in ipairs(self.importedModels) do
        if modelData.planet == planetName then
            if modelData.model and modelData.model.Parent then
                modelData.model:Destroy()
            end
            table.insert(modelsToRemove, i)
        end
    end
    
    -- Remove from table (in reverse order to avoid index issues)
    for i = #modelsToRemove, 1, -1 do
        table.remove(self.importedModels, modelsToRemove[i])
    end
    
    print("✅ Cleared imported models for " .. planetName)
end

-- Return the WorldImporter class
return WorldImporter 