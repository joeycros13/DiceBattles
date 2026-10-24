--!strict
-- NameTagController: every other player's name over their head in the game's own font
-- (2026-10-23, the user: "swapping the boring font with our own for the players", as the
-- NPCs' name tags were removed). Roblox's own name (and its health bar) is switched off
-- on this client (Humanoid.DisplayDistanceType = None) and a clone of the hand-built
-- ReplicatedStorage/Assets/UI/NameTag BillboardGui (Label: Luckiest Guy, white, ink
-- stroke; sized in studs, StudsOffset just under the weekly LeaderMedal) goes on the
-- Head showing the DisplayName. Your own name isn't shown, as in Roblox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NameTagController = {}

local TAG_NAME = "NameTag"
local player = Players.LocalPlayer

local function template(): BillboardGui?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local t = ui and ui:FindFirstChild(TAG_NAME)
	return if t and t:IsA("BillboardGui") then t else nil
end

local function tag(who: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	if who == player then
		return
	end
	local head = character:WaitForChild("Head", 10)
	local t = template()
	if not (head and head:IsA("BasePart") and t) or head:FindFirstChild(TAG_NAME) then
		return
	end
	local gui = t:Clone()
	gui.Adornee = head
	local label = gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = who.DisplayName
	end
	gui.Parent = head
end

local function watch(who: Player)
	who.CharacterAdded:Connect(function(character)
		tag(who, character)
	end)
	if who.Character then
		task.spawn(tag, who, who.Character)
	end
	who:GetPropertyChangedSignal("DisplayName"):Connect(function()
		local head = who.Character and who.Character:FindFirstChild("Head")
		local gui = head and head:FindFirstChild(TAG_NAME)
		local label = gui and gui:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = who.DisplayName
		end
	end)
end

function NameTagController.init(_injected: any) end

function NameTagController.start()
	Players.PlayerAdded:Connect(watch)
	for _, who in Players:GetPlayers() do
		watch(who)
	end
end

return NameTagController
