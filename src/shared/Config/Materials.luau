--!strict
-- Materials: the crafting materials players collect for armour (Config/Armor),
-- decided with the user on 2026-10-12.
--
-- Each world has four enemy materials, one per enemy, plus one quest item:
--   * enemies 1 and 2 drop theirs for the world's first armour set;
--   * enemy 3 and the boss drop theirs for the second set;
--   * the quest item comes from the world's questline (the "defeat the boss" step,
--     Config/Quests `reward.item`) and also goes into the second set.
-- Which enemy drops what, how often and how many lives in that enemy's
-- `materials` table in Config/Worlds (MaterialService rolls it on every kill).
--
--   id      the key, saved in the player's "materials" section
--   name    shown in the Crafting panel, the Materials view and the drop pop-up
--   world   the world it belongs to (the Materials view groups by it)
--   order   sort order inside its world
--   source  the enemy that drops it (an enemy id), the questline it comes from, or for a
--           gathered material the Config/Gathering node that gives it (with `gathered`)
--   gathered true for a material broken out of a gathering node (2026-10-18)
--   fished  true for a fish (2026-10-18), with `gathered`: `source` is the Config/Fishing
--           spot it bites at
--   rarity  its tile colour, one of Weapons.Rarities (user, 2026-10-12): in each world the
--           first enemy's material is Common, the second's Uncommon, the third's Rare,
--           the boss's Epic; quest items are Legendary
--   quest   true for a quest item: given once, never dropped
--   core    true for a secret-weapon core (2026-10-12): one per world, dropped about 1% by
--           that world's secret enemy, at most once per player (no duplicates, no pity);
--           it shows the big Index-style popup (rarity "Core") instead of a side toast, and
--           is infused into the Rusty Blade at that world's Crafter (the Farm Core first)
--   sell    coins for selling ONE from the Inventory (placeholder, 2026-10-20); quest items
--           and cores have none and can't be sold
--   color   its signature colour (the drop pop-up's accent until it has an icon)
--   icon    its drawn picture (designed on the Crafting & Armor canvas, art/icons/)

local Materials = {}

export type MaterialDef = {
	id: string,
	name: string,
	world: number,
	order: number,
	rarity: string,
	source: string,
	quest: boolean?,
	core: boolean?,
	gathered: boolean?,
	fished: boolean?,
	sell: number?,
	color: Color3,
	icon: string?,
}

Materials.Defs = {
	-- ==================== World 1 (The Sunny Meadows) ====================
	ChickenFeather = {
		id = "ChickenFeather",
		rarity = "Common",
		icon = "rbxassetid://100543718756830",
		name = "Chicken Feather",
		world = 1,
		sell = 2,
		order = 1,
		source = "Chicken",
		color = Color3.fromRGB(250, 246, 236),
	},
	BullHide = {
		id = "BullHide",
		rarity = "Uncommon",
		icon = "rbxassetid://85942265201882",
		name = "Bull Hide",
		world = 1,
		sell = 3,
		order = 2,
		source = "Bull",
		color = Color3.fromRGB(122, 74, 46),
	},
	Horsehair = {
		id = "Horsehair",
		rarity = "Rare",
		icon = "rbxassetid://97499083216514",
		name = "Horsehair",
		world = 1,
		sell = 8,
		order = 3,
		source = "Stallion",
		color = Color3.fromRGB(58, 60, 68),
	},
	GoldenStraw = {
		id = "GoldenStraw",
		rarity = "Epic",
		icon = "rbxassetid://84240567751498",
		name = "Golden Straw",
		world = 1,
		sell = 14,
		order = 4,
		source = "BossScarecrow",
		color = Color3.fromRGB(255, 205, 64),
	},
	LuckyHorseshoe = {
		id = "LuckyHorseshoe",
		rarity = "Legendary",
		icon = "rbxassetid://133553972989886",
		name = "Dale's Lucky Horseshoe",
		world = 1,
		order = 5,
		source = "DaleFarm",
		quest = true,
		color = Color3.fromRGB(176, 182, 190),
	},
	FarmCore = {
		id = "FarmCore",
		rarity = "Core",
		icon = "rbxassetid://71518709693512", -- the mirrored quad gem (2026-10-13)
		name = "Farm Core",
		world = 1,
		order = 6,
		source = "CornWraith",
		core = true,
		color = Color3.fromRGB(184, 50, 58),
	},
	-- gathered (2026-10-18): chopped and mined from World 1's nodes (Config/Gathering). Icons drawn
	-- 2026-10-19 (art/tools/icons/w1_gather_icons.html).
	OakLog = {
		id = "OakLog",
		icon = "rbxassetid://104043389166635",
		rarity = "Common",
		name = "Oak Log",
		world = 1,
		sell = 2,
		order = 7,
		source = "OakTree",
		gathered = true,
		color = Color3.fromRGB(150, 104, 62),
	},
	Stone = {
		id = "Stone",
		icon = "rbxassetid://118574059729672",
		rarity = "Common",
		name = "Stone",
		world = 1,
		sell = 2,
		order = 8,
		source = "Boulder",
		gathered = true,
		color = Color3.fromRGB(150, 150, 146),
	},
	-- fished (2026-10-18): caught at the pond (Config/Fishing). Every fish is the same dark
	-- shadow in the water; only these icons differ (w1_gather_icons.html, 2026-10-19).
	Minnow = {
		id = "Minnow",
		icon = "rbxassetid://135916252607286",
		rarity = "Common",
		name = "Minnow",
		world = 1,
		sell = 2,
		order = 9,
		source = "SunnyPond",
		gathered = true,
		fished = true,
		color = Color3.fromRGB(150, 176, 190),
	},
	Sunfish = {
		id = "Sunfish",
		icon = "rbxassetid://101784354405776",
		rarity = "Uncommon",
		name = "Sunfish",
		world = 1,
		sell = 5,
		order = 10,
		source = "SunnyPond",
		gathered = true,
		fished = true,
		color = Color3.fromRGB(240, 170, 60),
	},
	GoldenCarp = {
		id = "GoldenCarp",
		icon = "rbxassetid://105639157556378",
		rarity = "Rare",
		name = "Golden Carp",
		world = 1,
		sell = 8,
		order = 11,
		source = "SunnyPond",
		gathered = true,
		fished = true,
		color = Color3.fromRGB(246, 200, 64),
	},
	-- ==================== World 2 (The Redwood Forest) ====================
	FoxFur = {
		id = "FoxFur",
		rarity = "Common",
		icon = "rbxassetid://86600481340451",
		name = "Fox Fur",
		world = 2,
		sell = 20,
		order = 1,
		source = "Fox",
		color = Color3.fromRGB(240, 120, 40),
	},
	BoarTusk = {
		id = "BoarTusk",
		rarity = "Uncommon",
		icon = "rbxassetid://121748887194395",
		name = "Boar Tusk",
		world = 2,
		sell = 30,
		order = 2,
		source = "Boar",
		color = Color3.fromRGB(244, 236, 214),
	},
	BearClaw = {
		id = "BearClaw",
		rarity = "Rare",
		icon = "rbxassetid://100972982041577",
		name = "Bear Claw",
		world = 2,
		sell = 80,
		order = 3,
		source = "Bear",
		color = Color3.fromRGB(46, 40, 38),
	},
	HeartwoodSap = {
		id = "HeartwoodSap",
		rarity = "Epic",
		icon = "rbxassetid://131595994723597",
		name = "Heartwood Sap",
		world = 2,
		sell = 140,
		order = 4,
		source = "ElderTreant",
		color = Color3.fromRGB(255, 176, 46),
	},
	RangerBadge = {
		id = "RangerBadge",
		rarity = "Legendary",
		icon = "rbxassetid://129405277446389",
		name = "Ranger's Badge",
		world = 2,
		order = 5,
		source = "RangerRedwoods",
		quest = true,
		color = Color3.fromRGB(232, 186, 60),
	},
	ForestCore = {
		id = "ForestCore",
		rarity = "Core",
		icon = "rbxassetid://102403704250894", -- the mirrored quad gem (2026-10-13)
		name = "Forest Core",
		world = 2,
		order = 6,
		source = "Fairy",
		core = true,
		color = Color3.fromRGB(30, 140, 74),
	},
	-- gathered (2026-10-20): chopped from World 2's redwoods (Config/Gathering "RedwoodTree", a Stone Axe
	-- or better); Amber Sap is the rare drop. Icons: art/tools/icons/w2_gather_icons.html.
	RedwoodLog = {
		id = "RedwoodLog",
		icon = "rbxassetid://102750422922660",
		rarity = "Common",
		name = "Redwood Log",
		world = 2,
		sell = 20,
		order = 7,
		source = "RedwoodTree",
		gathered = true,
		color = Color3.fromRGB(140, 59, 36),
	},
	AmberSap = {
		id = "AmberSap",
		icon = "rbxassetid://126989956537553",
		rarity = "Rare",
		name = "Amber Sap",
		world = 2,
		sell = 80,
		order = 8,
		source = "RedwoodTree",
		gathered = true,
		color = Color3.fromRGB(240, 160, 40),
	},
	-- fished (2026-10-20): caught in World 2's creek and pond (Config/Fishing "RedwoodPond",
	-- a Stone Rod or better). Icons: art/tools/icons/w2_fish_icons.html, the World 1 fish's shape.
	Trout = {
		id = "Trout",
		icon = "rbxassetid://93149400962088",
		rarity = "Common",
		name = "Trout",
		world = 2,
		sell = 20,
		order = 9,
		source = "RedwoodPond",
		gathered = true,
		fished = true,
		color = Color3.fromRGB(127, 154, 72),
	},
	Perch = {
		id = "Perch",
		icon = "rbxassetid://88894631856595",
		rarity = "Uncommon",
		name = "Perch",
		world = 2,
		sell = 50,
		order = 10,
		source = "RedwoodPond",
		gathered = true,
		fished = true,
		color = Color3.fromRGB(196, 196, 62),
	},
	RainbowTrout = {
		id = "RainbowTrout",
		icon = "rbxassetid://112485612041250",
		rarity = "Rare",
		name = "Rainbow Trout",
		world = 2,
		sell = 80,
		order = 11,
		source = "RedwoodPond",
		gathered = true,
		fished = true,
		color = Color3.fromRGB(240, 122, 160),
	},
	-- ==================== World 3 (The Crystal Caverns) ====================
	-- (2026-10-13; no icons drawn yet, so the drop pop-up shows each colour)
	BatWing = {
		id = "BatWing",
		icon = "rbxassetid://88978398173349",
		rarity = "Common",
		name = "Bat Wing",
		world = 3,
		sell = 200,
		order = 1,
		source = "CaveBat",
		color = Color3.fromRGB(91, 79, 114),
	},
	GolemPebble = {
		id = "GolemPebble",
		icon = "rbxassetid://81057452845619",
		rarity = "Uncommon",
		name = "Golem Pebble",
		world = 3,
		sell = 300,
		order = 2,
		source = "PebbleGolem",
		color = Color3.fromRGB(255, 167, 51),
	},
	GolemCrystal = {
		id = "GolemCrystal",
		icon = "rbxassetid://117290053300265",
		rarity = "Rare",
		name = "Golem Crystal",
		world = 3,
		sell = 800,
		order = 3,
		source = "CrystalGolem",
		color = Color3.fromRGB(127, 244, 255),
	},
	QueensSilk = {
		id = "QueensSilk",
		icon = "rbxassetid://99319386625760",
		rarity = "Epic",
		name = "Queen's Silk",
		world = 3,
		sell = 1400,
		order = 4,
		source = "SpiderQueen",
		color = Color3.fromRGB(255, 92, 168),
	},
	-- the World 3 quest item (2026-10-13): given by Explorer Pip's defeat-the-Spider-Queen step
	-- (ExplorerCaverns step 8, 2026-10-17). Goes into Crystal Queen.
	MinersLantern = {
		id = "MinersLantern",
		icon = "rbxassetid://110907424907998",
		rarity = "Legendary",
		name = "Miner's Lantern",
		world = 3,
		order = 5,
		source = "ExplorerCaverns",
		quest = true,
		color = Color3.fromRGB(242, 194, 48),
	},
	-- the World 3 secret core (2026-10-13): pink with a gold pickaxe, dropped by the Gem Mole in the
	-- hidden mine.
	CaveCore = {
		id = "CaveCore",
		rarity = "Core",
		icon = "rbxassetid://128965725393405",
		name = "Cave Core",
		world = 3,
		order = 6,
		source = "GemMole",
		core = true,
		color = Color3.fromRGB(217, 58, 140),
	},
	-- gathered (2026-10-24, the user's World 3 gathering): mined from the Ore Rocks and Crystal
	-- Clusters (Config/Gathering, a Crystal Pickaxe or better); the Raw Gem is the cluster's rare
	-- drop. Sells x10 World 2's. Icons: art/tools/icons/w3_gather_icons.html.
	IronOre = {
		id = "IronOre",
		icon = "rbxassetid://106398702931897",
		rarity = "Common",
		name = "Iron Ore",
		world = 3,
		sell = 200,
		order = 7,
		source = "OreRock",
		gathered = true,
		color = Color3.fromRGB(218, 163, 123),
	},
	CrystalShard = {
		id = "CrystalShard",
		icon = "rbxassetid://126422401668223",
		rarity = "Common",
		name = "Crystal Shard",
		world = 3,
		sell = 200,
		order = 8,
		source = "CrystalCluster",
		gathered = true,
		color = Color3.fromRGB(111, 216, 240),
	},
	RawGem = {
		id = "RawGem",
		icon = "rbxassetid://78888808331617",
		rarity = "Rare",
		name = "Raw Gem",
		world = 3,
		sell = 800,
		order = 9,
		source = "CrystalCluster",
		gathered = true,
		color = Color3.fromRGB(224, 51, 111),
	},
	-- fished (2026-10-24): caught in the glowing lake (Config/Fishing "CrystalLake", a Crystal Rod
	-- or better).
	Glowfish = {
		id = "Glowfish",
		icon = "rbxassetid://106802223373555",
		rarity = "Common",
		name = "Glowfish",
		world = 3,
		sell = 200,
		order = 10,
		source = "CrystalLake",
		gathered = true,
		fished = true,
		color = Color3.fromRGB(120, 230, 210),
	},
	BlindCavefish = {
		id = "BlindCavefish",
		icon = "rbxassetid://134073876840921",
		rarity = "Uncommon",
		name = "Blind Cavefish",
		world = 3,
		sell = 500,
		order = 11,
		source = "CrystalLake",
		gathered = true,
		fished = true,
		color = Color3.fromRGB(240, 214, 220),
	},
	CrystalEel = {
		id = "CrystalEel",
		icon = "rbxassetid://99965290339014",
		rarity = "Rare",
		name = "Crystal Eel",
		world = 3,
		sell = 800,
		order = 12,
		source = "CrystalLake",
		gathered = true,
		fished = true,
		color = Color3.fromRGB(168, 140, 255),
	},
} :: { [string]: MaterialDef }

function Materials.get(id: any): MaterialDef?
	return if type(id) == "string" then Materials.Defs[id] else nil
end

-- Every material, by world and then order.
function Materials.list(): { MaterialDef }
	local list: { MaterialDef } = {}
	for _, def in Materials.Defs do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		if a.world ~= b.world then
			return a.world < b.world
		end
		return a.order < b.order
	end)
	return list
end

-- The player's counts, from their "Materials" attribute ("BullHide=3,ChickenFeather=12";
-- MaterialService publishes it). Works on both sides.
function Materials.counts(player: Player): { [string]: number }
	local out: { [string]: number } = {}
	local text = player:GetAttribute("Materials")
	for id, n in (if type(text) == "string" then text else ""):gmatch("([^,=]+)=(%d+)") do
		out[id] = tonumber(n) :: number
	end
	return out
end

return Materials
