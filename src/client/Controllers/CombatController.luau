--!strict
-- CombatController: the client-side mirror of the server's authoritative combat
-- state (ARCHITECTURE 2/4). It listens to the combat replication remotes
-- (CombatStateUpdated, TraitOffer, CombatEnded), caches the latest snapshot, and
-- notifies UI subscribers so CombatUI re-renders on every server change. It also
-- exposes intent senders (toggle lock, reroll, attack, choose trait) that only
-- fire request remotes -- the client never decides outcomes (R-P5).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))

type CombatState = Types.CombatState

-- Payload replicated by CombatService when a battle ends (win or loss).
export type CombatEndedInfo = {
	won: boolean,
	chapterId: number,
	rewards: { [string]: number }?,
}

local CombatController = {}

local deps: any = nil
local Remotes: any = nil

-- Request remotes (client -> server intents).
local toggleLockRemote: RemoteEvent? = nil
local rerollRemote: RemoteEvent? = nil
local attackRemote: RemoteEvent? = nil
local chooseTraitRemote: RemoteEvent? = nil

-- Latest replicated state + the current pick-3 trait offer (nil when none).
local state: CombatState? = nil
local traitOffer: { string }? = nil

local changedEvent: BindableEvent = Instance.new("BindableEvent")
local endedEvent: BindableEvent = Instance.new("BindableEvent")
local traitOfferEvent: BindableEvent = Instance.new("BindableEvent")

function CombatController.init(injected: any)
	deps = injected
	Remotes = deps.Remotes
	toggleLockRemote = Remotes.getEvent("ToggleLockDie")
	rerollRemote = Remotes.getEvent("Reroll")
	attackRemote = Remotes.getEvent("AttackEnemy")
	chooseTraitRemote = Remotes.getEvent("ChooseTrait")
end

function CombatController.start()
	Remotes.getEvent("CombatStateUpdated").OnClientEvent:Connect(function(newState: CombatState)
		state = newState
		-- Drop a stale offer once the server has left the trait-pick phase.
		if newState.phase ~= "TraitPick" then
			traitOffer = nil
		end
		changedEvent:Fire(newState)
	end)

	Remotes.getEvent("TraitOffer").OnClientEvent:Connect(function(offer: { string })
		traitOffer = offer
		traitOfferEvent:Fire(offer)
	end)

	Remotes.getEvent("CombatEnded").OnClientEvent:Connect(function(info: CombatEndedInfo)
		endedEvent:Fire(info)
		-- Battle is over; clear transient mirrors AFTER notifying subscribers so
		-- the end screen can still read the final numbers if needed.
		state = nil
		traitOffer = nil
	end)
end

-- ==================== reads ====================

function CombatController.get(): CombatState?
	return state
end

function CombatController.getTraitOffer(): { string }?
	return traitOffer
end

function CombatController.isInBattle(): boolean
	return state ~= nil
end

-- ==================== subscriptions ====================

function CombatController.onChanged(callback: (CombatState) -> ()): RBXScriptConnection
	return changedEvent.Event:Connect(callback)
end

function CombatController.onEnded(callback: (CombatEndedInfo) -> ()): RBXScriptConnection
	return endedEvent.Event:Connect(callback)
end

function CombatController.onTraitOffer(callback: ({ string }) -> ()): RBXScriptConnection
	return traitOfferEvent.Event:Connect(callback)
end

-- ==================== intents (request only) ====================

function CombatController.toggleLock(index: number)
	if toggleLockRemote then
		toggleLockRemote:FireServer(index)
	end
end

function CombatController.reroll()
	if rerollRemote then
		rerollRemote:FireServer()
	end
end

function CombatController.attack(targetIndex: number)
	if attackRemote then
		attackRemote:FireServer(targetIndex)
	end
end

function CombatController.chooseTrait(traitId: string)
	if chooseTraitRemote then
		chooseTraitRemote:FireServer(traitId)
	end
end

return CombatController
