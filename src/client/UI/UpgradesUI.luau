--!strict
-- UpgradesUI: the Upgrades stand's panel (2026-10-19, option B "list + detail" on
-- https://claude.ai/artifact/AxKfkGh2E8rdPAGwFEfDR1), hand-built as
-- StarterGui/UpgradesShop (Panel = "Upgrades", opened by the stand's ring,
-- Station "Upgrades"). The upgrades and every word are in Config/Upgrades.
--
-- Names the code uses:
--   Window/List       a ScrollingFrame of Templates/UpgradeRow clones, one per upgrade
--                     (Icon, UpgradeName, Pips/Pip1..3 for this world's three levels;
--                     IdleFill / SelectedFill / PipOn / PipOff attributes). Its canvas
--                     follows its layout (a one-column UIGridLayout since 2026-10-20, so a
--                     hovered or selected row grows round its own middle).
--   Window/World      Label: the highest world unlocked (it sets the cap)
--   Window/Coins      Amount (deep): the player's coins
--   Window/Detail/Card/Stage/Preview   the selected upgrade's icon
--   .../Info          UpgradeName, LevelPill/Label "Lv 2 / 3", Note ("Level 2 of 3 in
--                     World 1"), NowCard / NextCard (Title, Value, StatIcon(+Shadow) =
--                     the icon), TrackLabel, Track (Templates/WorldTemplate clones, one
--                     per world: Pips/Pip1..3, Label "W1"; PipOn / PipOpen / PipLocked /
--                     LockedTransparency attributes), Cost (Amount, deep; MetColor /
--                     ShortColor), Buy (Skin, Label; SkinCraft / SkinLocked,
--                     StrokeCraft / StrokeLocked, TextBuy / TextCoins / TextCapped /
--                     TextMaxed attributes)
-- Buying asks Remotes.BuyUpgrade (UpgradeService checks it all again).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Worlds = require(Config:WaitForChild("Worlds"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))

local UpgradesUI = {}

local PANEL_ID = "Upgrades"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local PanelWindow: any = nil
local window: any = nil
local selected = "Sprint"
local busy = false
local built = false

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function highest(): number
	return math.clamp(number("HighestWorld", 1), 1, Upgrades.MAX_WORLD)
end

local function setButton(button: any, look: string, words: string)
	button.Skin.Image = button:GetAttribute("Skin" .. look) or button.Skin.Image
	button.Label.Text = words
	local stroke = button.Label:FindFirstChildOfClass("UIStroke")
	local color = button:GetAttribute("Stroke" .. look)
	if stroke and typeof(color) == "Color3" then
		stroke.Color = color
	end
	-- a locked button can't be clicked, so it gets no hover or press (Util.ButtonFx)
	button.Active = look ~= "Locked"
end

-- Pips for the three levels a world holds: owned (On), still to buy (Open), out of reach (Locked).
local function paintPips(pips: Instance, from: number, level: number, open: boolean, template: Instance)
	for i = 1, Upgrades.LEVELS_PER_WORLD do
		local pip = pips:FindFirstChild("Pip" .. i) :: Frame?
		if pip then
			local n = from + i
			pip.BackgroundColor3 = template:GetAttribute(if n <= level then "PipOn" elseif open then (template:GetAttribute("PipOpen") and "PipOpen" or "PipOff") else (template:GetAttribute("PipLocked") and "PipLocked" or "PipOff"))
				or pip.BackgroundColor3
		end
	end
end

local function fitList()
	local list = window.List
	local layout = list:FindFirstChildWhichIsA("UIGridStyleLayout")
	local pad = list:FindFirstChildOfClass("UIPadding")
	local extra = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
	if layout then
		list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + extra)
	end
end

local function build()
	if built then
		return
	end
	built = true
	local list = window.List
	local template = window.Templates.UpgradeRow
	for index, def in Upgrades.list() do
		local row = template:Clone()
		row.Name = def.id
		row.LayoutOrder = index
		row.Visible = true
		row.Icon.Image = def.icon
		row.UpgradeName.Text = def.name
		row.Activated:Connect(function()
			selected = def.id
			UpgradesUI.refresh()
		end)
		row.Parent = list
	end
	local layout = list:FindFirstChildWhichIsA("UIGridStyleLayout")
	if layout then
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitList)
	end
	fitList()
	local track = window.Detail.Card.Info.Track
	local worldTemplate = window.Templates.WorldTemplate
	for w = 1, Upgrades.MAX_WORLD do
		local group = worldTemplate:Clone()
		group.Name = "W" .. w
		group.LayoutOrder = w
		group.Visible = true
		group.Label.Text = Upgrades.Text.worldShort:format(w)
		group.Parent = track
	end
end

function UpgradesUI.refresh()
	if not window then
		return
	end
	build()
	local world = highest()
	local cap = Upgrades.cap(world)
	local info = Worlds.get(world)
	if info and window:FindFirstChild("World") then
		window.World.Label.Text = Upgrades.Text.worldPill:format(world, (info.name:gsub("^The ", "")))
	end
	local coinsAmount = window:FindFirstChild("Coins") and window.Coins:FindFirstChild("Amount", true)
	if coinsAmount then
		coinsAmount.Text = Format.coins(number("Coins", 0))
	end

	-- the rows: this world's three levels
	local from = (world - 1) * Upgrades.LEVELS_PER_WORLD
	for _, row in window.List:GetChildren() do
		local def = Upgrades.get(row.Name)
		if def and row:IsA("GuiButton") then
			local level = Upgrades.level(player, def.id)
			row.BackgroundColor3 = row:GetAttribute(if def.id == selected then "SelectedFill" else "IdleFill") or row.BackgroundColor3
			row:SetAttribute("Selected", def.id == selected) -- stays grown (Util.ButtonFx)
			paintPips(row.Pips, from, level, true, row)
		end
	end

	local def = Upgrades.get(selected)
	if not def then
		return
	end
	local level = Upgrades.level(player, def.id)
	local inWorld = math.clamp(level - from, 0, Upgrades.LEVELS_PER_WORLD)
	local card = window.Detail.Card
	local detail = card.Info
	card.Stage.Preview.Image = def.icon
	detail.UpgradeName.Text = def.name
	detail.LevelPill.Label.Text = ("Lv %d / %d"):format(inWorld, Upgrades.LEVELS_PER_WORLD)
	detail.Note.Text = Upgrades.Text.levelOf:format(inWorld, Upgrades.LEVELS_PER_WORLD, world)
	detail.NowCard.Title.Text = Upgrades.Text.now
	detail.NowCard.Value.Text = Upgrades.describe(def, level)
	detail.NextCard.Title.Text = Upgrades.Text.next
	local maxed = level >= Upgrades.maxLevel()
	local capped = not maxed and level >= cap
	detail.NextCard.Value.Text = if maxed then Upgrades.Text.maxAll
		elseif capped then Upgrades.Text.maxWorld:format(world, world + 1)
		else Upgrades.describe(def, level + 1)
	for _, cardName in { "NowCard", "NextCard" } do
		for _, iconName in { "StatIcon", "StatIconShadow" } do
			local icon = detail[cardName]:FindFirstChild(iconName)
			if icon then
				icon.Image = def.icon
			end
		end
	end
	detail.TrackLabel.Text = Upgrades.Text.allLevels
	for _, group in detail.Track:GetChildren() do
		local w = tonumber((group.Name:match("^W(%d+)$")))
		if w and group:IsA("GuiObject") then
			local open = w <= world
			paintPips(group.Pips, (w - 1) * Upgrades.LEVELS_PER_WORLD, level, open, window.Templates.WorldTemplate)
			local fade = if open then 0 else (window.Templates.WorldTemplate:GetAttribute("LockedTransparency") or 0.5)
			group.Label.TextTransparency = fade
		end
	end

	local buy = detail.Buy
	local cost = if maxed then 0 else Upgrades.cost(def, level + 1)
	local amount = detail.Cost:FindFirstChild("Amount", true)
	detail.Cost.Visible = not maxed and not capped
	if amount then
		amount.Text = Format.coins(cost)
		amount.TextColor3 = detail.Cost:GetAttribute(if number("Coins", 0) >= cost then "MetColor" else "ShortColor") or amount.TextColor3
	end
	if maxed then
		setButton(buy, "Locked", buy:GetAttribute("TextMaxed") or "Maxed")
	elseif capped then
		setButton(buy, "Locked", (buy:GetAttribute("TextCapped") or "Unlock World %d"):format(world + 1))
	elseif number("Coins", 0) < cost then
		setButton(buy, "Locked", buy:GetAttribute("TextCoins") or "Need Coins")
	else
		setButton(buy, "Craft", buy:GetAttribute("TextBuy") or "Upgrade")
	end
end

local function onBuy()
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.getFunction("BuyUpgrade"):InvokeServer(selected)
	end)
	busy = false
	if not ok then
		warn("[UpgradesUI] BuyUpgrade failed: " .. tostring(result))
	end
	UiSound.play(if ok and result == true then "Purchase" else "Refuse")
	UpgradesUI.refresh()
end

local function wire(found: ScreenGui)
	window = found:WaitForChild("Window")
	window.Detail.Card.Info.Buy.Activated:Connect(onBuy)
	local names = { "Coins", "HighestWorld" }
	for _, def in Upgrades.list() do
		table.insert(names, Upgrades.attr(def.id))
	end
	for _, name in names do
		player:GetAttributeChangedSignal(name):Connect(UpgradesUI.refresh)
	end
	found:GetPropertyChangedSignal("Enabled"):Connect(UpgradesUI.refresh)
	UpgradesUI.refresh()
end

function UpgradesUI.init(injected: any)
	PanelWindow = injected.UI.PanelWindow
end

function UpgradesUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if found then
			wire(found)
		else
			warn("[UpgradesUI] no Upgrades panel (StarterGui/UpgradesShop)")
		end
	end)
end

return UpgradesUI
