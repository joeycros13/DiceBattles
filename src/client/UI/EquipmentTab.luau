--!strict
-- EquipmentTab: the Equipment view (R-E1..R-E8). Renders a 3D character rig in a
-- ViewportFrame with a code-driven idle animation, the six equipment slots laid
-- out around it (icon + slot level), a grid of unequipped gear sorted by rarity
-- (descending, icons only), and a detail popup with stats + Equip/Unequip. All
-- state is read from DataController (server-authoritative); equip/unequip only
-- send intent via the EquipGear/UnequipGear remotes and re-render on ProfileUpdated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Logic = Shared:WaitForChild("Logic")
local Slots = require(Config:WaitForChild("Slots"))
local Gear = require(Config:WaitForChild("Gear"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Balance = require(Config:WaitForChild("Balance"))
local GearStats = require(Logic:WaitForChild("GearStats"))
local InventoryLayout = require(Logic:WaitForChild("InventoryLayout"))
local MergeLogic = require(Logic:WaitForChild("MergeLogic"))

local EquipmentTab = {}

local deps: any = nil
local UIFactory: any = nil
local Responsive: any = nil
local AssetResolver: any = nil
local MenuShell: any = nil
local DataController: any = nil
local equipRemote: RemoteEvent? = nil
local unequipRemote: RemoteEvent? = nil
local levelSlotRemote: RemoteEvent? = nil
local mergeGearRemote: RemoteEvent? = nil
local autoMergeGearRemote: RemoteEvent? = nil

-- Built instances kept for re-render / re-layout.
local rootFrame: Frame? = nil
local characterArea: Frame? = nil
local leftColumn: Frame? = nil
local rightColumn: Frame? = nil
local viewport: ViewportFrame? = nil
local gridFrame: ScrollingFrame? = nil
local gridLayout: UIGridLayout? = nil
local gridPadding: UIPadding? = nil
local sideDivider: Frame? = nil

type SlotWidget = {
	button: TextButton,
	icon: Frame,
	glyph: TextLabel,
	levelLabel: TextLabel,
	stroke: UIStroke,
}
local slotWidgets: { [string]: SlotWidget } = {}
local gridCells: { Instance } = {}
local emptyCells: { Instance } = {}
local gridItemCount = 0
-- Latest computed unequipped tile size (px); equipped slots match this.
local inventoryCellSize = 0

-- Idle-animation state. `rigModel` is the player's loaded avatar (R-E1); when it
-- fails to load we fall back to the blocky placeholder parts in `rigParts`.
local rigModel: Model? = nil
local rigParts: { [string]: BasePart } = {}
local rigConnection: RBXScriptConnection? = nil
local rigStartClock = 0

-- Detail popup elements + current selection context.
local popupOverlay: Frame? = nil
local popupCard: Frame? = nil
local popupTitle: TextLabel? = nil
local popupSubtitle: TextLabel? = nil
local popupStat: TextLabel? = nil
local popupSlotLevel: TextLabel? = nil
local popupActionButton: TextButton? = nil
local popupUpgradeButton: TextButton? = nil
local popupCostLabel: TextLabel? = nil
local popupSelectedUid: string? = nil
local popupAction: (() -> ())? = nil
local popupUpgradeAction: (() -> ())? = nil

-- Merge panel elements + selection state (R-E9). `mergeSelected` holds up to
-- three chosen gear uids; the list is filtered to the first pick's type+rarity.
local mergeTriggerButton: TextButton? = nil
local inventoryTitle: TextLabel? = nil
local mergeOverlay: Frame? = nil
local mergeCard: Frame? = nil
local mergeInputButtons: { TextButton } = {}
local mergeOutputFrame: Frame? = nil
local mergeConfirmButton: TextButton? = nil
local mergeListFrame: ScrollingFrame? = nil
local mergeListCells: { Instance } = {}
local mergeSelected: { string } = {}
-- What the merge/auto button currently does: "auto", "manual", or "disabled".
local mergeButtonMode = "disabled"

-- ==================== small helpers ====================

local function abbrev(name: string): string
	return string.upper(string.sub(name, 1, 3))
end

-- Blend `color` toward the panel color to produce a muted fill.
local function dim(color: Color3, alpha: number): Color3
	return color:Lerp(UIFactory.Theme.Panel, alpha)
end

-- Destroy previously-built gear (item) cells (leaves layout/padding intact).
local function clearGrid()
	for _, cell in gridCells do
		cell:Destroy()
	end
	table.clear(gridCells)
end

-- Destroy the placeholder empty tiles.
local function clearEmpties()
	for _, cell in emptyCells do
		cell:Destroy()
	end
	table.clear(emptyCells)
end

-- ==================== rig + idle animation ====================

local function makePart(name: string, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Position the viewport camera to frame `model` from the front, using its
-- bounding box so avatars of any scale fit. Views along the rig's own facing
-- direction so we always see the avatar's face.
local function frameCamera(vp: ViewportFrame, model: Model)
	local camera = vp.CurrentCamera
	if not camera then
		return
	end
	local boundingCFrame, size = model:GetBoundingBox()
	local center = boundingCFrame.Position
	local extent = math.max(size.X, size.Y)
	local distance = (extent / 2) / math.tan(math.rad(camera.FieldOfView / 2)) * 1.4

	local root = model:FindFirstChild("HumanoidRootPart")
	local front = if root and root:IsA("BasePart") then root.CFrame.LookVector else Vector3.new(0, 0, -1)
	camera.CFrame = CFrame.lookAt(center + front * distance, center)
end

-- Blocky placeholder rig used when the real avatar cannot be loaded (offline /
-- API disabled). Kept as a graceful fallback so the tab is never empty.
local function buildBlockyRig(vp: ViewportFrame)
	local camera = vp.CurrentCamera or Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.2, 9), Vector3.new(0, -0.3, 0))
	camera.Parent = vp
	vp.CurrentCamera = camera

	local bodyColor = AssetResolver.resolve("rig/idle").color
	local model = Instance.new("Model")
	model.Name = "BlockyRig"

	rigParts.torso = makePart("Torso", Vector3.new(2, 2, 1), UIFactory.Theme.Accent)
	rigParts.head = makePart("Head", Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(232, 210, 180))
	rigParts.leftArm = makePart("LeftArm", Vector3.new(0.8, 2, 0.8), bodyColor)
	rigParts.rightArm = makePart("RightArm", Vector3.new(0.8, 2, 0.8), bodyColor)
	rigParts.leftLeg = makePart("LeftLeg", Vector3.new(0.9, 2, 0.9), dim(bodyColor, 0.35))
	rigParts.rightLeg = makePart("RightLeg", Vector3.new(0.9, 2, 0.9), dim(bodyColor, 0.35))

	for _, part in rigParts do
		part.Parent = model
	end
	model.Parent = vp
end

-- Default R15 idle animation clip. We use this rather than the player's equipped
-- HumanoidDescription.IdleAnimation because that id points to an animation
-- PACKAGE (bundle), which is not a directly loadable AnimationClip — the engine
-- only resolves packages when a character spawns normally, so LoadAnimation on it
-- fails ("AnimationClip loaded is not valid"). This default is a plain, valid clip.
local DEFAULT_IDLE_ANIMATION = 507766388

-- Load and loop the idle animation. Requires the model to sit under a WorldModel
-- so the Animator evaluates inside the ViewportFrame.
local function playIdle(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(DEFAULT_IDLE_ANIMATION)

	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track:Play()
	end
end

-- Parent the loaded avatar into a WorldModel inside the viewport, anchor its
-- root, play its idle animation, and frame the camera. A 1-to-1 avatar display.
local function setupPlayerRig(vp: ViewportFrame, model: Model)
	model.Name = "PlayerRig"

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "RigWorld"
	worldModel.Parent = vp

	model.Parent = worldModel
	model:PivotTo(CFrame.identity)

	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end

	rigModel = model
	playIdle(model)
	frameCamera(vp, model)
end

-- Build the character rig: try the player's real avatar first (R-E1), then fall
-- back to the placeholder. Runs async so bootstrap is not blocked by the fetch.
local function buildRig(vp: ViewportFrame)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.2, 9), Vector3.new(0, -0.3, 0))
	camera.Parent = vp
	vp.CurrentCamera = camera

	vp.Ambient = Color3.fromRGB(190, 194, 205)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.6).Unit

	rigStartClock = os.clock()

	task.spawn(function()
		local player = Players.LocalPlayer
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromUserId(player.UserId)
		end)
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			setupPlayerRig(vp, model)
		else
			warn("[EquipmentTab] avatar load failed, using placeholder rig:", model)
			buildBlockyRig(vp)
		end
	end)
end

-- Per-frame idle pose. The real avatar plays its own looping idle animation, so
-- nothing is done here for it; only the blocky fallback is code-animated.
local function animateRig()
	if rigModel then
		return
	end
	if not rigParts.torso then
		return
	end
	local t = os.clock() - rigStartClock
	local bob = math.sin(t * 2) * 0.1
	local yaw = math.sin(t * 0.8) * math.rad(12)
	local pivot = CFrame.new(0, bob, 0) * CFrame.Angles(0, yaw, 0)
	rigParts.torso.CFrame = pivot
	rigParts.head.CFrame = pivot * CFrame.new(0, 1.6, 0)
	rigParts.leftLeg.CFrame = pivot * CFrame.new(-0.5, -2, 0)
	rigParts.rightLeg.CFrame = pivot * CFrame.new(0.5, -2, 0)

	local swing = math.sin(t * 2) * math.rad(10)
	rigParts.leftArm.CFrame = pivot * CFrame.new(-1.4, 0.9, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -1, 0)
	rigParts.rightArm.CFrame = pivot * CFrame.new(1.4, 0.9, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -1, 0)
end

-- ==================== detail popup ====================

local function closePopup()
	popupSelectedUid = nil
	popupAction = nil
	popupUpgradeAction = nil
	if popupOverlay then
		popupOverlay.Visible = false
	end
end

-- Fill the popup with a gear instance's details and wire its action button to
-- Equip (if unequipped) or Unequip (if currently in its slot). Returns false if
-- the gear can no longer be resolved (e.g. it was removed).
local function populatePopup(gearUid: string): boolean
	local data = DataController.get()
	if not data then
		return false
	end
	local inst = data.gear[gearUid]
	if not inst then
		return false
	end
	local gearDef = Gear.get(inst.id)
	local slotDef = gearDef and Slots.get(gearDef.slot)
	if not (gearDef and slotDef) then
		return false
	end

	local slotId = slotDef.id
	local slotLevel = data.slotLevels[slotId] or 1
	local rarityDef = Rarities.get(inst.rarity)
	local rarityColor = rarityDef and rarityDef.color or UIFactory.Theme.Text

	local titleLabel = popupTitle :: TextLabel
	titleLabel.Text = gearDef.name
	titleLabel.TextColor3 = rarityColor

	local subtitleLabel = popupSubtitle :: TextLabel
	subtitleLabel.Text = ("%s  -  %s"):format(inst.rarity, slotDef.name)

	local statLabel = popupStat :: TextLabel
	local gearStat = GearStats.compute(inst.id, inst.rarity, slotLevel)
	if gearStat then
		statLabel.Text = ("%s: %s"):format(GearStats.statLabel(gearStat.stat), GearStats.format(gearStat))
	else
		statLabel.Text = ""
	end

	local slotLevelLabel = popupSlotLevel :: TextLabel
	slotLevelLabel.Text = ("Slot Level %d"):format(slotLevel)

	local isEquipped = data.equipped[slotId] == gearUid
	local button = popupActionButton :: TextButton
	local upgrade = popupUpgradeButton :: TextButton
	local costLabel = popupCostLabel :: TextLabel
	if isEquipped then
		button.Text = "Unequip"
		button.BackgroundColor3 = UIFactory.Theme.Negative
		popupAction = function()
			if unequipRemote then
				unequipRemote:FireServer(slotId)
			end
			closePopup()
		end

		-- Upgrade (level up the slot) is only offered for the equipped piece.
		-- Spends Slot Materials; stays open so the new level/stat update live (R-E8).
		upgrade.Visible = true
		if slotLevel >= Balance.SlotLevels.maxLevel then
			upgrade.Text = "Max Level"
			upgrade.AutoButtonColor = false
			upgrade.BackgroundColor3 = UIFactory.Theme.PanelAlt
			popupUpgradeAction = nil
			costLabel.Visible = false
		else
			-- Slot leveling spends Slot Materials (R-E8); the server validates
			-- affordability and toasts on failure.
			local materials = (data.currencies and data.currencies.materials) or 0
			local upgradeCost = Balance.SlotLevels.baseCost + (slotLevel - 1) * Balance.SlotLevels.costPerLevel
			local canAfford = materials >= upgradeCost

			upgrade.Text = ("Upgrade (%d M)"):format(upgradeCost)
			upgrade.AutoButtonColor = canAfford
			upgrade.BackgroundColor3 = canAfford and UIFactory.Theme.Accent or UIFactory.Theme.PanelAlt
			popupUpgradeAction = canAfford and function()
				if levelSlotRemote then
					levelSlotRemote:FireServer(slotId)
				end
			end or nil

			costLabel.Text = ("You have %d Materials  /  Upgrade: %d Materials"):format(materials, upgradeCost)
			costLabel.Visible = true
		end
	else
		button.Text = "Equip"
		button.BackgroundColor3 = UIFactory.Theme.Positive
		popupAction = function()
			if equipRemote then
				equipRemote:FireServer(gearUid)
			end
			closePopup()
		end

		upgrade.Visible = false
		popupUpgradeAction = nil
		costLabel.Visible = false
	end

	popupSelectedUid = gearUid
	return true
end

local function openPopup(gearUid: string)
	if populatePopup(gearUid) and popupOverlay then
		popupOverlay.Visible = true
	end
end

-- If the popup is open, refresh it against the latest data (or close if stale).
local function refreshPopup()
	if popupOverlay and popupOverlay.Visible and popupSelectedUid then
		if not populatePopup(popupSelectedUid) then
			closePopup()
		end
	end
end

local function buildPopup(parent: Frame)
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
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 21,
	})
	card.Parent = overlay
	popupCard = card
	UIFactory.corner(12).Parent = card
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = card
	UIFactory.padding(18).Parent = card

	local layout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
	})
	layout.Parent = card

	local title = UIFactory.textLabel({
		Name = "Title",
		LayoutOrder = 1,
		Size = UDim2.new(1, -30, 0, 30),
		Font = Theme.FontBold,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
	})
	title.Parent = card
	popupTitle = title

	local subtitle = UIFactory.textLabel({
		Name = "Subtitle",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.SubText,
		TextSize = 16,
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
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.FontBold,
		TextColor3 = Theme.Positive,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
	})
	stat.Parent = card
	popupStat = stat

	local slotLevel = UIFactory.textLabel({
		Name = "SlotLevel",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.SubText,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
	})
	slotLevel.Parent = card
	popupSlotLevel = slotLevel

	local action = UIFactory.textButton({
		Name = "Action",
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 46),
		TextSize = 20,
		Text = "Equip",
		ZIndex = 21,
	})
	action.Parent = card
	UIFactory.corner(10).Parent = action
	popupActionButton = action
	action.Activated:Connect(function()
		if popupAction then
			popupAction()
		end
	end)

	-- Upgrade button: levels the slot (equipped gear only). Hidden by default.
	local upgrade = UIFactory.textButton({
		Name = "Upgrade",
		LayoutOrder = 7,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Theme.Accent,
		TextSize = 20,
		Text = "Upgrade (Free)",
		Visible = false,
		ZIndex = 21,
	})
	upgrade.Parent = card
	UIFactory.corner(10).Parent = upgrade
	popupUpgradeButton = upgrade
	upgrade.Activated:Connect(function()
		if popupUpgradeAction then
			popupUpgradeAction()
		end
	end)

	-- Balance / upgrade-cost line, shown at the very bottom below the Upgrade
	-- button when an equipped piece is selected.
	local cost = UIFactory.textLabel({
		Name = "UpgradeCost",
		LayoutOrder = 8,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextColor3 = Theme.SubText,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 21,
	})
	cost.Parent = card
	popupCostLabel = cost

	-- Close (X) button, top-right of the card.
	local close = UIFactory.textButton({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Theme.PanelAlt,
		Text = "X",
		TextSize = 18,
		ZIndex = 22,
	})
	close.Parent = card
	UIFactory.corner(8).Parent = close
	close.Activated:Connect(closePopup)
end

-- ==================== slots ====================

local function buildSlotButton(slotId: string): TextButton
	local Theme = UIFactory.Theme
	local slotDef = Slots.get(slotId)

	local button = UIFactory.textButton({
		Name = slotId,
		BackgroundColor3 = Theme.Panel,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(72, 72),
		LayoutOrder = slotDef and slotDef.row or 1,
	})
	UIFactory.corner(10).Parent = button
	UIFactory.aspectRatio(1).Parent = button
	local stroke = UIFactory.stroke({ Color = Theme.Stroke })
	stroke.Parent = button

	local icon = UIFactory.frame({
		Name = "Icon",
		BackgroundColor3 = Theme.PanelAlt,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
	})
	icon.Parent = button
	UIFactory.corner(8).Parent = icon

	local glyph = UIFactory.textLabel({
		Name = "Glyph",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = 16,
		Text = slotDef and abbrev(slotDef.name) or "?",
	})
	glyph.Parent = icon

	-- Slot-level badge (bottom-middle). Level is tied to the slot (R-E3) and is
	-- only shown while a gear is equipped in this slot (set in renderSlots).
	local badge = UIFactory.frame({
		Name = "LevelBadge",
		BackgroundColor3 = Theme.Background,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.fromOffset(34, 16),
		Visible = false,
	})
	badge.Parent = button
	UIFactory.corner(6).Parent = badge
	local levelLabel = UIFactory.textLabel({
		Name = "Level",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextSize = 12,
		Text = "Lv 1",
	})
	levelLabel.Parent = badge

	slotWidgets[slotId] = {
		button = button,
		icon = icon,
		glyph = glyph,
		badge = badge,
		levelLabel = levelLabel,
		stroke = stroke,
	}

	button.Activated:Connect(function()
		local data = DataController.get()
		if not data then
			return
		end
		local equippedUid = data.equipped[slotId]
		if equippedUid then
			openPopup(equippedUid)
		end
	end)

	return button
end

-- ==================== grid cell ====================

local function buildGridCell(gearUid: string, inst: any, order: number): ImageButton
	local Theme = UIFactory.Theme
	local rarityDef = Rarities.get(inst.rarity)
	local rarityColor = rarityDef and rarityDef.color or Theme.SubText
	local gearDef = Gear.get(inst.id)
	local slotDef = gearDef and Slots.get(gearDef.slot)

	local cell = UIFactory.imageButton({
		Name = gearUid,
		BackgroundColor3 = dim(rarityColor, 0.35),
		BackgroundTransparency = 0,
		LayoutOrder = order,
		AutoButtonColor = true,
	})
	UIFactory.corner(8).Parent = cell
	UIFactory.stroke({ Color = rarityColor, Thickness = 2 }).Parent = cell

	local glyph = UIFactory.textLabel({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.AccentText,
		TextSize = 18,
		Text = slotDef and abbrev(slotDef.name) or "?",
	})
	glyph.Parent = cell

	cell.Activated:Connect(function()
		openPopup(gearUid)
	end)

	return cell
end

-- A non-interactive placeholder tile that signals free inventory capacity (R-E4).
local function buildEmptyCell(order: number): Frame
	local Theme = UIFactory.Theme
	local cell = UIFactory.frame({
		Name = "Empty",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.3,
		LayoutOrder = order,
	})
	UIFactory.corner(8).Parent = cell
	local stroke = UIFactory.stroke({ Color = Theme.Stroke })
	stroke.Transparency = 0.35
	stroke.Parent = cell

	local plus = UIFactory.textLabel({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.SubText,
		TextTransparency = 0.55,
		TextSize = 22,
		Text = "+",
	})
	plus.Parent = cell
	return cell
end

-- Size the grid to a fixed column count for the current width, then top up the
-- last row(s) with empty tiles. Called on data change and whenever the grid
-- resizes (so column count / empty count stay correct).
local function layoutGrid()
	if not (gridFrame and gridLayout) then
		return
	end
	local grid = gridFrame :: ScrollingFrame
	local gLayout = gridLayout :: UIGridLayout

	local compact = Responsive.isCompact()
	local pad = Responsive.scaled(10)
	local edge = Responsive.scaled(8)
	local targetTile = Responsive.scaled(if compact then 84 else 96)

	local width = grid.AbsoluteSize.X
	if width <= 0 then
		return
	end

	-- Keep an inner buffer on all sides and reserve the scrollbar so no tile is
	-- clipped by the frame edge (the reported issue). Then derive the column
	-- count from a target size and size cells to fill the buffered width exactly.
	if gridPadding then
		local udim = UDim.new(0, edge)
		gridPadding.PaddingLeft = udim
		gridPadding.PaddingRight = udim
		gridPadding.PaddingTop = udim
		gridPadding.PaddingBottom = udim
	end

	local available = width - edge * 2 - grid.ScrollBarThickness
	if available <= 0 then
		return
	end

	local columns = InventoryLayout.columnCount(available, targetTile, pad)
	local cell = InventoryLayout.cellSize(available, columns, pad)
	gLayout.CellPadding = UDim2.fromOffset(pad, pad)
	gLayout.CellSize = UDim2.fromOffset(cell, cell)
	inventoryCellSize = cell

	-- Fill out complete rows with empty tiles so the inventory reads as having
	-- spare capacity. A new row of empties only appears once items overflow the
	-- current rows (or the minimum needed to fill the visible area). See
	-- Shared/Logic/InventoryLayout (unit-tested in tests/LogicTests).
	clearEmpties()
	local height = grid.AbsoluteSize.Y - edge * 2
	local minRows = math.max(1, math.floor((height + pad) / (cell + pad)))
	local plan = InventoryLayout.plan(gridItemCount, columns, minRows)
	for i = 1, plan.emptyCount do
		local tile = buildEmptyCell(gridItemCount + i)
		tile.Parent = grid
		table.insert(emptyCells, tile)
	end
end

-- ==================== render ====================

local function renderSlots(data: any)
	for slotId, widget in slotWidgets do
		local Theme = UIFactory.Theme
		local level = data.slotLevels[slotId] or 1
		widget.levelLabel.Text = ("Lv %d"):format(level)

		local equippedUid = data.equipped[slotId]
		local inst = equippedUid and data.gear[equippedUid]
		-- Only surface the slot level when something is actually equipped here.
		widget.badge.Visible = inst ~= nil
		if inst then
			local rarityDef = Rarities.get(inst.rarity)
			local rarityColor = rarityDef and rarityDef.color or Theme.SubText
			widget.icon.BackgroundColor3 = dim(rarityColor, 0.25)
			widget.stroke.Color = rarityColor
			widget.stroke.Thickness = 2
			widget.glyph.TextColor3 = Theme.AccentText
		else
			widget.icon.BackgroundColor3 = Theme.PanelAlt
			widget.stroke.Color = Theme.Stroke
			widget.stroke.Thickness = 1
			widget.glyph.TextColor3 = Theme.SubText
		end
	end
end

local function renderGrid(data: any)
	clearGrid()

	-- Collect currently-equipped uids so they are excluded from the grid (R-E4).
	local equippedSet: { [string]: boolean } = {}
	for _, uid in data.equipped do
		if uid then
			equippedSet[uid] = true
		end
	end

	local list: { { uid: string, inst: any } } = {}
	for uid, inst in data.gear do
		if not equippedSet[uid] then
			table.insert(list, { uid = uid, inst = inst })
		end
	end

	-- Rarity descending, then uid for a stable order (R-E4).
	table.sort(list, function(a, b)
		local ra = Rarities.orderOf(a.inst.rarity)
		local rb = Rarities.orderOf(b.inst.rarity)
		if ra ~= rb then
			return ra > rb
		end
		return a.uid < b.uid
	end)

	for index, entry in list do
		local cell = buildGridCell(entry.uid, entry.inst, index)
		cell.Parent = gridFrame
		table.insert(gridCells, cell)
	end

	gridItemCount = #list
	layoutGrid()
end

-- ==================== merge panel ====================

local MERGE_COUNT = MergeLogic.COUNT

-- Forward declarations so handlers and refreshers can reference each other.
local refreshMergeSlots: () -> ()
local refreshMergeList: () -> ()

-- The type + rarity filter implied by the first selected gear, or nil if none.
local function currentMergeFilter(): { slot: string, rarity: string }?
	local data = DataController.get()
	local firstUid = mergeSelected[1]
	if not (data and firstUid) then
		return nil
	end
	local inst = data.gear[firstUid]
	if not inst then
		return nil
	end
	local slot = MergeLogic.slotOf(inst)
	if not slot then
		return nil
	end
	return { slot = slot, rarity = inst.rarity }
end

local function isSelected(uid: string): boolean
	for _, u in mergeSelected do
		if u == uid then
			return true
		end
	end
	return false
end

-- Paint an input/output tile to show a gear instance, or an empty placeholder.
local function styleGearTile(container: GuiObject, inst: any, emptyGlyph: string)
	local Theme = UIFactory.Theme
	local glyph = container:FindFirstChild("Glyph") :: TextLabel?
	local stroke = container:FindFirstChildWhichIsA("UIStroke") :: UIStroke?
	if inst then
		local gearDef = Gear.get(inst.id)
		local slotDef = gearDef and Slots.get(gearDef.slot)
		local rarityDef = Rarities.get(inst.rarity)
		local rarityColor = rarityDef and rarityDef.color or Theme.SubText
		container.BackgroundColor3 = dim(rarityColor, 0.35)
		if stroke then
			stroke.Color = rarityColor
			stroke.Thickness = 2
		end
		if glyph then
			glyph.Text = slotDef and abbrev(slotDef.name) or "?"
			glyph.TextColor3 = Theme.AccentText
		end
	else
		container.BackgroundColor3 = Theme.Background
		if stroke then
			stroke.Color = Theme.Stroke
			stroke.Thickness = 1
		end
		if glyph then
			glyph.Text = emptyGlyph
			glyph.TextColor3 = Theme.SubText
		end
	end
end

-- True if the player owns at least one auto-mergeable set (3 same type+rarity).
local function autoMergeAvailable(): boolean
	local data = DataController.get()
	if not data then
		return false
	end
	local instances: { { uid: string, id: string, rarity: string } } = {}
	for uid, inst in data.gear do
		table.insert(instances, { uid = uid, id = inst.id, rarity = inst.rarity })
	end
	return #MergeLogic.planAuto(instances).removeUids > 0
end

function refreshMergeSlots()
	local Theme = UIFactory.Theme
	local data = DataController.get()

	for index, button in mergeInputButtons do
		local uid = mergeSelected[index]
		local inst = uid and data and data.gear[uid] or nil
		styleGearTile(button, inst, "+")
	end

	-- Output preview = the upgrade of the first pick (all picks share type+rarity).
	local firstUid = mergeSelected[1]
	local firstInst = firstUid and data and data.gear[firstUid] or nil
	local preview = MergeLogic.resultFor(firstInst)
	if mergeOutputFrame then
		styleGearTile(mergeOutputFrame, preview, "?")
	end

	-- Button behaviour depends on whether a manual selection has started:
	--  * 0 picked  -> "Auto Merge Equipment" (enabled only if something can merge)
	--  * 1-2 picked -> "Select N gear" (disabled; manual flow in progress)
	--  * 3 picked   -> "Merge" (enabled when the upgrade is valid)
	local confirm = mergeConfirmButton
	if confirm then
		if #mergeSelected == 0 then
			confirm.Text = "Auto Merge Equipment"
			if autoMergeAvailable() then
				confirm.BackgroundColor3 = Theme.Accent
				confirm.AutoButtonColor = true
				mergeButtonMode = "auto"
			else
				confirm.BackgroundColor3 = Theme.PanelAlt
				confirm.AutoButtonColor = false
				mergeButtonMode = "disabled"
			end
		elseif #mergeSelected == MERGE_COUNT and preview ~= nil then
			confirm.Text = "Merge"
			confirm.BackgroundColor3 = Theme.Positive
			confirm.AutoButtonColor = true
			mergeButtonMode = "manual"
		elseif #mergeSelected < MERGE_COUNT then
			confirm.Text = ("Select %d gear"):format(MERGE_COUNT - #mergeSelected)
			confirm.BackgroundColor3 = Theme.PanelAlt
			confirm.AutoButtonColor = false
			mergeButtonMode = "disabled"
		else
			confirm.Text = "Cannot merge"
			confirm.BackgroundColor3 = Theme.PanelAlt
			confirm.AutoButtonColor = false
			mergeButtonMode = "disabled"
		end
	end
end

local function addMergeSelection(uid: string)
	if #mergeSelected >= MERGE_COUNT or isSelected(uid) then
		return
	end
	local data = DataController.get()
	if not data then
		return
	end
	local inst = data.gear[uid]
	if not inst then
		return
	end
	-- After the first pick, enforce matching type + rarity.
	local filter = currentMergeFilter()
	if filter and (MergeLogic.slotOf(inst) ~= filter.slot or inst.rarity ~= filter.rarity) then
		return
	end
	table.insert(mergeSelected, uid)
	refreshMergeSlots()
	refreshMergeList()
end

local function removeMergeSelection(index: number)
	if not mergeSelected[index] then
		return
	end
	table.remove(mergeSelected, index)
	refreshMergeSlots()
	refreshMergeList()
end

local function clearMergeList()
	for _, cell in mergeListCells do
		cell:Destroy()
	end
	table.clear(mergeListCells)
end

-- One selectable gear tile in the merge list; labels equipped pieces "Equipped".
local function buildMergeListTile(uid: string, inst: any, equipped: boolean): TextButton
	local Theme = UIFactory.Theme
	local rarityDef = Rarities.get(inst.rarity)
	local rarityColor = rarityDef and rarityDef.color or Theme.SubText
	local gearDef = Gear.get(inst.id)
	local slotDef = gearDef and Slots.get(gearDef.slot)

	local cell = UIFactory.textButton({
		Name = uid,
		BackgroundColor3 = dim(rarityColor, 0.35),
		AutoButtonColor = true,
		Text = "",
	})
	UIFactory.corner(8).Parent = cell
	UIFactory.stroke({ Color = rarityColor, Thickness = 2 }).Parent = cell

	local glyph = UIFactory.textLabel({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.AccentText,
		TextSize = 18,
		Text = slotDef and abbrev(slotDef.name) or "?",
	})
	glyph.Parent = cell

	if equipped then
		local tag = UIFactory.textLabel({
			Name = "EquippedTag",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.new(1, -6, 0, 14),
			BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.15,
			Font = Theme.FontBold,
			TextColor3 = Theme.Positive,
			TextSize = 11,
			Text = "Equipped",
		})
		UIFactory.corner(4).Parent = tag
		tag.Parent = cell
	end

	cell.Activated:Connect(function()
		addMergeSelection(uid)
	end)
	return cell
end

function refreshMergeList()
	clearMergeList()
	local data = DataController.get()
	if not (data and mergeListFrame) then
		return
	end

	local equippedSet: { [string]: boolean } = {}
	for _, uid in data.equipped do
		if uid then
			equippedSet[uid] = true
		end
	end

	local filter = currentMergeFilter()
	local list: { { uid: string, inst: any } } = {}
	for uid, inst in data.gear do
		if isSelected(uid) then
			continue
		end
		-- Skip gear that cannot be upgraded (e.g. Legendary has no higher tier).
		if not Rarities.next(inst.rarity) then
			continue
		end
		if filter and (MergeLogic.slotOf(inst) ~= filter.slot or inst.rarity ~= filter.rarity) then
			continue
		end
		table.insert(list, { uid = uid, inst = inst })
	end

	-- Rarity descending, then slot, then uid for a stable, grouped order.
	table.sort(list, function(a, b)
		local ra = Rarities.orderOf(a.inst.rarity)
		local rb = Rarities.orderOf(b.inst.rarity)
		if ra ~= rb then
			return ra > rb
		end
		local sa = MergeLogic.slotOf(a.inst) or ""
		local sb = MergeLogic.slotOf(b.inst) or ""
		if sa ~= sb then
			return sa < sb
		end
		return a.uid < b.uid
	end)

	for _, entry in list do
		local cell = buildMergeListTile(entry.uid, entry.inst, equippedSet[entry.uid] == true)
		cell.Parent = mergeListFrame
		table.insert(mergeListCells, cell)
	end
end

local function closeMergePanel()
	table.clear(mergeSelected)
	if mergeOverlay then
		mergeOverlay.Visible = false
	end
end

local function openMergePanel()
	table.clear(mergeSelected)
	if mergeOverlay then
		mergeOverlay.Visible = true
	end
	refreshMergeSlots()
	refreshMergeList()
end

-- Keep the panel consistent after any profile change (e.g. a successful merge
-- removes the consumed uids). Prunes stale selections, then re-renders.
local function refreshMergePanel()
	if not (mergeOverlay and mergeOverlay.Visible) then
		return
	end
	local data = DataController.get()
	if data then
		local kept: { string } = {}
		for _, uid in mergeSelected do
			if data.gear[uid] then
				table.insert(kept, uid)
			end
		end
		mergeSelected = kept
	end
	refreshMergeSlots()
	refreshMergeList()
end

local function render()
	local data = DataController.get()
	if not data then
		return
	end
	renderSlots(data)
	renderGrid(data)
	refreshPopup()
	refreshMergePanel()
end

-- ==================== layout (responsive) ====================

-- Number of equipment slots on the busier side (used to bound slot tile size).
local function maxSlotsPerSide(): number
	local counts: { [string]: number } = {}
	for _, slotId in Slots.Order do
		local def = Slots.get(slotId)
		if def then
			counts[def.side] = (counts[def.side] or 0) + 1
		end
	end
	local most = 1
	for _, n in counts do
		most = math.max(most, n)
	end
	return most
end

-- Spread a side's slots evenly from the top to the bottom of its column and size
-- each tile to `tile`. Using AnchorPoint.Y == Position.Y scale keeps every tile
-- inside the column bounds (top tile top-aligned, bottom tile bottom-aligned).
local function layoutColumn(side: string, tile: number)
	local sideSlots: { { id: string, row: number } } = {}
	for _, slotId in Slots.Order do
		local def = Slots.get(slotId)
		if def and def.side == side then
			table.insert(sideSlots, { id = slotId, row = def.row })
		end
	end
	table.sort(sideSlots, function(a, b)
		return a.row < b.row
	end)

	local n = #sideSlots
	for i, entry in sideSlots do
		local widget = slotWidgets[entry.id]
		if widget then
			local f = if n > 1 then (i - 1) / (n - 1) else 0.5
			widget.button.AnchorPoint = Vector2.new(0.5, f)
			widget.button.Position = UDim2.new(0.5, 0, f, 0)
			widget.button.Size = UDim2.fromOffset(tile, tile)
		end
	end
end

local function layout()
	if not (rootFrame and characterArea and viewport and gridFrame and gridLayout) then
		return
	end
	local compact = Responsive.isCompact()
	local gap = Responsive.scaled(12)

	local gridArea = rootFrame:FindFirstChild("InventoryArea") :: Frame?
	local divider = sideDivider

	-- Phone/compact: stack character (top) over inventory (bottom).
	-- Desktop: character on the LEFT, gear grid on the RIGHT.
	-- A divider line makes a clear cut between the two sides.
	if compact then
		local charHeightScale = 0.5
		characterArea.Position = UDim2.fromScale(0, 0)
		characterArea.Size = UDim2.new(1, 0, charHeightScale, -gap)
		if gridArea then
			gridArea.Position = UDim2.new(0, 0, charHeightScale, 0)
			gridArea.Size = UDim2.new(1, 0, 1 - charHeightScale, 0)
		end
		if divider then
			divider.AnchorPoint = Vector2.new(0.5, 0.5)
			divider.Position = UDim2.fromScale(0.5, charHeightScale)
			divider.Size = UDim2.new(1, 0, 0, 1)
		end
	else
		local charWidthScale = 0.5
		characterArea.Position = UDim2.fromScale(0, 0)
		characterArea.Size = UDim2.new(charWidthScale, -gap, 1, 0)
		if gridArea then
			gridArea.Position = UDim2.new(charWidthScale, gap, 0, 0)
			gridArea.Size = UDim2.new(1 - charWidthScale, -gap, 1, 0)
		end
		if divider then
			divider.AnchorPoint = Vector2.new(0.5, 0.5)
			divider.Position = UDim2.fromScale(charWidthScale, 0.5)
			divider.Size = UDim2.new(0, 1, 1, 0)
		end
	end

	-- Viewport fills the character area; the equipped-gear columns sit ON TOP of
	-- its edges so the gear overlaps the rig and reads as one panel (R-E1/R-E2).
	viewport.Position = UDim2.fromScale(0, 0)
	viewport.Size = UDim2.fromScale(1, 1)

	-- Refresh the inventory first so equipped tiles can match its cell size.
	layoutGrid()

	-- Buffers keep the gear off the viewport edges; columns span top->bottom.
	local vBuffer = Responsive.scaled(16)
	local edgeBuffer = Responsive.scaled(12)
	local perSide = maxSlotsPerSide()
	local charH = characterArea.AbsoluteSize.Y
	local colH = math.max(0, charH - vBuffer * 2)

	-- Match the unequipped tile size, but never so large that the slots would
	-- overlap within the available column height.
	local target = if inventoryCellSize > 0 then inventoryCellSize else Responsive.scaled(76)
	local maxTile = if colH > 0 then colH / perSide else target
	local tile = math.clamp(math.min(target, maxTile), Responsive.scaled(44), Responsive.scaled(140))

	if leftColumn and rightColumn then
		leftColumn.AnchorPoint = Vector2.new(0, 0.5)
		leftColumn.Position = UDim2.new(0, edgeBuffer, 0.5, 0)
		leftColumn.Size = UDim2.new(0, tile, 1, -vBuffer * 2)
		rightColumn.AnchorPoint = Vector2.new(1, 0.5)
		rightColumn.Position = UDim2.new(1, -edgeBuffer, 0.5, 0)
		rightColumn.Size = UDim2.new(0, tile, 1, -vBuffer * 2)
		layoutColumn("Left", tile)
		layoutColumn("Right", tile)
	end

	if popupCard then
		popupCard.Size = UDim2.fromOffset(Responsive.scaled(320), 0)
	end
end

-- ==================== build ====================

-- One clickable input slot in the merge row; clicking removes its selection.
local function buildMergeInputTile(index: number): TextButton
	local Theme = UIFactory.Theme
	local btn = UIFactory.textButton({
		Name = "Input" .. index,
		BackgroundColor3 = Theme.Background,
		AutoButtonColor = false,
		Text = "",
	})
	UIFactory.corner(10).Parent = btn
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = btn
	local glyph = UIFactory.textLabel({
		Name = "Glyph",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.SubText,
		TextSize = 24,
		Text = "+",
	})
	glyph.Parent = btn
	btn.Activated:Connect(function()
		removeMergeSelection(index)
	end)
	return btn
end

-- The full-screen merge modal: 3 input slots -> upgraded preview, a merge button,
-- and a filtered list of the player's gear (R-E9).
local function buildMergePanel(parent: Instance)
	local Theme = UIFactory.Theme

	local overlay = UIFactory.frame({
		Name = "MergeOverlay",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 30,
	})
	overlay.Parent = parent
	mergeOverlay = overlay

	-- Backdrop blocks clicks to the tab behind. It does NOT close the panel —
	-- only the X button does (per request).
	local backdrop = UIFactory.textButton({
		Name = "Backdrop",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
	})
	backdrop.Parent = overlay

	local cardW = Responsive.scaled(660)
	local cardH = Responsive.scaled(720)
	local card = UIFactory.frame({
		Name = "Card",
		BackgroundColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(cardW, cardH),
		-- Absorb clicks so hitting empty card space doesn't reach the click-off
		-- backdrop behind it (only the X should close the panel).
		Active = true,
		ZIndex = 31,
	})
	card.Parent = overlay
	mergeCard = card
	UIFactory.corner(14).Parent = card
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = card
	UIFactory.padding(Responsive.scaled(22)).Parent = card

	local title = UIFactory.textLabel({
		Name = "Title",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, -34, 0, 30),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Merge Equipment",
		ZIndex = 31,
	})
	title.Parent = card

	local close = UIFactory.textButton({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Theme.PanelAlt,
		Text = "X",
		TextSize = 18,
		ZIndex = 32,
	})
	UIFactory.corner(8).Parent = close
	close.Parent = card
	close.Activated:Connect(closeMergePanel)

	local subtitle = UIFactory.textLabel({
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.SubText,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Pick 3 gear of the same type and rarity to upgrade them.",
		ZIndex = 31,
	})
	subtitle.Parent = card

	-- Merge row: three input slots, an arrow, and the upgraded preview.
	local rowH = Responsive.scaled(96)
	local row = UIFactory.frame({
		Name = "MergeRow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, rowH),
		ZIndex = 31,
	})
	row.Parent = card
	local rowLayout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Responsive.scaled(10)),
	})
	rowLayout.Parent = row

	table.clear(mergeInputButtons)
	for i = 1, MERGE_COUNT do
		local btn = buildMergeInputTile(i)
		btn.Size = UDim2.fromOffset(rowH, rowH)
		btn.LayoutOrder = i
		btn.ZIndex = 31
		btn.Parent = row
		table.insert(mergeInputButtons, btn)
	end

	local arrow = UIFactory.textLabel({
		Name = "Arrow",
		LayoutOrder = MERGE_COUNT + 1,
		Size = UDim2.fromOffset(Responsive.scaled(36), rowH),
		Font = Theme.FontBold,
		TextColor3 = Theme.SubText,
		TextSize = 28,
		Text = ">",
		ZIndex = 31,
	})
	arrow.Parent = row

	local output = UIFactory.frame({
		Name = "Output",
		LayoutOrder = MERGE_COUNT + 2,
		BackgroundColor3 = Theme.Background,
		Size = UDim2.fromOffset(rowH, rowH),
		ZIndex = 31,
	})
	UIFactory.corner(10).Parent = output
	UIFactory.stroke({ Color = Theme.Accent, Thickness = 2 }).Parent = output
	local oglyph = UIFactory.textLabel({
		Name = "Glyph",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.SubText,
		TextSize = 24,
		Text = "?",
		ZIndex = 31,
	})
	oglyph.Parent = output
	output.Parent = row
	mergeOutputFrame = output

	local confirmY = 64 + rowH + 18
	local confirm = UIFactory.textButton({
		Name = "Confirm",
		Position = UDim2.fromOffset(0, confirmY),
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Theme.PanelAlt,
		AutoButtonColor = false,
		TextSize = 20,
		Text = "Auto Merge Equipment",
		ZIndex = 31,
	})
	UIFactory.corner(10).Parent = confirm
	confirm.Parent = card
	mergeConfirmButton = confirm
	confirm.Activated:Connect(function()
		if mergeButtonMode == "manual" then
			if mergeGearRemote then
				mergeGearRemote:FireServer(table.clone(mergeSelected))
			end
		elseif mergeButtonMode == "auto" then
			if autoMergeGearRemote then
				autoMergeGearRemote:FireServer()
			end
		end
	end)

	local dividerY = confirmY + 50 + 18
	local divider = UIFactory.frame({
		Name = "Divider",
		Position = UDim2.fromOffset(0, dividerY),
		BackgroundColor3 = Theme.Stroke,
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 31,
	})
	divider.Parent = card

	local listLabelY = dividerY + 8
	local listLabel = UIFactory.textLabel({
		Name = "ListLabel",
		Position = UDim2.fromOffset(0, listLabelY),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Your Gear",
		ZIndex = 31,
	})
	listLabel.Parent = card

	local listY = listLabelY + 26
	local list = UIFactory.scrolling({
		Name = "GearList",
		Position = UDim2.fromOffset(0, listY),
		Size = UDim2.new(1, 0, 1, -listY),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 31,
	})
	list.Parent = card
	mergeListFrame = list
	local listGrid = UIFactory.gridLayout({
		CellSize = UDim2.fromOffset(Responsive.scaled(84), Responsive.scaled(84)),
		CellPadding = UDim2.fromOffset(Responsive.scaled(12), Responsive.scaled(12)),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	})
	listGrid.Parent = list
	-- Spacing buffer + scrollbar reservation so tiles never clip the edges,
	-- matching the inventory grid.
	local listBuffer = Responsive.scaled(12)
	local listPad = UIFactory.create("UIPadding", {
		PaddingLeft = UDim.new(0, listBuffer),
		PaddingRight = UDim.new(0, listBuffer + list.ScrollBarThickness),
		PaddingTop = UDim.new(0, listBuffer),
		PaddingBottom = UDim.new(0, listBuffer),
	})
	listPad.Parent = list
end

local function buildColumn(name: string, side: "Left" | "Right"): Frame
	-- Slots are positioned manually in layout() (spread top->bottom), so no
	-- UIListLayout here.
	return UIFactory.frame({
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 76, 1, 0),
		Position = if side == "Left" then UDim2.fromScale(0, 0) else UDim2.new(1, 0, 0, 0),
		AnchorPoint = if side == "Left" then Vector2.new(0, 0) else Vector2.new(1, 0),
	})
end

function EquipmentTab.init(injected: any)
	deps = injected
	UIFactory = deps.Util.UIFactory
	Responsive = deps.Util.Responsive
	AssetResolver = deps.Util.AssetResolver
	MenuShell = deps.UI.MenuShell
	DataController = deps.Controllers.DataController
	equipRemote = deps.Remotes.getEvent("EquipGear")
	unequipRemote = deps.Remotes.getEvent("UnequipGear")
	levelSlotRemote = deps.Remotes.getEvent("LevelSlot")
	mergeGearRemote = deps.Remotes.getEvent("MergeGear")
	autoMergeGearRemote = deps.Remotes.getEvent("AutoMergeGear")
end

function EquipmentTab.start()
	local content = MenuShell.getContentFrame("Equipment")
	if not content then
		warn("[EquipmentTab] Equipment content frame missing")
		return
	end

	-- Remove the shell placeholder now that we render the real view.
	local placeholder = content:FindFirstChild("Placeholder")
	if placeholder then
		placeholder:Destroy()
	end

	local Theme = UIFactory.Theme
	local root = UIFactory.frame({
		Name = "EquipmentRoot",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	root.Parent = content
	rootFrame = root

	-- Character area: rig viewport flanked by two slot columns.
	local charArea = UIFactory.frame({
		Name = "CharacterArea",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0.58, 0),
	})
	charArea.Parent = root
	characterArea = charArea

	local vp = UIFactory.create("ViewportFrame", {
		Name = "RigViewport",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	})
	vp.Parent = charArea
	viewport = vp
	UIFactory.corner(12).Parent = vp
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = vp
	buildRig(vp)

	leftColumn = buildColumn("LeftSlots", "Left")
	rightColumn = buildColumn("RightSlots", "Right")
	leftColumn.Parent = charArea
	rightColumn.Parent = charArea

	-- Place the six slots per Config/Slots (Left: Helmet/Weapon/Belt;
	-- Right: Charm/Chestplate/Boots) ordered top->bottom by `row` (R-E2).
	for _, slotId in Slots.Order do
		local slotDef = Slots.get(slotId)
		if slotDef then
			local button = buildSlotButton(slotId)
			button.Parent = if slotDef.side == "Left" then leftColumn else rightColumn
		end
	end

	-- Inventory area: title + unequipped gear grid.
	local inventoryArea = UIFactory.frame({
		Name = "InventoryArea",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0.42, 0),
		Position = UDim2.fromScale(0, 0.58),
	})
	inventoryArea.Parent = root

	-- Header stack: Merge Equipment button ON TOP, then the Inventory title, then
	-- the grid — so the button is obvious and the inventory shifts down (R-E9).
	local btnH = Responsive.scaled(44)
	local titleH = Responsive.scaled(24)
	local gap = Responsive.scaled(10)
	local titleY = btnH + gap
	local headerH = titleY + titleH + gap

	local mergeButton = UIFactory.textButton({
		Name = "MergeButton",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, btnH),
		BackgroundColor3 = Theme.Accent,
		Font = Theme.FontBold,
		TextColor3 = Theme.AccentText,
		TextSize = 20,
		Text = "Merge Equipment",
	})
	UIFactory.corner(10).Parent = mergeButton
	mergeButton.Parent = inventoryArea
	mergeTriggerButton = mergeButton
	mergeButton.Activated:Connect(openMergePanel)

	local invTitle = UIFactory.textLabel({
		Name = "Title",
		Position = UDim2.fromOffset(0, titleY),
		Size = UDim2.new(1, 0, 0, titleH),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Inventory",
	})
	invTitle.Parent = inventoryArea
	inventoryTitle = invTitle

	local grid = UIFactory.scrolling({
		Name = "GearGrid",
		Position = UDim2.new(0, 0, 0, headerH),
		Size = UDim2.new(1, 0, 1, -headerH),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	grid.Parent = inventoryArea
	gridFrame = grid

	local gLayout = UIFactory.gridLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	})
	gLayout.Parent = grid
	gridLayout = gLayout

	-- Inner buffer so tiles never touch/clip the grid edges (updated in layoutGrid).
	local gridPad = UIFactory.padding(Responsive.scaled(8))
	gridPad.Parent = grid
	gridPadding = gridPad

	-- Divider giving a clear cut between the character side and the inventory.
	sideDivider = UIFactory.frame({
		Name = "SideDivider",
		BackgroundColor3 = Theme.Stroke,
		Size = UDim2.new(0, 1, 1, 0),
	})
	sideDivider.Parent = root

	-- Re-flow inventory (columns + empty tiles) whenever the grid resizes.
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGrid)
	-- Re-run layout when the character area gets real dimensions, so equipped
	-- slot tiles size/spread correctly.
	charArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	buildPopup(root)
	buildMergePanel(root)

	layout()
	Responsive.onChanged(function()
		layout()
	end)

	-- Re-render on any authoritative profile change (equip/unequip/slot level).
	DataController.onChanged(function()
		render()
	end)
	if DataController.get() then
		render()
	end

	-- Drive the idle animation only while the Equipment tab is visible.
	rigConnection = RunService.RenderStepped:Connect(function()
		if MenuShell.getActiveTab() == "Equipment" then
			animateRig()
		end
	end)
end

return EquipmentTab
