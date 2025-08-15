-- TestSystem.lua
-- Simple test script to verify all systems are working

local TestSystem = {}

function TestSystem()
    print("🔍 TESTING STAR WARS GAME SYSTEMS...")
    print("=" .. string.rep("=", 50))
    
    -- Test 1: Check for NPCs and their welds
    print("\n🧪 TEST 1: NPC System")
    local npcCount = 0
    local weldedNPCs = 0
    
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("Stormtrooper") then
            npcCount = npcCount + 1
            local hasWelds = false
            for _, part in pairs(obj:GetDescendants()) do
                if part:IsA("Weld") then
                    hasWelds = true
                    break
                end
            end
            if hasWelds then
                weldedNPCs = weldedNPCs + 1
            else
                print("❌ NPC " .. obj.Name .. " is missing welds")
            end
        end
    end
    
    print("📊 NPCs found: " .. npcCount .. " | Welded NPCs: " .. weldedNPCs)
    
    -- Test 2: Check for hangars
    print("\n🧪 TEST 2: Hangar System")
    local hangarCount = 0
    local accessibleHangars = 0
    
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("_Hangar") then
            hangarCount = hangarCount + 1
            local hasManager = false
            local hasLandingPads = false
            
            for _, part in pairs(obj:GetDescendants()) do
                if part.Name == "HangarManager" then
                    hasManager = true
                elseif part.Name:match("LandingPad") then
                    hasLandingPads = true
                end
            end
            
            if hasManager and hasLandingPads then
                accessibleHangars = accessibleHangars + 1
            else
                print("❌ Hangar " .. obj.Name .. " is missing manager or landing pads")
            end
        end
    end
    
    print("📊 Total hangars found: " .. hangarCount .. " | Accessible hangars: " .. accessibleHangars)
    
    -- Test 3: Check for transport hubs
    print("\n🧪 TEST 3: Transport System")
    local hubCount = 0
    
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("_TransportHub") then
            hubCount = hubCount + 1
        end
    end
    
    print("📊 Transport hubs found: " .. hubCount)
    
    -- Test 4: Check for planets
    print("\n🧪 TEST 4: Planet System")
    local planetCount = 0
    
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("Planet_") then
            planetCount = planetCount + 1
        end
    end
    
    print("📊 Planets found: " .. planetCount)
    
    -- Test 5: Check for spaceships
    print("\n🧪 TEST 5: Spaceship System")
    local shipCount = 0
    
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("XWing") then
            shipCount = shipCount + 1
        end
    end
    
    print("📊 X-Wings found: " .. shipCount)
    
    print("\n" .. string.rep("=", 50))
    print("✅ TESTING COMPLETE!")
end

return TestSystem 