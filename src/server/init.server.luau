--!strict
-- Server bootstrap: creates remotes, then loads and starts all services in
-- dependency order via the shared Loader.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared:WaitForChild("Loader"))
local Remotes = require(Shared:WaitForChild("Remotes"))

-- Services must init/start in this dependency order.
local SERVICE_ORDER = {
	-- first: every other service registers its saved section with it in init
	"PlayerDataService",
	"WorldEnemyService",
	"AvatarService",
	"MeleeService",
	"IndexService",
	"CoinService",
	"ExpService",
	-- crafting materials: drops on kills, quest items for QuestService
	"MaterialService",
	-- armour sets: bonus HP through ExpService
	"ArmorService",
	-- gathering tools owned (axes, pickaxes...); MeleeService holds them
	"ToolService",
	-- after CoinService / ExpService / MaterialService: it pays rewards through them
	"QuestService",
	-- world gates: spends coins and unlocks worlds through the services above
	"GateService",
	-- the Robux shop: grants coins and weapons through the services above
	"ShopService",
	-- the Crafting and Weapons stalls: crafting armour and buying weapons
	"StallService",
	-- potions: brewed at the Crafters (StallService), timers stamped by ShopService
	"PotionService",
	-- stat upgrades at the World 1 Upgrades stand: coins through CoinService, health through ExpService
	"UpgradeService",
	-- the 9 leaderboards and their reset rewards (coins, EXP, potions, boosts, materials through the services above)
	"LeaderboardService",
	-- the Daily Rewards stand and promo codes (Config/DailyRewards), rewards through the services above
	"DailyRewardService",
	-- selling from the Inventory: takes items through the services above, pays through CoinService
	"SellService",
	-- the admin panel: coins, EXP, levels, weapons and respawns through the services above
	"AdminService",
	-- walk-in teleport zones (the secret rooms' entrances and exits)
	"PortalService",
	-- the Infusers: cores into the Rusty / Worldheart Blade through MaterialService and MeleeService
	"InfuseService",
	-- World 3's secret crystal code: opens the front mineshaft for whoever solves it
	"SecretService",
	-- trees and rocks to break for materials, through MaterialService
	"GatherService",
	-- casting a rod for fish (Config/Fishing), through ToolService and MaterialService
	"FishingService",
	-- the healing fountain: walk-in zones that heal to full on a cooldown
	"HealZoneService",
	-- the player's own settings (volumes, toggles; Config/Settings), saved with everything else
	"SettingsService",
}

print("[Server] bootstrap starting")

-- Create RemoteEvents/RemoteFunctions before any service wires handlers.
Remotes.init()

local services = Loader.requireChildren(script:WaitForChild("Services"))

local deps = {
	Remotes = Remotes,
	Services = services,
}

Loader.initModules(services, deps, SERVICE_ORDER)
Loader.startModules(services, SERVICE_ORDER)

print("[Server] bootstrap complete")
