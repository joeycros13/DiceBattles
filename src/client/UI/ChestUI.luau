--!strict
-- ChestUI: the Shop tab (R-Y2, R-Y3, R-X1). Rendered as a bottom-navbar tab
-- alongside Equipment, Battle, and Talents by parenting its view into the
-- MenuShell "Shop" content frame (R-M1). Shows current balances, the single
-- chest with "Open 1" and "Spin All" actions, this open's rolled rewards, and a
-- read-only shop stub (gamepasses / products / daily). The client only sends
-- intent via the OpenChest remote and renders the replicated ChestOpened results
-- + balances (ProfileUpdated).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Currencies = require(Config:WaitForChild("Currencies"))
local Gear = require(Config:WaitForChild("Gear"))
local Shop = require(Config:WaitForChild("Shop"))

local ChestUI = {}

local deps: any = nil
local UIFactory: any = nil
local Responsive: any = nil
local AssetResolver: any = nil
local MenuShell: any = nil
local DataController: any = nil
local openChestRemote: RemoteEvent? = nil
local chestOpenedRemote: RemoteEvent? = nil

-- Currency pill value labels, keyed by currency id, for live refresh.
local currencyValueLabels: { [string]: TextLabel } = {}
local open1Button: TextButton? = nil
local spinAllButton: TextButton? = nil
local resultsList: Frame? = nil
local resultsEmptyLabel: TextLabel? = nil

-- Current keys balance from the latest replicated profile.
local function keyCount(data: any): number
	return (data and data.currencies and data.currencies.keys) or 0
end

-- Build one currency pill (color chip + abbrev + count) into a row.
local function buildCurrencyPill(currencyId: string, order: number): Frame
	local Theme = UIFactory.Theme
	local def = Currencies.get(currencyId)
	local visual = AssetResolver.resolve(def and def.icon or "")

	local pill = UIFactory.frame({
		Name = currencyId .. "Pill",
		LayoutOrder = order,
		BackgroundColor3 = Theme.PanelAlt,
		-- Fill an equal quarter of the row so pills scale with the viewport.
		Size = UDim2.new(0.25, -Responsive.scaled(8), 1, 0),
	})
	UIFactory.corner(Responsive.scaled(10)).Parent = pill
	UIFactory.padding(Responsive.scaled(8)).Parent = pill

	local chipSize = Responsive.scaled(30)
	local chip = UIFactory.frame({
		Name = "Chip",
		BackgroundColor3 = visual.color,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(chipSize, chipSize),
	})
	UIFactory.corner(math.floor(chipSize / 2)).Parent = chip
	local chipLabel = UIFactory.textLabel({
		Size = UDim2.fromScale(1, 1),
		Text = def and def.abbrev or "?",
		TextColor3 = Theme.AccentText,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(15),
	})
	chipLabel.Parent = chip
	chip.Parent = pill

	local value = UIFactory.textLabel({
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(1, -(chipSize + Responsive.scaled(8)), 1, 0),
		Text = "0",
		TextColor3 = Theme.Text,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(20),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	value.Parent = pill
	currencyValueLabels[currencyId] = value

	return pill
end

-- Format one rolled reward for the results list.
local function formatResult(result: any): (string, Color3)
	local Theme = UIFactory.Theme
	if result.kind == "currency" then
		local def = Currencies.get(result.currency)
		local name = def and def.name or result.currency
		return ("+%d %s"):format(result.amount or 0, name), Theme.Positive
	elseif result.kind == "gear" then
		local def = Gear.get(result.gearId)
		local name = def and def.name or result.gearId
		local color = AssetResolver.rarityColor(result.rarity)
		return ("%s  (%s)"):format(name, result.rarity or "?"), color
	end
	return "Reward", Theme.Text
end

-- Render the rolled results into the scrolling list (newest open replaces old).
local function renderResults(results: any)
	local list = resultsList
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local count = results and #results or 0
	if resultsEmptyLabel then
		resultsEmptyLabel.Visible = count == 0
	end

	local Theme = UIFactory.Theme
	for index, result in results do
		local text, color = formatResult(result)
		local row = UIFactory.frame({
			Name = "Result" .. index,
			LayoutOrder = index,
			BackgroundColor3 = Theme.PanelAlt,
			Size = UDim2.new(1, 0, 0, Responsive.scaled(42)),
		})
		UIFactory.corner(Responsive.scaled(8)).Parent = row
		UIFactory.padding(Responsive.scaled(10)).Parent = row
		local label = UIFactory.textLabel({
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextColor3 = color,
			Font = Theme.FontBold,
			TextSize = Responsive.scaled(18),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		label.Parent = row
		row.Parent = list
	end
end

-- Read-only shop row (name, price/grants, disabled "Soon" button).
local function buildShopRow(entry: any, order: number): Frame
	local Theme = UIFactory.Theme
	local row = UIFactory.frame({
		Name = entry.id .. "Row",
		LayoutOrder = order,
		BackgroundColor3 = Theme.PanelAlt,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(66)),
	})
	UIFactory.corner(Responsive.scaled(10)).Parent = row
	UIFactory.padding(Responsive.scaled(12)).Parent = row

	local name = UIFactory.textLabel({
		Name = "Name",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, -Responsive.scaled(124), 0, Responsive.scaled(26)),
		Text = entry.name,
		TextColor3 = Theme.Text,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(19),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	name.Parent = row

	local subtitle = entry.robux and ("R$ %d"):format(entry.robux) or "Free / Daily"
	local sub = UIFactory.textLabel({
		Name = "Sub",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, -Responsive.scaled(124), 0, Responsive.scaled(20)),
		Text = subtitle,
		TextColor3 = Theme.SubText,
		Font = Theme.Font,
		TextSize = Responsive.scaled(14),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	sub.Parent = row

	local buy = UIFactory.textButton({
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, Responsive.scaled(112), 0, Responsive.scaled(44)),
		BackgroundColor3 = Theme.Panel,
		AutoButtonColor = false,
		Text = "Soon",
		TextColor3 = Theme.SubText,
		TextSize = Responsive.scaled(18),
	})
	UIFactory.corner(Responsive.scaled(8)).Parent = buy
	buy.Parent = row

	return row
end

-- Enable/disable the chest buttons and refresh their labels + balances.
local function refresh(data: any)
	for currencyId, label in currencyValueLabels do
		local amount = (data and data.currencies and data.currencies[currencyId]) or 0
		label.Text = tostring(math.floor(amount))
	end

	local keys = keyCount(data)
	local Theme = UIFactory.Theme

	if open1Button then
		local canOpen = keys >= 1
		open1Button.AutoButtonColor = canOpen
		open1Button.BackgroundColor3 = canOpen and Theme.Accent or Theme.PanelAlt
	end
	if spinAllButton then
		local canSpin = keys >= 2
		spinAllButton.Text = keys >= 1 and ("Spin All (%d)"):format(keys) or "Spin All"
		spinAllButton.AutoButtonColor = canSpin
		spinAllButton.BackgroundColor3 = canSpin and Theme.Positive or Theme.PanelAlt
	end
end

-- Build the whole Shop tab view into `content` (the MenuShell content frame).
-- Everything lives in a single scrolling column so it stays readable on phones.
local function buildInto(content: Frame)
	local Theme = UIFactory.Theme

	local root = UIFactory.scrolling({
		Name = "ShopRoot",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	local layout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Responsive.scaled(14)),
	})
	layout.Parent = root

	-- Currency row.
	local currencyRow = UIFactory.frame({
		Name = "Currencies",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(52)),
	})
	local currencyLayout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Responsive.scaled(8)),
	})
	currencyLayout.Parent = currencyRow
	for order, currencyId in Currencies.Order do
		buildCurrencyPill(currencyId, order).Parent = currencyRow
	end
	currencyRow.Parent = root

	-- Chest section: title + action buttons.
	local chestBox = UIFactory.frame({
		Name = "Chest",
		LayoutOrder = 2,
		BackgroundColor3 = Theme.PanelAlt,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(128)),
	})
	UIFactory.corner(Responsive.scaled(12)).Parent = chestBox
	UIFactory.padding(Responsive.scaled(14)).Parent = chestBox
	local chestTitle = UIFactory.textLabel({
		Name = "ChestTitle",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, Responsive.scaled(28)),
		Text = "Chest  -  1 Key = 1 Roll",
		TextColor3 = Theme.Text,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	chestTitle.Parent = chestBox

	local open1 = UIFactory.textButton({
		Name = "Open1",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.48, -Responsive.scaled(5), 0, Responsive.scaled(54)),
		BackgroundColor3 = Theme.Accent,
		Text = "Open 1",
		TextSize = Responsive.scaled(22),
	})
	UIFactory.corner(Responsive.scaled(10)).Parent = open1
	open1.Activated:Connect(function()
		if openChestRemote then
			openChestRemote:FireServer(1)
		end
	end)
	open1.Parent = chestBox
	open1Button = open1

	local spinAll = UIFactory.textButton({
		Name = "SpinAll",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.52, -Responsive.scaled(5), 0, Responsive.scaled(54)),
		BackgroundColor3 = Theme.Positive,
		Text = "Spin All",
		TextSize = Responsive.scaled(22),
	})
	UIFactory.corner(Responsive.scaled(10)).Parent = spinAll
	spinAll.Activated:Connect(function()
		-- Send the current key count; the server clamps to what's affordable.
		local keys = keyCount(DataController.get())
		if openChestRemote and keys >= 1 then
			openChestRemote:FireServer(keys)
		end
	end)
	spinAll.Parent = chestBox
	spinAllButton = spinAll
	chestBox.Parent = root

	-- Rewards section (grows with its rows; the outer column scrolls).
	local resultsHeader = UIFactory.textLabel({
		Name = "ResultsHeader",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(26)),
		Text = "Rewards",
		TextColor3 = Theme.SubText,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(18),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	resultsHeader.Parent = root

	local results = UIFactory.frame({
		Name = "Results",
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local resultsLayout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Responsive.scaled(4)),
	})
	resultsLayout.Parent = results
	local empty = UIFactory.textLabel({
		Name = "Empty",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(40)),
		Text = "Open the chest to see rewards.",
		TextColor3 = Theme.SubText,
		Font = Theme.Font,
		TextSize = Responsive.scaled(16),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	empty.Parent = results
	resultsEmptyLabel = empty
	results.Parent = root
	resultsList = results

	-- Shop stub section (read-only).
	local shopHeader = UIFactory.textLabel({
		Name = "ShopHeader",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, Responsive.scaled(26)),
		Text = "Shop (Coming Soon)",
		TextColor3 = Theme.SubText,
		Font = Theme.FontBold,
		TextSize = Responsive.scaled(18),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	shopHeader.Parent = root

	local shopList = UIFactory.frame({
		Name = "Shop",
		LayoutOrder = 6,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local shopLayout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Responsive.scaled(8)),
	})
	shopLayout.Parent = shopList
	for order, entryId in Shop.Order do
		local entry = Shop.get(entryId)
		if entry then
			buildShopRow(entry, order).Parent = shopList
		end
	end
	shopList.Parent = root

	root.Parent = content
end

function ChestUI.init(injected: any)
	deps = injected
	UIFactory = deps.Util.UIFactory
	Responsive = deps.Util.Responsive
	AssetResolver = deps.Util.AssetResolver
	MenuShell = deps.UI.MenuShell
	DataController = deps.Controllers.DataController
	openChestRemote = deps.Remotes.getEvent("OpenChest")
	chestOpenedRemote = deps.Remotes.getEvent("ChestOpened")
end

function ChestUI.start()
	local content = MenuShell.getContentFrame("Shop")
	if not content then
		warn("[ChestUI] Shop content frame missing")
		return
	end

	-- Remove the shell placeholder now that we render the real view.
	local placeholder = content:FindFirstChild("Placeholder")
	if placeholder then
		placeholder:Destroy()
	end

	buildInto(content)

	-- Keep balances/buttons in sync with the replicated profile.
	refresh(DataController.get())
	DataController.onChanged(refresh)

	-- Render each open's rolled rewards in place.
	local opened = chestOpenedRemote :: RemoteEvent
	opened.OnClientEvent:Connect(function(results: any)
		renderResults(results)
	end)
end

return ChestUI
