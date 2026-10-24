--!strict
-- DailyRewardsUI: the Daily Rewards stand's panel (2026-10-19, option A "week row" on
-- https://claude.ai/artifact/FNn8enN7mGMHDjrBX3GWDf), hand-built as StarterGui/DailyRewards
-- (Panel = "Daily", opened by the stand's ring, Station "Daily"). The ladder, codes and every
-- word are in Config/DailyRewards; the streak comes from DailyRewardService's "DailyStreak" /
-- "DailyLastDay" attributes, read against the server clock (DailyRewards.status).
--
-- Names the code uses:
--   Window/Title, Window/Streak/Label ("3 day streak"), Window/Hint
--   Window/Days          a row (UIListLayout, HorizontalFlex Fill) of Templates/DayTile clones,
--                        one per ladder day: DayLabel, Icon, Check, Reward, TodayPill/Label, a
--                        UIStroke and a UIFlexItem (the big last day grows by the BigGrow attribute).
--                        Tile attributes: FillClaimed / FillToday / FillLocked / FillBig, Ink /
--                        InkLocked, StrokeToday, BigGrow, LockedIconTransparency.
--   Window/Claim         Skin, Label; SkinReady / SkinDone, StrokeReady / StrokeDone attributes
--   Window/NextIn        "Next reward in 5h 12m"
--   Window/CodeBox       Label, Input/Box (the TextBox), Redeem (Label)
--   Window/Message       the last claim's or code's result; the gui's OkColor / ErrorColor
-- Claiming asks Remotes.ClaimDaily, codes Remotes.RedeemCode (the service checks it all again).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local DailyRewards = require(Config:WaitForChild("DailyRewards"))
local Potions = require(Config:WaitForChild("Potions"))
local Shop = require(Config:WaitForChild("Shop"))

local DailyRewardsUI = {}

local PANEL_ID = "Daily"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer
local Text = DailyRewards.Text

local deps: any = nil
local PanelWindow: any = nil
local gui: any = nil
local window: any = nil
local tiles: { any } = {}
local busy = false

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function world(): number
	return math.max(1, number("HighestWorld", 1))
end

-- the ladder state now: ready, tiles claimed this week, the day the next claim gives
local function status(): (boolean, number, number)
	local last = number("DailyLastDay", -1)
	return DailyRewards.status(number("DailyStreak", 0), if last >= 0 then last else nil, DailyRewards.dayOf(Workspace:GetServerTimeNow()))
end

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h, m = seconds // 3600, (seconds % 3600) // 60
	if h > 0 then
		return ("%dh %dm"):format(h, m)
	end
	return ("%dm %ds"):format(m, seconds % 60)
end

local function iconOf(day: DailyRewards.Day): string
	if day.icon == "Potion" and day.potions and day.potions[1] then
		local def = Potions.get(day.potions[1].kind .. (Potions.tierAt(world()) or 1))
		return if def and def.icon then def.icon else ""
	end
	return DailyRewards.Icons[day.icon] or ""
end

local function words(day: DailyRewards.Day): string
	if day.big then
		return Text.chest
	end
	local coins = DailyRewards.coinsFor(day, world(), Shop.WorldScale)
	return table.concat(DailyRewards.describe(day, if coins > 0 then coins else nil), " + ")
end

local function setClaim(ready: boolean, nextDay: number)
	local claim = window.Claim
	local look = if ready then "Ready" else "Done"
	claim.Skin.Image = claim:GetAttribute("Skin" .. look) or claim.Skin.Image
	claim.Label.Text = if ready then Text.claim:format(nextDay) else Text.claimed
	local stroke = claim.Label:FindFirstChildOfClass("UIStroke")
	local color = claim:GetAttribute("Stroke" .. look)
	if stroke and typeof(color) == "Color3" then
		stroke.Color = color
	end
	claim.Active = ready
	claim.AutoButtonColor = false
end

local function build()
	for _, t in tiles do
		t:Destroy()
	end
	tiles = {}
	for n, day in DailyRewards.Ladder do
		local tile = window.Templates.DayTile:Clone()
		tile.Name = "Day" .. n
		tile.LayoutOrder = n
		tile.Visible = true
		local flex = tile:FindFirstChildOfClass("UIFlexItem")
		if flex and day.big then
			flex.GrowRatio = tile:GetAttribute("BigGrow") or 1.6
		end
		tile.DayLabel.Text = Text.day:format(n)
		tile.TodayPill.Label.Text = Text.today
		tile.Parent = window.Days
		tiles[n] = tile
	end
end

function DailyRewardsUI.refresh()
	if not window then
		return
	end
	local ready, claimed, nextDay = status()
	window.Streak.Label.Text = if claimed > 0 then Text.streak:format(claimed) else Text.streakNone
	for n, day in DailyRewards.Ladder do
		local tile = tiles[n]
		if tile then
			local isClaimed = n <= claimed
			local isToday = ready and n == nextDay
			local fill = if isToday then "FillToday" elseif isClaimed then "FillClaimed" elseif day.big then "FillBig" else "FillLocked"
			tile.BackgroundColor3 = tile:GetAttribute(fill) or tile.BackgroundColor3
			local ink = tile:GetAttribute(if isClaimed or isToday then "Ink" else "InkLocked") or tile.DayLabel.TextColor3
			tile.DayLabel.TextColor3 = ink
			tile.Reward.TextColor3 = ink
			tile.Reward.Text = words(day)
			tile.Icon.Image = iconOf(day)
			tile.Icon.ImageTransparency = if isClaimed or isToday then 0 else (tile:GetAttribute("LockedIconTransparency") or 0)
			tile.Check.Visible = isClaimed
			tile.TodayPill.Visible = isToday
			local stroke = tile:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if isToday then (tile:GetAttribute("StrokeToday") or stroke.Color) else (tile:GetAttribute("Ink") or stroke.Color)
			end
		end
	end
	setClaim(ready, nextDay)
	window.NextIn.Text = if ready then "" else Text.nextIn:format(duration(DailyRewards.resetsAt(Workspace:GetServerTimeNow()) - Workspace:GetServerTimeNow()))
end

local function say(ok: boolean, message: string)
	window.Message.Text = message
	window.Message.TextColor3 = gui:GetAttribute(if ok then "OkColor" else "ErrorColor") or window.Message.TextColor3
end

local function claim()
	if busy then
		return
	end
	local ready = status()
	if not ready then
		return
	end
	busy = true
	local ok, granted, result = pcall(function()
		return Remotes.getFunction("ClaimDaily"):InvokeServer()
	end)
	busy = false
	UiSound.play(if ok and granted == true then "QuestComplete" else "Refuse")
	if ok and granted == true and type(result) == "string" then
		say(true, Text.claimedMessage:format(result))
	elseif ok and result == "away" then
		say(false, Text.away)
	end
	DailyRewardsUI.refresh()
end

local function redeem()
	if busy then
		return
	end
	local box = window.CodeBox.Input.Box
	busy = true
	local ok, granted, message = pcall(function()
		return Remotes.getFunction("RedeemCode"):InvokeServer(box.Text)
	end)
	busy = false
	UiSound.play(if ok and granted == true then "QuestComplete" else "Refuse")
	if ok then
		say(granted == true, if type(message) == "string" then message else "")
		if granted then
			box.Text = ""
		end
	end
end

local function wire(found: ScreenGui)
	gui = found
	window = found:WaitForChild("Window")
	window.Title.Text = "Daily Rewards"
	window.Hint.Text = Text.hint
	window.CodeBox.Label.Text = Text.codeLabel
	window.CodeBox.Input.Box.PlaceholderText = Text.codeHint
	window.CodeBox.Redeem.Label.Text = Text.redeem
	window.Message.Text = ""
	build()
	window.Claim.Activated:Connect(claim)
	window.CodeBox.Redeem.Activated:Connect(redeem)
	window.CodeBox.Input.Box.FocusLost:Connect(function(enter: boolean)
		if enter then
			redeem()
		end
	end)
	for _, name in { "DailyStreak", "DailyLastDay", "HighestWorld" } do
		player:GetAttributeChangedSignal(name):Connect(DailyRewardsUI.refresh)
	end
	if deps.Util.FontDrop then
		deps.Util.FontDrop.watch(found)
	end
	DailyRewardsUI.refresh()
	-- the countdown and a new day while the panel is open
	task.spawn(function()
		while true do
			task.wait(1)
			if found.Enabled then
				DailyRewardsUI.refresh()
			end
		end
	end)
end

function DailyRewardsUI.init(injected: any)
	deps = injected
	PanelWindow = injected.UI.PanelWindow
end

function DailyRewardsUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if found then
			wire(found)
		else
			warn("[DailyRewardsUI] no Daily panel (StarterGui/DailyRewards)")
		end
	end)
end

return DailyRewardsUI
