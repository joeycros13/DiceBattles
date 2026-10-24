--!strict
-- MeleeService: real-time weapon combat.
--
-- Weapons. A player always has one weapon selected from Config/Weapons (the
-- default at first, then whatever they pick in the Inventory panel); it is the one
-- weapon in their hotbar. It is either in hand or put away ("holstered"): every
-- spawn starts with it put away, the hotbar (HolsterWeapon) takes it out or puts
-- it back, and picking a weapon in the Inventory puts that one in hand. The
-- player's "SelectedWeapon" / "Holstered" attributes publish this for the HUD;
-- the character's "Weapon" attribute is set only while it is in hand. Each player owns a set
-- of weapons: the starter weapon, plus whatever enemies drop (IndexService rolls
-- the drops and calls grant). The set and the selected weapon are saved as the
-- "weapons" section of PlayerDataService (2026-10-09). It is published as the
-- player's "OwnedWeapons" attribute (comma-separated ids). Only owned weapons
-- can be equipped; removeWeapons takes weapons out of the set (selling them through
-- SellService, the admin panel's Remove, infusing). The starter weapon (Weapons.default,
-- the Dagger) is always owned and can't be removed, so nobody is ever left empty-handed. Equipping clones the
-- model from ReplicatedStorage/Assets/Weapons and welds its Grip into the right
-- hand; the character's "Weapon" attribute tells every client which swing to play.
--
-- Swings. The client animates its own swing straight away and reports two things:
-- WeaponSwing when it starts (rate-limited by the weapon's cooldown, and mirrored
-- to other clients through the character's "SwingSeq" attribute), and WeaponHit
-- at the moment of impact, naming the enemies it touched and where it drew them.
-- Only one WeaponHit is accepted per swing, and every target is re-checked here:
-- alive, near where the server has it, and within the weapon's
-- reach of the player. The client never decides damage.
--
-- Fighting back. A hit enemy leaves its client-side wander and becomes a Fight
-- owned here: it chases its attacker, stops just inside its attack range, and
-- attacks on its own cooldown. An attack lands after the enemy's windup only if
-- the player is still in reach, so stepping back dodges it. If the enemy or its
-- target strays past Balance.Melee.leashRange from the spawn point -- or the
-- target dies or leaves -- it walks home (immune on the way) and
-- heals to full. Damage to players goes through Humanoid:TakeDamage, so dying is
-- an ordinary Roblox respawn. Worn armour takes its share off every hit (the
-- player's ArmorDefense attribute, ArmorService; 2026-10-12).
--
-- Positions are published as FightPos / FightLook attributes through
-- WorldEnemyService; clients smooth toward them.
--
-- Tools (2026-10-18). The hand can hold a gathering tool instead (Config/Tools; the
-- hotbar's Slot2.. take one out through Remotes.HoldTool { kind }): the player's best
-- tool of that kind (ToolService.best), welded into the hand like a weapon. One thing
-- in hand: taking a tool out puts the weapon away and taking the weapon out puts the
-- tool away. While a tool is out the character's "Tool" attribute names it (and
-- "Weapon" is unset) and the player's "HeldTool" names its kind. A tool swing is
-- rate-limited and mirrored through SwingSeq like a weapon's, but never hits enemies;
-- GatherService takes its hits on trees and rocks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Enemies = require(Config:WaitForChild("Enemies"))
local MapLayout = require(Config:WaitForChild("MapLayout"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Tools = require(Config:WaitForChild("Tools"))
-- the Worldheart Blade's damage / speed / reach follow the cores in it (Infuse.adjust)
local Infuse = require(Config:WaitForChild("Infuse"))
local Potions = require(Config:WaitForChild("Potions"))
-- stat upgrades (Config/Upgrades): Attack, Defense and Attack Speed
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Bonuses = require(Config:WaitForChild("Bonuses"))
local Weld = require(Shared:WaitForChild("Animation"):WaitForChild("Weld"))

local MeleeService = {}

-- An admin's own damage multiplier (the admin panel's Damage card, 2026-10-12; replaced the old
-- Studio-only testDamageMultiplier) is the player's "DamageMultiplier" attribute, read by
-- Config/Bonuses.damage with the Strength potion and the Attack upgrade; it isn't saved, so
-- everyone starts each session at x1.
-- Balance.Melee.testStartWeapons too: owned from the start, Studio only.
local TEST_START_WEAPONS: { string } = if RunService:IsStudio() then (Balance.Melee.testStartWeapons or {}) else {}

local deps: any = nil
local WorldEnemyService: any = nil
local ToolService: any = nil

local EQUIPPED_NAME = "EquippedWeapon"
-- How far above an enemy's feet the ground probe starts. Steps and ramps lower
-- than this are climbed; anything taller (a hedge, a hill wall) starts the probe
-- inside itself, which a raycast ignores, so the enemy stays on the ground below.
local STEP_UP = 2.5
local PROBE_DEPTH = 30
local ARRIVE_EPSILON = 0.3
-- How far past its stopping distance a chasing enemy may be and still count as
-- arrived. Without it, an enemy that stops exactly at the distance can read as a
-- hair too far every tick and never get round to attacking.
local STOP_TOLERANCE = 0.3
-- A WeaponHit later than this after its swing is ignored.
local HIT_GRACE = 1
-- Fraction of the cooldown a swing must wait, allowing for network jitter.
local COOLDOWN_TOLERANCE = 0.85
-- Extra slack on a fighting enemy's position: it moves between the client
-- drawing it and the hit arriving here.
local MOVING_SLACK = 4
-- How long an enemy holds still after its windup while the blow plays out.
local RECOVERY = 0.35
-- Delay before a freshly hit enemy can attack, so the first exchange is the
-- player's.
local FIRST_ATTACK_DELAY = 0.5
-- Vertical distance beyond which an attack cannot connect.
local MAX_HEIGHT_GAP = 8

type PlayerState = {
	weapon: string, -- the selected weapon (the hotbar's)
	holstered: boolean, -- the weapon is put away (a tool may be out instead)
	tool: string?, -- the kind of tool in hand (Config/Tools), nil for none
	owned: { [string]: boolean },
	lastSwing: number,
	swingTime: number?, -- start of the swing awaiting its WeaponHit
	swingHit: boolean,
}

type Fight = {
	id: string,
	position: Vector3,
	look: Vector3,
	target: Player,
	nextAttack: number,
	busyUntil: number,
}

local playerStates: { [Player]: PlayerState } = {}
local fights: { [string]: Fight } = {}
-- Per-enemy constants measured on first use.
local groundOffsets: { [string]: number } = {}
local bodyRadii: { [string]: number } = {}
local frontReaches: { [string]: number } = {}

local groundParams: RaycastParams? = nil

-- ==================== helpers ====================

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function isAlive(player: Player): boolean
	local humanoid = humanoidOf(player)
	return humanoid ~= nil and humanoid.Health > 0 and rootOf(player) ~= nil
end

local function meleeOf(enemy: any): any
	local def = Enemies.get(enemy.archetype)
	return def and def.melee
end

-- Half the enemy's widest footprint: reach is measured to its edge, not its
-- centre, so long bodies like the Bull can be hit on the nose.
local function bodyRadius(enemy: any): number
	local cached = bodyRadii[enemy.id]
	if cached then
		return cached
	end
	local inst = enemy.instance
	local size = if inst:IsA("Model") then inst:GetExtentsSize() elseif inst:IsA("BasePart") then inst.Size else Vector3.one
	local radius = math.max(size.X, size.Z) / 2
	bodyRadii[enemy.id] = radius
	return radius
end

-- How far the enemy's face (or weapon tip) sticks out in front of its pivot.
-- An enemy's attack range is counted from there, so the Bull stops with its
-- horns, not its middle, at the player.
local function frontReach(enemy: any): number
	local cached = frontReaches[enemy.id]
	if cached then
		return cached
	end
	local inst = enemy.instance
	local pivot = if inst:IsA("Model") then inst:GetPivot() elseif inst:IsA("BasePart") then inst.CFrame else CFrame.new()
	local front = 0
	local parts = inst:GetDescendants()
	if inst:IsA("BasePart") then
		table.insert(parts, inst)
	end
	for _, part in parts do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local offset = pivot:PointToObjectSpace(part.Position)
			front = math.max(front, -offset.Z + part.Size.Z / 2)
		end
	end
	frontReaches[enemy.id] = front
	return front
end

-- ==================== ground ====================

-- Enemies walk on the world's Ground folder and its bridges, never on
-- decorations, structures or each other.
local function buildGroundParams(): RaycastParams
	local include: { Instance } = {}
	for _, root in MapLayout.worldRoots() do
		local ground = MapLayout.worldFolder(root, "Ground")
		if ground then
			table.insert(include, ground)
		end
		local structures = MapLayout.worldFolder(root, "Structures")
		local bridges = structures and structures:FindFirstChild("Bridges")
		if bridges then
			table.insert(include, bridges)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	return params
end

local function groundY(x: number, z: number, fromY: number): number?
	if not groundParams then
		groundParams = buildGroundParams()
	end
	local hit = Workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -PROBE_DEPTH, 0), groundParams)
	return hit and hit.Position.Y
end

-- Height of the enemy's pivot above the ground it was placed on.
local function groundOffset(enemy: any): number?
	local cached = groundOffsets[enemy.id]
	if cached then
		return cached
	end
	local origin: Vector3 = enemy.origin
	local y = groundY(origin.X, origin.Z, origin.Y)
	if not y then
		return nil
	end
	groundOffsets[enemy.id] = origin.Y - y
	return origin.Y - y
end

local function snapToGround(enemy: any, position: Vector3): Vector3
	local offset = groundOffset(enemy)
	if not offset then
		return position
	end
	local y = groundY(position.X, position.Z, position.Y - offset + STEP_UP)
	return if y then Vector3.new(position.X, y + offset, position.Z) else position
end

-- ==================== weapons ====================

local function weaponTemplate(id: string): Model?
	local assets = ReplicatedStorage:FindFirstChild(MapLayout.AssetsFolder)
	local folder = assets and assets:FindFirstChild("Weapons")
	local template = folder and folder:FindFirstChild(id)
	return if template and template:IsA("Model") then template else nil
end

-- Replicate the owned set for the Inventory to list.
local function publishOwned(player: Player, state: PlayerState)
	local ids = {}
	for id in state.owned do
		table.insert(ids, id)
	end
	table.sort(ids)
	player:SetAttribute("OwnedWeapons", table.concat(ids, ","))
end

-- Replicate the selected weapon and whether it is put away, for the hotbar.
local function publishHand(player: Player, state: PlayerState)
	player:SetAttribute("SelectedWeapon", state.weapon)
	player:SetAttribute("Holstered", state.holstered)
	player:SetAttribute("HeldTool", state.tool)
end

local function stateOf(player: Player): PlayerState
	local state = playerStates[player]
	if not state then
		-- Everyone starts with the starter weapon; the rest drop from enemies.
		local owned: { [string]: boolean } = {}
		for _, def in Weapons.list() do
			if def.starter then
				owned[def.id] = true
			end
		end
		local selected = Weapons.default
		for _, id in TEST_START_WEAPONS do
			if Weapons.get(id) then
				owned[id] = true
				if selected == Weapons.default then
					selected = id
				end
			end
		end
		state = { weapon = selected, holstered = true, tool = nil, owned = owned, lastSwing = 0, swingTime = nil, swingHit = false }
		playerStates[player] = state
		publishOwned(player, state)
		publishHand(player, state)
	end
	return state
end

local function canUse(state: PlayerState, id: string): boolean
	local def = Weapons.get(id)
	return def ~= nil and (def.unarmed == true or def.starter == true or state.owned[id] == true)
end

-- Weld the weapon's Grip into the right hand (Animation.Weld's RightHand socket:
-- the RightGripAttachment, or the bottom of an R6 arm). The weld is named
-- HandWeld -- the client's animators tip the weapon in the hand through it.
local function attach(character: Model, id: string): boolean
	local def = Weapons.get(id)
	if def and def.unarmed then
		-- Fists: nothing to hold.
		local held = character:FindFirstChild(EQUIPPED_NAME)
		if held then
			held:Destroy()
		end
		character:SetAttribute("Weapon", id)
		return true
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local template = weaponTemplate(id)
	if not (hand and hand:IsA("BasePart") and template) then
		return false
	end
	local old = character:FindFirstChild(EQUIPPED_NAME)
	if old then
		old:Destroy()
	end

	local model = template:Clone()
	model.Name = EQUIPPED_NAME
	if not Weld.toSocket(model, character, "RightHand", nil, "HandWeld") then
		model:Destroy()
		return false
	end
	-- worn pairs (the Gold Gauntlets): each child model with a Socket attribute goes on
	-- that socket too (the left glove on the left hand)
	for _, child in model:GetChildren() do
		local socket = child:GetAttribute("Socket")
		if child:IsA("Model") and type(socket) == "string" and child.PrimaryPart then
			Weld.toSocket(child, character, socket, nil, "OffHandWeld")
		end
	end
	model.Parent = character
	character:SetAttribute("Tool", nil)
	character:SetAttribute("Weapon", id)
	return true
end

-- Weld a tool (Config/Tools; its model in ReplicatedStorage/Assets/Tools) into the
-- right hand in place of whatever is held.
local function attachTool(character: Model, def: Tools.ToolDef): boolean
	local assets = ReplicatedStorage:FindFirstChild(MapLayout.AssetsFolder)
	local folder = assets and assets:FindFirstChild("Tools")
	local template = folder and folder:FindFirstChild(def.id)
	if not (template and template:IsA("Model")) then
		warn(`[MeleeService] no tool model ReplicatedStorage/Assets/Tools/{def.id}`)
		return false
	end
	local old = character:FindFirstChild(EQUIPPED_NAME)
	if old then
		old:Destroy()
	end
	local model = template:Clone()
	model.Name = EQUIPPED_NAME
	if not Weld.toSocket(model, character, "RightHand", nil, "HandWeld") then
		model:Destroy()
		return false
	end
	model.Parent = character
	character:SetAttribute("Weapon", nil)
	character:SetAttribute("Tool", def.id)
	return true
end

-- Put the held weapon away: nothing in hand, no hold pose.
local function holster(character: Model)
	local held = character:FindFirstChild(EQUIPPED_NAME)
	if held then
		held:Destroy()
	end
	character:SetAttribute("Weapon", nil)
	character:SetAttribute("Tool", nil)
end

-- Select a weapon (it becomes the hotbar's) and put it in hand.
function MeleeService.equip(player: Player, id: any): boolean
	local state = stateOf(player)
	if not canUse(state, id) then
		return false
	end
	state.weapon = id
	state.holstered = false
	state.tool = nil
	state.swingTime = nil
	publishHand(player, state)
	local character = player.Character
	return character ~= nil and attach(character, id)
end

-- Add a weapon to the player's set (an enemy drop). Returns true if it is new
-- to them; one of each is all a player can hold.
function MeleeService.grant(player: Player, id: string): boolean
	local def = Weapons.get(id)
	if not def or def.unarmed then
		return false
	end
	local state = stateOf(player)
	if state.owned[id] then
		return false
	end
	state.owned[id] = true
	publishOwned(player, state)
	return true
end

function MeleeService.owns(player: Player, id: string): boolean
	return stateOf(player).owned[id] == true
end

-- Take the selected weapon out, or put it away.
function MeleeService.setHolstered(player: Player, holstered: any)
	local state = stateOf(player)
	state.holstered = holstered == true
	state.tool = nil
	state.swingTime = nil
	publishHand(player, state)
	local character = player.Character
	if not character then
		return
	end
	if state.holstered then
		holster(character)
	else
		attach(character, state.weapon)
	end
end

-- Take out the best tool of a kind (a hotbar tool slot), or put it away if that kind
-- is already in hand (or `kind` is nil, or the player owns none of it). The weapon is
-- put away either way.
function MeleeService.holdTool(player: Player, kind: any)
	local state = stateOf(player)
	local def = if type(kind) == "string" then ToolService.best(player, kind) else nil
	local character = player.Character
	state.holstered = true
	state.swingTime = nil
	if not def or state.tool == kind then
		state.tool = nil
		publishHand(player, state)
		if character then
			holster(character)
		end
		return
	end
	state.tool = kind
	publishHand(player, state)
	if character then
		attachTool(character, def)
	end
end

-- The tool in hand may have changed (one taken away, a better one bought): hold the
-- slot's best tool now, or put it away if none is left.
function MeleeService.refreshTool(player: Player)
	local state = stateOf(player)
	if not state.tool then
		return
	end
	local def = ToolService.best(player, state.tool)
	local character = player.Character
	if not def then
		state.tool = nil
		publishHand(player, state)
		if character then
			holster(character)
		end
	elseif character and character:GetAttribute("Tool") ~= def.id then
		attachTool(character, def)
	end
end

-- ==================== fights ====================

local function startFight(enemy: any, attacker: Player, seenAt: Vector3)
	local fight = fights[enemy.id]
	if fight then
		-- Whoever hit it last has its attention.
		fight.target = attacker
		return
	end
	local start = snapToGround(enemy, Vector3.new(seenAt.X, enemy.origin.Y, seenAt.Z))
	local root = rootOf(attacker)
	local toward = if root then flat(root.Position - start) else Vector3.zero
	fights[enemy.id] = {
		id = enemy.id,
		position = start,
		look = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.new(0, 0, -1),
		target = attacker,
		nextAttack = os.clock() + FIRST_ATTACK_DELAY,
		busyUntil = 0,
	}
	WorldEnemyService.setAiState(enemy.id, "Chase")
	WorldEnemyService.setFightPose(enemy.id, start, fights[enemy.id].look)
end

local function targetValid(enemy: any, fight: Fight): boolean
	local target = fight.target
	if not (target.Parent == Players and isAlive(target)) then
		return false
	end
	local root = rootOf(target) :: BasePart
	local leash = Balance.Melee.leashRange
	return flat(root.Position - enemy.origin).Magnitude <= leash and flat(fight.position - enemy.origin).Magnitude <= leash
end

local function beginAttack(enemy: any, fight: Fight, melee: any, now: number)
	fight.nextAttack = now + melee.cooldown
	fight.busyUntil = now + melee.windup + RECOVERY
	WorldEnemyService.signalAttack(enemy.id)
	local target = fight.target
	task.delay(melee.windup, function()
		-- The fight may have ended, or the enemy died, during the windup.
		if fights[enemy.id] ~= fight or not enemy.alive or enemy.aiState ~= "Chase" then
			return
		end
		local root = rootOf(target)
		local humanoid = humanoidOf(target)
		if not (root and humanoid and humanoid.Health > 0) then
			return
		end
		local gap = flat(root.Position - fight.position).Magnitude
		local reach = frontReach(enemy) + melee.range + Balance.Melee.dodgeSlack
		if gap <= reach and math.abs(root.Position.Y - fight.position.Y) < MAX_HEIGHT_GAP then
			local defense = target:GetAttribute("ArmorDefense")
			defense = if type(defense) == "number" then math.clamp(defense, 0, 0.9) else 0
			-- a Stoneskin potion cuts what armour lets through (Config/Potions)
			local skin = Potions.multiplier(target, "Stoneskin")
			-- and the Defense upgrade cuts it again (Config/Upgrades)
			local guard = Upgrades.value(target, "Defense")
			humanoid:TakeDamage(math.max(1, math.floor(melee.damage * (1 - defense) * skin * guard + 0.5)))
			-- every client shows the hit on that body; the hit player stumbles back from here
			deps.Remotes.getEvent("PlayerHurt"):FireAllClients({ character = target.Character, from = fight.position })
		end
	end)
end

-- Move `from` toward `to` by at most `step`, stopping `keep` short of it.
local function approach(from: Vector3, to: Vector3, step: number, keep: number): Vector3
	local delta = flat(to - from)
	local distance = delta.Magnitude
	if distance <= keep + 1e-3 then
		return from
	end
	return from + delta.Unit * math.min(step, distance - keep)
end

local function stepFight(enemy: any, fight: Fight, melee: any, dt: number, now: number)
	if enemy.aiState == "Return" then
		local home: Vector3 = enemy.origin
		local toHome = flat(home - fight.position)
		if toHome.Magnitude <= ARRIVE_EPSILON then
			fights[enemy.id] = nil
			WorldEnemyService.setFightPose(enemy.id, home, fight.look)
			WorldEnemyService.setAiState(enemy.id, "Idle")
			return
		end
		fight.look = toHome.Unit
		fight.position = approach(fight.position, home, melee.chaseSpeed * Balance.Melee.returnSpeedScale * dt, 0)
		return
	end

	if not targetValid(enemy, fight) then
		WorldEnemyService.setAiState(enemy.id, "Return")
		return
	end

	local root = rootOf(fight.target) :: BasePart
	local toTarget = flat(root.Position - fight.position)
	if toTarget.Magnitude > 1e-3 then
		fight.look = toTarget.Unit
	end
	if now < fight.busyUntil then
		return
	end
	local stop = frontReach(enemy) + melee.range * Balance.Melee.stopFraction
	if toTarget.Magnitude > stop + STOP_TOLERANCE then
		fight.position = approach(fight.position, root.Position, melee.chaseSpeed * dt, stop)
	elseif now >= fight.nextAttack then
		beginAttack(enemy, fight, melee, now)
	end
end

-- Chasing enemies push apart so a flock does not stack into one chicken.
local function separate()
	local list: { Fight } = {}
	for _, fight in fights do
		table.insert(list, fight)
	end
	local minGap = Balance.Melee.separation
	for i = 1, #list do
		for j = i + 1, #list do
			local a, b = list[i], list[j]
			local delta = flat(b.position - a.position)
			local distance = delta.Magnitude
			if distance < minGap then
				local push = if distance > 1e-3 then delta.Unit else Vector3.new(1, 0, 0)
				local half = push * ((minGap - distance) / 2)
				a.position -= half
				b.position += half
			end
		end
	end
end

local function tick(dt: number)
	local now = os.clock()
	for id, fight in fights do
		local enemy = WorldEnemyService.get(id)
		local melee = enemy and meleeOf(enemy)
		if not (enemy and melee and enemy.alive) or enemy.aiState == "Idle" then
			fights[id] = nil
			continue
		end
		stepFight(enemy, fight, melee, dt, now)
	end
	separate()
	for id, fight in fights do
		local enemy = WorldEnemyService.get(id)
		if enemy then
			fight.position = snapToGround(enemy, fight.position)
			WorldEnemyService.setFightPose(id, fight.position, fight.look)
		end
	end
end

-- ==================== intents ====================

function MeleeService.WeaponSwing(player: Player, weaponId: any)
	local state = stateOf(player)
	-- a tool swing: rate-limited and shown to others the same way, never a WeaponHit
	local tool = if state.tool then ToolService.best(player, state.tool) else nil
	local def: any = if tool then (if tool.id == weaponId then tool else nil) else Upgrades.adjust(player, Infuse.adjust(player, Weapons.get(weaponId)))
	if not def or not isAlive(player) or (not tool and (state.holstered or state.weapon ~= weaponId)) then
		return
	end
	local now = os.clock()
	if now - state.lastSwing < def.cooldown * COOLDOWN_TOLERANCE then
		return
	end
	state.lastSwing = now
	state.swingTime = now
	state.swingHit = false
	local character = player.Character :: Model
	local seq = character:GetAttribute("SwingSeq")
	character:SetAttribute("SwingSeq", (if type(seq) == "number" then seq else 0) + 1)
end

function MeleeService.WeaponHit(player: Player, targets: any)
	local state = stateOf(player)
	local def = Upgrades.adjust(player, Infuse.adjust(player, Weapons.get(state.weapon)))
	local now = os.clock()
	if state.holstered or not (def and state.swingTime and not state.swingHit) or now - state.swingTime > def.cooldown + HIT_GRACE then
		return
	end
	state.swingHit = true
	local root = rootOf(player)
	if type(targets) ~= "table" or not root then
		return
	end

	local seen: { [string]: boolean } = {}
	local landed = 0
	for _, entry in targets do
		if landed >= def.maxTargets then
			break
		end
		if type(entry) ~= "table" or type(entry.id) ~= "string" or typeof(entry.pos) ~= "Vector3" or seen[entry.id] then
			continue
		end
		seen[entry.id] = true
		local enemy = WorldEnemyService.get(entry.id)
		local melee = enemy and meleeOf(enemy)
		if not (enemy and melee and enemy.alive) or enemy.aiState == "Return" then
			continue
		end

		-- Was the enemy plausibly where the client drew it?
		local claimed: Vector3 = entry.pos
		local fight = fights[enemy.id]
		local slack = Balance.Melee.hitSlack
		local plausible = if fight
			then flat(claimed - fight.position).Magnitude <= slack + MOVING_SLACK
			else flat(claimed - enemy.origin).Magnitude <= enemy.wanderRadius + slack
		if not plausible then
			continue
		end
		-- And within reach of the player?
		if flat(claimed - root.Position).Magnitude > def.reach + bodyRadius(enemy) + slack then
			continue
		end

		landed += 1
		-- some weapons (the Toadstool Mace) ignore armour (def.ignoreArmor)
		local armor = if def.ignoreArmor then 0 else (melee.armor or 0)
		-- each target rolls its own crit: Balance.Melee's 10% for 1.5x, raised by the
		-- Crit Chance and Crit Damage upgrades (their level 0 is that base)
		local crit = math.random() < Upgrades.value(player, "CritChance")
		-- Strength and the Attack upgrade add their shares, the admin test multiplier on top (Config/Bonuses)
		local damage = def.damage * Bonuses.damage(player) * (1 - armor)
		local died = WorldEnemyService.damage(enemy.id, if crit then damage * Upgrades.value(player, "CritDamage") else damage, player, crit)
		if died then
			fights[enemy.id] = nil
		else
			startFight(enemy, player, claimed)
			local current = fights[enemy.id]
			if current and def.knockback > 0 then
				local away = flat(current.position - root.Position)
				if away.Magnitude > 1e-3 then
					current.position += away.Unit * def.knockback
				end
			end
		end
	end
end

-- Remove weapons from the player's set (SellService sells through this). Removing the
-- selected weapon selects the starter weapon instead (in hand or put away, as before).
-- `force` (revoke: the admin panel's Remove, infusing) also takes key items. Returns how
-- many were removed.
function MeleeService.removeWeapons(player: Player, ids: { any }, force: boolean?): number
	if type(ids) ~= "table" then
		return 0
	end
	local state = stateOf(player)
	local removed = 0
	for _, id in ids do
		local def = Weapons.get(id)
		if def and not def.unarmed and not def.starter and (force or not def.keep) and state.owned[id] then
			state.owned[id] = nil
			removed += 1
		end
	end
	if removed == 0 then
		return 0
	end
	if not canUse(state, state.weapon) then
		state.weapon = Weapons.default
		publishHand(player, state)
		if not state.holstered and player.Character then
			attach(player.Character, state.weapon)
		end
	end
	publishOwned(player, state)
	return removed
end

-- Take one weapon away (the admin panel, infusing). The starter can't be removed.
-- Returns true if the player had it.
function MeleeService.revoke(player: Player, id: string): boolean
	if not MeleeService.owns(player, id) then
		return false
	end
	MeleeService.removeWeapons(player, { id }, true)
	return not MeleeService.owns(player, id)
end

-- ==================== lifecycle ====================

function MeleeService.init(injected: any)
	deps = injected
	WorldEnemyService = deps.Services.WorldEnemyService
	ToolService = deps.Services.ToolService
	-- Saved from the published attributes, which outlive this service's own
	-- state while the player is leaving.
	deps.Services.PlayerDataService.register("weapons", {
		load = function(player: Player, value: any)
			if type(value) ~= "table" then
				return
			end
			local state = stateOf(player)
			for _, id in (if type(value.owned) == "table" then value.owned else {}) do
				local def = Weapons.get(id)
				if def and not def.unarmed then
					state.owned[id] = true
				end
			end
			if type(value.selected) == "string" and canUse(state, value.selected) then
				state.weapon = value.selected
			end
			publishOwned(player, state)
			publishHand(player, state)
		end,
		save = function(player: Player): any
			local owned = {}
			local list = player:GetAttribute("OwnedWeapons")
			for id in (if type(list) == "string" then list else ""):gmatch("[^,]+") do
				table.insert(owned, id)
			end
			return { owned = owned, selected = player:GetAttribute("SelectedWeapon") }
		end,
	})
end

function MeleeService.start()
	deps.Remotes.getEvent("EquipWeapon").OnServerEvent:Connect(function(player: Player, id: any)
		MeleeService.equip(player, id)
	end)
	deps.Remotes.getEvent("HolsterWeapon").OnServerEvent:Connect(function(player: Player, holstered: any)
		MeleeService.setHolstered(player, holstered)
	end)
	deps.Remotes.getEvent("HoldTool").OnServerEvent:Connect(function(player: Player, kind: any)
		MeleeService.holdTool(player, kind)
	end)
	deps.Remotes.getEvent("WeaponSwing").OnServerEvent:Connect(function(player: Player, id: any)
		MeleeService.WeaponSwing(player, id)
	end)
	deps.Remotes.getEvent("WeaponHit").OnServerEvent:Connect(function(player: Player, targets: any)
		MeleeService.WeaponHit(player, targets)
	end)

	-- Every spawn starts with the selected weapon put away (it stays in the
	-- hotbar). When it is taken out, dressing the avatar (AvatarService) can
	-- strip anything added before it finished, so drawing waits for that, and the
	-- weapon is put back if it is ever removed without being replaced.
	local function onCharacter(player: Player, character: Model)
		local state = stateOf(player)
		state.holstered = true
		state.tool = nil
		publishHand(player, state)
		local waitUntil = os.clock() + 10
		while character:GetAttribute("AvatarReady") ~= true and os.clock() < waitUntil and player.Character == character do
			task.wait(0.1)
		end
		-- R6 holds the weapon in its "Right Arm", R15 in its "RightHand".
		local deadline = os.clock() + 5
		while not (character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")) and os.clock() < deadline do
			task.wait(0.1)
		end
		if player.Character ~= character then
			return
		end
		-- Taken out while the avatar was still being dressed: put it back in hand.
		if not state.holstered and not character:FindFirstChild(EQUIPPED_NAME) then
			attach(character, state.weapon)
		end
		character.ChildRemoved:Connect(function(child)
			if child.Name ~= EQUIPPED_NAME then
				return
			end
			task.defer(function()
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				-- a tool out: put the same tool back
				local toolKind = stateOf(player).tool
				if toolKind then
					local tool = ToolService.best(player, toolKind)
					if tool and player.Character == character and humanoid and humanoid.Health > 0 and not character:FindFirstChild(EQUIPPED_NAME) then
						attachTool(character, tool)
					end
					return
				end
				local current = Weapons.get(stateOf(player).weapon)
				local holdsModel = current ~= nil and not current.unarmed
				local drawn = not stateOf(player).holstered
				if drawn and holdsModel and player.Character == character and humanoid and humanoid.Health > 0 and not character:FindFirstChild(EQUIPPED_NAME) then
					attach(character, stateOf(player).weapon)
				end
			end)
		end)
	end
	local function onPlayer(player: Player)
		stateOf(player) -- publishes OwnedWeapons straight away
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		playerStates[player] = nil
	end)

	local interval = 1 / Balance.Melee.tickRate
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulated += dt
		if accumulated >= interval then
			tick(accumulated)
			accumulated = 0
		end
	end)
end

return MeleeService
