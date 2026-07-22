--!strict
-- CombatSim: self-contained server test harness for the combat state machine
-- (Shared/Logic/CombatEngine + PlayerStats). It drives the PURE engine directly
-- with an injected RNG (no Player, remotes, or DataService needed), so a full
-- chapter can be simulated deterministically.
--
-- Runs automatically on server start (mapped to ServerScriptService.CombatSim in
-- default.project.json). Prints a PASS/FAIL summary and errors at the end on any
-- failure, matching tests/LogicTests conventions.
--
-- Covers: PlayerStats aggregation; a full 5-stage chapter win (enemies die,
-- stages advance, per-chapter dice unlock, boss on stage 5, terminal "Won");
-- HP carryover across stages (no per-stage refill); player death -> "Lost"; and
-- the pick-3 trait offer + selection at the dice cap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Logic = Shared:WaitForChild("Logic")
local Balance = require(Config:WaitForChild("Balance"))
local Chapters = require(Config:WaitForChild("Chapters"))
local CombatEngine = require(Logic:WaitForChild("CombatEngine"))
local PlayerStats = require(Logic:WaitForChild("PlayerStats"))

-- ==================== tiny assertion framework ====================

local passed = 0
local failed = 0
local failures: { string } = {}

local function record(ok: boolean, name: string, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		local msg = if detail then (name .. " -- " .. detail) else name
		table.insert(failures, msg)
		warn("[CombatSim] FAIL: " .. msg)
	end
end

local function expectEqual(actual: any, expected: any, name: string)
	record(actual == expected, name, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local EPS = 1e-6
local function expectApprox(actual: number, expected: number, name: string)
	record(math.abs(actual - expected) <= EPS, name, ("expected ~%s, got %s"):format(tostring(expected), tostring(actual)))
end

-- ==================== helpers ====================

-- A fully-defaulted PlayerStats.Stats, overridable per test.
local function makeStats(overrides: { [string]: number }?): PlayerStats.Stats
	local p = Balance.Player
	local stats: PlayerStats.Stats = {
		maxHp = p.baseHp,
		flatAttack = p.baseAttackFlat,
		pctAttack = 0,
		critChance = p.baseCritChance,
		critMultiplier = p.baseCritMultiplier,
		dodgeChance = p.baseDodgeChance,
		damageReduction = p.baseDamageReduction,
		healAmount = p.baseHealAmount,
		lifesteal = p.baseLifesteal,
		extraRerolls = 0,
		extraDice = 0,
	}
	if overrides then
		for k, v in overrides do
			(stats :: { [string]: number })[k] = v
		end
	end
	return stats
end

-- Drive a battle until it reaches a terminal phase (or the iteration cap). When
-- a TraitPick is hit, `pickTrait(offer)` chooses (defaults to the first offer).
local function runToEnd(
	battle: CombatEngine.Battle,
	maxIters: number,
	pickTrait: ((offer: { string }) -> string)?
): number
	local iters = 0
	while battle.state.phase == "PlayerTurn" or battle.state.phase == "TraitPick" do
		iters += 1
		if iters > maxIters then
			break
		end
		if battle.state.phase == "TraitPick" then
			local offer = battle.ctx.traitOffer or {}
			local choice = if pickTrait then pickTrait(offer) else offer[1]
			CombatEngine.chooseTrait(battle, choice)
		else
			CombatEngine.attack(battle, 1)
		end
	end
	return iters
end

-- ==================== PlayerStats aggregation ====================

do
	-- A profile with one gear piece and a couple of talents.
	local source = {
		gear = {
			g1 = { id = "WoodSword", rarity = "Common" }, -- Weapon -> attack
		},
		equipped = { Weapon = "g1" },
		slotLevels = { Weapon = 1 },
		talents = { Sharpen = 3, Vitality = 2, Multiroll = 1 }, -- +6 atk, +20 hp, +1 die
		startingDiceUpgrade = 0,
	}
	local stats = PlayerStats.compute(source)

	-- maxHp = baseHp + Vitality(10*2) = 100 + 20.
	expectApprox(stats.maxHp, Balance.Player.baseHp + 20, "PlayerStats maxHp includes Vitality")
	-- flatAttack = base(0) + WoodSword Common attack(GearBaseStat.attack=5) + Sharpen(2*3=6).
	expectApprox(stats.flatAttack, Balance.Player.baseAttackFlat + 5 + 6, "PlayerStats flatAttack gear+talent")
	-- extraDice from Multiroll level 1.
	expectApprox(stats.extraDice, 1, "PlayerStats extraDice from Multiroll")

	-- startingDice = clamp(base(1) + upgrade(0) + extraDice(1)) = 2.
	expectEqual(PlayerStats.startingDice(source, stats), 2, "PlayerStats startingDice base+extraDice")

	-- A big permanent upgrade clamps at the hard cap of 5.
	local capped = { gear = {}, equipped = {}, slotLevels = {}, talents = {}, startingDiceUpgrade = 10 }
	expectEqual(PlayerStats.startingDice(capped), Balance.Dice.maxDice, "PlayerStats startingDice clamps to maxDice")
end

-- ==================== full chapter win + boss + stage advance + unlock ====================

do
	-- Overwhelming attack so every enemy is one-shot; huge HP so the run never
	-- ends in death. Real (seeded) RNG exercises spawn variety + enemy actions.
	local stats = makeStats({ maxHp = 1e6, flatAttack = 1e6 })
	local seeded = Random.new(20240722)
	local battle = CombatEngine.newBattle({
		chapterId = 1,
		stats = stats,
		startingDice = 1,
		rng = function()
			return seeded:NextNumber()
		end,
	})

	expectEqual(battle.state.chapterId, 1, "win: chapter id")
	expectEqual(battle.state.stageIndex, 1, "win: starts at stage 1")
	expectEqual(battle.state.unlockedDice, 1, "win: starts with 1 die")

	local bossArchetype: string? = nil
	local bossIsBoss = false
	local sawStages: { [number]: boolean } = {}

	-- Custom loop so we can inspect the boss stage before it is cleared.
	local iters = 0
	while battle.state.phase == "PlayerTurn" or battle.state.phase == "TraitPick" do
		iters += 1
		if iters > 3000 then
			break
		end
		sawStages[battle.state.stageIndex] = true
		if battle.state.stageIndex == 5 and #battle.state.enemies > 0 and bossArchetype == nil then
			local e = battle.state.enemies[1]
			bossArchetype = e.archetype
			local rt = battle.ctx.enemyRuntime[e.uid]
			bossIsBoss = rt ~= nil and rt.isBoss
		end
		if battle.state.phase == "TraitPick" then
			CombatEngine.chooseTrait(battle, (battle.ctx.traitOffer or {})[1])
		else
			CombatEngine.attack(battle, 1)
		end
	end

	expectEqual(battle.state.phase, "Won", "win: reaches terminal Won")
	expectEqual(battle.state.stageIndex, 5, "win: cleared through the final stage")
	record(sawStages[1] and sawStages[2] and sawStages[3] and sawStages[4] and sawStages[5] == true,
		"win: advanced through all 5 stages")
	expectEqual(bossArchetype, "BossOgre", "win: stage 5 spawns the chapter-1 boss")
	expectEqual(bossIsBoss, true, "win: stage-5 enemy is flagged boss")
	-- Kills grant per-chapter XP which unlocks additional dice (R-C21).
	record(battle.state.unlockedDice > 1, "win: per-chapter leveling unlocked more dice",
		("unlockedDice=%d"):format(battle.state.unlockedDice))
	record(battle.state.perChapter.level > 1, "win: per-chapter level rose from kills",
		("level=%d"):format(battle.state.perChapter.level))
end

-- ==================== HP carryover across stages (no per-stage refill) ====================

do
	-- Constant near-1 RNG: dice always roll 6, enemies always pick "nothing"
	-- (so the player takes no damage), and one-shot attacks clear every stage.
	local stats = makeStats({ maxHp = 500, flatAttack = 1e6 })
	local const = function()
		return 0.999999
	end
	local battle = CombatEngine.newBattle({
		chapterId = 1,
		stats = stats,
		startingDice = 1,
		rng = const,
	})

	-- Wound the player below max right after entry; carryover must preserve it.
	local sentinel = stats.maxHp - 137
	battle.state.player.hp = sentinel

	local reachedStage2 = false
	local iters = 0
	while battle.state.phase == "PlayerTurn" or battle.state.phase == "TraitPick" do
		iters += 1
		if iters > 3000 then
			break
		end
		if battle.state.stageIndex >= 2 then
			reachedStage2 = true
			-- HP must not have been refilled when the stage advanced.
			expectApprox(battle.state.player.hp, sentinel, "carryover: HP preserved into later stage")
		end
		if battle.state.phase == "TraitPick" then
			-- Choose a non-lifesteal, non-heal trait so HP stays exactly at sentinel.
			CombatEngine.chooseTrait(battle, "IronSkin")
		else
			CombatEngine.attack(battle, 1)
		end
	end

	record(reachedStage2, "carryover: simulation advanced past stage 1")
	expectEqual(battle.state.phase, "Won", "carryover: run completed as Won")
	expectApprox(battle.state.player.hp, sentinel, "carryover: final HP equals wounded value (never refilled)")
end

-- ==================== player death -> Lost ====================

do
	-- Frail player, no offense: constant-0 RNG makes enemies always attack.
	local stats = makeStats({ maxHp = 10, flatAttack = 0, critChance = 0 })
	local const0 = function()
		return 0.0
	end
	local battle = CombatEngine.newBattle({
		chapterId = 1,
		stats = stats,
		startingDice = 1,
		rng = const0,
	})

	local iters = runToEnd(battle, 3000)
	expectEqual(battle.state.phase, "Lost", "death: frail player is defeated")
	record(iters < 3000, "death: run terminated (did not hit iteration cap)")
	record(battle.state.player.hp <= 0, "death: player HP reached 0",
		("hp=%s"):format(tostring(battle.state.player.hp)))
end

-- ==================== pick-3 trait offer at the dice cap ====================

do
	local stats = makeStats({ maxHp = 1e6, flatAttack = 1e6 })
	local seeded = Random.new(7)
	local battle = CombatEngine.newBattle({
		chapterId = 1,
		stats = stats,
		startingDice = Balance.Dice.maxDice, -- start already at the cap
		rng = function()
			return seeded:NextNumber()
		end,
	})

	-- Because the run starts at the dice cap, the first turn is a TraitPick.
	expectEqual(battle.state.phase, "TraitPick", "trait: cap start triggers TraitPick")
	local offer = battle.ctx.traitOffer or {}
	expectEqual(#offer, 3, "trait: exactly 3 traits offered")

	local chosen = offer[2]
	local ok = CombatEngine.chooseTrait(battle, chosen)
	expectEqual(ok, true, "trait: choosing an offered trait succeeds")
	expectEqual(battle.state.phase, "PlayerTurn", "trait: pick transitions to PlayerTurn")
	expectEqual(battle.ctx.traitOffered, true, "trait: offer marked consumed")
	record(battle.state.activeTraits[1] == chosen, "trait: chosen trait is active this battle",
		("active=%s chosen=%s"):format(tostring(battle.state.activeTraits[1]), tostring(chosen)))

	-- The offer fires only once: reaching the cap again does not re-offer.
	CombatEngine.beginNextTurn(battle)
	expectEqual(battle.state.phase, "PlayerTurn", "trait: no second offer after first pick")
end

-- ==================== chapter-completion reward math (R-C5, R-Y4) ====================

do
	-- Mirrors CombatService.grantChapterRewards coin formula for chapter 1.
	local coinsCh1 = Balance.Rewards.chapterBaseCoins + (1 - 1) * Balance.Rewards.chapterCoinsPerChapter
	expectApprox(coinsCh1, Balance.Rewards.chapterBaseCoins, "rewards: chapter 1 coins == base")
	local coinsCh3 = Balance.Rewards.chapterBaseCoins + (3 - 1) * Balance.Rewards.chapterCoinsPerChapter
	expectApprox(coinsCh3, Balance.Rewards.chapterBaseCoins + 2 * Balance.Rewards.chapterCoinsPerChapter,
		"rewards: later chapters pay more")
	record(Chapters.count() == 3, "rewards: 3 chapters defined")
end

-- ==================== summary ====================

local total = passed + failed
if failed == 0 then
	print(("[CombatSim] ALL PASSED (%d/%d)"):format(passed, total))
else
	print(("[CombatSim] %d/%d passed, %d FAILED:"):format(passed, total, failed))
	for _, msg in failures do
		print("  - " .. msg)
	end
	error(("[CombatSim] %d assertion(s) failed"):format(failed), 0)
end
