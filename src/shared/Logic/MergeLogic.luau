--!strict
-- MergeLogic: pure rules for merging gear (R-E9). Three gear of the SAME type
-- (slot) and SAME rarity combine into one gear of the same slot, one rarity
-- higher (Common -> Uncommon, etc.). The result keeps the base id of the first
-- input (so its stat family/icon is preserved) but at the upgraded rarity, since
-- rarity is stored per-instance and drives the stat multiplier.
--
-- Shared so the server (authoritative) and client (preview/enable-state) agree.
-- No Instances/networking here, so it is unit-testable (tests/LogicTests).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Gear = require(Config:WaitForChild("Gear"))
local Rarities = require(Config:WaitForChild("Rarities"))

local MergeLogic = {}

-- Number of matching gear required to perform a merge.
MergeLogic.COUNT = 3

export type GearInstance = { id: string, rarity: string }
export type MergeResult = {
	ok: boolean,
	result: GearInstance?, -- the upgraded gear produced on success
	slot: string?, -- shared slot of the inputs (when resolvable)
	error: string?, -- human-readable reason when ok == false
}

-- The gear a single selection would upgrade into, or nil if it cannot be merged
-- (unknown gear, or already at the highest rarity). Used for the output preview.
function MergeLogic.resultFor(instance: GearInstance?): GearInstance?
	if not instance then
		return nil
	end
	local def = Gear.get(instance.id)
	if not def then
		return nil
	end
	local nextRarity = Rarities.next(instance.rarity)
	if not nextRarity then
		return nil
	end
	return { id = instance.id, rarity = nextRarity }
end

-- Slot id shared by an instance (via its gear def), or nil if unresolvable.
function MergeLogic.slotOf(instance: GearInstance?): string?
	if not instance then
		return nil
	end
	local def = Gear.get(instance.id)
	return def and def.slot or nil
end

-- Validate a set of gear instances for merging and, on success, return the
-- upgraded gear. Enforces: exactly COUNT inputs, all resolvable, all the same
-- slot, all the same rarity, and that rarity has a higher tier.
function MergeLogic.evaluate(instances: { GearInstance }): MergeResult
	if #instances ~= MergeLogic.COUNT then
		return { ok = false, error = ("Merging requires exactly %d gear."):format(MergeLogic.COUNT) }
	end

	local firstDef = Gear.get(instances[1].id)
	if not firstDef then
		return { ok = false, error = "Unknown gear." }
	end
	local slot = firstDef.slot
	local rarity = instances[1].rarity

	for index = 2, #instances do
		local inst = instances[index]
		local def = Gear.get(inst.id)
		if not def then
			return { ok = false, error = "Unknown gear." }
		end
		if def.slot ~= slot then
			return { ok = false, slot = slot, error = "All gear must be the same type." }
		end
		if inst.rarity ~= rarity then
			return { ok = false, slot = slot, error = "All gear must be the same rarity." }
		end
	end

	local nextRarity = Rarities.next(rarity)
	if not nextRarity then
		return { ok = false, slot = slot, error = "This rarity cannot be upgraded further." }
	end

	return {
		ok = true,
		slot = slot,
		result = { id = instances[1].id, rarity = nextRarity },
	}
end

export type OwnedGear = { uid: string, id: string, rarity: string }
export type AutoPlan = {
	removeUids: { string }, -- owned uids consumed by the run
	addInstances: { { id: string, rarity: string } }, -- upgraded gear to grant
}

-- Plan an "auto merge": repeatedly combine every set of 3 same-type + same-rarity
-- gear, cascading upward so newly-created gear can merge again in the same run
-- (e.g. 3 Common + 2 Uncommon -> 1 Uncommon -> combines with the 2 to make a
-- Rare). Pure: returns the net uids to remove and the upgraded gear to add, so
-- the same result can be unit-tested and applied authoritatively. (R-E9)
function MergeLogic.planAuto(instances: { OwnedGear }): AutoPlan
	-- bySlot[slot][rarity] = { { uid = string?, id = string }, ... }
	-- A nil uid marks a token produced during this run (synthetic upgrade).
	local bySlot: { [string]: { [string]: { { uid: string?, id: string } } } } = {}
	for _, inst in instances do
		local def = Gear.get(inst.id)
		if not def then
			continue
		end
		local byRarity = bySlot[def.slot]
		if not byRarity then
			byRarity = {}
			bySlot[def.slot] = byRarity
		end
		local bucket = byRarity[inst.rarity]
		if not bucket then
			bucket = {}
			byRarity[inst.rarity] = bucket
		end
		table.insert(bucket, { uid = inst.uid, id = inst.id })
	end

	local removeUids: { string } = {}
	local addInstances: { { id: string, rarity: string } } = {}

	for _, byRarity in bySlot do
		-- Promote low -> high so produced tokens can cascade into higher buckets.
		for orderIdx = 1, #Rarities.Order - 1 do
			local rarity = Rarities.Order[orderIdx]
			local nextRarity = Rarities.Order[orderIdx + 1]
			local bucket = byRarity[rarity]
			if bucket then
				while #bucket >= MergeLogic.COUNT do
					local first = bucket[1]
					for _ = 1, MergeLogic.COUNT do
						local token = table.remove(bucket, 1)
						if token and token.uid then
							table.insert(removeUids, token.uid)
						end
					end
					local upgraded = byRarity[nextRarity]
					if not upgraded then
						upgraded = {}
						byRarity[nextRarity] = upgraded
					end
					table.insert(upgraded, { uid = nil, id = first.id })
				end
			end
		end

		-- Any synthetic tokens still standing are the gear to grant.
		for _, rarity in Rarities.Order do
			local bucket = byRarity[rarity]
			if bucket then
				for _, token in bucket do
					if not token.uid then
						table.insert(addInstances, { id = token.id, rarity = rarity })
					end
				end
			end
		end
	end

	return { removeUids = removeUids, addInstances = addInstances }
end

return MergeLogic
