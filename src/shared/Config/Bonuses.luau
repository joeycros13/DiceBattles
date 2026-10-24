--!strict
-- Bonuses: every stat's total, worked out in ONE place for the server (the real effect)
-- and for every screen (the numbers shown), so the two always agree.
--
-- Bonuses ADD before they multiply (2026-10-23, the user: "buying 1.5x and 2x gamepass
-- means 0.5 + 1 = 2.5x"; multiplied, maxed luck reached 16.5x). Each source gives a share
-- (x1.5 = +0.5) and a stat is 1 + the sum of its shares:
--   Luck / Coins / EXP   the shop's passes and running boosts (ShopService publishes their
--                        summed total as LuckBoost / CoinBoost / ExpBoost) + the upgrade
--   Damage               a Strength potion + the Attack upgrade, then the admin test
--                        multiplier (DamageMultiplier) on top, a test tool, not a bonus
--   Speed                a Swiftness potion + the worn armour's speed (their sum capped at
--                        Armor.MAX_SPEED) + the Sprint upgrade's share while sprinting
--   Max health           the Health upgrade (the only multiplier on it)
-- Damage TAKEN still multiplies (armour, Stoneskin, the Defense upgrade): added, their
-- reductions would reach 98% at the top. Attack speed is the upgrade alone (Upgrades.adjust).
-- A new gamepass or boost that raises a stat adds its share here (or, for luck / coins /
-- EXP, to Config/Shop, which ShopService already sums).
--
-- Weapon stats as shown everywhere except the Index (the user: the Index keeps the base
-- numbers): Bonuses.weapon(player, def) is the def after the Worldheart tier, the Attack
-- Speed upgrade and the damage bonuses; Bonuses.dps(player, def) its damage a second
-- (hits only, no crits).

local Config = script.Parent
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Potions = require(Config:WaitForChild("Potions"))
local Armor = require(Config:WaitForChild("Armor"))
local Infuse = require(Config:WaitForChild("Infuse"))

local Bonuses = {}

local function number(player: Player, name: string, fallback: number): number
	local v = player:GetAttribute(name)
	return if type(v) == "number" and v > 0 then v else fallback
end

-- The shop's summed passes and boosts for "Luck" / "Coins" / "Exp" (1 = none).
local SHOP_ATTR = { Luck = "LuckBoost", Coins = "CoinBoost", Exp = "ExpBoost" }
function Bonuses.shop(player: Player, stat: string): number
	local attr = SHOP_ATTR[stat]
	return if attr then number(player, attr, 1) else 1
end

-- Luck / Coins / EXP: 1 + the shop's share + the upgrade's share.
function Bonuses.total(player: Player, stat: string): number
	return 1 + (Bonuses.shop(player, stat) - 1) + (Upgrades.value(player, stat) - 1)
end
function Bonuses.luck(player: Player): number
	return Bonuses.total(player, "Luck")
end
function Bonuses.coins(player: Player): number
	return Bonuses.total(player, "Coins")
end
function Bonuses.exp(player: Player): number
	return Bonuses.total(player, "Exp")
end

-- The damage bonus without the admin test multiplier: 1 + Strength's share + the Attack
-- upgrade's share.
function Bonuses.damageBonus(player: Player): number
	return 1 + (Potions.multiplier(player, "Strength") - 1) + (Upgrades.value(player, "Attack") - 1)
end

-- Damage dealt: the bonus x the admin's own test multiplier (DamageMultiplier, x1 unset).
function Bonuses.damage(player: Player): number
	return Bonuses.damageBonus(player) * number(player, "DamageMultiplier", 1)
end

-- Max health: the Health upgrade.
function Bonuses.health(player: Player): number
	return Upgrades.value(player, "Health")
end

-- Walk / sprint speed as a multiple of StarterPlayer.CharacterWalkSpeed.
function Bonuses.speed(player: Player, sprinting: boolean): number
	local armour = player:GetAttribute("ArmorSpeed")
	local boost = math.min(
		(Potions.multiplier(player, "Swiftness") - 1) + (if type(armour) == "number" then armour else 0),
		Armor.MAX_SPEED
	)
	local sprint = if sprinting then math.max(0, Upgrades.value(player, "Sprint") - 1) else 0
	return 1 + boost + sprint
end

-- A weapon (or tool) def as this player swings it: its Worldheart tier (Infuse), the Attack
-- Speed upgrade and every damage bonus. `def` itself is never changed.
function Bonuses.weapon(player: Player, def: any): any
	if not def then
		return def
	end
	local swing = Upgrades.adjust(player, Infuse.adjust(player, def))
	local copy = table.clone(swing)
	copy.damage = (swing.damage or 0) * Bonuses.damage(player)
	return copy
end

-- Damage a second with every bonus (hits only; crits aren't counted).
function Bonuses.dps(player: Player, def: any): number
	local swing = Bonuses.weapon(player, def)
	if not swing then
		return 0
	end
	local cooldown = swing.cooldown or 1
	return if cooldown > 0 then (swing.damage or 0) / cooldown else (swing.damage or 0)
end

-- Every attribute a shown stat depends on, so a screen can refresh when one changes.
Bonuses.Watch = {
	"LuckBoost", "CoinBoost", "ExpBoost", "DamageMultiplier", "ArmorSpeed",
	"PotionTier_Strength", "PotionTier_Swiftness", "Potions",
	Upgrades.attr("Attack"), Upgrades.attr("AttackSpeed"), Upgrades.attr("Health"),
	Upgrades.attr("Luck"), Upgrades.attr("Coins"), Upgrades.attr("Exp"), Upgrades.attr("Sprint"),
	"InfusedCores",
}

return Bonuses
