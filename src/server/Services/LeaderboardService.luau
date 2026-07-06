--!strict
-- LeaderboardService: generic OrderedDataStore stat tracking (lb_<statName>).
-- Stub for Step 1.

local LeaderboardService = {}

local deps: any = nil

function LeaderboardService.init(injected: any)
	deps = injected
end

function LeaderboardService.start() end

return LeaderboardService
