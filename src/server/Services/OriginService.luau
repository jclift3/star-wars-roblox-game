--!strict
--[[
	OriginService.luau

	Records who the player decided to have been, once.

	WHY IT IS A SERVICE AND NOT A LINE IN PlayerService
	`Config/Origins.luau` has existed since 7c38b75 and every character in the
	game was `Origins.DEFAULT`, because nothing ever wrote the field. Four
	travel profiles, four home worlds and four factions were authored, tested
	by cheat code, and unreachable by playing -- this codebase's oldest failure
	mode, a complete system with no way in.

	IT IS THE ONE WRITE THAT CANNOT BE REPEATED
	Choosing sets the faction whose troops will not shoot you and the patron
	who flies you for free, and it moves you across the galaxy for nothing. A
	player who could reopen the screen would have a free jump to any of four
	worlds on demand, so `originChosen` is checked here rather than trusted
	from the client -- the two brothers play in the same room, and that is
	exactly where a re-roll gets found.

	THE RELOCATION IS FREE ON PURPOSE
	It goes through `PlayerService.travelTo` rather than `TravelService`: there
	is no fare and no cooldown for arriving at the life you started with, and
	an origin whose own home world is behind a fare you cannot pay at level 1
	would be an origin you cannot pick.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Origins = require(Shared.Config.Origins)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type PlayerProfile = Types.PlayerProfile

local OriginService = {
	name = "OriginService",
	-- After TravelService (38), whose jump this borrows, and well after
	-- DataService (1), whose profile it is the first writer of.
	priority = 39,
}

local function data()
	return ServiceLoader.get("DataService")
end

--[[
	Commits an origin. Returns false and a reason the player can be shown.

	The reasons are worth showing rather than swallowing: an unknown origin
	means the client is out of date, and "already chosen" is the honest answer
	to a second creation screen rather than a silent no-op.
]]
function OriginService.choose(player: Player, originId: string): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	if profile.originChosen then
		return false, "You have already chosen"
	end
	if not Origins.exists(originId) then
		return false, "Unknown origin"
	end

	local origin = Origins.get(originId)
	data().update(player, function(p: PlayerProfile)
		p.origin = origin.id
		p.faction = origin.faction
		p.homePlanet = origin.homePlanet
		p.originChosen = true
	end)

	if profile.currentPlanet ~= origin.homePlanet then
		local ok, reason = ServiceLoader.get("PlayerService").travelTo(player, origin.homePlanet)
		if not ok then
			-- The choice stands even if the flight did not: it is recorded and
			-- replicated already, and undoing it would leave the player facing
			-- the creation screen a second time over a respawn that failed.
			warn(`[OriginService] {player.Name} chose {origin.id} but could not reach it: {reason}`)
		end
	end

	--[[
		No toast here. There used to be one -- the origin's name, its world,
		"Success", four seconds -- and it was the whole of what a new character
		was told. From the 2026-08-17 playtest: "I still don't know what's going
		on, who I am."

		The announcement is `CreationController`'s card instead: longer, and up
		until it is dismissed. It needs nothing sent to it. The profile written
		above replicates on its own and the card is drawn off `originChosen`
		turning true, so a remote saying the same thing would be a second signal
		for one event, able to arrive without the other.
	]]
	return true, nil
end

function OriginService.init()
	Net.onServerEvent(Net.Event.ChooseOrigin, function(player: Player, originId: string)
		local ok, reason = OriginService.choose(player, originId)
		if not ok and reason then
			Net.fireClient(Net.Event.Notify, player, reason, "Error")
		end
	end, {
		-- As slow as travelling, because it usually is travelling.
		rateLimit = 1,
		validate = Net.args(Net.check.string(64)),
	})
end

return OriginService
