--!strict
-- CritterController: World 2's ambient animals -- deer grazing in small groups, squirrels
-- hopping round the tree trunks, and the owl on the lookout tower's roof ridge.
--
-- Each model tagged Critter (MapLayout.Tags.Critter) with a Kind attribute ("Deer",
-- "Squirrel" or "Owl") gets a PartRig (the rig contract is in PartRig) and an Animator
-- playing its kind's clip from Animation.Clips.Critters. This controller is the brain: it
-- decides what each animal does next and writes targets into the clip's state, and the
-- clip eases toward them. It also moves squirrels' Roots from hop to hop, turns deer on the
-- spot now and then, and blinks the owl (parts with the Blink attribute).
--
--   Deer      stand and look around (ears flick) -> graze (head down, chewing) -> stand;
--             sometimes step round to face a new way.
--   Squirrel  quick looks and tail flicks -> sit up on its haunches nibbling -> hop to a new
--             spot within WanderRadius (model attribute, default 5) of where it was placed:
--             only onto ground within one step of where it is, never into the creek, never
--             through a trunk or a building, never into a deer.
--   Owl       slow head swivels (well past its shoulders), a curious tilt, blinks, and a
--             wing ruffle now and then. While the camera is close it hoots now and then
--             (2026-10-21, the user's request): the hand-placed `Hoot` Sound inside the owl
--             (positional, so it carries from the roof) plays every CallMin..CallMax seconds
--             (its attributes) while the camera is within its RollOffMaxDistance, with a
--             little puff of the body.
--
-- One Scheduler system (Render, priority 12: after the enemies' wander at 10, before the
-- animators at 50). Animals farther than BRAIN_RANGE from the camera just wait; the
-- animators already skip far and off-screen rigs. Presentation only: nothing replicates.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared:WaitForChild("Config"):WaitForChild("MapLayout"))
local Animation = require(Shared:WaitForChild("Animation"))
local PartRig = Animation.PartRig
local Animator = Animation.Animator
local Scheduler = Animation.Scheduler
local CritterClips = Animation.Clips.Critters

local CritterController = {}

local BRAIN_RANGE = 220
local HOP_TIME = 0.3 -- seconds per hop
local HOP_LENGTH = 1.3 -- studs per hop, at most
local STEP_UP = 1.05 -- a squirrel hops up or down one hill step, no more
local TURN_TIME = 1.4 -- a deer stepping round

type Entry = {
	model: Model,
	kind: string,
	rig: any,
	animator: any,
	state: any,
	rng: Random,
	root: BasePart,
	half: number,
	feet: Vector3,
	yaw: number,
	home: Vector3,
	radius: number,
	mode: string,
	timer: number,
	look: number,
	flick: number,
	flickSide: string,
	path: { Vector3 },
	hopFrom: Vector3,
	hopT: number,
	turnFrom: number,
	turnTo: number,
	turnT: number,
	blink: number,
	blinkLeft: number,
	ruffle: number,
	tilt: number,
	hoot: number,
	hootSound: Sound?,
	eyelids: { BasePart },
	groundParams: RaycastParams?,
	blockParams: RaycastParams?,
	water: Instance?,
}

local entries: { [Model]: Entry } = {}

-- ==================== helpers ====================

local function place(e: Entry)
	e.root.CFrame = CFrame.new(e.feet + Vector3.new(0, e.half, 0)) * CFrame.Angles(0, e.yaw, 0)
end

local function setTargets(e: Entry, values: { [string]: number }, rates: { [string]: number }?)
	local target, rate = e.state.target, e.state.rate
	for k, v in values do
		target[k] = v
		rate[k] = if rates then rates[k] else nil
	end
end

local function yawTowards(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

-- Ground height at (x, z) near height y, or nil for water / no ground.
local function groundAt(e: Entry, x: number, z: number, y: number): number?
	local params = e.groundParams
	if not params then
		return nil
	end
	local hit = Workspace:Raycast(Vector3.new(x, y + 4, z), Vector3.new(0, -10, 0), params)
	if not hit or (e.water and hit.Instance:IsDescendantOf(e.water)) then
		return nil
	end
	return hit.Position.Y
end

-- A row of hop landings from the squirrel's feet to a spot near home, or nil.
local function planHops(e: Entry): { Vector3 }?
	for _ = 1, 8 do
		local a = e.rng:NextNumber(0, math.pi * 2)
		local r = e.radius * math.sqrt(e.rng:NextNumber())
		local goal = e.home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local flat = Vector3.new(goal.X - e.feet.X, 0, goal.Z - e.feet.Z)
		local d = flat.Magnitude
		if d < 1.2 or d > 4.5 then
			continue
		end
		-- nothing solid in the way (trunks, logs, buildings)
		if e.blockParams then
			local from = e.feet + Vector3.new(0, 0.6, 0)
			if Workspace:Raycast(from, flat, e.blockParams) then
				continue
			end
		end
		-- keep clear of the deer (critters aren't queryable, so check their feet)
		local nearDeer = false
		for _, other in entries do
			if other.kind == "Deer" then
				local off = Vector3.new(other.feet.X - goal.X, 0, other.feet.Z - goal.Z)
				if off.Magnitude < 3 + other.half * 0.6 then
					nearDeer = true
					break
				end
			end
		end
		if nearDeer then
			continue
		end
		local n = math.max(1, math.ceil(d / HOP_LENGTH))
		local path = {}
		local y = e.feet.Y
		local ok = true
		for i = 1, n do
			local p = e.feet + flat * (i / n)
			local gy = groundAt(e, p.X, p.Z, y)
			if not gy or math.abs(gy - y) > STEP_UP then
				ok = false
				break
			end
			y = gy
			table.insert(path, Vector3.new(p.X, gy, p.Z))
		end
		if ok then
			return path
		end
	end
	return nil
end

-- ==================== brains ====================

local function deer(e: Entry, dt: number)
	local s, rng = e.state, e.rng
	e.timer -= dt
	-- ear flicks whenever the head is up
	e.flick -= dt
	if e.flick <= 0 then
		e.flickSide = if rng:NextNumber() < 0.5 then "earL" else "earR"
		setTargets(e, { [e.flickSide] = 0.75 }, { [e.flickSide] = 30 })
		e.flick = rng:NextNumber(1.5, 4.5)
		task.delay(0.16, function()
			if e.state then
				setTargets(e, { [e.flickSide] = 0 }, { [e.flickSide] = 12 })
			end
		end)
	end
	if e.mode == "turn" then
		e.turnT = math.min(1, e.turnT + dt / TURN_TIME)
		local u = e.turnT
		local k = u * u * (3 - 2 * u)
		e.yaw = e.turnFrom + (e.turnTo - e.turnFrom) * k
		s.shuffle = math.sin(math.pi * u)
		place(e)
		if u >= 1 then
			s.shuffle = 0
			e.mode, e.timer = "stand", rng:NextNumber(1.5, 3)
		end
		return
	end
	if e.mode == "stand" then
		e.look -= dt
		if e.look <= 0 then
			e.look = rng:NextNumber(1.2, 2.6)
			setTargets(e, { headYaw = rng:NextNumber(-0.5, 0.5), headTilt = rng:NextNumber(-0.05, 0.15), headRoll = rng:NextNumber(-0.06, 0.06) })
		end
	end
	if e.timer > 0 then
		return
	end
	local roll = rng:NextNumber()
	if e.mode == "graze" or roll < 0.15 then
		e.mode, e.timer = "stand", rng:NextNumber(2.5, 5)
		setTargets(e, { headTilt = 0.08, lean = 0, lift = 0, chew = 0 }, { headTilt = 1.6 })
	elseif roll < 0.75 then
		e.mode, e.timer = "graze", rng:NextNumber(4, 9)
		setTargets(e, { headTilt = -1.7, headYaw = rng:NextNumber(-0.15, 0.15), headRoll = 0, lean = 0.1, lift = -0.12, chew = 1 }, { headTilt = 1.6 })
	else
		e.mode = "turn"
		e.turnFrom, e.turnT = e.yaw, 0
		e.turnTo = e.yaw + rng:NextNumber(0.3, 0.8) * (if rng:NextNumber() < 0.5 then -1 else 1)
		setTargets(e, { headTilt = 0.08, lean = 0, lift = 0, chew = 0, headYaw = 0 })
	end
end

local function squirrel(e: Entry, dt: number)
	local s, rng = e.state, e.rng
	if e.mode == "hop" then
		e.hopT += dt / HOP_TIME
		local target = e.path[1]
		if e.hopT >= 1 then
			e.feet = target
			table.remove(e.path, 1)
			if #e.path == 0 then
				s.hop = nil
				place(e)
				e.mode, e.timer = "idle", rng:NextNumber(0.6, 1.6)
				return
			end
			e.hopFrom, e.hopT = e.feet, 0
			target = e.path[1]
		end
		local u = e.hopT
		local flat = target - e.hopFrom
		e.yaw = yawTowards(Vector3.new(flat.X, 0, flat.Z))
		e.feet = e.hopFrom + flat * u
		s.hop = u
		place(e)
		e.feet = if u >= 1 then target else e.feet
		return
	end
	e.timer -= dt
	e.look -= dt
	if e.look <= 0 then
		e.look = rng:NextNumber(0.3, 0.9) * (if e.mode == "sit" then 1.8 else 1)
		setTargets(e, { headYaw = rng:NextNumber(-0.7, 0.7), headTilt = rng:NextNumber(-0.2, 0.2) })
		if rng:NextNumber() < 0.3 then
			setTargets(e, { tail = -0.35 }, { tail = 25 })
			task.delay(0.18, function()
				if e.state then
					setTargets(e, { tail = 0 })
				end
			end)
		end
	end
	if e.timer > 0 then
		return
	end
	local roll = rng:NextNumber()
	if e.mode == "sit" then
		setTargets(e, { sit = 0 }, { sit = 7 })
		e.mode, e.timer = "idle", rng:NextNumber(0.5, 1.2)
	elseif roll < 0.5 then
		local path = planHops(e)
		if path then
			e.mode, e.path, e.hopFrom, e.hopT = "hop", path, e.feet, 0
			setTargets(e, { headYaw = 0, headTilt = 0 })
		else
			e.timer = rng:NextNumber(0.5, 1.2)
		end
	elseif roll < 0.8 then
		setTargets(e, { sit = 1 }, { sit = 7 })
		e.mode, e.timer = "sit", rng:NextNumber(1.5, 3.5)
	else
		e.timer = rng:NextNumber(0.8, 2)
	end
end

local function owl(e: Entry, dt: number)
	local rng = e.rng
	-- slow, owl-ish head turns (fast swing, long hold), often well past the shoulders
	e.look -= dt
	if e.look <= 0 then
		e.look = rng:NextNumber(2.5, 6)
		local yaw = if rng:NextNumber() < 0.3 then 0 else rng:NextNumber(0.6, 2.2) * (if rng:NextNumber() < 0.5 then -1 else 1)
		setTargets(e, { headYaw = yaw }, { headYaw = 5 })
	end
	-- a curious tilt now and then
	e.tilt -= dt
	if e.tilt <= 0 then
		e.tilt = rng:NextNumber(4, 9)
		local roll = if rng:NextNumber() < 0.5 then rng:NextNumber(-0.35, 0.35) else 0
		setTargets(e, { headRoll = roll }, { headRoll = 4 })
	end
	-- blinks (sometimes a double blink)
	e.blink -= dt
	if e.blinkLeft > 0 then
		e.blinkLeft -= dt
		if e.blinkLeft <= 0 then
			for _, lid in e.eyelids do
				lid.Transparency = 1
			end
		end
	elseif e.blink <= 0 then
		e.blink = if rng:NextNumber() < 0.2 then 0.22 else rng:NextNumber(2, 5)
		e.blinkLeft = 0.12
		for _, lid in e.eyelids do
			lid.Transparency = 0
		end
	end
	-- a hoot while you're near
	local sound = e.hootSound
	if sound then
		e.hoot -= dt
		if e.hoot <= 0 then
			local low, high = sound:GetAttribute("CallMin"), sound:GetAttribute("CallMax")
			e.hoot = rng:NextNumber(if type(low) == "number" then low else 8, if type(high) == "number" then high else 16)
			local camera = Workspace.CurrentCamera
			if camera and (camera.CFrame.Position - e.feet).Magnitude < sound.RollOffMaxDistance then
				sound:Play()
				setTargets(e, { lift = 0.06 }, { lift = 12 })
				task.delay(0.4, function()
					if e.state then
						setTargets(e, { lift = 0 }, { lift = 6 })
					end
				end)
			end
		end
	end
	-- a wing ruffle
	e.ruffle -= dt
	if e.ruffle <= 0 then
		e.ruffle = rng:NextNumber(9, 16)
		setTargets(e, { wing = 0.35, lift = 0.05 }, { wing = 14, lift = 10 })
		task.delay(0.35, function()
			if e.state then
				setTargets(e, { wing = 0, lift = 0 }, { wing = 6, lift = 6 })
			end
		end)
	end
end

local BRAINS: { [string]: (Entry, number) -> () } = { Deer = deer, Squirrel = squirrel, Owl = owl }

-- ==================== lifecycle ====================

local function adopt(inst: Instance)
	if not inst:IsA("Model") or entries[inst] then
		return
	end
	local kind = inst:GetAttribute("Kind")
	if type(kind) ~= "string" or not BRAINS[kind] then
		return
	end
	local clip = CritterClips.clip(kind)
	local rig = PartRig.new(inst)
	if not (clip and rig) then
		return
	end
	local animator = Animator.new(rig, { cull = true })
	local rng = Random.new()
	local state = { rig = rig, seed = rng:NextNumber(0, 10), cur = {}, target = {}, rate = {}, hop = nil, shuffle = 0 }
	animator:Play(clip, { params = state })
	local root = rig.root :: BasePart
	local look = root.CFrame.LookVector
	local half = root.Size.Y / 2
	local feet = root.Position - Vector3.new(0, half, 0)
	local eyelids = {}
	for _, part in inst:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Blink") then
			part.Transparency = 1
			table.insert(eyelids, part)
		end
	end
	local entry: Entry = {
		model = inst,
		kind = kind,
		rig = rig,
		animator = animator,
		state = state,
		rng = rng,
		root = root,
		half = half,
		feet = feet,
		yaw = math.atan2(-look.X, -look.Z),
		home = feet,
		radius = (inst:GetAttribute("WanderRadius") :: number?) or 5,
		mode = if kind == "Squirrel" then "idle" else "stand",
		timer = rng:NextNumber(0.5, 3),
		look = rng:NextNumber(0, 1),
		flick = rng:NextNumber(1, 4),
		flickSide = "earL",
		path = {},
		hopFrom = feet,
		hopT = 0,
		turnFrom = 0,
		turnTo = 0,
		turnT = 0,
		blink = rng:NextNumber(1, 4),
		blinkLeft = 0,
		ruffle = rng:NextNumber(5, 12),
		tilt = rng:NextNumber(2, 6),
		hoot = rng:NextNumber(2, 6),
		hootSound = inst:FindFirstChild("Hoot", true) :: Sound?,
		eyelids = eyelids,
		groundParams = nil,
		blockParams = nil,
		water = nil,
	}
	if kind == "Squirrel" then
		local world = MapLayout.worldRootOf(inst)
		local ground = world and MapLayout.worldFolder(world, "Ground")
		local structures = world and MapLayout.worldFolder(world, "Structures")
		local decorations = world and MapLayout.worldFolder(world, "Decorations")
		if ground then
			local gp = RaycastParams.new()
			gp.FilterType = Enum.RaycastFilterType.Include
			gp.FilterDescendantsInstances = { ground, structures :: any, decorations :: any }
			entry.groundParams = gp
			entry.water = ground:FindFirstChild("Creek")
			local bp = RaycastParams.new()
			bp.FilterType = Enum.RaycastFilterType.Include
			bp.FilterDescendantsInstances = { structures :: any, decorations :: any }
			entry.blockParams = bp
		end
	end
	entries[inst] = entry
end

local function forget(inst: Instance)
	local entry = entries[inst :: any]
	if entry then
		entries[inst :: any] = nil
		entry.state = nil
		entry.animator:Destroy()
	end
end

function CritterController.init(_injected: any) end

function CritterController.start()
	local tag = MapLayout.Tags.Critter
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		task.defer(adopt, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(forget)
	for _, inst in CollectionService:GetTagged(tag) do
		adopt(inst)
	end
	Scheduler.bind("Render", "Critters", 12, function(dt)
		local camera = Workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position
		for _, entry in entries do
			if camPos and (entry.feet - camPos).Magnitude > BRAIN_RANGE then
				continue
			end
			BRAINS[entry.kind](entry, dt)
		end
	end)
end

return CritterController
