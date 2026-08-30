--!strict
--[[
	ClientState.luau

	The client's copy of the player's profile.

	The server sends the whole profile whenever anything in it changes, and
	every other controller reads it from here rather than invoking the server.
	That is the point: a HUD that asks the server for the credit balance every
	frame is both slow and wrong, because the answer is already in flight.

	This copy is advisory. Nothing here is trusted by the server -- it exists so
	the interface can be drawn and so input can be sensible about which weapon
	the player is holding.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Core.Net)
local Signal = require(Shared.Core.Signal)
local Inventory = require(Shared.Core.Inventory)

local ClientState = {
	name = "ClientState",
	priority = 1,
}

export type Profile = {
	credits: number,
	level: number,
	xp: number,
	skillPoints: number,
	skills: { [string]: number },
	origin: string,
	originChosen: boolean,
	alignment: number,
	flags: { [string]: boolean },
	faction: string,
	factionRep: { [string]: number },
	currentPlanet: string,
	homePlanet: string,
	inventory: Inventory.Inventory,
	equipped: { weapon: string?, offhand: string?, outfit: string?, ship: string? },
	unlockedShips: { string },
	shipDamage: { [string]: number },
	missions: {
		active: {
			[string]: { missionId: string, startedAt: number, objectives: { [number]: number }, stage: number },
		},
		completed: { [string]: number },
		lastCompleted: { [string]: number },
	},
	stats: { [string]: number },
}

local profile: Profile? = nil

ClientState.changed = Signal.new()

function ClientState.get(): Profile?
	return profile
end

--[[
	The equipped weapon's *catalogue* id, or nil while the profile is loading.

	`equipped.weapon` names a stack, which for a rolled blaster is `DH17#2`.
	Callers want the entry in `Config.Weapons` that says how it shoots, so the
	resolution happens once here rather than at every call site.
]]
function ClientState.equippedWeapon(): string?
	local p = profile
	return p and Inventory.idOf(p.inventory, p.equipped.weapon)
end

--- What the equipped weapon rolled, if anything. Nil for a plain one.
function ClientState.equippedWeaponRolls(): Inventory.Rolls?
	local p = profile
	return p and Inventory.rollsOf(p.inventory, p.equipped.weapon)
end

function ClientState.init()
	Net.onClientEvent(Net.Event.ProfileUpdated, function(view: Profile)
		profile = view
		ClientState.changed:fire(view)
	end)
end

function ClientState.start()
	-- The push above covers every later change, but a client that joins after
	-- the profile has already loaded would otherwise wait for the next one.
	task.spawn(function()
		local view = Net.invokeServer(Net.Function.GetProfile)
		if view and not profile then
			profile = view
			ClientState.changed:fire(view)
		end
	end)
end

return ClientState
