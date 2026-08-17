--!strict
--[[
	CombatService.luau

	All damage in the game goes through this module.

	AUTHORITY
	The client sends "I fired, from roughly here, in this direction". It does
	not send a target, a hit, or a damage number. The server re-derives all
	three. That inversion is the entire security model, and it is why the client
	cannot be trusted with anything more than input.

	Specifically the server checks, per shot:
	  - is the weapon actually equipped on the profile
	  - has enough time passed for the weapon's fire rate (server clock)
	  - is the claimed origin close to the player's real character
	  - does a fresh raycast from that origin actually hit something

	HITSCAN, VISUAL PROJECTILES
	Damage is resolved instantly by raycast; the bolt the player sees is a
	client-side visual that travels at the weapon's `projectileSpeed`. Doing it
	the other way round -- server-simulated projectiles -- means the shot that
	looked like a hit on the client can miss on the server, which feels broken
	no matter how correct it is.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Core.Net)
local Inventory = require(Shared.Core.Inventory)
local Signal = require(Shared.Core.Signal)
local Affixes = require(Shared.Config.Affixes)
local Palette = require(Shared.Config.Palette)
local Weapons = require(Shared.Config.Weapons)
local Loot = require(Shared.Config.Loot)
local Factions = require(Shared.Config.Factions)
local WeaponModel = require(Shared.Rig.WeaponModel)
local ServiceLoader = require(Shared.Core.ServiceLoader)

type DamageInfo = Types.DamageInfo
type PlayerProfile = Types.PlayerProfile

local CombatService = {
	name = "CombatService",
	priority = 30,
}

-- How far the claimed muzzle position may be from the player's root before we
-- reject the shot. Generous enough to absorb latency and animation offsets,
-- tight enough that it cannot be used to shoot around corners or across a map.
local MAX_ORIGIN_ERROR = 18

-- Small grace on the fire-rate check so a player on a bad connection is not
-- punished for a shot that arrives a few milliseconds early.
local FIRE_RATE_GRACE = 0.06

local lastFireAt: { [Player]: number } = {}
local lastSwingAt: { [Player]: number } = {}

-- Unseeded on purpose. Loot is the one thing in this game that must not be
-- reproducible: the planets are generated from fixed seeds so that every
-- player sees the same world, and a drop table on a fixed seed would mean
-- every player got the same blaster in the same order.
local lootRng = Random.new()

CombatService.damaged = Signal.new()
CombatService.killed = Signal.new()

local function data()
	return ServiceLoader.get("DataService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

--------------------------------------------------------------------------------
-- Target identity
--------------------------------------------------------------------------------

--[[
	Resolves whatever a raycast hit into a damageable character.

	Walks up from the part because a hit can land on a cosmetic pauldron welded
	to a limb, not the limb itself. Returns the humanoid plus the owning player
	when there is one.

	Exported because `AbilityService` sweeps its cones and blasts with the same
	overlap queries and has to answer the same question. A second copy of this
	walk would be a second place for "the pauldron is not the person" to be got
	subtly wrong.
]]
function CombatService.resolveTarget(part: BasePart?): (Humanoid?, Model?, Player?)
	if not part then
		return nil, nil, nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid, model, Players:GetPlayerFromCharacter(model)
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil, nil
end

--- The faction a character fights for. NPCs carry it as an attribute.
function CombatService.factionOf(character: Model): string
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local profile = data().get(player)
		return profile and profile.faction or Factions.DEFAULT
	end
	return character:GetAttribute("Faction") :: string? or Factions.DEFAULT
end

--[[
	Whether `attacker` is allowed to damage `target`.

	Player-versus-player is off. Everything else is decided by faction, which
	means shooting a stormtrooper while wearing Imperial colours is friendly
	fire and simply does not land -- rather than being allowed and then
	confusing the reputation system.
]]
function CombatService.canDamage(attacker: Model, target: Model): boolean
	if attacker == target then
		return false
	end
	local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if attackerPlayer and targetPlayer then
		return false
	end
	if not attackerPlayer and not targetPlayer then
		-- NPC on NPC: only genuine faction enemies brawl, or the streets of
		-- Mos Eisley turn into a permanent riot.
		return Factions.areEnemies(CombatService.factionOf(attacker), CombatService.factionOf(target))
	end
	return true
end

--------------------------------------------------------------------------------
-- Timed effects
--------------------------------------------------------------------------------

--[[
	Marks and barriers -- the two things one player can do to another player's
	fight, from ROADMAP 4.3's fourth target.

	WHY THEY LIVE HERE AND NOT IN `AbilityService`
	Both are read at the moment a hit lands, and `applyDamage` below is the
	only function that sees one. `AbilityService` writes them and never reads
	them again; putting the state next to the writer would mean exporting a
	getter that damage has to remember to call, which is the same shape of
	mistake as a system nothing has an entry point into.

	NOTHING STACKS
	A second mark on an already-marked target takes the larger of the two
	bonuses and restarts the clock; a second barrier does the same with what
	is left of the first. Two Force users alternating barriers would otherwise
	pile up a pool nothing could chew through, and the brothers will find that
	within an afternoon. Refreshing is allowed -- it costs a cooldown either
	way -- but adding is not.
]]
type Timed = {
	--- Mark: the fraction added to damage. Barrier: the damage still to soak.
	magnitude: number,
	expires: number,
}

--[[
	Weak-keyed, so a dead NPC's entry goes away with the NPC.

	Written as a cast because `setmetatable` returns the table with its own
	type and `--!strict` has no notion of a weak table. The alternative is a
	sweep loop holding every character that has ever been marked, on a server
	that despawns hundreds of them.
]]
local marks: { [Model]: Timed } = setmetatable({}, { __mode = "k" }) :: any
local barriers: { [Model]: Timed } = setmetatable({}, { __mode = "k" }) :: any

local MARK_GLOW = "MarkGlow"
local BARRIER_GLOW = "BarrierGlow"

--- The entry, if it has not lapsed. Expiry is checked on read rather than on a
--- timer: there is no tick to get out of step with, and nothing is spending
--- CPU on an effect nobody is being hit through.
local function liveEffect(store: { [Model]: Timed }, character: Model): Timed?
	local effect = store[character]
	if not effect then
		return nil
	end
	if os.clock() >= effect.expires then
		store[character] = nil
		return nil
	end
	return effect
end

--[[
	An outline, so the thing an ability did to somebody is visible.

	`Occluded`, not `AlwaysOnTop`: a mark you can see through a wall is a
	wallhack one of them would work out how to farm. Server-made rather than
	broadcast, because a Highlight replicates on its own and the client has
	no business deciding who is marked.

	The colours are the ones `EffectsController` flashes when the ability goes
	off, so the outline that appears is visibly the same thing as the light
	that caused it.
]]
local function glow(character: Model, name: string, colour: Color3, duration: number)
	local old = character:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local light = Instance.new("Highlight")
	light.Name = name
	light.FillTransparency = 1
	light.OutlineColor = colour
	light.DepthMode = Enum.HighlightDepthMode.Occluded
	light.Adornee = character
	light.Parent = character
	Debris:AddItem(light, duration)
end

--- Raises the damage *everyone* does to `target` by `bonus` for `duration`.
function CombatService.mark(target: Model, bonus: number, duration: number)
	if bonus <= 0 or duration <= 0 then
		return
	end
	local existing = liveEffect(marks, target)
	local magnitude = math.max(bonus, existing and existing.magnitude or 0)
	marks[target] = { magnitude = magnitude, expires = os.clock() + duration }
	glow(target, MARK_GLOW, Palette.SaberYellow, duration)
end

--- Gives `target` a pool of damage that is spent before their health is.
function CombatService.shield(target: Model, pool: number, duration: number)
	if pool <= 0 or duration <= 0 then
		return
	end
	local existing = liveEffect(barriers, target)
	local magnitude = math.max(pool, existing and existing.magnitude or 0)
	barriers[target] = { magnitude = magnitude, expires = os.clock() + duration }
	glow(target, BARRIER_GLOW, Palette.SaberBlue, duration)

	local player = Players:GetPlayerFromCharacter(target)
	if player then
		Net.fireClient(Net.Event.Notify, player, `Barrier: {math.floor(magnitude)}`, "Reward")
	end
end

--------------------------------------------------------------------------------
-- Damage
--------------------------------------------------------------------------------

--[[
	Whether a player with a lit sabre bats this particular shot away.

	Deflection is the one thing everybody knows a lightsaber does, and it is
	why the Force tree exists at all -- so `DeflectChance` reads as the fantasy
	rather than as a second armour stat:

	  * only against `Blaster`, so it is a *counter* to the ranged enemies the
	    other trees answer with more health, and does nothing against a
	    Tusken's gaffi stick;
	  * only with a sabre actually equipped, so it is a build and not a buff.
	    Holstering costs you the skill, which is the trade;
	  * all or nothing. A bolt that is deflected is gone. Shaving a percentage
	    off it would be `DamageReduction` under a better name.

	Capped, because five ranks is +45% and the tree will grow more sources of
	it: a number that can reach 1 makes a player immune to every blaster in
	the game, and the Force tree is not supposed to end the game.
]]
local MAX_DEFLECT = 0.75

local function deflects(victim: Player, info: DamageInfo): boolean
	if info.damageType ~= "Blaster" then
		return false
	end
	local chance = progression().getStats(victim).DeflectChance or 0
	if chance <= 0 then
		return false
	end

	local profile = data().get(victim)
	if not profile then
		return false
	end
	-- `equipped` names a carried stack, so a rolled sabre resolves back to the
	-- catalogue entry that says what class it is.
	local weaponId = Inventory.idOf(profile.inventory, profile.equipped.weapon)
	if not weaponId or not Weapons.exists(weaponId) or Weapons.get(weaponId).class ~= "Saber" then
		return false
	end

	-- `math.random`, like the crit roll, and deliberately not `lootRng`: a
	-- stream of deflects must not shift the sequence drops come out of.
	return math.random() < math.min(chance, MAX_DEFLECT)
end

--[[
	The single entry point for hurting anything.

	Nothing else in the codebase should touch Humanoid.Health directly: kill
	attribution, reputation and mission progress all hang off this function, and
	a direct health write skips every one of them.
]]
function CombatService.applyDamage(target: Model, info: DamageInfo): number
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	local amount = math.max(0, info.amount)
	if amount == 0 then
		return 0
	end

	-- A mark raises the attack itself, before anything the victim does about
	-- it, so it reads as "that one is easier to kill" rather than as armour
	-- piercing -- and so it is worth the same to whoever else is shooting,
	-- which is the entire point of the ability.
	local marked = liveEffect(marks, target)
	if marked then
		amount *= 1 + marked.magnitude
	end

	-- Armour is applied here rather than at the weapon, because a bolt, a
	-- sabre and a fall all have to respect it and only this function sees all
	-- three. NPCs have no outfit stats, so this is a no-op for them.
	local victim = Players:GetPlayerFromCharacter(target)
	if victim then
		if deflects(victim, info) then
			Net.fireClient(Net.Event.Notify, victim, "Deflected!", "Reward")
			return 0
		end
		local reduction = progression().getStats(victim).DamageReduction or 0
		amount *= 1 - math.clamp(reduction, 0, 0.75)
	end

	--[[
		The barrier soaks last, after armour, so the two do not multiply: a
		heavily armoured player would otherwise get far more out of the same
		pool than the one who actually needed covering.

		A hit swallowed whole returns 0 and stops here, like a deflect. The
		alternative is a floating "0" over the target and a `damaged` signal
		for a hit that did nothing, which is aggro and hit-feedback for free.
	]]
	local barrier = liveEffect(barriers, target)
	if barrier then
		local soaked = math.min(barrier.magnitude, amount)
		barrier.magnitude -= soaked
		amount -= soaked
		if barrier.magnitude <= 0 then
			barriers[target] = nil
			local light = target:FindFirstChild(BARRIER_GLOW)
			if light then
				light:Destroy()
			end
			if victim then
				Net.fireClient(Net.Event.Notify, victim, "Barrier broken", "Error")
			end
		end
		if amount <= 0 then
			return 0
		end
	end

	local before = humanoid.Health
	humanoid.Health = math.max(0, before - amount)
	local dealt = before - humanoid.Health

	CombatService.damaged:fire(target, info, dealt)

	if info.attacker then
		Net.fireClient(
			Net.Event.DamageDealt,
			info.attacker,
			math.floor(dealt + 0.5),
			info.isCritical == true,
			info.position
		)
	end

	if humanoid.Health <= 0 then
		CombatService.onKilled(target, info)
	end
	return dealt
end

--- Handles the consequences of a death: rewards, reputation, mission progress.
function CombatService.onKilled(target: Model, info: DamageInfo)
	CombatService.killed:fire(target, info)

	local killer = info.attacker
	if not killer or not killer:IsDescendantOf(Players) then
		return
	end

	local archetypeId = target:GetAttribute("Archetype") :: string?
	if not archetypeId then
		return -- not an NPC we track; nothing to award
	end

	local NPCArchetypes = require(Shared.Config.NPCArchetypes)
	if not NPCArchetypes.exists(archetypeId) then
		return
	end

	local profile = data().get(killer)
	if not profile then
		return
	end

	local npcLevel = (target:GetAttribute("Level") :: number?) or 1
	local xp = NPCArchetypes.xpFor(archetypeId, npcLevel, profile.level)
	local credits = NPCArchetypes.rollCredits(archetypeId)
	local archetype = NPCArchetypes.get(archetypeId)

	progression().awardXp(killer, xp)
	if credits > 0 then
		progression().awardCredits(killer, credits)
	end
	if archetype.repOnKill then
		progression().awardRep(killer, archetype.faction, archetype.repOnKill)
	end

	data().update(killer, function(p: PlayerProfile)
		p.stats.kills += 1
	end)

	--[[
		Loot last, so a drop is the final line in the notification stack and
		the one the player is still reading. Levelled off the NPC, not the
		killer -- see the note on `Loot.rollDrop`.
	]]
	local drop = Loot.rollDrop(lootRng, npcLevel)
	if drop then
		local taken = false
		data().update(killer, function(p: PlayerProfile)
			taken = Inventory.add(p.inventory, drop.id, 1, drop.rolls) ~= nil
		end)
		if not taken then
			-- A full bag is told about, not silently swallowed. The drop is
			-- gone either way -- there is no ground to leave it on -- so the
			-- player has to know to go and make room.
			Net.fireClient(Net.Event.Notify, killer, `Bag full -- left {Loot.nameOf(drop)} behind`, "Error")
			return
		end
		-- A rolled outfit or weapon changes nothing until it is equipped, so
		-- there is no cache to invalidate here.
		-- The toast's kind IS the rarity, so the colour it is drawn in comes
		-- from the same table the inventory panel reads and the two cannot
		-- disagree about what orange means.
		local rarity = Affixes.rarityOf(drop.rolls)
		Net.fireClient(Net.Event.Notify, killer, `{rarity.name}: {Loot.nameOf(drop)}`, rarity.name)
	end
end

--------------------------------------------------------------------------------
-- Firing
--------------------------------------------------------------------------------

local function raycastParams(ignore: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	params.IgnoreWater = true
	return params
end

--[[
	Everything the shooter's skills and gear change about one attack.

	A table rather than four more positional arguments: `resolveShot` was
	already seven parameters deep, and `nil, 1, 0` at a call site says
	nothing about which of them is the crit chance. An absent field means
	"the weapon's own number", so an NPC passes no table at all.
]]
export type ShotMods = {
	damageMult: number?,
	critChance: number?,
	critDamageBonus: number?,
	bonusPierce: number?,
}

--[[
	Resolves one shot from `character` and returns the damage dealt.

	`pierce` lets a heavy weapon punch through a target and keep going; each
	subsequent target is added to the ignore list and the ray is re-cast from
	the hit point, which is simpler and more predictable than a shape-cast.
]]
function CombatService.resolveShot(
	character: Model,
	weaponId: string,
	origin: Vector3,
	direction: Vector3,
	attacker: Player?,
	mods: ShotMods?
): number
	local weapon = Weapons.get(weaponId)
	local damageMult = mods and mods.damageMult or 1
	local critChance = mods and mods.critChance or 0
	local critMult = (weapon.critMultiplier or 2) + (mods and mods.critDamageBonus or 0)
	local params = raycastParams(character)
	local remaining = 1 + (weapon.pierce or 0) + (mods and mods.bonusPierce or 0)
	local from = origin
	local dir = direction.Unit * weapon.range
	local totalDealt = 0

	while remaining > 0 do
		local result = Workspace:Raycast(from, dir, params)
		if not result then
			break
		end

		local humanoid, targetModel = CombatService.resolveTarget(result.Instance)
		if not humanoid or not targetModel then
			break -- hit geometry; the bolt stops
		end

		if CombatService.canDamage(character, targetModel) then
			local distance = (result.Position - origin).Magnitude
			local base = Weapons.damageAtRange(weaponId, distance) * damageMult
			local isCrit = math.random() < critChance
			if isCrit then
				base *= critMult
			end

			totalDealt += CombatService.applyDamage(targetModel, {
				amount = base,
				source = character,
				attacker = attacker,
				damageType = if weapon.class == "Blaster" then "Blaster" else "Melee",
				position = result.Position,
				isCritical = isCrit,
			})
		end

		-- Either way the ray continues past this character, so exclude the
		-- whole model rather than the single part we hit.
		local filter = params.FilterDescendantsInstances
		table.insert(filter, targetModel)
		params.FilterDescendantsInstances = filter

		remaining -= 1
		from = result.Position
		dir = direction.Unit * math.max(0, weapon.range - (result.Position - origin).Magnitude)
		if dir.Magnitude < 1 then
			break
		end
	end

	return totalDealt
end

--------------------------------------------------------------------------------
-- Player input
--------------------------------------------------------------------------------

local function onFireWeapon(player: Player, origin: Vector3, direction: Vector3)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local profile = data().get(player)
	if not profile then
		return
	end

	-- The weapon is whatever the SERVER has recorded as equipped. A client
	-- claiming to fire a weapon it does not own gets nothing.
	-- `equipped` names a carried stack, so a rolled blaster resolves back to
	-- the catalogue entry that says how it shoots.
	local weaponId = Inventory.idOf(profile.inventory, profile.equipped.weapon)
	if not weaponId or not Weapons.exists(weaponId) then
		return
	end
	local weapon = Weapons.get(weaponId)
	if weapon.class ~= "Blaster" then
		return
	end

	if (origin - root.Position).Magnitude > MAX_ORIGIN_ERROR then
		return
	end

	local stats = progression().getStats(player)
	local cooldown = Weapons.cooldown(weaponId, stats.BlasterCooldownMult) - FIRE_RATE_GRACE
	local now = os.clock()
	if now - (lastFireAt[player] or 0) < cooldown then
		return
	end
	lastFireAt[player] = now

	-- Spread is applied server-side too, so a client cannot fire a perfectly
	-- accurate T-21 by sending a clean direction.
	local spread = math.rad(weapon.spread)
	local aim = direction.Unit
	if spread > 0 then
		local yaw = (math.random() - 0.5) * 2 * spread
		local pitch = (math.random() - 0.5) * 2 * spread
		aim = (CFrame.lookAt(Vector3.zero, aim) * CFrame.Angles(pitch, yaw, 0)).LookVector
	end

	CombatService.resolveShot(character, weaponId, origin, aim, player, {
		damageMult = stats.BlasterDamageMult,
		critChance = stats.CritChance,
		critDamageBonus = stats.CritDamageBonus,
		bonusPierce = stats.BonusPierce,
	})

	-- Everyone except the shooter needs the visual; the shooter already fired
	-- it locally on input for responsiveness.
	Net.fireAllExcept(Net.Event.WeaponEffect, player, weaponId, origin, aim)
end

local function onSaberSwing(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local profile = data().get(player)
	if not profile then
		return
	end
	-- `equipped` names a carried stack, so a rolled blaster resolves back to
	-- the catalogue entry that says how it shoots.
	local weaponId = Inventory.idOf(profile.inventory, profile.equipped.weapon)
	if not weaponId or not Weapons.exists(weaponId) then
		return
	end
	local weapon = Weapons.get(weaponId)
	if weapon.class ~= "Saber" and weapon.class ~= "Melee" then
		return
	end

	local stats = progression().getStats(player)
	local now = os.clock()
	if now - (lastSwingAt[player] or 0) < Weapons.cooldown(weaponId) - FIRE_RATE_GRACE then
		return
	end
	lastSwingAt[player] = now

	local damageMult = if weapon.class == "Saber" then (stats.SaberDamageMult or 1) else 1
	CombatService.swingMelee(character, weaponId, player, {
		damageMult = damageMult,
		critChance = stats.CritChance,
		critDamageBonus = stats.CritDamageBonus,
	})

	-- The character goes with it: a swing is drawn on the body that swung, and
	-- a position alone does not identify one. Bolts do not need it.
	Net.fireAllExcept(
		Net.Event.WeaponEffect,
		player,
		weaponId,
		root.Position,
		root.CFrame.LookVector,
		character
	)
end

--[[
	Sweeps a melee arc in front of `character` and damages everything in it.

	A sphere query plus a facing test, rather than a swept hitbox: a saber swing
	that connects with anything roughly in front of you at the right moment is
	what players expect, and precise blade geometry mostly produces misses that
	look like hits.
]]
function CombatService.swingMelee(
	character: Model,
	weaponId: string,
	attacker: Player?,
	mods: ShotMods?
): number
	local weapon = Weapons.get(weaponId)
	local damageMult = mods and mods.damageMult or 1
	local critChance = mods and mods.critChance or 0
	local critMult = (weapon.critMultiplier or 2) + (mods and mods.critDamageBonus or 0)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 0
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local centre = root.Position + root.CFrame.LookVector * (weapon.range * 0.4)
	local parts = Workspace:GetPartBoundsInRadius(centre, weapon.range * 0.7, params)

	local seen: { [Model]: boolean } = {}
	local hits = 0

	for _, part in parts do
		local humanoid, targetModel = CombatService.resolveTarget(part)
		if not humanoid or not targetModel or seen[targetModel] then
			continue
		end
		seen[targetModel] = true

		if not CombatService.canDamage(character, targetModel) then
			continue
		end

		-- Must be in front: a 180-degree arc, so you cannot hit what is behind you.
		local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			local toTarget = (targetRoot.Position - root.Position)
			if root.CFrame.LookVector:Dot(toTarget.Unit) < 0 then
				continue
			end
		end

		local isCrit = math.random() < critChance
		local amount = weapon.damage * damageMult
		if isCrit then
			amount *= critMult
		end

		CombatService.applyDamage(targetModel, {
			amount = amount,
			source = character,
			attacker = attacker,
			damageType = if weapon.class == "Saber" then "Saber" else "Melee",
			position = targetRoot and targetRoot.Position or centre,
			isCritical = isCrit,
		})
		hits += 1
	end

	return hits
end

--------------------------------------------------------------------------------
-- NPC entry points
--------------------------------------------------------------------------------

--[[
	Fires an NPC's weapon at a target position.

	NPC accuracy is a property of the archetype, not of aim: `spreadMult` widens
	the cone. That is how a stormtrooper misses convincingly instead of the AI
	having to pretend to be bad at maths.
]]
function CombatService.npcFire(npc: Model, weaponId: string, targetPosition: Vector3, spreadMult: number?)
	local weapon = Weapons.get(weaponId)
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local origin = root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 1, 0)
	local aim = (targetPosition - origin).Unit

	local spread = math.rad(weapon.spread * (spreadMult or 1))
	if spread > 0 then
		local yaw = (math.random() - 0.5) * 2 * spread
		local pitch = (math.random() - 0.5) * 2 * spread
		aim = (CFrame.lookAt(Vector3.zero, aim) * CFrame.Angles(pitch, yaw, 0)).LookVector
	end

	CombatService.resolveShot(npc, weaponId, origin, aim, nil, nil)
	Net.fireAllClients(Net.Event.WeaponEffect, weaponId, origin, aim)
end

function CombatService.npcMelee(npc: Model, weaponId: string)
	CombatService.swingMelee(npc, weaponId, nil, nil)
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Net.fireAllClients(Net.Event.WeaponEffect, weaponId, root.Position, root.CFrame.LookVector, npc)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CombatService.init()
	Net.onServerEvent(Net.Event.FireWeapon, onFireWeapon, {
		-- Above any real weapon's fire rate; the per-weapon cooldown above is
		-- the real limit. This only stops a flood from costing us CPU.
		rateLimit = 25,
		validate = Net.args(Net.check.vector3(100000), Net.check.vector3(2)),
	})

	Net.onServerEvent(Net.Event.SaberSwing, onSaberSwing, {
		rateLimit = 8,
		validate = Net.check.none,
	})

	Net.onServerEvent(Net.Event.EquipWeapon, function(player: Player, uid: string)
		local profile = data().get(player)
		if not profile then
			return
		end
		-- The client names a carried stack, not a catalogue entry, so a rolled
		-- blaster equips as itself rather than as the idea of a DH17.
		local weaponId = Inventory.idOf(profile.inventory, uid)
		if not weaponId or not Weapons.exists(weaponId) then
			return
		end
		-- Owned means "this exact stack is in the bag". Fists are the
		-- exception: always available, never carried.
		if uid ~= Weapons.DEFAULT and not profile.inventory[uid] then
			Net.fireClient(Net.Event.Notify, player, "You do not have that weapon", "Error")
			return
		end
		data().update(player, function(p)
			p.equipped.weapon = uid
		end)
		-- A weapon can carry rolled affixes, so swapping one changes the
		-- player's stats the same way changing an outfit does.
		progression().invalidate(player)

		if player.Character then
			WeaponModel.equip(player.Character, weaponId)
		end
	end, {
		rateLimit = 4,
		validate = Net.args(Net.check.string(64)),
	})
end

function CombatService.start()
	Players.PlayerRemoving:Connect(function(player)
		lastFireAt[player] = nil
		lastSwingAt[player] = nil
	end)

	-- A fresh character has empty hands. Re-equip what the profile says is
	-- held, so the weapon survives death and travel without the client asking.
	ServiceLoader.get("PlayerService").characterReady
		:connect(function(_player: Player, character: Model, profile)
			local weaponId = Inventory.idOf(profile.inventory, profile.equipped.weapon)
			if weaponId and Weapons.exists(weaponId) then
				WeaponModel.equip(character, weaponId)
			end
		end)
end

return CombatService
