--!strict
-- HotbarUI: wires the hand-built hotbar, StarterGui/WeaponHud/Hotbar, and the
-- Inventory button beside it, StarterGui/WeaponHud/InventoryButton.
--
--   * InventoryButton (left side of the screen): opens and closes the Inventory.
--   * Slot1 (key 1): the one weapon in the hotbar -- the selected weapon (the
--     Dagger at first, then whatever was last picked in the Inventory). It looks
--     like the weapon's Inventory tile: its "Skin" takes the rarity's tile image
--     (from the shared weapon tile, Util.WeaponTile), and
--     "Picture" shows the weapon's drawn icon (def.icon), bigger than the slot so
--     it pokes out. A weapon without an icon falls back to the "Icon" viewport.
--     Clicking it or pressing 1 takes the weapon out or puts it away
--     (WeaponController.toggleHolster).
--   * The slot holding what's in hand (the weapon taken out, or a tool) stays grown
--     like a hovered one (user, 2026-10-19), so it shows what's in your hand. The
--     Hotbar's HeldScale attribute sets how big (default: HoverScale). No other
--     highlight (the user's call).
--   * Tool slots (2026-10-18): Slot2.. are copies of Slot1, one per gathering tool kind
--     (their "ToolKind" attribute, Config/Tools.Kinds order: Axe, Pickaxe, Shovel, Rod
--     on keys 2-5). A slot shows only once the player owns a tool of its kind, and
--     shows their best one (highest tier) the same way Slot1 shows the weapon. Clicking
--     it or pressing its key takes that tool out (putting the weapon away) or puts it
--     back (WeaponController.holdTool).
--   * The side buttons (Inventory, Index, Shop) are bubbly drawn icons with no
--     circle behind them, and a Label (plus a LabelShadow) centred on the
--     drawing's bottom edge; Util.FontDrop centres the Luckiest Guy text.
--   * Hovering a slot or the Inventory button quickly grows it: its visuals sit
--     in a "Content" frame whose "HoverScale" UIScale is tweened, so the row
--     never reflows. The Hotbar's HoverScale / HoverGrowTime / HoverShrinkTime
--     attributes tune it.
-- Roblox's own backpack hotbar is switched off: it reserves the number keys and
-- this one replaces it.
-- Everything visual is authored; this only fills in the weapon previews.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Tools = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tools"))

local HotbarUI = {}

local PanelWindow: any = nil
local WeaponController: any = nil
local FontDrop: any = nil

local SIDE_BUTTONS = { "InventoryButton", "IndexButton", "ShopButton", "AdminButton", "StatsButton", "LeaderboardButton", "SettingsButton" }

local GUI_TIMEOUT = 15
local INVENTORY = "Inventory"
local player = Players.LocalPlayer

local hotbar: Instance? = nil
-- The weapon the slot's viewport currently shows.
local shownWeapon: string? = nil
-- slot name -> the tool it currently shows ("" for none)
local shownTools: { [string]: string } = {}
-- number keys for the tool slots: Two is Slot2 (Tools.Kinds[1]) and so on
local TOOL_KEYS = { Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }

local function slot(name: string): GuiButton?
	local found = hotbar and hotbar:FindFirstChild(name)
	return if found and found:IsA("GuiButton") then found else nil
end

local function iconOf(button: Instance?): ViewportFrame?
	local icon = button and button:FindFirstChild("Icon", true)
	return if icon and icon:IsA("ViewportFrame") then icon else nil
end

local WeaponTile = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("WeaponTile"))
-- the 3D view of a weapon (shared with every screen: Util.WeaponTile)
local showWeapon = WeaponTile.showModel

-- Show an item (weapon or tool) in a slot: its rarity skin, and its drawn icon or,
-- without one, its 3D view.
local function fill(button: GuiButton, def: any)
	-- the rarity skin comes from the shared weapon tile (Util.WeaponTile), so the
	-- slot always matches the Inventory and the Index
	local skin = button:FindFirstChild("Skin", true)
	if skin and skin:IsA("ImageLabel") then
		skin.Image = WeaponTile.skin(def.rarity)
	end
	local picture = button:FindFirstChild("Picture", true)
	local icon = iconOf(button)
	local drawn = def.icon ~= nil and picture ~= nil and picture:IsA("ImageLabel")
	if picture and picture:IsA("ImageLabel") then
		picture.Visible = drawn
		picture.Image = def.icon or ""
	end
	if icon then
		icon.Visible = not drawn
		if not drawn then
			showWeapon(icon, def.id)
		end
	end
end

-- Each tool slot: shown with the best tool of its kind, or hidden if the player has none.
local function refreshTools()
	if not hotbar then
		return
	end
	local owned = Tools.owned(player)
	for _, child in hotbar:GetChildren() do
		local kind = child:GetAttribute("ToolKind")
		if not (type(kind) == "string" and child:IsA("GuiButton")) then
			continue
		end
		local best = Tools.bestOf(owned, kind)
		child.Visible = best ~= nil
		local id = if best then best.id else ""
		if shownTools[child.Name] ~= id then
			shownTools[child.Name] = id
			if best then
				fill(child, best)
			end
		end
	end
end


local function tuning(name: string, fallback: number): number
	local value = hotbar and hotbar:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- Each wired button's size state: hovered, and (hotbar slots) holding what's in hand.
type Grow = { hovered: boolean, held: boolean, set: (boolean?) -> () }
local grows: { [GuiButton]: Grow } = {}

-- Grow a slot while the pointer is over it or while it holds what's in hand, and
-- ease it back after.
local function wireHover(button: GuiButton)
	local content = button:FindFirstChild("Content")
	local scale = content and content:FindFirstChild("HoverScale")
	if not (scale and scale:IsA("UIScale")) then
		return
	end
	local tween: Tween? = nil
	local state: Grow
	local function set(instant: boolean?)
		local hover = tuning("HoverScale", 1.15)
		local target = math.max(if state.hovered then hover else 1, if state.held then tuning("HeldScale", hover) else 1)
		local growing = target > (scale :: UIScale).Scale
		local time = if instant then 0 elseif growing then tuning("HoverGrowTime", 0.12) else tuning("HoverShrinkTime", 0.1)
		if tween then
			tween:Cancel()
		end
		tween = TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target })
		;(tween :: Tween):Play()
	end
	state = { hovered = false, held = false, set = set }
	grows[button] = state
	button.MouseEnter:Connect(function()
		state.hovered = true
		set()
	end)
	button.MouseLeave:Connect(function()
		state.hovered = false
		set()
	end)
end

-- Mark the hotbar slot that holds what's in hand: Slot1 while the weapon is out, a
-- tool slot while its kind is out.
local function refreshHeld()
	if not hotbar then
		return
	end
	local heldKind = player:GetAttribute("HeldTool")
	local weaponOut = player:GetAttribute("Holstered") ~= true and heldKind == nil
	for _, child in hotbar:GetChildren() do
		local state = child:IsA("GuiButton") and grows[child]
		if not state then
			continue
		end
		local kind = child:GetAttribute("ToolKind")
		local held = if kind ~= nil then kind == heldKind else (child.Name == "Slot1" and weaponOut)
		if held ~= state.held then
			state.held = held
			state.set()
		end
	end
end

local function refresh()
	refreshTools()
	refreshHeld()
	local selected = WeaponController.selected()
	local button = slot("Slot1")
	if not (button and selected) or selected.id == shownWeapon then
		return
	end
	shownWeapon = selected.id
	fill(button, selected)
end

-- the side buttons' grow-on-hover, for the modules that own the other buttons
HotbarUI.wireHover = wireHover

function HotbarUI.init(injected: any)
	PanelWindow = injected.UI.PanelWindow
	WeaponController = injected.Controllers.WeaponController
	FontDrop = injected.Util.FontDrop
end

function HotbarUI.start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	task.spawn(function()
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		local found = hud and hud:FindFirstChild("Hotbar")
		if not found then
			warn("[HotbarUI] no WeaponHud/Hotbar in StarterGui")
			return
		end
		hotbar = found
		-- the side buttons stack in WeaponHud/SideButtons (a UIListLayout), so look deep
		for _, name in SIDE_BUTTONS do
			local button = hud:FindFirstChild(name, true)
			if button then
				FontDrop.watch(button)
			end
		end

		local inventory = hud:FindFirstChild("InventoryButton", true)
		if inventory and inventory:IsA("GuiButton") then
			wireHover(inventory)
			inventory.Activated:Connect(function()
				if PanelWindow.isPanelOpen(INVENTORY) then
					PanelWindow.hidePanel()
				else
					PanelWindow.showPanel(INVENTORY)
				end
			end)
		end
		local weaponSlot = slot("Slot1")
		if weaponSlot then
			wireHover(weaponSlot)
			weaponSlot.Activated:Connect(WeaponController.toggleHolster)
		end
		for _, child in found:GetChildren() do
			local kind = child:GetAttribute("ToolKind")
			if type(kind) == "string" and child:IsA("GuiButton") then
				wireHover(child)
				child.Activated:Connect(function()
					if not player:GetAttribute("InputLocked") then
						WeaponController.holdTool(kind)
					end
				end)
			end
		end

		WeaponController.onChanged(refresh)
		refresh()
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- InputLocked: talking to an NPC (QuestController)
		if processed or Players.LocalPlayer:GetAttribute("InputLocked") then
			return
		end
		if input.KeyCode == Enum.KeyCode.One then
			WeaponController.toggleHolster()
			return
		end
		local index = table.find(TOOL_KEYS, input.KeyCode)
		local kind = index and Tools.Kinds[index]
		if kind and Tools.bestOf(Tools.owned(player), kind) then
			WeaponController.holdTool(kind)
		end
	end)
end

return HotbarUI
