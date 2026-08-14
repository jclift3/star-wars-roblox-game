--!strict
--[[
	PlayerService.luau

	Owns the player's body: when it spawns, where, how much health it has, how
	fast it moves, and how hard the planet pulls on it.

	SPAWNING IS MANUAL
	Players.CharacterAutoLoads is false in the Rojo project. That is deliberate:
	a character that spawns before its profile loads gets default health and
	default speed, and then either keeps them or visibly snaps to the right
	values a second later. Here the profile is awaited first and the character
	spawns already correct.

	SPRINT IS SERVER-AUTHORITATIVE
	The old version set WalkSpeed on the client, which means any exploiter had
	a speed slider. The client now only sends "I am holding shift"; the server
	decides what that is worth, using the player's actual Force Speed rank.

	PER-PLANET GRAVITY
	Roblox has one global gravity value, but players on one server can be on
	different worlds. So world gravity stays at the Roblox default and each
	character carries a VectorForce that cancels part of it. Kamino genuinely
	floats and Hoth genuinely drags, without touching Workspace.Gravity.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Signal = require(Shared.Core.Signal)
local Planets = require(Shared.Config.Planets)
local Costumes = require(Shared.Config.Costumes)
local RigBuilder = require(Shared.Rig.RigBuilder)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type PlayerProfile = Types.PlayerProfile

local PlayerService = {
	name = "PlayerService",
	priority = 20,
}

local BASE_WALK_SPEED = 16
local SPRINT_MULTIPLIER = 1.55
local BASE_JUMP_POWER = 50
local RESPAWN_DELAY = 5

-- How often the gravity force re-reads assembly mass. Equipping a weapon
-- changes it, and a stale force would make the player slowly sink or rise.
local MASS_REFRESH_INTERVAL = 1

local sprinting: { [Player]: boolean } = {}

PlayerService.characterReady = Signal.new()
PlayerService.playerDied = Signal.new()

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

--------------------------------------------------------------------------------
-- Spawn points
--------------------------------------------------------------------------------

--[[
	Finds where on `planetId` a player should appear.

	Looks for Workspace/Spawns/<PlanetId>, which the world builder populates.
	Falls back to any SpawnLocation, then to the origin -- the fallback matters
	because Coruscant has no ground, and dropping a player at 0,0,0 there is a
	very long fall. Spawn folders are the contract; this is just the safety net.
]]
local function spawnCFrameFor(planetId: string): CFrame
	local spawns = Workspace:FindFirstChild("Spawns")
	local planetFolder = spawns and spawns:FindFirstChild(planetId)

	if planetFolder then
		local candidates = {}
		for _, child in planetFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(candidates, child)
			end
		end
		if #candidates > 0 then
			local pick = candidates[math.random(1, #candidates)]
			return pick.CFrame + Vector3.new(0, 4, 0)
		end
	end

	local anySpawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if anySpawn then
		return anySpawn.CFrame + Vector3.new(0, 4, 0)
	end

	warn(`[PlayerService] no spawn point for "{planetId}"; using origin`)
	return CFrame.new(0, 12, 0)
end

--------------------------------------------------------------------------------
-- Gravity
--------------------------------------------------------------------------------

--[[
	Applies a planet's gravity to one character.

	The force cancels the difference between Roblox's gravity and the planet's:
	positive (upward) on low-gravity worlds, negative on heavy ones. Jump height
	and fall speed both follow from this for free, which is why it is done with
	physics rather than by fiddling with JumpPower.
]]
local function applyGravity(character: Model, planetGravity: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local existing = root:FindFirstChild("PlanetGravity")
	if existing then
		existing:Destroy()
	end

	if math.abs(planetGravity - Workspace.Gravity) < 0.5 then
		return -- close enough to standard; skip the physics object entirely
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "PlanetGravityAttachment"
	attachment.Parent = root

	local force = Instance.new("VectorForce")
	force.Name = "PlanetGravity"
	force.Attachment0 = attachment
	force.ApplyAtCenterOfMass = true
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = Vector3.zero
	force.Parent = root

	task.spawn(function()
		while force.Parent and character.Parent do
			-- AssemblyMass covers the whole welded character, so cosmetics and
			-- held weapons are already included.
			force.Force = Vector3.new(0, root.AssemblyMass * (Workspace.Gravity - planetGravity), 0)
			task.wait(MASS_REFRESH_INTERVAL)
		end
	end)
end

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------

--[[
	Dresses a player in their equipped outfit.

	This is the same Costumes/RigBuilder path the NPCs use, welded onto the
	character Roblox already loaded rather than onto a rig we build ourselves.
	Reusing the loaded character keeps the default Animate script, the camera
	and the control scripts intact -- swapping `player.Character` for a fresh
	model throws all three away and has to reimplement them.

	The stock avatar's hair, hats and clothing come off first, because a costume
	layered over a baseball cap and a t-shirt reads as neither.
]]
-- Marks the parts this service welded on, so changing outfit can strip the old
-- one without touching the body, the held weapon, or anything else bolted to
-- the character by another system.
local OUTFIT_PART = "OutfitPart"

local function applyOutfit(character: Model, outfitName: string?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		-- Costumes are positioned against R15 limb names and sizes. On an R6
		-- body every piece would silently fail to find its limb.
		warn("[PlayerService] costumes need R15; set Avatar Type to R15 in Game Settings")
		return
	end

	for _, item in character:GetChildren() do
		local isStockAvatar = item:IsA("Accessory") or item:IsA("Clothing") or item:IsA("ShirtGraphic")
		local isOldOutfit = item:IsA("BasePart") and item:GetAttribute(OUTFIT_PART) ~= nil
		if isStockAvatar or isOldOutfit then
			item:Destroy()
		end
	end

	if not outfitName then
		return
	end
	if not Costumes.exists(outfitName) then
		warn(`[PlayerService] unknown outfit "{outfitName}"; leaving avatar as-is`)
		return
	end

	for _, part in RigBuilder.attach(character, Costumes.get(outfitName)) do
		part:SetAttribute(OUTFIT_PART, true)
	end
end

--------------------------------------------------------------------------------
-- Applying profile to body
--------------------------------------------------------------------------------

local function applyStats(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local stats = progression().getStats(player)
	local maxHealth = progression().maxHealthFor(player)

	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.UseJumpPower = true
	humanoid.JumpPower = BASE_JUMP_POWER

	local moveMult = stats.MoveSpeedMult or 1
	humanoid.WalkSpeed = BASE_WALK_SPEED * moveMult * (if sprinting[player] then SPRINT_MULTIPLIER else 1)
end

--[[
	Re-dresses a player in whatever their profile now says, with no respawn.

	Called by ShopService when the equipped outfit changes. Reloading the
	character would also work, but it would teleport the player back to a spawn
	point and interrupt whatever they were doing -- a harsh punishment for
	changing your shirt.
]]
function PlayerService.refreshOutfit(player: Player)
	local character = player.Character
	local profile = data().get(player)
	if not character or not profile then
		return
	end
	applyOutfit(character, profile.equipped.outfit)
	-- Outfits carry stats, so speed and health have to be re-derived too.
	progression().invalidate(player)
	applyStats(player, character)
end

--- Health regen from the Combat Medic skill. Runs while the character lives.
local function startRegen(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	task.spawn(function()
		while character.Parent and humanoid.Health > 0 do
			task.wait(1)
			local regen = progression().getStats(player).HealthRegen or 0
			if regen > 0 and humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + regen)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local profile = data().await(player, 15)
	if not profile then
		return
	end

	local planet = Planets.get(profile.currentPlanet)

	-- Every arrival on a world -- first spawn, respawn, and travel -- comes
	-- through here, so this is the only place that has to care whether the
	-- destination has been generated yet.
	ServiceLoader.get("WorldService").ensure(profile.currentPlanet)

	-- LoadCharacter drops the character at a SpawnLocation of Roblox's
	-- choosing, which will usually be the wrong planet. Reposition before
	-- anything else so the player never sees the wrong world.
	character:PivotTo(spawnCFrameFor(profile.currentPlanet))

	applyOutfit(character, profile.equipped.outfit)
	applyStats(player, character)
	applyGravity(character, planet.gravity)
	startRegen(player, character)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			sprinting[player] = false
			data().update(player, function(p: PlayerProfile)
				p.stats.deaths += 1
			end)
			PlayerService.playerDied:fire(player, character)

			task.delay(RESPAWN_DELAY, function()
				if player:IsDescendantOf(Players) then
					player:LoadCharacterAsync()
				end
			end)
		end)
	end

	PlayerService.characterReady:fire(player, character, profile)
end

--- Moves a player to another world, respawning them at its spawn point.
function PlayerService.travelTo(player: Player, planetId: string): (boolean, string?)
	if not Planets.exists(planetId) then
		return false, "Unknown destination"
	end
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	if profile.currentPlanet == planetId then
		return false, "Already there"
	end

	local distance = Planets.distance(profile.currentPlanet, planetId)
	data().update(player, function(p: PlayerProfile)
		p.currentPlanet = planetId
		p.stats.lightYearsTravelled += distance
	end)

	player:LoadCharacterAsync()
	return true, nil
end

function PlayerService.init()
	Net.onServerEvent(Net.Event.SetSprinting, function(player: Player, wantsSprint: boolean)
		sprinting[player] = wantsSprint

		local character = player.Character
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		-- Recomputed from the profile every time. The client's message is a
		-- request, never a speed value.
		local moveMult = progression().getStats(player).MoveSpeedMult or 1
		humanoid.WalkSpeed = BASE_WALK_SPEED * moveMult * (if wantsSprint then SPRINT_MULTIPLIER else 1)
	end, {
		rateLimit = 8,
		validate = function(v: any): boolean
			return type(v) == "boolean"
		end,
	})
end

function PlayerService.start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(onCharacterAdded, player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end

	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)

	Players.PlayerRemoving:Connect(function(player)
		sprinting[player] = nil
	end)

	-- The actual first spawn. CharacterAutoLoads is off, so nothing happens
	-- until the profile is in hand and we know which planet to spawn them on.
	-- Every later respawn goes through the same CharacterAdded path.
	data().profileLoaded:connect(function(player: Player)
		player:LoadCharacterAsync()
	end)
end

return PlayerService
