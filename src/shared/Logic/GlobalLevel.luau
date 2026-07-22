--!strict
-- GlobalLevel: pure, deterministic account-XP math (R-C22). No `game` state
-- beyond Config, so it is unit-testable and reusable on both client (progress
-- bar previews) and server (authoritative level-ups). The XP curve mirrors the
-- per-chapter curve shape: xp needed for the next level grows linearly.

local Config = script.Parent.Parent.Config
local Balance = require(Config.Balance)

local GlobalLevel = {}

-- XP required to advance FROM `level` TO `level + 1`.
-- = baseXp + (level - 1) * xpPerLevel, with level floored at 1.
function GlobalLevel.xpToNext(level: number): number
	local g = Balance.Global
	local lvl = math.max(1, math.floor(level))
	return g.baseXp + (lvl - 1) * g.xpPerLevel
end

-- Apply `addedXp` to a (level, xp) pair, cascading through as many level-ups as
-- the total supports. Returns (newLevel, leftoverXp, levelsGained). Negative
-- inputs are clamped to 0 so this can never regress a profile.
function GlobalLevel.applyXp(level: number, xp: number, addedXp: number): (number, number, number)
	local newLevel = math.max(1, math.floor(level))
	local newXp = math.max(0, xp) + math.max(0, addedXp)
	local gained = 0
	while newXp >= GlobalLevel.xpToNext(newLevel) do
		newXp -= GlobalLevel.xpToNext(newLevel)
		newLevel += 1
		gained += 1
	end
	return newLevel, newXp, gained
end

-- Fraction (0..1) of progress toward the next level, for UI progress bars.
function GlobalLevel.progress(level: number, xp: number): number
	local need = GlobalLevel.xpToNext(level)
	if need <= 0 then
		return 0
	end
	return math.clamp(math.max(0, xp) / need, 0, 1)
end

return GlobalLevel
