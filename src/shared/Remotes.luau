--!strict
-- Remotes: central registry of RemoteEvent/RemoteFunction names so client and
-- server never mistype a networking string. The server creates the instances
-- via Remotes.init(); both sides fetch by name via getEvent/getFunction.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local CONTAINER_NAME = "Remotes"
local WAIT_TIMEOUT = 10

-- Request (client -> server) and Replication (server -> client) events.
local EVENT_NAMES: { string } = {
	-- Request (client -> server)
	"EquipWeapon",
	"HolsterWeapon",
	"WeaponSwing",
	"WeaponHit",
	"QuestAction", -- ("accept" | "turnIn", lineId): any questline (QuestService)
	"ShopBuy", -- { kind = "Bundle" | "Pass" | "Boost" | "Starter", id = string? }: the Robux shop (ShopService)
	"EquipTitle", -- (titleId: string): wear an earned Index title, "" to take it off (IndexService)
	"GateBuy", -- { id = string }: buy a world gate (GateService, Config/Gates)
	"EquipArmor", -- (id: string?): wear an owned armour set, nil takes it off (ArmorService)
	"SecretCrystalHit", -- (order: number): a swing reached World 3's secret crystal #order (SecretService)
	"GatherHit", -- (nodeIds: { string }): a tool swing reached these gathering nodes (GatherService)
	"HoldTool", -- (kind: string?): take out the best tool of that kind, or put it away (MeleeService, Config/Tools)
	"FishAction", -- { action = "cast", at = Vector3 } | { action = "hook" | "reel" } | { action = "ring", n = number, ok = boolean }: fishing (FishingService)
	"SetSetting", -- (id: string, value: number | boolean): change one of the player's settings (SettingsService, Config/Settings)

	-- Replication (server -> client)
	"IndexDiscovered", -- { kind = "Enemy" | "Weapon", id = string }: show the NEW popup
	"CoinsDropped", -- { body = Instance?, position = Vector3, amount = number, pieces = number }: the coin spill
	"ExpDropped", -- same shape: the blue EXP stars
	"MaterialsDropped", -- { body = Instance?, position = Vector3, items = { { id, amount } }, afterTalk = boolean? }: crafting materials (MaterialService)
	"TeleportFade", -- ("out" | "in", seconds): fade the screen to black and back around a teleport (PortalService)
	"GatherState", -- { id = string, hp = number, max = number, broken = boolean, hit = boolean? }: one of this player's gathering nodes changed (GatherService)
	"CoreInfused", -- { core = string, awakened = boolean, infuser = Instance }: play the infusion reveal (InfuseService)
	"FishState", -- { state = "Cast" | "Approach" | "Bite" | "Surface" | "Ring" | "Caught" | "Escaped" | "Reeled", ... }: this player's fishing (FishingService)
	"LeaderboardReward", -- { text, rank }: a leaderboard reward was granted (LeaderboardService), shown in chat
	"HealZone", -- { kind = "healed", amount } | { kind = "cooldown", seconds }: the healing fountain (HealZoneService)
	"PlayerHurt", -- { character = Model, from = Vector3 }: an enemy's hit landed on a player (MeleeService): every client flashes and flinches that body, the hit player stumbles back (HurtController)
}

-- RemoteFunctions (request/response).
local FUNCTION_NAMES: { string } = {
	"AdminAction", -- { action = string, ... } -> (ok: boolean, message: string): the admin panel (AdminService)
	"CraftArmor", -- (id: string) -> (ok: boolean, reason: string?): craft a set at the Crafting stall (CraftingService)
	"BuyWeapon", -- (id: string) -> (ok: boolean, reason: string?): buy a weapon at the Weapons stall (MerchantService)
	"BuyTool", -- (id: string) -> (ok: boolean, reason: string?): buy a gathering tool at the Weapons stall's Tools tab (StallService)
	"GetLeaderboard", -- (stat: string, period: string) -> { rows, you, resetsAt }: a leaderboard's top 50 (LeaderboardService)
	"BuyUpgrade", -- (id: string) -> (ok: boolean, reason: string?): buy the next level of an upgrade at the Upgrades stand (UpgradeService)
	"ClaimDaily", -- () -> (ok: boolean, reason or reward words): claim today's daily reward at the Daily Rewards stand (DailyRewardService)
	"RedeemCode", -- (code: string) -> (ok: boolean, words: string): redeem a promo code at the Daily Rewards stand (DailyRewardService)
	"BrewPotion", -- (id: string) -> (ok: boolean, reason: string?): brew a potion at the Crafter's Potions tab (PotionService)
	"DrinkPotion", -- (id: string) -> (ok: boolean, reason: string?): drink a held potion from the Inventory (PotionService)
	"InfuseCore", -- (core: string) -> (ok: boolean, reason: string?): set a core into the blade at an Infuser (InfuseService)
	"SellItems", -- ({ { kind, id, count? } }) -> (ok: boolean, coins: number): sell from the Inventory's Sell Mode (SellService, Config/Sell)
	"TravelToWorld", -- (world: number) -> (ok: boolean, reason: string?): teleport to an unlocked world's spawn (PortalService, the Worlds menu)
}

local container: Folder? = nil

local function getContainer(): Folder
	if container then
		return container
	end

	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(CONTAINER_NAME)
		if existing and existing:IsA("Folder") then
			container = existing
		else
			local folder = Instance.new("Folder")
			folder.Name = CONTAINER_NAME
			folder.Parent = ReplicatedStorage
			container = folder
		end
	else
		local found = ReplicatedStorage:WaitForChild(CONTAINER_NAME, WAIT_TIMEOUT)
		assert(
			found and found:IsA("Folder"),
			("Remotes container %q did not replicate within %d seconds; did the server call Remotes.init()?"):format(
				CONTAINER_NAME,
				WAIT_TIMEOUT
			)
		)
		container = found :: Folder
	end

	return container :: Folder
end

-- Server-only: create every declared RemoteEvent/RemoteFunction instance.
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init() must be called on the server")
	local folder = getContainer()

	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end

	for _, name in FUNCTION_NAMES do
		if not folder:FindFirstChild(name) then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = folder
		end
	end
end

function Remotes.getEvent(name: string): RemoteEvent
	local remote = getContainer():WaitForChild(name, WAIT_TIMEOUT)
	assert(remote and remote:IsA("RemoteEvent"), ("RemoteEvent %q not found"):format(name))
	return remote :: RemoteEvent
end

function Remotes.getFunction(name: string): RemoteFunction
	local remote = getContainer():WaitForChild(name, WAIT_TIMEOUT)
	assert(remote and remote:IsA("RemoteFunction"), ("RemoteFunction %q not found"):format(name))
	return remote :: RemoteFunction
end

return Remotes
