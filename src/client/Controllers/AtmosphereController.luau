--!strict
--[[
	AtmosphereController.luau

	Makes each planet feel like a different place.

	Every world in Planets.luau already declares its own fog, ambient light and
	day length; this is the thing that actually puts those numbers into
	Lighting. Tatooine is a bleached white haze, Hoth a cold blue one,
	Coruscant a hot orange dusk -- all from config, none of it hand-placed in
	Studio, so adding a planet needs no work here.

	Lighting is client-side, so this runs entirely on the client and reacts to
	the profile's currentPlanet changing. Arriving somewhere new is a two second
	cross-fade rather than a hard cut, which reads as the ship settling rather
	than as a glitch.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Planets = require(Shared.Config.Planets)
local ServiceLoader = require(Shared.Core.ServiceLoader)

local AtmosphereController = {
	name = "AtmosphereController",
	priority = 50,
}

local TRANSITION = TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Roblox's default sun is harsh and shadowless-looking. These are the settings
-- that stay the same everywhere; only colour and density change per planet.
local SHADOW_SOFTNESS = 0.35
local BRIGHTNESS = 2.2

local atmosphere: Atmosphere
local tint: ColorCorrectionEffect

local currentPlanet: string? = nil
local secondsPerDay = 900

-- Moonlight. Night is dimmed towards this rather than towards black, because a
-- planet you cannot see is not atmospheric, it is just broken -- and with a
-- fifteen minute day you would spend half your play time in it.
local NIGHT_TINT = Color3.fromRGB(40, 52, 82)

-- Ambient is driven every frame from the clock, so it cannot be tweened by
-- apply() as well without the two fighting. These hold where it is going.
local dayAmbient = Color3.fromRGB(120, 104, 80)
local dayOutdoor = Color3.fromRGB(160, 140, 108)
-- ...and where it is now, eased towards the target so arriving on a new world
-- still cross-fades rather than snapping.
local liveAmbient = dayAmbient
local liveOutdoor = dayOutdoor

--[[
	Density and haze per terrain type.

	Atmosphere is the one thing not in the planet config, because it is a
	rendering detail rather than a fact about the world: a swamp is thick and
	close, an ice field is thin and glaring, and that follows from the terrain
	rather than needing eight more tuned numbers.
]]
local TERRAIN_AIR: { [string]: { density: number, haze: number, glare: number } } = {
	Desert = { density = 0.36, haze = 1.8, glare = 0.35 },
	Ice = { density = 0.42, haze = 2.4, glare = 0.6 },
	Swamp = { density = 0.5, haze = 3.2, glare = 0.05 },
	Forest = { density = 0.34, haze = 1.4, glare = 0.1 },
	Volcanic = { density = 0.46, haze = 2.8, glare = 0.25 },
	Ocean = { density = 0.4, haze = 2.2, glare = 0.3 },
	Urban = { density = 0.3, haze = 1.2, glare = 0.15 },
}

local DEFAULT_AIR = { density = 0.3, haze = 1.2, glare = 0.15 }

--[[
	Takes over an effect of this class, or makes one.

	Deliberately searches by class rather than by name, because a place template
	ships its own Atmosphere and Bloom. Lighting only ever honours one
	Atmosphere, so creating a second one by name left the template's in charge
	and every planet's air was silently ignored.
]]
local function ensureEffect<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		existing.Name = name
		return existing :: any
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance :: any
end

--- 0 in full daylight, 1 in full night, ramping through dawn and dusk.
local function nightFactor(clock: number): number
	-- A crude sun altitude: positive between 6am and 6pm, peaking at noon. The
	-- 2.2 makes the world reach full brightness well before noon rather than
	-- spending the whole morning dim.
	local sun = math.sin(((clock - 6) / 12) * math.pi)
	return math.clamp(1 - sun * 2.2, 0, 1)
end

--- The night version of a daytime colour: dimmer, and pushed towards moonlight.
local function afterDark(c: Color3): Color3
	return c:Lerp(NIGHT_TINT, 0.72)
end

--- Puts a planet's declared look into Lighting, cross-fading from the old one.
local function apply(planetId: string, instant: boolean)
	if not Planets.exists(planetId) then
		-- Silence here used to mean a bad planet id looked exactly like a
		-- controller that never ran, which is a miserable thing to debug.
		warn(`[AtmosphereController] unknown planet "{planetId}"; lighting unchanged`)
		return
	end
	local planet = Planets.get(planetId)
	local air = TERRAIN_AIR[planet.terrain] or DEFAULT_AIR

	secondsPerDay = math.max(60, planet.dayLength * 3600)

	-- Handed to the clock loop rather than tweened here; see the note by the
	-- declarations above.
	dayAmbient = planet.ambientLight
	dayOutdoor = planet.outdoorAmbient
	if instant then
		liveAmbient = dayAmbient
		liveOutdoor = dayOutdoor
	end

	-- An Atmosphere object replaces Lighting's legacy fog outright, so setting
	-- FogStart/FogEnd here would do nothing. The planet's fog distance is
	-- expressed as density instead: the sooner a world wants to fade out, the
	-- thicker its air.
	local reach = math.clamp((planet.fogEnd - 400) / 2600, 0, 1)

	local atmosphereGoal = {
		Density = math.min(0.7, air.density + (1 - reach) * 0.25),
		Haze = air.haze,
		Glare = air.glare,
		Color = planet.fogColor,
		Decay = planet.skyTint,
	}
	-- The sky tint is applied as a colour grade rather than a skybox, because
	-- there are no texture assets in this project by design.
	local tintGoal = { TintColor = planet.skyTint }

	-- A zero-length tween is still a tween: it sets the properties on the next
	-- frame, which is exactly what the first application wants without needing
	-- a second code path that can drift out of step with this one.
	local info = if instant then TweenInfo.new(0) else TRANSITION

	TweenService:Create(atmosphere, info, atmosphereGoal):Play()
	TweenService:Create(tint, info, tintGoal):Play()
end

function AtmosphereController.init()
	atmosphere = ensureEffect("Atmosphere", "PlanetAtmosphere")
	tint = ensureEffect("ColorCorrectionEffect", "PlanetTint")
	local bloom: BloomEffect = ensureEffect("BloomEffect", "PlanetBloom")

	-- A Baseplate ships a DepthOfField that blurs anything past a few dozen
	-- studs. Layered under a planet's atmosphere it turns the whole world to
	-- mush, and nothing here wants it.
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end

	Lighting.Brightness = BRIGHTNESS
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = SHADOW_SOFTNESS
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ExposureCompensation = 0.1
	Lighting.ClockTime = 14

	tint.Saturation = 0.08
	tint.Contrast = 0.12
	tint.Brightness = 0

	-- Enough for neon signs, blaster bolts and lightsabers to bleed light,
	-- which is most of what makes the setting read as Star Wars at night.
	bloom.Intensity = 0.5
	bloom.Size = 20
	bloom.Threshold = 1.4
end

function AtmosphereController.start()
	local state = ServiceLoader.get("ClientState")

	local function follow(profile: any)
		if profile.currentPlanet == currentPlanet then
			return
		end
		local first = currentPlanet == nil
		currentPlanet = profile.currentPlanet
		apply(profile.currentPlanet, first)
	end

	state.changed:connect(follow)

	local existing = state.get()
	if existing then
		follow(existing)
	end

	-- Time of day. Short days are deliberate: a planet whose light never
	-- changes stops being a place after ten minutes.
	RunService.Heartbeat:Connect(function(dt: number)
		Lighting.ClockTime = (Lighting.ClockTime + dt * (24 / secondsPerDay)) % 24

		local night = nightFactor(Lighting.ClockTime)
		local targetAmbient = dayAmbient:Lerp(afterDark(dayAmbient), night)
		local targetOutdoor = dayOutdoor:Lerp(afterDark(dayOutdoor), night)

		-- Exponential ease, so this both follows the clock and cross-fades a
		-- change of planet without needing a separate tween to collide with.
		local alpha = 1 - math.exp(-dt / 0.6)
		liveAmbient = liveAmbient:Lerp(targetAmbient, alpha)
		liveOutdoor = liveOutdoor:Lerp(targetOutdoor, alpha)

		Lighting.Ambient = liveAmbient
		Lighting.OutdoorAmbient = liveOutdoor
	end)
end

return AtmosphereController
