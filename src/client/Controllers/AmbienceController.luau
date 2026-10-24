--!strict
-- AmbienceController: this player's lighting, per world and for special places
-- (2026-10-12, first for World 2's secret stump room, whose open top shows a twilight
-- sky; per world since 2026-10-21).
--
-- World looks: a world's `lighting` in Config/Worlds (World 1 "Golden afternoon",
-- World 2 "Misty morning", the user's picks 2026-10-21; World 3 "Deep sapphire",
-- 2026-10-24) is the look while the
-- player's "CurrentWorld" attribute (published by WorldBannerUI) names it: Lighting
-- properties (ClockTime, Brightness, ExposureCompensation, Ambient, OutdoorAmbient,
-- ColorShift_Top...) plus tables for Lighting's Atmosphere, ColorCorrection and
-- SunRays. A world with no `lighting` uses the lighting as built
-- in Studio, read once on start. Walking into another world eases to its look over
-- WORLD_EASE seconds.
--
-- Zones: a part tagged "AmbienceZone" is a box; while this player's character is
-- inside it, these attributes override the world's look:
--   ClockTime       number  the time of day to show (18.7 = dusk)
--   Ambient         Color3  Lighting.Ambient (lifts the shadows indoors)
--   OutdoorAmbient  Color3  Lighting.OutdoorAmbient
--   Brightness      number  Lighting.Brightness
-- Any of them may be left out. Only this client's Lighting changes; nobody
-- else's sky moves.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Worlds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Worlds"))

local AmbienceController = {}

local TAG = "AmbienceZone"
local POLL, EASE, WORLD_EASE = 0.25, 1.2, 4

local ZONE_PROPS = { "ClockTime", "Ambient", "OutdoorAmbient", "Brightness" }
local LIGHT_PROPS = { "ClockTime", "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient", "ColorShift_Top" }
-- the Lighting children a look may set, and their properties
local CHILDREN: { [string]: { class: string, props: { string } } } = {
	Atmosphere = { class = "Atmosphere", props = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" } },
	ColorCorrection = { class = "ColorCorrectionEffect", props = { "Brightness", "Contrast", "Saturation", "TintColor" } },
	SunRays = { class = "SunRaysEffect", props = { "Intensity", "Spread" } },
}

local player = Players.LocalPlayer
local built: { [string]: any } = {} -- the lighting as built in Studio
local currentZone: BasePart? = nil
local currentWorld: number? = nil
local tweens: { Tween } = {}

local function inside(zone: BasePart, point: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(point)
	local h = zone.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

-- Lighting as it stands now, in the shape of a world's `lighting` table.
local function snapshot(): { [string]: any }
	local look: { [string]: any } = {}
	for _, prop in LIGHT_PROPS do
		look[prop] = (Lighting :: any)[prop]
	end
	for key, child in CHILDREN do
		local inst = Lighting:FindFirstChildOfClass(child.class)
		if inst then
			local t = {}
			for _, prop in child.props do
				t[prop] = (inst :: any)[prop]
			end
			look[key] = t
		end
	end
	return look
end

-- The look to show: the world's own (or the built one), with the zone's overrides.
local function target(world: number, zone: BasePart?): { [string]: any }
	local def = Worlds.Defs[world]
	local base = (def and def.lighting) or built
	local look: { [string]: any } = table.clone(base)
	if zone then
		for _, prop in ZONE_PROPS do
			local v = zone:GetAttribute(prop)
			if v ~= nil then
				look[prop] = v
			end
		end
	end
	return look
end

local function ease(look: { [string]: any }, seconds: number)
	for _, t in tweens do
		t:Cancel()
	end
	table.clear(tweens)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local goal = {}
	for _, prop in LIGHT_PROPS do
		if look[prop] ~= nil then
			goal[prop] = look[prop]
		end
	end
	table.insert(tweens, TweenService:Create(Lighting, info, goal))
	for key, child in CHILDREN do
		local inst = Lighting:FindFirstChildOfClass(child.class)
		local values = look[key]
		if inst and type(values) == "table" then
			table.insert(tweens, TweenService:Create(inst, info, values))
		end
	end
	for _, t in tweens do
		t:Play()
	end
end

local function poll(): ()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local zone: BasePart? = nil
	if root and root:IsA("BasePart") then
		for _, z in CollectionService:GetTagged(TAG) do
			if z:IsA("BasePart") and z:IsDescendantOf(workspace) and inside(z, root.Position) then
				zone = z
				break
			end
		end
	end
	local w = player:GetAttribute("CurrentWorld")
	local world = if type(w) == "number" then w else 1
	if zone == currentZone and world == currentWorld then
		return
	end
	local seconds
	if currentWorld == nil then
		seconds = 0 -- the first look on join
	elseif zone ~= currentZone then
		-- between two zones ease; into or out of one (through a teleport's fade), snap,
		-- so the sky is already right when the screen clears
		seconds = if zone and currentZone then EASE else 0.05
	else
		seconds = WORLD_EASE
	end
	currentZone = zone
	currentWorld = world
	ease(target(world, zone), seconds)
end

-- Re-check now (FadeController calls this as a teleport's fade-in starts, 2026-10-20: the
-- 0.25 s poll let the old place's lighting show for a moment after a secret room's exit).
function AmbienceController.refresh()
	poll()
end

function AmbienceController.init(_injected: any) end

function AmbienceController.start()
	built = snapshot()
	task.spawn(function()
		while true do
			poll()
			task.wait(POLL)
		end
	end)
end

return AmbienceController
