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
local InventoryLayout = require(Logic:WaitForChild("InventoryLayout"))
local MergeLogic = require(Logic:WaitForChild("MergeLogic"))
local TalentLogic = require(Logic:WaitForChild("TalentLogic"))
local GlobalLevel = require(Logic:WaitForChild("GlobalLevel"))
local LootTable = require(Logic:WaitForChild("LootTable"))

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

-- ==================== InventoryLayout: empty-tile / row growth ====================

-- columnCount + cellSize: 7 columns of ~96px targets (10 pad) fit an 800px row,
-- and the cell then fills the row exactly.
expectEqual(InventoryLayout.columnCount(800, 96, 10), 7, "columnCount 800/96/10 => 7")
expectEqual(InventoryLayout.cellSize(800, 7, 10), 105, "cellSize 800/7/10 => 105")
expectEqual(InventoryLayout.columnCount(0, 96, 10), 1, "columnCount zero width => 1")

-- Row growth uses columns = 8, minRows = 5 (a 40-tile visible area).
local COLS = 8
local MINROWS = 5

-- Empty inventory: still fills the whole visible area.
do
	local p = InventoryLayout.plan(0, COLS, MINROWS)
	expectEqual(p.totalRows, 5, "plan(0) totalRows == minRows")
	expectEqual(p.emptyCount, 40, "plan(0) empties fill visible area")
end

-- A few items: no extra rows, empties fill the rest of the visible area.
do
	local p = InventoryLayout.plan(9, COLS, MINROWS)
	expectEqual(p.totalRows, 5, "plan(9) stays at minRows")
	expectEqual(p.emptyCount, 31, "plan(9) empties = 40 - 9")
end

-- Exactly filling the visible area: no empties, no extra row yet.
do
	local p = InventoryLayout.plan(40, COLS, MINROWS)
	expectEqual(p.totalRows, 5, "plan(40) exactly fills visible area")
	expectEqual(p.emptyCount, 0, "plan(40) no empties")
end

-- Overflow by ONE: grows by exactly one row, and only that row is padded.
do
	local p = InventoryLayout.plan(41, COLS, MINROWS)
	expectEqual(p.totalRows, 6, "plan(41) adds exactly one row")
	expectEqual(p.emptyCount, 7, "plan(41) only the new row is padded (8-1)")
end

-- Filling that new row: empties return to zero (no premature extra row).
do
	local p = InventoryLayout.plan(48, COLS, MINROWS)
	expectEqual(p.totalRows, 6, "plan(48) still six rows")
	expectEqual(p.emptyCount, 0, "plan(48) new row filled, no empties")
end

-- One more after that: exactly one further row appears, again padded alone.
do
	local p = InventoryLayout.plan(49, COLS, MINROWS)
	expectEqual(p.totalRows, 7, "plan(49) adds one more row")
	expectEqual(p.emptyCount, 7, "plan(49) only the newest row padded")
end

-- Guards: bad inputs are coerced, never error.
do
	local p = InventoryLayout.plan(5, 0, 0)
	expectEqual(p.columns, 1, "plan guards columns >= 1")
	expectEqual(p.totalRows, 5, "plan guards minRows >= 1 (rows == items at 1 col)")
end

-- ==================== MergeLogic: gear merging ====================

-- Three identical Common weapons upgrade to an Uncommon of the same base id.
do
	local r = MergeLogic.evaluate({
		{ id = "WoodSword", rarity = "Common" },
		{ id = "WoodSword", rarity = "Common" },
		{ id = "WoodSword", rarity = "Common" },
	})
	expectEqual(r.ok, true, "merge 3x WoodSword Common ok")
	expectEqual(r.result and r.result.id, "WoodSword", "merge result keeps base id")
	expectEqual(r.result and r.result.rarity, "Uncommon", "merge result rarity +1")
	expectEqual(r.slot, "Weapon", "merge result slot Weapon")
end

-- Same slot but different base ids (same rarity) still merge; result uses first id.
do
	local r = MergeLogic.evaluate({
		{ id = "IronSword", rarity = "Common" },
		{ id = "FlameBlade", rarity = "Common" },
		{ id = "WoodSword", rarity = "Common" },
	})
	expectEqual(r.ok, true, "merge mixed-id same-slot same-rarity ok")
	expectEqual(r.result and r.result.id, "IronSword", "merge mixed result uses first id")
	expectEqual(r.result and r.result.rarity, "Uncommon", "merge mixed result rarity +1")
end

-- Different slots are rejected.
do
	local r = MergeLogic.evaluate({
		{ id = "WoodSword", rarity = "Common" },
		{ id = "IronHelm", rarity = "Common" },
		{ id = "LeatherBelt", rarity = "Common" },
	})
	expectEqual(r.ok, false, "merge different slots rejected")
end

-- Different rarities are rejected.
do
	local r = MergeLogic.evaluate({
		{ id = "WoodSword", rarity = "Common" },
		{ id = "WoodSword", rarity = "Common" },
		{ id = "WoodSword", rarity = "Uncommon" },
	})
	expectEqual(r.ok, false, "merge different rarities rejected")
end

-- Legendary cannot be upgraded further.
do
	local r = MergeLogic.evaluate({
		{ id = "Aegis", rarity = "Legendary" },
		{ id = "Aegis", rarity = "Legendary" },
		{ id = "Aegis", rarity = "Legendary" },
	})
	expectEqual(r.ok, false, "merge Legendary rejected (no higher rarity)")
end

-- Wrong count is rejected.
do
	local r = MergeLogic.evaluate({
		{ id = "WoodSword", rarity = "Common" },
		{ id = "WoodSword", rarity = "Common" },
	})
	expectEqual(r.ok, false, "merge with 2 inputs rejected")
end

-- resultFor previews the upgrade for a single selection.
do
	local preview = MergeLogic.resultFor({ id = "WoodSword", rarity = "Common" })
	expectEqual(preview and preview.rarity, "Uncommon", "resultFor Common -> Uncommon")
	expectEqual(MergeLogic.resultFor({ id = "Aegis", rarity = "Legendary" }), nil, "resultFor Legendary -> nil")
	expectEqual(MergeLogic.resultFor(nil), nil, "resultFor nil -> nil")
	expectEqual(MergeLogic.slotOf({ id = "WoodSword", rarity = "Common" }), "Weapon", "slotOf WoodSword -> Weapon")
end

-- ==================== MergeLogic: auto merge (cascading) ====================

-- Helper: total gear of a given rarity produced by an auto plan.
local function countRarity(plan: any, rarity: string): number
	local n = 0
	for _, inst in plan.addInstances do
		if inst.rarity == rarity then
			n += 1
		end
	end
	return n
end

-- 3 Common weapons -> 1 Uncommon.
do
	local plan = MergeLogic.planAuto({
		{ uid = "a", id = "WoodSword", rarity = "Common" },
		{ uid = "b", id = "WoodSword", rarity = "Common" },
		{ uid = "c", id = "WoodSword", rarity = "Common" },
	})
	expectEqual(#plan.removeUids, 3, "auto 3 Common: removes 3")
	expectEqual(#plan.addInstances, 1, "auto 3 Common: adds 1")
	expectEqual(countRarity(plan, "Uncommon"), 1, "auto 3 Common: result Uncommon")
end

-- 3 Common + 2 Uncommon cascade: 3 Common -> 1 Uncommon, then 3 Uncommon -> 1 Rare.
do
	local plan = MergeLogic.planAuto({
		{ uid = "a", id = "WoodSword", rarity = "Common" },
		{ uid = "b", id = "WoodSword", rarity = "Common" },
		{ uid = "c", id = "WoodSword", rarity = "Common" },
		{ uid = "d", id = "IronSword", rarity = "Uncommon" },
		{ uid = "e", id = "IronSword", rarity = "Uncommon" },
	})
	expectEqual(#plan.removeUids, 5, "auto cascade: removes all 5 originals")
	expectEqual(#plan.addInstances, 1, "auto cascade: adds 1")
	expectEqual(countRarity(plan, "Rare"), 1, "auto cascade: result Rare")
end

-- Nothing to merge (only 2 of a kind).
do
	local plan = MergeLogic.planAuto({
		{ uid = "a", id = "WoodSword", rarity = "Common" },
		{ uid = "b", id = "WoodSword", rarity = "Common" },
	})
	expectEqual(#plan.removeUids, 0, "auto nothing: removes 0")
	expectEqual(#plan.addInstances, 0, "auto nothing: adds 0")
end

-- 9 Common weapons -> 3 Uncommon -> 1 Rare (full cascade, synthetics consumed).
do
	local nine: { any } = {}
	for i = 1, 9 do
		table.insert(nine, { uid = "w" .. i, id = "WoodSword", rarity = "Common" })
	end
	local plan = MergeLogic.planAuto(nine)
	expectEqual(#plan.removeUids, 9, "auto 9 Common: removes 9")
	expectEqual(#plan.addInstances, 1, "auto 9 Common: adds 1")
	expectEqual(countRarity(plan, "Rare"), 1, "auto 9 Common: result Rare")
end

-- Different slots merge independently in one run.
do
	local plan = MergeLogic.planAuto({
		{ uid = "a", id = "WoodSword", rarity = "Common" },
		{ uid = "b", id = "WoodSword", rarity = "Common" },
		{ uid = "c", id = "WoodSword", rarity = "Common" },
		{ uid = "d", id = "IronHelm", rarity = "Common" },
		{ uid = "e", id = "IronHelm", rarity = "Common" },
		{ uid = "f", id = "IronHelm", rarity = "Common" },
	})
	expectEqual(#plan.removeUids, 6, "auto multi-slot: removes 6")
	expectEqual(#plan.addInstances, 2, "auto multi-slot: adds 2")
	expectEqual(countRarity(plan, "Uncommon"), 2, "auto multi-slot: 2 Uncommon")
end

-- Legendary cannot merge and is left untouched.
do
	local plan = MergeLogic.planAuto({
		{ uid = "a", id = "Aegis", rarity = "Legendary" },
		{ uid = "b", id = "Aegis", rarity = "Legendary" },
		{ uid = "c", id = "Aegis", rarity = "Legendary" },
	})
	expectEqual(#plan.removeUids, 0, "auto Legendary: removes 0")
	expectEqual(#plan.addInstances, 0, "auto Legendary: adds 0")
end

-- ==================== TalentLogic: weighted roll ====================

-- A fresh talents map: every talent present at level 0 (matches R-T1 defaults).
local function freshTalents(): { [string]: number }
	return {
		Sharpen = 0,
		Vitality = 0,
		Berserk = 0,
		Precision = 0,
		LuckyHand = 0,
		Vampiric = 0,
		Multiroll = 0,
	}
end

-- Pool total weight = sum of every talent's rarity weight (2 Common@100,
-- 1 Uncommon@50, 2 Rare@20, 2 Legendary@2 = 294).
do
	local _, total = TalentLogic.buildPool(freshTalents())
	expectApprox(total, 294, "talent pool total weight (all level 0)")
end

-- Deterministic pick: rng at 0 hits the first pool entry (Sharpen), a mid roll
-- lands on Vitality, and a near-1 roll reaches the last entry (Multiroll).
expectEqual(TalentLogic.pick(freshTalents(), function() return 0.0 end), "Sharpen", "pick rng=0 -> first (Sharpen)")
expectEqual(TalentLogic.pick(freshTalents(), function() return 0.5 end), "Vitality", "pick rng=0.5 -> Vitality (147/294)")
expectEqual(TalentLogic.pick(freshTalents(), function() return 0.999 end), "Multiroll", "pick rng~1 -> last (Multiroll)")

-- Maxed talents are excluded: Multiroll (extraDice) caps at level 4.
expectEqual(TalentLogic.isMaxed("Multiroll", 4), true, "isMaxed Multiroll at cap")
expectEqual(TalentLogic.isMaxed("Multiroll", 3), false, "isMaxed Multiroll below cap")
expectEqual(TalentLogic.isMaxed("Sharpen", 999), false, "isMaxed uncapped talent never maxes")
do
	local maxed = freshTalents()
	maxed.Multiroll = 4
	local _, total = TalentLogic.buildPool(maxed)
	expectApprox(total, 292, "pool excludes maxed Multiroll (294 - 2)")
	-- A near-1 roll now lands on Vampiric (the new last eligible entry).
	expectEqual(TalentLogic.pick(maxed, function() return 0.999 end), "Vampiric", "pick skips maxed talent")
end

-- An empty talents map means every talent defaults to level 0 (profiles omit
-- unrolled talents), so buildPool still uses the full definition list and a pick
-- returns a valid, non-maxed talent rather than nil.
do
	local _, total = TalentLogic.buildPool({})
	expectApprox(total, 294, "empty talents map still builds the full pool")
	local picked = TalentLogic.pick({}, function() return 0.5 end)
	record(picked ~= nil, "pick with empty talents map returns a valid talent",
		("picked=%s"):format(tostring(picked)))
end

-- Distribution sanity (R-T2): rarer talents roll LESS often than common ones.
do
	local rng = Random.new(1337)
	local counts: { [string]: number } = {}
	local samples = 4000
	for _ = 1, samples do
		local id = TalentLogic.pick(freshTalents(), function()
			return rng:NextNumber()
		end)
		if id then
			counts[id] = (counts[id] or 0) + 1
		end
	end
	local common = (counts.Sharpen or 0) + (counts.Vitality or 0)
	local legendary = (counts.Multiroll or 0) + (counts.LuckyHand or 0)
	record(common > legendary, "distribution: Common rolled more than Legendary",
		("common=%d legendary=%d"):format(common, legendary))
	record((counts.Vitality or 0) > (counts.LuckyHand or 0), "distribution: a Common rolled more than a Legendary",
		("vitality=%d luckyHand=%d"):format(counts.Vitality or 0, counts.LuckyHand or 0))
end

-- ==================== TalentLogic: effect values & formatting ====================

expectApprox(TalentLogic.effectValue("Sharpen", 3), 6, "effectValue Sharpen L3 (2*3)")
expectApprox(TalentLogic.effectValue("Berserk", 2), 0.10, "effectValue Berserk L2 (0.05*2)")
expectApprox(TalentLogic.effectValue("Sharpen", 0), 0, "effectValue at level 0 is 0")

expectEqual(TalentLogic.formatBonus("Sharpen", 3), "+6 Attack", "formatBonus flat attack")
expectEqual(TalentLogic.formatBonus("Berserk", 2), "+10% Attack", "formatBonus percent attack")
expectEqual(TalentLogic.formatBonus("Precision", 1), "+2% Crit Chance", "formatBonus percent crit")
expectEqual(TalentLogic.formatBonus("Vampiric", 1), "+3% Lifesteal", "formatBonus percent lifesteal")
expectEqual(TalentLogic.formatBonus("Multiroll", 4), "+4 Dice", "formatBonus flat dice")
expectEqual(TalentLogic.effectLabel("pctAttack"), "Attack", "effectLabel pctAttack -> Attack")

-- ==================== GlobalLevel: XP curve & level-ups ====================

-- xpToNext follows baseXp + (level-1)*xpPerLevel, floored at level 1.
do
	local g = Balance.Global
	expectApprox(GlobalLevel.xpToNext(1), g.baseXp, "xpToNext(1) == baseXp")
	expectApprox(GlobalLevel.xpToNext(2), g.baseXp + g.xpPerLevel, "xpToNext(2) == baseXp + xpPerLevel")
	expectApprox(GlobalLevel.xpToNext(3), g.baseXp + 2 * g.xpPerLevel, "xpToNext(3)")
	-- Level below 1 is clamped to 1.
	expectApprox(GlobalLevel.xpToNext(0), g.baseXp, "xpToNext(0) clamps to level 1")
end

-- Not enough XP to level: xp banks, level unchanged, 0 gained.
do
	local need = GlobalLevel.xpToNext(1)
	local level, xp, gained = GlobalLevel.applyXp(1, 0, need - 1)
	expectEqual(level, 1, "applyXp below threshold: level unchanged")
	expectApprox(xp, need - 1, "applyXp below threshold: xp banked")
	expectEqual(gained, 0, "applyXp below threshold: 0 gained")
end

-- Exactly enough XP: one level, leftover 0.
do
	local level, xp, gained = GlobalLevel.applyXp(1, 0, GlobalLevel.xpToNext(1))
	expectEqual(level, 2, "applyXp exact: level 2")
	expectApprox(xp, 0, "applyXp exact: leftover 0")
	expectEqual(gained, 1, "applyXp exact: 1 gained")
end

-- Leftover carries: existing xp + added spills into the next level.
do
	local level, xp, gained = GlobalLevel.applyXp(1, 50, GlobalLevel.xpToNext(1))
	expectEqual(level, 2, "applyXp carry: level 2")
	expectApprox(xp, 50, "applyXp carry: leftover 50")
	expectEqual(gained, 1, "applyXp carry: 1 gained")
end

-- Cascading multi-level: enough XP for two levels at once.
do
	local twoLevels = GlobalLevel.xpToNext(1) + GlobalLevel.xpToNext(2)
	local level, xp, gained = GlobalLevel.applyXp(1, 0, twoLevels)
	expectEqual(level, 3, "applyXp cascade: level 3")
	expectApprox(xp, 0, "applyXp cascade: leftover 0")
	expectEqual(gained, 2, "applyXp cascade: 2 gained")
end

-- Zero / negative added XP never regresses a profile.
do
	local level, xp, gained = GlobalLevel.applyXp(2, 30, 0)
	expectEqual(level, 2, "applyXp zero add: level unchanged")
	expectApprox(xp, 30, "applyXp zero add: xp unchanged")
	expectEqual(gained, 0, "applyXp zero add: 0 gained")

	local nlevel, nxp, ngained = GlobalLevel.applyXp(2, 30, -100)
	expectEqual(nlevel, 2, "applyXp negative add: level unchanged")
	expectApprox(nxp, 30, "applyXp negative add: xp clamped (no loss)")
	expectEqual(ngained, 0, "applyXp negative add: 0 gained")
end

-- progress reports the fraction toward the next level.
do
	expectApprox(GlobalLevel.progress(1, 0), 0, "progress at 0 xp == 0")
	expectApprox(GlobalLevel.progress(1, GlobalLevel.xpToNext(1) / 2), 0.5, "progress half == 0.5")
	expectApprox(GlobalLevel.progress(1, GlobalLevel.xpToNext(1) * 2), 1, "progress clamps to 1")
end

-- ==================== LootTable: weighted rolls ====================

-- roll returns nil for an empty pool or all-zero weights.
do
	expectEqual(LootTable.roll({}), nil, "LootTable empty pool -> nil")
	expectEqual(LootTable.roll({ { weight = 0 }, { weight = 0 } }), nil, "LootTable zero weights -> nil")
end

-- roll maps the RNG value to the correct weighted bucket boundaries.
do
	-- Pool: A weight 1, B weight 3 (total 4). target = rng*4.
	local pool = { { id = "A", weight = 1 }, { id = "B", weight = 3 } }
	local a = LootTable.roll(pool, function()
		return 0.0
	end)
	expectEqual(a and a.id, "A", "LootTable target 0 -> A")
	local aEdge = LootTable.roll(pool, function()
		return 0.24 -- 0.96 < 1 -> still A
	end)
	expectEqual(aEdge and aEdge.id, "A", "LootTable target <1 -> A")
	local b = LootTable.roll(pool, function()
		return 0.25 -- 1.0 -> B bucket starts at 1
	end)
	expectEqual(b and b.id, "B", "LootTable target 1 -> B")
	local bHigh = LootTable.roll(pool, function()
		return 0.999
	end)
	expectEqual(bHigh and bHigh.id, "B", "LootTable target ~4 -> B")
end

-- roll skips zero-weight entries entirely.
do
	local pool = { { id = "Z", weight = 0 }, { id = "Y", weight = 5 } }
	local picked = LootTable.roll(pool, function()
		return 0.0
	end)
	expectEqual(picked and picked.id, "Y", "LootTable skips zero-weight entry")
end

-- rollMany returns exactly `count` results (clamped at 0 for non-positive).
do
	local pool = { { id = "A", weight = 1 } }
	expectEqual(#LootTable.rollMany(pool, 5), 5, "rollMany count 5")
	expectEqual(#LootTable.rollMany(pool, 0), 0, "rollMany count 0")
	expectEqual(#LootTable.rollMany(pool, -3), 0, "rollMany negative -> 0")
end

-- randomInt is inclusive on both ends and order-agnostic.
do
	expectEqual(LootTable.randomInt(3, 3, function()
		return 0.5
	end), 3, "randomInt min==max")
	expectEqual(LootTable.randomInt(1, 6, function()
		return 0.0
	end), 1, "randomInt rng 0 -> min")
	expectEqual(LootTable.randomInt(1, 6, function()
		return 0.999
	end), 6, "randomInt rng ~1 -> max")
	expectEqual(LootTable.randomInt(6, 1, function()
		return 0.0
	end), 1, "randomInt swapped bounds -> min")
end

-- Statistical bias sanity: heavier weight is picked far more often.
do
	local pool = { { id = "rare", weight = 1 }, { id = "common", weight = 99 } }
	local seed = Random.new(12345)
	local commonHits = 0
	for _ = 1, 2000 do
		local picked = LootTable.roll(pool, function()
			return seed:NextNumber()
		end)
		if picked and picked.id == "common" then
			commonHits += 1
		end
	end
	record(commonHits > 1800, "LootTable weight bias favors common", ("common hits = %d/2000"):format(commonHits))
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
