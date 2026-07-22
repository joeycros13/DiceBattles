--!strict
-- PlayerStats: pure aggregation of a player's effective combat stats from base
-- Balance values + equipped gear (via GearStats) + talents (via TalentLogic).
-- No `game` state beyond Config, so it is deterministic and unit-testable, and
-- is reused by CombatService (authoritative) and can back UI previews later.
--
-- Percent stats (crit/dodge/DR) and lifesteal are summed as fractions. Dice
-- unlock helpers derive the starting dice count for a run (R-C8, R-C21, R-C22).

local Config = script.Parent.Parent.Config
local Balance = require(Config.Balance)
local Slots = require(Config.Slots)
local GearStats = require(script.Parent.GearStats)
local TalentLogic = require(script.Parent.TalentLogic)
local Talents = require(Config.Talents)

local PlayerStats = {}

-- Effective, aggregated combat stats for a player entering combat.
export type Stats = {
	maxHp: number,
	flatAttack: number, -- flat added to the dice total before the % bonus
	pctAttack: number, -- fractional attack bonus (e.g. 0.25 = +25%)
	critChance: number,
	critMultiplier: number,
	dodgeChance: number,
	damageReduction: number,
	healAmount: number,
	lifesteal: number,
	extraRerolls: number, -- rerolls beyond Balance.Dice.baseRerolls
	extraDice: number, -- dice pre-unlocked from the extraDice talent
}

-- Minimal shape PlayerStats needs from a profile; PlayerData satisfies it.
export type StatSource = {
	gear: { [string]: { id: string, rarity: string } },
	equipped: { [string]: string? },
	slotLevels: { [string]: number },
	talents: { [string]: number },
	startingDiceUpgrade: number?,
	globalStatBonus: { [string]: number }?,
}

-- Fresh stats table seeded with the player's base values from Balance.
local function baseStats(): Stats
	local p = Balance.Player
	return {
		maxHp = p.baseHp,
		flatAttack = p.baseAttackFlat,
		pctAttack = 0,
		critChance = p.baseCritChance,
		critMultiplier = p.baseCritMultiplier,
		dodgeChance = p.baseDodgeChance,
		damageReduction = p.baseDamageReduction,
		healAmount = p.baseHealAmount,
		lifesteal = p.baseLifesteal,
		extraRerolls = 0,
		extraDice = 0,
	}
end

-- Add an equipped gear stat to the matching aggregate field.
local function applyGearStat(stats: Stats, stat: string, value: number)
	if stat == "hp" then
		stats.maxHp += value
	elseif stat == "attack" then
		stats.flatAttack += value
	elseif stat == "critChance" then
		stats.critChance += value
	elseif stat == "dodgeChance" then
		stats.dodgeChance += value
	elseif stat == "damageReduction" then
		stats.damageReduction += value
	elseif stat == "healAmount" then
		stats.healAmount += value
	end
end

-- Add a talent's effect (at its current level) to the matching aggregate field.
local function applyTalent(stats: Stats, effect: string, value: number)
	if effect == "flatAttack" then
		stats.flatAttack += value
	elseif effect == "pctAttack" then
		stats.pctAttack += value
	elseif effect == "critChance" then
		stats.critChance += value
	elseif effect == "hp" then
		stats.maxHp += value
	elseif effect == "lifesteal" then
		stats.lifesteal += value
	elseif effect == "extraReroll" then
		stats.extraRerolls += value
	elseif effect == "extraDice" then
		stats.extraDice += value
	end
end

-- Aggregate every source into a single Stats table.
function PlayerStats.compute(source: StatSource): Stats
	local stats = baseStats()

	-- Equipped gear: each slot's gear contributes its slot-scaled stat magnitude.
	for _, slotId in Slots.Order do
		local uid = source.equipped[slotId]
		if uid then
			local inst = source.gear[uid]
			if inst then
				local slotLevel = source.slotLevels[slotId] or 1
				local gearStat = GearStats.compute(inst.id, inst.rarity, slotLevel)
				if gearStat then
					applyGearStat(stats, gearStat.stat, gearStat.value)
				end
			end
		end
	end

	-- Talents: every defined talent at its current (possibly 0) level.
	for _, talentId in Talents.Order do
		local def = Talents.get(talentId)
		if def then
			local level = source.talents[talentId] or 0
			if level > 0 then
				applyTalent(stats, def.effect, TalentLogic.effectValue(talentId, level))
			end
		end
	end

	-- Global level-up bonuses (R-C22): keys map directly onto Stats fields, so a
	-- new gain category needs only a Balance/config entry and no logic change.
	if source.globalStatBonus then
		for statName, value in source.globalStatBonus do
			if type(value) == "number" and (stats :: any)[statName] ~= nil then
				(stats :: any)[statName] += value
			end
		end
	end

	return stats
end

-- Dice pre-unlocked at chapter entry: base + permanent starting-dice upgrade +
-- the extraDice talent, clamped to [1, maxDice] (ARCHITECTURE 6, R-C8/C22).
function PlayerStats.startingDice(source: StatSource, stats: Stats?): number
	local resolved = stats or PlayerStats.compute(source)
	local total = Balance.Dice.startingDice + (source.startingDiceUpgrade or 0) + resolved.extraDice
	return math.clamp(math.floor(total), 1, Balance.Dice.maxDice)
end

return PlayerStats
