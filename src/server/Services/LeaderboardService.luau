--!strict
-- LeaderboardService: the 6 leaderboards (Config/Leaderboards; 2026-10-19, the
-- user's design): coins earned, levels gained and kills, each weekly and all-time
-- (the daily boards were dropped on 2026-10-22).
--
-- Counting (per player, saved as the "leaderboard" section of PlayerDataService):
--   coins earned   CoinService.onEarned (kills, quests...; not Robux bundles or admin)
--   levels gained  ExpService.onLevelUp, once the player's save has loaded
--   kills          WorldEnemyService.onDefeated (every enemy, boss and secret enemy)
-- Each player keeps this week's totals with the week they belong to (a new week starts
-- them at 0), lifetime coins and kills, the chat tag a reward gave them and its expiry,
-- the medal each board gave them and its expiry, and their trophies ("Coins_Gold" = 2).
--
-- Published for every client (the medal over the head and in the player list, the #1
-- trail, the Trophies view; Client.Controllers.LeaderFlairController, PlayerListUI,
-- LeaderboardUI): LeaderMedal (the best live medal, "Gold" / "Silver" / "Bronze"),
-- LeaderMedalBoard (its board, "Coins"), LeaderTrail (the board of a live #1, the first
-- in Leaderboards.Stats order when there are several) and Trophies ("Coins_Gold=2,...").
--
-- Boards: each is an OrderedDataStore (Leaderboards.storeName, one per period key).
-- Every WRITE_EVERY seconds a server writes its players' changed scores, and every
-- READ_EVERY it reads each current board's top 50 into a cache that
-- Remotes.GetLeaderboard(stat, period) answers from. All-time levels rank by total EXP.
-- Without DataStores (an unpublished place, Studio) the boards are this server's own
-- players, kept in memory, so the panel still works for testing.
--
-- Rewards: a board that has ended (a new week) is claimed by one server through
-- the "LBRewards" store (UpdateAsync: the first server to mark it pays it), which reads
-- its paid places (the top 3) and posts each player's tier to their mailbox ("LBMailbox", u_<UserId>).
-- A player's mailbox is opened when they join (and checked every READ_EVERY): each
-- entry is granted (coins, EXP, potions, boosts, materials, chat tag, medal, trophy) and a
-- chat message says what they won (Remotes.LeaderboardReward). Without DataStores,
-- the admin "lbReset" action pays a period's rewards straight from the in-memory boards.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Leaderboards = require(Config:WaitForChild("Leaderboards"))
local Potions = require(Config:WaitForChild("Potions"))
local Materials = require(Config:WaitForChild("Materials"))
local Leveling = require(Config:WaitForChild("Leveling"))

local LeaderboardService = {}

type Counts = { Coins: number, Levels: number, Kills: number }
type Medal = { tier: string, untilT: number }
type State = {
	week: number,
	weekly: Counts,
	lifetime: { Coins: number, Kills: number },
	tag: string?,
	tagUntil: number?,
	medals: { [string]: Medal }, -- by board
	trophies: { [string]: number }, -- "<board>_<tier>" -> count
	dirty: boolean,
}
type Row = { rank: number, userId: number, name: string, value: number }

local deps: any = nil
local states: { [Player]: State } = {}
local cache: { [string]: { Row } } = {} -- store name -> top rows
local names: { [number]: string } = {}
local storesOk = true -- false once a DataStore call says they're unavailable
local rewardRemote: RemoteEvent? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function zero(): Counts
	return { Coins = 0, Levels = 0, Kills = 0 }
end

local function fresh(): State
	local t = now()
	return {
		week = Leaderboards.weekOf(t),
		weekly = zero(),
		lifetime = { Coins = 0, Kills = 0 },
		medals = {},
		trophies = {},
		dirty = false,
	}
end

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = fresh()
		states[player] = s
	end
	-- a new week starts its counts again
	local week = Leaderboards.weekOf(now())
	if s.week ~= week then
		s.week, s.weekly = week, zero()
	end
	return s
end

-- The chat tag, the best live medal, the #1 trail and the trophies, as attributes.
local function publishFlair(player: Player, s: State)
	local t = now()
	local live = s.tag ~= nil and (s.tagUntil or 0) > t
	player:SetAttribute("LeaderTag", if live then s.tag else nil)
	local best: string?, bestBoard: string?, trail: string? = nil, nil, nil
	for _, stat in Leaderboards.Stats do
		local m = s.medals[stat]
		if m and m.untilT > t and Leaderboards.Medals[m.tier] then
			local place = Leaderboards.Medals[m.tier].place
			if not best or place < Leaderboards.Medals[best].place then
				best, bestBoard = m.tier, stat
			end
			if m.tier == "Gold" and not trail then
				trail = stat
			end
		end
	end
	player:SetAttribute("LeaderMedal", best)
	player:SetAttribute("LeaderMedalBoard", bestBoard)
	player:SetAttribute("LeaderTrail", trail)
	local parts = {}
	for key, count in s.trophies do
		if type(count) == "number" and count > 0 then
			table.insert(parts, key .. "=" .. count)
		end
	end
	table.sort(parts)
	player:SetAttribute("Trophies", table.concat(parts, ","))
end

local function bump(player: Player, stat: string, amount: number)
	local s = stateOf(player)
	s.weekly[stat] += amount
	if stat ~= "Levels" then
		s.lifetime[stat] += amount
	end
	s.dirty = true
end

-- A player's score on a board.
local function scoreOf(player: Player, stat: string, period: string): number
	local s = stateOf(player)
	if period == "Weekly" then
		return s.weekly[stat]
	elseif stat == "Levels" then
		return deps.Services.ExpService.get(player)
	end
	return s.lifetime[stat]
end

local function storeFor(stat: string, period: string, t: number): (string, OrderedDataStore?)
	local name = Leaderboards.storeName(stat, period, Leaderboards.periodKey(period, t))
	if not storesOk then
		return name, nil
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if not ok then
		storesOk = false
		return name, nil
	end
	return name, store
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.Name else nil
	if not name then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok and type(result) == "string" then result else ("Player " .. userId)
	end
	names[userId] = name :: string
	return name :: string
end

-- The board straight from this server's players (no DataStores).
local function localBoard(stat: string, period: string): { Row }
	local rows = {}
	for _, player in Players:GetPlayers() do
		local value = scoreOf(player, stat, period)
		if value > 0 then
			table.insert(rows, { rank = 0, userId = player.UserId, name = player.Name, value = value })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	for i, row in rows do
		row.rank = i
	end
	return rows
end

local function readBoard(stat: string, period: string, t: number): { Row }?
	local _, store = storeFor(stat, period, t)
	if not store then
		return nil
	end
	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, Leaderboards.TOP)
	end)
	if not ok then
		storesOk = false
		return nil
	end
	local rows = {}
	for i, entry in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(rows, { rank = i, userId = userId, name = nameOf(userId), value = entry.value })
		end
	end
	return rows
end

local function writeScores()
	if not storesOk then
		return
	end
	local t = now()
	for player, s in states do
		if not s.dirty then
			continue
		end
		s.dirty = false
		for _, stat in Leaderboards.Stats do
			for _, period in Leaderboards.Periods do
				local value = math.floor(scoreOf(player, stat, period))
				local _, store = storeFor(stat, period, t)
				if store and value > 0 then
					local ok = pcall(function()
						(store :: OrderedDataStore):SetAsync(tostring(player.UserId), value)
					end)
					if not ok then
						storesOk = false
						return
					end
				end
			end
		end
	end
end

local function refreshCache()
	local t = now()
	for _, stat in Leaderboards.Stats do
		for _, period in Leaderboards.Periods do
			local name = Leaderboards.storeName(stat, period, Leaderboards.periodKey(period, t))
			cache[name] = readBoard(stat, period, t) or cache[name] or {}
		end
	end
end

-- ===== rewards =====

local function grant(player: Player, period: string, stat: string, rank: number, tier: Leaderboards.Tier)
	local reward = tier.reward
	local s = stateOf(player)
	local services = deps.Services
	if reward.coins then
		services.CoinService.add(player, reward.coins, "reward")
	end
	if reward.exp then
		services.ExpService.add(player, reward.exp)
	end
	local world = math.max(1, (player:GetAttribute("HighestWorld") :: number?) or 1)
	local band = Potions.tierAt(world) or 1
	for _, p in reward.potions or {} do
		services.PotionService.add(player, p.kind .. band, p.count)
	end
	for _, b in reward.boosts or {} do
		services.ShopService.addBoost(player, b.id, b.minutes * 60)
	end
	if reward.materials then
		for _, mat in Materials.list() do
			if (mat :: any).world == world and not (mat :: any).core and not (mat :: any).quest and not (mat :: any).gathered then
				services.MaterialService.add(player, mat.id, reward.materials)
			end
		end
	end
	-- the tag and the medal last until the next reset of the board's period
	local untilT = Leaderboards.resetsAt(period, now()) or now()
	if reward.tag then
		s.tag = reward.tag:format(Leaderboards.Text.statShort[stat] or stat)
		s.tagUntil = untilT
	end
	if reward.trophy then
		s.medals[stat] = { tier = reward.trophy, untilT = untilT }
		local key = stat .. "_" .. reward.trophy
		s.trophies[key] = (s.trophies[key] or 0) + 1
	end
	publishFlair(player, s)
	s.dirty = true
	if rewardRemote then
		local t = Leaderboards.Text
		rewardRemote:FireClient(player, {
			text = t.won:format(tier.label, t.period[period], t.stat[stat], table.concat(Leaderboards.describe(reward), ", ")),
			rank = rank,
		})
	end
end

local mailbox: DataStore? = nil
local paid: DataStore? = nil

local function openMailbox(player: Player)
	if not (storesOk and mailbox) then
		return
	end
	local entries = {}
	local ok = pcall(function()
		(mailbox :: DataStore):UpdateAsync("u_" .. player.UserId, function(old)
			entries = if type(old) == "table" then old else {}
			return {}
		end)
	end)
	if not ok then
		return
	end
	for _, entry in entries do
		local tier = Leaderboards.tierFor(entry.period, entry.rank)
		if tier then
			grant(player, entry.period, entry.stat, entry.rank, tier)
		end
	end
end

-- Pay the boards of a period that has ended (key = the old period's key), once.
local function payPeriod(period: string, key: string)
	if not (storesOk and paid and mailbox) then
		return
	end
	local mine = false
	pcall(function()
		(paid :: DataStore):UpdateAsync(period .. "_" .. key, function(old)
			if old then
				return nil -- another server paid it
			end
			mine = true
			return true
		end)
	end)
	if not mine then
		return
	end
	for _, stat in Leaderboards.Stats do
		local name = Leaderboards.storeName(stat, period, key)
		local ok, pages = pcall(function()
			return DataStoreService:GetOrderedDataStore(name):GetSortedAsync(false, math.max(1, Leaderboards.paidPlaces(period)))
		end)
		if ok then
			for rank, entry in (pages :: DataStorePages):GetCurrentPage() do
				pcall(function()
					(mailbox :: DataStore):UpdateAsync("u_" .. entry.key, function(old)
						local list = if type(old) == "table" then old else {}
						table.insert(list, { period = period, stat = stat, rank = rank })
						return list
					end)
				end)
			end
		end
	end
end

-- Without DataStores: pay a period straight from this server's boards (admin "lbReset").
function LeaderboardService.payLocal(period: string): number
	local paidCount = 0
	for _, stat in Leaderboards.Stats do
		for _, row in localBoard(stat, period) do
			local tier = Leaderboards.tierFor(period, row.rank)
			local player = Players:GetPlayerByUserId(row.userId)
			if tier and player then
				grant(player, period, stat, row.rank, tier)
				paidCount += 1
			end
		end
	end
	return paidCount
end

-- ===== the remote =====

function LeaderboardService.board(player: Player, stat: any, period: any): any
	if not (table.find(Leaderboards.Stats, stat) and table.find(Leaderboards.Periods, period)) then
		return nil
	end
	local t = now()
	local rows = if storesOk then (cache[Leaderboards.storeName(stat, period, Leaderboards.periodKey(period, t))] or {}) else localBoard(stat, period)
	local you: any = { value = scoreOf(player, stat, period) }
	for _, row in rows do
		if row.userId == player.UserId then
			you.rank = row.rank
			break
		end
	end
	local shown = {}
	for _, row in rows do
		local value = row.value
		if stat == "Levels" and period == "All" then
			value = (Leveling.fromTotal(value))
		end
		table.insert(shown, { rank = row.rank, name = row.name, value = value, userId = row.userId })
	end
	if stat == "Levels" and period == "All" then
		you.value = (Leveling.fromTotal(you.value))
	end
	return { rows = shown, you = you, resetsAt = Leaderboards.resetsAt(period, t) }
end

-- ===== lifecycle =====

function LeaderboardService.init(injected: any)
	deps = injected
	rewardRemote = deps.Remotes.getEvent("LeaderboardReward")
	deps.Services.PlayerDataService.register("leaderboard", {
		load = function(player: Player, value: any)
			local s = fresh()
			if type(value) == "table" then
				local t = now()
				if value.week == Leaderboards.weekOf(t) and type(value.weekly) == "table" then
					s.weekly = { Coins = value.weekly.Coins or 0, Levels = value.weekly.Levels or 0, Kills = value.weekly.Kills or 0 }
				end
				if type(value.lifetime) == "table" then
					s.lifetime = { Coins = value.lifetime.Coins or 0, Kills = value.lifetime.Kills or 0 }
				end
				s.tag = if type(value.tag) == "string" then value.tag else nil
				s.tagUntil = if type(value.tagUntil) == "number" then value.tagUntil else nil
				-- trophies are per board since 2026-10-22 ("Coins_Gold"); older plain
				-- "Gold" counts (Studio tests only) are dropped
				if type(value.trophies) == "table" then
					for key, count in value.trophies do
						if type(key) == "string" and key:find("_", 1, true) and type(count) == "number" then
							s.trophies[key] = count
						end
					end
				end
				if type(value.medals) == "table" then
					for stat, m in value.medals do
						if type(m) == "table" and type(m.tier) == "string" and type(m.untilT) == "number" then
							s.medals[stat] = { tier = m.tier, untilT = m.untilT }
						end
					end
				end
			end
			states[player] = s
			publishFlair(player, s)
		end,
		save = function(player: Player): any
			local s = states[player]
			if not s then
				return nil
			end
			return {
				week = s.week, weekly = s.weekly, lifetime = s.lifetime,
				tag = s.tag, tagUntil = s.tagUntil, medals = s.medals, trophies = s.trophies,
			}
		end,
	})
end

function LeaderboardService.start()
	local services = deps.Services
	services.CoinService.onEarned(function(player, amount)
		bump(player, "Coins", amount)
	end)
	services.ExpService.onLevelUp(function(player, gained)
		if player:GetAttribute("DataLoaded") then
			bump(player, "Levels", gained)
		end
	end)
	services.WorldEnemyService.onDefeated(function(_enemy, killer)
		if killer then
			bump(killer, "Kills", 1)
		end
	end)
	deps.Remotes.getFunction("GetLeaderboard").OnServerInvoke = function(player: Player, stat: any, period: any)
		return LeaderboardService.board(player, stat, period)
	end
	Players.PlayerRemoving:Connect(function(player)
		task.delay(5, function()
			states[player] = nil
		end)
	end)

	local ok = pcall(function()
		mailbox = DataStoreService:GetDataStore("LBMailbox")
		paid = DataStoreService:GetDataStore("LBRewards")
	end)
	storesOk = ok
	Players.PlayerAdded:Connect(function(player)
		task.spawn(openMailbox, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(openMailbox, player)
	end

	-- the board loop: write, read, pay ended weeks, expire tags and medals
	task.spawn(function()
		local t = now()
		local lastKeys = { Weekly = Leaderboards.periodKey("Weekly", t) }
		local lastWrite = 0
		while true do
			if os.clock() - lastWrite >= Leaderboards.WRITE_EVERY then
				lastWrite = os.clock()
				writeScores()
			end
			refreshCache()
			local tt = now()
			for period, key in lastKeys do
				local current = Leaderboards.periodKey(period, tt)
				if current ~= key then
					lastKeys[period] = current
					writeScores()
					task.spawn(payPeriod, period, key)
				end
			end
			for _, player in Players:GetPlayers() do
				local s = states[player]
				if s then
					publishFlair(player, s)
				end
				task.spawn(openMailbox, player)
			end
			task.wait(Leaderboards.READ_EVERY)
		end
	end)
end

return LeaderboardService
