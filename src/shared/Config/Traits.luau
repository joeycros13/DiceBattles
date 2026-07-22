--!strict
-- Traits: per-battle trait pool offered as a pick-3 when the player reaches 5
-- active dice (R-C23). Traits are temporary and apply for the current battle
-- only. Effects reuse the same categories as talents plus battle-only tweaks.

export type TraitEffect =
	"flatAttack"
	| "pctAttack"
	| "critChance"
	| "critMultiplier"
	| "extraReroll"
	| "lifesteal"
	| "damageReduction"
	| "healAmount"

export type TraitDef = {
	id: string,
	name: string,
	effect: TraitEffect,
	value: number, -- flat amount applied for the battle
	description: string,
	icon: string,
}

local Traits = {}

Traits.Order = {
	"GlassCannon",
	"SteadyHands",
	"KeenEye",
	"Executioner",
	"Bloodthirst",
	"IronSkin",
	"SecondWind",
}

Traits.Defs = {
	GlassCannon = { id = "GlassCannon", name = "Glass Cannon", effect = "pctAttack", value = 0.5, description = "+50% attack for this battle.", icon = "trait/pctAttack" },
	SteadyHands = { id = "SteadyHands", name = "Steady Hands", effect = "extraReroll", value = 2, description = "+2 rerolls each turn this battle.", icon = "trait/extraReroll" },
	KeenEye = { id = "KeenEye", name = "Keen Eye", effect = "critChance", value = 0.15, description = "+15% crit chance this battle.", icon = "trait/critChance" },
	Executioner = { id = "Executioner", name = "Executioner", effect = "critMultiplier", value = 1.0, description = "Crits deal an extra x1 this battle.", icon = "trait/critMultiplier" },
	Bloodthirst = { id = "Bloodthirst", name = "Bloodthirst", effect = "lifesteal", value = 0.2, description = "Heal for 20% of damage dealt.", icon = "trait/lifesteal" },
	IronSkin = { id = "IronSkin", name = "Iron Skin", effect = "damageReduction", value = 0.2, description = "+20% damage reduction this battle.", icon = "trait/damageReduction" },
	SecondWind = { id = "SecondWind", name = "Second Wind", effect = "healAmount", value = 25, description = "+25 heal amount this battle.", icon = "trait/healAmount" },
} :: { [string]: TraitDef }

function Traits.get(id: string): TraitDef?
	return Traits.Defs[id]
end

return Traits
