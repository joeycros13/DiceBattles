--!strict
-- Chapters: chapter -> stage -> enemy composition + boss flag (R-C1, R-C2).
-- First build: 3 chapters x 5 stages each; the last stage of every chapter is a
-- boss. Each non-boss stage defines an enemyPool and a min/max count; the server
-- (CombatService) randomly spawns 1-3 enemies drawn from the pool. Boss stages
-- spawn exactly one enemy from the pool, scaled by Balance.Enemy multipliers.

export type StageDef = {
	boss: boolean,
	enemyPool: { string }, -- Enemies.Defs keys
	minEnemies: number,
	maxEnemies: number,
}

export type ChapterDef = {
	id: number,
	name: string,
	stages: { StageDef }, -- length 5; stages[5].boss == true
}

local Chapters = {}

Chapters.Order = { 1, 2, 3 }

Chapters.Defs = {
	[1] = {
		id = 1,
		name = "The Green Meadows",
		stages = {
			{ boss = false, enemyPool = { "Slime" }, minEnemies = 1, maxEnemies = 2 },
			{ boss = false, enemyPool = { "Slime", "Goblin" }, minEnemies = 1, maxEnemies = 3 },
			{ boss = false, enemyPool = { "Goblin", "Archer" }, minEnemies = 2, maxEnemies = 3 },
			{ boss = false, enemyPool = { "Goblin", "Archer", "Golem" }, minEnemies = 2, maxEnemies = 3 },
			{ boss = true, enemyPool = { "BossOgre" }, minEnemies = 1, maxEnemies = 1 },
		},
	},
	[2] = {
		id = 2,
		name = "The Frozen Caverns",
		stages = {
			{ boss = false, enemyPool = { "Goblin", "Archer" }, minEnemies = 1, maxEnemies = 3 },
			{ boss = false, enemyPool = { "Archer", "Golem" }, minEnemies = 2, maxEnemies = 3 },
			{ boss = false, enemyPool = { "Golem" }, minEnemies = 1, maxEnemies = 2 },
			{ boss = false, enemyPool = { "Archer", "Golem" }, minEnemies = 2, maxEnemies = 3 },
			{ boss = true, enemyPool = { "BossLich" }, minEnemies = 1, maxEnemies = 1 },
		},
	},
	[3] = {
		id = 3,
		name = "The Molten Peak",
		stages = {
			{ boss = false, enemyPool = { "Archer", "Golem" }, minEnemies = 2, maxEnemies = 3 },
			{ boss = false, enemyPool = { "Golem" }, minEnemies = 2, maxEnemies = 3 },
			{ boss = false, enemyPool = { "Goblin", "Archer", "Golem" }, minEnemies = 3, maxEnemies = 3 },
			{ boss = false, enemyPool = { "Golem" }, minEnemies = 3, maxEnemies = 3 },
			{ boss = true, enemyPool = { "BossDragon" }, minEnemies = 1, maxEnemies = 1 },
		},
	},
} :: { [number]: ChapterDef }

function Chapters.get(id: number): ChapterDef?
	return Chapters.Defs[id]
end

-- Total number of chapters defined.
function Chapters.count(): number
	return #Chapters.Order
end

return Chapters
