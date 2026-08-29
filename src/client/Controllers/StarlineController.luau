--!strict
--[[
	StarlineController.luau

	Draws the streaks that say a hyperspace crossing is happening.

	WHY A CROSSING NEEDS ANYTHING DRAWN AT ALL
	The jump is real: the hull physically covers twelve thousand studs of the
	same Workspace at about fifteen hundred studs a second. That is the
	honest implementation and it looks like nothing, because there is nothing
	out there to move past. Speed you cannot see is not speed -- it is a
	twenty-second pause with the controls taken away, which is the worst
	thing a journey could be.

	These lines are the reference frame. They are the only thing between the
	worlds that the eye can measure the ship against.

	CLIENT-ONLY, PARENTED TO THE CAMERA
	The same trick `SkyDeckController` and `SkyTrafficController` run on:
	nothing here is replicated, saved, collided with, shot, landed on or
	walked by anything looking for a spawn point. `CurrentCamera` is also the
	one parent Roblox clears on respawn, which is exactly the lifetime this
	wants.

	And it is a trick this project trusts for **shapes and not for people**
	(2026-08-29, the ghost crowd). A streak at distance genuinely is a lit
	line; there is no eye anywhere that reads it as anything more specific.

	THE FIELD IS A BOX THAT WRAPS, NOT A STREAM THAT SPAWNS
	Every line is created once when the jump starts, and each frame that
	drifts out of a box around the camera is folded back in on the opposite
	face. No allocation while flying, a constant part count, and no way for a
	long crossing to cost more than a short one.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StarlineController = {
	name = "StarlineController",
	-- After AtmosphereController (50) and the cloud deck (51): these are
	-- drawn against the black sky both of those decide the look of.
	priority = 52,
}

--[[
	How many lines, and how big the box they live in is.

	The count is high because the effect is a *field* -- a dozen streaks read
	as a dozen objects and 220 read as motion. They are cheap: one anchored,
	unqueryable, shadowless neon part each, all inside a hundred-stud box, so
	the whole field is smaller than a single building.
]]
local COUNT = 220
local FIELD = 90

--- Length of a streak, before it is stretched by the ship's speed.
local MIN_LENGTH = 8
local MAX_LENGTH = 26
local THICKNESS = 0.22

--[[
	How much longer a streak gets at full speed than at a standstill.

	Driven off how far the drive has spooled up rather than being a constant,
	so engaging and dropping out are both visibly a *ramp* -- which is the
	only cue the player gets that anything is spooling at all, the hull
	having no instruments.
]]
local MAX_STRETCH = 7

--[[
	How fast the field slides past, on top of the ship's own motion.

	Purely apparent. The lines are drifting through a box that is stapled to
	the camera, so this number is the whole of the sensation and none of the
	physics -- the hull's real speed is `Orbit.jumpSpeedFor` and is decided a
	long way from here.
]]
local DRIFT = 900

local folder: Folder? = nil
local streaks: { BasePart } = {}
--- Each streak's unstretched length, so the stretch is applied to the part's
--- own size rather than compounding onto whatever it was last frame.
local lengths: { number } = {}
local streaking = false
local stretch = 0

local rng = Random.new()

local function teardown()
	if folder then
		folder:Destroy()
	end
	folder = nil
	table.clear(streaks)
	table.clear(lengths)
end

--- A point somewhere in the box, in the camera's own frame of reference.
local function scatter(): Vector3
	return Vector3.new(
		rng:NextNumber(-FIELD, FIELD),
		rng:NextNumber(-FIELD, FIELD),
		rng:NextNumber(-FIELD, FIELD)
	)
end

local function build(): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end

	teardown()

	local created = Instance.new("Folder")
	created.Name = "Starlines"
	created.Parent = camera
	folder = created

	for _ = 1, COUNT do
		local length = rng:NextNumber(MIN_LENGTH, MAX_LENGTH)
		local line = Instance.new("Part")
		line.Name = "Streak"
		line.Size = Vector3.new(THICKNESS, THICKNESS, length)
		line.Position = scatter()
		line.Color = Color3.fromRGB(198, 216, 255)
		line.Material = Enum.Material.Neon
		-- Varied so the field has depth rather than reading as one sheet of
		-- lines all the same distance away.
		line.Transparency = rng:NextNumber(0.15, 0.6)
		line.Anchored = true
		line.CanCollide = false
		line.CanQuery = false
		line.CanTouch = false
		line.CastShadow = false
		line.Locked = true
		line.Parent = created
		table.insert(streaks, line)
		table.insert(lengths, length)
	end
	return true
end

--[[
	Turns the field on or off.

	`fraction` is how far the drive has spooled up, 0..1, and it is the
	caller's job because the caller is the flight loop that owns the speed.
	Passing it in rather than reading the hull from here keeps this file
	knowing nothing about ships.
]]
function StarlineController.setStreaking(on: boolean, fraction: number?)
	stretch = math.clamp(fraction or 1, 0, 1)
	if on == streaking then
		return
	end
	streaking = on
	if on then
		build()
	else
		teardown()
	end
end

function StarlineController.start()
	RunService.RenderStepped:Connect(function(dt: number)
		if not streaking then
			return
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		-- Respawning replaces the camera and takes the field with it, which
		-- would otherwise leave a crossing silently blank for the rest of
		-- its twenty seconds.
		if not folder or folder.Parent ~= camera then
			if not build() then
				return
			end
		end

		local frame = camera.CFrame
		local slide = DRIFT * stretch * dt
		local pull = 1 + (MAX_STRETCH - 1) * stretch

		for index, line in streaks do
			--[[
				Held in the camera's frame throughout: read where the streak
				is relative to the camera, slide it backwards along the axis
				the camera is looking down, wrap it, and write it out again.

				Working in world space instead would mean folding the ship's
				heading in by hand -- and the heading is locked to the lane
				during a jump, so the two would agree right up until the
				player aborted, which is precisely when they must not.
			]]
			local offset = frame:PointToObjectSpace(line.Position)
			local z = offset.Z + slide
			if z > FIELD then
				-- Out through the back: reappear at the far face, somewhere
				-- new across the other two axes. Re-using the same X and Y
				-- would make the field read as a set of fixed rails.
				local fresh = scatter()
				offset = Vector3.new(fresh.X, fresh.Y, -FIELD)
			else
				offset = Vector3.new(offset.X, offset.Y, z)
			end

			-- Aligned with the camera, not merely positioned in front of it:
			-- a streak is only a streak while it points the way you are
			-- going.
			line.CFrame = frame * CFrame.new(offset)
			line.Size = Vector3.new(THICKNESS, THICKNESS, lengths[index] * pull)
		end
	end)
end

return StarlineController
