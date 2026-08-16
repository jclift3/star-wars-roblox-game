--!strict
--[[
	VendorController.luau

	Puts a sign over the people who will sell you something.

	WHY
	Trading already worked: every NPC carries a ProximityPrompt that reads
	"Trade" for a vendor, and `ShopService` measures the range server-side. What
	was missing was *discovery*. That prompt only appears at 12 studs, which
	means you have to already be standing next to the right person to learn they
	are the right person -- in a market square holding five merchants and
	seventeen civilians who look no different at a distance.

	So this is a signpost, not an interaction. Nothing here can buy anything.

	BOUNDED ON PURPOSE
	Tatooine spawns fourteen Jawas and five merchants. Labelling all nineteen
	would be worse than labelling none, so only the nearest few are drawn, from
	a fixed pool of billboards that are re-pointed rather than rebuilt.

	NOT DRAWN THROUGH WALLS
	Unlike the objective beacon, these are ordinary billboards: a shop sign
	glowing through a building is how you end up walking into a wall. If you
	cannot see the vendor, you should not see their sign.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NPCArchetypes = require(Shared.Config.NPCArchetypes)
local Palette = require(Shared.Config.Palette)
local Shops = require(Shared.Config.Shops)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local VendorController = {
	name = "VendorController",
	priority = 46,
}

local player = Players.LocalPlayer

local ACCENT = Palette.RebelOrange
local TEXT = Color3.fromRGB(232, 236, 242)
local DIM = Color3.fromRGB(150, 154, 162)

-- Far enough to pick a stall out across a market, close enough that a town on
-- the horizon is not a wall of floating text.
local SIGHT_RANGE = 140
local MAX_SIGNS = 4
-- A sign does not need to be frame-accurate: the billboard tracks its adornee
-- by itself, so this interval only governs *which* vendors are labelled.
local REFRESH_INTERVAL = 0.35

type Sign = {
	gui: BillboardGui,
	title: TextLabel,
	hint: TextLabel,
}

type Candidate = {
	adornee: BasePart,
	shopName: string,
	distance: number,
}

local signs: { Sign } = {}
local since = REFRESH_INTERVAL

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function buildSign(gui: Instance): Sign
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VendorSign"
	billboard.Size = UDim2.fromOffset(190, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	-- Cheap failsafe: even if the refresh leaves a stale adornee for a tick,
	-- Roblox stops drawing it past the range we care about.
	billboard.MaxDistance = SIGHT_RANGE
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	billboard.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = TEXT
	title.TextStrokeTransparency = 0.4
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Parent = billboard

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 13
	hint.TextColor3 = DIM
	hint.TextStrokeTransparency = 0.5
	hint.Position = UDim2.fromOffset(0, 18)
	hint.Size = UDim2.new(1, 0, 0, 16)
	hint.Parent = billboard

	return { gui = billboard, title = title, hint = hint }
end

--------------------------------------------------------------------------------
-- Finding vendors
--------------------------------------------------------------------------------

--[[
	Every vendor in sight, nearest first.

	Reads the replicated NPC models directly, the same way the server does in
	`ShopService.vendorNear` -- vendors wander, so a registry of posts would
	point at where they used to be.
]]
local function vendorsInSight(from: Vector3): { Candidate }
	local found: { Candidate } = {}

	local crowd = Workspace:FindFirstChild("NPCs")
	if not crowd then
		return found
	end

	for _, model in crowd:GetDescendants() do
		if not model:IsA("Model") then
			continue
		end
		local archetypeId = model:GetAttribute("Archetype") :: string?
		if not archetypeId or not NPCArchetypes.exists(archetypeId) then
			continue
		end
		local shopId = NPCArchetypes.get(archetypeId).shop
		if not shopId or not Shops.exists(shopId) then
			continue
		end

		local root = model:FindFirstChild("HumanoidRootPart")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			continue -- a dead shopkeeper is not open for business
		end

		local distance = (root.Position - from).Magnitude
		if distance <= SIGHT_RANGE then
			table.insert(found, {
				adornee = root,
				shopName = Shops.get(shopId).displayName,
				distance = distance,
			})
		end
	end

	table.sort(found, function(a: Candidate, b: Candidate)
		return a.distance < b.distance
	end)
	return found
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------

local function hideAll()
	for _, sign in signs do
		sign.gui.Enabled = false
	end
end

local function refresh()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		hideAll()
		return
	end

	-- A panel has the screen; signs behind it are noise. Same rule the
	-- objective waypoint follows.
	for _, name in
		{ "InventoryController", "MissionBoardController", "SkillTreeController", "GalaxyMapController" }
	do
		local panel = ServiceLoader.find(name)
		if panel and panel.isOpen() then
			hideAll()
			return
		end
	end

	local found = vendorsInSight(root.Position)

	for index, sign in signs do
		local candidate = found[index]
		if not candidate then
			sign.gui.Enabled = false
			continue
		end

		sign.gui.Adornee = candidate.adornee
		sign.gui.Enabled = true
		sign.title.Text = candidate.shopName

		if candidate.distance <= Shops.VENDOR_RANGE then
			-- The one state that matters: close enough that the panel will
			-- actually let you buy.
			sign.title.TextColor3 = ACCENT
			sign.hint.TextColor3 = ACCENT
			sign.hint.Text = "[B]  Trade"
		else
			sign.title.TextColor3 = TEXT
			sign.hint.TextColor3 = DIM
			sign.hint.Text = `{math.floor(candidate.distance)} studs`
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function VendorController.init()
	local gui = player:WaitForChild("PlayerGui")
	for _ = 1, MAX_SIGNS do
		table.insert(signs, buildSign(gui))
	end
end

function VendorController.start()
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since < REFRESH_INTERVAL then
			return
		end
		since = 0
		refresh()
	end)
end

return VendorController
