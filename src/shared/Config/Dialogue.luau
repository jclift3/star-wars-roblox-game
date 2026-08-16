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
	--[[
		Offered only to one origin.

		The cheap half of making the four origins felt: a stranger on the
		street can have one line that only a Scrapper would ever think to
		say, without a second tree written for the other three.
	]]
	origin: string?,
	minLevel: number?,
	minRep: number?,
	maxRep: number?,
	missionActive: string?,
	missionCompleted: string?,
	missionNotCompleted: string?,
	--[[
		Something the character did, from Config/Flags.luau.

		This is the whole of branching, and it is why a conversation can be
		about the player rather than at them: the difference between a line
		that fires because you are level 14 and a line that fires because you
		walked out of that tomb is the difference between a game that knows
		you exist and one that does not.
	]]
	flag: string?,
	notFlag: string?,
	minAlignment: number?,
	maxAlignment: number?,
}

export type Choice = {
	text: string,
	next: string?, -- node id; nil ends the conversation
	action: string?, -- one of Action
	condition: Condition?,
	--[[
		WHAT PICKING THIS COSTS YOU

		`alignment` shifts the character; `sets` raises flags. Both are applied
		by the server when the choice is taken, and both are why a dialogue
		tree is more than a menu -- a branch that changes nothing outside the
		conversation is a branch the player is right to stop reading.

		Deliberately no way to *lower* a flag. A thing you did stays done.
	]]
	alignment: number?,
	sets: { string }?,
}

--[[
	Everything a condition is allowed to ask about.

	Passed as one record rather than eight positional arguments: `meets` grew
	from three checks to eleven, and the call site had reached the point where
	swapping `level` and `rep` would have type-checked cleanly and been wrong
	in a way nothing could catch.
]]
export type Context = {
	origin: string,
	level: number,
	-- Standing with the SPEAKER's faction, not a whole table: a conversation
	-- has an opinion about one faction, and passing the map would invite a
	-- condition that quietly means a different one.
	rep: number,
	alignment: number,
	flags: { [string]: boolean },
	activeMissions: { [string]: any },
	completedMissions: { [string]: number },
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
				--[[
					One line each, and only ever one of them on screen: the
					menu is no longer for anybody, but it is different for
					everybody. Put on the Civilian because the Civilian is
					the archetype that spawns in the largest numbers on
					every world, so this is the origin the player is
					reminded of most often for the least authoring.
				]]
				{ text = "You are afraid of me.", next = "afraid", condition = { origin = "Acolyte" } },
				{
					text = "I grew up in a block like this one.",
					next = "block",
					condition = { origin = "Conscript" },
				},
				{ text = "Who do you owe?", next = "owing", condition = { origin = "Scoundrel" } },
				{
					text = "Anything round here worth pulling apart?",
					next = "salvage",
					condition = { origin = "Scrapper" },
				},
				--[[
					Civilians are the archetype that spawns in the largest
					numbers on every world, which already made them the right
					place for the four origin lines. It makes them the right
					place for this too: the Underlevels fork is a thing the
					player did to people, and the people are the ones who
					should still be talking about it.
				]]
				{
					text = "You know who I am.",
					next = "grateful",
					condition = { flag = "WarnedTheUnderlevels" },
				},
				{
					text = "You know who I am.",
					next = "frightened",
					condition = { flag = "PrunedTheUnderlevels" },
				},
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
		afraid = {
			lines = {
				"Yes. Everyone is. You will find that stops being useful to you sooner than you think.",
				"My grandmother was afraid of your Academy and she never saw it. I have seen it. So.",
			},
			choices = { LEAVE },
		},
		block = {
			lines = {
				"Then you know why nobody here waves. Good. It saves me explaining it.",
				"Everybody grew up in a block like this one. Not everybody came back wearing that.",
			},
			choices = { LEAVE },
		},
		owing = {
			lines = {
				"Everyone. That is not a joke, it is a filing system.",
				"Less than I did last year, and I did nothing differently, which frightens me.",
			},
			choices = { LEAVE },
		},
		salvage = {
			lines = {
				"Everything. That is the problem -- if it were worth anything somebody would already have taken it.",
				"There is a machine under the east wall nobody has fixed in nine years. If you fix it I will not tell anyone it was you.",
			},
			choices = { LEAVE },
		},
		grateful = {
			lines = {
				"My cousin was on that list. She is on a freighter now and she does not know your name either, which is how she stays on it.",
				"We do. Nobody says it where the plate can hear, so this is the whole of your thank you. Take it, it cost more than it sounds.",
			},
			choices = { LEAVE },
		},
		frightened = {
			lines = {
				"I know who you are. I am going to keep walking now, and you are going to let me, because I am not on any list and I would like to stay that way.",
				"Please do not talk to me in the street. -- No. I am not being rude. I am being careful, and you are the reason.",
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

--[[
	The one conversation in the game that costs the player something.

	An enforcer has somebody against a wall over four hundred credits, and the
	player can pay it, walk past it, or enjoy it. It is small on purpose: the
	fork that teaches a player their choices are real should be the cheapest
	one in the game, not the climax.

	BOTH BRANCHES CLOSE BOTH DOORS
	Each condition carries `notFlag` for its own outcome AND the other's, so
	the moment happens once per character rather than once per enforcer -- and
	there are eighteen of these on the Nar Shaddaa Promenade alone. See
	Config/Flags.luau; `validate` enforces the half of this that is a rule.
]]
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
				{
					text = "Who is that against the wall?",
					next = "debt",
					condition = { notFlag = "MetTheDebtor" },
				},
				LEAVE,
			},
		},
		useful = {
			lines = {
				"Everybody is useful once. Twice is how you get a name around here.",
			},
			choices = { WORK, LEAVE },
		},
		debt = {
			lines = {
				"Him? Four hundred, eleven weeks late. He has a very good reason and I have heard it twice. Third time I stop listening with my ears.",
				"Nobody. He was nobody eleven weeks ago too, he just had four hundred credits then.",
			},
			choices = {
				--[[
					`MetTheDebtor` is what makes this happen once; the other
					flag is what the world remembers about it. Both branches
					raise the first, so either answer shuts the door -- one
					`notFlag` cannot exclude two outcomes, and giving the
					moment its own flag is cheaper and clearer than making
					conditions take lists.
				]]
				{
					text = "The debt is mine. Take it out of what I am owed.",
					next = "paid",
					alignment = 90,
					sets = { "MetTheDebtor", "PaidTheStrangersDebt" },
					condition = { notFlag = "MetTheDebtor" },
				},
				{
					text = "Do not let me interrupt.",
					next = "watched",
					alignment = -90,
					sets = { "MetTheDebtor", "LetThemBreakHisHands" },
					condition = { notFlag = "MetTheDebtor" },
				},
				-- Walking away is free and stays available: refusing to decide
				-- is a legitimate answer and should not be worth alignment.
				{ text = "Not my business.", action = Action.Leave },
			} :: { Choice },
		},
		paid = {
			lines = {
				"Huh. Written off, then. -- Do not do that again where people can see you. It gets around, and then everyone here is eleven weeks late.",
			},
			choices = { LEAVE },
		},
		watched = {
			lines = {
				"No, you would not. -- Stand further back. It goes further than people expect.",
			},
			choices = { LEAVE },
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
				-- The other half of the Underlevels fork. An officer who knows
				-- exactly what you did either way is the cheapest possible
				-- proof to the player that the choice was recorded.
				{
					text = "About the Underlevels.",
					next = "pruned",
					condition = { flag = "PrunedTheUnderlevels" },
				},
				{
					text = "About the Underlevels.",
					next = "warned",
					condition = { flag = "WarnedTheUnderlevels" },
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
		pruned = {
			lines = {
				"Eight, and quietly. -- You will find the second list easier than the first. Everyone does. That is not a warning, it is a recruitment figure.",
			},
			choices = { WORK, LEAVE },
		},
		warned = {
			lines = {
				"Four households, empty, in the hour before we arrived. -- I do not need to know how. I need to know that you know I know. Good. We understand each other and neither of us has said anything actionable.",
			},
			choices = { LEAVE },
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
				--[[
					THE PART THE PLAYER ACTUALLY FEELS

					Everything above this line is machinery. This is what it
					was for: a line that exists because of something this
					character did, offered by somebody who was not there when
					they did it. A stranger who knows what you found is the
					difference between a world and a set.

					Ordered narrowest first. Conditions do not rank
					themselves -- `resolveChoices` keeps every choice that
					qualifies -- so the later thread has to be written above
					the earlier one or the player is offered both and the
					story appears to be running backwards.
				]]
				{
					text = "The man in the tomb was requisitioning people.",
					next = "afterTomb",
					condition = { flag = "TombOpened" },
				},
				{
					text = "Lot 9 was not a warehouse.",
					next = "lot9",
					condition = { flag = "SawLot9", notFlag = "TombOpened" },
				},
				{
					text = "There is a form for collecting acolytes.",
					next = "intake",
					condition = { flag = "SawTheIntakeForm", notFlag = "SawLot9" },
				},
				{
					text = "A droid on Taris counted fourteen crates to one buyer.",
					next = "fourteen",
					condition = { flag = "HeardNineRemember", notFlag = "SawLot9" },
				},
				LEAVE,
			},
		},
		growing = {
			lines = {
				"Whatever is ordered. We are very good at it, and we have never once been asked whether we should be.",
			},
			choices = { LEAVE },
		},
		afterTomb = {
			lines = {
				"I know what you did. Everyone in this building knows, and not one of us has said the word out loud yet. -- The requisitions stopped. That is the first good news in nine years and I do not trust it, because the forms are still printed.",
			},
			choices = { WORK, LEAVE },
		},
		lot9 = {
			lines = {
				"No. It was a shelf. -- I want you to notice that nothing in there was dead. That is the part I cannot put in a report, because a report has a field for cause and there is no cause, only an absence where a person's talent used to sit.",
			},
			choices = { WORK, LEAVE },
		},
		intake = {
			lines = {
				"Of course there is. There is a form for everything, and a form means it happened often enough to be worth printing. -- Ask yourself who ordered the print run, not who signed the copy.",
			},
			choices = { WORK, LEAVE },
		},
		fourteen = {
			lines = {
				"Fourteen is a shipment. One is an accident and fourteen is a schedule. -- Whoever ordered them was not experimenting. They already knew what they wanted and how much of it.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

--------------------------------------------------------------------------------
-- The recurring cast
--------------------------------------------------------------------------------

--[[
	Six trees that are allowed to assume they have met you.

	Every tree above this line is written for a *kind* of person -- there are
	eleven Czerka researchers on Taris and the tree has to work for all of
	them. These six are written for one person each, which changes what the
	writing is allowed to do: it can open by recognising you, it can be wrong
	about you, and it can refer to a thing that happened once.

	The shape is the same in all six on purpose. A line for the origin who
	belongs to this character, a line for each of the origins who do not, and
	then whatever the flags say. The origin lines matter as much as the flags:
	Vashk raised the Acolyte and has never met a Scrapper, and the difference
	between those two conversations is most of what makes an origin feel like
	a life rather than a starting zone.

	`Cast.luau` says who they are and where they stand. See CAMPAIGN.md §7.
]]

def({
	id = "CastVashk",
	nodes = {
		start = {
			lines = {
				"You are still breathing. Statistically that is already unusual. -- Say what you came to say; I do not enjoy being circled.",
				"The Academy has not missed you. Institutions do not miss people. I notice, which is a different thing, and rarer.",
			},
			choices = {
				WORK,
				--[[
					Vashk's own student first, then the three who do not know
					him. Narrowest-first, same rule as the Researcher tree:
					nothing ranks conditions, so the specific line has to be
					written above the general one.
				]]
				{
					text = "You had her put down and you did not stop walking.",
					next = "defective",
					condition = { origin = "Acolyte", flag = "SawTheIntakeForm" },
				},
				{ text = "Overseer.", next = "student", condition = { origin = "Acolyte" } },
				{ text = "I am not one of yours.", next = "outsider" },
				{
					text = "There is a form for collecting acolytes. Who ordered the print run?",
					next = "theForm",
					condition = { flag = "SawTheIntakeForm" },
				},
				{
					text = "A Jedi Master has a name for what is happening.",
					next = "named",
					condition = { flag = "NamedTheQuiet" },
				},
				LEAVE,
			},
		},
		student = {
			lines = {
				"I told you on your first day that most of you would die here and that this was the point. You are annoyed that it was true. Everyone is, eventually.",
			},
			choices = { WORK, LEAVE },
		},
		outsider = {
			lines = {
				"No. You have the posture of somebody who was fed regularly. -- Do not mistake that for an insult. It is the closest thing to good fortune anybody in this building has had.",
			},
			choices = { WORK, LEAVE },
		},
		defective = {
			lines = {
				"I signed it. I have signed four hundred and six of them, and I can tell you the year of each one, which is not a defence and I am not offering it as one. -- She was not defective. There is no word for what she was, so the form has a box that says so, and I ticked it.",
			},
			choices = {
				{ text = "Then why keep signing them?", next = "keepSigning" },
				LEAVE,
			} :: { Choice },
		},
		keepSigning = {
			lines = {
				"Because the ones I do not sign are collected anyway, and then nobody has written it down. -- Thirty years of it, in a hand nobody reads. If you ever find who reads it, you will know more than I do.",
			},
			choices = { WORK, LEAVE },
		},
		theForm = {
			lines = {
				"An excellent question, and the only one worth asking. It is not the Academy. We requisition students; we do not requisition a *count*. -- Somebody outside this order told the Empire how many it needed and by when.",
			},
			choices = { WORK, LEAVE },
		},
		named = {
			lines = {
				"A name. Thirty years and a Jedi gets to say it out loud in a room where nobody is frightened of her. -- Good. Use it. A thing with a name can be put on a form, and a thing on a form can be traced.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

def({
	id = "CastTolenMarr",
	nodes = {
		start = {
			lines = {
				"Sergeant Marr. Twenty-one years, four postings, one commendation I did not want. Sit down or do not.",
				"If you are here from Command, I filed it. If you are here about what was in it, sit down.",
			},
			choices = {
				WORK,
				{
					text = "You were the one who wrote it up as fatigue.",
					next = "filed",
					condition = { origin = "Conscript", flag = "SawBothCopies" },
				},
				{ text = "Sergeant.", next = "soldier", condition = { origin = "Conscript" } },
				{ text = "I have never worn a uniform.", next = "civilian" },
				{
					text = "I have a copy of the stripping manifest.",
					next = "manifest",
					condition = { flag = "HasTheManifest" },
				},
				{
					text = "A Jedi Master has a name for what is happening.",
					next = "named",
					condition = { flag = "NamedTheQuiet" },
				},
				LEAVE,
			},
		},
		soldier = {
			lines = {
				"You came out the other side of it, which is more than the report says about you. The report says the incident concluded. -- Incidents do not conclude. They stop happening to one person and start happening to another.",
			},
			choices = { WORK, LEAVE },
		},
		civilian = {
			lines = {
				"Then you can ask questions I cannot, and nobody puts a note in your file for it. -- I am not being friendly. I am being practical, and you should not confuse the two while you are useful to me.",
			},
			choices = { WORK, LEAVE },
		},
		filed = {
			lines = {
				"I wrote what they would file. If I had written what I saw, the report goes in a drawer and I go somewhere without a comm. Written the way I wrote it, it went to eleven desks. -- One of those desks wrote back. That is why I am still asking.",
			},
			choices = {
				{ text = "Which desk?", next = "whichDesk" },
				LEAVE,
			} :: { Choice },
		},
		whichDesk = {
			lines = {
				"Procurement. Not intelligence, not medical -- procurement. A woman with a budget wanted to know whether the effect was reproducible. She used that word in an official reply and nobody flagged it.",
			},
			choices = { WORK, LEAVE },
		},
		manifest = {
			lines = {
				"Let me see it. -- No, keep it, I do not want it in my hand. Read me the third column. That is a delivery schedule, and the Republic is on it as a *supplier*. -- I have been telling myself for two years that we were only slow.",
			},
			choices = { WORK, LEAVE },
		},
		named = {
			lines = {
				"The Jedi named it. Good for the Jedi. -- Now watch what my service does with the name, because I have seen this shape before: we will agree it is terrible, and then we will classify it, and then it will be nobody's job.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

def({
	id = "CastVessKadar",
	nodes = {
		start = {
			lines = {
				"There you are. I had you at four days and you took six, which costs you nothing and tells me something. -- Sit. I am fond of you and you still owe me.",
				"Everyone who walks up to this table wants something. The honest ones say so in the first sentence.",
			},
			choices = {
				WORK,
				{
					text = "The girl in the crate. You knew what the cargo was.",
					next = "theGirl",
					condition = { origin = "Scoundrel", flag = "OwesNobody" },
				},
				{ text = "How much do I owe today?", next = "debt", condition = { origin = "Scoundrel" } },
				{ text = "I do not owe you anything.", next = "stranger" },
				{
					text = "I covered a stranger's debt on the Promenade.",
					next = "paidOne",
					condition = { flag = "PaidTheStrangersDebt" },
				},
				{
					text = "I watched the Cartel collect and I said nothing.",
					next = "watchedOne",
					condition = { flag = "LetThemBreakHisHands" },
				},
				LEAVE,
			},
		},
		debt = {
			lines = {
				"Less than yesterday, which is the only sentence in this business anybody is ever glad to hear. -- I could clear it. I want you to notice that I have not, and to ask yourself why, and then to do nothing about it, because I like the arrangement.",
			},
			choices = { WORK, LEAVE },
		},
		stranger = {
			lines = {
				"Not yet. Nobody does, at first. -- I sell what nobody else will and I charge what the room will bear. You will be back, and I will be pleasant about it, and both of us will pretend that is a kindness.",
			},
			choices = { WORK, LEAVE },
		},
		theGirl = {
			lines = {
				"I knew it was sealed, sedated and worth eleven thousand, and I did not open it, because a fixer who opens the cargo is a fixer nobody hires twice. -- You opened it. -- I have thought about that more than I would like, and I have not changed anything, and those are two separate facts about me.",
			},
			choices = {
				{ text = "Who was the buyer?", next = "buyer" },
				LEAVE,
			} :: { Choice },
		},
		buyer = {
			lines = {
				"A Czerka account, paid clean, signed by somebody with a doctorate. -- That is the part that should frighten you. Not the Hutts. The paperwork.",
			},
			choices = { WORK, LEAVE },
		},
		paidOne = {
			lines = {
				"I heard. The whole level heard, which is the problem: eleven people now believe their debt is the kind of thing a stranger might cover. -- I am not angry. I am recalculating, and that is worse for them and better for you.",
			},
			choices = { WORK, LEAVE },
		},
		watchedOne = {
			lines = {
				"You stood there. -- I am not going to pretend to be shocked; I have stood there. But do not tell me it was business. Business was the debt. The hands were somebody enjoying themselves, and you watched that part too.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

def({
	id = "CastOrdo9",
	nodes = {
		start = {
			lines = {
				"Greeting: hello. I have run diagnostics eleven times since you left and I remain missing the same forty-one per cent. Statement: I have decided to find this funny.",
				"Observation: you are approaching from my left, which is the side with the damaged sensor. Speculation: either you have forgotten, or you are being kind, and I cannot presently tell those apart.",
			},
			choices = {
				WORK,
				{
					text = "Nine. What else do you remember about the crates?",
					next = "crates",
					condition = { origin = "Scrapper", flag = "HeardNineRemember" },
				},
				{
					text = "How are you holding together?",
					next = "repair",
					condition = { origin = "Scrapper" },
				},
				{ text = "What are you?", next = "whatAreYou" },
				{
					text = "I have been inside Lot 9.",
					next = "lot9",
					condition = { flag = "SawLot9" },
				},
				LEAVE,
			},
		},
		repair = {
			lines = {
				"Answer: adequately, and improving, which I attribute entirely to you and a scavenged coupling of the wrong gauge. Addendum: the coupling of the wrong gauge is the part I am fondest of.",
			},
			choices = { WORK, LEAVE },
		},
		whatAreYou = {
			lines = {
				"Answer: an HK-series unit, which I am told means something to people who were alive earlier. Qualification: I do not remember being it. Assessment: I have been informed that this is the best possible outcome, by someone who then would not look at me.",
			},
			choices = { WORK, LEAVE },
		},
		crates = {
			lines = {
				"Retrieval: fourteen. Fourteen deliveries, one recipient, no return leg logged. Difficulty: the recipient field is intact and the recipient name is not, which is not corruption -- corruption is untidy and that field was *cleared*.",
			},
			choices = {
				{ text = "Somebody wiped it deliberately.", next = "wiped" },
				LEAVE,
			} :: { Choice },
		},
		wiped = {
			lines = {
				"Concurrence. And here is the part I have not said out loud: the instruction to clear it is in my own maintenance log, in my own authorisation. Statement: I did that. Clarification: I do not remember doing that, and I have stopped finding it funny.",
			},
			choices = { WORK, LEAVE },
		},
		lot9 = {
			lines = {
				"Query: were the racks numbered? -- Do not answer. I already know they were numbered, and I know that because I have a stored route to a building I have never told you I could find. Conclusion: I carried them. Request: do not reassure me.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

def({
	id = "CastRynSolaa",
	nodes = {
		start = {
			lines = {
				"Come in. You are the fourth person this year to walk up that path looking like they have something they are not sure they are allowed to say. -- You are allowed.",
				"Peace. -- No, look at me properly. I am not going to tell you that you imagined it.",
			},
			choices = {
				WORK,
				--[[
					The one line any origin can reach that sets a flag three
					other characters read. Guarded by its own flag, so the
					naming happens once.

					Gated on level rather than on evidence, and that is a
					compromise worth writing down: the honest condition is
					"has seen any of the four prologues", and a Condition is
					an AND of its fields with no way to say *or*. Four copies
					of this choice, one per prologue flag, would show the same
					line twice to a character who saw two of them. Level 20 is
					the proxy -- late enough that a player arriving here has
					been somewhere.
				]]
				{
					text = "Say what it is. Out loud.",
					next = "naming",
					sets = { "NamedTheQuiet" },
					condition = { minLevel = 20, notFlag = "NamedTheQuiet" },
				},
				{
					text = "You said it. Has the Council?",
					next = "council",
					condition = { flag = "NamedTheQuiet" },
				},
				{
					text = "One of your Order went hollow in front of me.",
					next = "witness",
					condition = { origin = "Conscript" },
				},
				{ text = "I was raised on Korriban.", next = "korriban", condition = { origin = "Acolyte" } },
				{ text = "Why would a Jedi talk to me at all?", next = "why" },
				LEAVE,
			},
		},
		naming = {
			lines = {
				"The Quiet. -- That is what it is called by the four of us who have written it down, and I am aware of how it sounds. Something is taking the Force out of living people and leaving the people. -- There. It is said, and the room did not fall down, and now you and I both have to be someone who knows.",
			},
			choices = {
				{ text = "Then what do we do?", next = "council" },
				LEAVE,
			} :: { Choice },
		},
		council = {
			lines = {
				"The Council has read every word and asked for a fifth report. -- I have stopped believing that is caution. An institution that is frightened does not act; it commissions. Whatever gets done about this will be done by people acting against their own order, and I am now one of them.",
			},
			choices = { WORK, LEAVE },
		},
		witness = {
			lines = {
				"You carried her out. I read the file -- the real one, not the one with fatigue written on it. -- You are the only non-sensitive I have met who has watched it happen, and you have no idea how much that is worth. You cannot be told you imagined it.",
			},
			choices = { WORK, LEAVE },
		},
		korriban = {
			lines = {
				"I know. You have been standing there deciding how I will take it. -- Badly, if you had come ten years ago. It cannot touch the people who have no talent to take, which means it is not a Sith weapon and not a Jedi problem. It is being done to *us*, and I am afraid I have to include you in that word.",
			},
			choices = { WORK, LEAVE },
		},
		why = {
			lines = {
				"Because you came up the path, and because the people who are going to be useful about this are not going to be Jedi. -- We are being hunted and we are the last to notice. That is not wisdom. That is what being important does to you.",
			},
			choices = { WORK, LEAVE },
		},
	},
})

def({
	id = "CastAnethCorr",
	nodes = {
		start = {
			lines = {
				"Doctor Corr. You are not on today's list, and I would rather talk to you than have you removed, so let us do that instead. -- Everything here is legal. I say that first because it is the part people refuse to believe.",
				"You have questions, and I will answer them, and that will be worse for you than being lied to. Most people find this out too late to leave.",
			},
			choices = {
				WORK,
				{
					text = "The racks in Lot 9 have people in them.",
					next = "racks",
					condition = { flag = "SawLot9" },
				},
				{
					text = "I have your stripping manifest.",
					next = "manifest",
					condition = { flag = "HasTheManifest", notFlag = "SawLot9" },
				},
				{
					text = "A Jedi Master has a name for what you do.",
					next = "named",
					condition = { flag = "NamedTheQuiet" },
				},
				{ text = "What exactly does Czerka procure?", next = "procure" },
				LEAVE,
			},
		},
		procure = {
			lines = {
				"Whatever the contract specifies. I have a budget, a quota and a client, and I have never met the client, which is normal and which I am aware sounds otherwise. -- I am not the interesting part of this. I am the part that makes it happen on schedule.",
			},
			choices = { WORK, LEAVE },
		},
		racks = {
			lines = {
				"Yes. Sedated, monitored, and in better health than most of this planet -- which is not a defence, it is a specification. The contract requires them intact. -- You want me to be frightened of you now. I would rather you asked who wrote the specification, because I did not, and I would very much like to know.",
			},
			choices = {
				{ text = "Then stop filling it.", next = "stop" },
				LEAVE,
			} :: { Choice },
		},
		stop = {
			lines = {
				"And be replaced within the quarter by someone who does not keep records. -- I know how that sounds. It is also the only true thing I have said today: my successor's quota would be the same and there would be no manifest for you to be holding.",
			},
			choices = { WORK, LEAVE },
		},
		manifest = {
			lines = {
				"Then you have my signature, my requisition numbers and the shipping schedule, and none of it is a crime in any jurisdiction that has an office on this planet. -- Take it to the Republic. I am serious. Watch what they do with it, and then come back and we will have a much shorter conversation.",
			},
			choices = { WORK, LEAVE },
		},
		named = {
			lines = {
				"The Quiet. -- How very Jedi. We call it attrition, in the schedule, because a schedule needs a word for the difference between what arrives and what is usable. -- I have been putting a number in that column for six years without once asking what it was a number of.",
			},
			choices = { WORK, LEAVE },
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

	A pure function over `ctx` rather than a lookup, so the client could also
	run it if a preview is ever wanted -- and so the server can build the
	context once per conversation instead of once per choice.
]]
function Dialogue.meets(condition: Condition?, ctx: Context): boolean
	if not condition then
		return true
	end
	if condition.origin and condition.origin ~= ctx.origin then
		return false
	end
	if condition.minLevel and ctx.level < condition.minLevel then
		return false
	end
	if condition.minRep and ctx.rep < condition.minRep then
		return false
	end
	if condition.maxRep and ctx.rep > condition.maxRep then
		return false
	end
	if condition.missionActive and not ctx.activeMissions[condition.missionActive] then
		return false
	end
	if condition.missionCompleted and not ctx.completedMissions[condition.missionCompleted] then
		return false
	end
	if condition.missionNotCompleted and ctx.completedMissions[condition.missionNotCompleted] then
		return false
	end
	if condition.flag and not ctx.flags[condition.flag] then
		return false
	end
	if condition.notFlag and ctx.flags[condition.notFlag] then
		return false
	end
	if condition.minAlignment and ctx.alignment < condition.minAlignment then
		return false
	end
	if condition.maxAlignment and ctx.alignment > condition.maxAlignment then
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
function Dialogue.validate(
	missionExists: (string) -> boolean,
	originExists: (string) -> boolean,
	flagExists: (string) -> boolean
): { string }
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
				--[[
					A choice that neither walks anywhere nor does anything just
					closes the panel, which is almost never what was meant --
					unless it moves the character, in which case ending the
					conversation on the decision is exactly the point.
				]]
				if not choice.next and not choice.action and not choice.alignment and not choice.sets then
					table.insert(problems, `{id}.{nodeId}: choice {i} has neither next nor action`)
				end

				--[[
					An undeclared flag is written to a profile nothing reads and
					no condition can ever match, which looks precisely like a
					branch the author forgot to finish. Same check on both
					sides, because either half being misspelt breaks the pair.
				]]
				local sets: { string } = choice.sets or {}
				for _, flagId in sets do
					if not flagExists(flagId) then
						table.insert(problems, `{id}.{nodeId}: choice {i} sets undeclared flag "{flagId}"`)
					end
				end

				--[[
					AN ALIGNMENT CHOICE MUST BE ABLE TO CLOSE ITSELF

					A conversation can be reopened as often as the player
					likes, and archetypes spawn in the dozens -- eighteen
					Cartel enforcers stand on one Nar Shaddaa street. A choice
					that pays alignment and cannot become unavailable is
					therefore a button that pays alignment forever, and this
					game is played by two brothers in one room who will find
					it within the hour.

					The fix is a convention -- set a flag, condition on
					`notFlag` for it -- and a convention nothing checks is a
					convention that holds until the day somebody is in a
					hurry. So it is checked.
				]]
				if choice.alignment and choice.alignment ~= 0 then
					local guard = choice.condition and choice.condition.notFlag
					local guarded = false
					for _, flagId in sets do
						if flagId == guard then
							guarded = true
						end
					end
					if not guarded then
						table.insert(
							problems,
							`{id}.{nodeId}: choice {i} moves alignment but can be taken again `
								.. "(needs a flag in 'sets' matched by 'condition.notFlag')"
						)
					end
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
					-- A misspelt origin is a line no character can ever be
					-- shown, which reads exactly like a line nobody wrote.
					if c.origin ~= nil and not originExists(c.origin) then
						table.insert(problems, `{id}.{nodeId}: choice {i} names unknown origin "{c.origin}"`)
					end
					local function checkFlag(named: string?)
						if named ~= nil and not flagExists(named) then
							table.insert(
								problems,
								`{id}.{nodeId}: choice {i} reads undeclared flag "{named}"`
							)
						end
					end
					checkFlag(c.flag)
					checkFlag(c.notFlag)
				end
			end
		end
	end

	table.sort(problems)
	return problems
end

return Dialogue
