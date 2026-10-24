--!strict
-- CraftingUI: wires the hand-built Crafting stall, StarterGui/CraftingShop (the
-- "Recipe book" layout, option B on the Crafting & Armor canvas, 2026-10-12).
-- Nothing here builds UI: the set buttons and recipe rows are clones of the
-- hand-built Window/Templates/SetTemplate and IngredientTemplate (authored
-- hidden, shown on the clone).
--
--   Window/Tabs      TabArmor / TabPotions (2026-10-19; each with a Tab attribute and a
--                    Label, coloured from the gui's TabSelectedFill / TabSelectedText /
--                    TabIdleFill / TabIdleText like the Weaponsmith's)
--   Window/Sets      one SetTemplate per armour set of the world the player
--                    stands in (their "CurrentWorld"), or one PotionTemplate (a half-size
--                    copy: the list wraps into two columns) per potion its Crafter brews
--                    (Config/Potions: the tier of the world's band; no Pointer): Tile (rarity skin
--                    from Util.WeaponTile), Icon, Lock ("Lv N" while their level is
--                    short), Check (owned), SetName. The selected one is full
--                    size with a Pointer toward the details; the others shrink
--                    (Tile/SelectScale to IdleScale) and dim (IdleColor /
--                    IdleTextColor), the user's call after a white box looked off
--   Window/Detail    the selected set or potion: Stage/Preview, Info/SetName, Rarity
--                    (colour from its Color_<Rarity> attributes), Blurb,
--                    Cards (a row that packs the shown cards left): DefenseCard / HealthCard
--                    (Value) for a set, plus RegenCard / SpeedCard only for a set that has
--                    that bonus (2026-10-22); EffectCard / LastsCard for a potion
--                    (EffectCard's StatIcon is the potion's own picture),
--                    Ingredients (a ScrollingFrame, one row per recipe material or potion:
--                    Slot/Icon, ItemName, Count "have / need", Bar/Fill; its RowShare /
--                    GapShare attributes are a row's and a gap's share of the visible
--                    height, so a long recipe scrolls instead of running under Craft), Level ("Level N" for a
--                    set; for a potion "Have ×N" from its HaveFormat), Cost, Craft
--   Craft            Craft (Brew for a potion: TextBrew) when everything is met;
--                    otherwise locked with why (level, then materials, then coins); an
--                    owned set shows Wear, or Wearing while it's worn. Looks and words
--                    come from the button's Skin* / Stroke* / Text* attributes.
-- Crafting asks Remotes.CraftArmor (StallService checks it all again and puts the
-- set on); Wear fires Remotes.EquipArmor; brewing asks Remotes.BrewPotion
-- (PotionService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Armor = require(Config:WaitForChild("Armor"))
local Bonuses = require(Config:WaitForChild("Bonuses"))
local Materials = require(Config:WaitForChild("Materials"))
local Potions = require(Config:WaitForChild("Potions"))
local Worlds = require(Config:WaitForChild("Worlds"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))
local WeaponTile = require(Util:WaitForChild("WeaponTile"))

local CraftingUI = {}

local PANEL_ID = "Crafting"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

-- What a potion's Effect card says: its title and value (Config/Potions).
local EFFECT_TITLE: { [string]: string } = {
	Health = "Heals",
	Strength = "Damage",
	Stoneskin = "Defense",
	Swiftness = "Speed",
	Regen = "Regen",
	Gatherer = "Tool Power",
	Angler = "Rare Fish",
}

local PanelWindow: any = nil
local gui: any = nil
local window: any = nil
local tab = "Armor"
local selected: string? = nil
local shownList: string? = nil -- which list the Sets column holds ("Armor:1", "Potions:1")
local busy = false

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function world(): number
	return number("CurrentWorld", 1)
end

local function owns(id: string): boolean
	local owned = player:GetAttribute("OwnedArmor")
	return type(owned) == "string" and ("," .. owned .. ","):find("," .. id .. ",", 1, true) ~= nil
end

local function setsHere(): { Armor.ArmorDef }
	local out = {}
	for _, def in Armor.list() do
		if def.world == world() then
			table.insert(out, def)
		end
	end
	return out
end

-- The potions this world's Crafter brews: its band's tier, those with a recipe, and of Tier I
-- only this world's own (Config/Potions `world`).
local function potionsHere(): { Potions.PotionDef }
	local out = {}
	local tier = Potions.tierAt(world())
	for _, def in Potions.list() do
		if def.tier == tier and def.recipe and (def.world == nil or def.world == world()) then
			table.insert(out, def)
		end
	end
	return out
end

-- What the Sets column lists on this tab.
local function entriesHere(): { any }
	return if tab == "Potions" then potionsHere() :: { any } else setsHere() :: { any }
end

local function entryOf(id: string?): any
	return if tab == "Potions" then Potions.get(id) else Armor.get(id)
end

-- The short name on a potion's button ("Health I").
local function shortName(def: Potions.PotionDef): string
	return def.short
end

-- How many of a recipe item the player holds: a material, or a potion.
local function held(id: string, counts: { [string]: number }, potions: { [string]: number }): number
	return if Potions.get(id) then potions[id] or 0 else counts[id] or 0
end

-- Why the set can't be crafted yet ("level" / "materials" / "coins"), or nil.
local function blocker(def: Armor.ArmorDef, counts: { [string]: number }): string?
	if number("Level", 1) < def.level then
		return "level"
	end
	for _, item in def.recipe do
		if (counts[item.id] or 0) < item.count then
			return "materials"
		end
	end
	if number("Coins", 0) < def.coins then
		return "coins"
	end
	return nil
end

-- Why the potion can't be brewed yet ("materials" / "coins"), or nil.
local function brewBlocker(def: Potions.PotionDef, counts: { [string]: number }, potions: { [string]: number }): string?
	for _, item in def.recipe or {} do
		if held(item.id, counts, potions) < item.count then
			return "materials"
		end
	end
	if number("Coins", 0) < def.coins then
		return "coins"
	end
	return nil
end

local function setButton(button: any, look: string, words: string)
	button.Skin.Image = button:GetAttribute("Skin" .. look) or button.Skin.Image
	button.Label.Text = words
	local stroke = button.Label:FindFirstChildOfClass("UIStroke")
	local color = button:GetAttribute("Stroke" .. look)
	if stroke and typeof(color) == "Color3" then
		stroke.Color = color
	end
	-- a locked button can't be clicked, so it gets no hover or press (Util.ButtonFx)
	button.Active = look ~= "Locked"
end

local function rebuildSets()
	local list = window.Sets
	-- Sets is a grid (each tile grows round its own middle); its cell is the tab's tile
	-- size, the Sets frame's Cell_Armor / Cell_Potions attributes
	local grid = list:FindFirstChildOfClass("UIGridLayout")
	local cell = list:GetAttribute(if tab == "Potions" then "Cell_Potions" else "Cell_Armor")
	if grid and typeof(cell) == "UDim2" then
		grid.CellSize = cell
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for index, def in entriesHere() do
		local template = if tab == "Potions" then window.Templates:FindFirstChild("PotionTemplate") else nil
		local button = (template or window.Templates.SetTemplate):Clone()
		button.Name = def.id
		button.LayoutOrder = index
		button.Visible = true
		button.Tile.Image = WeaponTile.skin(def.rarity)
		button.Tile.Icon.Image = def.icon or ""
		button.SetName.Text = if tab == "Potions" then shortName(def) else def.name
		button.Activated:Connect(function()
			selected = def.id
			CraftingUI.refresh()
		end)
		button.Parent = list
	end
end

-- One recipe row: a material or a potion, with how many are held of how many needed.
local function addRow(rows: Instance, index: number, item: { id: string, count: number }, have: number, done: boolean, shownDone: boolean)
	local def: any = Potions.get(item.id) or Materials.get(item.id)
	local row = window.Templates.IngredientTemplate:Clone()
	row.Name = item.id
	row.LayoutOrder = index
	row.Visible = true
	-- the item on its rarity's tile, like the Inventory
	row.Slot.Image = WeaponTile.skin(def and def.rarity)
	row.Slot.Icon.Image = def and def.icon or ""
	row.ItemName.Text = def and def.name or item.id
	row.Count.Text = if shownDone
		then "×" .. Format.commas(item.count)
		else Format.commas(have) .. " / " .. Format.commas(item.count)
	row.Count.TextColor3 = row:GetAttribute(if done then "DoneColor" else "ShortColor")
	row.Bar.Fill.Size = UDim2.fromScale(math.clamp(have / item.count, 0, 1), 1)
	row.Bar.Fill.Visible = have > 0
	row.Bar.Fill.Gradient.Color = ColorSequence.new(
		row:GetAttribute(if done then "DoneTop" else "ShortTop"),
		row:GetAttribute(if done then "DoneBottom" else "ShortBottom")
	)
	row.Parent = rows
end

-- Size the recipe list's canvas to its rows. The canvas is the list's measured height
-- times how many visible heights the rows need (a ScrollingFrame's CanvasSize scale is
-- a share of its parent, not of itself, so it's set from the measurement), and the rows
-- and gaps are shares of the canvas shrunk by the same factor: a row stays RowShare of
-- what you see however many there are. Refitted when the screen changes size.
local fitted: { [ScrollingFrame]: boolean } = {}
local function fitRows(rows: Instance)
	if not rows:IsA("ScrollingFrame") then
		return
	end
	local list = {}
	for _, child in rows:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(list, child)
		end
	end
	local share = rows:GetAttribute("RowShare") or 0.3
	local gap = rows:GetAttribute("GapShare") or 0.04
	local canvas = math.max(1, #list * share + math.max(0, #list - 1) * gap)
	rows.CanvasSize = UDim2.new(0, 0, 0, math.floor(rows.AbsoluteSize.Y * canvas + 0.5))
	for _, row in list do
		row.Size = UDim2.fromScale(1, share / canvas)
	end
	local layout = rows:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(gap / canvas, 0)
	end
	-- (a refresh while open keeps the scroll; a shorter list clamps it by itself)
	if not fitted[rows] then
		fitted[rows] = true
		rows:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fitRows(rows)
		end)
	end
end

local function clearRows(rows: Instance)
	for _, child in rows:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- one of the detail's stat cards (they sit in Info/Cards)
local function card(name: string): any
	return window.Detail.Card.Info:FindFirstChild(name, true)
end

-- "0.25", "5": a share as a percentage without trailing zeros
local function percentText(share: number): string
	return (("%.2f"):format(share * 100):gsub("0+$", ""):gsub("%.$", ""))
end

-- `set`: the armour set shown (its regen / speed cards show only if it has them)
local function showCards(potion: boolean, set: Armor.ArmorDef?)
	card("DefenseCard").Visible = not potion
	card("HealthCard").Visible = not potion
	card("RegenCard").Visible = not potion and set ~= nil and (set.regen or 0) > 0
	card("SpeedCard").Visible = not potion and set ~= nil and (set.speed or 0) > 0
	card("EffectCard").Visible = potion
	card("LastsCard").Visible = potion
end

local function fillHeader(def: any)
	local info = window.Detail.Card.Info
	window.Detail.Card.Stage.Preview.Image = def.icon or ""
	info.SetName.Text = def.name
	local color = info.Rarity:GetAttribute("Color_" .. def.rarity)
	if typeof(color) == "Color3" then
		info.Rarity.BackgroundColor3 = color
	end
	info.Rarity.Label.Text = def.rarity
end

local function fillCost(coins: number, met: boolean)
	local info = window.Detail.Card.Info
	local costAmount = info.Cost:FindFirstChild("Amount", true)
	costAmount.Text = Format.coins(coins)
	costAmount.TextColor3 = info.Cost:GetAttribute(if met then "MetColor" else "ShortColor")
end

local function fillDetail(def: Armor.ArmorDef, counts: { [string]: number })
	local info = window.Detail.Card.Info
	fillHeader(def)
	showCards(false, def)
	info.Blurb.Text = def.blurb
	card("DefenseCard").Value.Text = math.floor(def.defense * 100 + 0.5) .. "%"
	-- with the Health upgrade (Config/Bonuses; 2026-10-23, the user: real numbers everywhere but the Index)
	card("HealthCard").Value.Text = "+" .. Format.commas(math.floor(def.health * Bonuses.health(player) + 0.5))
	card("RegenCard").Value.Text = "+" .. percentText(def.regen or 0) .. "%/s"
	card("SpeedCard").Value.Text = "+" .. percentText(def.speed or 0) .. "%"

	local rows = info.Ingredients
	clearRows(rows)
	-- an owned set's recipe reads as done: just what it took
	local crafted = owns(def.id)
	for index, item in def.recipe do
		local have = if crafted then item.count else counts[item.id] or 0
		addRow(rows, index, item, have, have >= item.count, crafted)
	end
	fitRows(rows)

	local levelMet = crafted or number("Level", 1) >= def.level
	info.Level.Label.Text = "Level " .. def.level
	info.Level.BackgroundColor3 = info.Level:GetAttribute(if levelMet then "MetColor" else "ShortColor")
	fillCost(def.coins, crafted or number("Coins", 0) >= def.coins)

	local craft = info.Craft
	if owns(def.id) then
		local worn = player:GetAttribute("EquippedArmor") == def.id
		setButton(craft, if worn then "Owned" else "Craft", craft:GetAttribute(if worn then "TextWearing" else "TextWear"))
	else
		local why = blocker(def, counts)
		if why == "level" then
			setButton(craft, "Locked", (craft:GetAttribute("TextLevel") or "Need Level %d"):format(def.level))
		elseif why == "materials" then
			setButton(craft, "Locked", craft:GetAttribute("TextMaterials"))
		elseif why == "coins" then
			setButton(craft, "Locked", craft:GetAttribute("TextCoins"))
		else
			setButton(craft, "Craft", craft:GetAttribute("TextCraft"))
		end
	end
end

local function fillPotion(def: Potions.PotionDef, counts: { [string]: number }, potions: { [string]: number })
	local info = window.Detail.Card.Info
	fillHeader(def)
	showCards(true)
	info.Blurb.Text = Potions.describe(def)
	local percent = Potions.percent(def.power)
	local effect = card("EffectCard")
	effect.Title.Text = EFFECT_TITLE[def.kind] or "Effect"
	effect.Value.Text = if def.kind == "Health"
		then percent .. "%"
		elseif def.kind == "Regen" then "+" .. percent .. "%/s"
		else "+" .. percent .. "%"
	for _, name in { "StatIcon", "StatIconShadow" } do
		local icon = effect:FindFirstChild(name)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = def.icon or icon.Image
		end
	end
	card("LastsCard").Value.Text = if def.seconds > 0 then ("%d:%02d"):format(def.seconds // 60, def.seconds % 60) else "Instant"

	local rows = info.Ingredients
	clearRows(rows)
	for index, item in def.recipe or {} do
		local have = held(item.id, counts, potions)
		addRow(rows, index, item, have, have >= item.count, false)
	end
	fitRows(rows)

	local have = potions[def.id] or 0
	info.Level.Label.Text = (info.Level:GetAttribute("HaveFormat") or "Have ×%s"):format(Format.commas(have))
	info.Level.BackgroundColor3 = info.Level:GetAttribute("MetColor")
	fillCost(def.coins, number("Coins", 0) >= def.coins)

	local craft = info.Craft
	local why = brewBlocker(def, counts, potions)
	if why == "materials" then
		setButton(craft, "Locked", craft:GetAttribute("TextMaterials"))
	elseif why == "coins" then
		setButton(craft, "Locked", craft:GetAttribute("TextCoins"))
	else
		setButton(craft, "Craft", craft:GetAttribute("TextBrew") or "Brew")
	end
end

local function styleTabs()
	local tabs = window:FindFirstChild("Tabs")
	for _, button in tabs and tabs:GetChildren() or {} do
		local name = button:GetAttribute("Tab")
		if button:IsA("GuiButton") and type(name) == "string" then
			local on = name == tab
			button:SetAttribute("Selected", on) -- the open tab stays grown (Util.ButtonFx)
			local fill = gui:GetAttribute(if on then "TabSelectedFill" else "TabIdleFill")
			if typeof(fill) == "Color3" then
				button.BackgroundColor3 = fill
			end
			local label = button:FindFirstChild("Label")
			local text = gui:GetAttribute(if on then "TabSelectedText" else "TabIdleText")
			if label and label:IsA("TextLabel") and typeof(text) == "Color3" then
				label.TextColor3 = text
			end
		end
	end
end

function CraftingUI.refresh()
	if not window then
		return
	end
	styleTabs()
	local listKey = tab .. ":" .. world()
	if shownList ~= listKey then
		shownList = listKey
		selected = nil
		rebuildSets()
	end
	local entries = entriesHere()
	local def = entryOf(selected)
	if not def or not table.find(entries, def) then
		-- start on the first set they don't own yet (any potion: the first)
		def = nil
		for _, candidate in entries do
			if tab == "Potions" or not owns(candidate.id) then
				def = candidate
				break
			end
		end
		def = def or entries[1]
		selected = def and def.id
	end

	local info = Worlds.get(world())
	if info and window:FindFirstChild("World") then
		window.World.Label.Text = ("World %d · %s"):format(info.id, (info.name:gsub("^The ", "")))
	end
	local coinsPill = window:FindFirstChild("Coins")
	local coinsAmount = coinsPill and coinsPill:FindFirstChild("Amount", true)
	if coinsAmount then
		coinsAmount.Text = Format.coins(number("Coins", 0))
	end

	local counts = Materials.counts(player)
	local potions = Potions.counts(player)
	for _, button in window.Sets:GetChildren() do
		local entry = entryOf(button.Name)
		if entry and button:IsA("GuiButton") then
			local tile = button:FindFirstChild("Tile") :: any
			local on = entry.id == selected
			button.Pointer.Visible = on and tab ~= "Potions"
			button:SetAttribute("Selected", on) -- stays grown (Util.ButtonFx)
			tile.SelectScale.Scale = if on then 1 else button:GetAttribute("IdleScale") or 0.86
			local dim = button:GetAttribute("IdleColor") or Color3.new(0.8, 0.8, 0.8)
			tile.ImageColor3 = if on then Color3.new(1, 1, 1) else dim
			tile.Icon.ImageColor3 = if on then Color3.new(1, 1, 1) else dim
			button.SetName.TextColor3 = button:GetAttribute(if on then "SelectedTextColor" else "IdleTextColor") or button.SetName.TextColor3
			if tab == "Potions" then
				tile.Check.Visible = false
				tile.Lock.Visible = false
			else
				tile.Check.Visible = owns(entry.id)
				tile.Lock.Visible = not owns(entry.id) and number("Level", 1) < entry.level
				tile.Lock.Label.Text = "Lv " .. entry.level
			end
		end
	end
	window.Detail.Visible = def ~= nil
	if def and tab == "Potions" then
		fillPotion(def, counts, potions)
	elseif def then
		fillDetail(def, counts)
	end
end

local function onCraft()
	if busy then
		return
	end
	if tab == "Potions" then
		local def = Potions.get(selected)
		if not def or brewBlocker(def, Materials.counts(player), Potions.counts(player)) then
			return
		end
		busy = true
		local ok, result = pcall(function()
			return Remotes.getFunction("BrewPotion"):InvokeServer(def.id)
		end)
		busy = false
		if not ok then
			warn("[CraftingUI] BrewPotion failed: " .. tostring(result))
		end
		UiSound.play(if ok and result == true then "Purchase" else "Refuse")
		CraftingUI.refresh()
		return
	end
	local def = Armor.get(selected)
	if not def then
		return
	end
	if owns(def.id) then
		if player:GetAttribute("EquippedArmor") ~= def.id then
			Remotes.getEvent("EquipArmor"):FireServer(def.id)
		end
		return
	end
	if blocker(def, Materials.counts(player)) then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.getFunction("CraftArmor"):InvokeServer(def.id)
	end)
	busy = false
	if not ok then
		warn("[CraftingUI] CraftArmor failed: " .. tostring(result))
	end
	UiSound.play(if ok and result == true then "Purchase" else "Refuse")
	CraftingUI.refresh()
end

local function wire(found: ScreenGui)
	gui = found
	window = found:WaitForChild("Window")
	window.Detail.Card.Info.Craft.Activated:Connect(onCraft)
	local tabs = window:FindFirstChild("Tabs")
	for _, button in tabs and tabs:GetChildren() or {} do
		local name = button:GetAttribute("Tab")
		if button:IsA("GuiButton") and type(name) == "string" then
			button.Activated:Connect(function()
				tab = name
				CraftingUI.refresh()
			end)
		end
	end
	for _, name in { "Coins", "Level", "Materials", "Potions", "OwnedArmor", "EquippedArmor", "CurrentWorld", "Upgrade_Health" } do
		player:GetAttributeChangedSignal(name):Connect(CraftingUI.refresh)
	end
	found:GetPropertyChangedSignal("Enabled"):Connect(CraftingUI.refresh)
	CraftingUI.refresh()
end

function CraftingUI.init(injected: any)
	PanelWindow = injected.UI.PanelWindow
end

function CraftingUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if found then
			wire(found)
		else
			warn("[CraftingUI] no Crafting panel (StarterGui/CraftingShop)")
		end
	end)
end

return CraftingUI
