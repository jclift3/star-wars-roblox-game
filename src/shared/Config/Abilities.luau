--!strict
--[[
	Abilities.luau

	The verbs. Things a skill point can buy that are not a percentage.

	WHY THIS EXISTS
	ROADMAP 4.3, target 1. Nineteen skills across four trees and every one of
	them was a flat linear passive -- `+6% blaster damage per rank`, `+15 HP
	per rank`. A tree made only of those has no decisions in it: every point is
	worth the same as every other point, so at level 40 two players who chose
	differently have the same character with the numbers in a different order.

	One skill already admitted the gap. `ForcePush` said "Unlocks Force Push"
	and was marked `unimplemented` because there was nowhere for a power to
	live. This file is that place.

	WHAT AN ABILITY IS
	A cooldown, optionally a cost, and one of three shapes. Deliberately three
	and not one-per-ability: a service with a branch per ability becomes a
	service nobody can add to, and every verb worth having so far is a cone in
	front of you, a thing thrown at a point, or something that happens around
	you.

	THE SAME HONESTY RULE AS SKILLS
	`unimplemented` means exactly what it means in `Progression.luau`, and
	`validate` refuses an ability whose stats or node do not exist. An ability
	on the bar that does nothing when pressed is worse than one that is not
	there, because the player paid a skill point for it.

	AUTHORITY
	Nothing here is enforcement -- it is a description, and the client has it
	too so it can draw the bar. `AbilityService` re-checks every field of it
	server-side before anything happens. See the note at the top of that file.
]]

local Abilities = {}

--[[
	How an ability finds what it affects.

	`Cone`   -- forward from the caster, `range` long, `angle` degrees wide.
	            A narrow one is a single-target beam; a wide one is a shove.
	`Point`  -- at the spot the caster is aiming at, up to `range` away,
	            affecting everything within `radius`. `fuse` delays it.
	`Aura`   -- centred on the caster, `radius` wide. The only shape that can
	            reach a *teammate*, which is why the two heals use it.
]]
local Shape: { [string]: string } = {
	Cone = "Cone",
	Point = "Point",
	Aura = "Aura",
}
Abilities.Shape = Shape

export type AbilityDef = {
	id: string,
	displayName: string,
	--- One line, shown on the bar's tooltip and in the skill panel.
	description: string,

	--[[
		The skill node that unlocks it, which must be at rank 1 or better.

		An ability is never bought directly: it is what a *node* is worth, so
		the tree stays the one place a player spends points. The node's rank
		then scales it through `scaleStat`, which is what stops rank 2-5 of an
		unlock node from being the dead weight they would otherwise be.
	]]
	node: string,

	shape: string,
	--- Seconds before it can be used again. Server clock, always.
	cooldown: number,
	--[[
		Force energy spent per use, or nil for an ability that costs only its
		cooldown.

		Only Force abilities cost anything. A Scoundrel does not have a
		mystical resource and giving him one to keep the systems symmetrical
		would be a bar with a meter on it that means nothing. The asymmetry is
		paid for the other way: Force abilities hit harder.
	]]
	forceCost: number?,

	--- Cone: how far it reaches. Point: how far away it may be aimed.
	range: number,
	--- Point/Aura: how wide the effect is. Unused by Cone.
	radius: number?,
	--- Cone only: half-angle in degrees, so 35 is a 70-degree fan.
	angle: number?,
	--- Point only: seconds between the throw and the bang.
	fuse: number?,

	damage: number?,
	--- Defaults to "Force". Only `deflects` reads this, and only for "Blaster".
	damageType: string?,
	--- Impulse applied to whatever it hits, in studs per second.
	knockback: number?,
	--- Aura only: health restored to the caster and to allies in radius.
	heal: number?,

	--[[
		The stat that scales this ability's numbers, from `Progression`.

		One stat per ability rather than separate damage/heal/knockback
		multipliers: an ability is one thing and its rank should make all of
		it better. The stat is what the unlocking node's `effect` moves.
	]]
	scaleStat: string,

	unimplemented: string?,
}

local defs: { [string]: AbilityDef } = {}
local order: { string } = {}

local function def(a: AbilityDef): AbilityDef
	defs[a.id] = a
	table.insert(order, a.id)
	return a
end

--------------------------------------------------------------------------------
-- Force
--------------------------------------------------------------------------------

--[[
	The oldest verb in the setting, and the one skill in the game that has
	been promising itself since the tree was written.

	Wide and short: it is a shove, not a beam. The damage is small on purpose
	-- what it is for is putting three metres between you and the four people
	who just walked around the corner, and an ability that both saves you and
	kills them is the only ability anyone would ever press.
]]
def({
	id = "ForcePush",
	displayName = "Force Push",
	description = "Hurls everything in front of you backwards.",
	node = "ForcePush",
	shape = Shape.Cone,
	cooldown = 8,
	forceCost = 25,
	range = 42,
	angle = 35,
	damage = 18,
	knockback = 95,
	scaleStat = "PushPower",
})

--[[
	The dark half of the fork, and gated on the *node*, not here.

	Putting the alignment bound on the ability would let a light character buy
	the skill and then be refused every time they pressed it -- a point spent
	on nothing, which is the exact failure `Progression.validate` exists to
	prevent. `SkillNode.maxAlignment` refuses the purchase instead.
]]
def({
	id = "ForceLightning",
	displayName = "Force Lightning",
	description = "A single arc, and whatever it touches stops moving.",
	node = "ForceLightning",
	shape = Shape.Cone,
	-- A 10-degree half-angle at 60 studs is a line. Reusing Cone rather than
	-- adding a fourth shape for one ability: a beam *is* a very narrow cone,
	-- and the alternative is a target the client picks and the server trusts.
	cooldown = 10,
	forceCost = 40,
	range = 60,
	angle = 10,
	damage = 70,
	scaleStat = "ForceDamageMult",
})

--[[
	The light half. Heals you and anyone standing with you.

	It is an `Aura` rather than a targeted heal because there is no friendly
	targeting in this game and adding one for a single ability would be a
	worse feature than "stand near your brother". That constraint turned out
	to be the design: the light branch is the one that rewards being close to
	somebody, which is ROADMAP 4.3's co-op target arriving for free.
]]
def({
	id = "ForceMend",
	displayName = "Force Mend",
	description = "Knits you and everyone near you back together.",
	node = "ForceMend",
	shape = Shape.Aura,
	cooldown = 14,
	forceCost = 45,
	range = 0,
	radius = 26,
	heal = 55,
	scaleStat = "HealPower",
})

--------------------------------------------------------------------------------
-- Combat
--------------------------------------------------------------------------------

--[[
	The non-Force answer to a room with six people in it.

	`fuse` is the whole design: it lands where you aimed and then waits, so
	throwing it is a prediction rather than a click. That is also what keeps it
	from being a better blaster -- against one moving target it is worse.
]]
def({
	id = "FragGrenade",
	displayName = "Frag Grenade",
	description = "Lobbed, then a second and a half of regret.",
	node = "Grenadier",
	shape = Shape.Point,
	cooldown = 12,
	range = 90,
	radius = 20,
	fuse = 1.4,
	damage = 75,
	damageType = "Explosive",
	knockback = 40,
	scaleStat = "ExplosiveDamageMult",
})

--------------------------------------------------------------------------------
-- Engineering
--------------------------------------------------------------------------------

--[[
	A heal with no Force behind it, so the three origins who will never open
	that tree still have one.

	Weaker and slower than `ForceMend` and costs nothing but the wait, which
	is the trade the whole non-Force side of the game runs on.
]]
def({
	id = "FieldStim",
	displayName = "Field Stim",
	description = "A shot for you and anyone bleeding next to you.",
	node = "FieldStim",
	shape = Shape.Aura,
	cooldown = 20,
	range = 0,
	radius = 26,
	heal = 40,
	scaleStat = "HealPower",
})

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

Abilities.defs = defs

--- Ability ids in declaration order, which is the order the bar draws them in.
function Abilities.ids(): { string }
	return table.clone(order)
end

function Abilities.exists(id: string): boolean
	return defs[id] ~= nil
end

function Abilities.get(id: string): AbilityDef
	local a = defs[id]
	assert(a, `Abilities.get: unknown ability "{id}"`)
	return a
end

--[[
	The abilities a set of purchased skills has unlocked, in bar order.

	Takes the skill map rather than a profile so both sides can call it: the
	client draws the bar from `ClientState`, the server checks a request
	against `profile.skills`, and there is one definition of "unlocked".
]]
function Abilities.unlockedBy(skills: { [string]: number }): { string }
	local out: { string } = {}
	for _, id in order do
		local a = defs[id]
		if not a.unimplemented and (skills[a.node] or 0) >= 1 then
			table.insert(out, id)
		end
	end
	return out
end

--[[
	Faults in this file. Cross-checked against the skill tree, which is the
	half this module cannot see on its own.

	Called from `AbilityService.init` -- the server is where a boot warning is
	read, and an ability that names a node nobody can buy is a button that
	never appears with nothing anywhere saying why.
]]
function Abilities.validate(
	nodeExists: (string) -> boolean,
	statExists: (string) -> boolean,
	statIsLive: (string) -> boolean
): { string }
	local problems: { string } = {}

	for _, id in order do
		local a = defs[id]

		if not nodeExists(a.node) then
			table.insert(problems, `{id}: unlocked by "{a.node}", which is not a skill`)
		end
		if not statExists(a.scaleStat) then
			table.insert(problems, `{id}: scales on "{a.scaleStat}", which is not a stat`)
		elseif not statIsLive(a.scaleStat) and not a.unimplemented then
			table.insert(problems, `{id}: nothing reads "{a.scaleStat}"`)
		end

		if Shape[a.shape] == nil then
			table.insert(problems, `{id}: unknown shape "{a.shape}"`)
		end
		if a.cooldown <= 0 then
			table.insert(problems, `{id}: cooldown is {a.cooldown}, so it can be held down`)
		end

		-- An ability that neither hurts nor heals is a button that plays a
		-- sound. Knockback alone would count, so it is named here too.
		if not a.damage and not a.heal and not a.knockback then
			table.insert(problems, `{id}: does no damage, no healing and no knockback`)
		end

		if a.shape == Shape.Cone then
			if not a.angle then
				table.insert(problems, `{id}: is a Cone with no angle`)
			end
			if a.range <= 0 then
				table.insert(problems, `{id}: is a Cone with no range`)
			end
		elseif not a.radius or a.radius <= 0 then
			table.insert(problems, `{id}: is a {a.shape} with no radius`)
		end

		-- A heal that reaches enemies would make an ally-only shape pointless
		-- and a damaging aura centred on yourself is a different ability.
		if a.shape == Shape.Aura and a.damage then
			table.insert(problems, `{id}: is an Aura that deals damage, which would hit your own side`)
		end
	end

	return problems
end

return Abilities
