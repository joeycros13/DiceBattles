--!strict
-- Weapons: the melee weapons a player can pick from the Inventory panel, and
-- everything that makes each one feel different.
--
-- Read by both sides: the client plays the swing and decides what it touched,
-- the server re-checks every number here before any damage lands (MeleeService).
-- The models live in ReplicatedStorage/Assets/Weapons/<id>, built along -Z from
-- an invisible "Grip" part that is welded into the character's right hand.
--
--   damage      HP removed per enemy hit (before the enemy's armour)
--   cooldown    seconds from one swing to the next; also the swing's length
--   reach       studs from the player's centre to the edge of the enemy
--   arc         width of the hit cone in degrees (360 = all around)
--   maxTargets  enemies one swing can hit
--   hitTime     fraction of the swing at which the hit is checked
--   knockback   studs an enemy is shoved away on hit
--   swing       which swing animation WeaponController plays (Animation.Clips.Weapons.SWINGS)
--   rarity      Common / Uncommon / Rare / Epic / Legendary / Secret / Relic: the item's tile
--               colour in the Inventory (Weapons.Rarities lists them in order)
--   secret      true for a hidden weapon: the Index keeps it out of its dropper's
--               drop list until the player has found it (the Corn Cob)
--   price       (optional) coins to buy it at the Weapons stall (MerchantService). Only
--               Common..Epic weapons have one, about 3x the coins earned farming its
--               best drop, so buying is the longer grind (user, 2026-10-12);
--               Legendary and Secret weapons are drop or quest only
--   sell        coins the Inventory's Sell Mode pays for one (SellService, Config/Sell); a
--               placeholder per item (2026-10-20). No sell = can't be sold
--   ignoreArmor (optional) true: the enemy's armour doesn't reduce this weapon's damage
--   impact      (optional) an effect WeaponController plays where the weapon
--               lands at its Hit moment: "Slam" = a ground-slam rumble, "Gust" = wind
--               rolling out across the sweep (the Weathervane Spear), "Pumpkin" = orange
--               sparks and seeds where the head lands (the Pumpkin King's Mace)
--   icon        the weapon's picture for the hotbar and the Inventory tiles: a
--               cel-shaded render of its mesh (art/weapon_icons.py). Without one
--               they fall back to a live model viewport
--   world       the world it belongs to (the admin panel groups weapons by it)
--   handed      1 or 2. Every weapon sits in the right hand; two-handed ones also
--               bring the left hand onto the shaft (the model's OffGrip)
--   starter     true for the weapon every player starts with (Weapons.default):
--               always owned, can't be sold, and it lives in the hotbar's first slot
--   unarmed     (optional) no model is held and the arms stay free; nothing uses
--               this since Fists were removed

-- World scale (2026-10-23, the user: World 1 near 100, World 2 1K, World 3 10K...): every weapon's
-- damage is x2 / x8 / x32 for Worlds 1 / 2 / 3, like its world's enemy health (Config/Leveling), so
-- fights last as before. Damage numbers in older comments are before it.

local Weapons = {}

export type WeaponDef = {
	id: string,
	world: number,
	name: string,
	blurb: string,
	order: number,
	color: Color3, -- card accent in the Inventory panel
	damage: number,
	cooldown: number,
	reach: number,
	arc: number,
	maxTargets: number,
	hitTime: number,
	knockback: number,
	swing: string,
	rarity: string?,
	handed: number?,
	starter: boolean?,
	-- a key item that can't be sold (the Rusty Blade: quest-only, and it becomes the Worldheart Blade)
	keep: boolean?,
	-- the Worldheart Blade's tier (cores in it): its damage, speed and reach come from Config/Infuse
	worldheartTier: number?,
	unarmed: boolean?,
	secret: boolean?,
	impact: string?,
	icon: string?,
	ignoreArmor: boolean?,
	price: number?,
	sell: number?, -- coins for selling it; nil = can't be sold (starter, key items)
	-- worn, not held (the Gold Gauntlets, 2026-10-13): the model stays lined up with the forearm
	-- instead of turning in the hand, and a child model with a Socket attribute (LeftGauntlet)
	-- is welded to that socket too. Use handed = 2 so the swing moves the left arm.
	worn: boolean?,
}

Weapons.Defs = {
	-- Damage rule (user, 2026-10-13: weapons scale with each world's boss HP; numbers not final):
	-- each rarity kills ITS world's boss (HP / (1 - armour)) in the same time in every world:
	-- Common 16 s, Uncommon 13.5, Rare 11.5, Epic 10, Legendary 6.5 (the boss-drop one ~7% slower),
	-- Secret 5.5. Crowd weapons (5+ targets or 200+ degree arc) do 10% less; armour-ignoring ones are
	-- measured against raw HP. damage = round(target DPS x cooldown). The starter and the Rusty Blade
	-- keep theirs. Re-run this rule when a boss's HP or armour changes.
	-- 2026-10-20, the health ladder (every world's boss now has the most health; Config/Worlds): the bosses
	-- are King 200 at 20% armour (250 effective, ~ the old 256, so World 1 kept its numbers), Elder Treant
	-- 563 at 20% (704, was 1,714: World 2's weapons x0.41) and Spider Queen 1,572 at 20% (1,965, was 3,714:
	-- World 3's x0.53); the armour-ignoring Mace and Diamond Pickaxe follow the raw health (x0.47, x0.60).
	-- 2026-10-24, the rescale from base fights (memory world-scaling-baseline): a maxed player's DPS -- the
	-- world's secret with its upgrades, hits only -- is about 100 / 1,000 / 10,000. World 1 stays (the Corn
	-- Cob at upgrades 3: 107); World 2's damage x0.8 (the Marshmallow Stick at upgrades 6: 1,328 -> 1,062);
	-- World 2's prices and sells x10 World 1's by rarity (Common 1,500, Uncommon 4,000 / 6,500, Rare 7,000,
	-- Epic 18,000 / 20,000; a sell about a tenth of the price, drop-only ones x10 their World 1 counterpart).
	-- World 3's damage x0.63 (the Rock Candy Club at upgrades 9: 16,773 -> 10,567) and prices / sells x10 World 2's
	-- (15,000 / 40,000 / 65,000 / 70,000 / 180,000 / 200,000).
	-- ==================== World 1 (The Sunny Meadows) ====================
	-- shown as the "Trowel" since the 2026-10-12 remodel (a garden trowel); the id stays "Dagger" so saves,
	-- the Index and quest progress keep working
	Dagger = {
		id = "Dagger",
		world = 1,
		icon = "rbxassetid://135288098151094",
		rarity = "Common",
		name = "Trowel",
		blurb = "Pull back and jab. Quick and short.",
		order = 1,
		color = Color3.fromRGB(176, 182, 190),
		handed = 1,
		starter = true,
		damage = 12,
		cooldown = 0.4,
		reach = 4.5,
		arc = 50,
		maxTargets = 1,
		hitTime = 0.5,
		knockback = 0,
		swing = "Jab",
	},
	Sickle = {
		id = "Sickle",
		world = 1,
		sell = 18,
		price = 150,
		icon = "rbxassetid://109909666740470",
		rarity = "Common",
		name = "Sickle",
		blurb = "A fast flat hook across the body. Catches two.",
		order = 2,
		color = Color3.fromRGB(160, 166, 175),
		handed = 1,
		damage = 14,
		cooldown = 0.45,
		reach = 5.5,
		arc = 140,
		maxTargets = 2,
		hitTime = 0.55, -- where the Hook passes in front of the body
		knockback = 0,
		swing = "Hook",
	},
	Machete = {
		id = "Machete",
		world = 1,
		sell = 50,
		price = 400,
		icon = "rbxassetid://94460052611934",
		rarity = "Uncommon",
		name = "Machete",
		blurb = "Raised high, then a diagonal slash all the way through.",
		order = 3,
		color = Color3.fromRGB(96, 170, 110),
		handed = 1,
		damage = 20,
		cooldown = 0.55,
		reach = 6.5,
		arc = 110,
		maxTargets = 2,
		hitTime = 0.5,
		knockback = 0,
		swing = "Diagonal",
	},
	Shovel = {
		id = "Shovel",
		world = 1,
		sell = 58,
		price = 700,
		icon = "rbxassetid://116513633926651",
		rarity = "Rare",
		name = "Shovel",
		blurb = "Straight up, straight down. Bonk.",
		order = 4,
		color = Color3.fromRGB(176, 130, 82),
		handed = 1,
		damage = 40,
		cooldown = 0.9,
		reach = 6.5,
		arc = 60,
		maxTargets = 2,
		hitTime = 0.6,
		knockback = 6,
		swing = "Bonk",
	},
	Pitchfork = {
		id = "Pitchfork",
		world = 1,
		sell = 40,
		price = 650,
		icon = "rbxassetid://136084151914012",
		rarity = "Uncommon",
		name = "Pitchfork",
		blurb = "Swing it to your side and drive it through everything in a line.",
		order = 5,
		color = Color3.fromRGB(196, 150, 84),
		handed = 2,
		damage = 28,
		cooldown = 0.75,
		reach = 10,
		arc = 40,
		maxTargets = 3,
		hitTime = 0.55,
		knockback = 1,
		swing = "Thrust",
	},
	Scythe = {
		id = "Scythe",
		world = 1,
		sell = 170,
		price = 1800,
		icon = "rbxassetid://89826212012485",
		rarity = "Epic",
		name = "Scythe",
		blurb = "A wide, slow sweep that cuts down everything in front of you.",
		order = 6,
		color = Color3.fromRGB(140, 110, 200),
		handed = 2,
		damage = 56,
		cooldown = 1.2,
		reach = 8.5,
		arc = 200,
		maxTargets = 6,
		hitTime = 0.46, -- the sweep's fastest point
		knockback = 2,
		swing = "Sweep",
	},
	-- Secret (2026-10-09, the user's idea): a giant corn cob, 8.7 studs long, held
	-- one-handed by its stubby stalk. A rare drop from the Scarecrow King that
	-- the Index hides until it's found. Hits hard (50, the user's call), with
	-- big knockback and a ground-slam impact (impact = "Slam").
	CornCob = {
		id = "CornCob",
		world = 1,
		sell = 1200,
		icon = "rbxassetid://115219442892366",
		rarity = "Secret",
		secret = true,
		name = "Corn Cob",
		blurb = "A giant corn cob. Up, then BONK.",
		order = 7,
		color = Color3.fromRGB(255, 210, 63),
		handed = 1,
		damage = 94,
		cooldown = 1.0,
		reach = 8,
		arc = 90,
		maxTargets = 3,
		hitTime = 0.6,
		knockback = 10,
		swing = "CornBonk",
		impact = "Slam",
	},
	-- The first Legendaries (2026-10-11, canvas https://claude.ai/artifact/Xiq7CR3mir1Ymy3mNy62Jz).
	-- Weathervane Spear: Dale's reward for the last quest (Config/Quests), not
	-- dropped by anything. Two-handed, the same 8.7 length as the Corn Cob (the
	-- user's call), and it must hit harder than the mace. Its own attack (2026-10-19)
	-- is the wide "Gust" sweep, so the arc is wide; a gust rolls out on the hit.
	WeathervaneSpear = {
		id = "WeathervaneSpear",
		world = 1,
		sell = 335,
		icon = "rbxassetid://94808711177974",
		rarity = "Legendary",
		name = "Weathervane Spear",
		blurb = "Dale's barn-top rooster, sharpened.",
		order = 8,
		color = Color3.fromRGB(255, 196, 61),
		handed = 2,
		damage = 86,
		cooldown = 1.1,
		reach = 10.5,
		arc = 120,
		maxTargets = 4,
		hitTime = 0.46,
		knockback = 8,
		swing = "Gust",
		impact = "Gust",
	},
	-- Pumpkin King's Mace: a Legendary drop from the Scarecrow King, his own
	-- pumpkin head on a sharpened stake. One-handed (the Dagger's hold); its own
	-- attack (2026-10-19) is the diagonal "Pumpkin smash" with sparks and seeds where
	-- it lands, and its carved face glows angry through each swing. Less damage per
	-- hit and per second than the spear.
	PumpkinMace = {
		id = "PumpkinMace",
		world = 1,
		sell = 390,
		icon = "rbxassetid://124980720153437",
		rarity = "Legendary",
		name = "Pumpkin King's Mace",
		blurb = "The King's own head, on a stake.",
		order = 9,
		color = Color3.fromRGB(232, 120, 30),
		handed = 1,
		damage = 74,
		cooldown = 1.0,
		reach = 7.5,
		arc = 100,
		maxTargets = 3,
		hitTime = 0.58,
		knockback = 10,
		swing = "PumpkinSmash",
		impact = "Pumpkin",
	},
	-- ==================== World 2 (The Redwood Forest) ====================
	-- The cartoony World 2 set (user, 2026-10-11): each made from something in the
	-- forest, with its own signature colour (Blender weapons_w2_v3_build). One-handers
	-- use the Dagger's hold, two-handers the Pitchfork's (the Pinecone Staff level).
	Hatchet = {
		id = "Hatchet",
		world = 2,
		sell = 180,
		price = 1500,
		icon = "rbxassetid://104904531666743",
		rarity = "Common",
		name = "Birch Hatchet",
		blurb = "A quick copper chop.",
		order = 10,
		color = Color3.fromRGB(79, 199, 178),
		handed = 1,
		damage = 141,
		cooldown = 0.5,
		reach = 5.5,
		arc = 90,
		maxTargets = 1,
		hitTime = 0.5,
		knockback = 1,
		swing = "Chop1H",
	},
	Cleaver = {
		id = "Cleaver",
		world = 2,
		sell = 450,
		price = 4000,
		icon = "rbxassetid://94960897963841",
		rarity = "Uncommon",
		name = "Stone & Bone Cleaver",
		blurb = "A wide stone cleave. Hits three.",
		order = 11,
		color = Color3.fromRGB(125, 147, 166),
		handed = 1,
		damage = 198,
		cooldown = 0.6,
		reach = 6,
		arc = 150,
		maxTargets = 3,
		hitTime = 0.56,
		knockback = 1,
		-- an overhead chop down (user, 2026-10-11)
		swing = "Cleave",
	},
	Quarterstaff = {
		id = "Quarterstaff",
		world = 2,
		sell = 500,
		price = 6500,
		icon = "rbxassetid://138720679031855",
		rarity = "Uncommon",
		name = "Pinecone Staff",
		blurb = "Longest reach. Sweeps them away.",
		order = 12,
		color = Color3.fromRGB(166, 224, 92),
		handed = 2,
		damage = 211,
		cooldown = 0.7,
		reach = 11,
		arc = 200,
		maxTargets = 3,
		-- the head passes straight ahead about here in the right-to-left sweep
		hitTime = 0.54,
		knockback = 7,
		swing = "StaffSweep",
	},
	-- ignores the enemy's armour (MeleeService)
	Mace = {
		id = "Mace",
		world = 2,
		sell = 580,
		price = 7000,
		icon = "rbxassetid://92824725919490",
		rarity = "Rare",
		name = "Toadstool Mace",
		blurb = "Toadstool bonk. Ignores armor.",
		order = 13,
		color = Color3.fromRGB(232, 57, 43),
		handed = 1,
		damage = 237,
		cooldown = 0.75,
		reach = 6.5,
		arc = 80,
		maxTargets = 2,
		hitTime = 0.6,
		knockback = 4,
		swing = "CornBonk",
		ignoreArmor = true,
	},
	WoodsmansAxe = {
		id = "WoodsmansAxe",
		world = 2,
		sell = 1700,
		price = 18000,
		icon = "rbxassetid://82102785735288",
		rarity = "Epic",
		name = "Lumberjack's Splitter",
		blurb = "The biggest single chop.",
		order = 14,
		color = Color3.fromRGB(210, 58, 46),
		handed = 2,
		damage = 563,
		cooldown = 1.25,
		reach = 8.5,
		arc = 70,
		maxTargets = 2,
		hitTime = 0.6,
		knockback = 6,
		swing = "Chop2H",
	},
	Greatclub = {
		id = "Greatclub",
		world = 2,
		sell = 1800,
		price = 20000,
		icon = "rbxassetid://105072471859350",
		rarity = "Epic",
		name = "Boulder Club",
		blurb = "Slams the ground all around.",
		order = 15,
		color = Color3.fromRGB(90, 209, 255),
		handed = 2,
		damage = 467,
		cooldown = 1.15,
		reach = 7.5,
		arc = 360,
		maxTargets = 6,
		hitTime = 0.6,
		knockback = 9,
		swing = "Slam2H",
		impact = "Slam",
	},
	-- Legendary: the Elder Treant's drop (5%). Thrust for now.
	HeartwoodStaff = {
		id = "HeartwoodStaff",
		world = 2,
		sell = 3900,
		icon = "rbxassetid://100796082047391",
		rarity = "Legendary",
		name = "Heartwood Staff",
		blurb = "The Elder Treant's living heart.",
		order = 16,
		color = Color3.fromRGB(255, 176, 46),
		handed = 2,
		damage = 640,
		cooldown = 1.1,
		reach = 10.5,
		arc = 60,
		maxTargets = 5,
		hitTime = 0.55,
		knockback = 8,
		swing = "Thrust",
	},
	-- Legendary: the park ranger's final quest reward (the ranger isn't built yet).
	-- Must out-damage the Heartwood Staff per hit and per second.
	LanternFlail = {
		id = "LanternFlail",
		world = 2,
		sell = 3350,
		icon = "rbxassetid://123737485261829",
		rarity = "Legendary",
		name = "Firefly Lantern",
		blurb = "The ranger's firefly lantern.",
		order = 17,
		color = Color3.fromRGB(214, 255, 92),
		handed = 1,
		damage = 762,
		cooldown = 1.1,
		reach = 9,
		arc = 160,
		maxTargets = 4,
		hitTime = 0.55, -- where the Hook passes in front of the body
		knockback = 6,
		swing = "Hook",
	},
	-- Secret: the Elder Treant's 2% drop, a forked roasting stick with two
	-- marshmallows. Beats both World 2 Legendaries.
	MarshmallowStick = {
		id = "MarshmallowStick",
		world = 2,
		sell = 12000,
		icon = "rbxassetid://119824929669130",
		rarity = "Secret",
		secret = true,
		name = "Marshmallow Stick",
		blurb = "Two toasty marshmallows. Poke!",
		order = 18,
		color = Color3.fromRGB(255, 248, 236),
		handed = 1,
		damage = 819,
		cooldown = 1.0,
		reach = 9,
		arc = 60,
		maxTargets = 3,
		hitTime = 0.5,
		knockback = 12,
		swing = "Jab",
	},
	-- ==================== World 3 (The Crystal Caverns), 2026-10-13 ====================
	-- Ore and crystal weapons (memory world3-weapons). About 1.5x World 2's damage per
	-- second; stall prices about 3x the coins earned farming each one's best drop.
	-- Starting numbers: the user will balance them later.
	BatwingBlade = {
		id = "BatwingBlade",
		world = 3,
		sell = 1800,
		icon = "rbxassetid://107455703660303",
		price = 15000,
		rarity = "Common",
		name = "Batwing Blade",
		blurb = "A bat's wing for a blade. Quick, wide slashes.",
		order = 22,
		color = Color3.fromRGB(91, 79, 114),
		handed = 1,
		damage = 1230,
		cooldown = 0.5,
		reach = 6,
		arc = 130,
		maxTargets = 2,
		hitTime = 0.55,
		knockback = 1,
		swing = "HookEdge",
	},
	IronPickaxe = {
		id = "IronPickaxe",
		world = 3,
		sell = 4500,
		icon = "rbxassetid://91124481325550",
		price = 40000,
		rarity = "Uncommon",
		name = "Iron Pickaxe",
		blurb = "A miner's pick. One heavy peck.",
		order = 23,
		color = Color3.fromRGB(107, 113, 124),
		handed = 1,
		damage = 1915,
		cooldown = 0.65,
		reach = 6.5,
		arc = 70,
		maxTargets = 1,
		hitTime = 0.58,
		knockback = 2,
		swing = "Mine",
	},
	PebbleMallet = {
		id = "PebbleMallet",
		world = 3,
		sell = 5000,
		icon = "rbxassetid://119108914655796",
		price = 65000,
		rarity = "Uncommon",
		name = "Pebble Mallet",
		blurb = "A golem's stones on a stick. Big knockback.",
		order = 24,
		color = Color3.fromRGB(163, 152, 130),
		handed = 1,
		damage = 2339,
		cooldown = 0.8,
		reach = 6.5,
		arc = 90,
		maxTargets = 2,
		hitTime = 0.6,
		knockback = 9,
		swing = "CornBonk",
	},
	-- worn on both fists: the right glove is the model, the left glove its LeftGauntlet
	GoldGauntlets = {
		id = "GoldGauntlets",
		world = 3,
		sell = 5800,
		icon = "rbxassetid://115612303994754",
		price = 70000,
		rarity = "Rare",
		name = "Gold Gauntlets",
		blurb = "Solid gold fists. A fast one-two.",
		order = 25,
		color = Color3.fromRGB(224, 170, 34),
		handed = 2,
		worn = true,
		damage = 1552,
		cooldown = 0.45,
		reach = 5,
		arc = 70,
		maxTargets = 1,
		hitTime = 0.36,
		knockback = 2,
		swing = "Punch",
	},
	GeodeGlaive = {
		id = "GeodeGlaive",
		world = 3,
		sell = 17000,
		icon = "rbxassetid://104805345801317",
		price = 180000,
		rarity = "Epic",
		name = "Geode Glaive",
		blurb = "A geode on a pole. The longest sweep in the caves.",
		order = 26,
		color = Color3.fromRGB(195, 178, 255),
		handed = 2,
		damage = 3931,
		cooldown = 1.1,
		reach = 11.5,
		arc = 200,
		maxTargets = 5,
		hitTime = 0.54,
		knockback = 5,
		swing = "GlaiveSweep",
	},
	EmberCoalMaul = {
		id = "EmberCoalMaul",
		world = 3,
		sell = 18000,
		icon = "rbxassetid://118251004250439",
		price = 200000,
		rarity = "Epic",
		name = "Ember Coal Maul",
		blurb = "A smouldering lump of coal. Slams all around.",
		order = 27,
		color = Color3.fromRGB(255, 122, 26),
		handed = 2,
		damage = 4455,
		cooldown = 1.25,
		reach = 7.5,
		arc = 360,
		maxTargets = 6,
		hitTime = 0.6,
		knockback = 9,
		swing = "Slam2H",
		impact = "Slam",
	},
	-- Legendary: the Spider Queen's drop (5%)
	QueensFang = {
		id = "QueensFang",
		world = 3,
		sell = 39000,
		icon = "rbxassetid://119838500056485",
		rarity = "Legendary",
		name = "Queen's Fang",
		blurb = "The Spider Queen's own fang, still dripping venom.",
		order = 28,
		color = Color3.fromRGB(255, 92, 168),
		handed = 1,
		damage = 5947,
		cooldown = 1.05,
		reach = 9,
		arc = 140,
		maxTargets = 4,
		hitTime = 0.5,
		knockback = 5,
		swing = "Diagonal",
	},
	-- Legendary: the World 3 quest's final reward (Explorer Pip, ExplorerCaverns step 10, 2026-10-17).
	-- The only World 3 weapon that ignores armour (user's pick).
	DiamondPickaxe = {
		id = "DiamondPickaxe",
		world = 3,
		sell = 33500,
		icon = "rbxassetid://125209009387476",
		rarity = "Legendary",
		name = "Diamond Pickaxe",
		blurb = "Cuts through anything. Even armor.",
		order = 29,
		color = Color3.fromRGB(95, 232, 255),
		handed = 1,
		damage = 5363,
		cooldown = 1.1,
		reach = 8,
		arc = 100,
		maxTargets = 3,
		hitTime = 0.58,
		knockback = 8,
		swing = "MineLong",
		ignoreArmor = true,
	},
	-- SECRET: the Spider Queen's 2% (the joke crystal, like the Marshmallow Stick)
	RockCandyClub = {
		id = "RockCandyClub",
		world = 3,
		sell = 120000,
		icon = "rbxassetid://127581908994975",
		rarity = "Secret",
		secret = true,
		name = "Rock Candy Club",
		blurb = "The sweetest crystal in the caves. Bonk!",
		order = 30,
		color = Color3.fromRGB(185, 138, 255),
		handed = 1,
		damage = 7197,
		cooldown = 1.0,
		reach = 9.5,
		arc = 90,
		maxTargets = 3,
		hitTime = 0.5,
		knockback = 14,
		swing = "DiagonalLong",
	},
	-- ==================== the secret super weapon (memory secret-weapon-plan) ====================
	-- The Rusty Blade (2026-10-12): an extra reward on Dale's quest 5. Weaker than the
	-- Trowel on purpose -- its worth is the empty socket in its guard. Infusing the Farm
	-- Core (the Corn Wraith's 1% drop) at World 1's Crafter turns it into the Worldheart
	-- Blade (Transcendent); later worlds' cores fill its other sockets. Relic rarity:
	-- its own rusty-copper tile. Borrows the Machete's hold and swing for now.
	RustyBlade = {
		id = "RustyBlade",
		world = 1,
		icon = "rbxassetid://122696521889378",
		rarity = "Relic",
		name = "Rusty Blade",
		blurb = "Old, rusted and dull. There's an empty socket in the guard...",
		order = 19,
		color = Color3.fromRGB(196, 106, 58),
		handed = 1,
		damage = 10,
		cooldown = 0.55,
		reach = 6,
		arc = 90,
		maxTargets = 1,
		hitTime = 0.5,
		knockback = 0,
		swing = "Diagonal",
		keep = true, -- never sold: the only way to get the Worldheart Blade
	},
	-- The Rusty Blade awakened by the Farm Core (memory secret-weapon-plan, 2026-10-12): dark violet steel,
	-- 7 empty sockets down the blade for the other worlds' cores. With one core it is on par with World 1's
	-- secret (the Corn Cob, ~50 DPS); each later core will add a tier (not built yet). Not dropped or sold:
	-- the World 1 Crafter's infuser makes it (still to build); the admin panel gives it for testing.
	WorldheartBlade = {
		id = "WorldheartBlade",
		world = 1,
		icon = "rbxassetid://139512882134603", -- tier 1: the Farm Core gem (9-stud blade, re-rendered 2026-10-16)
		rarity = "Transcendent",
		name = "Worldheart Blade",
		blurb = "Awakened by the Farm Core. Seven empty sockets wait for the cores of other worlds.",
		order = 20,
		color = Color3.fromRGB(107, 47, 168),
		handed = 1,
		damage = 98, -- with 1 core; more cores raise it (Config/Infuse tiers)
		cooldown = 0.95,
		reach = 8.5,
		arc = 110,
		maxTargets = 3,
		hitTime = 0.5,
		knockback = 4,
		swing = "DiagonalHuge",
		keep = true,
		worldheartTier = 1,
	},
	-- Tier 2 (2026-10-12): the Worldheart Blade with the Forest Core set in as well. Each tier is its
	-- own weapon (user: an admin can hold the Rusty Blade, tier 1 and tier 2 at once); infusing the
	-- next core swaps the player's current tier for the next (InfuseService). Same model, hold and
	-- swing; its stats are tier 2's (Config/Infuse.tier), the numbers here are only the fallback.
	WorldheartBlade2 = {
		id = "WorldheartBlade2",
		world = 2,
		icon = "rbxassetid://94030372083642", -- tier 2: Farm + Forest Core gems (re-rendered 2026-10-16)
		rarity = "Transcendent",
		name = "Worldheart Blade II",
		blurb = "The Farm and Forest Cores burn in its sockets. Six remain empty.",
		order = 21,
		color = Color3.fromRGB(107, 47, 168),
		handed = 1,
		damage = 973,
		cooldown = 0.864,
		reach = 8.93,
		arc = 110,
		maxTargets = 3,
		hitTime = 0.5,
		knockback = 4,
		swing = "DiagonalHuge",
		keep = true,
		worldheartTier = 2,
	},
	-- Tier 3 (2026-10-13): the Cave Core (the Gem Mole's 1% drop) set in at World 3's Infuser. Same
	-- model, hold and swing; stats are tier 3's (Rock Candy Club DPS x1.1, +20% speed, +10% reach).
	WorldheartBlade3 = {
		id = "WorldheartBlade3",
		world = 3,
		icon = "rbxassetid://132665823343556", -- tier 3: Farm + Forest + Cave Core gems
		rarity = "Transcendent",
		name = "Worldheart Blade III",
		blurb = "The Farm, Forest and Cave Cores burn in its sockets. Five remain empty.",
		order = 22,
		color = Color3.fromRGB(107, 47, 168),
		handed = 1,
		damage = 9953,
		cooldown = 0.792,
		reach = 9.35,
		arc = 110,
		maxTargets = 3,
		hitTime = 0.5,
		knockback = 4,
		swing = "DiagonalHuge",
		keep = true,
		worldheartTier = 3,
	},
} :: { [string]: WeaponDef }

-- Equipped on every spawn until the player picks something else.
Weapons.default = "Dagger"

-- Rarity tiers, lowest first (the Inventory colours each item's tile by its tier).
-- Relic (the Rusty Blade) sits past Secret: weak, but one of a kind. Core is the
-- secret-weapon cores' tier (Config/Materials `core`), on the soil-brown tile. Transcendent (the
-- Worldheart Blade) is the top: a plum-to-deep-violet tile with a gold rim.
Weapons.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret", "Relic", "Core", "Transcendent" }

function Weapons.get(id: any): WeaponDef?
	return if type(id) == "string" then Weapons.Defs[id] else nil
end

-- Every weapon in Inventory order.
function Weapons.list(): { WeaponDef }
	local list: { WeaponDef } = {}
	for _, def in Weapons.Defs do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

return Weapons
