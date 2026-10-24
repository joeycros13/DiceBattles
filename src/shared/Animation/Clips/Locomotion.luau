--!strict
-- Locomotion: an R6 character's idle, walk and sprint as ONE procedural clip
-- (priority Movement), blended by actual ground speed every frame. It is the
-- base every other character clip (weapon holds, swings, flinches) layers on.
--
--   idle    a planted, staggered stance -- left foot a little ahead, feet apart,
--           arms angled off the torso -- with the torso, arms and head bobbing
--           gently up and down (the feet stay on the ground)
--   walk    long, open strides: legs and arms swing wide and away from the body,
--           from pivots set above the joints so hands and feet travel a longer
--           arc; bouncy step, hip roll and swivel, a steady head, lean into turns
--   sprint  the walk pushed to the extreme: bigger swings, wider arms, higher
--           pivots, a strong forward lean, pumping arms
-- On the ground it replaces Roblox's default walk; in the air, climbing,
-- swimming or seated its weight drops to 0 so the default jump / fall / climb
-- animations show. Sprint is "clearly faster than StarterPlayer's walk speed",
-- so it works for other players without knowing their input.
--
--   animator:Play(Locomotion.clip, { params = { model = character } })
--   params.forceGround = true  for display copies that have no floor (idles)
--   params.speed = 24          to fake a ground speed (previews, mannequins)
--   params.onStep = fn(foot, sprint)  called as each foot lands while walking or
--                              running on the ground (foot 1 / 2, sprint 0..1), at
--                              the stride's own timing, so footstep sounds follow
--                              the legs at any speed (PlayerAnimator, 2026-10-21)
--
-- ==================== tuning ====================
-- Every value lives in Locomotion.IDLE / WALK / SPRINT. Degrees for angles,
-- studs for distances; in the torso's frame.
--   *Swing     how far a limb swings forward/back
--   *Out       how far a limb is angled away from the body (abduction)
--   *OutSwing  extra outward angle at the top of each swing (arms arc wide)
--   *Spread    studs the limb is moved out from the torso (so it clears it)
--   *Pivot     studs ABOVE the joint the swing rotates about. 0 = the R6 joint
--              itself; higher = the limb slides along with the swing, which
--              reads as a longer reach / stride.
-- Pitch +: limb swings forward. Arms swing against the legs.
--   plant      0..1: how much the body is lowered so the lowest foot touches
--              the ground (swinging legs lift the feet). 1 = always planted;
--              below 1 lets a sprint leave the ground between steps. This is
--              what makes the body dip at each footfall; `bob` adds on top.

local StarterPlayer = game:GetService("StarterPlayer")

local Animation = script.Parent.Parent
local Clip = require(Animation.Clip)
local Pose = require(Animation.Pose)

local Locomotion = {}

Locomotion.BLEND_RATE = 7 -- how fast idle / walk / sprint ease into each other (1/sec)
Locomotion.GROUND_RATE = 10 -- how fast the whole pose fades on leaving / touching the ground
Locomotion.STRIDE_LENGTH = 9 -- studs travelled per full stride cycle (two steps)
local FOOTFALLS = { math.pi / 2, math.pi * 1.5 } -- stride phases where each foot lands
Locomotion.TURN_LEAN = 0.06 -- degrees of roll per degree/sec of turning
Locomotion.TURN_LEAN_MAX = 8

Locomotion.IDLE = {
	plant = 1,
	bobRate = 1.9, -- radians/sec (one bob ~3.3 s)
	bob = 0.07, -- studs the torso dips (legs compensate, feet stay planted)
	chest = 1.2, -- degrees the chest rocks back as it rises
	-- Staggered stance: left foot ahead, right foot behind, both turned out.
	leftLegForward = 8,
	rightLegBack = 6,
	legOut = 4,
	legSpread = 0,
	-- Arms hang angled off the torso and sway a beat behind the bob.
	armOut = 7,
	armForward = 3,
	armSpread = 0,
	armLag = 0.7, -- radians the arms trail the torso's bob
	armBob = 2, -- degrees of arm sway with the bob
	headLag = 0.45, -- radians the head trails the bob
	headNod = 1.6, -- degrees
}

Locomotion.WALK = {
	plant = 1,
	legSwing = 42,
	legOut = 2,
	legOutSwing = 1,
	legSpread = 0,
	legPivot = 0.3,
	armSwing = 42,
	armForward = 4,
	armOut = 6,
	armOutSwing = 3,
	armSpread = 0,
	armPivot = 0.35,
	armLag = 0.35, -- radians the arms trail the legs
	bob = 0.06, -- studs of extra bounce on top of the planting dip
	lean = 5,
	roll = 3.5, -- side-to-side weight shift
	swivel = 7, -- body yaw with each step
	headSteady = 0.75, -- fraction of the body's roll/swivel the head cancels
	nod = 2,
}

Locomotion.SPRINT = {
	plant = 0.75,
	legSwing = 66,
	legOut = 3,
	legOutSwing = 2,
	legSpread = 0,
	legPivot = 0.5,
	armSwing = 76,
	armForward = 14,
	armOut = 9,
	armOutSwing = 4,
	armSpread = 0,
	armPivot = 0.5,
	armLag = 0.25,
	bob = 0.1,
	lean = 16,
	roll = 3,
	swivel = 11,
	headSteady = 0.8,
	nod = 3,
}

local GROUND_STATES = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Landed] = true,
	[Enum.HumanoidStateType.None] = true,
}

local random = Random.new()

-- Pose fields, in degrees / studs, summed across layers by weight.
local FIELDS = {
	"rootLift", "rootPitch", "rootYaw", "rootRoll",
	"neckPitch", "neckYaw", "neckRoll",
	"lArmPitch", "lArmRoll", "rArmPitch", "rArmRoll",
	"lLegPitch", "lLegRoll", "rLegPitch", "rLegRoll",
	"armSpread", "armPivot", "legSpread", "legPivot", "legLift", "plant",
}

-- R6 geometry for foot planting (torso frame): hip joints (the top outer
-- corner of each leg), and the four bottom corners of each leg relative to its
-- hip joint at rest.
local LEFT_HIP, RIGHT_HIP = Vector3.new(-1, -1, 0), Vector3.new(1, -1, 0)
local LEFT_SOLE = { Vector3.new(0, -2, -0.5), Vector3.new(0, -2, 0.5), Vector3.new(1, -2, -0.5), Vector3.new(1, -2, 0.5) }
local RIGHT_SOLE = { Vector3.new(0, -2, -0.5), Vector3.new(0, -2, 0.5), Vector3.new(-1, -2, -0.5), Vector3.new(-1, -2, 0.5) }
local REST_FOOT_Y = -3 -- soles below the torso's centre at rest

local function blank(): { [string]: number }
	local pose = {}
	for _, field in FIELDS do
		pose[field] = 0
	end
	return pose
end

local function addInto(into: { [string]: number }, from: { [string]: number }, weight: number)
	if weight <= 0 then
		return
	end
	for key, value in from do
		into[key] += value * weight
	end
end

local function idlePose(s: any)
	local IDLE = Locomotion.IDLE
	local t = s.clock * IDLE.bobRate
	local dip = 0.5 - 0.5 * math.cos(t) -- 0 (up) .. 1 (down)
	local arm = math.sin(t - IDLE.armLag)
	local p = blank()
	p.plant = IDLE.plant
	p.rootLift = -IDLE.bob * dip
	p.legLift = IDLE.bob * dip -- legs rise against the torso: feet stay put
	p.rootPitch = -IDLE.chest * (0.5 - dip)
	p.lLegPitch = IDLE.leftLegForward
	p.rLegPitch = -IDLE.rightLegBack
	p.lLegRoll = -IDLE.legOut
	p.rLegRoll = IDLE.legOut
	p.legSpread = IDLE.legSpread
	p.lArmRoll = -(IDLE.armOut + IDLE.armBob * arm)
	p.rArmRoll = IDLE.armOut + IDLE.armBob * arm
	p.lArmPitch = IDLE.armForward
	p.rArmPitch = IDLE.armForward
	p.armSpread = IDLE.armSpread
	p.neckPitch = IDLE.headNod * math.sin(t - IDLE.headLag) + IDLE.chest * (0.5 - dip)
	return p
end

-- One gait (walk or sprint) from its tuning table.
local function gaitPose(G: any, phase: number)
	local sn, cs = math.sin(phase), math.cos(phase)
	local arm = math.sin(phase - G.armLag)
	local p = blank()
	p.plant = G.plant
	-- Highest as the legs pass each other, lowest as each foot lands.
	p.rootLift = G.bob * (math.abs(cs) - 0.5)
	p.rootPitch = -G.lean
	p.rootRoll = G.roll * sn
	p.rootYaw = G.swivel * sn
	p.lLegPitch = G.legSwing * sn
	p.rLegPitch = -G.legSwing * sn
	local legOut = G.legOut + G.legOutSwing * math.abs(sn)
	p.lLegRoll = -legOut
	p.rLegRoll = legOut
	p.legSpread = G.legSpread
	p.legPivot = G.legPivot
	p.lArmPitch = G.armForward - G.armSwing * arm
	p.rArmPitch = G.armForward + G.armSwing * arm
	local armOut = G.armOut + G.armOutSwing * math.abs(arm)
	p.lArmRoll = -armOut
	p.rArmRoll = armOut
	p.armSpread = G.armSpread
	p.armPivot = G.armPivot
	-- The head cancels most of the body's sway, so it reads as looking ahead.
	p.neckYaw = -G.swivel * sn * G.headSteady
	p.neckRoll = -G.roll * sn * G.headSteady
	p.neckPitch = G.lean * 0.6 + G.nod * math.cos(phase * 2)
	return p
end

-- A limb pose: moved out by `spread` (+X = the limb's own side) and up by
-- `lift`, swinging about a point `pivot` studs above its joint.
local function limb(pitch: number, roll: number, side: number, spread: number, pivot: number, lift: number): CFrame
	local rotation = Pose.angles(pitch, 0, roll)
	if pivot ~= 0 then
		rotation = CFrame.new(0, pivot, 0) * rotation * CFrame.new(0, -pivot, 0)
	end
	return CFrame.new(side * spread, lift, 0) * rotation
end

local function evaluate(track: any, out: { [string]: CFrame }, dt: number): number
	local s = track.params
	local model = s.model
	local humanoid = s.humanoid or (model and model:FindFirstChildOfClass("Humanoid"))
	local root = s.root or (model and model:FindFirstChild("HumanoidRootPart"))
	if not (humanoid and root) or humanoid.Health <= 0 then
		return 0
	end
	s.humanoid, s.root = humanoid, root
	if s.clock == nil then
		s.clock = random:NextNumber(0, 100) -- so two idle players don't bob in sync
		s.phase, s.moving, s.sprint, s.ground, s.turnRoll = 0, 0, 0, 1, 0
	end

	local grounded = s.forceGround
		or s.speed ~= nil
		or (GROUND_STATES[humanoid:GetState()] == true and humanoid.FloorMaterial ~= Enum.Material.Air)
	s.ground += ((if grounded then 1 else 0) - s.ground) * math.min(1, dt * Locomotion.GROUND_RATE)
	s.clock += dt

	local speed: number
	if s.speed ~= nil then
		speed = s.speed
	elseif s.forceGround then
		speed = 0
	else
		local velocity = root.AssemblyLinearVelocity
		speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	end
	local walkSpeed = StarterPlayer.CharacterWalkSpeed
	local k = math.min(1, dt * Locomotion.BLEND_RATE)
	s.moving += (math.clamp(speed / (walkSpeed * 0.5), 0, 1) - s.moving) * k
	s.sprint += (math.clamp((speed - walkSpeed * 1.1) / (walkSpeed * 0.3), 0, 1) - s.sprint) * k
	local before = s.phase
	s.phase = (s.phase + dt * speed / Locomotion.STRIDE_LENGTH * math.pi * 2) % (math.pi * 2)
	-- A foot lands where the stride's bob is lowest (the legs furthest apart): phase
	-- pi/2 and 3pi/2. Report each one passed this frame.
	if s.onStep and not s.forceGround and s.ground > 0.9 and s.moving > 0.5 then
		for foot, at in FOOTFALLS do
			local crossed = if s.phase >= before then (before < at and at <= s.phase) else (at > before or at <= s.phase)
			if crossed then
				s.onStep(foot, s.sprint)
			end
		end
	end

	-- Lean into turns: roll toward the inside, from how fast the heading changes.
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local turnRate = 0
	if s.lastYaw and dt > 0 then
		turnRate = math.deg(((yaw - s.lastYaw + math.pi) % (math.pi * 2)) - math.pi) / dt
	end
	s.lastYaw = yaw
	local turnTarget = math.clamp(turnRate * Locomotion.TURN_LEAN, -Locomotion.TURN_LEAN_MAX, Locomotion.TURN_LEAN_MAX) * s.moving
	s.turnRoll += (turnTarget - s.turnRoll) * math.min(1, dt * 6)

	if s.ground < 0.01 then
		return 0 -- airborne: the default jump / fall pose shows untouched
	end

	local p = blank()
	addInto(p, idlePose(s), 1 - s.moving)
	addInto(p, gaitPose(Locomotion.WALK, s.phase), s.moving * (1 - s.sprint))
	addInto(p, gaitPose(Locomotion.SPRINT, s.phase), s.moving * s.sprint)
	p.rootRoll += s.turnRoll

	local leftHip = limb(p.lLegPitch, p.lLegRoll, -1, p.legSpread, p.legPivot, p.legLift)
	local rightHip = limb(p.rLegPitch, p.rLegRoll, 1, p.legSpread, p.legPivot, p.legLift)
	local body = CFrame.new(0, p.rootLift, 0) * Pose.angles(p.rootPitch, p.rootYaw, p.rootRoll)

	-- Plant: move the body until the lowest sole is back on the ground (down when
	-- swinging legs lift the feet, up when splayed legs would sink them).
	local lowest = math.huge
	for _, corner in LEFT_SOLE do
		lowest = math.min(lowest, (body * (LEFT_HIP + leftHip * corner)).Y)
	end
	for _, corner in RIGHT_SOLE do
		lowest = math.min(lowest, (body * (RIGHT_HIP + rightHip * corner)).Y)
	end
	local rise = lowest - REST_FOOT_Y
	if rise > 0 then
		body = CFrame.new(0, -rise * p.plant, 0) * body
	else
		body = CFrame.new(0, -rise, 0) * body -- never through the floor
	end

	out.Root = body
	out.Neck = Pose.angles(p.neckPitch, p.neckYaw, p.neckRoll)
	out.LeftShoulder = limb(p.lArmPitch, p.lArmRoll, -1, p.armSpread, p.armPivot, 0)
	out.RightShoulder = limb(p.rArmPitch, p.rArmRoll, 1, p.armSpread, p.armPivot, 0)
	out.LeftHip = leftHip
	out.RightHip = rightHip
	return s.ground
end

Locomotion.clip = Clip.procedural({
	name = "Locomotion",
	priority = "Movement",
	fadeIn = 0.25,
	evaluate = evaluate,
})

return Locomotion
