--!strict
-- WorldAudioController: each world's background sounds play only while you're in
-- it (2026-10-21; World 2 got its own birds and wind, and both worlds' beds had
-- played everywhere at once).
--
-- A "bed" is a looping Sound placed directly in Workspace.Worlds.<W##_Name>/
-- Ambience/Sounds (World 1's Birds and Music, World 2's Birds and Wind). The
-- server starts every bed (Playing = true, so no code is needed to start them);
-- this only turns each one's volume up or down, here, for this player:
--   * the beds of the world in the player's "CurrentWorld" attribute (published by
--     WorldBannerUI; World 1 until it's set) ease to their authored volume,
--   * every other world's beds ease to 0,
-- over FADE seconds. Sounds inside parts (the water) are positional and left alone.
-- The authored volume is kept in each bed's "BaseVolume" attribute, so a bed can
-- be retuned in Studio without code.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local WorldAudioController = {}

local FADE = 2.5

local player = Players.LocalPlayer

type Bed = { sound: Sound, world: number }
local beds: { Bed } = {}

local function worldOf(folder: Instance): number?
	return tonumber(folder.Name:match("^W(%d+)"))
end

local function collect()
	local worlds = workspace:FindFirstChild("Worlds")
	for _, folder in if worlds then worlds:GetChildren() else {} do
		local id = worldOf(folder)
		local ambience = folder:FindFirstChild("Ambience")
		local sounds = ambience and ambience:FindFirstChild("Sounds")
		for _, s in if id and sounds then sounds:GetChildren() else {} do
			if s:IsA("Sound") then
				if s:GetAttribute("BaseVolume") == nil then
					s:SetAttribute("BaseVolume", s.Volume)
				end
				table.insert(beds, { sound = s, world = id :: number })
			end
		end
	end
end

local function apply(seconds: number)
	local current = player:GetAttribute("CurrentWorld")
	local here = if type(current) == "number" then current else 1
	for _, bed in beds do
		local base = bed.sound:GetAttribute("BaseVolume")
		local goal = if bed.world == here and type(base) == "number" then base else 0
		TweenService:Create(bed.sound, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Volume = goal }):Play()
	end
end

function WorldAudioController.init(_deps: any) end

function WorldAudioController.start()
	collect()
	-- straight to the right mix on join, then fade on every world change
	apply(0)
	player:GetAttributeChangedSignal("CurrentWorld"):Connect(function()
		apply(FADE)
	end)
end

return WorldAudioController
