--!strict
-- Balance: tunable constants for combat, dice, progression, and economy.
-- Every number here is a PLACEHOLDER meant to be tuned later; systems read
-- from this module so balancing never requires touching logic code.

local Balance = {}

-- === Dice (R-C8, R-C11) ===
Balance.Dice = {
	faces = 6, -- die values are 1..faces
	startingDice = 1, -- dice at chapter entry before upgrades
	maxDice = 5, -- hard cap across all sources
	baseRerolls = 3, -- rerolls granted at the start of each turn
}

-- Hand multipliers (R-C12). Names map to DiceHands detection results.
Balance.HandMultipliers = {
	highCard = 1.0,
	onePair = 1.5,
	twoPair = 2.0,
	threeOfAKind = 2.5,
	straight = 3.0,
	fullHouse = 4.0,
	fourOfAKind = 5.0,
	fiveOfAKind = 8.0,
}

-- === Player base stats (R-C14..R-C18) ===
Balance.Player = {
	baseHp = 100,
	baseAttackFlat = 0, -- flat added to dice total before multipliers
	baseCritChance = 0.05, -- 0..1
	baseCritMultiplier = 2.0, -- crit deals x2 (R-C14)
	baseDodgeChance = 0.0, -- 0..1 (R-C16)
	baseDamageReduction = 0.0, -- 0..1 (R-C15)
	baseHealAmount = 0,
	baseLifesteal = 0.0, -- 0..1 of damage dealt
	-- Safety clamps so stacking never breaks resolution.
	maxCritChance = 1.0,
	maxDodgeChance = 0.9,
	maxDamageReduction = 0.9,
}

-- === Gear (magnitude of a Common-rarity piece per stat, before rarity/slot scaling) ===
Balance.GearBaseStat = {
	hp = 20,
	attack = 5,
	critChance = 0.03,
	dodgeChance = 0.03,
	damageReduction = 0.02,
	healAmount = 8,
}

-- === Slot leveling (R-E8) ===
Balance.SlotLevels = {
	maxLevel = 20,
	-- Buff multiplier applied to equipped gear = 1 + (level-1) * bonusPerLevel.
	bonusPerLevel = 0.10,
	-- Material cost to go from level L to L+1 = baseCost + (L-1) * costPerLevel.
	baseCost = 5,
	costPerLevel = 5,
}

-- === Per-chapter (transient) leveling & dice unlock (R-C21) ===
Balance.PerChapter = {
	xpPerEnemyKill = 10,
	xpPerBossKill = 40,
	-- XP needed to reach level L+1 = baseXp + (L-1) * xpPerLevel.
	baseXp = 20,
	xpPerLevel = 15,
	-- Each per-chapter level-up unlocks one more die (up to Balance.Dice.maxDice).
	diceUnlockPerLevel = 1,
}

-- === Global (persistent) account leveling (R-C22) ===
Balance.Global = {
	xpPerChapterComplete = 100,
	baseXp = 100,
	xpPerLevel = 50,
	-- Rewards granted per global level-up.
	statPointsPerLevel = 1,
	talentRollsPerLevel = 1,
	-- Starting-dice upgrade every N global levels (permanent, still capped at 5).
	startingDiceEveryLevels = 5,
}

-- === Enemy / boss scaling ===
Balance.Enemy = {
	-- Boss stages multiply the base archetype stats (R-C2).
	bossHpMultiplier = 4.0,
	bossAttackMultiplier = 2.0,
	-- Per-chapter difficulty ramp applied to enemy stats (chapterIndex based).
	hpPerChapter = 0.25, -- +25% hp per chapter beyond the first
	attackPerChapter = 0.15,
}

-- === Economy (R-Y*) ===
Balance.Economy = {
	talentRollCost = 50, -- coins per talent roll (R-T2)
	chestKeyCost = 1, -- keys per chest roll (R-Y2)
}

-- === Rewards (R-C5, R-Y4) granted on chapter completion. Placeholder values;
-- scaled by chapter id so later chapters pay out more. Global XP is granted
-- separately via Balance.Global.xpPerChapterComplete. ===
Balance.Rewards = {
	chapterBaseCoins = 100, -- coins for completing chapter 1
	chapterCoinsPerChapter = 50, -- extra coins per chapter beyond the first
	chapterKeys = 1, -- chest keys per chapter completion
}

return Balance
