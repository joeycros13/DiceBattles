--!strict
-- WorldEnemyService: the authoritative registry for the enemies standing in the
-- world. Studio owns the spawn markers; this service owns everything else --
-- which archetype spawns where, each enemy's state, and its respawn.
--
-- An enemy comes from a marker in <World>/Spawns/EnemySpawns, a boss from one in
-- <World>/Spawns/BossSpawns. If a model of the marker's archetype exists in
-- ServerStorage/Assets/Enemies (or /Bosses), it is cloned to the marker's pose
-- and the marker is put away in ServerStorage/SpawnMarkers (a marker is a full
-- preview copy of the enemy, so left in Workspace, even hidden, every player
-- would download it); if not, the marker itself becomes the body. That
-- fallback is deliberate: a bare Part dropped into EnemySpawns is a working enemy
-- immediately, and adding the model later upgrades it with no edits here.
--
-- Bosses work exactly like enemies; only their wander/respawn defaults differ.
-- An enemy's max HP is its `hp` in Config/Worlds.
--
-- Replication is attribute-based: each live body carries EnemyId / Archetype /
-- MaxHp / Hp / Alive / AiState / WorldId / WanderRadius, which reach every
-- client for free and need no bespoke remote or per-player bookkeeping. The body
-- is also tagged WorldEnemy, which is how WorldEnemyController finds it without
-- knowing any folder path. In exchange the client owns every visual -- the
-- wander drift, the health bar, and hiding a defeated enemy.
--
-- Because the wander is client-side, this service never moves an idle enemy, so
-- its server-side position is its spawn point.
--
-- Kills: defeat() takes the player whose weapon hit finished it, and
-- onDefeated() listeners hear (enemy, killer) -- IndexService, CoinService,
-- ExpService and QuestService use that.
--
-- Fights live in MeleeService. While one runs, the enemy's AiState is "Chase"
-- or "Return" and MeleeService -- not the client wander -- decides where it
-- stands, publishing FightPos / FightLook for clients to follow.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Enemies = require(Config:WaitForChild("Enemies"))
local MapLayout = require(Config:WaitForChild("MapLayout"))
local Worlds = require(Config:WaitForChild("Worlds"))

local WorldEnemyService = {}

-- How long to wait for Studio's map to finish replicating into Workspace.
local MAP_TIMEOUT = 30

export type WorldEnemy = {
	id: string,
	instance: Instance, -- the live body clients see and this service publishes to
	marker: Instance, -- the authored spawn point (same object when no template exists)
	worldId: number,
	archetype: string,
	isBoss: boolean,
	origin: Vector3,
	maxHp: number,
	hp: number,
	alive: boolean,
	respawnSeconds: number,
	wanderRadius: number,
	aiState: string, -- "Idle" (wandering), "Chase" or "Return" (MeleeService owns it)
}

local enemies: { [string]: WorldEnemy } = {}
local defeatedListeners: { (WorldEnemy, Player?) -> () } = {}
-- deaths per enemy id, so a stale respawn timer can tell it's been overtaken
local lives: { [string]: number } = {}

-- ==================== map discovery ====================

local function waitForWorlds(): { Instance }
	local deadline = os.clock() + MAP_TIMEOUT
	while os.clock() < deadline do
		local roots = MapLayout.worldRoots()
		if #roots > 0 then
			return roots
		end
		task.wait(0.5)
	end
	return {}
end

-- Markers are found two ways on purpose: anything sitting in the world's
-- EnemySpawns folder counts, and so does anything tagged EnemySpawn wherever it
-- sits. The folder alone is enough for the common case (drop a part in), and the
-- tag covers markers that live inside some other model.
local function markersIn(root: Instance, folderName: string, tag: string): { Instance }
	local found: { Instance } = {}
	local seen: { [Instance]: boolean } = {}

	local function consider(inst: Instance)
		if seen[inst] or not (inst:IsA("BasePart") or inst:IsA("Model")) then
			return
		end
		seen[inst] = true
		table.insert(found, inst)
	end

	local spawns = MapLayout.worldFolder(root, "Spawns")
	local folder = spawns and spawns:FindFirstChild(folderName)
	if folder then
		for _, child in folder:GetChildren() do
			consider(child)
		end
	end
	for _, tagged in CollectionService:GetTagged(tag) do
		if tagged:IsDescendantOf(root) then
			consider(tagged)
		end
	end

	return found
end

-- ==================== spawning a body ====================

local function cframeOf(inst: Instance): CFrame
	if inst:IsA("BasePart") then
		return inst.CFrame
	elseif inst:IsA("Model") then
		return inst:GetPivot()
	end
	return CFrame.new()
end

local function templateFor(folderName: string, id: string): Instance?
	local assets = ServerStorage:FindFirstChild(MapLayout.AssetsFolder)
	local folder = assets and assets:FindFirstChild(folderName)
	local template = folder and folder:FindFirstChild(id)
	if template and (template:IsA("Model") or template:IsA("BasePart")) then
		return template
	end
	return nil
end

-- The wander writes CFrames on the client every frame, so the body must not also
-- be driven by physics.
local function anchorAll(inst: Instance)
	if inst:IsA("BasePart") then
		inst.Anchored = true
	end
	for _, descendant in inst:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

-- A marker that has been replaced by a spawned model is still the record of
-- where the enemy belongs (its pivot and attributes are read at registration),
-- but nobody needs to see it: it moves out of Workspace into a server-only
-- folder, so clients never receive its parts. The saved place keeps it in the
-- map as the edit-time preview.
local storedMarkers: Folder? = nil
local function stowMarker(marker: Instance)
	if not storedMarkers then
		local folder = Instance.new("Folder")
		folder.Name = "SpawnMarkers"
		folder.Parent = ServerStorage
		storedMarkers = folder
	end
	marker.Parent = storedMarkers
end

local function poseAt(body: Instance, cf: CFrame)
	if body:IsA("Model") then
		body:PivotTo(cf)
	elseif body:IsA("BasePart") then
		body.CFrame = cf
	end
end

-- Returns the instance that becomes the enemy's body: a clone of the archetype's
-- template, or the marker itself when no template exists yet.
local function bodyFor(marker: Instance, archetype: string, isBoss: boolean, container: Instance?): Instance
	local template = templateFor(if isBoss then "Bosses" else "Enemies", archetype)
	if not template or not container then
		anchorAll(marker)
		return marker
	end

	local body = template:Clone()
	body.Name = archetype
	poseAt(body, cframeOf(marker))
	anchorAll(body)
	body.Parent = container
	stowMarker(marker)
	return body
end

-- ==================== registration ====================

-- Push the enemy's state to every client. Attributes are the entire replication
-- channel for world enemies, so this runs after every mutation.
local function publish(enemy: WorldEnemy)
	local inst = enemy.instance
	inst:SetAttribute("EnemyId", enemy.id)
	inst:SetAttribute("Archetype", enemy.archetype)
	inst:SetAttribute("IsBoss", enemy.isBoss)
	inst:SetAttribute("WorldId", enemy.worldId)
	inst:SetAttribute("MaxHp", enemy.maxHp)
	inst:SetAttribute("Hp", enemy.hp)
	inst:SetAttribute("Alive", enemy.alive)
	inst:SetAttribute("AiState", enemy.aiState)
end

-- Resolve a marker's archetype: an enemy marker's Archetype attribute (falling
-- back to the owning world's default), or a boss marker's BossId. Returns nil
-- when nothing valid is named.
local function archetypeFor(marker: Instance, worldId: number, isBoss: boolean): string?
	local attribute = if isBoss then "BossId" else "Archetype"
	local named = marker:GetAttribute(attribute)
	if type(named) == "string" and Enemies.get(named) then
		return named
	end
	if type(named) == "string" then
		warn(("[WorldEnemyService] %s names unknown %s %q"):format(marker:GetFullName(), attribute, named))
	end
	if isBoss then
		return nil
	end
	local world = Worlds.get(worldId)
	local default = world and world.worldEnemy and world.worldEnemy.archetype
	if default and Enemies.get(default) then
		return default
	end
	return nil
end

local function numberAttribute(inst: Instance, name: string, fallback: number): number
	local value = inst:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- How long a defeated enemy stays down: its world's time for its kind (the user's
-- rule, 2026-10-19: one time per tier per world, bosses and the secret enemy alike).
local function respawnFor(worldId: number, def: any, isBoss: boolean): number
	local world = Worlds.get(worldId)
	local times = world and world.respawn
	if times then
		if isBoss then
			return times.boss
		elseif def and def.secret then
			return times.secret
		elseif def and def.tier and times[def.tier] then
			return times[def.tier]
		end
	end
	return if isBoss then Balance.WorldEnemy.bossRespawnSeconds else Balance.WorldEnemy.respawnSeconds
end

local function register(marker: Instance, worldId: number, index: number, isBoss: boolean): boolean
	local archetype = archetypeFor(marker, worldId, isBoss)
	if not archetype then
		warn(("[WorldEnemyService] %s has no valid %s; skipping"):format(marker:GetFullName(), if isBoss then "BossId" else "Archetype"))
		return false
	end

	local root = MapLayout.worldRootOf(marker)
	local container = root and MapLayout.worldFolder(root, if isBoss then "Bosses" else "Enemies")
	local body = bodyFor(marker, archetype, isBoss, container)

	-- Studio names can repeat, so the world id, kind and index keep ids unique.
	local id = ("%d:%s%s#%d"):format(worldId, if isBoss then "boss:" else "", marker.Name, index)
	local def = Enemies.get(archetype)
	local maxHp = math.max(1, def and def.hp or 1)
	local wanderRadius = numberAttribute(
		marker,
		"WanderRadius",
		if isBoss then Balance.WorldEnemy.bossWanderRadius else Balance.WorldEnemy.wanderRadius
	)
	local enemy: WorldEnemy = {
		id = id,
		instance = body,
		marker = marker,
		worldId = worldId,
		archetype = archetype,
		isBoss = isBoss,
		origin = cframeOf(marker).Position,
		maxHp = maxHp,
		hp = maxHp,
		alive = true,
		respawnSeconds = numberAttribute(marker, "RespawnSeconds", respawnFor(worldId, def, isBoss)),
		wanderRadius = wanderRadius,
		aiState = "Idle",
	}
	enemies[id] = enemy

	-- The wander itself runs on the client, which reads its radius from here.
	-- MeleeService also uses it to check hits on a wandering enemy.
	body:SetAttribute("WanderRadius", wanderRadius)
	local melee = def and def.melee
	if melee then
		body:SetAttribute("AttackMove", melee.move)
	end
	publish(enemy)
	-- Tagged last: the controller adopts a body the moment it sees the tag, so
	-- every attribute it reads must already be there.
	CollectionService:AddTag(body, MapLayout.Tags.WorldEnemy)
	return true
end

-- ==================== reads ====================

function WorldEnemyService.get(enemyId: string): WorldEnemy?
	return enemies[enemyId]
end

-- Every registered enemy, keyed by id. Read-only for callers.
function WorldEnemyService.all(): { [string]: WorldEnemy }
	return enemies
end

-- ==================== mutations ====================

-- Weapon damage from MeleeService. Returns true when the hit killed the enemy,
-- which is then defeated (credited to `attacker`).
function WorldEnemyService.damage(enemyId: string, amount: number, attacker: Player?, crit: boolean?): boolean
	local enemy = enemies[enemyId]
	if not enemy or not enemy.alive then
		return false
	end
	enemy.hp = math.max(0, enemy.hp - math.max(0, math.floor(amount + 0.5)))
	-- Who landed the hit ("HitBy", their UserId), set before Hp like CritHp: only that
	-- player's screen draws the damage bubble and, on the killing hit, the BONK
	-- (2026-10-23, the user: other players shouldn't see someone else's).
	enemy.instance:SetAttribute("HitBy", if attacker then attacker.UserId else nil)
	-- A critical hit marks the HP it left ("CritHp"), set before Hp so the client
	-- reads both together and draws the gold bubble; any other hit clears it.
	enemy.instance:SetAttribute("CritHp", if crit then enemy.hp else nil)
	if enemy.hp <= 0 then
		WorldEnemyService.defeat(enemyId, attacker)
		return true
	end
	publish(enemy)
	return false
end

-- MeleeService's fight state. Going back to "Idle" also clears the fight pose and
-- restores full HP: an enemy that gave up on a fight walked home to heal.
function WorldEnemyService.setAiState(enemyId: string, state: string)
	local enemy = enemies[enemyId]
	if not enemy or enemy.aiState == state then
		return
	end
	enemy.aiState = state
	if state == "Idle" then
		enemy.instance:SetAttribute("FightPos", nil)
		enemy.instance:SetAttribute("FightLook", nil)
		if enemy.alive then
			enemy.hp = enemy.maxHp
		end
	end
	publish(enemy)
end

-- Where a fighting enemy stands and faces. Published on its own, not through
-- publish(), because it changes many times a second.
function WorldEnemyService.setFightPose(enemyId: string, position: Vector3, look: Vector3)
	local enemy = enemies[enemyId]
	if not enemy then
		return
	end
	enemy.instance:SetAttribute("FightPos", position)
	enemy.instance:SetAttribute("FightLook", look)
end

-- Picks among an enemy's attack moves (melee.moves).
local moveRandom = Random.new()

-- Tell watching clients an attack started, so they play its animation. An
-- enemy with several moves (melee.moves) picks one evenly at random; it is set
-- before AttackSeq ticks, so every client plays the same one.
function WorldEnemyService.signalAttack(enemyId: string)
	local enemy = enemies[enemyId]
	if not enemy then
		return
	end
	local def = Enemies.get(enemy.archetype)
	local moves = def and def.melee and def.melee.moves
	if moves and #moves > 0 then
		enemy.instance:SetAttribute("AttackMove", moves[moveRandom:NextInteger(1, #moves)])
	end
	local seq = enemy.instance:GetAttribute("AttackSeq")
	enemy.instance:SetAttribute("AttackSeq", (if type(seq) == "number" then seq else 0) + 1)
end

-- Call `callback(enemy, killer)` whenever an enemy is defeated. `killer` is
-- the player who won, when there is one.
function WorldEnemyService.onDefeated(callback: (WorldEnemy, Player?) -> ())
	table.insert(defeatedListeners, callback)
end

-- The enemy lost a fight: mark it dead (clients hide it) and queue its respawn.
function WorldEnemyService.defeat(enemyId: string, killer: Player?)
	local enemy = enemies[enemyId]
	if not enemy or not enemy.alive then
		return
	end
	enemy.hp = 0
	enemy.alive = false
	enemy.aiState = "Idle"
	enemy.instance:SetAttribute("FightPos", nil)
	enemy.instance:SetAttribute("FightLook", nil)
	publish(enemy)
	for _, callback in defeatedListeners do
		task.spawn(callback, enemy, killer)
	end

	-- Each death gets a number, so a respawn forced early (the admin panel)
	-- isn't followed by this timer reviving it again mid-fight.
	local life = (lives[enemyId] or 0) + 1
	lives[enemyId] = life
	task.delay(enemy.respawnSeconds, function()
		-- The registry entry may have been dropped, or the body removed, while the
		-- respawn was pending.
		local current = enemies[enemyId]
		if not current or not current.instance.Parent or lives[enemyId] ~= life then
			return
		end
		current.hp = current.maxHp
		current.alive = true
		current.aiState = "Idle"
		publish(current)
	end)
end

-- Bring every enemy of one kind back now, at full HP and calm (the admin
-- panel, 2026-10-11): the dead ones reappear, the living ones are healed and
-- dropped out of any fight. Returns how many there are.
function WorldEnemyService.respawnArchetype(archetype: string): number
	local count = 0
	for id, enemy in enemies do
		if enemy.archetype ~= archetype or not enemy.instance.Parent then
			continue
		end
		count += 1
		lives[id] = (lives[id] or 0) + 1 -- cancels a pending timed respawn
		enemy.hp = enemy.maxHp
		enemy.alive = true
		enemy.aiState = "Idle"
		enemy.instance:SetAttribute("FightPos", nil)
		enemy.instance:SetAttribute("FightLook", nil)
		publish(enemy)
	end
	return count
end

-- ==================== lifecycle ====================

function WorldEnemyService.start()
	task.spawn(function()
		local roots = waitForWorlds()
		if #roots == 0 then
			warn(("[WorldEnemyService] no %s folder in Workspace; no world enemies registered"):format(
				MapLayout.WorldsFolder
			))
			return
		end

		local total, bosses = 0, 0
		for _, root in roots do
			local world = Worlds.byFolder(root.Name)
			local worldId = MapLayout.worldIdOf(root) or (world and world.id)
			if not worldId then
				warn(("[WorldEnemyService] %s has no WorldId attribute and no matching world config; skipping"):format(
					root:GetFullName()
				))
				continue
			end

			for index, marker in markersIn(root, "EnemySpawns", MapLayout.Tags.EnemySpawn) do
				if register(marker, worldId, index, false) then
					total += 1
				end
			end
			for index, marker in markersIn(root, "BossSpawns", MapLayout.Tags.BossSpawn) do
				if register(marker, worldId, index, true) then
					bosses += 1
				end
			end
		end

		print(("[WorldEnemyService] registered %d world enemies and %d bosses across %d worlds"):format(
			total,
			bosses,
			#roots
		))
	end)
end

return WorldEnemyService
