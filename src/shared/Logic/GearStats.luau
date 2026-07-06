--!strict
-- GearStats: pure computation of a gear piece's effective stat magnitude given
-- its rarity and the level of the slot it occupies (R-E3, R-E6, R-E7, R-E8).
-- No `game` state beyond Config, so it is deterministic and reusable on both the
-- equipment UI (display) and the server/combat resolution (later steps).
--
-- Magnitude = base * rarityMultiplier * slotLevelMultiplier where:
--   base                 = gear.baseStat override, else Balance.GearBaseStat[stat]
--   rarityMultiplier     = Rarities.Defs[rarity].multiplier
--   slotLevelMultiplier  = 1 + (slotLevel - 1) * Balance.SlotLevels.bonusPerLevel

local Config = script.Parent.Parent.Config
local Gear = require(Config.Gear)
local Slots = require(Config.Slots)
local Rarities = require(Config.Rarities)
local Balance = require(Config.Balance)

local GearStats = {}

export type StatType = Slots.StatType

export type GearStat = {
	stat: StatType,
	value: number, -- effective magnitude (fractional for percent stats)
	isPercent: boolean,
}

-- Stats stored as fractions (0..1) that read as percentages in the UI.
local PERCENT_STATS: { [string]: boolean } = {
	critChance = true,
	dodgeChance = true,
	damageReduction = true,
}

-- True if the stat is expressed as a fraction that should render as a percent.
function GearStats.isPercent(stat: string): boolean
	return PERCENT_STATS[stat] == true
end

-- Common-rarity base magnitude for a gear id: its own override or the slot's
-- default from Balance. Returns 0 for unknown gear.
function GearStats.baseMagnitude(gearId: string): number
	local gearDef = Gear.get(gearId)
	if not gearDef then
		return 0
	end
	if gearDef.baseStat ~= nil then
		return gearDef.baseStat
	end
	local slotDef = Slots.get(gearDef.slot)
	if not slotDef then
		return 0
	end
	return (Balance.GearBaseStat :: { [string]: number })[slotDef.stat] or 0
end

-- Buff multiplier contributed by a slot's level (level 1 = x1.0).
function GearStats.slotMultiplier(slotLevel: number): number
	local level = math.max(1, slotLevel)
	return 1 + (level - 1) * Balance.SlotLevels.bonusPerLevel
end

-- Effective stat a gear piece provides at a given rarity and slot level.
-- Returns nil if the gear id (and thus its slot/stat) cannot be resolved.
function GearStats.compute(gearId: string, rarity: string, slotLevel: number): GearStat?
	local gearDef = Gear.get(gearId)
	if not gearDef then
		return nil
	end
	local slotDef = Slots.get(gearDef.slot)
	if not slotDef then
		return nil
	end

	local rarityDef = Rarities.get(rarity)
	local rarityMult = rarityDef and rarityDef.multiplier or 1

	local base = GearStats.baseMagnitude(gearId)
	local value = base * rarityMult * GearStats.slotMultiplier(slotLevel)

	return {
		stat = slotDef.stat,
		value = value,
		isPercent = GearStats.isPercent(slotDef.stat),
	}
end

-- Human-readable stat name for UI labels (e.g. "critChance" -> "Crit Chance").
local STAT_LABELS: { [string]: string } = {
	hp = "Health",
	attack = "Attack",
	critChance = "Crit Chance",
	dodgeChance = "Dodge Chance",
	damageReduction = "Damage Reduction",
	healAmount = "Heal Amount",
}

function GearStats.statLabel(stat: string): string
	return STAT_LABELS[stat] or stat
end

-- Format an effective magnitude for display: percent stats as "+12.5%", flat
-- stats as "+30" (rounded). Always prefixed with "+" since gear only buffs.
function GearStats.format(gearStat: GearStat): string
	if gearStat.isPercent then
		local pct = gearStat.value * 100
		local rounded = math.floor(pct * 10 + 0.5) / 10
		return ("+%s%%"):format(tostring(rounded))
	end
	return ("+%d"):format(math.floor(gearStat.value + 0.5))
end

return GearStats
