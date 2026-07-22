--!strict
-- InventoryService: authoritative gear inventory operations — equip, unequip, and
-- (later) slot leveling (R-E2..R-E8, ARCHITECTURE.md 4/9). All state lives in the
-- player's profile and is mutated only through DataService, which replicates the
-- change back to the owning client. The client sends intent via the EquipGear /
-- UnequipGear remotes; the server validates ownership and legality here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Logic = Shared:WaitForChild("Logic")
local Gear = require(Config:WaitForChild("Gear"))
local Slots = require(Config:WaitForChild("Slots"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Balance = require(Config:WaitForChild("Balance"))
local MergeLogic = require(Logic:WaitForChild("MergeLogic"))

local MATERIAL_CURRENCY = "materials"

local InventoryService = {}

local deps: any = nil
local DataService: any = nil
local CurrencyService: any = nil
local equipRemote: RemoteEvent? = nil
local unequipRemote: RemoteEvent? = nil
local levelSlotRemote: RemoteEvent? = nil
local mergeGearRemote: RemoteEvent? = nil
local autoMergeGearRemote: RemoteEvent? = nil
local toastRemote: RemoteEvent? = nil

-- Generate a gear key not already present in the profile.
local function newGearUid(profile: any): string
	local uid
	repeat
		uid = "gear_" .. HttpService:GenerateGUID(false)
	until profile.gear[uid] == nil
	return uid
end

-- Optional player feedback; no-op until a Toast UI consumes it.
local function toast(player: Player, message: string)
	if toastRemote then
		toastRemote:FireClient(player, message)
	end
end

-- Equip an owned gear instance into the slot dictated by its definition. Any
-- piece already in that slot is implicitly unequipped (returns to the grid).
-- Returns true on success. Server-authoritative: validates ownership + slot.
function InventoryService.EquipGear(player: Player, gearUid: string): boolean
	if type(gearUid) ~= "string" then
		return false
	end

	local data = DataService.get(player)
	if not data then
		return false
	end

	local instance = data.gear[gearUid]
	if not instance then
		toast(player, "You do not own that gear.")
		return false
	end

	local gearDef = Gear.get(instance.id)
	if not gearDef then
		return false
	end
	local slotDef = Slots.get(gearDef.slot)
	if not slotDef then
		return false
	end
	local slotId = slotDef.id

	if data.equipped[slotId] == gearUid then
		return true -- already equipped in its slot; nothing to do
	end

	DataService.update(player, function(profile)
		profile.equipped[slotId] = gearUid
	end)
	return true
end

-- Clear whatever is equipped in `slotId` (R-E5). Returns true if the slot is a
-- valid slot id (even if it was already empty).
function InventoryService.UnequipGear(player: Player, slotId: string): boolean
	if type(slotId) ~= "string" or not Slots.get(slotId) then
		return false
	end

	local data = DataService.get(player)
	if not data then
		return false
	end

	if data.equipped[slotId] == nil then
		return true -- already empty
	end

	DataService.update(player, function(profile)
		profile.equipped[slotId] = nil
	end)
	return true
end

-- Material cost to raise a slot from its current level to the next (R-E8).
-- baseCost + (level-1) * costPerLevel, so higher levels cost more.
function InventoryService.slotUpgradeCost(currentLevel: number): number
	local level = math.max(1, currentLevel)
	return Balance.SlotLevels.baseCost + (level - 1) * Balance.SlotLevels.costPerLevel
end

-- Raise a slot's level by one by spending slot materials, up to
-- Balance.SlotLevels.maxLevel (R-E8, ARCHITECTURE.md 9). Spending goes through
-- CurrencyService (the sole balance mutator); the level is written via
-- DataService.update. Returns true only when materials were actually spent and
-- the level rose, so the client can gate feedback on the result.
function InventoryService.LevelSlot(player: Player, slotId: string): boolean
	if type(slotId) ~= "string" or not Slots.get(slotId) then
		return false
	end

	local data = DataService.get(player)
	if not data then
		return false
	end

	local current = data.slotLevels[slotId] or 1
	if current >= Balance.SlotLevels.maxLevel then
		toast(player, "That slot is already at max level.")
		return false
	end

	local cost = InventoryService.slotUpgradeCost(current)
	if not CurrencyService.canAfford(player, MATERIAL_CURRENCY, cost) then
		toast(player, ("Not enough materials (need %d)."):format(cost))
		return false
	end

	if not CurrencyService.spend(player, MATERIAL_CURRENCY, cost) then
		return false
	end

	DataService.update(player, function(profile)
		local level = profile.slotLevels[slotId] or 1
		profile.slotLevels[slotId] = math.min(level + 1, Balance.SlotLevels.maxLevel)
	end)

	local slotDef = Slots.get(slotId)
	toast(player, ("%s upgraded to Lv %d."):format(slotDef and slotDef.name or slotId, current + 1))
	return true
end

-- Grant one gear instance to a player's inventory (unequipped). Used by loot
-- sources such as ChestService (ARCHITECTURE.md 9). `rarity` is optional and
-- defaults to the gear def's canonical rarity when omitted/invalid. Returns the
-- new gear uid on success, or nil if the gear id is unknown / profile unloaded.
function InventoryService.GrantGear(player: Player, gearId: string, rarity: string?): string?
	local gearDef = Gear.get(gearId)
	if not gearDef then
		return nil
	end

	local data = DataService.get(player)
	if not data then
		return nil
	end

	local resolvedRarity = gearDef.rarity
	if type(rarity) == "string" and Rarities.get(rarity) then
		resolvedRarity = rarity
	end

	local newUid: string? = nil
	DataService.update(player, function(profile)
		newUid = newGearUid(profile)
		profile.gear[newUid] = { id = gearId, rarity = resolvedRarity }
	end)
	return newUid
end

-- Merge three owned gear of the same type + rarity into one gear a rarity higher
-- (R-E9). Validated by the shared MergeLogic so client and server agree. Consumed
-- pieces are removed from the inventory (and unequipped if any was equipped); the
-- upgraded gear is added unequipped. Returns true on success.
function InventoryService.MergeGear(player: Player, uids: any): boolean
	if type(uids) ~= "table" then
		return false
	end

	local data = DataService.get(player)
	if not data then
		return false
	end

	-- Collect exactly COUNT distinct, owned uids and resolve their instances.
	local seen: { [string]: boolean } = {}
	local orderedUids: { string } = {}
	local instances: { { id: string, rarity: string } } = {}
	for _, uid in uids do
		if type(uid) ~= "string" or seen[uid] then
			toast(player, "Invalid merge selection.")
			return false
		end
		local inst = data.gear[uid]
		if not inst then
			toast(player, "You do not own that gear.")
			return false
		end
		seen[uid] = true
		table.insert(orderedUids, uid)
		table.insert(instances, { id = inst.id, rarity = inst.rarity })
	end

	if #orderedUids ~= MergeLogic.COUNT then
		toast(player, ("Merging requires exactly %d gear."):format(MergeLogic.COUNT))
		return false
	end

	local evaluation = MergeLogic.evaluate(instances)
	if not (evaluation.ok and evaluation.result) then
		toast(player, evaluation.error or "These gear cannot be merged.")
		return false
	end
	local result = evaluation.result

	DataService.update(player, function(profile)
		-- Remove the consumed pieces, unequipping any that were equipped.
		for _, uid in orderedUids do
			profile.gear[uid] = nil
			for slotId, equippedUid in profile.equipped do
				if equippedUid == uid then
					profile.equipped[slotId] = nil
				end
			end
		end
		-- Add the upgraded gear (unequipped).
		local newUid = newGearUid(profile)
		profile.gear[newUid] = { id = result.id, rarity = result.rarity }
	end)

	local gearDef = Gear.get(result.id)
	toast(player, ("Merged into %s %s!"):format(result.rarity, gearDef and gearDef.name or result.id))
	return true
end

-- Auto-merge every set of 3 same-type + same-rarity gear the player owns,
-- cascading upward (R-E9). Consumed pieces are removed (and unequipped); the
-- upgraded gear is granted unequipped. Returns true if anything was merged.
function InventoryService.AutoMergeGear(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end

	local instances: { { uid: string, id: string, rarity: string } } = {}
	for uid, inst in data.gear do
		table.insert(instances, { uid = uid, id = inst.id, rarity = inst.rarity })
	end

	local plan = MergeLogic.planAuto(instances)
	if #plan.removeUids == 0 then
		toast(player, "Nothing to auto-merge.")
		return false
	end

	DataService.update(player, function(profile)
		for _, uid in plan.removeUids do
			profile.gear[uid] = nil
			for slotId, equippedUid in profile.equipped do
				if equippedUid == uid then
					profile.equipped[slotId] = nil
				end
			end
		end
		for _, newInst in plan.addInstances do
			local newUid = newGearUid(profile)
			profile.gear[newUid] = { id = newInst.id, rarity = newInst.rarity }
		end
	end)

	toast(player, ("Auto-merged %d gear into %d."):format(#plan.removeUids, #plan.addInstances))
	return true
end

function InventoryService.init(injected: any)
	deps = injected
	DataService = deps.Services.DataService
	CurrencyService = deps.Services.CurrencyService
	equipRemote = deps.Remotes.getEvent("EquipGear")
	unequipRemote = deps.Remotes.getEvent("UnequipGear")
	levelSlotRemote = deps.Remotes.getEvent("LevelSlot")
	mergeGearRemote = deps.Remotes.getEvent("MergeGear")
	autoMergeGearRemote = deps.Remotes.getEvent("AutoMergeGear")
	toastRemote = deps.Remotes.getEvent("Toast")
end

function InventoryService.start()
	local equip = equipRemote :: RemoteEvent
	local unequip = unequipRemote :: RemoteEvent
	local levelSlot = levelSlotRemote :: RemoteEvent

	equip.OnServerEvent:Connect(function(player: Player, gearUid: any)
		InventoryService.EquipGear(player, gearUid)
	end)
	unequip.OnServerEvent:Connect(function(player: Player, slotId: any)
		InventoryService.UnequipGear(player, slotId)
	end)
	levelSlot.OnServerEvent:Connect(function(player: Player, slotId: any)
		InventoryService.LevelSlot(player, slotId)
	end)

	local merge = mergeGearRemote :: RemoteEvent
	merge.OnServerEvent:Connect(function(player: Player, uids: any)
		InventoryService.MergeGear(player, uids)
	end)

	local autoMerge = autoMergeGearRemote :: RemoteEvent
	autoMerge.OnServerEvent:Connect(function(player: Player)
		InventoryService.AutoMergeGear(player)
	end)
end

return InventoryService
