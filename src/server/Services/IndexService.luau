--!strict
-- IndexService: each player's Index (bestiary and weapon book) -- which enemies
-- they have defeated, how often, and which weapons they have found -- plus the
-- weapon drops that fill it.
--
--   * Kills: WorldEnemyService.onDefeated tells us who beat what. The first kill
--     of a kind discovers that enemy.
--   * Drops: every kill rolls the enemy's drop table (Config/Worlds, each entry
--     on its own). A drop the player doesn't own is granted (MeleeService.grant);
--     the first time a weapon is ever found it is discovered. Every chance is
--     multiplied by the killer's "LuckBoost" attribute (passes and timed
--     boosts, ShopService; they multiply together), capped at 100%.
--   * Every discovery fires Remotes.IndexDiscovered { kind, id } to that player
--     for the NEW popup. Starter weapons are discovered quietly.
--   * Armour (user, 2026-10-13): a set is found the first time the player gets
--     it (crafting it, ArmorService.grant). Its first find shows the NEW popup
--     (kind "Armor"); sets owned before this existed are added quietly on join.
--   * Items (2026-10-20, the whole book): every tool, material, fish, potion and quest item
--     the player gets is counted -- rises of the "Materials", "Potions" and "OwnedTools"
--     attributes (MaterialService, PotionService, ToolService), after the player's data has
--     loaded (what they held then is found quietly). The first find of a tool, fish, potion,
--     quest item or Rare-or-better material shows the NEW popup (kind "Item"); common
--     materials only get their side toast. Cores are never counted (secret).
--   * Titles (Title 2 on the Index Expansion canvas): a world whose every page is filled
--     (Index.progress) earns its Collector title; with that and the world's core infused into
--     the Worldheart Blade (Index.coreDone) its Completionist title. Earned titles are kept
--     even if the world gains new entries later. The first earn shows the popup (kind
--     "Title"). One title is worn at a time (Remotes.EquipTitle(id), or "" to take it off);
--     ChatTagController shows it in chat.
--   * State reaches the client as player attributes: "IndexKills"
--     ("Chicken=3,Bull=1"), "IndexWeapons" ("Dagger,Sickle"), "IndexArmor"
--     ("FarmhandsGear,HarvestKnight"), "IndexItems" ("OakLog=128,WoodenAxe=1"),
--     "Titles" ("Collector1") and "Title" (the one worn, or nil).
--
-- Saving: the Index is saved permanently (the user's call, 2026-10-07; the one
-- piece of save data in the game). DataStore "Index", key "u_<UserId>":
-- { v = 1, kills = { [enemyId] = n }, weapons = { [weaponId] = true },
--   armor = { [armorId] = true }, items = { [itemId] = n }, titles = { [titleId] = true },
--   title = titleId? }.
-- Loaded on join, saved every AUTOSAVE seconds when changed, on leave and on
-- shutdown. Saves merge with what is stored (higher counts, union of weapons),
-- so a second server can never wipe progress. When DataStores are unavailable
-- (an unpublished place, or Studio without API access) the Index still works
-- for the session and warns once.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Weapons = require(Config:WaitForChild("Weapons"))
local Index = require(Config:WaitForChild("Index"))
local Armor = require(Config:WaitForChild("Armor"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Bonuses = require(Config:WaitForChild("Bonuses"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Materials = require(Config:WaitForChild("Materials"))
local Potions = require(Config:WaitForChild("Potions"))
local Tools = require(Config:WaitForChild("Tools"))

local IndexService = {}

local STORE_NAME = "Index"
local VERSION = 1
local AUTOSAVE = 120
local RETRIES = 3

type Profile = {
	kills: { [string]: number },
	weapons: { [string]: boolean },
	armor: { [string]: boolean },
	items: { [string]: number },
	titles: { [string]: boolean },
	title: string?,
	-- what the player held at the last look, per attribute (nil until their data loaded)
	held: { [string]: { [string]: number } }?,
	hushUntil: number, -- os.clock() until which item finds don't pop up (admin Give All)
	dirty: boolean,
	loaded: boolean, -- false: nothing stored was read, so never write over it
}

local deps: any = nil
local MeleeService: any = nil
local discovered: RemoteEvent? = nil
local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local random = Random.new()
-- defined with the titles, below; the discoveries above it call it
local updateTitles: (player: Player, profile: Profile, quiet: boolean?) -> ()

-- ==================== saving ====================

local function keyOf(player: Player): string
	return "u_" .. player.UserId
end

local function retry<T>(fn: () -> T): (boolean, T | string)
	local ok, result = false, nil :: any
	for attempt = 1, RETRIES do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(attempt)
	end
	return false, result
end

local function load(player: Player, profile: Profile)
	local ds = store
	if not ds then
		return
	end
	-- The first read tells us whether DataStores work here at all: an
	-- unpublished place or Studio without API access fails at once, and
	-- retrying won't help.
	local firstOk, firstData = pcall(function()
		return ds:GetAsync(keyOf(player))
	end)
	local ok, data = firstOk, firstData
	if not firstOk then
		local message = tostring(firstData)
		if message:find("publish") or message:find("API") or message:find("Studio") then
			store = nil
			warn("[IndexService] DataStores unavailable (publish the place and turn on Studio API access to save); the Index lasts this session only: " .. message)
			return
		end
		ok, data = retry(function()
			return ds:GetAsync(keyOf(player))
		end)
	end
	if not ok then
		warn(("[IndexService] couldn't load %s's Index (%s); it won't be saved this session"):format(player.Name, tostring(data)))
		return
	end
	if type(data) == "table" then
		for id, n in (data :: any).kills or {} do
			if type(n) == "number" then
				profile.kills[id] = (profile.kills[id] or 0) + n
			end
		end
		for id, v in (data :: any).weapons or {} do
			if v == true then
				profile.weapons[id] = true
			end
		end
		for id, v in (data :: any).armor or {} do
			if v == true then
				profile.armor[id] = true
			end
		end
		for id, n in (data :: any).items or {} do
			if type(n) == "number" then
				profile.items[id] = math.max(profile.items[id] or 0, n)
			end
		end
		for id, v in (data :: any).titles or {} do
			if v == true then
				profile.titles[id] = true
			end
		end
		if type((data :: any).title) == "string" then
			profile.title = (data :: any).title
		end
	end
	profile.loaded = true
end

local function save(player: Player, profile: Profile)
	local ds = store
	if not (ds and profile.loaded and profile.dirty) then
		return
	end
	profile.dirty = false
	local ok, err = retry(function()
		return ds:UpdateAsync(keyOf(player), function(old: any)
			local kills = table.clone(profile.kills)
			local weapons = table.clone(profile.weapons)
			local armor = table.clone(profile.armor)
			local items = table.clone(profile.items)
			local titles = table.clone(profile.titles)
			if type(old) == "table" then
				for id, n in old.kills or {} do
					kills[id] = math.max(kills[id] or 0, n)
				end
				for id, v in old.weapons or {} do
					weapons[id] = weapons[id] or v
				end
				for id, v in old.armor or {} do
					armor[id] = armor[id] or v
				end
				for id, n in old.items or {} do
					items[id] = math.max(items[id] or 0, n)
				end
				for id, v in old.titles or {} do
					titles[id] = titles[id] or v
				end
			end
			return { v = VERSION, kills = kills, weapons = weapons, armor = armor, items = items, titles = titles, title = profile.title }
		end)
	end)
	if not ok then
		profile.dirty = true
		warn(("[IndexService] couldn't save %s's Index: %s"):format(player.Name, tostring(err)))
	end
end

-- ==================== state ====================

local function publish(player: Player, profile: Profile)
	local kills = {}
	for id, n in profile.kills do
		table.insert(kills, id .. "=" .. n)
	end
	table.sort(kills)
	local weapons = {}
	for id in profile.weapons do
		table.insert(weapons, id)
	end
	table.sort(weapons)
	player:SetAttribute("IndexKills", table.concat(kills, ","))
	player:SetAttribute("IndexWeapons", table.concat(weapons, ","))
	local armor = {}
	for id in profile.armor do
		table.insert(armor, id)
	end
	table.sort(armor)
	player:SetAttribute("IndexArmor", table.concat(armor, ","))
	local items = {}
	for id, n in profile.items do
		table.insert(items, id .. "=" .. n)
	end
	table.sort(items)
	player:SetAttribute("IndexItems", table.concat(items, ","))
	local titles = {}
	for id in profile.titles do
		table.insert(titles, id)
	end
	table.sort(titles)
	player:SetAttribute("Titles", table.concat(titles, ","))
	player:SetAttribute("Title", if profile.title and profile.titles[profile.title] then profile.title else nil)
end

-- `again`: a weapon the player found before, lost and got back -- the popup
-- plays without its NEW tag (user, 2026-10-11).
local function announce(player: Player, kind: string, id: string, again: boolean?)
	if discovered then
		discovered:FireClient(player, { kind = kind, id = id, again = again == true })
	end
end

-- Mark a weapon found. Returns true (and shows the popup unless `quiet`) the
-- first time.
function IndexService.discoverWeapon(player: Player, id: string, quiet: boolean?): boolean
	local profile = profiles[player]
	if not profile or profile.weapons[id] or not Weapons.get(id) then
		return false
	end
	profile.weapons[id] = true
	profile.dirty = true
	publish(player, profile)
	if not quiet then
		announce(player, "Weapon", id)
	end
	if profile.held then
		updateTitles(player, profile)
	end
	return true
end

-- Mark an armour set found (ArmorService.grant, when the player first gets it).
-- Returns true (and shows the popup unless `quiet`) the first time.
function IndexService.discoverArmor(player: Player, id: string, quiet: boolean?): boolean
	local profile = profiles[player]
	if not profile or profile.armor[id] or not Armor.get(id) then
		return false
	end
	profile.armor[id] = true
	profile.dirty = true
	publish(player, profile)
	if not quiet then
		announce(player, "Armor", id)
	end
	if profile.held then
		updateTitles(player, profile)
	end
	return true
end

-- A weapon handed over as a reward (Dale's last quest): discovered as usual,
-- and the popup shows even if the Index already had it, so a reward is always
-- announced across the top of the screen.
function IndexService.showWeapon(player: Player, id: string)
	if not IndexService.discoverWeapon(player, id) and Weapons.get(id) then
		announce(player, "Weapon", id, true)
	end
end

-- ==================== titles ====================

-- Earn every title the player now qualifies for (kept once earned). `quiet`: no popup
-- (the check on join).
updateTitles = function(player: Player, profile: Profile, quiet: boolean?)
	local progress = Index.progressOf(player)
	local changed = false
	for _, worldId in Worlds.Order do
		local collector, completionist = Index.titlesOf(worldId)
		if not (collector and completionist) then
			continue
		end
		if not profile.titles[collector.id] then
			local p = Index.progress(worldId, progress)
			if p.total > 0 and p.found >= p.total then
				profile.titles[collector.id] = true
				changed = true
				if not quiet then
					announce(player, "Title", collector.id)
				end
			end
		end
		if profile.titles[collector.id] and not profile.titles[completionist.id] and Index.coreDone(player, worldId) then
			profile.titles[completionist.id] = true
			changed = true
			if not quiet then
				announce(player, "Title", completionist.id)
			end
		end
	end
	if changed then
		profile.dirty = true
		publish(player, profile)
	end
end

-- Wear an earned title, or take it off ("" / nil).
local function equipTitle(player: Player, id: any)
	local profile = profiles[player]
	if not profile then
		return
	end
	if id == nil or id == "" then
		profile.title = nil
	elseif type(id) == "string" and profile.titles[id] and Index.titleOf(id) then
		profile.title = id
	else
		return
	end
	profile.dirty = true
	publish(player, profile)
end

-- ==================== items ====================

-- No item popups for the next `seconds` (admin Give All hands out dozens at once; the
-- attribute changes it causes arrive a moment later).
function IndexService.hush(player: Player, seconds: number)
	local profile = profiles[player]
	if profile then
		profile.hushUntil = os.clock() + seconds
	end
end

-- The first find of these shows the NEW popup; common materials only get their toast.
local function announces(id: string): boolean
	local section = Index.sectionOf(id)
	if section == "Materials" then
		local def = Materials.get(id)
		return def ~= nil and Index.rarityRank(def.rarity) >= Index.rarityRank("Rare")
	end
	return section ~= nil
end

-- Count `amount` more of an item; the first find of a listed one may pop up.
local function gained(player: Player, profile: Profile, id: string, amount: number, quiet: boolean)
	local def = Index.itemDef(id)
	if amount <= 0 or not def or def.core then
		return
	end
	local first = (profile.items[id] or 0) <= 0
	profile.items[id] = (profile.items[id] or 0) + amount
	profile.dirty = true
	if first and not quiet and os.clock() >= profile.hushUntil and announces(id) then
		announce(player, "Item", id)
	end
end

-- What the player holds now, per watched attribute.
local WATCHED = { "Materials", "Potions", "OwnedTools" }
local function holding(player: Player, name: string): { [string]: number }
	if name == "Materials" then
		return Materials.counts(player)
	elseif name == "Potions" then
		return Potions.counts(player)
	end
	local out: { [string]: number } = {}
	for id in Tools.owned(player) do
		out[id] = 1
	end
	return out
end

-- Compare what is held with the last look: every rise is counted. `quiet` on the first
-- look, which only marks what is already held as found.
local function look(player: Player, profile: Profile, name: string, quiet: boolean)
	local held = profile.held :: { [string]: { [string]: number } }
	local before = held[name] or {}
	local now = holding(player, name)
	for id, n in now do
		if quiet then
			if (profile.items[id] or 0) < n and Index.itemDef(id) and not (Index.itemDef(id) :: any).core then
				profile.items[id] = math.max(profile.items[id] or 0, n)
				profile.dirty = true
			end
		else
			gained(player, profile, id, n - (before[id] or 0), false)
		end
	end
	held[name] = now
end

-- Start counting once the player's data (materials, potions, tools) has loaded.
local function watchItems(player: Player, profile: Profile)
	if not player:GetAttribute("DataLoaded") then
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	if profiles[player] ~= profile then
		return
	end
	profile.held = {}
	for _, name in WATCHED do
		look(player, profile, name, true)
		player:GetAttributeChangedSignal(name):Connect(function()
			if profiles[player] == profile then
				look(player, profile, name, false)
				publish(player, profile)
				updateTitles(player, profile)
			end
		end)
	end
	player:GetAttributeChangedSignal("InfusedCores"):Connect(function()
		if profiles[player] == profile then
			updateTitles(player, profile)
		end
	end)
	publish(player, profile)
	updateTitles(player, profile, true)
end

local function onKill(enemy: any, killer: Player?)
	local profile = killer and profiles[killer]
	if not (killer and profile) then
		return
	end
	local id: string = enemy.archetype
	local first = profile.kills[id] == nil
	profile.kills[id] = (profile.kills[id] or 0) + 1
	profile.dirty = true
	publish(killer, profile)
	if first and not Index.isSecret(id) then -- secret enemies never pop up in the Index
		announce(killer, "Enemy", id)
		if profile.held then
			updateTitles(killer, profile)
		end
	end
	-- passes, boosts and the Luck upgrade, added (Config/Bonuses)
	local luck = Bonuses.luck(killer)
	for _, drop in Index.dropsOf(id) do
		if random:NextNumber() < math.min(1, drop.chance * luck) and MeleeService.grant(killer, drop.weapon) then
			-- the first find is NEW; one already in the Index (sold or removed, now
			-- back) still pops up, just without the NEW tag
			IndexService.showWeapon(killer, drop.weapon)
		end
	end
end

local function onPlayer(player: Player)
	local profile: Profile = { kills = {}, weapons = {}, armor = {}, items = {}, titles = {}, title = nil, held = nil, hushUntil = 0, dirty = false, loaded = false }
	profiles[player] = profile
	load(player, profile)
	if profiles[player] ~= profile then
		return -- left while loading
	end
	for _, def in Weapons.list() do
		if def.starter then
			profile.weapons[def.id] = profile.weapons[def.id] or true
		end
	end
	-- armour owned before the Index tracked it counts as found (no popup)
	local ArmorService = deps.Services.ArmorService
	for _, def in Armor.list() do
		if ArmorService and ArmorService.owns(player, def.id) and not profile.armor[def.id] then
			profile.armor[def.id] = true
			profile.dirty = true
		end
	end
	publish(player, profile)
	watchItems(player, profile)
end

-- ==================== lifecycle ====================

function IndexService.init(injected: any)
	deps = injected
	MeleeService = deps.Services.MeleeService
	discovered = deps.Remotes.getEvent("IndexDiscovered")
	deps.Remotes.getEvent("EquipTitle").OnServerEvent:Connect(equipTitle)
end

function IndexService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[IndexService] DataStores unavailable (publish the place and turn on Studio API access to save); the Index lasts this session only: " .. tostring(result))
	end

	deps.Services.WorldEnemyService.onDefeated(onKill)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			save(player, profile)
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				save(player, profile)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for player, profile in profiles do
				task.spawn(save, player, profile)
			end
		end
	end)
end

return IndexService
