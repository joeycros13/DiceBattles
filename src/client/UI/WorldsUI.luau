--!strict
-- WorldsUI: the Worlds menu (Worlds Menu canvas option C "Carousel" and HUD icon 1, the globe with a
-- gold ring; the user's picks, 2026-10-12). Wires the hand-built StarterGui/WorldsPanel and its HUD
-- button WeaponHud/SideButtons/WorldsButton; nothing here builds UI.
--
-- One big banner (Window/Viewport/Banner, a rounded CanvasGroup that clips the slide) shows the selected world (its Index picture, Config/Worlds `profile`), a gold
-- "World N" tag and its name; Prev / Next and the numbered dots below pick a world (8: chapter 1),
-- sliding the old banner out and the new one in (Next from the right, Prev from the left). Only the
-- worlds unlocked (HighestWorld) can be picked: Prev / Next stop (and fade) at the ends and a locked
-- world's dot doesn't respond (2026-10-21, the user).
-- The banner's right-hand corner says what you can do there:
--   * Teleport  a world you have unlocked (HighestWorld) and aren't in: Remotes.TravelToWorld sends
--               you to its spawn with the fade (PortalService.travel); the panel closes first
--   * Here      the world you are in (CurrentWorld, published by WorldBannerUI)
--   * Locked    a world that exists but isn't unlocked: its gate's level and price (Config/Gates);
--               walking through the gate is still how you unlock it
--   * Soon      a world that isn't built yet ("?" picture)
-- Words and dot colours are attributes on the gui (TextTag, TextLocked, TextSoon, TextHere,
-- TextUnknown, DotHere / DotOpen / DotLocked / DotSoon / DotSelected). Prev / Next show their drawn
-- gold buttons (`Art`) and a locked dot its padlock (`Lock`): option B on the Quest Guide & Worlds
-- Arrows canvas (2026-10-21).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Gates = require(Config:WaitForChild("Gates"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Format = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Format"))

local WorldsUI = {}

local PANEL = "Worlds"
local COUNT = 8 -- worlds in chapter 1
local GUI_TIMEOUT = 15
local LOCKED_TINT = Color3.fromRGB(105, 105, 118)
-- switching worlds slides the banners sideways inside Window/Viewport (user, 2026-10-12)
local SLIDE = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local deps: any = nil
local PanelWindow: any = nil
local gui: ScreenGui? = nil
local selected = 1
local busy = false
local slides: { Tween } = {}

local function attr(name: string, fallback: any): any
	local value = gui and gui:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- The last world the menu can show: the highest one unlocked (2026-10-21, the user: you
-- can't scroll past the worlds you have), never past the chapter.
local function reachable(): number
	return math.clamp(number("HighestWorld", 1), 1, COUNT)
end

type Status = "here" | "open" | "locked" | "soon"

local function statusOf(i: number): (Status, any)
	local def = Worlds.get(i)
	if not def then
		return "soon", nil
	end
	if i == number("CurrentWorld", 1) then
		return "here", def
	end
	return (if i <= number("HighestWorld", 1) then "open" else "locked"), def
end

local function gateOf(world: number): any
	for _, gate in Gates.list do
		if gate.world == world then
			return gate
		end
	end
	return nil
end

local function render()
	local g = gui
	if not g then
		return
	end
	local win = (g :: any).Window
	local banner = win.Viewport.Banner
	local status, def = statusOf(selected)
	local picture = if def and def.profile then def.profile else nil
	banner.Picture.Visible = picture ~= nil
	banner.Picture.Image = picture or ""
	banner.Picture.ImageColor3 = if status == "locked" then LOCKED_TINT else Color3.new(1, 1, 1)
	banner.Unknown.Visible = picture == nil
	banner.Tag.Label.Text = (attr("TextTag", "World %d") :: string):format(selected)
	banner.WorldName.Text = if def then (def.name:gsub("^The ", "")) else attr("TextUnknown", "???")
	banner.Teleport.Visible = status == "open"
	banner.Here.Visible = status == "here"
	banner.Here.Label.Text = attr("TextHere", "You are here")
	banner.Locked.Visible = status == "locked"
	if status == "locked" then
		local gate = gateOf(selected)
		banner.Locked.Label.Text = if gate then (attr("TextLocked", "Locked · Level %d · %s coins") :: string):format(gate.level, Format.coins(gate.coins)) else "Locked"
	end
	banner.Soon.Visible = status == "soon"
	banner.Soon.Label.Text = attr("TextSoon", "Coming soon")
	-- the arrows stop at the first world and the last unlocked one; a stopped arrow fades
	for name, can in { Prev = selected > 1, Next = selected < reachable() } do
		local arrow = win:FindFirstChild(name)
		if arrow and arrow:IsA("GuiButton") then
			arrow.Active = can
			local art = arrow:FindFirstChild("Art")
			if art and art:IsA("ImageLabel") then
				art.ImageTransparency = if can then 0 else 0.55
			end
		end
	end
	-- the dots
	for i = 1, COUNT do
		local dot = win.Dots:FindFirstChild("Dot" .. i)
		if dot then
			local s = statusOf(i)
			dot.BackgroundColor3 = if i == selected then attr("DotSelected", Color3.fromHex("f2c14e"))
				elseif s == "here" then attr("DotHere", Color3.fromHex("36c6e0"))
				elseif s == "open" then attr("DotOpen", Color3.fromHex("36c6e0"))
				elseif s == "locked" then attr("DotLocked", Color3.fromHex("3a4552"))
				else attr("DotSoon", Color3.fromHex("5d6873"))
			-- a locked or unbuilt world's dot shows its padlock (`Lock`, option B, 2026-10-21)
			-- instead of its number, unless it is the one picked
			local lock = dot:FindFirstChild("Lock")
			local closed = (s == "locked" or s == "soon") and i ~= selected
			if lock and lock:IsA("GuiObject") then
				lock.Visible = closed
				dot.Label.Visible = not closed
			end
			dot.Label.TextTransparency = if s == "soon" and i ~= selected then 0.45 else 0
			-- a world past the unlocked ones can't be picked: no hover or press either
			dot.Active = i <= reachable()
		end
	end
end

-- Pick a world; `dir` +1 slides the new banner in from the right (Next), -1 from the left.
-- Worlds past the unlocked ones can't be picked, and Prev / Next stop at the ends.
local function select(i: number, dir: number?)
	local g = gui
	local target = i
	if target < 1 or target > reachable() or target == selected or not g then
		return
	end
	local d = dir or (if target > selected then 1 else -1)
	local viewport = (g :: any).Window.Viewport
	local banner = viewport.Banner
	-- finish any slide still running
	for _, t in slides do
		t:Cancel()
	end
	slides = {}
	for _, child in viewport:GetChildren() do
		if child.Name == "Outgoing" then
			child:Destroy()
		end
	end
	-- the old banner as a still copy, sliding out; the real one, refilled, sliding in
	local outgoing = banner:Clone()
	outgoing.Name = "Outgoing"
	outgoing.Position = UDim2.fromScale(0, 0)
	for _, b in outgoing:GetDescendants() do
		if b:IsA("GuiButton") then
			b.Active = false
		end
	end
	outgoing.Parent = viewport
	selected = target
	render()
	banner.Position = UDim2.fromScale(d, 0)
	local a = TweenService:Create(outgoing, SLIDE, { Position = UDim2.fromScale(-d, 0) })
	local b = TweenService:Create(banner, SLIDE, { Position = UDim2.fromScale(0, 0) })
	slides = { a, b }
	a.Completed:Connect(function()
		outgoing:Destroy()
	end)
	a:Play()
	b:Play()
end

function WorldsUI.open()
	if not gui then
		return
	end
	selected = number("CurrentWorld", 1)
	local banner = (gui :: any).Window.Viewport.Banner
	banner.Position = UDim2.fromScale(0, 0)
	render()
	PanelWindow.showPanel(PANEL)
end

function WorldsUI.toggle()
	if PanelWindow.isPanelOpen(PANEL) then
		PanelWindow.hidePanel()
	else
		WorldsUI.open()
	end
end

local function teleport()
	if busy or statusOf(selected) ~= "open" then
		return
	end
	busy = true
	local world = selected
	PanelWindow.hidePanel()
	local ok, reason = deps.Remotes.getFunction("TravelToWorld"):InvokeServer(world)
	if not ok then
		warn(("[WorldsUI] teleport to world %d refused: %s"):format(world, tostring(reason)))
	end
	busy = false
end

function WorldsUI.init(injected: any)
	deps = injected
	PanelWindow = deps.UI.PanelWindow
end

function WorldsUI.start()
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local found = playerGui:WaitForChild("WorldsPanel", GUI_TIMEOUT)
		if not (found and found:IsA("ScreenGui")) then
			warn("[WorldsUI] no WorldsPanel ScreenGui in StarterGui")
			return
		end
		gui = found
		local win = (found :: any).Window
		win.Viewport.Banner.Teleport.Activated:Connect(teleport)
		win.Prev.Activated:Connect(function()
			select(selected - 1, -1)
		end)
		win.Next.Activated:Connect(function()
			select(selected + 1, 1)
		end)
		for i = 1, COUNT do
			local dot = win.Dots:FindFirstChild("Dot" .. i)
			if dot and dot:IsA("GuiButton") then
				dot.Activated:Connect(function()
					select(i)
				end)
			end
		end
		if deps.Util.FontDrop then
			deps.Util.FontDrop.watch(found)
		end
		-- the HUD button
		local hud = playerGui:WaitForChild("WeaponHud", GUI_TIMEOUT)
		local button = hud and hud:FindFirstChild("WorldsButton", true)
		if button and button:IsA("GuiButton") then
			if deps.UI.HotbarUI and deps.UI.HotbarUI.wireHover then
				deps.UI.HotbarUI.wireHover(button)
			end
			button.Activated:Connect(WorldsUI.toggle)
		end
	end)
	for _, name in { "HighestWorld", "CurrentWorld" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if PanelWindow.isPanelOpen(PANEL) then
				render()
			end
		end)
	end
end

return WorldsUI
