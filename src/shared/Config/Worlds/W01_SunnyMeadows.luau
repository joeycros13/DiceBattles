--!strict
-- World 1: The Sunny Meadows (renamed from The Green Meadows, 2026-10-11).
--
-- A world file owns everything about one world: its enemy roster and its boss.
-- Adding a world means adding a file like this one and listing it in
-- Worlds/init.luau.

local WorldTypes = require(script.Parent.Parent.WorldTypes)

-- World scale (2026-10-23, the user: World 1 near 100, World 2 1K, World 3 10K...; Config/Leveling):
-- every enemy's health x2, like the weapons; damage, coins and EXP unchanged (World 1 is x1). Health
-- numbers in older comments are before it.
--
-- The base fight (2026-10-24, the user's anchor for every world's numbers, memory world-scaling-baseline):
-- a fresh level-1 player with only the Trowel loses about 50% of their health fighting a Chicken
-- (art/tools/balance/base_fights.py: 22 damage, two pecks most fights, three in some; it was 6, 14%).
-- The rest keep their damage ratio to the Chicken (x3.67): Bull 59, Stallion 73, Scarecrow King 81,
-- Corn Wraith 55 (16 / 20 / 22 / 15 before). Health, coins and EXP are unchanged; with the new
-- level curve (Config/Leveling) a typical player still buys the World 2 gate in 29.9 min.
--
-- The reward ladder (2026-10-24, the user: spread the elite grind, elites still the best way to level,
-- the boss worth a hefty amount but not the best to farm; its pull is its weapon drops). Per kill, in
-- elites, for both EXP and coins: small 0.37, medium 0.7, elite 1, boss 4.3, the secret enemy 1.4. Per
-- second for a player mid to late in the world (art/tools/balance/rates_probe.py): small 64-73%, medium
-- 74-84%, elite 100%, boss 77-94% (one spot, a long fight and a 30 s respawn). Each world's whole ladder
-- is then scaled to its time target with world_sim.py.
-- World 1 at 0.75x: 30.1 min to the gate (a min-maxer; one who fights whatever pays within 25% 30.7).

local World: WorldTypes.WorldDef = {
	id = 1,
	name = "The Sunny Meadows",
	folder = "W01_SunnyMeadows",
	-- the Index world card (re-shot 2026-10-19 for the grown map, no enemies; art/portraits/worlds/world_W01_2026-10-19.png)
	profile = "rbxassetid://85727377419936",
	-- "Golden afternoon" (the user's pick, 2026-10-21): a later, warmer sun.
	lighting = {
		ClockTime = 16.2,
		Brightness = 2.6,
		ExposureCompensation = -0.2,
		Ambient = Color3.fromHex("50464f"),
		OutdoorAmbient = Color3.fromHex("a89c9a"),
		ColorShift_Top = Color3.fromHex("ffd6a0"),
		Atmosphere = { Density = 0.32, Offset = 0.2, Color = Color3.fromHex("ffe6c8"), Decay = Color3.fromHex("c0906e"), Glare = 0.3, Haze = 1.0 },
		ColorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0.2, TintColor = Color3.fromHex("fff1e0") },
		SunRays = { Intensity = 0.06, Spread = 0.6 },
	},

	-- Respawn seconds by kind (the user's rule, 2026-10-19): every enemy of a tier
	-- comes back after the same time in its world; bosses and the secret enemy
	-- after `boss` / `secret`. A spawn marker's RespawnSeconds attribute still wins.
	respawn = { small = 10, medium = 15, elite = 20, boss = 30, secret = 30 },

	enemies = {
		-- Minion: the weakest world enemy, in flocks along the front of every path
		-- (ServerStorage/Assets/Enemies/Chicken).
		Chicken = {
			id = "Chicken",
			tier = "small",
			name = "Angry Chicken",
			hp = 80,
			portrait = "rbxassetid://119866244895251", -- calm face (2026-10-11)
			-- Quick, weak pecks.
			melee = { damage = 22, cooldown = 1.2, windup = 0.25, range = 1.5, chaseSpeed = 15, armor = 0, move = "peck" },
			-- Coins and rates are tuned for a ~30-minute World 1 (2026-10-19; see Balance).
			coins = { min = 9, max = 18 },
			exp = 12,
			drops = {
				{ weapon = "Sickle", chance = 0.20 },
				{ weapon = "Machete", chance = 0.05 },
			},
			-- crafting materials (Config/Materials): the first armour set
			materials = { { id = "ChickenFeather", chance = 0.5, min = 1, max = 2 } },
		},
		-- Elite: guards the far end of each path before the boss platform. Hits
		-- harder, so it is a real check before the boss
		-- (ServerStorage/Assets/Enemies/Bull).
		Bull = {
			id = "Bull",
			tier = "medium",
			name = "Raging Bull",
			hp = 190, -- 140 until 2026-10-20 (the health ladder: Chicken < Bull < Stallion < King)
			portrait = "rbxassetid://105217136953827", -- calm face (2026-10-11)
			-- Slow, heavy horn charges with a long reach.
			melee = { damage = 59, cooldown = 2.0, windup = 0.45, range = 1.5, chaseSpeed = 14, armor = 0.1, move = "gore" },
			coins = { min = 18, max = 35 },
			exp = 22,
			drops = {
				{ weapon = "Machete", chance = 0.25 },
				{ weapon = "Pitchfork", chance = 0.15 },
				{ weapon = "Shovel", chance = 0.15 },
			},
			materials = { { id = "BullHide", chance = 0.5, min = 1, max = 2 } },
		},
		-- Elite: the third enemy (user, 2026-10-12), a dappled grey wild horse guarding the
		-- path up to the King's platform. Rears up and slams both front hooves down (the
		-- Bear's "slam"). Tougher and faster than the Bull. Its crafting material,
		-- Horsehair, goes in the second World 1 armour set (ServerStorage/Assets/Enemies/Stallion).
		Stallion = {
			id = "Stallion",
			tier = "elite",
			name = "Wild Stallion",
			hp = 260, -- 220 until 2026-10-20 (the health ladder)
			portrait = "rbxassetid://73569429526048", -- calm face (2026-10-12)
			melee = { damage = 73, cooldown = 2.2, windup = 0.78, range = 1.6, chaseSpeed = 16, armor = 0.15, move = "slam" },
			coins = { min = 25, max = 50 },
			exp = 32,
			drops = {
				{ weapon = "Shovel", chance = 0.15 },
				{ weapon = "Scythe", chance = 0.10 },
			},
			-- the second armour set
			materials = { { id = "Horsehair", chance = 0.5, min = 1, max = 1 } },
		},
		-- SECRET (2026-10-12): the Corn Wraith haunts the hidden cellar under the farm
		-- (drop down the silo). A floating corn-cob head with a leaf crown over a mass of
		-- flowing leaves; a one-handed diagonal slash with its right leaf arm. Elite sized, a little
		-- tougher than the Bull. Kept out of the Index (secret). Its drop -- one part of the
		-- secret crafted weapon -- is still to design (ServerStorage/Assets/Enemies/CornWraith).
		CornWraith = {
			id = "CornWraith",
			name = "Corn Wraith",
			hp = 360,
			secret = true,
			adminPortrait = "rbxassetid://85851674951625", -- admin panel only, never the Index (2026-10-17)
			melee = { damage = 55, cooldown = 1.7, windup = 0.48, range = 1.8, chaseSpeed = 15, armor = 0.1, move = "slash" },
			coins = { min = 35, max = 70 },
			exp = 45,
			-- the Farm Core: 1%, once per player; luck never changes a core's chance
			materials = { { id = "FarmCore", chance = 0.01, min = 1, max = 1 } },
		},
	},

	bosses = {
		-- The Sunny Meadows boss, waiting on the boss platform
		-- (ServerStorage/Assets/Bosses/BossScarecrow).
		BossScarecrow = {
			id = "BossScarecrow",
			name = "Scarecrow King",
			-- 32 x the old boss multiplier of 4, so the fight is unchanged.
			hp = 400, -- 128 with 50% armour until 2026-10-20: the boss now has the most health
			portrait = "rbxassetid://80515484828150", -- calm black face, with the elbow and knee ties (2026-10-11; was 122472392610626)
			-- Pitchfork jabs with the longest reach; armour halves weapon damage so the
			-- fight outlasts the Bull's.
			melee = { damage = 81, cooldown = 2.2, windup = 0.5, range = 1.2, chaseSpeed = 11, armor = 0.2, move = "stab" },
			coins = { min = 110, max = 215 },
			exp = 135,
			drops = {
				{ weapon = "Pitchfork", chance = 0.25 },
				{ weapon = "Scythe", chance = 0.20 },
				-- Legendary: his own pumpkin head on a stake
				{ weapon = "PumpkinMace", chance = 0.05 },
				-- the secret Corn Cob (0.1%, the user's rate for secrets)
				{ weapon = "CornCob", chance = 0.001 },
			},
			materials = { { id = "GoldenStraw", chance = 0.5, min = 1, max = 1 } },
		},
	},

	worldEnemy = { archetype = "Chicken" },
}

return World
