--!strict
-- UpgradeService: the stat upgrades bought at World 1's Upgrades stand
-- (Config/Upgrades; 2026-10-19, the user's design).
--
-- Each player's levels are saved as the "upgrades" section of PlayerDataService,
-- { [id] = level }, and published as "Upgrade_<id>" player attributes, which the
-- systems that own each stat read through Upgrades.value (SprintController,
-- MeleeService, ExpService, CoinService, IndexService, MaterialService,
-- GatherService, WeaponController). This service also owns the Regen upgrade's
-- healing: Roblox's own Health script keeps its 1% a second, and every second
-- this adds the upgrade's extra share of max health.
--
-- Remotes.BuyUpgrade(id) -> (ok, reason): at the Upgrades stand (StallService.atStall,
-- Station "Upgrades"), below the player's cap (3 levels per world unlocked,
-- HighestWorld) and with the coins.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Upgrades"))
local Potions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Potions"))

local UpgradeService = {}

local STATION = "Upgrades"
local REGEN_STEP = 1

local deps: any = nil

local function publish(player: Player, levels: { [string]: number })
	for _, def in Upgrades.list() do
		player:SetAttribute(Upgrades.attr(def.id), levels[def.id] or 0)
	end
end

local function levelsOf(player: Player): { [string]: number }
	local levels = {}
	for _, def in Upgrades.list() do
		local level = Upgrades.level(player, def.id)
		if level > 0 then
			levels[def.id] = level
		end
	end
	return levels
end

local function highestWorld(player: Player): number
	local value = player:GetAttribute("HighestWorld")
	return if type(value) == "number" then value else 1
end

-- Why `player` can't buy the next level of `def` now, or nil if they can.
function UpgradeService.blocker(player: Player, def: Upgrades.UpgradeDef): string?
	local level = Upgrades.level(player, def.id)
	if level >= Upgrades.maxLevel() then
		return "maxed"
	elseif level >= Upgrades.cap(highestWorld(player)) then
		return "capped"
	elseif not deps.Services.StallService.atStall(player, STATION) then
		return "away"
	elseif deps.Services.CoinService.get(player) < Upgrades.cost(def, level + 1) then
		return "coins"
	end
	return nil
end

function UpgradeService.buy(player: Player, id: any): (boolean, string?)
	local def = Upgrades.get(id)
	if not def then
		return false, "unknown"
	end
	local why = UpgradeService.blocker(player, def)
	if why then
		return false, why
	end
	local level = Upgrades.level(player, def.id) + 1
	deps.Services.CoinService.add(player, -Upgrades.cost(def, level))
	player:SetAttribute(Upgrades.attr(def.id), level)
	return true, nil
end

-- An admin setting a level directly (AdminService), clamped to 0..max.
function UpgradeService.set(player: Player, id: string, level: number)
	if Upgrades.get(id) then
		player:SetAttribute(Upgrades.attr(id), math.clamp(math.floor(level), 0, Upgrades.maxLevel()))
	end
end

function UpgradeService.init(injected: any)
	deps = injected
	deps.Services.PlayerDataService.register("upgrades", {
		load = function(player: Player, value: any)
			local levels = {}
			if type(value) == "table" then
				for id, level in value do
					if Upgrades.get(id) and type(level) == "number" then
						levels[id] = math.clamp(math.floor(level), 0, Upgrades.maxLevel())
					end
				end
			end
			publish(player, levels)
		end,
		save = function(player: Player): any
			return levelsOf(player)
		end,
	})
end

function UpgradeService.start()
	deps.Remotes.getFunction("BuyUpgrade").OnServerInvoke = function(player: Player, id: any)
		return UpgradeService.buy(player, id)
	end
	local function onPlayer(player: Player)
		-- a player without a save yet still gets every attribute (all 0)
		if player:GetAttribute(Upgrades.attr("Sprint")) == nil then
			publish(player, {})
		end
		-- however the Health level changes (a buy, a save loading, an admin), max HP follows
		player:GetAttributeChangedSignal(Upgrades.attr("Health")):Connect(function()
			deps.Services.ExpService.applyHealth(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	-- Regen: the upgrade's extra share of max health every second, plus a running Regen
	-- potion's (Config/Potions, 2026-10-20) and the worn armour's (Config/Armor, 2026-10-22)
	task.spawn(function()
		while true do
			task.wait(REGEN_STEP)
			for _, player in Players:GetPlayers() do
				local armour = player:GetAttribute("ArmorRegen")
				local extra = Upgrades.value(player, "Regen") + Potions.power(player, "Regen")
					+ (if type(armour) == "number" then armour else 0)
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if extra > 0 and humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * extra * REGEN_STEP)
				end
			end
		end
	end)
end

return UpgradeService
