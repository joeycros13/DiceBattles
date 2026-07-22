--!strict
-- CombatService: per-player AUTHORITATIVE combat driver (ARCHITECTURE 4/6,
-- R-C1..R-C23). It owns no combat math itself; the deterministic state machine
-- lives in Shared/Logic/CombatEngine (pure, injected RNG). This service:
--   * validates every client intent (ownership, phase, chapter unlock),
--   * builds the per-run player stats from the profile (PlayerStats),
--   * drives the engine and replicates results via CombatStateUpdated,
--   * offers the pick-3 trait draft (TraitOffer) at the dice cap,
--   * persists durable results on a win (progress, global XP, currency rewards)
--     and returns the player to the menu on win/death via CombatEnded (R-C5/C20).
-- Combat state is transient and never persisted (ARCHITECTURE 7).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Logic = Shared:WaitForChild("Logic")
local Balance = require(Config:WaitForChild("Balance"))
local Chapters = require(Config:WaitForChild("Chapters"))
local CombatEngine = require(Logic:WaitForChild("CombatEngine"))
local PlayerStats = require(Logic:WaitForChild("PlayerStats"))

local COIN_CURRENCY = "coins"
local KEY_CURRENCY = "keys"

local CombatService = {}

local deps: any = nil
local DataService: any = nil
local CurrencyService: any = nil
local GlobalLevelService: any = nil

-- One live battle per player (transient).
local battles: { [Player]: CombatEngine.Battle } = {}

local combatStateUpdated: RemoteEvent? = nil
local combatEnded: RemoteEvent? = nil
local traitOffer: RemoteEvent? = nil
local toastRemote: RemoteEvent? = nil

-- ==================== helpers ====================

local function toast(player: Player, message: string)
	if toastRemote then
		toastRemote:FireClient(player, message)
	end
end

-- Replicate the current combat state to the owning client, plus the trait offer
-- when the engine is waiting on a TraitPick (R-C23).
local function sync(player: Player)
	local battle = battles[player]
	if not battle then
		return
	end
	if combatStateUpdated then
		combatStateUpdated:FireClient(player, battle.state)
	end
	if battle.state.phase == "TraitPick" and battle.ctx.traitOffer and traitOffer then
		traitOffer:FireClient(player, battle.ctx.traitOffer)
	end
end

-- Grant durable chapter-completion rewards and advance progression (R-C5, R-Y4).
-- Global XP (and its cascading level-ups + grants) is owned by GlobalLevelService;
-- here we record progress + leaderboard stat, then hand XP to that service and
-- bank the currency rewards.
local function grantChapterRewards(player: Player, chapterId: number): { [string]: number }
	local coins = Balance.Rewards.chapterBaseCoins + (chapterId - 1) * Balance.Rewards.chapterCoinsPerChapter
	local keys = Balance.Rewards.chapterKeys
	local totalChapters = Chapters.count()

	-- Detect a first-time clear so we can add the one-time milestone XP bonus.
	local firstClear = false
	DataService.update(player, function(profile)
		firstClear = chapterId > profile.progress.chaptersCompleted
		profile.progress.chaptersCompleted = math.max(profile.progress.chaptersCompleted, chapterId)
		profile.progress.currentChapter = math.clamp(chapterId + 1, 1, totalChapters)
		profile.stats = profile.stats or {}
		profile.stats.highestChapter = math.max(profile.stats.highestChapter or 0, chapterId)
	end)

	-- Global XP: base completion award plus a first-clear milestone bonus (R-C22).
	local globalXp = Balance.Global.xpPerChapterComplete
	if firstClear then
		globalXp += Balance.Global.xpPerChapterMilestone
	end
	GlobalLevelService.addXp(player, globalXp)

	CurrencyService.add(player, COIN_CURRENCY, coins)
	CurrencyService.add(player, KEY_CURRENCY, keys)

	return { coins = coins, keys = keys, globalXp = globalXp }
end

-- Terminal battle handling: replicate the final state, fire CombatEnded (which
-- sends the client back to the menu), grant rewards on a win, and drop the state.
local function finishBattle(player: Player)
	local battle = battles[player]
	if not battle then
		return
	end
	local phase = battle.state.phase
	local chapterId = battle.state.chapterId

	sync(player)

	if phase == "Won" then
		local rewards = grantChapterRewards(player, chapterId)
		if combatEnded then
			combatEnded:FireClient(player, {
				won = true,
				chapterId = chapterId,
				rewards = rewards,
			})
		end
		toast(player, ("Chapter %d complete! +%d coins"):format(chapterId, rewards.coins))
	else -- "Lost"
		if combatEnded then
			combatEnded:FireClient(player, {
				won = false,
				chapterId = chapterId,
			})
		end
		toast(player, "You were defeated. Returning to menu.")
	end

	battles[player] = nil
end

-- After any player action, replicate and, if the battle ended, finalize it.
local function afterAction(player: Player)
	local battle = battles[player]
	if not battle then
		return
	end
	local phase = battle.state.phase
	if phase == "Won" or phase == "Lost" then
		finishBattle(player)
	else
		sync(player)
	end
end

-- ==================== public: start + intents ====================

-- Begin the player's current chapter (R-B1, R-C1). Rejects if a profile is not
-- loaded, a battle is already active, or the chapter is not yet unlocked.
function CombatService.StartBattle(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	if battles[player] then
		toast(player, "You are already in battle.")
		return false
	end

	local chapterId = data.progress.currentChapter
	local chapter = Chapters.get(chapterId)
	if not chapter then
		toast(player, "That chapter does not exist.")
		return false
	end
	-- Unlocked only up to the next chapter after the highest completed (R-B2/C5).
	if chapterId > data.progress.chaptersCompleted + 1 then
		toast(player, "That chapter is locked.")
		return false
	end

	local stats = PlayerStats.compute(data)
	local startingDice = PlayerStats.startingDice(data, stats)

	local random = Random.new()
	local battle = CombatEngine.newBattle({
		chapterId = chapterId,
		stats = stats,
		startingDice = startingDice,
		rng = function()
			return random:NextNumber()
		end,
	})
	battles[player] = battle

	sync(player)
	return true
end

-- Flip a die's lock for the turn (R-C10).
function CombatService.ToggleLockDie(player: Player, index: any): boolean
	if type(index) ~= "number" then
		return false
	end
	local battle = battles[player]
	if not battle then
		return false
	end
	if CombatEngine.toggleLock(battle, index) then
		sync(player)
		return true
	end
	return false
end

-- Reroll unlocked dice, consuming one reroll (R-C11).
function CombatService.Reroll(player: Player): boolean
	local battle = battles[player]
	if not battle then
		return false
	end
	if CombatEngine.reroll(battle) then
		sync(player)
		return true
	end
	return false
end

-- Attack the selected enemy, resolving the full turn (R-C3, R-C6).
function CombatService.AttackEnemy(player: Player, targetIndex: any): boolean
	if type(targetIndex) ~= "number" then
		return false
	end
	local battle = battles[player]
	if not battle then
		return false
	end
	local result = CombatEngine.attack(battle, targetIndex)
	if not result then
		return false
	end
	afterAction(player)
	return true
end

-- Pick one offered trait for the current battle (R-C23).
function CombatService.ChooseTrait(player: Player, traitId: any): boolean
	if type(traitId) ~= "string" then
		return false
	end
	local battle = battles[player]
	if not battle then
		return false
	end
	if CombatEngine.chooseTrait(battle, traitId) then
		afterAction(player)
		return true
	end
	return false
end

-- Re-send current state (safe client resync; performs no mutation).
function CombatService.RollDice(player: Player)
	sync(player)
end

-- True if the player currently has an active battle.
function CombatService.isInBattle(player: Player): boolean
	return battles[player] ~= nil
end

function CombatService.init(injected: any)
	deps = injected
	DataService = deps.Services.DataService
	CurrencyService = deps.Services.CurrencyService
	GlobalLevelService = deps.Services.GlobalLevelService
	combatStateUpdated = deps.Remotes.getEvent("CombatStateUpdated")
	combatEnded = deps.Remotes.getEvent("CombatEnded")
	traitOffer = deps.Remotes.getEvent("TraitOffer")
	toastRemote = deps.Remotes.getEvent("Toast")
end

function CombatService.start()
	deps.Remotes.getEvent("StartBattle").OnServerEvent:Connect(function(player: Player)
		CombatService.StartBattle(player)
	end)
	deps.Remotes.getEvent("RollDice").OnServerEvent:Connect(function(player: Player)
		CombatService.RollDice(player)
	end)
	deps.Remotes.getEvent("ToggleLockDie").OnServerEvent:Connect(function(player: Player, index: any)
		CombatService.ToggleLockDie(player, index)
	end)
	deps.Remotes.getEvent("Reroll").OnServerEvent:Connect(function(player: Player)
		CombatService.Reroll(player)
	end)
	deps.Remotes.getEvent("AttackEnemy").OnServerEvent:Connect(function(player: Player, targetIndex: any)
		CombatService.AttackEnemy(player, targetIndex)
	end)
	deps.Remotes.getEvent("ChooseTrait").OnServerEvent:Connect(function(player: Player, traitId: any)
		CombatService.ChooseTrait(player, traitId)
	end)

	-- Drop transient combat state when a player leaves (never persisted).
	Players.PlayerRemoving:Connect(function(player: Player)
		battles[player] = nil
	end)
end

return CombatService
