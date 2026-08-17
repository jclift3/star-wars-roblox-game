--!strict
--[[
	AbilityService.luau

	Runs the verbs declared in `Config/Abilities.luau`.

	AUTHORITY
	Same inversion as `CombatService`, for the same reason: the client sends an
	ability id and an aim direction, and nothing else. It does not send a
	target, a hit, a damage number, a landing point, or how much Force it has
	left. The server owns all six.

	`Config/Abilities.luau` is replicated so the client can draw the bar, which
	means the client also knows every cooldown and cost. That is fine and it is
	also worth nothing to a cheat: every field is re-read from the same table
	server-side before anything happens. The boys will play this in the same
	room and one of them will try.

	THE FORCE POOL IS NOT SAVED
	It lives in this module for the length of a session and refills on spawn.
	A resource that regenerates in under a minute has nothing to remember, and
	persisting it would mean a player who logged out mid-fight logs back in
	unable to do the thing they logged in to do.

	NO BRANCH PER ABILITY
	Three shape resolvers, and adding a sixth ability is a table entry. The
	moment this file grows an `if abilityId == "..."` it has started becoming
	the file nobody can add to.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Abilities = require(Shared.Config.Abilities)
local Progression = require(Shared.Config.Progression)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type AbilityDef = Abilities.AbilityDef

local AbilityService = {
	name = "AbilityService",
	-- After CombatService (30), whose `applyDamage` and `resolveTarget` this
	-- calls, and after ProgressionService (10), which owns the stat cache.
	priority = 32,
}

--[[
	The same grace `CombatService` gives a blaster, and for the same reason: a
	player on a bad connection whose key press arrives forty milliseconds early
	should get the ability, not a refusal they cannot explain.
]]
local COOLDOWN_GRACE = 0.06

--- How often Force ticks back. Coarse on purpose -- a smooth bar is a lie the
--- client can tell locally, and this is one replicated number per second.
local REGEN_INTERVAL = 1

--- Force now, per player. Absent means "not spawned yet", not zero.
local forceNow: { [Player]: number } = {}

--- os.clock() of the last successful use, per player per ability.
local lastUsedAt: { [Player]: { [string]: number } } = {}

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

local function combat()
	return ServiceLoader.get("CombatService")
end

--------------------------------------------------------------------------------
-- The Force pool
--------------------------------------------------------------------------------

--- A player's Force ceiling. Zero for anybody who never opened the tree.
local function maxForceOf(player: Player): number
	return progression().getStats(player).MaxForce or 0
end

--[[
	Tells one player what their pool looks like.

	Sent on every change rather than polled, because the only two things that
	move it are spending and the regen tick, and both happen here.
]]
local function pushForce(player: Player)
	local max = maxForceOf(player)
	if max <= 0 then
		return -- no pool, no meter; the bar draws nothing
	end
	Net.fireClient(Net.Event.ForceChanged, player, math.floor(forceNow[player] or 0), math.floor(max))
end

local function refill(player: Player)
	forceNow[player] = maxForceOf(player)
	pushForce(player)
end

--------------------------------------------------------------------------------
-- Shapes
--------------------------------------------------------------------------------

--[[
	Every distinct character with a Humanoid whose parts touch a sphere.

	Returns models, not parts: a query at any useful radius returns a dozen
	limbs of the same person, and an ability that damaged each of them
	separately would do ten times its listed damage to whoever stood closest.
]]
local function charactersInRadius(centre: Vector3, radius: number, ignore: Model): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }

	local seen: { [Model]: boolean } = {}
	local out: { Model } = {}
	for _, part in Workspace:GetPartBoundsInRadius(centre, radius, params) do
		local humanoid, model = combat().resolveTarget(part)
		if humanoid and model and not seen[model] and humanoid.Health > 0 then
			seen[model] = true
			table.insert(out, model)
		end
	end
	return out
end

local function rootOf(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

--[[
	Shoves a character away from `from`.

	Flattened and given a lift: an impulse along the raw line between two people
	standing on the same floor is horizontal, which grinds a body along the
	ground instead of throwing it. Scaled by assembly mass so a heavy rig and a
	light one travel the same distance -- an impulse that ignored mass would
	make Force Push a lottery on the target's build.
]]
local function shove(target: Model, from: Vector3, power: number)
	local root = rootOf(target)
	if not root then
		return
	end
	local away = (root.Position - from) * Vector3.new(1, 0, 1)
	local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
	root:ApplyImpulse((dir + Vector3.new(0, 0.45, 0)).Unit * power * root.AssemblyMass)
end

local function heal(character: Model, amount: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
end

--[[
	Applies everything an ability does to the enemies it caught.

	Damage is routed through `CombatService.applyDamage` -- never
	`Humanoid.Health` -- so an ability kill pays XP, credits, loot, reputation
	and mission progress exactly like a blaster kill. That is the whole reason
	that function is the only door.

	A mark rides the same `canDamage` gate as the damage, which is the answer
	to "who can be marked": exactly the people you were allowed to shoot. A
	mark on a civilian would be a debuff sitting on somebody nobody may hit.
]]
local function strike(caster: Model, attacker: Player?, def: AbilityDef, scale: number, targets: { Model })
	local amount = (def.damage or 0) * scale
	local knockback = (def.knockback or 0) * scale
	local mark = (def.mark or 0) * scale
	for _, target in targets do
		if not combat().canDamage(caster, target) then
			continue
		end
		if mark > 0 then
			combat().mark(target, mark, def.duration or 0)
		end
		if amount > 0 then
			local root = rootOf(target)
			combat().applyDamage(target, {
				amount = amount,
				source = caster,
				attacker = attacker,
				damageType = def.damageType or "Force",
				position = root and root.Position or nil,
			})
		end
		if knockback > 0 then
			local casterRoot = rootOf(caster)
			shove(target, casterRoot and casterRoot.Position or Vector3.zero, knockback)
		end
	end
end

--[[
	Where a `Point` ability actually lands.

	Raycast rather than trusting a client-sent position: the client picks the
	direction, the server picks the spot. Without the cast a grenade could be
	dropped on the far side of a wall, or at a coordinate nobody can see.
]]
local function landingSpot(caster: Model, origin: Vector3, direction: Vector3, range: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { caster }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(origin, direction * range, params)
	return if hit then hit.Position else origin + direction * range
end

--------------------------------------------------------------------------------
-- Casting
--------------------------------------------------------------------------------

--[[
	Runs an ability that has already been paid for and permitted.

	Split from the checks above it so the rules and the effects can be read
	separately: everything below this line assumes the caster is allowed.

	It also broadcasts the visual, rather than the caller doing it before
	calling in: only this function knows where a `Point` ability actually
	landed, and a client drawing the grenade where it was *aimed* would draw it
	through the wall the server stopped it against.
]]
local function cast(player: Player?, caster: Model, def: AbilityDef, scale: number, direction: Vector3)
	local root = rootOf(caster)
	if not root then
		return
	end
	local origin = root.Position + Vector3.new(0, 1.5, 0)

	if def.shape == Abilities.Shape.Cone then
		Net.fireAllClients(Net.Event.AbilityUsed, def.id, origin, direction)
		--[[
			A sphere query filtered by angle, not a cone cast -- Roblox has no
			cone query, and the alternative (a fan of raycasts) misses anything
			standing between two rays. The dot product against the cosine of
			the half-angle is the cone.
		]]
		local limit = math.cos(math.rad(def.angle or 45))
		local inCone: { Model } = {}
		for _, target in charactersInRadius(origin, def.range, caster) do
			local targetRoot = rootOf(target)
			if not targetRoot then
				continue
			end
			local toTarget = targetRoot.Position - origin
			if toTarget.Magnitude > 0.1 and direction:Dot(toTarget.Unit) >= limit then
				table.insert(inCone, target)
			end
		end
		strike(caster, player, def, scale, inCone)
	elseif def.shape == Abilities.Shape.Point then
		local spot = landingSpot(caster, origin, direction, def.range)
		Net.fireAllClients(Net.Event.AbilityUsed, def.id, spot, direction)
		--[[
			The sweep happens after the fuse, not now. Resolving it on the
			throw and merely showing the delay would make a grenade a hitscan
			weapon with a slow animation, and standing up out of the blast
			radius would do nothing.
		]]
		task.delay(def.fuse or 0, function()
			if not caster:IsDescendantOf(Workspace) then
				return
			end
			strike(caster, player, def, scale, charactersInRadius(spot, def.radius or 1, caster))
		end)
	else
		--[[
			Aura. The caster always, plus every *player* in radius.

			Player-only because there is no friendly-NPC concept in this game
			and healing whatever civilian happened to be standing there is a
			worse rule than "your brother". `Abilities.validate` refuses an
			Aura that deals damage or marks, so this can never be used
			against anybody.
		]]
		Net.fireAllClients(Net.Event.AbilityUsed, def.id, root.Position, direction)
		local amount = (def.heal or 0) * scale
		local pool = (def.absorb or 0) * scale
		local function cover(target: Model)
			if amount > 0 then
				heal(target, amount)
			end
			if pool > 0 then
				combat().shield(target, pool, def.duration or 0)
			end
		end
		cover(caster)
		for _, target in charactersInRadius(root.Position, def.radius or 1, caster) do
			if Players:GetPlayerFromCharacter(target) then
				cover(target)
			end
		end
	end
end

--[[
	What an ability costs and how long it locks, after the player's skills.

	Both are derived in one place because both are read twice -- once to
	refuse the press and once to charge for it -- and the two reads drifting
	apart is a cooldown you can dodge or a cost you pay without the check.
	`getStats` is cached per player, so asking it four times is four table
	lookups.
]]
local function costOf(player: Player, def: AbilityDef): number
	if not def.forceCost then
		return 0
	end
	return def.forceCost * (progression().getStats(player).ForceCostMult or 1)
end

local function cooldownOf(player: Player, def: AbilityDef): number
	return def.cooldown * (progression().getStats(player).AbilityCooldownMult or 1)
end

--[[
	Faults in a request, or nil if it is allowed. Does not spend anything.

	Every refusal is a sentence, because the bar shows it. A key that greys out
	with no explanation is the same bug as a skill node that refuses silently.
]]
local function refusalFor(player: Player, def: AbilityDef, now: number): string?
	local profile = data().get(player)
	if not profile then
		return "Still waking up"
	end
	if def.unimplemented then
		return def.unimplemented
	end
	if (profile.skills[def.node] or 0) < 1 then
		return "You have not learned that"
	end

	local used = lastUsedAt[player]
	local last = used and used[def.id] or 0
	local left = cooldownOf(player, def) - (now - last) - COOLDOWN_GRACE
	if left > 0 then
		return string.format("%s: %.1fs", def.displayName, left)
	end

	if (forceNow[player] or 0) < costOf(player, def) then
		return "Not enough Force"
	end
	return nil
end

local function onUseAbility(player: Player, abilityId: string, direction: Vector3)
	if not Abilities.exists(abilityId) then
		return -- not a typo the player can make; no reply is the right reply
	end
	local def = Abilities.get(abilityId)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local refusal = refusalFor(player, def, now)
	if refusal then
		Net.fireClient(Net.Event.AbilityRefused, player, abilityId, refusal)
		return
	end

	-- Charged before the effect runs, so an ability that errors mid-cast still
	-- costs what it said it would rather than becoming free.
	local used = lastUsedAt[player]
	if not used then
		used = {}
		lastUsedAt[player] = used
	end
	used[abilityId] = now

	local cost = costOf(player, def)
	if cost > 0 then
		forceNow[player] = math.max(0, (forceNow[player] or 0) - cost)
		pushForce(player)
	end

	local scale = progression().getStats(player)[def.scaleStat] or 1
	local aim = if direction.Magnitude > 0.001 then direction.Unit else Vector3.new(0, 0, -1)

	cast(player, character, def, scale, aim)
end

--------------------------------------------------------------------------------
-- NPC entry point
--------------------------------------------------------------------------------

--[[
	Lets an NPC use an ability, bypassing cooldowns and the Force pool.

	Neither of those exists for an NPC: its pacing comes from its behaviour
	tree, and giving it a resource to track would be book-keeping nobody can
	see. Kept here rather than in `NPCService` so there is still exactly one
	implementation of what an ability does.
]]
function AbilityService.npcUse(npc: Model, abilityId: string, direction: Vector3)
	if not Abilities.exists(abilityId) then
		return
	end
	local root = rootOf(npc)
	if not root then
		return
	end
	local aim = if direction.Magnitude > 0.001 then direction.Unit else root.CFrame.LookVector
	cast(nil, npc, Abilities.get(abilityId), 1, aim)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function AbilityService.init()
	--[[
		An ability naming a skill nobody can buy is a button that never appears
		with nothing anywhere saying why -- the exact failure `Progression`
		already guards against on its own side of the join.
	]]
	local problems = Abilities.validate(function(nodeId)
		return Progression.nodes[nodeId] ~= nil
	end, function(stat)
		return Progression.baseStats[stat] ~= nil
	end, function(stat)
		return Progression.LIVE_STATS[stat] ~= nil
	end)
	for _, problem in problems do
		warn(`[AbilityService] ability config: {problem}`)
	end

	--[[
		And the same join read the other way. `Abilities.validate` can only
		check that an ability names a real node; nothing there can see a *node*
		that names an ability which does not exist, and the symptom of that is
		a skill whose detail pane quietly stops mentioning what it unlocks.
		This service is the one place that holds both tables.
	]]
	for id, node in Progression.nodes do
		local grants = node.ability
		if grants and not Abilities.exists(grants) then
			warn(`[AbilityService] skill config: {id} grants "{grants}", which is not an ability`)
		end
	end

	Net.onServerEvent(Net.Event.UseAbility, onUseAbility, {
		-- Well above the shortest cooldown in the table; the per-ability
		-- cooldown above is the real limit. This only stops a held key from
		-- costing us a sphere query per frame.
		rateLimit = 10,
		validate = Net.args(Net.check.string(48), Net.check.vector3(2)),
	})
end

function AbilityService.start()
	ServiceLoader.get("PlayerService").characterReady:connect(function(player: Player)
		refill(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		forceNow[player] = nil
		lastUsedAt[player] = nil
	end)

	--[[
		One accumulator for everybody rather than a loop per player: at four
		players this is indistinguishable, and at forty it is the difference
		between one timer and forty.
	]]
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since < REGEN_INTERVAL then
			return
		end
		local elapsed = since
		since = 0

		for player in forceNow do
			local max = maxForceOf(player)
			if max <= 0 then
				continue
			end
			local regen = progression().getStats(player).ForceRegen or 0
			-- Clamped to `max` every tick, so buying a rank of ForceSensitive
			-- raises the ceiling and losing one cannot leave a player above it.
			local next_ = math.clamp((forceNow[player] or 0) + regen * elapsed, 0, max)
			if next_ ~= forceNow[player] then
				forceNow[player] = next_
				pushForce(player)
			end
		end
	end)
end

return AbilityService
