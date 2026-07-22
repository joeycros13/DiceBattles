--!strict
-- LeaderboardService: generic global leaderboards backed by OrderedDataStore
-- (R-L1/R-L2, ARCHITECTURE.md 8).
--
-- One OrderedDataStore per named stat, keyed `lb_<statName>`, entry key = userId.
-- The set of tracked stats is data-driven by Config/Leaderboards, so adding a
-- board is one config entry + one SubmitForPlayer call from the gameplay event.
--
-- Responsibilities:
--   * Submit(statName, userId, value): persist a player's value, keeping the MAX
--     seen (seed stats are "highest ..."), coalescing rapid submits per key.
--   * GetTop(statName, count): descending ranked list [{ userId, name, value }].
--   * Periodically refresh each board's top-N, cache it, and replicate to clients
--     via the LeaderboardUpdated remote (send the cache to each joiner).
--   * Fall back to an in-memory MOCK ordered store in Studio (or when the real
--     OrderedDataStore is unavailable) so the board is exercisable offline.
--
-- All writes go through this service; it never touches PlayerData directly except
-- to READ the current stat value in SubmitForPlayer (DataService stays the owner).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Leaderboards = require(Config:WaitForChild("Leaderboards"))

export type Entry = { userId: number, name: string, value: number }

local LeaderboardService = {}

-- ==================== configuration ====================

local KEY_PREFIX = "lb_" -- OrderedDataStore name = KEY_PREFIX .. statName
local REFRESH_INTERVAL = 30 -- fallback interval to pick up OTHER servers' changes
local FLUSH_INTERVAL = 2 -- seconds between draining the pending-write queue
local USE_MOCK_IN_STUDIO = true -- Studio uses the in-memory mock (no persistence)

-- ==================== state ====================

local deps: any = nil
local DataService: any = nil
local leaderboardUpdated: RemoteEvent? = nil

local usingMock = false
local stores: { [string]: any } = {} -- statName -> OrderedDataStore (or mock)

-- Pending writes coalesced by stat/user: only the highest value survives a flush.
local pending: { [string]: { [number]: number } } = {} -- statName -> userId -> value

-- Last computed top-N per stat, replicated to clients and sent to new joiners.
local cache: { [string]: { Entry } } = {}

-- Resolve display names once (network call) and reuse.
local nameCache: { [number]: string } = {}

-- ==================== mock ordered store ====================

-- Minimal OrderedDataStore stand-in: SetAsync + GetSortedAsync(descending) so
-- Studio play-solo exercises the exact same code paths as live.
local function createMockOrderedStore()
	local values: { [string]: number } = {}
	return {
		SetAsync = function(_self, key: string, value: number)
			values[key] = value
		end,
		GetSortedAsync = function(_self, _ascending: boolean, pageSize: number)
			local ordered: { { key: string, value: number } } = {}
			for key, value in values do
				table.insert(ordered, { key = key, value = value })
			end
			table.sort(ordered, function(a, b)
				return a.value > b.value
			end)
			local page: { { key: string, value: number } } = {}
			for i = 1, math.min(pageSize, #ordered) do
				page[i] = ordered[i]
			end
			-- Mimic the DataStorePages surface we actually use.
			return {
				GetCurrentPage = function()
					return page
				end,
			}
		end,
	}
end

-- Lazily fetch (and cache) the ordered store for a stat.
local function getStore(statName: string): any?
	local existing = stores[statName]
	if existing then
		return existing
	end

	if usingMock then
		local mock = createMockOrderedStore()
		stores[statName] = mock
		return mock
	end

	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(KEY_PREFIX .. statName)
	end)
	if ok and store then
		stores[statName] = store
		return store
	end

	warn(("[LeaderboardService] OrderedDataStore unavailable for %q: %s"):format(statName, tostring(store)))
	return nil
end

-- ==================== name resolution ====================

local function resolveName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end

	-- Prefer an online player's name (free, always current).
	local online = Players:GetPlayerByUserId(userId)
	if online then
		nameCache[userId] = online.Name
		return online.Name
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = (ok and type(name) == "string") and name or ("User " .. tostring(userId))
	nameCache[userId] = resolved
	return resolved
end

-- ==================== submission ====================

-- Queue a value for a stat/user, coalescing to the max pending value. The queue
-- is drained on an interval to respect DataStore write budgets (only the latest
-- value per key is written).
function LeaderboardService.Submit(statName: string, userId: number, value: number)
	if type(statName) ~= "string" or not Leaderboards.get(statName) then
		warn(("[LeaderboardService] Submit ignored: unknown stat %q"):format(tostring(statName)))
		return
	end
	if type(userId) ~= "number" or type(value) ~= "number" then
		return
	end

	local intValue = math.floor(value)
	local queue = pending[statName]
	if not queue then
		queue = {}
		pending[statName] = queue
	end
	queue[userId] = math.max(queue[userId] or intValue, intValue)
end

-- Convenience: read the current stat value from a player's profile and submit it
-- under their userId. This is the single call gameplay events make.
function LeaderboardService.SubmitForPlayer(player: Player, statName: string)
	local data = DataService and DataService.get(player)
	local stats = data and data.stats
	if not stats then
		return
	end
	local value = stats[statName]
	-- Only post real progress: a non-positive value means the player hasn't
	-- earned a place on this board yet (e.g. 0 chapters cleared).
	if type(value) == "number" and value > 0 then
		LeaderboardService.Submit(statName, player.UserId, value)
	end
end

-- Write one value, keeping the max already stored (boards track "highest ...").
local function writeEntry(store: any, userId: number, value: number)
	pcall(function()
		store:SetAsync(tostring(userId), value)
	end)
end

-- Drain the pending queue, coalesced per key, into the ordered stores.
-- Returns true if at least one value was written (so callers can refresh).
local function flush(): boolean
	local wrote = false
	for statName, queue in pending do
		local store = getStore(statName)
		if store then
			for userId, value in queue do
				writeEntry(store, userId, value)
				wrote = true
			end
		end
		pending[statName] = nil
	end
	return wrote
end

-- ==================== reads / replication ====================

-- Descending ranked entries for a stat: [{ userId, name, value }].
function LeaderboardService.GetTop(statName: string, count: number): { Entry }
	local def = Leaderboards.get(statName)
	if not def then
		return {}
	end
	local store = getStore(statName)
	if not store then
		return {}
	end

	local wanted = math.clamp(count, 1, 100)
	local entries: { Entry } = {}
	local ok, err = pcall(function()
		local pages = store:GetSortedAsync(false, wanted)
		local page = pages:GetCurrentPage()
		for _, item in page do
			local userId = tonumber(item.key)
			if userId then
				table.insert(entries, {
					userId = userId,
					name = resolveName(userId),
					value = item.value,
				})
			end
		end
	end)
	if not ok then
		warn(("[LeaderboardService] GetTop failed for %q: %s"):format(statName, tostring(err)))
	end
	return entries
end

-- Cached top-N for a stat (last refresh); empty until the first refresh runs.
function LeaderboardService.getCached(statName: string): { Entry }
	return cache[statName] or {}
end

-- The full replicated payload: statName -> ranked entries.
local function buildPayload(): { [string]: { Entry } }
	local payload: { [string]: { Entry } } = {}
	for statName, entries in cache do
		payload[statName] = entries
	end
	return payload
end

-- Refresh every board's cache from the store, then broadcast to all clients.
local function refresh()
	for _, def in Leaderboards.all() do
		cache[def.statName] = LeaderboardService.GetTop(def.statName, def.topCount)
	end
	if leaderboardUpdated then
		leaderboardUpdated:FireAllClients(buildPayload())
	end
end

-- ==================== lifecycle ====================

function LeaderboardService.init(injected: any)
	deps = injected
	DataService = deps.Services.DataService
	leaderboardUpdated = deps.Remotes.getEvent("LeaderboardUpdated")

	usingMock = RunService:IsStudio() and USE_MOCK_IN_STUDIO
	if usingMock then
		print("[LeaderboardService] Studio detected -> using in-memory MOCK ordered store")
	end
end

function LeaderboardService.start()
	-- Seed each joining player's stats into the boards and send them the cache.
	DataService.ProfileLoaded.Event:Connect(function(player: Player)
		for _, def in Leaderboards.all() do
			LeaderboardService.SubmitForPlayer(player, def.statName)
		end
		if leaderboardUpdated then
			leaderboardUpdated:FireClient(player, buildPayload())
		end
	end)

	-- Write-flush loop (coalesced to respect DataStore budgets). As soon as a
	-- write lands we refresh + broadcast so standings update near-instantly for
	-- the player who just changed a stat, instead of waiting a full cycle.
	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			if flush() then
				refresh()
			end
		end
	end)

	-- Slow fallback refresh so this server also reflects changes made on OTHER
	-- live servers; the write-flush loop above handles local updates promptly.
	task.spawn(function()
		task.wait(1)
		refresh()
		while true do
			task.wait(REFRESH_INTERVAL)
			refresh()
		end
	end)
end

return LeaderboardService
