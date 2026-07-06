--!strict
-- LogicTests: self-contained server test harness for the pure combat-logic
-- modules (Shared/Logic/DiceHands and Shared/Logic/DamageFormula).
--
-- Runs automatically on server start (mapped to ServerScriptService.LogicTests
-- in default.project.json). It prints a PASS/FAIL summary and errors at the end
-- if anything fails, so failures are impossible to miss in the output.
--
-- Covers: every dice hand for 1..5 dice, hand-ranking tie-breaks, the exact
-- player-damage ordering (flat -> % -> hand -> crit) including crit, lifesteal,
-- deterministic crit/dodge rolls, and incoming-damage resolution
-- (dodge -> % reduction -> shield -> HP with overflow).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = Shared:WaitForChild("Logic")
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local DiceHands = require(Logic:WaitForChild("DiceHands"))
local DamageFormula = require(Logic:WaitForChild("DamageFormula"))

local M = Balance.HandMultipliers
local EPS = 1e-9

-- ==================== tiny assertion framework ====================

local passed = 0
local failed = 0
local failures: { string } = {}

local function record(ok: boolean, name: string, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		local msg = detail and (name .. " -- " .. detail) or name
		table.insert(failures, msg)
		warn("[LogicTests] FAIL: " .. msg)
	end
end

local function approx(a: number, b: number): boolean
	return math.abs(a - b) <= EPS
end

local function expectEqual(actual: any, expected: any, name: string)
	record(actual == expected, name, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function expectApprox(actual: number, expected: number, name: string)
	record(approx(actual, expected), name, ("expected ~%s, got %s"):format(tostring(expected), tostring(actual)))
end

-- ==================== DiceHands: every hand ====================

local function expectHand(dice: { number }, hand: string, mult: number)
	local res = DiceHands.evaluate(dice)
	local label = ("hand{%s}"):format(table.concat(dice, ","))
	expectEqual(res.hand, hand, label .. " name")
	expectApprox(res.multiplier, mult, label .. " multiplier")
end

-- 1 die: only high card is possible.
expectHand({ 5 }, "highCard", M.highCard)

-- 2 dice: high card, one pair.
expectHand({ 2, 5 }, "highCard", M.highCard)
expectHand({ 3, 3 }, "onePair", M.onePair)

-- 3 dice: high card, one pair, three of a kind (no two pair / straight yet).
expectHand({ 1, 2, 4 }, "highCard", M.highCard)
expectHand({ 2, 2, 5 }, "onePair", M.onePair)
expectHand({ 4, 4, 4 }, "threeOfAKind", M.threeOfAKind)
expectHand({ 1, 2, 3 }, "highCard", M.highCard) -- straight needs 5 dice

-- 4 dice: adds two pair and four of a kind; full house/straight still need 5.
expectHand({ 1, 2, 3, 5 }, "highCard", M.highCard)
expectHand({ 1, 2, 3, 4 }, "highCard", M.highCard) -- 4-in-a-row is NOT a straight
expectHand({ 5, 5, 2, 6 }, "onePair", M.onePair)
expectHand({ 2, 2, 5, 5 }, "twoPair", M.twoPair)
expectHand({ 3, 3, 3, 6 }, "threeOfAKind", M.threeOfAKind)
expectHand({ 6, 6, 6, 6 }, "fourOfAKind", M.fourOfAKind)

-- 5 dice: all hands available.
expectHand({ 1, 3, 4, 5, 2 }, "straight", M.straight) -- 1-5
expectHand({ 2, 3, 4, 5, 6 }, "straight", M.straight) -- 2-6
expectHand({ 1, 2, 3, 4, 6 }, "highCard", M.highCard) -- distinct but not consecutive
expectHand({ 5, 5, 1, 2, 3 }, "onePair", M.onePair)
expectHand({ 2, 2, 4, 4, 6 }, "twoPair", M.twoPair)
expectHand({ 3, 3, 3, 5, 6 }, "threeOfAKind", M.threeOfAKind)
expectHand({ 5, 5, 5, 2, 2 }, "fullHouse", M.fullHouse)
expectHand({ 6, 6, 6, 6, 1 }, "fourOfAKind", M.fourOfAKind)
expectHand({ 4, 4, 4, 4, 4 }, "fiveOfAKind", M.fiveOfAKind)

-- Ranking tie-breaks (best hand wins).
expectHand({ 6, 6, 6, 6, 6 }, "fiveOfAKind", M.fiveOfAKind) -- five > four
expectHand({ 2, 2, 2, 3, 3 }, "fullHouse", M.fullHouse) -- full house > three of a kind
-- four of a kind (5.0) must beat full house (4.0): 4-of-a-kind + 1 spare.
expectHand({ 1, 1, 1, 1, 5 }, "fourOfAKind", M.fourOfAKind)

-- multiplierFor helper + unknown fallback.
expectApprox(DiceHands.multiplierFor("fiveOfAKind"), M.fiveOfAKind, "multiplierFor five")
expectApprox(DiceHands.multiplierFor("nonsense"), M.highCard, "multiplierFor unknown -> highCard")

-- ==================== DamageFormula: player damage ordering ====================

-- No bonuses, high card: damage == dice total.
do
	local r = DamageFormula.computePlayerDamage({ diceTotal = 7, handMultiplier = M.highCard })
	expectApprox(r.damage, 7, "player no-bonus damage")
	expectEqual(r.crit, false, "player no-bonus crit flag")
end

-- Flat applied BEFORE %, not after: (10 + 10) * (1 + 1.0) = 40, not 10 + 10*2 = 30.
do
	local r = DamageFormula.computePlayerDamage({
		diceTotal = 10,
		flatBonus = 10,
		pctBonus = 1.0,
		handMultiplier = M.highCard,
	})
	expectApprox(r.adjusted, 40, "player flat-before-pct adjusted")
	expectApprox(r.damage, 40, "player flat-before-pct damage")
end

-- Hand multiplier applied after flat/%: (10 + 5) * 1.5 * 2(onePair) = 45.
do
	local r = DamageFormula.computePlayerDamage({
		diceTotal = 10,
		flatBonus = 5,
		pctBonus = 0.5,
		handMultiplier = M.twoPair, -- 2.0
	})
	expectApprox(r.adjusted, 22.5, "player adjusted before hand")
	expectApprox(r.beforeCrit, 45, "player beforeCrit (after hand)")
	expectApprox(r.damage, 45, "player non-crit final")
end

-- Crit applied LAST, after the hand multiplier: same as above but *2.
do
	local r = DamageFormula.computePlayerDamage({
		diceTotal = 10,
		flatBonus = 5,
		pctBonus = 0.5,
		handMultiplier = M.twoPair,
		crit = true,
		critMultiplier = 2.0,
	})
	expectApprox(r.beforeCrit, 45, "player crit beforeCrit unchanged")
	expectApprox(r.damage, 90, "player crit final (x2 after hand)")
	expectEqual(r.crit, true, "player crit flag true")
end

-- Crit multiplier is configurable and multiplies the post-hand value.
do
	local r = DamageFormula.computePlayerDamage({
		diceTotal = 4,
		handMultiplier = M.fiveOfAKind, -- 8.0
		crit = true,
		critMultiplier = 3.0,
	})
	expectApprox(r.beforeCrit, 32, "player big-hand beforeCrit (4*8)")
	expectApprox(r.damage, 96, "player big-hand crit (x3)")
end

-- Lifesteal is a fraction of the FINAL (post-crit) damage.
do
	local r = DamageFormula.computePlayerDamage({
		diceTotal = 20,
		handMultiplier = M.highCard,
		crit = true,
		critMultiplier = 2.0,
		lifesteal = 0.25,
	})
	expectApprox(r.damage, 40, "player lifesteal final damage")
	expectApprox(r.lifestealHeal, 10, "player lifesteal heal (25% of final)")
end

-- Default crit multiplier falls back to Balance.
do
	local r = DamageFormula.computePlayerDamage({
		diceTotal = 10,
		handMultiplier = M.highCard,
		crit = true,
	})
	expectApprox(r.damage, 10 * Balance.Player.baseCritMultiplier, "player default crit multiplier")
end

-- ==================== DamageFormula: deterministic crit/dodge rolls ====================

-- roll < chance => hit; injected rng makes this deterministic.
record(DamageFormula.rollCrit(0.5, function() return 0.0 end) == true, "rollCrit 0.0 < 0.5 => true")
record(DamageFormula.rollCrit(0.5, function() return 0.9 end) == false, "rollCrit 0.9 !< 0.5 => false")
record(DamageFormula.rollCrit(0.05, function() return 0.05 end) == false, "rollCrit boundary (roll==chance) => false")
-- crit chance clamps to Balance max (1.0): even a 0.999 roll crits at 100%.
record(DamageFormula.rollCrit(5.0, function() return 0.999 end) == true, "rollCrit clamps chance to max")

record(DamageFormula.rollDodge(0.3, function() return 0.1 end) == true, "rollDodge 0.1 < 0.3 => true")
record(DamageFormula.rollDodge(0.3, function() return 0.5 end) == false, "rollDodge 0.5 !< 0.3 => false")
-- dodge chance clamps to Balance max (0.9): a 0.95 roll can never be dodged.
record(DamageFormula.rollDodge(5.0, function() return 0.95 end) == false, "rollDodge clamps chance to max (0.9)")

-- ==================== DamageFormula: incoming damage resolution ====================

-- Dodge => zero damage, HP and shield untouched.
do
	local r = DamageFormula.resolveIncomingDamage({ incoming = 100, shield = 30, hp = 80, dodged = true })
	expectEqual(r.dodged, true, "incoming dodged flag")
	expectApprox(r.hpLost, 0, "incoming dodged hpLost 0")
	expectApprox(r.shield, 30, "incoming dodged shield unchanged")
	expectApprox(r.hp, 80, "incoming dodged hp unchanged")
end

-- % reduction only (no shield): 100 * (1 - 0.2) = 80 straight to HP.
do
	local r = DamageFormula.resolveIncomingDamage({ incoming = 100, damageReduction = 0.2, shield = 0, hp = 200 })
	expectApprox(r.afterReduction, 80, "incoming DR afterReduction")
	expectApprox(r.hpLost, 80, "incoming DR hpLost")
	expectApprox(r.hp, 120, "incoming DR remaining hp")
end

-- Shield absorbs fully: 50 <= 100 shield, HP untouched.
do
	local r = DamageFormula.resolveIncomingDamage({ incoming = 50, shield = 100, hp = 80 })
	expectApprox(r.shieldAbsorbed, 50, "incoming shield full absorb")
	expectApprox(r.shield, 50, "incoming shield remaining")
	expectApprox(r.hpLost, 0, "incoming shield hp untouched")
end

-- Overflow past shield carries to HP in the same hit.
do
	local r = DamageFormula.resolveIncomingDamage({ incoming = 100, shield = 30, hp = 80 })
	expectApprox(r.shieldAbsorbed, 30, "incoming overflow shield absorbed")
	expectApprox(r.shield, 0, "incoming overflow shield emptied")
	expectApprox(r.hpLost, 70, "incoming overflow hpLost")
	expectApprox(r.hp, 10, "incoming overflow remaining hp")
end

-- Full ordering: reduction THEN shield THEN HP. 100 * (1-0.5)=50; shield 20 => 30 to HP.
do
	local r = DamageFormula.resolveIncomingDamage({ incoming = 100, damageReduction = 0.5, shield = 20, hp = 80 })
	expectApprox(r.afterReduction, 50, "incoming order afterReduction")
	expectApprox(r.shieldAbsorbed, 20, "incoming order shield absorbed")
	expectApprox(r.hpLost, 30, "incoming order hpLost")
	expectApprox(r.hp, 50, "incoming order remaining hp")
end

-- DR clamps to Balance max (0.9): 0.99 requested => 0.9 applied, 100 => 10 to HP.
do
	local r = DamageFormula.resolveIncomingDamage({ incoming = 100, damageReduction = 0.99, shield = 0, hp = 80 })
	expectApprox(r.afterReduction, 10, "incoming DR clamp afterReduction")
	expectApprox(r.hpLost, 10, "incoming DR clamp hpLost")
end

-- HP floors at 0 (lethal overkill): 500 damage vs 80 HP => hp 0, hpLost 80.
do
	local r = DamageFormula.resolveIncomingDamage({ incoming = 500, shield = 0, hp = 80 })
	expectApprox(r.hp, 0, "incoming lethal hp floored at 0")
	expectApprox(r.hpLost, 80, "incoming lethal hpLost == hp")
end

-- ==================== summary ====================

local total = passed + failed
if failed == 0 then
	print(("[LogicTests] ALL PASSED (%d/%d)"):format(passed, total))
else
	print(("[LogicTests] %d/%d passed, %d FAILED:"):format(passed, total, failed))
	for _, msg in failures do
		print("  - " .. msg)
	end
	error(("[LogicTests] %d assertion(s) failed"):format(failed), 0)
end
