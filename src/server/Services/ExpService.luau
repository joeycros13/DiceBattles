--!strict
-- ExpService: EXP and levels from defeated enemies (the same shape as
-- CoinService).
--
-- A player's progress is one number, their total EXP, published as the
-- "ExpTotal" attribute; "Level" is published beside it for convenience.
-- Config/Leveling turns the total into a level and the bar's x / y. Saved as the
-- "exp" section of PlayerDataService (2026-10-09); the level follows from it.
-- Kill EXP is multiplied by the player's "ExpBoost" attribute (ShopService);
-- quest rewards are not.
--
-- When a player defeats an enemy (WorldEnemyService.onDefeated) they get the
-- enemy's `exp` from Config/Worlds. The killer's client hears
-- Remotes.ExpDropped first, so it can hold the EXP bar while
-- Balance.Exp.piecesMin..piecesMax blue stars fling out and fly to it.
--
-- Max health follows the level (Leveling.maxHealth: 100 at level 1, x10 every 25 levels since
-- 2026-10-24; it was +10 a level). A new character starts full; a level up heals to the new
-- max at once (user, 2026-10-19: early HP is scarce and regen is slow). An admin can override the max for the
-- session (player attribute MaxHealthOverride, AdminService). Worn armour adds
-- its bonus HP on top of the level's (player attribute ArmorHealth, ArmorService;
-- 2026-10-12).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Leveling = require(Config:WaitForChild("Leveling"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Bonuses = require(Config:WaitForChild("Bonuses"))

local ExpService = {}

local deps: any = nil
local dropped: RemoteEvent? = nil
local random = Random.new()

-- Level-ups (gained > 0 levels) for listeners: the leaderboards (2026-10-19). Not
-- fired for the level a save loads with.
local levelListeners: { (Player, number) -> () } = {}

function ExpService.onLevelUp(callback: (Player, number) -> ())
	table.insert(levelListeners, callback)
end

function ExpService.get(player: Player): number
	local value = player:GetAttribute("ExpTotal")
	return if type(value) == "number" then value else 0
end

function ExpService.add(player: Player, amount: number)
	local total = ExpService.get(player) + math.floor(amount)
	player:SetAttribute("ExpTotal", total)
	player:SetAttribute("Level", (Leveling.fromTotal(total)))
end

-- EXP that comes from somewhere other than a kill (a quest reward): the same
-- star spill from `position`, then added; `afterTalk` as in CoinService.spill.
function ExpService.spill(player: Player, amount: number, position: Vector3, afterTalk: boolean?)
	if amount <= 0 then
		return
	end
	if dropped then
		dropped:FireClient(player, {
			position = position,
			amount = amount,
			pieces = random:NextInteger(Balance.Exp.piecesMin, Balance.Exp.piecesMax),
			afterTalk = afterTalk == true,
		})
	end
	ExpService.add(player, amount)
end

-- ==================== max health ====================

-- What the player's max health should be: the admin override if there is one,
-- otherwise their level's plus their armour's bonus.
function ExpService.maxHealth(player: Player): number
	local override = player:GetAttribute("MaxHealthOverride")
	if type(override) == "number" and override > 0 then
		return override
	end
	local armor = player:GetAttribute("ArmorHealth")
	local bonus = if type(armor) == "number" and armor > 0 then armor else 0
	-- the Health upgrade multiplies the lot (Config/Upgrades)
	return math.floor((Leveling.maxHealth((Leveling.fromTotal(ExpService.get(player)))) + bonus) * Bonuses.health(player) + 0.5)
end

-- Bring the character's max health in line. Health rises by any gain (so a
-- level up's HP is usable at once) or fills completely with `fill`; a lower max
-- just caps it.
function ExpService.applyHealth(player: Player, fill: boolean?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local want = ExpService.maxHealth(player)
	local gain = want - humanoid.MaxHealth
	humanoid.MaxHealth = want
	if fill then
		humanoid.Health = want
	elseif gain > 0 then
		humanoid.Health = math.min(want, humanoid.Health + gain)
	elseif humanoid.Health > want then
		-- a lower max (armour taken off) doesn't clamp Health by itself
		humanoid.Health = want
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or player.Character ~= character then
		return
	end
	ExpService.applyHealth(player, true)
	-- dressing (AvatarService) can swap parts; settle it again once that's done
	if not character:GetAttribute("AvatarReady") then
		character:GetAttributeChangedSignal("AvatarReady"):Wait()
	end
	if player.Character == character then
		ExpService.applyHealth(player, humanoid.Health >= humanoid.MaxHealth)
	end
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
	local amount = def and def.exp
	if not amount or amount <= 0 then
		return
	end
	-- passes and boosts (ExpBoost) plus the EXP upgrade, added (Config/Bonuses)
	local boost = Bonuses.exp(killer)
	if boost ~= 1 then
		amount = math.max(1, math.floor(amount * boost + 0.5))
	end
	-- the spill first, so the client knows to hold its bar
	if dropped then
		dropped:FireClient(killer, {
			body = enemy.instance,
			position = bodyPosition(enemy.instance) or enemy.origin,
			amount = amount,
			pieces = random:NextInteger(Balance.Exp.piecesMin, Balance.Exp.piecesMax),
		})
	end
	ExpService.add(killer, amount)
end

function ExpService.init(injected: any)
	deps = injected
	dropped = deps.Remotes.getEvent("ExpDropped")
	deps.Services.PlayerDataService.register("exp", {
		load = function(player: Player, value: any)
			if type(value) == "number" then
				local total = math.max(0, math.floor(value))
				player:SetAttribute("ExpTotal", total)
				player:SetAttribute("Level", (Leveling.fromTotal(total)))
			end
		end,
		save = function(player: Player): any
			return ExpService.get(player)
		end,
	})
end

function ExpService.start()
	deps.Services.WorldEnemyService.onDefeated(onKill)
	local function onPlayer(player: Player)
		if player:GetAttribute("ExpTotal") == nil then
			ExpService.add(player, 0)
		end
		local shownLevel = player:GetAttribute("Level")
		player:GetAttributeChangedSignal("Level"):Connect(function()
			local level = player:GetAttribute("Level")
			-- a level up fills health; anything else (an admin setting it lower) only caps it
			local up = type(level) == "number" and type(shownLevel) == "number" and level > shownLevel
			if up then
				for _, listener in levelListeners do
					task.spawn(listener, player, (level :: number) - (shownLevel :: number))
				end
			end
			shownLevel = level
			ExpService.applyHealth(player, up)
		end)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return ExpService
