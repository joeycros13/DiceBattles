--!strict
-- UiSound: the UI and reward sounds (2026-10-22, the user: "the UI and rewards sounds").
-- Every sound is a hand-made Sound in ReplicatedStorage/Assets/Sounds/UI named for its
-- moment, in SoundService's "UI" SoundGroup; `UiSound.play(name)` plays a copy of it
-- (not positional: parented to SoundService). The picks are auditioned from
-- SoundService/AudioCandidates_2026-10-22 and swapped in by copying a SoundId.
--   Hover        a clickable button is hovered (Util.ButtonFx)
--   Click        a clickable button is pressed (Util.ButtonFx)
--   Refuse       a locked button is pressed, or the server turns a buy down
--   PanelOpen / PanelClose   a panel pops open or shut (UI.PanelWindow)
--   CoinLand / ExpLand       each flying coin or EXP star reaches the HUD (CoinsUI,
--                PlayerCardUI); they climb in pitch, see Ladder below
--   Purchase     coins spent at a stall, the Upgrades stand, the Crafter, a gate, a sale
--   Drink        a potion drunk from the Inventory
--   QuestAccept / QuestComplete   a quest step taken or handed in (QuestController)
--   NewItem      the Index NEW popup (UI.IndexPopup)
--   LevelUp      the LEVEL UP pop over the player's head (PlayerCardUI)
-- Each Sound's own Volume, PlaybackSpeed and PlaybackRegion are used as set, plus these
-- attributes (all optional):
--   MinGap       seconds before the same sound plays again (default 0.05), so a button
--                brushed by the mouse or ten coins landing at once don't stack up
--   PitchJitter  plays at a random speed within ± this share (default 0)
--   LadderStep / LadderMax / LadderReset   each play within LadderReset seconds of the
--                last climbs LadderStep higher (a share of the speed), up to LadderMax
--                steps: a spill of coins rises like a little tune
--   Attack / Release   a volume envelope of our own: from silent up to Volume over
--                Attack seconds, then down to silent over Release seconds (and stopped).
--                Roblox can't play a sound backwards (a negative PlaybackSpeed clamps to
--                0), so PanelClose fakes the reversed PanelOpen whoosh this way: the loud
--                middle of it (PlaybackRegion) with a quick swell and a long fade.
-- A button with an "FxNoSound" attribute makes no hover or click sound.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local UiSound = {}

local folder: Instance? = nil
local lastPlayed: { [string]: number } = {}
local ladders: { [string]: { step: number, at: number } } = {}

local function number(sound: Sound, name: string, fallback: number): number
	local value = sound:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

function UiSound.init(_injected: any) end

function UiSound.start()
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	local sounds = assets and assets:WaitForChild("Sounds", 10)
	folder = sounds and sounds:WaitForChild("UI", 10)
	if not folder then
		warn("[UiSound] missing ReplicatedStorage/Assets/Sounds/UI")
	end
end

-- Play the UI sound `name` (a Sound in Assets/Sounds/UI); does nothing if there is none.
function UiSound.play(name: string)
	local template = folder and folder:FindFirstChild(name)
	if not (template and template:IsA("Sound")) then
		return
	end
	local now = os.clock()
	if lastPlayed[name] and now - lastPlayed[name] < number(template, "MinGap", 0.05) then
		return
	end
	lastPlayed[name] = now
	local speed = template.PlaybackSpeed
	local jitter = number(template, "PitchJitter", 0)
	if jitter > 0 then
		speed *= 1 + (math.random() * 2 - 1) * jitter
	end
	local stepSize = number(template, "LadderStep", 0)
	if stepSize > 0 then
		local ladder = ladders[name]
		if ladder and now - ladder.at <= number(template, "LadderReset", 0.6) then
			ladder.step = math.min(ladder.step + 1, number(template, "LadderMax", 6))
			ladder.at = now
		else
			ladder = { step = 0, at = now }
			ladders[name] = ladder
		end
		speed *= 1 + ladder.step * stepSize
	end
	local sound = template:Clone()
	sound.PlaybackSpeed = speed
	sound.Parent = SoundService
	local attack = number(template, "Attack", 0)
	local release = number(template, "Release", 0)
	if attack > 0 then
		sound.Volume = 0
		TweenService:Create(sound, TweenInfo.new(attack, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = template.Volume,
		}):Play()
	end
	if release > 0 then
		task.delay(attack, function()
			if not sound.Parent then
				return
			end
			local fade = TweenService:Create(sound, TweenInfo.new(release, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = 0,
			})
			fade.Completed:Once(function()
				sound:Destroy()
			end)
			fade:Play()
		end)
	end
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- in case Ended never comes (a sound that failed to load)
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return UiSound
