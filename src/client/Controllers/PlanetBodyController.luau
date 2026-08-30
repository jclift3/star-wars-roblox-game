--!strict
--[[
	PlanetBodyController.luau

	Puts the other eight worlds in the sky.

	THE COMPLAINT
	*"We also have to make the planets look like planets and be farther
	apart."* -- Logan, 2026-08-30.

	Those read as two asks and they are one. The nine worlds have been
	sixteen thousand studs apart in a single Workspace since the first one
	was generated, but **nothing has ever rendered in the gap**. Distance you
	cannot see is not distance: a void with no landmarks in it is the same
	experience at four thousand studs as at forty, so the grid could be
	widened all day and the galaxy would go on feeling like one room with a
	loading screen in it. And "look like planets" is the same hole from the
	other side -- until now the only planet-shaped thing in the game was the
	cloud deck you are standing under, which exists specifically to *hide*
	the fact that a world is a flat plate.

	Draw the neighbours and both halves close at once. Coruscant hangs in
	Tatooine's orbit at the true bearing and the true angular size, small
	because it is genuinely far; fly out into the dark and it grows while the
	one behind you shrinks. That is the only way the sixteen thousand studs
	become a thing the player can feel.

	THEY ARE AT THEIR REAL ADDRESSES
	No shell, no projection, no per-frame angular arithmetic. A body is a
	ball parked on `Planets.originFor`, which is where the world actually is,
	so its bearing, its size and the rate it grows at as you approach are all
	just perspective doing its job. Occlusion comes out right for free --
	your own cloud deck is between you and it, so it hides behind weather the
	way it should -- and so does haze: `Orbit.Sky` takes atmospheric density
	to zero above the ceiling, which means the bodies are invisible from the
	ground and sharp from orbit without a single line here knowing which is
	which.

	`BODY_RADIUS` is smaller than `Planets.worldRadius`, and that is not a
	mismatch to fix. The plate you land on is a *region* of a world, the way
	every playable map in every game is; the ball is the world. You are never
	looking at both, because the body fades out as you cross into its system
	and the real ground takes over the job.

	CLIENT-ONLY, LIKE THE CLOUD AND THE SECOND SUN
	Parented to the camera, so it is never replicated, never saved, and never
	walked by anything looking for somewhere to spawn or something to shoot.
	Nothing here can be collided with, landed on or flown into. Nine worlds
	is nine balls and nine halos, built once and never moved, so the only
	per-frame work in the file is eighteen transparency writes.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Orbit = require(Shared.Config.Orbit)
local Planets = require(Shared.Config.Planets)

local PlanetBodyController = {
	name = "PlanetBodyController",
	-- After SkyDeckController, which owns the weather these hide behind.
	priority = 52,
}

--[[
	How big a world is, as a body.

	Nine hundred studs of radius is eighteen hundred of diameter, which is
	the largest round number under Roblox's 2,048-stud part limit -- and that
	limit is the reason the number is what it is rather than a taste
	decision. It puts a neighbour at `WORLD_SPACING` at about six and a half
	degrees across: thirteen times the moon, unmistakably a place rather than
	a star, and unmistakably somewhere else.
]]
local BODY_RADIUS = 900

--[[
	The atmosphere.

	A lit sphere alone reads as a ball. What says *planet* is that the glow
	carries a little way past the terminator, so the lit edge is soft and the
	dark side still has a rim on it. A slightly larger Neon shell in the
	world's own `skyTint` does that, and it is the difference between eight
	grey dots and eight worlds.
]]
local HALO_SCALE = 1.07
local HALO_TRANSPARENCY = 0.82

--[[
	Where a body stops being the planet and the ground starts.

	Inside a system the real plate, its towers and its weather are the world,
	and a translucent ball the size of the sky drawn through all of it would
	be a bug. So the body dissolves across the approach: solid out at
	`FADE_FULL`, gone by the time `Orbit.systemAt` would name it.

	The band is wide on purpose. It is crossed during the seconds a ship is
	dropping out of a jump and looking around, which is exactly when a hard
	cut would be seen.
]]
local FADE_GONE = Orbit.SYSTEM_RADIUS
local FADE_FULL = Orbit.SYSTEM_RADIUS * 1.6

type Body = { body: Part, halo: Part }

local folder: Folder? = nil
local bodies: { Body } = {}

local function ball(name: string, radius: number, at: Vector3, color: Color3, parent: Folder): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * (radius * 2)
	p.CFrame = CFrame.new(at)
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	-- An eighteen-hundred-stud shadow caster would black out a hemisphere.
	p.CastShadow = false
	p.Locked = true
	p.Parent = parent
	return p
end

local function rebuild()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	if folder then
		folder:Destroy()
	end
	table.clear(bodies)

	local f = Instance.new("Folder")
	f.Name = "PlanetBodies"
	f.Parent = camera
	folder = f

	for _, id in Planets.ids() do
		local planet = Planets.get(id)
		local at = Planets.originFor(id)

		-- Its own soil, seen through its own air. Hoth reads white, Kashyyyk
		-- green and Coruscant grey without a second colour being authored.
		local body = ball(id, BODY_RADIUS, at, planet.groundColor:Lerp(planet.fogColor, 0.25), f)
		-- Not Neon: the whole point is that the sun lights one side of it and
		-- the terminator curves. A self-lit ball has no shape in it at all.
		body.Material = Enum.Material.SmoothPlastic

		local halo = ball(id .. "Air", BODY_RADIUS * HALO_SCALE, at, planet.skyTint, f)
		halo.Material = Enum.Material.Neon

		table.insert(bodies, { body = body, halo = halo })
	end
end

function PlanetBodyController.start()
	rebuild()

	RunService.Heartbeat:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		-- Respawning replaces the camera these hang off, taking them with it.
		if not folder or folder.Parent ~= camera then
			rebuild()
		end

		local eye = camera.CFrame.Position
		for _, pair in bodies do
			local away = (pair.body.Position - eye).Magnitude
			local show = math.clamp((away - FADE_GONE) / (FADE_FULL - FADE_GONE), 0, 1)
			pair.body.Transparency = 1 - show
			pair.halo.Transparency = 1 - show * (1 - HALO_TRANSPARENCY)
		end
	end)
end

return PlanetBodyController
