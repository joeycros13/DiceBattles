--!strict
-- ShopService: extensible stub for gamepasses, Robux products, and a daily shop
-- (R-X1, ARCHITECTURE.md 9/11). Intentionally thin: it exposes the catalog and
-- the seams where real MarketplaceService wiring will land, but performs no real
-- purchases yet. Structured this way so a later step can implement each stub
-- (ProcessReceipt, PromptGamePassPurchase, daily rotation) without reshaping
-- callers. All currency grants, when live, must go through CurrencyService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Shop = require(Config:WaitForChild("Shop"))

local ShopService = {}

local deps: any = nil
local DataService: any = nil
local CurrencyService: any = nil
local toastRemote: RemoteEvent? = nil

-- Optional player feedback; harmless no-op until a Toast UI consumes it.
local function toast(player: Player, message: string)
	if toastRemote then
		toastRemote:FireClient(player, message)
	end
end

-- The full catalog (pure data). UI reads this to render the shop.
function ShopService.getCatalog(): { [string]: Shop.ShopEntry }
	return Shop.Defs
end

-- Catalog entries of a single kind ("gamepass" | "product" | "daily"), ordered.
function ShopService.getByKind(kind: string): { Shop.ShopEntry }
	return Shop.byKind(kind :: any)
end

-- STUB: begin a purchase for `entryId`. A later step will branch on the entry's
-- kind and call MarketplaceService:PromptGamePassPurchase / PromptProductPurchase,
-- then grant via CurrencyService in ProcessReceipt. For now it just acknowledges.
-- Returns false to signal "not fulfilled yet" so callers don't assume a grant.
function ShopService.PromptPurchase(player: Player, entryId: string): boolean
	local entry = Shop.get(entryId)
	if not entry then
		return false
	end
	toast(player, ("%s is coming soon."):format(entry.name))
	return false
end

-- STUB: the daily shop rotation. A later step will derive a deterministic daily
-- set (e.g. seeded by os.time // 86400) and track per-player claims in the
-- profile. For now it returns the static daily entries from config.
function ShopService.getDailyShop(_player: Player?): { Shop.ShopEntry }
	return Shop.byKind("daily")
end

function ShopService.init(injected: any)
	deps = injected
	DataService = deps.Services.DataService
	CurrencyService = deps.Services.CurrencyService
	toastRemote = deps.Remotes.getEvent("Toast")
end

function ShopService.start() end

return ShopService
