--!strict
-- CombatUI: the full in-battle view (ARCHITECTURE 2, R-C3..R-C23). It renders the
-- authoritative combat state mirrored by CombatController and sends intents only
-- (server owns all outcomes, R-P5). Responsibilities:
--   * enemy row with HP + shield bars, selection highlight, tap-to-select (R-C3),
--   * player HP + shield bar with per-chapter level readout (R-C18/C21),
--   * dice with lock toggles (R-C10) and a reroll button showing rerolls left (R-C11),
--   * current hand + multiplier + dice-total feedback (R-C12/C13),
--   * an Attack button that strikes the selected enemy (R-C3),
--   * a pick-3 trait draft overlay at the dice cap (R-C23),
--   * victory / defeat screens with rewards, returning to the menu (R-C5/C20).
-- The combat ScreenGui overlays and hides the menu shell for the duration of a
-- battle, then restores it when the battle ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Logic = Shared:WaitForChild("Logic")
local Types = require(Shared:WaitForChild("Types"))
local Balance = require(Config:WaitForChild("Balance"))
local Chapters = require(Config:WaitForChild("Chapters"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Traits = require(Config:WaitForChild("Traits"))
local DiceHands = require(Logic:WaitForChild("DiceHands"))

type CombatState = Types.CombatState

local CombatUI = {}

local deps: any = nil
local UIFactory: any = nil
local Responsive: any = nil
local AssetResolver: any = nil
local MenuShell: any = nil
local CombatController: any = nil

-- Friendly display names for the hand keys from DiceHands/Balance (R-C12).
local HAND_NAMES: { [string]: string } = {
	highCard = "High Card",
	onePair = "One Pair",
	twoPair = "Two Pair",
	threeOfAKind = "Three of a Kind",
	straight = "Straight",
	fullHouse = "Full House",
	fourOfAKind = "Four of a Kind",
	fiveOfAKind = "Five of a Kind",
}

local SHIELD_COLOR = Color3.fromRGB(120, 210, 235)

-- ==================== widget references ====================

local screenGui: ScreenGui? = nil
local board: Frame? = nil
local topBar: Frame? = nil
local topInfoLabel: TextLabel? = nil
local phaseLabel: TextLabel? = nil
local enemiesArea: Frame? = nil
local enemiesRow: Frame? = nil
local feedbackBar: Frame? = nil
local feedbackLabel: TextLabel? = nil
local bottomPanel: Frame? = nil
local playerBarBg: Frame? = nil
local playerHpFill: Frame? = nil
local playerShieldFill: Frame? = nil
local playerBarLabel: TextLabel? = nil
local diceRow: Frame? = nil
local rerollButton: TextButton? = nil
local attackButton: TextButton? = nil

local traitOverlay: Frame? = nil
local traitCards: Frame? = nil
local endOverlay: Frame? = nil
local endTitle: TextLabel? = nil
local endSubtitle: TextLabel? = nil

-- ==================== runtime state ====================

local active = false -- a battle screen is currently shown
local selectedUid: string? = nil -- currently targeted enemy (R-C3)

-- ==================== small helpers ====================

local function scaled(px: number): number
	return Responsive.scaled(px)
end

-- Update a horizontal HP/shield bar. `shieldFill` overlays the left of the bar.
local function updateBar(hpFill: Frame, shieldFill: Frame, label: TextLabel, cur: number, max: number, shield: number)
	local hpRatio = if max > 0 then math.clamp(cur / max, 0, 1) else 0
	hpFill.Size = UDim2.fromScale(hpRatio, 1)
	local shieldRatio = if max > 0 then math.clamp(shield / max, 0, 1) else 0
	shieldFill.Size = UDim2.new(shieldRatio, 0, 0.42, 0)
	shieldFill.Visible = shield > 0
	if shield > 0 then
		label.Text = ("%d / %d   +%d"):format(math.max(0, math.floor(cur + 0.5)), math.floor(max + 0.5), math.floor(shield + 0.5))
	else
		label.Text = ("%d / %d"):format(math.max(0, math.floor(cur + 0.5)), math.floor(max + 0.5))
	end
end

-- Build an empty HP/shield bar; returns its updatable parts.
local function buildBar(hpColor: Color3): (Frame, Frame, Frame, TextLabel)
	local Theme = UIFactory.Theme
	local bg = UIFactory.frame({
		Name = "Bar",
		BackgroundColor3 = Color3.fromRGB(22, 24, 32),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
	})
	UIFactory.corner(6).Parent = bg
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = bg

	local hpFill = UIFactory.frame({
		Name = "HpFill",
		BackgroundColor3 = hpColor,
		Size = UDim2.fromScale(1, 1),
	})
	UIFactory.corner(6).Parent = hpFill
	hpFill.Parent = bg

	local shieldFill = UIFactory.frame({
		Name = "ShieldFill",
		BackgroundColor3 = SHIELD_COLOR,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(0, 0, 0.42, 0),
		Visible = false,
	})
	UIFactory.corner(6).Parent = shieldFill
	shieldFill.Parent = bg

	local label = UIFactory.textLabel({
		Name = "BarLabel",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.AccentText,
		TextStrokeTransparency = 0.5,
		TextSize = scaled(14),
		Text = "",
	})
	label.Parent = bg

	return bg, hpFill, shieldFill, label
end

-- ==================== show / hide ====================

local function getMenuGui(): ScreenGui?
	if MenuShell and MenuShell.getScreenGui then
		return MenuShell.getScreenGui()
	end
	return nil
end

local function showCombat()
	if screenGui then
		screenGui.Enabled = true
	end
	local menu = getMenuGui()
	if menu then
		menu.Enabled = false
	end
	if endOverlay then
		endOverlay.Visible = false
	end
	if traitOverlay then
		traitOverlay.Visible = false
	end
end

local function hideCombat()
	if screenGui then
		screenGui.Enabled = false
	end
	local menu = getMenuGui()
	if menu then
		menu.Enabled = true
	end
end

-- ==================== enemy row (R-C3) ====================

local function selectedIndex(state: CombatState): number?
	for i, enemy in state.enemies do
		if enemy.uid == selectedUid then
			return i
		end
	end
	return nil
end

-- Ensure a living enemy is selected; default to the first when the previous
-- target died or none is chosen yet.
local function ensureSelection(state: CombatState)
	if selectedUid and selectedIndex(state) then
		return
	end
	selectedUid = if #state.enemies > 0 then state.enemies[1].uid else nil
end

local function onEnemyClicked(uid: string, state: CombatState)
	selectedUid = uid
	CombatUI.render(state)
end

local function buildEnemyCard(enemy: Types.CombatEnemy, state: CombatState): TextButton
	local Theme = UIFactory.Theme
	local def = Enemies.get(enemy.archetype)
	local visual = AssetResolver.resolve(def and def.icon or "enemy/?")
	local selected = enemy.uid == selectedUid

	local card = UIFactory.textButton({
		Name = "Enemy_" .. enemy.uid,
		BackgroundColor3 = selected and Theme.PanelAlt or Theme.Panel,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(scaled(138), scaled(190)),
		Text = "",
	})
	UIFactory.corner(12).Parent = card
	local stroke = UIFactory.stroke({
		Color = selected and Theme.Accent or Theme.Stroke,
		Thickness = selected and 3 or 1,
	})
	stroke.Parent = card
	UIFactory.padding(scaled(8)).Parent = card

	local layout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, scaled(6)),
	})
	layout.Parent = card

	local iconSize = scaled(72)
	local icon = UIFactory.frame({
		Name = "Icon",
		LayoutOrder = 1,
		BackgroundColor3 = visual.color,
		Size = UDim2.fromOffset(iconSize, iconSize),
	})
	UIFactory.corner(10).Parent = icon
	icon.Parent = card
	local glyph = UIFactory.textLabel({
		Size = UDim2.fromScale(1, 1),
		Text = visual.label,
		Font = Theme.FontBold,
		TextColor3 = Theme.AccentText,
		TextSize = scaled(20),
	})
	glyph.Parent = icon

	local name = UIFactory.textLabel({
		Name = "Name",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, scaled(20)),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = scaled(15),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = def and def.name or enemy.archetype,
	})
	name.Parent = card

	local barHolder = UIFactory.frame({
		Name = "BarHolder",
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, scaled(22)),
	})
	barHolder.Parent = card
	local bg, hpFill, shieldFill, label = buildBar(Theme.Negative)
	bg.Parent = barHolder
	updateBar(hpFill, shieldFill, label, enemy.hp, enemy.maxHp, enemy.shield)

	card.Activated:Connect(function()
		onEnemyClicked(enemy.uid, state)
	end)

	return card
end

local function renderEnemies(state: CombatState)
	local row = enemiesRow
	if not row then
		return
	end
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, enemy in state.enemies do
		local card = buildEnemyCard(enemy, state)
		card.Parent = row
	end
end

-- ==================== dice (R-C9..C11) ====================

local function buildDie(die: Types.Die, index: number, interactive: boolean): TextButton
	local Theme = UIFactory.Theme
	local size = scaled(70)
	local button = UIFactory.textButton({
		Name = "Die" .. index,
		BackgroundColor3 = die.locked and Theme.Accent or Theme.PanelAlt,
		AutoButtonColor = interactive,
		Active = interactive,
		Size = UDim2.fromOffset(size, size),
		Font = Theme.FontBold,
		TextColor3 = die.locked and Theme.AccentText or Theme.Text,
		TextSize = scaled(30),
		Text = tostring(die.value),
	})
	UIFactory.corner(10).Parent = button
	UIFactory.stroke({
		Color = die.locked and Theme.Accent or Theme.Stroke,
		Thickness = die.locked and 3 or 1,
	}).Parent = button

	local tag = UIFactory.textLabel({
		Name = "LockTag",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, scaled(14)),
		Font = Theme.FontBold,
		TextColor3 = die.locked and Theme.AccentText or Theme.SubText,
		TextSize = scaled(11),
		Text = die.locked and "LOCKED" or "tap to lock",
	})
	tag.Parent = button

	if interactive then
		button.Activated:Connect(function()
			CombatController.toggleLock(index)
		end)
	end

	return button
end

local function renderDice(state: CombatState)
	local row = diceRow
	if not row then
		return
	end
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local interactive = state.phase == "PlayerTurn"
	for index, die in state.dice do
		local button = buildDie(die, index, interactive)
		button.Parent = row
	end
end

-- ==================== feedback + controls ====================

local function renderFeedback(state: CombatState)
	if not feedbackLabel then
		return
	end
	local values: { number } = {}
	local total = 0
	for _, die in state.dice do
		table.insert(values, die.value)
		total += die.value
	end
	local result = DiceHands.evaluate(values)
	local handName = HAND_NAMES[result.hand] or result.hand
	-- Show the dice sum AND the value after the hand multiplier so the number
	-- matches the damage the player actually deals (e.g. 8 dice x1.5 -> 12).
	-- Flat/%/crit bonuses are resolved server-side and are not included here.
	local afterMult = math.floor(total * result.multiplier + 0.5)
	feedbackLabel.Text = ("%s    x%s    %d → %d"):format(handName, tostring(result.multiplier), total, afterMult)
end

local function renderControls(state: CombatState)
	local Theme = UIFactory.Theme
	local isPlayerTurn = state.phase == "PlayerTurn"

	if rerollButton then
		rerollButton.Text = ("Reroll (%d)"):format(state.rerollsLeft)
		local canReroll = isPlayerTurn and state.rerollsLeft > 0
		rerollButton.Active = canReroll
		rerollButton.AutoButtonColor = canReroll
		rerollButton.BackgroundColor3 = canReroll and Theme.PanelAlt or Theme.Panel
		rerollButton.TextColor3 = canReroll and Theme.Text or Theme.SubText
	end

	if attackButton then
		local canAttack = isPlayerTurn and selectedIndex(state) ~= nil
		attackButton.Active = canAttack
		attackButton.AutoButtonColor = canAttack
		attackButton.BackgroundColor3 = canAttack and Theme.Accent or Theme.Panel
		attackButton.TextColor3 = canAttack and Theme.AccentText or Theme.SubText
	end
end

-- ==================== top bar + player ====================

local function renderTopBar(state: CombatState)
	local chapter = Chapters.get(state.chapterId)
	if topInfoLabel then
		topInfoLabel.Text = ("%s   -   Stage %d / %d"):format(
			chapter and chapter.name or ("Chapter " .. state.chapterId),
			state.stageIndex,
			chapter and #chapter.stages or state.stageIndex
		)
	end
	if phaseLabel then
		phaseLabel.Text = ("Lvl %d   -   %d / %d dice"):format(
			state.perChapter.level,
			state.unlockedDice,
			Balance.Dice.maxDice
		)
	end
end

local function renderPlayer(state: CombatState)
	if playerHpFill and playerShieldFill and playerBarLabel then
		updateBar(playerHpFill, playerShieldFill, playerBarLabel, state.player.hp, state.player.maxHp, state.player.shield)
	end
end

-- ==================== trait draft overlay (R-C23) ====================

local function buildTraitCard(traitId: string): Frame
	local Theme = UIFactory.Theme
	local def = Traits.get(traitId)
	local visual = AssetResolver.resolve(def and def.icon or "trait/?")

	local card = UIFactory.frame({
		Name = "Trait_" .. traitId,
		BackgroundColor3 = Theme.Panel,
		Size = UDim2.fromOffset(scaled(190), scaled(250)),
	})
	UIFactory.corner(14).Parent = card
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = card
	UIFactory.padding(scaled(12)).Parent = card

	local layout = UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, scaled(8)),
	})
	layout.Parent = card

	local iconSize = scaled(56)
	local icon = UIFactory.frame({
		Name = "Icon",
		LayoutOrder = 1,
		BackgroundColor3 = visual.color,
		Size = UDim2.fromOffset(iconSize, iconSize),
	})
	UIFactory.corner(10).Parent = icon
	icon.Parent = card
	local glyph = UIFactory.textLabel({
		Size = UDim2.fromScale(1, 1),
		Text = visual.label,
		Font = Theme.FontBold,
		TextColor3 = Theme.AccentText,
		TextSize = scaled(16),
	})
	glyph.Parent = icon

	local name = UIFactory.textLabel({
		Name = "Name",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, scaled(22)),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = scaled(17),
		Text = def and def.name or traitId,
	})
	name.Parent = card

	local desc = UIFactory.textLabel({
		Name = "Desc",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, scaled(80)),
		Font = Theme.Font,
		TextColor3 = Theme.SubText,
		TextSize = scaled(14),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = def and def.description or "",
	})
	desc.Parent = card

	local choose = UIFactory.textButton({
		Name = "Choose",
		LayoutOrder = 4,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, scaled(40)),
		BackgroundColor3 = Theme.Accent,
		TextSize = scaled(16),
		Text = "Choose",
	})
	UIFactory.corner(10).Parent = choose
	choose.Parent = card
	choose.Activated:Connect(function()
		CombatController.chooseTrait(traitId)
	end)

	return card
end

local function showTraitOverlay(offer: { string })
	local overlay = traitOverlay
	local holder = traitCards
	if not (overlay and holder) then
		return
	end
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, traitId in offer do
		buildTraitCard(traitId).Parent = holder
	end
	overlay.Visible = true
end

-- ==================== end screen (R-C5, R-C20) ====================

local function showEndScreen(info: any)
	active = false
	local overlay = endOverlay
	if not (overlay and endTitle and endSubtitle) then
		return
	end
	local Theme = UIFactory.Theme
	if info.won then
		endTitle.Text = "Victory!"
		endTitle.TextColor3 = Theme.Positive
		local rewards = info.rewards or {}
		local parts: { string } = {}
		if rewards.coins then
			table.insert(parts, ("+%d coins"):format(rewards.coins))
		end
		if rewards.keys then
			table.insert(parts, ("+%d keys"):format(rewards.keys))
		end
		if rewards.globalXp then
			table.insert(parts, ("+%d XP"):format(rewards.globalXp))
		end
		endSubtitle.Text = if #parts > 0 then ("Chapter cleared!   " .. table.concat(parts, "   ")) else "Chapter cleared!"
	else
		endTitle.Text = "Defeat"
		endTitle.TextColor3 = Theme.Negative
		endSubtitle.Text = "You were defeated. Try again from the menu."
	end
	if traitOverlay then
		traitOverlay.Visible = false
	end
	overlay.Visible = true
end

-- ==================== master render ====================

function CombatUI.render(state: CombatState)
	ensureSelection(state)
	renderTopBar(state)
	renderPlayer(state)
	renderEnemies(state)
	renderDice(state)
	renderFeedback(state)
	renderControls(state)

	if state.phase == "TraitPick" then
		local offer = CombatController.getTraitOffer()
		if offer then
			showTraitOverlay(offer)
		end
	elseif traitOverlay then
		traitOverlay.Visible = false
	end
end

-- ==================== build ====================

function CombatUI.init(injected: any)
	deps = injected
	UIFactory = deps.Util.UIFactory
	Responsive = deps.Util.Responsive
	AssetResolver = deps.Util.AssetResolver
	MenuShell = deps.UI.MenuShell
	CombatController = deps.Controllers.CombatController
end

-- Recompute size/position for the fixed regions on viewport/device changes.
local function layoutCombat()
	if not (board and topBar and enemiesArea and feedbackBar and bottomPanel) then
		return
	end
	local topH = scaled(48)
	local feedbackH = scaled(50)
	local playerBarH = scaled(30)
	local diceH = scaled(96)
	local controlsH = scaled(58)
	local gap = scaled(12)
	local bottomH = playerBarH + gap + diceH + gap + controlsH

	topBar.Size = UDim2.new(1, 0, 0, topH)

	bottomPanel.Size = UDim2.new(1, 0, 0, bottomH)

	feedbackBar.Position = UDim2.new(0, 0, 1, -(bottomH + gap))
	feedbackBar.Size = UDim2.new(1, 0, 0, feedbackH)

	enemiesArea.Position = UDim2.new(0, 0, 0, topH + gap)
	enemiesArea.Size = UDim2.new(1, 0, 1, -(topH + gap + feedbackH + gap + bottomH + gap))

	if playerBarBg then
		playerBarBg.Size = UDim2.new(1, 0, 0, playerBarH)
	end
	if diceRow then
		diceRow.Position = UDim2.new(0, 0, 0, playerBarH + gap)
		diceRow.Size = UDim2.new(1, 0, 0, diceH)
	end
	local controlsY = playerBarH + gap + diceH + gap
	if rerollButton then
		rerollButton.Position = UDim2.new(0, 0, 0, controlsY)
		rerollButton.Size = UDim2.new(0.4, -gap / 2, 0, controlsH)
	end
	if attackButton then
		attackButton.Position = UDim2.new(0.4, gap / 2, 0, controlsY)
		attackButton.Size = UDim2.new(0.6, -gap / 2, 0, controlsH)
	end
end

function CombatUI.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local Theme = UIFactory.Theme

	local gui = UIFactory.create("ScreenGui", {
		Name = "CombatUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Enabled = false,
	})
	screenGui = gui

	local root = UIFactory.frame({
		Name = "Root",
		BackgroundColor3 = Theme.Background,
		Size = UDim2.fromScale(1, 1),
	})
	root.Parent = gui

	local boardFrame = UIFactory.frame({
		Name = "Board",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	UIFactory.padding(scaled(14)).Parent = boardFrame
	boardFrame.Parent = root
	board = boardFrame

	-- Top bar: chapter/stage on the left, per-chapter level + dice count right.
	local top = UIFactory.frame({
		Name = "TopBar",
		BackgroundColor3 = Theme.Panel,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, scaled(48)),
	})
	UIFactory.corner(10).Parent = top
	UIFactory.padding(scaled(10)).Parent = top
	top.Parent = boardFrame
	topBar = top

	local info = UIFactory.textLabel({
		Name = "Info",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0.65, 0, 1, 0),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = scaled(18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})
	info.Parent = top
	topInfoLabel = info

	local phase = UIFactory.textLabel({
		Name = "Phase",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.35, 0, 1, 0),
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextSize = scaled(16),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	phase.Parent = top
	phaseLabel = phase

	-- Enemy area (fills the middle); enemies laid out in a centered row.
	local enemies = UIFactory.frame({
		Name = "EnemiesArea",
		BackgroundTransparency = 1,
	})
	enemies.Parent = boardFrame
	enemiesArea = enemies

	local row = UIFactory.frame({
		Name = "EnemiesRow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	})
	row.Parent = enemies
	enemiesRow = row
	UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, scaled(12)),
	}).Parent = row

	-- Feedback bar (current hand + multiplier + dice total).
	local feedback = UIFactory.frame({
		Name = "FeedbackBar",
		BackgroundColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, 0, 0, scaled(50)),
	})
	UIFactory.corner(10).Parent = feedback
	feedback.Parent = boardFrame
	feedbackBar = feedback
	local fbLabel = UIFactory.textLabel({
		Name = "FeedbackLabel",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = scaled(20),
		Text = "",
	})
	fbLabel.Parent = feedback
	feedbackLabel = fbLabel

	-- Bottom panel: player bar, dice row, and controls.
	local bottom = UIFactory.frame({
		Name = "BottomPanel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, scaled(200)),
	})
	bottom.Parent = boardFrame
	bottomPanel = bottom

	local pBg, pHp, pShield, pLabel = buildBar(Theme.Positive)
	pBg.Name = "PlayerBar"
	pBg.Size = UDim2.new(1, 0, 0, scaled(30))
	pBg.Parent = bottom
	playerBarBg = pBg
	playerHpFill = pHp
	playerShieldFill = pShield
	playerBarLabel = pLabel

	local dice = UIFactory.frame({
		Name = "DiceRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, scaled(96)),
	})
	dice.Parent = bottom
	diceRow = dice
	UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, scaled(10)),
	}).Parent = dice

	local reroll = UIFactory.textButton({
		Name = "RerollButton",
		BackgroundColor3 = Theme.PanelAlt,
		Size = UDim2.new(0.4, 0, 0, scaled(58)),
		TextSize = scaled(20),
		Text = "Reroll (0)",
	})
	UIFactory.corner(12).Parent = reroll
	reroll.Parent = bottom
	rerollButton = reroll
	reroll.Activated:Connect(function()
		local st = CombatController.get()
		if st and st.phase == "PlayerTurn" and st.rerollsLeft > 0 then
			CombatController.reroll()
		end
	end)

	local attack = UIFactory.textButton({
		Name = "AttackButton",
		BackgroundColor3 = Theme.Accent,
		Size = UDim2.new(0.6, 0, 0, scaled(58)),
		TextSize = scaled(24),
		Text = "Attack",
	})
	UIFactory.corner(12).Parent = attack
	attack.Parent = bottom
	attackButton = attack
	attack.Activated:Connect(function()
		local st = CombatController.get()
		if not (st and st.phase == "PlayerTurn") then
			return
		end
		local idx = selectedIndex(st)
		if idx then
			CombatController.attack(idx)
		end
	end)

	-- ===== trait draft overlay (R-C23) =====
	local tOverlay = UIFactory.frame({
		Name = "TraitOverlay",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.4,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 50,
	})
	tOverlay.Parent = root
	traitOverlay = tOverlay
	local tHeader = UIFactory.textLabel({
		Name = "Header",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		Size = UDim2.new(0.9, 0, 0, scaled(40)),
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextSize = scaled(26),
		Text = "5 Dice Unlocked - Choose a Trait",
		ZIndex = 51,
	})
	tHeader.Parent = tOverlay
	local tCards = UIFactory.frame({
		Name = "TraitCards",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.95, 0, 0, scaled(250)),
		ZIndex = 51,
	})
	tCards.Parent = tOverlay
	traitCards = tCards
	UIFactory.listLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, scaled(16)),
	}).Parent = tCards

	-- ===== victory / defeat overlay (R-C5, R-C20) =====
	local eOverlay = UIFactory.frame({
		Name = "EndOverlay",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 60,
	})
	eOverlay.Parent = root
	endOverlay = eOverlay
	local eCard = UIFactory.frame({
		Name = "Card",
		BackgroundColor3 = Theme.Background,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0, scaled(240)),
		ZIndex = 61,
	})
	UIFactory.corner(16).Parent = eCard
	UIFactory.stroke({ Color = Theme.Stroke }).Parent = eCard
	UIFactory.padding(scaled(20)).Parent = eCard
	UIFactory.create("UISizeConstraint", { MaxSize = Vector2.new(scaled(460), math.huge) }).Parent = eCard
	eCard.Parent = eOverlay

	local eTitle = UIFactory.textLabel({
		Name = "Title",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, scaled(56)),
		Font = Theme.FontBold,
		TextColor3 = Theme.Positive,
		TextSize = scaled(40),
		Text = "Victory!",
		ZIndex = 61,
	})
	eTitle.Parent = eCard
	endTitle = eTitle

	local eSub = UIFactory.textLabel({
		Name = "Subtitle",
		Position = UDim2.new(0, 0, 0, scaled(64)),
		Size = UDim2.new(1, 0, 0, scaled(80)),
		Font = Theme.Font,
		TextColor3 = Theme.SubText,
		TextSize = scaled(18),
		TextWrapped = true,
		Text = "",
		ZIndex = 61,
	})
	eSub.Parent = eCard
	endSubtitle = eSub

	local eButton = UIFactory.textButton({
		Name = "ReturnButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, scaled(50)),
		BackgroundColor3 = Theme.Accent,
		TextSize = scaled(20),
		Text = "Return to Menu",
		ZIndex = 61,
	})
	UIFactory.corner(12).Parent = eButton
	eButton.Parent = eCard
	eButton.Activated:Connect(function()
		if endOverlay then
			endOverlay.Visible = false
		end
		hideCombat()
	end)

	gui.Parent = playerGui

	layoutCombat()
	Responsive.onChanged(layoutCombat)

	-- Drive the view from the authoritative mirror.
	CombatController.onChanged(function(state: CombatState)
		if not active then
			active = true
			selectedUid = nil
			showCombat()
		end
		CombatUI.render(state)
	end)

	CombatController.onTraitOffer(function(offer: { string })
		if active then
			showTraitOverlay(offer)
		end
	end)

	CombatController.onEnded(function(info: any)
		showEndScreen(info)
	end)
end

return CombatUI
