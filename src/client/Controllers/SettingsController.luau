--!strict
-- SettingsController: applies the player's settings (Config/Settings) on this client
-- (2026-10-22, the Settings panel). It follows the "Setting_<id>" player attributes
-- SettingsService publishes:
--   volumes     each SoundService SoundGroup's Volume = its BaseVolume attribute (the
--               game's own mix) x the setting: Music, Ambience, Effects (the hit, pop,
--               footstep and secret sounds), UI (Util.UiSound)
--   Guide       the guide arrow (GuideController); the tracker's Guide button changes
--               this setting too, so the two always agree
--   Particles   every ParticleEmitter in a world's Ambience folder (petals, butterflies,
--               fireflies, the waterfall mist...) is switched off, and back on to what it
--               was; gameplay bursts (Animation.Effects) are never touched
--   Shadows     Lighting.GlobalShadows
-- Hits (Util.BonkPop) and SprintZoom (SprintController) are read where they're used,
-- through Settings.on.
--
-- SettingsController.set(id, value, final?) is how the panel changes one: it takes
-- effect at once (the attribute is set here first) and is sent to the server
-- (Remotes.SetSetting) at most every SEND_EVERY seconds while a slider is dragged, and
-- always when `final` is true.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Settings"))

local SettingsController = {}

local SEND_EVERY = 0.25
local player = Players.LocalPlayer

local deps: any = nil
local remote: RemoteEvent? = nil
local lastSent: { [string]: number } = {}
local pending: { [string]: any } = {}
-- emitters switched off by the Particles setting, with whether each was on before
local emitters: { [ParticleEmitter]: boolean } = {}

local function applyVolume(def: Settings.SettingDef)
	local group = def.group and SoundService:FindFirstChild(def.group)
	if group and group:IsA("SoundGroup") then
		local base = group:GetAttribute("BaseVolume")
		if type(base) ~= "number" then
			base = group.Volume
			group:SetAttribute("BaseVolume", base)
		end
		group.Volume = (base :: number) * (Settings.value(player, def.id) :: number)
	end
end

local function ambienceEmitters(): { ParticleEmitter }
	local found = {}
	local worlds = Workspace:FindFirstChild("Worlds")
	for _, world in if worlds then worlds:GetChildren() else {} do
		local ambience = world:FindFirstChild("Ambience")
		for _, d in if ambience then ambience:GetDescendants() else {} do
			if d:IsA("ParticleEmitter") then
				table.insert(found, d)
			end
		end
	end
	return found
end

local function applyParticles()
	local on = Settings.on(player, "Particles")
	if on then
		for emitter, was in emitters do
			emitter.Enabled = was
		end
		table.clear(emitters)
	else
		for _, emitter in ambienceEmitters() do
			if emitters[emitter] == nil then
				emitters[emitter] = emitter.Enabled
			end
			emitter.Enabled = false
			emitter:Clear()
		end
	end
end

local function apply(id: string)
	local def = Settings.get(id)
	if not def then
		return
	end
	if def.kind == "volume" then
		applyVolume(def)
	elseif id == "Guide" then
		local Guide = deps.Controllers.GuideController
		if Guide and Guide.isEnabled() ~= Settings.on(player, id) then
			Guide.setEnabled(Settings.on(player, id))
		end
	elseif id == "Particles" then
		applyParticles()
	elseif id == "Shadows" then
		Lighting.GlobalShadows = Settings.on(player, id)
	end
end

local function send(id: string)
	local value = pending[id]
	if value ~= nil and remote then
		pending[id] = nil
		lastSent[id] = os.clock()
		remote:FireServer(id, value)
	end
end

-- Change a setting from this client (the Settings panel).
function SettingsController.set(id: string, value: any, final: boolean?)
	local def = Settings.get(id)
	local clean = def and Settings.clean(def, value)
	if clean == nil then
		return
	end
	player:SetAttribute(Settings.attr(id), clean)
	pending[id] = clean
	local since = os.clock() - (lastSent[id] or 0)
	if final or since >= SEND_EVERY then
		send(id)
	else
		task.delay(SEND_EVERY - since, function()
			send(id)
		end)
	end
end

function SettingsController.init(injected: any)
	deps = injected
end

function SettingsController.start()
	remote = deps.Remotes.getEvent("SetSetting")
	for _, def in Settings.list() do
		player:GetAttributeChangedSignal(Settings.attr(def.id)):Connect(function()
			apply(def.id)
		end)
		apply(def.id)
	end
	-- the tracker's Guide button is the same setting
	local Guide = deps.Controllers.GuideController
	if Guide then
		Guide.onChanged(function(on: boolean)
			if Settings.on(player, "Guide") ~= on then
				SettingsController.set("Guide", on, true)
			end
		end)
	end
end

return SettingsController
