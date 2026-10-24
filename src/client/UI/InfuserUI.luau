--!strict
-- InfuserUI: the Infuser altar's panel (Infuser canvas option B "Blade Showcase", the user's pick,
-- 2026-10-12). Wires the hand-built StarterGui/InfuserPanel; nothing here builds UI.
--
-- InfuserController opens it from the altar's "Infuse" prompt with InfuserUI.open(altar). It shows:
--   * BladeCard: the Worldheart Blade, a dark silhouette ("???") until it has awakened;
--   * Right/Sockets/Socket1..8: one row per world's socket; a filled socket shows its core's
--     icon, the socket this altar's core would fill shows it faded once the player holds it,
--     every other one "?" and "N · ???" (where cores drop stays secret);
--   * Right/Line: the gui's TextHint / TextReady / TextNeedBlade / TextAwake / TextNext;
--   * Right/Needs: the blade and the core this altar asks for (vague until the player has them);
--   * Right/Infuse: the Craft button's skins and label outlines (Skin* / Stroke* Ready, Locked, Done); it
--     asks the server (Remotes.InfuseCore) and closes the panel for the reveal.
-- The panel refills while open when the player's materials, weapons or infused cores change, and
-- closes when they walk away from the altar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Infuse = require(Config:WaitForChild("Infuse"))
local Materials = require(Config:WaitForChild("Materials"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Format = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Format"))

local InfuserUI = {}

local PANEL = "Infuser"
local GUI_TIMEOUT = 15
local LEAVE_SLACK = 4
local READY_ROW = Color3.fromHex("ffe7a3")
local READY_STROKE = Color3.fromHex("c9922a")
local FILLED_ROW = Color3.fromHex("e9dcff")
local PLAIN_ROW = Color3.fromHex("f1dfc0")
local INK = Color3.fromHex("231b2e")
local CHIP_MET = Color3.fromHex("bfeab3")
local CHIP_PLAIN = Color3.fromHex("e6dccb")
local ERROR_TEXT = Color3.fromHex("c0392b")
local LINE_TEXT = Color3.fromHex("3d1866")

local REASONS = {
	range = "Stand closer to the altar.",
	core = "The altar senses no core.",
	blade = "An old blade must be offered.",
	order = "The cores go in world order.",
	done = "This socket is already filled.",
}

local player = Players.LocalPlayer
local deps: any = nil
local PanelWindow: any = nil
local gui: ScreenGui? = nil
local altar: Instance? = nil
local busy = false

local function attr(name: string, fallback: string): string
	local value = gui and gui:GetAttribute(name)
	return if type(value) == "string" then value else fallback
end

local function owns(id: string): boolean
	local text = player:GetAttribute("OwnedWeapons")
	for owned in (if type(text) == "string" then text else ""):gmatch("[^,]+") do
		if owned == id then
			return true
		end
	end
	return false
end

local function altarWorld(): number
	local w = altar and altar:GetAttribute("World")
	return if type(w) == "number" then w else 1
end

type View = { state: string, core: string?, hasCore: boolean, hasBlade: boolean, awake: boolean, infused: { [string]: boolean } }

local function view(): View
	local world = altarWorld()
	local core = Infuse.coreOfWorld(world)
	local infused = Infuse.infused(player)
	local hasCore = core ~= nil and (Materials.counts(player)[core :: string] or 0) >= 1
	local awake = infused[Infuse.FIRST] == true
	for tier = 1, Infuse.SOCKETS do
		if owns(Infuse.bladeOf(tier)) then
			awake = true
		end
	end
	local state
	if core and infused[core] then
		state = "Done"
	elseif core == Infuse.FIRST then
		local hasBlade = owns(Infuse.BLADE)
		state = if hasBlade and hasCore then "Ready" elseif hasCore then "NeedBlade" else "Hint"
		return { state = state, core = core, hasCore = hasCore, hasBlade = hasBlade, awake = awake, infused = infused }
	else
		-- cores go in world order: an earlier world's core is still missing
		state = if awake and hasCore and not Infuse.isNext(player, core :: string) then "Order"
			elseif awake and hasCore then "Ready"
			else "Hint"
	end
	return { state = state, core = core, hasCore = hasCore, hasBlade = awake, awake = awake, infused = infused }
end

local function setStroke(inst: Instance, color: Color3)
	local s = inst:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = color
	end
end

local function fill()
	local g = gui
	if not g then
		return
	end
	local v = view()
	local win = g:FindFirstChild("Window") :: any
	local inner = win.Inner
	-- the blade
	local card = inner.BladeCard
	card.Blade.ImageColor3 = if v.awake then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
	card.Blade.ImageTransparency = if v.awake then 0 else 0.45
	card.BladeName.Text = if v.awake then "Worldheart Blade" else "???"
	-- its stats: now, or now -> after this core (Config/Infuse tiers); hidden while it's still a secret
	local stats = card:FindFirstChild("Stats")
	if stats then
		local pct = function(x: number): number
			return math.floor(x * 100 + 0.5)
		end
		local count = 0
		for _ in v.infused do
			count += 1
		end
		if v.state == "Ready" and v.core == Infuse.FIRST then
			stats.Text = attr("StatsAwaken", "Damage %s"):format(Format.commas(Infuse.tier(1).damage))
		elseif v.state == "Ready" then
			local now, after = Infuse.tier(count), Infuse.tier(count + 1)
			stats.Text = attr("StatsUpgrade", "Damage %s → %s"):format(Format.commas(now.damage), Format.commas(after.damage), pct(now.speedBonus), pct(after.speedBonus), pct(now.reachBonus), pct(after.reachBonus))
		elseif v.awake then
			local now = Infuse.tier(count)
			stats.Text = attr("StatsNow", "Damage %s"):format(Format.commas(now.damage), pct(now.speedBonus), pct(now.reachBonus))
		end
		stats.Visible = v.awake or v.state == "Ready"
	end
	-- the sockets
	local world = altarWorld()
	for i = 1, Infuse.SOCKETS do
		local row = inner.Right.Sockets:FindFirstChild("Socket" .. i) :: any
		if row then
			local id = Infuse.coreOfWorld(i)
			local def = id and Materials.get(id)
			local filled = id ~= nil and (v.infused[id :: string] == true or (i == 1 and v.awake))
			local offered = not filled and i == world and v.hasCore
			local shown = def ~= nil and (filled or offered)
			row.Gem.Icon.Visible = shown
			row.Gem.Icon.Image = if def and def.icon then def.icon else ""
			row.Gem.Icon.ImageTransparency = if filled then 0 else 0.45
			row.Gem.Unknown.Visible = not shown
			row.Label.Text = ("%d · %s"):format(i, if shown and def then def.name else "???")
			local ready = offered and v.state == "Ready"
			row.BackgroundColor3 = if ready then READY_ROW elseif filled then FILLED_ROW else PLAIN_ROW
			setStroke(row, if ready then READY_STROKE else INK)
		end
	end
	-- the line and the needs
	local right = inner.Right
	-- the altar's own world in the header pill ("World 2 · Redwood Forest")
	local worldDef = Worlds.get(world)
	local worldName = if worldDef then (worldDef.name:gsub("^The ", "")) else ""
	win.World.Label.Text = ("World %d · %s"):format(world, worldName)
	local coreName = if v.core and Materials.get(v.core) then (Materials.get(v.core) :: any).name else ""
	right.Line.TextColor3 = LINE_TEXT
	right.Line.Text = if v.state == "Ready" and v.core ~= Infuse.FIRST then attr("TextReadyLater", "The %s finds its socket in the blade."):format(coreName)
		elseif v.state == "Ready" then attr("TextReady", "")
		elseif v.state == "NeedBlade" then attr("TextNeedBlade", "")
		elseif v.state == "Order" then attr("TextOrder", "The %s waits for the cores of the worlds before it."):format(coreName)
		elseif v.state == "Done" then (if v.core == Infuse.FIRST then attr("TextAwake", "") else attr("TextNext", ""))
		else attr("TextHint", "")
	local coreDef = v.core and Materials.get(v.core)
	local bladeChip, coreChip = right.Needs.BladeNeed, right.Needs.CoreNeed
	if v.core == Infuse.FIRST then
		bladeChip.Label.Text = if v.state == "Done" then "Rusty Blade: used" elseif v.hasBlade then "Rusty Blade" else "An old blade"
	else
		bladeChip.Label.Text = if v.awake then "Worldheart Blade" else "An awakened blade"
	end
	coreChip.Label.Text = if v.state == "Done" then (if coreDef then coreDef.name .. ": set" else "Set")
		elseif v.hasCore and coreDef then coreDef.name
		else "A world's heart"
	bladeChip.BackgroundColor3 = if v.hasBlade and v.state ~= "Done" then CHIP_MET else CHIP_PLAIN
	coreChip.BackgroundColor3 = if v.hasCore and v.state ~= "Done" then CHIP_MET else CHIP_PLAIN
	-- the button
	local button = right.Infuse
	local ready = v.state == "Ready"
	button.Skin.Image = if ready then button:GetAttribute("SkinReady")
		elseif v.state == "Done" then button:GetAttribute("SkinDone")
		else button:GetAttribute("SkinLocked")
	button.Label.Text = if v.state == "Done" then attr("ButtonDone", "Awakened!") else attr("ButtonInfuse", "Infuse")
	local strokeColor = button:GetAttribute(if ready then "StrokeReady" elseif v.state == "Done" then "StrokeDone" else "StrokeLocked")
	local labelStroke = button.Label:FindFirstChildOfClass("UIStroke")
	if labelStroke and typeof(strokeColor) == "Color3" then
		labelStroke.Color = strokeColor
	end
	button.Active = ready
	button.AutoButtonColor = false
end

local function onInfuse()
	if busy or not altar then
		return
	end
	local v = view()
	if v.state ~= "Ready" or not v.core then
		return
	end
	busy = true
	local ok, reason = deps.Remotes.getFunction("InfuseCore"):InvokeServer(v.core)
	busy = false
	if ok then
		PanelWindow.hidePanel()
	elseif gui then
		UiSound.play("Refuse")
		local line = (gui:FindFirstChild("Window") :: any).Inner.Right.Line
		line.TextColor3 = ERROR_TEXT
		line.Text = REASONS[reason] or "The altar does not answer."
	end
end

function InfuserUI.open(model: Instance)
	if not gui then
		return
	end
	altar = model
	fill()
	PanelWindow.showPanel(PANEL)
end

function InfuserUI.init(injected: any)
	deps = injected
	PanelWindow = deps.UI.PanelWindow
end

function InfuserUI.start()
	task.spawn(function()
		local found = player:WaitForChild("PlayerGui"):WaitForChild("InfuserPanel", GUI_TIMEOUT)
		if not (found and found:IsA("ScreenGui")) then
			warn("[InfuserUI] no InfuserPanel ScreenGui in StarterGui")
			return
		end
		gui = found
		local button = (found:FindFirstChild("Window") :: any).Inner.Right.Infuse
		button.Activated:Connect(onInfuse)
		if deps.Util.FontDrop then
			deps.Util.FontDrop.watch(found)
		end
	end)
	for _, name in { "Materials", "OwnedWeapons", "InfusedCores" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if PanelWindow.isPanelOpen(PANEL) then
				fill()
			end
		end)
	end
	-- walking away closes it
	RunService.Heartbeat:Connect(function()
		if not (altar and PanelWindow.isPanelOpen(PANEL)) then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local at = if altar:IsA("Model") then altar:GetPivot().Position else nil
		if root and root:IsA("BasePart") and at then
			local offset = root.Position - at
			if Vector2.new(offset.X, offset.Z).Magnitude > Infuse.RANGE + LEAVE_SLACK then
				PanelWindow.hidePanel()
			end
		end
	end)
end

return InfuserUI
