--!strict
-- CoinsUI: the HUD coin counter (WeaponHud/Coins/Panel: CoinIcon, Amount).
-- Wires the hand-built HUD; the only things it makes are clones of
-- WeaponHud/Templates/FlyingCoin.
--
--   * The counter shows the player's "Coins" attribute (CoinService), but it
--     counts up to a new total over the Coins frame's CountSeconds instead of
--     jumping, so a kill reads as coins being added.
--   * A kill's coins (LootController) fly in from where they lay: each
--     collect() call sends one FlyingCoin along a curve to the icon
--     (Util.HudFly, FlySeconds), and the icon bumps (BumpScale) as each lands. While a
--     spill is on its way the counter waits, and starts counting when its
--     first coin lands.
--   * shown() / onShown() give what the counter shows right now, so other HUD
--     pieces (the quest tracker) move in step with it instead of jumping
--     ahead to the balance.
--   * Each landing coin plays Util.UiSound's "CoinLand" (its pitch climbs through a spill).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local CoinsUI = {}

local HudFly: any = nil
local Format: any = nil
local FontDrop: any = nil
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local hud: ScreenGui? = nil
local coinsFrame: Instance? = nil
local amountLabel: TextLabel? = nil
local icon: GuiObject? = nil

local displayed = 0
local countValue: NumberValue? = nil
local countTween: Tween? = nil
local pending = 0 -- spills whose coins haven't reached the counter yet
local shownEvent = Instance.new("BindableEvent")

local function attribute(name: string, fallback: number): number
	local value = coinsFrame and coinsFrame:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function balance(): number
	local value = player:GetAttribute("Coins")
	return if type(value) == "number" then value else 0
end

local function show(value: number)
	displayed = value
	if amountLabel then
		amountLabel.Text = Format.coins(value)
	end
	shownEvent:Fire(value)
end

-- The coin count the counter shows right now (it trails the balance while a
-- spill flies in and counts up).
function CoinsUI.shown(): number
	return math.floor(displayed + 0.5)
end

function CoinsUI.onShown(callback: (number) -> ()): RBXScriptConnection
	return shownEvent.Event:Connect(callback)
end

-- Count the label from what it shows now to `target`.
local function countTo(target: number)
	if countTween then
		countTween:Cancel()
	end
	if not countValue then
		local value = Instance.new("NumberValue")
		value.Changed:Connect(show)
		countValue = value
	end
	local value = countValue :: NumberValue
	value.Value = displayed
	if target == displayed then
		return
	end
	countTween = TweenService:Create(value, TweenInfo.new(attribute("CountSeconds", 1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	;(countTween :: Tween):Play()
end

-- A spill is about to fly in: hold the counter until it lands.
function CoinsUI.beginSpill()
	pending += 1
end

-- The spill is done (or had nothing to show): count to the balance.
function CoinsUI.endSpill()
	pending = math.max(0, pending - 1)
	countTo(balance())
end

-- Fly one coin from `from` (a viewport point, in pixels) to the counter's icon;
-- `landed` runs when it arrives.
function CoinsUI.collect(from: Vector2, landed: (() -> ())?)
	local templates = hud and hud:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("FlyingCoin")
	if not (hud and icon and template and template:IsA("GuiObject")) then
		if landed then
			landed()
		end
		return
	end
	HudFly.fly(hud :: ScreenGui, template, from, icon :: GuiObject, attribute("FlySeconds", 0.55), function()
		HudFly.bump(icon, attribute("BumpScale", 1.25))
		UiSound.play("CoinLand")
		if landed then
			landed()
		end
	end)
end

function CoinsUI.flyStagger(): number
	return attribute("FlyStagger", 0.08)
end

function CoinsUI.init(injected: any)
	HudFly = injected.Util.HudFly
	Format = injected.Util.Format
	FontDrop = injected.Util.FontDrop
end

function CoinsUI.start()
	task.spawn(function()
		local found = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		if not (found and found:IsA("ScreenGui")) then
			warn("[CoinsUI] no WeaponHud")
			return
		end
		hud = found
		-- the counter stacks in WeaponHud/TopLeft under the player card
		coinsFrame = found:FindFirstChild("Coins", true)
		-- the count is Luckiest Guy on the card-style coin bar (option C, 2026-10-21)
		if coinsFrame and FontDrop then
			FontDrop.watch(coinsFrame)
		end
		local amount = coinsFrame and coinsFrame:FindFirstChild("Amount", true)
		amountLabel = if amount and amount:IsA("TextLabel") then amount else nil
		local coinIcon = coinsFrame and coinsFrame:FindFirstChild("CoinIcon", true)
		icon = if coinIcon and coinIcon:IsA("GuiObject") then coinIcon else nil
		show(balance())
		player:GetAttributeChangedSignal("Coins"):Connect(function()
			-- coins on their way count up when they land; anything else counts
			-- after a beat (in case its spill is announced a moment later)
			task.delay(0.2, function()
				if pending == 0 then
					countTo(balance())
				end
			end)
		end)
	end)
end

return CoinsUI
