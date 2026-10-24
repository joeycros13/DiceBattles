--!strict
-- ArmorService: the armour sets a player owns and the one they wear
-- (Config/Armor, 2026-10-12). A set is one item; crafting it (CraftingService)
-- grants it here.
--
-- Published as player attributes:
--   OwnedArmor     comma-separated ids
--   EquippedArmor  the worn set's id, or "" for none
--   ArmorDefense   0..1 off every enemy hit (MeleeService reads it)
--   ArmorHealth    extra max HP (ExpService.maxHealth adds it)
--   ArmorRegen     extra share of max HP healed a second (UpgradeService's regen tick)
--   ArmorSpeed     extra walk / sprint speed, a share (SprintController)
-- Remotes.EquipArmor(id) wears an owned set; nil (or the worn one's id) takes
-- it off. Crafting a set puts it on straight away.
--
-- Saved as the "armor" section of PlayerDataService: { owned = { ids }, equipped = id? }.
--
-- The worn set shows on the character: ServerStorage/Assets/Armor/<id> is a model of
-- Blender meshes (art/meshes/armor_<set>.fbx), each piece carrying a "Bone" attribute
-- (Torso / LeftArm / RightArm / LeftLeg / RightLeg) and an "Offset" (Vector3, its
-- centre in that body part's frame). Wearing a set clones it into the character as a
-- model named "Armor" and welds every piece to its body part, so it moves with the
-- R6 limbs; it's redone on every spawn once AvatarService has dressed the avatar.
-- A set with no model yet only changes the stats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Armor = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Armor"))

local ArmorService = {}

type State = { owned: { [string]: boolean }, equipped: string? }

local deps: any = nil
local states: { [Player]: State } = {}

local WORN_NAME = "Armor"
-- a piece's Bone attribute -> the R6 body part it's welded to
local BODY_PART = { Torso = "Torso", LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg" }

local function template(id: string?): Model?
	local assets = ServerStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Armor")
	local model = id and folder and folder:FindFirstChild(id)
	return if model and model:IsA("Model") then model else nil
end

-- Put the worn set's model on the character (or take it off).
local function dress(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild(WORN_NAME)
	if old then
		old:Destroy()
	end
	local state = states[player]
	local source = template(state and state.equipped)
	if not source then
		return
	end
	local worn = source:Clone()
	worn.Name = WORN_NAME
	for _, piece in worn:GetDescendants() do
		if piece:IsA("BasePart") then
			local bone = character:FindFirstChild(BODY_PART[piece:GetAttribute("Bone") or ""] or "")
			local offset = piece:GetAttribute("Offset")
			if bone and bone:IsA("BasePart") and typeof(offset) == "Vector3" then
				piece.Anchored = false
				piece.CFrame = bone.CFrame * CFrame.new(offset)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = bone
				weld.Part1 = piece
				weld.Parent = piece
			else
				piece:Destroy()
			end
		end
	end
	-- A model this size can reach a client over several frames; the count lets the
	-- Inventory preview wait until every piece has arrived before copying it.
	local pieces = 0
	for _, piece in worn:GetDescendants() do
		if piece:IsA("BasePart") then
			pieces += 1
		end
	end
	worn:SetAttribute("Pieces", pieces)
	worn.Parent = character
end

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = { owned = {}, equipped = nil }
		states[player] = state
	end
	return state
end

local function publish(player: Player, state: State)
	local owned = {}
	for id in state.owned do
		table.insert(owned, id)
	end
	table.sort(owned)
	local def = Armor.get(state.equipped)
	player:SetAttribute("OwnedArmor", table.concat(owned, ","))
	player:SetAttribute("EquippedArmor", if def then def.id else "")
	player:SetAttribute("ArmorDefense", if def then def.defense else 0)
	player:SetAttribute("ArmorHealth", if def then def.health else 0)
	player:SetAttribute("ArmorRegen", if def then def.regen or 0 else 0)
	player:SetAttribute("ArmorSpeed", if def then def.speed or 0 else 0)
	-- the bonus HP follows at once (a gain is usable straight away)
	deps.Services.ExpService.applyHealth(player)
	local character = player.Character
	if character and character:GetAttribute("AvatarReady") == true then
		dress(player)
	end
end

function ArmorService.owns(player: Player, id: string): boolean
	return stateOf(player).owned[id] == true
end

function ArmorService.equipped(player: Player): string?
	return stateOf(player).equipped
end

-- Add a set to the player's collection. Returns true if it is new to them.
-- The first time ever, the Index marks it found and shows the NEW popup.
function ArmorService.grant(player: Player, id: string): boolean
	local state = stateOf(player)
	if not Armor.get(id) or state.owned[id] then
		return false
	end
	state.owned[id] = true
	publish(player, state)
	local IndexService = deps.Services.IndexService
	if IndexService then
		IndexService.discoverArmor(player, id)
	end
	return true
end

-- Wear an owned set; nil takes the worn one off. Returns true if it changed.
function ArmorService.equip(player: Player, id: any): boolean
	local state = stateOf(player)
	local want: string? = if type(id) == "string" and state.owned[id] and Armor.get(id) then id else nil
	if id ~= nil and want == nil then
		return false -- not theirs
	end
	if want == state.equipped then
		return false
	end
	state.equipped = want
	publish(player, state)
	return true
end

-- Take a set away (the admin panel). Returns true if they had it.
function ArmorService.revoke(player: Player, id: string): boolean
	local state = stateOf(player)
	if not state.owned[id] then
		return false
	end
	state.owned[id] = nil
	if state.equipped == id then
		state.equipped = nil
	end
	publish(player, state)
	return true
end

function ArmorService.init(injected: any)
	deps = injected
	deps.Services.PlayerDataService.register("armor", {
		load = function(player: Player, value: any)
			if type(value) ~= "table" then
				return
			end
			local state = stateOf(player)
			for _, id in (if type(value.owned) == "table" then value.owned else {}) do
				if Armor.get(id) then
					state.owned[id] = true
				end
			end
			if type(value.equipped) == "string" and state.owned[value.equipped] then
				state.equipped = value.equipped
			end
			publish(player, state)
			-- sets owned before the Index tracked armour count as found, quietly
			local IndexService = deps.Services.IndexService
			if IndexService then
				for id in state.owned do
					IndexService.discoverArmor(player, id, true)
				end
			end
		end,
		save = function(player: Player): any
			local state = states[player]
			if not state then
				return nil
			end
			local owned = {}
			for id in state.owned do
				table.insert(owned, id)
			end
			table.sort(owned)
			return { owned = owned, equipped = state.equipped }
		end,
	})
end

function ArmorService.start()
	-- The armour models stay in ServerStorage, so a client first sees their meshes when a
	-- set goes on. A plain copy (no scripts, no tags) goes to ReplicatedStorage/Assets/
	-- ArmorModels for the client's Preloader to load on join (2026-10-20, the user:
	-- nothing may load in front of the player). Bare mesh ids can't be preloaded: a
	-- content string is fetched as an image.
	local assets = ServerStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Armor")
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	if folder and shared and not shared:FindFirstChild("ArmorModels") then
		local copy = folder:Clone()
		copy.Name = "ArmorModels"
		local CollectionService = game:GetService("CollectionService")
		for _, d in copy:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
			else
				for _, tag in CollectionService:GetTags(d) do
					CollectionService:RemoveTag(d, tag)
				end
			end
		end
		copy.Parent = shared
	end

	deps.Remotes.getEvent("EquipArmor").OnServerEvent:Connect(function(player: Player, id: any)
		-- the worn set's own id takes it off, so one button can toggle
		if id ~= nil and id == stateOf(player).equipped then
			id = nil
		end
		ArmorService.equip(player, id)
	end)
	-- every spawn: wait for the avatar to be dressed (it can swap body parts), then
	-- put the worn set on
	local function onCharacter(player: Player, character: Model)
		if character:GetAttribute("AvatarReady") ~= true then
			character:GetAttributeChangedSignal("AvatarReady"):Wait()
		end
		if player.Character == character then
			dress(player)
		end
	end
	local function onPlayer(player: Player)
		publish(player, stateOf(player))
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
	-- PlayerDataService saves on leave first (it connected earlier), then this clears
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(function()
			states[player] = nil
		end)
	end)
end

return ArmorService
