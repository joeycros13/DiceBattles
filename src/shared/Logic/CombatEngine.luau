--!strict
-- CombatEngine: the pure, deterministic combat state machine (ARCHITECTURE 6,
-- R-C1..R-C23). It owns chapter/stage/turn flow, enemy spawning, dice, damage,
-- enemy actions, per-chapter XP/dice unlock, HP carryover, stage advance, chapter
-- completion, and the pick-3 trait offer at 5 dice. It has NO dependency on
-- `game`, Players, remotes, or DataService: all randomness is injected and all
-- state lives in the passed-in Battle table. This keeps combat unit-simulatable
-- (see tests/CombatSim) while CombatService stays a thin authoritative wrapper
-- (validation + persistence + replication).

local Config = script.Parent.Parent.Config
local Types = require(script.Parent.Parent.Types)
local Balance = require(Config.Balance)
local Chapters = require(Config.Chapters)
local Enemies = require(Config.Enemies)
local Traits = require(Config.Traits)
local DiceHands = require(script.Parent.DiceHands)
local DamageFormula = require(script.Parent.DamageFormula)
local PlayerStats = require(script.Parent.PlayerStats)

local CombatEngine = {}

type Rng = () -> number

-- Per-enemy behaviour kept server-side only (not replicated); parallels the
-- replicated CombatEnemy by uid.
export type EnemyRuntime = {
	attack: number,
	heal: number,
	shield: number,
	actions: Enemies.ActionWeights,
	isBoss: boolean,
}

-- Transient combat context that never leaves the server (RNG, enemy behaviour,
-- uid allocation, trait-offer bookkeeping).
export type Context = {
	stats: PlayerStats.Stats,
	enemyRuntime: { [string]: EnemyRuntime },
	rng: Rng,
	uidCounter: number,
	traitOffered: boolean,
	traitOffer: { string }?,
}

-- A live battle = the replicated state plus its private context.
export type Battle = {
	state: Types.CombatState,
	ctx: Context,
}

export type EnemyActionLog = {
	uid: string,
	action: string,
	amount: number,
	dodged: boolean?,
}

-- Summary of one player attack (and any enemy counter-turn) for feedback + tests.
export type AttackResult = {
	hand: string,
	multiplier: number,
	diceTotal: number,
	damage: number,
	crit: boolean,
	targetUid: string,
	killed: boolean,
	xpGained: number,
	stageCleared: boolean,
	enemyActions: { EnemyActionLog },
	outcome: string, -- resulting phase after the turn resolved
}

-- ==================== small helpers ====================

local function rollDie(rng: Rng): number
	return math.floor(rng() * Balance.Dice.faces) + 1
end

local function newUid(ctx: Context): string
	ctx.uidCounter += 1
	return "e" .. tostring(ctx.uidCounter)
end

-- Base player stats layered with any active per-battle traits (R-C23).
local function effectiveStats(battle: Battle): PlayerStats.Stats
	local eff = table.clone(battle.ctx.stats)
	for _, traitId in battle.state.activeTraits do
		local def = Traits.get(traitId)
		if def then
			local e = def.effect
			local v = def.value
			if e == "flatAttack" then
				eff.flatAttack += v
			elseif e == "pctAttack" then
				eff.pctAttack += v
			elseif e == "critChance" then
				eff.critChance += v
			elseif e == "critMultiplier" then
				eff.critMultiplier += v
			elseif e == "extraReroll" then
				eff.extraRerolls += v
			elseif e == "lifesteal" then
				eff.lifesteal += v
			elseif e == "damageReduction" then
				eff.damageReduction += v
			elseif e == "healAmount" then
				eff.healAmount += v
			end
		end
	end
	return eff
end

-- Weighted enemy action pick (R-C7). Injected rng keeps it deterministic.
local function pickAction(weights: Enemies.ActionWeights, rng: Rng): string
	local total = weights.attack + weights.heal + weights.shield + weights.nothing
	if total <= 0 then
		return "nothing"
	end
	local target = rng() * total
	local cumulative = weights.attack
	if target < cumulative then
		return "attack"
	end
	cumulative += weights.heal
	if target < cumulative then
		return "heal"
	end
	cumulative += weights.shield
	if target < cumulative then
		return "shield"
	end
	return "nothing"
end

-- ==================== spawning ====================

-- Populate state.enemies (and ctx.enemyRuntime) for the current stage (R-C2).
-- Boss stages spawn exactly one boss-scaled enemy; normal stages spawn a random
-- 1..3 drawn from the pool. Per-chapter difficulty ramp scales hp/attack.
local function spawnStage(battle: Battle)
	local state = battle.state
	local ctx = battle.ctx
	local chapter = Chapters.get(state.chapterId)
	assert(chapter, ("CombatEngine: unknown chapter %s"):format(tostring(state.chapterId)))
	local stage = chapter.stages[state.stageIndex]
	assert(stage, ("CombatEngine: chapter %d has no stage %d"):format(state.chapterId, state.stageIndex))

	state.enemies = {}
	ctx.enemyRuntime = {}

	local count: number
	if stage.boss then
		count = 1
	else
		local span = stage.maxEnemies - stage.minEnemies
		count = stage.minEnemies + math.floor(ctx.rng() * (span + 1))
		count = math.clamp(count, 1, 3) -- enemy count is 1..3 (R-C2)
	end

	local hpRamp = 1 + Balance.Enemy.hpPerChapter * (state.chapterId - 1)
	local atkRamp = 1 + Balance.Enemy.attackPerChapter * (state.chapterId - 1)

	for _ = 1, count do
		local poolIndex = math.floor(ctx.rng() * #stage.enemyPool) + 1
		local archetypeId = stage.enemyPool[poolIndex]
		local def = Enemies.get(archetypeId)
		if def then
			local hp = def.hp * hpRamp
			local attack = def.attack * atkRamp
			if stage.boss then
				hp *= Balance.Enemy.bossHpMultiplier
				attack *= Balance.Enemy.bossAttackMultiplier
			end
			local maxHp = math.floor(hp + 0.5)
			local uid = newUid(ctx)
			table.insert(state.enemies, {
				uid = uid,
				archetype = def.id,
				hp = maxHp,
				maxHp = maxHp,
				shield = 0,
			})
			ctx.enemyRuntime[uid] = {
				attack = attack,
				heal = def.heal,
				shield = def.shield,
				actions = def.actions,
				isBoss = stage.boss,
			}
		end
	end
end

-- ==================== dice ====================

local function rollAllDice(battle: Battle)
	local dice: { Types.Die } = {}
	for i = 1, battle.state.unlockedDice do
		dice[i] = { value = rollDie(battle.ctx.rng), locked = false }
	end
	battle.state.dice = dice
end

-- Grow the dice array to match unlockedDice after a mid-battle unlock, without
-- disturbing existing dice (they re-randomize at the next turn start anyway).
local function syncDiceCount(battle: Battle)
	local dice = battle.state.dice
	while #dice < battle.state.unlockedDice do
		table.insert(dice, { value = rollDie(battle.ctx.rng), locked = false })
	end
end

-- Rerolls granted at the start of a turn: base + talent/trait extras (R-C11).
local function turnRerolls(battle: Battle): number
	local eff = effectiveStats(battle)
	return math.max(0, math.floor(Balance.Dice.baseRerolls + eff.extraRerolls))
end

-- ==================== trait offer (R-C23) ====================

-- Pick 3 distinct traits from the pool using the injected rng.
local function makeTraitOffer(ctx: Context): { string }
	local pool = table.clone(Traits.Order)
	local offer: { string } = {}
	local n = math.min(3, #pool)
	for _ = 1, n do
		local idx = math.floor(ctx.rng() * #pool) + 1
		table.insert(offer, pool[idx])
		table.remove(pool, idx)
	end
	return offer
end

-- Start the next player turn. The first time the run reaches the dice cap it
-- enters TraitPick (offering 3 traits) instead of PlayerTurn; otherwise it
-- re-randomizes all dice, clears locks, and resets rerolls (R-C9, R-C10).
function CombatEngine.beginNextTurn(battle: Battle)
	local state = battle.state
	local ctx = battle.ctx
	if not ctx.traitOffered and state.unlockedDice >= Balance.Dice.maxDice then
		ctx.traitOffer = makeTraitOffer(ctx)
		state.phase = "TraitPick"
		return
	end
	state.phase = "PlayerTurn"
	state.rerollsLeft = turnRerolls(battle)
	rollAllDice(battle)
end

-- ==================== per-chapter XP & dice unlock (R-C21) ====================

local function xpToNext(level: number): number
	return Balance.PerChapter.baseXp + (level - 1) * Balance.PerChapter.xpPerLevel
end

-- Grant XP for a kill and process any resulting level-ups (each unlocks a die up
-- to the cap). Returns the XP granted.
local function grantKillXp(battle: Battle, isBoss: boolean): number
	local state = battle.state
	local gained = if isBoss then Balance.PerChapter.xpPerBossKill else Balance.PerChapter.xpPerEnemyKill
	local pc = state.perChapter
	pc.xp += gained
	while pc.xp >= xpToNext(pc.level) do
		pc.xp -= xpToNext(pc.level)
		pc.level += 1
		if state.unlockedDice < Balance.Dice.maxDice then
			state.unlockedDice = math.min(Balance.Dice.maxDice, state.unlockedDice + Balance.PerChapter.diceUnlockPerLevel)
			syncDiceCount(battle)
		end
	end
	return gained
end

-- ==================== enemy turn ====================

-- Each living enemy takes exactly one weighted action (R-C6, R-C7). Incoming
-- attacks resolve dodge -> DR -> shield -> HP (R-C15/C16). Sets phase to "Lost"
-- and stops early if the player dies.
local function enemyTurn(battle: Battle, result: AttackResult)
	local state = battle.state
	local ctx = battle.ctx
	local eff = effectiveStats(battle)

	for _, enemy in state.enemies do
		if enemy.hp > 0 then
			local rt = ctx.enemyRuntime[enemy.uid]
			if rt then
				local action = pickAction(rt.actions, ctx.rng)
				local entry: EnemyActionLog = { uid = enemy.uid, action = action, amount = 0 }
				if action == "attack" then
					local dodged = DamageFormula.rollDodge(eff.dodgeChance, ctx.rng)
					local res = DamageFormula.resolveIncomingDamage({
						incoming = rt.attack,
						damageReduction = eff.damageReduction,
						dodged = dodged,
						shield = state.player.shield,
						hp = state.player.hp,
					})
					state.player.shield = res.shield
					state.player.hp = res.hp
					entry.amount = res.hpLost + res.shieldAbsorbed
					entry.dodged = res.dodged
					table.insert(result.enemyActions, entry)
					if state.player.hp <= 0 then
						state.phase = "Lost"
						return
					end
				elseif action == "heal" then
					local before = enemy.hp
					enemy.hp = math.min(enemy.maxHp, enemy.hp + rt.heal)
					entry.amount = enemy.hp - before
					table.insert(result.enemyActions, entry)
				elseif action == "shield" then
					enemy.shield += rt.shield
					entry.amount = rt.shield
					table.insert(result.enemyActions, entry)
				else
					table.insert(result.enemyActions, entry)
				end
			end
		end
	end
end

-- ==================== public: create + player actions ====================

export type NewBattleParams = {
	chapterId: number,
	stats: PlayerStats.Stats,
	startingDice: number,
	rng: Rng?,
}

-- Create a fresh battle for a chapter: full HP, stage 1 spawned, first turn begun
-- (which may be a TraitPick if the run already starts at the dice cap).
function CombatEngine.newBattle(params: NewBattleParams): Battle
	local rng = params.rng or math.random
	local unlocked = math.clamp(math.floor(params.startingDice), 1, Balance.Dice.maxDice)
	local maxHp = math.floor(params.stats.maxHp + 0.5)

	local state: Types.CombatState = {
		chapterId = params.chapterId,
		stageIndex = 1,
		phase = "PlayerTurn",
		enemies = {},
		player = { hp = maxHp, maxHp = maxHp, shield = 0 },
		perChapter = { level = 1, xp = 0 },
		dice = {},
		unlockedDice = unlocked,
		rerollsLeft = Balance.Dice.baseRerolls,
		activeTraits = {},
	}
	local ctx: Context = {
		stats = params.stats,
		enemyRuntime = {},
		rng = rng,
		uidCounter = 0,
		traitOffered = false,
		traitOffer = nil,
	}
	local battle: Battle = { state = state, ctx = ctx }

	spawnStage(battle)
	CombatEngine.beginNextTurn(battle)
	return battle
end

-- Toggle a die's lock (R-C10). Only valid on the player's turn.
function CombatEngine.toggleLock(battle: Battle, index: number): boolean
	local state = battle.state
	if state.phase ~= "PlayerTurn" then
		return false
	end
	local die = state.dice[index]
	if not die then
		return false
	end
	die.locked = not die.locked
	return true
end

-- Reroll only the unlocked dice, consuming one reroll (R-C11).
function CombatEngine.reroll(battle: Battle): boolean
	local state = battle.state
	if state.phase ~= "PlayerTurn" then
		return false
	end
	if state.rerollsLeft <= 0 then
		return false
	end
	for _, die in state.dice do
		if not die.locked then
			die.value = rollDie(battle.ctx.rng)
		end
	end
	state.rerollsLeft -= 1
	return true
end

-- Choose one of the offered traits (R-C23), apply it for the battle, and begin
-- the (now trait-unlocked) player turn.
function CombatEngine.chooseTrait(battle: Battle, traitId: string): boolean
	local state = battle.state
	local ctx = battle.ctx
	if state.phase ~= "TraitPick" then
		return false
	end
	local offer = ctx.traitOffer
	if not offer then
		return false
	end
	local valid = false
	for _, id in offer do
		if id == traitId then
			valid = true
			break
		end
	end
	if not valid then
		return false
	end

	table.insert(state.activeTraits, traitId)
	ctx.traitOffered = true
	ctx.traitOffer = nil
	CombatEngine.beginNextTurn(battle)
	return true
end

-- Resolve a player attack on the enemy at `targetIndex`, then (unless the stage
-- was cleared) resolve the enemy turn and begin the next player turn. Returns a
-- summary, or nil if the action was illegal (wrong phase / dead-or-missing
-- target). Terminal outcomes set state.phase to "Won" or "Lost".
function CombatEngine.attack(battle: Battle, targetIndex: number): AttackResult?
	local state = battle.state
	local ctx = battle.ctx
	if state.phase ~= "PlayerTurn" then
		return nil
	end
	local enemy = state.enemies[targetIndex]
	if not enemy or enemy.hp <= 0 then
		return nil
	end

	local eff = effectiveStats(battle)

	local diceTotal = 0
	local values: { number } = {}
	for _, die in state.dice do
		table.insert(values, die.value)
		diceTotal += die.value
	end
	local hand = DiceHands.evaluate(values)
	local crit = DamageFormula.rollCrit(eff.critChance, ctx.rng)
	local dmg = DamageFormula.computePlayerDamage({
		diceTotal = diceTotal,
		flatBonus = eff.flatAttack,
		pctBonus = eff.pctAttack,
		handMultiplier = hand.multiplier,
		crit = crit,
		critMultiplier = eff.critMultiplier,
		lifesteal = eff.lifesteal,
	})

	-- Apply to the selected enemy: shield first, overflow to HP (mirrors R-C15).
	local dealt = dmg.damage
	local shieldAbsorbed = math.min(enemy.shield, dealt)
	enemy.shield -= shieldAbsorbed
	local overflow = dealt - shieldAbsorbed
	enemy.hp = math.max(0, enemy.hp - overflow)

	-- Lifesteal heals the player from the final damage (R-C14 talent/trait).
	if dmg.lifestealHeal > 0 then
		state.player.hp = math.min(state.player.maxHp, state.player.hp + dmg.lifestealHeal)
	end

	local result: AttackResult = {
		hand = hand.hand,
		multiplier = hand.multiplier,
		diceTotal = diceTotal,
		damage = dealt,
		crit = crit,
		targetUid = enemy.uid,
		killed = false,
		xpGained = 0,
		stageCleared = false,
		enemyActions = {},
		outcome = state.phase,
	}

	if enemy.hp <= 0 then
		local rt = ctx.enemyRuntime[enemy.uid]
		result.killed = true
		result.xpGained = grantKillXp(battle, rt ~= nil and rt.isBoss or false)
		for i, e in state.enemies do
			if e.uid == enemy.uid then
				table.remove(state.enemies, i)
				break
			end
		end
		ctx.enemyRuntime[enemy.uid] = nil
	end

	-- Stage cleared? (R-C4/C5) The killing blow ends the stage before enemies act.
	if #state.enemies == 0 then
		local chapter = Chapters.get(state.chapterId)
		local finalStage = chapter and state.stageIndex >= #chapter.stages
		if finalStage then
			state.phase = "Won"
			result.outcome = "Won"
			return result
		end
		state.stageIndex += 1
		spawnStage(battle) -- HP carries over: player.hp is untouched (R-C19)
		CombatEngine.beginNextTurn(battle)
		result.stageCleared = true
		result.outcome = state.phase
		return result
	end

	-- Otherwise every living enemy takes its turn (R-C6).
	enemyTurn(battle, result)
	if state.phase == "Lost" then
		result.outcome = "Lost"
		return result
	end

	CombatEngine.beginNextTurn(battle)
	result.outcome = state.phase
	return result
end

-- Current best hand for the dice on the table (UI/feedback helper).
function CombatEngine.currentHand(battle: Battle): DiceHands.HandResult
	local values: { number } = {}
	for _, die in battle.state.dice do
		table.insert(values, die.value)
	end
	return DiceHands.evaluate(values)
end

return CombatEngine
