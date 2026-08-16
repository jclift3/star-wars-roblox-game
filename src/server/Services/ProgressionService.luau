--!strict
--[[
	ProgressionService.luau

	XP, levels, skill points and the derived stat table every other system reads.

	Everything that hands out a reward comes through here rather than editing
	the profile directly, so multipliers (Scavenger's credit bonus, level-scaled
	XP) are applied in exactly one place. A combat system that writes credits
	itself will silently skip the player's investment in Engineering.

	DERIVED STATS
	`Progression.computeStats` folds skill ranks into a flat table. That fold is
	pure but not free, and combat asks for it on every shot, so results are
	cached per player and invalidated when skills change. The cache is the only
	stateful part of this service.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Inventory = require(Shared.Core.Inventory)
local Signal = require(Shared.Core.Signal)
local Progression = require(Shared.Config.Progression)
local Factions = require(Shared.Config.Factions)
local Outfits = require(Shared.Config.Outfits)

local ServiceLoader = require(Shared.Core.ServiceLoader)

type PlayerProfile = Types.PlayerProfile

local ProgressionService = {
	name = "ProgressionService",
	priority = 10,
}

local statCache: { [Player]: { [string]: number } } = {}

ProgressionService.leveledUp = Signal.new()
ProgressionService.statsChanged = Signal.new()
ProgressionService.rankChanged = Signal.new()

local function data()
	return ServiceLoader.get("DataService")
end

local function notify(player: Player, message: string, kind: string?)
	Net.fireClient(Net.Event.Notify, player, message, kind or "Info")
end

--------------------------------------------------------------------------------
-- Stats
--------------------------------------------------------------------------------

--[[
	Everything the player's gear contributes: the outfit's authored stats, plus
	whatever the equipped outfit and weapon rolled.

	`equipped` holds inventory uids, not catalogue ids -- for a plain item the
	two are the same string, which is why nothing needed changing when stacks
	arrived, but a rolled item is `DH17#2` and only the stack knows it is a
	DH17.

	Cloned before anything is folded in, because `Outfits.statsFor` hands back
	the config's own table: adding a roll to it in place would permanently
	rewrite that outfit for every player on the server.
]]
local function gearStats(profile): { [string]: number }
	local inv = profile.inventory
	local extra = table.clone(Outfits.statsFor(Inventory.idOf(inv, profile.equipped.outfit)))
	for _, uid in { profile.equipped.outfit, profile.equipped.weapon } do
		local rolls = Inventory.rollsOf(inv, uid)
		if rolls then
			for stat, delta in rolls do
				extra[stat] = (extra[stat] or 0) + delta
			end
		end
	end
	return extra
end

--- The player's folded stat table. Cheap to call; cached until skills change.
function ProgressionService.getStats(player: Player): { [string]: number }
	local cached = statCache[player]
	if cached then
		return cached
	end
	local profile = data().get(player)
	-- Worn gear stacks with skills. Anything that changes the equipped outfit
	-- OR WEAPON must call `invalidate`, or the player keeps the old gear's
	-- numbers -- weapons carry stats now that they can roll affixes.
	local stats = Progression.computeStats(
		profile and profile.skills or {},
		if profile then gearStats(profile) else nil
	)
	statCache[player] = stats
	return stats
end

function ProgressionService.invalidate(player: Player)
	statCache[player] = nil
	ProgressionService.statsChanged:fire(player, ProgressionService.getStats(player))
end

--- Max health at the player's current level, including the Toughness skill.
function ProgressionService.maxHealthFor(player: Player): number
	local profile = data().get(player)
	local level = profile and profile.level or 1
	local stats = ProgressionService.getStats(player)
	return Progression.baseHealthForLevel(level) + (stats.BonusHealth or 0)
end

--------------------------------------------------------------------------------
-- Awards
--------------------------------------------------------------------------------

--[[
	Grants XP and processes any resulting level-ups.

	Loops rather than levelling once, because a big mission turn-in can span
	several levels at low level and stopping at one would quietly eat the rest.
]]
function ProgressionService.awardXp(player: Player, amount: number): number
	if amount <= 0 then
		return 0
	end
	local granted = math.floor(amount)
	local levelsGained = 0

	data().update(player, function(profile: PlayerProfile)
		profile.xp += granted

		while profile.level < Progression.MAX_LEVEL do
			local needed = Progression.xpForNextLevel(profile.level)
			if profile.xp < needed then
				break
			end
			profile.xp -= needed
			profile.level += 1
			profile.skillPoints += Progression.SKILL_POINTS_PER_LEVEL
			levelsGained += 1
		end

		if profile.level >= Progression.MAX_LEVEL then
			profile.xp = 0
		end
	end)

	if levelsGained > 0 then
		local profile = data().get(player)
		local level = profile and profile.level or 1
		notify(
			player,
			`Level {level}! +{levelsGained} skill point{if levelsGained > 1 then "s" else ""}`,
			"LevelUp"
		)
		ProgressionService.leveledUp:fire(player, level, levelsGained)
	end

	return granted
end

--- Grants credits with the Scavenger multiplier applied.
function ProgressionService.awardCredits(player: Player, amount: number, raw: boolean?): number
	if amount <= 0 then
		return 0
	end
	local mult = if raw then 1 else (ProgressionService.getStats(player).CreditMult or 1)
	local granted = math.floor(amount * mult)
	data().update(player, function(profile: PlayerProfile)
		profile.credits += granted
	end)
	return granted
end

--[[
	Spends credits if the player can afford it.

	Returns false without changing anything when they cannot, so callers can
	treat it as a guard: `if not spendCredits(...) then return end`.
]]
function ProgressionService.spendCredits(player: Player, amount: number): boolean
	local profile = data().get(player)
	if not profile or profile.credits < amount then
		return false
	end
	data().update(player, function(p: PlayerProfile)
		p.credits -= amount
	end)
	return true
end

--- Vendor price for `basePrice` after the Haggler skill.
function ProgressionService.priceFor(player: Player, basePrice: number): number
	local mult = ProgressionService.getStats(player).PriceMult or 1
	return math.max(1, math.floor(basePrice * mult))
end

--[[
	Pays out the rank ladder for a promotion, and returns what it paid.

	Every rank in `Config/Factions.luau` carries a `creditStipend` that nothing
	had ever read, so a promotion was a toast and nothing else -- the ladder
	described a career and paid like a hobby.

	Rules that fall out of it being a *ladder*:
	- **Every rank newly reached is paid**, not just the one landed on, so a
	  mission big enough to jump two ranks is not worth less than two smaller
	  ones.
	- **Only ranks above the highest already paid**, which is what
	  `factionRankPaid` is for. Rep goes down as well as up, and being paid
	  again for climbing back is a credit printer.
	- **Raw**, past the Scavenger multiplier: a stipend is a salary the faction
	  sets, and `creditStipend` should be the number the player is handed.
]]
local function stipendFor(player: Player, factionId: string, newRank: number): number
	local profile = data().get(player)
	if not profile then
		return 0
	end

	local paid = profile.factionRankPaid[factionId] or 1
	if newRank <= paid then
		return 0
	end

	local def = Factions.get(factionId)
	local total = 0
	for index = paid + 1, math.min(newRank, #def.ranks) do
		total += def.ranks[index].creditStipend
	end

	data().update(player, function(p: PlayerProfile)
		p.factionRankPaid[factionId] = newRank
	end)
	if total <= 0 then
		return 0
	end
	return ProgressionService.awardCredits(player, total, true)
end

--[[
	Applies a reputation change, including its spillover to other factions.

	Announces rank changes in either direction, and pays the stipend for a
	promotion. A silent demotion after a massacre is worse than no reputation
	system at all -- the player has to see the consequence to connect it to the
	cause.
]]
function ProgressionService.awardRep(player: Player, factionId: string, delta: number)
	if delta == 0 or not Factions.exists(factionId) then
		return
	end

	local before: { [string]: number }? = nil
	local after: { [string]: number }? = nil

	data().update(player, function(profile: PlayerProfile)
		local updated = Factions.applyRepChange(profile.factionRep, factionId, delta)
		before = table.clone(profile.factionRep)
		after = updated
		profile.factionRep = updated
	end)

	-- Copy out of the upvalues so the type checker can narrow them.
	local prev, curr = before, after
	if not prev or not curr then
		return
	end

	for id, newRep in curr do
		local oldRep = prev[id] or 0
		if newRep == oldRep then
			continue
		end
		local oldRank = Factions.rankIndexFor(id, oldRep)
		local newRank = Factions.rankIndexFor(id, newRep)
		if newRank == oldRank then
			continue
		end

		local faction = Factions.get(id)
		local rank = Factions.rankFor(id, newRep)
		if newRank > oldRank then
			local stipend = stipendFor(player, id, newRank)
			local paid = if stipend > 0 then ` (+{stipend} cr)` else ""
			notify(player, `{faction.displayName}: promoted to {rank.name}{paid}`, "Promotion")
		else
			notify(player, `{faction.displayName}: demoted to {rank.name}`, "Demotion")
		end
		ProgressionService.rankChanged:fire(player, id, newRank, oldRank)
	end
end

--------------------------------------------------------------------------------
-- Skills
--------------------------------------------------------------------------------

--[[
	Buys one rank in a skill node.

	All validation is server-side. The client sends a node id and nothing else;
	it cannot assert that it has the points, the level or the prerequisites.
]]
function ProgressionService.purchaseSkill(player: Player, nodeId: string): (boolean, string?)
	local profile = data().get(player)
	if not profile then
		return false, "Profile not loaded"
	end

	local ok, reason = Progression.canPurchase(nodeId, profile.skills, profile.level, profile.skillPoints)
	if not ok then
		return false, reason
	end

	data().update(player, function(p: PlayerProfile)
		p.skills[nodeId] = (p.skills[nodeId] or 0) + 1
		p.skillPoints -= 1
	end)

	ProgressionService.invalidate(player)

	local node = Progression.nodes[nodeId]
	local rank = profile.skills[nodeId] or 1
	notify(player, `{node.displayName} rank {rank}`, "Skill")
	return true, nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ProgressionService.init()
	Net.onServerEvent(Net.Event.SpendSkillPoint, function(player: Player, nodeId: string)
		local ok, reason = ProgressionService.purchaseSkill(player, nodeId)
		if not ok and reason then
			notify(player, reason, "Error")
		end
	end, {
		rateLimit = 4,
		validate = Net.args(Net.check.string(64)),
	})
end

function ProgressionService.start()
	Players.PlayerRemoving:Connect(function(player)
		statCache[player] = nil
	end)

	-- A freshly loaded profile means the cached stats (if any) are from a
	-- previous session on this server object and must not be reused.
	data().profileLoaded:connect(function(player: Player)
		statCache[player] = nil
	end)
end

return ProgressionService
