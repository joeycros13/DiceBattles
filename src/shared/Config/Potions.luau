--!strict
-- Potions (2026-10-19, agreed with the user): four potions, three tiers each, brewed at the
-- Crafter's Potions tab and drunk from the Inventory (click the tile, then Drink).
--
--   Health     an instant heal (over HEAL_SECONDS) of a share of max HP; a drink cooldown
--   Strength   + a share of weapon damage, applied last (MeleeService)
--   Stoneskin  - a share of damage taken, after armour's defence (MeleeService)
--   Swiftness  + a share of walk and sprint speed (SprintController)
-- World 2's three (2026-10-20, the user: the rest of the 2026-10-18 proposal; Tier I recipes are
-- for testing):
--   Regen      heals a share of max HP every second, on top of Roblox's own 1% and the Regen
--              upgrade (UpgradeService's regen tick)
--   Gatherer   + a share of a tool's power, so trees and rocks break in fewer hits (GatherService)
--   Angler     + a share of the weight of every fish rarer than Common at a spot, so rare fish
--              bite more often (FishingService)
--
-- Tiers follow world bands: Tier I is brewed from World 1-2 materials at those worlds'
-- Crafters, Tier II from World 3-5 materials plus a Tier I potion, Tier III from World 6-7
-- materials plus a Tier II potion. A tier is brewed at a Crafter of any world in its band,
-- except Tier I, which belongs to one world (the user, 2026-10-20): Health, Strength, Stoneskin and
-- Swiftness are World 1's, brewed only at its Crafter from its materials; Regen, Gatherer's and
-- Angler's are World 2's, brewed only at its Crafter from its materials (`world` on the def).
--
-- Rules (PotionService):
--   * the same potion at the same tier adds its time; a higher tier replaces a lower one (the
--     lower one's time is lost); a lower tier can't be drunk while a higher one runs
--   * different potions all run at once, each with its own chip on the BoostHud
--   * timers count down only while the player is in the game: dying doesn't touch them and
--     leaving pauses them (saved as the "potions" section)
--
-- A potion's id is <Kind><tier> ("Health1"). Recipes list materials (Config/Materials) and
-- potions (by id) with a count, plus coins. Tier I recipes use World 1 materials until World 2
-- has its own gathering; the numbers are placeholders the user can change. Tier III has no
-- recipe until Worlds 6-7 exist.

local Potions = {}

export type Ingredient = { id: string, count: number }
export type PotionDef = {
	id: string,
	kind: string,
	tier: number,
	name: string,
	short: string, -- the name without "Potion", for chips and the Crafter ("Gatherer's II")
	rarity: string, -- its tile colour (Weapons.Rarities)
	order: number,
	power: number, -- the effect's share (0.3 = 30%)
	seconds: number, -- how long it lasts (0 for Health: instant)
	recipe: { Ingredient }?, -- nil: can't be brewed yet
	coins: number,
	world: number?, -- Tier I only: the one world whose Crafter brews it (nil: any world of the band)
	sell: number, -- coins for selling one from the Inventory (placeholder, 2026-10-20)
	icon: string?,
	color: Color3,
}

Potions.Kinds = { "Health", "Strength", "Stoneskin", "Swiftness", "Regen", "Gatherer", "Angler" }
Potions.Numerals = { "I", "II", "III" }

-- The worlds whose Crafters brew each tier.
Potions.Bands = {
	{ from = 1, to = 2 },
	{ from = 3, to = 5 },
	{ from = 6, to = 7 },
}

Potions.HEAL_SECONDS = 1 -- a Health potion fills the bar over this long
Potions.HEALTH_COOLDOWN = 20 -- seconds before another Health potion can be drunk
Potions.MAX_SPEED = 0.25 -- Swiftness never goes past +25% (user's cap)
Potions.BASE_REGEN = 0.01 -- Roblox's own healing, a share of max HP a second (Regen's multiplier is against it)

-- What each kind does, per tier, and its look.
local KINDS: { [string]: any } = {
	Health = {
		label = "Health Potion",
		power = { 0.3, 0.5, 0.8 },
		seconds = { 0, 0, 0 },
		color = Color3.fromRGB(228, 66, 72),
		order = 1,
		world = 1,
	},
	Strength = {
		label = "Strength Potion",
		power = { 0.15, 0.25, 0.4 },
		seconds = { 180, 240, 300 },
		color = Color3.fromRGB(242, 140, 40),
		order = 2,
		world = 1,
	},
	Stoneskin = {
		label = "Stoneskin Potion",
		power = { 0.1, 0.2, 0.3 },
		seconds = { 180, 240, 300 },
		color = Color3.fromRGB(150, 150, 160),
		order = 3,
		world = 1,
	},
	Swiftness = {
		label = "Swiftness Potion",
		power = { 0.1, 0.18, 0.25 },
		seconds = { 180, 240, 300 },
		color = Color3.fromRGB(64, 196, 232),
		order = 4,
		world = 1,
	},
	-- power: a share of max HP healed every second (0.01 = 1%, doubling Roblox's own healing)
	Regen = {
		label = "Regen Potion",
		power = { 0.01, 0.015, 0.02 },
		seconds = { 180, 240, 300 },
		color = Color3.fromRGB(88, 200, 96),
		order = 5,
		world = 2,
	},
	-- power: + a share of the tool's power per hit (a Wooden Axe's 10 becomes 12.5: an oak in 4 chops, not 5)
	Gatherer = {
		label = "Gatherer's Potion",
		short = "Gatherer's",
		power = { 0.25, 0.5, 1 },
		seconds = { 180, 240, 300 },
		color = Color3.fromRGB(200, 130, 52),
		order = 6,
		world = 2,
	},
	-- power: + a share of every non-Common fish's weight (World 2's 60 / 30 / 10 becomes 60 / 45 / 15 at Tier I)
	Angler = {
		label = "Angler's Potion",
		short = "Angler's",
		power = { 0.5, 1, 1.5 },
		seconds = { 180, 240, 300 },
		color = Color3.fromRGB(58, 110, 232),
		order = 7,
		world = 2,
	},
}

local RARITY = { "Uncommon", "Epic", "Legendary" }

-- Placeholder recipes (user can change): Tier I from World 1 (fish + gathered + an enemy drop),
-- Tier II from World 3's enemy drops plus the Tier I potion.
local RECIPES: { [string]: { recipe: { Ingredient }, coins: number } } = {
	Health1 = { recipe = { { id = "Minnow", count = 2 }, { id = "ChickenFeather", count = 3 } }, coins = 25 },
	Strength1 = { recipe = { { id = "Sunfish", count = 1 }, { id = "BullHide", count = 2 }, { id = "OakLog", count = 2 } }, coins = 50 },
	Stoneskin1 = { recipe = { { id = "Stone", count = 4 }, { id = "BullHide", count = 2 }, { id = "Sunfish", count = 1 } }, coins = 50 },
	Swiftness1 = { recipe = { { id = "Horsehair", count = 2 }, { id = "Minnow", count = 2 }, { id = "OakLog", count = 2 } }, coins = 40 },
	-- World 2's, for testing (2026-10-20): only World 2's fish, gathered wood and enemy drops
	-- Amber Sap (the redwoods' rare drop) goes in the healing one (the user, 2026-10-20: use it in a World 2 recipe)
	Regen1 = { recipe = { { id = "Trout", count = 2 }, { id = "FoxFur", count = 3 }, { id = "AmberSap", count = 1 } }, coins = 400 },
	Gatherer1 = { recipe = { { id = "Perch", count = 2 }, { id = "BoarTusk", count = 2 }, { id = "RedwoodLog", count = 4 } }, coins = 450 },
	Angler1 = { recipe = { { id = "RainbowTrout", count = 1 }, { id = "Perch", count = 2 }, { id = "BearClaw", count = 1 } }, coins = 500 },
	-- World 3's Tier II (2026-10-24, the user: Health, Strength and Stoneskin II are World 3's; Swiftness II
	-- belongs to World 4): the Tier I potion, the glowing lake's fish, the mined ore or shards, an enemy drop
	Health2 = { recipe = { { id = "Health1", count = 1 }, { id = "Glowfish", count = 2 }, { id = "BatWing", count = 3 } }, coins = 4000 },
	Strength2 = { recipe = { { id = "Strength1", count = 1 }, { id = "CrystalEel", count = 1 }, { id = "IronOre", count = 4 }, { id = "GolemCrystal", count = 2 } }, coins = 5000 },
	Stoneskin2 = { recipe = { { id = "Stoneskin1", count = 1 }, { id = "BlindCavefish", count = 2 }, { id = "CrystalShard", count = 4 }, { id = "GolemPebble", count = 2 } }, coins = 5000 },
	Swiftness2 = { recipe = { { id = "Swiftness1", count = 1 }, { id = "BatWing", count = 3 }, { id = "GolemCrystal", count = 1 } }, coins = 4500 },
}

-- What one potion sells for from the Inventory (placeholders, 2026-10-20; World 2's Tier I brews and
-- sells x10 World 1's since 2026-10-24; Tier II, first brewed in World 3, x10 World 2's Tier I).
local SELL: { [string]: number } = {
	Health1 = 18,
	Strength1 = 32,
	Stoneskin1 = 29,
	Swiftness1 = 24,
	Health2 = 2500,
	Strength2 = 3200,
	Stoneskin2 = 3000,
	Swiftness2 = 2800,
	Health3 = 420,
	Strength3 = 560,
	Stoneskin3 = 515,
	Swiftness3 = 470,
	Regen1 = 250,
	Regen2 = 2800,
	Regen3 = 700,
	Gatherer1 = 280,
	Gatherer2 = 3000,
	Gatherer3 = 790,
	Angler1 = 320,
	Angler2 = 3200,
	Angler3 = 950,
}

-- Drawn icons, style B "grows with tier" (user's pick 2026-10-19): a vial, a bottle with a gold
-- collar, a gold decanter (art/tools/icons/potion_icons.py → art/icons/potions/).
local ICONS: { [string]: string } = {
	Health1 = "rbxassetid://96906400249097",
	Health2 = "rbxassetid://134768524806508",
	Health3 = "rbxassetid://115291350166883",
	Strength1 = "rbxassetid://90969307607055",
	Strength2 = "rbxassetid://108751104595027",
	Strength3 = "rbxassetid://121202039415654",
	Stoneskin1 = "rbxassetid://119330017125547",
	Stoneskin2 = "rbxassetid://134307654328870",
	Stoneskin3 = "rbxassetid://108049189531590",
	Swiftness1 = "rbxassetid://114114649795281",
	Swiftness2 = "rbxassetid://82114976938925",
	Swiftness3 = "rbxassetid://89917816345363",
	-- World 2's three (2026-10-20): Regen green with a plus, Gatherer's amber with an axe, Angler's blue with a fish
	Regen1 = "rbxassetid://90761972576074",
	Regen2 = "rbxassetid://100261071992720",
	Regen3 = "rbxassetid://96275987831548",
	Gatherer1 = "rbxassetid://135167643332794",
	Gatherer2 = "rbxassetid://131335149938680",
	Gatherer3 = "rbxassetid://105862877284140",
	Angler1 = "rbxassetid://102947906879139",
	Angler2 = "rbxassetid://71152897917402",
	Angler3 = "rbxassetid://91090191334479",
}

Potions.Defs = {} :: { [string]: PotionDef }
for kind, info in KINDS do
	for tier = 1, 3 do
		local id = kind .. tier
		local recipe = RECIPES[id]
		Potions.Defs[id] = {
			id = id,
			kind = kind,
			tier = tier,
			name = info.label .. " " .. Potions.Numerals[tier],
			short = (info.short or kind) .. " " .. Potions.Numerals[tier],
			rarity = RARITY[tier],
			order = tier * 10 + info.order,
			power = info.power[tier],
			seconds = info.seconds[tier],
			recipe = recipe and recipe.recipe,
			coins = recipe and recipe.coins or 0,
			world = if tier == 1 then info.world else nil,
			sell = SELL[id] or 0,
			icon = ICONS[id],
			color = info.color,
		}
	end
end

function Potions.get(id: any): PotionDef?
	return if type(id) == "string" then Potions.Defs[id] else nil
end

-- Every potion, by tier and then kind.
function Potions.list(): { PotionDef }
	local list = {}
	for _, def in Potions.Defs do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- The tier a world's Crafter brews (nil past the last band).
function Potions.tierAt(world: number): number?
	for tier, band in Potions.Bands do
		if world >= band.from and world <= band.to then
			return tier
		end
	end
	return nil
end

-- A share as a percentage without a needless ".0" (0.015 -> "1.5", 0.25 -> "25").
function Potions.percent(share: number): string
	local text = ("%.1f"):format(share * 100)
	return (text:gsub("%.0$", ""))
end

-- What a potion does, in words ("Heals 30% of your health", "+15% damage for 3:00").
function Potions.describe(def: PotionDef): string
	local percent = Potions.percent(def.power)
	local length = ("%d:%02d"):format(def.seconds // 60, def.seconds % 60)
	if def.kind == "Health" then
		return ("Heals %s%% of your health"):format(percent)
	elseif def.kind == "Strength" then
		return ("+%s%% damage for %s"):format(percent, length)
	elseif def.kind == "Stoneskin" then
		return ("%s%% less damage taken for %s"):format(percent, length)
	elseif def.kind == "Regen" then
		return ("Heals %s%% of your health a second for %s"):format(percent, length)
	elseif def.kind == "Gatherer" then
		return ("Tools hit trees and rocks %s%% harder for %s"):format(percent, length)
	elseif def.kind == "Angler" then
		return ("Rarer fish bite %s%% more often for %s"):format(percent, length)
	end
	return ("+%s%% speed for %s"):format(percent, length)
end

-- The player's potions held, from their "Potions" attribute ("Health1=2,Swiftness1=1";
-- PotionService publishes it). Works on both sides.
function Potions.counts(player: Player): { [string]: number }
	local out: { [string]: number } = {}
	local text = player:GetAttribute("Potions")
	for id, n in (if type(text) == "string" then text else ""):gmatch("([^,=]+)=(%d+)") do
		out[id] = tonumber(n) :: number
	end
	return out
end

-- The running effect of a kind on a player: (tier, seconds left), or nil. Read from the
-- "Potion_<kind>" (seconds left) and "PotionTier_<kind>" attributes.
function Potions.running(player: Player, kind: string): (number?, number)
	local left = player:GetAttribute("Potion_" .. kind)
	local tier = player:GetAttribute("PotionTier_" .. kind)
	if type(left) == "number" and left > 0 and type(tier) == "number" then
		return tier, left
	end
	return nil, 0
end

-- A running potion's power (0 when none): Regen's share of max HP a second, for one.
function Potions.power(player: Player, kind: string): number
	local tier = Potions.running(player, kind)
	local def = tier and Potions.get(kind .. tier)
	return if def then def.power else 0
end

-- The multiplier a running potion gives (1 when none): damage dealt (Strength), damage
-- taken (Stoneskin, below 1), speed (Swiftness), healing against Roblox's own 1% a second
-- (Regen), tool power (Gatherer) or the weight of fish rarer than Common (Angler).
function Potions.multiplier(player: Player, kind: string): number
	local tier = Potions.running(player, kind)
	local def = tier and Potions.get(kind .. tier)
	if not def then
		return 1
	end
	if kind == "Regen" then
		return 1 + def.power / Potions.BASE_REGEN
	elseif kind == "Stoneskin" then
		return 1 - def.power
	elseif kind == "Swiftness" then
		return 1 + math.min(def.power, Potions.MAX_SPEED)
	end
	return 1 + def.power
end

return Potions
