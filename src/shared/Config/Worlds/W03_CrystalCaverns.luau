--!strict
-- World 3: The Crystal Caverns, a cave (the user's call, 2026-10-11; it was
-- planned as The Molten Peak).
--
-- Roster (picked with the user, 2026-10-13): Cave Bat, Pebble Golem, Crystal Golem
-- and the Spider Queen boss. Starting numbers, about twice World 2's.
--
-- Drops use the World 3 weapons (2026-10-13, memory world3-weapons). The Diamond
-- Pickaxe (Legendary) comes only from the World 3 quest's final reward.

-- The health ladder and a prepared player (2026-10-20, as World 2's): the base is a level-36 arrival (450 HP)
-- in Heartwood Bark (+160 HP, 32%) with World 2's upgrades maxed (x1.30 HP, x0.94 damage taken, x1.18 damage,
-- x0.91 swing time) swinging the Heartwood Staff: 793 HP, taking x0.639, 118 damage a second. Each enemy
-- mirrors its World 1 counterpart against a fresh level-1 Dagger player: hits take 6 / 12 / 20 / 22% of health
-- (Bat 74, Pebble Golem 149, Crystal Golem 248, Spider Queen 273; the Gem Mole 15%, 186) and kills take as long
-- (Bat 314, Pebble Golem 747 at 10% armour, Crystal Golem 1,022 at 15%, Spider Queen 1,572 at 20%, Gem Mole
-- 1,415 at 10%). Coins and EXP are not re-simulated yet (World 3 has no world_sim dump).
local WorldTypes = require(script.Parent.Parent.WorldTypes)

-- World scale (2026-10-23, Config/Leveling), PROVISIONAL until World 3 is rebuilt and simulated:
-- health x32 (the weapons are x32), damage and EXP x16. Numbers in older comments are before it.
--
-- The base fight (2026-10-24, the user's anchor, memory world-scaling-baseline): a player arriving maxed from
-- World 2 -- level 50 (9,120 HP on the new curve), Heartwood Bark (+750, 32%), every upgrade at level 6, the
-- Heartwood Staff: 12,831 HP, taking x0.639, 754 damage a second -- loses about 50% of their health fighting a
-- Cave Bat (base_fights.py, without the Staff's knockback): Bat 1,220 damage (49% over an 11 s fight). Health
-- x10 World 2's (Bat 8,000, Pebble Golem 19,000, Crystal Golem 26,000, Spider Queen 40,000, Gem Mole 36,000);
-- the rest keep World 3's damage ratios to the Bat (x2.01 / x3.35 / x3.69, Mole x2.51): 2,460 / 4,090 /
-- 4,500 / 3,070. Kill EXP and coins x5.5 World 2's (Bat 220 / 100-200, Pebble 660 / 400-660, Crystal 920 /
-- 660-990, Queen 3,300 / 1,500-2,300, Mole 1,320 / 410-660), tuned with world_sim.py --world 3 --from 2
-- --upgrades 6 --start-level 50 --start-weapons HeartwoodStaff to a mock World 4 gate (level 75, 250,000
-- coins; Config/Gates notes it): 50.3 min typical (9 in 10 by 51.4), no deaths; unprepared (no upgrades, the
-- Firefly Lantern) 80.5 min. Pip's questline is done by about minute 9 and the rest is mostly Crystal Golems.
--
-- The reward ladder (2026-10-24, the user: spread the elite grind, elites still the best way to level,
-- the boss worth a hefty amount but not the best to farm; its pull is its weapon drops). Per kill, in
-- elites, for both EXP and coins: small 0.37, medium 0.7, elite 1, boss 4.3, the secret enemy 1.4. Per
-- second for a player mid to late in the world (art/tools/balance/rates_probe.py): small 64-73%, medium
-- 74-84%, elite 100%, boss 77-94% (one spot, a long fight and a 30 s respawn). Each world's whole ladder
-- is then scaled to its time target with world_sim.py.
-- World 3 at 0.95x the old Crystal Golem: 49.6 min (a player who fights whatever pays within 25%: 56.1 min,
-- mostly Pebble Golems).

local World: WorldTypes.WorldDef = {
	id = 3,
	name = "The Crystal Caverns",
	folder = "W03_CrystalCaverns",
	-- the Index world card and Worlds-menu banner (2026-10-17, no enemies, past the stalls
	-- looking at the boarded-up mine entrance; art/portraits/worlds/world_W03_2026-10-17.png)
	profile = "rbxassetid://106928307558031",
	-- "Deep sapphire" (the user's pick, 2026-10-24): a blue cave light and haze with more
	-- contrast and colour, so the glowing crystals and the lake stand out. No sky shows
	-- underground, so the sun settings only keep the look steady.
	lighting = {
		ClockTime = 14,
		Brightness = 2,
		ExposureCompensation = -0.1,
		Ambient = Color3.fromHex("7d7fb8"),
		OutdoorAmbient = Color3.fromHex("7d7fb8"),
		ColorShift_Top = Color3.fromHex("e6e8ff"),
		Atmosphere = { Density = 0.38, Offset = 0, Color = Color3.fromHex("6f78c8"), Decay = Color3.fromHex("2a2d66"), Glare = 0, Haze = 1.6 },
		ColorCorrection = { Brightness = 0, Contrast = 0.18, Saturation = 0.22, TintColor = Color3.fromHex("d6dcff") },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- Respawn seconds by kind (the user's rule, 2026-10-19): every enemy of a tier
	-- comes back after the same time in its world; bosses and the secret enemy
	-- after `boss` / `secret`. A spawn marker's RespawnSeconds attribute still wins.
	respawn = { small = 10, medium = 15, elite = 20, boss = 30, secret = 30 },

	enemies = {
		-- Minion: a small bat that hovers low at the front of every lane and in the
		-- halls; swoops down for a bite (ServerStorage/Assets/Enemies/CaveBat).
		CaveBat = {
			id = "CaveBat",
			tier = "small",
			name = "Cave Bat",
			portrait = "rbxassetid://72271902069536", -- calm face (2026-10-13)
			hp = 8000, -- x10 the Fox (2026-10-24); 10,048 before
			melee = { damage = 1220, cooldown = 1.2, windup = 0.47, range = 1.6, chaseSpeed = 18, armor = 0, move = "swoop" },
			coins = { min = 195, max = 385 },
			exp = 320,
			drops = {
				{ weapon = "BatwingBlade", chance = 0.20 },
				{ weapon = "IronPickaxe", chance = 0.05 },
			},
			materials = { { id = "BatWing", chance = 0.5, min = 1, max = 2 } },
		},
		-- Tough minion: stacked stones round a glowing core, mid-lane; a wind-up
		-- punch (ServerStorage/Assets/Enemies/PebbleGolem).
		PebbleGolem = {
			id = "PebbleGolem",
			tier = "medium",
			name = "Pebble Golem",
			portrait = "rbxassetid://92185614445143", -- calm face (2026-10-13)
			hp = 19000, -- x10 the Boar (2026-10-24); 23,904 before
			melee = { damage = 2460, cooldown = 1.8, windup = 0.48, range = 1.5, chaseSpeed = 14, armor = 0.1, move = "punch" },
			coins = { min = 370, max = 730 },
			exp = 610,
			drops = {
				{ weapon = "IronPickaxe", chance = 0.20 },
				{ weapon = "PebbleMallet", chance = 0.15 },
				{ weapon = "GoldGauntlets", chance = 0.08 },
			},
			materials = { { id = "GolemPebble", chance = 0.5, min = 1, max = 2 } },
		},
		-- Elite: dark slate with crystal clusters, guarding the two lanes into the boss
		-- hall; an overhead double-fist slam (ServerStorage/Assets/Enemies/CrystalGolem).
		CrystalGolem = {
			id = "CrystalGolem",
			tier = "elite",
			name = "Crystal Golem",
			portrait = "rbxassetid://84986641261720", -- calm face (2026-10-13)
			hp = 26000, -- x10 the Bear (2026-10-24); 32,704 before
			melee = { damage = 4090, cooldown = 2.4, windup = 0.74, range = 1.6, chaseSpeed = 12, armor = 0.15, move = "smash" },
			coins = { min = 525, max = 1045 },
			exp = 875,
			drops = {
				{ weapon = "GoldGauntlets", chance = 0.15 },
				{ weapon = "GeodeGlaive", chance = 0.10 },
				{ weapon = "EmberCoalMaul", chance = 0.08 },
			},
			materials = { { id = "GolemCrystal", chance = 0.4, min = 1, max = 1 } },
		},
		-- SECRET (2026-10-13): the Gem Mole of the hidden mine. Found by striking the
		-- three pulsing crystals in the order the tunnel's hint shows (blue, pink,
		-- purple), which opens the front mineshaft into the room carved out of the
		-- first rock island. A friendly round mole in a tiny hard hat with a pink
		-- diamond nose; swipes with a big digging paw. A little tougher than the
		-- Crystal Golem but hits softer. Kept out of the Index (secret). Drops the
		-- Cave Core, the third gem of the Worldheart Blade
		-- (ServerStorage/Assets/Enemies/GemMole).
		GemMole = {
			id = "GemMole",
			name = "Gem Mole",
			hp = 36000, -- x10 the Fairy (2026-10-24); 45,280 before
			secret = true,
			adminPortrait = "rbxassetid://95259297161320", -- admin panel only, never the Index (2026-10-17)
			melee = { damage = 3070, cooldown = 1.8, windup = 0.48, range = 1.8, chaseSpeed = 15, armor = 0.1, move = "slash" },
			coins = { min = 735, max = 1460 },
			exp = 1225,
			-- the Cave Core: about 1%, once per player (trial numbers)
			materials = { { id = "CaveCore", chance = 0.01, min = 1, max = 1 } },
		},
	},

	bosses = {
		-- The Crystal Caverns boss, in the far hall (ServerStorage/Assets/Bosses/SpiderQueen).
		-- Two attacks, picked 50/50 with the same timing: a front-leg stab and a
		-- rear-up slam.
		SpiderQueen = {
			id = "SpiderQueen",
			name = "Spider Queen",
			portrait = "rbxassetid://80870479752276", -- calm face (2026-10-13)
			hp = 40000, -- x10 the Elder Treant (2026-10-24); 50,304 before
			melee = { damage = 4500, cooldown = 2.4, windup = 0.74, range = 1.5, chaseSpeed = 11, armor = 0.2, move = "legstab", moves = { "legstab", "rearslam" } },
			coins = { min = 2260, max = 4480 },
			exp = 3760,
			drops = {
				{ weapon = "GeodeGlaive", chance = 0.20 },
				{ weapon = "EmberCoalMaul", chance = 0.20 },
				-- Legendary: the Queen's own fang
				{ weapon = "QueensFang", chance = 0.05 },
				-- the secret Rock Candy Club (hidden in the Index until found)
				{ weapon = "RockCandyClub", chance = 0.001 }, -- secrets drop at 0.1% (the user's rule); 2% until 2026-10-24
			},
			materials = { { id = "QueensSilk", chance = 0.5, min = 1, max = 1 } },
		},
	},

	worldEnemy = { archetype = "CaveBat" },
}

return World
