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
	Sharpen = { id = "Sharpen", name = "Sharpen", rarity = "Common", effect = "flatAttack", perLevel = 2, icon = "talent/flatAttack" },
	Vitality = { id = "Vitality", name = "Vitality", rarity = "Common", effect = "hp", perLevel = 10, icon = "talent/hp" },
	Berserk = { id = "Berserk", name = "Berserk", rarity = "Uncommon", effect = "pctAttack", perLevel = 0.05, icon = "talent/pctAttack" },
	Precision = { id = "Precision", name = "Precision", rarity = "Rare", effect = "critChance", perLevel = 0.02, icon = "talent/critChance" },
	LuckyHand = { id = "LuckyHand", name = "Lucky Hand", rarity = "Epic", effect = "extraReroll", perLevel = 1, icon = "talent/extraReroll" },
	Vampiric = { id = "Vampiric", name = "Vampiric", rarity = "Rare", effect = "lifesteal", perLevel = 0.03, icon = "talent/lifesteal" },
	Multiroll = { id = "Multiroll", name = "Multiroll", rarity = "Legendary", effect = "extraDice", perLevel = 1, maxLevel = 4, icon = "talent/extraDice" },
} :: { [string]: TalentDef }

function Talents.get(id: string): TalentDef?
	return Talents.Defs[id]
end

return Talents
