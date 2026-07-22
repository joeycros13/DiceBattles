--!strict
-- Shop: catalog stub reserving room for gamepasses, Robux products, and a daily
-- shop (R-X1, ARCHITECTURE.md 9/11). Pure data only. Real asset ids (gamepass /
-- developer product ids) are 0 placeholders; wiring them to MarketplaceService is
-- deferred to a later step. Systems read this generically so adding an entry is a
-- one-line config change.

export type ShopKind = "gamepass" | "product" | "daily"

export type ShopEntry = {
	id: string,
	name: string,
	kind: ShopKind,
	description: string,
	icon: string, -- logical asset id for AssetResolver (e.g. "shop/gamepass")
	robux: number?, -- Robux price (gamepasses / products)
	assetId: number?, -- MarketplaceService gamepass/product id (0 = placeholder)
	grants: { [string]: number }?, -- currency grants (products / daily)
}

local Shop = {}

-- Display order per section; UI iterates these for a stable layout.
Shop.Order = {
	"VIP",
	"DoubleCoins",
	"GemsSmall",
	"GemsLarge",
	"KeysBundle",
	"DailyCoins",
	"DailyKeys",
}

Shop.Defs = {
	-- Gamepasses (permanent perks).
	VIP = {
		id = "VIP",
		name = "VIP",
		kind = "gamepass",
		description = "Permanent perks and a daily bonus. (Coming soon)",
		icon = "shop/gamepass",
		robux = 199,
		assetId = 0,
	},
	DoubleCoins = {
		id = "DoubleCoins",
		name = "2x Coins",
		kind = "gamepass",
		description = "Doubles all coin rewards. (Coming soon)",
		icon = "shop/gamepass",
		robux = 149,
		assetId = 0,
	},

	-- Developer products (consumable currency bundles).
	GemsSmall = {
		id = "GemsSmall",
		name = "Handful of Gems",
		kind = "product",
		description = "A small pouch of gems. (Coming soon)",
		icon = "shop/product",
		robux = 99,
		assetId = 0,
		grants = { gems = 100 },
	},
	GemsLarge = {
		id = "GemsLarge",
		name = "Chest of Gems",
		kind = "product",
		description = "A large chest of gems. (Coming soon)",
		icon = "shop/product",
		robux = 799,
		assetId = 0,
		grants = { gems = 1000 },
	},
	KeysBundle = {
		id = "KeysBundle",
		name = "Key Bundle",
		kind = "product",
		description = "10 chest keys. (Coming soon)",
		icon = "shop/product",
		robux = 199,
		assetId = 0,
		grants = { keys = 10 },
	},

	-- Daily shop (rotating free/cheap offers).
	DailyCoins = {
		id = "DailyCoins",
		name = "Daily Coins",
		kind = "daily",
		description = "A free coin stipend, once per day. (Coming soon)",
		icon = "shop/daily",
		grants = { coins = 250 },
	},
	DailyKeys = {
		id = "DailyKeys",
		name = "Daily Key",
		kind = "daily",
		description = "A free chest key, once per day. (Coming soon)",
		icon = "shop/daily",
		grants = { keys = 1 },
	},
} :: { [string]: ShopEntry }

function Shop.get(id: string): ShopEntry?
	return Shop.Defs[id]
end

-- All entries of a given kind, in Shop.Order (stable for UI).
function Shop.byKind(kind: ShopKind): { ShopEntry }
	local list: { ShopEntry } = {}
	for _, id in Shop.Order do
		local def = Shop.Defs[id]
		if def and def.kind == kind then
			table.insert(list, def)
		end
	end
	return list
end

return Shop
