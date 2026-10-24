--!strict
-- Balance: tunable constants for world enemies, sprinting, weapon combat and
-- the coin / EXP spills.
-- Every number here is a PLACEHOLDER meant to be tuned later; systems read
-- from this module so balancing never requires touching logic code.

local Balance = {}

-- === World enemies (spawned at each world's EnemySpawn / BossSpawn markers) ===
-- Stats come from the archetype in the owning world's config file; this section
-- tunes their presence in the world. Values here apply to every world, so
-- anything that should differ per world belongs in Config/Worlds/<world>.luau.
Balance.WorldEnemy = {
	wanderRadius = 5, -- studs from its spawn point the enemy may drift within (marker can override)
	-- delay before a defeated enemy returns at full HP, for a world whose config has
	-- no `respawn` table (each world's tiers set it; a marker can override)
	respawnSeconds = 20,
	bossWanderRadius = 4, -- bosses pace a small circle on their platform (marker can override)
	bossRespawnSeconds = 60,
}

-- === Sprinting ===
-- There's no base sprint any more (2026-10-19, the user's call): the Sprint
-- upgrade unlocks it and sets its speed (Config/Upgrades, SprintController).

-- === Real-time weapon combat (MeleeService) ===
-- Per-weapon numbers live in Config/Weapons, per-enemy ones in each enemy's
-- `melee` block; this is what applies to every fight.
Balance.Melee = {
	leashRange = 35, -- an enemy gives up once it, or its target, is this far from its spawn point
	returnSpeedScale = 1.5, -- walking home is this much faster than chasing
	stopFraction = 0.75, -- a chasing enemy stops this fraction of its attack range past its front
	dodgeSlack = 1.5, -- extra studs beyond range at which a landing attack still connects
	separation = 3, -- chasing enemies keep at least this far apart
	-- Server-side tolerance for hit claims, in studs: covers the per-client wander
	-- and network delay between where the client drew an enemy and where the
	-- server has it.
	hitSlack = 4,
	-- Critical hits (2026-10-21, the user): every weapon hit has this chance to deal
	-- critMultiplier times its damage, shown as a gold "CRIT!" bubble (BonkPop.hit).
	critChance = 0.10,
	critMultiplier = 1.5,
	tickRate = 20, -- AI updates per second
	-- For playtesting: weapons every player owns from the start, Studio only; the
	-- first one starts selected in the hotbar. Empty since 2026-10-11 (the user
	-- took the Corn Cob off); the admin panel's Give is the usual way now.
	testStartWeapons = {},
}

-- Coins dropped by defeated enemies (CoinService). Each enemy's own range is
-- its `coins` entry in Config/Worlds; these are the visual spill only.
Balance.Coins = {
	piecesMin = 3, -- coins that fling out of the enemy...
	piecesMax = 5, -- ...whatever the amount actually is
}

-- EXP from defeated enemies (ExpService): each enemy's `exp` is in Config/Worlds,
-- the level curve in Config/Leveling; these are the blue stars that spill out.
Balance.Exp = {
	piecesMin = 3,
	piecesMax = 5,
}

return Balance
