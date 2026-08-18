--!strict
--[[
	VehicleService.luau

	Owns the speeder a player calls in: where it appears, who may drive it,
	and when it goes away.

	WHY THIS EXISTS AT ALL
	A district is about a minute across on foot and a planet is several. Every
	mission in the game is therefore bracketed by a walk that is not gameplay,
	and the walk is the same one every time. The roadmap files this under
	Phase 2b ("ships"), but the expensive part of that phase is a space scene
	and the part that is actually costing the player their evening is ground
	travel through worlds that already exist.

	ONE AT A TIME, AND IT FOLLOWS YOU
	A summon while you already have one puts the old one away. That is not a
	convenience -- it is what stops a server accumulating parked speeders that
	nobody will ever come back for, without needing a timer, a cleanup pass,
	or a rule the player has to be told.

	THE DRIVER SIMULATES THEIR OWN SPEEDER
	`SetNetworkOwner(driver)` and the constraints are written by the driver's
	own client (see VehicleController). Anything else costs a round trip
	between pressing W and moving, which at speed is the difference between a
	vehicle and a suggestion. What that concedes is real and worth stating: a
	modified client could make its own speeder go faster than the config says.
	It buys nothing -- there is no vehicle combat, no race, and no reward tied
	to arriving early -- and the ownership record, the price, the level gate
	and the seat are all still decided here.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Ships = require(Shared.Config.Ships)
local ShipModel = require(Shared.Rig.ShipModel)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type PlayerProfile = Types.PlayerProfile

local VehicleService = {
	name = "VehicleService",
	priority = 36, -- after ShopService, which owns the till that sells these
}

local spawned: { [Player]: Model } = {}

local function data()
	return ServiceLoader.get("DataService")
end

local function notify(player: Player, message: string, kind: string)
	Net.fireClient(Net.Event.Notify, player, message, kind)
end

local function vehicleFolder(): Folder
	local existing = Workspace:FindFirstChild("Vehicles")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = Workspace
	return folder
end

--------------------------------------------------------------------------------
-- Ownership
--------------------------------------------------------------------------------

--[[
	True if `player` has unlocked `shipId`.

	`unlockedShips` is a plain array of ids and not part of the inventory,
	because a speeder is not a thing you carry: it cannot be dropped, sold,
	rolled with affixes or counted against the bag cap, and putting it in
	`profile.inventory` would have meant teaching every one of those paths
	about an item they must all refuse.
]]
function VehicleService.owns(profile: PlayerProfile, shipId: string): boolean
	return table.find(profile.unlockedShips, shipId) ~= nil
end

--- Records a purchase. Called by ShopService, which has already taken payment.
function VehicleService.grant(player: Player, shipId: string)
	data().update(player, function(p: PlayerProfile)
		if not table.find(p.unlockedShips, shipId) then
			table.insert(p.unlockedShips, shipId)
		end
		-- The first speeder you buy is the one you meant to ride. Making the
		-- player buy it and then also select it is a step with one possible
		-- answer, and the failure it produces is "I bought a speeder and the
		-- key does nothing".
		if not p.equipped.ship then
			p.equipped.ship = shipId
		end
	end)
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------

--- Puts away whatever `player` currently has out. Safe to call at any time.
function VehicleService.dismiss(player: Player)
	local model = spawned[player]
	spawned[player] = nil
	if not model then
		return
	end

	-- Anyone riding it, including passengers who did not ask for this, is put
	-- back on their feet rather than deleted along with the seat.
	for _, seat in model:GetDescendants() do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			local occupant = seat.Occupant
			if occupant then
				occupant.Sit = false
			end
		end
	end

	model:Destroy()
end

--[[
	Hands physics to whoever is in the driver's seat, and takes it back.

	Network ownership cannot be set on an anchored part, so the order matters
	in both directions: unanchor before granting, revoke before anchoring.
	Getting that backwards throws, and the symptom is a speeder that seats you
	and then refuses to move.

	Only the driver's seat is watched, not the passengers'. A passenger is
	cargo; the physics has to belong to exactly one machine and it belongs to
	whoever is steering.
]]
local function watch(model: Model)
	local chassis = model.PrimaryPart :: BasePart
	local seat = ShipModel.driverSeat(model)
	if not seat then
		warn(`[VehicleService] {model.Name} has no driver seat`)
		return
	end

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not chassis.Parent then
			return
		end

		local occupant = seat.Occupant
		local character = occupant and occupant.Parent
		local driver = if character and character:IsA("Model")
			then Players:GetPlayerFromCharacter(character)
			else nil

		if driver then
			chassis.Anchored = false
			chassis:SetNetworkOwner(driver)
		else
			-- Covers an NPC sitting in it as well as an empty seat: without a
			-- player to simulate it, nothing would be driving the constraints
			-- and it would simply drop out of the sky.
			chassis:SetNetworkOwner(nil)
			chassis.AssemblyLinearVelocity = Vector3.zero
			chassis.AssemblyAngularVelocity = Vector3.zero
			chassis.Anchored = true
		end
	end)
end

--[[
	Calls in the player's selected speeder, or puts the current one away.

	Returns false and a reason the player can be shown. A single toggle rather
	than two verbs because there is only ever one, and a player who has
	forgotten which state they are in presses the same key either way.
]]
function VehicleService.toggle(player: Player): (boolean, string?)
	if spawned[player] then
		VehicleService.dismiss(player)
		return true, nil
	end

	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local shipId = profile.equipped.ship
	if not shipId or not Ships.exists(shipId) then
		return false, "You do not own a speeder"
	end
	if not VehicleService.owns(profile, shipId) then
		return false, "You do not own that speeder"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then
		return false, "Not while you are down"
	end

	local def = Ships.get(shipId)
	local model = ShipModel.build(shipId)
	local chassis = model.PrimaryPart :: BasePart

	--[[
		Placed ahead of the player at their own height plus the hover gap,
		facing the same way they are.

		Not raycast down to find the ground: a speeder dropped a few studs
		high falls those few studs, which looks like a delivery, whereas one
		placed by a raycast that hit a rock ends up inside it. The hover loop
		takes over on the first frame either way.
	]]
	local ahead = root.CFrame * CFrame.new(0, 0, -Ships.SUMMON_DISTANCE)
	model:PivotTo(
		CFrame.new(ahead.Position + Vector3.new(0, def.hoverHeight, 0), ahead.Position + ahead.LookVector)
	)

	-- Parked speeders hover. Anchoring an idle one is not a shortcut around
	-- physics, it is what a repulsorlift does when you get off it -- and it
	-- means an unoccupied vehicle costs the server nothing at all.
	chassis.Anchored = true
	model.Parent = vehicleFolder()

	model:SetAttribute("OwnerUserId", player.UserId)
	spawned[player] = model

	watch(model)

	notify(player, `{def.displayName} standing by`, "Info")
	return true, nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function VehicleService.init()
	Net.onServerEvent(Net.Event.SummonVehicle, function(player: Player)
		local ok, reason = VehicleService.toggle(player)
		if not ok and reason then
			notify(player, reason, "Error")
		end
	end, {
		-- Deliberately tight. Every call either builds or destroys a physics
		-- model, which is the most expensive thing a keypress can do here.
		rateLimit = 2,
		validate = Net.check.none,
	})
end

--[[
	A speeder belongs to one character, not to the session.

	`CharacterRemoving` fires on death and on travel alike, and both want the
	same answer. Death is obvious. Travel is the one that would otherwise
	break something: `PlayerService.travelTo` reloads the character into a
	world that WorldService has rebuilt from scratch, and a speeder left
	behind would be parked in coordinates that now belong to a different
	planet's geometry.

	Connected once per player rather than once per summon, because a summon
	is a keypress and a player can press a key all afternoon.
]]
local function follow(player: Player)
	player.CharacterRemoving:Connect(function()
		VehicleService.dismiss(player)
	end)
end

function VehicleService.start()
	for _, problem in Ships.validate() do
		warn(`[VehicleService] {problem}`)
	end

	Players.PlayerAdded:Connect(follow)
	for _, player in Players:GetPlayers() do
		follow(player)
	end
	Players.PlayerRemoving:Connect(VehicleService.dismiss)
end

return VehicleService
