--!strict
-- Hurt: a character's recoil when an enemy's hit lands (2026-10-22, the user: the player
-- should "stumble back" the way enemies flinch). An additive keyframe clip at Override
-- priority, so it layers on whatever the body is doing (walking, a weapon hold, a swing)
-- and never fights it, like Clips.Enemies.flinch. HurtController plays it on the hit
-- player's character, and pushes the character back (the stumble) for the player who
-- was hit.
--
--   entry.animator:Play(Hurt.flinch())
--
-- Tuning (degrees, Animation.Pose's axes: pitch + tips the torso / head back, swings an
-- arm forward): Hurt.FLINCH. The recoil snaps in over SNAP seconds and settles over the
-- rest of LENGTH.

local Animation = script.Parent.Parent
local Clip = require(Animation.Clip)

local Hurt = {}

Hurt.LENGTH = 0.42
Hurt.SNAP = 0.07
Hurt.FLINCH = {
	lean = 14, -- the torso tips back
	head = 16, -- the head snaps back on top of it
	arms = 24, -- both arms fly forward a little
	armsOut = 10, -- and out from the body
}

local cached: any = nil

function Hurt.flinch(): any
	if cached then
		return cached
	end
	local F = Hurt.FLINCH
	local function key(rot: { number }): { any }
		return {
			{ t = 0 },
			{ t = Hurt.SNAP, rot = rot, ease = "QuadOut" },
			{ t = Hurt.LENGTH, ease = "Smooth" },
		}
	end
	cached = Clip.new({
		name = "Player_flinch",
		priority = "Override",
		additive = true,
		length = Hurt.LENGTH,
		fadeIn = 0,
		fadeOut = 0.05,
		joints = {
			Root = key({ F.lean, 0, 0 }),
			Neck = key({ F.head, 0, 0 }),
			LeftShoulder = key({ F.arms, 0, F.armsOut }),
			RightShoulder = key({ F.arms, 0, -F.armsOut }),
		},
	})
	return cached
end

return Hurt
