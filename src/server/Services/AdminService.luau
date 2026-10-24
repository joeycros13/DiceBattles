--!strict
-- AdminService: the admin panel's server side (user's request, 2026-10-11).
--
-- Who counts as an admin is Config/Admin (listed user ids, the place's owner,
-- anyone in a Studio playtest). Admins get the player attribute IsAdmin = true,
-- which shows the panel's button. Every request comes through the
-- Remotes.AdminAction RemoteFunction and is checked here again, so the remote
-- is useless to anyone else.
--
-- Actions ({ action = ..., ... } -> ok, message), all on the asking player:
--   coins   { amount }   add (or, negative, take) coins; the balance stays >= 0
--   exp     { amount }   add (or take) EXP; the level follows
--   level   { level }    set the level (EXP to the start of that level)
--   levelUp {}           up one level
--   give    { weapon }   add a weapon to the inventory
--   remove  { weapon }   take one away (never the starter)
--   respawn { archetype } bring every enemy of that kind back now
--   health  { amount }   set max health for this session and fill up (0 = back
--                        to the level's own max; ExpService.applyHealth)
--   heal    {}           refill health
--   material { id, amount } add (or take) a crafting material (Config/Materials)
--   armor   { id, remove? } give an armour set (Config/Armor), or take it away
--   tool    { id, remove? } give a gathering tool (Config/Tools), or take it away
--   potion  { id, amount } add (or take) potions (Config/Potions; the panel's Potions page)
--   quest   { line, step } put a questline on a step, on offer (one past the last finishes it)
--   questSkip { line }   move a questline on one step (no rewards; quest items are handed over)
--   potionsEnd {}        end every running potion
--   upgrade { id, level } set an upgrade's level (Config/Upgrades; the panel's Upgrades page)
--   upgradeAll { level } set every upgrade to one level (Max all / Reset all)
--   daily { streak, yesterday }  set the Daily Rewards streak; yesterday = the last claim was
--                        yesterday (the next claim climbs), else it's forgotten (testing)
--   lbReset { period }   pay the Weekly boards' leaderboard rewards now from this
--                        server's boards (testing; real resets need DataStores)
-- material and armor have no panel buttons yet; call them through the remote (tool is on the
-- panel's Tools page since 2026-10-19)
-- (testing the crafting, 2026-10-12).
-- Everything goes through the owning services, so it is saved like normal play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Admin = require(Config:WaitForChild("Admin"))
local Armor = require(Config:WaitForChild("Armor"))
local Materials = require(Config:WaitForChild("Materials"))
local Potions = require(Config:WaitForChild("Potions"))
local Quests = require(Config:WaitForChild("Quests"))
local Tools = require(Config:WaitForChild("Tools"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Leveling = require(Config:WaitForChild("Leveling"))

local AdminService = {}

local deps: any = nil
local Text = Admin.Text

local function commas(n: number): string
	local whole = math.floor(math.abs(n) + 0.5)
	local grouped = tostring(whole):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (if n < 0 then "-" else "+") .. (grouped:gsub("^,", ""))
end

function AdminService.isAdmin(player: Player): boolean
	if Admin.studioAlways and RunService:IsStudio() then
		return true
	end
	if table.find(Admin.userIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId and game.CreatorId ~= 0
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

-- Total EXP at the very start of `level`.
local function totalFor(level: number): number
	local total = 0
	for l = Leveling.START, level - 1 do
		total += Leveling.need(l)
	end
	return total
end

local function amountOf(request: any): number?
	local n = tonumber(request.amount)
	if not n or n ~= n then
		return nil
	end
	return math.clamp(math.floor(n + 0.5), -Admin.maxAmount, Admin.maxAmount)
end

local function plain(n: number): string
	local grouped = tostring(math.floor(math.abs(n) + 0.5)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

local function weaponOf(request: any): any
	return if type(request.weapon) == "string" then Weapons.get(request.weapon) else nil
end

local ACTIONS: { [string]: (Player, any) -> (boolean, string) } = {
	coins = function(player, request)
		local amount = amountOf(request)
		if not amount then
			return false, Text.badNumber
		end
		local CoinService = deps.Services.CoinService
		amount = math.max(amount, -CoinService.get(player))
		CoinService.add(player, amount, "admin")
		return true, Text.coinsDone:format(commas(amount))
	end,
	exp = function(player, request)
		local amount = amountOf(request)
		if not amount then
			return false, Text.badNumber
		end
		local ExpService = deps.Services.ExpService
		amount = math.max(amount, -ExpService.get(player))
		ExpService.add(player, amount)
		return true, Text.expDone:format(commas(amount))
	end,
	level = function(player, request)
		local level = tonumber(request.level)
		if not level or level ~= level then
			return false, Text.badNumber
		end
		level = math.clamp(math.floor(level), Leveling.START, 1000)
		local ExpService = deps.Services.ExpService
		ExpService.add(player, totalFor(level) - ExpService.get(player))
		return true, Text.levelDone:format(tostring(level))
	end,
	levelUp = function(player, _request)
		local ExpService = deps.Services.ExpService
		local level = Leveling.fromTotal(ExpService.get(player)) + 1
		ExpService.add(player, totalFor(level) - ExpService.get(player))
		return true, Text.levelDone:format(tostring(level))
	end,
	give = function(player, request)
		local def = weaponOf(request)
		if not def then
			return false, Text.unknown
		end
		if deps.Services.MeleeService.grant(player, def.id) then
			deps.Services.IndexService.discoverWeapon(player, def.id, true)
			return true, Text.giveDone:format(def.name)
		end
		return false, Text.giveHave:format(def.name)
	end,
	remove = function(player, request)
		local def = weaponOf(request)
		if not def then
			return false, Text.unknown
		end
		if def.starter then
			return false, Text.removeStarter:format(def.name)
		end
		if deps.Services.MeleeService.revoke(player, def.id) then
			return true, Text.removeDone:format(def.name)
		end
		return false, Text.removeMissing:format(def.name)
	end,
	health = function(player, request)
		local n = tonumber(request.amount)
		if not n or n ~= n then
			return false, Text.badNumber
		end
		n = math.clamp(math.floor(n + 0.5), 0, Admin.maxHealth)
		player:SetAttribute("MaxHealthOverride", if n > 0 then n else nil)
		local ExpService = deps.Services.ExpService
		ExpService.applyHealth(player, true)
		if n > 0 then
			return true, Text.healthDone:format(plain(n))
		end
		return true, Text.healthReset:format(plain(ExpService.maxHealth(player)))
	end,
	damage = function(player, request)
		local n = tonumber(request.amount)
		if not n or n ~= n then
			return false, Text.badNumber
		end
		n = math.clamp(n, Admin.minDamage, Admin.maxDamage)
		n = math.floor(n * 100 + 0.5) / 100
		player:SetAttribute("DamageMultiplier", if n ~= 1 then n else nil)
		if n == 1 then
			return true, Text.damageResetDone
		end
		return true, Text.damageDone:format(tostring(n))
	end,
	heal = function(player, _request)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return false, Text.healDead
		end
		humanoid.Health = humanoid.MaxHealth
		return true, Text.healDone:format(plain(humanoid.MaxHealth))
	end,
	respawn = function(_player, request)
		local def = if type(request.archetype) == "string" then Enemies.get(request.archetype) else nil
		if not def then
			return false, Text.unknown
		end
		local count = deps.Services.WorldEnemyService.respawnArchetype(def.id)
		return true, Text.respawnDone:format(count, def.name)
	end,
	material = function(player, request)
		local def = Materials.get(request.id)
		local amount = amountOf(request)
		if not def then
			return false, Text.unknown
		elseif not amount then
			return false, Text.badNumber
		end
		local MaterialService = deps.Services.MaterialService
		amount = math.max(amount, -MaterialService.get(player, def.id))
		MaterialService.add(player, def.id, amount)
		return true, Text.materialDone:format(commas(amount), def.name)
	end,
	potion = function(player, request)
		local def = Potions.get(request.id)
		local amount = amountOf(request)
		if not def then
			return false, Text.unknown
		elseif not amount then
			return false, Text.badNumber
		end
		local PotionService = deps.Services.PotionService
		amount = math.max(amount, -PotionService.get(player, def.id))
		PotionService.add(player, def.id, amount)
		return true, Text.materialDone:format(commas(amount), def.name)
	end,
	quest = function(player, request)
		local line = Quests.get(request.line)
		if not line then
			return false, Text.unknown
		elseif type(request.step) ~= "number" then
			return false, Text.badNumber
		end
		local step, done = deps.Services.QuestService.setStep(player, line.id, request.step)
		if not step then
			return false, Text.unknown
		end
		return true, if done then Text.questDone:format(line.name) else Text.questSet:format(line.name, step, #line.steps)
	end,
	questSkip = function(player, request)
		local line = Quests.get(request.line)
		local now = line and deps.Services.QuestService.stepOf(player, line.id)
		if not (line and now) then
			return false, Text.unknown
		elseif now > #line.steps then
			return false, Text.questAlreadyDone:format(line.name)
		end
		local step, done = deps.Services.QuestService.setStep(player, line.id, now + 1)
		return true, if done then Text.questDone:format(line.name) else Text.questSet:format(line.name, step :: number, #line.steps)
	end,
	potionsEnd = function(player, _request)
		deps.Services.PotionService.clearRunning(player)
		return true, Text.potionsEnded
	end,
	upgrade = function(player, request)
		local level = tonumber(request.level)
		local def = Upgrades.get(request.id)
		if not (def and level) then
			return false, Text.badNumber
		end
		deps.Services.UpgradeService.set(player, def.id, level)
		return true, Text.upgradeSet:format(def.name, Upgrades.level(player, def.id))
	end,
	upgradeAll = function(player, request)
		local level = tonumber(request.level)
		if not level then
			return false, Text.badNumber
		end
		for _, def in Upgrades.list() do
			deps.Services.UpgradeService.set(player, def.id, level)
		end
		return true, Text.upgradesAll:format(math.clamp(math.floor(level), 0, Upgrades.maxLevel()))
	end,
	-- daily { streak?, yesterday? }: set the Daily Rewards streak (testing); yesterday = true makes
	-- the last claim yesterday (so the next one climbs), else the claim is forgotten (claim today)
	daily = function(player, request)
		local service = deps.Services.DailyRewardService
		local streak = if type(request.streak) == "number" then request.streak else 0
		service.set(player, streak, if request.yesterday then service.today() - 1 else nil)
		return true, ("Daily streak %d%s"):format(streak, if request.yesterday then ", last claim yesterday" else "")
	end,
	lbReset = function(_player, request)
		if request.period ~= "Weekly" then
			return false, "Weekly only (the daily boards are gone)"
		end
		local paid = deps.Services.LeaderboardService.payLocal(request.period)
		return true, ("Paid %d %s rewards"):format(paid, request.period)
	end,
	-- Give All (user, 2026-10-12): every weapon (the Rusty Blade and every Worldheart tier at once:
	-- only possible from here), every gathering tool (2026-10-19), every armour set, and
	-- Admin.giveAllMaterials of each material (one of each core). Admins only, like every action.
	giveAll = function(player, _request)
		local MeleeService = deps.Services.MeleeService
		local IndexService = deps.Services.IndexService
		local weapons, tools, armor = 0, 0, 0
		-- the Index counts all of it, quietly (no popup per tool, fish and potion)
		IndexService.hush(player, 2)
		for id, def in Weapons.Defs do
			if not def.unarmed and MeleeService.grant(player, id) then
				IndexService.discoverWeapon(player, id, true)
				weapons += 1
			end
		end
		for id in Tools.Defs do
			if deps.Services.ToolService.grant(player, id) then
				tools += 1
			end
		end
		for _, def in Armor.list() do
			-- found quietly first, so Give All doesn't queue a popup per set
			IndexService.discoverArmor(player, def.id, true)
			if deps.Services.ArmorService.grant(player, def.id) then
				armor += 1
			end
		end
		local MaterialService = deps.Services.MaterialService
		for _, def in Materials.list() do
			local want = if def.core then 1 else Admin.giveAllMaterials
			local have = MaterialService.get(player, def.id)
			if have < want then
				MaterialService.add(player, def.id, want - have)
			end
		end
		-- and Admin.giveAllPotions of every potion, Tier III too though it has no recipe yet
		-- (user, 2026-10-19)
		local PotionService = deps.Services.PotionService
		for _, def in Potions.list() do
			local have = PotionService.get(player, def.id)
			if have < Admin.giveAllPotions then
				PotionService.add(player, def.id, Admin.giveAllPotions - have)
			end
		end
		return true, Text.giveAllDone:format(weapons, tools, armor, Admin.giveAllMaterials, Admin.giveAllPotions)
	end,
	tool = function(player, request)
		local def = Tools.get(request.id)
		if not def then
			return false, Text.unknown
		end
		local ToolService = deps.Services.ToolService
		if request.remove then
			if ToolService.revoke(player, def.id) then
				return true, Text.armorRemoved:format(def.name)
			end
			return false, Text.removeMissing:format(def.name)
		end
		if ToolService.grant(player, def.id) then
			return true, Text.armorDone:format(def.name)
		end
		return false, Text.giveHave:format(def.name)
	end,
	armor = function(player, request)
		local def = Armor.get(request.id)
		if not def then
			return false, Text.unknown
		end
		local ArmorService = deps.Services.ArmorService
		if request.remove then
			if ArmorService.revoke(player, def.id) then
				return true, Text.armorRemoved:format(def.name)
			end
			return false, Text.removeMissing:format(def.name)
		end
		if ArmorService.grant(player, def.id) then
			return true, Text.armorDone:format(def.name)
		end
		return false, Text.giveHave:format(def.name)
	end,
}

local function handle(player: Player, request: any): (boolean, string)
	if not AdminService.isAdmin(player) then
		return false, Text.notAdmin
	end
	local action = type(request) == "table" and ACTIONS[request.action]
	if not action then
		return false, Text.unknown
	end
	local ok, success, message = pcall(action, player, request)
	if not ok then
		warn("[AdminService] " .. tostring(success))
		return false, Text.unknown
	end
	print(("[AdminService] %s: %s -> %s"):format(player.Name, tostring(request.action), message))
	return success, message
end

function AdminService.init(injected: any)
	deps = injected
end

function AdminService.start()
	deps.Remotes.getFunction("AdminAction").OnServerInvoke = handle
	local function onPlayer(player: Player)
		player:SetAttribute("IsAdmin", AdminService.isAdmin(player))
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return AdminService
