--!strict
-- QuestTrackerUI: the quest tracker on the right of the screen (Tracker C
-- "Target badge", picked on the Claude Design canvas), in the hand-built
-- StarterGui/QuestTracker/Tracker.
--
-- It follows one questline at a time: Quests.tracked picks the line of the world
-- the player stands in, else any line with a step under way (2026-10-11, with
-- Ranger Rowan's line). It shows while that line's step is Active or Ready
-- (QuestService's per-line Step / State / Progress attributes, Quests.attr):
--   Tab/Label   "Dale's Farm · 3/10", or "Complete! · 3/10" once done
--   Badge       Portrait (the enemy's Index portrait, a coin, a level badge, or
--               Dale once done) inside Ring: a Track ring plus the Right / Left
--               halves of the fill, whose hard-edged UIGradients are rotated to
--               show the progress (right half 0-50%, left half 50-100%)
--   Verb        the words before {braces} in the step's `track` ("DEFEAT")
--   Target      the part in braces, in red ("Angry Chickens")
--   Count       "3 / 5", or the line's returnNote once done
--               A gather / bring step's tool phase (Quests.toolNeeded, 2026-10-21)
--               shows "BUY A Wooden Axe" / "UPGRADE TO A Stone Axe", the tool's
--               icon and "at the Weaponsmith" until the tool is owned
--   Chips       a "bring" step with several materials (2026-10-19, option A on the
--               Quest Tracker Materials canvas): instead of Count, one clone of
--               QuestTracker/Templates/MaterialChip per item (Icon, Count "5/8" in
--               its Format), coloured from its ShortFill / ShortText / DoneFill /
--               DoneText attributes; the badge shows the first item still short
--   Reward      the gold tab under the card: Caption, Coins / Exp (Icon, Amount) and
--               Item (Icon: the quest item or weapon), what this step pays
--   Guide       turns the guide arrow on / off (GuideController); shown only
--               when there is somewhere to point. While held down it sits
--               pressed into its lip (GuideLip) and darkens by PressDarken,
--               and only flips on release. IconShadow is the icon's shadow. Its
--               Icon shows the drawn map pin from IconOn / IconOff (option C)
--
-- Coin and level progress follow the HUD, not the server: the server adds
-- coins and EXP the moment an enemy dies, but the counters wait for the coins
-- and stars to fly in. So "earn" / "give" steps read CoinsUI.shown() and
-- "level" steps PlayerCardUI.Exp.shownLevel(), and a step only looks done once
-- the counter has caught up. The state as shown ("Active" until the counter
-- catches up, then "Ready") is published on the local player as
-- "QuestShownState", with the line's id as "QuestShownLine" (both client-only),
-- which GuideController follows too.
--
-- The three quest attributes arrive one at a time, so a refresh is deferred to
-- read them together. A step only latches as done (caughtUp) once the server
-- also says Ready, and the latches clear whenever the step changes or the
-- state leaves Active / Ready (every new step passes through Offer): a new step
-- read with the previous step's progress once showed quests 3, 4, 7, 8 and 10
-- as done straight after accepting them.
-- Colours for each state are attributes on Tracker and on Guide.
-- QuestController turns the whole ScreenGui off during a conversation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Enemies = require(Config:WaitForChild("Enemies"))
local Materials = require(Config:WaitForChild("Materials"))
local Quests = require(Config:WaitForChild("Quests"))
local Weapons = require(Config:WaitForChild("Weapons"))

local Format = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Format"))

local QuestTrackerUI = {}

local player = Players.LocalPlayer

local deps: any = nil
local tracker: Frame? = nil
local guidePressed = false
-- steps whose shown progress has reached the goal, so a later count-up can't
-- make a finished step look unfinished again
local caughtUp: { [number]: boolean } = {}
local shownProgress = 0 -- the ring's current fraction, tweened toward the real one
local ringTween: Tween? = nil
local ringValue = Instance.new("NumberValue")

local function attr(name: string): any
	return tracker and tracker:GetAttribute(name)
end

local function colour(name: string, fallback: Color3): Color3
	local value = attr(name)
	return if typeof(value) == "Color3" then value else fallback
end

-- "Defeat the {Scarecrow King}" -> "DEFEAT THE", "Scarecrow King"
local function split(line: string): (string, string)
	local before, inner = line:match("^(.-)%s*{(.-)}")
	if not before then
		return "", line
	end
	return before:upper(), inner
end

-- Show `fraction` (0..1) of the ring: the right half fills 0-50%, the left half
-- 50-100%, each by rotating its hard-edged gradient.
local function setRing(fraction: number)
	local frame = tracker
	local ring = frame and frame:FindFirstChild("Ring", true)
	if not ring then
		return
	end
	local right = ring:FindFirstChild("Right")
	local left = ring:FindFirstChild("Left")
	local rightGradient = right and right:FindFirstChildWhichIsA("UIGradient", true)
	local leftGradient = left and left:FindFirstChildWhichIsA("UIGradient", true)
	if rightGradient then
		rightGradient.Rotation = math.clamp(fraction, 0, 0.5) * 360
	end
	if leftGradient then
		leftGradient.Rotation = 180 + math.clamp(fraction - 0.5, 0, 0.5) * 360
	end
end

local function iconFor(line: Quests.Line, step: Quests.Step, ready: boolean): string
	if ready then
		return line.npc.portrait
	elseif step.kind == "kill" then
		local def = Enemies.get(step.target or "")
		return if def and def.portrait then def.portrait else ""
	elseif step.kind == "level" then
		return attr("LevelIcon") or ""
	elseif Quests.material(step) then
		local id = Quests.material(step)
		if step.kind == "bring" then
			-- the first item still short
			local held = Materials.counts(player)
			for _, item in step.items or {} do
				if (held[item.id] or 0) < item.count then
					id = item.id
					break
				end
			end
		end
		local def = Materials.get(id)
		return def and def.icon or ""
	end
	return attr("CoinIcon") or ""
end

local function refreshGuide()
	local frame = tracker
	local button = frame and frame:FindFirstChild("Guide")
	if not (button and button:IsA("GuiButton")) then
		return
	end
	local Guide = deps.Controllers.GuideController
	local shown = Guide.guidable()
	button.Visible = shown
	local lip = frame:FindFirstChild("GuideLip")
	if lip and lip:IsA("GuiObject") then
		lip.Visible = shown
	end
	local on = Guide.isEnabled()
	local function pick(name: string, fallback: Color3): Color3
		local value = button:GetAttribute(name)
		return if typeof(value) == "Color3" then value else fallback
	end
	local darken = button:GetAttribute("PressDarken")
	local shade = if guidePressed then (if type(darken) == "number" then darken else 0.18) else 0
	button.BackgroundColor3 = pick(if on then "OnColor" else "OffColor", Color3.new(1, 1, 1)):Lerp(Color3.new(0, 0, 0), shade)
	local icon = button:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		-- A drawn icon per state (IconOn / IconOff, the map pin of option C, 2026-10-21)
		-- keeps its own colours; a plain one is tinted by OnIconColor / OffIconColor.
		local image = button:GetAttribute(if on then "IconOn" else "IconOff")
		if type(image) == "string" and image ~= "" then
			icon.Image = image
			icon.ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.new(0, 0, 0), shade)
		else
			icon.ImageColor3 = pick(if on then "OnIconColor" else "OffIconColor", Color3.new(1, 1, 1)):Lerp(Color3.new(0, 0, 0), shade)
		end
	end
	local shadow = button:FindFirstChild("IconShadow")
	if shadow and shadow:IsA("ImageLabel") then
		shadow.ImageColor3 = pick(if on then "OnShadowColor" else "OffShadowColor", Color3.new(0, 0, 0))
	end
end

-- Progress as the HUD shows it (see the header).
local function displayedProgress(stepIndex: number, step: Quests.Step, state: string, progress: number): number
	local goal = Quests.goal(step)
	if caughtUp[stepIndex] then
		return goal
	end
	local shown = progress
	if step.kind == "earn" then
		local coins = player:GetAttribute("Coins")
		local behind = math.max(0, (if type(coins) == "number" then coins else 0) - deps.UI.CoinsUI.shown())
		shown = progress - behind
	elseif step.kind == "give" then
		shown = deps.UI.CoinsUI.shown()
	elseif step.kind == "level" then
		shown = deps.UI.PlayerCardUI.Exp.shownLevel()
	end
	shown = math.clamp(shown, 0, goal)
	-- Latch only what the server agrees is done. "give" and "bring" can fall back if
	-- coins or materials are spent, so they never latch.
	if shown >= goal and state == "Ready" and step.kind ~= "give" and step.kind ~= "bring" then
		caughtUp[stepIndex] = true
	end
	return shown
end

local lastKey: string? = nil

-- The gold Reward tab under the card (option B on the Quest Guide canvas, 2026-10-21):
-- what handing this step in pays. Coins / Exp show their amounts; Item shows the quest
-- item's or weapon's icon. Pieces the step doesn't give are hidden.
local function renderReward(frame: Frame, step: Quests.Step)
	local tab = frame:FindFirstChild("Reward")
	if not (tab and tab:IsA("GuiObject")) then
		return
	end
	local reward = step.reward or {}
	local function show(name: string, amount: number?)
		local piece = tab:FindFirstChild(name)
		if not (piece and piece:IsA("GuiObject")) then
			return
		end
		piece.Visible = amount ~= nil and amount > 0
		local label = piece:FindFirstChild("Amount")
		if label and label:IsA("TextLabel") and amount then
			label.Text = if name == "Coins" then Format.coins(amount) else Format.commas(amount)
		end
	end
	show("Coins", reward.coins)
	show("Exp", reward.exp)
	local icon: string? = nil
	if reward.weapon then
		local def = Weapons.get(reward.weapon)
		icon = def and def.icon
	elseif reward.item then
		local def = Materials.get(reward.item)
		icon = def and def.icon
	end
	local item = tab:FindFirstChild("Item")
	if item and item:IsA("GuiObject") then
		item.Visible = icon ~= nil
		local image = item:FindFirstChild("Icon")
		if image and image:IsA("ImageLabel") then
			image.Image = icon or ""
		end
	end
	tab.Visible = (reward.coins or 0) > 0 or (reward.exp or 0) > 0 or icon ~= nil
end

-- One chip per material of a "bring" step: its icon and "held/needed", green once met.
local function renderChips(chips: Instance, items: { { id: string, count: number } })
	local gui = chips:FindFirstAncestorWhichIsA("ScreenGui")
	local templates = gui and gui:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("MaterialChip")
	for _, child in chips:GetChildren() do
		if child:IsA("GuiObject") then
			local keep = false
			for _, item in items do
				if child.Name == item.id then
					keep = true
				end
			end
			if not keep then
				child:Destroy()
			end
		end
	end
	if not template then
		return
	end
	local held = Materials.counts(player)
	for index, item in items do
		local chip = chips:FindFirstChild(item.id) :: any
		if not chip then
			chip = template:Clone()
			chip.Name = item.id
			chip.Visible = true
			local def = Materials.get(item.id)
			chip.Icon.Image = def and def.icon or ""
			chip.Parent = chips
		end
		chip.LayoutOrder = index
		local have = math.min(held[item.id] or 0, item.count)
		local met = have >= item.count
		chip.BackgroundColor3 = template:GetAttribute(if met then "DoneFill" else "ShortFill") or chip.BackgroundColor3
		chip.Count.TextColor3 = template:GetAttribute(if met then "DoneText" else "ShortText") or chip.Count.TextColor3
		chip.Count.Text = (template:GetAttribute("Format") or "%s/%s"):format(Format.commas(have), Format.commas(item.count))
	end
end

local function render()
	local frame = tracker
	if not frame then
		return
	end
	local line = Quests.tracked(player)
	local stepIndex = line and player:GetAttribute(Quests.attr("Step", line.id))
	local state = line and player:GetAttribute(Quests.attr("State", line.id))
	local progress = line and player:GetAttribute(Quests.attr("Progress", line.id))
	local stepKey = if line then ("%s/%s"):format(line.id, tostring(stepIndex)) else nil
	if stepKey ~= lastKey then
		lastKey = stepKey
		table.clear(caughtUp)
	end
	local step = if line and type(stepIndex) == "number" then line.steps[stepIndex] else nil
	if not (line and step) or (state ~= "Active" and state ~= "Ready") then
		table.clear(caughtUp)
		frame.Visible = false
		player:SetAttribute("QuestShownLine", nil)
		player:SetAttribute("QuestShownState", nil)
		refreshGuide()
		return
	end
	line = line :: Quests.Line
	player:SetAttribute("QuestShownLine", line.id)
	frame.Visible = true
	local goal = Quests.goal(step)
	local have = displayedProgress(stepIndex :: number, step, state :: string, if type(progress) == "number" then progress else 0)
	-- done on the server, but wait for the counter before saying so
	local ready = state == "Ready" and have >= goal
	player:SetAttribute("QuestShownState", if ready then "Ready" else "Active")
	refreshGuide()

	-- state colours
	local key = if ready then "Ready" else "Active"
	local rim = colour("Rim" .. key, Color3.fromRGB(12, 112, 132))
	local lip = colour("Lip" .. key, Color3.fromRGB(10, 85, 102))
	for _, name in { "Tab", "Pill", "Badge" } do
		local piece = frame:FindFirstChild(name)
		local stroke = piece and piece:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = rim
		end
	end
	for _, name in { "PillLip", "BadgeLip" } do
		local piece = frame:FindFirstChild(name)
		if piece and piece:IsA("GuiObject") then
			piece.BackgroundColor3 = lip
		end
	end
	local tab = frame:FindFirstChild("Tab") :: Frame
	tab.BackgroundColor3 = colour("Tab" .. key, Color3.fromRGB(20, 169, 211))
	local tabLabel = tab:FindFirstChild("Label") :: TextLabel
	tabLabel.Text = ("%s · %d/%d"):format(if ready then "Complete!" else line.short, stepIndex :: number, #line.steps)
	local tabStroke = tabLabel:FindFirstChildWhichIsA("UIStroke")
	if tabStroke then
		tabStroke.Color = lip
	end

	-- badge
	local portrait = frame:FindFirstChild("Portrait", true) :: ImageLabel
	portrait.Image = iconFor(line, step, ready)
	local ring = frame:FindFirstChild("Ring", true) :: Frame
	local fillColour = colour("Fill" .. key, Color3.fromRGB(226, 56, 44))
	for _, d in ring:GetDescendants() do
		if d:IsA("ImageLabel") then
			d.ImageColor3 = if d.Name == "Track" then colour(if ready then "TrackReady" else "TrackColor", Color3.new(1, 1, 1)) else fillColour
		end
	end
	renderReward(frame, step)

	-- the tool phase (Quests.toolNeeded): get the tool first, then gather
	local tool = if ready then nil else Quests.toolNeeded(step, player)
	if tool then
		portrait.Image = tool.icon or ""
	end
	local fraction = if ready then 1 elseif tool then 0 else have / goal
	if ringTween then
		ringTween:Cancel()
	end
	ringValue.Value = shownProgress
	local tween = TweenService:Create(ringValue, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Value = fraction })
	ringTween = tween
	tween:Play()

	-- text
	local trackLine = if ready then line.returnTrack else step.track
	if tool then
		local upgrade = tool.recipe ~= nil and tool.recipe.tool ~= nil
		trackLine = (if upgrade then Quests.ToolText.upgrade else Quests.ToolText.buy):format(tool.name)
	end
	local verb, name = split(trackLine)
	local verbLabel = frame:FindFirstChild("Verb") :: TextLabel
	verbLabel.Text = verb
	verbLabel.TextColor3 = rim
	local targetLabel = frame:FindFirstChild("Target") :: TextLabel
	targetLabel.Text = name
	local countLabel = frame:FindFirstChild("Count") :: TextLabel
	local chips = frame:FindFirstChild("Chips")
	local byItem = not ready and not tool and step.kind == "bring" and chips ~= nil and #(step.items or {}) > 1
	countLabel.Visible = not byItem
	if chips and chips:IsA("GuiObject") then
		chips.Visible = byItem
		renderChips(chips, if byItem then step.items or {} else {})
	end
	if ready then
		countLabel.Text = line.returnNote
	elseif tool then
		countLabel.Text = Quests.ToolText.note
	else
		countLabel.Text = ('%s <font color="#6b8f97">/ %s</font>'):format(Format.commas(have), Format.commas(goal))
	end
end

-- Coalesce bursts of changes (three attributes, a counter ticking up) into one
-- render at the end of the frame.
local queued = false
local function refresh()
	if queued then
		return
	end
	queued = true
	task.defer(function()
		queued = false
		render()
	end)
end

function QuestTrackerUI.init(injected: any)
	deps = injected
end

function QuestTrackerUI.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("QuestTracker", 30)
	local frame = gui and gui:FindFirstChild("Tracker")
	if not (frame and frame:IsA("Frame")) then
		warn("[QuestTrackerUI] StarterGui has no QuestTracker/Tracker")
		return
	end
	tracker = frame
	ringValue.Changed:Connect(function(value: number)
		shownProgress = value
		setRing(value)
	end)
	for _, id in Quests.order do
		for _, field in { "Step", "State", "Progress" } do
			player:GetAttributeChangedSignal(Quests.attr(field, id)):Connect(refresh)
		end
	end
	-- walking into another world can switch the tracked line
	player:GetAttributeChangedSignal("CurrentWorld"):Connect(refresh)
	-- a bring step's chips and badge follow the materials held
	player:GetAttributeChangedSignal("Materials"):Connect(refresh)
	-- a gather step's tool phase ends when the tool arrives
	player:GetAttributeChangedSignal("OwnedTools"):Connect(refresh)
	local guide = frame:FindFirstChild("Guide")
	if guide and guide:IsA("GuiButton") then
		-- Held down, the button sits on its lip; it flips on release.
		local rest = guide.Position
		local lip = frame:FindFirstChild("GuideLip")
		-- The lip's spot measured at the button's own anchor: the button grows from its
		-- centre (ButtonFx) while the lip is anchored top-left, and using the lip's
		-- Position as-is threw the held button up and left (2026-10-21).
		local pressedAt = rest
		if lip and lip:IsA("GuiObject") then
			local d = guide.AnchorPoint - lip.AnchorPoint
			pressedAt = UDim2.new(
				lip.Position.X.Scale + lip.Size.X.Scale * d.X,
				lip.Position.X.Offset + lip.Size.X.Offset * d.X,
				lip.Position.Y.Scale + lip.Size.Y.Scale * d.Y,
				lip.Position.Y.Offset + lip.Size.Y.Offset * d.Y
			)
		end
		local function setPressed(down: boolean)
			guidePressed = down
			guide.Position = if down then pressedAt else rest
			refreshGuide()
		end
		guide.MouseButton1Down:Connect(function()
			setPressed(true)
		end)
		guide.MouseButton1Up:Connect(function()
			setPressed(false)
		end)
		guide.MouseLeave:Connect(function()
			if guidePressed then
				setPressed(false)
			end
		end)
		guide.Activated:Connect(function()
			local Guide = deps.Controllers.GuideController
			Guide.setEnabled(not Guide.isEnabled())
		end)
	end
	deps.Controllers.GuideController.onChanged(refreshGuide)
	-- follow the HUD counters as they count up
	deps.UI.CoinsUI.onShown(refresh)
	deps.UI.PlayerCardUI.Exp.onShown(refresh)
	setRing(0)
	refresh()
end

return QuestTrackerUI
