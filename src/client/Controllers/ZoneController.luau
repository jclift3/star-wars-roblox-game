--!strict
--[[
	ZoneController.luau

	Announces the district you have walked into, and how dangerous it is.

	WHY
	The world is banded by level: `ZoneDef.distance` decides a district's level
	range (`Planets.bandFor`) and NPCs spawn inside it, so walking outward is
	walking into harder things. None of which is visible. Without this the
	feedback for crossing a band is being killed by something four levels above
	you, some distance from where you made the decision, with no way to connect
	the two -- which is the exact complaint the roadmap raised.

	So: name the district as you enter it, state its level range, and say
	plainly when it is above you.

	READ-ONLY, LIKE THE WAYPOINTS
	The server publishes each district's centre as an attribute on its zone
	folder when it builds the planet -- districts are placed procedurally from
	the planet's seed, so that is the only record of where they ended up. The
	band comes from the same shared config the server levelled the NPCs from,
	so the warning cannot disagree with the fight. Nothing is asked of the
	server and there is no remote.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Panels = require(Shared.Core.Panels)
local Planets = require(Shared.Config.Planets)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local ZoneController = {
	name = "ZoneController",
	priority = 43,
}

local player = Players.LocalPlayer

local TEXT = Color3.fromRGB(232, 236, 242)
local DIM = Color3.fromRGB(150, 158, 170)
local SAFE = Color3.fromRGB(120, 196, 130)
local DANGER = Color3.fromRGB(228, 96, 84)

--- How often to ask which district the player is standing in.
local CHECK_INTERVAL = 0.4
--[[
	How much closer a rival district has to be before the banner changes.

	Districts have no borders -- "which one am I in" is nearest-centre -- so
	without this, standing on the line between two of them flickers the banner
	back and forth every time the player shifts their weight.
]]
local HYSTERESIS = 80

local BANNER_HOLD = 3.5
local BANNER_FADE = 1.0

local screen: ScreenGui
local nameLabel: TextLabel
local bandLabel: TextLabel
local warnLabel: TextLabel

local currentZone: string? = nil
local currentPlanet = ""
local sinceCheck = 0
--- Seconds the banner has left, counting down through the fade.
local showing = 0

local function state()
	return ServiceLoader.get("ClientState")
end

--------------------------------------------------------------------------------
-- Where am I
--------------------------------------------------------------------------------

--[[
	The nearest district centre on `planetId`, or nil if the planet has none.

	`bias` is the district to prefer -- the one the player is already in --
	which gets HYSTERESIS studs of credit so a rival has to be properly closer
	rather than merely closer.
]]
local function nearestZone(planetId: string, position: Vector3, bias: string?): string?
	local root = Workspace:FindFirstChild("Zones")
	local planetFolder = root and root:FindFirstChild(planetId)
	if not planetFolder then
		return nil
	end

	local best: string? = nil
	local bestDistance = math.huge
	for _, zone in planetFolder:GetChildren() do
		local centre = zone:GetAttribute("Centre")
		if typeof(centre) ~= "Vector3" then
			continue
		end
		local distance = (centre - position).Magnitude
		if zone.Name == bias then
			distance -= HYSTERESIS
		end
		if distance < bestDistance then
			best, bestDistance = zone.Name, distance
		end
	end
	return best
end

--- "DuneSea" -> "DUNE SEA". Zone ids are the only name a district has.
local function prettify(id: string): string
	local spaced = (id:gsub("(%l)(%u)", "%1 %2"))
	return spaced:upper()
end

--------------------------------------------------------------------------------
-- The banner
--------------------------------------------------------------------------------

local function announce(planetId: string, zoneId: string, level: number)
	local band = Planets.bandFor(planetId, zoneId)
	local under = Planets.underlevelled(level, band)

	nameLabel.Text = prettify(zoneId)
	nameLabel.TextColor3 = if under then DANGER else TEXT
	bandLabel.Text = `LEVEL {band.min} - {band.max}`
	bandLabel.TextColor3 = if under then DANGER else SAFE

	-- Only the warning says what to do about it. The band on its own is a
	-- number, and a number is not a decision.
	warnLabel.Visible = under
	warnLabel.Text = `YOU ARE LEVEL {level}  --  TURN BACK`

	showing = BANNER_HOLD + BANNER_FADE
end

local function build()
	local gui = player:WaitForChild("PlayerGui")

	screen = Instance.new("ScreenGui")
	screen.Name = "ZoneBanner"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- Under the panels, same as the waypoints: a district name over an open
	-- shop is noise.
	screen.DisplayOrder = 5
	screen.Enabled = false
	screen.Parent = gui

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.new(0.5, 0, 0.16, 0)
	holder.Size = UDim2.fromOffset(560, 96)
	holder.Parent = screen

	nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Zone"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 34
	nameLabel.TextColor3 = TEXT
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Size = UDim2.new(1, 0, 0, 40)
	nameLabel.Parent = holder

	bandLabel = Instance.new("TextLabel")
	bandLabel.Name = "Band"
	bandLabel.BackgroundTransparency = 1
	bandLabel.Font = Enum.Font.Gotham
	bandLabel.TextSize = 15
	bandLabel.TextColor3 = DIM
	bandLabel.TextStrokeTransparency = 0.5
	bandLabel.Position = UDim2.fromOffset(0, 42)
	bandLabel.Size = UDim2.new(1, 0, 0, 20)
	bandLabel.Parent = holder

	warnLabel = Instance.new("TextLabel")
	warnLabel.Name = "Warning"
	warnLabel.BackgroundTransparency = 1
	warnLabel.Font = Enum.Font.GothamBold
	warnLabel.TextSize = 16
	warnLabel.TextColor3 = DANGER
	warnLabel.TextStrokeTransparency = 0.4
	warnLabel.Position = UDim2.fromOffset(0, 66)
	warnLabel.Size = UDim2.new(1, 0, 0, 22)
	warnLabel.Visible = false
	warnLabel.Parent = holder
end

--------------------------------------------------------------------------------
-- Per-frame update
--------------------------------------------------------------------------------

local function update(dt: number)
	if showing > 0 then
		showing -= dt
		-- The last BANNER_FADE seconds are the fade; before that it is solid.
		local alpha = 1 - math.clamp(showing / BANNER_FADE, 0, 1)
		screen.Enabled = showing > 0 and not Panels.anyFullScreenOpen()
		nameLabel.TextTransparency = alpha
		nameLabel.TextStrokeTransparency = 0.4 + alpha * 0.6
		bandLabel.TextTransparency = alpha
		bandLabel.TextStrokeTransparency = 0.5 + alpha * 0.5
		warnLabel.TextTransparency = alpha
		warnLabel.TextStrokeTransparency = 0.4 + alpha * 0.6
	end

	sinceCheck += dt
	if sinceCheck < CHECK_INTERVAL then
		return
	end
	sinceCheck = 0

	local profile = state().get()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not profile or not (root and root:IsA("BasePart")) then
		return
	end

	local planetId = profile.currentPlanet
	if not Planets.exists(planetId) then
		return
	end
	-- Landing somewhere new is an entry into whatever district you land in,
	-- even if it happens to share a name with the one you left.
	if planetId ~= currentPlanet then
		currentPlanet = planetId
		currentZone = nil
	end

	local zoneId = nearestZone(planetId, root.Position, currentZone)
	if not zoneId or zoneId == currentZone then
		return
	end
	currentZone = zoneId
	announce(planetId, zoneId, profile.level)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ZoneController.init()
	build()
end

function ZoneController.start()
	RunService.RenderStepped:Connect(update)
end

return ZoneController
