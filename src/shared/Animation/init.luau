--!strict
-- Animation: Bonk Quest's own animation system. Require this one module and
-- reach everything through it:
--
--   local Animation = require(ReplicatedStorage.Shared.Animation)
--   local entry = Animation.Character.get(character)        -- shared rig + animator
--   local track = entry.animator:Play(Animation.Clips.Weapons.swing(def), { speed = 2 })
--   track:GetMarkerReachedSignal("Hit"):Connect(...)
--   Animation.Effects.burst(position, "HitSpark")
--   Animation.CameraFX.zoom("Sprint", 8)
--   Animation.Tween.to(door, { Pivot = openCFrame }, 0.4, "BackOut")
--
-- Layers, bottom to top (each only depends on the ones above it in this list):
--
--   core       Signal  Easing  Spring  Pose  Scheduler  PartBatch
--   clips      Clip (keyframes, procedural, Animation Editor import)  Track
--   rigs       JointRig (Motor6D characters)  PartRig (part-built enemies)
--   playback   Animator (blending, priorities, LOD)  Character (one per model)
--   motion     Tween (any property, Pivot, Scale)  Motion (move/rotate/path/spin/bob)
--              Weld (sockets, attach, rigidify)
--   feel       Effects + EffectPresets (pooled particles, flashes, trails, sound)
--              CameraFX (FOV zoom layers; no shake, by the user's rule)
--   content    Clips.Locomotion  Clips.Weapons  Clips.Enemies  Clips.Critters  Clips.Hurt
--
-- Everything that runs per frame is a Scheduler system, in one fixed order:
--   Joints  (PreSimulation, after Roblox's Animator)  50 Animator.joints
--   Render  (PreRender)  10 world enemies  20 Tween  30 Motion  50 Animator.parts
--                        100 PartBatch flush (all part moves in one BulkMoveTo)
--   Camera  (after Roblox's camera)  50 CameraFX
-- Tuning aids during a playtest (set on the client, no code needed):
--   Scheduler module, attribute Profiling = true  -> its "Stats" attribute shows
--                                                  ms per system, every second
--   Animator module,  attribute PinTime = 0..1    -> every one-shot clip (swings,
--                                                  enemy moves) freezes there

local Clip = require(script.Clip)

local Animation = {
	Signal = require(script.Signal),
	Easing = require(script.Easing),
	Spring = require(script.Spring),
	Pose = require(script.Pose),
	Scheduler = require(script.Scheduler),
	PartBatch = require(script.PartBatch),
	Clip = Clip,
	Track = require(script.Track),
	JointRig = require(script.JointRig),
	PartRig = require(script.PartRig),
	Animator = require(script.Animator),
	Character = require(script.Character),
	Tween = require(script.Tween),
	Motion = require(script.Motion),
	Weld = require(script.Weld),
	Effects = require(script.Effects),
	EffectPresets = require(script.EffectPresets),
	CameraFX = require(script.CameraFX),
	Priority = Clip.Priority,
	Clips = {
		Locomotion = require(script.Clips.Locomotion),
		Weapons = require(script.Clips.Weapons),
		Enemies = require(script.Clips.Enemies),
		Critters = require(script.Clips.Critters),
		Hurt = require(script.Clips.Hurt),
	},
}

return Animation
