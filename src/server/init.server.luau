--!strict
-- Server bootstrap: creates remotes, then loads and starts all services in
-- dependency order via the shared Loader.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared:WaitForChild("Loader"))
local Remotes = require(Shared:WaitForChild("Remotes"))

-- Services must init/start in this dependency order.
local SERVICE_ORDER = {
	"DataService",
	"CurrencyService",
	"InventoryService",
	"TalentService",
	"GlobalLevelService",
	"CombatService",
	"ChestService",
	"ShopService",
	"LeaderboardService",
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
