--!strict
-- DamageFormula: pure combat math for player outgoing damage and incoming enemy
-- damage resolution (ARCHITECTURE.md 6; R-C14..R-C18). No `game` state beyond
-- Balance config, so it is deterministic and unit-testable. RNG (crit/dodge) is
-- injectable so callers stay authoritative and tests stay deterministic.
--
-- Player damage ordering (R-C14 / ARCHITECTURE 6):
--   final = (diceTotal + flat) * (1 + pct) * handMultiplier * (crit and critMult or 1)
--   Crit is rolled once per attack, applied AFTER the hand multiplier.
--
-- Incoming damage ordering (R-C15): dodge -> % reduction -> shield buffer -> HP.
--   Overflow past the shield carries to HP in the same hit.

local Balance = require(script.Parent.Parent.Config.Balance)

local DamageFormula = {}

-- ==================== Player outgoing damage ====================

export type PlayerDamageParams = {
	diceTotal: number, -- sum of current dice face values
	flatBonus: number?, -- flat attack added before the % bonus (default 0)
	pctBonus: number?, -- fractional % bonus, e.g. 0.25 = +25% (default 0)
	handMultiplier: number, -- from DiceHands.evaluate().multiplier
	crit: boolean?, -- whether this attack crit (roll via rollCrit); default false
	critMultiplier: number?, -- crit damage factor (default Balance baseCritMultiplier)
	lifesteal: number?, -- fraction of final damage healed to player (default 0)
}

export type PlayerDamageResult = {
	base: number, -- dice total
	adjusted: number, -- after flat then % : (base + flat) * (1 + pct)
	beforeCrit: number, -- after hand multiplier
	crit: boolean, -- whether crit was applied
	damage: number, -- final damage dealt to the enemy
	lifestealHeal: number, -- HP the player heals from this hit
}

-- Compute final player damage. Deterministic: crit is passed in, not rolled here.
function DamageFormula.computePlayerDamage(params: PlayerDamageParams): PlayerDamageResult
	local flat = params.flatBonus or 0
	local pct = params.pctBonus or 0
	local critMult = params.critMultiplier or Balance.Player.baseCritMultiplier
	local crit = params.crit == true
	local lifesteal = params.lifesteal or 0

	local base = params.diceTotal
	local adjusted = (base + flat) * (1 + pct)
	local beforeCrit = adjusted * params.handMultiplier
	local damage = beforeCrit * (if crit then critMult else 1)
	local lifestealHeal = damage * lifesteal

	return {
		base = base,
		adjusted = adjusted,
		beforeCrit = beforeCrit,
		crit = crit,
		damage = damage,
		lifestealHeal = lifestealHeal,
	}
end

-- Roll whether an attack crits. `rng` (optional) returns a float in [0,1); when
-- omitted, math.random() is used. Crit chance is clamped to Balance max.
function DamageFormula.rollCrit(critChance: number, rng: (() -> number)?): boolean
	local chance = math.clamp(critChance, 0, Balance.Player.maxCritChance)
	local roll = if rng then rng() else math.random()
	return roll < chance
end

-- ==================== Incoming enemy damage ====================

export type IncomingParams = {
	incoming: number, -- raw enemy attack value
	damageReduction: number?, -- fractional DR, e.g. 0.2 = -20% (default 0)
	dodged: boolean?, -- whether the hit was dodged (roll via rollDodge); default false
	shield: number, -- current shield buffer
	hp: number, -- current HP
}

export type IncomingResult = {
	dodged: boolean,
	afterReduction: number, -- damage remaining after % reduction (0 if dodged)
	shieldAbsorbed: number, -- amount soaked by the shield
	hpLost: number, -- amount removed from HP
	shield: number, -- remaining shield after the hit
	hp: number, -- remaining HP after the hit (floored at 0)
}

-- Resolve one incoming hit against the player in order: dodge -> % reduction ->
-- shield -> HP, with shield overflow carrying to HP in the same hit.
function DamageFormula.resolveIncomingDamage(params: IncomingParams): IncomingResult
	if params.dodged == true then
		return {
			dodged = true,
			afterReduction = 0,
			shieldAbsorbed = 0,
			hpLost = 0,
			shield = params.shield,
			hp = params.hp,
		}
	end

	local dr = math.clamp(params.damageReduction or 0, 0, Balance.Player.maxDamageReduction)
	local afterReduction = params.incoming * (1 - dr)

	local shieldAbsorbed = math.min(params.shield, afterReduction)
	local remainingShield = params.shield - shieldAbsorbed

	local overflow = afterReduction - shieldAbsorbed
	local hpLost = math.min(params.hp, overflow)
	local remainingHp = params.hp - hpLost

	return {
		dodged = false,
		afterReduction = afterReduction,
		shieldAbsorbed = shieldAbsorbed,
		hpLost = hpLost,
		shield = remainingShield,
		hp = remainingHp,
	}
end

-- Roll whether an incoming attack is dodged (R-C16). `rng` optional as above.
function DamageFormula.rollDodge(dodgeChance: number, rng: (() -> number)?): boolean
	local chance = math.clamp(dodgeChance, 0, Balance.Player.maxDodgeChance)
	local roll = if rng then rng() else math.random()
	return roll < chance
end

return DamageFormula
