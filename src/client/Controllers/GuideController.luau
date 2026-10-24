--!strict
-- GuideController: the guide arrow on the ground that points the way to the
-- current quest objective (the user's request, 2026-10-08).
--
-- It follows the line the tracker shows ("QuestShownLine", set by QuestTrackerUI
-- from Quests.tracked). What it points at (that line's step, plus the state as
-- the tracker shows it -- "QuestShownState", which stays Active until the coin /
-- EXP counters catch up -- so the arrow never turns to the giver before the HUD
-- says the step is done):
--   Ready                    the line's quest giver -- always, once a step is done
--   Active, a "kill" step    the nearest living enemy of that kind
--   Active, gather / bring   the tool's Weapons stall while the step's tool is
--                            missing (Quests.toolNeeded), then the nearest standing
--                            node, or for an enemy drop the nearest such enemy
--   anything else            nothing: earning coins or reaching a level has no
--                            place to go, so the arrow and the tracker's Guide
--                            button are hidden
-- The tracker's Guide button turns it on and off (setEnabled); it starts on.
--
-- The arrow is a clone of ReplicatedStorage/Assets/Effects/GuideArrow (a flat
-- invisible part with the arrow Decal on its Top face; a Top-face decal's top
-- edge lies along the part's +Z, measured in a playtest). It floats flat at
-- chest height (`Height` studs above the HumanoidRootPart) `Distance` studs
-- ahead of the player toward the target, creeps forward by `Slide` every
-- `SlideSeconds`, and hides within `HideWithin` studs of the target -- all
-- attributes on the template. (It used to lie on the raycast ground, and
-- climbed onto roofs.) A dark copy of the arrow lies on the ground straight
-- below it as its shadow, found by a short ray down from the arrow
-- (`ShadowReach`), so it never lands on a roof overhead. It is client-only and moves as an Animation.Scheduler Render system
-- (priority 60).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MapLayout = require(Config:WaitForChild("MapLayout"))
local Quests = require(Config:WaitForChild("Quests"))
local Materials = require(Config:WaitForChild("Materials"))
local Worlds = require(Config:WaitForChild("Worlds"))
local Animation = require(Shared:WaitForChild("Animation"))

local GuideController = {}

local player = Players.LocalPlayer

local deps: any = nil
local enabled = true
local changedEvent = Instance.new("BindableEvent")
local arrow: BasePart? = nil
local decal: Decal? = nil
local shadow: BasePart? = nil
local shadowDecal: Decal? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function number(name: string, fallback: number): number
	local value = arrow and arrow:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function currentLine(): Quests.Line?
	return Quests.get(player:GetAttribute("QuestShownLine"))
end

local function currentStep(): (Quests.Step?, string?)
	local line = currentLine()
	if not line then
		return nil, nil
	end
	local index = player:GetAttribute(Quests.attr("Step", line.id))
	local state = player:GetAttribute("QuestShownState")
	if state == nil then
		state = player:GetAttribute(Quests.attr("State", line.id))
	end
	local step = if type(index) == "number" then line.steps[index] else nil
	return step, if type(state) == "string" then state else nil
end

local function giverPosition(): Vector3?
	local line = currentLine()
	if not line then
		return nil
	end
	for _, giver in CollectionService:GetTagged(MapLayout.Tags.QuestGiver) do
		if giver:IsA("Model") and giver:GetAttribute("QuestLine") == line.id then
			return giver:GetPivot().Position
		end
	end
	return nil
end

-- The ring of a world's Weapons stall, where its tools are sold (a gather step's
-- tool phase, Quests.toolNeeded).
local function weaponStall(world: number): Vector3?
	local def = Worlds.get(world)
	local folder = def and Workspace:FindFirstChild("Worlds") and Workspace.Worlds:FindFirstChild(def.folder)
	local merchants = folder and folder:FindFirstChild("Structures") and folder.Structures:FindFirstChild("Merchants")
	local stall = merchants and merchants:FindFirstChild("WeaponStation")
	local ring = stall and stall:FindFirstChild("ShopRing")
	return if ring and ring:IsA("BasePart") then ring.Position elseif stall and stall:IsA("Model") then stall:GetPivot().Position else nil
end

local function nearestEnemy(archetype: string, from: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, body in CollectionService:GetTagged(MapLayout.Tags.WorldEnemy) do
		if body:GetAttribute("Archetype") == archetype and body:GetAttribute("Alive") ~= false then
			local position = if body:IsA("Model") then body:GetPivot().Position elseif body:IsA("BasePart") then body.Position else nil
			if position then
				local distance = flat(position - from).Magnitude
				if distance < bestDistance then
					best, bestDistance = position, distance
				end
			end
		end
	end
	return best
end

-- The material a gather / bring step still needs, if any: a bring step points at the
-- first item short (2026-10-19).
local function neededMaterial(step: Quests.Step): string?
	if step.kind == "gather" then
		return step.target
	elseif step.kind == "bring" then
		local held = player:GetAttribute("Materials")
		for _, item in step.items or {} do
			local n = if type(held) == "string" then tonumber(held:match("%f[%w]" .. item.id .. "=(%d+)") or "0") else 0
			if (n or 0) < item.count then
				return item.id
			end
		end
	end
	return nil
end

-- True when the current quest state has somewhere to point.
function GuideController.guidable(): boolean
	local step, state = currentStep()
	if not step then
		return false
	end
	return state == "Ready"
		or (state == "Active" and (step.kind == "kill" or neededMaterial(step) ~= nil or Quests.toolNeeded(step, player) ~= nil))
end

local function target(from: Vector3): Vector3?
	local step, state = currentStep()
	if not step then
		return nil
	elseif state == "Ready" then
		return giverPosition()
	elseif state == "Active" and step.kind == "kill" and step.target then
		return nearestEnemy(step.target, from)
	elseif state == "Active" then
		local tool = Quests.toolNeeded(step, player)
		if tool then
			return weaponStall(tool.world)
		end
		local material = neededMaterial(step)
		local gather = deps and deps.Controllers.GatherController
		local node = if material and gather then gather.nearest(material, from) else nil
		if node then
			return node
		end
		-- An enemy drop (Rowan's Fox Fur, 2026-10-21): the nearest enemy that drops it.
		local def = material and Materials.get(material)
		if def and def.source then
			return nearestEnemy(def.source, from)
		end
	end
	return nil
end

local function setShown(shown: boolean)
	if decal then
		decal.Transparency = if shown then 0 else 1
	end
	if not shown and shadowDecal then
		shadowDecal.Transparency = 1
	end
end

local function step(_dt: number, now: number)
	local part = arrow
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (part and enabled and root and root:IsA("BasePart")) then
		setShown(false)
		return
	end
	local goal = target(root.Position)
	local offset = if goal then flat(goal - root.Position) else Vector3.zero
	if not goal or offset.Magnitude <= number("HideWithin", 9) then
		setShown(false)
		return
	end
	local direction = offset.Unit
	local loop = (now % number("SlideSeconds", 0.9)) / number("SlideSeconds", 0.9)
	local spot = root.Position + direction * (number("Distance", 4) + number("Slide", 0.8) * loop)
	spot += Vector3.new(0, number("Height", 0.5), 0)
	-- -Z faces away from the target, so the image's top (+Z) points at it
	part.CFrame = CFrame.lookAt(spot, spot - direction)
	setShown(true)

	-- The shadow: on the ground straight below, if there is ground close enough.
	local ground = shadow
	local dark = shadowDecal
	if ground and dark then
		rayParams.FilterDescendantsInstances = { character, part, ground }
		local hit = Workspace:Raycast(spot, Vector3.new(0, -number("ShadowReach", 8), 0), rayParams)
		if hit then
			local below = Vector3.new(spot.X, hit.Position.Y + 0.06, spot.Z)
			ground.CFrame = CFrame.lookAt(below, below - direction)
			-- fainter the higher the arrow floats
			local gap = spot.Y - hit.Position.Y
			dark.Transparency = math.clamp(number("ShadowTransparency", 0.55) + gap * 0.04, 0, 1)
		else
			dark.Transparency = 1
		end
	end
end

function GuideController.isEnabled(): boolean
	return enabled
end

function GuideController.setEnabled(on: boolean)
	if enabled ~= on then
		enabled = on
		changedEvent:Fire(on)
	end
end

function GuideController.onChanged(callback: (boolean) -> ()): RBXScriptConnection
	return changedEvent.Event:Connect(callback)
end

function GuideController.init(injected: any)
	deps = injected
end

function GuideController.start()
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	local effects = assets and assets:WaitForChild("Effects", 10)
	local template = effects and effects:WaitForChild("GuideArrow", 10)
	if not (template and template:IsA("BasePart")) then
		warn("[GuideController] missing ReplicatedStorage/Assets/Effects/GuideArrow; no guide arrow")
		return
	end
	local part = template:Clone()
	part.Parent = MapLayout.runtimeFolder()
	arrow = part
	local image = part:FindFirstChildWhichIsA("Decal")
	decal = image
	-- the shadow is the same arrow, darkened, on its own part
	if image then
		local ground = part:Clone()
		ground.Name = "GuideArrowShadow"
		local dark = ground:FindFirstChildWhichIsA("Decal") :: Decal
		dark.Color3 = Color3.new(0, 0, 0)
		ground.Parent = part.Parent
		shadow = ground
		shadowDecal = dark
	end
	setShown(false)
	Animation.Scheduler.bind("Render", "GuideArrow", 60, step)
end

return GuideController
