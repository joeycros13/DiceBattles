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
	"StartBattle",
	"RollDice",
	"ToggleLockDie",
	"Reroll",
	"AttackEnemy",
	"EquipGear",
	"UnequipGear",
	"LevelSlot",
	"RollTalent",
	"OpenChest",
	"ChooseTrait",
	-- Replication (server -> client)
	"ProfileUpdated",
	"CombatStateUpdated",
	"CombatEnded",
	"TraitOffer",
	"Toast",
}

-- RemoteFunctions (request/response). None required yet; reserved for future use.
local FUNCTION_NAMES: { string } = {}

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
		container = ReplicatedStorage:WaitForChild(CONTAINER_NAME) :: Folder
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
