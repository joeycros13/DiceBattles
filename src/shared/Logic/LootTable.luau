--!strict
-- LootTable: generic, pure weighted-roll helper (ARCHITECTURE.md 2/9, R-Y2/Y3).
-- No `game` state, so it is deterministic and unit-testable, and reusable by any
-- weighted selection (chest loot, gear rarity, etc.). Callers supply the entry
-- list and an optional RNG; the same `weight` convention as Rarities/TalentLogic
-- (higher weight = more likely) is used throughout.

local LootTable = {}

-- Injected RNG returns a float in [0, 1). Defaults to math.random when omitted,
-- so tests can pass a deterministic stub (matching DamageFormula/TalentLogic).
type Rng = () -> number

-- Entries are any tables carrying a numeric `weight` field. Extra fields (kind,
-- amount ranges, currency id, ...) are ignored here and interpreted by the
-- caller. Typed loosely (`any`) so callers can pass their own richer records
-- without strict-mode subtyping friction.

-- Sum of positive weights across the pool.
local function totalWeight(entries: { any }): number
	local total = 0
	for _, entry in entries do
		local w = entry.weight or 0
		if w > 0 then
			total += w
		end
	end
	return total
end

-- Pick ONE entry, weighted by `weight` (higher = more likely). Returns the same
-- entry reference, or nil when the pool has no positive-weight entries. `rng`
-- returns a float in [0, 1); defaults to math.random for production use.
function LootTable.roll(entries: { any }, rng: Rng?): any?
	local roll = rng or math.random
	local total = totalWeight(entries)
	if total <= 0 then
		return nil
	end

	local target = roll() * total
	local cumulative = 0
	for _, entry in entries do
		local w = entry.weight or 0
		if w > 0 then
			cumulative += w
			if target < cumulative then
				return entry
			end
		end
	end

	-- Floating-point safety: fall back to the last positive-weight entry.
	for i = #entries, 1, -1 do
		if (entries[i].weight or 0) > 0 then
			return entries[i]
		end
	end
	return nil
end

-- Roll `count` independent times, returning the chosen entries in order. A
-- non-positive count (or an empty pool) yields an empty result table.
function LootTable.rollMany(entries: { any }, count: number, rng: Rng?): { any }
	local results: { any } = {}
	for _ = 1, math.max(0, math.floor(count)) do
		local entry = LootTable.roll(entries, rng)
		if entry then
			table.insert(results, entry)
		end
	end
	return results
end

-- Inclusive random integer in [min, max]. Order-agnostic (swaps if min > max).
-- `rng` returns a float in [0, 1); defaults to math.random.
function LootTable.randomInt(min: number, max: number, rng: Rng?): number
	local roll = rng or math.random
	local lo, hi = min, max
	if hi < lo then
		lo, hi = hi, lo
	end
	return math.floor(lo) + math.floor(roll() * (math.floor(hi) - math.floor(lo) + 1))
end

return LootTable
