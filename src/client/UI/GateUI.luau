--!strict
-- GateUI: wires the hand-built world gate signs and opens the gates the player
-- has unlocked (World 2 gate, style B "Ranger's Lodge Gate", 2026-10-10).
--
-- A sign is a SurfaceGui in StarterGui with a "GateId" attribute, adorned to its
-- gate's SignBoard (Workspace.Shared.Gates.<model>). Every word comes from
-- Shared.Config.Gates.Text (the user's rule: UI text lives in code); the title
-- is the world's name from Config/Worlds. This fills in:
--   * Banner/Label: Text.banner with the world number; Title: the world's name.
--   * LevelRow / CoinsRow: Label (Text.level / Text.coins), and Check when the
--     player meets it (or owns the gate), else Have (Text.youLevel / youCoins).
--   * MaterialRow1, 2... (2026-10-19): one per entry of the gate's `materials`, the
--     same pieces, with the material's icon on Icon (Text.material / youMaterial);
--     rows past the list are hidden.
--   * Buy (Skin, Content: Lock, Label (+ Ink1..4, Face), Coin, Amount), one of the game's pill buttons
--     (option A on the Quest Guide canvas, 2026-10-21): its Skin takes the gui's
--     Skin_<Met|Locked|Unlocked> image and reads Text.buy / Text.locked /
--     Text.unlocked alone (the requirements are the rows above it; its Lock, Coin and
--     Amount stay hidden since 2026-10-21). It is Active only
--     while Met, so Util.ButtonFx grows and squashes it (its FxScale) only then.
--     Pressing it while Met fires Remotes.GateBuy { id } (GateService checks
--     everything again).
--   * Every gate part with the attribute OpensWithGate (the curtain and its
--     vines, the SignBoard and its ropes) turns invisible and walk-through once
--     the player's HighestWorld reaches the gate's world, and the sign itself is
--     switched off. It's local, so each player's gate opens alone.
-- Luckiest Guy labels have UIPaddings, so Util.FontDrop centres them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Gates = require(Config:WaitForChild("Gates"))
local Materials = require(Config:WaitForChild("Materials"))

local GateUI = {}

local player = Players.LocalPlayer
local deps: any = nil
local buyRemote: RemoteEvent? = nil

-- each opening part's own CanCollide, so closing puts it back
local closedCollide: { [BasePart]: boolean } = {}

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- 12500 -> "12,500"
local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function worldName(id: number): string
	local folder = Config:FindFirstChild("Worlds")
	for _, module in if folder then folder:GetChildren() else {} do
		if module:IsA("ModuleScript") then
			local ok, def = pcall(require, module)
			if ok and type(def) == "table" and def.id == id and type(def.name) == "string" then
				return def.name
			end
		end
	end
	return ""
end

local function modelOf(gate: Gates.Gate): Instance?
	local shared = workspace:FindFirstChild("Shared")
	local folder = shared and shared:FindFirstChild("Gates")
	return folder and folder:FindFirstChild(gate.model)
end

local function setOpen(model: Instance?, open: boolean)
	for _, d in if model then model:GetDescendants() else {} do
		if d:IsA("BasePart") and d:GetAttribute("OpensWithGate") then
			if closedCollide[d] == nil then
				closedCollide[d] = d.CanCollide
			end
			d.LocalTransparencyModifier = if open then 1 else 0
			d.CanCollide = not open and closedCollide[d]
		end
	end
end

local function setText(label: Instance?, text: string)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function fillRow(row: Instance?, text: string, met: boolean, short: string, shortColor: Color3)
	if not row then
		return
	end
	setText(row:FindFirstChild("Label"), text)
	local check = row:FindFirstChild("Check")
	if check and check:IsA("GuiObject") then
		check.Visible = met
	end
	local have = row:FindFirstChild("Have")
	if have and have:IsA("TextLabel") then
		have.Visible = not met
		have.Text = short
		have.TextColor3 = shortColor
	end
end

-- "Met" | "Locked" | "Unlocked"
local function materialsMet(gate: Gates.Gate): boolean
	local held = Materials.counts(player)
	for _, item in gate.materials or {} do
		if (held[item.id] or 0) < item.count then
			return false
		end
	end
	return true
end

local function stateOf(gate: Gates.Gate): string
	if number("HighestWorld", 1) >= gate.world then
		return "Unlocked"
	elseif number("Level", 1) >= gate.level and number("Coins", 0) >= gate.coins and materialsMet(gate) then
		return "Met"
	end
	return "Locked"
end

local function render(gui: SurfaceGui, gate: Gates.Gate)
	local Text = Gates.Text
	local state = stateOf(gate)
	local unlocked = state == "Unlocked"
	-- a bought gate's sign goes away with its ropes (OpensWithGate parts)
	gui.Enabled = not unlocked
	local level, coins = number("Level", 1), number("Coins", 0)
	local shortColor = attribute(gui, "ShortColor", Color3.fromRGB(224, 48, 42))
	local banner = gui:FindFirstChild("Banner")
	setText(banner and banner:FindFirstChild("Label"), Text.banner:format(gate.world))
	setText(gui:FindFirstChild("Title"), worldName(gate.world))
	fillRow(gui:FindFirstChild("LevelRow"), Text.level:format(gate.level), unlocked or level >= gate.level, Text.youLevel:format(level), shortColor)
	fillRow(gui:FindFirstChild("CoinsRow"), Text.coins:format(deps.Util.Format.coins(gate.coins)), unlocked or coins >= gate.coins, Text.youCoins:format(deps.Util.Format.coins(coins)), shortColor)
	local held = Materials.counts(player)
	local items = gate.materials or {}
	for i = 1, 8 do
		local row = gui:FindFirstChild("MaterialRow" .. i)
		if not row then
			break
		end
		local item = items[i]
		local shadow = gui:FindFirstChild("MaterialRow" .. i .. "Shadow")
		for _, piece in { row, shadow } do
			if piece and piece:IsA("GuiObject") then
				piece.Visible = item ~= nil
			end
		end
		if item then
			local def = Materials.get(item.id)
			local icon = row:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") and def and def.icon then
				icon.Image = def.icon
			end
			local have = held[item.id] or 0
			fillRow(row, Text.material:format(commas(item.count), def and def.name or item.id), unlocked or have >= item.count, Text.youMaterial:format(commas(have)), shortColor)
		end
	end

	local buy = gui:FindFirstChild("Buy")
	local content = buy and buy:FindFirstChild("Content")
	if buy and buy:IsA("GuiButton") and content then
		-- the game's pill buttons (option A, 2026-10-21): green "Buy  2,500" once you can,
		-- grey with a padlock and the price while locked; ButtonFx grows / squashes it
		-- only while it's Active
		-- just the word (2026-10-21, the user): the four requirements are listed above it,
		-- so the button no longer repeats the price
		-- the Label is the word's ink layer; its copies (Ink1..4 a pixel off each way, then the
		-- white Face) fill the B's small counters, which a UIStroke leaves open (2026-10-21)
		local label = content:FindFirstChild("Label")
		local word = if unlocked then Text.unlocked elseif state == "Met" then Text.buy else Text.locked
		setText(label, word)
		for _, layer in if label then label:GetChildren() else {} do
			setText(layer, word)
		end
		local show = { Label = true, Lock = false, Coin = false, Amount = false }
		for name, visible in show do
			local piece = content:FindFirstChild(name)
			if piece and piece:IsA("GuiObject") then
				piece.Visible = visible
			end
		end
		local skin = buy:FindFirstChild("Skin")
		local image = attribute(gui, "Skin_" .. state, nil)
		if skin and skin:IsA("ImageLabel") and type(image) == "string" then
			skin.Image = image
		end
		buy.Active = state == "Met"
	end
	setOpen(modelOf(gate), unlocked)
end

local function wire(gui: SurfaceGui)
	local id = gui:GetAttribute("GateId")
	local gate = if type(id) == "string" then Gates.byId(id) else nil
	if not gate or gui:GetAttribute("GateWired") then
		return
	end
	gui:SetAttribute("GateWired", true)
	local model = modelOf(gate)
	local board = model and model:FindFirstChild("SignBoard", true)
	if board and board:IsA("BasePart") then
		gui.Adornee = board
	end
	deps.Util.FontDrop.watch(gui)

	local function update()
		render(gui, gate)
	end

	local buy = gui:FindFirstChild("Buy")
	if buy and buy:IsA("GuiButton") then
		buy.Activated:Connect(function()
			if stateOf(gate) == "Met" and buyRemote then
				-- the gate opening (HighestWorld reaching it) plays the Purchase sound
				local before = number("HighestWorld", 1)
				local watch: RBXScriptConnection? = nil
				watch = player:GetAttributeChangedSignal("HighestWorld"):Connect(function()
					if number("HighestWorld", 1) > before then
						UiSound.play("Purchase")
					end
					if watch then
						watch:Disconnect()
					end
				end)
				task.delay(5, function()
					if watch then
						watch:Disconnect()
					end
				end)
				buyRemote:FireServer({ id = gate.id })
			end
		end)
	end
	for _, name in { "Level", "Coins", "HighestWorld", "Materials" } do
		player:GetAttributeChangedSignal(name):Connect(update)
	end
	update()
end

function GateUI.init(injected: any)
	deps = injected
	buyRemote = deps.Remotes.getEvent("GateBuy")
end

function GateUI.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local function check(child: Instance)
		if child:IsA("SurfaceGui") and child:GetAttribute("GateId") then
			wire(child)
		end
	end
	for _, child in playerGui:GetChildren() do
		check(child)
	end
	playerGui.ChildAdded:Connect(check)
end

return GateUI
