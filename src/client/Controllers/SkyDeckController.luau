--!strict
--[[
	SkyDeckController.luau

	Puts weather between the ground and space.

	WHAT IT IS ACTUALLY FOR
	Not decoration, though it works as some. A world in this game is a plate:
	`Planets.groundRadius` is around 1,300 studs and the flight ceiling is 900
	studs up, so a starship reaching orbit is two-thirds of a plate-radius
	above **a flat disc with a hard edge, floating in nothing**. That is the
	one thing that decides whether space feels like arriving somewhere or like
	finding the end of the map, and no starfield fixes it -- you would be
	looking straight down at the seam.

	A layer of cloud a little under the ceiling hides the plate and its edge
	completely, and then does three more things for free. Crossing the ceiling
	stops being a state change and becomes a physical event: you punch up
	through weather and pop out on top of it. What is left below reads as *the
	planet*, which a disc never will. And every world looks better from the
	ground, which was the other complaint in the same playtest.

	CLIENT-ONLY, LIKE THE TRAFFIC AND THE SECOND SUN
	Parented to the camera, so it is never replicated, never saved and never
	walked by anything looking for somewhere to spawn or something to shoot.
	Seeded off the planet id, so two brothers in one room are under one sky.
	Nothing here can be collided with, landed on or flown into -- a ship
	passes straight through, which is what cloud does.

	`Terrain.Clouds` would have been fewer lines and was rejected: Roblox
	renders it at a fixed altitude that is not a settable property, so it
	cannot be put at *our* ceiling, and a cloud layer at the wrong height is
	worse than no cloud layer.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Orbit = require(Shared.Config.Orbit)
local Planets = require(Shared.Config.Planets)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local SkyDeckController = {
	name = "SkyDeckController",
	-- After AtmosphereController, which owns the fog these are seen through.
	priority = 51,
}

--[[
	One cloud is a flattened disc, and a deck is a hundred of them overlapping.

	A `Ball` part cannot be flattened -- Roblox renders it as a sphere of the
	smallest axis whatever the Size says -- so the puff is a `Cylinder` laid on
	its side. Overlapped at these transparencies the edges disappear into each
	other and the result reads as a mass rather than as parts, which is the
	whole trick and the reason the count matters more than the shape.
]]
local MIN_DIAMETER = 420
local MAX_DIAMETER = 980

--- Overlap factor. One is bare coverage and looks like a plate of coins.
local CROWDING = 1.35

--- Enough to be a deck, few enough that nine worlds' worth is not a budget.
local MIN_PUFFS = 24
local MAX_PUFFS = 240

local folder: Folder? = nil
local currentPlanet: string? = nil

--[[
	A stable seed from a planet id.

	Only has to agree with itself across clients, never with the server's
	world seed -- the same five lines and the same reason as
	`SkyTrafficController`. Two players on Hoth are under one overcast;
	Hoth and Dantooine do not get the same one.
]]
local function seedFrom(id: string): number
	local seed = 7
	for i = 1, #id do
		seed = (seed * 31 + string.byte(id, i)) % 2147483647
	end
	return seed
end

--- Where the cloud lives: under the camera, not in Workspace.
local function container(): Folder?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local existing = folder
	if existing and existing.Parent == camera then
		return existing
	end
	if existing then
		-- The camera is replaced on respawn, taking its children with it.
		existing:Destroy()
	end

	local f = Instance.new("Folder")
	f.Name = "SkyDeck"
	f.Parent = camera
	folder = f
	return f
end

local function clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

--- Tears down whatever was overhead and lays out this planet's weather.
local function rebuild(planetId: string)
	clear()

	local deck = Orbit.deckFor(planetId)
	if not deck then
		-- A vertical city has no plate to hide and towers standing through
		-- the altitude this would occupy. Orbit.luau decides; see it there.
		return
	end

	local parent = container()
	if not parent then
		return
	end

	local origin = Planets.originFor(planetId)
	local rng = Random.new(seedFrom(planetId))

	--[[
		How many discs it takes to cover a disc.

		Area over area, times the cover the terrain asked for, times a crowding
		factor -- rather than a tuned count, because `spread` is derived from
		the planet's own size and a fixed number would leave the big worlds
		showing their edges and the small ones paying for sky nobody sees.
	]]
	local average = (MIN_DIAMETER + MAX_DIAMETER) * 0.5
	local count =
		math.clamp(math.floor((deck.spread * 2 / average) ^ 2 * deck.cover * CROWDING), MIN_PUFFS, MAX_PUFFS)

	for _ = 1, count do
		-- Square-rooted, so the points land evenly over the area instead of
		-- piling into the middle and leaving the rim -- the one part of the
		-- sky that has to be covered -- thin.
		local distance = deck.spread * math.sqrt(rng:NextNumber())
		local angle = rng:NextNumber(0, math.pi * 2)
		local diameter = rng:NextNumber(MIN_DIAMETER, MAX_DIAMETER)

		local puff = Instance.new("Part")
		puff.Name = "Cloud"
		puff.Shape = Enum.PartType.Cylinder
		-- A cylinder's length is its X axis, so the disc is laid flat by
		-- turning it a quarter turn about Z.
		puff.Size = Vector3.new(rng:NextNumber(deck.thickness * 0.4, deck.thickness), diameter, diameter)
		puff.CFrame = CFrame.new(
			origin.X + math.cos(angle) * distance,
			deck.altitude + rng:NextNumber(-deck.thickness, deck.thickness) * 0.5,
			origin.Z + math.sin(angle) * distance
		) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.pi * 0.5)
		puff.Color = deck.color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.14))
		puff.Transparency = deck.transparency + rng:NextNumber(0, 0.18)
		puff.Material = Enum.Material.SmoothPlastic
		puff.Anchored = true
		puff.CanCollide = false
		puff.CanQuery = false
		puff.CanTouch = false
		-- A hundred shadow casters at 800 studs would stripe the whole world,
		-- and the planet's own ambient already carries the overcast.
		puff.CastShadow = false
		puff.Locked = true
		puff.Parent = parent
	end
end

function SkyDeckController.start()
	local state = ServiceLoader.get("ClientState")

	local function follow(profile: any)
		if profile.currentPlanet == currentPlanet then
			return
		end
		currentPlanet = profile.currentPlanet
		rebuild(profile.currentPlanet)
	end

	state.changed:connect(follow)

	local existing = state.get()
	if existing then
		follow(existing)
	end

	-- The deck itself never moves, so there is no per-frame work here. This
	-- watches for the one thing that takes it away: respawning replaces the
	-- camera these are parented to, and the sky would silently vanish the
	-- first time the player died.
	RunService.Heartbeat:Connect(function()
		local camera = Workspace.CurrentCamera
		local planetId = currentPlanet
		if folder and planetId and camera and folder.Parent ~= camera then
			rebuild(planetId)
		end
	end)
end

return SkyDeckController
