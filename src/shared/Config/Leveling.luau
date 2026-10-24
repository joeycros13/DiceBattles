--!strict
-- Leveling: the EXP curve, shared by ExpService (server) and the HUD's EXP bar.
--
-- A player has one number, their total EXP ("ExpTotal" attribute). Their
-- level and how far into it they are follow from it:
--   need(level)        EXP to go from `level` to `level + 1`
--   fromTotal(total)   level, EXP into that level, EXP that level needs
-- Players start at level 1 (the badge on the player card).
--   maxHealth(level)   the player's max HP at that level (ExpService applies it)
--   scaleAt(level)     the world a level is in, as the old split scale (below)
--
-- The curve (2026-10-24, the user: every world about x10 the one before, enemy damage keeping
-- pace with enemy health, and a gate every 25 levels): max HP and the EXP a level needs both
-- grow by GROWTH a level, x10 every 25 levels, so each world's levels give x10 the health of
-- the last world's with no jump at the gate. Max HP is 100 at level 1, 912 at 25, 1,000 at 26,
-- 10,000 at 51; each level up adds a little more than the one before (+10, +10, +12, +13...).
-- A level needs 40 EXP at level 1 and x10 every 25 levels (3,366 in all to level 25), tuned
-- with art/tools/balance/world_sim.py so a typical player buys the World 2 gate in about 30
-- minutes. It replaced 30 + 15 a level with health 100 + 10 a level, both x4 / x16 from each
-- gate's level (the "world scale" of 2026-10-23), which jumped at the gate (330 -> 1,360 HP).
--
-- The old world scale is still how Worlds 2 and 3's configs were sized (until they're re-tuned
-- on this curve, the rescale of 2026-10-24):
--   SCALE[world]       x1, x4, x16, x64... : enemy damage, armour health, kill and quest EXP
--   2 x SCALE[world]   x2, x8, x32...      : weapon damage, enemy health, tool power, node health,
--                      the Worldheart tiers

local Gates = require(script.Parent.Gates)

local Leveling = {}

Leveling.SCALE = { 1, 4, 16, 64, 256, 1024, 4096, 16384 }

-- The scale of the world a level belongs to: a level at or past a gate's level is in that gate's
-- world, whether or not the gate is bought yet (it can't be bought before).
function Leveling.scaleAt(level: number): number
	local world = 1
	for _, gate in Gates.list do
		if level >= gate.level and gate.world > world then
			world = gate.world
		end
	end
	return Leveling.SCALE[math.min(world, #Leveling.SCALE)]
end

Leveling.START = 1
-- x10 every LEVELS_PER_WORLD levels (one world's gate to the next)
Leveling.LEVELS_PER_WORLD = 25
Leveling.GROWTH = 10 ^ (1 / Leveling.LEVELS_PER_WORLD)
Leveling.FIRST = 40 -- EXP to go from level 1 to 2
Leveling.BASE_HEALTH = 100 -- max HP at level 1

-- x GROWTH for every level past the first
local function grown(base: number, level: number): number
	return math.floor(base * Leveling.GROWTH ^ (math.max(level, Leveling.START) - Leveling.START) + 0.5)
end

function Leveling.need(level: number): number
	return grown(Leveling.FIRST, level)
end

function Leveling.maxHealth(level: number): number
	return grown(Leveling.BASE_HEALTH, level)
end

function Leveling.fromTotal(total: number): (number, number, number)
	local level = Leveling.START
	local left = math.max(0, total)
	while left >= Leveling.need(level) do
		left -= Leveling.need(level)
		level += 1
	end
	return level, left, Leveling.need(level)
end

return Leveling
