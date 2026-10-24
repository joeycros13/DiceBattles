--!strict
-- Shop: everything sold for Robux (the user's list, 2026-10-09). ShopService
-- grants purchases on the server; Client.UI.RobuxShopUI fills the hand-built
-- StarterGui/RobuxShop from this.
--
-- Ids: every `productId` (developer products, bought again and again) and
-- `passId` (gamepasses, bought once) is 0 until it is created on the Roblox
-- website for the published place. While an id is 0, Studio grants the item
-- straight away when its Buy button is pressed (a test purchase); live servers
-- refuse it. `price` is what the shop shows; keep it equal to the price set on
-- the website.
--
--   Bundles      coin bundles: `coins` x WorldScale[the player's highest world
--                unlocked]. Repeatable.
--   Passes       permanent multipliers: luck (every weapon drop chance), coins
--                and EXP from kills. Everything owned ADDS its share (2026-10-23,
--                the user; it multiplied before): VIP 1.25 + 2x Luck + a 2x boost =
--                1 + 0.25 + 1 + 1 = 3.25x luck, and the upgrades add on top
--                (Config/Bonuses).
--                VIP also gives the gold [VIP] chat tag.
--   Boosts       timed multipliers, bought again and again; buying one that is
--                running adds its time. The clock only runs while in game.
--   StarterPack  once per player.

local Shop = {}

export type Bundle = { id: string, name: string, coins: number, productId: number, price: number, order: number }
export type Pass = { id: string, name: string, passId: number, price: number, luck: number?, coins: number?, exp: number?, chatTag: boolean? }
export type Boost = { id: string, name: string, productId: number, price: number, seconds: number, luck: number?, coins: number?, exp: number? }

-- Coin bundles grow with the highest world the player has unlocked: x10 a world since
-- 2026-10-23 (it was 1, 4, 16), like the gates' coins (Config/Leveling, world scale).
Shop.WorldScale = { 1, 10, 100, 1000, 10000, 100000, 1000000, 10000000 }

Shop.Bundles = {
	Handful = { id = "Handful", name = "Handful", coins = 250, productId = 0, price = 25, order = 1 },
	Pouch = { id = "Pouch", name = "Pouch", coins = 750, productId = 0, price = 59, order = 2 },
	Sack = { id = "Sack", name = "Sack", coins = 2000, productId = 0, price = 129, order = 3 },
	Chest = { id = "Chest", name = "Chest", coins = 5000, productId = 0, price = 279, order = 4 },
	Vault = { id = "Vault", name = "Vault", coins = 12500, productId = 0, price = 549, order = 5 },
} :: { [string]: Bundle }

Shop.Passes = {
	VIP = { id = "VIP", name = "VIP", passId = 0, price = 399, luck = 1.25, coins = 1.25, exp = 1.25, chatTag = true },
	Luck2 = { id = "Luck2", name = "2x Luck", passId = 0, price = 449, luck = 2 },
	Luck15 = { id = "Luck15", name = "1.5x Luck", passId = 0, price = 199, luck = 1.5 },
	Coins15 = { id = "Coins15", name = "1.5x Coins", passId = 0, price = 149, coins = 1.5 },
	Exp15 = { id = "Exp15", name = "1.5x EXP", passId = 0, price = 149, exp = 1.5 },
} :: { [string]: Pass }

Shop.Boosts = {
	Luck = { id = "Luck", name = "2x Luck", productId = 0, price = 39, seconds = 900, luck = 2 },
	Coins = { id = "Coins", name = "2x Coins", productId = 0, price = 29, seconds = 900, coins = 2 },
	Exp = { id = "Exp", name = "2x EXP", productId = 0, price = 29, seconds = 900, exp = 2 },
} :: { [string]: Boost }

Shop.StarterPack = {
	productId = 0,
	price = 99,
	coins = 500,
	-- a timed boost thrown in: Shop.Boosts[boost] for `boostSeconds`
	boost = "Luck",
	boostSeconds = 1800,
	-- a weapon id to include once the starter item exists (granted through
	-- MeleeService.grant)
	weapon = nil :: string?,
}

-- The HUD's running-boost stack (bottom right, BoostHudUI): the timer wording.
Shop.BoostHud = {
	timeFormat = "%d:%02d", -- minutes, seconds
	hourFormat = "%d:%02d:%02d", -- once stacked boosts pass an hour
}

-- The coins a bundle gives a player whose highest unlocked world is `world`.
function Shop.bundleCoins(bundle: Bundle, world: number): number
	local scale = Shop.WorldScale[math.clamp(world, 1, #Shop.WorldScale)] or 1
	return bundle.coins * scale
end

return Shop
