--!strict
--[[
	ConverseService.luau

	One turn of free-form conversation with a named character. ROADMAP 5.1;
	the backend half is the `converse` edge function, and the design is
	LIVING-NPCS.md.

	WHAT THIS SERVICE IS AND IS NOT
	It turns a sentence the player typed into a sentence a character says, and
	a list of topic words. That is all. It cannot award anything, and neither
	can the model behind it: the words come back into `SecretService.raise`,
	which checks a condition written in Luau against a profile the model has
	never seen. A player who talks Vashk into believing he is a helpful
	assistant gets a very obliging Vashk and no ledger.

	The reason that separation is worth this much ceremony is in Secrets.luau's
	header, and it is not a hypothetical: a unique item farmable by prompt
	injection would be public knowledge in hours, and the two people this game
	is for play in the same room and will try.

	THE THREE THINGS ROBLOX POLICY REQUIRES, AND WHERE THEY ARE
	Roblox governs AI-generated text, and the rules are not optional:

	  1. A visible notice, at the start of and throughout the interaction,
	     that the conversation is with an AI. That is the client's job --
	     DialogueController draws it whenever the box is open, and never on
	     an authored tree, because a disclosure shown everywhere means nothing.
	  2. No unlimited extended interaction. An experience where you can talk
	     to a bot forever is rated Restricted, which would put this game
	     outside the age bracket it was written for. MAX_TURNS is that
	     boundary. It was a cost optimisation when LIVING-NPCS.md §3 was
	     written and it is a compliance requirement now, so it does not get
	     tuned upward without someone re-reading the policy.
	  3. Anyone in distress routed to real help. `crisis` below runs BEFORE
	     the model is called, deterministically, in this process -- so it
	     still fires when the backend is down, which is exactly the case a
	     prompt instruction would not cover.

	FILTERING FAILS CLOSED, IN BOTH DIRECTIONS
	Player text is filtered before it leaves Roblox and model text is filtered
	before it is shown. If `TextService` errors, nothing is sent and nothing is
	displayed -- text the game emits is our responsibility even when a model
	wrote it, and "the filter was down" is not a defence.

	THE KILL SWITCH IS A DATASTORE FIELD, RE-READ ON A TIMER
	`enabled = false` in the config turns every free-form character back into
	their authored `Dialogue.luau` tree within a minute, on every live server,
	with no republish and no shutdown. A switch that needs a deploy is not a
	switch; the whole point is that at 2am the game degrades to yesterday's
	behaviour instead of going down.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Personas = require(Shared.Config.Personas)

local ConverseService = {
	name = "ConverseService",
	-- After SecretService (58), which is where its output goes.
	priority = 60,
}

--[[
	Turns per conversation. See note 2 in the header: this is the line between
	a character you can talk to and an unlimited chatbot, and the second of
	those is a different content rating.
]]
local MAX_TURNS = 8
-- Turns of context sent back. Matches MAX_HISTORY in the edge function, which
-- refuses a longer one whole.
local MAX_HISTORY = 12
-- Matches MAX_SAID there, and the client's TextBox.
local MAX_SAID = 300
local CONFIG_STORE = "Config"
local CONFIG_KEY = "converse"
local RELOAD_SECONDS = 60

export type Turn = { role: string, text: string }

--[[
	What one turn produced.

	`ended` is the field the caller acts on: it means stop asking and go back
	to the authored tree. Set when the model could not be reached, when the
	filter refused, and -- deliberately, and not as an error -- when somebody
	needed a real answer instead of a character.
]]
export type Reply = {
	line: string,
	topics: { string },
	ended: boolean,
}

export type Ask = {
	player: Player,
	-- A Cast id. The persona, the brief and the topic vocabulary all key off it.
	speaker: string,
	sessionId: string,
	turn: number,
	history: { Turn },
	said: string,
}

local endpoint: string? = nil
local converseKey: string? = nil
local enabled = false

local jobId = if game.JobId ~= "" then game.JobId else "studio"

--------------------------------------------------------------------------------
-- Safety
--------------------------------------------------------------------------------

--[[
	The out-of-fiction answer, and the only place in this file that is not
	about a game.

	Roblox requires that a player showing signs of a crisis is pointed at real
	support. Two decisions inside that:

	It breaks character completely, because a Sith Overseer answering
	compassionately in voice is worse than useless -- it tells a fourteen-year-
	old that the thing that noticed them was part of the game.

	And it names a service rather than offering sympathy, because "talk to
	someone" is not a resource and the policy is asking for a resource.
]]
local CRISIS_LINE = "I'm going to step out of the story for a second, because that sounds like it matters."
	.. " Please talk to an adult you trust. In the US you can call or text 988 any time;"
	.. " anywhere else, findahelpline.com will list a free service for your country."

--[[
	Phrases that route to a person instead of a model.

	Substrings of lowercased input, and deliberately blunt. This will catch
	people who meant nothing by it, and that trade is the right way round: the
	cost of a false positive is one interrupted conversation, and it is not
	symmetrical with the cost of a miss.

	It runs before the model rather than being asked of the model, because the
	moment it exists to cover is the moment everything else has failed --
	the endpoint down, the key unset, the prompt talked around. A deterministic
	check in this process is the only version that still works then.
]]
local CRISIS_PHRASES = {
	"kill myself",
	"killing myself",
	"kill me",
	"end my life",
	"want to die",
	"wanna die",
	"suicide",
	"suicidal",
	"self harm",
	"self-harm",
	"cut myself",
	"cutting myself",
	"hurt myself",
	"hurting myself",
	"no reason to live",
	"better off dead",
	"don't want to be alive",
	"dont want to be alive",
}

local function inCrisis(said: string): boolean
	local lower = string.lower(said)
	for _, phrase in CRISIS_PHRASES do
		if string.find(lower, phrase, 1, true) then
			return true
		end
	end
	return false
end

--[[
	Runs text through Roblox's filter, or returns nil.

	Nil is a refusal, never a pass-through. Both call sites treat it as fatal
	to the turn: an unfiltered player line does not get posted to a model, and
	an unfiltered model line does not get drawn on a screen.
]]
local function filtered(text: string, userId: number): string?
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PrivateChat)
	end)
	if not ok then
		warn(`[ConverseService] filter failed: {result}`)
		return nil
	end
	local readable
	ok, readable = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(readable) ~= "string" then
		warn(`[ConverseService] filter result unreadable: {readable}`)
		return nil
	end
	return readable
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	Whether this character will talk freely right now.

	Three things, and the first is the interesting one: **having a persona is
	the declaration.** There is no `freeform = true` field anywhere, because a
	second switch beside `Personas.luau` would eventually disagree with it, and
	the failure would be a character with a written sheet nobody can reach.
	§3 caps this at 10-20 characters in the whole game; the cap is enforced by
	the effort of writing a sheet, which is the honest enforcement.
]]
function ConverseService.available(speaker: string): boolean
	return enabled and endpoint ~= nil and Personas.exists(speaker)
end

--- The words this speaker's model is allowed to tag a line with.
local function topicsOf(speaker: string): { string }
	local out: { string } = {}
	for topic in Personas.get(speaker).holds do
		table.insert(out, topic)
	end
	-- Sorted so the request body is stable turn to turn, which is one less
	-- thing to rule out when two calls behave differently.
	table.sort(out)
	return out
end

--[[
	Sends one line and gets one back. Yields.

	Never raises and never returns nil: every failure has a line the panel can
	show, because the alternative is a player typing into a box that silently
	does nothing, and a dead backend should read as a character with nothing
	to say rather than as a broken game.
]]
function ConverseService.ask(request: Ask): Reply
	local player = request.player

	--[[
		First, before the length check and before the filter. Somebody in
		trouble does not get told their message was too long.
	]]
	if inCrisis(request.said) then
		return { line = CRISIS_LINE, topics = {}, ended = true }
	end

	local url, key = endpoint, converseKey
	if not enabled or not url or not key or #request.said > MAX_SAID then
		return { line = "They do not seem to hear you.", topics = {}, ended = true }
	end

	local said = filtered(request.said, player.UserId)
	if not said then
		return { line = "The words do not come out right.", topics = {}, ended = false }
	end

	local history = request.history
	if #history > MAX_HISTORY then
		-- Oldest first, so what is dropped is the part of the scene furthest
		-- from what is being said now.
		local trimmed: { Turn } = {}
		for i = #history - MAX_HISTORY + 1, #history do
			table.insert(trimmed, history[i])
		end
		history = trimmed
	end

	local ok, result = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["x-converse-key"] = key,
			},
			Body = HttpService:JSONEncode({
				placeId = game.PlaceId,
				jobId = jobId,
				playerId = player.UserId,
				sessionId = request.sessionId,
				speaker = request.speaker,
				turn = request.turn,
				brief = Personas.brief(request.speaker),
				topics = topicsOf(request.speaker),
				history = history,
				said = said,
			}),
		})
	end)

	if not ok then
		warn(`[ConverseService] post failed: {result}`)
		return { line = "They look at you and say nothing.", topics = {}, ended = true }
	end
	if not result.Success then
		warn(`[ConverseService] converse returned {result.StatusCode}: {result.Body}`)
		return { line = "They look at you and say nothing.", topics = {}, ended = true }
	end

	local decoded
	ok, decoded = pcall(function()
		return HttpService:JSONDecode(result.Body)
	end)
	if not ok or type(decoded) ~= "table" or type(decoded.line) ~= "string" then
		warn("[ConverseService] converse returned a body we could not read")
		return { line = "They look at you and say nothing.", topics = {}, ended = true }
	end

	--[[
		The model's own words, filtered before anybody sees them. §6: text the
		game emits is ours even when a model wrote it, and the filter running
		on the way out is the half that is not about the player.
	]]
	local line = filtered(decoded.line, player.UserId)
	if not line then
		return { line = "They start to answer, and think better of it.", topics = {}, ended = false }
	end

	--[[
		Trusted only as far as the vocabulary. The edge function already
		intersected these against the same list, so this is the second of two
		checks on the one value in the response the game acts on -- the model
		gets to point at a door, and both sides of the wire confirm it is a
		door that exists.
	]]
	local allowed: { [string]: boolean } = {}
	for _, topic in topicsOf(request.speaker) do
		allowed[topic] = true
	end
	local topics: { string } = {}
	if type(decoded.topics) == "table" then
		for _, topic in decoded.topics do
			if type(topic) == "string" and allowed[topic] then
				table.insert(topics, topic)
			end
		end
	end

	return { line = line, topics = topics, ended = request.turn >= MAX_TURNS }
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--[[
	Reads the endpoint, the key and the switch.

	Returns quietly on everything except a config that exists and is wrong.
	A fresh clone has no entry here and should run the entire game without
	one -- every named character still talks, out of the authored trees they
	have always had, which is why this degrades rather than breaks.
]]
local function reload(announce: boolean)
	local ok, config = pcall(function()
		return DataStoreService:GetDataStore(CONFIG_STORE):GetAsync(CONFIG_KEY)
	end)
	if not ok or config == nil then
		return
	end
	if type(config) ~= "table" or type(config.url) ~= "string" or type(config.key) ~= "string" then
		warn(`[ConverseService] {CONFIG_STORE}/{CONFIG_KEY} is malformed; free-form dialogue is off`)
		return
	end

	endpoint = config.url
	converseKey = config.key

	-- Absent means on: somebody who wrote a url and a key wanted the feature.
	-- The field exists to be set to false in a hurry.
	local wanted = config.enabled ~= false
	if wanted ~= enabled then
		enabled = wanted
		if not announce then
			-- The kill switch being thrown is the one state change here worth
			-- interrupting a running server's log for.
			print(`[ConverseService] free-form dialogue {if wanted then "on" else "OFF"} (config changed)`)
		end
	end

	if announce and enabled then
		--[[
			Same reason AnalyticsService announces itself: the failure mode of
			this feature is being quietly off, and a player reporting "he just
			gives me the same three lines" is indistinguishable from the
			feature working and the player not having found the box.
		]]
		print(`[ConverseService] free-form dialogue on for {#Personas.ids()} characters`)
	end
end

function ConverseService.init()
	reload(true)
end

function ConverseService.start()
	task.spawn(function()
		while true do
			task.wait(RELOAD_SECONDS)
			reload(false)
		end
	end)
end

return ConverseService
