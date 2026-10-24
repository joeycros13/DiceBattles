--!strict
-- ShopUI: wires the hand-built Weapons shop, StarterGui/WeaponsShop (the
-- "Counter list" layout chosen on the Claude Design canvas). Nothing here
-- builds UI; the rows are hand-placed under Window/List, one per weapon, each
-- named Item_<id> with ItemId / Price attributes.
--
-- What this fills in:
--   * Window/Coins/Amount: the player's coin balance (their "Coins" attribute).
--   * each row's Art: the shared weapon tile (Util.WeaponTile: rarity skin and drawn
--     icon, like the Inventory; 2026-10-12, it was an old viewport tile).
--   * each weapon row's Dps / Damage / Speed / Reach chips (Content/Value), from Config/Weapons.
--   * Buy/Content, Coins/Content and each stat chip's Content are centred rows
--     (Util.CenterRow): the coin, price or "Owned" sit centred in the button.
--   * each row's Buy button, in one of three looks set by its attributes:
--       owned (the starter weapon, or in OwnedWeapons) -> SkinOwned, OwnedText
--       affordable                                     -> SkinBuy, the price
--       too expensive                                  -> SkinLocked, the price
-- The price is the weapon's `price` in Config/Weapons (what the server charges);
-- a row's Price attribute is only the fallback for a weapon without one.
-- Clicking an affordable Buy asks Remotes.BuyWeapon (StallService checks the
-- price, coins and that the player stands at the stall, then grants the
-- weapon with the Index pop-up); the row restyles itself from OwnedWeapons.
-- Every world has its own Weapons stall selling only that world's weapons
-- (2026-10-12): the list holds every world's rows and shows only those whose
-- weapon's `world` is the player's "CurrentWorld" (published by WorldBannerUI).
-- Tabs (2026-10-19, user's request): Window/Tabs holds TabWeapons and TabTools
-- (each with a Tab attribute and a Label); the gui's TabSelectedFill / TabSelectedText
-- / TabIdleFill / TabIdleText attributes colour them. Rows with Kind = "Tool" are the
-- gathering tools (Config/Tools: price, world, OwnedTools) and show only on the Tools
-- tab; their Buy asks Remotes.BuyTool (StallService) and owning one shows its
-- hotbar slot. The other rows are weapons and show on the Weapons tab.
-- Upgrades (2026-10-20, option C "upgrade path" on the Tool Upgrade Recipes canvas,
-- https://claude.ai/artifact/1zSpsCCM1Xg7DSgxdNuUPX): a tool with a `recipe` (the Stone Axe and
-- Stone Rod: the wooden one plus Oak Log, Stone, Fox Fur and Boar Tusk) shows the path in its
-- hand-built row: `UpgradeFrom` (the previous tool's shared tile, its `Owned` tick shown while
-- it is owned) → `Arrow` → `Art`, with `FromText` under them (its `Format` "Upgrades your %s"),
-- and the materials in the `Recipe` grid: one clone of Templates/RecipeCard per material
-- (`IconBox/Icon`, `ItemName`, `Count` in the card's `Format`, `Bar/Fill` as wide as the share
-- held), coloured by the card's ShortText / DoneText and ShortFill / DoneFill. The cards are made
-- once per row; a refresh only re-reads the counts. Once the tool is owned the grid hides. Buy
-- stays locked (SkinLocked, not clickable) until the previous tool, every material and the coins
-- are there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tools = require(Shared:WaitForChild("Config"):WaitForChild("Tools"))
local Materials = require(Shared:WaitForChild("Config"):WaitForChild("Materials"))
local Weapons = require(Shared:WaitForChild("Config"):WaitForChild("Weapons"))
local Worlds = require(Shared:WaitForChild("Config"):WaitForChild("Worlds"))
local Format = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Format"))
local Bonuses = require(Shared:WaitForChild("Config"):WaitForChild("Bonuses"))

local ShopUI = {}

local PANEL_ID = "Weapons"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local PanelWindow: any = nil
local shop: ScreenGui? = nil
local buying = false
-- the open tab: "Weapons" or "Tools"
local tab = "Weapons"

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function isTool(row: Instance): boolean
	return row:GetAttribute("Kind") == "Tool"
end

-- a row's item: a gathering tool for Kind = "Tool" rows, else a weapon
local function defOf(row: Instance): any
	local id = row:GetAttribute("ItemId")
	return if isTool(row) then Tools.get(id) else Weapons.get(id)
end

local function owns(def: any): boolean
	if def.starter then
		return true
	end
	if def.kind then
		return Tools.owned(player)[def.id] == true
	end
	local owned = player:GetAttribute("OwnedWeapons")
	return type(owned) == "string" and ("," .. owned .. ","):find("," .. def.id .. ",", 1, true) ~= nil
end

local function coins(): number
	local value = player:GetAttribute("Coins")
	return if type(value) == "number" then value else 0
end

local function currentWorld(): number
	local value = player:GetAttribute("CurrentWorld")
	return if type(value) == "number" then value else 1
end

local function priceOf(row: Instance, def: any): number
	return def.price or attribute(row, "Price", 0)
end

-- a tool upgrade's ingredients: { icon, have, need } (the previous tool first)
local function ingredients(def: any): { { icon: string, have: number, need: number } }
	local out = {}
	local recipe = def.recipe
	if not recipe then
		return out
	end
	if recipe.tool then
		local prev = Tools.get(recipe.tool)
		table.insert(out, { icon = prev and prev.icon or "", have = Tools.owned(player)[recipe.tool] and 1 or 0, need = 1 })
	end
	local held = Materials.counts(player)
	for _, item in recipe.materials do
		local m = Materials.get(item.id)
		table.insert(out, { icon = m and m.icon or "", have = held[item.id] or 0, need = item.count })
	end
	return out
end

local function recipeMet(def: any): boolean
	for _, item in ingredients(def) do
		if item.have < item.need then
			return false
		end
	end
	return true
end

-- fill a row's upgrade path: the previous tool's tick, and the Recipe grid's cards (made once from
-- Templates/RecipeCard, counts every refresh)
local function fillRecipe(row: Instance, def: any)
	local recipe = def.recipe
	local grid = row:FindFirstChild("Recipe")
	local templates = shop and shop:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("RecipeCard")
	if not (recipe and grid and template) then
		return
	end
	local from = row:FindFirstChild("UpgradeFrom")
	local tick = from and from:FindFirstChild("Owned")
	if tick and tick:IsA("GuiObject") then
		tick.Visible = recipe.tool ~= nil and Tools.owned(player)[recipe.tool] == true
	end
	local owned = owns(def)
	if grid:IsA("GuiObject") then
		grid.Visible = not owned
	end
	local held = Materials.counts(player)
	if grid:GetAttribute("Built") ~= #recipe.materials then
		for _, c in grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, item in recipe.materials do
			local m = Materials.get(item.id)
			local card = template:Clone()
			card.Name = "Card" .. i
			card.LayoutOrder = i
			card.Visible = true
			local icon = card:FindFirstChild("Icon", true)
			if icon and icon:IsA("ImageLabel") then
				icon.Image = m and m.icon or ""
			end
			local name = card:FindFirstChild("ItemName")
			if name and name:IsA("TextLabel") then
				name.Text = m and m.name or item.id
			end
			card.Parent = grid
		end
		grid:SetAttribute("Built", #recipe.materials)
	end
	for i, item in recipe.materials do
		local card = grid:FindFirstChild("Card" .. i)
		if card then
			local have = held[item.id] or 0
			local done = have >= item.count
			local count = card:FindFirstChild("Count")
			if count and count:IsA("TextLabel") then
				count.Text = (attribute(template, "Format", "%s/%s") :: string):format(Format.commas(math.min(have, 9999)), Format.commas(item.count))
				count.TextColor3 = attribute(template, if done then "DoneText" else "ShortText", count.TextColor3)
			end
			local fill = card:FindFirstChild("Fill", true)
			if fill and fill:IsA("GuiObject") then
				fill.Size = UDim2.fromScale(math.clamp(have / item.count, 0, 1), 1)
				fill.Visible = have > 0
				fill.BackgroundColor3 = attribute(template, if done then "DoneFill" else "ShortFill", fill.BackgroundColor3)
			end
		end
	end
end

local WeaponTile = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("WeaponTile"))
-- the 3D view of a weapon (shared with every screen: Util.WeaponTile)
local showWeapon = WeaponTile.showModel

local function rows(): { Instance }
	local list = shop and shop:FindFirstChild("List", true)
	local out = {}
	if list then
		for _, row in list:GetChildren() do
			if type(row:GetAttribute("ItemId")) == "string" then
				table.insert(out, row)
			end
		end
	end
	return out
end

local function styleButton(row: Instance, def: any, balance: number)
	local buy = row:FindFirstChild("Buy")
	if not (buy and buy:IsA("GuiButton")) then
		return
	end
	local skin = buy:FindFirstChild("Skin")
	local coin = buy:FindFirstChild("Coin", true)
	local label = buy:FindFirstChild("Label", true)
	local price = priceOf(row, def)
	local owned = owns(def)
	local look = if owned then "SkinOwned" elseif balance >= price and recipeMet(def) then "SkinBuy" else "SkinLocked"
	if skin and skin:IsA("ImageLabel") then
		skin.Image = attribute(buy, look, skin.Image)
	end
	-- only a buy that can go through is clickable (hover and press: Util.ButtonFx)
	buy.Active = look == "SkinBuy"
	if coin and coin:IsA("GuiObject") then
		coin.Visible = not owned
	end
	if label and label:IsA("TextLabel") then
		if label:GetAttribute("PriceColor") == nil then
			label:SetAttribute("PriceColor", label.TextColor3)
		end
		local stroke = label:FindFirstChildOfClass("UIStroke")
		label.Text = if owned then attribute(buy, "OwnedText", "Owned") else Format.coins(price)
		label.TextColor3 = if owned then attribute(buy, "OwnedTextColor", label.TextColor3)
			elseif look == "SkinLocked" then attribute(buy, "LockedTextColor", label:GetAttribute("PriceColor") :: Color3)
			else label:GetAttribute("PriceColor") :: Color3
		if stroke then
			stroke.Enabled = not owned
		end
	end
	buy.AutoButtonColor = false
end

-- A weapon row's stat chips come from Config/Weapons (2026-10-20: they were typed by hand and
-- went stale when the health ladder rescaled World 2 and 3's weapons): Dps (the purple chip in
-- front, "15 DPS", WeaponTile.dpsText; 2026-10-22, like the Inventory), Damage, Speed (swings a
-- second, "2.5/s") and Reach, each chip's Content/Value. They show what the player would really
-- swing, with every bonus they have (Config/Bonuses; 2026-10-23, the user), so refresh refills them.
local function fillStats(row: Instance, def: any)
	local function stat(chip: string, text: string)
		local holder = row:FindFirstChild(chip)
		local value = holder and holder:FindFirstChild("Value", true)
		if value and value:IsA("TextLabel") then
			value.Text = text
		end
	end
	local swing = Bonuses.weapon(player, def)
	stat("Dps", WeaponTile.dpsText(def))
	stat("Damage", Format.commas(math.floor((swing.damage or 0) + 0.5)))
	stat("Speed", (("%.1f"):format(1 / (swing.cooldown or 1)):gsub("%.0$", "")) .. "/s")
	stat("Reach", (("%.1f"):format(swing.reach or 0):gsub("%.0$", "")))
end

local function refresh()
	if not shop then
		return
	end
	local balance = coins()
	local coinsPill = shop:FindFirstChild("Coins", true)
	local amount = coinsPill and coinsPill:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		amount.Text = Format.coins(balance)
	end
	local world = currentWorld()
	-- the header pill names the world whose stall this is (as the Crafter's does)
	local info = Worlds.get(world)
	local pill = shop:FindFirstChild("World", true)
	local pillLabel = pill and pill:FindFirstChild("Label")
	if info and pillLabel and pillLabel:IsA("TextLabel") then
		pillLabel.Text = ("World %d · %s"):format(info.id, (info.name:gsub("^The ", "")))
	end
	for _, row in rows() do
		local def = defOf(row)
		if def then
			styleButton(row, def, balance)
			if isTool(row) then
				fillRecipe(row, def)
			else
				fillStats(row, def)
			end
		end
		if row:IsA("GuiObject") then
			row.Visible = def ~= nil and (def.world or 1) == world and isTool(row) == (tab == "Tools")
		end
	end
	-- the tabs: the open one in the selected colours
	local tabs = shop:FindFirstChild("Tabs", true)
	for _, button in tabs and tabs:GetChildren() or {} do
		local name = button:GetAttribute("Tab")
		if button:IsA("GuiButton") and type(name) == "string" then
			local on = name == tab
			button:SetAttribute("Selected", on) -- the open tab stays grown (Util.ButtonFx)
			button.BackgroundColor3 = attribute(shop, if on then "TabSelectedFill" else "TabIdleFill", button.BackgroundColor3)
			local label = button:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				label.TextColor3 = attribute(shop, if on then "TabSelectedText" else "TabIdleText", label.TextColor3)
			end
		end
	end
end

local function wire(gui: ScreenGui)
	shop = gui
	for _, row in rows() do
		local id = row:GetAttribute("ItemId") :: string
		-- the shared tile in the Art slot (its own name and damage pill are hidden:
		-- the row shows them)
		local art = row:FindFirstChild("Art")
		local def = defOf(row)
		if art and art:IsA("ImageLabel") and def and not art:FindFirstChild(id) then
			art.ImageTransparency = 1
			local old = art:FindFirstChild("Icon")
			if old then
				old.Visible = false
			end
			local tile = WeaponTile.new(def, { name = false, stat = false, statText = "" })
			if tile then
				-- centred, so its hover grows round its middle (Util.ButtonFx)
				tile.AnchorPoint = Vector2.new(0.5, 0.5)
				tile.Position = UDim2.fromScale(0.5, 0.5)
				tile.Size = UDim2.fromScale(1, 1)
				tile.Parent = art
			end
		end
		-- an upgrade's path: the previous tool's tile in UpgradeFrom (the shared tile, like Art)
		local from = row:FindFirstChild("UpgradeFrom")
		local prev = def and def.recipe and def.recipe.tool and Tools.get(def.recipe.tool)
		if from and prev and not from:FindFirstChild(prev.id) then
			local tile = WeaponTile.new(prev, { name = false, stat = false, statText = "" })
			if tile then
				tile.Name = prev.id
				tile.AnchorPoint = Vector2.new(0.5, 0.5)
				tile.Position = UDim2.fromScale(0.5, 0.5)
				tile.Size = UDim2.fromScale(1, 1)
				tile.Parent = from
			end
			local text = row:FindFirstChild("FromText")
			if text and text:IsA("TextLabel") then
				text.Text = (attribute(text, "Format", "Upgrades your %s") :: string):format(prev.name)
			end
		end
		local buy = row:FindFirstChild("Buy")
		if buy and buy:IsA("GuiButton") then
			buy.Activated:Connect(function()
				local def = defOf(row)
				if buying or not def or not def.price or owns(def) or coins() < def.price or not recipeMet(def) then
					return
				end
				buying = true
				local remote = if isTool(row) then "BuyTool" else "BuyWeapon"
				local ok, bought = pcall(function()
					return Remotes.getFunction(remote):InvokeServer(id)
				end)
				buying = false
				if not ok then
					warn("[ShopUI] " .. remote .. " failed: " .. tostring(bought))
				end
				UiSound.play(if ok and bought == true then "Purchase" else "Refuse")
				refresh()
			end)
		end
	end
	player:GetAttributeChangedSignal("Coins"):Connect(refresh)
	player:GetAttributeChangedSignal("OwnedWeapons"):Connect(refresh)
	player:GetAttributeChangedSignal("OwnedTools"):Connect(refresh)
	player:GetAttributeChangedSignal("Materials"):Connect(refresh)
	local tabs = gui:FindFirstChild("Tabs", true)
	for _, button in tabs and tabs:GetChildren() or {} do
		local name = button:GetAttribute("Tab")
		if button:IsA("GuiButton") and type(name) == "string" then
			button.Activated:Connect(function()
				tab = name
				refresh()
			end)
		end
	end
	player:GetAttributeChangedSignal("CurrentWorld"):Connect(refresh)
	for _, name in Bonuses.Watch do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	gui:GetPropertyChangedSignal("Enabled"):Connect(refresh)
	refresh()
end

function ShopUI.init(injected: any)
	PanelWindow = injected.UI.PanelWindow
end

function ShopUI.start()
	task.spawn(function()
		local gui = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if gui then
			wire(gui)
		else
			warn("[ShopUI] no Weapons shop panel (StarterGui/WeaponsShop)")
		end
	end)
end

return ShopUI
