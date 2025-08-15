@echo off
echo ========================================
echo STAR WARS GAME - SCRIPT UPDATER
echo ========================================
echo.

echo This script will update all your Star Wars game scripts.
echo Make sure you have the scripts in the same folder as this batch file.
echo.

echo Copying scripts to Roblox Studio...
echo.

REM Copy main script
if exist "StarWarsGame\ServerScripts\00_Main.lua" (
    copy "StarWarsGame\ServerScripts\00_Main.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\" /Y
    echo ✅ Updated 00_Main.lua
) else (
    echo ❌ 00_Main.lua not found
)

REM Copy GameManager
if exist "StarWarsGame\ServerScripts\GameManagement\GameManager.lua" (
    copy "StarWarsGame\ServerScripts\GameManagement\GameManager.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\GameManagement\" /Y
    echo ✅ Updated GameManager.lua
) else (
    echo ❌ GameManager.lua not found
)

REM Copy SpaceshipManager
if exist "StarWarsGame\ServerScripts\SpaceshipSystem\SpaceshipManager.lua" (
    copy "StarWarsGame\ServerScripts\SpaceshipSystem\SpaceshipManager.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\SpaceshipSystem\" /Y
    echo ✅ Updated SpaceshipManager.lua
) else (
    echo ❌ SpaceshipManager.lua not found
)

REM Copy FactionManager
if exist "StarWarsGame\ServerScripts\FactionSystem\FactionManager.lua" (
    copy "StarWarsGame\ServerScripts\FactionSystem\FactionManager.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\FactionSystem\" /Y
    echo ✅ Updated FactionManager.lua
) else (
    echo ❌ FactionManager.lua not found
)

REM Copy MonetizationManager
if exist "StarWarsGame\ServerScripts\MonetizationSystem\MonetizationManager.lua" (
    copy "StarWarsGame\ServerScripts\MonetizationSystem\MonetizationManager.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\MonetizationSystem\" /Y
    echo ✅ Updated MonetizationManager.lua
) else (
    echo ❌ MonetizationManager.lua not found
)

REM Copy PlanetGenerator
if exist "StarWarsGame\ServerScripts\PlanetGeneration\PlanetGenerator.lua" (
    copy "StarWarsGame\ServerScripts\PlanetGeneration\PlanetGenerator.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\PlanetGeneration\" /Y
    echo ✅ Updated PlanetGenerator.lua
) else (
    echo ❌ PlanetGenerator.lua not found
)

REM Copy WorldImporter
if exist "StarWarsGame\ServerScripts\PlanetGeneration\WorldImporter.lua" (
    copy "StarWarsGame\ServerScripts\PlanetGeneration\WorldImporter.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\PlanetGeneration\" /Y
    echo ✅ Updated WorldImporter.lua
) else (
    echo ❌ WorldImporter.lua not found
)

REM Copy SpaceshipSpawner
if exist "StarWarsGame\ServerScripts\SpaceshipSystem\SpaceshipSpawner.lua" (
    copy "StarWarsGame\ServerScripts\SpaceshipSystem\SpaceshipSpawner.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\SpaceshipSystem\" /Y
    echo ✅ Updated SpaceshipSpawner.lua
) else (
    echo ❌ SpaceshipSpawner.lua not found
)

REM Copy NPCManager
if exist "StarWarsGame\ServerScripts\NPCSystem\NPCManager.lua" (
    copy "StarWarsGame\ServerScripts\NPCSystem\NPCManager.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\NPCSystem\" /Y
    echo ✅ Updated NPCManager.lua
) else (
    echo ❌ NPCManager.lua not found
)

REM Copy InterPlanetTravel
if exist "StarWarsGame\ServerScripts\TravelSystem\InterPlanetTravel.lua" (
    copy "StarWarsGame\ServerScripts\TravelSystem\InterPlanetTravel.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\TravelSystem\" /Y
    echo ✅ Updated InterPlanetTravel.lua
) else (
    echo ❌ InterPlanetTravel.lua not found
)

REM Copy TestSystem
if exist "StarWarsGame\ServerScripts\TestSystem.lua" (
    copy "StarWarsGame\ServerScripts\TestSystem.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\ServerScripts\" /Y
    echo ✅ Updated TestSystem.lua
) else (
    echo ❌ TestSystem.lua not found
)

REM Copy SprintSystem
if exist "StarWarsGame\StarterPlayerScripts\SprintSystem.lua" (
    copy "StarWarsGame\StarterPlayerScripts\SprintSystem.lua" "C:\Users\%USERNAME%\AppData\Local\Roblox\Versions\*\content\scripts\StarWarsGame\StarterPlayerScripts\" /Y
    echo ✅ Updated SprintSystem.lua
) else (
    echo ❌ SprintSystem.lua not found
)

echo.
echo ========================================
echo SCRIPT UPDATE COMPLETE!
echo ========================================
echo.
echo Now in Roblox Studio:
echo 1. Delete the old scripts
echo 2. Import the new ones
echo 3. Test the game
echo.
pause 