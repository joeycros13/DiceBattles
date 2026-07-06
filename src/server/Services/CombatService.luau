--!strict
-- CombatService: per-player authoritative combat state machine
-- (chapter/stage/turn flow, dice, damage, enemy actions). Stub for Step 1.

local CombatService = {}

local deps: any = nil

function CombatService.init(injected: any)
	deps = injected
end

function CombatService.start() end

return CombatService
