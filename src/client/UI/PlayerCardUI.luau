--!strict
-- PlayerCardUI: wires the hand-built player card, StarterGui/WeaponHud/TopLeft/PlayerCard
-- (found with a deep FindFirstChild, so it can move inside the HUD's layouts).
--
-- Live today:
--   * PlayerName: the player's display name,
--   * Avatar/AvatarImage: the player's Roblox headshot (the striped circle shows
--     until it loads, or if it can't),
--   * Health: Fill width and the Amount text, from the character's Humanoid.
--     The fill colour comes from the bar's HealthyColor / LowColor / LowFraction
--     attributes.
--   * Stamina: removed (user, 2026-10-11: sprinting is unlimited). The bar was
--     deleted; Health and XP sit in Panel/Info's UIListLayout, which spaces them.
--   * Every number reads with commas (Util.Format), like the shop.
--   * XP bar ("EXP" Label, Amount "x / y") and the LevelBadge: from the
--     player's "ExpTotal" attribute (ExpService) through Config/Leveling. Like
--     the coin counter it counts up over the XP bar's CountSeconds, rolling
--     over into the next level as it passes one.
--   * PlayerCardUI.Exp is the EXP stars' landing spot for LootController
--     (beginSpill / collect / endSpill, the same shape as CoinsUI): each star
--     flies to the XP bar (FlyingStar template, FlySeconds) and bumps it
--     (BumpScale); the count starts when the first one lands.
--   * PlayerCardUI.Exp.shownLevel() / onShown() give the level the badge shows
--     right now, for the quest tracker to follow.
--   * A level up (2026-10-22, the user: like the BONK, not a banner at the top of the
--     screen): when the badge reaches a level the server raised after the data loaded,
--     a small LEVEL UP! pops over the player's head (Util.BonkPop.levelUp) and
--     Util.UiSound plays "LevelUp". Joining counts up from 0 to the saved
--     level quietly. A count that passes two levels raises the number in the same pop
--     (within LEVEL_MERGE seconds). Each landing star plays "ExpLand".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Leveling = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Leveling"))
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local PlayerCardUI = {}

local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local card: Instance? = nil
local hud: ScreenGui? = nil
local HudFly: any = nil
local Format: any = nil
local BonkPop: any = nil

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function find(name: string, className: string): any
	local found = card and card:FindFirstChild(name, true)
	return if found and found:IsA(className) then found else nil
end

local function showHealth(humanoid: Humanoid)
	local bar = find("Health", "GuiObject")
	if not bar then
		return
	end
	local ratio = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
	local fill = bar:FindFirstChild("Fill", true)
	if fill and fill:IsA("GuiObject") then
		fill.Size = UDim2.fromScale(ratio, fill.Size.Y.Scale)
		local low = ratio <= attribute(bar, "LowFraction", 0.3)
		fill.BackgroundColor3 = attribute(bar, if low then "LowColor" else "HealthyColor", fill.BackgroundColor3)
	end
	local amount = bar:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		amount.Text = Format.ratio(math.ceil(humanoid.Health), humanoid.MaxHealth)
	end
end

-- ==================== EXP ====================

local expShown = 0 -- the total EXP the bar shows right now
local expValue: NumberValue? = nil
local expTween: Tween? = nil
local expPending = 0 -- star spills still on their way
local shownLevel = Leveling.START
local levelEvent = Instance.new("BindableEvent")
local LEVEL_MERGE = 0.9 -- seconds a level-up pop takes further levels in
local earnedLevel = 0 -- the highest Level the server published after DataLoaded
local poppedLevel = 0
local popAt = -math.huge
local raisePop: ((number) -> ())? = nil

local function expTotal(): number
	local value = player:GetAttribute("ExpTotal")
	return if type(value) == "number" then value else 0
end

local function xpNumber(name: string, fallback: number): number
	local bar = find("XP", "GuiObject")
	local value = bar and bar:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- The level badge is square, the number centred in it, and widens only once the number
-- no longer fits (2026-10-21, the user). The number's width at the size TextScaled gives
-- it is measured; the badge grows (to the left: it's anchored on its right edge, away from
-- the bars) just enough for the label, `Slack` x that width wide, to hold it. The badge's
-- `MinAspect` (1, square) and `Slack` (1.12) attributes set it.
-- FredokaOne's digits and comma, in em (measured 2026-10-23 in a browser from the Google
-- Fonts copy): advance width, the ink's centre of mass from the glyph's left, its ink area.
local GLYPHS: { [string]: { adv: number, mass: number, area: number } } = {
	["0"] = { adv = 0.608, mass = 0.3014, area = 0.2778 },
	["1"] = { adv = 0.407, mass = 0.2445, area = 0.1575 },
	["2"] = { adv = 0.609, mass = 0.3039, area = 0.2873 },
	["3"] = { adv = 0.608, mass = 0.3254, area = 0.2665 },
	["4"] = { adv = 0.592, mass = 0.3218, area = 0.2467 },
	["5"] = { adv = 0.530, mass = 0.2563, area = 0.2578 },
	["6"] = { adv = 0.560, mass = 0.2737, area = 0.2544 },
	["7"] = { adv = 0.561, mass = 0.2840, area = 0.1968 },
	["8"] = { adv = 0.582, mass = 0.2884, area = 0.2921 },
	["9"] = { adv = 0.560, mass = 0.2812, area = 0.2548 },
	[","] = { adv = 0.238, mass = 0.1138, area = 0.0475 },
}

local function fitBadge(badge: TextLabel)
	local holder = badge.Parent
	local ratio = holder and holder:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not (holder and holder:IsA("GuiObject") and ratio) or badge.AbsoluteSize.Y <= 0 or holder.AbsoluteSize.Y <= 0 then
		return
	end
	local function get(name: string, fallback: number): number
		local v = holder:GetAttribute(name)
		return if type(v) == "number" then v else fallback
	end
	-- the drawn text's shape, scaled to the full height TextScaled gives it when nothing
	-- squeezes it (TextBounds keeps its shape even while the width squeezes it)
	local bounds = badge.TextBounds
	if bounds.Y <= 0 then
		return
	end
	local width = bounds.X / bounds.Y * badge.AbsoluteSize.Y
	local share = math.max(0.1, badge.Size.X.Scale)
	local need = width * get("Slack", 1.12) / share / holder.AbsoluteSize.Y
	local aspect = math.max(get("MinAspect", 1), need)
	if math.abs(ratio.AspectRatio - aspect) > 0.005 then
		ratio.AspectRatio = aspect
	end
	-- Centred by its weight, not its box (2026-10-23, the user: "centered at all times"):
	-- Roblox centres the digits' advance box, but a "1" is a stem with its flag on the
	-- left, so it read as pushed right. Each digit's visual centre (its ink's centre of
	-- mass) is measured in FredokaOne (GLYPHS, in em); the label moves by the string's
	-- mass centre minus its box centre.
	local text = badge.Text
	local total, massX, mass = 0, 0, 0
	for i = 1, #text do
		local glyph = GLYPHS[text:sub(i, i)]
		if glyph then
			massX += (total + glyph.mass) * glyph.area
			mass += glyph.area
			total += glyph.adv
		end
	end
	local shift = 0
	if mass > 0 and total > 0 and holder.AbsoluteSize.X > 0 then
		local pxPerEm = bounds.X / total
		shift = -(massX / mass - total / 2) * pxPerEm / holder.AbsoluteSize.X
	end
	-- Then onto whole pixels (2026-10-23, measured in a playtest): Roblox draws text that
	-- starts part-way into a pixel from the next whole pixel, which put every number about
	-- 1 px right and 1.2 px low at the HUD's size (dead centre at 5x). The label's top-left
	-- corner goes down to the whole pixel at or before where centring puts it; measured
	-- after: "25" within 0.3 px both ways. It's worked out from the badge's own position
	-- (the label's moving doesn't move the badge, so this never feeds itself).
	local W, H = holder.AbsoluteSize.X, holder.AbsoluteSize.Y
	local lw, lh = badge.AbsoluteSize.X, badge.AbsoluteSize.Y
	local left = holder.AbsolutePosition.X + (0.5 + shift) * W - badge.AnchorPoint.X * lw
	local top = holder.AbsolutePosition.Y + 0.5 * H - badge.AnchorPoint.Y * lh
	local x = 0.5 + shift + (math.floor(left + 1e-3) - left) / W
	local y = 0.5 + (math.floor(top + 1e-3) - top) / H
	if math.abs(badge.Position.X.Scale - x) > 1e-5 or math.abs(badge.Position.Y.Scale - y) > 1e-5 then
		badge.Position = UDim2.fromScale(x, y)
	end
end

-- The LEVEL UP! pop, the badge bump and the sound, for `level`.
local function celebrate(level: number)
	poppedLevel = level
	local now = os.clock()
	if raisePop and now - popAt < LEVEL_MERGE then
		(raisePop :: (number) -> ())(level)
		return
	end
	popAt = now
	UiSound.play("LevelUp")
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if BonkPop and head and head:IsA("BasePart") then
		raisePop = BonkPop.levelUp(head, level)
	else
		raisePop = nil
	end
end

local function showExp(total: number)
	expShown = total
	local level, into, need = Leveling.fromTotal(math.floor(total + 0.5))
	local bar = find("XP", "GuiObject")
	if bar then
		local fill = bar:FindFirstChild("Fill", true)
		if fill and fill:IsA("GuiObject") then
			fill.Size = UDim2.fromScale(math.clamp(into / need, 0, 1), fill.Size.Y.Scale)
		end
		local amount = bar:FindFirstChild("Amount", true)
		if amount and amount:IsA("TextLabel") then
			amount.Text = Format.ratio(into, need)
		end
	end
	local badge = find("Level", "TextLabel")
	if badge then
		badge.Text = Format.commas(level) -- fitBadge follows its TextBounds
	end
	if level ~= shownLevel then
		local rose = level > shownLevel
		shownLevel = level
		levelEvent:Fire(level)
		if rose and level <= earnedLevel and level > poppedLevel then
			celebrate(level)
		end
	end
end

-- Count the bar from what it shows now up to `target` total EXP.
local function countExp(target: number)
	if expTween then
		expTween:Cancel()
	end
	if not expValue then
		local value = Instance.new("NumberValue")
		value.Changed:Connect(showExp)
		expValue = value
	end
	local value = expValue :: NumberValue
	value.Value = expShown
	if target == expShown then
		return
	end
	expTween = TweenService:Create(value, TweenInfo.new(xpNumber("CountSeconds", 1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	;(expTween :: Tween):Play()
end

-- Where LootController sends EXP stars.
PlayerCardUI.Exp = {}

function PlayerCardUI.Exp.beginSpill()
	expPending += 1
end

function PlayerCardUI.Exp.endSpill()
	expPending = math.max(0, expPending - 1)
	countExp(expTotal())
end

function PlayerCardUI.Exp.collect(from: Vector2, landed: (() -> ())?)
	local bar = find("XP", "GuiObject")
	local templates = hud and hud:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("FlyingStar")
	if not (hud and bar and template and template:IsA("GuiObject")) then
		if landed then
			landed()
		end
		return
	end
	HudFly.fly(hud :: ScreenGui, template, from, bar, xpNumber("FlySeconds", 0.55), function()
		HudFly.bump(bar, xpNumber("BumpScale", 1.08))
		UiSound.play("ExpLand")
		if landed then
			landed()
		end
	end)
end

-- The level the badge shows right now (it trails the real level while stars
-- fly in and the bar counts up).
function PlayerCardUI.Exp.shownLevel(): number
	return shownLevel
end

function PlayerCardUI.Exp.onShown(callback: (number) -> ()): RBXScriptConnection
	return levelEvent.Event:Connect(callback)
end

function PlayerCardUI.Exp.flyStagger(): number
	return xpNumber("FlyStagger", 0.08)
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	showHealth(humanoid)
	humanoid.HealthChanged:Connect(function()
		showHealth(humanoid)
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		showHealth(humanoid)
	end)
end

local function showIdentity()
	local name = find("PlayerName", "TextLabel")
	if name then
		name.Text = player.DisplayName
	end
	local image = find("AvatarImage", "ImageLabel")
	if image and player.UserId > 0 then
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and content then
			image.Image = content
		end
	end
end

-- Keep a level badge's number fitted and centred (the HUD's, and the copies on the
-- profile and inspect cards): the badge widens for big numbers and the number is
-- centred by its weight (fitBadge).
function PlayerCardUI.watchBadge(badge: TextLabel)
	for _, property in { "AbsoluteSize", "TextBounds", "Text" } do
		badge:GetPropertyChangedSignal(property):Connect(function()
			fitBadge(badge)
		end)
	end
	-- the whole-pixel snap follows the badge wherever it moves (a panel popping open)
	local holder = badge.Parent
	if holder and holder:IsA("GuiObject") then
		holder:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			fitBadge(badge)
		end)
	end
	-- a badge whose number never changes (the join's level can equal the template's
	-- "1") gets no change event: fit once
	task.defer(fitBadge, badge)
end

function PlayerCardUI.init(injected: any)
	HudFly = injected.Util.HudFly
	Format = injected.Util.Format
	BonkPop = injected.Util.BonkPop
end

function PlayerCardUI.start()
	-- StarterGui's copy can land in PlayerGui after this starts.
	task.spawn(function()
		local gui = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		-- the card stacks in WeaponHud/TopLeft with the coin counter
		local found = gui and gui:FindFirstChild("PlayerCard", true)
		if not found then
			warn("[PlayerCardUI] no WeaponHud/PlayerCard in StarterGui")
			return
		end
		card = found
		hud = gui :: any
		showIdentity()
		local badge = find("Level", "TextLabel")
		if badge then
			-- FredokaOne draws centred in its box, so the number needs no drop (measured
			-- within 1 px of the badge's middle, 2026-10-21); fitBadge centres it by weight
			PlayerCardUI.watchBadge(badge)
		end
		showExp(expTotal())
		player:GetAttributeChangedSignal("Level"):Connect(function()
			local level = player:GetAttribute("Level")
			if player:GetAttribute("DataLoaded") == true and type(level) == "number" then
				earnedLevel = math.max(earnedLevel, level)
			end
		end)
		player:GetAttributeChangedSignal("ExpTotal"):Connect(function()
			-- stars on their way count up when they land; anything else counts
			-- after a beat (in case its spill is announced a moment later)
			task.delay(0.2, function()
				if expPending == 0 then
					countExp(expTotal())
				end
			end)
		end)
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then
			watchCharacter(player.Character)
		end
	end)
end

return PlayerCardUI
