--!strict
-- InventoryService: gear inventory, equip/unequip, slot levels. Stub for Step 1.

local InventoryService = {}

local deps: any = nil

function InventoryService.init(injected: any)
	deps = injected
end

function InventoryService.start() end

return InventoryService
