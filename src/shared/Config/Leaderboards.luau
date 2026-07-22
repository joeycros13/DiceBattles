--!strict
-- Leaderboards: declares the named stats tracked by the OrderedDataStore-backed
-- LeaderboardService (R-L1/R-L2, ARCHITECTURE.md 8). Pure data only.
--
-- Adding a new leaderboard stat is a one-entry change here plus a single
-- LeaderboardService.SubmitForPlayer call from the gameplay event that changes
-- the stat; the service (store, sorting, replication, display) is fully generic.
--
-- `statName` MUST match the key written into PlayerData.stats so the service can
-- read the current value directly from a player's profile.

export type LeaderboardStat = {
	statName: string, -- key in PlayerData.stats and the OrderedDataStore suffix (lb_<statName>)
	displayName: string, -- human-readable heading shown in the UI
	topCount: number, -- how many ranked entries to fetch/replicate
}

local Leaderboards = {}

-- Display order; the UI iterates this for a stable layout.
Leaderboards.Order = {
	"highestChapter",
}

Leaderboards.Defs = {
	highestChapter = {
		statName = "highestChapter",
		displayName = "Highest Chapter",
		topCount = 25,
	},
} :: { [string]: LeaderboardStat }

function Leaderboards.get(statName: string): LeaderboardStat?
	return Leaderboards.Defs[statName]
end

-- All stat defs in Leaderboards.Order (stable for iteration/UI).
function Leaderboards.all(): { LeaderboardStat }
	local list: { LeaderboardStat } = {}
	for _, statName in Leaderboards.Order do
		local def = Leaderboards.Defs[statName]
		if def then
			table.insert(list, def)
		end
	end
	return list
end

return Leaderboards
