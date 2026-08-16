--!strict
--[[
	DevService.luau

	Cheat codes, so the game can be looked at without being played first.

	WHY THIS EXISTS
	Most of what has been built is behind a level gate or a price tag, which is
	correct for a player and useless for an author. Seeing whether Hoth reads as
	cold currently costs about four hours of Tatooine. This is the skeleton key.

	WHO CAN USE IT
	Studio, or the account that owns the place. Nobody else, ever -- a code
	that hands out 10,000 credits is an economy with a hole in it the moment a
	stranger learns the word. The gate is checked per message rather than once
	at join, because it is one comparison and the failure mode of caching it
	wrongly is the entire problem.

	THE ORIGIN CODES ARE THE POINT
	`thereisnocow` is the convenient one, but `iamacolyte` and friends are the
	ones that actually test something. Until the creation screen exists every
	character is a Scoundrel, which means the four travel profiles -- the whole
	reason origins were built -- cannot be seen at all. These make them visible.
	They are derived from `Origins.ids()`, so a fifth origin gets a code for
	free and a renamed one cannot leave a dead code behind.

	HOW YOU ENTER ONE
	Type it in the normal Roblox chat. `Player.Chatted` still fires server-side
	under TextChatService, and using it means this feature needs no client code,
	no remote and no UI. The message stays visible in the chat window -- there
	is no server-side way to unsend it -- which does not matter for a tool only
	its author can use.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Origins = require(Shared.Config.Origins)
local Progression = require(Shared.Config.Progression)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type PlayerProfile = Types.PlayerProfile

local DevService = {
	name = "DevService",
	-- Last. It only listens, and everything it calls belongs to someone else.
	priority = 90,
}

--- The level `thereisnocow` lifts you to: past every world's minLevel - 4 grace
--- except the Core and the deep Outer Rim, which is the point of the code.
local BOOST_LEVEL = 12
local BOOST_CREDITS = 10000

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

local function tell(player: Player, message: string, kind: string?)
	Net.fireClient(Net.Event.Notify, player, message, kind or "Reward")
end

--------------------------------------------------------------------------------
-- Who is allowed
--------------------------------------------------------------------------------

--[[
	True in Studio, true for the account that owns the place, false for everyone.

	A group-owned place reports the *group* id as `game.CreatorId` and so never
	matches a UserId -- deliberately not handled. Every API for asking "does this
	player own that group" is deprecated, and if this place ever moves to a
	group the codes still work in Studio, which is where they are used anyway.
]]
local function mayCheat(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

--------------------------------------------------------------------------------
-- The codes
--------------------------------------------------------------------------------

--[[
	Raises the player to at least `level`, through the normal XP path.

	Setting `profile.level` directly would skip the skill points and the
	level-up toast, leaving a level 12 character with one skill point and no
	idea it happened. Awarding the difference in cumulative XP lets
	`awardXp` do all of it.
]]
local function liftToLevel(player: Player, level: number)
	local profile = data().get(player)
	if not profile then
		return
	end
	local target = Progression.totalXpForLevel(math.min(level, Progression.MAX_LEVEL))
	local current = Progression.totalXpForLevel(profile.level) + profile.xp
	if target > current then
		progression().awardXp(player, target - current)
	end
end

local codes: { [string]: (Player) -> () } = {}

codes.thereisnocow = function(player: Player)
	-- Raw, because the Scavenger multiplier turning 10,000 into 11,500 would
	-- make the one number in this file that should be predictable unpredictable.
	progression().awardCredits(player, BOOST_CREDITS, true)
	liftToLevel(player, BOOST_LEVEL)
	tell(player, `The cow says nothing. +{BOOST_CREDITS} cr, level {BOOST_LEVEL}.`)
end

-- One per origin: `iamacolyte`, `iamconscript`, `iamscoundrel`, `iamscrapper`.
for _, id in Origins.ids() do
	codes[`iam{string.lower(id)}`] = function(player: Player)
		data().update(player, function(profile: PlayerProfile)
			profile.origin = id
			-- Otherwise the old origin's cooldown is still running against the
			-- new one, which reads as the code having done nothing.
			profile.lastTravelAt = 0
		end)
		local def = Origins.get(id)
		tell(player, `You are a {def.displayName} now. {def.travelBlurb}`)
	end
end

--------------------------------------------------------------------------------
-- Entry
--------------------------------------------------------------------------------

--- Chat text reduced to the letters, so casing and stray punctuation cannot
--- make a working code look broken.
local function normalise(message: string): string
	return (string.gsub(string.lower(message), "[^%a]", ""))
end

function DevService.start()
	local function listen(player: Player)
		player.Chatted:Connect(function(message: string)
			local code = codes[normalise(message)]
			if not code then
				return
			end
			if not mayCheat(player) then
				-- Deliberately silent. Telling a stranger they typed a real
				-- code and were refused is an invitation to keep guessing.
				return
			end
			code(player)
		end)
	end

	for _, player in Players:GetPlayers() do
		listen(player)
	end
	Players.PlayerAdded:Connect(listen)
end

return DevService
