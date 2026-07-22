--!strict
-- BattleTab: the Battle view (R-B1..R-B3). The default view shows the player's
-- current chapter with a Start Battle button (R-B1). Clicking the chapter card
-- (the "level", NOT the Start Battle button) opens a scrollable list of every
-- chapter, ordered so scrolling UP reveals upcoming/locked chapters and scrolling
-- DOWN reveals beaten ones (R-B2); the list auto-centers on the current chapter.
-- Start Battle sends intent via the StartBattle remote; the server owns all combat
-- state. Progress is read from DataController (server-authoritative): a chapter is
-- BEATEN when its id <= progress.chaptersCompleted, CURRENT when it equals
-- progress.currentChapter, and LOCKED otherwise. The default view re-renders on
-- ProfileUpdated, so it advances automatically once a chapter is completed (R-B3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Chapters = require(Config:WaitForChild("Chapters"))

local BattleTab = {}

local deps: any = nil
local UIFactory: any = nil
local Responsive: any = nil
local MenuShell: any = nil
local DataController: any = nil
local startBattleRemote: RemoteEvent? = nil

-- Default-view widgets (kept for re-render / re-layout).
local rootFrame: Frame? = nil
local chapterCard: TextButton? = nil
local cardNumberLabel: TextLabel? = nil
local cardNameLabel: TextLabel? = nil
local cardSubtitleLabel: TextLabel? = nil
local startButton: TextButton? = nil

-- Chapter-list overlay widgets.
local listOverlay: Frame? = nil
local listScroll: ScrollingFrame? = nil
type RowWidget = {
	frame: TextButton,
	stroke: UIStroke,
	title: TextLabel,
	status: TextLabel,
}
local rowWidgets: { [number]: RowWidget } = {}

-- ==================== progress helpers ====================

type ChapterStatus = "beaten" | "current" | "locked"

-- Where a chapter sits in the player's progression (server-authoritative).
local function chapterStatus(data: any, id: number): ChapterStatus
	local progress = data.progress or {}
	local completed = progress.chaptersCompleted or 0
	local current = progress.currentChapter or 1
	if id <= completed then
		return "beaten"
	elseif id == current then
		return "current"
	end
	return "locked"
end

-- The chapter the default view should feature: the current one, clamped to the
-- range of defined chapters (guards a currentChapter that ran past the last one
-- after everything is beaten).
local function displayChapterId(data: any): number
	local current = (data.progress and data.progress.currentChapter) or 1
	return math.clamp(current, 1, Chapters.count())
end

-- ==================== default view render ====================

local function render()
	local data = DataController.get()
	if not data then
		return
	end

	local id = displayChapterId(data)
	local def = Chapters.get(id)
	local status = chapterStatus(data, id)
	local allBeaten = (data.progress and data.progress.chaptersCompleted or 0) >= Chapters.count()

	if cardNumberLabel then
		cardNumberLabel.Text = ("CHAPTER %d / %d"):format(id, Chapters.count())
	end
	if cardNameLabel then
		cardNameLabel.Text = def and def.name or ("Chapter " .. id)
	end
	if cardSubtitleLabel then
		local stageCount = def and #def.stages or 0
		cardSubtitleLabel.Text = ("%d Stages   -   Tap to view all chapters"):format(stageCount)
	end

	if startButton then
		local Theme = UIFactory.Theme
		if allBeaten and status ~= "current" then
			-- Every chapter cleared: allow replaying the final chapter.
			startButton.Text = "Replay Chapter"
		else
			startButton.Text = "Start Battle"
		end
		startButton.BackgroundColor3 = Theme.Accent
		startButton.AutoButtonColor = true
	end
end

-- ==================== chapter list overlay ====================

local function closeList()
	if listOverlay then
		listOverlay.Visible = false
	end
end

-- Repaint every row from the latest progression data.
local function renderRows(data: any)
	local Theme = UIFactory.Theme
	for id, widget in rowWidgets do
		local def = Chapters.get(id)
		local status = chapterStatus(data, id)
		widget.title.Text = ("Chapter %d   -   %s"):format(id, def and def.name or "?")

		-- Locked chapters are non-interactive: no hover highlight, no hand cursor,
		-- and clicks do nothing (Active = false) so it reads as unselectable.
		local interactive = status ~= "locked"
		widget.frame.Active = interactive
		widget.frame.AutoButtonColor = interactive
		widget.frame.Selectable = interactive

		if status == "beaten" then
			widget.frame.BackgroundColor3 = Theme.Panel
			widget.stroke.Color = Theme.Positive
			widget.status.Text = "CLEARED"
			widget.status.TextColor3 = Theme.Positive
			widget.title.TextColor3 = Theme.Text
		elseif status == "current" then
			widget.frame.BackgroundColor3 = Theme.PanelAlt
			widget.stroke.Color = Theme.Accent
			widget.status.Text = "CURRENT"
			widget.status.TextColor3 = Theme.Accent
			widget.title.TextColor3 = Theme.Text
		else
			widget.frame.BackgroundColor3 = Theme.Panel
			widget.stroke.Color = Theme.Stroke
			widget.status.Text = "LOCKED"
			widget.status.TextColor3 = Theme.SubText
			widget.title.TextColor3 = Theme.SubText
		end
	end
end

-- Scroll the list so the current chapter sits centered in the viewport, giving
-- headroom to scroll up (locked) and down (beaten) as required by R-B2.
local function centerOnCurrent(data: any)
	local scroll = listScroll
	if not scroll then
		return
	end
	local row = rowWidgets[displayChapterId(data)]
	if not row then
		return
	end
	local frame = row.frame
	local offset = (frame.AbsolutePosition.Y - scroll.AbsolutePosition.Y) + scroll.CanvasPosition.Y
	local target = offset - (scroll.AbsoluteWindowSize.Y - frame.AbsoluteSize.Y) / 2
	local maxScroll = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
	scroll.CanvasPosition = Vector2.new(0, math.clamp(target, 0, maxScroll))
end

local function openList()
	local data = DataController.get()
	if not (data and listOverlay) then
		return
	end
	renderRows(data)
	listOverlay.Visible = true
	-- Defer so absolute sizes/positions are valid before we center the scroll.
	task.defer(function()
		if listOverlay and listOverlay.Visible then
			centerOnCurrent(data)
		end
	end)
end

-- Build one chapter row. Rows are informational + close the list on click; the
-- player only ever battles their current chapter via Start Battle.
local function buildRow(id: number): RowWidget
	local Theme = UIFactory.Theme
	-- Descending LayoutOrder puts the highest (locked/upcoming) chapters at the
	-- TOP and chapter 1 (beaten) at the BOTTOM (R-B2).
	local button = UIFactory.textButton({
		Name = "Chapter" .. id,
		LayoutOrder = Chapters.count() - id,
		BackgroundColor3 = Theme.Panel,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(64)),
		Text = "",
	})
	UIFactory.corner(10).Parent = button
	local stroke = UIFactory.stroke({ Color = Theme.Stroke, Thickness = 2 })
	stroke.Parent = button
	UIFactory.padding(Responsive.scaled(12)).Parent = button

	local title = UIFactory.textLabel({
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0.68, 0, 1, 0),
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	title.Parent = button

	local status = UIFactory.textLabel({
		Name = "Status",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.3, 0, 1, 0),
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(14),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	status.Parent = button

	button.Activated:Connect(closeList)

	return {
		frame = button,
		stroke = stroke,
		title = title,
		status = status,
	}
end

local function buildListOverlay(parent: Instance)
	local Theme = UIFactory.Theme
	local overlay = UIFactory.frame({
		Name = "ChapterList",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
	})
	overlay.Parent = parent
	listOverlay = overlay

	-- Click-off backdrop closes the list.
	local backdrop = UIFactory.textButton({
		Name = "Backdrop",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
	})
	backdrop.Parent = overlay
	backdrop.Activated:Connect(closeList)

	local card = UIFactory.frame({
		Name = "Card",
		BackgroundColor3 = Theme.Background,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.86, 0),
		ZIndex = 21,
	})
	card.Parent = overlay
	UIFactory.corner(14).Parent = card
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = card
	UIFactory.padding(Responsive.scaled(16)).Parent = card
	UIFactory.create("UISizeConstraint", {
		MaxSize = Vector2.new(Responsive.scaled(460), math.huge),
	}).Parent = card

	local headerH = Responsive.scaled(40)

	local header = UIFactory.textLabel({
		Name = "Header",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, -Responsive.scaled(40), 0, headerH),
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Chapters",
		ZIndex = 21,
	})
	header.Parent = card

	local close = UIFactory.textButton({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(headerH, headerH),
		BackgroundColor3 = Theme.PanelAlt,
		Text = "X",
		TextSize = Responsive.scaled(16),
		ZIndex = 22,
	})
	UIFactory.corner(8).Parent = close
	close.Parent = card
	close.Activated:Connect(closeList)

	local scroll = UIFactory.scrolling({
		Name = "ChapterScroll",
		Position = UDim2.new(0, 0, 0, headerH + Responsive.scaled(10)),
		Size = UDim2.new(1, 0, 1, -(headerH + Responsive.scaled(10))),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 21,
	})
	scroll.Parent = card
	listScroll = scroll
	local layout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Responsive.scaled(8)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	layout.Parent = scroll
	-- Pad both sides equally (accounting for the scrollbar on the right) so rows
	-- stay horizontally centered in the card instead of leaning to the left.
	local sidePad = scroll.ScrollBarThickness + Responsive.scaled(4)
	UIFactory.create("UIPadding", {
		PaddingLeft = UDim.new(0, sidePad),
		PaddingRight = UDim.new(0, sidePad),
	}).Parent = scroll

	table.clear(rowWidgets)
	for _, id in Chapters.Order do
		local widget = buildRow(id)
		widget.frame.Parent = scroll
		widget.frame.ZIndex = 21
		rowWidgets[id] = widget
	end
end

-- ==================== start battle ====================

local function onStartBattle()
	local data = DataController.get()
	if not (data and startBattleRemote) then
		return
	end
	-- Send intent only; the server validates and drives combat (server-authoritative).
	startBattleRemote:FireServer(displayChapterId(data))
end

-- ==================== build ====================

function BattleTab.init(injected: any)
	deps = injected
	UIFactory = deps.Util.UIFactory
	Responsive = deps.Util.Responsive
	MenuShell = deps.UI.MenuShell
	DataController = deps.Controllers.DataController
	startBattleRemote = deps.Remotes.getEvent("StartBattle")
end

function BattleTab.start()
	local content = MenuShell.getContentFrame("Battle")
	if not content then
		warn("[BattleTab] Battle content frame missing")
		return
	end

	-- Remove the shell placeholder now that we render the real view.
	local placeholder = content:FindFirstChild("Placeholder")
	if placeholder then
		placeholder:Destroy()
	end

	local Theme = UIFactory.Theme
	local root = UIFactory.frame({
		Name = "BattleRoot",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	root.Parent = content
	rootFrame = root

	local startH = Responsive.scaled(60)
	local gap = Responsive.scaled(12)

	-- Chapter card fills the space above the Start Battle button. The whole card
	-- is the clickable "level" that opens the chapter list (R-B2).
	local card = UIFactory.textButton({
		Name = "ChapterCard",
		BackgroundColor3 = Theme.Panel,
		AutoButtonColor = false,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 1, -(startH + gap)),
		Text = "",
	})
	UIFactory.corner(16).Parent = card
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = card
	UIFactory.padding(Responsive.scaled(20)).Parent = card
	card.Parent = root
	chapterCard = card

	local stack = UIFactory.frame({
		Name = "Stack",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	})
	stack.Parent = card
	local stackLayout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Responsive.scaled(10)),
	})
	stackLayout.Parent = stack

	local numberLabel = UIFactory.textLabel({
		Name = "ChapterNumber",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, Responsive.scaled(22)),
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextSize = Responsive.scaled(18),
		Text = "CHAPTER 1",
	})
	numberLabel.Parent = stack
	cardNumberLabel = numberLabel

	local nameLabel = UIFactory.textLabel({
		Name = "ChapterName",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(44)),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = Responsive.scaled(40),
		TextWrapped = true,
		Text = "...",
	})
	nameLabel.Parent = stack
	cardNameLabel = nameLabel

	local subtitleLabel = UIFactory.textLabel({
		Name = "Subtitle",
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(20)),
		TextColor3 = Theme.SubText,
		TextSize = Responsive.scaled(16),
		TextWrapped = true,
		Text = "",
	})
	subtitleLabel.Parent = stack
	cardSubtitleLabel = subtitleLabel

	card.Activated:Connect(openList)

	-- Start Battle button pinned to the bottom, full width (R-B1).
	local start = UIFactory.textButton({
		Name = "StartButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, startH),
		BackgroundColor3 = Theme.Accent,
		TextSize = Responsive.scaled(26),
		Text = "Start Battle",
	})
	UIFactory.corner(12).Parent = start
	start.Parent = root
	startButton = start
	start.Activated:Connect(onStartBattle)

	-- Chapter list overlay lives above the default view within this tab.
	buildListOverlay(root)

	-- Re-render on any authoritative profile change (advances to the next chapter
	-- after one is beaten, per R-B3).
	DataController.onChanged(function()
		render()
		if listOverlay and listOverlay.Visible then
			local data = DataController.get()
			if data then
				renderRows(data)
			end
		end
	end)
	if DataController.get() then
		render()
	end
end

return BattleTab
