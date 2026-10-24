--!strict
-- IndexUI: wires the hand-built Index (StarterGui/Index, layout C "Open book"
-- from the Claude Design canvas) and its HUD button (WeaponHud/IndexButton).
-- Nothing here builds UI; lists are clones of Index/Templates.
--
--   * The whole book (2026-10-20, tab strip B and Title 2 on the Index Expansion canvas,
--     https://claude.ai/artifact/25K21YcFmckdyVGPEa3VpX): eight sections (Index.Sections).
--     RightPage/Tabs holds a hand-placed button per section (Tab<Section>, attribute `Tab`;
--     Icon, Label, Count "found/total" for the world picked or all worlds; the open one wears
--     the Tabs' SkinSelected / TextSelected and `Selected`, the rest SkinIdle / TextIdle).
--     The page shows only the open section: creatures, weapons and armour as before, the
--     other five as Templates/EntryRow rows in each Section's `Entries` list (the shared
--     rarity tile in Tile, ItemName, RarityPill, Chip1 / Chip2 with where it comes from,
--     and CountCaption / CountValue: how many the player has caught, found or collected).
--     Rows are not buttons. The row's attributes hold every word.
--   * RightPage/Heading is the world's name (or All worlds), Total its found / total.
--   * RightPage/Titles (a world picked): the Collector card (every page found) and, once
--     that is earned, the Secret card -- "???" under a wax seal until the world's
--     Completionist title is earned (IndexService decides; the book never says what it
--     needs). An earned card toggles wearing it (Remotes.EquipTitle); the worn one is
--     `Selected`. Looks and words are the Titles frame's attributes.
--   * Left page: how much of the whole book is found (Progress, ProgressBar/Fill), "All",
--     and one card per world (Templates/WorldCard: the world's profile picture and its
--     Percent chip; Templates/LockedWorld for a world with nothing yet).
--     Picking one filters the right page.
--   * Right page (user's pick C on the Index Armour Pages canvas, 2026-10-13):
--     one Templates/Section per world -- a row of creature photos, a row of the
--     world's weapons (Index.weaponsOf) and a row of its armour sets (Config/Armor),
--     each with a header and found/total.
--     "All" lists every world's section with its WorldTitle; a picked world shows
--     only its own. Creatures are Templates/PhotoCard photos; weapons and sets
--     are the shared rarity tile (Util.WeaponTile, as in the drop slip).
--     Not found yet (a creature never defeated, a weapon never owned, a set never
--     crafted): the shared
--     question mark (WeaponTile's UnknownImage) and "???", and it isn't a button.
--   * Clicking a found photo opens the DropSlip to the left of the book:
--     - a creature: its drops (Templates/DropRow; weapons not found yet show the
--       question mark), then the crafting materials it drops, and its Stats row
--       (coins, EXP);
--     - an armour set (2026-10-13): its rarity tile (PortraitTile), "Rare ·
--       Crafted", Defense / Health (ArmorStats; a second row with RegenStat / SpeedStat
--       only for the bonuses the set has, 2026-10-22), the level and coins it takes
--       (ArmorCost) and its Recipe: each material with the creature that drops
--       it and how often, or the quest that gives it. DropsTitle and RowsClip
--       move to their Armor* positions (attributes) to make room; a second stats row
--       moves them (and the cost rows) down by the stats frame's ExtraRow.
--     - a weapon (2026-10-13): its rarity tile, "Epic · Found", its four stats in two
--       rows (WeaponStats: DpsStat, DamageStat / ReachStat, SpeedStat), its Weaponsmith
--       price if the stall sells it (WeaponCost)
--       and "Found in": each enemy that drops it with this player's chance, and
--       any quest that gives it.
--     Clicking the same photo again closes it. The book sits in the middle of
--     the screen; while the slip is open the book slides right so the pair is
--     centred instead (Window's SlipGap / SlipShiftSeconds).
--
-- Data: Config/Index (rosters, drops, armorOf, materialSource) and the player's
-- "IndexKills" / "IndexWeapons" / "IndexArmor" attributes from IndexService.
-- Every look that changes with state (skins, colours, wording) is an attribute
-- on the templates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Index = require(Config:WaitForChild("Index"))
local Armor = require(Config:WaitForChild("Armor"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Materials = require(Config:WaitForChild("Materials"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Quests = require(Config:WaitForChild("Quests"))
local Tools = require(Config:WaitForChild("Tools"))
local Potions = require(Config:WaitForChild("Potions"))
local Fishing = require(Config:WaitForChild("Fishing"))
local Gathering = require(Config:WaitForChild("Gathering"))
local Infuse = require(Config:WaitForChild("Infuse"))
local Bonuses = require(Config:WaitForChild("Bonuses"))

local Util = script.Parent.Parent:WaitForChild("Util")
local WeaponTile = require(Util:WaitForChild("WeaponTile"))
local Format = require(Util:WaitForChild("Format"))
local FontDrop = require(Util:WaitForChild("FontDrop"))

local IndexUI = {}

local PANEL_ID = "Index"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local PanelWindow: any = nil
local panel: ScreenGui? = nil

local filter: number? = nil -- a world id, or nil for All
local selected: string? = nil -- the creature or armour set whose slip is showing
local selectedKind: string? = nil -- "Enemy", "Weapon" or "Armor"
local tab = "Creatures" -- the open section (Index.Sections)
local Remotes: any = nil

local function attribute(inst: Instance?, name: string, fallback: any): any
	local value = inst and inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function find(name: string): any
	return panel and panel:FindFirstChild(name, true)
end

local function template(name: string): GuiObject?
	local folder = panel and panel:FindFirstChild("Templates")
	local found = folder and folder:FindFirstChild(name)
	return if found and found:IsA("GuiObject") then found else nil
end

local function setText(parent: Instance, name: string, value: string, color: Color3?)
	local label = parent:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		label.Text = value
		if color then
			label.TextColor3 = color
		end
	end
end

local function show(parent: Instance, name: string, visible: boolean): any
	local child = parent:FindFirstChild(name)
	if child and child:IsA("GuiObject") then
		child.Visible = visible
	end
	return child
end

-- "2/4": compact, for the chips and headers
local function count(found: number, total: number): string
	return Format.commas(found) .. "/" .. Format.commas(total)
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A scrolling list whose items are sized by aspect ratios: AutomaticCanvasSize
-- doesn't see those, so the canvas follows the layout's measured height.
local function fitCanvas(list: Instance)
	if not list:IsA("ScrollingFrame") or list:GetAttribute("CanvasWired") then
		return
	end
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return
	end
	list:SetAttribute("CanvasWired", true)
	local padding = list:FindFirstChildOfClass("UIPadding")
	local function fit()
		local extra = if padding then padding.PaddingTop.Offset + padding.PaddingBottom.Offset else 0
		list.CanvasSize = UDim2.fromOffset(0, math.ceil(layout.AbsoluteContentSize.Y + extra))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()
end

-- A frame as tall as its list's content. AutomaticSize can't be used: it
-- counts the raw height of items sized by an aspect ratio (UDim2(1, 0, 0, 100000)).
local function fitHeight(frame: GuiObject)
	local layout = frame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return
	end
	local function fit()
		frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, math.ceil(layout.AbsoluteContentSize.Y))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()
end

-- ==================== player progress ====================

local function kills(): { [string]: number }
	local out: { [string]: number } = {}
	local raw = player:GetAttribute("IndexKills")
	if type(raw) == "string" then
		for id, n in raw:gmatch("([^,=]+)=(%d+)") do
			out[id] = tonumber(n) :: number
		end
	end
	return out
end

local function idSet(attributeName: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local raw = player:GetAttribute(attributeName)
	if type(raw) == "string" then
		for id in raw:gmatch("[^,]+") do
			out[id] = true
		end
	end
	return out
end

local function foundWeapons(): { [string]: boolean }
	return idSet("IndexWeapons")
end

local function foundArmor(): { [string]: boolean }
	return idSet("IndexArmor")
end

-- ==================== weapon views ====================

-- the 3D view of a weapon (shared with every screen: Util.WeaponTile); IndexPopup uses it too
IndexUI.showWeapon = WeaponTile.showModel

-- ==================== drop slip ====================

local render: () -> ()
local renderTabs: (counts: { [string]: { found: number, total: number } }) -> ()
local renderTitles: (progress: Index.Progress) -> ()

-- Centre the book, or the book and its open slip together.
local shiftTween: Tween? = nil
local function centerBook(slipOpen: boolean)
	local window = find("Window")
	local slip = find("DropSlip")
	if not (window and window:IsA("GuiObject") and slip and slip:IsA("GuiObject")) then
		return
	end
	local shift = 0
	if slipOpen then
		-- the panel's pop-in UIScale shrinks AbsoluteSize; measure unscaled
		local pop = window:FindFirstChild("PopScale")
		local s = if pop and pop:IsA("UIScale") and pop.Scale > 0.01 then pop.Scale else 1
		local gap = window.AbsoluteSize.X / s * attribute(window, "SlipGap", 0.02)
		shift = math.floor((slip.AbsoluteSize.X / s + gap) / 2 + 0.5)
	end
	local target = UDim2.new(0.5, shift, window.Position.Y.Scale, window.Position.Y.Offset)
	if shiftTween then
		shiftTween:Cancel()
	end
	shiftTween = TweenService:Create(window, TweenInfo.new(attribute(window, "SlipShiftSeconds", 0.18), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target })
	;(shiftTween :: Tween):Play()
end

-- A drop chance with this player's luck applied (LuckBoost: passes and timed
-- boosts multiply together, ShopService), capped at 100% like the server's roll.
function IndexUI.luckyChance(chance: number): number
	-- passes, boosts and the Luck upgrade, added (Config/Bonuses)
	local luck = Bonuses.luck(Players.LocalPlayer)
	return math.min(1, chance * luck)
end
local luckyChance = IndexUI.luckyChance

-- Move a slip piece to its spot for a creature or an armour set (its
-- <Kind>Position / <Kind>Size attributes).
local function place(inst: Instance?, kind: string)
	if not (inst and inst:IsA("GuiObject")) then
		return
	end
	local position = inst:GetAttribute(kind .. "Position")
	if typeof(position) == "UDim2" then
		inst.Position = position
	end
	local size = inst:GetAttribute(kind .. "Size")
	if typeof(size) == "UDim2" then
		inst.Size = size
	end
end

-- The slip's row list, emptied and scrolled to the top.
local function emptyRows(slip: Instance): Instance?
	-- Rows scrolls when a list is longer than fits (user, 2026-10-11). The slip
	-- is tilted, and Roblox skips ClipsDescendants under a rotated ancestor, so
	-- Rows sits in a CanvasGroup (RowsClip) that does the clipping (2026-10-12).
	local rows = slip:FindFirstChild("Rows", true)
	if not rows then
		return nil
	end
	fitCanvas(rows)
	if rows:IsA("ScrollingFrame") then
		rows.CanvasPosition = Vector2.zero
	end
	clear(rows)
	return rows
end

-- Show the pieces for one kind of slip ("Creature", "Weapon", "Armor") and hide
-- the others'. `room`: the extra cost row shows, so the list sits at its Armor*
-- spot; otherwise at its Creature* spot.
local function slipMode(slip: Instance, kind: string, room: boolean)
	local creature = kind == "Creature"
	show(slip, "Portrait", creature)
	show(slip, "Stats", creature)
	show(slip, "PortraitTile", not creature)
	show(slip, "ArmorStats", kind == "Armor")
	show(slip, "ArmorCost", kind == "Armor")
	show(slip, "WeaponStats", kind == "Weapon")
	show(slip, "WeaponCost", kind == "Weapon" and room)
	local spot = if room then "Armor" else "Creature"
	local title = slip:FindFirstChild("DropsTitle")
	place(title, spot)
	if title and title:IsA("TextLabel") then
		title.Text = attribute(title, kind .. "Text", title.Text)
	end
	place(slip:FindFirstChild("RowsClip"), spot)
	place(slip:FindFirstChild("ArmorCost"), "Armor")
	place(slip:FindFirstChild("WeaponCost"), "Armor")
end

-- A slip whose stats take a second row (a weapon's four stats; an armour set with regen
-- or speed, 2026-10-22): everything under the stats moves down by the stats frame's
-- ExtraRow attribute (slip scale) and the list gives up that height. Run after slipMode.
local function lowerForStats(slip: Instance, stats: Instance?)
	local extra = stats and stats:GetAttribute("ExtraRow")
	if type(extra) ~= "number" then
		return
	end
	for _, name in { "DropsTitle", "RowsClip", "ArmorCost", "WeaponCost" } do
		local piece = slip:FindFirstChild(name)
		if piece and piece:IsA("GuiObject") then
			piece.Position += UDim2.fromScale(0, extra)
			if name == "RowsClip" then
				piece.Size -= UDim2.fromScale(0, extra)
			end
		end
	end
end

-- "0.25", "5": a share as a percentage without trailing zeros
local function percentText(share: number): string
	return (("%.2f"):format(share * 100):gsub("0+$", ""):gsub("%.$", ""))
end

-- The slip's picture for a weapon or armour set: its icon on its rarity tile.
local function tilePicture(slip: Instance, rarity: string, icon: string?)
	local tile = slip:FindFirstChild("PortraitTile")
	if tile and tile:IsA("ImageLabel") then
		tile.Image = WeaponTile.skin(rarity)
		local picture = tile:FindFirstChild("Picture")
		if picture and picture:IsA("ImageLabel") then
			picture.Image = icon or ""
		end
	end
end

-- "Rare · Crafted" / "Epic · Found": the rarity in its colour, then a word.
local function rarityLine(slip: Instance, rarity: string, formatName: string)
	local line = slip:FindFirstChild("Kills")
	if line and line:IsA("TextLabel") then
		local color: Color3 = attribute(template("DropRow"), "Color_" .. rarity, line.TextColor3)
		line.RichText = true
		line.Text = (attribute(line, formatName, "%s%s") :: string):format(color:ToHex(), rarity)
	end
end

-- A crafting material's row in a creature's drop slip: its rarity tile, name, rarity with
-- how many drop ("Uncommon · ×1–2") and its chance. Known once the creature has been
-- defeated. Luck doesn't change material chances (MaterialService), so none is applied.
local function materialRow(rowTemplate: GuiObject, drop: any, known: boolean, unknownName: string): GuiObject
	local mat = Materials.get(drop.id) :: any
	local row = rowTemplate:Clone()
	row.Name = drop.id
	row.Visible = true
	local slot = row:FindFirstChild("Tile")
	local tile = slot and WeaponTile.new(mat, { known = known, name = false, stat = false })
	if slot and tile then
		tile.Parent = slot
	end
	local rarity = mat.rarity or "Common"
	setText(row, "WeaponName", if known then mat.name else unknownName, attribute(rowTemplate, if known then "NameColor" else "UnknownNameColor", nil))
	local amount = if drop.max > drop.min then (" · ×%d–%d"):format(drop.min, drop.max) elseif drop.min > 1 then (" · ×%d"):format(drop.min) else ""
	setText(row, "Rarity", if known then rarity .. amount else attribute(rowTemplate, "UnknownRarity", ""), attribute(rowTemplate, if known then "Color_" .. rarity else "UnknownNameColor", nil))
	setText(row, "Chance", Index.percent(drop.chance), attribute(rowTemplate, if known then "ChanceColor" else "UnknownChanceColor", nil))
	return row
end

-- One recipe material in an armour set's slip: its tile, "Horsehair ×10", where it
-- comes from ("Wild Stallion", "Dale's quest") and the drop chance or "Quest".
local function recipeRow(rowTemplate: GuiObject, ingredient: Armor.Ingredient): GuiObject?
	local mat = Materials.get(ingredient.id) :: any
	if not mat then
		return nil
	end
	local row = rowTemplate:Clone()
	row.Name = ingredient.id
	row.Visible = true
	local slot = row:FindFirstChild("Tile")
	local tile = slot and WeaponTile.new(mat, { known = true, name = false, stat = false })
	if slot and tile then
		tile.Parent = slot
	end
	-- "Horsehair ×10"; a single quest item is just its name (long names need the room)
	local label = if ingredient.count > 1 then (attribute(rowTemplate, "AmountFormat", "%s ×%d") :: string):format(mat.name, ingredient.count) else mat.name
	setText(row, "WeaponName", label, attribute(rowTemplate, "NameColor", nil))
	local source = Index.materialSource(ingredient.id)
	local from = if not source then "" elseif source.quest then (attribute(rowTemplate, "QuestFormat", "%s's quest") :: string):format(source.name) else source.name
	setText(row, "Rarity", from, attribute(rowTemplate, "SourceColor", nil))
	if source and source.quest then
		setText(row, "Chance", attribute(rowTemplate, "QuestText", "Quest"), attribute(rowTemplate, "Color_Legendary", nil))
	else
		-- an enemy drop shows this player's luck (cores never take luck; fish odds aren't drops)
		local chance = source and source.chance
		if chance and not (mat.core or mat.fished or mat.gathered) then
			chance = luckyChance(chance)
		end
		setText(row, "Chance", if chance then Index.percent(chance) else "", attribute(rowTemplate, "ChanceColor", nil))
	end
	return row
end

local function renderCreatureSlip(slip: Instance, id: string, def: any)
	slipMode(slip, "Creature", false)
	local killed = kills()[id]
	local known = killed ~= nil
	local rowTemplate = template("DropRow")
	local unknownName = if rowTemplate then attribute(rowTemplate, "UnknownName", "???") else "???"

	local portrait = slip:FindFirstChild("Portrait")
	if portrait and portrait:IsA("ImageLabel") then
		portrait.Image = def.portrait or ""
		portrait.ImageColor3 = if known or not rowTemplate then Color3.new(1, 1, 1) else attribute(rowTemplate, "SilhouetteColor", Color3.new(0, 0, 0))
	end
	setText(slip, "EnemyName", if known then def.name else unknownName)
	setText(slip, "Kills", if known then ("Defeated \u{00D7} %d"):format(killed :: number) else "Not defeated yet")

	-- what a kill gives, once it has been defeated
	local stats = slip:FindFirstChild("Stats")
	if stats then
		local unknown = attribute(stats, "UnknownValue", "???")
		local coins = def.coins
		local coinText = if not coins then "0" elseif coins.min == coins.max then tostring(coins.min) else ("%d\u{2013}%d"):format(coins.min, coins.max)
		local coinStat = stats:FindFirstChild("CoinStat")
		if coinStat then
			setText(coinStat, "Value", if known then coinText else unknown)
		end
		local expStat = stats:FindFirstChild("ExpStat")
		if expStat then
			setText(expStat, "Value", if known then (attribute(stats, "ExpFormat", "%d EXP") :: string):format(def.exp or 0) else unknown)
		end
	end

	local rows = emptyRows(slip)
	if not (rows and rowTemplate) then
		return
	end
	local found = foundWeapons()
	-- every drop is listed, secret ones too (the user's call, 2026-10-11): until
	-- found, a secret shows the question mark on its own black rainbow tile
	local drops = {}
	for _, drop in Index.dropsOf(id) do
		if Weapons.get(drop.weapon) then
			table.insert(drops, drop)
		end
	end
	local materialDrops = {}
	for _, drop in def.materials or {} do
		if Materials.get(drop.id) then
			table.insert(materialDrops, drop)
		end
	end
	show(slip, "NoDrops", #drops == 0 and #materialDrops == 0)
	for order, drop in materialDrops do
		local row = materialRow(rowTemplate, drop, known, unknownName)
		row.LayoutOrder = 1000 + order
		row.Parent = rows
	end
	for order, drop in drops do
		local weapon = Weapons.get(drop.weapon)
		if not weapon then
			continue
		end
		local have = found[drop.weapon] == true
		local rowGui = rowTemplate:Clone()
		rowGui.Name = drop.weapon
		rowGui.LayoutOrder = order
		rowGui.Visible = true
		local rarity = weapon.rarity or "Common"
		-- the same tile as the Inventory (Util.WeaponTile) in the row's Tile slot;
		-- the row prints the name itself, so the tile's own name and pill are off
		local slot = rowGui:FindFirstChild("Tile")
		local tile = slot and WeaponTile.new(weapon, { known = have, name = false, stat = false })
		if slot and tile then
			tile.Parent = slot
		end
		setText(rowGui, "WeaponName", if have then weapon.name else unknownName, attribute(rowTemplate, if have then "NameColor" else "UnknownNameColor", nil))
		setText(rowGui, "Rarity", if have then rarity else attribute(rowTemplate, "UnknownRarity", ""), attribute(rowTemplate, if have then "Color_" .. rarity else "UnknownNameColor", nil))
		-- the chance for this player: drop chance x their luck (passes, boosts), capped
		-- at 100%, the same as IndexService rolls it
		setText(rowGui, "Chance", Index.percent(luckyChance(drop.chance)), attribute(rowTemplate, if have then "ChanceColor" else "UnknownChanceColor", nil))
		rowGui.Parent = rows
	end
end

local function renderArmorSlip(slip: Instance, def: Armor.ArmorDef)
	slipMode(slip, "Armor", true)
	local rowTemplate = template("DropRow")
	local rarity = def.rarity or "Common"
	tilePicture(slip, rarity, def.icon)
	setText(slip, "EnemyName", def.name)
	rarityLine(slip, rarity, "ArmorFormat")
	local stats = slip:FindFirstChild("ArmorStats")
	if stats then
		local defense = stats:FindFirstChild("DefenseStat")
		if defense then
			setText(defense, "Value", (attribute(stats, "DefenseFormat", "%d%%") :: string):format(math.floor(def.defense * 100 + 0.5)))
		end
		local health = stats:FindFirstChild("HealthStat")
		if health then
			setText(health, "Value", (attribute(stats, "HealthFormat", "+%d") :: string):format(def.health))
		end
		-- the second row: only the bonuses the set has, packed to the left
		local regen, speed = def.regen or 0, def.speed or 0
		local regenStat = stats:FindFirstChild("RegenStat")
		local speedStat = stats:FindFirstChild("SpeedStat")
		local left = stats:FindFirstChild("DefenseStat")
		local right = stats:FindFirstChild("HealthStat")
		if regenStat and regenStat:IsA("GuiObject") then
			regenStat.Visible = regen > 0
			setText(regenStat, "Value", (attribute(stats, "RegenFormat", "+%s%%/s") :: string):format(percentText(regen)))
		end
		if speedStat and speedStat:IsA("GuiObject") and left and right and left:IsA("GuiObject") and right:IsA("GuiObject") then
			speedStat.Visible = speed > 0
			setText(speedStat, "Value", (attribute(stats, "SpeedFormat", "+%s%%") :: string):format(percentText(speed)))
			local column = if regen > 0 then right else left
			speedStat.Position = UDim2.new(column.Position.X, speedStat.Position.Y)
		end
		if regen > 0 or speed > 0 then
			lowerForStats(slip, stats)
		end
	end
	local cost = slip:FindFirstChild("ArmorCost")
	if cost then
		local pill = cost:FindFirstChild("LevelPill")
		if pill then
			setText(pill, "Label", (attribute(cost, "LevelFormat", "Level %d") :: string):format(def.level))
		end
		local coins = cost:FindFirstChild("CoinStat")
		if coins then
			setText(coins, "Value", Format.coins(def.coins))
		end
	end

	show(slip, "NoDrops", #def.recipe == 0)
	local rows = emptyRows(slip)
	if not (rows and rowTemplate) then
		return
	end
	for order, ingredient in def.recipe do
		local row = recipeRow(rowTemplate, ingredient)
		if row then
			row.LayoutOrder = order
			row.Parent = rows
		end
	end
end

-- where each enemy lives, for the weapon slip's rows
local function worldOfEnemy(enemyId: string): any
	for _, entry in Index.all() do
		if entry.id == enemyId then
			return Worlds.get(entry.worldId)
		end
	end
	return nil
end

local function renderWeaponSlip(slip: Instance, def: any)
	local price = if type(def.price) == "number" and not def.starter then def.price else nil
	slipMode(slip, "Weapon", price ~= nil)
	local rowTemplate = template("DropRow")
	local rarity = def.rarity or "Common"
	tilePicture(slip, rarity, def.icon)
	setText(slip, "EnemyName", def.name)
	rarityLine(slip, rarity, "WeaponFormat")
	-- four stats in two rows (2026-10-22, like the Inventory's weapon card): DPS and Damage,
	-- then Reach and the seconds a swing takes, after the Worldheart Blade's tier (Infuse.adjust)
	local stats = slip:FindFirstChild("WeaponStats")
	if stats then
		local swing = Infuse.adjust(Players.LocalPlayer, def)
		local dps = stats:FindFirstChild("DpsStat")
		if dps then
			setText(dps, "Value", (attribute(stats, "DpsFormat", "%s DPS") :: string):format(WeaponTile.dpsNumber(def, true)))
		end
		local damage = stats:FindFirstChild("DamageStat")
		if damage then
			setText(damage, "Value", (attribute(stats, "DamageFormat", "%d") :: string):format(math.floor((swing.damage or 0) + 0.5)))
		end
		local reach = stats:FindFirstChild("ReachStat")
		if reach then
			setText(reach, "Value", (attribute(stats, "ReachFormat", "%s") :: string):format((("%.1f"):format(swing.reach or 0):gsub("%.0$", ""))))
		end
		local speed = stats:FindFirstChild("SpeedStat")
		if speed then
			setText(speed, "Value", (attribute(stats, "SpeedFormat", "%s s") :: string):format((("%.2f"):format(swing.cooldown or 0):gsub("0$", ""))))
		end
		lowerForStats(slip, stats)
	end
	local cost = slip:FindFirstChild("WeaponCost")
	local coins = cost and cost:FindFirstChild("CoinStat")
	if coins and price then
		setText(coins, "Value", Format.coins(price))
	end

	local sources = Index.weaponSources(def.id)
	show(slip, "NoDrops", #sources == 0)
	local rows = emptyRows(slip)
	if not (rows and rowTemplate) then
		return
	end
	for order, source in sources do
		local row = rowTemplate:Clone()
		row.LayoutOrder = order
		row.Visible = true
		local tile = row:FindFirstChild("Tile")
		local quest = source.quest and Quests.lines[source.quest]
		local enemy = source.enemy and Worlds.enemyDefs()[source.enemy]
		if quest then
			row.Name = source.quest :: string
			if tile and tile:IsA("ImageLabel") then
				-- the slot is see-through in the template (weapon tiles sit inside it)
				tile.Image = quest.npc and quest.npc.portrait or ""
				tile.ImageTransparency = 0
			end
			setText(row, "WeaponName", if quest.npc then quest.npc.name else quest.name, attribute(rowTemplate, "NameColor", nil))
			setText(row, "Rarity", quest.name, attribute(rowTemplate, "SourceColor", nil))
			setText(row, "Chance", attribute(rowTemplate, "QuestText", "Quest"), attribute(rowTemplate, "Color_Legendary", nil))
		elseif enemy then
			row.Name = source.enemy :: string
			if tile and tile:IsA("ImageLabel") then
				tile.Image = enemy.portrait or ""
				tile.ImageTransparency = 0
			end
			local world = worldOfEnemy(source.enemy :: string)
			setText(row, "WeaponName", enemy.name, attribute(rowTemplate, "NameColor", nil))
			setText(row, "Rarity", if world then world.name else "", attribute(rowTemplate, "SourceColor", nil))
			setText(row, "Chance", Index.percent(luckyChance(source.chance or 0)), attribute(rowTemplate, "ChanceColor", nil))
		else
			row:Destroy()
			continue
		end
		row.Parent = rows
	end
end

local function renderSlip()
	local slip = find("DropSlip")
	if not (slip and slip:IsA("GuiObject")) then
		return
	end
	local enemy = if selected and selectedKind == "Enemy" then Worlds.enemyDefs()[selected] else nil
	local set = if selected and selectedKind == "Armor" then Armor.get(selected) else nil
	local weapon = if selected and selectedKind == "Weapon" then Weapons.get(selected) else nil
	local open = enemy ~= nil or set ~= nil or weapon ~= nil
	slip.Visible = open
	centerBook(open)
	if set then
		renderArmorSlip(slip, set)
	elseif weapon then
		renderWeaponSlip(slip, weapon)
	elseif enemy and selected then
		renderCreatureSlip(slip, selected, enemy)
	end
end

-- ==================== pages ====================

local function select(kind: string, id: string)
	if selected == id and selectedKind == kind then
		selected, selectedKind = nil, nil
	else
		selected, selectedKind = id, kind
	end
	render()
end

local function renderWorlds(killed: { [string]: number }, owned: { [string]: boolean }, crafted: { [string]: boolean })
	local list = find("Worlds")
	local cardTemplate, lockedTemplate = template("WorldCard"), template("LockedWorld")
	if not (list and cardTemplate and lockedTemplate) then
		return
	end
	clear(list)
	for order, worldId in Worlds.Order do
		local world = Worlds.get(worldId)
		local roster = Index.roster(worldId)
		local sets = Index.armorOf(worldId)
		local arms = Index.weaponsOf(worldId)
		if not world then
			continue
		end
		if #roster == 0 and #sets == 0 and #arms == 0 then
			-- nothing to find here yet
			local lockedGui = lockedTemplate:Clone()
			lockedGui.Name = world.folder
			lockedGui.LayoutOrder = order
			lockedGui.Visible = true
			setText(lockedGui, "WorldName", world.name)
			lockedGui.Parent = list
			continue
		end
		local done = Index.progress(worldId, Index.progressOf(player))
		local cardGui = cardTemplate:Clone() :: any
		cardGui.Name = world.folder
		cardGui.LayoutOrder = order
		cardGui.Visible = true
		cardGui.Image = world.profile or ""
		local picked = filter == worldId
		local rim = cardGui:FindFirstChild("Rim")
		if rim and rim:IsA("UIStroke") then
			rim.Color = attribute(cardTemplate, if picked then "SelectedRimColor" else "RimColor", rim.Color)
		end
		cardGui.Rotation = if picked then attribute(cardTemplate, "SelectedRotation", 0) else 0
		setText(cardGui, "WorldName", world.name)
		local percent = cardGui:FindFirstChild("Percent")
		if percent then
			setText(percent, "Value", ("%d%%"):format(if done.total > 0 then math.floor(done.found / done.total * 100) else 0))
		end
		cardGui.Activated:Connect(function()
			filter = worldId
			selected, selectedKind = nil, nil
			render()
		end)
		cardGui.Parent = list
	end
end

-- Photos stuck in at slightly different angles.
local function tiltOf(cardTemplate: GuiObject, order: number): number
	local tilt = attribute(cardTemplate, "Tilt", 0)
	return if order % 2 == 1 then -tilt else tilt * 0.8
end

-- Not found yet: the same question mark the weapon tiles show (WeaponTile's
-- UnknownImage, user 2026-10-12). Returns false when there is no such image.
local function mystery(portrait: Instance?): boolean
	local image = WeaponTile.attribute("UnknownImage", nil)
	if portrait and portrait:IsA("ImageLabel") and type(image) == "string" and image ~= "" then
		portrait.Visible = true
		portrait.Image = image
		portrait.ImageColor3 = Color3.new(1, 1, 1)
		return true
	end
	return false
end

-- Only something found opens a slip; an unknown card isn't a button.
local function clickable(cardGui: any, known: boolean, kind: string, id: string)
	cardGui.Active = known
	cardGui.AutoButtonColor = known
	cardGui.Selectable = known
	if known then
		cardGui.Activated:Connect(function()
			select(kind, id)
		end)
	end
end

local function creatureCard(cardTemplate: GuiObject, entry: any, order: number, killed: { [string]: number }): GuiObject
	local known = killed[entry.id] ~= nil
	local cardGui = cardTemplate:Clone() :: any
	cardGui.Name = entry.id
	cardGui.LayoutOrder = order
	cardGui.Visible = true
	local skin = if selectedKind == "Enemy" and selected == entry.id
		then "SkinSelected"
		elseif known then (if entry.isBoss then "SkinBossFound" else "SkinFound")
		else (if entry.isBoss then "SkinBossUnknown" else "SkinUnknown")
	cardGui.Image = attribute(cardTemplate, skin, cardGui.Image)
	cardGui.Rotation = tiltOf(cardTemplate, order)
	local portrait = cardGui:FindFirstChild("Portrait")
	if not (not known and mystery(portrait)) and portrait and portrait:IsA("ImageLabel") then
		portrait.Image = entry.def.portrait or ""
		portrait.ImageColor3 = if known then Color3.new(1, 1, 1) else attribute(cardTemplate, "SilhouetteColor", Color3.new(0, 0, 0))
	end
	local nameColor = if known
		then attribute(cardTemplate, "NameColor", nil)
		else attribute(cardTemplate, if entry.isBoss then "BossUnknownNameColor" else "UnknownNameColor", nil)
	setText(cardGui, "EnemyName", if known then entry.def.name else attribute(cardTemplate, "UnknownName", "???"), nameColor)
	setText(cardGui, "Kills", if known then ("\u{00D7} %d"):format(killed[entry.id]) else "")
	show(cardGui, "BossBadge", entry.isBoss)
	clickable(cardGui, known, "Enemy", entry.id)
	return cardGui
end

-- A weapon or armour set on the page: the shared rarity tile (Util.WeaponTile,
-- the same as the drop slip's), its name on it; not found yet, the question
-- mark on the dimmed tile and not a button (user, 2026-10-13: no photo frame).
-- The picked one gets the section's SelectedRim* outline.
local function itemTile(sectionTemplate: GuiObject, def: any, known: boolean, kind: string, order: number): GuiObject?
	local tile = WeaponTile.new(def, { known = known, stat = false }) :: any
	if not tile then
		return nil
	end
	tile.LayoutOrder = order
	local rim = tile:FindFirstChild("Rim")
	if rim and rim:IsA("UIStroke") and selectedKind == kind and selected == def.id then
		rim.Color = attribute(sectionTemplate, "SelectedRimColor", rim.Color)
		rim.Thickness = attribute(sectionTemplate, "SelectedRimThickness", 0.04)
	end
	if tile:IsA("GuiButton") then
		clickable(tile, known, kind, def.id)
	end
	return tile
end

-- ---------- the item pages (tools, materials, fish, potions, treasures) ----------

-- The tool that breaks a gathering node: the lowest tier of its kind that can.
local function toolFor(node: any): any
	local best: any = nil
	for _, def in Tools.Defs do
		if def.kind == node.tool and def.tier >= node.tier and (best == nil or def.tier < best.tier) then
			best = def
		end
	end
	return best
end

local function chipText(row: Instance, name: string, text: string?)
	local chip = row:FindFirstChild(name)
	if chip and chip:IsA("GuiObject") then
		chip.Visible = text ~= nil and text ~= ""
		if text then
			setText(chip, "Label", text)
		end
	end
end

-- What a row says about where an item comes from (Chip1, Chip2) and what its count is
-- called (caught / found / collected).
local function aboutItem(rowTemplate: Instance, section: string, def: any): (string?, string?, string)
	local f = function(name: string, fallback: string): string
		return attribute(rowTemplate, name, fallback)
	end
	if section == "Tools" then
		local kind = Tools.KindNames[def.kind] or def.kind
		local from = def.recipe and def.recipe.tool and Tools.get(def.recipe.tool)
		return f("TierFormat", "%s · Tier %d"):format(kind, def.tier), if from then f("UpgradeFormat", "Upgrades the %s"):format(from.name) else f("SoldText", "Weaponsmith"), ""
	elseif section == "Potions" then
		return Potions.describe(def), nil, f("CollectedText", "Collected")
	elseif section == "Fish" then
		local spot = Fishing.spot(def.source)
		return spot and spot.name, f("BiteFormat", "%s bite"):format(Fishing.Fish[def.id] or "Easy"), f("CaughtText", "Caught")
	elseif section == "Treasures" then
		local source = Index.materialSource(def.id)
		return source and f("QuestFormat", "%s's quest"):format(source.name), nil, f("FoundText", "Found")
	end
	local source = Index.materialSource(def.id)
	local from = source and f("FromFormat", "From %s"):format(source.name)
	if def.gathered then
		local node = Gathering.get(def.source)
		local tool = node and toolFor(node)
		return from, tool and f("NeedsFormat", "Needs a %s"):format(tool.name), f("FoundText", "Found")
	end
	local chance = source and source.chance and luckyChance(source.chance)
	return from, chance and f("ChanceFormat", "%s chance"):format(Index.percent(chance)), f("FoundText", "Found")
end

local function entryRow(rowTemplate: GuiObject, section: string, def: any, order: number, held: number): GuiObject
	local found = held > 0
	local row = rowTemplate:Clone()
	row.Name = def.id
	row.LayoutOrder = order
	row.Visible = true
	if row:IsA("Frame") then
		row.BackgroundColor3 = attribute(rowTemplate, if found then "FillFound" else "FillUnknown", row.BackgroundColor3)
	end
	local slot = row:FindFirstChild("Tile")
	local tile = slot and WeaponTile.new(def, { known = found, name = false, stat = false })
	if slot and tile then
		tile.Parent = slot
	end
	setText(row, "ItemName", if found then def.name else attribute(rowTemplate, "UnknownName", "???"), attribute(rowTemplate, if found then "NameColor" else "UnknownNameColor", nil))
	local rarity = def.rarity or "Common"
	local pill = row:FindFirstChild("RarityPill")
	if pill and pill:IsA("GuiObject") then
		pill.BackgroundColor3 = attribute(template("DropRow"), "Color_" .. rarity, pill.BackgroundColor3)
		setText(pill, "Label", rarity)
	end
	local first, second, caption = aboutItem(rowTemplate, section, def)
	chipText(row, "Chip1", first)
	chipText(row, "Chip2", second)
	-- a lone first chip takes the second one's room too (a potion's effect)
	local chip1 = row:FindFirstChild("Chip1")
	if chip1 and chip1:IsA("GuiObject") then
		local size = chip1:GetAttribute(if second then "NarrowSize" else "WideSize")
		if typeof(size) == "UDim2" then
			chip1.Size = size
		end
	end
	local shown = found and caption ~= ""
	setText(row, "CountCaption", if shown then caption else "")
	setText(row, "CountValue", if shown then (attribute(rowTemplate, "CountFormat", "×%s") :: string):format(Format.commas(held)) else "")
	return row
end

-- One world's spread for the open tab: its creatures, weapons or armour sets as tiles, or
-- the rows of one of the item pages. nil when the world has nothing in that section.
local function section(sectionTemplate: GuiObject, cardTemplate: GuiObject, worldId: number, order: number, killed: { [string]: number }, owned: { [string]: boolean }, crafted: { [string]: boolean }): GuiObject?
	local world = Worlds.get(worldId)
	local listed = Index.entries(worldId, tab)
	if not world or #listed == 0 then
		return nil
	end
	local roster = if tab == "Creatures" then listed else {}
	local sets = if tab == "Armor" then listed else {}
	local arms = if tab == "Weapons" then listed else {}
	local sec = sectionTemplate:Clone()
	sec.Name = world.folder
	sec.LayoutOrder = order
	sec.Visible = true
	local title = show(sec, "WorldTitle", filter == nil)
	if title then
		title.Text = world.name
	end
	-- the tab already names the section: no headers
	for _, name in { "CreaturesHeader", "WeaponsHeader", "ArmorHeader" } do
		show(sec, name, false)
	end
	local entries = show(sec, "Entries", #roster == 0 and #sets == 0 and #arms == 0)
	local rowTemplate = template("EntryRow")
	if entries and rowTemplate and #roster == 0 and #sets == 0 and #arms == 0 then
		local items = Index.progressOf(player).items
		for i, def in listed do
			entryRow(rowTemplate, tab, def, i, items[def.id] or 0).Parent = entries
		end
		fitHeight(entries :: GuiObject)
	end

	local creatureRow = sec:FindFirstChild("Creatures")
	for i, entry in roster do
		if creatureRow then
			creatureCard(cardTemplate, entry, i, killed).Parent = creatureRow
		end
	end
	local weaponRow = sec:FindFirstChild("Weapons")
	for i, def in arms do
		local tile = weaponRow and itemTile(sectionTemplate, def, owned[def.id] == true, "Weapon", i)
		if tile then
			tile.Parent = weaponRow
		end
	end
	show(sec, "Weapons", #arms > 0)
	local armorRow = sec:FindFirstChild("Armor")
	for i, def in sets do
		local tile = armorRow and itemTile(sectionTemplate, def, crafted[def.id] == true, "Armor", i)
		if tile then
			tile.Parent = armorRow
		end
	end
	show(sec, "Creatures", #roster > 0)
	show(sec, "Armor", #sets > 0)
	return sec
end

-- the filter the page was last drawn for: the scroll is kept while it stays the
-- same (picking a photo redraws the page), and goes back to the top when it changes
local drawnFilter: number? = -1
local drawnTab = ""

local function renderPage(killed: { [string]: number }, owned: { [string]: boolean }, crafted: { [string]: boolean })
	local grid = find("Grid")
	local sectionTemplate, cardTemplate = template("Section"), template("PhotoCard")
	if not (grid and sectionTemplate and cardTemplate) then
		return
	end
	fitCanvas(grid)
	local scroll = if grid:IsA("ScrollingFrame") and drawnFilter == filter and drawnTab == tab then grid.CanvasPosition else Vector2.zero
	drawnFilter = filter
	drawnTab = tab
	clear(grid)
	local shown = 0
	for order, worldId in (if filter then { filter } else Worlds.Order) :: { number } do
		local sec = section(sectionTemplate, cardTemplate, worldId, order, killed, owned, crafted)
		if sec then
			sec.Parent = grid
			fitHeight(sec)
			shown += 1
		end
	end
	local empty = find("Empty")
	if empty and empty:IsA("GuiObject") then
		empty.Visible = shown == 0
	end
	if grid:IsA("ScrollingFrame") then
		grid.CanvasPosition = scroll
		-- the new sections size themselves a frame later; scroll back once they have
		task.defer(function()
			if drawnFilter == filter then
				grid.CanvasPosition = scroll
			end
		end)
	end
end

-- ---------- tabs and titles ----------

renderTabs = function(counts: { [string]: { found: number, total: number } })
	local bar = find("Tabs")
	if not bar then
		return
	end
	for _, button in bar:GetChildren() do
		local name = button:GetAttribute("Tab")
		if not (button:IsA("GuiButton") and type(name) == "string") then
			continue
		end
		local open = name == tab
		local skin = button:FindFirstChild("Skin")
		if skin and skin:IsA("ImageLabel") then
			skin.Image = attribute(bar, if open then "SkinSelected" else "SkinIdle", skin.Image)
		end
		local ink: Color3 = attribute(bar, if open then "TextSelected" else "TextIdle", Color3.new(1, 1, 1))
		local c = counts[name] or { found = 0, total = 0 }
		setText(button, "Label", (button:FindFirstChild("Label") :: TextLabel).Text, ink)
		setText(button, "Count", count(c.found, c.total), ink)
		button:SetAttribute("Selected", open)
	end
end

-- The world's two titles: the Collector card, and once that is earned the Secret card.
renderTitles = function(progress: Index.Progress)
	local box = find("Titles")
	if not (box and box:IsA("GuiObject")) then
		return
	end
	box.Visible = filter ~= nil
	if not filter then
		return
	end
	local earned: { [string]: boolean } = {}
	local raw = player:GetAttribute("Titles")
	for id in (if type(raw) == "string" then raw else ""):gmatch("[^,]+") do
		earned[id] = true
	end
	local worn = player:GetAttribute("Title")
	local collector, completionist = Index.titlesOf(filter)
	local p = Index.progress(filter, progress)
	local function card(name: string, title: Index.Title?, iconName: string, secretLook: boolean, note: string, visible: boolean)
		local button = box:FindFirstChild(name)
		if not (button and button:IsA("GuiButton")) then
			return
		end
		button.Visible = visible
		local has = title ~= nil and earned[title.id] == true
		local wearing = has and worn == (title :: Index.Title).id
		local state = if wearing then "Worn" elseif has then "Earned" elseif secretLook then "Secret" else "Locked"
		local skin = button:FindFirstChild("Skin")
		if skin and skin:IsA("GuiObject") then
			skin.BackgroundColor3 = attribute(box, "Fill" .. state, skin.BackgroundColor3)
			local rim = skin:FindFirstChild("Rim")
			if rim and rim:IsA("UIStroke") then
				rim.Color = attribute(box, "Rim" .. state, rim.Color)
			end
		end
		local icon = button:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			icon.Image = attribute(box, iconName, icon.Image)
		end
		local shownName = if title and not (secretLook and not has) then title.name else attribute(box, "SecretName", "???")
		setText(button, "TitleName", shownName, attribute(box, if state == "Secret" then "NameSecretColor" elseif state == "Locked" then "NameLockedColor" else "NameColor", nil))
		setText(button, "Note", if wearing then attribute(box, "TextWorn", "") elseif has then attribute(box, "TextEarned", "") else note, attribute(box, if state == "Secret" then "NoteSecretColor" else "NoteColor", nil))
		button.Active = has
		button:SetAttribute("Selected", wearing)
		button:SetAttribute("TitleId", if has then (title :: Index.Title).id else nil)
	end
	local collectorEarned = collector ~= nil and earned[collector.id] == true
	card("Collector", collector, "IconCollector", false, (attribute(box, "TextLocked", "%s / %s") :: string):format(Format.commas(p.found), Format.commas(p.total)), true)
	local completionistEarned = completionist ~= nil and earned[completionist.id] == true
	card("Secret", completionist, if completionistEarned then "IconCompletionist" else "IconSeal", true, attribute(box, "TextSecret", ""), collectorEarned)
end

render = function()
	if not panel then
		return
	end
	local killed = kills()
	local owned = foundWeapons()
	local crafted = foundArmor()
	-- a selection that isn't found (any more) closes
	if selected and ((selectedKind == "Enemy" and killed[selected] == nil) or (selectedKind == "Weapon" and not owned[selected]) or (selectedKind == "Armor" and not crafted[selected])) then
		selected, selectedKind = nil, nil
	end
	-- found / total: the whole book (left page), the page shown, and each tab
	local progress = Index.progressOf(player)
	local found, total = 0, 0
	local shownFound, shownTotal = 0, 0
	local tabs: { [string]: { found: number, total: number } } = {}
	for _, worldId in Worlds.Order do
		local p = Index.progress(worldId, progress)
		found += p.found
		total += p.total
		if filter == nil or filter == worldId then
			shownFound += p.found
			shownTotal += p.total
			for name, part in p.sections do
				local t = tabs[name] or { found = 0, total = 0 }
				t.found += part.found
				t.total += part.total
				tabs[name] = t
			end
		end
	end
	local progressLabel = find("Progress")
	setText(panel, "Progress", (attribute(progressLabel, "Format", "%s of %s found") :: string):format(Format.commas(found), Format.commas(total)))
	local fill = find("ProgressBar")
	fill = fill and fill:FindFirstChild("Fill")
	if fill and fill:IsA("GuiObject") then
		-- never narrower than it is tall: the fill is rounded at both ends, so a sliver
		-- squashed into a lopsided blob at a low count (2026-10-21, the user); now a
		-- little progress shows as a round dot that grows into the bar
		local bar = fill.Parent :: GuiObject
		local least = if bar.AbsoluteSize.X > 0 then bar.AbsoluteSize.Y / bar.AbsoluteSize.X else 0
		local share = if total > 0 then found / total else 0
		fill.Size = UDim2.fromScale(if share > 0 then math.max(share, least) else 0, 1)
		fill.Visible = found > 0
	end
	local world = filter and Worlds.get(filter)
	local heading = find("Heading")
	setText(panel, "Heading", if world then world.name else attribute(heading, "AllText", "All worlds"))
	setText(panel, "Total", count(shownFound, shownTotal))
	renderTabs(tabs)
	renderTitles(progress)
	renderWorlds(killed, owned, crafted)
	renderPage(killed, owned, crafted)
	renderSlip()
end

-- ==================== HUD button ====================

-- Grow the button while the pointer is over it (the Hotbar's tuning).
local function wireHover(button: GuiButton, tuning: Instance?)
	local content = button:FindFirstChild("Content")
	local scale = content and content:FindFirstChild("HoverScale")
	if not (scale and scale:IsA("UIScale")) then
		return
	end
	local function value(name: string, fallback: number): number
		local v = tuning and tuning:GetAttribute(name)
		return if type(v) == "number" then v else fallback
	end
	local tween: Tween? = nil
	local function to(target: number, time: number)
		if tween then
			tween:Cancel()
		end
		tween = TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target })
		;(tween :: Tween):Play()
	end
	button.MouseEnter:Connect(function()
		to(value("HoverScale", 1.15), value("HoverGrowTime", 0.12))
	end)
	button.MouseLeave:Connect(function()
		to(1, value("HoverShrinkTime", 0.1))
	end)
end

local function wireButton()
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
	local button = hud and hud:FindFirstChild("IndexButton", true)
	if not (button and button:IsA("GuiButton")) then
		warn("[IndexUI] no WeaponHud/IndexButton")
		return
	end
	wireHover(button, hud:FindFirstChild("Hotbar"))
	button.Activated:Connect(function()
		if PanelWindow.isPanelOpen(PANEL_ID) then
			PanelWindow.hidePanel()
		else
			PanelWindow.showPanel(PANEL_ID)
		end
	end)
end

-- ==================== lifecycle ====================

local function wirePanel(gui: ScreenGui)
	panel = gui
	local all = find("AllButton")
	if all and all:IsA("GuiButton") then
		all.Activated:Connect(function()
			filter = nil
			selected, selectedKind = nil, nil
			render()
		end)
	end
	local bar = find("Tabs")
	-- the tab names (Luckiest Guy) sit centred on each pill's face (2026-10-22: they drew high)
	if bar then
		FontDrop.watch(bar)
	end
	for _, button in (if bar then bar:GetChildren() else {}) :: { Instance } do
		local name = button:GetAttribute("Tab")
		if button:IsA("GuiButton") and type(name) == "string" then
			button.Activated:Connect(function()
				tab = name
				selected, selectedKind = nil, nil
				render()
			end)
		end
	end
	local titles = find("Titles")
	for _, name in { "Collector", "Secret" } do
		local button = titles and titles:FindFirstChild(name)
		if button and button:IsA("GuiButton") then
			button.Activated:Connect(function()
				local id = button:GetAttribute("TitleId")
				if type(id) == "string" then
					Remotes.getEvent("EquipTitle"):FireServer(if player:GetAttribute("Title") == id then "" else id)
				end
			end)
		end
	end
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			render()
		else
			selected, selectedKind = nil, nil
			drawnFilter = -1
		end
	end)
	-- LuckBoost changes the drop chances shown
	for _, name in { "IndexKills", "IndexWeapons", "IndexArmor", "IndexItems", "Titles", "Title", "LuckBoost", Upgrades.attr("Luck") } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if gui.Enabled then
				render()
			end
		end)
	end
	render()
end

function IndexUI.init(injected: any)
	PanelWindow = injected.UI.PanelWindow
	Remotes = injected.Remotes
end

function IndexUI.start()
	task.spawn(wireButton)
	task.spawn(function()
		local gui = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if gui then
			wirePanel(gui)
		else
			warn("[IndexUI] no Index panel (StarterGui/Index)")
		end
	end)
end

return IndexUI
