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
local Personas = require(Shared.Config.Personas)
local Progression = require(Shared.Config.Progression)
local Secrets = require(Shared.Config.Secrets)
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
	-- Never sent to the client. See the note on `Dialogue.Choice.topic`: a
	-- line the panel marked as load-bearing would stop being a question.
	topic: string?,
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
	-- The line last sent. Kept only so that opening the text box can leave it
	-- on screen: the character should not have to say something new to be
	-- asked a question, and any line written for that moment would be written
	-- in one of the six voices and wrong in the other five.
	line: string,
	choices: { Resolved },
	--[[
		Free-form state. Lives here rather than in ConverseService for the
		reason SecretService takes its context as an argument: this session is
		already the record of what is happening in front of this NPC, and a
		second one keyed by player would have to be torn down in all the same
		places -- walking away, dying, the server closing -- and would
		eventually miss one.
	]]
	asking: boolean,
	turns: number,
	-- Declared here rather than imported from ConverseService: services reach
	-- each other through ServiceLoader in this codebase, and a `require` of a
	-- sibling service purely to borrow a two-field type would be the first
	-- one. The shape is checked where it matters, at the JSON encoder.
	history: { { role: string, text: string } },
	--[[
		A turn is in flight.

		Not a nicety: every turn costs money, and the rate limiter in Net
		allows a burst. Without this a client that fires the remote three
		times in a second buys three calls to answer one question.
	]]
	pending: boolean,
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

local function secrets()
	return ServiceLoader.get("SecretService")
end

local function converse()
	return ServiceLoader.get("ConverseService")
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
	Everything a condition is allowed to ask about, for this player in front of
	this speaker.

	One builder, because two things now judge conditions against it: the filter
	that decides which lines are shown, and SecretService, which decides
	whether a question landed. `rep` is standing with the speaker's own
	faction, so a second copy of this would eventually be built against a
	different faction than the line the player clicked was -- and the symptom
	would be a secret that opens for the wrong people.
]]
local function contextFor(player: Player, profile: any, faction: string): Dialogue.Context
	return {
		origin = profile.origin,
		level = profile.level,
		rep = profile.factionRep[faction] or 0,
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

	local ctx = contextFor(player, profile, session.faction)

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
			topic = choice.topic,
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
	Draws the panel. Both the authored path and the free-form one end here.

	`ask` is the whole of what the client is told about free-form mode, and it
	does two things there: it puts a text box under the reply list, and it
	shows the notice saying the answers are generated. That notice is required
	by Roblox policy for the length of the interaction, which is the reason
	this is a per-node flag rather than something set once when the box opens
	-- every frame the box is on screen is a frame that has to carry it.
]]
local function sendNode(player: Player, session: Session, line: string, choices: { Resolved }, ask: boolean)
	local wire = {}
	for _, choice in choices do
		table.insert(wire, { text = choice.text, kind = choice.kind })
	end

	Net.fireClient(Net.Event.StartDialogue, player, {
		speaker = session.speaker,
		title = session.title,
		text = line,
		choices = wire,
		ask = ask,
	})
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

	--[[
		The one choice nobody wrote.

		Appended at the top of the conversation only, and only for a speaker
		who has a character sheet and a backend that answers. Generated rather
		than authored for the same reason the mission list is: six trees would
		otherwise each carry a line that has to be added when the feature
		arrives and deleted when the kill switch is thrown, and the second of
		those would not happen.
	]]
	if nodeId == Dialogue.rootOf(Dialogue.get(session.treeId)) and converse().available(session.giverId) then
		table.insert(
			choices,
			{ text = "Actually -- I want to ask you something.", kind = Action.Ask, action = Action.Ask }
		)
	end

	session.nodeId = nodeId
	session.line = line
	session.choices = choices

	sendNode(player, session, line, choices, false)
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
		line = "",
		choices = {},
		asking = false,
		turns = 0,
		history = {},
		pending = false,
	}
	sessions[player] = session

	if not inRange(player, session) then
		finish(player)
		return
	end

	goTo(player, session, Dialogue.rootOf(Dialogue.get(treeId)))
end

--------------------------------------------------------------------------------
-- Free-form
--------------------------------------------------------------------------------

--[[
	Draws the panel in ask mode, with one way out and a box to type in.

	The reply list collapses to a single "Never mind." on purpose. A menu
	beside a text box is a menu the player will use, and the moment they do,
	the thing this feature was built to be -- a person you have to talk to --
	is a thing you can click past.
]]
local ASK_CHOICES: { Resolved } = { { text = "Never mind.", kind = Action.Leave, action = Action.Leave } }

local function askMode(player: Player, session: Session, line: string)
	session.asking = true
	session.choices = ASK_CHOICES
	sendNode(player, session, line, ASK_CHOICES, true)
end

--[[
	Leaves free-form and returns to the top of the authored tree.

	Back to the tree rather than out of the conversation, because the turn cap
	is the common way to arrive here and being thrown out of the panel for
	having talked too long reads as a bug. The root node's own opening line is
	written in this character's voice, so the conversation comes back around
	instead of ending on a message from the game.
]]
local function stopAsking(player: Player, session: Session, notice: string?)
	session.asking = false
	session.history = {}
	session.turns = 0
	if notice then
		Net.fireClient(Net.Event.Notify, player, notice, "Info")
	end
	goTo(player, session, Dialogue.rootOf(Dialogue.get(session.treeId)))
end

--[[
	One turn. The player typed `said`; the character answers.

	The order of the checks below is the security argument, so it is worth
	reading as a list rather than as code. Nothing reaches the model until the
	player is in a session, in free-form, in range, and not already waiting on
	an answer -- and nothing the model says reaches a reward until
	`SecretService.raise` has judged it against a profile the model has never
	been shown.
]]
function DialogueService.say(player: Player, said: string)
	local session = sessions[player]
	if not session or not session.asking or session.pending then
		return
	end
	-- An empty box is a mis-click on the send key, not a question. Caught
	-- here so it costs a return rather than a round trip and a row.
	if not string.match(said, "%S") then
		return
	end
	if not inRange(player, session) then
		finish(player, "OutOfRange")
		return
	end

	session.pending = true
	session.turns += 1

	local reply = converse().ask({
		player = player,
		speaker = session.giverId,
		sessionId = tostring(player.UserId) .. ":" .. session.giverId,
		turn = session.turns,
		history = session.history,
		said = said,
	})

	session.pending = false

	-- Everything below acts on a session that may have ended while the call
	-- was out: the player can walk off, die or quit inside a round trip.
	if sessions[player] ~= session then
		return
	end
	if not inRange(player, session) then
		finish(player, "OutOfRange")
		return
	end

	table.insert(session.history, { role = "user", text = said })
	table.insert(session.history, { role = "assistant", text = reply.line })

	--[[
		The handoff, and the only thing the model's output is allowed to do.

		A tag is a request to be asked a question, not an answer to it:
		`raise` re-reads the profile, runs the same `Dialogue.meets` an
		authored choice runs, and returns a node only if the player had
		already earned it. So the best possible jailbreak buys a player the
		right to have their own inventory checked.
	]]
	for _, topic in reply.topics do
		local profile = data().get(player)
		if not profile then
			break
		end
		local ctx = contextFor(player, profile, session.faction)
		local opened = secrets().raise(player, session.giverId, topic, ctx)
		if opened then
			-- The answer is authored, in the tree, and always was. The model
			-- found the door; it did not write what is behind it.
			session.asking = false
			session.history = {}
			session.turns = 0
			goTo(player, session, opened)
			return
		end
	end

	if reply.ended then
		stopAsking(player, session, "They have said all they mean to, for now.")
		return
	end

	askMode(player, session, reply.line)
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
		Re-checked here and not only where the choice was offered. The switch
		can be thrown between the panel being drawn and the button being
		pressed, and a kill switch that a conversation already in progress
		gets to ignore is not one.
	]]
	if choice.action == Action.Ask then
		if not converse().available(session.giverId) then
			return
		end
		askMode(player, session, session.line)
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

	--[[
		The one kind of choice whose destination the tree does not decide.

		`choice.next` is the deflection the author wrote; the node a secret
		opens is named by the secret. Which of the two the player lands on is
		settled here, on the server, out of a config no client and no future
		language model can reach -- see SecretService's header for why that
		separation is the whole feature rather than an implementation detail.

		After the flag block above, for the reason that block gives: a secret
		whose condition reads a flag this very choice set must see it set.
	]]
	local topic = choice.topic
	local profile = if topic then data().get(player) else nil
	if topic and profile then
		local ctx = contextFor(player, profile, session.faction)
		local opened = secrets().raise(player, session.giverId, topic, ctx)
		if opened then
			goTo(player, session, opened)
			return
		end
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

	-- Here for the same reason and with the same four predicates: a secret's
	-- `requires` is a Dialogue.Condition, and the two files that could check
	-- it are the two that would close a cycle by requiring each other.
	for _, problem in Secrets.validate(Missions.exists, Origins.exists, Flags.exists, statIsLive) do
		warn(`[DialogueService] secrets config: {problem}`)
	end

	--[[
		And the character sheets behind those secrets. Nothing generates text
		yet -- this is the Luau half of ROADMAP 5.1, deliberately built ahead
		of the model for the reason Secrets.luau was -- but the check has to
		run from the day the file exists, because the failure it catches is a
		persona and a secret drifting apart, and that drift is silent until
		the day something asks a model a question the sheet never covered.
	]]
	for _, problem in Personas.validate() do
		warn(`[DialogueService] personas config: {problem}`)
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

	--[[
		The only place in the game a player sends free text to the server.

		Rate limited to one a second rather than the usual six, because unlike
		every other remote here a call costs money at a third party. The real
		budget is enforced in Postgres, across servers -- this is just the
		part a single game server can see.

		The length cap is the same 300 the edge function enforces and the
		client's box allows. Three copies of one number is worth it: the
		client's is a courtesy, this one keeps a hostile client from making
		the game pay for a novel, and the backend's is the boundary.
	]]
	Net.onServerEvent(Net.Event.DialogueSay, function(player: Player, said: string)
		DialogueService.say(player, said)
	end, {
		rateLimit = 1,
		validate = Net.args(Net.check.string(300)),
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
