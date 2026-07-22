--!strict
-- LeaderboardController: mirrors the leaderboard data replicated from the server
-- (ARCHITECTURE.md 8). Listens to the `LeaderboardUpdated` remote, caches the
-- latest per-stat ranked entries, and notifies UI subscribers on any change.
-- Read-only on the client.

export type Entry = { userId: number, name: string, value: number }
export type Payload = { [string]: { Entry } }

local LeaderboardController = {}

local deps: any = nil
local Remotes: any = nil

local boards: Payload = {}
local changedEvent: BindableEvent = Instance.new("BindableEvent")

function LeaderboardController.init(injected: any)
	deps = injected
	Remotes = deps.Remotes
end

function LeaderboardController.start()
	local updated = Remotes.getEvent("LeaderboardUpdated")
	updated.OnClientEvent:Connect(function(payload: Payload)
		boards = payload or {}
		changedEvent:Fire(boards)
	end)
end

-- Ranked entries for a stat (empty until the first replication arrives).
function LeaderboardController.get(statName: string): { Entry }
	return boards[statName] or {}
end

-- The whole replicated payload (statName -> entries).
function LeaderboardController.getAll(): Payload
	return boards
end

-- Subscribe to leaderboard updates; callback receives the full payload.
function LeaderboardController.onChanged(callback: (Payload) -> ()): RBXScriptConnection
	return changedEvent.Event:Connect(callback)
end

return LeaderboardController
