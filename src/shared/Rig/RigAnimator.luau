--!strict
--[[
	RigAnimator.luau

	Drives walk/run/idle/jump/fall animations for NPC rigs.

	Players get this for free from Roblox's built-in "Animate" LocalScript, but
	that script only runs for real players. NPCs need their own state machine, and
	without one they glide around in a T-pose -- which is exactly what the old
	version of this project did.

	Uses Roblox's stock R15 animation assets, so there is nothing to upload.
]]

local ANIMATION_IDS: { [string]: string } = {
	Idle = "rbxassetid://507766666",
	IdleAlt = "rbxassetid://507766951",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
	Jump = "rbxassetid://507765000",
	Fall = "rbxassetid://507767968",
	Climb = "rbxassetid://507765644",
}

-- Below this speed the NPC is considered stationary.
local IDLE_THRESHOLD = 0.6
-- Above this speed we switch from the walk cycle to the run cycle.
local RUN_THRESHOLD = 11

local RigAnimator = {}
RigAnimator.__index = RigAnimator

export type RigAnimator = typeof(setmetatable(
	{} :: {
		humanoid: Humanoid,
		animator: Animator,
		tracks: { [string]: AnimationTrack },
		current: string?,
		connections: { RBXScriptConnection },
		destroyed: boolean,
	},
	RigAnimator
))

local function loadTrack(animator: Animator, id: string): AnimationTrack
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local track = animator:LoadAnimation(anim)
	anim:Destroy()
	return track
end

function RigAnimator.new(rig: Model): RigAnimator?
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local existing = humanoid:FindFirstChildOfClass("Animator")
	local animator: Animator
	if existing then
		animator = existing
	else
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local self = setmetatable({
		humanoid = humanoid,
		animator = animator,
		tracks = {} :: { [string]: AnimationTrack },
		current = nil :: string?,
		connections = {} :: { RBXScriptConnection },
		destroyed = false,
	}, RigAnimator)

	-- Loading can fail if the asset is unavailable; a silent NPC is far better
	-- than a hard error that kills the whole spawn loop.
	for name, id in ANIMATION_IDS do
		local ok, track = pcall(loadTrack, self.animator, id)
		if ok then
			self.tracks[name] = track
		end
	end

	for _, name in { "Idle", "IdleAlt", "Walk", "Run", "Climb" } do
		local t = self.tracks[name]
		if t then
			t.Looped = true
			t.Priority = Enum.AnimationPriority.Core
		end
	end
	for _, name in { "Jump", "Fall" } do
		local t = self.tracks[name]
		if t then
			t.Looped = false
			t.Priority = Enum.AnimationPriority.Movement
		end
	end

	self:_bind()
	self:play("Idle")
	return self
end

function RigAnimator.play(self: RigAnimator, name: string, speed: number?)
	if self.destroyed or self.current == name then
		if speed and self.current == name then
			local t = self.tracks[name]
			if t then
				t:AdjustSpeed(speed)
			end
		end
		return
	end

	local nextTrack = self.tracks[name]
	if not nextTrack then
		return
	end

	local prev = self.current and self.tracks[self.current]
	if prev then
		prev:Stop(0.15)
	end

	nextTrack:Play(0.15)
	if speed then
		nextTrack:AdjustSpeed(speed)
	end
	self.current = name
end

function RigAnimator._bind(self: RigAnimator)
	local humanoid = self.humanoid

	table.insert(
		self.connections,
		humanoid.Running:Connect(function(speed: number)
			if self.destroyed or humanoid.Health <= 0 then
				return
			end
			if speed < IDLE_THRESHOLD then
				self:play("Idle")
			elseif speed < RUN_THRESHOLD then
				-- Scale playback so the feet roughly match ground speed.
				self:play("Walk", speed / 8)
			else
				self:play("Run", speed / 14)
			end
		end)
	)

	table.insert(
		self.connections,
		humanoid.Jumping:Connect(function()
			if not self.destroyed then
				self:play("Jump")
			end
		end)
	)

	table.insert(
		self.connections,
		humanoid.FreeFalling:Connect(function(active: boolean)
			if not self.destroyed and active then
				self:play("Fall")
			end
		end)
	)

	table.insert(
		self.connections,
		humanoid.Climbing:Connect(function(speed: number)
			if not self.destroyed and speed > IDLE_THRESHOLD then
				self:play("Climb", speed / 5)
			end
		end)
	)

	table.insert(
		self.connections,
		humanoid.Died:Connect(function()
			self:destroy()
		end)
	)
end

function RigAnimator.destroy(self: RigAnimator)
	if self.destroyed then
		return
	end
	self.destroyed = true
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
	for _, t in self.tracks do
		t:Stop(0.1)
	end
	table.clear(self.tracks)
	self.current = nil
end

return RigAnimator
