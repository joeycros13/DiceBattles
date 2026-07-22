--!strict
-- Currencies: currency ids + display metadata (R-Y1).
-- CurrencyService mutates balances generically by reading these ids.

export type CurrencyDef = {
	id: string,
	name: string,
	abbrev: string,
	premium: boolean, -- purchasable with Robux
	icon: string, -- logical asset id for AssetResolver
	description: string,
}

local Currencies = {}

Currencies.Order = { "coins", "gems", "materials", "keys" }

Currencies.Defs = {
	coins = {
		id = "coins",
		name = "Coins",
		abbrev = "C",
		premium = false,
		icon = "currency/coins",
		description = "Spent on talent rolls.",
	},
	gems = {
		id = "gems",
		name = "Gems",
		abbrev = "G",
		premium = true,
		icon = "currency/gems",
		description = "Premium currency for the shop and chests.",
	},
	materials = {
		id = "materials",
		name = "Slot Materials",
		abbrev = "M",
		premium = false,
		icon = "currency/materials",
		description = "Spent to level up equipment slots.",
	},
	keys = {
		id = "keys",
		name = "Keys",
		abbrev = "K",
		premium = false,
		icon = "currency/keys",
		description = "One key opens one chest roll.",
	},
} :: { [string]: CurrencyDef }

function Currencies.get(id: string): CurrencyDef?
	return Currencies.Defs[id]
end

return Currencies
