--!strict
-- LeaderFlairController: the weekly leaderboard winners' flair, on every player's
-- character, for everyone to see (2026-10-22, the user's picks on the "Leaderboard
-- rewards" canvas, https://claude.ai/artifact/Sjkt4yWCvqYH2dWYRot9Vg):
--   * medal A over the head: a clone of the hand-built ReplicatedStorage/Assets/UI/
--     LeaderMedal BillboardGui (its Medal image = the player's best medal, gold / silver /
--     bronze from Config/Leaderboards.Medals) on the Head, while the player's
--     LeaderMedal attribute is set;
--   * the #1 trail: a clone of ReplicatedStorage/Assets/Effects/LeaderTrails/<board> (an
--     Attachment holding the board's ParticleEmitters: gold coins for Coins, blue EXP
--     stars for Levels, red-orange sparks for Kills) on the HumanoidRootPart, while the
--     player's LeaderTrail attribute names a board; its emitters only run while the
--     character moves (faster than the trail's MinSpeed attribute, default 2 studs/s).
-- LeaderboardService publishes both attributes and clears them at the next weekly reset.
-- Every client builds these for every player itself, so nothing goes through the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Leaderboards = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Leaderboards"))

local LeaderFlairController = {}

local MEDAL_NAME = "LeaderMedal"
local TRAIL_NAME = "LeaderTrail"
local MOVE_CHECK = 0.15 -- seconds between the trails' moving checks

local assets: Instance? = nil
local watched: { [Player]: { RBXScriptConnection } } = {}
local trails: { [Player]: Attachment } = {}

local function medalTemplate(): BillboardGui?
	local ui = assets and assets:FindFirstChild("UI")
	local t = ui and ui:FindFirstChild(MEDAL_NAME)
	return if t and t:IsA("BillboardGui") then t else nil
end

local function trailTemplate(board: string): Attachment?
	local effects = assets and assets:FindFirstChild("Effects")
	local folder = effects and effects:FindFirstChild("LeaderTrails")
	local t = folder and folder:FindFirstChild(board)
	return if t and t:IsA("Attachment") then t else nil
end

-- Put the player's medal and trail on their current character (or take them off).
local function refresh(who: Player)
	local character = who.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	local tier = who:GetAttribute("LeaderMedal")
	local medal = if type(tier) == "string" then Leaderboards.Medals[tier] else nil
	local shown = head and head:FindFirstChild(MEDAL_NAME)
	if medal and head and head:IsA("BasePart") then
		local template = medalTemplate()
		if not shown and template then
			shown = template:Clone()
			;(shown :: BillboardGui).Adornee = head
			shown.Parent = head
		end
		local image = shown and shown:FindFirstChild("Medal", true)
		if image and image:IsA("ImageLabel") then
			image.Image = medal.medal
		end
	elseif shown then
		shown:Destroy()
	end

	local board = who:GetAttribute("LeaderTrail")
	local current = trails[who]
	local wanted = if type(board) == "string" then board else nil
	if current and (not wanted or current.Name ~= wanted or current.Parent ~= root) then
		current:Destroy()
		trails[who] = nil
		current = nil
	end
	if wanted and not current and root and root:IsA("BasePart") then
		local template = trailTemplate(wanted)
		if template then
			local trail = template:Clone()
			trail.Name = wanted
			for _, e in trail:GetDescendants() do
				if e:IsA("ParticleEmitter") then
					e.Enabled = false
				end
			end
			trail.Parent = root
			trails[who] = trail
		end
	end
end

local function watch(who: Player)
	if watched[who] then
		return
	end
	watched[who] = {
		who:GetAttributeChangedSignal("LeaderMedal"):Connect(function()
			refresh(who)
		end),
		who:GetAttributeChangedSignal("LeaderTrail"):Connect(function()
			refresh(who)
		end),
		who.CharacterAdded:Connect(function(character)
			-- the Head and root arrive a moment after the model
			character:WaitForChild("Head", 10)
			character:WaitForChild("HumanoidRootPart", 10)
			refresh(who)
		end),
	}
	refresh(who)
end

local function unwatch(who: Player)
	for _, c in watched[who] or {} do
		c:Disconnect()
	end
	watched[who] = nil
	local trail = trails[who]
	if trail then
		trail:Destroy()
	end
	trails[who] = nil
end

function LeaderFlairController.init(_deps: any)
	assets = ReplicatedStorage:WaitForChild("Assets")
end

function LeaderFlairController.start()
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(unwatch)
	for _, who in Players:GetPlayers() do
		task.spawn(watch, who)
	end
	-- a trail only streams while its runner moves
	task.spawn(function()
		while true do
			task.wait(MOVE_CHECK)
			for _, trail in trails do
				local root = trail.Parent
				if root and root:IsA("BasePart") then
					local v = root.AssemblyLinearVelocity
					local minSpeed = trail:GetAttribute("MinSpeed")
					local moving = Vector3.new(v.X, 0, v.Z).Magnitude > (if type(minSpeed) == "number" then minSpeed else 2)
					for _, e in trail:GetDescendants() do
						if e:IsA("ParticleEmitter") and e.Enabled ~= moving then
							e.Enabled = moving
						end
					end
				end
			end
		end
	end)
end

return LeaderFlairController
