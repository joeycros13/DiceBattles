--!strict
-- AssetResolver: maps a logical id (e.g. "slot/Weapon", "rarity/Epic", "rig/idle")
-- to a placeholder visual (ARCHITECTURE.md 10, R-X4). v1 returns colors + a short
-- glyph label; swapping in real assets later means editing only the maps below.
-- UI code renders whatever `resolve` returns and never hard-codes asset ids.
--
-- Logical-id categories (all resolve here; add new ones in one place):
--   tab/<TabId>          explicit MAP entry
--   currency/<id>        explicit MAP entry (Config/Currencies icon)
--   rig/<name>           explicit MAP entry (ViewportFrame body tint)
--   rarity/<RarityId>    Config/Rarities color
--   slot/<SlotId>        SLOT_COLORS
--   gear/<SlotId>        SLOT_COLORS (gear inherits its slot's tint)
--   talent/<Effect>      EFFECT_VISUALS (Config/Talents icon)
--   trait/<Effect>       EFFECT_VISUALS (Config/Traits icon)
--   shop/<ShopKind>      SHOP_VISUALS (Config/Shop icon)
--   enemy/<name>         ENEMY_VISUALS (Config/Enemies icon)
--   anim/<name>          ANIMATIONS (see AssetResolver.animationId)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))

local AssetResolver = {}

-- A resolved placeholder visual. `image` is "" until a real asset id is wired in;
-- consumers should show the color + label when `image` is empty.
export type Visual = {
	image: string, -- rbxassetid string, or "" for a pure color/label placeholder
	color: Color3,
	label: string, -- short glyph/text drawn over the placeholder
}

local deps: any = nil

local FALLBACK: Visual = {
	image = "",
	color = Color3.fromRGB(70, 74, 92),
	label = "?",
}

-- Explicit visuals for well-known logical ids. Category prefixes not listed here
-- fall through to the rule-based resolver below.
local MAP: { [string]: Visual } = {
	["tab/Equipment"] = { image = "", color = Color3.fromRGB(96, 140, 255), label = "EQ" },
	["tab/Battle"] = { image = "", color = Color3.fromRGB(228, 108, 92), label = "BT" },
	["tab/Talents"] = { image = "", color = Color3.fromRGB(140, 108, 235), label = "TL" },
	["tab/Shop"] = { image = "", color = Color3.fromRGB(80, 200, 120), label = "SH" },

	["rig/idle"] = { image = "", color = Color3.fromRGB(120, 124, 140), label = "RIG" },

	["currency/coins"] = { image = "", color = Color3.fromRGB(245, 200, 70), label = "C" },
	["currency/gems"] = { image = "", color = Color3.fromRGB(120, 210, 235), label = "G" },
	["currency/materials"] = { image = "", color = Color3.fromRGB(180, 150, 110), label = "M" },
	["currency/keys"] = { image = "", color = Color3.fromRGB(230, 210, 150), label = "K" },
}

-- Per-effect placeholder tints + short glyphs, shared by talents and traits since
-- both key their icons off the same effect vocabulary (TalentEffect / TraitEffect
-- in Config/Talents & Config/Traits). Icons resolve as "talent/<effect>" or
-- "trait/<effect>", e.g. "talent/hp" or "trait/damageReduction".
local EFFECT_VISUALS: { [string]: Visual } = {
	flatAttack = { image = "", color = Color3.fromRGB(224, 108, 92), label = "ATK" },
	pctAttack = { image = "", color = Color3.fromRGB(232, 140, 96), label = "%AK" },
	critChance = { image = "", color = Color3.fromRGB(245, 200, 70), label = "CRT" },
	critMultiplier = { image = "", color = Color3.fromRGB(245, 170, 60), label = "CDM" },
	extraReroll = { image = "", color = Color3.fromRGB(120, 210, 235), label = "RRL" },
	extraDice = { image = "", color = Color3.fromRGB(140, 108, 235), label = "DIE" },
	hp = { image = "", color = Color3.fromRGB(80, 200, 120), label = "HP" },
	lifesteal = { image = "", color = Color3.fromRGB(200, 90, 150), label = "LFS" },
	damageReduction = { image = "", color = Color3.fromRGB(120, 150, 200), label = "DEF" },
	healAmount = { image = "", color = Color3.fromRGB(110, 205, 150), label = "HEL" },
}

-- Per-shop-kind placeholder tints + short glyphs (keyed by ShopKind from
-- Config/Shop). Shop icons resolve as "shop/<kind>" e.g. "shop/gamepass".
local SHOP_VISUALS: { [string]: Visual } = {
	gamepass = { image = "", color = Color3.fromRGB(245, 200, 70), label = "VIP" },
	product = { image = "", color = Color3.fromRGB(120, 210, 235), label = "R$" },
	daily = { image = "", color = Color3.fromRGB(80, 200, 120), label = "DAY" },
}

-- Logical animation ids → concrete Roblox asset ids. Kept here (not hard-coded in
-- UI) so swapping in a bespoke idle/emote is a one-line change (R-X4 covers
-- animations). 0 = unset (animationId returns "" and callers skip loading).
local ANIMATIONS: { [string]: number } = {
	-- A plain, valid idle clip. The avatar's own idle is a PACKAGE (bundle) that
	-- LoadAnimation cannot resolve inside a ViewportFrame, so we use this default.
	idle = 507766388,
}

-- Per-enemy placeholder tints + short glyphs (keyed by the lowercase name that
-- follows "enemy/" in an EnemyDef.icon, e.g. "enemy/slime"). Bosses use a
-- distinct warm palette so they read as threats.
local ENEMY_VISUALS: { [string]: Visual } = {
	slime = { image = "", color = Color3.fromRGB(120, 200, 120), label = "SL" },
	goblin = { image = "", color = Color3.fromRGB(150, 175, 90), label = "GB" },
	archer = { image = "", color = Color3.fromRGB(110, 160, 210), label = "AR" },
	golem = { image = "", color = Color3.fromRGB(150, 140, 120), label = "GO" },
	boss_ogre = { image = "", color = Color3.fromRGB(210, 120, 80), label = "OG" },
	boss_lich = { image = "", color = Color3.fromRGB(160, 100, 200), label = "LI" },
	boss_dragon = { image = "", color = Color3.fromRGB(220, 90, 70), label = "DR" },
}

-- Per-slot placeholder tints (keyed by slot id from Config/Slots).
local SLOT_COLORS: { [string]: Color3 } = {
	Helmet = Color3.fromRGB(150, 170, 200),
	Weapon = Color3.fromRGB(210, 120, 110),
	Belt = Color3.fromRGB(170, 140, 110),
	Charm = Color3.fromRGB(200, 160, 210),
	Chestplate = Color3.fromRGB(130, 160, 150),
	Boots = Color3.fromRGB(140, 150, 175),
}

function AssetResolver.init(injected: any)
	deps = injected
end

function AssetResolver.start() end

-- Split "category/name" into its two parts (name may be empty).
local function split(id: string): (string, string)
	local slash = string.find(id, "/", 1, true)
	if not slash then
		return id, ""
	end
	return string.sub(id, 1, slash - 1), string.sub(id, slash + 1)
end

-- Color for a rarity id, from Config/Rarities (falls back to grey).
function AssetResolver.rarityColor(rarityId: string): Color3
	local def = Rarities.get(rarityId)
	return def and def.color or FALLBACK.color
end

-- Resolve a logical id to a placeholder Visual. Always returns a value.
function AssetResolver.resolve(id: string): Visual
	local explicit = MAP[id]
	if explicit then
		return explicit
	end

	local category, name = split(id)
	if category == "rarity" then
		return {
			image = "",
			color = AssetResolver.rarityColor(name),
			label = string.sub(name, 1, 1),
		}
	elseif category == "slot" then
		return {
			image = "",
			color = SLOT_COLORS[name] or FALLBACK.color,
			label = string.sub(name, 1, 2),
		}
	elseif category == "gear" then
		-- Gear placeholders inherit their slot's tint (name is the slot id).
		return {
			image = "",
			color = SLOT_COLORS[name] or FALLBACK.color,
			label = string.sub(name, 1, 2),
		}
	elseif category == "talent" or category == "trait" then
		-- Talents and traits share the same effect vocabulary (name is the effect).
		return EFFECT_VISUALS[name] or FALLBACK
	elseif category == "shop" then
		-- Shop placeholders keyed by ShopKind (name is "gamepass"/"product"/"daily").
		return SHOP_VISUALS[name] or FALLBACK
	elseif category == "enemy" then
		-- Enemy placeholders keyed by the archetype's icon suffix.
		return ENEMY_VISUALS[name] or FALLBACK
	end

	return FALLBACK
end

-- Resolve a logical animation id (e.g. "anim/idle") to a concrete rbxassetid
-- string, or "" when unset. Callers load only when non-empty, so swapping the
-- clip (or clearing it) never touches UI logic.
function AssetResolver.animationId(id: string): string
	local category, name = split(id)
	local assetId = category == "anim" and ANIMATIONS[name] or 0
	if assetId == 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(assetId)
end

-- Convenience: apply a resolved visual onto an ImageLabel/ImageButton.
-- Uses the real image if present, otherwise renders the color placeholder.
function AssetResolver.applyImage(target: ImageLabel | ImageButton, id: string)
	local visual = AssetResolver.resolve(id)
	target.Image = visual.image
	if visual.image == "" then
		target.BackgroundTransparency = 0
		target.BackgroundColor3 = visual.color
	else
		target.ImageColor3 = Color3.new(1, 1, 1)
	end
end

return AssetResolver
