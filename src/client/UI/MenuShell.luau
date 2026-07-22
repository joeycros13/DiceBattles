--!strict
-- MenuShell: the root menu ScreenGui with the bottom tabs (Equipment, Battle,
-- Talents, Shop) and tab switching (R-M1). Owns the shared layout chrome and exposes a
-- content container per tab so the individual tab modules (later steps) parent
-- their views into it. Responsive for phone and desktop (R-M2) via Util/Responsive.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GlobalLevel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("GlobalLevel"))

local MenuShell = {}

local deps: any = nil
local UIFactory: any = nil
local Responsive: any = nil
local AssetResolver: any = nil
local DataController: any = nil

-- Bottom tabs, left-to-right (R-M1).
local TAB_ORDER = { "Equipment", "Battle", "Talents", "Shop" }

-- Design-pixel heights for the bottom tab bar per form factor (scaled at runtime).
local TABBAR_HEIGHT_DESKTOP = 66
local TABBAR_HEIGHT_PHONE = 104

-- Design-pixel heights for the persistent top header (global level + XP bar).
local HEADER_HEIGHT_DESKTOP = 52
local HEADER_HEIGHT_PHONE = 72

local screenGui: ScreenGui? = nil
local contentArea: Frame? = nil
local tabBar: Frame? = nil

-- Persistent global-level header widgets (R-C22 feedback).
local headerBar: Frame? = nil
local levelBadge: Frame? = nil
local levelBadgeLabel: TextLabel? = nil
local xpTrack: Frame? = nil
local xpFill: Frame? = nil
local xpLabel: TextLabel? = nil

local contentFrames: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}
local tabButtonLabels: { [string]: TextLabel } = {}
local activeTab: string? = nil
local tabChangedEvent: BindableEvent? = nil

function MenuShell.init(injected: any)
	deps = injected
	UIFactory = deps.Util.UIFactory
	Responsive = deps.Util.Responsive
	AssetResolver = deps.Util.AssetResolver
	DataController = deps.Controllers.DataController
	tabChangedEvent = Instance.new("BindableEvent")
end

-- Build a single content panel (one per tab). Later tab modules parent into it.
local function buildContentFrame(tabId: string): Frame
	local Theme = UIFactory.Theme
	local frame = UIFactory.frame({
		Name = tabId .. "Content",
		BackgroundColor3 = Theme.Background,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	})
	UIFactory.padding(Responsive.scaled(12)).Parent = frame

	-- Placeholder shown until the dedicated tab module renders its own view.
	local placeholder = UIFactory.textLabel({
		Name = "Placeholder",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Theme.SubText,
		TextSize = Responsive.scaled(22),
		Font = Theme.FontBold,
		Text = tabId,
	})
	placeholder.Parent = frame

	return frame
end

-- Build one bottom-bar tab button (icon placeholder + label), wired to switch tabs.
local function buildTabButton(tabId: string, order: number): TextButton
	local Theme = UIFactory.Theme
	local button = UIFactory.textButton({
		Name = tabId .. "Tab",
		LayoutOrder = order,
		Size = UDim2.fromScale(1 / #TAB_ORDER, 1),
		BackgroundColor3 = Theme.Panel,
		AutoButtonColor = false,
		Text = "",
	})

	local stack = UIFactory.frame({
		Name = "Stack",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	stack.Parent = button
	local layout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Responsive.scaled(4)),
	})
	layout.Parent = stack

	local visual = AssetResolver.resolve("tab/" .. tabId)
	local iconSize = Responsive.scaled(Responsive.isCompact() and 30 or 26)
	local icon = UIFactory.frame({
		Name = "Icon",
		LayoutOrder = 1,
		BackgroundColor3 = visual.color,
		Size = UDim2.fromOffset(iconSize, iconSize),
	})
	UIFactory.corner(math.floor(iconSize / 4)).Parent = icon
	local glyph = UIFactory.textLabel({
		Size = UDim2.fromScale(1, 1),
		Text = visual.label,
		TextColor3 = Theme.AccentText,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(12),
	})
	glyph.Parent = icon
	icon.Parent = stack

	local label = UIFactory.textLabel({
		Name = "Label",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Responsive.scaled(18)),
		Text = tabId,
		TextColor3 = Theme.SubText,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(Responsive.isCompact() and 15 or 14),
	})
	label.Parent = stack
	tabButtonLabels[tabId] = label

	button.Activated:Connect(function()
		MenuShell.showTab(tabId)
	end)

	return button
end

-- Scaled pixel height of the top header for the current device class.
local function headerHeight(): number
	return Responsive.scaled(Responsive.isCompact() and HEADER_HEIGHT_PHONE or HEADER_HEIGHT_DESKTOP)
end

-- Scaled metrics shared by the header build + responsive relayout.
local function headerMetrics(): (number, number, number)
	local badgeWidth = Responsive.scaled(78)
	local gap = Responsive.scaled(10)
	local trackHeight = Responsive.scaled(Responsive.isCompact() and 22 or 20)
	return badgeWidth, gap, trackHeight
end

-- Build the persistent top header: a "Lv N" badge and a stretchy XP progress bar
-- that mirrors the replicated global level/XP (R-C22). Positions are explicit so
-- the bar stretches with the viewport without a flex layout.
local function buildHeader(): Frame
	local Theme = UIFactory.Theme
	local badgeWidth, gap, trackHeight = headerMetrics()

	local bar = UIFactory.frame({
		Name = "HeaderBar",
		BackgroundColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 0, headerHeight()),
	})
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = bar
	UIFactory.padding(Responsive.scaled(10)).Parent = bar

	local badge = UIFactory.frame({
		Name = "LevelBadge",
		BackgroundColor3 = Theme.Accent,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, badgeWidth, 1, 0),
	})
	UIFactory.corner(Responsive.scaled(8)).Parent = badge
	local badgeLabel = UIFactory.textLabel({
		Name = "Level",
		Size = UDim2.fromScale(1, 1),
		Text = "Lv 1",
		TextColor3 = Theme.AccentText,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(18),
	})
	badgeLabel.Parent = badge
	badge.Parent = bar

	local track = UIFactory.frame({
		Name = "XPTrack",
		BackgroundColor3 = Theme.PanelAlt,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, badgeWidth + gap, 0.5, 0),
		Size = UDim2.new(1, -(badgeWidth + gap), 0, trackHeight),
	})
	UIFactory.corner(math.floor(trackHeight / 2)).Parent = track
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = track

	local fill = UIFactory.frame({
		Name = "XPFill",
		BackgroundColor3 = Theme.Positive,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 2,
	})
	UIFactory.corner(math.floor(trackHeight / 2)).Parent = fill
	fill.Parent = track

	local xpText = UIFactory.textLabel({
		Name = "XPText",
		Size = UDim2.fromScale(1, 1),
		Text = "0 / 0 XP",
		TextColor3 = Theme.Text,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(13),
		ZIndex = 3,
	})
	xpText.Parent = track
	track.Parent = bar

	headerBar = bar
	levelBadge = badge
	levelBadgeLabel = badgeLabel
	xpTrack = track
	xpFill = fill
	xpLabel = xpText
	return bar
end

-- Update the header from the latest replicated profile (nil-safe before load).
local function refreshHeader(data: any)
	if not (levelBadgeLabel and xpFill and xpLabel) then
		return
	end
	local g = data and data.global
	local level = (g and g.level) or 1
	local xp = (g and g.xp) or 0
	local need = GlobalLevel.xpToNext(level)
	local frac = GlobalLevel.progress(level, xp)

	;(levelBadgeLabel :: TextLabel).Text = ("Lv %d"):format(level)
	;(xpFill :: Frame).Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0)
	;(xpLabel :: TextLabel).Text = ("%d / %d XP"):format(math.floor(xp), math.floor(need))
end

-- Recompute size-dependent properties for the current viewport/device class.
local function layout()
	if not (screenGui and contentArea and tabBar) then
		return
	end
	local barHeight = Responsive.scaled(
		Responsive.isCompact() and TABBAR_HEIGHT_PHONE or TABBAR_HEIGHT_DESKTOP
	)
	local headH = headerHeight()
	tabBar.Size = UDim2.new(1, 0, 0, barHeight)
	-- Content sits between the header (top) and the tab bar (bottom).
	contentArea.Position = UDim2.new(0, 0, 0, headH)
	contentArea.Size = UDim2.new(1, 0, 1, -(barHeight + headH))

	if headerBar and levelBadge and xpTrack and levelBadgeLabel and xpLabel then
		local badgeWidth, gap, trackHeight = headerMetrics()
		headerBar.Size = UDim2.new(1, 0, 0, headH)
		levelBadge.Size = UDim2.new(0, badgeWidth, 1, 0)
		xpTrack.Position = UDim2.new(0, badgeWidth + gap, 0.5, 0)
		xpTrack.Size = UDim2.new(1, -(badgeWidth + gap), 0, trackHeight)
		levelBadgeLabel.TextSize = Responsive.scaled(18)
		xpLabel.TextSize = Responsive.scaled(13)
	end

	for tabId, button in tabButtons do
		local icon = button:FindFirstChild("Stack") and (button.Stack :: Frame):FindFirstChild("Icon")
		local iconSize = Responsive.scaled(Responsive.isCompact() and 30 or 26)
		if icon and icon:IsA("Frame") then
			icon.Size = UDim2.fromOffset(iconSize, iconSize)
		end
		local label = tabButtonLabels[tabId]
		if label then
			label.TextSize = Responsive.scaled(Responsive.isCompact() and 15 or 14)
		end
	end
end

-- Apply the visual selected/deselected state to every tab button.
local function refreshSelection()
	local Theme = UIFactory.Theme
	for tabId, button in tabButtons do
		local selected = tabId == activeTab
		button.BackgroundColor3 = selected and Theme.PanelAlt or Theme.Panel
		local label = tabButtonLabels[tabId]
		if label then
			label.TextColor3 = selected and Theme.Accent or Theme.SubText
		end
	end
end

function MenuShell.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = UIFactory.create("ScreenGui", {
		Name = "MenuShell",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
	})
	screenGui = gui

	local root = UIFactory.frame({
		Name = "Root",
		BackgroundColor3 = UIFactory.Theme.Background,
		Size = UDim2.fromScale(1, 1),
	})
	root.Parent = gui

	local content = UIFactory.frame({
		Name = "ContentArea",
		BackgroundColor3 = UIFactory.Theme.Background,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 1, 0),
	})
	content.Parent = root
	contentArea = content

	local bar = UIFactory.frame({
		Name = "TabBar",
		BackgroundColor3 = UIFactory.Theme.Panel,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, TABBAR_HEIGHT_DESKTOP),
	})
	bar.Parent = root
	tabBar = bar

	-- Persistent top header with the global level badge + XP bar.
	local header = buildHeader()
	header.Parent = root

	UIFactory.stroke({ Color = UIFactory.Theme.Stroke }).Parent = bar
	local barLayout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 0),
	})
	barLayout.Parent = bar

	for order, tabId in TAB_ORDER do
		local frame = buildContentFrame(tabId)
		frame.Parent = content
		contentFrames[tabId] = frame

		local button = buildTabButton(tabId, order)
		button.Parent = bar
		tabButtons[tabId] = button
	end

	gui.Parent = playerGui

	layout()
	Responsive.onChanged(layout)

	-- Mirror the replicated global level/XP into the header, now and on change.
	refreshHeader(DataController.get())
	DataController.onChanged(refreshHeader)
	task.spawn(function()
		refreshHeader(DataController.waitForData(10))
	end)

	-- Default to the first tab.
	MenuShell.showTab(TAB_ORDER[1])
end

-- Switch the visible tab. No-op if the id is unknown or already active.
function MenuShell.showTab(tabId: string)
	if not contentFrames[tabId] then
		return
	end
	if activeTab == tabId then
		return
	end
	activeTab = tabId
	for id, frame in contentFrames do
		frame.Visible = id == tabId
	end
	refreshSelection()
	if tabChangedEvent then
		tabChangedEvent:Fire(tabId)
	end
end

-- The content container for a tab; tab modules parent their views here.
function MenuShell.getContentFrame(tabId: string): Frame?
	return contentFrames[tabId]
end

function MenuShell.getActiveTab(): string?
	return activeTab
end

function MenuShell.getScreenGui(): ScreenGui?
	return screenGui
end

-- Subscribe to tab changes; callback receives the new tab id.
function MenuShell.onTabChanged(callback: (string) -> ()): RBXScriptConnection
	assert(tabChangedEvent, "MenuShell not initialized")
	return tabChangedEvent.Event:Connect(callback)
end

return MenuShell
