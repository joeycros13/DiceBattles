--!strict
-- Talents: passive, permanent talent definitions (R-T1..R-T4).
-- All talents exist from the start at level 0; a rarity-weighted roll (R-T2)
-- increases one talent's level by 1. Effect value scales as perLevel * level.
-- Levels are uncapped except extraDice, which caps at maxLevel = 4 (the 5th die).

-- Effect categories (R-T4).
export type TalentEffect =
	"flatAttack"
	| "pctAttack"
	| "critChance"
	| "extraReroll"
	| "extraDice"
	| "hp"
	| "lifesteal"

export type TalentDef = {
	id: string,
	name: string,
	rarity: string, -- Rarities.Defs key (biases roll weight)
	effect: TalentEffect,
	perLevel: number, -- value added per level
	maxLevel: number?, -- nil = uncapped
	icon: string,
	desc: string, -- plain-language explanation shown in the detail popup
}

local Talents = {}

Talents.Order = {
	"Sharpen",
	"Vitality",
	"Berserk",
	"Precision",
	"LuckyHand",
	"Vampiric",
	"Multiroll",
}

Talents.Defs = {
	Sharpen = { id = "Sharpen", name = "Sharpen", rarity = "Common", effect = "flatAttack", perLevel = 2, icon = "talent/flatAttack", desc = "Permanently adds flat attack power to every hit." },
	Vitality = { id = "Vitality", name = "Vitality", rarity = "Common", effect = "hp", perLevel = 10, icon = "talent/hp", desc = "Raises your maximum health so you survive longer." },
	Berserk = { id = "Berserk", name = "Berserk", rarity = "Uncommon", effect = "pctAttack", perLevel = 0.05, icon = "talent/pctAttack", desc = "Increases your total attack damage by a percentage." },
	Precision = { id = "Precision", name = "Precision", rarity = "Rare", effect = "critChance", perLevel = 0.02, icon = "talent/critChance", desc = "Improves your chance to land a critical hit for bonus damage." },
	LuckyHand = { id = "LuckyHand", name = "Lucky Hand", rarity = "Legendary", effect = "extraReroll", perLevel = 1, icon = "talent/extraReroll", desc = "Grants an extra dice reroll each battle to chase better hands." },
	Vampiric = { id = "Vampiric", name = "Vampiric", rarity = "Rare", effect = "lifesteal", perLevel = 0.03, icon = "talent/lifesteal", desc = "Heals you for a portion of the damage you deal." },
	Multiroll = { id = "Multiroll", name = "Multiroll", rarity = "Legendary", effect = "extraDice", perLevel = 1, maxLevel = 4, icon = "talent/extraDice", desc = "Rolls an additional die each turn (up to +4 dice)." },
} :: { [string]: TalentDef }

function Talents.get(id: string): TalentDef?
	return Talents.Defs[id]
end

return Talents
