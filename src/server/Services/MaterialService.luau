--!strict
-- MaterialService: the crafting materials each player holds (Config/Materials),
-- for the armour sets in Config/Armor (2026-10-12).
--
-- Gathering: trees and rocks broken by GatherService give theirs through `drop`.
--
-- Kills: every kill rolls the enemy's `materials` table (Config/Worlds); each
-- entry rolls on its own and drops min..max of its material, its chance times the
-- killer's "LuckBoost" (capped at 100%, like weapon drops). Quest items come
-- from QuestService (give), once per player. Secret-weapon cores (`core`) drop
-- like materials but at most once per player ever (remembered in `received`, so
-- infusing one later never lets it drop again), luck never changes their chance
-- (the user's rule, 2026-10-19), and they announce through the big Index popup
-- (Remotes.IndexDiscovered { kind = "Core", id }) instead of a toast.
--
-- The counts reach the client as the player's "Materials" attribute,
-- "BullHide=3,ChickenFeather=12" (read it with Materials.counts). Remotes.MaterialsDropped
-- { body?, position, items = { { id, amount } }, afterTalk? } tells the player's
-- client so it can show what dropped.
--
-- Saved as the "materials" section of PlayerDataService:
--   { counts = { [id] = n }, received = { [questItemId] = true } }
-- `received` remembers every quest item ever handed over, so one used up in
-- crafting is never given again, and a save from before quest items existed
-- gets the ones it already earned (QuestService asks through giveOnce).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Enemies = require(Config:WaitForChild("Enemies"))
local Materials = require(Config:WaitForChild("Materials"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Bonuses = require(Config:WaitForChild("Bonuses"))

local MaterialService = {}

type Profile = {
	counts: { [string]: number },
	received: { [string]: boolean },
}

local deps: any = nil
local dropped: RemoteEvent? = nil
local discovered: RemoteEvent? = nil
local profiles: { [Player]: Profile } = {}
local random = Random.new()

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if not profile then
		profile = { counts = {}, received = {} }
		profiles[player] = profile
	end
	return profile
end

local function publish(player: Player, profile: Profile)
	local parts = {}
	for id, n in profile.counts do
		if n > 0 then
			table.insert(parts, id .. "=" .. n)
		end
	end
	table.sort(parts)
	player:SetAttribute("Materials", table.concat(parts, ","))
end

function MaterialService.get(player: Player, id: string): number
	return profileOf(player).counts[id] or 0
end

-- Add (or, with a negative amount, take) a material. Never goes below 0.
function MaterialService.add(player: Player, id: string, amount: number)
	if not Materials.get(id) then
		return
	end
	local profile = profileOf(player)
	local n = math.max(0, (profile.counts[id] or 0) + math.floor(amount))
	profile.counts[id] = if n > 0 then n else nil
	publish(player, profile)
end

-- Whether the player holds every ingredient of a recipe (Config/Armor).
function MaterialService.has(player: Player, recipe: { { id: string, count: number } }): boolean
	for _, item in recipe do
		if MaterialService.get(player, item.id) < item.count then
			return false
		end
	end
	return true
end

-- Use up a recipe's ingredients. Returns false (and takes nothing) if any are short.
function MaterialService.take(player: Player, recipe: { { id: string, count: number } }): boolean
	if not MaterialService.has(player, recipe) then
		return false
	end
	for _, item in recipe do
		MaterialService.add(player, item.id, -item.count)
	end
	return true
end

-- Hand over a quest item, at most once ever. With `position` it is announced
-- like a drop there (after the conversation closes). Returns true if given.
function MaterialService.giveOnce(player: Player, id: string, position: Vector3?): boolean
	local profile = profileOf(player)
	if not Materials.get(id) or profile.received[id] then
		return false
	end
	profile.received[id] = true
	if dropped and position then
		dropped:FireClient(player, { position = position, items = { { id = id, amount = 1 } }, afterTalk = true })
	end
	MaterialService.add(player, id, 1)
	return true
end

local function bodyPosition(body: Instance): Vector3?
	if body:IsA("Model") then
		return body:GetBoundingBox().Position
	elseif body:IsA("BasePart") then
		return body.Position
	end
	return nil
end

local function onKill(enemy: any, killer: Player?)
	if not killer then
		return
	end
	local def = Enemies.get(enemy.archetype)
	local table_ = def and def.materials
	if not table_ then
		return
	end
	local profile = profileOf(killer)
	-- passes, boosts and the Luck upgrade, added (Config/Bonuses); never cores
	local luck = Bonuses.luck(killer)
	local items = {}
	for _, drop in table_ do
		local material = Materials.get(drop.id)
		if not material then
			continue
		end
		if material.core then
			-- one per player, ever: no duplicates
			if not profile.received[drop.id] and random:NextNumber() < drop.chance then
				profile.received[drop.id] = true
				MaterialService.add(killer, drop.id, 1)
				if discovered then
					discovered:FireClient(killer, { kind = "Core", id = drop.id })
				end
			end
		elseif random:NextNumber() < math.min(1, drop.chance * luck) then
			local amount = random:NextInteger(drop.min, math.max(drop.min, drop.max))
			if amount > 0 then
				table.insert(items, { id = drop.id, amount = amount })
			end
		end
	end
	MaterialService.drop(killer, items, bodyPosition(enemy.instance) or enemy.origin, enemy.instance)
end

-- Give the player these materials and show them (the side toast). Kills and gathering
-- nodes (GatherService) both come through here.
function MaterialService.drop(player: Player, items: { { id: string, amount: number } }, position: Vector3, body: Instance?)
	if #items == 0 then
		return
	end
	-- announce first, like the coin spill, so the client can hold its counts
	if dropped then
		dropped:FireClient(player, { body = body, position = position, items = items })
	end
	for _, item in items do
		MaterialService.add(player, item.id, item.amount)
	end
end

function MaterialService.init(injected: any)
	deps = injected
	dropped = deps.Remotes.getEvent("MaterialsDropped")
	discovered = deps.Remotes.getEvent("IndexDiscovered")
	deps.Services.PlayerDataService.register("materials", {
		load = function(player: Player, value: any)
			if type(value) ~= "table" then
				return
			end
			local profile = profileOf(player)
			for id, n in (if type(value.counts) == "table" then value.counts else {}) do
				if Materials.get(id) and type(n) == "number" and n > 0 then
					profile.counts[id] = math.floor(n)
				end
			end
			for id, v in (if type(value.received) == "table" then value.received else {}) do
				if v == true then
					profile.received[id] = true
				end
			end
			publish(player, profile)
		end,
		save = function(player: Player): any
			local profile = profiles[player]
			if not profile then
				return nil
			end
			return { counts = table.clone(profile.counts), received = table.clone(profile.received) }
		end,
	})
end

function MaterialService.start()
	deps.Services.WorldEnemyService.onDefeated(onKill)
	local function onPlayer(player: Player)
		publish(player, profileOf(player))
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	-- PlayerDataService saves on leave first (it connected earlier), then this clears
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(function()
			profiles[player] = nil
		end)
	end)
end

return MaterialService
