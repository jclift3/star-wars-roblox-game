--!strict
--[[
	TerminalService.luau

	Stands a locked console at every place that would keep one, and opens it
	for the people who can.

	WHY THIS EXISTS
	`Slicer` is five ranks deep in the Engineering tree and has never done
	anything. It was marked `unimplemented`, which kept it honest but left the
	skill trees with the same hole ROADMAP 4.3 target 5 names: every live stat
	in the game makes a fight shorter, and none of them changes what is in
	front of you. A tier 3 lock at the spaceport is the first thing in this
	world that a Scrapper can deal with and a Sith Acolyte simply cannot.

	THE REFUSAL IS THE ADVERTISEMENT
	A console you cannot open still says its tier on the tag above it and
	still tells you, by name, which rank of which skill would have opened it.
	That is deliberate and it is the lesson from the 2026-08-17 report: a
	system the player is never told about does not exist. The locked door is
	how `Slicer` introduces itself to somebody who has not bought it.

	CRACKED IS A PROPERTY OF THE WORLD
	A sliced terminal goes dark for everyone and comes back after
	`Terminals.COOLDOWN`, exactly the bargain `PickupService` makes. The two
	brothers play in one room, so a console one of them has opened has to read
	as open to the other; and per-player bookkeeping would mean a set of
	opened terminal ids living in a profile forever.

	NOTHING IS PLACED BY HAND
	`Config/Terminals.luau` derives the whole list from the points of interest
	and their level bands. This service only builds what that says exists.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Affixes = require(Shared.Config.Affixes)
local Loot = require(Shared.Config.Loot)
local Missions = require(Shared.Config.Missions)
local Progression = require(Shared.Config.Progression)
local Terminals = require(Shared.Config.Terminals)
local Inventory = require(Shared.Core.Inventory)
local Net = require(Shared.Core.Net)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Types = require(Shared.Types)

type PlayerProfile = Types.PlayerProfile

local TerminalService = {
	name = "TerminalService",
	-- After MissionService (50), which every crack reports to, and after
	-- PickupService (55) for no reason but keeping the world-dressing
	-- services in one block.
	priority = 57,
}

-- How far off the tag is legible. Matches PickupService's, so a console and a
-- crate at the same landmark name themselves from the same distance.
local TAG_DISTANCE = 140
-- Reach of the prompt. Tighter than a pickup's: this is a thing you walk up
-- and stand at, not a thing you find in rubble.
local PROMPT_DISTANCE = 12
-- Slicing takes a moment. Long enough to read as work rather than a button.
local HOLD = 1.4
-- Planets are only checked for missing consoles this often; the answer
-- changes when somebody travels, not between frames.
local SWEEP_INTERVAL = 4

--[[
	How far out from the marker's centre a console stands, and the widest
	marker that is allowed to push it.

	A landmark's marker is as wide as the thing standing on it, so a console
	dropped at the centre is inside the building. Ringing it at the full skirt
	is right for a crate and wrong here: a `drawn` point of interest -- an
	academy, a temple grounds -- has a marker the size of the whole district,
	and its console would end up on the district's outer boundary, which is a
	field. Capping the skirt puts that one near the middle of its own grounds
	and leaves an ordinary building's console just outside the wall.
]]
local STAND_OFF = 10
local MAX_SKIRT = 40

--[[
	A console in the world.

	`spentAt` is the clock reading when somebody cracked it, or nil while it
	is armed. Kept next to the parts rather than as an attribute so the
	rearm timer and the prompt cannot disagree about which state it is in.
]]
type Live = {
	def: Terminals.TerminalDef,
	screen: BasePart,
	label: TextLabel,
	prompt: ProximityPrompt,
	spentAt: number?,
}

-- Keyed by `planet|poi`, which is the only id a terminal has.
local live: { [string]: Live } = {}
local lootRng = Random.new()

local ARMED = Color3.fromRGB(90, 220, 235)
local CRACKED = Color3.fromRGB(150, 40, 40)

local function data()
	return ServiceLoader.get("DataService")
end

local function missions()
	return ServiceLoader.get("MissionService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

local function keyOf(def: Terminals.TerminalDef): string
	return `{def.planet}|{def.poi}`
end

--------------------------------------------------------------------------------
-- World model
--------------------------------------------------------------------------------

local function folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function poiPart(planetId: string, poiId: string): BasePart?
	local root = Workspace:FindFirstChild("POI")
	local planetFolder = root and root:FindFirstChild(planetId)
	local part = planetFolder and planetFolder:FindFirstChild(poiId)
	return if part and part:IsA("BasePart") then part else nil
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

--- Drops `position` onto whatever solid ground is under it.
local function onGround(position: Vector3, ignore: Instance): Vector3
	groundParams.FilterDescendantsInstances = { ignore }
	local hit = Workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -300, 0), groundParams)
	return if hit then hit.Position else position
end

--- What the tag over a console reads, in whichever state it is in.
local function caption(def: Terminals.TerminalDef, spent: boolean): string
	return if spent then "CRACKED" else `{def.displayName}  --  TIER {def.tier}`
end

local function build(def: Terminals.TerminalDef, parent: Folder, anchor: BasePart): Live
	--[[
		Always the same spot for the same place, on every server and for both
		players: the angle is derived from the id rather than rolled, so
		"the console round the back of the depot" stays a sentence one brother
		can say to the other.
	]]
	local angle = (#def.poi * 0.7 + string.byte(def.poi, 1)) % (math.pi * 2)
	local skirt = math.min(math.max(anchor.Size.X, anchor.Size.Z) * 0.5, MAX_SKIRT)
	local reach = skirt + STAND_OFF
	local spot = anchor.Position + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
	local ground = onGround(spot, parent)

	local model = Instance.new("Model")
	model.Name = def.poi

	local pedestal = Instance.new("Part")
	pedestal.Name = "Pedestal"
	pedestal.Anchored = true
	pedestal.Size = Vector3.new(3.2, 4.4, 1.4)
	pedestal.Color = Color3.fromRGB(48, 52, 58)
	pedestal.Material = Enum.Material.DiamondPlate
	pedestal.TopSurface = Enum.SurfaceType.Smooth
	pedestal.BottomSurface = Enum.SurfaceType.Smooth
	-- Turned to face back at the landmark, so the lit face is the one you see
	-- walking out to it rather than the blank sheet metal behind.
	pedestal.CFrame = CFrame.new(ground + Vector3.new(0, 2.2, 0), anchor.Position + Vector3.new(0, 2.2, 0))
	pedestal.Parent = model

	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Anchored = true
	screen.CanCollide = false
	screen.Size = Vector3.new(2.4, 1.6, 0.2)
	screen.Color = ARMED
	screen.Material = Enum.Material.Neon
	-- Tilted back like a lectern, and stood proud of the pedestal's face.
	screen.CFrame = pedestal.CFrame * CFrame.new(0, 1.3, -0.75) * CFrame.Angles(math.rad(-25), 0, 0)
	screen.Parent = model

	local light = Instance.new("PointLight")
	light.Color = ARMED
	light.Brightness = 1.4
	light.Range = 14
	light.Parent = screen

	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.AlwaysOnTop = true
	tag.Size = UDim2.fromOffset(230, 18)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	tag.MaxDistance = TAG_DISTANCE
	tag.Parent = screen

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = ARMED
	label.TextStrokeTransparency = 0.4
	label.Text = caption(def, false)
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = tag

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Slice"
	prompt.ObjectText = def.displayName
	prompt.HoldDuration = HOLD
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestal

	model.PrimaryPart = pedestal
	model.Parent = parent

	local entry: Live = { def = def, screen = screen, label = label, prompt = prompt, spentAt = nil }
	prompt.Triggered:Connect(function(player: Player)
		TerminalService.slice(player, entry)
	end)
	return entry
end

--- Repaints a console and turns its prompt on or off.
local function setSpent(entry: Live, spent: boolean)
	local colour = if spent then CRACKED else ARMED
	entry.screen.Color = colour
	entry.label.TextColor3 = colour
	entry.label.Text = caption(entry.def, spent)
	local light = entry.screen:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = colour
	end
	entry.prompt.Enabled = not spent
	entry.spentAt = if spent then os.clock() else nil
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------

--[[
	Makes sure every console this planet should have is standing.

	Idempotent, like `PickupService.ensure`: it is both what seeds a fresh
	world and what the sweep calls every few seconds thereafter.
]]
local function ensure(planetId: string)
	local parent = folder(planetId, folder("Terminals", Workspace))
	for _, def in Terminals.forPlanet(planetId) do
		local key = keyOf(def)
		local existing = live[key]
		if existing and existing.prompt.Parent then
			continue
		end
		local anchor = poiPart(planetId, def.poi)
		if not anchor then
			-- The planet has not been built yet. WorldService builds on
			-- demand; the next sweep will find it.
			continue
		end
		live[key] = build(def, parent, anchor)
	end
end

--------------------------------------------------------------------------------
-- Slicing
--------------------------------------------------------------------------------

--[[
	Opens a console, or explains what would have.

	The refusal is a full sentence naming the rank, not "you cannot do that".
	Two thirds of the value of this whole system is in that line: it is where
	a player who has never opened the skill tree finds out that the skill tree
	decides what is in the world.
]]
function TerminalService.slice(player: Player, entry: Live)
	if entry.spentAt then
		return
	end
	local profile = data().get(player)
	if not profile then
		return
	end

	local def = entry.def
	local stats = progression().getStats(player)
	local tier = math.floor(stats.SliceTier or 0)
	if tier < def.tier then
		Net.fireClient(
			Net.Event.Notify,
			player,
			`Tier {def.tier} lock. Slicer rank {def.tier} would open this; you have {tier}.`,
			"Error"
		)
		return
	end

	setSpent(entry, true)

	local credits = progression().awardCredits(player, Terminals.creditsFor(def))
	progression().awardXp(player, Terminals.xpFor(def))
	Net.fireClient(Net.Event.Notify, player, `Sliced {def.displayName}  --  {credits} credits`, "Reward")

	--[[
		Sometimes there is something in it, on exactly the odds a kill has.

		Reusing `Loot.rollDrop` rather than inventing a terminal drop table is
		the point: one tuned number for "how often does the game hand you an
		item", and a console on a ten-minute timer is strictly worse than
		fighting the things standing around it. A better payout here would
		turn slicing into the farm and access into the side effect.
	]]
	local drop = Loot.rollDrop(lootRng, def.level)
	if drop then
		local taken = false
		data().update(player, function(p: PlayerProfile)
			taken = Inventory.add(p.inventory, drop.id, 1, drop.rolls) ~= nil
		end)
		if taken then
			local rarity = Affixes.rarityOf(drop.rolls)
			Net.fireClient(Net.Event.Notify, player, `{rarity.name}: {Loot.nameOf(drop)}`, rarity.name)
		else
			Net.fireClient(Net.Event.Notify, player, `Bag full -- left {Loot.nameOf(drop)} behind`, "Error")
		end
	end

	-- The terminal's id is its point of interest, which is what a `Slice`
	-- objective names -- so this needs no translation table and no new case
	-- in MissionService.
	missions().report(player, Missions.Objective.Slice, def.poi, 1)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function TerminalService.init()
	for _, problem in Terminals.validate(Progression.nodes.Slicer.maxRank) do
		warn(`[TerminalService] terminal config: {problem}`)
	end
end

function TerminalService.start()
	local accumulator = 0

	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < SWEEP_INTERVAL then
			return
		end
		accumulator = 0

		local now = os.clock()
		for _, entry in live do
			local spentAt = entry.spentAt
			if spentAt and now - spentAt >= Terminals.COOLDOWN then
				setSpent(entry, false)
			end
		end

		local planets: { [string]: boolean } = {}
		for _, player in Players:GetPlayers() do
			local profile = data().get(player)
			if profile then
				planets[profile.currentPlanet] = true
			end
		end
		for planetId in planets do
			local ok, err = pcall(ensure :: any, planetId)
			if not ok then
				warn(`[TerminalService] failed to place terminals on "{planetId}": {err}`)
			end
		end
	end)
end

return TerminalService
