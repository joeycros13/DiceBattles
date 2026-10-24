--!strict
-- IndexPopup: the NEW popup at the top of the screen when the player discovers
-- a creature or a weapon (popup 1 "Ray burst" from the Claude Design canvas).
-- Wires the hand-built StarterGui/IndexPopup; nothing here builds UI.
--
-- IndexService fires Remotes.IndexDiscovered { kind = "Enemy" | "Weapon", id,
-- again? }. `again` is a weapon the player had before, lost (sold, removed) and
-- got back: the popup still plays, without the NEW tag (user, 2026-10-11).
-- Drop chances on the chips include the player's luck (IndexUI.luckyChance).
-- Discoveries queue up and play one at a time: the popup pops in, its rays
-- turn behind the picture, and after ShowSeconds it pops out.
--   * Enemy: its portrait, the teal banner and "Added to your Index" (the
--     Popup's *Enemy attributes).
--   * Weapon: its drawn icon (def.icon, else a 3D view in Icon), a chip per
--     enemy that drops it, and a look that grows with its RARITY (the user's
--     request, 2026-10-09): every <Name>_<Rarity> attribute on Popup --
--       Banner, Rays (image, "" = none), RaysColor, RaysTransparency, RaysSpin
--       (seconds a turn), SparklesSpin (0 = none, negative = backwards),
--       SparklesColor, GlowColor, GlowPulse (how much the glow breathes),
--       NameStroke, PopFrom (0 = grow from nothing, >1 = slam down from that
--       size), PopSeconds, ShowSeconds, Flash / FlashColor (a full-screen
--       flash, peak opacity), Dim (darkens the screen behind it), Rainbow (glow, sparkles and name outline cycle hues),
--       NewText ("NEW!" / "SECRET!"), ChanceColor (the drop % on the chips).
--     Common is plain grey with no rays; Uncommon / Rare green / blue rays;
--     Epic purple with sparkles and a breathing glow; Legendary gold with a
--     flash; Secret slams in over a dimmed, flashing screen with rainbow rays.
--     The camera never shakes (the user's call, 2026-10-09).
--   * Core (2026-10-12): a secret-weapon core (Config/Materials `core`), fired by
--     MaterialService. Its drawn icon, the <Name>_Core look (soil-brown banner),
--     the CoreSubtitle line and no drop chips (where it drops stays secret).
--   * Armor (2026-10-13): an armour set crafted for the first time (IndexService
--     via ArmorService.grant). Its drawn icon, its rarity's look, the
--     ArmorSubtitle line and no chips.
--   * Item (2026-10-20, the whole book): the first tool, fish, potion, quest item or
--     Rare-or-better material (IndexService). Its drawn icon, its rarity's look, the
--     ItemSubtitle line and no chips.
--   * Title (2026-10-20): an Index title earned. The Popup's TitleIcon / TitleSecretIcon trophy,
--     a Collector title in the Legendary look and a Completionist title in the Secret look,
--     TitleNewText for the tag ("NEW TITLE!") and the TitleSubtitle line.

local Players = game:GetService("Players")
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Index = require(Config:WaitForChild("Index"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Materials = require(Config:WaitForChild("Materials"))
local Armor = require(Config:WaitForChild("Armor"))
local Worlds = require(Config:WaitForChild("Worlds"))

local IndexPopup = {}

local GUI_TIMEOUT = 15
local MAX_CHIPS = 3
local player = Players.LocalPlayer

local deps: any = nil
local IndexUI: any = nil

type Discovery = { kind: string, id: string, again: boolean? }
local queue: { Discovery } = {}
local playing = false
local gui: ScreenGui? = nil

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function hex(c: Color3): string
	return c:ToHex()
end

-- One discovery's look: weapons read <name>_<Rarity>, enemies <name>Enemy.
type Look = (name: string, fallback: any) -> any
local function lookFor(pop: Instance, item: Discovery): Look
	if item.kind == "Enemy" then
		return function(name, fallback)
			return attribute(pop, name .. "Enemy", fallback)
		end
	end
	local rarity = "Common"
	if item.kind == "Title" then
		local title = Index.titleOf(item.id)
		rarity = if title and title.secret then "Secret" else "Legendary"
	elseif item.kind == "Item" then
		local def = Index.itemDef(item.id)
		rarity = def and def.rarity or "Common"
	elseif item.kind == "Core" then
		local core = Materials.get(item.id)
		rarity = core and core.rarity or "Core"
	elseif item.kind == "Armor" then
		local set = Armor.get(item.id)
		rarity = set and set.rarity or "Common"
	else
		local def = Weapons.get(item.id)
		rarity = def and def.rarity or "Common"
	end
	return function(name, fallback)
		return attribute(pop, name .. "_" .. rarity, attribute(pop, name .. "Weapon", fallback))
	end
end

-- Fill the popup for one discovery. Returns false if there is nothing to show.
local function fill(pop: Frame, item: Discovery, look: Look): boolean
	local isEnemy = item.kind == "Enemy"
	local isCore = item.kind == "Core"
	local isArmor = item.kind == "Armor"
	local isItem = item.kind == "Item"
	local isTitle = item.kind == "Title"
	local p = pop :: any
	local name: string
	local drawn = false
	if isEnemy then
		local def = Worlds.enemyDefs()[item.id]
		if not def then
			return false
		end
		name = def.name
		p.Portrait.Image = def.portrait or ""
	elseif isTitle then
		local title = Index.titleOf(item.id)
		if not title then
			return false
		end
		name = title.name
		local icon = attribute(pop, if title.secret then "TitleSecretIcon" else "TitleIcon", "")
		drawn = icon ~= "" and p:FindFirstChild("Picture") ~= nil
		if drawn then
			p.Picture.Image = icon
		end
	elseif isItem then
		local def = Index.itemDef(item.id)
		if not def then
			return false
		end
		name = def.name
		drawn = def.icon ~= nil and p:FindFirstChild("Picture") ~= nil
		if drawn then
			p.Picture.Image = def.icon :: string
		end
	elseif isArmor then
		local def = Armor.get(item.id)
		if not def then
			return false
		end
		name = def.name
		drawn = def.icon ~= nil and p:FindFirstChild("Picture") ~= nil
		if drawn then
			p.Picture.Image = def.icon :: string
		end
	elseif isCore then
		local def = Materials.get(item.id)
		if not def then
			return false
		end
		name = def.name
		drawn = def.icon ~= nil and p:FindFirstChild("Picture") ~= nil
		if drawn then
			p.Picture.Image = def.icon :: string
		end
	else
		local def = Weapons.get(item.id)
		if not def then
			return false
		end
		name = def.name
		drawn = def.icon ~= nil and p:FindFirstChild("Picture") ~= nil
		if drawn then
			p.Picture.Image = def.icon
		else
			IndexUI.showWeapon(p.Icon, item.id)
		end
	end
	p.Portrait.Visible = isEnemy
	p.Icon.Visible = not isEnemy and not drawn
	if p:FindFirstChild("Picture") then
		p.Picture.Visible = drawn
	end
	local raysImage = look("Rays", p.Rays.Image)
	p.Rays.Visible = raysImage ~= ""
	if raysImage ~= "" then
		p.Rays.Image = raysImage
	end
	p.Rays.ImageColor3 = look("RaysColor", Color3.new(1, 1, 1))
	p.Rays.ImageTransparency = look("RaysTransparency", 0.1)
	p.Glow.ImageColor3 = look("GlowColor", Color3.new(1, 1, 1))
	local sparkles = p:FindFirstChild("Sparkles")
	if sparkles then
		sparkles.Visible = look("SparklesSpin", 0) ~= 0
		sparkles.ImageColor3 = look("SparklesColor", Color3.new(1, 1, 1))
	end
	p.Banner.Image = look("Banner", p.Banner.Image)
	p.Banner.ItemName.Text = name
	local stroke = p.Banner.ItemName:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = look("NameStroke", stroke.Color)
	end
	local tag = p:FindFirstChild("NewTag")
	local tagLabel = tag and tag:FindFirstChild("Label")
	if tagLabel and tagLabel:IsA("TextLabel") then
		tagLabel.Text = if isTitle then attribute(pop, "TitleNewText", "NEW TITLE!") else look("NewText", "NEW!")
	end
	-- nothing is new about a weapon found again
	if tag and tag:IsA("GuiObject") then
		tag.Visible = not item.again
	end
	p.Subtitle.Visible = isEnemy or isCore or isArmor or isItem or isTitle
	p.Subtitle.Text = if isCore
		then attribute(pop, "CoreSubtitle", "Take it to the Crafter")
		elseif isTitle then attribute(pop, "TitleSubtitle", "Wear it from your Index")
		elseif isItem then attribute(pop, "ItemSubtitle", "Added to your Index")
		elseif isArmor then attribute(pop, "ArmorSubtitle", "Added to your Index")
		else attribute(pop, "EnemySubtitle", "Added to your Index")

	-- weapons: where they drop, likeliest first
	local chips = p.Chips :: Frame
	local showChips = not isEnemy and not isCore and not isArmor and not isItem and not isTitle
	chips.Visible = showChips
	for _, child in chips:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local templates = gui and gui:FindFirstChild("Templates")
	local chipTemplate = templates and templates:FindFirstChild("Chip")
	if showChips and chipTemplate then
		-- sized from the screen: the popup itself is scaled to 0 while it pops in
		local screen = (gui :: ScreenGui).AbsoluteSize.Y
		-- a share of the screen height, so it reads the same on a phone (no pixel floor)
		local textSize = math.max(1, math.floor(screen * attribute(chipTemplate, "TextScale", 0.02) + 0.5))
		local accent = hex(look("ChanceColor", attribute(chipTemplate, "ChanceColor", Color3.new(1, 1, 1))))
		for order, source in Index.sourcesOf(item.id) do
			if order > MAX_CHIPS then
				break
			end
			local enemy = Worlds.enemyDefs()[source.enemy]
			local chip = chipTemplate:Clone() :: any
			chip.LayoutOrder = order
			chip.Visible = true
			chip.Label.TextSize = textSize
			chip.Label.Text = ('%s <font color="#%s">%s</font>'):format(enemy and enemy.name or source.enemy, accent, Index.percent(IndexUI.luckyChance(source.chance)))
			chip.Parent = chips
		end
	end
	return true
end

local function spin(image: Instance?, seconds: number): Tween?
	if not (image and image:IsA("GuiObject")) or seconds == 0 then
		return nil
	end
	image.Rotation = 0
	local tween = TweenService:Create(image, TweenInfo.new(math.abs(seconds), Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
		Rotation = if seconds > 0 then 360 else -360,
	})
	tween:Play()
	return tween
end

local function screenFrame(name: string): Frame?
	local found = gui and gui:FindFirstChild(name)
	return if found and found:IsA("Frame") then found else nil
end

local function playNext()
	local pop = gui and gui:FindFirstChild("Popup")
	if playing or not (pop and pop:IsA("Frame")) then
		return
	end
	local item = table.remove(queue, 1)
	if not item then
		return
	end
	playing = true
	local look = lookFor(pop, item)
	local scale = pop:FindFirstChildOfClass("UIScale")
	if not fill(pop, item, look) then
		playing = false
		playNext()
		return
	end
	UiSound.play("NewItem")
	local p = pop :: any
	local tweens: { Tween } = {}
	local function keep(tween: Tween?)
		if tween then
			table.insert(tweens, tween)
		end
	end

	-- rays and sparkles turn while it shows (sparkles the other way)
	keep(spin(p.Rays, look("RaysSpin", attribute(pop, "RaysSpinSeconds", 9))))
	keep(spin(p:FindFirstChild("Sparkles"), look("SparklesSpin", 0)))
	-- the glow breathes
	local glow = p.Glow :: ImageLabel
	local glowSize = glow.Size
	local pulse = look("GlowPulse", 0)
	if pulse > 0 then
		local big = UDim2.fromScale(glowSize.X.Scale * (1 + pulse), glowSize.Y.Scale * (1 + pulse))
		local breathe = TweenService:Create(glow, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = big })
		breathe:Play()
		keep(breathe)
	end
	-- the screen behind: dim it, flash it
	local dim = screenFrame("Dim")
	local dimTo = look("Dim", 0)
	if dim and dimTo > 0 then
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 - dimTo }):Play()
	end
	local flash = screenFrame("Flash")
	local flashPeak = look("Flash", 0)
	if flash and flashPeak > 0 then
		flash.BackgroundColor3 = look("FlashColor", Color3.new(1, 1, 1))
		flash.BackgroundTransparency = 1 - flashPeak
		TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
	-- rainbow: the glow, sparkles and name outline cycle through the hues
	local rainbow = look("Rainbow", false) == true
	if rainbow then
		task.spawn(function()
			local stroke = p.Banner.ItemName:FindFirstChildOfClass("UIStroke")
			local sparkles = p:FindFirstChild("Sparkles")
			local start = os.clock()
			local lasts = look("ShowSeconds", 3) + look("PopSeconds", 0.35) + 0.3
			while playing and os.clock() - start < lasts do
				local hue = ((os.clock() - start) * 0.5) % 1
				glow.ImageColor3 = Color3.fromHSV(hue, 0.55, 1)
				if sparkles then
					sparkles.ImageColor3 = Color3.fromHSV((hue + 0.5) % 1, 0.35, 1)
				end
				if stroke then
					stroke.Color = Color3.fromHSV(hue, 0.85, 0.55)
				end
				task.wait(1 / 30)
			end
		end)
	end

	-- pop in: grow from nothing with an overshoot, or slam down from big
	local from = look("PopFrom", 0)
	local popSeconds = look("PopSeconds", 0.35)
	if scale then
		scale.Scale = if from > 0 then from else 0
	end
	pop.Visible = true
	if scale then
		local style = if from > 1 then Enum.EasingStyle.Bounce else Enum.EasingStyle.Back
		TweenService:Create(scale, TweenInfo.new(popSeconds, style, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.wait(look("ShowSeconds", attribute(pop, "ShowSeconds", 3)))
	if dim and dimTo > 0 then
		TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	end
	if scale then
		local out = TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		out:Play()
		out.Completed:Wait()
	end
	pop.Visible = false
	for _, tween in tweens do
		tween:Cancel()
	end
	glow.Size = glowSize
	playing = false
	playNext()
end

function IndexPopup.show(kind: string, id: string, again: boolean?)
	table.insert(queue, { kind = kind, id = id, again = again == true })
	task.spawn(playNext)
end

function IndexPopup.init(injected: any)
	deps = injected
	IndexUI = deps.UI.IndexUI
end

function IndexPopup.start()
	deps.Remotes.getEvent("IndexDiscovered").OnClientEvent:Connect(function(info: any)
		if type(info) == "table" and type(info.kind) == "string" and type(info.id) == "string" then
			IndexPopup.show(info.kind, info.id, info.again == true)
		end
	end)
	task.spawn(function()
		local found = player:WaitForChild("PlayerGui"):WaitForChild("IndexPopup", GUI_TIMEOUT)
		if found and found:IsA("ScreenGui") then
			gui = found
			playNext()
		else
			warn("[IndexPopup] no IndexPopup ScreenGui in StarterGui")
		end
	end)
end

return IndexPopup
