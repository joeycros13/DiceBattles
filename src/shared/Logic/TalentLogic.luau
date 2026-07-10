--!strict
-- TalentLogic: pure, deterministic talent helpers reusable on both client and
-- server (R-T2..R-T4). No `game` state beyond Config, so the weighted roll can be
-- validated server-side and previewed client-side, and it is unit-testable.
--
-- A roll picks ONE talent weighted by its rarity's weight (rarer = less likely),
-- skipping any talent already at its maxLevel (e.g. extraDice caps at level 4).
-- Effect value scales linearly as perLevel * level.

local Config = script.Parent.Parent.Config
local Talents = require(Config.Talents)
local Rarities = require(Config.Rarities)

local TalentLogic = {}

export type TalentEffect = Talents.TalentEffect

-- An entry in the weighted roll pool.
export type PoolEntry = { id: string, weight: number }

-- Injected RNG returns a float in [0, 1). Defaults to math.random when omitted,
-- so tests can pass a deterministic stub (matching DamageFormula's convention).
type Rng = () -> number

-- True if `talentId` is at (or above) its cap and thus cannot be rolled further.
function TalentLogic.isMaxed(talentId: string, level: number): boolean
	local def = Talents.get(talentId)
	if not def then
		return true
	end
	return def.maxLevel ~= nil and level >= (def.maxLevel :: number)
end

-- Build the weighted roll pool from a talents map ({ [talentId]: level }).
-- Excludes maxed talents. Weight is the talent's rarity weight (higher = more
-- common). Iterates in Talents.Order for a stable, deterministic pool.
function TalentLogic.buildPool(talents: { [string]: number }): ({ PoolEntry }, number)
	local pool: { PoolEntry } = {}
	local total = 0
	for _, id in Talents.Order do
		local def = Talents.get(id)
		if def then
			local level = talents[id] or 0
			if not TalentLogic.isMaxed(id, level) then
				local rarityDef = Rarities.get(def.rarity)
				local weight = rarityDef and rarityDef.weight or 1
				if weight > 0 then
					table.insert(pool, { id = id, weight = weight })
					total += weight
				end
			end
		end
	end
	return pool, total
end

-- Pick one talent id from the pool, weighted by rarity (rarer = less likely).
-- Returns nil only when nothing is rollable (all talents maxed). `rng` returns
-- a float in [0, 1); defaults to math.random for production use.
function TalentLogic.pick(talents: { [string]: number }, rng: Rng?): string?
	local roll = rng or math.random
	local pool, total = TalentLogic.buildPool(talents)
	if total <= 0 then
		return nil
	end

	local target = roll() * total
	local cumulative = 0
	for _, entry in pool do
		cumulative += entry.weight
		if target < cumulative then
			return entry.id
		end
	end
	-- Floating-point safety: fall back to the last eligible entry.
	return pool[#pool].id
end

-- The effect magnitude a talent provides at a given level (perLevel * level).
-- Returns 0 for unknown talents.
function TalentLogic.effectValue(talentId: string, level: number): number
	local def = Talents.get(talentId)
	if not def then
		return 0
	end
	return def.perLevel * math.max(0, level)
end

-- ==================== display helpers ====================

-- Per-effect display metadata: a human label and whether it reads as a percent.
local EFFECT_META: { [string]: { label: string, percent: boolean } } = {
	flatAttack = { label = "Attack", percent = false },
	pctAttack = { label = "Attack", percent = true },
	critChance = { label = "Crit Chance", percent = true },
	extraReroll = { label = "Rerolls", percent = false },
	extraDice = { label = "Dice", percent = false },
	hp = { label = "HP", percent = false },
	lifesteal = { label = "Lifesteal", percent = true },
}

-- Human-readable label for an effect category (e.g. "pctAttack" -> "Attack").
function TalentLogic.effectLabel(effect: string): string
	local meta = EFFECT_META[effect]
	return meta and meta.label or effect
end

-- True if the effect is a fraction (0..1) that should render as a percentage.
function TalentLogic.isPercent(effect: string): boolean
	local meta = EFFECT_META[effect]
	return meta ~= nil and meta.percent
end

-- Format a talent's bonus at a level as a signed string, e.g. "+6 Attack",
-- "+15% Attack", "+2% Crit Chance", "+1 Die". Returns "-" for unknown talents.
function TalentLogic.formatBonus(talentId: string, level: number): string
	local def = Talents.get(talentId)
	if not def then
		return "-"
	end
	local value = TalentLogic.effectValue(talentId, level)
	local label = TalentLogic.effectLabel(def.effect)
	if TalentLogic.isPercent(def.effect) then
		local pct = value * 100
		local rounded = math.floor(pct * 10 + 0.5) / 10
		return ("+%s%% %s"):format(tostring(rounded), label)
	end
	return ("+%d %s"):format(math.floor(value + 0.5), label)
end

return TalentLogic
