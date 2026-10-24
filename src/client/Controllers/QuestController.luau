--!strict
-- QuestController: talking to quest givers (Dale the Farmer, Ranger Rowan...;
-- Config/Quests). A giver's "QuestLine" attribute names its line, and the
-- conversation reads that line's attributes (Quests.attr).
--
-- Every model tagged QuestGiver gets a "Talk" ProximityPrompt (E), drawn as the
-- game's speech-bubble prompt (Style Custom; PromptController shows
-- Assets/UI/TalkPrompt, "Talk to <ShortName>"). Talking:
--   1. hides the HUD and tracker, freezes the player and hides their body (it
--      would stand in the shot). Frozen means: movement controls off, the
--      HumanoidRootPart anchored, and the local player's "InputLocked"
--      attribute set, which WeaponController (swings), SprintController and
--      HotbarUI (the holster key) all respect,
--   2. eases the camera in on the giver's face, framed so the face sits right
--      of the dialogue card,
--   3. plays the conversation for the player's quest state through DialogueUI:
--      Offer -> the offer lines + Objective, Reward, Accept / Not now
--      Active -> the reminder line, Okay
--      Ready -> the hand-in lines, Claim reward, then straight on to the next
--               step's offer
--      Done -> the closing line
--   4. eases the camera back and gives everything back.
-- Accepting and handing in go to QuestService through Remotes.QuestAction.
--
-- Talkers (tag Talker, attribute TalkerId; Config/Talkers) get the same prompt, shot and
-- card, but say their def's lines for the player's state and close on one button: no
-- quest (Finn the fisherman's lesson, 2026-10-18).
--
-- The camera is an Animation.Scheduler Camera system (priority 40, before
-- CameraFX at 50), bound only while a conversation runs.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Enemies = require(Config:WaitForChild("Enemies"))
local Materials = require(Config:WaitForChild("Materials"))
local MapLayout = require(Config:WaitForChild("MapLayout"))
local Quests = require(Config:WaitForChild("Quests"))
local Talkers = require(Config:WaitForChild("Talkers"))
local Animation = require(Shared:WaitForChild("Animation"))
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local QuestController = {}

local player = Players.LocalPlayer

-- Camera shot: this far in front of the face, the aim this far to the face's
-- side (so the face sits right of the card) and the ease times.
local SHOT_DISTANCE = 6.2
local SHOT_SIDE = 2.6
local SHOT_LIFT = 0.25
-- Swing round toward the giver's left, so a tool held in the right hand isn't
-- across the face.
local SHOT_ORBIT = math.rad(18)
local EASE_IN = 0.6
local EASE_OUT = 0.45
-- How long to wait for the server to confirm an accept / hand-in.
local SERVER_WAIT = 3
local PROMPT_DISTANCE = 10
local PROMPT_KEY = Enum.KeyCode.E
-- the conversation closes by itself if the player ends up farther than this from
-- the giver (user, 2026-10-12: auto close the quest screen when you walk away)
local LEAVE_DISTANCE = PROMPT_DISTANCE + 6

local deps: any = nil
local remote: RemoteEvent? = nil
local talking = false

-- ==================== camera ====================

local cameraFrom = CFrame.identity
local cameraTo = CFrame.identity
local cameraStart = 0
local cameraSeconds = 1

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 4
end

local function cameraStep(_dt: number, now: number)
	local camera = Workspace.CurrentCamera
	if camera then
		-- held Scriptable in case anything resets it mid-conversation
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		local t = math.clamp((now - cameraStart) / cameraSeconds, 0, 1)
		camera.CFrame = cameraFrom:Lerp(cameraTo, easeOut(t))
	end
end

local function moveCamera(to: CFrame, seconds: number)
	local camera = Workspace.CurrentCamera
	cameraFrom = if camera then camera.CFrame else to
	cameraTo = to
	cameraStart = os.clock()
	cameraSeconds = seconds
	task.wait(seconds)
end

local function faceShot(giver: Model): CFrame?
	local head = giver:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return nil
	end
	local look = head.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local side = (-look):Cross(Vector3.yAxis)
	look = (look * math.cos(SHOT_ORBIT) + side * math.sin(SHOT_ORBIT)).Unit
	local eye = head.Position + look * SHOT_DISTANCE + Vector3.new(0, SHOT_LIFT, 0)
	local right = CFrame.lookAt(eye, head.Position).RightVector
	return CFrame.lookAt(eye, head.Position - right * SHOT_SIDE - Vector3.new(0, SHOT_LIFT, 0))
end

-- ==================== the player's side ====================

local function controls(): any
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
	end)
	return if ok and module then module:GetControls() else nil
end

local function setFrozen(frozen: boolean)
	player:SetAttribute("InputLocked", if frozen then true else nil)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = frozen
	end
end

local function setBodyHidden(hidden: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- The HUD ScreenGuis hidden while talking, and whether each was on.
local HIDDEN_GUIS = { "WeaponHud", "QuestTracker" }

local function setHudHidden(hidden: boolean, saved: { [string]: boolean })
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, name in HIDDEN_GUIS do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") then
			if hidden then
				saved[name] = gui.Enabled
				gui.Enabled = false
			elseif saved[name] ~= nil then
				gui.Enabled = saved[name]
			end
		end
	end
end

-- ==================== conversation ====================

local function iconFor(step: Quests.Step): string
	local objective = player:WaitForChild("PlayerGui"):FindFirstChild("Objective", true)
	local function attr(name: string): string
		local value = objective and objective:GetAttribute(name)
		return if type(value) == "string" then value else ""
	end
	if step.kind == "kill" then
		local def = Enemies.get(step.target or "")
		return if def and def.portrait then def.portrait else ""
	elseif step.kind == "level" then
		return attr("LevelIcon")
	elseif Quests.material(step) then
		local def = Materials.get(Quests.material(step))
		return def and def.icon or ""
	end
	return attr("CoinIcon")
end

local function where(line: Quests.Line): string
	return ("%s/%s"):format(tostring(player:GetAttribute(Quests.attr("Step", line.id))), tostring(player:GetAttribute(Quests.attr("State", line.id))))
end

-- Ask the server, then wait for it to move the quest on. True if it did.
local function send(line: Quests.Line, action: string): boolean
	if not remote then
		return false
	end
	local before = where(line)
	remote:FireServer(action, line.id)
	local deadline = os.clock() + SERVER_WAIT
	while os.clock() < deadline do
		task.wait(0.05)
		local now = where(line)
		if now ~= before then
			return true
		end
	end
	return false
end

-- The card's tag for a line's current step ("Quest 3 of 10"), or the finished line's.
local function lineTag(line: Quests.Line): string
	local index = player:GetAttribute(Quests.attr("Step", line.id))
	local step = if type(index) == "number" then line.steps[index] else nil
	return if step then ("Quest %d of %d"):format(index :: number, #line.steps) else "Questline Complete"
end

local function converse(line: Quests.Line)
	local DialogueUI = deps.UI.DialogueUI
	while true do
		local index = player:GetAttribute(Quests.attr("Step", line.id))
		local state = player:GetAttribute(Quests.attr("State", line.id))
		local step = if type(index) == "number" then line.steps[index] else nil
		local tag = if step then lineTag(line) else nil
		if step and state == "Offer" then
			local choice = DialogueUI.say({
				lines = step.offer,
				tag = tag,
				objective = { text = step.objective, icon = iconFor(step) },
				reward = step.reward,
				accept = "Accept Quest",
				later = "Not now",
			})
			if choice == "accept" and send(line, "accept") then
				UiSound.play("QuestAccept")
			end
			return
		elseif step and state == "Active" then
			DialogueUI.say({ lines = step.reminder, tag = tag, later = "Okay" })
			return
		elseif step and state == "Ready" then
			local choice = DialogueUI.say({ lines = step.complete, tag = tag, reward = step.reward, accept = "Claim Reward" })
			if choice ~= "accept" or not send(line, "turnIn") then
				return
			end
			UiSound.play("QuestComplete")
			-- handed in: carry straight on to the next step's offer
		else
			DialogueUI.say({ lines = line.finished, tag = "Questline Complete", later = "Goodbye" })
			return
		end
	end
end

-- Who a model is, how its conversation runs (a quest giver's line, or a talker's def), and
-- the card's tag right now (so the card opens with it, not the last speaker's).
local function speaker(giver: Instance): ({ name: string, short: string, portrait: string }?, (() -> ())?, string?)
	local line = Quests.get(giver:GetAttribute("QuestLine"))
	if line then
		return line.npc, function()
			converse(line)
		end, lineTag(line)
	end
	local def = Talkers.get(giver:GetAttribute("TalkerId"))
	if def then
		local said = def.talk(player)
		return def.npc, function()
			deps.UI.DialogueUI.say({ lines = said.lines, tag = said.tag, later = said.later })
		end, said.tag
	end
	return nil, nil, nil
end

local function talk(giver: Model, prompt: ProximityPrompt)
	local camera = Workspace.CurrentCamera
	local shot = faceShot(giver)
	local npc, run, tag = speaker(giver)
	if talking or not (camera and shot and npc and run) then
		return
	end
	talking = true
	prompt.Enabled = false
	if deps.UI.PanelWindow.isPanelOpen() then
		deps.UI.PanelWindow.hidePanel()
	end

	local saved: { [string]: boolean } = {}
	setHudHidden(true, saved)
	local control = controls()
	if control then
		control:Disable()
	end
	setFrozen(true)
	setBodyHidden(true)
	local savedType, savedCFrame = camera.CameraType, camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local system = Animation.Scheduler.bind("Camera", "QuestCamera", 40, cameraStep)

	-- The speaker goes in before the card opens: it used to be set only once the camera had eased in, so for
	-- that moment the card showed whoever spoke last (or the card's default, Dale) (user, 2026-10-11).
	deps.UI.DialogueUI.setSpeaker((npc :: any).name, (npc :: any).portrait, tag)
	deps.UI.DialogueUI.open()
	-- walked (or was knocked, or teleported) away from the giver: end the talk
	local anchor = giver.PrimaryPart or giver:FindFirstChild("Torso") or giver:FindFirstChild("HumanoidRootPart")
	task.spawn(function()
		while talking do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart") and anchor and anchor:IsA("BasePart")) or (root.Position - anchor.Position).Magnitude > LEAVE_DISTANCE then
				deps.UI.DialogueUI.cancel()
				break
			end
			task.wait(0.2)
		end
	end)
	moveCamera(shot :: CFrame, EASE_IN)
	local ok, err = pcall(run :: () -> ())
	if not ok then
		warn("[QuestController] conversation failed: " .. tostring(err))
	end
	deps.UI.DialogueUI.close()

	moveCamera(savedCFrame, EASE_OUT)
	system:Unbind()
	camera.CameraType = savedType
	setBodyHidden(false)
	setFrozen(false)
	if control then
		control:Enable()
	end
	setHudHidden(false, saved)
	prompt.Enabled = true
	talking = false
end

-- ==================== givers ====================

local function adopt(giver: Instance)
	local npc = speaker(giver)
	if not giver:IsA("Model") or not npc then
		return
	end
	local anchor = giver.PrimaryPart or giver:FindFirstChild("Torso")
	if not (anchor and anchor:IsA("BasePart")) or anchor:FindFirstChild("TalkPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = npc.name
	prompt.KeyboardKeyCode = PROMPT_KEY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("ShortName", npc.short)
	prompt.Parent = anchor
	prompt.Triggered:Connect(function()
		task.spawn(talk, giver, prompt)
	end)
end

function QuestController.init(injected: any)
	deps = injected
	remote = deps.Remotes.getEvent("QuestAction")
end

function QuestController.start()
	-- Download every quest giver's portrait up front, so a first conversation never waits on the image.
	task.spawn(function()
		local images = {}
		for _, id in Quests.order do
			local line = Quests.get(id)
			if line and line.npc.portrait ~= "" then
				local image = Instance.new("ImageLabel")
				image.Image = line.npc.portrait
				table.insert(images, image)
			end
		end
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(images)
		end)
	end)
	for _, tag in { MapLayout.Tags.QuestGiver, MapLayout.Tags.Talker } do
		for _, giver in CollectionService:GetTagged(tag) do
			adopt(giver)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(adopt)
	end
end

return QuestController
