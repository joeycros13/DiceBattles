--!strict
-- World 2: The Redwood Forest (the user's name, 2026-10-11; it was planned as
-- The Frozen Caverns, then a forest under the placeholder The Whispering
-- Woods). The World 2 gate's sign shows the name.
--
-- Roster (decided with the user, 2026-10-11): angry wildlife plus a forest-spirit
-- boss. Starting numbers, not final. Sizes were set against World 1: the Fox is as
-- tall as the Chicken, the Bear slightly bigger than the Bull, the Boar between.
--
-- Drops use the World 2 weapons (switched on 2026-10-11). A drop must name a
-- weapon that exists in Config/Weapons. The Firefly Lantern (Legendary) comes only
-- from the park ranger's final quest.

local WorldTypes = require(script.Parent.Parent.WorldTypes)

-- World 2 balance (2026-10-20, the user: World 2's enemies match World 1's, Chicken -> Fox, Bull -> Boar,
-- Stallion -> Bear): HP x ~6.9 (the Birch Hatchet's damage per second over the Sickle's, so fights last as
-- long), damage tuned so an early fight costs ~14% of health like World 1, EXP equal to the World 1
-- counterpart, coins tuned with art/tools/balance/world_sim.py --world 2 for ~45 min from arriving to buying
-- the World 3 gate (typical 44.4). Old numbers in the comments.
--
-- The health ladder and a prepared player (2026-10-20, the user: every world's health must climb small <
-- medium < elite < boss, and World 2's hits must be "scaled a lot up" so arriving ready pays off). The base is
-- the prepared arrival: level 25 (340 HP) in Harvest Knight (+75 HP, 18%) with World 1's Health, Defense,
-- Attack and Attack Speed upgrades maxed, swinging the Pumpkin King's Mace: 477 HP, taking x0.795, 42.2
-- damage a second. Each enemy mirrors its World 1 counterpart against a fresh level-1 player with the Dagger
-- (100 HP, 15 a second):
--   * damage: the same share of health per hit -- Fox = Chicken 6% (36), Bear = Stallion 20% (120), Elder
--     Treant = King 22% (132), Fairy = Corn Wraith 15% (90); the Boar takes 12% (72, the Bull's 16% killed the
--     prepared player 2.5 times in the first ten minutes in world_sim.py). damage = share x 477 / 0.795.
--   * health: the same time to kill -- Fox 113, Boar 268 (10% armour), Bear 366 (15%), Elder Treant 563 (20%),
--     Fairy 507 (10%). The weapons follow the Treant (Config/Weapons, the boss-kill rule).
--   * coins x0.72 so the World 3 gate's 25,000 still takes ~45 min: world_sim.py --world 2 --upgrades 3
--     --start-weapons PumpkinMace: 44.1 min typical, 1.6 deaths; an unprepared arrival (no upgrades, the
--     Spear) 49.1 min and 6.5 deaths.

-- World scale (2026-10-23, Config/Leveling): health x8 (the weapons are x8), EXP x4 (a level needs
-- x4 from 25 on), and damage x3.46: the same share of the prepared arrival as before, which is now
-- (340 x 4 + 75 Harvest Knight) x 1.15 = 1,650 HP (Harvest Knight is World 1 armour, unscaled).
-- world_sim.py after it: 47.9 min prepared, 1.1 deaths; 53.0 unprepared, 4.4. Numbers in the comments
-- above and below are before it.
--
-- The base fight (2026-10-24, the user's anchor, memory world-scaling-baseline): a player arriving maxed from
-- World 1 -- level 25 (912 HP on the new curve, Config/Leveling), Harvest Knight, every upgrade at level 3, the
-- Pumpkin King's Mace: 1,135 HP, taking x0.795, 84.5 damage a second -- loses about 50% of their health
-- fighting a Fox (art/tools/balance/base_fights.py, counted without the Mace's knockback, which in the game
-- shoves the Fox out of reach and makes the fight easier). Health is x10 World 1's (Fox 800, Boar 1,900,
-- Bear 2,600, Elder Treant 4,000, Fairy 3,600), the Fox hits for 80 (51% over a 10 s fight) and the rest
-- keep World 2's damage ratios to it (x2 / x3.3 / x3.66, Fairy x2.5): Boar 159, Bear 266, Treant 293, Fairy
-- 199. A Fox hits only 3.6x the Chicken, not x10, because the arrival's Mace is only 2.8x the Trowel against
-- x10 health, so its fights run three times as long. Kill EXP is x4 and kill coins x3 of the World 1
-- counterparts (a maxed player kills fast and World 2 is meant to last 45-60 min, not 30): world_sim.py
-- --world 2 --from 1 --upgrades 3 --start-weapons PumpkinMace: 48.4 min typical to the World 3 gate (9 in
-- 10 by 51.9), 0.1 deaths, ~16,000 coins spare toward World 2's upgrades; an unprepared arrival (no
-- upgrades, the Spear) 64.9 min, 1.3 deaths. Prices, rewards and sells are x10 World 1's (Config/Weapons,
-- Armor, Tools, Quests, Materials, Potions).
--
-- The reward ladder (2026-10-24, the user: spread the elite grind, elites still the best way to level,
-- the boss worth a hefty amount but not the best to farm; its pull is its weapon drops). Per kill, in
-- elites, for both EXP and coins: small 0.37, medium 0.7, elite 1, boss 4.3, the secret enemy 1.4. Per
-- second for a player mid to late in the world (art/tools/balance/rates_probe.py): small 64-73%, medium
-- 74-84%, elite 100%, boss 77-94% (one spot, a long fight and a 30 s respawn). Each world's whole ladder
-- is then scaled to its time target with world_sim.py.
-- World 2 at 0.95x the old Bear: 48.3 min to the World 3 gate (a player who fights whatever pays within
-- 25%: 52.9 min, 171 boars and 102 bears).

local World: WorldTypes.WorldDef = {
	id = 2,
	name = "The Redwood Forest",
	folder = "W02_RedwoodForest",
	-- the Index world card (2026-10-12, no enemies; art/index/world_W02_2026-10-12.png)
	profile = "rbxassetid://114443855013343",
	-- "Misty morning" (the user's pick, 2026-10-21): a soft morning sun and blue-grey
	-- haze between the trees. No sun rays in World 2 (the user's rule).
	lighting = {
		ClockTime = 9.6,
		Brightness = 1.9,
		ExposureCompensation = -0.15,
		Ambient = Color3.fromHex("4a5562"),
		OutdoorAmbient = Color3.fromHex("93a6b8"),
		ColorShift_Top = Color3.fromHex("f6efe2"),
		Atmosphere = { Density = 0.46, Offset = 0.1, Color = Color3.fromHex("dce8f0"), Decay = Color3.fromHex("8ca6b4"), Glare = 0.05, Haze = 2.0 },
		ColorCorrection = { Brightness = 0, Contrast = 0.08, Saturation = 0.04, TintColor = Color3.fromHex("eef6ff") },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},

	-- Respawn seconds by kind (the user's rule, 2026-10-19): every enemy of a tier
	-- comes back after the same time in its world; bosses and the secret enemy
	-- after `boss` / `secret`. A spawn marker's RespawnSeconds attribute still wins.
	respawn = { small = 10, medium = 15, elite = 20, boss = 30, secret = 30 },

	enemies = {
		-- Minion: quick and common, at the front of both lanes
		-- (ServerStorage/Assets/Enemies/Fox).
		Fox = {
			id = "Fox",
			tier = "small",
			name = "Snarling Fox",
			portrait = "rbxassetid://102792357956654", -- calm face (2026-10-11)
			hp = 800, -- x10 the Chicken (2026-10-24); 904 before
			-- Quick pounces with a snap at the end.
			melee = { damage = 80, cooldown = 1.0, windup = 0.5, range = 1.5, chaseSpeed = 17, armor = 0, move = "pounce" },
			coins = { min = 35, max = 70 },
			exp = 60,
			drops = {
				{ weapon = "Hatchet", chance = 0.20 },
				{ weapon = "Cleaver", chance = 0.05 },
			},
			-- crafting materials (Config/Materials): the first armour set
			materials = { { id = "FoxFur", chance = 0.5, min = 1, max = 2 } },
		},
		-- Tough minion: armoured hide and a tusk charge
		-- (ServerStorage/Assets/Enemies/Boar).
		Boar = {
			id = "Boar",
			tier = "medium",
			name = "Wild Boar",
			portrait = "rbxassetid://105726195455752", -- calm face (2026-10-11)
			hp = 1900, -- x10 the Bull (2026-10-24); 2,144 before
			melee = { damage = 159, cooldown = 1.8, windup = 0.55, range = 1.5, chaseSpeed = 15, armor = 0.1, move = "charge" },
			coins = { min = 65, max = 135 },
			exp = 110,
			drops = {
				{ weapon = "Cleaver", chance = 0.20 },
				{ weapon = "Quarterstaff", chance = 0.15 },
				{ weapon = "Mace", chance = 0.08 },
			},
			materials = { { id = "BoarTusk", chance = 0.5, min = 1, max = 2 } },
		},
		-- Elite: one at the far end of each lane; rears up for a two-paw slam
		-- (ServerStorage/Assets/Enemies/Bear).
		Bear = {
			id = "Bear",
			tier = "elite",
			name = "Grizzly Bear",
			portrait = "rbxassetid://117018743106247", -- calm face (2026-10-11)
			hp = 2600, -- x10 the Stallion (2026-10-24); 2,928 before
			melee = { damage = 266, cooldown = 2.4, windup = 0.78, range = 1.6, chaseSpeed = 13, armor = 0.15, move = "slam" },
			coins = { min = 95, max = 190 },
			exp = 160,
			drops = {
				{ weapon = "Mace", chance = 0.15 },
				{ weapon = "WoodsmansAxe", chance = 0.10 },
				{ weapon = "Greatclub", chance = 0.08 },
			},
			-- the second armour set
			materials = { { id = "BearClaw", chance = 0.4, min = 1, max = 1 } },
		},
		-- SECRET (2026-10-12): the Fairy of the hollow stump. Found by looking through the
		-- lookout telescope at the fairy ring, then standing in the ring for 5 s. A small
		-- mushroom-cap fairy with fluttering wings; flicks her acorn wand for a pop of
		-- fairy dust. Quick and a bit tougher than the Bear, but hits softer. Kept out of
		-- the Index (secret). Her drop -- one part of the secret crafted weapon -- is still
		-- to design (ServerStorage/Assets/Enemies/Fairy).
		Fairy = {
			id = "Fairy",
			name = "Fairy",
			hp = 3600, -- x10 the Corn Wraith (2026-10-24); 4,056 before
			secret = true,
			adminPortrait = "rbxassetid://128352315360379", -- admin panel only, never the Index (2026-10-17)
			melee = { damage = 199, cooldown = 1.6, windup = 0.45, range = 2.2, chaseSpeed = 18, armor = 0.1, move = "zap" },
			coins = { min = 135, max = 265 },
			exp = 225,
			-- the Forest Core: about 1%, once per player (trial numbers)
			materials = { { id = "ForestCore", chance = 0.01, min = 1, max = 1 } },
		},
	},

	bosses = {
		-- The Redwood Forest boss, in the mossy ruins arena
		-- (ServerStorage/Assets/Bosses/ElderTreant). Lifts a knee and stomps.
		ElderTreant = {
			id = "ElderTreant",
			name = "Elder Treant",
			portrait = "rbxassetid://98505547017601", -- calm face (2026-10-11)
			hp = 4000, -- x10 the Scarecrow King (2026-10-24); 4,504 before
			-- Two attacks, picked 50/50, same damage and timing (user, 2026-10-11): the
			-- knee-up stomp and an overhead double-arm smash.
			melee = { damage = 293, cooldown = 2.4, windup = 0.72, range = 1.5, chaseSpeed = 10, armor = 0.2, move = "stomp", moves = { "stomp", "smash" } },
			coins = { min = 410, max = 815 },
			exp = 690,
			drops = {
				{ weapon = "WoodsmansAxe", chance = 0.20 },
				{ weapon = "Greatclub", chance = 0.20 },
				-- Legendary: the treant's living heart
				{ weapon = "HeartwoodStaff", chance = 0.05 },
				-- the secret Marshmallow Stick (hidden in the Index until found)
				{ weapon = "MarshmallowStick", chance = 0.001 }, -- secrets drop at 0.1% (the user's rule); 2% until 2026-10-20
			},
			materials = { { id = "HeartwoodSap", chance = 0.5, min = 1, max = 1 } },
		},
	},

	worldEnemy = { archetype = "Fox" },
}

return World
