--!strict
-- PlayerAnimator: idle, walk and sprint for every player character, on the
-- Animation system.
--
-- Each character gets one shared rig + animator (Animation.Character), and this
-- plays the Locomotion clip on it at priority Movement. The clip itself -- the
-- breathing idle, the bouncy walk, the sprint and all their tuning -- lives in
-- ReplicatedStorage.Shared.Animation.Clips.Locomotion. Weapons (WeaponController)
-- play their hold and swings on the SAME animator at higher priorities, so the
-- two never fight over a joint.
--
-- Other players' characters are level-of-detail culled (far ones update less
-- often); the local player's always run at full rate.
--
-- Footsteps (2026-10-21, the user: the stepping sound didn't match the walk): the
-- Locomotion clip reports each footfall (its `onStep`), and each one plays the
-- hand-picked ReplicatedStorage/Assets/Sounds/Footstep from the character's root,
-- a little higher or lower each time (its `PitchJitter` attribute) and louder while
-- sprinting (`SprintBoost`). Roblox's own looping "Running" sound is muted so the
-- two never play together.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animation"))
local Character = Animation.Character
local Locomotion = Animation.Clips.Locomotion

local PlayerAnimator = {}

local player = Players.LocalPlayer

local function footstepTemplate(): Sound?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	local found = sounds and sounds:FindFirstChild("Footstep")
	return if found and found:IsA("Sound") then found else nil
end

local function number(inst: Instance, name: string, fallback: number): number
	local v = inst:GetAttribute(name)
	return if type(v) == "number" then v else fallback
end

-- One sound per foot on the character's root, so a quick step never cuts off the last.
local function stepper(model: Model): ((number, number) -> ())?
	local template = footstepTemplate()
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (template and root) then
		return nil
	end
	local feet = {}
	for foot = 1, 2 do
		local s = template:Clone()
		s.Name = "Footstep" .. foot
		s.Parent = root
		feet[foot] = s
	end
	local speed, volume = template.PlaybackSpeed, template.Volume
	local jitter = number(template, "PitchJitter", 0.08)
	local boost = number(template, "SprintBoost", 0.3)
	return function(foot: number, sprint: number)
		local s = feet[foot]
		if s and s.Parent then
			s.PlaybackSpeed = speed * (1 + (math.random() * 2 - 1) * jitter)
			s.Volume = volume * (1 + boost * sprint)
			s:Play()
		end
	end
end

-- Roblox's RbxCharacterSounds puts a looping "Running" sound in the root; ours replaces it.
local function muteRunning(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local function mute(child: Instance)
		if child:IsA("Sound") and child.Name == "Running" then
			child.Volume = 0
		end
	end
	for _, child in root:GetChildren() do
		mute(child)
	end
	root.ChildAdded:Connect(mute)
end

local function animate(model: Model, cull: boolean, forceGround: boolean, onStep: ((number, number) -> ())?)
	local entry = Character.get(model, { cull = cull })
	entry.animator:Stop(Locomotion.clip, 0)
	entry.animator:Play(Locomotion.clip, { params = { model = model, forceGround = forceGround, onStep = onStep } })
end

local function watchCharacter(owner: Player, character: Model)
	if not Character.ready(character, 10) or not character.Parent then
		return
	end
	muteRunning(character)
	animate(character, owner ~= player, false, stepper(character))
	-- The avatar is rebuilt once its outfit lands; find the new joints.
	character:GetAttributeChangedSignal("AvatarReady"):Connect(function()
		local entry = Character.peek(character)
		if entry then
			entry.rig:Refresh()
		end
	end)
end

local function watchPlayer(owner: Player)
	owner.CharacterAdded:Connect(function(character)
		watchCharacter(owner, character)
	end)
	if owner.Character then
		task.spawn(watchCharacter, owner, owner.Character)
	end
end

-- Animate a character copy that isn't a player's (the Inventory preview, inside
-- a ViewportFrame's WorldModel). It always counts as standing, so it idles.
function PlayerAnimator.track(model: Model)
	animate(model, false, true)
end

function PlayerAnimator.untrack(model: Model)
	Character.release(model)
end

function PlayerAnimator.init(_injected: any) end

function PlayerAnimator.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, owner in Players:GetPlayers() do
		watchPlayer(owner)
	end
end

return PlayerAnimator
