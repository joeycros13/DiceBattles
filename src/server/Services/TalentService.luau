--!strict
-- TalentService: authoritative talent rolls (R-T1..R-T4). A roll costs coins and,
-- when affordable, picks ONE talent weighted by rarity (rarer = less likely) and
-- raises its level by 1. All RNG and validation live here (server-authoritative);
-- the client only sends intent via the RollTalent remote and re-renders on the
-- replicated ProfileUpdated. Coin spending goes through CurrencyService (the sole
-- balance mutator); talent levels are written through DataService.update.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Logic = Shared:WaitForChild("Logic")
local Balance = require(Config:WaitForChild("Balance"))
local Talents = require(Config:WaitForChild("Talents"))
local TalentLogic = require(Logic:WaitForChild("TalentLogic"))

local COIN_CURRENCY = "coins"

local TalentService = {}

local deps: any = nil
local DataService: any = nil
local CurrencyService: any = nil
local rollTalentRemote: RemoteEvent? = nil
local toastRemote: RemoteEvent? = nil

-- Optional player feedback; harmless no-op until a Toast UI consumes it.
local function toast(player: Player, message: string)
	if toastRemote then
		toastRemote:FireClient(player, message)
	end
end

-- Roll one talent: spend the coin cost, then rarity-weighted +1 a talent (R-T2).
-- Returns the rolled talent id on success, or nil if the roll was rejected
-- (profile not loaded, nothing rollable, or insufficient coins).
function TalentService.RollTalent(player: Player): string?
	local data = DataService.get(player)
	if not data then
		return nil
	end

	local cost = Balance.Economy.talentRollCost

	-- Nothing to roll if every talent is already at its cap.
	local _, totalWeight = TalentLogic.buildPool(data.talents)
	if totalWeight <= 0 then
		toast(player, "All talents are maxed out.")
		return nil
	end

	-- Affordability is checked before we spend or pick (R-T2).
	if not CurrencyService.canAfford(player, COIN_CURRENCY, cost) then
		toast(player, ("Not enough coins (need %d)."):format(cost))
		return nil
	end

	-- Pick before spending so a nil pick never costs coins.
	local talentId = TalentLogic.pick(data.talents)
	if not talentId then
		return nil
	end

	if not CurrencyService.spend(player, COIN_CURRENCY, cost) then
		-- Balance changed between the check and the spend; abort cleanly.
		return nil
	end

	DataService.update(player, function(profile)
		local level = profile.talents[talentId] or 0
		profile.talents[talentId] = level + 1
	end)

	local def = Talents.get(talentId)
	local newLevel = data.talents[talentId] or 0
	toast(player, ("Rolled %s -> Lv %d"):format(def and def.name or talentId, newLevel))
	return talentId
end

function TalentService.init(injected: any)
	deps = injected
	DataService = deps.Services.DataService
	CurrencyService = deps.Services.CurrencyService
	rollTalentRemote = deps.Remotes.getEvent("RollTalent")
	toastRemote = deps.Remotes.getEvent("Toast")
end

function TalentService.start()
	local roll = rollTalentRemote :: RemoteEvent
	roll.OnServerEvent:Connect(function(player: Player)
		TalentService.RollTalent(player)
	end)
end

return TalentService
