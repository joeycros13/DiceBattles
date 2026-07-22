--!strict
-- ChestLoot: the single chest's weighted loot table (R-Y2, R-Y3). One key buys
-- one roll here; ChestService resolves each rolled entry into a concrete reward
-- via CurrencyService / InventoryService. Pure data (no side effects); every
-- value is a PLACEHOLDER to be tuned later.
--
-- Entry kinds:
--   "currency" -> grants a random amount in [min, max] of `currency`.
--   "gear"     -> grants one random gear piece; its rarity is rolled separately
--                 by ChestService (weighted by Rarities), so no fields needed here.

export type LootKind = "currency" | "gear"

export type LootEntry = {
	id: string, -- stable id for logging / UI
	kind: LootKind,
	weight: number, -- roll likelihood (higher = more common)
	currency: string?, -- Currencies id, for kind == "currency"
	min: number?, -- inclusive min amount, for kind == "currency"
	max: number?, -- inclusive max amount, for kind == "currency"
}

local ChestLoot = {}

ChestLoot.Entries = {
	{ id = "coinsSmall", kind = "currency", weight = 40, currency = "coins", min = 25, max = 75 },
	{ id = "coinsBig", kind = "currency", weight = 15, currency = "coins", min = 100, max = 220 },
	{ id = "materialsSmall", kind = "currency", weight = 30, currency = "materials", min = 3, max = 8 },
	{ id = "materialsBig", kind = "currency", weight = 10, currency = "materials", min = 10, max = 22 },
	{ id = "gemsSmall", kind = "currency", weight = 8, currency = "gems", min = 1, max = 5 },
	{ id = "keysBonus", kind = "currency", weight = 5, currency = "keys", min = 1, max = 2 },
	{ id = "gearDrop", kind = "gear", weight = 12 },
} :: { LootEntry }

return ChestLoot
