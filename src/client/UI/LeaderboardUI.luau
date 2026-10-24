--!strict
-- LeaderboardUI: the Leaderboards panel (2026-10-19, option A "tabs and podium" on
-- https://claude.ai/artifact/E7RQQXPYH2ZCKBB6V4YaWk), opened from the HUD's
-- WeaponHud/SideButtons/LeaderboardButton. Boards and rewards are Config/Leaderboards;
-- the numbers come from Remotes.GetLeaderboard (LeaderboardService).
--
-- Hand-built StarterGui/LeaderboardPanel (Panel = "Leaderboards"), laid out as Ranks A
-- "Spotlight stage" (2026-10-21, https://claude.ai/artifact/BW6XYrhkThRjExFbRB41Xj):
--   Window/Periods/<Weekly|All|Trophies> pills in a dark header pill (Period attribute, Label);
--                                       Trophies (2026-10-22, view B on the "Leaderboard rewards"
--                                       canvas, https://claude.ai/artifact/Sjkt4yWCvqYH2dWYRot9Vg)
--                                       swaps the board for Window/Trophies
--   Window/Tabs/<Coins|Levels|Kills>    big stat pills under the header (Stat attribute,
--                                       IconRing/Icon, Label)
--   Window/ResetPill/Reset              the header's dark pill, a Util.CenterRow with its Clock:
--                                       "Resets in 5h 12m" / "Never resets"
--   Window/Stage                        the glowing stage behind the podium (Rays turn slowly,
--                                       Confetti, Base)
--   Window/ListCard                     the cream card behind List and You
--   Window/Podium/Place1..3             PlayerName, Value, Block/Rank, Avatar (the player's
--                                       headshot), Crown on Place1 (podium option A, 2026-10-21)
--   Window/List                         a ScrollingFrame of Templates/Row clones (#4-50:
--                                       Rank circle, Avatar headshot, PlayerName, Value);
--                                       Window/Empty when no one
--   Window/You                          your own place (Rank, PlayerName, Value)
--   Window/Rewards                      Title, Tiers (Templates/TierCard clones: Label = the
--                                       tier's badge in its Fill1..3 colour, Chips holding one
--                                       Templates/Chip with every prize on a line), Note (all-time)
--   Window/Trophies                     the trophy cabinet (hidden until Trophies is picked):
--                                       Title, Note (shown with no trophies yet) and a
--                                       Row_<Coins|Levels|Kills> per board (IconRing/Icon,
--                                       BoardName, and Gold / Silver / Bronze slots, each a Cup,
--                                       Count "x2" and Place "#1"); counts from the player's
--                                       Trophies attribute (LeaderboardService); an empty cup fades
--                                       to the frame's EmptyCupTransparency
-- Colours: the gui's TabSelected / TabIdle / PillSelected / PillIdle / PillSelectedText /
-- PillIdleText attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Leaderboards = require(Shared:WaitForChild("Config"):WaitForChild("Leaderboards"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))

local LeaderboardUI = {}

local PANEL = "Leaderboards"
local GUI_TIMEOUT = 15
local CACHE_SECONDS = 15
local player = Players.LocalPlayer

local deps: any = nil
local PanelWindow: any = nil
local gui: any = nil
local window: any = nil
local stat = "Coins"
local period = "Weekly"
local boards: { [string]: { data: any, at: number } } = {}
local shownResetsAt: number? = nil

local Text = Leaderboards.Text

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	if d > 0 then
		return ("%dd %dh"):format(d, h)
	elseif h > 0 then
		return ("%dh %dm"):format(h, m)
	end
	return ("%dm %ds"):format(m, seconds % 60)
end

local function valueText(value: number): string
	if stat == "Levels" and period == "All" then
		return Text.level:format(Format.commas(value))
	end
	return if stat == "Coins" then Format.coins(value) else Format.commas(value)
end

local function fetch(): any
	local key = stat .. "_" .. period
	local hit = boards[key]
	if hit and os.clock() - hit.at < CACHE_SECONDS then
		return hit.data
	end
	local ok, data = pcall(function()
		return Remotes.getFunction("GetLeaderboard"):InvokeServer(stat, period)
	end)
	if not ok or type(data) ~= "table" then
		return hit and hit.data or nil
	end
	boards[key] = { data = data, at = os.clock() }
	return data
end

local function styleTabs()
	for _, b in window.Tabs:GetChildren() do
		if b:IsA("GuiButton") then
			b.BackgroundColor3 = gui:GetAttribute(if b:GetAttribute("Stat") == stat then "TabSelected" else "TabIdle") or b.BackgroundColor3
			b:SetAttribute("Selected", b:GetAttribute("Stat") == stat) -- stays grown (Util.ButtonFx)
		end
	end
	for _, b in window.Periods:GetChildren() do
		if b:IsA("GuiButton") then
			local on = b:GetAttribute("Period") == period
			b:SetAttribute("Selected", on) -- stays grown (Util.ButtonFx)
			b.BackgroundColor3 = gui:GetAttribute(if on then "PillSelected" else "PillIdle") or b.BackgroundColor3
			b.Label.TextColor3 = gui:GetAttribute(if on then "PillSelectedText" else "PillIdleText") or b.Label.TextColor3
		end
	end
end

local function fillRewards()
	local card = window.Rewards
	for _, c in card.Tiers:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local tiers = Leaderboards.Rewards[period]
	card.Title.Text = if tiers then Text.rewards else Text.allTime
	card.Note.Text = Text.allTimeNote
	card.Note.Visible = tiers == nil
	for index, tier in tiers or {} do
		local tc = window.Templates.TierCard:Clone()
		tc.Name = "Tier" .. index
		tc.LayoutOrder = index
		tc.Visible = true
		-- Ranks A (2026-10-21): the tier's colour is its badge (Label); the prizes read as
		-- one line ("1,000 coins · Chat tag · ...") instead of a row of tiny chips
		tc.Label.BackgroundColor3 = tc:GetAttribute("Fill" .. index) or tc.Label.BackgroundColor3
		tc.Label.Text = tier.label
		tc.Parent = card.Tiers
		local chip = window.Templates.Chip:Clone()
		chip.Name = "Prizes"
		chip.Visible = true
		chip.Text = table.concat(Leaderboards.describe(tier.reward), " · ")
		chip.Parent = tc.Chips
	end
end

-- The board's pieces, all hidden while the Trophies view shows.
local BOARD_PARTS = { "Tabs", "Stage", "Podium", "ListCard", "List", "Empty", "You", "Rewards", "ResetPill" }

local function trophyCounts(who: Player): { [string]: number }
	local out = {}
	local raw = who:GetAttribute("Trophies")
	if type(raw) == "string" then
		for key, n in raw:gmatch("([%w_]+)=(%d+)") do
			out[key] = tonumber(n) :: number
		end
	end
	return out
end

-- Fill a trophy shelf (this panel's Trophies, or the profile's copy) with `who`'s cups.
local function fillTrophies(box: Instance, who: Player)
	local counts = trophyCounts(who)
	local total = 0
	local faded = box:GetAttribute("EmptyCupTransparency")
	for _, board in Leaderboards.Stats do
		local row = box:FindFirstChild("Row_" .. board, true)
		if row then
			local name = row:FindFirstChild("BoardName")
			if name and name:IsA("TextLabel") then
				name.Text = Text.statShort[board] or board
			end
			for _, tier in Leaderboards.MedalOrder do
				local slot = row:FindFirstChild(tier)
				local n = counts[board .. "_" .. tier] or 0
				total += n
				if slot then
					local cup = slot:FindFirstChild("Cup")
					if cup and cup:IsA("ImageLabel") then
						cup.Image = Leaderboards.Medals[tier].cup
						cup.ImageTransparency = if n > 0 then 0 else (if type(faded) == "number" then faded else 0.65)
					end
					local count = slot:FindFirstChild("Count")
					if count and count:IsA("TextLabel") then
						count.Text = Text.trophyCount:format(n)
					end
					local place = slot:FindFirstChild("Place")
					if place and place:IsA("TextLabel") then
						place.Text = Text.trophyPlace[tier] or tier
					end
				end
			end
		end
	end
	local title = box:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = Text.trophiesTitle
	end
	local note = box:FindFirstChild("Note")
	if note and note:IsA("TextLabel") then
		note.Text = Text.noTrophies
		note.Visible = total == 0
	end
end

local function renderTrophies()
	local box = window:FindFirstChild("Trophies")
	if box then
		fillTrophies(box, player)
	end
end

-- The profile card's Trophies tab shows another player's shelf the same way.
function LeaderboardUI.fillTrophies(box: Instance, who: Player)
	fillTrophies(box, who)
end

-- Show the board or the Trophies view.
local function showView(trophies: boolean)
	for _, name in BOARD_PARTS do
		local part = window:FindFirstChild(name)
		if part and part:IsA("GuiObject") then
			part.Visible = not trophies and (name ~= "Empty" or part.Visible)
		end
	end
	local box = window:FindFirstChild("Trophies")
	if box and box:IsA("GuiObject") then
		box.Visible = trophies
	end
end

local function fitList()
	local layout = window.List:FindFirstChildOfClass("UIListLayout")
	local pad = window.List:FindFirstChildOfClass("UIPadding")
	if layout then
		local extra = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
		window.List.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + extra)
	end
end

function LeaderboardUI.refresh()
	if not window then
		return
	end
	styleTabs()
	if period == "Trophies" then
		showView(true)
		renderTrophies()
		return
	end
	showView(false)
	fillRewards()
	local data = fetch()
	local rows = if data then data.rows or {} else {}
	for rank = 1, 3 do
		local place = window.Podium:FindFirstChild("Place" .. rank)
		local row = rows[rank]
		if place then
			place.PlayerName.Text = if row then row.name else "—"
			place.Value.Text = if row then valueText(row.value) else ""
			place.Block.Rank.Text = tostring(rank)
			-- the drawn podium (option A, 2026-10-21): each step shows its player's headshot
			local avatar = place:FindFirstChild("Avatar")
			if avatar and avatar:IsA("ImageLabel") then
				avatar.Image = if row and row.userId then ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(row.userId) else ""
			end
		end
	end
	for _, c in window.List:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i = 4, #rows do
		local row = rows[i]
		local r = window.Templates.Row:Clone()
		r.Name = "Rank" .. row.rank
		r.LayoutOrder = row.rank
		r.Visible = true
		r.Rank.Text = tostring(row.rank)
		r.PlayerName.Text = row.name
		local avatar = r:FindFirstChild("Avatar")
		if avatar and avatar:IsA("ImageLabel") and row.userId then
			avatar.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(row.userId)
		end
		r.Value.Text = valueText(row.value)
		r.Parent = window.List
	end
	window.Empty.Text = Text.empty
	window.Empty.Visible = #rows == 0
	fitList()
	local you = if data then data.you else nil
	window.You.Rank.Text = if you and you.rank then Text.you:format(you.rank) else Text.youUnranked
	window.You.PlayerName.Text = player.Name
	window.You.Value.Text = valueText(if you then you.value or 0 else 0)
	shownResetsAt = if data then data.resetsAt else nil
end

-- the countdown ticks every second while open
local function tickReset()
	if not window then
		return
	end
	-- Reset sits in the header's ResetPill, a CenterRow with the hourglass (2026-10-21)
	local reset = window:FindFirstChild("Reset", true)
	if not (reset and reset:IsA("TextLabel")) then
		return
	end
	reset.Text = if shownResetsAt
		then Text.resetsIn:format(duration(shownResetsAt - Workspace:GetServerTimeNow()))
		else Text.never
end

function LeaderboardUI.toggle()
	if PanelWindow.isPanelOpen(PANEL) then
		PanelWindow.hidePanel()
	else
		PanelWindow.showPanel(PANEL)
		LeaderboardUI.refresh()
		tickReset()
	end
end

local function wire(found: ScreenGui)
	gui = found
	window = found:WaitForChild("Window")
	for _, b in window.Tabs:GetChildren() do
		local s = b:GetAttribute("Stat")
		if b:IsA("GuiButton") and type(s) == "string" then
			b.Label.Text = Text.stat[s] or s
			b.Activated:Connect(function()
				stat = s
				LeaderboardUI.refresh()
			end)
		end
	end
	for _, b in window.Periods:GetChildren() do
		local p = b:GetAttribute("Period")
		if b:IsA("GuiButton") and type(p) == "string" then
			b.Label.Text = Text.period[p] or p
			b.Activated:Connect(function()
				period = p
				LeaderboardUI.refresh()
				tickReset()
			end)
		end
	end
	if window:FindFirstChild("Title") then
		window.Title.Text = Text.title
	end
	if deps.Util.FontDrop then
		deps.Util.FontDrop.watch(found)
	end
	-- the rays behind the podium turn slowly (Ranks A, 2026-10-21)
	local stage = window:FindFirstChild("Stage")
	local rays = stage and stage:FindFirstChild("Rays")
	if rays and rays:IsA("GuiObject") then
		TweenService:Create(rays, TweenInfo.new(40, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
	end
	player:GetAttributeChangedSignal("Trophies"):Connect(function()
		if period == "Trophies" and found.Enabled then
			renderTrophies()
		end
	end)
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
	local button = hud and hud:FindFirstChild("LeaderboardButton", true)
	if button and button:IsA("GuiButton") then
		if deps.UI.HotbarUI and deps.UI.HotbarUI.wireHover then
			deps.UI.HotbarUI.wireHover(button)
		end
		button.Activated:Connect(LeaderboardUI.toggle)
	end
	task.spawn(function()
		local since = 0
		while true do
			task.wait(1)
			if found.Enabled then
				tickReset()
				since += 1
				if since >= CACHE_SECONDS then
					since = 0
					LeaderboardUI.refresh()
				end
			end
		end
	end)
end

function LeaderboardUI.init(injected: any)
	deps = injected
	PanelWindow = injected.UI.PanelWindow
end

function LeaderboardUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL, GUI_TIMEOUT)
		if found then
			wire(found)
		else
			warn("[LeaderboardUI] no Leaderboards panel (StarterGui/LeaderboardPanel)")
		end
	end)
end

return LeaderboardUI
