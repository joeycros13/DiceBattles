--!strict
-- GatherService: trees and rocks players break for materials (2026-10-18).
--
-- Nodes are models tagged "GatherNode" in each world's Gathering folder, with a `Node`
-- attribute naming a Config/Gathering def. On start each gets a `NodeId` attribute
-- (unique, replicated) that the clients name it by.
--
-- You break a node with a tool (Config/Tools), taken out from its own hotbar slot
-- (MeleeService.holdTool). The client's swing (WeaponController.onSwingLanded) says
-- which nodes it reached (Remotes.GatherHit); this service re-checks each one: a tool
-- the player owns is in hand, it is the node's kind and at least its tier, the swing is
-- not faster than the tool allows, and the node is within the tool's reach of the
-- player. The tool's power comes off the node's hp.
--
-- Every player breaks nodes for themselves. Each has their own hp per node and their
-- own respawn timer, so a node knocked down by one player still stands for everyone
-- else. Damage heals back to full after Gathering.healAfter seconds without a hit. A
-- broken node gives its drops through MaterialService.drop (saved, with the side
-- toast) and comes back after its `respawn` seconds. Remotes.GatherState tells that
-- player's client about every change, so it can show the health bar and hide or
-- bring back the node.
--
-- Node state is per session (not saved): a rejoin starts with every node standing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Gathering = require(Config:WaitForChild("Gathering"))
local Tools = require(Config:WaitForChild("Tools"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Potions = require(Config:WaitForChild("Potions"))

local GatherService = {}

-- Fraction of the tool's cooldown a swing must wait, allowing for network jitter
-- (the same slack MeleeService gives).
local COOLDOWN_TOLERANCE = 0.85

type NodeState = {
	hp: number,
	lastHit: number,
	brokenUntil: number?,
}

local deps: any = nil
local stateRemote: RemoteEvent? = nil
local random = Random.new()

-- NodeId -> the node's model
local nodes: { [string]: Model } = {}
local nextId = 0
-- per player: NodeId -> their state for that node (only nodes they have hit)
local states: { [Player]: { [string]: NodeState } } = {}
local lastSwing: { [Player]: number } = {}

local function register(model: Instance)
	if not (model:IsA("Model") and model:IsDescendantOf(workspace)) then
		return
	end
	if not Gathering.get(model:GetAttribute("Node")) then
		warn(`[GatherService] {model:GetFullName()} has no known Node attribute; it can't be gathered`)
		return
	end
	local id = model:GetAttribute("NodeId")
	if type(id) ~= "string" or nodes[id] ~= nil then
		nextId += 1
		id = "n" .. nextId
		model:SetAttribute("NodeId", id)
	end
	nodes[id :: string] = model
end

local function unregister(model: Instance)
	local id = model:GetAttribute("NodeId")
	if type(id) == "string" and nodes[id] == model then
		nodes[id] = nil
	end
end

local function send(player: Player, id: string, def: Gathering.NodeDef, state: NodeState, hit: boolean)
	if stateRemote then
		stateRemote:FireClient(player, {
			id = id,
			hp = state.hp,
			max = def.hp,
			broken = state.brokenUntil ~= nil,
			hit = hit,
		})
	end
end

-- Roll a node's drops: each entry on its own. The Gathering upgrade (Config/Upgrades) is a
-- chance that an entry's amount comes doubled (2026-10-22, 1% a level; it was a straight
-- +10% materials a level).
local function rollDrops(def: Gathering.NodeDef, player: Player): { { id: string, amount: number } }
	local double = Upgrades.value(player, "Gathering")
	local items = {}
	for _, drop in def.drops do
		if random:NextNumber() < drop.chance then
			local amount = random:NextInteger(drop.min, math.max(drop.min, drop.max))
			if amount > 0 and double > 0 and random:NextNumber() < double then
				amount *= 2
			end
			if amount > 0 then
				table.insert(items, { id = drop.id, amount = amount })
			end
		end
	end
	return items
end

local function breakNode(player: Player, id: string, model: Model, def: Gathering.NodeDef, state: NodeState)
	state.hp = 0
	state.brokenUntil = os.clock() + def.respawn
	send(player, id, def, state, true)
	local cf, size = model:GetBoundingBox()
	deps.Services.MaterialService.drop(player, rollDrops(def, player), cf.Position + Vector3.new(0, size.Y / 2, 0), model)

	local until_ = state.brokenUntil
	task.delay(def.respawn, function()
		local mine = states[player]
		if mine and mine[id] == state and state.brokenUntil == until_ then
			state.brokenUntil = nil
			state.hp = def.hp
			send(player, id, def, state, false)
		end
	end)
end

local function onHit(player: Player, ids: any)
	if type(ids) ~= "table" then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return
	end
	-- an owned tool must be in hand: the character's Tool attribute is set only then
	local tool = Tools.get(character:GetAttribute("Tool"))
	if not (tool and deps.Services.ToolService.owns(player, tool.id)) then
		return
	end
	local now = os.clock()
	if now - (lastSwing[player] or 0) < tool.cooldown * COOLDOWN_TOLERANCE then
		return
	end
	lastSwing[player] = now

	local mine = states[player]
	if not mine then
		mine = {}
		states[player] = mine
	end
	local seen: { [string]: boolean } = {}
	local landed = 0
	for _, id in ids do
		if landed >= tool.maxTargets then
			break
		end
		if type(id) ~= "string" or seen[id] then
			continue
		end
		seen[id] = true
		local model = nodes[id]
		local def = model and Gathering.get(model:GetAttribute("Node"))
		if not (model and def and model.Parent) or def.tool ~= tool.kind or tool.tier < def.tier then
			continue
		end
		-- within the tool's reach of the node's edge?
		local cf, size = model:GetBoundingBox()
		local offset = cf.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		local radius = math.max(size.X, size.Z) / 2
		if flat - radius > tool.reach + Gathering.reachSlack or math.abs(offset.Y) > size.Y / 2 + 10 then
			continue
		end

		local state = mine[id]
		if not state then
			state = { hp = def.hp, lastHit = 0, brokenUntil = nil }
			mine[id] = state
		end
		if state.brokenUntil then
			continue
		end
		if now - state.lastHit > Gathering.healAfter then
			state.hp = def.hp
		end
		state.lastHit = now
		landed += 1
		-- a Gatherer's potion adds its share to the tool's power (Config/Potions)
		state.hp = math.max(0, state.hp - tool.power * Potions.multiplier(player, "Gatherer"))
		if state.hp <= 0 then
			breakNode(player, id, model :: Model, def, state)
		else
			send(player, id, def, state, true)
		end
	end
end

function GatherService.init(injected: any)
	deps = injected
	stateRemote = deps.Remotes.getEvent("GatherState")
end

function GatherService.start()
	for _, model in CollectionService:GetTagged(Gathering.Tag) do
		register(model)
	end
	CollectionService:GetInstanceAddedSignal(Gathering.Tag):Connect(register)
	CollectionService:GetInstanceRemovedSignal(Gathering.Tag):Connect(unregister)
	deps.Remotes.getEvent("GatherHit").OnServerEvent:Connect(onHit)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
		lastSwing[player] = nil
	end)
end

return GatherService
