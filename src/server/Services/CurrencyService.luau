--!strict
-- CurrencyService: sole mutator of balances (coins, gems, materials, keys)
-- with add/spend validation. Stub for Step 1.

local CurrencyService = {}

local deps: any = nil

function CurrencyService.init(injected: any)
	deps = injected
end

function CurrencyService.start() end

return CurrencyService
