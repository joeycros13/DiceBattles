--!strict
-- LeaderboardUI: a click-to-open leaderboard popup shown from the Battle tab.
-- Call LeaderboardUI.attach(parent) to add a "Leaderboards" button plus a hidden
-- centered overlay into that parent; clicking the button opens the overlay, which
-- lists the global boards replicated by the server (R-L1/R-L2, ARCHITECTURE.md 8).
-- Vanilla Instances via UIFactory, responsive via Util/Responsive. Read-only: it
-- renders LeaderboardController data and re-renders on any update while visible.
--
-- Boards are data-driven from Config/Leaderboards, so a new leaderboard stat
-- shows up here automatically once the server replicates it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Leaderboards =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Leaderboards"))

local LeaderboardUI = {}

local deps: any = nil
local UIFactory: any = nil
local Responsive: any = nil
local LeaderboardController: any = nil

local MAX_ROWS = 10 -- rows shown per board (top N)

local overlay: Frame? = nil
local sectionBodies: { [string]: Frame } = {}

function LeaderboardUI.init(injected: any)
	deps = injected
	UIFactory = deps.Util.UIFactory
	Responsive = deps.Util.Responsive
	LeaderboardController = deps.Controllers.LeaderboardController
end

-- One "rank. name ......... value" row.
local function buildRow(rank: number, entry: any, order: number): Frame
	local Theme = UIFactory.Theme
	local isSelf = entry.userId == Players.LocalPlayer.UserId

	local row = UIFactory.frame({
		Name = "Row" .. rank,
		LayoutOrder = order,
		BackgroundColor3 = isSelf and Theme.PanelAlt or Theme.Panel,
		BackgroundTransparency = isSelf and 0 or 1,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(28)),
	})
	if isSelf then
		UIFactory.corner(Responsive.scaled(4)).Parent = row
	end

	local rankLabel = UIFactory.textLabel({
		Name = "Rank",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(0, Responsive.scaled(34), 1, 0),
		Text = ("%d."):format(rank),
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(15),
	})
	rankLabel.Parent = row

	-- Name column takes all remaining width (card is wide enough for full names).
	local nameLabel = UIFactory.textLabel({
		Name = "PlayerName",
		Position = UDim2.new(0, Responsive.scaled(34), 0, 0),
		Size = UDim2.new(1, -Responsive.scaled(34 + 64), 1, 0),
		Text = entry.name,
		TextColor3 = isSelf and Theme.Accent or Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Theme.Font,
		TextSize = Responsive.scaled(15),
	})
	nameLabel.Parent = row

	local valueLabel = UIFactory.textLabel({
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, Responsive.scaled(60), 1, 0),
		Text = tostring(entry.value),
		TextColor3 = Theme.Positive,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(15),
	})
	valueLabel.Parent = row

	return row
end

-- One board section: heading + rows container. Rows are filled in by refresh().
local function buildSection(def: any, order: number): Frame
	local Theme = UIFactory.Theme
	local section = UIFactory.frame({
		Name = def.statName .. "Section",
		LayoutOrder = order,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	})
	local sLayout = UIFactory.listLayout({ Padding = UDim.new(0, Responsive.scaled(2)) })
	sLayout.Parent = section

	local heading = UIFactory.textLabel({
		Name = "Heading",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(20)),
		Text = def.displayName,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(15),
	})
	heading.Parent = section

	local rows = UIFactory.frame({
		Name = "Rows",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	})
	local rLayout = UIFactory.listLayout({ Padding = UDim.new(0, Responsive.scaled(1)) })
	rLayout.Parent = rows
	rows.Parent = section

	sectionBodies[def.statName] = rows
	return section
end

-- Re-render every section's rows from the latest replicated data.
local function refresh()
	local Theme = UIFactory.Theme
	for statName, rows in sectionBodies do
		for _, child in rows:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end

		local entries = LeaderboardController.get(statName)
		if #entries == 0 then
			local empty = UIFactory.textLabel({
				Name = "Empty",
				LayoutOrder = 0,
				Size = UDim2.new(1, 0, 0, Responsive.scaled(20)),
				Text = "No entries yet",
				TextColor3 = Theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Theme.Font,
				TextSize = Responsive.scaled(12),
			})
			empty.Parent = rows
		else
			for rank = 1, math.min(#entries, MAX_ROWS) do
				local row = buildRow(rank, entries[rank], rank)
				row.Parent = rows
			end
		end
	end
end

local function close()
	if overlay then
		overlay.Visible = false
	end
end

local function open()
	if overlay then
		refresh()
		overlay.Visible = true
	end
end

-- Build the hidden popup overlay (dark backdrop + centered card + scrollable
-- board sections) into `parent`. Mirrors the Battle tab's chapter-list overlay.
local function buildOverlay(parent: Instance)
	local Theme = UIFactory.Theme

	local root = UIFactory.frame({
		Name = "LeaderboardOverlay",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 30,
	})
	root.Parent = parent
	overlay = root

	-- Click-off backdrop closes the popup.
	local backdrop = UIFactory.textButton({
		Name = "Backdrop",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
	})
	backdrop.Parent = root
	backdrop.Activated:Connect(close)

	local card = UIFactory.frame({
		Name = "Card",
		BackgroundColor3 = Theme.Background,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.95, 0, 0.86, 0),
		ZIndex = 31,
	})
	card.Parent = root
	UIFactory.corner(14).Parent = card
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = card
	UIFactory.padding(Responsive.scaled(16)).Parent = card
	-- Wide enough to show full player names without truncation on any device.
	UIFactory.create("UISizeConstraint", {
		MaxSize = Vector2.new(Responsive.scaled(680), math.huge),
	}).Parent = card

	local headerH = Responsive.scaled(40)

	local header = UIFactory.textLabel({
		Name = "Header",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, -Responsive.scaled(40), 0, headerH),
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Leaderboards",
		ZIndex = 31,
	})
	header.Parent = card

	local closeBtn = UIFactory.textButton({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(headerH, headerH),
		BackgroundColor3 = Theme.PanelAlt,
		Text = "X",
		TextSize = Responsive.scaled(16),
		ZIndex = 32,
	})
	UIFactory.corner(8).Parent = closeBtn
	closeBtn.Parent = card
	closeBtn.Activated:Connect(close)

	local scroll = UIFactory.scrolling({
		Name = "BoardScroll",
		Position = UDim2.new(0, 0, 0, headerH + Responsive.scaled(10)),
		Size = UDim2.new(1, 0, 1, -(headerH + Responsive.scaled(10))),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 31,
	})
	scroll.Parent = card
	local layout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Responsive.scaled(16)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	layout.Parent = scroll
	local sidePad = scroll.ScrollBarThickness + Responsive.scaled(4)
	UIFactory.create("UIPadding", {
		PaddingLeft = UDim.new(0, sidePad),
		PaddingRight = UDim.new(0, sidePad),
	}).Parent = scroll

	table.clear(sectionBodies)
	for order, def in Leaderboards.all() do
		local section = buildSection(def, order)
		section.Parent = scroll
		for _, child in section:GetDescendants() do
			if child:IsA("GuiObject") then
				child.ZIndex = 31
			end
		end
		section.ZIndex = 31
	end
end

-- Add a "Leaderboards" button (top-right of `parent`) and the popup overlay it
-- opens. Called by the Battle tab so the board lives only there (R-L2 display).
function LeaderboardUI.attach(parent: Instance)
	local Theme = UIFactory.Theme

	local button = UIFactory.textButton({
		Name = "LeaderboardButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Responsive.scaled(10), 0, Responsive.scaled(10)),
		Size = UDim2.fromOffset(Responsive.scaled(150), Responsive.scaled(36)),
		BackgroundColor3 = Theme.Accent,
		Text = "Leaderboards",
		TextSize = Responsive.scaled(16),
		ZIndex = 6,
	})
	UIFactory.corner(Responsive.scaled(8)).Parent = button
	UIFactory.stroke({ Color = Theme.AccentText, Thickness = 1, Transparency = 0.7 }).Parent = button
	button.Parent = parent
	button.Activated:Connect(open)

	buildOverlay(parent)

	-- Keep rows current while the popup is open.
	LeaderboardController.onChanged(function()
		if overlay and overlay.Visible then
			refresh()
		end
	end)
end

-- No standalone GUI; the Battle tab drives this via attach().
function LeaderboardUI.start() end

return LeaderboardUI
