--!strict
-- ButtonFx: the hover and click effect on every clickable button (2026-10-20, the
-- user's request with the chunky-pill buttons: "a hover effect over every button that
-- is clickable ... all clickable buttons need the click effect as well").
--
-- A button takes part when it has a hand-built UIScale child named "FxScale" (added in
-- Studio to every button; clones of templates carry it). Watches the whole PlayerGui.
--   hover   grows to the button's (or its ScreenGui's) "FxHover" attribute (default 1.06)
--   press   squashes to "FxPress" (default 0.92) while held; the action runs on release, as
--           it springs back with a little overshoot
--   selected  a "Selected" attribute (set by the UI modules on the open tab or chosen row)
--           keeps it grown, to "FxSelected" (default the hover size), hovered or not
-- It grows round its own centre: a free button is anchored at (0.5, 0.5), a list centres
-- its items on the cross axis (a grown item then pushes its neighbours aside), and a grid
-- grows each item round its cell's centre (2026-10-20, the user: "it should expand from the
-- center ... like the Inventory, Index buttons").
-- A button is clickable while it is Active and Interactable, and has no "Disabled"
-- attribute set. The UI modules set Active = false on a button whose requirements
-- aren't met (Need Coins, Need Level, Owned...), so it gets neither effect.
-- Attributes to opt out of one half: "FxNoHover" (its own code grows it already: the
-- side buttons, the hotbar slots) and "FxNoPress".
-- Roblox applies only ONE UIScale per object, so a button must not carry another one
-- (the old "PressScale"s were removed on 2026-10-20: while both were there, the X buttons
-- and stall tabs showed no hover or press at all).
-- Sounds (2026-10-22, Util.UiSound): hovering a clickable button plays "Hover", pressing it
-- "Click", and pressing a locked one (Active off, or Disabled) "Refuse". "FxNoSound" on a
-- button turns its sounds off.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UiSound = require(script.Parent:WaitForChild("UiSound"))

local ButtonFx = {}

local HOVER, PRESS = 1.06, 0.92
local GROW = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SQUASH = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRING = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local wired: { [GuiButton]: boolean } = {}

local function setting(button: GuiButton, name: string, default: number): number
	local value = button:GetAttribute(name)
	if type(value) ~= "number" then
		local screen = button:FindFirstAncestorWhichIsA("LayerCollector")
		value = screen and screen:GetAttribute(name)
	end
	return if type(value) == "number" then value else default
end

local function clickable(button: GuiButton): boolean
	local interactable = (button :: any).Interactable
	return button.Active and interactable ~= false and button:GetAttribute("Disabled") ~= true
end

local function wire(button: GuiButton)
	if wired[button] then
		return
	end
	local scale = button:FindFirstChild("FxScale")
	if not (scale and scale:IsA("UIScale")) then
		return
	end
	wired[button] = true
	local hovered, pressed = false, false
	local tween: Tween? = nil
	local function to(target: number, info: TweenInfo)
		if tween then
			tween:Cancel()
		end
		tween = TweenService:Create(scale, info, { Scale = target })
		;(tween :: Tween):Play()
	end
	local function rest(info: TweenInfo)
		-- a selected button (the open tab, the chosen row) always stays grown
		local selected = button:GetAttribute("Selected") == true
		local grow = selected or (hovered and clickable(button) and button:GetAttribute("FxNoHover") ~= true)
		to(if grow then setting(button, if selected then "FxSelected" else "FxHover", setting(button, "FxHover", HOVER)) else 1, info)
	end
	local function sound(name: string)
		if button:GetAttribute("FxNoSound") ~= true then
			UiSound.play(name)
		end
	end
	button.MouseEnter:Connect(function()
		hovered = true
		if not pressed then
			rest(GROW)
		end
		if clickable(button) and button:GetAttribute("Selected") ~= true then
			sound("Hover")
		end
	end)
	button.MouseLeave:Connect(function()
		hovered, pressed = false, false
		rest(GROW)
	end)
	button.MouseButton1Down:Connect(function()
		if not clickable(button) then
			sound("Refuse")
		elseif button:GetAttribute("FxNoPress") ~= true then
			pressed = true
			to(setting(button, "FxPress", PRESS), SQUASH)
		end
		if clickable(button) then
			sound("Click")
		end
	end)
	button.MouseButton1Up:Connect(function()
		if pressed then
			pressed = false
			rest(SPRING)
		end
	end)
	-- a touch has no hover: squash on the tap, then spring back
	button.TouchTap:Connect(function()
		-- a tap also fires MouseButton1Down on most devices; MinGap keeps it to one sound
		sound(if clickable(button) then "Click" else "Refuse")
		if clickable(button) and button:GetAttribute("FxNoPress") ~= true and not pressed then
			to(setting(button, "FxPress", PRESS), SQUASH)
			task.delay(0.07, function()
				rest(SPRING)
			end)
		end
	end)
	-- becoming locked (or unlocked), selected or not settles it at once
	button:GetPropertyChangedSignal("Active"):Connect(function()
		rest(GROW)
	end)
	for _, name in { "Selected", "Disabled" } do
		button:GetAttributeChangedSignal(name):Connect(function()
			if not pressed then
				rest(GROW)
			end
		end)
	end
	if button:GetAttribute("Selected") == true then
		rest(GROW)
	end
	button.Destroying:Connect(function()
		wired[button] = nil
	end)
end

local function watch(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") then
			wire(d)
		elseif d:IsA("UIScale") and d.Name == "FxScale" and d.Parent and d.Parent:IsA("GuiButton") then
			wire(d.Parent)
		end
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("GuiButton") then
			-- its FxScale may arrive just after it
			task.defer(wire, d)
		elseif d:IsA("UIScale") and d.Name == "FxScale" and d.Parent and d.Parent:IsA("GuiButton") then
			wire(d.Parent)
		end
	end)
end

function ButtonFx.init(_injected: any) end

function ButtonFx.start()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	watch(gui)
end

return ButtonFx
