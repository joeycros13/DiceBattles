--!strict
-- GlobalLevelService: global XP/level; level-ups grant stats, talent rolls,
-- and permanent starting-dice upgrades. Stub for Step 1.

local GlobalLevelService = {}

local deps: any = nil

function GlobalLevelService.init(injected: any)
	deps = injected
end

function GlobalLevelService.start() end

return GlobalLevelService
