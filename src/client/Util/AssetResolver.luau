--!strict
-- AssetResolver: maps a logical id (e.g. "slot/Weapon", "rarity/Epic", "rig/idle")
-- to a placeholder visual (ARCHITECTURE.md 10, R-X4). v1 returns colors + a short
-- glyph label; swapping in real assets later means editing only the maps below.
-- UI code renders whatever `resolve` returns and never hard-codes asset ids.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))

local AssetResolver = {}

-- A resolved placeholder visual. `image` is "" until a real asset id is wired in;
-- consumers should show the color + label when `image` is empty.
export type Visual = {
	image: string, -- rbxassetid string, or "" for a pure color/label placeholder
	color: Color3,
	label: string, -- short glyph/text drawn over the placeholder
}

local deps: any = nil

local FALLBACK: Visual = {
	image = "",
	color = Color3.fromRGB(70, 74, 92),
	label = "?",
}

-- Explicit visuals for well-known logical ids. Category prefixes not listed here
-- fall through to the rule-based resolver below.
local MAP: { [string]: Visual } = {
	["tab/Equipment"] = { image = "", color = Color3.fromRGB(96, 140, 255), label = "EQ" },
	["tab/Battle"] = { image = "", color = Color3.fromRGB(228, 108, 92), label = "BT" },
	["tab/Talents"] = { image = "", color = Color3.fromRGB(140, 108, 235), label = "TL" },

	["rig/idle"] = { image = "", color = Color3.fromRGB(120, 124, 140), label = "RIG" },

	["currency/coins"] = { image = "", color = Color3.fromRGB(245, 200, 70), label = "C" },
	["currency/gems"] = { image = "", color = Color3.fromRGB(120, 210, 235), label = "G" },
	["currency/materials"] = { image = "", color = Color3.fromRGB(180, 150, 110), label = "M" },
	["currency/keys"] = { image = "", color = Color3.fromRGB(230, 210, 150), label = "K" },
}

-- Per-slot placeholder tints (keyed by slot id from Config/Slots).
local SLOT_COLORS: { [string]: Color3 } = {
	Helmet = Color3.fromRGB(150, 170, 200),
	Weapon = Color3.fromRGB(210, 120, 110),
	Belt = Color3.fromRGB(170, 140, 110),
	Charm = Color3.fromRGB(200, 160, 210),
	Chestplate = Color3.fromRGB(130, 160, 150),
	Boots = Color3.fromRGB(140, 150, 175),
}

function AssetResolver.init(injected: any)
	deps = injected
end

function AssetResolver.start() end

-- Split "category/name" into its two parts (name may be empty).
local function split(id: string): (string, string)
	local slash = string.find(id, "/", 1, true)
	if not slash then
		return id, ""
	end
	return string.sub(id, 1, slash - 1), string.sub(id, slash + 1)
end

-- Color for a rarity id, from Config/Rarities (falls back to grey).
function AssetResolver.rarityColor(rarityId: string): Color3
	local def = Rarities.get(rarityId)
	return def and def.color or FALLBACK.color
end

-- Resolve a logical id to a placeholder Visual. Always returns a value.
function AssetResolver.resolve(id: string): Visual
	local explicit = MAP[id]
	if explicit then
		return explicit
	end

	local category, name = split(id)
	if category == "rarity" then
		return {
			image = "",
			color = AssetResolver.rarityColor(name),
			label = string.sub(name, 1, 1),
		}
	elseif category == "slot" then
		return {
			image = "",
			color = SLOT_COLORS[name] or FALLBACK.color,
			label = string.sub(name, 1, 2),
		}
	elseif category == "gear" then
		-- Gear placeholders inherit their slot's tint (name is the slot id).
		return {
			image = "",
			color = SLOT_COLORS[name] or FALLBACK.color,
			label = string.sub(name, 1, 2),
		}
	end

	return FALLBACK
end

-- Convenience: apply a resolved visual onto an ImageLabel/ImageButton.
-- Uses the real image if present, otherwise renders the color placeholder.
function AssetResolver.applyImage(target: ImageLabel | ImageButton, id: string)
	local visual = AssetResolver.resolve(id)
	target.Image = visual.image
	if visual.image == "" then
		target.BackgroundTransparency = 0
		target.BackgroundColor3 = visual.color
	else
		target.ImageColor3 = Color3.new(1, 1, 1)
	end
end

return AssetResolver
