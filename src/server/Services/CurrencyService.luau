--!strict
-- CurrencyService: the sole mutator of player currency balances (coins, gems,
-- materials, keys) with add/spend validation (ARCHITECTURE.md 9, R-Y1). Every
-- balance change flows through here so validation and replication stay in one
-- place; all writes go through DataService.update. Other services (TalentService,
-- and later ChestService/InventoryService) call these instead of touching
-- `profile.currencies` directly. Reads/mutations are keyed by Currencies ids.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Currencies = require(Config:WaitForChild("Currencies"))

local CurrencyService = {}

local deps: any = nil
local DataService: any = nil

-- Validate that `currencyId` names a known currency.
local function isValidCurrency(currencyId: string): boolean
	return type(currencyId) == "string" and Currencies.get(currencyId) ~= nil
end

-- Current balance of a currency for a player (0 if unknown / not loaded).
function CurrencyService.get(player: Player, currencyId: string): number
	if not isValidCurrency(currencyId) then
		return 0
	end
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return (data.currencies :: { [string]: number })[currencyId] or 0
end

-- True if the player can afford `amount` of `currencyId` (amount must be >= 0).
function CurrencyService.canAfford(player: Player, currencyId: string, amount: number): boolean
	if type(amount) ~= "number" or amount < 0 then
		return false
	end
	return CurrencyService.get(player, currencyId) >= amount
end

-- Grant `amount` (>= 0) of a currency. Returns true on success.
function CurrencyService.add(player: Player, currencyId: string, amount: number): boolean
	if not isValidCurrency(currencyId) or type(amount) ~= "number" or amount < 0 then
		return false
	end
	if amount == 0 then
		return true
	end
	return DataService.update(player, function(profile)
		local balances = profile.currencies :: { [string]: number }
		balances[currencyId] = (balances[currencyId] or 0) + amount
	end)
end

-- Spend `amount` (>= 0) of a currency if affordable. Returns true only when the
-- deduction actually happened, so callers can gate an action on the result.
function CurrencyService.spend(player: Player, currencyId: string, amount: number): boolean
	if not isValidCurrency(currencyId) or type(amount) ~= "number" or amount < 0 then
		return false
	end
	if amount == 0 then
		return true
	end
	if not CurrencyService.canAfford(player, currencyId, amount) then
		return false
	end
	return DataService.update(player, function(profile)
		local balances = profile.currencies :: { [string]: number }
		balances[currencyId] = (balances[currencyId] or 0) - amount
	end)
end

function CurrencyService.init(injected: any)
	deps = injected
	DataService = deps.Services.DataService
end

function CurrencyService.start() end

return CurrencyService
