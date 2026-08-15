--!strict
--[[
	Dialogue.luau

	Every conversation in the game, as data.

	A tree is a bag of nodes. A node is some lines and a list of choices; a
	choice either walks to another node or performs an action and ends. That is
	the whole model -- deliberately small, because the interesting part of a
	conversation in an RPG is not the branching, it is what the branches are
	allowed to do.

	WHAT DIALOGUE IS FOR HERE
	Not flavour. Flavour is what a barked line is for. This exists because four
	systems already built had no way to reach each other: missions could only be
	taken from a menu, TalkTo objectives had no caller, quest givers were
	scenery, and vendors were a panel you opened on faith. A conversation is the
	one surface all of those meet on.

	MISSION OFFERS ARE NOT WRITTEN HERE
	A choice with `action = Action.Work` walks to a node the service generates
	from the speaker's available missions. Authoring an "accept the droid job"
	line per mission per giver would go stale the first time a mission moved
	planets, the same way the hand-written pickup table would have. The offer
	list is derived, so it cannot disagree with Missions.luau.

	Generated node ids are prefixed with "@" and authored ones may not be, so
	the two namespaces cannot collide.

	CONDITIONS ARE EVALUATED ON THE SERVER
	`condition` on a choice is a filter, not a suggestion: a choice the player
	does not qualify for is never sent to them, so it cannot be selected by a
	client that lies about which button it pressed.
]]

local Dialogue = {}

--- What a choice does when there is nothing to walk to. Server switches on these.
local Action: { [string]: string } = {
	Leave = "Leave", -- ends the conversation
	Shop = "Shop", -- ends it and opens the trade panel
	Work = "Work", -- walks to the generated list of this speaker's missions
}
Dialogue.Action = Action

local VALID_ACTIONS: { [string]: boolean } = {}
for _, a in Action do
	VALID_ACTIONS[a] = true
end

--- Marks a node id as generated rather than authored. See the header.
Dialogue.GENERATED_PREFIX = "@"

--[[
	Requirements for a choice to be offered at all.

	Every field is optional and all present fields must hold. Rep is measured
	against the speaker's own faction, which is the only faction a conversation
	has an opinion about.
]]
export type Condition = {
	minLevel: number?,
	minRep: number?,
	maxRep: number?,
	missionActive: string?,
	missionCompleted: string?,
	missionNotCompleted: string?,
}

export type Choice = {
	text: string,
	next: string?, -- node id; nil ends the conversation
	action: string?, -- one of Action
	condition: Condition?,
}

export type Node = {
	-- One line is picked at random each time the node is shown, so the tenth
	-- civilian on the street is not word-for-word the first.
	lines: { string },
	choices: { Choice }?,
}

export type Tree = {
	id: string,
	root: string?, -- defaults to "start"
	nodes: { [string]: Node },
}

local defs: { [string]: Tree } = {}

local function def(t: Tree): Tree
	defs[t.id] = t
	return t
end

-- Written once and reused: nearly every tree ends the same way, and repeating
-- the literal 17 times invites one of them to drift.
local LEAVE: Choice = { text = "Never mind.", action = Action.Leave }
local WORK: Choice = { text = "Anything that needs doing?", action = Action.Work }
local TRADE: Choice = { text = "Let me see what you have.", action = Action.Shop }

--------------------------------------------------------------------------------
-- Tatooine and the fringe
--------------------------------------------------------------------------------

def({
	id = "MoistureFarmer",
	nodes = {
		start = {
			lines = {
				"Vaporators are running dry and the sand does not care. What brings you out this far?",
				"Not many walk out to the homesteads on purpose. You lost, or looking?",
				"If you are here about water, I have none to spare. If you are here about work, sit down.",
			},
			choices = {
				WORK,
				{ text = "What is life like out here?", next = "life" },
				LEAVE,
			},
		},
		life = {
			lines = {
				"You get up before the suns, you fix what broke overnight, and you do it again. It is honest. It is also very dull, most years.",
				"Quiet, until it isn't. Tuskens come down out of the Dune Sea when the wells run low, and then it is not quiet at all.",
			},
			--[[
				Annotated because the list opens with a written-out choice.
				Luau reads the element type off the first entry, so a list that
				starts with one carrying `next` fixes the type as "has a next",
				and the shared LEAVE below -- whose `next` is nil -- no longer
				fits. Saying `{ Choice }` outright settles it either way.
			]]
			choices = {
				{ text = "The Tuskens give you trouble?", next = "tuskens" },
				LEAVE,
			} :: { Choice },
		},
		tuskens = {
			lines = {
				"They were here first. That does not make it easier when they take the herd, but it is worth remembering before you go out shooting.",
			},
			choices = { LEAVE },
		},
	},
})

def({
	id = "Jawa",
	nodes = {
		start = {
			lines = {
				"Utinni! You buy? Very good price, almost working!",
				"Ohh! Big one has credits? Jawa has parts. Many parts.",
				"Nnn... you not Imperial. Good. Imperials never pay.",
			},
			choices = {
				TRADE,
				{
					text = "A farmer's astromech went missing. Was that you?",
					next = "droid",
					condition = { missionActive = "TatDustAndDroids" },
				},
				{ text = "What do you have in the sandcrawler?", next = "crawler" },
				LEAVE,
			},
		},
		droid = {
			lines = {
				"Nnn! Not stolen! Found! Droid was walking, we help it stop walking. Is in the crawler with the others.",
				"Ohh. That one. Very loud, very rude. You take it. Please take it.",
			},
			choices = {
				{ text = "I will take it off your hands.", action = Action.Leave },
			},
		},
		crawler = {
			lines = {
				"Everything! Nothing! Both! You look, you find, you pay.",
			},
			choices = { TRADE, LEAVE },
		},
	},
})

def({
	id = "Smuggler",
	nodes = {
		start = {
			lines = {
				"You have the look of somebody who needs something moved. Or somebody who is about to be moved.",
				"Keep your voice down and your hands where I can see them and we will get along fine.",
				"I do not know you. That is usually a good sign, in here.",
			},
			choices = {
				WORK,
				{ text = "Who runs this town?", next = "town" },
				LEAVE,
			},
		},
		town = {
			lines = {
				"Officially? The Empire. Actually? Whoever the Hutts are paying this month. Do not confuse the two out loud.",
			},
			choices = { LEAVE },
		},
	},
})

def({
	id = "Merchant",
	nodes = {
		start = {
			lines = {
				"Best stock on the street, and the street knows it. Have a look.",
				"Everything is honest and everything is for sale. Rare combination.",
				"You break it, you have bought it. You buy it, you can break it all you like.",
			},
			choices = {
				TRADE,
				WORK,
				{ text = "Where does all this come from?", next = "supply" },
				LEAVE,
			},
		},
		supply = {
			lines = {
				"Ships come in, crates come off, I do not read the manifests. Neither should you.",
			},
			choices = { TRADE, LEAVE },
		},
	},
})

def({
	id = "Civilian",
	nodes = {
		start = {
			lines = {
				"I do not want any trouble.",
				"Busy day. Busy year, really.",
				"You are not from here, are you. It shows.",
				"Move along, friend. Standing still gets you noticed.",
			},
			choices = {
				WORK,
				{ text = "Heard anything worth knowing?", next = "rumour" },
				LEAVE,
			},
		},
		rumour = {
			lines = {
				"Patrols are thicker than they were. Somebody upset somebody, and it was not me.",
				"They say there is work down at the docks. They also say the last three who took it did not come back.",
				"Nothing worth the trouble of telling you. Sorry.",
			},
			choices = { LEAVE },
		},
	},
})

def({
	id = "ProtocolDroid",
	nodes = {
		start = {
			lines = {
				"Oh! A visitor. I am fluent in over six million forms of communication, though most days nobody uses any of them on me.",
				"Greetings. Please do not deactivate me. It happens more than you would think.",
				"How wonderful to be spoken to rather than about.",
			},
			choices = {
				WORK,
				{ text = "You must overhear a great deal.", next = "listening" },
				LEAVE,
			},
		},
		listening = {
			lines = {
				"I hear everything and I am asked about none of it, which I have come to understand is the entire point of a protocol droid.",
				"People say the most remarkable things in front of a droid. They forget we have memory banks.",
			},
			choices = { LEAVE },
		},
	},
})

--------------------------------------------------------------------------------
-- The underworld
--------------------------------------------------------------------------------

def({
	id = "BountyHunter",
	nodes = {
		start = {
			lines = {
				"You are not on my list. Enjoy that while it lasts.",
				"I am working. Whatever you want, want it quickly.",
				"Sit somewhere else. I do not like my back to the door either.",
			},
			choices = {
				WORK,
				{ text = "Who is on the list?", next = "list" },
				LEAVE,
			},
		},
		list = {
			lines = {
				"People who thought a debt was a suggestion. Do not become one of them and we will never speak again.",
			},
			choices = { LEAVE },
		},
	},
})

def({
	id = "CartelEnforcer",
	nodes = {
		start = {
			lines = {
				"This is Hutt ground. Behave accordingly.",
				"You are either paying, working, or leaving. Pick one.",
				"I have thrown better than you off this level. Say something interesting.",
			},
			choices = {
				WORK,
				{ text = "I can be useful.", next = "useful", condition = { minRep = -50 } },
				LEAVE,
			},
		},
		useful = {
			lines = {
				"Everybody is useful once. Twice is how you get a name around here.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

--------------------------------------------------------------------------------
-- The Empire
--------------------------------------------------------------------------------

def({
	id = "ImperialOfficer",
	nodes = {
		start = {
			lines = {
				"State your business. Briefly.",
				"Identification. Now. -- No? Then you had better be worth my time.",
				"The Empire is not in the habit of chatting. What do you want?",
			},
			choices = {
				WORK,
				{
					text = "I am at the Empire's service.",
					next = "loyal",
					condition = { minRep = 100 },
				},
				{ text = "Just passing through.", action = Action.Leave },
			},
		},
		loyal = {
			lines = {
				"Your record is noted. Order is not maintained by sentiment, but it is maintained by people like you.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

def({
	id = "SithTaunt",
	nodes = {
		start = {
			lines = {
				"I can feel you deciding whether to run. Decide faster.",
				"You are afraid. Good. Fear is the only honest thing about you.",
			},
			choices = { LEAVE },
		},
	},
})

def({
	id = "SithLord",
	nodes = {
		start = {
			lines = {
				"You have come a long way to kneel. Most do not realise that until the end.",
				"The Jedi told you the dark side is a shortcut. They never mention that it is also a door.",
			},
			choices = { LEAVE },
		},
	},
})

--------------------------------------------------------------------------------
-- The Republic and the Jedi
--------------------------------------------------------------------------------

def({
	id = "RepublicPilot",
	nodes = {
		start = {
			lines = {
				"If you are here about the ship, she flies. Mostly.",
				"Keep it quiet. Half this hangar is listening and a quarter of it is paid to.",
				"You look like you can hold a blaster. We are always short of those.",
			},
			choices = {
				WORK,
				{ text = "How is the war going?", next = "war" },
				LEAVE,
			},
		},
		war = {
			lines = {
				"We lost two more crews last month and gained a hundred volunteers. I have stopped deciding whether that is good news.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

def({
	id = "RepublicTrooper",
	nodes = {
		start = {
			lines = {
				"Eyes open. This position is not as secure as command thinks it is.",
				"You are not on the roster. That is either very good or very bad.",
				"Need something, or just admiring the sandbags?",
			},
			choices = {
				WORK,
				{ text = "Why do you fight?", next = "why" },
				LEAVE,
			},
		},
		why = {
			lines = {
				"They took my homeworld's shipyards and called it a tax. You only need one reason.",
			},
			choices = { LEAVE },
		},
	},
})

def({
	id = "RepublicSecurity",
	nodes = {
		start = {
			lines = {
				"Senate district. Keep your weapon holstered in the plaza and we will have no difficulty.",
				"The upper levels are closed to visitors. The rest of the district is not. Enjoy it.",
				"You have a traveller's look about you. This world is kinder than most places to that.",
			},
			choices = {
				WORK,
				{ text = "Is the Empire here?", next = "empire" },
				LEAVE,
			},
		},
		empire = {
			lines = {
				"At the spaceport, counting things. We are polite to them and we count them back.",
			},
			choices = { LEAVE },
		},
	},
})

def({
	id = "RepublicVeteran",
	nodes = {
		start = {
			lines = {
				"Been a long time since anybody saluted. Do not start now.",
				"You are young. Everybody is, from here.",
				"I held a line on Coruscant while they signed the treaty behind me. Ask me anything else.",
			},
			choices = {
				WORK,
				{ text = "What happened to the rest of your unit?", next = "unit" },
				LEAVE,
			},
		},
		unit = {
			lines = {
				"Some died. Some took the discharge and the pension. I sat down in the mud and did not get up until it was over. That is the whole story.",
			},
			choices = { LEAVE },
		},
	},
})

def({
	id = "JediMaster",
	nodes = {
		start = {
			lines = {
				"Peace. You are louder in the Force than you are on your feet.",
				"Sit, if you like. Nothing here is urgent, whatever you were told.",
				"I felt you coming an hour ago. You will learn to be quieter.",
			},
			choices = {
				WORK,
				{ text = "Teach me about the Force.", next = "force", condition = { minLevel = 5 } },
				LEAVE,
			},
		},
		force = {
			lines = {
				"It is not a weapon you pick up. It is a direction you keep choosing. The choosing is the difficult part.",
				"Strength comes quickly and control does not. Most who fall were simply in a hurry.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

def({
	id = "Researcher",
	nodes = {
		start = {
			lines = {
				"You are not on the manifest. Interesting. Most irregularities here are not.",
				"Please do not touch the tanks. The contents are further along than they look.",
				"Czerka does not receive visitors. We receive specimens, clients, and mistakes.",
			},
			choices = {
				WORK,
				{ text = "What are you growing here?", next = "growing" },
				LEAVE,
			},
		},
		growing = {
			lines = {
				"Whatever is ordered. We are very good at it, and we have never once been asked whether we should be.",
			},
			choices = { LEAVE },
		},
	},
})

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

Dialogue.defs = defs

function Dialogue.get(id: string): Tree
	local t = defs[id]
	assert(t, `Dialogue.get: unknown tree "{id}"`)
	return t
end

function Dialogue.exists(id: string): boolean
	return defs[id] ~= nil
end

--- The node a conversation opens on.
function Dialogue.rootOf(tree: Tree): string
	return tree.root or "start"
end

--[[
	Whether a player satisfies a choice's condition.

	`rep` is the player's standing with the speaker's faction, passed in rather
	than looked up so this stays a pure function the client could also run if a
	preview is ever wanted.
]]
function Dialogue.meets(
	condition: Condition?,
	level: number,
	rep: number,
	activeMissions: { [string]: any },
	completedMissions: { [string]: number }
): boolean
	if not condition then
		return true
	end
	if condition.minLevel and level < condition.minLevel then
		return false
	end
	if condition.minRep and rep < condition.minRep then
		return false
	end
	if condition.maxRep and rep > condition.maxRep then
		return false
	end
	if condition.missionActive and not activeMissions[condition.missionActive] then
		return false
	end
	if condition.missionCompleted and not completedMissions[condition.missionCompleted] then
		return false
	end
	if condition.missionNotCompleted and completedMissions[condition.missionNotCompleted] then
		return false
	end
	return true
end

--[[
	Cross-checks every tree against itself and against the missions it names.

	Same reasoning as Missions.validate: a choice pointing at a node that does
	not exist is a conversation that dead-ends silently, and the player has no
	way to tell that from an author's deliberate full stop.
]]
function Dialogue.validate(missionExists: (string) -> boolean): { string }
	local problems = {}

	for id, tree in defs do
		local root = Dialogue.rootOf(tree)
		if not tree.nodes[root] then
			table.insert(problems, `{id}: root node "{root}" does not exist`)
		end

		for nodeId, node in tree.nodes do
			if string.sub(nodeId, 1, 1) == Dialogue.GENERATED_PREFIX then
				table.insert(problems, `{id}: node "{nodeId}" uses the reserved generated-id prefix`)
			end
			if #node.lines == 0 then
				table.insert(problems, `{id}.{nodeId}: no lines`)
			end

			local choices: { Choice } = node.choices or {}
			for i, choice in choices do
				if choice.next and not tree.nodes[choice.next] then
					table.insert(problems, `{id}.{nodeId}: choice {i} goes to unknown node "{choice.next}"`)
				end
				if choice.action and not VALID_ACTIONS[choice.action] then
					table.insert(problems, `{id}.{nodeId}: choice {i} has unknown action "{choice.action}"`)
				end
				-- A choice that neither walks anywhere nor does anything just
				-- closes the panel, which is almost never what was meant.
				if not choice.next and not choice.action then
					table.insert(problems, `{id}.{nodeId}: choice {i} has neither next nor action`)
				end

				local c = choice.condition
				if c then
					--[[
						Checked field by field rather than gathered into a
						table first: the fields are optional, so a literal
						built from them would have holes, and generalised
						iteration stops at the first one.
					]]
					local function checkMission(named: string?)
						if named ~= nil and not missionExists(named) then
							table.insert(
								problems,
								`{id}.{nodeId}: choice {i} names unknown mission "{named}"`
							)
						end
					end
					checkMission(c.missionActive)
					checkMission(c.missionCompleted)
					checkMission(c.missionNotCompleted)
				end
			end
		end
	end

	table.sort(problems)
	return problems
end

return Dialogue
