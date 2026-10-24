--!strict
-- SprintController: hold Shift (gamepad: left stick) to sprint while moving.
-- Sprinting is unlocked by the Sprint upgrade (Config/Upgrades, 2026-10-19: no base
-- sprint any more, the user's call): level 1 sprints at 1.2x the walk speed and each
-- level adds 0.04. Without it Shift does nothing. Sprinting is unlimited: stamina and
-- its HUD bar were removed on 2026-10-11 (user's call).
--
-- The sprint animation itself is PlayerAnimator's (it sees the extra speed);
-- this only adds a small camera FOV push, as an Animation.CameraFX zoom layer
-- ("Sprint") that eases in and out.
--
-- A Swiftness potion (Config/Potions, 2026-10-19) and the worn armour's speed bonus
-- (Config/Armor, the player's ArmorSpeed attribute, 2026-10-22) speed up both walking and
-- sprinting, together never past + Armor.MAX_SPEED, and the Sprint upgrade's share adds on
-- while sprinting (they add, 2026-10-23: Config/Bonuses.speed), so the walk speed is set
-- every step from StarterPlayer's CharacterWalkSpeed x that total.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades"))
local Settings = require(Shared:WaitForChild("Config"):WaitForChild("Settings"))
local Bonuses = require(Shared:WaitForChild("Config"):WaitForChild("Bonuses"))
local CameraFX = require(Shared:WaitForChild("Animation")).CameraFX

local SprintController = {}

local SPRINT_KEYS = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3 }

local FOV_SPEED = 8 -- how fast the FOV push eases in and out
local FOV_PUSH = 8 -- degrees added while sprinting
local MOVING = 0.1 -- MoveDirection magnitude that counts as moving

local player = Players.LocalPlayer

local held = false -- a sprint key is down
local sprinting = false

local function canSprint(humanoid: Humanoid): boolean
	return held
		-- no sprint until the first Sprint upgrade
		and Upgrades.value(player, "Sprint") > 0
		and humanoid.Health > 0
		and humanoid.MoveDirection.Magnitude > MOVING
		-- talking to an NPC (QuestController)
		and not player:GetAttribute("InputLocked")
end

local function step(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		return
	end

	local want = canSprint(humanoid)

	if want ~= sprinting then
		sprinting = want
		-- the FOV push is the player's "Sprint zoom" setting (Config/Settings)
		if sprinting and Settings.on(player, "SprintZoom") then
			CameraFX.zoom("Sprint", FOV_PUSH, FOV_SPEED)
		else
			CameraFX.release("Sprint")
		end
	end
	-- a Swiftness potion, the worn armour's speed (their sum capped) and the Sprint
	-- upgrade while sprinting, added (Config/Bonuses.speed)
	local speed = StarterPlayer.CharacterWalkSpeed * Bonuses.speed(player, sprinting)
	if math.abs(humanoid.WalkSpeed - speed) > 0.01 then
		humanoid.WalkSpeed = speed
	end
end

-- ==================== public ====================

function SprintController.isSprinting(): boolean
	return sprinting
end

-- ==================== lifecycle ====================

function SprintController.init(_injected: any) end

function SprintController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not table.find(SPRINT_KEYS, input.KeyCode) then
			return
		end
		held = true
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if table.find(SPRINT_KEYS, input.KeyCode) then
			held = false
		end
	end)

	local function onCharacter(character: Model)
		sprinting = false
		CameraFX.release("Sprint")
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	RunService.PreSimulation:Connect(step)
end

return SprintController
