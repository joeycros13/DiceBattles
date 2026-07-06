--!strict
-- Client bootstrap: loads util, controllers, and UI, then inits/starts them in
-- dependency order via the shared Loader (util -> controllers -> UI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared:WaitForChild("Loader"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UTIL_ORDER = {
	"Responsive",
	"AssetResolver",
	"UIFactory",
}

local CONTROLLER_ORDER = {
	"DataController",
	"CombatController",
}

local UI_ORDER = {
	"MenuShell",
	"EquipmentTab",
	"BattleTab",
	"TalentsTab",
	"CombatUI",
}

print("[Client] bootstrap starting")

local util = Loader.requireChildren(script:WaitForChild("Util"))
local controllers = Loader.requireChildren(script:WaitForChild("Controllers"))
local ui = Loader.requireChildren(script:WaitForChild("UI"))

local deps = {
	Remotes = Remotes,
	Util = util,
	Controllers = controllers,
	UI = ui,
}

-- Init in dependency order: util first, then controllers, then UI.
Loader.initModules(util, deps, UTIL_ORDER)
Loader.initModules(controllers, deps, CONTROLLER_ORDER)
Loader.initModules(ui, deps, UI_ORDER)

Loader.startModules(util, UTIL_ORDER)
Loader.startModules(controllers, CONTROLLER_ORDER)
Loader.startModules(ui, UI_ORDER)

print("[Client] bootstrap complete")
