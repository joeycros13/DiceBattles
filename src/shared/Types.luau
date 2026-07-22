--!strict
-- Types: shared Luau type aliases used across client, server, and shared logic.
-- This module exports types only; it returns an empty table at runtime.

-- Persisted player profile (see ARCHITECTURE.md 5.1).
export type GlobalData = {
	level: number,
	xp: number,
}

export type Currencies = {
	coins: number,
	gems: number,
	materials: number,
	keys: number,
}

export type GearInstance = {
	id: string,
	rarity: string,
}

export type Progress = {
	currentChapter: number,
	chaptersCompleted: number,
}

export type PlayerData = {
	version: number,
	global: GlobalData,
	currencies: Currencies,
	startingDiceUpgrade: number,
	gear: { [string]: GearInstance },
	equipped: { [string]: string? },
	slotLevels: { [string]: number },
	talents: { [string]: number },
	progress: Progress,
	stats: { [string]: number },
	-- Permanent combat-stat bonuses accumulated from global level-ups (R-C22).
	-- Keys match PlayerStats.Stats field names (e.g. maxHp, flatAttack).
	globalStatBonus: { [string]: number },
}

-- Transient per-player combat state (see ARCHITECTURE.md 5.2).
export type CombatPhase = "PlayerTurn" | "EnemyTurn" | "TraitPick" | "Won" | "Lost"

export type Die = {
	value: number,
	locked: boolean,
}

export type CombatEnemy = {
	uid: string,
	archetype: string,
	hp: number,
	maxHp: number,
	shield: number,
}

export type CombatPlayer = {
	hp: number,
	maxHp: number,
	shield: number,
}

export type CombatState = {
	chapterId: number,
	stageIndex: number,
	phase: CombatPhase,
	enemies: { CombatEnemy },
	player: CombatPlayer,
	perChapter: { level: number, xp: number },
	dice: { Die },
	unlockedDice: number,
	rerollsLeft: number,
	activeTraits: { string },
}

return {}
