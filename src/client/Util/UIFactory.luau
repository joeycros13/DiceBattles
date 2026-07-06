--!strict
-- UIFactory: helpers to build common vanilla Instance-based UI objects (R-P2).
-- Provides a tiny declarative `create(className, props, children)` plus shortcuts
-- for the widgets used across the menu, and a shared color/theme palette so the
-- UI stays visually consistent. Pure construction helpers; no game-state.

local UIFactory = {}

local deps: any = nil

-- Shared visual palette. Tabs/panels reference these for a consistent look.
UIFactory.Theme = {
	Background = Color3.fromRGB(18, 20, 28),
	Panel = Color3.fromRGB(30, 33, 44),
	PanelAlt = Color3.fromRGB(38, 42, 56),
	Accent = Color3.fromRGB(88, 132, 255),
	AccentText = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(236, 238, 244),
	SubText = Color3.fromRGB(150, 156, 172),
	Stroke = Color3.fromRGB(58, 64, 82),
	Positive = Color3.fromRGB(80, 200, 120),
	Negative = Color3.fromRGB(228, 92, 92),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}

function UIFactory.init(injected: any)
	deps = injected
end

function UIFactory.start() end

-- Shallow-merge `props` over `defaults`, returning a new table.
local function withDefaults(defaults: { [string]: any }, props: { [string]: any }?): { [string]: any }
	local merged: { [string]: any } = {}
	for key, value in defaults do
		merged[key] = value
	end
	if props then
		for key, value in props do
			merged[key] = value
		end
	end
	return merged
end

-- Generic instance builder: applies properties then parents children.
-- Children may be passed via `props.Children` or the third argument.
function UIFactory.create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	if props then
		local nested = props.Children
		for key, value in props do
			if key ~= "Children" then
				(instance :: any)[key] = value
			end
		end
		if nested then
			for _, child in nested :: { Instance } do
				child.Parent = instance
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	return instance
end

local create = UIFactory.create
local Theme = UIFactory.Theme

function UIFactory.frame(props: { [string]: any }?): Frame
	return create("Frame", withDefaults({
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
	}, props))
end

function UIFactory.textLabel(props: { [string]: any }?): TextLabel
	return create("TextLabel", withDefaults({
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Text,
		TextScaled = false,
		TextSize = 18,
		Text = "",
	}, props))
end

function UIFactory.textButton(props: { [string]: any }?): TextButton
	return create("TextButton", withDefaults({
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.FontBold,
		TextColor3 = Theme.AccentText,
		TextSize = 18,
		Text = "",
	}, props))
end

function UIFactory.imageLabel(props: { [string]: any }?): ImageLabel
	return create("ImageLabel", withDefaults({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, props))
end

function UIFactory.imageButton(props: { [string]: any }?): ImageButton
	return create("ImageButton", withDefaults({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, props))
end

function UIFactory.scrolling(props: { [string]: any }?): ScrollingFrame
	return create("ScrollingFrame", withDefaults({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Stroke,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, props))
end

-- Rounded corners.
function UIFactory.corner(radius: number?): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

-- Uniform inner padding.
function UIFactory.padding(pad: number): UIPadding
	local udim = UDim.new(0, pad)
	return create("UIPadding", {
		PaddingTop = udim,
		PaddingBottom = udim,
		PaddingLeft = udim,
		PaddingRight = udim,
	})
end

function UIFactory.stroke(props: { [string]: any }?): UIStroke
	return create("UIStroke", withDefaults({
		Color = Theme.Stroke,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, props))
end

function UIFactory.listLayout(props: { [string]: any }?): UIListLayout
	return create("UIListLayout", withDefaults({
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 8),
	}, props))
end

function UIFactory.gridLayout(props: { [string]: any }?): UIGridLayout
	return create("UIGridLayout", withDefaults({
		SortOrder = Enum.SortOrder.LayoutOrder,
		CellSize = UDim2.new(0, 96, 0, 96),
		CellPadding = UDim2.new(0, 8, 0, 8),
	}, props))
end

-- Locks a GuiObject to a fixed aspect ratio (e.g. square gear cells).
function UIFactory.aspectRatio(ratio: number): UIAspectRatioConstraint
	return create("UIAspectRatioConstraint", { AspectRatio = ratio })
end

return UIFactory
