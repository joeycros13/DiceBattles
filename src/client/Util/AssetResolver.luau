--!strict
-- AssetResolver: maps a logical id (e.g. "gear/weapon") to a placeholder visual.
-- Swapping in real assets = updating this map only. Stub for Step 1.

local AssetResolver = {}

local deps: any = nil

function AssetResolver.init(injected: any)
	deps = injected
end

function AssetResolver.start() end

return AssetResolver
