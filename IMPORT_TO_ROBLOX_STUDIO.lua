-- IMPORT_TO_ROBLOX_STUDIO.lua
-- Run this script in Roblox Studio to import all Star Wars game systems

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("🚀 STAR WARS GAME - STUDIO IMPORT SCRIPT")
print("=" .. string.rep("=", 50))

-- Function to create a script from source
local function CreateScript(parent, name, source, scriptType)
    local script = Instance.new(scriptType or "Script")
    script.Name = name
    script.Source = source
    script.Parent = parent
    return script
end

-- Function to create a folder structure
local function CreateFolder(parent, name)
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

print("📁 Creating folder structure...")

-- Create main folder structure
local starWarsFolder = CreateFolder(ReplicatedStorage, "StarWarsGame")
local serverScripts = CreateFolder(starWarsFolder, "ServerScripts")
local gameManagement = CreateFolder(serverScripts, "GameManagement")
local spaceshipSystem = CreateFolder(serverScripts, "SpaceshipSystem")
local factionSystem = CreateFolder(serverScripts, "FactionSystem")
local monetizationSystem = CreateFolder(serverScripts, "MonetizationSystem")
local planetGeneration = CreateFolder(serverScripts, "PlanetGeneration")
local npcSystem = CreateFolder(serverScripts, "NPCSystem")
local travelSystem = CreateFolder(serverScripts, "TravelSystem")
local starterPlayerScripts = CreateFolder(starWarsFolder, "StarterPlayerScripts")

print("✅ Folder structure created!")

-- Now you need to manually copy each script content into the appropriate folders
print("📝 MANUAL IMPORT REQUIRED:")
print("1. Copy the content of each .lua file into the corresponding script in Roblox Studio")
print("2. Make sure each script is in the correct folder")
print("3. Set the script type (Script, LocalScript, or ModuleScript) as needed")
print("")
print("📁 FOLDERS CREATED:")
print("- ReplicatedStorage.StarWarsGame.ServerScripts.GameManagement")
print("- ReplicatedStorage.StarWarsGame.ServerScripts.SpaceshipSystem")
print("- ReplicatedStorage.StarWarsGame.ServerScripts.FactionSystem")
print("- ReplicatedStorage.StarWarsGame.ServerScripts.MonetizationSystem")
print("- ReplicatedStorage.StarWarsGame.ServerScripts.PlanetGeneration")
print("- ReplicatedStorage.StarWarsGame.ServerScripts.NPCSystem")
print("- ReplicatedStorage.StarWarsGame.ServerScripts.TravelSystem")
print("- ReplicatedStorage.StarWarsGame.StarterPlayerScripts")
print("")
print("🎯 NEXT STEPS:")
print("1. Create a Script in ServerScriptService named '00_Main'")
print("2. Copy the content of 00_Main.lua into it")
print("3. Create ModuleScripts in each folder with the corresponding content")
print("4. Test the game!")

print("=" .. string.rep("=", 50))
print("✅ Import script complete!") 