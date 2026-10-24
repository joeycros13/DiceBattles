--!strict
-- SettingsService: each player's own settings (Config/Settings; 2026-10-22, the
-- Settings panel). Saved as the "settings" section of PlayerDataService, { [id] = value }
-- holding only what differs from the default, and published as "Setting_<id>" player
-- attributes (every setting, defaults too, so the client never guesses).
--
-- Remotes.SetSetting(id, value): the Settings panel changing one. The value is checked
-- against its def (Settings.clean) and anything else is ignored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Settings"))

local SettingsService = {}

local deps: any = nil

local function publish(player: Player, values: { [string]: any })
	for _, def in Settings.list() do
		local value = values[def.id]
		player:SetAttribute(Settings.attr(def.id), if value ~= nil then value else def.default)
	end
end

function SettingsService.set(player: Player, id: any, value: any)
	local def = Settings.get(id)
	local clean = def and Settings.clean(def, value)
	if def and clean ~= nil then
		player:SetAttribute(Settings.attr(def.id), clean)
	end
end

function SettingsService.init(injected: any)
	deps = injected
	deps.Services.PlayerDataService.register("settings", {
		load = function(player: Player, value: any)
			local values = {}
			if type(value) == "table" then
				for id, v in value do
					local def = Settings.get(id)
					local clean = def and Settings.clean(def, v)
					if clean ~= nil then
						values[id] = clean
					end
				end
			end
			publish(player, values)
		end,
		save = function(player: Player): any
			local values = {}
			for _, def in Settings.list() do
				local value = Settings.value(player, def.id)
				if value ~= def.default then
					values[def.id] = value
				end
			end
			return values
		end,
	})
end

function SettingsService.start()
	deps.Remotes.getEvent("SetSetting").OnServerEvent:Connect(function(player: Player, id: any, value: any)
		SettingsService.set(player, id, value)
	end)
	local function onPlayer(player: Player)
		-- a player without a save yet still gets every attribute (the defaults)
		if player:GetAttribute(Settings.attr("Music")) == nil then
			publish(player, {})
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return SettingsService
