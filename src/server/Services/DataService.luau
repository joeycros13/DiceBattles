--!strict
-- DataService: authoritative persistence layer for one save per user (R-D1..R-D3).
--
-- Responsibilities:
--   * Build a well-defined default PlayerData profile from config (R-D3).
--   * Load a profile on join from DataStore behind a SESSION LOCK so two live
--     servers can never write the same key concurrently (R-D2).
--   * Expose read/mutate accessors so every other service reads and edits state
--     through this single owner, and replicate changes to the owning client.
--   * Autosave on an interval and on player leave, refreshing / releasing the
--     lock as appropriate; flush everything on BindToClose (R-D2).
--   * Fall back to an in-memory MOCK store in Studio (or when DataStore access is
--     unavailable) so the game is fully playable offline.
--
-- Combat state is transient and NOT persisted; only durable results other
-- services write into the profile are saved (ARCHITECTURE.md 7).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = Shared:WaitForChild("Config")
local Currencies = require(Config:WaitForChild("Currencies"))
local Slots = require(Config:WaitForChild("Slots"))
local Talents = require(Config:WaitForChild("Talents"))

type PlayerData = Types.PlayerData

-- A stored record wraps the durable data plus the session lock metadata.
type Lock = { sessionId: string, placeId: number, timestamp: number }
type Record = { data: PlayerData?, lock: Lock? }

-- A live in-memory session for a connected player.
type Session = {
	key: string,
	data: PlayerData,
	saving: boolean,
}

local DataService = {}

-- Fired as (player: Player, data: PlayerData) once a profile is loaded &
-- reconciled. Services that need to react to a fresh profile connect to this.
DataService.ProfileLoaded = Instance.new("BindableEvent")

-- ==================== configuration ====================

local DATASTORE_NAME = "PlayerData_v1"
local KEY_PREFIX = "Player_"
local CURRENT_VERSION = 1

local AUTOSAVE_INTERVAL = 60 -- seconds between periodic saves
local LOCK_STALE_SECONDS = 20 * 60 -- a lock older than this is considered dead and may be stolen
local LOAD_MAX_ATTEMPTS = 6 -- attempts to acquire the lock before giving up
local LOAD_RETRY_DELAY = 5 -- seconds between lock-acquire attempts
local USE_MOCK_IN_STUDIO = true -- Studio always uses the in-memory mock

-- Unique id for THIS server; used to detect whether a lock belongs to us. JobId
-- is empty in Studio/local, so fall back to a generated guid.
local SESSION_ID: string = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

-- ==================== state ====================

local deps: any = nil
local profileUpdated: RemoteEvent? = nil
local store: any = nil
local usingMock = false
local sessions: { [Player]: Session } = {}

-- ==================== defaults & reconciliation ====================

-- Deep copy a plain-data value (numbers/strings/bools/tables). Profiles only
-- ever contain JSON-safe data, so this is sufficient and avoids shared refs.
local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy: any = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Starter gear granted to brand-new players so the Equipment tab is usable
-- before chests exist (Step 13 introduces the loot source). Each entry becomes
-- an owned, initially-unequipped instance. Safe to trim once chests land.
local STARTER_GEAR: { { id: string, rarity: string } } = {
	{ id = "WoodSword", rarity = "Common" },
	{ id = "IronSword", rarity = "Uncommon" },
	{ id = "IronHelm", rarity = "Common" },
	{ id = "RunicHelm", rarity = "Rare" },
	{ id = "LeatherBelt", rarity = "Common" },
	{ id = "LeatherVest", rarity = "Common" },
	{ id = "LuckyCharm", rarity = "Common" },
	{ id = "Sandals", rarity = "Common" },
	{ id = "SwiftBoots", rarity = "Uncommon" },

	-- TEST GEAR (R-E9): plentiful same type+rarity sets so gear merging can be
	-- exercised end-to-end. Trim alongside STARTER_GEAR once chests land.
	-- Weapons: enough Common to merge twice, plus Uncommon and Rare sets.
	{ id = "WoodSword", rarity = "Common" },
	{ id = "WoodSword", rarity = "Common" },
	{ id = "WoodSword", rarity = "Common" },
	{ id = "IronSword", rarity = "Common" },
	{ id = "IronSword", rarity = "Common" },
	{ id = "IronSword", rarity = "Uncommon" },
	{ id = "IronSword", rarity = "Uncommon" },
	{ id = "FlameBlade", rarity = "Rare" },
	{ id = "FlameBlade", rarity = "Rare" },
	{ id = "FlameBlade", rarity = "Rare" },
	-- Helmets
	{ id = "IronHelm", rarity = "Common" },
	{ id = "IronHelm", rarity = "Common" },
	{ id = "SteelHelm", rarity = "Uncommon" },
	{ id = "SteelHelm", rarity = "Uncommon" },
	{ id = "SteelHelm", rarity = "Uncommon" },
	-- Boots
	{ id = "Sandals", rarity = "Common" },
	{ id = "Sandals", rarity = "Common" },
	{ id = "SwiftBoots", rarity = "Uncommon" },
	-- Charms
	{ id = "LuckyCharm", rarity = "Common" },
	{ id = "LuckyCharm", rarity = "Common" },
	{ id = "LuckyCharm", rarity = "Uncommon" },
	-- Chestplates
	{ id = "LeatherVest", rarity = "Common" },
	{ id = "LeatherVest", rarity = "Common" },
	{ id = "PlateArmor", rarity = "Rare" },
	-- Belts
	{ id = "LeatherBelt", rarity = "Common" },
	{ id = "LeatherBelt", rarity = "Common" },
	{ id = "HealerSash", rarity = "Rare" },

	-- BULK TEST GEAR: extra pieces so the inventory overflows several rows,
	-- exercising scrolling + one-row-at-a-time growth. Trim with STARTER_GEAR.
	{ id = "WoodSword", rarity = "Common" },
	{ id = "WoodSword", rarity = "Common" },
	{ id = "WoodSword", rarity = "Common" },
	{ id = "IronSword", rarity = "Uncommon" },
	{ id = "IronSword", rarity = "Uncommon" },
	{ id = "IronSword", rarity = "Uncommon" },
	{ id = "FlameBlade", rarity = "Rare" },
	{ id = "FlameBlade", rarity = "Rare" },
	{ id = "DragonFang", rarity = "Epic" },
	{ id = "IronHelm", rarity = "Common" },
	{ id = "IronHelm", rarity = "Common" },
	{ id = "IronHelm", rarity = "Common" },
	{ id = "SteelHelm", rarity = "Uncommon" },
	{ id = "SteelHelm", rarity = "Uncommon" },
	{ id = "RunicHelm", rarity = "Rare" },
	{ id = "RunicHelm", rarity = "Rare" },
	{ id = "Sandals", rarity = "Common" },
	{ id = "Sandals", rarity = "Common" },
	{ id = "Sandals", rarity = "Common" },
	{ id = "SwiftBoots", rarity = "Uncommon" },
	{ id = "SwiftBoots", rarity = "Uncommon" },
	{ id = "PhantomBoots", rarity = "Epic" },
	{ id = "LuckyCharm", rarity = "Common" },
	{ id = "LuckyCharm", rarity = "Common" },
	{ id = "LuckyCharm", rarity = "Common" },
	{ id = "LuckyCharm", rarity = "Uncommon" },
	{ id = "LuckyCharm", rarity = "Uncommon" },
	{ id = "CritGem", rarity = "Epic" },
	{ id = "LeatherVest", rarity = "Common" },
	{ id = "LeatherVest", rarity = "Common" },
	{ id = "LeatherVest", rarity = "Common" },
	{ id = "PlateArmor", rarity = "Rare" },
	{ id = "PlateArmor", rarity = "Rare" },
	{ id = "Aegis", rarity = "Legendary" },
	{ id = "LeatherBelt", rarity = "Common" },
	{ id = "LeatherBelt", rarity = "Common" },
	{ id = "LeatherBelt", rarity = "Uncommon" },
	{ id = "HealerSash", rarity = "Rare" },
	{ id = "HealerSash", rarity = "Rare" },
	{ id = "HealerSash", rarity = "Rare" },
}

-- Build a fresh, well-defined default profile for a brand-new player (R-D3).
-- Derived from config so adding a currency/slot/talent needs no edits here.
local function makeDefaultData(): PlayerData
	local currencies: { [string]: number } = {}
	for _, id in Currencies.Order do
		currencies[id] = 0
	end
	-- TEST CURRENCY: seed coins so talent rolls can be exercised end-to-end
	-- before a real coin source (chapter rewards / chests) lands. Trim once
	-- those economy sources exist (Steps 12-13).
	currencies.coins = 500

	local slotLevels: { [string]: number } = {}
	local equipped: { [string]: string? } = {}
	for _, id in Slots.Order do
		slotLevels[id] = 1 -- slots start at level 1 (R-E3, R-E8)
		equipped[id] = nil -- nothing equipped initially
	end

	local talents: { [string]: number } = {}
	for _, id in Talents.Order do
		talents[id] = 0 -- all talents present from the start at level 0 (R-T1)
	end

	local gear: { [string]: Types.GearInstance } = {}
	for index, entry in STARTER_GEAR do
		gear["starter_" .. index] = { id = entry.id, rarity = entry.rarity }
	end

	return {
		version = CURRENT_VERSION,
		global = { level = 1, xp = 0 },
		currencies = (currencies :: any) :: Types.Currencies,
		startingDiceUpgrade = 0,
		gear = gear,
		equipped = equipped,
		slotLevels = slotLevels,
		talents = talents,
		progress = { currentChapter = 1, chaptersCompleted = 0 },
		-- Seed leaderboard-tracked stats to well-defined starting values (R-L2).
		stats = { highestChapter = 1, highestPlayerLevel = 1 },
		-- Permanent combat-stat bonuses from global level-ups (R-C22); empty at start.
		globalStatBonus = {},
	}
end

-- Recursively add any keys present in template but missing in target, without
-- ever overwriting values the player already has. Lets defaults (new currencies,
-- slots, talents, fields) safely appear on old saves.
local function fillMissing(target: { [any]: any }, template: { [any]: any })
	for key, templateValue in template do
		local current = target[key]
		if current == nil then
			target[key] = deepCopy(templateValue)
		elseif type(current) == "table" and type(templateValue) == "table" then
			fillMissing(current, templateValue)
		end
	end
end

-- Take whatever was loaded (possibly nil / an older version) and return a
-- complete, current-version PlayerData. This is the single migration entry
-- point: the `version` field enables future explicit migrations.
local function reconcile(loaded: PlayerData?): PlayerData
	local template = makeDefaultData()
	if type(loaded) ~= "table" then
		return template
	end
	local data = loaded :: PlayerData
	fillMissing(data :: any, template :: any)
	data.version = CURRENT_VERSION
	return data
end

-- ==================== store resolution (real vs mock) ====================

-- In-memory stand-in implementing the tiny slice of the DataStore API we use.
-- Data does not persist across sessions, which is exactly what we want in
-- Studio without API access enabled.
local function createMockStore(): any
	local storage: { [string]: any } = {}
	local mock = {}

	function mock:GetAsync(key: string): any
		return deepCopy(storage[key])
	end

	function mock:SetAsync(key: string, value: any)
		storage[key] = deepCopy(value)
	end

	function mock:UpdateAsync(key: string, transform: (any) -> any): any
		local transformed = transform(deepCopy(storage[key]))
		if transformed ~= nil then
			storage[key] = deepCopy(transformed)
		end
		return deepCopy(storage[key])
	end

	function mock:RemoveAsync(key: string): any
		local previous = storage[key]
		storage[key] = nil
		return previous
	end

	return mock
end

-- Pick the real DataStore when available; otherwise fall back to the mock and
-- log why, so the choice is never silent.
local function resolveStore()
	if RunService:IsStudio() and USE_MOCK_IN_STUDIO then
		usingMock = true
		store = createMockStore()
		print("[DataService] Studio detected -> using in-memory MOCK store (no persistence)")
		return
	end

	local ok, real = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok and real then
		store = real
		usingMock = false
		print(("[DataService] using live DataStore %q"):format(DATASTORE_NAME))
	else
		usingMock = true
		store = createMockStore()
		warn(("[DataService] DataStore unavailable (%s) -> using in-memory MOCK store"):format(tostring(real)))
	end
end

-- ==================== lock helpers ====================

-- True if a lock belongs to another server and is still fresh (not stale).
local function isForeignAndFresh(lock: Lock?): boolean
	if not lock then
		return false
	end
	if lock.sessionId == SESSION_ID then
		return false
	end
	return (os.time() - lock.timestamp) < LOCK_STALE_SECONDS
end

local function makeLock(): Lock
	return { sessionId = SESSION_ID, placeId = game.PlaceId, timestamp = os.time() }
end

-- ==================== replication ====================

-- Push the authoritative profile to its owning client (server -> client).
local function replicate(player: Player)
	local session = sessions[player]
	if session and profileUpdated then
		profileUpdated:FireClient(player, session.data)
	end
end

-- ==================== load / save ====================

-- Attempt one atomic lock acquisition via UpdateAsync. Returns the acquired
-- record on success, nil if the key is locked by a live foreign session, and
-- errors are surfaced via the second return value.
local function tryAcquire(key: string): (Record?, string?)
	local acquired: Record? = nil
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old: Record?): Record?
			local record: Record = old or {}
			if isForeignAndFresh(record.lock) then
				-- Another live server owns this profile; abort the write.
				return nil
			end
			record.lock = makeLock()
			acquired = record
			return record
		end)
	end)
	if not ok then
		return nil, tostring(err)
	end
	return acquired, nil
end

-- Load (or create) a player's profile behind the session lock. Retries while the
-- key is held by a live foreign session; kicks the player if it can never be
-- acquired so we never risk a data-losing overwrite.
local function loadProfile(player: Player)
	local key = KEY_PREFIX .. tostring(player.UserId)
	local record: Record? = nil

	for attempt = 1, LOAD_MAX_ATTEMPTS do
		if player.Parent == nil then
			return -- player left mid-load
		end

		local acquired, err = tryAcquire(key)
		if err then
			warn(("[DataService] load attempt %d for %s failed: %s"):format(attempt, player.Name, err))
		elseif acquired then
			record = acquired
			break
		else
			warn(("[DataService] profile for %s is locked by another session (attempt %d)"):format(player.Name, attempt))
		end

		if attempt < LOAD_MAX_ATTEMPTS then
			task.wait(LOAD_RETRY_DELAY)
		end
	end

	if player.Parent == nil then
		return
	end

	if not record then
		player:Kick("Your saved data is currently in use by another server. Please rejoin in a moment.")
		return
	end

	local data = reconcile(record.data)
	sessions[player] = { key = key, data = data, saving = false }

	print(("[DataService] loaded profile for %s (v%d)"):format(player.Name, data.version))
	DataService.ProfileLoaded:Fire(player, data)
	replicate(player)
end

-- Persist a player's profile. When `release` is true the lock is cleared (used on
-- leave / shutdown); otherwise the lock timestamp is refreshed to keep it alive.
-- We refuse to overwrite if our lock was stolen by a live foreign session.
local function saveProfile(player: Player, release: boolean)
	local session = sessions[player]
	if not session or session.saving then
		return
	end
	session.saving = true

	local ok, err = pcall(function()
		store:UpdateAsync(session.key, function(old: Record?): Record?
			local record: Record = old or {}
			if isForeignAndFresh(record.lock) then
				-- We lost the lock to another live session; do not clobber it.
				return nil
			end
			record.data = session.data
			record.lock = if release then nil else makeLock()
			return record
		end)
	end)

	session.saving = false

	if ok then
		print(("[DataService] saved profile for %s%s"):format(player.Name, if release then " (released)" else ""))
	else
		warn(("[DataService] save FAILED for %s: %s"):format(player.Name, tostring(err)))
	end
end

-- ==================== public accessors ====================

-- True once the player's profile has finished loading.
function DataService.isLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

-- Read the live profile table for a player (nil if not loaded yet). Callers
-- should treat the result as owned by DataService and mutate only via `update`.
function DataService.get(player: Player): PlayerData?
	local session = sessions[player]
	return session and session.data or nil
end

-- Block until the player's profile is loaded (or `timeout` seconds elapse).
function DataService.waitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 10)
	while sessions[player] == nil and os.clock() < deadline do
		if player.Parent == nil then
			return nil
		end
		task.wait()
	end
	local session = sessions[player]
	return session and session.data or nil
end

-- Mutate a player's profile through a callback, then replicate the change to the
-- owning client. Returns false if the profile is not loaded. This is the single
-- sanctioned write path for other services.
function DataService.update(player: Player, mutator: (PlayerData) -> ()): boolean
	local session = sessions[player]
	if not session then
		warn(("[DataService] update ignored for %s: profile not loaded"):format(player.Name))
		return false
	end
	mutator(session.data)
	replicate(player)
	return true
end

-- Force an immediate (lock-refreshing) save for a single player.
function DataService.save(player: Player)
	saveProfile(player, false)
end

-- Save every loaded profile (used by autosave and shutdown).
function DataService.saveAll(release: boolean)
	for player in sessions do
		saveProfile(player, release)
	end
end

-- True when running against the in-memory mock (no real persistence).
function DataService.isMock(): boolean
	return usingMock
end

-- ==================== lifecycle ====================

local function onPlayerRemoving(player: Player)
	if sessions[player] then
		saveProfile(player, true)
		sessions[player] = nil
	end
end

function DataService.init(injected: any)
	deps = injected
	if deps and deps.Remotes then
		profileUpdated = deps.Remotes.getEvent("ProfileUpdated")
	end
	resolveStore()
end

function DataService.start()
	-- Load for anyone already present (Studio play-solo joins before start()).
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end

	Players.PlayerAdded:Connect(function(player)
		loadProfile(player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Periodic autosave (also refreshes each live lock so it never goes stale).
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			DataService.saveAll(false)
		end
	end)

	-- Flush + release all locks on server shutdown so profiles unlock cleanly.
	game:BindToClose(function()
		DataService.saveAll(true)
	end)
end

return DataService
