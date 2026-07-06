--!strict
-- CombatController: mirrors combat state and sends combat intents. Stub for Step 1.

local CombatController = {}

local deps: any = nil

function CombatController.init(injected: any)
	deps = injected
end

function CombatController.start() end

return CombatController
