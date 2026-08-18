--!strict
--[[
	Types.luau

	Shared type vocabulary. Kept in one module so server and client agree on the
	shape of anything that crosses the network boundary.
]]

local Inventory = require(script.Parent.Core.Inventory)

--[[
	A single procedurally built cosmetic part welded onto a rig limb.

	Sizes are RELATIVE to the limb by default (`scale`), not absolute studs.
	That is deliberate: HumanoidDescription scaling resizes the underlying limb
	parts at runtime, so a Wookiee's chest plate has to grow with his chest.
	Absolute `size` exists only for held props (blasters, saber hilts) that
	should stay a fixed real-world size regardless of who is holding them.

	`offset` is likewise a FRACTION of the limb's size, so a pauldron sitting at
	offset.Y = 0.5 stays at the top of the shoulder on every body plan.
]]
export type CosmeticPart = {
	name: string,
	limb: string,
	shape: string?, -- "Block" | "Ball" | "Cylinder" | "Wedge"
	scale: Vector3?, -- multiple of the limb's size
	size: Vector3?, -- absolute studs; overrides `scale`
	offset: Vector3?, -- limb-local, as a fraction of limb size
	rot: Vector3?, -- limb-local euler rotation, in degrees
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	canCollide: boolean?,
	light: { color: Color3, range: number, brightness: number }?,
}

export type SkillId = "Combat" | "Piloting" | "Force" | "Engineering"

export type PlayerProfile = {
	version: number,
	credits: number,
	level: number,
	xp: number,
	skillPoints: number,
	skills: { [string]: number },
	-- The character's background: picks the skill tree, the home world, and who
	-- is willing to fly them anywhere. See Config/Origins.luau.
	origin: string,
	-- Whether the player picked that origin or merely has the default. Without
	-- a separate flag the two are indistinguishable, so the creation screen
	-- would either never appear or appear again for anyone who chose the
	-- default on purpose.
	originChosen: boolean,
	--[[
		-1000 to +1000, moved by what the character chooses rather than by what
		they kill. Deliberately not derivable from `factionRep`: see
		Config/Alignment.luau for why the two have to be able to disagree.
	]]
	alignment: number,
	--[[
		Things this character has done that the world is allowed to remember.

		A map rather than an array for the same reason `inventory` is: a
		profile is DataStore-serialised and replicated, and neither survives a
		sparse array. Keys are declared in Config/Flags.luau -- an undeclared
		one is a condition that can never be true and no error anywhere.
	]]
	flags: { [string]: boolean },
	faction: string,
	factionRep: { [string]: number },
	-- Highest rank index each faction has already paid a stipend for. Rep can
	-- fall and be earned again, so without this a player could yo-yo one
	-- faction's standing across a threshold and be paid for the promotion
	-- every time.
	factionRankPaid: { [string]: number },
	homePlanet: string,
	currentPlanet: string,
	-- os.time of the last jump, so a travel cooldown survives a rejoin rather
	-- than being cleared by one.
	lastTravelAt: number,
	-- Stacks keyed by uid, not a bag of counts: see Core/Inventory.luau, and
	-- change it only through that module.
	inventory: Inventory.Inventory,
	equipped: { weapon: string?, offhand: string?, outfit: string?, ship: string? },
	-- Plain ids, not inventory stacks: a speeder cannot be dropped, sold or
	-- rolled with affixes, so it never needs a uid and must never count
	-- against the bag cap. `equipped.ship` names which of these the summon
	-- key calls in.
	unlockedShips: { string },
	missions: {
		active: { [string]: MissionProgress },
		completed: { [string]: number }, -- missionId -> completion count
		lastCompleted: { [string]: number }, -- missionId -> os.time of last turn-in
	},
	stats: {
		playtime: number,
		kills: number,
		deaths: number,
		missionsCompleted: number,
		lightYearsTravelled: number,
	},
	createdAt: number,
	lastSeen: number,
}

export type MissionProgress = {
	missionId: string,
	startedAt: number,
	objectives: { [number]: number }, -- objective index -> current count
	stage: number,
}

export type DamageInfo = {
	amount: number,
	source: Instance?,
	attacker: Player?,
	damageType: string, -- "Blaster" | "Saber" | "Melee" | "Explosive" | "Environment"
	position: Vector3?,
	isCritical: boolean?,
}

return {}
