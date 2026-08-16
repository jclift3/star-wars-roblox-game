--!strict
--[[
	Types.luau

	Shared type vocabulary. Kept in one module so server and client agree on the
	shape of anything that crosses the network boundary.
]]

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
	faction: string,
	factionRep: { [string]: number },
	homePlanet: string,
	currentPlanet: string,
	-- os.time of the last jump, so a travel cooldown survives a rejoin rather
	-- than being cleared by one.
	lastTravelAt: number,
	inventory: { [string]: number },
	equipped: { weapon: string?, offhand: string?, outfit: string? },
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
