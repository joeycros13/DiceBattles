--!strict
-- SettingsUI: the Settings panel (2026-10-22, layout A "Sectioned list" on
-- https://claude.ai/artifact/QCU1fmrygg133qdZJxWcHh), opened from the HUD's gear,
-- WeaponHud/SideButtons/SettingsButton. The settings and their words are Config/Settings;
-- SettingsController applies them and sends them to the server.
--
-- Hand-built StarterGui/SettingsPanel (Panel = "Settings"; the Stats panel's window):
--   Window/Title, Close, Reset (the gold pill: every setting back to its default)
--   Window/List          a ScrollingFrame; its rows are placed by hand as shares of the
--                        canvas, whose height is the list's width x its CanvasRatio attribute
--     Header_<section>   the Sound / Gameplay / Graphics pills
--     Row_<id>           Icon, SettingName, Note, and one of:
--       Slider           Track (Fill, Knob), Hit (the drag area), Value (ValueFormat "%d%%")
--       Switch           a pill button: Skin, Label, Knob; attributes SkinOn / SkinOff,
--                        TextOn / TextOff, KnobOnX / KnobOffX, LabelOnX / LabelOffX
--     Note               "Saved to your account automatically"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Settings"))

local SettingsUI = {}

local PANEL = "Settings"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local deps: any = nil
local PanelWindow: any = nil
local window: any = nil
local renders: { [string]: () -> () } = {}

local function controller(): any
	return deps.Controllers.SettingsController
end

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function wireSlider(def: Settings.SettingDef, slider: any)
	local track, hit = slider.Track, slider.Hit
	local dragging = false
	renders[def.id] = function()
		local v = Settings.value(player, def.id) :: number
		track.Fill.Size = UDim2.fromScale(v, 1)
		track.Knob.Position = UDim2.fromScale(v, 0.5)
		slider.Value.Text = string.format(attribute(slider, "ValueFormat", "%d%%"), math.floor(v * 100 + 0.5))
	end
	local function valueAt(x: number): number
		local width = track.AbsoluteSize.X
		return if width > 0 then math.clamp((x - track.AbsolutePosition.X) / width, 0, 1) else 0
	end
	hit.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = true
			controller().set(def.id, valueAt(input.Position.X))
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if dragging and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch) then
			controller().set(def.id, valueAt(input.Position.X))
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if dragging and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			dragging = false
			controller().set(def.id, valueAt(input.Position.X), true)
		end
	end)
end

local function wireSwitch(def: Settings.SettingDef, switch: any)
	renders[def.id] = function()
		local on = Settings.on(player, def.id)
		local state = if on then "On" else "Off"
		switch.Skin.Image = attribute(switch, "Skin" .. state, switch.Skin.Image)
		switch.Label.Text = attribute(switch, "Text" .. state, state)
		switch.Label.Position = UDim2.fromScale(attribute(switch, "Label" .. state .. "X", 0.5), switch.Label.Position.Y.Scale)
		switch.Knob.Position = UDim2.fromScale(attribute(switch, "Knob" .. state .. "X", 0.5), switch.Knob.Position.Y.Scale)
	end
	switch.Activated:Connect(function()
		controller().set(def.id, not Settings.on(player, def.id), true)
	end)
end

local function fitCanvas()
	local list = window.List
	local ratio = attribute(list, "CanvasRatio", 1)
	list.CanvasSize = UDim2.fromOffset(0, math.floor(list.AbsoluteSize.X * ratio + 0.5))
end

function SettingsUI.toggle()
	if PanelWindow.isPanelOpen(PANEL) then
		PanelWindow.hidePanel()
	else
		PanelWindow.showPanel(PANEL)
	end
end

function SettingsUI.init(injected: any)
	deps = injected
	PanelWindow = injected.UI.PanelWindow
end

function SettingsUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL, GUI_TIMEOUT)
		if not found then
			warn("[SettingsUI] no Settings panel (StarterGui/SettingsPanel)")
			return
		end
		window = found:WaitForChild("Window")
		for _, def in Settings.list() do
			local row = window.List:FindFirstChild("Row_" .. def.id)
			if row and def.kind == "volume" and row:FindFirstChild("Slider") then
				wireSlider(def, row.Slider)
			elseif row and row:FindFirstChild("Switch") then
				wireSwitch(def, row.Switch)
			end
			local render = renders[def.id]
			if render then
				player:GetAttributeChangedSignal(Settings.attr(def.id)):Connect(render)
				render()
			end
		end
		local reset = window:FindFirstChild("Reset")
		if reset and reset:IsA("GuiButton") then
			reset.Activated:Connect(function()
				for _, def in Settings.list() do
					controller().set(def.id, def.default, true)
				end
			end)
		end
		window.List:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCanvas)
		fitCanvas()
		if deps.Util.FontDrop then
			deps.Util.FontDrop.watch(found)
		end
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		local button = hud and hud:FindFirstChild("SettingsButton", true)
		if button and button:IsA("GuiButton") then
			if deps.UI.HotbarUI and deps.UI.HotbarUI.wireHover then
				deps.UI.HotbarUI.wireHover(button)
			end
			button.Activated:Connect(SettingsUI.toggle)
		end
	end)
end

return SettingsUI
