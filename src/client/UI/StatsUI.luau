--!strict
-- StatsUI: the Stats panel (2026-10-19, option A "stat sheet" on
-- https://claude.ai/artifact/E7RQQXPYH2ZCKBB6V4YaWk), opened from the HUD's
-- WeaponHud/SideButtons/StatsButton. Every stat shows as its total MULTIPLIER (the user's
-- rule), except chances and regen, which are percentages since 2026-10-22 (the user: Crit
-- Chance, Regen, Gathering), with a chip for each thing that feeds it:
--   Max Health    the number: (level's HP + armour) x the Health upgrade (flat bonuses
--                 first, then multipliers)
--   Luck / Coins / EXP   1 + the shop's passes and boosts' share (LuckBoost / CoinBoost /
--                 ExpBoost, ShopService) + the upgrade's share
--   Damage        1 + the Strength potion's share + the Attack upgrade's
-- Bonuses ADD (2026-10-23, the user: x1.5 and x2 make x2.5): the totals come from
-- Config/Bonuses, the same numbers the server uses, and each chip shows its share as a
-- multiplier ("Passes & boosts +1.5×" on a ×2.50 total).
--   Defense       how much tougher: 1 / (armour's damage x Stoneskin x the Defense upgrade)
--   Attack Speed  the upgrade (Upgrades.multiplier)
--   Gathering     the chance a tree's or rock's drop comes doubled (the upgrade; a Gatherer's
--                 potion makes tools hit harder, so it isn't on it)
--   Regen         the share of max HP healed a second: Roblox's base 1% plus the upgrade's
--                 share plus a Regen potion's
--   Sprint        1 + the Sprint upgrade's share + a Swiftness potion's + the armour's
--                 ("Locked" before Sprint 1)
--   Crit Damage   a critical hit's whole multiplier (x1.50 at the start, the upgrade adds 0.05)
--   Crit Chance   the chance a hit is critical: the base 10% plus the upgrade
-- An admin's own test settings show as an "Admin" chip, only while one is set: the
-- damage multiplier (DamageMultiplier) and the max-health override (MaxHealthOverride,
-- which replaces the whole max), so the panel matches what they really have.
-- The numbers come from Util/StatSheet (shared with the profile cards).
-- Hand-built StarterGui/StatsPanel (Panel = "Stats"): Window/World/Label, Window/Sheet
-- (a UIGridLayout) filled with Templates/StatRow clones (Tile/Icon, StatName, Parts,
-- Total; UpColor / SameColor attributes), each Parts holding Templates/PartChip clones
-- (TextScale attribute: the chip's text size as a share of its height).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Upgrades = require(Config:WaitForChild("Upgrades"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))
local StatSheet = require(Util:WaitForChild("StatSheet"))

local StatsUI = {}

local PANEL = "Stats"
local GUI_TIMEOUT = 15
local TICK = 0.5
local player = Players.LocalPlayer

local Text = StatSheet.Text
local ORDER = StatSheet.ORDER

local PanelWindow: any = nil
local FontDrop: any = nil
local deps: any = nil
local window: any = nil
local rows: { [string]: any } = {}

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function build()
	local sheet = window.Sheet
	for index, id in ORDER do
		local row = window.Templates.StatRow:Clone()
		row.Name = id
		row.LayoutOrder = index
		row.Visible = true
		local def = Upgrades.get(id)
		row.Tile.Icon.Image = if def then def.icon else ""
		row.StatName.Text = StatSheet.name(id)
		row.Parent = sheet
		rows[id] = row
	end
end

local function fillChips(row: any, parts: { string })
	for _, child in row.Parts:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if #parts == 0 then
		parts = { Text.noBonus }
	end
	local template = window.Templates.PartChip
	local size = math.max(8, math.floor(row.Parts.AbsoluteSize.Y * (template:GetAttribute("TextScale") or 0.62)))
	for index, words in parts do
		local chip = template:Clone()
		chip.Name = "Chip" .. index
		chip.LayoutOrder = index
		chip.Visible = true
		chip.Text = words
		chip.TextSize = size
		chip.Parent = row.Parts
	end
end

function StatsUI.refresh()
	if not window then
		return
	end
	if window:FindFirstChild("World") then
		window.World.Label.Text = Text.pill:format(Format.commas(number("Level", 1)))
	end
	for id, row in rows do
		local total, parts, raised = StatSheet.measure(player, id)
		row.Total.Text = total
		row.Total.TextColor3 = row:GetAttribute(if raised then "UpColor" else "SameColor") or row.Total.TextColor3
		fillChips(row, parts)
	end
end

function StatsUI.toggle()
	if PanelWindow.isPanelOpen(PANEL) then
		PanelWindow.hidePanel()
	else
		PanelWindow.showPanel(PANEL)
		StatsUI.refresh()
	end
end

function StatsUI.init(injected: any)
	deps = injected
	PanelWindow = injected.UI.PanelWindow
	FontDrop = injected.Util.FontDrop
end

function StatsUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL, GUI_TIMEOUT)
		if not found then
			warn("[StatsUI] no Stats panel (StarterGui/StatsPanel)")
			return
		end
		window = found:WaitForChild("Window")
		build()
		if FontDrop then
			FontDrop.watch(found)
		end
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		local button = hud and hud:FindFirstChild("StatsButton", true)
		if button and button:IsA("GuiButton") then
			if deps.UI.HotbarUI and deps.UI.HotbarUI.wireHover then
				deps.UI.HotbarUI.wireHover(button)
			end
			button.Activated:Connect(StatsUI.toggle)
		end
		-- live while open: boost and potion timers run out, health changes
		while true do
			task.wait(TICK)
			if found.Enabled then
				StatsUI.refresh()
			end
		end
	end)
end

return StatsUI
