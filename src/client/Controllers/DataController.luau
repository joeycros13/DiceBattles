--!strict
-- DataController: mirrors the authoritative PlayerData replicated from the server
-- (ARCHITECTURE.md 2). Listens to the `ProfileUpdated` remote, caches the latest
-- profile, and notifies UI subscribers so views re-render on any server change.
-- Read-only on the client: it never mutates state, only requests actions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))

type PlayerData = Types.PlayerData

local DataController = {}

local deps: any = nil
local Remotes: any = nil

local profile: PlayerData? = nil
local changedEvent: BindableEvent = Instance.new("BindableEvent")

function DataController.init(injected: any)
	deps = injected
	Remotes = deps.Remotes
end

function DataController.start()
	local profileUpdated = Remotes.getEvent("ProfileUpdated")
	profileUpdated.OnClientEvent:Connect(function(data: PlayerData)
		profile = data
		changedEvent:Fire(data)
	end)
end

-- Latest replicated profile, or nil if it has not arrived yet.
function DataController.get(): PlayerData?
	return profile
end

-- Block until the first profile arrives (or `timeout` seconds elapse).
function DataController.waitForData(timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 10)
	while profile == nil and os.clock() < deadline do
		task.wait()
	end
	return profile
end

-- Subscribe to profile updates; callback receives the new PlayerData.
function DataController.onChanged(callback: (PlayerData) -> ()): RBXScriptConnection
	return changedEvent.Event:Connect(callback)
end

return DataController
