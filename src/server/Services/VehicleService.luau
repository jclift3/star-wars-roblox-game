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
local Inventory = require(Shared.Core.Inventory)
local Net = require(Shared.Core.Net)
local Panels = require(Shared.Core.Panels)
local Orbit = require(Shared.Config.Orbit)
local Planets = require(Shared.Config.Planets)
local Ships = require(Shared.Config.Ships)
local ShipModel = require(Shared.Rig.ShipModel)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type PlayerProfile = Types.PlayerProfile

local VehicleService = {
	name = "VehicleService",
	priority = 36, -- after ShopService, which owns the till that sells these
}

local spawned: { [Player]: Model } = {}

--[[
	How long to wait before putting a pilot back in a seat they cannot leave.

	Leaving a `VehicleSeat` is a jump: Roblox reads the same key that got you
	out, so a character re-seated inside the same frame leaps straight back
	out again on the input still being held. A quarter second is past the
	jump and still well short of anybody noticing they were ever loose.
]]
local RESEAT_DELAY = 0.25

--[[
	Seconds between "which world is this hull over?" sweeps.

	Nine distance checks per piloted starship, and the answer only matters at
	the moment a ship crosses a system boundary at a few hundred studs a
	second -- so a second of lag on the sky changing is under a wingspan of
	travel, and the cost is nothing.
]]
local SYSTEM_POLL = 1

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
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
	Whether there is a pad here at all, whoever is parked on it.

	Deliberately a different question from `nearestPad`. That one refuses a
	pad another player's hull is sitting on, because it is choosing somewhere
	to *put* a ship. This one asks whether a person could stand here, and the
	ship on the disc is the one they are about to climb out of.
]]
local function padNear(position: Vector3): boolean
	for _, pad in CollectionService:GetTagged(Ships.PAD_TAG) do
		if pad:IsA("BasePart") and (pad.Position - position).Magnitude < Ships.PAD_RANGE then
			return true
		end
	end
	return false
end

--[[
	Whether stepping out of this hull would be stepping into vacuum.

	Two ways to be nowhere survivable: above the world's ceiling, or outside
	any world's system at all. The first is orbit and the second is the dark
	between worlds, and a character released into either falls forever --
	`Workspace.FallenPartsDestroyHeight` is not even reachable from up there,
	so it is not even a quick death.
]]
local function inVacuum(chassis: BasePart): boolean
	local system = Orbit.systemAt(chassis.Position)
	if not system then
		return true
	end
	return chassis.Position.Y >= Orbit.ceilingFor(system)
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
-- Durability
--------------------------------------------------------------------------------

--[[
	DAMAGE LIVES ON THE PROFILE, NOT ON THE WRECK

	The obvious build is a broken hull left standing in the world with a
	repair prompt on it. It is also the wrong one, and the reason is the
	summon key: `toggle` is a toggle, so a player whose speeder had just
	been wrecked would press V once to put the wreck away and once more to
	get a factory-fresh one out. Free repairs, discovered in about ten
	seconds by anyone who presses a key twice.

	Keyed by ship id on the profile, none of that is reachable. Dismissing a
	broken hull and calling it back gets you the same broken hull, on this
	server or the next one, tomorrow. The model in the world is a *view* of
	a number in the save file, which is the same shape as everything else
	the player owns.

	It also gets the fiction right for free: the speeder is not a rental.
]]

--[[
	What mends a hull, and how much of one.

	`HullPlate` already existed -- a salvage pickup with a world model, a
	prompt verb of "Salvage", and exactly one use anywhere in the game (a
	single Deliver objective in Missions.luau). It has been sitting in the
	loot tables being scenery. This is the job it was named for.

	A fraction of the hull's own maximum rather than a flat number, so a
	plate is worth the same *proportion* on a Swoop as on a Freighter. Two
	plates rebuild anything from scrap, which is a real cost without being
	an expedition.
]]
local REPAIR_ITEM = "HullPlate"
local REPAIR_FRACTION = 0.5

--- Current and maximum integrity of `shipId` for this profile.
function VehicleService.integrity(profile: PlayerProfile, shipId: string): (number, number)
	local max = Ships.get(shipId).integrity
	local taken = profile.shipDamage[shipId] or 0
	return math.clamp(max - taken, 0, max), max
end

--[[
	Publishes a hull's condition onto the model itself.

	Attributes rather than a remote, for the same reason the weapon tint is:
	Roblox replicates them to everyone who can see the model, so the driver's
	gauge, a brother watching from the kerb and the prompt below all read one
	server-authored number and cannot disagree.
]]
local function publish(model: Model, current: number, max: number)
	model:SetAttribute("Integrity", current)
	model:SetAttribute("MaxIntegrity", max)
	model:SetAttribute("Disabled", current <= 0)
end

--- True if the hull `player` has out is too broken to drive.
local function isDisabled(model: Model): boolean
	return model:GetAttribute("Disabled") == true
end

--[[
	Stops a dead hull dead: pilot out, physics back, and it stays put.

	Deliberately *not* a despawn. The player chose "disabled until repaired
	in the field", and the whole weight of that choice is that the thing is
	still there, in the wrong place, and you are looking at it.
]]
local function ground(model: Model)
	local chassis = model.PrimaryPart :: BasePart
	for _, seat in model:GetDescendants() do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			local occupant = seat.Occupant
			if occupant then
				occupant.Sit = false
			end
		end
	end
	-- Ownership must be revoked before anchoring, the same ordering `watch`
	-- documents -- backwards, it throws, and the hull keeps flying.
	chassis:SetNetworkOwner(nil)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	chassis.Anchored = true
end

--[[
	Takes damage off the hull `player` currently has out.

	WHO IS TRUSTED WITH THIS, AND WHY IT IS THE CLIENT
	The driver's own machine simulates the vehicle -- that is settled at the
	top of this file and is not up for renegotiation at 200 studs a second.
	Only that machine knows it hit something, so only that machine can say
	so. What that concedes is worth stating plainly and is *smaller* than it
	looks: a modified client can decline to report its own crashes, and the
	prize for doing so is not paying a repair bill on its own speeder. It
	cannot damage anybody else's, because nobody else's is ever the subject
	of this call.

	That asymmetry is exactly why vehicle *weapons* will not come through
	here when they arrive. A shot that hurts your brother's hull has to be
	decided by the server, the way every other shot in the game already is.

	The clamp is therefore for bugs, not for cheats. A hull cannot lose more
	speed in one impact than its own top speed, so anything larger is a
	physics spike -- a spawn, a teleport, a lift -- and not a crash.
]]
function VehicleService.impact(player: Player, amount: number)
	local model = spawned[player]
	if not model or isDisabled(model) then
		return
	end
	local shipId = model:GetAttribute("ShipId")
	if type(shipId) ~= "string" or not Ships.exists(shipId) then
		return
	end

	local def = Ships.get(shipId)
	local damage = math.clamp(amount, 0, def.speed)
	if damage < 1 then
		return
	end

	local current, max = 0, def.integrity
	data().update(player, function(p: PlayerProfile)
		local taken = math.min((p.shipDamage[shipId] or 0) + damage, def.integrity)
		p.shipDamage[shipId] = taken
		current = def.integrity - taken
	end)

	publish(model, current, max)
	if current <= 0 then
		ground(model)
		local plates = math.ceil(1 / REPAIR_FRACTION)
		notify(player, `{def.displayName} is wrecked. {plates} hull plates will get it running.`, "Error")
	end
end

--[[
	Spends one hull plate on the vehicle `player` is standing at.

	Returns false and something to show them. Repairing a hull that is
	merely dented is allowed on purpose: making the player wait until it is
	dead before a plate will go in teaches them to drive it into a wall.
]]
function VehicleService.repair(player: Player): (boolean, string?)
	local model = spawned[player]
	if not model then
		return false, "Nothing here to work on"
	end
	local shipId = model:GetAttribute("ShipId")
	if type(shipId) ~= "string" or not Ships.exists(shipId) then
		return false, "Nothing here to work on"
	end

	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local def = Ships.get(shipId)
	local current, max = VehicleService.integrity(profile, shipId)
	if current >= max then
		return false, `The {def.displayName} is not damaged`
	end
	if Inventory.count(profile.inventory, REPAIR_ITEM) < 1 then
		return false, `You need hull plating. Salvage some -- wrecks and scrapyards have it.`
	end

	--[[
		Field Repair, ranked in Engineering, is what a plate is worth to you.

		That node has been sitting in `Progression.luau` marked
		`unimplemented = "Nothing damages a ship yet"` since the trees were
		written, and its blocker was true right up until the paragraph above
		this one. It is now the only thing in the game that reads
		`RepairMult`, which is what lets the `unimplemented` come off -- and
		it means the tree's one dead node is dead because of a missing
		mechanic rather than a missing idea.

		Five ranks take a plate from half a hull to 110% of one, so a
		maxed engineer walks away from any wreck for a single plate. That is
		a real reason to be the one carrying them.
	]]
	local mult = progression().getStats(player)["RepairMult"] or 1
	local mended = 0
	data().update(player, function(p: PlayerProfile)
		-- `remove` returns what it actually took, and the payout is against
		-- that, not against what was asked for -- Core/Inventory.luau's rule.
		local took = Inventory.remove(p.inventory, REPAIR_ITEM, 1)
		if took < 1 then
			return
		end
		local taken = math.max((p.shipDamage[shipId] or 0) - def.integrity * REPAIR_FRACTION * mult * took, 0)
		mended = (p.shipDamage[shipId] or 0) - taken
		if taken <= 0 then
			p.shipDamage[shipId] = nil
		else
			p.shipDamage[shipId] = taken
		end
	end)
	if mended <= 0 then
		return false, "You need hull plating"
	end

	local after = data().get(player)
	local now = if after then (VehicleService.integrity(after, shipId)) else current
	publish(model, now, max)
	if now > 0 then
		-- Only unanchored if somebody gets back in; `watch` owns that. All
		-- this has to undo is the "will not start" flag.
		model:SetAttribute("Disabled", false)
	end
	return true, `{def.displayName} repaired -- {math.floor(now)}/{math.floor(max)}`
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
		-- A wreck offers the only thing it can do. Same prompt, same key: the
		-- label has always been what says which of its jobs is currently
		-- true, and being broken is a third one.
		if isDisabled(model) then
			prompt.Enabled = true
			prompt.ActionText = "Repair"
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

	model:GetAttributeChangedSignal("Disabled"):Connect(relabel)

	if prompt then
		prompt.Triggered:Connect(function(player: Player)
			local humanoid = livingHumanoid(player)
			if not humanoid then
				return
			end
			if isDisabled(model) then
				-- Anyone may turn a spanner on it, but it is still the
				-- owner's speeder and the owner's plating -- `repair` reads
				-- the caller's own bag and their own hull, so a passing
				-- stranger simply finds nothing of theirs here to mend.
				local ok, reason = VehicleService.repair(player)
				if reason then
					notify(player, reason, if ok then "Success" else "Error")
				end
				relabel()
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

	--[[
		Who was at the controls a moment ago.

		`Occupant` tells you who is in the seat now, and the case that needs
		guarding is the one where the answer is nobody. Without this the
		service cannot tell a pilot stepping out from a seat that was already
		empty, and they are the same event to Roblox.
	]]
	local lastDriver: Player? = nil

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

		local left = lastDriver
		lastDriver = driver

		--[[
			YOU CANNOT STEP OUT INTO VACUUM

			The pad rule read in the other direction. A starship launches from
			a pad because a hull appearing out of nothing is not a thing a
			freighter does; by the same token a pilot may only *leave* one
			where there is ground or a pad under it. Anywhere else, pressing
			the jump key in orbit would end the session -- and the player who
			pressed it was pressing it to look out of the window.

			Deferred rather than immediate: leaving a `VehicleSeat` is a jump,
			and a character re-seated inside the same frame is a character
			that leaps straight back out again on the input still being held.
			Every condition is re-tested on the other side of that wait,
			because a quarter of a second is long enough for the ship to have
			been dismissed or the pilot to have died.

			`spawned[left] == model` is what keeps this out of the way of
			`dismiss`, which empties every seat on purpose and clears the
			table before it does.
		]]
		if
			not driver
			and left
			and spawned[left] == model
			and inVacuum(chassis)
			and not padNear(chassis.Position)
		then
			notify(left, "Not out here. Land first, or set down on a pad.", "Error")
			task.delay(RESEAT_DELAY, function()
				if spawned[left] ~= model or seat.Occupant then
					return
				end
				local humanoid = livingHumanoid(left)
				if humanoid and inVacuum(chassis) then
					seat:Sit(humanoid)
				end
			end)
		end

		if driver and isDisabled(model) then
			-- Sitting in it is allowed; going anywhere is not. Tipping them
			-- straight back out would read as the seat being broken rather
			-- than the speeder, and the hull stays anchored either way.
			notify(driver, "It will not start. It needs hull plating.", "Error")
		elseif driver then
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

	-- Before `watch`, which reads `Disabled` the moment it labels the prompt.
	local current, max = VehicleService.integrity(profile, shipId)
	publish(model, current, max)

	watch(model)

	if current <= 0 then
		ground(model)
		notify(player, `The {def.displayName} is wrecked. Repair it where it stands.`, "Error")
		return true, nil
	end

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

	Net.onServerEvent(Net.Event.VehicleImpact, function(player: Player, amount: number)
		VehicleService.impact(player, amount)
	end, {
		-- Loose enough for a hull bouncing along a canyon wall, which is
		-- several genuine impacts a second, and the handler clamps each one
		-- anyway. See `impact` for why a flood here is not worth defending
		-- against: the only hull it can reach is the sender's own.
		rateLimit = 12,
		-- The upper bound is the fastest hull in the file with room over it.
		-- `impact` clamps properly, against the hull actually being driven.
		validate = Net.check.number(0, 1000),
	})
end

--[[
	THE SERVER DECIDES WHICH WORLD YOU ARE OVER

	All nine planets sit in one Workspace on a 12,000-stud grid, so a pilot
	who holds a heading long enough genuinely arrives somewhere else. Nothing
	told the game that until now: `profile.currentPlanet` could only change
	by respawning, so you could fly the whole way and land under the wrong
	sky, among the wrong people, on the wrong mission board.

	Here rather than on the client, because the client owns the hull's
	physics and must not be trusted to say which world it has reached. It
	costs no remote either way -- position replicates back to the server
	regardless of who has network ownership.

	Deep space *keeps* your last world rather than clearing it. Fourteen
	readers take `currentPlanet` as a valid planet id, and there is nothing
	sensible for a sky, a mission board or a spawn point to be when the
	answer is "nowhere".
]]
local function reviewSystems()
	for player, model in spawned do
		local chassis = model.PrimaryPart
		if not chassis or not VehicleService.pilotedStarship(player) then
			continue
		end

		local system = Orbit.systemAt(chassis.Position)
		local profile = data().get(player)
		if not (system and profile) or profile.currentPlanet == system then
			continue
		end

		local ok = ServiceLoader.get("PlayerService").setPlanet(player, system)
		if ok then
			notify(player, `Entering {Planets.get(system).displayName} space`, "Info")
		end
	end
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

	task.spawn(function()
		while true do
			task.wait(SYSTEM_POLL)
			reviewSystems()
		end
	end)
end

return VehicleService
