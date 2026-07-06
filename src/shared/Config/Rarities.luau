--!strict
-- Rarities: rarity order + per-rarity stat multiplier, roll weight, and color.
-- Pure data (see ARCHITECTURE.md 5, R-E6). Rarity scales the magnitude of a
-- slot's buff and biases weighted rolls (rarer = less likely).

export type RarityDef = {
	id: string,
	name: string,
	order: number, -- 1 = lowest
	multiplier: number, -- scales gear base stat magnitude
	weight: number, -- weighted-roll likelihood (higher = more common)
	color: Color3, -- placeholder tint for AssetResolver
}

local Rarities = {}

-- Low -> high (R-E6).
Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

Rarities.Defs = {
	Common = {
		id = "Common",
		name = "Common",
		order = 1,
		multiplier = 1.0,
		weight = 100,
		color = Color3.fromRGB(170, 170, 170),
	},
	Uncommon = {
		id = "Uncommon",
		name = "Uncommon",
		order = 2,
		multiplier = 1.5,
		weight = 50,
		color = Color3.fromRGB(80, 200, 90),
	},
	Rare = {
		id = "Rare",
		name = "Rare",
		order = 3,
		multiplier = 2.25,
		weight = 20,
		color = Color3.fromRGB(60, 140, 240),
	},
	Epic = {
		id = "Epic",
		name = "Epic",
		order = 4,
		multiplier = 3.5,
		weight = 6,
		color = Color3.fromRGB(170, 80, 230),
	},
	Legendary = {
		id = "Legendary",
		name = "Legendary",
		order = 5,
		multiplier = 5.0,
		weight = 2,
		color = Color3.fromRGB(245, 175, 45),
	},
} :: { [string]: RarityDef }

-- Lookup helper (pure).
function Rarities.get(id: string): RarityDef?
	return Rarities.Defs[id]
end

-- Numeric sort order for a rarity id (0 if unknown).
function Rarities.orderOf(id: string): number
	local def = Rarities.Defs[id]
	return def and def.order or 0
end

return Rarities
