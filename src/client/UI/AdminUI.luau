--!strict
-- AdminUI: wires the hand-built admin panel, StarterGui/AdminPanel (layout A
-- "Tabbed console", the user's pick 2026-10-11; canvas
-- https://claude.ai/artifact/VGyCNhGop9tZDV5LnqQvZB). Admins only: the player
-- attribute IsAdmin (AdminService) must be true. F2 (Config/Admin toggleKey) or
-- the HUD's Admin side button (a controller, under Shop) opens and closes it
-- through PanelWindow (Panel = "Admin"). Every request goes to
-- Remotes.AdminAction, which the server checks again.
--
-- The panel has the Inventory's look (2026-10-20, the user: "the same look as the
-- inventory"): the Window wears the drawn aqua window (Skin, art/tools/ui/admin_window.py)
-- with its Shadow, the Header sits on the drawn cyan band, and Body lies on the two drawn
-- panels, Tabs beside Content (Body's list); Content stacks Pages above Status. Every
-- button is a pill (a Skin image and a Label on its face), like the rest of the game.
-- Pieces are found by name at any depth:
--   Title, Close; Tabs/Tab<Player|Weapons|Armor|Tools|Materials|Mobs> (a "Tab" attribute
--   naming the page; Label), Hint;
--   PagePlayer: CoinsCard / ExpCard (Icon, Title, Have, Amount, Add, Take,
--     Quick1, Quick2), LevelCard (Badge/Label, Title, Amount, Set, LevelUp),
--     DamageCard (Badge = your damage multiplier, Amount, Set, Reset = back to x1; not saved),
--     HealthCard (Badge/Label = your max HP, Title, Amount, Set = set max HP for
--     the session (0 = back to the level's), Heal);
--   PageWeapons/List, PageArmor/List, PageMaterials/List: one section per world
--     (2026-10-12, like the mobs): a Templates/WorldHeader, then a
--     Templates/CardSection grid (its height follows its cards) of
--     Templates/WeaponCard -- the shared tile (Util.WeaponTile) in its Tile slot,
--     plus Action (Give / Remove / Starter: the pill in the template's <state>Skin
--     attribute). Weapons are sorted by damage, weakest first; armour by
--     order; materials use Templates/MaterialCard (Buttons/Give, Buttons/Take:
--     Admin.Text.materialStep at a time, the count on the tile's pill);
--   PageTools/List (2026-10-19): the gathering tools (Config/Tools) per world, on
--     WeaponCards with their kind on the pill; Give / Remove send the `tool` action;
--   PagePotions/List (2026-10-19): every potion (Config/Potions) per tier, on
--     MaterialCards (count on the pill); Give / Take send the `potion` action;
--   PageUpgrades/List (2026-10-22): a Templates/UpgradeAllRow (Icon, Texts/LineName, Texts/Note,
--     MaxAll / ResetAll = the `upgradeAll` action at the top level or 0), then a
--     Templates/UpgradeRow per upgrade in Config/Upgrades order (Icon, Texts/LineName,
--     Texts/Note "Level 2 of 24 · x1.20 crit chance", AmountField/Amount = a level, Set =
--     the `upgrade` action to that level, Up = one level up);
--   PageMobs/List: Templates/WorldHeader, then a Templates/MobRow per enemy kind
--     (Portrait, MobName, Note, Respawn);
--   PageQuests/List (2026-10-19): a Templates/QuestRow per questline (Portrait = the
--     giver, Texts/LineName, Texts/Note "Step 6 of 10 · Active", Amount = a step number,
--     Go = the `quest` action to that step (one past the last finishes the line), Skip =
--     `questSkip`, one step on);
--   Status/Label: the last result. It always keeps its room (idle = see-through),
--     so a message never resizes the page (gui attributes StatusOk,
--     StatusError, StatusSeconds).
-- Buttons have Label children (their hover and press: Util.ButtonFx); the gui's SkinTabSelected /
-- SkinTabIdle pills dress the tabs. Every word comes from Config/Admin.Text.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Admin = require(Config:WaitForChild("Admin"))
local Armor = require(Config:WaitForChild("Armor"))
local Materials = require(Config:WaitForChild("Materials"))
local Potions = require(Config:WaitForChild("Potions"))
local Quests = require(Config:WaitForChild("Quests"))
local Tools = require(Config:WaitForChild("Tools"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Leveling = require(Config:WaitForChild("Leveling"))
local MapLayout = require(Config:WaitForChild("MapLayout"))

local AdminUI = {}

local PANEL = "Admin"
local Text = Admin.Text
local player = Players.LocalPlayer

local deps: any = nil
local Format: any = nil
local WeaponTile: any = nil
local remote: RemoteFunction? = nil
local gui: ScreenGui? = nil
local window: Frame? = nil
local page = "PagePlayer"
local statusTicket = 0

local function attr(inst: Instance, name: string, fallback: any): any
	local v = inst:GetAttribute(name)
	return if v ~= nil then v else fallback
end

-- a piece by name anywhere under `root` (default: the window)
local function find(name: string, root: Instance?): any
	local r = root or window
	return r and r:FindFirstChild(name, true)
end

local function setLabel(button: Instance?, str: string)
	local label = button and button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = str
	elseif button and button:IsA("TextButton") then
		button.Text = str
	end
end

local function number(name: string): number
	local v = player:GetAttribute(name)
	return if type(v) == "number" then v else 0
end

-- ==================== feedback ====================

local function status(ok: boolean, message: string)
	local pill = find("Status")
	if not (gui and pill and pill:IsA("GuiObject")) then
		return
	end
	statusTicket += 1
	local ticket = statusTicket
	pill.BackgroundTransparency = 0
	pill.BackgroundColor3 = attr(gui, if ok then "StatusOk" else "StatusError", pill.BackgroundColor3)
	setLabel(pill, message)
	task.delay(attr(gui, "StatusSeconds", 3), function()
		if ticket == statusTicket then
			pill.BackgroundTransparency = 1
			setLabel(pill, "")
		end
	end)
end

local function ask(request: { [string]: any })
	if not remote then
		return
	end
	local ok, success, message = pcall(function()
		return (remote :: RemoteFunction):InvokeServer(request)
	end)
	if not ok then
		status(false, tostring(success))
	else
		status(success == true, tostring(message))
	end
end

-- A pressed button runs `fn` (its hover and press look come from Util.ButtonFx, like every button).
local function wireButton(button: Instance?, fn: () -> ())
	if not (button and button:IsA("GuiButton")) then
		return
	end
	button.Activated:Connect(fn)
end

-- "1,000" / " 250 " -> 1000; nil if it isn't a number
local function read(box: Instance?): number?
	if not (box and box:IsA("TextBox")) then
		return nil
	end
	return tonumber((box.Text:gsub("[,%s]", "")))
end

-- A button is a pill (its Skin image); a state swaps which pill it wears.
local function reskin(button: Instance?, image: string?)
	local skin = button and button:FindFirstChild("Skin")
	if skin and skin:IsA("ImageLabel") and image then
		skin.Image = image
	end
end

-- ==================== player page ====================

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function renderPlayer()
	local coinsCard, expCard, levelCard = find("CoinsCard"), find("ExpCard"), find("LevelCard")
	local healthCard = find("HealthCard")
	local h = humanoid()
	if healthCard and h then
		setLabel(find("Badge", healthCard), Format.commas(math.floor(h.MaxHealth + 0.5)))
	end
	-- the Damage card's badge: your own multiplier (the "DamageMultiplier" attribute, x1 when unset)
	local damageCard = find("DamageCard")
	if damageCard then
		local m = player:GetAttribute("DamageMultiplier")
		setLabel(find("Badge", damageCard), Text.damageBadge:format(tostring(if type(m) == "number" then m else 1)))
	end
	local level, into, need = Leveling.fromTotal(number("ExpTotal"))
	local coinsHave = coinsCard and find("Have", coinsCard)
	if coinsHave then
		coinsHave.Text = Text.youHave:format(Format.coins(number("Coins")))
	end
	local expHave = expCard and find("Have", expCard)
	if expHave then
		expHave.Text = Text.expInto:format(Format.commas(into), Format.commas(need), Format.commas(level))
	end
	if levelCard then
		setLabel(find("Badge", levelCard), Format.commas(level))
	end
end

local function wireAmountCard(card: Instance?, action: string, quick: { number })
	if not card then
		return
	end
	local box = find("Amount", card)
	local function send(sign: number)
		local amount = read(box)
		if not amount then
			status(false, Text.badNumber)
			return
		end
		ask({ action = action, amount = sign * math.abs(amount) })
	end
	wireButton(find("Add", card), function()
		send(1)
	end)
	wireButton(find("Take", card), function()
		send(-1)
	end)
	for i, amount in quick do
		local chip = find("Quick" .. i, card)
		setLabel(chip, Text.quick:format(Format.commas(amount)))
		wireButton(chip, function()
			ask({ action = action, amount = amount })
		end)
	end
end

-- ==================== weapons page ====================

local function owned(): { [string]: boolean }
	local set = {}
	local list = player:GetAttribute("OwnedWeapons")
	for id in (if type(list) == "string" then list else ""):gmatch("[^,]+") do
		set[id] = true
	end
	return set
end

-- A world's section in a page's list: its header, then a grid of cards whose
-- height follows its content. Made once, reused on every render.
-- A header and a card grid in a page's list, named by `key` ("3" for World 3, "T2").
local function sectionFor(list: Instance, key: string, title: string, order: number): Instance?
	local templates = gui and gui:FindFirstChild("Templates")
	local headerTemplate = templates and templates:FindFirstChild("WorldHeader")
	local sectionTemplate = templates and templates:FindFirstChild("CardSection")
	if not (headerTemplate and sectionTemplate) then
		return nil
	end
	local header = list:FindFirstChild("Header" .. key)
	if not header then
		header = headerTemplate:Clone()
		header.Name = "Header" .. key
		header.Visible = true
		header.Parent = list
	end
	header.LayoutOrder = order
	header.Text = title
	local section = list:FindFirstChild("Cards" .. key)
	if not section then
		section = sectionTemplate:Clone()
		section.Name = "Cards" .. key
		section.Visible = true
		section.Parent = list
		local layout = section:FindFirstChildWhichIsA("UIGridStyleLayout")
		if layout then
			local function fit()
				section.Size = UDim2.new(1, 0, 0, math.ceil(layout.AbsoluteContentSize.Y))
			end
			layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
			fit()
		end
	end
	section.LayoutOrder = order + 1
	return section
end

local function worldSection(list: Instance, worldId: number, order: number): Instance?
	local world = Worlds.get(worldId)
	return sectionFor(list, tostring(worldId), Text.worldHeader:format(worldId, world and world.name or ""), order)
end

-- The page's List, and the worlds that have something to list, in world order.
local function pageList(name: string): Instance?
	local pageFrame = find(name)
	return pageFrame and pageFrame:FindFirstChild("List")
end

-- A card in `section` for `id`, made from `templateName` with `def` on the shared tile.
local function card(section: Instance, id: string, templateName: string, def: any, opts: any, wire: (Instance) -> ()): Instance?
	local existing = section:FindFirstChild(id)
	if existing then
		return existing
	end
	local templates = gui and gui:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild(templateName)
	if not template then
		return nil
	end
	local c = template:Clone()
	c.Name = id
	c.Visible = true
	local slot = c:FindFirstChild("Tile")
	local tile = slot and WeaponTile.new(def, opts)
	if tile then
		tile.Parent = slot
	end
	wire(c)
	c.Parent = section
	return c
end

local function styleAction(action: Instance?, state: string)
	local templates = gui and gui:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("WeaponCard")
	if template then
		reskin(action, attr(template, state .. "Skin", nil))
	end
end

local function renderWeapons()
	local list = pageList("PageWeapons")
	if not list then
		return
	end
	local have = owned()
	local order = 0
	for _, worldId in Worlds.Order do
		local defs = {}
		for _, def in Weapons.list() do
			if (def.world or 1) == worldId then
				table.insert(defs, def)
			end
		end
		if #defs == 0 then
			continue
		end
		table.sort(defs, function(a, b)
			return if a.damage == b.damage then a.order < b.order else a.damage < b.damage
		end)
		order += 2
		local section = worldSection(list, worldId, order)
		if not section then
			return
		end
		for index, def in defs do
			local id = def.id
			local c = card(section, id, "WeaponCard", def, nil, function(c)
				wireButton(c:FindFirstChild("Action"), function()
					local current = Weapons.get(id)
					if current and not current.starter then
						ask({ action = if owned()[id] then "remove" else "give", weapon = id })
					end
				end)
			end)
			if c then
				c.LayoutOrder = index
				local state = if def.starter then "Starter" elseif have[id] then "Remove" else "Give"
				local action = c:FindFirstChild("Action")
				setLabel(action, if state == "Starter" then Text.starter elseif state == "Remove" then Text.remove else Text.give)
				styleAction(action, state)
			end
		end
	end
end

-- ==================== armour page ====================

local function ownedArmor(): { [string]: boolean }
	local set = {}
	local list = player:GetAttribute("OwnedArmor")
	for id in (if type(list) == "string" then list else ""):gmatch("[^,]+") do
		set[id] = true
	end
	return set
end

local function renderArmor()
	local list = pageList("PageArmor")
	if not list then
		return
	end
	local have = ownedArmor()
	local order = 0
	for _, worldId in Worlds.Order do
		local defs = {}
		for _, def in Armor.list() do
			if def.world == worldId then
				table.insert(defs, def)
			end
		end
		if #defs == 0 then
			continue
		end
		order += 2
		local section = worldSection(list, worldId, order)
		if not section then
			return
		end
		for index, def in defs do
			local id = def.id
			local c = card(section, id, "WeaponCard", def, { statText = Text.armorDef:format(math.floor(def.defense * 100 + 0.5)) }, function(c)
				wireButton(c:FindFirstChild("Action"), function()
					ask({ action = "armor", id = id, remove = ownedArmor()[id] == true })
				end)
			end)
			if c then
				c.LayoutOrder = index
				local state = if have[id] then "Remove" else "Give"
				local action = c:FindFirstChild("Action")
				setLabel(action, if state == "Remove" then Text.remove else Text.give)
				styleAction(action, state)
			end
		end
	end
end

-- ==================== tools page ====================

local function renderTools()
	local list = pageList("PageTools")
	if not list then
		return
	end
	local have = Tools.owned(player)
	local order = 0
	for _, worldId in Worlds.Order do
		local defs = {}
		for _, def in Tools.Defs do
			if def.world == worldId then
				table.insert(defs, def)
			end
		end
		if #defs == 0 then
			continue
		end
		-- the hotbar's order of kinds, then tier
		table.sort(defs, function(a, b)
			local ka, kb = table.find(Tools.Kinds, a.kind) or 99, table.find(Tools.Kinds, b.kind) or 99
			return if ka == kb then a.tier < b.tier else ka < kb
		end)
		order += 2
		local section = worldSection(list, worldId, order)
		if not section then
			return
		end
		for index, def in defs do
			local id = def.id
			local c = card(section, id, "WeaponCard", def, { statText = Tools.KindNames[def.kind] or def.kind }, function(c)
				wireButton(c:FindFirstChild("Action"), function()
					ask({ action = "tool", id = id, remove = Tools.owned(player)[id] == true })
				end)
			end)
			if c then
				c.LayoutOrder = index
				local state = if have[id] then "Remove" else "Give"
				local action = c:FindFirstChild("Action")
				setLabel(action, if state == "Remove" then Text.remove else Text.give)
				styleAction(action, state)
			end
		end
	end
end

-- ==================== materials page ====================

local function renderMaterials()
	local list = pageList("PageMaterials")
	if not list then
		return
	end
	local counts = Materials.counts(player)
	local step = Text.materialStep or 10
	local order = 0
	for _, worldId in Worlds.Order do
		local defs = {}
		for _, def in Materials.list() do
			if def.world == worldId then
				table.insert(defs, def)
			end
		end
		if #defs == 0 then
			continue
		end
		order += 2
		local section = worldSection(list, worldId, order)
		if not section then
			return
		end
		for index, def in defs do
			local id = def.id
			local c = card(section, id, "MaterialCard", def, { statText = "" }, function(c)
				wireButton(c:FindFirstChild("Give", true), function()
					ask({ action = "material", id = id, amount = step })
				end)
				wireButton(c:FindFirstChild("Take", true), function()
					ask({ action = "material", id = id, amount = -step })
				end)
				setLabel(c:FindFirstChild("Give", true), Text.giveMany:format(step))
				setLabel(c:FindFirstChild("Take", true), Text.takeMany:format(step))
				styleAction(c:FindFirstChild("Give", true), "Give")
				styleAction(c:FindFirstChild("Take", true), "Remove")
			end)
			if c then
				c.LayoutOrder = index
				-- the count on the tile's pill
				local value = c:FindFirstChild("Stat", true)
				value = value and value:FindFirstChild("Value", true)
				if value and value:IsA("TextLabel") then
					value.Text = Text.materialCount:format(Format.commas(counts[id] or 0))
				end
			end
		end
	end
end

-- ==================== potions page ====================

local function renderPotions()
	local list = pageList("PagePotions")
	if not list then
		return
	end
	local counts = Potions.counts(player)
	local step = Text.potionStep or 1
	for tier, band in Potions.Bands do
		local section = sectionFor(list, "T" .. tier, Text.tierHeader:format(Potions.Numerals[tier], band.from, band.to), tier * 2)
		if not section then
			return
		end
		local index = 0
		for _, def in Potions.list() do
			if def.tier ~= tier then
				continue
			end
			index += 1
			local id = def.id
			local c = card(section, id, "MaterialCard", def, { statText = "" }, function(c)
				wireButton(c:FindFirstChild("Give", true), function()
					ask({ action = "potion", id = id, amount = step })
				end)
				wireButton(c:FindFirstChild("Take", true), function()
					ask({ action = "potion", id = id, amount = -step })
				end)
				setLabel(c:FindFirstChild("Give", true), Text.giveMany:format(step))
				setLabel(c:FindFirstChild("Take", true), Text.takeMany:format(step))
				styleAction(c:FindFirstChild("Give", true), "Give")
				styleAction(c:FindFirstChild("Take", true), "Remove")
			end)
			if c then
				c.LayoutOrder = index
				local value = c:FindFirstChild("Stat", true)
				value = value and value:FindFirstChild("Value", true)
				if value and value:IsA("TextLabel") then
					value.Text = Text.materialCount:format(Format.commas(counts[id] or 0))
				end
			end
		end
	end
end

-- ==================== upgrades page ====================

local function renderUpgrades()
	local pageFrame = find("PageUpgrades")
	local list = pageFrame and pageFrame:FindFirstChild("List")
	local templates = gui and gui:FindFirstChild("Templates")
	local rowTemplate = templates and templates:FindFirstChild("UpgradeRow")
	local allTemplate = templates and templates:FindFirstChild("UpgradeAllRow")
	if not (list and rowTemplate and allTemplate) then
		return
	end
	local max = Upgrades.maxLevel()
	if not list:FindFirstChild("All") then
		local all = allTemplate:Clone()
		all.Name = "All"
		all.Visible = true
		all.LayoutOrder = 0
		find("LineName", all).Text = Text.allUpgrades
		find("Note", all).Text = Text.allUpgradesNote
		setLabel(find("MaxAll", all), Text.maxAll)
		setLabel(find("ResetAll", all), Text.resetAll)
		wireButton(find("MaxAll", all), function()
			ask({ action = "upgradeAll", level = max })
		end)
		wireButton(find("ResetAll", all), function()
			ask({ action = "upgradeAll", level = 0 })
		end)
		all.Parent = list
	end
	for index, def in Upgrades.list() do
		local id = def.id
		local row = list:FindFirstChild(id)
		if not row then
			row = rowTemplate:Clone()
			row.Name = id
			row.Visible = true
			row.LayoutOrder = index
			find("Icon", row).Image = def.icon
			find("LineName", row).Text = def.name
			setLabel(find("Set", row), Text.setLevel)
			setLabel(find("Up", row), Text.upOne)
			local box = find("Amount", row)
			wireButton(find("Set", row), function()
				local level = tonumber(box and box.Text or "")
				if not level then
					status(false, Text.badNumber)
					return
				end
				ask({ action = "upgrade", id = id, level = level })
			end)
			wireButton(find("Up", row), function()
				ask({ action = "upgrade", id = id, level = Upgrades.level(player, id) + 1 })
			end)
			row.Parent = list
		end
		local level = Upgrades.level(player, id)
		find("Note", row).Text = Text.upgradeNote:format(level, max, Upgrades.describe(def, level))
		local box = find("Amount", row)
		if box and box:IsA("TextBox") and not box:IsFocused() then
			box.Text = tostring(level)
		end
	end
end

-- ==================== quests page ====================

local function renderQuests()
	local pageFrame = find("PageQuests")
	local list = pageFrame and pageFrame:FindFirstChild("List")
	local templates = gui and gui:FindFirstChild("Templates")
	local rowTemplate = templates and templates:FindFirstChild("QuestRow")
	if not (list and rowTemplate) then
		return
	end
	for index, id in Quests.order do
		local line = Quests.get(id)
		if not line then
			continue
		end
		local row = list:FindFirstChild(id)
		if not row then
			row = rowTemplate:Clone()
			row.Name = id
			row.Visible = true
			row.Parent = list
			local box = find("Amount", row)
			setLabel(find("Go", row), Text.goTo)
			setLabel(find("Skip", row), Text.skip)
			wireButton(find("Go", row), function()
				local step = tonumber(box and box.Text or "")
				if not step then
					status(false, Text.badNumber)
					return
				end
				ask({ action = "quest", line = id, step = step })
			end)
			wireButton(find("Skip", row), function()
				ask({ action = "questSkip", line = id })
			end)
		end
		row.LayoutOrder = index
		find("Portrait", row).Image = line.npc.portrait
		find("LineName", row).Text = line.name
		local step = player:GetAttribute(Quests.attr("Step", id))
		local state = player:GetAttribute(Quests.attr("State", id))
		local n = #line.steps
		find("Note", row).Text = if type(step) == "number" and step > n then Text.questFinished:format(n)
			else Text.questNote:format(if type(step) == "number" then step else 1, n, tostring(state or "Offer"))
		local box = find("Amount", row)
		if box and box:IsA("TextBox") and not box:IsFocused() then
			box.Text = tostring(if type(step) == "number" then math.min(step, n + 1) else 1)
		end
	end
end

-- ==================== mobs page ====================

local function tally(): { [string]: { total: number, dead: number } }
	local counts = {}
	for _, body in CollectionService:GetTagged(MapLayout.Tags.WorldEnemy) do
		local kind = body:GetAttribute("Archetype")
		if type(kind) == "string" then
			local c = counts[kind] or { total = 0, dead = 0 }
			c.total += 1
			if body:GetAttribute("Alive") == false then
				c.dead += 1
			end
			counts[kind] = c
		end
	end
	return counts
end

local function renderMobs()
	local pageFrame = find("PageMobs")
	local list = pageFrame and pageFrame:FindFirstChild("List")
	local templates = gui and gui:FindFirstChild("Templates")
	local header = templates and templates:FindFirstChild("WorldHeader")
	local rowTemplate = templates and templates:FindFirstChild("MobRow")
	if not (list and header and rowTemplate) then
		return
	end
	local counts = tally()
	local order = 0
	for _, worldId in Worlds.Order do
		local world = Worlds.get(worldId)
		if not world then
			continue
		end
		local kinds = {}
		for _, def in world.enemies or {} do
			table.insert(kinds, def)
		end
		table.sort(kinds, function(a, b)
			return (a.hp or 0) < (b.hp or 0)
		end)
		for _, def in world.bosses or {} do
			table.insert(kinds, def)
		end
		if #kinds == 0 then
			continue
		end
		order += 1
		local key = "World" .. worldId
		local h = list:FindFirstChild(key) or header:Clone()
		h.Name = key
		h.Visible = true
		h.LayoutOrder = order
		h.Text = Text.worldHeader:format(worldId, world.name)
		h.Parent = list
		for _, def in kinds do
			order += 1
			local isBoss = world.bosses ~= nil and world.bosses[def.id] ~= nil
			local row = list:FindFirstChild(def.id)
			if not row then
				row = rowTemplate:Clone()
				row.Name = def.id
				row.Visible = true
				row.Parent = list
				local id = def.id
				wireButton(find("Respawn", row), function()
					ask({ action = "respawn", archetype = id })
					renderMobs()
				end)
			end
			row.LayoutOrder = order
			-- secret enemies have no `portrait` (it would show in the Index); their
			-- admin-only picture is `adminPortrait`
			find("Portrait", row).Image = def.portrait or def.adminPortrait or ""
			find("MobName", row).Text = def.name
			local c = counts[def.id] or { total = 0, dead = 0 }
			local note = find("Note", row)
			if isBoss and c.total <= 1 then
				note.Text = Text.bossNote:format(if c.dead > 0 then Text.bossDead else Text.bossAlive)
			else
				note.Text = if c.dead > 0 then Text.mobNote:format(c.total, c.dead) else Text.mobNoteAllAlive:format(c.total)
			end
			setLabel(find("Respawn", row), if c.total > 1 then Text.respawnMany:format(c.total) else Text.respawnOne)
		end
	end
end

-- ==================== pages ====================

local function showPage(name: string)
	page = name
	for _, n in { "PagePlayer", "PageWeapons", "PageArmor", "PageTools", "PageMaterials", "PagePotions", "PageUpgrades", "PageQuests", "PageMobs" } do
		local p = find(n)
		if p then
			p.Visible = n == name
		end
	end
	local tabs = find("Tabs")
	for _, tab in if tabs then tabs:GetChildren() else {} do
		if tab:IsA("GuiButton") and tab:GetAttribute("Tab") then
			local on = tab:GetAttribute("Tab") == name
			tab:SetAttribute("Selected", on) -- the open tab stays grown (Util.ButtonFx)
			reskin(tab, attr(gui :: ScreenGui, if on then "SkinTabSelected" else "SkinTabIdle", nil))
		end
	end
	if name == "PagePlayer" then
		renderPlayer()
	elseif name == "PageWeapons" then
		renderWeapons()
	elseif name == "PageArmor" then
		renderArmor()
	elseif name == "PageTools" then
		renderTools()
	elseif name == "PageMaterials" then
		renderMaterials()
	elseif name == "PagePotions" then
		renderPotions()
	elseif name == "PageUpgrades" then
		renderUpgrades()
	elseif name == "PageQuests" then
		renderQuests()
	else
		renderMobs()
	end
end

-- A scrolling list's canvas follows its layout (aspect-sized items aren't seen
-- by AutomaticCanvasSize).
local function fitCanvas(list: Instance?)
	if not (list and list:IsA("ScrollingFrame")) then
		return
	end
	local layout = list:FindFirstChildWhichIsA("UIGridStyleLayout")
	if not layout then
		return
	end
	-- a list whose first row has an outline (Quests) has top / bottom padding, so the outline
	-- isn't clipped; the canvas makes room for it
	local padding = list:FindFirstChildOfClass("UIPadding")
	local function fit()
		local extra = if padding then padding.PaddingTop.Offset + padding.PaddingBottom.Offset else 0
		list.CanvasSize = UDim2.fromOffset(0, math.ceil(layout.AbsoluteContentSize.Y + extra) + 4)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()
end

local function isAdmin(): boolean
	return player:GetAttribute("IsAdmin") == true
end

local function toggle()
	local PanelWindow = deps.UI.PanelWindow
	if PanelWindow.isPanelOpen(PANEL) then
		PanelWindow.hidePanel()
	elseif isAdmin() then
		PanelWindow.showPanel(PANEL)
		showPage(page)
	end
end

function AdminUI.init(injected: any)
	deps = injected
	Format = deps.Util.Format
	WeaponTile = deps.Util.WeaponTile
	remote = deps.Remotes.getFunction("AdminAction")
end

function AdminUI.start()
	task.spawn(function()
		local found = deps.UI.PanelWindow.getPanel(PANEL, 15)
		if not found then
			warn("[AdminUI] no StarterGui/AdminPanel")
			return
		end
		gui = found
		window = found:FindFirstChild("Window") :: Frame
		deps.Util.FontDrop.watch(found)

		-- every word from Config/Admin
		find("Title").Text = Text.title
		find("Hint").Text = Text.hint
		for _, tab in find("Tabs"):GetChildren() do
			local target = tab:GetAttribute("Tab")
			if tab:IsA("GuiButton") and type(target) == "string" then
				setLabel(tab, Text.tabs[target] or target)
				wireButton(tab, function()
					showPage(target)
				end)
			end
		end
		for card, title in { CoinsCard = Text.coinsTitle, ExpCard = Text.expTitle, LevelCard = Text.levelTitle, HealthCard = Text.healthTitle, DamageCard = Text.damageTitle } do
			local c = find(card)
			if c then
				find("Title", c).Text = title
				setLabel(find("Add", c), Text.add)
				setLabel(find("Take", c), Text.take)
			end
		end
		wireAmountCard(find("CoinsCard"), "coins", Admin.quick.coins)
		wireAmountCard(find("ExpCard"), "exp", Admin.quick.exp)
		local levelCard = find("LevelCard")
		local setButton, upButton, levelBox = find("Set", levelCard), find("LevelUp", levelCard), find("Amount", levelCard)
		setLabel(setButton, Text.set)
		setLabel(upButton, Text.levelUp)
		wireButton(setButton, function()
			local level = read(levelBox)
			if not level then
				status(false, Text.badNumber)
				return
			end
			ask({ action = "level", level = level })
		end)
		wireButton(upButton, function()
			ask({ action = "levelUp" })
		end)
		local healthCard = find("HealthCard")
		if healthCard then
			local healthBox = find("Amount", healthCard)
			setLabel(find("Set", healthCard), Text.set)
			setLabel(find("Heal", healthCard), Text.heal)
			wireButton(find("Set", healthCard), function()
				local amount = read(healthBox)
				if not amount then
					status(false, Text.badNumber)
					return
				end
				ask({ action = "health", amount = amount })
			end)
			wireButton(find("Heal", healthCard), function()
				ask({ action = "heal" })
			end)
		end
		-- Give All (under the tabs): every weapon, armour set and material at once
		local giveAll = find("GiveAll")
		if giveAll then
			setLabel(giveAll, Text.giveAll)
			wireButton(giveAll, function()
				ask({ action = "giveAll" })
			end)
		end
		-- the Damage card: set your own damage multiplier, or put it back to x1
		local damageCard = find("DamageCard")
		if damageCard then
			local damageBox = find("Amount", damageCard)
			setLabel(find("Set", damageCard), Text.set)
			setLabel(find("Reset", damageCard), Text.damageReset)
			wireButton(find("Set", damageCard), function()
				local amount = read(damageBox)
				if not amount or amount <= 0 then
					status(false, Text.badNumber)
					return
				end
				ask({ action = "damage", amount = amount })
			end)
			wireButton(find("Reset", damageCard), function()
				ask({ action = "damage", amount = 1 })
			end)
		end
		local pill = find("Status")
		if pill then
			pill.BackgroundTransparency = 1
			setLabel(pill, "")
		end
		for _, name in { "PageWeapons", "PageArmor", "PageTools", "PageMaterials", "PagePotions", "PageUpgrades", "PageQuests", "PageMobs" } do
			fitCanvas(find(name):FindFirstChild("List"))
		end
		showPage(page)

		-- live values while it's open, on the page showing them (2026-10-20: these lists
		-- re-rendered on every material drop and weapon change with the panel shut, part of
		-- the hitch the user felt; opening the panel renders its page anyway)
		local function live(pageName: string, render: () -> ()): () -> ()
			return function()
				if found.Enabled and page == pageName then
					render()
				end
			end
		end
		for _, name in { "Coins", "ExpTotal" } do
			player:GetAttributeChangedSignal(name):Connect(live("PagePlayer", renderPlayer))
		end
		player:GetAttributeChangedSignal("OwnedWeapons"):Connect(live("PageWeapons", renderWeapons))
		player:GetAttributeChangedSignal("OwnedArmor"):Connect(live("PageArmor", renderArmor))
		player:GetAttributeChangedSignal("OwnedTools"):Connect(live("PageTools", renderTools))
		player:GetAttributeChangedSignal("Materials"):Connect(live("PageMaterials", renderMaterials))
		player:GetAttributeChangedSignal("Potions"):Connect(live("PagePotions", renderPotions))
		for _, def in Upgrades.list() do
			player:GetAttributeChangedSignal(Upgrades.attr(def.id)):Connect(live("PageUpgrades", renderUpgrades))
		end
		for _, id in Quests.order do
			for _, field in { "Step", "State" } do
				player:GetAttributeChangedSignal(Quests.attr(field, id)):Connect(live("PageQuests", renderQuests))
			end
		end
		-- the Health card's badge follows the character's max HP
		local function watchHealth(character: Model)
			local h = character:WaitForChild("Humanoid", 10)
			if h and h:IsA("Humanoid") then
				h:GetPropertyChangedSignal("MaxHealth"):Connect(live("PagePlayer", renderPlayer))
			end
		end
		player:GetAttributeChangedSignal("DamageMultiplier"):Connect(live("PagePlayer", renderPlayer))
		player.CharacterAdded:Connect(watchHealth)
		if player.Character then
			task.spawn(watchHealth, player.Character)
		end
		task.spawn(function()
			while true do
				task.wait(1)
				if found.Enabled and page == "PageMobs" then
					renderMobs()
				end
			end
		end)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Admin.toggleKey and not processed then
			toggle()
		end
	end)

	-- the HUD's Admin side button (a controller, under Shop): admins only
	task.spawn(function()
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", 15)
		local button = hud and hud:FindFirstChild("AdminButton", true)
		if not (button and button:IsA("GuiButton")) then
			return
		end
		local function show()
			button.Visible = isAdmin()
		end
		player:GetAttributeChangedSignal("IsAdmin"):Connect(show)
		show()
		deps.UI.HotbarUI.wireHover(button)
		button.Activated:Connect(toggle)
	end)
end

return AdminUI
