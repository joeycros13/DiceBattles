--!strict
-- PanelWindow: shows and hides the hand-built panels.
--
-- A panel is a ScreenGui designed in StarterGui and given a "Panel" attribute
-- naming it ("Weapons", "Crafting", "Inventory"). Everything about how it looks
-- -- size, layout, colours, the items in a shop -- is authored there in Studio;
-- this module only switches panels on and off, one at a time, and closes the
-- open one when any button named "Close" inside it is pressed.
--
-- Walking into a stall's ring (InteractionController) opens that stall's panel;
-- the HUD's Inventory button (InventoryUI) opens the Inventory.
--
-- Opening pops the panel out of its centre: a UIScale named "PopScale" (on
-- the panel's Window, authored) grows from 0 with a little overshoot over the
-- panel's "OpenSeconds". Closing shrinks it back to 0 over "CloseSeconds",
-- and only then turns the panel off. Switching straight to another panel
-- closes the old one at once, so two windows never overlap. A panel without a
-- PopScale just appears and disappears. Opening plays Util.UiSound's "PanelOpen",
-- closing "PanelClose" (switching straight to another panel plays only the open).
--
-- While a panel is open nothing else can be clicked (2026-10-22, the user: "the only way
-- out is walking away (if it is a station), clicking outside of the panel, or clicking
-- the X"):
--   * the HUD's buttons hide: WeaponHud's SideButtons, Hotbar and Attack, and the whole
--     QuestTracker (its Guide button); each comes back as it was when the last panel
--     closes. The player card and coins stay, so prices and balances can be watched.
--   * each panel has a hand-built full-screen "Catcher" (an invisible TextButton under the
--     Window): a click outside the window closes the panel instead of reaching the HUD or
--     the world. The Window and its pieces are Active, so a click on the panel itself never
--     falls through to the catcher.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local PanelWindow = {}

local panels: { [string]: ScreenGui } = {}
local openPanel: string? = nil

-- the HUD pieces hidden while a panel is open: { gui, child } (child nil = the whole gui)
local HUD_HIDDEN = { { "WeaponHud", "SideButtons" }, { "WeaponHud", "Hotbar" }, { "WeaponHud", "Attack" }, { "QuestTracker" } }
local hudSaved: { [Instance]: boolean }? = nil -- what each was before the first panel opened
local popTweens: { [ScreenGui]: Tween } = {}

local function number(gui: Instance, name: string, fallback: number): number
	local value = gui:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function popScale(gui: ScreenGui): UIScale?
	local scale = gui:FindFirstChild("PopScale", true)
	return if scale and scale:IsA("UIScale") then scale else nil
end

-- Animate a panel's PopScale; `done` runs if the tween finishes uninterrupted.
local function pop(gui: ScreenGui, target: number, info: TweenInfo, done: (() -> ())?)
	local running = popTweens[gui]
	if running then
		running:Cancel()
		popTweens[gui] = nil
	end
	local scale = popScale(gui)
	if not scale then
		if done then
			done()
		end
		return
	end
	local tween = TweenService:Create(scale, info, { Scale = target })
	popTweens[gui] = tween
	tween.Completed:Connect(function(state)
		if popTweens[gui] == tween then
			popTweens[gui] = nil
		end
		if state == Enum.PlaybackState.Completed and done then
			done()
		end
	end)
	tween:Play()
end

local function openNow(gui: ScreenGui)
	-- reopened while still shrinking: grow back from where it is
	local scale = popScale(gui)
	if scale and not gui.Enabled then
		scale.Scale = 0
	end
	gui.Enabled = true
	pop(gui, 1, TweenInfo.new(number(gui, "OpenSeconds", 0.22), Enum.EasingStyle.Back, Enum.EasingDirection.Out))
end

local function closeNow(gui: ScreenGui, animate: boolean)
	if not gui.Enabled then
		return
	end
	if not animate then
		pop(gui, 1, TweenInfo.new(0))
		gui.Enabled = false
		return
	end
	pop(gui, 0, TweenInfo.new(number(gui, "CloseSeconds", 0.14), Enum.EasingStyle.Back, Enum.EasingDirection.In), function()
		gui.Enabled = false
	end)
end

-- Hide (or bring back) the HUD's buttons. Hiding saves what each piece was, so a piece
-- something else had hidden (the Attack button off a touch screen, the tracker with no
-- quest) stays hidden when they come back.
local function setHudHidden(hidden: boolean)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	if hidden and not hudSaved then
		local saved: { [Instance]: boolean } = {}
		for _, path in HUD_HIDDEN do
			local gui = playerGui:FindFirstChild(path[1])
			local piece = gui and (if path[2] then gui:FindFirstChild(path[2]) else gui)
			if piece and piece:IsA("GuiObject") then
				saved[piece] = piece.Visible
				piece.Visible = false
			elseif piece and piece:IsA("ScreenGui") then
				saved[piece] = piece.Enabled
				piece.Enabled = false
			end
		end
		hudSaved = saved
	elseif not hidden and hudSaved then
		for piece, was in hudSaved do
			if piece:IsA("GuiObject") then
				piece.Visible = was
			elseif piece:IsA("ScreenGui") then
				piece.Enabled = was
			end
		end
		hudSaved = nil
	end
end

function PanelWindow.init(_injected: any) end

local function adopt(gui: Instance)
	if not gui:IsA("ScreenGui") then
		return
	end
	local id = gui:GetAttribute("Panel")
	if type(id) ~= "string" or panels[id] == gui then
		return
	end
	panels[id] = gui
	gui.Enabled = false
	-- a click outside the window closes the panel
	local catcher = gui:FindFirstChild("Catcher")
	if catcher and catcher:IsA("GuiButton") then
		catcher.Activated:Connect(function()
			if openPanel == id then
				PanelWindow.hidePanel()
			end
		end)
	end
	for _, descendant in gui:GetDescendants() do
		if descendant.Name == "Close" and descendant:IsA("GuiButton") then
			descendant.Activated:Connect(function()
				if openPanel == id then
					PanelWindow.hidePanel()
				end
			end)
			-- its hover grow and press squash come from Util.ButtonFx (its FxScale), like every button
		end
	end
end

function PanelWindow.start()
	-- StarterGui's copies arrive in PlayerGui on the first spawn; the authored
	-- panels have ResetOnSpawn off, so they are never replaced after that.
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, gui in playerGui:GetChildren() do
		adopt(gui)
	end
	playerGui.ChildAdded:Connect(adopt)
end

-- True if a hand-built panel with that id exists.
function PanelWindow.hasPanel(panelId: string): boolean
	return PanelWindow.getPanel(panelId) ~= nil
end

-- The panel's ScreenGui, for modules that fill in live values. Waits up to
-- `timeout` seconds for it to arrive from StarterGui (default: no wait).
function PanelWindow.getPanel(panelId: string, timeout: number?): ScreenGui?
	local deadline = os.clock() + (timeout or 0)
	repeat
		if panels[panelId] then
			return panels[panelId]
		end
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			for _, gui in playerGui:GetChildren() do
				adopt(gui)
			end
		end
		if panels[panelId] or os.clock() >= deadline then
			break
		end
		task.wait(0.1)
	until false
	return panels[panelId]
end

-- Open a panel, replacing whichever one was showing.
function PanelWindow.showPanel(panelId: string)
	local gui = panels[panelId]
	if not gui then
		return
	end
	for id, other in panels do
		if id ~= panelId then
			closeNow(other, false)
		end
	end
	if openPanel ~= panelId then
		UiSound.play("PanelOpen")
	end
	openPanel = panelId
	setHudHidden(true)
	openNow(gui)
end

function PanelWindow.hidePanel()
	local id = openPanel
	openPanel = nil
	if id and panels[id] then
		UiSound.play("PanelClose")
		closeNow(panels[id], true)
	end
	setHudHidden(false)
end

-- True when `panelId` (or any panel, if omitted) is showing.
function PanelWindow.isPanelOpen(panelId: string?): boolean
	if not openPanel then
		return false
	end
	return panelId == nil or openPanel == panelId
end

return PanelWindow
