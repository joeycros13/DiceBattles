--!strict
-- PlayerListUI: our own player list in the top-right corner (option B "Aqua
-- panel", the user's pick on https://claude.ai/artifact/TCrLRPcksd1n63eFStF2SD,
-- 2026-10-19). It replaces Roblox's PlayerList CoreGui and shows every player's
-- name, level and coins, sorted by level, then coins; the local player's row is
-- highlighted.
--
-- Hand-built StarterGui/PlayerList (the Inventory's aqua look):
--   Panel                     top right; code sets its height to fit the rows
--                             and its top gap to match its right gap
--     Shadow, Rim             the drop shadow and the teal outline
--     Body (a plain Frame, UIListLayout; not a CanvasGroup, whose UIGradient
--       would tint every row)
--       Header/Title, Header/Count/Label   "Players", "3 / 12"
--       Heads                 Player / Level / Coins column heads
--       Rows (ScrollingFrame) clones of Templates/Row
--       Foot                  the gap under the last row
--   Templates/Row             Hit (an invisible button over the row: opens that player's
--                             profile card, ProfileUI), PlayerName, Level, Coins, Medal (a hidden dark chip right of
--                             the name: Icon = the medal, Label "#1 Coins" in the medal's
--                             colour, its UIStroke the same; shown while the player wears a
--                             weekly leaderboard medal, and the name box narrows to its
--                             NarrowWidth attribute so the two never overlap: option B on
--                             https://claude.ai/artifact/Sjkt4yWCvqYH2dWYRot9Vg, 2026-10-22);
--                             Fill<Even|Odd|You> / Transparency<...> attributes
--                             (no border: a gold stroke on the yellow row only
--                             showed as dark spots at its rounded corners)
-- Gui attributes: MaxRows (rows shown before the list scrolls), CountFormat,
-- ToggleKey (a KeyCode name; it folds the list down to the header, like
-- Roblox's own), PushDown (comma list of "<ScreenGui>/<child>" HUD pieces on
-- the right that move down to stay clear of the panel) and PushGap (the gap
-- left under it, a share of the screen height).
--
-- Level and Coins are the players' own attributes (ExpService, CoinService),
-- and LeaderMedal / LeaderMedalBoard the medal LeaderboardService gave them, which
-- replicate to every client. Coins read through Format.coins (1.1M).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Leaderboards = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Leaderboards"))

local PlayerListUI = {}

local player = Players.LocalPlayer
local deps: any = nil
local gui: ScreenGui? = nil
local panel: Frame? = nil
local rowsFrame: ScrollingFrame? = nil
local template: Frame? = nil
local folded = false
local rows: { [Player]: Frame } = {}
local watching: { [Player]: { RBXScriptConnection } } = {}
local pushed: { { target: GuiObject, baseY: number } } = {}
local renderQueued = false

local function attr(inst: Instance, name: string, fallback: any): any
	local v = inst:GetAttribute(name)
	return if v ~= nil then v else fallback
end

local function number(who: Player, name: string, fallback: number): number
	local v = who:GetAttribute(name)
	return if type(v) == "number" then v else fallback
end

-- Roblox's own list is turned off; SetCore can fail while the CoreGui loads.
local function hideCoreList()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

-- The panel is as tall as its header, column heads, foot and the rows shown
-- (up to MaxRows; more scroll). Then the HUD pieces under it move clear.
local function fit()
	local g, p, list = gui, panel, rowsFrame
	if not (g and p and list) then
		return
	end
	local body = p:FindFirstChild("Body") :: GuiObject?
	local layout = list:FindFirstChildWhichIsA("UIListLayout")
	local parentHeight = g.AbsoluteSize.Y
	if not (body and layout) or parentHeight <= 0 then
		return
	end
	local fixed = 0
	for _, name in { "Header", "Heads", "Foot" } do
		local piece = body:FindFirstChild(name) :: GuiObject?
		if piece and piece.Visible then
			fixed += piece.AbsoluteSize.Y
		end
	end
	local content = layout.AbsoluteContentSize.Y
	local shown = content
	local maxRows = attr(g, "MaxRows", 5) :: number
	local count = 0
	local first: Frame? = nil
	for _, row in rows do
		count += 1
		first = first or row
	end
	if count > maxRows and first then
		local gap = layout.Padding.Offset + layout.Padding.Scale * list.AbsoluteSize.Y
		shown = maxRows * first.AbsoluteSize.Y + (maxRows - 1) * gap
	end
	list.CanvasSize = UDim2.fromOffset(0, content)
	local height = fixed + (if folded then 0 else shown)
	p.Size = UDim2.new(p.Size.X.Scale, 0, height / parentHeight, 0)

	-- The gap above the panel matches the one on its right (the user,
	-- 2026-10-19), measured from the top of the screen: the gui sits under
	-- Roblox's top bar, so the panel reaches up into it.
	local rightGap = g.AbsolutePosition.X + g.AbsoluteSize.X - (p.AbsolutePosition.X + p.AbsoluteSize.X)
	local inset = if g.ScreenInsets == Enum.ScreenInsets.None or g.ScreenInsets == Enum.ScreenInsets.DeviceSafeInsets then 0 else GuiService:GetGuiInset().Y
	p.Position = UDim2.new(p.Position.X, UDim.new((rightGap - inset) / parentHeight, 0))

	-- push the right-hand HUD pieces below the panel (and its shadow)
	local bottom = p.AbsolutePosition.Y + p.AbsoluteSize.Y
	local shadow = p:FindFirstChild("Shadow") :: GuiObject?
	if shadow then
		bottom = math.max(bottom, shadow.AbsolutePosition.Y + shadow.AbsoluteSize.Y)
	end
	-- In PushDown order, each piece also clears the one before it while that
	-- one shows (the toasts stay under a pushed quest tracker).
	local gap = (attr(g, "PushGap", 0.015) :: number) * parentHeight
	bottom += gap
	for _, entry in pushed do
		local target = entry.target
		local holder: any = target.Parent
		if holder and (holder:IsA("LayerCollector") or holder:IsA("GuiObject")) then
			local h = holder.AbsoluteSize.Y
			local top = holder.AbsolutePosition.Y
			if h > 0 then
				local baseTop = top + entry.baseY * h - target.AnchorPoint.Y * target.AbsoluteSize.Y
				local shift = math.max(0, bottom - baseTop)
				target.Position = UDim2.new(target.Position.X, UDim.new(entry.baseY + shift / h, 0))
				local shown = target.Visible and (not holder:IsA("ScreenGui") or holder.Enabled)
				if shown then
					bottom = math.max(bottom, baseTop + shift + target.AbsoluteSize.Y + gap)
				end
			end
		end
	end
end

local function style(row: Frame, key: string)
	local t = template :: Frame
	row.BackgroundColor3 = attr(t, "Fill" .. key, row.BackgroundColor3)
	row.BackgroundTransparency = attr(t, "Transparency" .. key, row.BackgroundTransparency)
end

local function render()
	renderQueued = false
	local g = gui
	if not g then
		return
	end
	local Format = deps.Util.Format
	local order = {}
	for who, row in rows do
		table.insert(order, who)
		local name = row:FindFirstChild("PlayerName") :: TextLabel?
		if name then
			name.Text = who.DisplayName
		end
		local level = row:FindFirstChild("Level") :: TextLabel?
		if level then
			level.Text = Format.commas(number(who, "Level", 1))
		end
		local coins = row:FindFirstChild("Coins") :: TextLabel?
		if coins then
			coins.Text = Format.coins(number(who, "Coins", 0))
		end
		-- this week's leaderboard medal: the chip names the board ("#1 Coins")
		local chip = row:FindFirstChild("Medal") :: Frame?
		local tier = who:GetAttribute("LeaderMedal")
		local board = who:GetAttribute("LeaderMedalBoard")
		local medal = if type(tier) == "string" then Leaderboards.Medals[tier] else nil
		if chip then
			chip.Visible = medal ~= nil and type(board) == "string"
			if medal and type(board) == "string" then
				local icon = chip:FindFirstChild("Icon") :: ImageLabel?
				if icon then
					icon.Image = medal.medal
				end
				local text = chip:FindFirstChild("Label") :: TextLabel?
				if text then
					text.Text = Leaderboards.Text.medalChip:format(medal.place, Leaderboards.Text.statShort[board] or board)
					text.TextColor3 = medal.fill
				end
				local stroke = chip:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = medal.fill
				end
			end
		end
		if name then
			local wide = ((template :: Frame):FindFirstChild("PlayerName") :: TextLabel).Size
			local narrow = name:GetAttribute("NarrowWidth")
			name.Size = if chip and chip.Visible and type(narrow) == "number" then UDim2.new(narrow, 0, wide.Y.Scale, 0) else wide
		end
	end
	-- level, then coins, then name so ties don't swap places
	table.sort(order, function(a, b)
		local la, lb = number(a, "Level", 1), number(b, "Level", 1)
		if la ~= lb then
			return la > lb
		end
		local ca, cb = number(a, "Coins", 0), number(b, "Coins", 0)
		if ca ~= cb then
			return ca > cb
		end
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	for i, who in order do
		local row = rows[who]
		row.LayoutOrder = i
		style(row, if who == player then "You" elseif i % 2 == 0 then "Odd" else "Even")
	end
	local count = g:FindFirstChild("Count", true)
	local label = count and count:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = (attr(g, "CountFormat", "%d / %d") :: string):format(#order, Players.MaxPlayers)
	end
	task.defer(fit)
end

local function queue()
	if not renderQueued then
		renderQueued = true
		task.defer(render)
	end
end

local function add(who: Player)
	local list, t = rowsFrame, template
	if not (list and t) or rows[who] then
		return
	end
	local row = t:Clone()
	row.Name = "Row_" .. who.UserId
	row.Visible = true
	row.Parent = list
	rows[who] = row
	-- a click on a row opens that player's profile card (ProfileUI; 2026-10-23)
	local hit = row:FindFirstChild("Hit")
	if hit and hit:IsA("GuiButton") then
		hit.Activated:Connect(function()
			local profile = deps and deps.UI and deps.UI.ProfileUI
			if profile and who.Parent then
				profile.show(who)
			end
		end)
	end
	watching[who] = {
		who:GetAttributeChangedSignal("Level"):Connect(queue),
		who:GetAttributeChangedSignal("Coins"):Connect(queue),
		who:GetAttributeChangedSignal("LeaderMedal"):Connect(queue),
		who:GetAttributeChangedSignal("LeaderMedalBoard"):Connect(queue),
		who:GetPropertyChangedSignal("DisplayName"):Connect(queue),
	}
	queue()
end

local function remove(who: Player)
	local row = rows[who]
	if row then
		row:Destroy()
		rows[who] = nil
	end
	for _, c in watching[who] or {} do
		c:Disconnect()
	end
	watching[who] = nil
	queue()
end

function PlayerListUI.init(injected: any)
	deps = injected
end

function PlayerListUI.start()
	task.spawn(hideCoreList)
	task.spawn(function()
		local found = player:WaitForChild("PlayerGui"):WaitForChild("PlayerList", 15)
		if not (found and found:IsA("ScreenGui")) then
			warn("[PlayerListUI] no StarterGui/PlayerList")
			return
		end
		local templates = found:FindFirstChild("Templates")
		local list = found:FindFirstChild("Rows", true) :: ScrollingFrame?
		local foundPanel = found:FindFirstChild("Panel") :: Frame?
		local row = templates and templates:FindFirstChild("Row") :: Frame?
		if not (foundPanel and list and row) then
			warn("[PlayerListUI] PlayerList is missing Panel, Rows or Templates/Row")
			return
		end
		gui, panel, rowsFrame, template = found, foundPanel, list, row
		-- the preview rows from Edit mode
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		deps.Util.FontDrop.watch(found)

		-- the HUD pieces that move down to stay clear
		local playerGui = player.PlayerGui
		for _, path in (attr(found, "PushDown", "") :: string):split(",") do
			local guiName, childName = path:match("^%s*([^/]+)/(.-)%s*$")
			if guiName and childName then
				local holder = playerGui:WaitForChild(guiName, 15)
				local target = holder and holder:FindFirstChild(childName)
				if target and target:IsA("GuiObject") then
					table.insert(pushed, { target = target, baseY = target.Position.Y.Scale })
					-- a piece showing or hiding moves the ones under it
					target:GetPropertyChangedSignal("Visible"):Connect(fit)
					target:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
				end
			end
		end

		for _, who in Players:GetPlayers() do
			add(who)
		end
		Players.PlayerAdded:Connect(add)
		Players.PlayerRemoving:Connect(remove)
		found:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		local layout = list:FindFirstChildWhichIsA("UIListLayout")
		if layout then
			layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
		end

		local key = Enum.KeyCode:FromName(attr(found, "ToggleKey", "Tab") :: string)
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or input.KeyCode ~= key then
				return
			end
			folded = not folded
			list.Visible = not folded
			local heads = found:FindFirstChild("Heads", true) :: GuiObject?
			if heads then
				heads.Visible = not folded
			end
			fit()
		end)
		render()
	end)
end

return PlayerListUI
