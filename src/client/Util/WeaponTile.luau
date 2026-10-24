--!strict
-- WeaponTile: the one weapon tile every screen shows (user, 2026-10-11: "the
-- tiles for each thing carry across everything so that it can be reused").
-- The hand-built template is ReplicatedStorage/Assets/UI/WeaponTile; the
-- Inventory grid, the Index drop slip and the admin panel all clone it through
-- here, and the hotbar and shop read their rarity skins and 3D views from it,
-- so restyling that one template restyles them all.
--
-- Template pieces: Skin (rarity art), Picture (the weapon's drawn icon), Icon
-- (a ViewportFrame, used when a weapon has no drawn icon), ItemName, Stat/Value
-- ("7.5 DPS"), Rim (UIStroke), EquippedBadge, SellMark. Attributes:
-- Skin_<Rarity>, DpsFormat ("%s DPS"), UnknownImage (the question mark shown for a weapon
-- or material not found yet, user 2026-10-12; without it the old dark silhouette
-- in SilhouetteColor), UnknownTileColor (the dimmed tile), and the Rim /
-- EquippedRim / SellRim colours and thicknesses the Inventory uses.
--
--   WeaponTile.new(def, opts)        a filled clone
--   WeaponTile.fill(tile, def, opts) refill one (opts below)
--   WeaponTile.skin(rarity)          the rarity's skin image
--   WeaponTile.attribute(name)       any template attribute
--   WeaponTile.showModel(viewport, id) a weapon framed in a 3D view
--   WeaponTile.dps(def, base?, who?) / dpsText(def, base?, who?)  a weapon's damage per second as the
--                                    player swings it (Config/Bonuses.dps: the Worldheart tier,
--                                    the Attack Speed upgrade, Strength, the Attack upgrade...;
--                                    2026-10-23, the user: every screen but the Index shows
--                                    your real numbers); base = true for the Index's plain
--                                    numbers (the Worldheart tier only). The pill shows it and
--                                    the Inventory ranks weapons by it (2026-10-22, the user:
--                                    damage alone made Equip Best pick slow secret weapons)
-- opts: known (false = a question mark on a dimmed tile), name / stat (false
-- hides the tile's own name / damage pill where the screen shows them itself),
-- statText (the pill's words instead of "N DPS": armour sets and materials use
-- the same tile, 2026-10-12, with "10% Def" / "×15").
-- Any def with an id, name, rarity and icon works: Config/Armor sets and
-- Config/Materials entries are shown on this tile too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- the Worldheart Blade's pill shows the player's own tier (Config/Infuse)
local Infuse = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Infuse"))
local Bonuses = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Bonuses"))

local Format = require(script.Parent:WaitForChild("Format"))

local WeaponTile = {}

export type Options = { known: boolean?, name: boolean?, stat: boolean?, statText: string? }

function WeaponTile.template(): GuiObject?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local tile = ui and ui:FindFirstChild("WeaponTile")
	return if tile and tile:IsA("GuiObject") then tile else nil
end

function WeaponTile.attribute(name: string, fallback: any): any
	local template = WeaponTile.template()
	local value = template and template:GetAttribute(name)
	return if value ~= nil then value else fallback
end

-- A weapon's damage per second as the player swings it (Config/Bonuses), or with `base`
-- only its Worldheart tier (Infuse.adjust), as the Index shows it. `who` is whose bonuses
-- and tier count (default the local player; the profile cards pass the player shown).
function WeaponTile.dps(def: any, base: boolean?, who: Player?): number
	local holder = who or Players.LocalPlayer
	if not base then
		return Bonuses.dps(holder, def)
	end
	local swing = Infuse.adjust(holder, def)
	local damage, cooldown = swing.damage or 0, swing.cooldown or 1
	return if cooldown > 0 then damage / cooldown else damage
end

-- "7.5", "1,571": a weapon's DPS as a number, one decimal below 100, whole with commas above.
function WeaponTile.dpsNumber(def: any, base: boolean?, who: Player?): string
	local dps = WeaponTile.dps(def, base, who)
	return if dps < 100 then (("%.1f"):format(dps):gsub("%.0$", "")) else Format.commas(math.floor(dps + 0.5))
end

-- "7.5 DPS", "1,571 DPS"
function WeaponTile.dpsText(def: any, base: boolean?, who: Player?): string
	return (WeaponTile.attribute("DpsFormat", "%s DPS") :: string):format(WeaponTile.dpsNumber(def, base, who))
end

function WeaponTile.skin(rarity: string?): string
	return WeaponTile.attribute("Skin_" .. (rarity or "Common"), WeaponTile.attribute("Skin_Common", ""))
end

-- ==================== 3D view ====================

-- A weapon standing diagonally in a viewport, framed to fit. Of the two ways to
-- face it (the model's X or Y toward the camera) the one showing more of it wins,
-- so blades show their flat and the scythe its curve -- never edge-on.
local POSES = {
	CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(-0.77, 0.64, 0)), -- X toward the camera
	CFrame.fromMatrix(Vector3.zero, Vector3.new(0.77, -0.64, 0), Vector3.new(0, 0, 1)), -- Y toward the camera
}
-- Points that outline the model's visible parts: each part's six face centres
-- and its corners pulled 3/4 of the way in, so round meshes aren't framed too small.
local OUTLINE = {}
for _, x in { -1, 1 } do
	table.insert(OUTLINE, Vector3.new(x, 0, 0))
	table.insert(OUTLINE, Vector3.new(0, x, 0))
	table.insert(OUTLINE, Vector3.new(0, 0, x))
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(OUTLINE, Vector3.new(x, y, z) * 0.75)
		end
	end
end
local function outline(model: Model): { Vector3 }
	local points = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local h = part.Size / 2
			for _, k in OUTLINE do
				table.insert(points, part.CFrame * (h * k))
			end
		end
	end
	return points
end
local function box(model: Model): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in outline(model) do
		lo, hi = lo:Min(p), hi:Max(p)
	end
	return lo, hi
end

-- The viewport's "Fill" attribute is how much of the frame the weapon fills
-- (default 0.9); "Aspect" stands in for its shape before it is laid out.
function WeaponTile.showModel(viewport: ViewportFrame, id: string)
	viewport:ClearAllChildren()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Weapons")
	-- gathering tools (Config/Tools) keep their models in Assets/Tools
	local tools = assets and assets:FindFirstChild("Tools")
	local template = (folder and folder:FindFirstChild(id)) or (tools and tools:FindFirstChild(id))
	if not (template and template:IsA("Model")) then
		return
	end
	local model = template:Clone()
	local bestArea, best = -1, POSES[1]
	for _, pose in POSES do
		model:PivotTo(pose)
		local lo, hi = box(model)
		local area = (hi.X - lo.X) * (hi.Y - lo.Y)
		if area > bestArea then
			bestArea, best = area, pose
		end
	end
	model:PivotTo(best)
	model.Parent = viewport
	local lo, hi = box(model)
	local center = (lo + hi) / 2
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local fill = viewport:GetAttribute("Fill")
	fill = if type(fill) == "number" and fill > 0 then fill else 0.9
	local size = viewport.AbsoluteSize
	local declared = viewport:GetAttribute("Aspect")
	local aspect = if size.Y > 0 then size.X / size.Y elseif type(declared) == "number" then declared else 1
	local tanV = math.tan(math.rad(15))
	local distance = 0
	for _, p in outline(model) do
		local d = p - center
		distance = math.max(distance, d.Z + math.abs(d.X) / (tanV * aspect * fill), d.Z + math.abs(d.Y) / (tanV * fill))
	end
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 0, distance), center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- ==================== tiles ====================

function WeaponTile.fill(tile: GuiObject, def: any, opts: Options?)
	local o: Options = opts or {}
	local known = o.known ~= false
	local white = Color3.new(1, 1, 1)
	local silhouette = WeaponTile.attribute("SilhouetteColor", Color3.new(0, 0, 0))
	local skin = tile:FindFirstChild("Skin")
	if skin and skin:IsA("ImageLabel") then
		skin.Image = WeaponTile.skin(def.rarity)
		skin.ImageColor3 = if known then white else WeaponTile.attribute("UnknownTileColor", Color3.fromRGB(102, 102, 102))
	end
	-- the drawn icon (def.icon) in Picture; without one, the live model in Icon
	local picture = tile:FindFirstChild("Picture")
	local icon = tile:FindFirstChild("Icon")
	-- not found yet: the question mark (UnknownImage) instead of the item's own picture
	local unknownImage = WeaponTile.attribute("UnknownImage", "")
	local mystery = not known and type(unknownImage) == "string" and unknownImage ~= "" and picture ~= nil and picture:IsA("ImageLabel")
	local drawn = mystery or (def.icon ~= nil and picture ~= nil and picture:IsA("ImageLabel"))
	if picture and picture:IsA("ImageLabel") then
		picture.Visible = drawn
		picture.Image = if mystery then unknownImage else (def.icon or "")
		picture.ImageColor3 = if known or mystery then white else silhouette
	end
	if icon and icon:IsA("ViewportFrame") then
		icon.Visible = not drawn
		icon.ImageColor3 = if known then white else silhouette
		if not drawn then
			WeaponTile.showModel(icon, def.id)
		else
			icon:ClearAllChildren()
		end
	end
	local itemName = tile:FindFirstChild("ItemName")
	if itemName and itemName:IsA("TextLabel") then
		itemName.Visible = o.name ~= false and known
		itemName.Text = def.name
	end
	local stat = tile:FindFirstChild("Stat")
	if stat and stat:IsA("GuiObject") then
		stat.Visible = o.stat ~= false and known
		local value = stat:FindFirstChild("Value", true)
		-- the DPS is worked out only for a pill that shows it (items without a swing never do)
		if value and value:IsA("TextLabel") and (o.statText or stat.Visible) then
			value.Text = o.statText or WeaponTile.dpsText(def)
		end
	end
	for _, name in { "EquippedBadge", "SellMark" } do
		local piece = tile:FindFirstChild(name)
		if piece and piece:IsA("GuiObject") then
			piece.Visible = false
		end
	end
end

function WeaponTile.new(def: any, opts: Options?): GuiObject?
	local template = WeaponTile.template()
	if not template then
		warn("[WeaponTile] no ReplicatedStorage/Assets/UI/WeaponTile")
		return nil
	end
	local tile = template:Clone()
	tile.Name = def.id
	tile.Visible = true
	WeaponTile.fill(tile, def, opts)
	return tile
end

function WeaponTile.init(_injected: any) end
function WeaponTile.start() end

return WeaponTile
