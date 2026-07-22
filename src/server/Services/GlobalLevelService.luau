--!strict
-- GlobalLevelService: authoritative persistent account progression (R-C22).
--
-- Owns the single write path for global XP/levels. Other services (CombatService
-- on chapter completion / milestones) call `addXp`; this service:
--   * banks XP and cascades level-ups via the pure Shared/Logic/GlobalLevel curve,
--   * grants each level-up's rewards into the profile:
--       - permanent combat-stat increases (globalStatBonus, reflected in PlayerStats),
--       - free talent rolls (rarity-weighted +1 via TalentLogic, applied immediately),
--       - a permanent starting-dice upgrade every N levels (capped so a run never
--         begins above the 5-dice cap),
--   * keeps the highestPlayerLevel leaderboard stat in sync (R-L2),
--   * replicates via DataService.update and toasts feedback.
-- All mutation goes through DataService (the sole persistence owner).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Logic = Shared:WaitForChild("Logic")
local Balance = require(Config:WaitForChild("Balance"))
local Talents = require(Config:WaitForChild("Talents"))
local GlobalLevel = require(Logic:WaitForChild("GlobalLevel"))
local TalentLogic = require(Logic:WaitForChild("TalentLogic"))

local GlobalLevelService = {}

local deps: any = nil
local DataService: any = nil
local toastRemote: RemoteEvent? = nil

-- Server-authoritative RNG for the free talent rolls granted on level-up.
local rng = Random.new()

-- Optional player feedback; harmless no-op until a Toast UI consumes it.
local function toast(player: Player, message: string)
	if toastRemote then
		toastRemote:FireClient(player, message)
	end
end

-- Apply ONE level-up's rewards to the profile (mutates in place). `newLevel` is
-- the level just reached, used for the "every N levels" starting-dice cadence.
local function applyLevelRewards(profile: any, newLevel: number)
	-- 1) Permanent stat increases (reflected in combat via PlayerStats.compute).
	profile.globalStatBonus = profile.globalStatBonus or {}
	for statName, value in Balance.Global.statGainsPerLevel do
		profile.globalStatBonus[statName] = (profile.globalStatBonus[statName] or 0) + value
	end

	-- 2) Free talent rolls: rarity-weighted +1, applied immediately (R-T2 shape).
	for _ = 1, Balance.Global.talentRollsPerLevel do
		local talentId = TalentLogic.pick(profile.talents, function()
			return rng:NextNumber()
		end)
		if talentId then
			profile.talents[talentId] = (profile.talents[talentId] or 0) + 1
		end
	end

	-- 3) Permanent starting-dice upgrade every N levels, capped so a run never
	--    begins above the hard dice cap (ARCHITECTURE 6, R-C8/C22).
	if newLevel % Balance.Global.startingDiceEveryLevels == 0 then
		local maxUpgrade = Balance.Dice.maxDice - Balance.Dice.startingDice
		profile.startingDiceUpgrade = math.clamp((profile.startingDiceUpgrade or 0) + 1, 0, maxUpgrade)
	end
end

-- Grant `amount` global XP to a player, cascading level-ups and their rewards.
-- Returns the number of levels gained (0 if the profile is not loaded or the
-- amount is non-positive). This is the single sanctioned global-XP write path.
function GlobalLevelService.addXp(player: Player, amount: number): number
	if type(amount) ~= "number" or amount <= 0 then
		return 0
	end

	local levelsGained = 0
	DataService.update(player, function(profile)
		local oldLevel = profile.global.level
		local newLevel, leftoverXp, gained = GlobalLevel.applyXp(oldLevel, profile.global.xp, amount)

		profile.global.level = newLevel
		profile.global.xp = leftoverXp
		levelsGained = gained

		-- Apply rewards for each level crossed, in order (dice cadence needs the
		-- exact resulting level of each step).
		for level = oldLevel + 1, newLevel do
			applyLevelRewards(profile, level)
		end

		if gained > 0 then
			profile.stats = profile.stats or {}
			profile.stats.highestPlayerLevel = math.max(profile.stats.highestPlayerLevel or 1, newLevel)
		end
	end)

	if levelsGained > 0 then
		local data = DataService.get(player)
		local level = data and data.global.level or 0
		toast(player, ("Global Level Up! You are now level %d."):format(level))
	end

	return levelsGained
end

-- Current global level (0 if the profile is not loaded).
function GlobalLevelService.getLevel(player: Player): number
	local data = DataService.get(player)
	return data and data.global.level or 0
end

function GlobalLevelService.init(injected: any)
	deps = injected
	DataService = deps.Services.DataService
	toastRemote = deps.Remotes.getEvent("Toast")
end

function GlobalLevelService.start() end

return GlobalLevelService
