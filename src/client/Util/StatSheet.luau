--!strict
-- StatSheet: every stat's shown total and the chips of what feeds it, for any player
-- (their published attributes; 2026-10-23). The Stats panel (StatsUI, chips and totals)
-- and the profile cards (ProfileUI, totals) both show these, so they always agree:
--   StatSheet.measure(who, id) -> total text, chip texts, whether it is above its base
--   StatSheet.ORDER            the 12 stat ids in sheet order (two columns: combat down
--                              the left, the rest down the right)
--   StatSheet.name(id)         a stat's shown name; StatSheet.Text every word
-- Every stat is a multiplier with its sources' shares added ("Passes & boosts +1.5×"
-- on ×2.50), except Crit Chance, Regen and Gathering, which are percentages, and Max
-- Health, which is the number (see StatsUI's header for each stat's sources).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Potions = require(Config:WaitForChild("Potions"))
local Leveling = require(Config:WaitForChild("Leveling"))
local Bonuses = require(Config:WaitForChild("Bonuses"))

local Format = require(script.Parent:WaitForChild("Format"))

local StatSheet = {}

-- Every word the stat rows show (the Stats panel, the profile).
local Text = {
	pill = "Level %s · all your stats",
	locked = "Locked",
	noBonus = "No bonus yet",
	level = "Level HP %s",
	armour = "Armor +%s",
	upgrade = "Upgrade %s",
	shop = "Passes & boosts %s",
	potion = "%s %s",
	armourDefense = "Armor %s",
	base = "Base 1% a second",
	critBase = "Base %s of hits",
	plus = "+%s", -- a share: "+1.5×", or for the percentage stats "+0.45%"
	armourRegen = "Armor +%s",
	armourSpeed = "Armor %s",
	doubleNote = "Chance to double drops",
	critDamageBase = "Base %s",
	adminX = "Admin %s",
	adminOverride = "Admin override",
	names = {
		Health = "Max Health", Luck = "Luck", Attack = "Damage", Coins = "Coins", Defense = "Defense",
		Exp = "EXP", AttackSpeed = "Attack Speed", Regen = "Regen", Sprint = "Sprint", Gathering = "Gathering",
		CritDamage = "Crit Damage", CritChance = "Crit Chance",
	},
}
-- two columns: combat down the left (Health, Damage, Crit Damage, Defense, Attack
-- Speed, Sprint), the rest down the right
StatSheet.ORDER = { "Health", "Luck", "Attack", "Coins", "CritDamage", "CritChance", "Defense", "Exp", "AttackSpeed", "Regen", "Sprint", "Gathering" }

local function number(who: Player, name: string, fallback: number): number
	local value = who:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local times = Upgrades.times

-- A bonus's share as a chip amount, always a multiplier (2026-10-23, the user: "the only
-- thing the stats should be displaying is the multiplier values"): x2.5 -> "+1.5×",
-- x1.15 -> "+0.15×". The shares add up to the total (×1 + +1.5× = ×2.50).
local function added(amount: number): string
	local text = ("%.2f"):format(amount):gsub("0+$", ""):gsub("%.$", "")
	return Text.plus:format(text .. "×")
end
local function share(multiplier: number): string
	return added(multiplier - 1)
end

local function upgradeX(who: Player, id: string): number
	local def = Upgrades.get(id)
	return if def then Upgrades.multiplier(def, Upgrades.level(who, id)) else 1
end

-- A potion's short name for a chip ("Strength II"), or nil while none runs.
local function potionName(who: Player, kind: string): string?
	local tier = Potions.running(who, kind)
	local def = tier and Potions.get(kind .. tier)
	return def and (def.short or def.name) or nil
end

-- One stat's total and its source chips.
function StatSheet.measure(who: Player, id: string): (string, { string }, boolean)
	local parts = {}
	local up = Upgrades.level(who, id) > 0
	if id == "Health" then
		local character = who.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local level = number(who, "Level", 1)
		table.insert(parts, Text.level:format(Format.commas(Leveling.maxHealth(level))))
		local armour = number(who, "ArmorHealth", 0)
		if armour > 0 then
			table.insert(parts, Text.armour:format(Format.commas(armour)))
		end
		if up then
			table.insert(parts, Text.upgrade:format(times(upgradeX(who, id))))
		end
		local override = number(who, "MaxHealthOverride", 0) > 0
		if override then
			table.insert(parts, Text.adminOverride)
		end
		local max = if humanoid then humanoid.MaxHealth else Leveling.maxHealth(level)
		return Format.commas(math.floor(max + 0.5)), parts, armour > 0 or up or override
	elseif id == "Luck" or id == "Coins" or id == "Exp" then
		local shop = Bonuses.shop(who, id)
		if shop ~= 1 then
			table.insert(parts, Text.shop:format(share(shop)))
		end
		if up then
			table.insert(parts, Text.upgrade:format(share(upgradeX(who, id))))
		end
		local total = Bonuses.total(who, id)
		return times(total), parts, total > 1.0001
	elseif id == "Attack" then
		local strength = Potions.multiplier(who, "Strength")
		local name = potionName(who, "Strength")
		if name then
			table.insert(parts, Text.potion:format(name, share(strength)))
		end
		if up then
			table.insert(parts, Text.upgrade:format(share(upgradeX(who, id))))
		end
		-- the admin's test multiplier works on top of the added bonuses
		local admin = number(who, "DamageMultiplier", 1)
		if admin ~= 1 then
			table.insert(parts, Text.adminX:format(times(admin)))
		end
		local total = Bonuses.damage(who)
		return times(total), parts, total > 1.0001
	elseif id == "Defense" then
		local armour = 1 - math.clamp(number(who, "ArmorDefense", 0), 0, 0.9)
		local skin = Potions.multiplier(who, "Stoneskin")
		if armour < 1 then
			table.insert(parts, Text.armourDefense:format(times(1 / armour)))
		end
		local name = potionName(who, "Stoneskin")
		if name then
			table.insert(parts, Text.potion:format(name, times(1 / skin)))
		end
		if up then
			table.insert(parts, Text.upgrade:format(times(upgradeX(who, id))))
		end
		local total = 1 / (armour * skin * Upgrades.value(who, "Defense"))
		return times(total), parts, total > 1.0001
	elseif id == "Sprint" then
		-- the worn armour's speed (Config/Armor) works on walking too, so it shows even
		-- before sprinting is unlocked
		local armour = number(who, "ArmorSpeed", 0)
		if not up then
			if armour > 0 then
				return Text.locked, { Text.armourSpeed:format(added(armour)) }, false
			end
			return Text.locked, { Text.noBonus }, false
		end
		table.insert(parts, Text.upgrade:format(share(upgradeX(who, id))))
		local swift = Potions.multiplier(who, "Swiftness")
		local name = potionName(who, "Swiftness")
		if name then
			table.insert(parts, Text.potion:format(name, share(swift)))
		end
		if armour > 0 then
			table.insert(parts, Text.armourSpeed:format(added(armour)))
		end
		return times(Bonuses.speed(who, true)), parts, true
	elseif id == "Regen" then
		-- percentages of max HP a second: Roblox's own 1%, the upgrade's share, a potion's
		table.insert(parts, Text.base)
		local upgrade = Upgrades.value(who, id)
		if up then
			table.insert(parts, Text.upgrade:format(Text.plus:format(Upgrades.percent(upgrade))))
		end
		local potion = Potions.power(who, "Regen")
		local name = potionName(who, "Regen")
		if name and potion > 0 then
			table.insert(parts, Text.potion:format(name, Text.plus:format(Upgrades.percent(potion))))
		end
		-- the worn armour's (Config/Armor)
		local armour = number(who, "ArmorRegen", 0)
		if armour > 0 then
			table.insert(parts, Text.armourRegen:format(Upgrades.percent(armour)))
		end
		local total = Upgrades.BASE_REGEN + upgrade + potion + armour
		return Upgrades.percent(total), parts, total > Upgrades.BASE_REGEN + 1e-6
	elseif id == "CritDamage" then
		local def = Upgrades.get(id)
		table.insert(parts, Text.critDamageBase:format(times(def and def.base or 1.5)))
		if up then
			table.insert(parts, Text.upgrade:format(added(Upgrades.value(who, id) - (def and def.base or 1.5))))
		end
		return times(Upgrades.value(who, id)), parts, up
	elseif id == "CritChance" then
		local def = Upgrades.get(id)
		local base = def and def.base or 0.1
		table.insert(parts, Text.critBase:format(Upgrades.percent(base)))
		local value = Upgrades.value(who, id)
		if up then
			table.insert(parts, Text.upgrade:format(Text.plus:format(Upgrades.percent(value - base))))
		end
		return Upgrades.percent(value), parts, up
	elseif id == "Gathering" then
		table.insert(parts, Text.doubleNote)
		local value = Upgrades.value(who, id)
		if up then
			table.insert(parts, Text.upgrade:format(Text.plus:format(Upgrades.percent(value))))
		end
		return Upgrades.percent(value), parts, up
	end
	-- Attack Speed: the upgrade alone
	if up then
		table.insert(parts, Text.upgrade:format(times(upgradeX(who, id))))
	end
	return times(upgradeX(who, id)), parts, up
end

function StatSheet.name(id: string): string
	return Text.names[id] or id
end

StatSheet.Text = Text

function StatSheet.init(_injected: any) end
function StatSheet.start() end

return StatSheet
