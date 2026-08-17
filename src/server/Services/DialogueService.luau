--!strict
--[[
	DialogueService.luau

	Runs conversations. One at a time, per player, entirely on the server.

	WHY THE SERVER HOLDS THE CONVERSATION
	The client is sent a node and a list of choices, and answers with an index
	into that list -- not a node id, not an action name. So a client can only
	ever pick something it was actually offered, and the whole class of "select
	the accept-mission branch without meeting the condition" simply does not
	arise. The session is the authority on what was on screen.

	IT STARTS FROM THE WORLD, NOT FROM A KEYPRESS
	NPCService already owns the proximity prompt on every interactable NPC and
	fires `interacted` when it is triggered. This service listens there. There
	is no client-callable "start talking to that model" remote, so there is
	nothing to spoof a range check against.

	MISSION OFFERS ARE DERIVED
	The Work action builds its choices from Missions.boardFor, filtered to the
	missions this archetype gives. Adding a mission with `giver = "Merchant"`
	makes every merchant in the galaxy offer it, with no dialogue edit -- the
	same reason PickupService reads its spawn table out of the missions rather
	than keeping a second copy.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cast = require(Shared.Config.Cast)
local Dialogue = require(Shared.Config.Dialogue)
local Flags = require(Shared.Config.Flags)
local Missions = require(Shared.Config.Missions)
local NPCArchetypes = require(Shared.Config.NPCArchetypes)
local Net = require(Shared.Core.Net)
local Origins = require(Shared.Config.Origins)
local Progression = require(Shared.Config.Progression)
local ServiceLoader = require(Shared.Core.ServiceLoader)
local Shops = require(Shared.Config.Shops)

local DialogueService = {
	name = "DialogueService",
	priority = 56,
}

local Action = Dialogue.Action

-- Walking away ends the conversation. Generous enough that turning on the spot
-- or being nudged by a passer-by does not close the panel mid-sentence.
local TALK_RANGE = 26

-- Generated node ids. Authored ids may not start with "@", so these cannot
-- collide with anything in Dialogue.luau.
local NODE_WORK = "@work"
local NODE_OFFER = "@offer:"

--[[
	A choice as the server knows it. The client is told `text` and `kind`; the
	rest is how the selection is carried out and never leaves this machine.
]]
type Resolved = {
	text: string,
	kind: string?, -- styling hint for the client
	next: string?,
	action: string?,
	missionId: string?,
	-- Carried through the session rather than re-read from the tree on
	-- selection: the client answers with an index, so the only honest source
	-- for what that index costs is the list the server actually sent.
	alignment: number?,
	sets: { string }?,
}

type Session = {
	npc: Model,
	archetypeId: string,
	speaker: string,
	--[[
		Whose missions this speaker offers, and what the panel calls them.

		Both are the archetype for a crowd NPC and the cast member for a named
		one. They are stored rather than recomputed because a session outlives
		the model lookup, and because `giverId` is what the whole Work branch
		matches on -- deriving it twice is how the board and the conversation
		end up disagreeing about who gives what.
	]]
	giverId: string,
	title: string,
	faction: string,
	treeId: string,
	nodeId: string,
	choices: { Resolved },
}

local sessions: { [Player]: Session } = {}
local rng = Random.new()

local function data()
	return ServiceLoader.get("DataService")
end

local function missions()
	return ServiceLoader.get("MissionService")
end

local function progression()
	return ServiceLoader.get("ProgressionService")
end

--------------------------------------------------------------------------------
-- Building a node
--------------------------------------------------------------------------------

--- Missions this speaker gives that the player could take right now.
local function offersFor(profile: any, giverId: string): { Missions.MissionDef }
	local out: { Missions.MissionDef } = {}
	for _, entry in Missions.boardFor(profile.currentPlanet, profile, os.time()) do
		if entry.mission.giver == giverId and not entry.locked then
			table.insert(out, entry.mission)
		end
	end
	return out
end

--[[
	Turns an authored node's choices into the list the player may pick from.

	Two filters beyond the authored condition, both expressing something the
	config cannot know about itself: a Trade line is dropped when the speaker
	keeps no shop, and a Work line is dropped when they have nothing to offer.
	Offering a button that answers "actually, no" is worse than not offering it.
]]
local function resolveChoices(
	player: Player,
	profile: any,
	session: Session,
	node: Dialogue.Node
): { Resolved }
	local out: { Resolved } = {}
	local archetype = NPCArchetypes.get(session.archetypeId)

	local ctx: Dialogue.Context = {
		origin = profile.origin,
		level = profile.level,
		rep = profile.factionRep[session.faction] or 0,
		alignment = profile.alignment,
		flags = profile.flags,
		activeMissions = profile.missions.active,
		completedMissions = profile.missions.completed,
		-- Skills folded together with the equipped outfit, which is why this
		-- comes from ProgressionService rather than off the profile: it is
		-- the same table combat reads, so a line that says "you could open
		-- that" cannot be shown to somebody who could not.
		stats = progression().getStats(player),
	}

	local authored: { Dialogue.Choice } = node.choices or {}
	for _, choice in authored do
		if not Dialogue.meets(choice.condition, ctx) then
			continue
		end
		if choice.action == Action.Shop then
			local shopId = archetype.shop
			if not shopId or not Shops.exists(shopId) then
				continue
			end
		end
		if choice.action == Action.Work and #offersFor(profile, session.giverId) == 0 then
			continue
		end

		table.insert(out, {
			text = choice.text,
			kind = choice.action,
			next = choice.next,
			action = choice.action,
			alignment = choice.alignment,
			sets = choice.sets,
		})
	end

	return out
end

--- The generated node listing everything this speaker has going.
local function workNode(profile: any, session: Session): (string, { Resolved })
	local available = offersFor(profile, session.giverId)
	if #available == 0 then
		return "There is nothing I need doing right now. Come back another time.",
			{
				{ text = "Understood.", action = Action.Leave },
			}
	end

	local choices: { Resolved } = {}
	for _, mission in available do
		table.insert(choices, {
			text = mission.displayName,
			kind = "Mission",
			next = NODE_OFFER .. mission.id,
			missionId = mission.id,
		})
	end
	table.insert(choices, { text = "Not today.", action = Action.Leave })

	return "As it happens, yes. Depends what you are willing to do.", choices
end

--- The generated node that reads a mission's briefing and offers to take it.
local function offerNode(missionId: string): (string, { Resolved })
	local mission = Missions.get(missionId)
	return mission.briefing,
		{
			{ text = "I will take it.", kind = "Accept", action = Action.Leave, missionId = missionId },
			{ text = "Tell me about the others.", next = NODE_WORK },
			{ text = "Not interested.", action = Action.Leave },
		}
end

--------------------------------------------------------------------------------
-- Session
--------------------------------------------------------------------------------

local function finish(player: Player, reason: string?)
	if not sessions[player] then
		return
	end
	sessions[player] = nil
	Net.fireClient(Net.Event.EndDialogue, player, reason)
end

--- Whether the player is still standing in front of the person they are talking to.
local function inRange(player: Player, session: Session): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local npcRoot = session.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not npcRoot or not session.npc.Parent then
		return false
	end
	local humanoid = session.npc:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (npcRoot.Position - root.Position).Magnitude <= TALK_RANGE
end

--[[
	Sends `nodeId` to the player and records what they were offered.

	Generated nodes are handled first because they have no entry in the tree.
	Everything after that is the authored path.
]]
local function goTo(player: Player, session: Session, nodeId: string)
	local profile = data().get(player)
	if not profile then
		finish(player)
		return
	end

	local line: string
	local choices: { Resolved }

	if nodeId == NODE_WORK then
		line, choices = workNode(profile, session)
	elseif string.sub(nodeId, 1, #NODE_OFFER) == NODE_OFFER then
		local missionId = string.sub(nodeId, #NODE_OFFER + 1)
		if not Missions.exists(missionId) then
			finish(player)
			return
		end
		line, choices = offerNode(missionId)
	else
		local tree = Dialogue.get(session.treeId)
		local node = tree.nodes[nodeId]
		if not node then
			warn(`[DialogueService] {session.treeId} has no node "{nodeId}"`)
			finish(player)
			return
		end
		line = node.lines[rng:NextInteger(1, #node.lines)]
		choices = resolveChoices(player, profile, session, node)
	end

	-- A node whose every choice was filtered out would otherwise leave the
	-- player staring at a panel with no way out but Escape.
	if #choices == 0 then
		table.insert(choices, { text = "Goodbye.", action = Action.Leave })
	end

	session.nodeId = nodeId
	session.choices = choices

	local wire = {}
	for _, choice in choices do
		table.insert(wire, { text = choice.text, kind = choice.kind })
	end

	Net.fireClient(Net.Event.StartDialogue, player, {
		speaker = session.speaker,
		title = session.title,
		text = line,
		choices = wire,
	})
end

--- Opens a conversation with `npc`. Called from NPCService's proximity prompt.
function DialogueService.begin(player: Player, npc: Model, archetypeId: string)
	if not NPCArchetypes.exists(archetypeId) then
		return
	end
	local archetype = NPCArchetypes.get(archetypeId)

	-- Set by NPCService on a named character. Everything about the speaker
	-- except the body they wear comes from the cast entry when it is there.
	local castId = npc:GetAttribute("Cast")
	local cast = if type(castId) == "string" and Cast.exists(castId) then Cast.get(castId) else nil

	local treeId = if cast then cast.dialogue else archetype.dialogue
	if not treeId or not Dialogue.exists(treeId) then
		return
	end
	local profile = data().get(player)
	if not profile then
		return
	end

	local session: Session = {
		npc = npc,
		archetypeId = archetypeId,
		speaker = npc.Name,
		giverId = if cast then cast.id else archetypeId,
		title = if cast then cast.title else archetype.displayName,
		faction = archetype.faction,
		treeId = treeId,
		nodeId = "",
		choices = {},
	}
	sessions[player] = session

	if not inRange(player, session) then
		finish(player)
		return
	end

	goTo(player, session, Dialogue.rootOf(Dialogue.get(treeId)))
end

--- Acts on the player's pick. `index` is into the list they were last sent.
function DialogueService.choose(player: Player, index: number)
	local session = sessions[player]
	if not session then
		return
	end
	if not inRange(player, session) then
		finish(player, "OutOfRange")
		return
	end

	local choice = session.choices[index]
	if not choice then
		return
	end

	--[[
		The consequence lands before anything else the choice does.

		A branch that walks on to another node would otherwise build that
		node's context from the profile as it was a moment ago, so a line
		conditioned on the flag you just set would not appear until the next
		conversation -- which reads as the flag not working.
	]]
	if choice.alignment or choice.sets then
		progression().awardAlignment(player, choice.alignment or 0, choice.sets)
	end

	-- Accepting is done before the panel closes so the refusal, if there is
	-- one, reaches the player while they are still looking at the speaker.
	if choice.missionId and choice.action == Action.Leave then
		local ok, reason = missions().accept(player, choice.missionId)
		if not ok and reason then
			Net.fireClient(Net.Event.Notify, player, reason, "Error")
		end
	end

	if choice.next then
		goTo(player, session, choice.next)
		return
	end

	finish(player, choice.action)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function DialogueService.init()
	local function statIsLive(stat: string): boolean
		return Progression.LIVE_STATS[stat] ~= nil
	end
	for _, problem in Dialogue.validate(Missions.exists, Origins.exists, Flags.exists, statIsLive) do
		warn(`[DialogueService] dialogue config: {problem}`)
	end

	-- Checked here rather than in Cast itself: Dialogue is the one config the
	-- cast could not require without closing a cycle, since its trees are
	-- written for the cast and the cast names its trees.
	for _, problem in Cast.validate(Dialogue.exists) do
		warn(`[DialogueService] cast config: {problem}`)
	end

	--[[
		Every archetype that can be spoken to needs something to say. Without
		this the prompt appears, the player presses E, and nothing happens --
		which reads as a broken game rather than a quiet NPC.
	]]
	for id, archetype in NPCArchetypes.defs do
		if not archetype.interactable then
			continue
		end
		if not archetype.dialogue then
			warn(`[DialogueService] archetype "{id}" is interactable with no dialogue tree`)
		elseif not Dialogue.exists(archetype.dialogue) then
			warn(`[DialogueService] archetype "{id}" names unknown tree "{archetype.dialogue}"`)
		end
	end

	Net.onServerEvent(Net.Event.DialogueChoice, function(player: Player, index: number)
		DialogueService.choose(player, index)
	end, {
		rateLimit = 6,
		validate = Net.args(Net.check.integer(1, 32)),
	})

	Net.onServerEvent(Net.Event.EndDialogue, function(player: Player)
		finish(player)
	end, { rateLimit = 6, validate = Net.check.none })
end

function DialogueService.start()
	ServiceLoader.get("NPCService").interacted
		:connect(function(player: Player, npc: Model, archetypeId: string)
			DialogueService.begin(player, npc, archetypeId)
		end)

	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)
end

return DialogueService
