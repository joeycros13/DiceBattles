--!strict
-- Armor: the armour sets, crafted at the Crafting stall (CraftingService), worn
-- one at a time (ArmorService). Decided with the user on 2026-10-12; the numbers
-- are starting values.
--
-- A set is ONE item (the Inventory has a single Armour slot). Two sets per world:
--   * set 1: materials from the world's first two enemies, coins and a level;
--   * set 2: materials from enemy 3 and the boss, the world's quest item, coins
--     and a level.
--
--   id        the key, saved in the player's "armor" section
--   name      shown in the Crafting panel and the Inventory
--   blurb     one line for the Crafting panel
--   world     the world whose stall crafts it
--   order     sort order (the Crafting panel and the Inventory list)
--   rarity    the tile colour, one of Weapons.Rarities
--   level     the level needed to craft it
--   coins     coins spent crafting it
--   recipe    the materials it takes, in display order (Config/Materials ids);
--             all of them are used up
--   defense   0..1: the fraction taken off every enemy hit while it's worn
--   health    extra max HP while it's worn, on top of the level's: about a quarter to a
--             third of a player's HP at the set's level (see World scale below), so
--             armour stays worth wearing
--   regen     (optional) extra share of max HP healed a second while it's worn, on top of
--             Roblox's 1% and the Regen upgrade / potion (UpgradeService's regen tick)
--   speed     (optional) extra walk and sprint speed while it's worn, a share (0.05 = +5%;
--             SprintController; armour and Swiftness together never pass Armor.MAX_SPEED)
--             Bonuses (2026-10-22, the user: beginner sets have none, later ones one,
--             later still both, growing big): World 1 none; World 2 Woodland Hide +5% speed,
--             Heartwood Bark +0.25% regen; World 3 Cave Runner +10% speed, Crystal Queen
--             +0.5% regen and +8% speed; Worlds 4-7 both, up to about +2% / +25%.
--   sell      coins for selling it from the Inventory (placeholder, 2026-10-20)
--   icon      its drawn picture (designed on the Crafting & Armor canvas, art/icons/)

-- World scale (the rescale, 2026-10-24): coins and sell prices go x10 a world, and health is set so every set
-- adds about a quarter to a third of the level's max HP when it unlocks (the user: only enemy damage has to follow
-- the x10; armour, weapons, enemy health and drop rates follow what plays right against it): Farmhand's Gear 35 of
-- 145 at level 5, Harvest Knight 75 of 331 at 14, Woodland Hide 350 of 1,202 at 28, Heartwood Bark 750 of 2,089 at
-- 34, Cave Runner 5,500 of 19,055 at 58, Crystal Queen 13,000 of 36,308 at 65 (World 2's 29% / 36%; they were
-- 3,500 / 7,500, x10 World 2's, until their levels moved up). Defence, regen and speed are shares and don't scale.

local Armor = {}

export type Ingredient = { id: string, count: number }
export type ArmorDef = {
	id: string,
	name: string,
	blurb: string,
	world: number,
	order: number,
	rarity: string,
	level: number,
	coins: number,
	recipe: { Ingredient },
	defense: number,
	health: number,
	regen: number?,
	speed: number?,
	sell: number?,
	icon: string?,
}

-- Worn armour and a Swiftness potion together never make walking more than this much faster.
Armor.MAX_SPEED = 0.5

Armor.Defs = {
	-- ==================== World 1 (The Sunny Meadows) ====================
	FarmhandsGear = {
		id = "FarmhandsGear",
		icon = "rbxassetid://71932067359739",
		name = "Farmhand's Gear",
		blurb = "Stitched from feathers and hide. Better than nothing!",
		world = 1,
		sell = 62,
		order = 1,
		rarity = "Uncommon",
		level = 5,
		coins = 150,
		recipe = {
			{ id = "ChickenFeather", count = 15 },
			{ id = "BullHide", count = 10 },
			{ id = "OakLog", count = 8 }, -- gathered (2026-10-19, user)
		},
		defense = 0.10,
		health = 35,
	},
	HarvestKnight = {
		id = "HarvestKnight",
		icon = "rbxassetid://76701684844891",
		name = "Harvest Knight",
		blurb = "Golden straw plate with Dale's lucky horseshoe on the chest.",
		world = 1,
		sell = 150,
		order = 2,
		rarity = "Rare",
		level = 14,
		coins = 750,
		recipe = {
			{ id = "Horsehair", count = 8 },
			{ id = "GoldenStraw", count = 3 },
			{ id = "LuckyHorseshoe", count = 1 },
			{ id = "Stone", count = 12 }, -- gathered (2026-10-19, user)
			{ id = "OakLog", count = 6 },
		},
		defense = 0.18,
		health = 75,
	},
	-- ==================== World 2 (The Redwood Forest) ====================
	WoodlandHide = {
		id = "WoodlandHide",
		icon = "rbxassetid://112957981852004",
		name = "Woodland Hide",
		blurb = "Fox fur and tusk toggles. Warm and tough.",
		world = 2,
		sell = 620,
		order = 3,
		rarity = "Rare",
		level = 28, -- 20 until 2026-10-21: players arrive at 25, so it unlocked on arrival
		coins = 1500,
		recipe = {
			{ id = "FoxFur", count = 15 },
			{ id = "BoarTusk", count = 10 },
			{ id = "RedwoodLog", count = 10 }, -- gathered (2026-10-21, user: like World 1's sets)
		},
		defense = 0.25,
		health = 350,
		speed = 0.05,
	},
	HeartwoodBark = {
		id = "HeartwoodBark",
		icon = "rbxassetid://132195103624695",
		name = "Heartwood Bark",
		blurb = "Living bark, bear claws and the ranger's badge.",
		world = 2,
		sell = 1500,
		order = 4,
		rarity = "Epic",
		level = 34, -- 27 until 2026-10-21: Rowan's second level step, like Harvest Knight and Dale's
		coins = 7500,
		recipe = {
			{ id = "BearClaw", count = 10 },
			{ id = "HeartwoodSap", count = 3 },
			{ id = "RangerBadge", count = 1 },
			{ id = "RedwoodLog", count = 12 }, -- gathered (2026-10-21)
			{ id = "AmberSap", count = 1 },
		},
		defense = 0.32,
		health = 750,
		regen = 0.0025,
	},
	-- ==================== World 3 (The Crystal Caverns), 2026-10-13 ====================
	CaveRunner = {
		id = "CaveRunner",
		icon = "rbxassetid://114489790834583",
		name = "Cave Runner",
		blurb = "Golem stone with a glowing core and stone bat wings.",
		world = 3,
		sell = 6200,
		order = 5,
		rarity = "Epic",
		level = 58, -- 53 until 2026-10-24: Pip's EXP rewards got players there in under 4 minutes
		coins = 15000,
		recipe = {
			{ id = "BatWing", count = 15 },
			{ id = "GolemPebble", count = 10 },
			{ id = "IronOre", count = 12 }, -- mined (2026-10-24), like Woodland Hide's Redwood Logs
		},
		defense = 0.38,
		health = 5500,
		speed = 0.10,
	},
	CrystalQueen = {
		id = "CrystalQueen",
		icon = "rbxassetid://119317145003009",
		name = "Crystal Queen",
		blurb = "Spider carapace, the Queen's hourglass and a burst of crystals.",
		world = 3,
		sell = 15000,
		order = 6,
		rarity = "Legendary",
		level = 65, -- 59 until 2026-10-24; Pip's second level step, like Heartwood Bark and Rowan's
		coins = 75000,
		recipe = {
			{ id = "GolemCrystal", count = 10 },
			{ id = "QueensSilk", count = 3 },
			{ id = "MinersLantern", count = 1 },
			{ id = "CrystalShard", count = 12 }, -- mined (2026-10-24), like Heartwood Bark's logs and sap
			{ id = "RawGem", count = 1 },
		},
		defense = 0.44,
		health = 13000,
		regen = 0.005,
		speed = 0.08,
	},
} :: { [string]: ArmorDef }

function Armor.get(id: any): ArmorDef?
	return if type(id) == "string" then Armor.Defs[id] else nil
end

-- Every set in order.
function Armor.list(): { ArmorDef }
	local list: { ArmorDef } = {}
	for _, def in Armor.Defs do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

return Armor
