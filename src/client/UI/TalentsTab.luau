--!strict
-- TalentsTab: the Talents view (R-T1..R-T4). Shows every talent as a square,
-- rarity-tinted tile displaying just its name + level; clicking a tile opens a
-- detail popup with the current stat boost, the next-level preview, and a plain-
-- language description. A Roll Talent button is pinned to the bottom of the tab
-- and spends coins to rarity-weighted +1 one talent. All state is read from
-- DataController (server-authoritative); the Roll button only sends intent via the
-- RollTalent remote and the view re-renders on ProfileUpdated. A small banner
-- reports the last roll by diffing talent levels between replicated profiles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Logic = Shared:WaitForChild("Logic")
local Talents = require(Config:WaitForChild("Talents"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Balance = require(Config:WaitForChild("Balance"))
local TalentLogic = require(Logic:WaitForChild("TalentLogic"))

local TalentsTab = {}

local deps: any = nil
local UIFactory: any = nil
local Responsive: any = nil
local AssetResolver: any = nil
local MenuShell: any = nil
local DataController: any = nil
local rollTalentRemote: RemoteEvent? = nil

-- The coin cost per roll (R-T2), read from Balance so tuning stays in config.
local ROLL_COST = Balance.Economy.talentRollCost

-- Built instances kept for re-render / re-layout.
local rootFrame: Frame? = nil
local headerFrame: Frame? = nil
local coinLabel: TextLabel? = nil
local rollButton: TextButton? = nil
local bannerLabel: TextLabel? = nil
local gridFrame: ScrollingFrame? = nil
local gridLayout: UIGridLayout? = nil
local gridPadding: UIPadding? = nil

-- Square tiles only show a name + level; details live in the popup below.
type TileWidget = {
	frame: Frame,
	stroke: UIStroke,
	name: TextLabel,
	level: TextLabel,
}
local tileWidgets: { [string]: TileWidget } = {}

-- Detail popup elements + which talent is currently shown (for live refresh).
local popupOverlay: Frame? = nil
local popupTitle: TextLabel? = nil
local popupSubtitle: TextLabel? = nil
local popupStat: TextLabel? = nil
local popupNext: TextLabel? = nil
local popupDesc: TextLabel? = nil
local popupSelectedId: string? = nil

-- Snapshot of talent levels from the previous render, used to detect which talent
-- a roll leveled up (so the banner + row flash can point it out).
local lastLevels: { [string]: number } = {}
local bannerResetToken = 0

-- ==================== small helpers ====================

-- Blend `color` toward the panel color to produce a muted tile fill (mirrors the
-- gear-tile treatment in EquipmentTab so the two grids feel consistent).
local function dim(color: Color3, alpha: number): Color3
	return color:Lerp(UIFactory.Theme.Panel, alpha)
end

local function coinBalance(data: any): number
	return (data.currencies and data.currencies.coins) or 0
end

-- ==================== roll button ====================

-- Enable / label the Roll button from the latest data: disabled when the player
-- cannot afford a roll or every talent is already maxed.
local function updateRollButton(data: any)
	local button = rollButton
	if not button then
		return
	end
	local Theme = UIFactory.Theme
	local coins = coinBalance(data)
	local _, poolWeight = TalentLogic.buildPool(data.talents)

	if poolWeight <= 0 then
		button.Text = "All Talents Maxed"
		button.BackgroundColor3 = Theme.PanelAlt
		button.AutoButtonColor = false
	elseif coins < ROLL_COST then
		button.Text = ("Roll Talent  (%d C)"):format(ROLL_COST)
		button.BackgroundColor3 = Theme.PanelAlt
		button.AutoButtonColor = false
	else
		button.Text = ("Roll Talent  (%d C)"):format(ROLL_COST)
		button.BackgroundColor3 = Theme.Accent
		button.AutoButtonColor = true
	end
end

-- True if a roll is currently allowed (affordable + something to roll).
local function canRoll(data: any): boolean
	local _, poolWeight = TalentLogic.buildPool(data.talents)
	return poolWeight > 0 and coinBalance(data) >= ROLL_COST
end

-- ==================== result banner ====================

-- Show the last-roll banner for a moment, then fade back to the idle hint.
local function flashBanner(text: string)
	local banner = bannerLabel
	if not banner then
		return
	end
	banner.Text = text
	banner.TextColor3 = UIFactory.Theme.Positive

	bannerResetToken += 1
	local token = bannerResetToken
	task.delay(3, function()
		if bannerResetToken == token and bannerLabel then
			bannerLabel.Text = ("Each roll costs %d coins and levels a random talent."):format(ROLL_COST)
			bannerLabel.TextColor3 = UIFactory.Theme.SubText
		end
	end)
end

-- ==================== detail popup ====================

local function closePopup()
	popupSelectedId = nil
	if popupOverlay then
		popupOverlay.Visible = false
	end
end

-- Fill the popup with a talent's stat boost + description. Returns false if the
-- talent can no longer be resolved.
local function populatePopup(talentId: string): boolean
	local data = DataController.get()
	local def = Talents.get(talentId)
	if not (data and def) then
		return false
	end
	local level = data.talents[talentId] or 0
	local rarityDef = Rarities.get(def.rarity)
	local rarityColor = rarityDef and rarityDef.color or UIFactory.Theme.Text

	local title = popupTitle :: TextLabel
	title.Text = def.name
	title.TextColor3 = rarityColor

	local subtitle = popupSubtitle :: TextLabel
	subtitle.Text = ("%s  -  %s  -  Lv %d"):format(def.rarity, TalentLogic.effectLabel(def.effect), level)

	local stat = popupStat :: TextLabel
	stat.Text = ("Now: %s"):format(TalentLogic.formatBonus(talentId, level))

	local nextLabel = popupNext :: TextLabel
	if TalentLogic.isMaxed(talentId, level) then
		nextLabel.Text = "Maxed out"
		nextLabel.TextColor3 = UIFactory.Theme.Accent
	else
		nextLabel.Text = ("Next level: %s"):format(TalentLogic.formatBonus(talentId, level + 1))
		nextLabel.TextColor3 = UIFactory.Theme.SubText
	end

	local desc = popupDesc :: TextLabel
	desc.Text = def.desc

	popupSelectedId = talentId
	return true
end

local function openPopup(talentId: string)
	if populatePopup(talentId) and popupOverlay then
		popupOverlay.Visible = true
	end
end

-- Keep an open popup in sync with the latest data (e.g. after a roll levels it up).
local function refreshPopup()
	if popupOverlay and popupOverlay.Visible and popupSelectedId then
		if not populatePopup(popupSelectedId) then
			closePopup()
		end
	end
end

local function buildPopup(parent: Instance)
	local Theme = UIFactory.Theme
	local overlay = UIFactory.frame({
		Name = "DetailPopup",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
	})
	overlay.Parent = parent
	popupOverlay = overlay

	-- Click-off backdrop closes the popup.
	local backdrop = UIFactory.textButton({
		Name = "Backdrop",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
	})
	backdrop.Parent = overlay
	backdrop.Activated:Connect(closePopup)

	local card = UIFactory.frame({
		Name = "Card",
		BackgroundColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Responsive.scaled(340), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 21,
	})
	card.Parent = overlay
	UIFactory.corner(12).Parent = card
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = card
	UIFactory.padding(Responsive.scaled(18)).Parent = card

	local layout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Responsive.scaled(10)),
	})
	layout.Parent = card

	local title = UIFactory.textLabel({
		Name = "Title",
		LayoutOrder = 1,
		Size = UDim2.new(1, -Responsive.scaled(34), 0, Responsive.scaled(32)),
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(26),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
	})
	title.Parent = card
	popupTitle = title

	local subtitle = UIFactory.textLabel({
		Name = "Subtitle",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(20)),
		TextColor3 = Theme.SubText,
		TextSize = Responsive.scaled(16),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
	})
	subtitle.Parent = card
	popupSubtitle = subtitle

	local divider = UIFactory.frame({
		Name = "Divider",
		LayoutOrder = 3,
		BackgroundColor3 = Theme.Stroke,
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 21,
	})
	divider.Parent = card

	local stat = UIFactory.textLabel({
		Name = "Stat",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(26)),
		Font = Theme.FontBold,
		TextColor3 = Theme.Positive,
		TextSize = Responsive.scaled(22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
	})
	stat.Parent = card
	popupStat = stat

	local nextLabel = UIFactory.textLabel({
		Name = "Next",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(20)),
		TextColor3 = Theme.SubText,
		TextSize = Responsive.scaled(16),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
	})
	nextLabel.Parent = card
	popupNext = nextLabel

	local desc = UIFactory.textLabel({
		Name = "Description",
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Theme.Text,
		TextSize = Responsive.scaled(16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		ZIndex = 21,
	})
	desc.Parent = card
	popupDesc = desc

	-- Close (X) button, top-right of the card.
	local close = UIFactory.textButton({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Responsive.scaled(8), 0, Responsive.scaled(8)),
		Size = UDim2.fromOffset(Responsive.scaled(30), Responsive.scaled(30)),
		BackgroundColor3 = Theme.PanelAlt,
		Text = "X",
		TextSize = Responsive.scaled(16),
		ZIndex = 22,
	})
	UIFactory.corner(8).Parent = close
	close.Parent = card
	close.Activated:Connect(closePopup)
end

-- ==================== tiles ====================

-- Build one square talent tile: a rarity-tinted button showing only the talent
-- name + level. Clicking it opens the detail popup. Sized by the grid layout.
local function buildTile(talentId: string, order: number): TileWidget
	local Theme = UIFactory.Theme
	local def = Talents.get(talentId)
	local rarityDef = def and Rarities.get(def.rarity)
	local rarityColor = rarityDef and rarityDef.color or Theme.SubText

	local button = UIFactory.create("TextButton", {
		Name = talentId,
		BackgroundColor3 = dim(rarityColor, 0.4),
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = order,
	})
	UIFactory.corner(12).Parent = button
	local stroke = UIFactory.stroke({ Color = rarityColor, Thickness = 2 })
	stroke.Parent = button
	UIFactory.padding(Responsive.scaled(8)).Parent = button

	-- Talent name: big, fills the upper portion (TextScaled shrinks it on small
	-- tiles, the size constraint caps it on large ones).
	local nameLabel = UIFactory.textLabel({
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 0.66, 0),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextScaled = true,
		TextWrapped = true,
		Text = def and def.name or talentId,
	})
	nameLabel.Parent = button
	UIFactory.create("UITextSizeConstraint", { MaxTextSize = Responsive.scaled(36) }).Parent = nameLabel

	-- Level, centered along the bottom edge: plain white text, no background.
	local levelLabel = UIFactory.textLabel({
		Name = "Level",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0.26, 0),
		Font = Theme.FontBold,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		Text = "Level 0",
	})
	levelLabel.Parent = button
	UIFactory.create("UITextSizeConstraint", { MaxTextSize = Responsive.scaled(28) }).Parent = levelLabel

	button.Activated:Connect(function()
		openPopup(talentId)
	end)

	return {
		frame = button,
		stroke = stroke,
		name = nameLabel,
		level = levelLabel,
	}
end

-- ==================== render ====================

local function renderTiles(data: any)
	for _, talentId in Talents.Order do
		local widget = tileWidgets[talentId]
		if widget then
			local level = data.talents[talentId] or 0
			widget.level.Text = ("Level %d"):format(level)
		end
	end
end

-- Detect which talent leveled up since the last render and flash it (R-T2 feedback).
local function reportRoll(data: any)
	-- Skip the very first render (no prior snapshot to diff against).
	if next(lastLevels) ~= nil then
		for _, talentId in Talents.Order do
			local before = lastLevels[talentId] or 0
			local now = data.talents[talentId] or 0
			if now > before then
				local def = Talents.get(talentId)
				flashBanner(("Rolled %s  ->  Lv %d!"):format(def and def.name or talentId, now))
				local widget = tileWidgets[talentId]
				if widget then
					local rarityColor = (def and Rarities.get(def.rarity) and Rarities.get(def.rarity).color)
						or UIFactory.Theme.Accent
					-- Thicken the tile border briefly, then settle back to the
					-- normal rarity outline.
					widget.stroke.Color = UIFactory.Theme.Accent
					widget.stroke.Thickness = 4
					task.delay(3, function()
						if widget.stroke then
							widget.stroke.Color = rarityColor
							widget.stroke.Thickness = 2
						end
					end)
				end
				break
			end
		end
	end

	-- Refresh the snapshot for the next diff.
	for _, talentId in Talents.Order do
		lastLevels[talentId] = data.talents[talentId] or 0
	end
end

-- Fit the tile grid to the current width with SQUARE cells: a fixed 6 columns on
-- desktop/tablet and 4 on phone (smaller tiles), sizing each cell so width == height.
local function layoutGrid()
	local grid = gridFrame
	local layout = gridLayout
	if not grid or not layout then
		return
	end
	local width = grid.AbsoluteSize.X
	if width <= 0 then
		return
	end
	local buffer = Responsive.scaled(4)
	local pad = Responsive.scaled(8)
	local columns = Responsive.isCompact() and 4 or 6
	local avail = width - buffer * 2 - grid.ScrollBarThickness
	local cell = math.max(1, math.floor((avail - (columns - 1) * pad) / columns))
	layout.CellSize = UDim2.fromOffset(cell, cell) -- square
	layout.CellPadding = UDim2.fromOffset(pad, pad)
	if gridPadding then
		gridPadding.PaddingLeft = UDim.new(0, buffer)
		gridPadding.PaddingRight = UDim.new(0, buffer + grid.ScrollBarThickness)
		gridPadding.PaddingTop = UDim.new(0, buffer)
		gridPadding.PaddingBottom = UDim.new(0, buffer)
	end
end

local function render()
	local data = DataController.get()
	if not data then
		return
	end
	if coinLabel then
		coinLabel.Text = tostring(coinBalance(data))
	end
	renderTiles(data)
	updateRollButton(data)
	reportRoll(data)
	refreshPopup()
end

-- ==================== build ====================

function TalentsTab.init(injected: any)
	deps = injected
	UIFactory = deps.Util.UIFactory
	Responsive = deps.Util.Responsive
	AssetResolver = deps.Util.AssetResolver
	MenuShell = deps.UI.MenuShell
	DataController = deps.Controllers.DataController
	rollTalentRemote = deps.Remotes.getEvent("RollTalent")
end

function TalentsTab.start()
	local content = MenuShell.getContentFrame("Talents")
	if not content then
		warn("[TalentsTab] Talents content frame missing")
		return
	end

	-- Remove the shell placeholder now that we render the real view.
	local placeholder = content:FindFirstChild("Placeholder")
	if placeholder then
		placeholder:Destroy()
	end

	local Theme = UIFactory.Theme
	local root = UIFactory.frame({
		Name = "TalentsRoot",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	root.Parent = content
	rootFrame = root

	-- Layout bands: coin pill on top, tile grid in the middle, and the banner +
	-- Roll button pinned to the BOTTOM of the tab.
	local coinH = Responsive.scaled(42)
	local rollH = Responsive.scaled(56)
	local bannerH = Responsive.scaled(22)
	local gap = Responsive.scaled(10)
	local topH = coinH
	local bottomH = bannerH + gap + rollH

	-- Coin pill (icon + amount), top-right.
	local coinVisual = AssetResolver.resolve("currency/coins")
	local coinPill = UIFactory.frame({
		Name = "CoinPill",
		BackgroundColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(Responsive.scaled(150), coinH),
	})
	coinPill.Parent = root
	headerFrame = coinPill
	UIFactory.corner(coinH // 2).Parent = coinPill
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = coinPill

	local coinIcon = UIFactory.frame({
		Name = "Icon",
		BackgroundColor3 = coinVisual.color,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Responsive.scaled(5), 0.5, 0),
		Size = UDim2.fromOffset(coinH - Responsive.scaled(10), coinH - Responsive.scaled(10)),
	})
	coinIcon.Parent = coinPill
	UIFactory.corner(999).Parent = coinIcon
	local coinIconGlyph = UIFactory.textLabel({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.AccentText,
		TextSize = Responsive.scaled(16),
		Text = coinVisual.label,
	})
	coinIconGlyph.Parent = coinIcon

	local coinAmount = UIFactory.textLabel({
		Name = "Amount",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Responsive.scaled(12), 0.5, 0),
		Size = UDim2.new(1, -(coinH + Responsive.scaled(12)), 1, 0),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = Responsive.scaled(20),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0",
	})
	coinAmount.Parent = coinPill
	coinLabel = coinAmount

	-- Roll button, pinned to the very bottom, full width.
	local roll = UIFactory.textButton({
		Name = "RollButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, rollH),
		BackgroundColor3 = Theme.Accent,
		TextSize = Responsive.scaled(24),
		Text = ("Roll Talent  (%d C)"):format(ROLL_COST),
	})
	UIFactory.corner(10).Parent = roll
	roll.Parent = root
	rollButton = roll
	roll.Activated:Connect(function()
		local data = DataController.get()
		if data and canRoll(data) and rollTalentRemote then
			rollTalentRemote:FireServer()
		end
	end)

	-- Banner: last-roll result or the idle hint, just above the Roll button.
	local banner = UIFactory.textLabel({
		Name = "Banner",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(rollH + gap)),
		Size = UDim2.new(1, 0, 0, bannerH),
		TextColor3 = Theme.SubText,
		TextSize = Responsive.scaled(15),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = ("Each roll costs %d coins and levels a random talent."):format(ROLL_COST),
	})
	banner.Parent = root
	bannerLabel = banner

	-- Talent tile grid, filling the space between the coin pill and the footer.
	local grid = UIFactory.scrolling({
		Name = "TalentGrid",
		Position = UDim2.new(0, 0, 0, topH + gap),
		Size = UDim2.new(1, 0, 1, -(topH + gap + bottomH + gap)),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	grid.Parent = root
	gridFrame = grid
	local gLayout = UIFactory.gridLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	gLayout.Parent = grid
	gridLayout = gLayout
	local gPad = UIFactory.create("UIPadding", {
		PaddingRight = UDim.new(0, grid.ScrollBarThickness + Responsive.scaled(4)),
	})
	gPad.Parent = grid
	gridPadding = gPad

	-- Build tiles in rarity-DESCENDING order (highest rarity first), tie-breaking
	-- by id so the arrangement is stable.
	local ordered = table.clone(Talents.Order)
	table.sort(ordered, function(a, b)
		local da, db = Talents.get(a), Talents.get(b)
		local ra = da and Rarities.orderOf(da.rarity) or 0
		local rb = db and Rarities.orderOf(db.rarity) or 0
		if ra ~= rb then
			return ra > rb
		end
		return a < b
	end)

	table.clear(tileWidgets)
	for order, talentId in ordered do
		local widget = buildTile(talentId, order)
		widget.frame.Parent = grid
		tileWidgets[talentId] = widget
	end

	-- Detail popup lives above everything else in the tab.
	buildPopup(root)

	-- Re-flow the grid whenever its width or the device scale changes.
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGrid)
	Responsive.onChanged(layoutGrid)
	layoutGrid()

	-- Re-render on any authoritative profile change (roll result / coin change).
	DataController.onChanged(function()
		render()
	end)
	if DataController.get() then
		render()
	end
end

return TalentsTab
