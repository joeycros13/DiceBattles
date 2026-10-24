--!strict
-- ShopService: the Robux shop (Config/Shop) -- coin bundles, gamepasses, timed
-- boosts and the starter pack -- and the multipliers they give.
--
--   * Buying: the client fires Remotes.ShopBuy { kind, id } (kind = "Bundle" |
--     "Pass" | "Boost" | "Starter"). With a real id the server opens Roblox's
--     purchase prompt; with id 0 (not created on the website yet) Studio grants
--     it at once as a test purchase and live servers refuse it.
--   * Developer products are granted in ProcessReceipt, once per PurchaseId
--     (the last RECEIPTS ids are saved), and the player's data is saved before
--     the purchase is confirmed. Gamepasses come from
--     UserOwnsGamePassAsync on join and PromptGamePassPurchaseFinished, and are
--     saved too (so Studio test passes stick).
--   * Multipliers: every owned pass and running boost ADDS its share (2026-10-23,
--     the user: 1.5x + 2x = 2.5x; they multiplied until then, which took maxed luck to
--     16.5x), and Config/Bonuses adds the upgrades' shares on top. Published on the
--     player as "LuckBoost" (weapon drop
--     chances, IndexService), "CoinBoost" (kill coins, CoinService) and
--     "ExpBoost" (kill EXP, ExpService); also "OwnedPasses" (comma list),
--     "VIP" (the chat tag, Client.Controllers.ChatTagController),
--     "Boost_<id>" (seconds left) and "StarterPackBought".
--   * Saved as the "shop" section of PlayerDataService. Boost time only runs
--     while the player is in game.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Shop = require(Config:WaitForChild("Shop"))

local ShopService = {}

local RECEIPTS = 50
local LOAD_WAIT = 15
-- how long a leaving player's state is kept, so the final save can read it
local FORGET_AFTER = 60

type State = {
	passes: { [string]: boolean },
	boosts: { [string]: number }, -- seconds left
	-- when each running boost started (an increasing stamp): the HUD's potion
	-- stack shows the first one bought at the bottom (user, 2026-10-11)
	started: { [string]: number },
	starterPack: boolean,
	receipts: { string },
}

local stamps = 0
local function nextStamp(): number
	stamps += 1
	return stamps
end

-- The same stamps for PotionService's timers, so the BoostHud stacks potions and boosts in
-- the order they started.
function ShopService.nextStamp(): number
	return nextStamp()
end

local deps: any = nil
local PlayerDataService: any = nil
local states: { [Player]: State } = {}
-- productId -> grant function, built from Config/Shop at start
local products: { [number]: (Player) -> () } = {}

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = { passes = {}, boosts = {}, started = {}, starterPack = false, receipts = {} }
		states[player] = s
	end
	return s
end

-- "Boost_<id>" seconds left and "BoostOrder_<id>" (when it started; nil once it
-- has run out), for the shop's timers and the HUD's potion stack
local function publishTimers(player: Player, s: State)
	for id in Shop.Boosts do
		local left = math.ceil(s.boosts[id] or 0)
		player:SetAttribute("Boost_" .. id, left)
		player:SetAttribute("BoostOrder_" .. id, if left > 0 then s.started[id] else nil)
	end
end

local function publish(player: Player, s: State)
	-- each pass and boost adds its share (x2 = +1), Config/Bonuses
	local luck, coins, exp = 1, 1, 1
	local owned = {}
	for id in s.passes do
		local pass = Shop.Passes[id]
		if pass then
			table.insert(owned, id)
			luck += (pass.luck or 1) - 1
			coins += (pass.coins or 1) - 1
			exp += (pass.exp or 1) - 1
		end
	end
	for id, left in s.boosts do
		local boost = Shop.Boosts[id]
		if boost and left > 0 then
			luck += (boost.luck or 1) - 1
			coins += (boost.coins or 1) - 1
			exp += (boost.exp or 1) - 1
		end
	end
	table.sort(owned)
	player:SetAttribute("LuckBoost", luck)
	player:SetAttribute("CoinBoost", coins)
	player:SetAttribute("ExpBoost", exp)
	player:SetAttribute("OwnedPasses", table.concat(owned, ","))
	player:SetAttribute("VIP", s.passes.VIP == true)
	player:SetAttribute("StarterPackBought", s.starterPack)
	publishTimers(player, s)
end

-- ==================== granting ====================

function ShopService.grantPass(player: Player, id: string)
	local s = stateOf(player)
	if Shop.Passes[id] and not s.passes[id] then
		s.passes[id] = true
		publish(player, s)
	end
end

function ShopService.addBoost(player: Player, id: string, seconds: number)
	local s = stateOf(player)
	if Shop.Boosts[id] and seconds > 0 then
		if (s.boosts[id] or 0) <= 0 or not s.started[id] then
			s.started[id] = nextStamp() -- a fresh start; topping up keeps its place
		end
		s.boosts[id] = (s.boosts[id] or 0) + seconds
		publish(player, s)
	end
end

local function grantBundle(player: Player, id: string)
	local bundle = Shop.Bundles[id]
	if bundle then
		deps.Services.CoinService.add(player, Shop.bundleCoins(bundle, PlayerDataService.highestWorld(player)), "shop")
	end
end

local function grantStarter(player: Player)
	local s = stateOf(player)
	local pack = Shop.StarterPack
	s.starterPack = true
	deps.Services.CoinService.add(player, pack.coins, "shop")
	if pack.boost then
		ShopService.addBoost(player, pack.boost, pack.boostSeconds)
	end
	if pack.weapon then
		deps.Services.MeleeService.grant(player, pack.weapon)
	end
	publish(player, s)
end

-- ==================== Roblox purchases ====================

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local deadline = os.clock() + LOAD_WAIT
	while not PlayerDataService.isLoaded(player) and os.clock() < deadline and player.Parent do
		task.wait(0.2)
	end
	if not PlayerDataService.isLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local s = stateOf(player)
	local id = tostring(receipt.PurchaseId)
	if not table.find(s.receipts, id) then
		local grant = products[receipt.ProductId]
		if not grant then
			warn("[ShopService] no product with id " .. tostring(receipt.ProductId))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		grant(player)
		table.insert(s.receipts, id)
		while #s.receipts > RECEIPTS do
			table.remove(s.receipts, 1)
		end
	end
	-- Confirm only once the grant is saved; until then Roblox retries, and the
	-- receipt id above stops a second grant.
	if PlayerDataService.canSave() and not PlayerDataService.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function checkPasses(player: Player)
	for id, pass in Shop.Passes do
		if pass.passId > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.passId)
			end)
			if ok and owns and player.Parent then
				ShopService.grantPass(player, id)
			end
		end
	end
end

-- The Buy buttons. Real ids open Roblox's prompt; id 0 is a Studio test.
local function onBuy(player: Player, request: any)
	if type(request) ~= "table" or type(request.kind) ~= "string" then
		return
	end
	local s = stateOf(player)
	local kind, id = request.kind, request.id
	local productId: number?, passId: number? = nil, nil
	local grant: (() -> ())? = nil
	if kind == "Bundle" and Shop.Bundles[id] then
		productId = Shop.Bundles[id].productId
		grant = function()
			grantBundle(player, id)
		end
	elseif kind == "Boost" and Shop.Boosts[id] then
		productId = Shop.Boosts[id].productId
		grant = function()
			ShopService.addBoost(player, id, Shop.Boosts[id].seconds)
		end
	elseif kind == "Starter" and not s.starterPack then
		productId = Shop.StarterPack.productId
		grant = function()
			grantStarter(player)
		end
	elseif kind == "Pass" and Shop.Passes[id] and not s.passes[id] then
		passId = Shop.Passes[id].passId
		grant = function()
			ShopService.grantPass(player, id)
		end
	else
		return
	end
	if productId and productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
	elseif passId and passId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, passId)
	elseif RunService:IsStudio() and grant then
		grant()
	else
		warn(("[ShopService] %s %s has no Roblox id yet (Config/Shop)"):format(kind, tostring(id)))
	end
end

-- ==================== lifecycle ====================

function ShopService.init(injected: any)
	deps = injected
	PlayerDataService = deps.Services.PlayerDataService
	PlayerDataService.register("shop", {
		load = function(player: Player, value: any)
			local s = stateOf(player)
			if type(value) == "table" then
				for _, id in (if type(value.passes) == "table" then value.passes else {}) do
					if Shop.Passes[id] then
						s.passes[id] = true
					end
				end
				for id, left in (if type(value.boosts) == "table" then value.boosts else {}) do
					if Shop.Boosts[id] and type(left) == "number" and left > 0 then
						s.boosts[id] = left
					end
				end
				-- the saved order the boosts were bought in, oldest first
				for _, id in (if type(value.boostOrder) == "table" then value.boostOrder else {}) do
					if type(id) == "string" and (s.boosts[id] or 0) > 0 and not s.started[id] then
						s.started[id] = nextStamp()
					end
				end
				for id, left in s.boosts do
					if left > 0 and not s.started[id] then
						s.started[id] = nextStamp()
					end
				end
				s.starterPack = value.starterPack == true
				for _, id in (if type(value.receipts) == "table" then value.receipts else {}) do
					table.insert(s.receipts, tostring(id))
				end
			end
			publish(player, s)
		end,
		save = function(player: Player): any
			local s = states[player]
			if not s then
				return nil
			end
			local passes = {}
			for id in s.passes do
				table.insert(passes, id)
			end
			local boosts, order = {}, {}
			for id, left in s.boosts do
				if left > 0 then
					boosts[id] = math.ceil(left)
					table.insert(order, id)
				end
			end
			table.sort(order, function(a, b)
				return (s.started[a] or 0) < (s.started[b] or 0)
			end)
			return { passes = passes, boosts = boosts, boostOrder = order, starterPack = s.starterPack, receipts = table.clone(s.receipts) }
		end,
	})
end

function ShopService.start()
	for id, bundle in Shop.Bundles do
		if bundle.productId > 0 then
			products[bundle.productId] = function(player)
				grantBundle(player, id)
			end
		end
	end
	for id, boost in Shop.Boosts do
		if boost.productId > 0 then
			products[boost.productId] = function(player)
				ShopService.addBoost(player, id, boost.seconds)
			end
		end
	end
	if Shop.StarterPack.productId > 0 then
		products[Shop.StarterPack.productId] = grantStarter
	end
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		for id, pass in Shop.Passes do
			if pass.passId == passId then
				ShopService.grantPass(player, id)
			end
		end
	end)
	deps.Remotes.getEvent("ShopBuy").OnServerEvent:Connect(onBuy)

	local function onPlayer(player: Player)
		publish(player, stateOf(player))
		task.spawn(checkPasses, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		task.delay(FORGET_AFTER, function()
			states[player] = nil
		end)
	end)

	-- boost clocks
	task.spawn(function()
		while true do
			task.wait(1)
			for player, s in states do
				if player.Parent ~= Players then
					continue
				end
				local expired, running = false, false
				for id, left in s.boosts do
					if left > 0 then
						running = true
						s.boosts[id] = math.max(0, left - 1)
						if s.boosts[id] == 0 then
							expired = true
							s.started[id] = nil
						end
					end
				end
				if expired then
					publish(player, s)
				elseif running then
					publishTimers(player, s)
				end
			end
		end
	end)
end

return ShopService
