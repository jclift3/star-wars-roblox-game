--!strict
--[[
	SecretService.luau

	Decides whether a character has been talked out of something, and pays for
	it. The deterministic half of LIVING-NPCS.md, built before the half that
	generates text.

	THE ENTIRE SECURITY ARGUMENT IS THAT THIS FILE IS BORING
	`raise` is handed a speaker, a word, and a context the *server* built out
	of the player's own profile. It looks the word up in a table nobody outside
	this machine can edit, runs the same `Dialogue.meets` every conversation
	line runs, and pays out. Nothing it reads came from the client, and when
	Phase 5 arrives nothing it reads will have come from a language model
	either -- the model gets to pick the word, and that is all it gets.

	So the worst a jailbroken character can ever do is say something it should
	not have. It cannot open the drawer, because the drawer was never listening
	to it. That property is worth more than any amount of prompt hardening, and
	it only survives if the check stays here and stays dull.

	WHY IT PAYS ONCE AND ANSWERS FOREVER
	The reward is gated on `SecretDef.record` not already being set; the
	*answer* is not. Ask twice and the character tells you again, which is what
	a person does, and gets you nothing, which is what a ledger does. Both fall
	out of one flag, so there is no second place for the two to disagree.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Dialogue = require(Shared.Config.Dialogue)
local Inventory = require(Shared.Core.Inventory)
local Net = require(Shared.Core.Net)
local Secrets = require(Shared.Config.Secrets)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Types = require(Shared.Types)

type PlayerProfile = Types.PlayerProfile

local SecretService = {
	name = "SecretService",
	-- After DialogueService (56), which is the only thing that calls it.
	priority = 58,
}

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

local function analytics()
	return ServiceLoader.get("AnalyticsService")
end

--------------------------------------------------------------------------------
-- Paying out
--------------------------------------------------------------------------------

--[[
	Hands over one secret's reward. Returns false if the bag would not take it.

	Credits are awarded `raw`, so a Bargaining build does not inflate them.
	Every other source of credits in the game is a price or a fee and scaling
	those is the point of the stat; what somebody tells you is not a
	transaction, and a secret worth 40% more to one character than another
	would be the only thing in the file that could be farmed for value.
]]
local function pay(player: Player, secret: Secrets.SecretDef): boolean
	local reward = secret.reward
	local item = reward.item

	--[[
		The one refusal. `Inventory.add` returns nil when a rolled item will
		not fit, and a unique object that silently evaporates into a full bag
		is exactly the kind of loss a player cannot diagnose and will never
		forgive -- so the flag is not raised, and the secret can be earned
		again once there is room.
	]]
	if item and reward.rolls and Inventory.full(data().get(player).inventory) then
		return false
	end

	if reward.xp then
		progression().awardXp(player, reward.xp)
	end
	if reward.credits then
		progression().awardCredits(player, reward.credits, true)
	end
	if item then
		data().update(player, function(profile: PlayerProfile)
			Inventory.add(profile.inventory, item, reward.count or 1, reward.rolls)
		end)
	end

	-- Last, and through the same choke point every other flag goes through,
	-- so an undeclared record id is the same boot warning here as anywhere.
	progression().awardAlignment(player, 0, { secret.record })
	return true
end

--- The line that tells the player what they just got, or nil if it was nothing.
local function receipt(secret: Secrets.SecretDef): string?
	local reward = secret.reward
	local parts: { string } = {}
	local name = Secrets.rewardName(reward)
	if name then
		table.insert(parts, name)
	end
	if reward.credits then
		table.insert(parts, `{reward.credits} credits`)
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, "  --  ")
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	The player has asked `speaker` about `topic`. Returns the node to send them
	to, or nil to let the authored deflection stand.

	`ctx` is passed in rather than rebuilt because DialogueService has already
	made exactly the right one for this conversation -- the speaker's faction
	decides what `rep` means, and reassembling it here would be a second
	builder that eventually reads a different faction than the line the player
	just clicked did.
]]
function SecretService.raise(player: Player, speaker: string, topic: string, ctx: Dialogue.Context): string?
	local secret = Secrets.find(speaker, topic)
	if not secret then
		return nil
	end

	-- Already told you. The node still opens; nothing else happens.
	if ctx.flags[secret.record] then
		return secret.opens
	end

	if not Dialogue.meets(secret.requires, ctx) then
		return nil
	end

	if not pay(player, secret) then
		Net.fireClient(Net.Event.Notify, player, "No room -- come back with an empty hand", "Error")
		return nil
	end

	local line = receipt(secret)
	if line then
		Net.fireClient(Net.Event.Notify, player, line, "Reward")
	end

	-- Only the first telling, because that is the one `pay` ran for. A repeat
	-- ask returns above and is a `talk`, which is what it is.
	local telemetry = analytics()
	telemetry.log(player, telemetry.Kind.Secret, { secret = secret.id, speaker = speaker })
	return secret.opens
end

return SecretService
