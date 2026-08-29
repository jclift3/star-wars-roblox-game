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

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)
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
-- Landing pads
--------------------------------------------------------------------------------

--[[
	The nearest free landing pad to `position`, or nil if there is none.

	"Free" means no other player's ship is already sitting on it. A spaceport
	draws three pads and the two brothers this game is for play in the same
	room, so the case where both of them call a hull down onto the same disc
	is not a corner -- it is Saturday. Two physics models occupying the same
	coordinates shove each other off it.

	Scanning every tagged pad in the world rather than only this planet's is
	deliberate laziness that is also correct: there are fifteen pads across
	nine worlds and the planets are 12,000 studs apart, so anything on
	another world fails the range test before it fails anything else.
]]
local function nearestPad(position: Vector3): BasePart?
	local taken: { [BasePart]: boolean } = {}
	for _, model in spawned do
		local chassis = model.PrimaryPart
		if not chassis then
			continue
		end
		for _, pad in CollectionService:GetTagged(Ships.PAD_TAG) do
			if pad:IsA("BasePart") and (pad.Position - chassis.Position).Magnitude < pad.Size.Y * 0.5 then
				taken[pad] = true
			end
		end
	end

	local best: BasePart? = nil
	local bestDistance = Ships.PAD_RANGE
	for _, pad in CollectionService:GetTagged(Ships.PAD_TAG) do
		if not pad:IsA("BasePart") or taken[pad] then
			continue
		end
		local distance = (pad.Position - position).Magnitude
		if distance < bestDistance then
			best = pad
			bestDistance = distance
		end
	end
	return best
end

--[[
	The one thing the player has to do next to get a starship on the ground.

	Every refusal in this chain used to name the state: "Call down a starship
	first", "You have no vehicle selected". Both are true, neither says what
	to press, and between them sits a purchase at a vendor in a district you
	may never have walked to. That is *finished but unreachable* -- the
	failure this project has now shipped four times -- and it costs a player
	the single most expensive thing they own.

	There are four rungs and the player can be standing on any of them, so
	the message says which. Keys come from the bindings rather than being
	typed, because a hint that is separately authored is a hint that starts
	lying the day somebody rebinds the key.
]]
function VehicleService.starshipHint(player: Player): string
	local summon = Ships.SUMMON_KEY.Name
	local profile = data().get(player)
	if not profile then
		return `Press {summon} at a landing pad to call down a starship`
	end

	local owned: string? = nil
	for _, id in profile.unlockedShips do
		if Ships.exists(id) and Ships.isStarship(id) then
			owned = id
			break
		end
	end
	if not owned then
		return "You own no starship. The Ship Broker at a spaceport sells them."
	end

	local chosen = profile.equipped.ship
	if not (chosen and Ships.exists(chosen) and Ships.isStarship(chosen)) then
		local gear = Panels.toggleKey("InventoryController")
		local key = if gear then gear.Name else "B"
		return `Choose your {Ships.get(owned).displayName} in GEAR ({key}), then press {summon} at a landing pad`
	end

	return `Press {summon} at a landing pad to call down your {Ships.get(chosen).displayName}`
end

--[[
	The starship `player` is currently at the controls of, if any.

	TravelService asks, because sitting in a hull you own is what turns a
	chartered fare into a fuel bill. Deliberately the *driver's* seat and
	nothing else: a passenger is riding, and letting a passenger buy the
	cheap fare would mean one player with a Dagger discounting the whole
	server's travel by standing still.
]]
function VehicleService.pilotedStarship(player: Player): string?
	local model = spawned[player]
	if not model then
		return nil
	end
	local shipId = model:GetAttribute("ShipId")
	if type(shipId) ~= "string" or not Ships.isStarship(shipId) then
		return nil
	end
	local seat = ShipModel.driverSeat(model)
	local occupant = seat and seat.Occupant
	local character = occupant and occupant.Parent
	local driver = if character and character:IsA("Model")
		then Players:GetPlayerFromCharacter(character)
		else nil
	return if driver == player then shipId else nil
end

--- The vehicle `player` currently has out, if any. Read-only to callers;
--- everything that creates or removes one goes through this service.
function VehicleService.spawnedFor(player: Player): Model?
	return spawned[player]
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
local function livingHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function watch(model: Model)
	local chassis = model.PrimaryPart :: BasePart
	local seat = ShipModel.driverSeat(model)
	if not seat then
		warn(`[VehicleService] {model.Name} has no driver seat`)
		return
	end

	--[[
		ONE PROMPT, AND THE LABEL SAYS WHICH SEAT IT IS OFFERING

		Reported three times over 2026-08-19: the ship could not be driven.
		Walking into a seat was never going to work -- `ShipModel` seals every
		seat inside the chassis collider, and that file carries the geometry --
		and the prompt that replaced it was drawn at a seat, which is to say
		inside an opaque hull, so it was never seen either. It hangs above the
		ship now. This is the rule it announces.

		An empty ship is flown by whoever gets in. Once somebody is at the
		controls, boarding puts you in the back instead, which is the case the
		other seats exist for and the case the two brothers actually play.
		Rather than leave that as a hidden promotion nobody could predict, the
		label reads "Pilot" or "Ride" depending on which half of it is
		currently true, and a ship with nowhere left to sit turns its prompt
		off rather than offering a seat it has not got.
	]]
	-- `VehicleSeat` does not inherit from `Seat`, so this is exactly the
	-- passenger seats and never the driver's.
	local riders: { Seat } = {}
	for _, part in model:GetChildren() do
		if part:IsA("Seat") then
			table.insert(riders, part)
		end
	end

	local prompt = ShipModel.boardPrompt(model)

	local function freeRider(): Seat?
		for _, rider in riders do
			if not rider.Occupant then
				return rider
			end
		end
		return nil
	end

	local function relabel()
		if not prompt then
			return
		end
		if not seat.Occupant then
			prompt.Enabled = true
			prompt.ActionText = ShipModel.PILOT_TEXT
			return
		end
		prompt.Enabled = freeRider() ~= nil
		prompt.ActionText = ShipModel.RIDE_TEXT
	end

	if prompt then
		prompt.Triggered:Connect(function(player: Player)
			local humanoid = livingHumanoid(player)
			if not humanoid then
				return
			end
			if not seat.Occupant then
				seat:Sit(humanoid)
				return
			end
			local rider = freeRider()
			if rider then
				rider:Sit(humanoid)
			end
		end)
	end
	for _, rider in riders do
		rider:GetPropertyChangedSignal("Occupant"):Connect(relabel)
	end

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not chassis.Parent then
			return
		end

		relabel()

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
		local gear = Panels.toggleKey("InventoryController")
		local key = if gear then gear.Name else "B"
		return false,
			if #profile.unlockedShips > 0
				then `Choose a vehicle in GEAR ({key}) first`
				else `You own no vehicle. Buy one from a trader, then choose it in GEAR ({key}).`
	end
	if not VehicleService.owns(profile, shipId) then
		return false, "You do not own that"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then
		return false, "Not while you are down"
	end

	local def = Ships.get(shipId)

	--[[
		A starship needs somewhere to have been.

		A speeder appearing out of nothing beside you is a repulsorlift
		valet and reads as one. A freighter doing it does not, and the
		refusal is worth more than the convenience: it is the only reason
		the player ever walks to a spaceport, and the spaceports have been
		standing on five worlds with three empty pads each since the first
		planet was generated.

		Checked before the model is built, so a refusal costs nothing.
	]]
	local pad: BasePart? = nil
	if Ships.isStarship(shipId) then
		pad = nearestPad(root.Position)
		if not pad then
			return false, "Starships launch from a landing pad. Find a spaceport."
		end
	end

	local model = ShipModel.build(shipId)
	local chassis = model.PrimaryPart :: BasePart

	--[[
		On the pad if there is one, otherwise ahead of the player at their
		own height plus the hover gap. Facing the way they are either way.

		Not raycast down to find the ground: a speeder dropped a few studs
		high falls those few studs, which looks like a delivery, whereas one
		placed by a raycast that hit a rock ends up inside it. The hover loop
		takes over on the first frame either way.
	]]
	local at: Vector3
	if pad then
		-- The pad is a cylinder stood on end, so its thickness is on X and
		-- its 68-stud face is the disc. Reading `Size.Y` would put the ship
		-- thirty-four studs in the air.
		at = pad.Position + Vector3.new(0, pad.Size.X * 0.5 + def.hoverHeight, 0)
	else
		at = (root.CFrame * CFrame.new(0, 0, -Ships.SUMMON_DISTANCE)).Position
			+ Vector3.new(0, def.hoverHeight, 0)
	end

	-- Flattened, because `CFrame.new(at, at)` throws and a character looking
	-- straight down is the one way the two arguments can be equal.
	local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if facing.Magnitude < 0.01 then
		facing = Vector3.new(0, 0, -1)
	end
	model:PivotTo(CFrame.new(at, at + facing))

	-- Parked speeders hover. Anchoring an idle one is not a shortcut around
	-- physics, it is what a repulsorlift does when you get off it -- and it
	-- means an unoccupied vehicle costs the server nothing at all.
	chassis.Anchored = true
	model.Parent = vehicleFolder()

	model:SetAttribute("OwnerUserId", player.UserId)
	spawned[player] = model

	watch(model)

	--[[
		The toast says how to ride it, because nothing else in the game does.

		It used to say "walk into the seat", which was true of the code and
		false of the game: the seats are inside the chassis collider and
		could not be walked into. Boarding is a prompt now, and the toast
		names the same key and the same word the prompt shows rather than
		describing them, so the two cannot disagree.

		It also says where to look. The prompt floats above the hull, which
		is deliberate and is still the one thing about it a player would not
		guess.

		The steering was the same kind of omission for a different reason:
		`VehicleSeat` turns WASD into `Throttle` and `Steer` for free, and
		free is exactly why no screen ever mentioned it.

		The pitch keys are named only on a starship. A speeder has no use for
		them, and a line that lists two controls that do nothing teaches the
		player that the rest of the line might be wrong too.
	]]
	local board = `Press {Ships.BOARD_PROMPT_KEY.Name} at the {ShipModel.PILOT_TEXT} prompt above it`
	local how = if Ships.isStarship(shipId)
		then `{board}. WASD to fly, {Ships.PITCH_UP_KEY.Name} up, {Ships.PITCH_DOWN_KEY.Name} down.`
		else `{board}, then WASD.`
	notify(player, `{def.displayName} standing by. {how}`, "Info")
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
