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

local function global()
	return ServiceLoader.get("GlobalService")
end

--[[
	Claims being the first player in the whole game told this, and says so.

	WHY THIS IS THE PAYOUT AND NOT A RARER ITEM
	LIVING-NPCS 7 asks for "the unique version" of the reward, which sounds
	like a second reward table and is not. What actually makes a first-solve
	worth having is that it is *first* -- a fact about everyone else, which no
	amount of item quality can imitate, and which this game has never been able
	to state before because a DataStore key was the only place it could live.
	So the prize is the sentence, and the credits are doubled to make it a
	sentence with something behind it.

	Doubled rather than given a number, so that a secret worth 3,000 credits is
	worth 6,000 to whoever got there first and no table anywhere has to be kept
	in step with the reward it is decorating. It cannot inflate anything: it is
	`raw`, so Bargaining does not touch it, and it can happen exactly once per
	secret for the lifetime of the game.

	WHY THE LOSER IS TOLD WHO WON
	Because the alternative is silence, and silence is indistinguishable from
	the feature not existing. Two brothers in one room is the entire audience
	here, and "Corr told <name> first" is the whole of what makes the six
	secrets a race rather than six errands. It costs the loser nothing -- the
	ordinary reward has already been paid by the time this runs.

	Yields on a DataStore, so it is spawned. Nothing above it waits.
]]
local function claimFirst(player: Player, secret: Secrets.SecretDef)
	task.spawn(function()
		local won, holder = global().claim(Secrets.firstKey(secret.id), player)
		if won then
			local bonus = secret.reward.credits
			if bonus then
				progression().awardCredits(player, bonus, true)
			end
			local line = if bonus
				then `FIRST IN THE GALAXY  --  {bonus} credits over`
				else "FIRST IN THE GALAXY"
			Net.fireClient(Net.Event.Notify, player, line, "Promotion")
		elseif holder then
			-- Only when somebody is actually named. A failed DataStore call
			-- returns no holder, and "you were beaten by nobody" is a worse
			-- thing to say than nothing at all.
			Net.fireClient(Net.Event.Notify, player, `{holder} was told this first`, "Info")
		end
	end)
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

	-- After the receipt, so the ordinary reward is read first and the galaxy
	-- line lands on top of it as the extra it is.
	claimFirst(player, secret)

	-- Only the first telling, because that is the one `pay` ran for. A repeat
	-- ask returns above and is a `talk`, which is what it is.
	local telemetry = analytics()
	telemetry.log(player, telemetry.Kind.Secret, { secret = secret.id, speaker = speaker })
	return secret.opens
end

return SecretService
