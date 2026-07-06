--!strict
-- DataService: authoritative persistence layer (profile load/save, session lock,
-- autosave, defaults). All other services depend on it. Stub for Step 1.

local DataService = {}

local deps: any = nil

function DataService.init(injected: any)
	deps = injected
end

function DataService.start() end

return DataService
