-- Dump one world's balance data for art/tools/balance/world_sim.py.
-- Run it in Studio's Edit datamodel (execute_luau, or the command bar) and save
-- what it returns as art/tools/balance/world<N>.json. Everything comes from the
-- real configs and the map, so the simulation never holds a typed-in number.
-- Set WORLD to the world to dump. Portraits, icons and dialogue are left out.
local WORLD = 1

local HttpService = game:GetService("HttpService")
local Config = game.ReplicatedStorage.Shared.Config

-- keep only what JSON can hold (Color3s, functions... are dropped)
local function plain(v: any, depth: number?): any
	local d = depth or 0
	local t = typeof(v)
	if t == "number" or t == "string" or t == "boolean" then
		return v
	elseif t == "table" and d < 8 then
		local out = {}
		for k, x in v do
			local p = plain(x, d + 1)
			if p ~= nil then
				out[tostring(k)] = p
			end
		end
		return out
	end
	return nil
end

local function pos(inst: Instance?): { number }?
	if not inst then
		return nil
	end
	local p = if inst:IsA("Model") then inst:GetPivot().Position elseif inst:IsA("BasePart") then inst.Position else nil
	return p and { math.floor(p.X * 10 + 0.5) / 10, math.floor(p.Y * 10 + 0.5) / 10, math.floor(p.Z * 10 + 0.5) / 10 }
end

-- Edit mode caches require() between runs, so a config Rojo just changed would
-- come back stale: require a fresh copy of each module instead.
local function fresh(module: Instance): any
	local copy = module:Clone()
	copy.Name = "_Fresh" .. module.Name
	copy.Parent = module.Parent
	local ok, result = pcall(require, copy :: ModuleScript)
	copy:Destroy()
	assert(ok, result)
	return result
end

local Worlds = require(Config.Worlds)
local world = fresh(Config.Worlds[Worlds.get(WORLD).folder])
local folder = workspace.Worlds[world.folder]

local function pick(list: any): any
	local out = {}
	for id, def in list do
		if type(def) == "table" and def.world == WORLD then
			local p = plain(def)
			p.icon, p.portrait, p.desc, p.blurb = nil, nil, nil, nil
			out[tostring(def.id or id)] = p
		end
	end
	return out
end

local Weapons = fresh(Config.Weapons)
local Tools = fresh(Config.Tools)
local Armor = fresh(Config.Armor)
local Gates = fresh(Config.Gates)
local Quests = fresh(Config.Quests)
local Gathering = fresh(Config.Gathering)
local Leveling = fresh(Config.Leveling)
local Balance = fresh(Config.Balance)

local cfg = plain(world)
for _, group in { cfg.enemies, cfg.bosses } do
	for _, e in group do
		e.portrait, e.adminPortrait = nil, nil
	end
end
cfg.profile = nil

local data: any = {
	world = WORLD,
	config = cfg,
	weapons = pick(Weapons.Defs),
	tools = pick(Tools.Defs),
	armor = pick(Armor.Defs),
	gathering = pick(Gathering.Nodes),
	-- since 2026-10-24 max HP and a level's EXP both grow x GROWTH a level (x10 every 25 levels)
	leveling = { start = Leveling.START, first = Leveling.FIRST, growth = Leveling.GROWTH, baseHealth = Leveling.BASE_HEALTH, scale = {} },
	-- no base sprint since 2026-10-19 (the Sprint upgrade unlocks it; upgrades are outside the run)
	balance = { sprint = 1, leash = Balance.Melee.leashRange, gatherHealAfter = Gathering.healAfter },
	walkSpeed = game.StarterPlayer.CharacterWalkSpeed,
	respawnTime = game.Players.RespawnTime,
	map = { markers = {}, nodes = {}, places = {}, healZones = {} },
}
-- the world scale's steps (Leveling.scaleAt): { level, multiplier } from each gate's level on
table.insert(data.leveling.scale, { Leveling.START, Leveling.SCALE[1] })
for _, g in Gates.list do
	table.insert(data.leveling.scale, { g.level, Leveling.SCALE[g.world] })
end
for _, g in Gates.list do
	if g.world == WORLD + 1 then
		data.gate = plain(g)
		data.map.places.gate = pos(workspace.Shared.Gates:FindFirstChild(g.model))
	end
end
for id, line in Quests.lines do
	if line.world == WORLD then
		local q = plain(line)
		for _, step in q.steps or {} do
			step.offer, step.reminder, step.complete, step.track, step.objective = nil, nil, nil, nil, nil
		end
		q.npc, q.finished, q.returnNote, q.returnTrack = nil, nil, nil, nil
		data.quest = q
		for _, m in folder:GetDescendants() do
			if m:GetAttribute("QuestLine") == id then
				data.map.places.questGiver = pos(m)
			end
		end
	end
end
for _, kind in { "EnemySpawns", "BossSpawns" } do
	for _, m in folder.Spawns[kind]:GetChildren() do
		table.insert(data.map.markers, {
			archetype = m:GetAttribute("Archetype") or m:GetAttribute("BossId"),
			boss = kind == "BossSpawns",
			wander = m:GetAttribute("WanderRadius"),
			respawn = m:GetAttribute("RespawnSeconds"), -- a marker override, if any
			pos = pos(m),
		})
	end
end
for _, n in (folder:FindFirstChild("Gathering") or Instance.new("Folder")):GetChildren() do
	table.insert(data.map.nodes, { node = n:GetAttribute("Node"), pos = pos(n) })
end
data.map.places.spawn = pos(folder.Spawns:FindFirstChild("PlayerSpawn"))
data.map.healZones = {}
for _, zone in game:GetService("CollectionService"):GetTagged("HealZone") do
	if zone:IsDescendantOf(folder) then
		table.insert(data.map.healZones, { pos = pos(zone), cooldown = zone:GetAttribute("Cooldown") or 30 })
	end
end
local merchants = folder.Structures:FindFirstChild("Merchants")
if merchants then
	for _, stall in merchants:GetChildren() do
		data.map.places[stall.Name] = pos(stall:FindFirstChild("ShopRing") or stall)
	end
end
return HttpService:JSONEncode(data)
