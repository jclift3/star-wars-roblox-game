--!strict
--[[
	InteriorService.luau

	Owns the one room in the game that belongs to the player: who may board
	it, where it is built, and what is standing in it.

	WHY A SHIP NEEDS AN INSIDE
	A starship has been the most expensive thing in the shop and the only one
	the player never gets to be *in* since ROADMAP 2b. It answers the first
	line of the user's own note ("Customization on interior of spaceships"),
	and it is the only thing in the game that is bought purely because you
	want it -- every other credit spent buys a number that goes up.

	BOARDING IS A TELEPORT, AND IT IS GATED ON THE HULL
	You must have called a starship down and be standing beside it. Not a
	convenience check: it is the whole reason the room reads as *this ship's*
	room rather than as a menu, and it makes the spaceports -- which have
	stood on five worlds with three empty pads each since the first planet
	was generated -- somewhere you go for a second reason.

	Speeders have no inside. A cabin is keyed by starship id in
	Furnishings.luau, which is the same statement made in config.

	THE ROOM IS BUILT SIX THOUSAND STUDS UP
	Above every flight ceiling in the game (the highest is Coruscant's 1,400)
	and off the planet grid on two more axes, so nothing can be seen from a
	world and nothing in a world can be seen from here. *Above* and not
	below, which matters more than it looks: `Workspace.FallenPartsDestroyHeight`
	deletes anything that drops past it, and a character teleported beneath
	it is a character deleted on arrival.

	One cabin per player, built when they board and destroyed when they
	leave. Persisting them would mean a server holding a room nobody is in,
	multiplied by everyone who has ever pressed the key.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Furnishings = require(Shared.Config.Furnishings)
local Ships = require(Shared.Config.Ships)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local CabinBuilder = require(script.Parent.Parent.World.CabinBuilder)

type PlayerProfile = Types.PlayerProfile

local InteriorService = {
	name = "InteriorService",
	priority = 37, -- after VehicleService (36), whose hull you board from
}

--- Where the first cabin stands. See the header for why it is up and not down.
local CABIN_ORIGIN = Vector3.new(-6000, 6000, -6000)

--- Studs between one player's cabin and the next. The longest cabin is 40.
local CABIN_SPACING = 600

local cabins: { [Player]: Model } = {}
local returnTo: { [Player]: CFrame } = {}
local berths: { [number]: Player } = {}

local function data()
	return ServiceLoader.get("DataService")
end

local function notify(player: Player, message: string, kind: string)
	Net.fireClient(Net.Event.Notify, player, message, kind)
end

local function interiorFolder(): Folder
	local existing = Workspace:FindFirstChild("Interiors")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Interiors"
	folder.Parent = Workspace
	return folder
end

--[[
	The patch of sky this player's cabin is built in.

	Reused for as long as they are aboard so that re-placing a furnishing
	rebuilds the room around them rather than moving it, and released on the
	way out so a server that has cycled fifty players is not laying cabins
	out to the horizon.
]]
local function claimBerth(player: Player): number
	for index, holder in berths do
		if holder == player then
			return index
		end
	end
	local index = 1
	while berths[index] do
		index += 1
	end
	berths[index] = player
	return index
end

local function releaseBerth(player: Player)
	for index, holder in berths do
		if holder == player then
			berths[index] = nil
			return
		end
	end
end

local function berthCFrame(index: number): CFrame
	return CFrame.new(CABIN_ORIGIN + Vector3.new((index - 1) * CABIN_SPACING, 0, 0))
end

--------------------------------------------------------------------------------
-- Ownership
--------------------------------------------------------------------------------

function InteriorService.owns(profile: PlayerProfile, furnishingId: string): boolean
	return table.find(profile.unlockedFurnishings, furnishingId) ~= nil
end

--[[
	Records a purchase. Called by ShopService, which has already taken payment.

	The first piece you buy for a given slot is also placed, for the reason
	the first speeder you buy is also equipped: buying a thing and then
	separately being made to use it is a step with one possible answer, and
	the failure it produces is "I bought a bunk and nothing happened".
]]
function InteriorService.grant(player: Player, furnishingId: string)
	if not Furnishings.exists(furnishingId) then
		return
	end
	local slot = Furnishings.get(furnishingId).slot

	data().update(player, function(p: PlayerProfile)
		if not table.find(p.unlockedFurnishings, furnishingId) then
			table.insert(p.unlockedFurnishings, furnishingId)
		end
		if not p.cabin[slot] then
			p.cabin[slot] = furnishingId
		end
	end)
end

--------------------------------------------------------------------------------
-- The room
--------------------------------------------------------------------------------

local function teardown(player: Player)
	local model = cabins[player]
	cabins[player] = nil
	returnTo[player] = nil
	releaseBerth(player)
	if model then
		model:Destroy()
	end
end

--- Draws (or redraws) `player`'s cabin in their berth. Returns its pivot.
local function raise(player: Player, shipId: string, placed: { [string]: string }): CFrame
	local existing = cabins[player]
	if existing then
		existing:Destroy()
	end

	local at = berthCFrame(claimBerth(player))
	local model = CabinBuilder.build(shipId, placed)
	model:PivotTo(at)
	model.Parent = interiorFolder()
	model:SetAttribute("OwnerUserId", player.UserId)
	cabins[player] = model
	return at
end

--[[
	Puts the player inside their own ship.

	Returns false and a reason they can be shown, in the same shape
	VehicleService.toggle uses -- a refusal the caller can print beats a
	silent no-op, which is what a key that sometimes does nothing feels like.
]]
function InteriorService.board(player: Player): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and humanoid and humanoid.Health > 0) then
		return false, "Not while you are down"
	end

	local hull = ServiceLoader.get("VehicleService").spawnedFor(player)
	local shipId = hull and hull:GetAttribute("ShipId")
	if type(shipId) ~= "string" or not Ships.isStarship(shipId) then
		return false, "Call down a starship first"
	end
	if (root.Position - hull:GetPivot().Position).Magnitude > Furnishings.BOARD_RANGE then
		return false, `Stand by your {Ships.get(shipId).displayName} to board it`
	end

	-- Standing up first: a seated character cannot be moved, so teleporting
	-- one out of the pilot's seat leaves them in the seat and the cabin
	-- empty.
	humanoid.Sit = false

	local at = raise(player, shipId, profile.cabin)
	returnTo[player] = root.CFrame
	character:PivotTo(at * CabinBuilder.spawnPointOf(shipId))

	notify(player, `Aboard the {Furnishings.cabinFor(shipId).displayName}`, "Info")
	return true, nil
end

--- Puts the player back where they boarded from and takes the room down.
function InteriorService.leave(player: Player)
	local back = returnTo[player]
	local character = player.Character
	teardown(player)

	if back and character and character.PrimaryPart then
		character:PivotTo(back)
	end
end

function InteriorService.isAboard(player: Player): boolean
	local model: Model? = cabins[player]
	return model ~= nil
end

function InteriorService.toggle(player: Player): (boolean, string?)
	if InteriorService.isAboard(player) then
		InteriorService.leave(player)
		return true, nil
	end
	return InteriorService.board(player)
end

--------------------------------------------------------------------------------
-- Furnishing
--------------------------------------------------------------------------------

--[[
	Puts a furnishing in its slot, or empties the slot when `furnishingId` is
	nil.

	A furnishing declares its own slot, so the client sends what to place and
	never where -- which removes the whole class of request that would put a
	krayt skull in the console bay. Emptying is the one case that needs the
	slot named, because there is no item to read it off.
]]
function InteriorService.place(player: Player, slotId: string, furnishingId: string?): (boolean, string?)
	if not Furnishings.slot(slotId) then
		return false, "No such fitting"
	end

	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	if furnishingId then
		if not Furnishings.exists(furnishingId) then
			return false, "No such fitting"
		end
		if not InteriorService.owns(profile, furnishingId) then
			return false, "You do not own that"
		end
		if Furnishings.get(furnishingId).slot ~= slotId then
			return false, "That does not go there"
		end
	end

	data().update(player, function(p: PlayerProfile)
		-- Through `any`, because clearing a slot means writing nil into a
		-- map declared as holding strings, and that is exactly the
		-- assignment `--!strict` refuses to spell.
		(p.cabin :: any)[slotId] = furnishingId
	end)

	--[[
		Redrawn under the player's feet if they are standing in it.

		Rebuilding the whole room for one piece is the cheap answer and the
		right one: a cabin is around forty parts, it is built in a place
		nobody else can see, and swapping a single furnishing in place means
		this service holding a second index of what is currently drawn --
		state that can disagree with the profile, which is the bug the
		rebuild cannot have.
	]]
	if cabins[player] then
		local fresh = data().get(player)
		local hull = cabins[player]:GetAttribute("ShipId")
		if fresh and type(hull) == "string" then
			local at = raise(player, hull, fresh.cabin)
			local character = player.Character
			if character and character.PrimaryPart then
				character:PivotTo(at * CabinBuilder.spawnPointOf(hull))
			end
		end
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function InteriorService.init()
	Net.onServerEvent(Net.Event.ToggleCabin, function(player: Player)
		local ok, reason = InteriorService.toggle(player)
		if not ok and reason then
			notify(player, reason, "Error")
		end
	end, {
		-- Tight for the same reason SummonVehicle is: every call either
		-- builds or destroys a roomful of parts.
		rateLimit = 2,
		validate = Net.check.none,
	})

	Net.onServerEvent(
		Net.Event.PlaceFurnishing,
		function(player: Player, slotId: string, furnishingId: string?)
			local ok, reason = InteriorService.place(player, slotId, furnishingId)
			if not ok and reason then
				notify(player, reason, "Error")
			end
		end,
		{
			rateLimit = 6,
			validate = Net.args(Net.check.string(64), Net.check.optional(Net.check.string(64))),
		}
	)
end

--[[
	A cabin belongs to one character, not to the session.

	`CharacterRemoving` covers death, travel and respawn alike, and all three
	want the same answer: take the room down without teleporting anybody,
	because the body that was standing in it no longer exists. Teleporting
	first would be writing a CFrame to a model Roblox is in the middle of
	destroying.
]]
local function follow(player: Player)
	player.CharacterRemoving:Connect(function()
		teardown(player)
	end)
end

function InteriorService.start()
	for _, problem in Furnishings.validate() do
		warn(`[InteriorService] {problem}`)
	end

	Players.PlayerAdded:Connect(follow)
	for _, player in Players:GetPlayers() do
		follow(player)
	end
	Players.PlayerRemoving:Connect(teardown)
end

return InteriorService
