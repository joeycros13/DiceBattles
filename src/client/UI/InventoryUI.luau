--!strict
-- InventoryUI: wires up the hand-built Inventory window and the HUD's touch
-- Attack button and hit flash. Nothing here creates UI from scratch.
--
-- Inventory (StarterGui/Inventory, a PanelWindow panel):
--   * Equipment (left): the Weapon and Armor sockets (Inventory B on the Crafting &
--     Armor canvas, 2026-10-12: armour is one item, so the Helmet / Chestplate /
--     Legs slots went), each showing what's equipped in Inner/Picture on its
--     rarity tile (Inner/RarityTile) or its placeholder SlotIcon, and
--     CharacterView, a WorldModel holding a live copy of the player that
--     PlayerAnimator idles and WeaponController poses with the weapon in hand. The
--     copy is rebuilt when the window opens, when the weapon changes and when the
--     worn armour model on the character changes.
--   * Items (right): shared WeaponTiles (Util.WeaponTile) for every owned weapon
--     (OwnedWeapons, MeleeService), owned armour set (OwnedArmor, ArmorService) and
--     material held (Materials, MaterialService), plus every gathering tool owned
--     (OwnedTools, ToolService; 2026-10-19), sorted by rarity (highest first),
--     then type (weapons, tools, armour, materials), then strength. The selected
--     weapon and the worn set get the EquippedBadge; clicking a weapon puts it in
--     hand, clicking a set wears it (again takes it off: Remotes.EquipArmor). Tool
--     tiles only show what is owned (the user's call): tools come out of their hotbar
--     slot, which always holds the best one of its kind.
--   * Damage / Health / Defense cards under the character, and the header's Capacity pill:
--     how many different things are held (its Format, "%s Items"; 2026-10-20, the user: a
--     count, not a "35 / 50" bag size).
--   * Potions (Config/Potions, 2026-10-19): one tile per potion held ("×3"). Clicking one
--     opens the tile's hand-built DrinkMenu (the user's pick, option A on the Potions UI
--     canvas): Effect (what it does), Drink (Remotes.DrinkPotion) and Cancel. A refusal
--     shows on Effect in words (full health, a stronger one running, the Health cooldown
--     from the DrinkMenu's CooldownText and the "PotionHealReady" attribute).
--   * TopBar: the Filter dropdown (All / Weapons / Tools / Armor / Potions / Materials) and the
--     SearchBox (matches names) narrow the grid.
--   * BottomBar: Equip Best equips the highest-DPS weapon (WeaponTile.dps) and the highest-defense
--     set owned. Sell Mode (2026-10-20: everything sells but quest items and cores,
--     Config/Sell) makes clicks pick tiles instead (SellMark + Sell* rim) and each tile's
--     pill shows what it sells for (the template's SellFormat, or NoSellText for what
--     can't be sold). A weapon, tool or set is picked by a click; a potion or material
--     opens the tile's hand-built SellMenu to choose how many (Title, Minus, Count (a
--     TextBox), Plus, All, Worth (WorthFormat), Pick, Cancel) and its pill then reads
--     "12 / 40" (PickedFormat). Picking a Legendary or rarer weapon, tool or set first asks
--     on the tile (2026-10-20, the user): its hand-built ConfirmMenu (Title "Are you sure?",
--     Worth (WorthFormat), Yes, Cancel); Yes picks it. With anything picked, BottomBar/SellWorth shows the coins
--     (Icon, Amount, Format) and the Sell button sells it all (Remotes.SellItems,
--     SellService). The Hint reads its Text_Sell attribute while Sell Mode is on.
-- Looks that change with state come from attributes on the template / buttons.
--
-- HUD (WeaponHud): "Attack" is shown on touch screens only; getting hit flashes
-- "HitFlash" (PeakTransparency / FadeSeconds) and pops the damage over the
-- player's head. The camera doesn't shake (the user's call, 2026-10-09).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Armor = require(Config:WaitForChild("Armor"))
local Bonuses = require(Config:WaitForChild("Bonuses"))
local Potions = require(Config:WaitForChild("Potions"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Materials = require(Config:WaitForChild("Materials"))
local Potions = require(Config:WaitForChild("Potions"))
local Sell = require(Config:WaitForChild("Sell"))
local Tools = require(Config:WaitForChild("Tools"))
local Weapons = require(Config:WaitForChild("Weapons"))

local InventoryUI = {}

local deps: any = nil
local DamagePopup: any = nil
local PanelWindow: any = nil
local WeaponController: any = nil
local PlayerAnimator: any = nil
local sellRemote: RemoteFunction? = nil
local armorRemote: RemoteEvent? = nil

local PANEL_ID = "Inventory"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

-- What each filter option shows.
local FILTER_SHOWS: { [string]: { weapons: boolean?, tools: boolean?, armor: boolean?, potions: boolean?, materials: boolean? } } = {
	All = { weapons = true, tools = true, armor = true, potions = true, materials = true },
	Weapons = { weapons = true },
	Tools = { tools = true },
	Armor = { armor = true },
	Potions = { potions = true },
	Materials = { materials = true },
}
local EMPTY_TEXT: { [string]: string } = {
	All = "Nothing here yet",
	Weapons = "No weapons",
	Tools = "No tools yet: buy them at the Weaponsmith",
	Armor = "No armor yet",
	Potions = "No potions yet: brew them at the Crafter",
	Materials = "No materials yet",
}

local panel: ScreenGui? = nil
local hud: ScreenGui? = nil

local filter = "All"
local openPotion: string? = nil -- the potion whose tile shows its DrinkMenu
local drinking = false
local drinkNote: { [string]: string } = {} -- a refusal shown on that potion's Effect line
local query = ""
local sellMode = false
-- what Sell Mode has picked, by "<kind>:<id>"; stacks carry how many
type Pick = { kind: string, id: string, count: number }
local picks: { [string]: Pick } = {}
local openStack: string? = nil -- the potion / material whose tile shows its SellMenu
local openConfirm: string? = nil -- the Legendary+ tile asking "Are you sure?" before it is picked
-- picking anything this rare or rarer asks first (Weapons.Rarities order)
local CONFIRM_FROM = table.find(Weapons.Rarities, "Legendary") or 5
local selling = false

local preview: Model? = nil

-- ==================== helpers ====================

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function find(name: string, className: string): any
	local found = panel and panel:FindFirstChild(name, true)
	return if found and found:IsA(className) then found else nil
end

-- A button's visible text lives in its "Label" child (so the button's gradient
-- doesn't tint it); fall back to the button's own Text.
local function setButtonText(button: Instance?, value: string)
	if not button then
		return
	end
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = value
	elseif button:IsA("TextButton") then
		button.Text = value
	end
end

local WeaponTile = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("WeaponTile"))
local Format = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Format"))

local function ownedWeapons(): { Weapons.WeaponDef }
	local list: { Weapons.WeaponDef } = {}
	local owned = player:GetAttribute("OwnedWeapons")
	if type(owned) == "string" then
		for id in owned:gmatch("[^,]+") do
			local def = Weapons.get(id)
			if def and not def.unarmed then
				table.insert(list, def)
			end
		end
	end
	-- best first by damage per second as it swings (the Worldheart Blade's tier counted), so
	-- Equip Best takes the fastest killer, not the hardest single hit
	table.sort(list, function(a, b)
		local da, db = WeaponTile.dps(a), WeaponTile.dps(b)
		return if da == db then a.order < b.order else da > db
	end)
	return list
end

-- Owned armour sets, best defense first.
local function ownedArmor(): { Armor.ArmorDef }
	local list: { Armor.ArmorDef } = {}
	local owned = player:GetAttribute("OwnedArmor")
	for id in (if type(owned) == "string" then owned else ""):gmatch("[^,]+") do
		local def = Armor.get(id)
		if def then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		return if a.defense == b.defense then a.order < b.order else a.defense > b.defense
	end)
	return list
end

local function wornArmor(): Armor.ArmorDef?
	return Armor.get(player:GetAttribute("EquippedArmor"))
end

-- ==================== items grid ====================

local renderGrid: () -> ()

type GridEntry = { kind: string, def: any, rank: number, typeRank: number, strength: number }

-- How many lines are picked, and the coins they come to.
local function pickTotals(): (number, number)
	local n, coins = 0, 0
	for _, pick in picks do
		n += 1
		coins += (Sell.price(pick.kind, pick.id) or 0) * pick.count
	end
	return n, coins
end

local function renderButtons()
	local count, coins = pickTotals()
	local sellButton = find("SellButton", "GuiButton")
	if sellButton then
		sellButton.Visible = sellMode and count > 0
		setButtonText(sellButton, (attribute(sellButton, "TextFormat", "Sell (%d)") :: string):format(count))
	end
	local worth = find("SellWorth", "GuiObject")
	if worth then
		worth.Visible = sellMode and count > 0
		local amount = worth:FindFirstChild("Amount", true)
		if amount and amount:IsA("TextLabel") then
			amount.Text = (attribute(worth, "Format", "+%s") :: string):format(Format.coins(coins))
		end
	end
	local modeButton = find("SellMode", "GuiButton")
	if modeButton then
		setButtonText(modeButton, attribute(modeButton, if sellMode then "ActiveText" else "Text", "Sell Mode"))
	end
end

-- The Weapon / Armor sockets: the equipped item's rarity tile and icon, filling the whole
-- socket (Inner/RarityTile is sized past Inner to the socket's edge, and the socket's own
-- dashed Skin hides under it; 2026-10-22, the user), or the placeholder Skin + SlotIcon.
-- A weapon is always selected (the Dagger at least), so only the Armor socket ever shows
-- its placeholder.
local function renderSockets()
	local equipment = find("Equipment", "GuiObject")
	local current = WeaponController.selected()
	local worn = wornArmor()
	for _, pair in { { "Weapon", current :: any }, { "Armor", worn :: any } } do
		local slot, def = pair[1], pair[2]
		local socket = equipment and equipment:FindFirstChild(slot)
		local inner = socket and socket:FindFirstChild("Inner")
		local picture = inner and inner:FindFirstChild("Picture")
		local placeholder = inner and inner:FindFirstChild("SlotIcon")
		local rarityTile = inner and inner:FindFirstChild("RarityTile")
		local icon = def and def.icon
		if rarityTile and rarityTile:IsA("ImageLabel") then
			rarityTile.Visible = def ~= nil
			rarityTile.Image = if def then WeaponTile.skin(def.rarity) else ""
		end
		if picture and picture:IsA("ImageLabel") then
			picture.Visible = icon ~= nil
			picture.Image = icon or ""
		end
		if placeholder and placeholder:IsA("GuiObject") then
			placeholder.Visible = icon == nil
		end
		local slotSkin = socket and socket:FindFirstChild("Skin")
		if slotSkin and slotSkin:IsA("GuiObject") then
			slotSkin.Visible = def == nil
		end
	end
end

-- The two stat cards beside the window (2026-10-22, option B on
-- https://claude.ai/artifact/6LM4U8XgrVihfD1RrWvCMQ, both on the left as the user asked):
--   Window/WeaponStats  the selected weapon: ItemName, Dps/Value (its DPS, WeaponTile.dps),
--                       Row_Damage / Row_Range / Row_Speed (each Icon + Label + Value; the card's
--                       RangeFormat "%s" studs and SpeedFormat "%s s" per swing)
--   Window/ArmorStats   the worn set: ItemName (EmptyName when none), Row_Health / Row_Defense
--                       (NoneText greyed, the card's Off* colours, while nothing is worn) and
--                       Row_Regen / Row_Speed only when the set has that bonus (2026-10-22, the
--                       user): Speed moves up into Regen's slot, and the card's Face / Lip /
--                       Blocker end under the last row shown (each row's SlotY attribute keeps
--                       its authored spot)
-- Both show the player's real numbers (2026-10-23, the user: every bonus, everywhere but
-- the Index): the weapon after its Worldheart tier, the Attack Speed upgrade and every damage
-- bonus (Config/Bonuses.weapon), the set's health after the Health upgrade.
local function setRow(card: Instance, row: string, value: string, on: boolean)
	local frame = card:FindFirstChild(row, true)
	if not (frame and frame:IsA("GuiObject")) then
		return
	end
	local function colour(name: string, fallback: Color3): Color3
		local c = card:GetAttribute(name)
		return if typeof(c) == "Color3" then c else fallback
	end
	local state = if on then "On" else "Off"
	frame.BackgroundColor3 = colour(state .. "Fill", frame.BackgroundColor3)
	local label = frame:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextColor3 = colour(state .. "Label", label.TextColor3)
	end
	local text = frame:FindFirstChild("Value")
	if text and text:IsA("TextLabel") then
		text.Text = value
		text.TextColor3 = colour(state .. "Value", text.TextColor3)
	end
	-- the row's Upgrades icon (2026-10-22) fades with a greyed row (the card's OffIconTransparency)
	local icon = frame:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		local off = card:GetAttribute("OffIconTransparency")
		icon.ImageTransparency = if on then 0 else (if type(off) == "number" then off else 0.55)
	end
end

local function renderStatCards()
	local weaponCard = find("WeaponStats", "GuiObject")
	if weaponCard then
		local def = WeaponController.selected()
		local swing = def and Bonuses.weapon(player, def)
		local name = weaponCard:FindFirstChild("ItemName", true)
		if name and name:IsA("TextLabel") then
			name.Text = def and def.name or ""
		end
		local dps = weaponCard:FindFirstChild("Dps", true)
		local value = dps and dps:FindFirstChild("Value")
		if value and value:IsA("TextLabel") then
			value.Text = if def then WeaponTile.dpsNumber(def) else "0"
		end
		local range = (weaponCard:GetAttribute("RangeFormat") or "%s") :: string
		local speed = (weaponCard:GetAttribute("SpeedFormat") or "%s s") :: string
		setRow(weaponCard, "Row_Damage", Format.commas(math.floor((swing and swing.damage or 0) + 0.5)), true)
		setRow(weaponCard, "Row_Range", range:format(("%.1f"):format(swing and swing.reach or 0):gsub("%.0$", "")), true)
		setRow(weaponCard, "Row_Speed", speed:format(("%.2f"):format(swing and swing.cooldown or 0):gsub("0$", "")), true)
	end
	local armorCard = find("ArmorStats", "GuiObject")
	if armorCard then
		local set = wornArmor()
		local none = (armorCard:GetAttribute("NoneText") or "None") :: string
		local name = armorCard:FindFirstChild("ItemName", true)
		if name and name:IsA("TextLabel") then
			name.Text = if set then set.name else (armorCard:GetAttribute("EmptyName") or "No armor") :: string
		end
		local function percent(share: number): string
			return (("%.2f"):format(share * 100):gsub("0+$", ""):gsub("%.$", "")) .. "%"
		end
		setRow(armorCard, "Row_Health", if set then "+" .. Format.commas(math.floor(set.health * Bonuses.health(player) + 0.5)) else none, set ~= nil)
		setRow(armorCard, "Row_Defense", if set then percent(set.defense) else none, set ~= nil)
		local regen = set and set.regen or 0
		local fast = set and set.speed or 0
		setRow(armorCard, "Row_Regen", "+" .. percent(regen) .. "/s", true)
		setRow(armorCard, "Row_Speed", "+" .. percent(fast), true)
		-- only the bonuses the set has show, packed up under Defense
		local slots = {}
		for _, name in { "Row_Health", "Row_Defense", "Row_Regen", "Row_Speed" } do
			local row = armorCard:FindFirstChild(name)
			if row and row:IsA("GuiObject") then
				local y = row:GetAttribute("SlotY")
				if type(y) ~= "number" then
					y = row.Position.Y.Scale
					row:SetAttribute("SlotY", y)
				end
				table.insert(slots, { row = row, y = y })
			end
		end
		local shown = { Row_Health = true, Row_Defense = true, Row_Regen = regen > 0, Row_Speed = fast > 0 }
		local slot, bottom = 1, 0
		for _, entry in slots do
			local row = entry.row
			row.Visible = shown[row.Name] == true
			if row.Visible then
				local y = slots[slot].y
				row.Position = UDim2.new(row.Position.X, UDim.new(y, 0))
				bottom = y + row.Size.Y.Scale
				slot += 1
			end
		end
		-- the drawn card ends the same gap under its last row as it was authored with
		local last = slots[#slots]
		if last then
			local pad = 1 - (last.y + last.row.Size.Y.Scale)
			for _, name in { "Face", "Lip", "Blocker" } do
				local piece = armorCard:FindFirstChild(name)
				if piece and piece:IsA("GuiObject") then
					piece.Size = UDim2.new(piece.Size.X, UDim.new(bottom + pad, 0))
				end
			end
		end
	end
end

-- The Damage / Health / Defense cards under the character, and the item count
-- in the header (its Format attribute sets the wording).
local function renderStats(count: number)
	renderStatCards()
	-- the mini cards are the player's own totals: a hit's damage with every bonus, max
	-- health, and the whole damage reduction (armour, Stoneskin and the Defense upgrade
	-- multiply: Config/Bonuses)
	local current = WeaponController.selected()
	local damage = find("DamageValue", "TextLabel")
	if damage then
		local swing = current and Bonuses.weapon(player, current)
		damage.Text = Format.commas(math.floor((swing and swing.damage or 0) + 0.5))
	end
	local health = find("HealthValue", "TextLabel")
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if health then
		health.Text = Format.commas(math.floor((humanoid and humanoid.MaxHealth or 100) + 0.5))
	end
	local defense = find("DefenseValue", "TextLabel")
	if defense then
		local value = player:GetAttribute("ArmorDefense")
		local armour = 1 - math.clamp(if type(value) == "number" then value else 0, 0, 0.9)
		local taken = armour * Potions.multiplier(player, "Stoneskin") * Upgrades.value(player, "Defense")
		defense.Text = math.floor((1 - taken) * 100 + 0.5) .. "%"
	end
	renderSockets()
	local capacity = find("Capacity", "GuiObject")
	local capLabel = capacity and capacity:FindFirstChild("Label")
	if capLabel and capLabel:IsA("TextLabel") then
		capLabel.Text = (attribute(capacity, "Format", "%s Items") :: string):format(Format.commas(count))
	end
end

local Responsive = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Responsive"))

local function styleTile(tile: GuiObject, equipped: boolean, picked: boolean)
	local badge = tile:FindFirstChild("EquippedBadge")
	if badge and badge:IsA("GuiObject") then
		badge.Visible = equipped and not picked
	end
	local rim = tile:FindFirstChild("Rim") or tile:FindFirstChildOfClass("UIStroke")
	if rim and rim:IsA("UIStroke") then
		local prefix = if picked then "SellRim" elseif equipped then "EquippedRim" else "Rim"
		rim.Color = attribute(tile, prefix .. "Color", rim.Color)
		-- the attribute is in reference-screen pixels; Responsive sizes it for this screen
		-- the tile's Rim is a ScaledSize stroke, so <prefix>Thickness is a fraction
		-- of the tile's side (SellRimThickness 0.0238 ~ 4 px on a 1080-high screen)
		local authored = rim:GetAttribute("BaseThickness")
		Responsive.setStroke(rim, attribute(tile, prefix .. "Thickness", if type(authored) == "number" then authored else rim.Thickness))
	end
	local mark = tile:FindFirstChild("SellMark")
	if mark and mark:IsA("GuiObject") then
		mark.Visible = picked
	end
end

-- The grid's canvas follows its UIGridLayout (2026-10-19, user: the bottom row was cut
-- off): AutomaticCanvasSize ignores aspect-ratio cells, like the Index's rows. The gap
-- above the first row and below the last is the same as the gap at the sides (user,
-- 2026-10-19), measured from the tiles. Inside a ScrollingFrame a UIPadding's scale is a
-- share of the CANVAS, so the top / bottom padding is set as gap / canvas.
local function fitCanvas(grid: ScrollingFrame)
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	if not layout then
		return
	end
	-- the left gap: from the grid's edge to the leftmost tile
	local left = math.huge
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			left = math.min(left, child.AbsolutePosition.X)
		end
	end
	local gap = if left < math.huge then math.max(0, left - grid.AbsolutePosition.X) else 0
	local height = math.ceil(layout.AbsoluteContentSize.Y + 2 * gap)
	grid.CanvasSize = UDim2.new(0, 0, 0, height)
	local padding = grid:FindFirstChildOfClass("UIPadding")
	if padding and height > 0 then
		padding.PaddingTop = UDim.new(gap / height, 0)
		padding.PaddingBottom = UDim.new(gap / height, 0)
	end
end

-- Why a drink was refused, in words for the Effect line.
local function refusal(reason: string?): string
	if reason == "full" then
		return "Already at full health"
	elseif reason == "weaker" then
		return "A stronger one is running"
	elseif reason == "cooldown" then
		return "Not yet"
	elseif reason == "dead" then
		return "Not while knocked out"
	end
	return "Can't drink that now"
end

-- ==================== the grid ====================
--
-- Each thing held keeps ONE tile for the session (2026-10-20, the user: switching weapons
-- and killing enemies froze the game for a moment). The grid used to be destroyed and
-- re-cloned on every change, ~70 shared tiles (each with its Drink / Sell / Confirm menus)
-- for a full bag, about 200 ms a time; it ran on every weapon switch and every material
-- drop, open or not. Now a tile is cloned the first time its thing shows, its buttons
-- are wired once and read the tile's state when clicked, and a render only refills
-- what changed, re-orders, and hides the tiles of things no longer shown. Renders are
-- asked for with renderGrid() and run once at the end of the frame.

-- One pooled tile and what its buttons act on.
type TileState = {
	tile: GuiObject,
	key: string,
	kind: string,
	def: any,
	rank: number,
	price: number?,
	stacks: boolean,
	stack: number, -- how many are held (potions / materials)
	count: number, -- the SellMenu's chosen count while it is open
	filled: string?, -- what the tile was last filled with
}
local tiles: { [string]: TileState } = {}
local fillers: { GuiObject } = {}
local renderQueued = false
local doRender: () -> ()

renderGrid = function()
	if renderQueued then
		return
	end
	renderQueued = true
	task.defer(function()
		renderQueued = false
		doRender()
	end)
end

-- Sell Mode picks for a weapon, tool or set: a Legendary or rarer one asks on its
-- ConfirmMenu first, and a click on the tile while it asks closes it again.
local function choose(st: TileState)
	picks[st.key] = { kind = st.kind, id = st.def.id, count = 1 }
	openConfirm = nil
	renderGrid()
end
local function togglePick(st: TileState)
	if not st.price then
		return
	end
	if picks[st.key] then
		picks[st.key] = nil
	elseif openConfirm == st.key then
		openConfirm = nil
	elseif st.rank >= CONFIRM_FROM then
		openConfirm = st.key
	else
		choose(st)
		return
	end
	renderGrid()
end

-- The SellMenu's count and worth, as edited (no re-render until Pick).
local function showSellCount(st: TileState)
	local menu = st.tile:FindFirstChild("SellMenu")
	if not menu then
		return
	end
	st.count = math.clamp(st.count, 1, math.max(1, st.stack))
	local box = menu:FindFirstChild("Count")
	if box and box:IsA("TextBox") then
		box.Text = Format.commas(st.count)
	end
	local worth = menu:FindFirstChild("Worth")
	if worth and worth:IsA("TextLabel") then
		worth.Text = (attribute(menu, "WorthFormat", "%s Coins") :: string):format(Format.coins((st.price or 0) * st.count))
	end
end

-- Wire a new tile's buttons once; they act on `st` as it is when clicked.
local function wireTile(st: TileState)
	local tile = st.tile
	local function on(parent: Instance?, name: string, action: () -> ())
		local button = parent and parent:FindFirstChild(name)
		if button and button:IsA("GuiButton") then
			button.Activated:Connect(action)
		end
	end
	if tile:IsA("GuiButton") then
		tile.Activated:Connect(function()
			if sellMode then
				if st.stacks then
					-- a potion or material opens its SellMenu to choose how many
					if st.price then
						openStack = if openStack == st.key then nil else st.key
						renderGrid()
					end
				else
					togglePick(st)
				end
			elseif st.kind == "weapon" then
				WeaponController.equip(st.def.id)
			elseif st.kind == "armor" then
				-- clicking wears the set, or takes it off
				if armorRemote then
					armorRemote:FireServer(st.def.id)
				end
			elseif st.kind == "potion" then
				-- a potion opens its DrinkMenu
				openPotion = if openPotion == st.def.id then nil else st.def.id
				drinkNote[st.def.id] = nil
				renderGrid()
			end
			-- outside Sell Mode a tool tile does nothing (user, 2026-10-19): tools are taken
			-- out from their hotbar slot, which always holds the best one of its kind
		end)
	end
	if not st.stacks then
		local confirm = tile:FindFirstChild("ConfirmMenu")
		on(confirm, "Yes", function()
			choose(st)
		end)
		on(confirm, "Cancel", function()
			openConfirm = nil
			renderGrid()
		end)
	end
	if st.kind == "potion" then
		local menu = tile:FindFirstChild("DrinkMenu")
		on(menu, "Cancel", function()
			openPotion = nil
			drinkNote[st.def.id] = nil
			renderGrid()
		end)
		on(menu, "Drink", function()
			if drinking then
				return
			end
			drinking = true
			local id = st.def.id
			local ok, okDrink, reason = pcall(function()
				return deps.Remotes.getFunction("DrinkPotion"):InvokeServer(id)
			end)
			drinking = false
			UiSound.play(if ok and okDrink then "Drink" else "Refuse")
			if ok and okDrink then
				openPotion = nil
				drinkNote[id] = nil
				-- a healing potion: + signs off the body and a green edge glow (HurtController)
				local drunk = Potions.get(id)
				if drunk and drunk.kind == "Health" and deps.Controllers.HurtController then
					deps.Controllers.HurtController.healed()
				end
			else
				drinkNote[id] = refusal(if ok then reason else nil)
			end
			renderGrid()
		end)
	end
	if st.stacks then
		local menu = tile:FindFirstChild("SellMenu")
		on(menu, "Minus", function()
			st.count -= 1
			showSellCount(st)
		end)
		on(menu, "Plus", function()
			st.count += 1
			showSellCount(st)
		end)
		on(menu, "All", function()
			st.count = st.stack
			showSellCount(st)
		end)
		local box = menu and menu:FindFirstChild("Count")
		if box and box:IsA("TextBox") then
			box.FocusLost:Connect(function()
				local typed = tonumber((box.Text:gsub("[^%d]", "")))
				if typed then
					st.count = typed
				end
				showSellCount(st)
			end)
		end
		on(menu, "Pick", function()
			picks[st.key] = { kind = st.kind, id = st.def.id, count = st.count }
			openStack = nil
			renderGrid()
		end)
		on(menu, "Cancel", function()
			openStack = nil
			renderGrid()
		end)
	end
end

-- The menus on a tile: the potion's DrinkMenu, the SellMenu of a stack, a set's or
-- weapon's ConfirmMenu.
local function renderMenus(st: TileState)
	local tile, def = st.tile, st.def
	local confirm = tile:FindFirstChild("ConfirmMenu")
	if confirm and confirm:IsA("GuiObject") then
		confirm.Visible = not st.stacks and sellMode and openConfirm == st.key
		local worth = confirm:FindFirstChild("Worth")
		if confirm.Visible and worth and worth:IsA("TextLabel") and st.price then
			worth.Text = (attribute(confirm, "WorthFormat", "%s Coins") :: string):format(Format.coins(st.price))
		end
	end
	local drink = tile:FindFirstChild("DrinkMenu")
	if drink and drink:IsA("GuiObject") then
		drink.Visible = st.kind == "potion" and openPotion == def.id and not sellMode
		local effect = drink:FindFirstChild("Effect")
		if drink.Visible and effect and effect:IsA("TextLabel") then
			local text = drinkNote[def.id] or Potions.describe(def)
			local ready = player:GetAttribute("PotionHealReady")
			if def.kind == "Health" and not drinkNote[def.id] and type(ready) == "number" then
				local left = math.ceil(ready - workspace:GetServerTimeNow())
				if left > 0 then
					text = (attribute(drink, "CooldownText", "Ready in %ds") :: string):format(left)
				end
			end
			effect.Text = text
		end
	end
	local sell = tile:FindFirstChild("SellMenu")
	if sell and sell:IsA("GuiObject") then
		local open = st.stacks and st.price ~= nil and openStack == st.key
		if open and not sell.Visible then
			-- opening: start from what is picked, or 1
			local pick = picks[st.key]
			st.count = if pick then pick.count else 1
		end
		sell.Visible = open
		if open then
			showSellCount(st)
		end
	end
end

doRender = function()
	local grid = find("Grid", "ScrollingFrame")
	if not grid then
		return
	end
	-- it renders while closed too: with the tiles kept that costs little, and a new
	-- thing's tile is ready before the window opens (no tiles appearing on open)
	-- The hotbar's weapon counts as equipped, in hand or put away.
	local current = WeaponController.selected()
	local shown = 0
	local owned = ownedWeapons()
	local sets = ownedArmor()
	local shows = FILTER_SHOWS[filter] or FILTER_SHOWS.All
	local needle = query:lower()
	local function matches(name: string): boolean
		return needle == "" or name:lower():find(needle, 1, true) ~= nil
	end
	-- Everything shown, sorted by rarity (highest first), then type (weapons, armour,
	-- materials), then strength (user, 2026-10-12).
	local entries: { GridEntry } = {}
	local function rank(rarity: string?): number
		return table.find(Weapons.Rarities, rarity or "Common") or 1
	end
	if shows.weapons then
		for _, def in owned do
			if matches(def.name) then
				table.insert(entries, { kind = "weapon", def = def, rank = rank(def.rarity), typeRank = 1, strength = WeaponTile.dps(def) })
			end
		end
	end
	if shows.tools then
		for id in Tools.owned(player) do
			local def = Tools.get(id)
			if def and matches(def.name) then
				table.insert(entries, { kind = "tool", def = def, rank = rank(def.rarity), typeRank = 2, strength = def.tier })
			end
		end
	end
	if shows.armor then
		for _, def in sets do
			if matches(def.name) then
				table.insert(entries, { kind = "armor", def = def, rank = rank(def.rarity), typeRank = 3, strength = def.defense })
			end
		end
	end
	local held = Potions.counts(player)
	if shows.potions then
		for _, def in Potions.list() do
			if (held[def.id] or 0) > 0 and matches(def.name) then
				table.insert(entries, { kind = "potion", def = def, rank = rank(def.rarity), typeRank = 4, strength = def.tier * 10 - def.order % 10 })
			end
		end
	end
	if openPotion and (held[openPotion] or 0) <= 0 then
		openPotion = nil
	end
	local counts = Materials.counts(player)
	-- picks of things no longer held go; stacks shrink to what is left
	local ownedTools = Tools.owned(player)
	local function holds(pick: Pick): number
		if pick.kind == "weapon" then
			for _, def in owned do
				if def.id == pick.id then
					return 1
				end
			end
			return 0
		elseif pick.kind == "tool" then
			return if ownedTools[pick.id] then 1 else 0
		elseif pick.kind == "armor" then
			for _, set in sets do
				if set.id == pick.id then
					return 1
				end
			end
			return 0
		end
		return (if pick.kind == "potion" then held else counts)[pick.id] or 0
	end
	for key, pick in picks do
		local have = holds(pick)
		if have <= 0 then
			picks[key] = nil
		else
			pick.count = math.min(pick.count, have)
		end
	end
	if openStack and not sellMode then
		openStack = nil
	end
	if openConfirm and not sellMode then
		openConfirm = nil
	end
	if shows.materials then
		for _, def in Materials.list() do
			if (counts[def.id] or 0) > 0 and matches(def.name) then
				table.insert(entries, { kind = "material", def = def, rank = rank(def.rarity), typeRank = 5, strength = -(def.world * 100 + def.order) })
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		if a.typeRank ~= b.typeRank then
			return a.typeRank < b.typeRank
		end
		if a.strength ~= b.strength then
			return a.strength > b.strength
		end
		return a.def.name < b.def.name
	end)

	local worn = wornArmor()
	local noSell: string = WeaponTile.attribute("NoSellText", "Can't sell")
	-- the Worldheart Blade's pill follows the cores infused, so a refill keys on them too
	local cores = tostring(player:GetAttribute("InfusedCores"))
	local seen: { [string]: boolean } = {}
	for order, entry in entries do
		local def = entry.def
		-- the shared tile (ReplicatedStorage/Assets/UI/WeaponTile, Util.WeaponTile): rarity
		-- skin, drawn icon, name and its pill ("50 Dmg", "10% Def", "×12")
		local key = entry.kind .. ":" .. def.id
		local pick = picks[key]
		local price = Sell.price(entry.kind, def.id)
		local stacks = Sell.Stacks[entry.kind] == true
		local stack = if entry.kind == "potion" then held[def.id] or 0 elseif entry.kind == "material" then counts[def.id] or 0 else 0
		local statText: string? = nil
		if sellMode and not price then
			statText = noSell
		elseif sellMode and stacks and pick then
			statText = (WeaponTile.attribute("PickedFormat", "%s / %s") :: string):format(Format.commas(pick.count), Format.commas(stack))
		elseif sellMode and not stacks then
			-- what it sells for
			statText = (WeaponTile.attribute("SellFormat", "%s Coins") :: string):format(Format.coins(price :: number))
		elseif entry.kind == "tool" then
			statText = ("Tier %d"):format(def.tier)
		elseif entry.kind == "armor" then
			statText = math.floor(def.defense * 100 + 0.5) .. "% Def"
		elseif stacks then
			statText = "×" .. Format.commas(stack)
		end
		local filled = (statText or "") .. "|" .. cores
		local st = tiles[key]
		if not st then
			local tile = WeaponTile.new(def, if statText then { statText = statText } else nil)
			if not tile then
				continue
			end
			local fresh: TileState = {
				tile = tile,
				key = key,
				kind = entry.kind,
				def = def,
				rank = entry.rank,
				price = price,
				stacks = stacks,
				stack = stack,
				count = 1,
				filled = filled,
			}
			tiles[key] = fresh
			wireTile(fresh)
			tile.Parent = grid
			st = fresh
		end
		local state = st :: TileState
		state.def, state.rank, state.price, state.stacks, state.stack = def, entry.rank, price, stacks, stack
		if state.filled ~= filled then
			state.filled = filled
			WeaponTile.fill(state.tile, def, if statText then { statText = statText } else nil)
		end
		seen[key] = true
		shown += 1
		state.tile.LayoutOrder = order
		state.tile.Visible = true
		local picked = sellMode and pick ~= nil
		local equipped = (entry.kind == "weapon" and current ~= nil and current.id == def.id)
			or (entry.kind == "armor" and worn ~= nil and worn.id == def.id)
		styleTile(state.tile, equipped, picked)
		renderMenus(state)
	end
	-- the tiles of things not shown now (filtered out, sold, used up) wait hidden
	for key, st in tiles do
		if not seen[key] then
			st.tile.Visible = false
		end
	end

	-- pad the grid with empty slots: at least MinSlots, and always whole rows
	local slotTemplate = panel and panel:FindFirstChild("Templates") and panel.Templates:FindFirstChild("EmptySlot")
	if slotTemplate and slotTemplate:IsA("GuiObject") then
		local columns = attribute(grid, "Columns", 5)
		local total = math.max(attribute(grid, "MinSlots", 15), math.ceil(shown / columns) * columns)
		local need = total - shown
		while #fillers < need do
			local filler = slotTemplate:Clone()
			filler.Parent = grid
			table.insert(fillers, filler)
		end
		for i, filler in fillers do
			filler.LayoutOrder = 10000 + i
			filler.Visible = i <= need
		end
	end
	-- every different thing held, whatever the filter shows
	local items = #owned + #sets
	for _ in Tools.owned(player) do
		items += 1
	end
	for _, list in { held, counts } do
		for _, n in list do
			if n > 0 then
				items += 1
			end
		end
	end
	renderStats(items)

	-- the hint line under the cards: its Text_<filter> attribute, else as authored
	local hint = find("Hint", "TextLabel")
	if hint then
		if hint:GetAttribute("DefaultText") == nil then
			hint:SetAttribute("DefaultText", hint.Text)
		end
		hint.Text = if sellMode then attribute(hint, "Text_Sell", "Pick what to sell.") else attribute(hint, "Text_" .. filter, hint:GetAttribute("DefaultText"))
	end
	renderButtons()

	local empty = find("Empty", "TextLabel")
	if empty then
		empty.Visible = shown == 0
		empty.Text = if query ~= "" then "No matches" else (EMPTY_TEXT[filter] or "Nothing here yet")
	end
end

local function setSellMode(on: boolean)
	sellMode = on
	table.clear(picks)
	openStack = nil
	openConfirm = nil
	openPotion = nil
	renderGrid()
end

-- ==================== character preview ====================

local function clearPreview()
	if preview then
		PlayerAnimator.untrack(preview)
		WeaponController.untrack(preview)
		preview:Destroy()
		preview = nil
	end
end

-- A posed copy of the player, holding the current weapon, in CharacterView.
local function buildPreview()
	clearPreview()
	local view = find("CharacterView", "ViewportFrame")
	local world = view and view:FindFirstChildOfClass("WorldModel")
	local character = player.Character
	if not (view and world and character and character:FindFirstChild("HumanoidRootPart")) then
		return
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = wasArchivable
	if not copy then
		return
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local root = copy:FindFirstChild("HumanoidRootPart") :: BasePart
	copy.PrimaryPart = root
	root.Anchored = true
	copy:PivotTo(CFrame.new(0, 0, 0))
	copy.Parent = world
	preview = copy

	local camera = view:FindFirstChildOfClass("Camera") or Instance.new("Camera")
	camera.FieldOfView = 38
	-- Front three-quarter view; characters face -Z.
	camera.CFrame = CFrame.lookAt(Vector3.new(-3.6, 0.5, -11.2), Vector3.new(0, -0.2, 0))
	camera.Parent = view
	view.CurrentCamera = camera

	PlayerAnimator.track(copy)
	WeaponController.track(copy)
end

-- ==================== wiring ====================

local function wirePanel(gui: ScreenGui)
	panel = gui

	-- the stat cards' Luckiest Guy words sit centred in their boxes (Util.FontDrop)
	for _, name in { "WeaponStats", "ArmorStats" } do
		local card = gui:FindFirstChild(name, true)
		if card and deps.Util.FontDrop then
			deps.Util.FontDrop.watch(card)
		end
	end

	local grid = find("Grid", "ScrollingFrame")
	local gridLayout = grid and grid:FindFirstChildOfClass("UIGridLayout")
	if grid and gridLayout then
		gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			fitCanvas(grid)
		end)
		grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fitCanvas(grid)
		end)
	end

	-- Filter dropdown.
	local filterButton = find("Filter", "GuiButton")
	local options = find("Options", "GuiObject")
	if filterButton and options then
		options.Visible = false
		filterButton.Activated:Connect(function()
			options.Visible = not options.Visible
		end)
		for _, option in options:GetChildren() do
			local value = option:GetAttribute("Filter")
			if option:IsA("GuiButton") and type(value) == "string" then
				option.Activated:Connect(function()
					filter = value
					options.Visible = false
					setButtonText(filterButton, value)
					renderGrid()
				end)
			end
		end
	end

	local search = find("SearchBox", "TextBox")
	if search then
		search:GetPropertyChangedSignal("Text"):Connect(function()
			query = search.Text
			renderGrid()
		end)
	end

	local equipBest = find("EquipBest", "GuiButton")
	if equipBest then
		equipBest.Activated:Connect(function()
			local best = ownedWeapons()[1]
			if best then
				WeaponController.equip(best.id)
			end
			local bestSet = ownedArmor()[1]
			local worn = wornArmor()
			if bestSet and armorRemote and not (worn and worn.id == bestSet.id) then
				armorRemote:FireServer(bestSet.id)
			end
		end)
	end
	local modeButton = find("SellMode", "GuiButton")
	if modeButton then
		modeButton.Activated:Connect(function()
			setSellMode(not sellMode)
		end)
	end
	local sellButton = find("SellButton", "GuiButton")
	if sellButton then
		sellButton.Activated:Connect(function()
			if selling or not sellRemote then
				return
			end
			local lines = {}
			for _, pick in picks do
				table.insert(lines, { kind = pick.kind, id = pick.id, count = pick.count })
			end
			if #lines == 0 then
				return
			end
			selling = true
			local remote = sellRemote :: RemoteFunction
			local ok, sold = pcall(function()
				return remote:InvokeServer(lines)
			end)
			UiSound.play(if ok and sold == true then "Purchase" else "Refuse")
			selling = false
			setSellMode(false)
		end)
	end

	-- The preview lives only while the window is open.
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			buildPreview()
			renderGrid()
		else
			clearPreview()
			if options then
				options.Visible = false
			end
			if sellMode then
				setSellMode(false)
			end
		end
	end)

	-- the Worldheart Blade's damage grows with each core infused
	player:GetAttributeChangedSignal("InfusedCores"):Connect(function()
		if gui.Enabled then
			renderGrid()
		end
	end)

	-- renderGrid also drops picks of anything no longer held
	for _, name in { "OwnedWeapons", "OwnedArmor", "EquippedArmor", "Materials", "OwnedTools", "Potions" } do
		player:GetAttributeChangedSignal(name):Connect(renderGrid)
	end
	-- every bonus the shown stats include (an upgrade bought, a potion starting or ending...)
	for _, name in Bonuses.Watch do
		player:GetAttributeChangedSignal(name):Connect(renderGrid)
	end
	player:GetAttributeChangedSignal("PotionTier_Stoneskin"):Connect(renderGrid)
	player:GetAttributeChangedSignal(Upgrades.attr("Defense")):Connect(renderGrid)
	-- the max-health change lands just after the armour's own attributes
	player:GetAttributeChangedSignal("ArmorHealth"):Connect(function()
		task.delay(0.1, renderGrid)
	end)
	-- the preview copies the character, so rebuild it when the worn armour model
	-- (ArmorService puts it on as "Armor") arrives or goes. The model's pieces can
	-- reach the client over several frames, so wait until its "Pieces" count is
	-- all there (up to 2 s) before copying; a newer switch cancels an older wait
	-- (2026-10-12: switching sets sometimes showed a set with pieces missing).
	local armorToken = 0
	local function piecesIn(model: Instance): number
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end
	local function watchArmor(character: Model)
		local function changed(child: Instance)
			if child.Name ~= "Armor" or not gui.Enabled then
				return
			end
			armorToken += 1
			local token = armorToken
			task.spawn(function()
				local worn = character:FindFirstChild("Armor")
				local want = worn and worn:GetAttribute("Pieces")
				if worn and type(want) == "number" then
					local deadline = os.clock() + 2
					while token == armorToken and worn.Parent == character and piecesIn(worn) < want and os.clock() < deadline do
						task.wait()
					end
				end
				task.wait() -- one more frame for the welds to settle the pieces onto the limbs
				if token == armorToken and gui.Enabled then
					buildPreview()
				end
			end)
		end
		character.ChildAdded:Connect(changed)
		character.ChildRemoved:Connect(changed)
	end
	player.CharacterAdded:Connect(watchArmor)
	if player.Character then
		watchArmor(player.Character)
	end
	WeaponController.onChanged(function()
		renderGrid()
		if gui.Enabled then
			-- Wait a beat for the new weapon model to arrive on the character.
			task.delay(0.15, function()
				if gui.Enabled then
					buildPreview()
				end
			end)
		end
	end)

	renderGrid()
end

-- ==================== HUD ====================

local function flashHit()
	local flash = hud and hud:FindFirstChild("HitFlash")
	if not (flash and flash:IsA("GuiObject")) then
		return
	end
	flash.BackgroundTransparency = attribute(flash, "PeakTransparency", 0.45)
	TweenService:Create(flash, TweenInfo.new(attribute(flash, "FadeSeconds", 0.45), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	local head = character:WaitForChild("Head", 5)
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health: number)
		local lost = last - health
		last = health
		-- Ignore the slow natural regen ticking the other way, and tiny changes.
		if lost >= 1 then
			flashHit()
			if head and head:IsA("BasePart") then
				DamagePopup.show(head, "-" .. math.floor(lost + 0.5), "Player", 1.5)
			end
		end
	end)
end

local function wireHud(gui: ScreenGui)
	local attack = gui:FindFirstChild("Attack")
	if attack and attack:IsA("GuiButton") then
		-- A tap on the screen is already camera and movement, so touch gets a button.
		attack.Visible = UserInputService.TouchEnabled
		attack.Activated:Connect(function()
			WeaponController.swing()
		end)
	end
end

-- ==================== lifecycle ====================

function InventoryUI.init(injected: any)
	deps = injected
	DamagePopup = deps.Util.DamagePopup
	PanelWindow = deps.UI.PanelWindow
	WeaponController = deps.Controllers.WeaponController
	PlayerAnimator = deps.Controllers.PlayerAnimator
	sellRemote = deps.Remotes.getFunction("SellItems")
	armorRemote = deps.Remotes.getEvent("EquipArmor")
end

function InventoryUI.start()
	-- One health bar, not two.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	-- StarterGui's copies can land in PlayerGui after this starts, so wait for
	-- them on a thread of their own rather than holding up the loader.
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local hudGui = playerGui:WaitForChild("WeaponHud", GUI_TIMEOUT)
		if hudGui and hudGui:IsA("ScreenGui") then
			hud = hudGui
			wireHud(hudGui)
		else
			warn("[InventoryUI] no WeaponHud ScreenGui in StarterGui")
		end
		local found = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if found then
			wirePanel(found)
		else
			warn('[InventoryUI] no ScreenGui in StarterGui has Panel = "Inventory"')
		end
	end)

	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
end

return InventoryUI
