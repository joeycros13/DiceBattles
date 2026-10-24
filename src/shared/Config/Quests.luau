--!strict
-- Quests: every questline, one per quest giver, shared by QuestService (server:
-- progress, rewards) and the client (QuestController's dialogue, QuestTrackerUI,
-- GuideController's arrow).
--   DaleFarm        Dale the Farmer, "Trouble on Dale's Farm" (World 1, 2026-10-08,
--                   the user's design)
--   RangerRedwoods  Ranger Rowan, "Trouble in the Redwoods" (World 2, 2026-10-11);
--                   the final reward is the Firefly Lantern (LanternFlail)
--   ExplorerCaverns Explorer Pip, "Into the Crystal Caverns" (World 3, 2026-10-17,
--                   picked on the design canvas); the final reward is the Diamond
--                   Pickaxe. Level steps follow the other lines: the first comes at the
--                   same EXP as before the 2026-10-19 curve (36), the second at the
--                   second set's level (42).
-- Lines run side by side: each player has a step in every line, published as
-- per-line attributes (Quests.attr). A giver model (tagged QuestGiver) names its
-- line in its "QuestLine" attribute. Add a line to `lines` and `order` and give it
-- a giver; nothing else needs to change.
--
-- Each line has an id, name, short (the tracker tab), world (the world whose
-- tracker shows it first), npc { name, short, portrait }, returnTrack, returnNote,
-- finished, and steps. Steps run one at a time. Each step has:
--   kind       "kill"  defeat `count` of enemy `target` (a Config/Worlds id)
--              "earn"  earn `amount` coins, counted from accepting
--              "level" reach level `level`
--              "give"  hand Dale `amount` coins (taken when handing in)
--              "gather" gather `count` of material `target` (a Config/Materials id),
--                      counted from accepting (2026-10-19: chopping, mining)
--              "bring" hand over `items` ({ { id, count } } materials, taken when
--                      handing in); progress is the total held toward the total
--                      needed. Fish never go in quests (user: they're for potions)
--   objective  the red objective line in the dialogue's Objective box
--   track      the tracker line: the words before {braces} become the small
--              label ("DEFEAT"), the part in braces the red name (the enemy or
--              thing to look for)
--   reward     coins / exp given when handing in (weapon = a Config/Weapons id;
--              item = a Config/Materials quest item, given once: each line's
--              "defeat the boss" step hands over the item its world's second
--              armour set needs, 2026-10-12)
--   offer      the giver's lines when giving the quest
--   reminder   their line if you talk to them mid-quest
--   complete   their lines when you hand it in
-- In dialogue lines, [square brackets] mark the objective: bold and red.
--
-- A gather / bring step whose material comes from a node the player has no good
-- enough tool for runs in two phases on the tracker (2026-10-21, the user): first
-- "Buy a {Wooden Axe}" / "Upgrade to a {Stone Axe}" at the Weaponsmith
-- (Quests.toolNeeded, Quests.ToolText; the guide arrow points at that world's
-- Weapons stall), then the gathering itself. The server's step doesn't change: the
-- tool phase is only what the tracker and the arrow show while the tool is missing.
--
-- All the wording and numbers here are free to edit.

local Gathering = require(script.Parent:WaitForChild("Gathering"))
local Tools = require(script.Parent:WaitForChild("Tools"))

-- World scale (2026-10-23, Config/Leveling): every step's EXP x1 / x4 / x16 for Worlds 1 / 2 / 3, like
-- the EXP a level needs there. Coins are unscaled (they already grew x10 a world).

local Quests = {}

-- The tracker's tool phase: the line (a tool's name goes in the braces) and the note
-- under it (the stall's name).
Quests.ToolText = {
	buy = "Buy a {%s}",
	upgrade = "Upgrade to a {%s}",
	note = "at the Weaponsmith",
}

export type Reward = { coins: number?, exp: number?, weapon: string?, item: string? }
export type Step = {
	kind: string,
	target: string?,
	count: number?,
	items: { { id: string, count: number } }?,
	amount: number?,
	level: number?,
	objective: string,
	track: string,
	reward: Reward,
	offer: { string },
	reminder: { string },
	complete: { string },
}
export type Line = {
	id: string,
	name: string,
	short: string,
	world: number,
	npc: { name: string, short: string, portrait: string },
	returnTrack: string,
	returnNote: string,
	finished: { string },
	steps: { Step },
}

local lines: { [string]: Line } = {}

lines.DaleFarm = {
	id = "DaleFarm",
	name = "Trouble on Dale's Farm",
	world = 1,
	-- the tracker's title
	short = "Dale's Farm",
	npc = {
		name = "Dale the Farmer",
		short = "Dale",
		-- art/quest/portrait_Dale.png
		portrait = "rbxassetid://72658452496108",
	},
	-- the tracker line once a step is done
	returnTrack = "Return to {Dale the Farmer}",
	returnNote = "to claim your reward",
	-- what he says once every step is done
	finished = { "Thanks to you, the farm's peaceful again. Come by anytime, partner!" },
	steps = {
		{
			kind = "kill",
			target = "Chicken",
			count = 5,
			objective = "Defeat 5 Angry Chickens",
			track = "Defeat {Angry Chickens}",
			reward = { coins = 25, exp = 20 },
			offer = {
				"Well howdy there, partner! Name's Dale. I've been farmin' this here meadow for forty years.",
				"Lately my chickens have gone plumb mad. Peckin' my crops, peckin' my boots, peckin' ME!",
				"Reckon you could [defeat 5 Angry Chickens] for me? I'll make it worth your while.",
			},
			reminder = { "Them chickens are still runnin' wild! [Defeat 5 Angry Chickens], would ya?" },
			complete = { "Well I'll be! Five fewer feathered menaces. Here, take this for your trouble." },
		},
		{
			-- 2026-10-19 (user): was "earn 75 coins"; teaches the axe early
			kind = "gather",
			target = "OakLog",
			count = 5,
			objective = "Chop 5 Oak Logs",
			track = "Chop {Oak Logs}",
			reward = { coins = 30, exp = 30 },
			offer = {
				"Now, a farmhand's gotta keep the stove burnin', and that means firewood.",
				"You can't chop a tree with that little dagger, though. The Weaponsmith on the plaza sells all the tools: axes, pickaxes, fishin' rods.",
				"Pick yourself up a [Wooden Axe] first. Then head to them big oaks by the cliffs and [chop 5 Oak Logs].",
			},
			reminder = { "Got your axe from the Weaponsmith on the plaza? Then [chop 5 Oak Logs] and come see me." },
			complete = { "Now that's a fine stack of firewood! Here's a little somethin' for the sweat." },
		},
		{
			kind = "kill",
			target = "Chicken",
			count = 10,
			objective = "Defeat 10 Angry Chickens",
			track = "Defeat {Angry Chickens}",
			reward = { coins = 40, exp = 40 },
			offer = {
				"Bad news, partner. Them chickens multiplied overnight.",
				"I need you to [defeat 10 Angry Chickens] before they eat my whole carrot patch!",
			},
			reminder = { "Still a whole lotta cluckin' out there! [Defeat 10 Angry Chickens]." },
			complete = { "Ten more down! My carrots thank ya. So do I." },
		},
		{
			kind = "kill",
			target = "Bull",
			count = 3,
			objective = "Defeat 3 Raging Bulls",
			track = "Defeat {Raging Bulls}",
			reward = { coins = 60, exp = 60 },
			offer = {
				"Somethin' bigger's stirrin' now. Them bulls up the paths are seein' red.",
				"They knocked my fence clean over! [Defeat 3 Raging Bulls] and teach 'em some manners.",
			},
			reminder = { "Watch them horns! [Defeat 3 Raging Bulls]." },
			complete = { "Three bulls! You're tougher than you look, friend." },
		},
		{
			kind = "level",
			level = 9,
			objective = "Reach level 9",
			track = "Reach {Level 9}",
			-- + the Rusty Blade (Relic), the start of the secret super weapon (2026-10-12)
			reward = { coins = 50, weapon = "RustyBlade" },
			offer = {
				"Them bulls'll only get meaner from here. You gotta toughen up.",
				"Go get some practice in and [reach level 9]. Come back when you're ready.",
			},
			reminder = { "Keep at it! [Reach level 9] first." },
			complete = {
				"Now that's a seasoned fighter if I ever saw one!",
				"Here, I dug this old blade up behind the barn. Rusty as anything... but that empty socket's always made me wonder.",
			},
		},
		{
			-- 2026-10-19 (user): was "give 200 coins"; the logs and stone are taken at hand-in
			kind = "bring",
			items = { { id = "OakLog", count = 8 }, { id = "Stone", count = 8 } },
			objective = "Bring Dale 8 Oak Logs and 8 Stone",
			track = "Bring Dale {Logs and Stone}",
			reward = { coins = 80, exp = 100 },
			offer = {
				"I hate to ask, but them bulls flattened my barn door and knocked the wall stones loose.",
				"Could you [bring me 8 Oak Logs and 8 Stone] for the repairs? A pickaxe'll crack them boulders; the Weaponsmith sells those too.",
			},
			reminder = { "No rush... but my barn door's still flat. [Bring me 8 Oak Logs and 8 Stone]." },
			complete = { "Bless ya! That door'll be standin' by sundown. Here, it ain't much, but it's honest." },
		},
		{
			kind = "kill",
			target = "Bull",
			count = 5,
			objective = "Defeat 5 Raging Bulls",
			track = "Defeat {Raging Bulls}",
			reward = { coins = 100, exp = 100 },
			offer = {
				"Word is the bulls are gatherin' near the boss platform.",
				"Head up there and [defeat 5 Raging Bulls] before they stampede the whole valley.",
			},
			reminder = { "Them bulls ain't gonna fight themselves! [Defeat 5 Raging Bulls]." },
			complete = { "The valley's quiet for the first time in weeks. Thank ya kindly." },
		},
		{
			kind = "kill",
			target = "BossScarecrow",
			count = 1,
			objective = "Defeat the Scarecrow King",
			track = "Defeat the {Scarecrow King}",
			reward = { coins = 150, exp = 150, item = "LuckyHorseshoe" },
			offer = {
				"Now I know who's behind all this ruckus. The Scarecrow King!",
				"He's been riling up my animals from that platform up north. [Defeat the Scarecrow King]!",
			},
			reminder = { "That pumpkin-headed menace is still up there! [Defeat the Scarecrow King]." },
			complete = {
				"You beat the Scarecrow King?! Well, I'll be a monkey's uncle!",
				"Here, take my [lucky horseshoe]. The crafter in town can work it into some fine armor.",
			},
		},
		{
			kind = "level",
			level = 14,
			objective = "Reach level 14",
			track = "Reach {Level 14}",
			reward = { coins = 100 },
			offer = {
				"Bad news. That old scarecrow's stitched himself back together.",
				"He comes back stronger every time. Go [reach level 14] so you can stand up to him.",
			},
			reminder = { "Keep trainin'! [Reach level 14]." },
			complete = { "Look at ya! The strongest farmhand this meadow's ever seen." },
		},
		{
			kind = "kill",
			target = "BossScarecrow",
			count = 5,
			objective = "Defeat the Scarecrow King 5 times",
			track = "Defeat the {Scarecrow King}",
			-- The quest-only Weathervane Spear (Legendary, 2026-10-11).
			reward = { coins = 300, exp = 300, weapon = "WeathervaneSpear" },
			offer = {
				"This is it, partner. The Scarecrow King has to learn his lesson for good.",
				"[Defeat the Scarecrow King 5 times] and he'll never bother this farm again.",
				"Do this, and I'll give ya somethin' I've been savin' a long, long time.",
			},
			reminder = { "He keeps comin' back! [Defeat the Scarecrow King 5 times]." },
			complete = {
				"You did it! The farm's safe at last.",
				"Here. This was my granddaddy's. I reckon it's yours now.",
			},
		},
	} :: { Step },
}

-- Ranger Rowan on the cabin porch at the World 2 camp (2026-10-11). Numbers are
-- starting values (the user will tune them later).
-- Rewards are x10 Dale's, step for step (2026-10-24, the rescale: coins and EXP x10 a world).
lines.RangerRedwoods = {
	id = "RangerRedwoods",
	name = "Trouble in the Redwoods",
	world = 2,
	short = "The Redwoods",
	npc = {
		name = "Ranger Rowan",
		short = "Rowan",
		-- art/quest/portrait_Rowan.png
		portrait = "rbxassetid://92115376888229",
	},
	returnTrack = "Return to {Ranger Rowan}",
	returnNote = "to claim your reward",
	finished = { "Thanks to you, the redwoods are at peace. My fire's always warm for you, friend." },
	steps = {
		{
			kind = "kill",
			target = "Fox",
			count = 5,
			objective = "Defeat 5 Snarling Foxes",
			track = "Defeat {Snarling Foxes}",
			reward = { coins = 250, exp = 200 },
			offer = {
				"Evening, traveller. I'm Ranger Rowan. I look after these redwoods.",
				"Something has the wildlife riled up. The foxes snap at anything that moves.",
				"Could you [defeat 5 Snarling Foxes] for me? They won't make it easy.",
			},
			reminder = { "Those foxes are still prowling the trails. [Defeat 5 Snarling Foxes]." },
			complete = { "That's a relief. The trail's safer already. Here, for your trouble." },
		},
		{
			-- 2026-10-21 (user): was "earn 300 coins"; the fur goes toward the Stone Axe
			kind = "gather",
			target = "FoxFur",
			count = 6,
			objective = "Collect 6 Fox Fur",
			track = "Collect {Fox Fur}",
			reward = { coins = 300, exp = 300 },
			offer = {
				"Your old wooden axe won't bite into a redwood. You'll want a Stone Axe.",
				"The weaponsmith wraps their grips in fox fur. Go and [collect 6 Fox Fur] from the foxes on the trail.",
			},
			reminder = { "Those foxes still have their coats. [Collect 6 Fox Fur]." },
			complete = { "Thick and warm. That'll make a fine grip. Now all you need is a boar tusk or two." },
		},
		{
			kind = "kill",
			target = "Fox",
			count = 10,
			objective = "Defeat 10 Snarling Foxes",
			track = "Defeat {Snarling Foxes}",
			reward = { coins = 400, exp = 400 },
			offer = {
				"I counted tracks this morning. Far more foxes than there should be.",
				"Please [defeat 10 Snarling Foxes] before they overrun the camp.",
			},
			reminder = { "I can still hear them yipping. [Defeat 10 Snarling Foxes]." },
			complete = { "Quiet at last. You move through these woods like you were born here." },
		},
		{
			kind = "kill",
			target = "Boar",
			count = 3,
			objective = "Defeat 3 Wild Boars",
			track = "Defeat {Wild Boars}",
			reward = { coins = 600, exp = 600 },
			offer = {
				"Now the boars are charging hikers right off the trail.",
				"Their hides are thick, so hit hard. [Defeat 3 Wild Boars].",
			},
			reminder = { "Mind those tusks! [Defeat 3 Wild Boars]." },
			complete = { "Three boars! I'll mark those trails open again." },
		},
		{
			kind = "level",
			level = 30, -- 22 until 2026-10-20: players arrive at 25 since the World 2 gate moved to level 25
			objective = "Reach level 30",
			track = "Reach {Level 30}",
			reward = { coins = 500 },
			offer = {
				"Deeper in, the bears are waking up angry. You're not ready for them yet.",
				"Train up and [reach level 30]. I'll be right here by the fire.",
			},
			reminder = { "Keep training. [Reach level 30] first." },
			complete = { "Look at you. Strong enough to stare down a grizzly." },
		},
		{
			-- 2026-10-21 (user): was "give 600 coins"; the logs and tusks are taken at hand-in
			kind = "bring",
			items = { { id = "RedwoodLog", count = 10 }, { id = "BoarTusk", count = 4 } },
			objective = "Bring Rowan 10 Redwood Logs and 4 Boar Tusks",
			track = "Bring Rowan {Logs and Tusks}",
			reward = { coins = 800, exp = 1000 },
			offer = {
				"The boars battered the lookout tower. I can't keep watch from up there like this.",
				"Could you [bring me 10 Redwood Logs and 4 Boar Tusks]? Logs for the beams, tusks for pegs.",
				"Only a Stone Axe will fell a redwood. The Weaponsmith by the gate can turn your wooden axe into one.",
			},
			reminder = { "The tower still needs fixing. [Bring me 10 Redwood Logs and 4 Boar Tusks]." },
			complete = { "Thank you. The tower will be standing tall by morning. Take this, it's what I can spare." },
		},
		{
			kind = "kill",
			target = "Bear",
			count = 2,
			objective = "Defeat 2 Grizzly Bears",
			track = "Defeat {Grizzly Bears}",
			reward = { coins = 1000, exp = 1000 },
			offer = {
				"From the tower I spotted two grizzlies guarding the path to the old ruins.",
				"[Defeat 2 Grizzly Bears] so we can find out what's stirring in there.",
			},
			reminder = { "The bears still block the ruins. [Defeat 2 Grizzly Bears]." },
			complete = { "The path's clear. And now I know what's behind all this..." },
		},
		{
			kind = "kill",
			target = "ElderTreant",
			count = 1,
			objective = "Defeat the Elder Treant",
			track = "Defeat the {Elder Treant}",
			reward = { coins = 1500, exp = 1500, item = "RangerBadge" },
			offer = {
				"The Elder Treant. The oldest tree in the forest has woken, and it's furious.",
				"Its rage is spreading to every creature here. Go to the ruins and [defeat the Elder Treant].",
			},
			reminder = { "The ruins lie past the bears' path. [Defeat the Elder Treant]." },
			complete = {
				"You felled the Elder Treant?! In all my years, I've never seen the like.",
				"You've earned this: my [ranger's badge]. Any crafter will know what it means.",
			},
		},
		{
			kind = "level",
			level = 34, -- 27 until 2026-10-20 (World 2 balance)
			objective = "Reach level 34",
			track = "Reach {Level 34}",
			reward = { coins = 1000 },
			offer = {
				"Bad news. Roots don't die easily. The treant is growing back, stronger than before.",
				"You'll need to be stronger too. [Reach level 34].",
			},
			reminder = { "Keep at it. [Reach level 34]." },
			complete = { "The strongest warden these woods have ever had." },
		},
		{
			kind = "kill",
			target = "ElderTreant",
			count = 5, -- 3 until 2026-10-20 (World 2 balance; Dale's is 5 too)
			objective = "Defeat the Elder Treant 5 times",
			track = "Defeat the {Elder Treant}",
			-- The quest-only Firefly Lantern (Legendary, 2026-10-11).
			reward = { coins = 3000, exp = 3000, weapon = "LanternFlail" },
			offer = {
				"This is it. We have to calm that old tree for good.",
				"[Defeat the Elder Treant 5 times] and the forest can finally rest.",
				"Do this, and I'll trust you with something very special.",
			},
			reminder = { "It keeps regrowing! [Defeat the Elder Treant 5 times]." },
			complete = {
				"You did it. Listen... the forest is quiet again.",
				"This lantern has lit my way for years. The fireflies chose you. It's yours now.",
			},
		},
	} :: { Step },
}

-- Explorer Pip beside the boarded-up mine entrance at the end of the World 3 entry
-- hall (2026-10-17). His mapping crew went missing deeper in; they turn up past the
-- Spider Queen's hall. Numbers are starting values, about twice Rowan's.
-- Rewards x10 Rowan's step for step and the coin steps 2,000 / 10,000 (2026-10-24, the rescale). Level steps 60 / 65
-- (players arrive at 50; were 55 / 59, but Pip's EXP rewards got a player there in 5 and 8 minutes): with
-- world_sim.py they come about a third and two fifths of the way through World 3, as Rowan's 30 / 34 do in World 2.
lines.ExplorerCaverns = {
	id = "ExplorerCaverns",
	name = "Into the Crystal Caverns",
	world = 3,
	short = "The Caverns",
	npc = {
		name = "Explorer Pip",
		short = "Pip",
		-- art/quest/portrait_Pip.png (determined-cohen worktree, 2026-10-17)
		portrait = "rbxassetid://111659781861627",
	},
	returnTrack = "Return to {Explorer Pip}",
	returnNote = "to claim your reward",
	finished = { "Every tunnel's on my map now, thanks to you. The crew says hello. Come back any time, partner!" },
	steps = {
		{
			kind = "kill",
			target = "CaveBat",
			count = 5,
			objective = "Defeat 5 Cave Bats",
			track = "Defeat {Cave Bats}",
			reward = { coins = 2500, exp = 2000 },
			offer = {
				"Oh! A real person, down here! I'm Pip, explorer and map-maker.",
				"My crew went deeper into these caverns to map them, and they never came back.",
				"The bats keep flapping my lantern out. Could you [defeat 5 Cave Bats] so I can see where I'm going?",
			},
			reminder = { "Still too many wings in the dark. [Defeat 5 Cave Bats], please!" },
			complete = { "Light! Lovely, steady light. You're handy to have around." },
		},
		{
			-- (2026-10-24) World 3's gathering, like Dale's and Rowan's step 2: the Ore Rocks
			kind = "gather",
			target = "IronOre",
			count = 5,
			objective = "Mine 5 Iron Ore",
			track = "Mine {Iron Ore}",
			reward = { coins = 3000, exp = 3000 },
			offer = {
				"My crew's pick snapped down here, and mine's a wooden toy next to these rocks.",
				"The Weaponsmith by the way in can turn your wooden pickaxe into a Crystal Pickaxe.",
				"Then find the grey rocks streaked with orange and [mine 5 Iron Ore]. I'll forge new pitons from it.",
			},
			reminder = { "Grey rocks, orange veins. [Mine 5 Iron Ore] with a Crystal Pickaxe." },
			complete = { "Good solid ore! A natural! Now let's go find that trail." },
		},
		{
			kind = "kill",
			target = "CaveBat",
			count = 10,
			objective = "Defeat 10 Cave Bats",
			track = "Defeat {Cave Bats}",
			reward = { coins = 4000, exp = 4000 },
			offer = {
				"My crew marked their path on the walls, but the bats nested right over it.",
				"[Defeat 10 Cave Bats] and clear the way.",
			},
			reminder = { "The marks are under all those bats. [Defeat 10 Cave Bats]." },
			complete = { "There! Chalk arrows, and a boot print. They came this way!" },
		},
		{
			kind = "kill",
			target = "PebbleGolem",
			count = 3,
			objective = "Defeat 3 Pebble Golems",
			track = "Defeat {Pebble Golems}",
			reward = { coins = 6000, exp = 6000 },
			offer = {
				"The arrows point down the tunnels, but the rocks there walk.",
				"[Defeat 3 Pebble Golems] so I can chart it.",
			},
			reminder = { "Can't draw a map with the map walking around. [Defeat 3 Pebble Golems]." },
			complete = { "Charted! Well, it's mostly pebbles now." },
		},
		{
			kind = "level",
			level = 60,
			objective = "Reach level 60",
			track = "Reach {Level 60}",
			reward = { coins = 5000 },
			offer = {
				"The tunnel ends at a sheer drop. Whatever's down there isn't for beginners.",
				"Come back when you [reach level 60].",
			},
			reminder = { "Toughen up a bit first. [Reach level 60]." },
			complete = { "Look at you! Tougher than a stalagmite." },
		},
		{
			-- (2026-10-24) the mined bring step, like Rowan's step 6 (x10 its reward)
			kind = "bring",
			items = { { id = "IronOre", count = 10 }, { id = "CrystalShard", count = 10 } },
			objective = "Bring Pip 10 Iron Ore and 10 Crystal Shards",
			track = "Bring Pip {Ore and Shards}",
			reward = { coins = 8000, exp = 10000 },
			offer = {
				"The old winch at the drop is busted. It needs new gears and a new lamp.",
				"Could you [bring me 10 Iron Ore and 10 Crystal Shards]? Ore for the gears, shards for the light.",
				"The crystal clusters glow pink and purple and blue. Your Crystal Pickaxe will crack them.",
			},
			reminder = { "No gears, no light, no way down. [Bring me 10 Iron Ore and 10 Crystal Shards]." },
			complete = { "Clank, whirr, glow, perfect! Hold on tight, we're going down." },
		},
		{
			kind = "kill",
			target = "CrystalGolem",
			count = 2,
			objective = "Defeat 2 Crystal Golems",
			track = "Defeat {Crystal Golems}",
			reward = { coins = 10000, exp = 10000 },
			offer = {
				"Bad news: the lower hall is guarded by Crystal Golems. Big shiny ones.",
				"[Defeat 2 Crystal Golems] and we're through.",
			},
			reminder = { "They're pretty, but they're in the way. [Defeat 2 Crystal Golems]." },
			complete = { "We're through! And there's webbing everywhere. I don't like webbing." },
		},
		{
			kind = "kill",
			target = "SpiderQueen",
			count = 1,
			objective = "Defeat the Spider Queen",
			track = "Defeat the {Spider Queen}",
			reward = { coins = 15000, exp = 15000, item = "MinersLantern" },
			offer = {
				"That's the one hall nobody's ever mapped. The Spider Queen lives there.",
				"I think she has my crew's gear. [Defeat the Spider Queen] and look for anything of theirs.",
			},
			reminder = { "She's in the big hall past the webs. [Defeat the Spider Queen]." },
			complete = {
				"That lantern! It's our miner's. And if she dropped it, the crew got past her.",
				"Keep the [miner's lantern]. The crafter here can work it into some fine armor.",
			},
		},
		{
			kind = "level",
			level = 65,
			objective = "Reach level 65",
			track = "Reach {Level 65}",
			reward = { coins = 10000 },
			offer = {
				"Fresh tracks lead past her hall, deeper than any map. We'll need you at your best.",
				"[Reach level 65] first.",
			},
			reminder = { "Not yet, not yet. [Reach level 65]." },
			complete = { "Ready? Me too. Let's finish this." },
		},
		{
			kind = "kill",
			target = "SpiderQueen",
			count = 3,
			objective = "Defeat the Spider Queen 3 times",
			track = "Defeat the {Spider Queen}",
			-- The quest-only Diamond Pickaxe (Legendary).
			reward = { coins = 30000, exp = 30000, weapon = "DiamondPickaxe" },
			offer = {
				"She keeps coming back, and every time she seals the tunnel behind her with web.",
				"[Defeat the Spider Queen 3 times] and we'll break through for good.",
			},
			reminder = { "The web's thinning! [Defeat the Spider Queen 3 times]." },
			complete = {
				"We're through, and my crew's safe on the other side!",
				"They dug this up down there. A diamond pickaxe. It's yours, partner.",
			},
		},
	} :: { Step },
}

Quests.lines = lines
-- the order lines are checked in (the tracker's fallback when the player's
-- world has nothing to show)
Quests.order = { "DaleFarm", "RangerRedwoods", "ExplorerCaverns" }

function Quests.get(id: any): Line?
	return if type(id) == "string" then lines[id] else nil
end

-- The player attribute a line's field is published on: Quests.attr("Step",
-- "DaleFarm") -> "QuestStep_DaleFarm". Fields: Step, State, Progress (server),
-- and ShownState (client-only, the state as the tracker shows it).
function Quests.attr(field: string, id: string): string
	return ("Quest%s_%s"):format(field, id)
end

-- Which line the tracker and guide arrow follow (client): the line of the world
-- the player stands in (its "CurrentWorld" attribute, set by WorldBannerUI) if
-- that line has a step under way (Active / Ready), otherwise the first line in
-- `order` that has one. Nil when nothing is under way.
function Quests.tracked(player: Player): Line?
	local function busy(line: Line): boolean
		local state = player:GetAttribute(Quests.attr("State", line.id))
		return state == "Active" or state == "Ready"
	end
	local world = player:GetAttribute("CurrentWorld")
	for _, id in Quests.order do
		local line = lines[id]
		if line and line.world == world and busy(line) then
			return line
		end
	end
	for _, id in Quests.order do
		local line = lines[id]
		if line and busy(line) then
			return line
		end
	end
	return nil
end

-- How much progress finishes a step.
function Quests.goal(step: Step): number
	if step.kind == "kill" or step.kind == "gather" then
		return step.count or 1
	elseif step.kind == "level" then
		return step.level or 1
	elseif step.kind == "bring" then
		local total = 0
		for _, item in step.items or {} do
			total += item.count
		end
		return math.max(total, 1)
	end
	return step.amount or 1
end

-- The material a gather / bring step is about (its icon on the dialogue and tracker).
function Quests.material(step: Step): string?
	if step.kind == "gather" then
		return step.target
	elseif step.kind == "bring" then
		local first = step.items and step.items[1]
		return first and first.id
	end
	return nil
end

-- The tool a gather / bring step still needs before its material can be gathered (see
-- the header): the lowest tier of the node's tool kind that can break it, or nil once
-- the player owns one as good (or the material isn't from a node, like Fox Fur). A
-- bring step only asks about the items still short.
function Quests.toolNeeded(step: Step, player: Player): Tools.ToolDef?
	local ids: { string } = {}
	if step.kind == "gather" and step.target then
		ids = { step.target }
	elseif step.kind == "bring" then
		local held = player:GetAttribute("Materials")
		for _, item in step.items or {} do
			local n = if type(held) == "string" then tonumber(held:match("%f[%w]" .. item.id .. "=(%d+)") or "0") else 0
			if (n or 0) < item.count then
				table.insert(ids, item.id)
			end
		end
	end
	local owned = Tools.owned(player)
	for _, id in ids do
		for _, node in Gathering.Nodes do
			for _, drop in node.drops do
				if drop.id == id then
					local best = Tools.bestOf(owned, node.tool)
					if best == nil or best.tier < node.tier then
						local pick: Tools.ToolDef? = nil
						for _, def in Tools.Defs do
							if def.kind == node.tool and def.tier >= node.tier and (pick == nil or def.tier < pick.tier) then
								pick = def
							end
						end
						return pick
					end
				end
			end
		end
	end
	return nil
end

return Quests
