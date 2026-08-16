--!strict
--[[
	MissionKinds.luau

	The shape of a mission: objective kinds and the three types.

	WHY THIS IS NOT IN Missions.luau
	It was, and by rights it should be -- but `Radiant.luau` generates
	MissionDefs and `Missions` has to resolve generated ids back through it, so
	the two require each other. Cycles in Luau resolve to nil at require time,
	which is a crash at boot with a stack that names neither culprit.

	Splitting the *shape* out breaks the cycle: both sides require this, and
	this requires nothing. `Missions` re-exports every name below, so no caller
	needs to know the split happened.
]]

local MissionKinds = {}

--- Canonical objective kinds. MissionService switches on exactly these.
local Objective: { [string]: string } = {
	Kill = "Kill", -- kill `count` NPCs of archetype `target`
	Collect = "Collect", -- pick up `count` of item `target`
	TalkTo = "TalkTo", -- speak to the NPC tagged `target`
	Reach = "Reach", -- enter the point of interest `target`
	Deliver = "Deliver", -- carry item `target` to NPC/POI `destination`
	Escort = "Escort", -- keep NPC `target` alive to `destination`
	Survive = "Survive", -- stay alive `count` seconds in `target` zone
	Slice = "Slice", -- slice terminal `target`; needs the Slicer skill
	Destroy = "Destroy", -- destroy `count` of object `target`
}
MissionKinds.Objective = Objective

-- Set form, for validating a kind that arrives as a plain string.
local VALID_KINDS: { [string]: boolean } = {}
for _, kind in Objective do
	VALID_KINDS[kind] = true
end
MissionKinds.VALID_KINDS = VALID_KINDS

export type ObjectiveDef = {
	kind: string,
	target: string?,
	destination: string?,
	-- Point of interest where this objective's work happens. Required for
	-- Collect: it is where PickupService puts the items, and without it the
	-- objective is a scavenger hunt across 3000 studs with no clue attached.
	at: string?,
	count: number?,
	planet: string?,
	description: string,
	-- Hidden objectives are not shown until a prior one completes, so a twist
	-- stays a twist instead of being spoiled by the tracker.
	hidden: boolean?,
	optional: boolean?,
}

export type Rewards = {
	xp: number,
	credits: number,
	rep: { [string]: number }?,
	items: { [string]: number }?,
	weapon: string?,
	skillPoints: number?,
}

export type MissionDef = {
	id: string,
	displayName: string,
	summary: string,
	-- Flavour shown by the giver when the mission is offered.
	briefing: string,
	-- Shown on turn-in. Worth writing: it is the only payoff for reading.
	debriefing: string?,

	kind: string, -- "Story" | "Side" | "Bounty" | "Delivery" | "Repeatable"
	faction: string,
	planet: string,
	giver: string, -- NPC archetype id, or a named NPC tag

	minLevel: number,
	requiredRep: number?, -- with `faction`
	requires: { string }?, -- mission ids that must be completed first

	objectives: { ObjectiveDef },
	rewards: Rewards,

	repeatable: boolean?,
	cooldown: number?, -- seconds before a repeatable can be retaken
	timeLimit: number?, -- seconds; nil = untimed
	next: string?, -- follow-up mission id
}

return MissionKinds
