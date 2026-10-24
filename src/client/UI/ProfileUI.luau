--!strict
-- ProfileUI: the player card (2026-10-23, option A "profile sheet" on
-- https://claude.ai/artifact/MkJ7Xobg1XbSe6zZ8gJxfp, the user's pick), for yourself or
-- any other player. Opened by your own avatar on the HUD card (your profile), a row of
-- the player list, or the inspect card's Full Profile / Inventory buttons (InspectUI).
-- Everything comes from the shown player's published attributes, so another player's
-- card needs nothing from the server:
--   Identity (always shown)  avatar headshot, level badge, name, @username, worn title,
--                            weekly medal chip, Health and EXP bars, coins, Index
--                            progress over every world, the world they are in
--   Stats tab                Gear: the weapon (its DPS with THEIR bonuses) and armour
--                            worn, View Inventory; Stats: the 12 stat totals
--                            (Util/StatSheet, the Stats panel's numbers)
--   Inventory tab            read-only: everything they hold on the shared tiles
--   Trophies tab             the Ranks panel's trophy shelf with their cups
-- Hand-built StarterGui/PlayerProfile (Panel = "Profile"; a copy of the Stats panel's
-- window): Window/Title, Close, Tabs/Tab<Stats|Inventory|Trophies> (attribute Tab;
-- gui PillIdle / PillSelected / PillIdleText / PillSelectedText colours),
-- Identity (Avatar/Photo, Avatar/LevelBadge/Level, PlayerName, UserName,
-- TitleChip/Label, Medal (Icon, Label), Health / XP (Track/Fill, Amount), CoinsTile /
-- IndexTile (Value), WorldLine), Gear (WeaponCard / ArmorCard: TileSlot, ItemName,
-- Rarity, Stat/Value; ArmorCard's EmptyName; ViewInventory), Stats (Sheet of
-- Templates/StatLine: Icon, StatName, Total; UpColor / SameColor), InventoryView
-- (Count with its Format, Grid, Empty) and TrophiesView. Rarity text colours are the
-- gui's Color_<Rarity> attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Weapons = require(Config:WaitForChild("Weapons"))
local Armor = require(Config:WaitForChild("Armor"))
local Tools = require(Config:WaitForChild("Tools"))
local Potions = require(Config:WaitForChild("Potions"))
local Materials = require(Config:WaitForChild("Materials"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Index = require(Config:WaitForChild("Index"))
local Leveling = require(Config:WaitForChild("Leveling"))
local Leaderboards = require(Config:WaitForChild("Leaderboards"))
local Upgrades = require(Config:WaitForChild("Upgrades"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))
local WeaponTile = require(Util:WaitForChild("WeaponTile"))
local StatSheet = require(Util:WaitForChild("StatSheet"))

local ProfileUI = {}

local PANEL = "Profile"
local GUI_TIMEOUT = 15
local TICK = 0.5
local player = Players.LocalPlayer

-- Every word the card shows itself (the stat words are StatSheet's).
local Text = {
	userName = "@%s",
	world = "World %d · %s",
	noTitle = "No title yet",
	percent = "%d%%",
	tier = "Tier %d",
	defense = "%d%% Def",
	armorRarity = "%s · +%s HP",
	count = "×%s",
	noArmor = "No armor",
	trophiesOf = "%s's trophies", -- another player's shelf (yours keeps "My trophies")
}

local PanelWindow: any = nil
local FontDrop: any = nil
local deps: any = nil
local gui: ScreenGui? = nil
local window: any = nil
local target: Player? = nil
local tab = "Stats"
local statLines: { [string]: any } = {}
local gearShown: { [string]: string } = {} -- slot -> the id its tile shows
local invTiles: { [string]: GuiObject } = {} -- "kind:id" -> its tile, made once
local invKey = "" -- what the grid last showed (holder + their items)
local photos: { [number]: string } = {} -- UserId -> headshot

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function number(who: Player, name: string, fallback: number): number
	local value = who:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function rarityColor(rarity: string?, fallback: Color3): Color3
	local value = gui and rarity and gui:GetAttribute("Color_" .. rarity)
	return if typeof(value) == "Color3" then value else fallback
end

-- "Dagger,Sickle" -> { "Dagger", "Sickle" }; "Minnow=3,Stone=12" -> { Minnow = 3, ... }
local function list(who: Player, name: string): { string }
	local out = {}
	local raw = who:GetAttribute(name)
	if type(raw) == "string" then
		for id in raw:gmatch("[^,]+") do
			table.insert(out, id)
		end
	end
	return out
end
local function counts(who: Player, name: string): { [string]: number }
	local out = {}
	local raw = who:GetAttribute(name)
	if type(raw) == "string" then
		for id, n in raw:gmatch("([^,=]+)=(%d+)") do
			out[id] = tonumber(n) :: number
		end
	end
	return out
end

-- The headshot, fetched once per player (it yields, so off the render path).
local function setPhoto(image: ImageLabel, who: Player)
	local cached = photos[who.UserId]
	if cached then
		image.Image = cached
		return
	end
	image.Image = ""
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(who.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and type(content) == "string" then
			photos[who.UserId] = content
			if target == who then
				image.Image = content
			end
		end
	end)
end

local function worldOf(who: Player): number
	local current = who:GetAttribute("CurrentWorld")
	if type(current) == "number" and Worlds.get(current) then
		return current
	end
	return math.max(1, number(who, "HighestWorld", 1))
end

-- Index progress over every world that has entries, as a whole percentage.
local function indexPercent(who: Player): number
	local progress = Index.progressOf(who)
	local found, total = 0, 0
	local world = 1
	while Worlds.get(world) do
		local p = Index.progress(world, progress)
		found += p.found
		total += p.total
		world += 1
	end
	return if total > 0 then math.floor(found / total * 100) else 0
end

-- A Health / EXP bar copied from the HUD card: Track/Fill and Amount.
local function fillBar(bar: Instance?, value: number, max: number)
	if not bar then
		return
	end
	local share = if max > 0 then math.clamp(value / max, 0, 1) else 0
	local fill = bar:FindFirstChild("Fill", true)
	if fill and fill:IsA("GuiObject") then
		fill.Size = UDim2.fromScale(share, fill.Size.Y.Scale)
		local low, healthy = bar:GetAttribute("LowColor"), bar:GetAttribute("HealthyColor")
		if typeof(low) == "Color3" and typeof(healthy) == "Color3" then
			fill.BackgroundColor3 = if share <= attribute(bar, "LowFraction", 0.3) then low else healthy
		end
	end
	local amount = bar:FindFirstChild("Amount")
	if amount and amount:IsA("TextLabel") then
		amount.Text = Format.ratio(math.floor(value + 0.5), math.floor(max + 0.5))
	end
end

-- The weekly medal chip (the player list's chip): hidden without a medal.
local function fillMedal(chip: Instance?, who: Player)
	if not (chip and chip:IsA("GuiObject")) then
		return
	end
	local tier = who:GetAttribute("LeaderMedal")
	local board = who:GetAttribute("LeaderMedalBoard")
	local medal = if type(tier) == "string" then Leaderboards.Medals[tier] else nil
	chip.Visible = medal ~= nil and type(board) == "string"
	if medal and type(board) == "string" then
		local icon = chip:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			icon.Image = medal.medal
		end
		local text = chip:FindFirstChild("Label")
		if text and text:IsA("TextLabel") then
			text.Text = Leaderboards.Text.medalChip:format(medal.place, Leaderboards.Text.statShort[board] or board)
			text.TextColor3 = medal.fill
		end
		local stroke = chip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = medal.fill
		end
	end
end

-- The worn title's name ("Meadows Collector"), or nil.
local function titleName(who: Player): string?
	local title = Index.titleOf(who:GetAttribute("Title"))
	return title and title.name or nil
end

-- Everything a card shows about who they are; shared with the inspect card.
function ProfileUI.fillIdentity(root: Instance, who: Player)
	local avatar = root:FindFirstChild("Avatar")
	local photo = avatar and avatar:FindFirstChild("Photo")
	if photo and photo:IsA("ImageLabel") then
		setPhoto(photo, who)
	end
	local level = root:FindFirstChild("Level", true)
	if level and level:IsA("TextLabel") then
		level.Text = Format.commas(number(who, "Level", 1))
	end
	local name = root:FindFirstChild("PlayerName")
	if name and name:IsA("TextLabel") then
		name.Text = who.DisplayName
	end
	local health = root:FindFirstChild("Health")
	local character = who.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		fillBar(health, humanoid.Health, humanoid.MaxHealth)
	else
		local max = Leveling.maxHealth(number(who, "Level", 1))
		fillBar(health, max, max)
	end
end

local function fillProfileIdentity(who: Player)
	local id = window.Identity
	ProfileUI.fillIdentity(id, who)
	id.UserName.Text = Text.userName:format(who.Name)
	local title = titleName(who)
	id.TitleChip.Label.Text = title or Text.noTitle
	fillMedal(id:FindFirstChild("Medal"), who)
	local _, into, need = Leveling.fromTotal(math.floor(number(who, "ExpTotal", 0)))
	fillBar(id:FindFirstChild("XP"), into, need)
	id.CoinsTile.Value.Text = Format.coins(number(who, "Coins", 0))
	id.IndexTile.Value.Text = Text.percent:format(indexPercent(who))
	local world = worldOf(who)
	local def = Worlds.get(world)
	id.WorldLine.Text = Text.world:format(world, if def then def.name else "")
end

-- One equipment slot's shared tile in a card's TileSlot, refilled only when it changes.
local function slotTile(slot: Instance, key: string, def: any?)
	local id = if def then def.id else ""
	if gearShown[key] == id and (slot:FindFirstChildWhichIsA("GuiObject") ~= nil) == (def ~= nil) then
		return
	end
	gearShown[key] = id
	for _, child in slot:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if def then
		local tile = WeaponTile.new(def, { name = false, stat = false })
		if tile then
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			tile.Position = UDim2.fromScale(0.5, 0.5)
			tile.Size = UDim2.fromScale(1, 1)
			tile.Active = false -- display only: no hover, no click
			tile.Parent = slot
		end
	end
end

-- The weapon and armour cards; shared with the inspect card's minis (key keeps the
-- two cards' tiles apart).
function ProfileUI.fillGear(weaponCard: Instance, armorCard: Instance, who: Player, key: string)
	local weapon = Weapons.get(who:GetAttribute("SelectedWeapon")) or Weapons.get(Weapons.default)
	slotTile(weaponCard:FindFirstChild("TileSlot") :: Instance, key .. "Weapon", weapon)
	local wName = weaponCard:FindFirstChild("ItemName")
	if wName and wName:IsA("TextLabel") then
		wName.Text = if weapon then weapon.name else ""
	end
	local wRarity = weaponCard:FindFirstChild("Rarity")
	if wRarity and wRarity:IsA("TextLabel") and weapon then
		wRarity.Text = weapon.rarity
		wRarity.TextColor3 = rarityColor(weapon.rarity, wRarity.TextColor3)
	end
	local dps = if weapon then WeaponTile.dpsText(weapon, false, who) else ""
	local wStat = weaponCard:FindFirstChild("Stat")
	local wValue = wStat and (if wStat:IsA("TextLabel") then wStat else wStat:FindFirstChild("Value"))
	if wValue and wValue:IsA("TextLabel") then
		wValue.Text = dps
	end

	local set = Armor.get(who:GetAttribute("EquippedArmor"))
	slotTile(armorCard:FindFirstChild("TileSlot") :: Instance, key .. "Armor", set)
	local aName = armorCard:FindFirstChild("ItemName")
	if aName and aName:IsA("TextLabel") then
		aName.Text = if set then set.name else attribute(armorCard, "EmptyName", Text.noArmor)
		-- with no set worn there's no tile, so "No armor" sits in the middle of the card
		-- (below a head, if the card has one); its authored spot is kept to go back to
		if aName:GetAttribute("BasePosition") == nil then
			aName:SetAttribute("BasePosition", aName.Position)
			aName:SetAttribute("BaseAnchor", aName.AnchorPoint)
		end
		if set then
			aName.Position = aName:GetAttribute("BasePosition")
			aName.AnchorPoint = aName:GetAttribute("BaseAnchor")
		else
			local head = armorCard:FindFirstChild("Head")
			local top = if head and head:IsA("GuiObject") then head.Size.Y.Scale else 0
			aName.AnchorPoint = Vector2.new(0.5, 0.5)
			aName.Position = UDim2.fromScale(0.5, top + (1 - top) / 2)
		end
	end
	local aRarity = armorCard:FindFirstChild("Rarity")
	if aRarity and aRarity:IsA("TextLabel") then
		aRarity.Visible = set ~= nil
		if set then
			aRarity.Text = Text.armorRarity:format(set.rarity, Format.commas(math.floor(set.health * Upgrades.value(who, "Health") + 0.5)))
			aRarity.TextColor3 = rarityColor(set.rarity, aRarity.TextColor3)
		end
	end
	local aStat = armorCard:FindFirstChild("Stat")
	if aStat and aStat:IsA("GuiObject") then
		aStat.Visible = set ~= nil
		local aValue = if aStat:IsA("TextLabel") then aStat else aStat:FindFirstChild("Value")
		if set and aValue and aValue:IsA("TextLabel") then
			aValue.Text = Text.defense:format(math.floor(set.defense * 100 + 0.5))
		end
	end
end

local function fillStats(who: Player)
	local sheet = window.Stats.Sheet
	for index, id in StatSheet.ORDER do
		local line = statLines[id]
		if not line then
			line = window.Templates.StatLine:Clone()
			line.Name = id
			line.LayoutOrder = index
			line.Visible = true
			local def = Upgrades.get(id)
			line.Icon.Image = if def then def.icon else ""
			line.StatName.Text = StatSheet.name(id)
			line.Parent = sheet
			statLines[id] = line
		end
		local total, _, raised = StatSheet.measure(who, id)
		line.Total.Text = total
		line.Total.TextColor3 = line:GetAttribute(if raised then "UpColor" else "SameColor") or line.Total.TextColor3
	end
end

type Entry = { key: string, def: any, statText: string, group: number, rank: number, sort: number }

-- Everything the player holds, in the grid's order: weapons (best DPS first), armour,
-- tools, potions, materials.
local function holdings(who: Player): { Entry }
	local out: { Entry } = {}
	local function add(kind: string, def: any, statText: string, group: number, sort: number)
		table.insert(out, { key = kind .. ":" .. def.id, def = def, statText = statText, group = group, rank = Index.rarityRank(def.rarity), sort = sort })
	end
	for _, id in list(who, "OwnedWeapons") do
		local def = Weapons.get(id)
		if def then
			add("Weapon", def, WeaponTile.dpsText(def, false, who), 1, WeaponTile.dps(def, false, who))
		end
	end
	for _, id in list(who, "OwnedArmor") do
		local def = Armor.get(id)
		if def then
			add("Armor", def, Text.defense:format(math.floor(def.defense * 100 + 0.5)), 2, def.defense)
		end
	end
	for _, id in list(who, "OwnedTools") do
		local def = Tools.get(id)
		if def then
			add("Tool", def, Text.tier:format(def.tier), 3, def.tier)
		end
	end
	for id, n in counts(who, "Potions") do
		local def = Potions.get(id)
		if def and n > 0 then
			add("Potion", def, Text.count:format(Format.commas(n)), 4, n)
		end
	end
	for id, n in counts(who, "Materials") do
		local def = Materials.get(id)
		if def and n > 0 then
			add("Material", def, Text.count:format(Format.commas(n)), 5, n)
		end
	end
	table.sort(out, function(a, b)
		if a.group ~= b.group then
			return a.group < b.group
		end
		if a.group == 1 and a.sort ~= b.sort then
			return a.sort > b.sort
		end
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		return (a.def.name or a.def.id) < (b.def.name or b.def.id)
	end)
	return out
end

local function fitGrid(grid: ScrollingFrame)
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	local pad = grid:FindFirstChildOfClass("UIPadding")
	if layout then
		local extra = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
		grid.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + extra)
	end
end

-- The read-only inventory: one tile per thing for the session (no rebuilds), refilled
-- only when what the player holds changes.
local function fillInventory(who: Player)
	local view = window.InventoryView
	local entries = holdings(who)
	local parts = { tostring(who.UserId) }
	for _, entry in entries do
		table.insert(parts, entry.key .. "=" .. entry.statText)
	end
	local key = table.concat(parts, ",")
	if key == invKey then
		return
	end
	invKey = key
	local shown: { [string]: boolean } = {}
	for order, entry in entries do
		local tile = invTiles[entry.key]
		if tile then
			WeaponTile.fill(tile, entry.def, { statText = entry.statText })
		else
			tile = WeaponTile.new(entry.def, { statText = entry.statText })
			if tile then
				tile.Active = false
				tile.Parent = view.Grid
				invTiles[entry.key] = tile
			end
		end
		if tile then
			tile.LayoutOrder = order
			tile.Visible = true
			shown[entry.key] = true
		end
	end
	for k, tile in invTiles do
		if not shown[k] then
			tile.Visible = false
		end
	end
	view.Count.Text = (attribute(view.Count, "Format", "%s items") :: string):format(Format.commas(#entries))
	view.Empty.Visible = #entries == 0
	task.defer(fitGrid, view.Grid)
end

local function showTab(name: string)
	tab = name
	local stats = name == "Stats"
	window.Gear.Visible = stats
	window.Stats.Visible = stats
	window.InventoryView.Visible = name == "Inventory"
	window.TrophiesView.Visible = name == "Trophies"
	for _, button in window.Tabs:GetChildren() do
		local id = button:GetAttribute("Tab")
		if button:IsA("GuiButton") and type(id) == "string" then
			local on = id == name
			button:SetAttribute("Selected", on) -- stays grown (Util.ButtonFx)
			button.BackgroundColor3 = attribute(gui :: any, if on then "PillSelected" else "PillIdle", button.BackgroundColor3)
			local label = button:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				label.TextColor3 = attribute(gui :: any, if on then "PillSelectedText" else "PillIdleText", label.TextColor3)
			end
		end
	end
end

function ProfileUI.refresh()
	local who = target
	if not (window and who) then
		return
	end
	if not who.Parent then
		PanelWindow.hidePanel()
		return
	end
	fillProfileIdentity(who)
	if tab == "Stats" then
		ProfileUI.fillGear(window.Gear.WeaponCard, window.Gear.ArmorCard, who, "Profile")
		fillStats(who)
	elseif tab == "Inventory" then
		fillInventory(who)
	elseif tab == "Trophies" then
		local board = deps.UI.LeaderboardUI
		if board and board.fillTrophies then
			board.fillTrophies(window.TrophiesView, who)
			if who ~= player then
				window.TrophiesView.Title.Text = Text.trophiesOf:format(who.DisplayName)
			end
		end
	end
end

-- Open `who`'s card (default yourself) on a tab (default Stats).
function ProfileUI.show(who: Player?, tabName: string?)
	if not window then
		return
	end
	target = who or player
	if window:FindFirstChild("Title") then
		window.Title.Text = (target :: Player).DisplayName
	end
	showTab(tabName or "Stats")
	PanelWindow.showPanel(PANEL)
	ProfileUI.refresh()
end

function ProfileUI.init(injected: any)
	deps = injected
	PanelWindow = injected.UI.PanelWindow
	FontDrop = injected.Util.FontDrop
end

function ProfileUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL, GUI_TIMEOUT)
		if not found then
			warn("[ProfileUI] no Profile panel (StarterGui/PlayerProfile)")
			return
		end
		gui = found
		window = found:WaitForChild("Window")
		for _, button in window.Tabs:GetChildren() do
			local id = button:GetAttribute("Tab")
			if button:IsA("GuiButton") and type(id) == "string" then
				button.Activated:Connect(function()
					showTab(id)
					ProfileUI.refresh()
				end)
			end
		end
		window.Gear.ViewInventory.Activated:Connect(function()
			showTab("Inventory")
			ProfileUI.refresh()
		end)
		if FontDrop then
			FontDrop.watch(found)
		end
		local card = deps.UI.PlayerCardUI
		local badge = window.Identity:FindFirstChild("Level", true)
		if card and card.watchBadge and badge then
			card.watchBadge(badge)
		end
		-- your own avatar on the HUD card opens your profile
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		local own = hud and hud:FindFirstChild("ProfileButton", true)
		if own and own:IsA("GuiButton") then
			own.Activated:Connect(function()
				if PanelWindow.isPanelOpen(PANEL) and target == player then
					PanelWindow.hidePanel()
				else
					ProfileUI.show(player)
				end
			end)
		end
		-- live while open: health, timers, a new drop
		while true do
			task.wait(TICK)
			if found.Enabled then
				ProfileUI.refresh()
			end
		end
	end)
end

return ProfileUI
