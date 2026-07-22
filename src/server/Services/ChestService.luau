--!strict
-- ChestService: the single chest's loot flow (R-Y2, R-Y3, ARCHITECTURE.md 9).
-- One key buys one weighted LootTable roll; "spin all" spends every key the
-- player owns in one call. All RNG and validation are server-authoritative; the
-- client only sends intent via the OpenChest remote and re-renders on the
-- replicated ProfileUpdated (balances) + ChestOpened (this open's results).
--
-- Rewards are granted through the sanctioned mutators only:
--   * currency drops via CurrencyService.add,
--   * gear drops via InventoryService.GrantGear (rarity rolled here, weighted by
--     Rarities so rarer gear is less likely).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Logic = Shared:WaitForChild("Logic")
local Balance = require(Config:WaitForChild("Balance"))
local Gear = require(Config:WaitForChild("Gear"))
local Rarities = require(Config:WaitForChild("Rarities"))
local ChestLoot = require(Config:WaitForChild("ChestLoot"))
local LootTable = require(Logic:WaitForChild("LootTable"))

local KEY_CURRENCY = "keys"

-- A single resolved reward, sent to the client for display.
export type LootResult = {
	kind: string, -- "currency" | "gear"
	currency: string?, -- for kind == "currency"
	amount: number?, -- for kind == "currency"
	gearId: string?, -- for kind == "gear"
	rarity: string?, -- for kind == "gear"
}

local ChestService = {}

local deps: any = nil
local DataService: any = nil
local CurrencyService: any = nil
local InventoryService: any = nil
local openChestRemote: RemoteEvent? = nil
local chestOpenedRemote: RemoteEvent? = nil
local toastRemote: RemoteEvent? = nil

-- Server-authoritative RNG for all loot rolls (matches GlobalLevelService).
local rng = Random.new()
local function rngFloat(): number
	return rng:NextNumber()
end

-- Optional player feedback; harmless no-op until a Toast UI consumes it.
local function toast(player: Player, message: string)
	if toastRemote then
		toastRemote:FireClient(player, message)
	end
end

-- Cached weighted rarity pool for gear drops (built once from Rarities).
local rarityPool: { { id: string, weight: number } } = {}
for _, id in Rarities.Order do
	local def = Rarities.get(id)
	if def and def.weight > 0 then
		table.insert(rarityPool, { id = id, weight = def.weight })
	end
end

-- Cached gear id list for uniform piece selection (rarity is rolled separately).
local gearIds: { string } = {}
for id in Gear.Defs do
	table.insert(gearIds, id)
end

-- Roll a rarity id weighted by Rarities weight (rarer = less likely).
local function rollRarity(): string
	local picked = LootTable.roll(rarityPool, rngFloat)
	return (picked and picked.id) or Rarities.Order[1]
end

-- Resolve ONE rolled loot entry into a concrete reward, granting it through the
-- sanctioned mutators. Returns a LootResult describing what was granted, or nil.
local function grantEntry(player: Player, entry: any): LootResult?
	if entry.kind == "currency" then
		local currencyId = entry.currency
		if type(currencyId) ~= "string" then
			return nil
		end
		local amount = LootTable.randomInt(entry.min or 1, entry.max or 1, rngFloat)
		if amount <= 0 then
			return nil
		end
		CurrencyService.add(player, currencyId, amount)
		return { kind = "currency", currency = currencyId, amount = amount }
	elseif entry.kind == "gear" then
		if #gearIds == 0 then
			return nil
		end
		local gearId = gearIds[LootTable.randomInt(1, #gearIds, rngFloat)]
		local rarity = rollRarity()
		InventoryService.GrantGear(player, gearId, rarity)
		return { kind = "gear", gearId = gearId, rarity = rarity }
	end
	return nil
end

-- Open the chest `count` times (R-Y2). Each roll costs Balance.Economy.chestKeyCost
-- keys; `count` is clamped to what the player can afford, so a "spin all" request
-- (count == huge / keys) simply consumes every affordable key. Keys are spent up
-- front, then each roll is resolved and granted. Returns the list of LootResults
-- (nil if nothing could be opened). Server-authoritative: validates affordability.
function ChestService.OpenChest(player: Player, count: any): { LootResult }?
	local data = DataService.get(player)
	if not data then
		return nil
	end

	local requested = tonumber(count) or 1
	requested = math.floor(requested)
	if requested < 1 then
		requested = 1
	end

	local cost = math.max(1, Balance.Economy.chestKeyCost)
	local keys = CurrencyService.get(player, KEY_CURRENCY)
	local affordableRolls = math.floor(keys / cost)
	if affordableRolls < 1 then
		toast(player, "You need a key to open the chest.")
		return nil
	end

	local rolls = math.min(requested, affordableRolls)
	local spend = rolls * cost

	-- Spend keys before rolling so a mid-roll failure can never grant free loot.
	if not CurrencyService.spend(player, KEY_CURRENCY, spend) then
		return nil
	end

	local results: { LootResult } = {}
	for _ = 1, rolls do
		local entry = LootTable.roll(ChestLoot.Entries, rngFloat)
		if entry then
			local granted = grantEntry(player, entry)
			if granted then
				table.insert(results, granted)
			end
		end
	end

	if chestOpenedRemote then
		chestOpenedRemote:FireClient(player, results)
	end
	toast(player, ("Opened %d chest%s."):format(rolls, rolls == 1 and "" or "s"))
	return results
end

function ChestService.init(injected: any)
	deps = injected
	DataService = deps.Services.DataService
	CurrencyService = deps.Services.CurrencyService
	InventoryService = deps.Services.InventoryService
	openChestRemote = deps.Remotes.getEvent("OpenChest")
	chestOpenedRemote = deps.Remotes.getEvent("ChestOpened")
	toastRemote = deps.Remotes.getEvent("Toast")
end

function ChestService.start()
	local open = openChestRemote :: RemoteEvent
	open.OnServerEvent:Connect(function(player: Player, count: any)
		ChestService.OpenChest(player, count)
	end)
end

return ChestService
