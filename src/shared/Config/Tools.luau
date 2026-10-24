--!strict
-- Tools: the gathering tools -- axes, pickaxes, shovels and fishing rods (2026-10-18,
-- the user's design). Each kind has its own hotbar slot next to the weapon's
-- (WeaponHud/Hotbar, Slot2.. in Tools.Kinds order), and each world sells a better tier
-- of the kinds it uses (World 1 a Wooden Axe, World 2 a Stone Axe...). A gathering node
-- (Config/Gathering) names the kind it needs and the lowest tier that can break it, so
-- an activity that comes back in a later world needs that world's tool. A higher tier
-- also hits harder (`power`), so old nodes go faster.
--
-- A slot always holds the player's best tool of its kind (highest tier owned). Taking a
-- tool out puts the weapon away, and taking the weapon out puts the tool away: one
-- thing in hand. Tools never hurt enemies.
--
--   id        the key, saved in the player's "tools" section and the model's name in
--             ReplicatedStorage/Assets/Tools (a Grip PrimaryPart, like a weapon)
--   name      shown in the hotbar and the shop
--   kind      one of Tools.Kinds
--   tier      1 = World 1's tool, 2 = the next world's...
--   world     the world whose shop sells it
--   power     taken off a node's hp per hit
--   rarity    its tile skin (the hotbar slot, the Inventory)
--   price     coins at that world's shop (placeholder)
--   sell      coins for selling it from the Inventory (placeholder, 2026-10-20)
--   icon      its drawn picture (cel-shaded render like the weapons', art/icons/tools; without one
--             the hotbar falls back to the 3D view)
--   recipe    (optional) an upgrade: the previous tier of the same tool (`tool`, taken when it is
--             made) plus that world's `materials` ({ id, count }), on top of the coin `price`
--             (2026-10-20, the gathering plan: tools build up, each tier from the one before)
-- Swinging reuses the weapon animation system (Animation.Clips.Weapons keys holds by id
-- and swings by `swing`), so each tool has the same swing fields a weapon has:
--   handed, cooldown, hitTime, reach, arc, maxTargets, swing

-- World scale (2026-10-23, Config/Leveling): power x2 / x8 for Worlds 1 / 2, like the nodes'
-- health (Config/Gathering), so a node takes the same number of hits.

local Tools = {}

export type Recipe = { tool: string?, materials: { { id: string, count: number } } }

export type ToolDef = {
	id: string,
	name: string,
	kind: string,
	tier: number,
	world: number,
	power: number,
	rarity: string,
	price: number?,
	sell: number?,
	icon: string?,
	recipe: Recipe?,
	handed: number,
	cooldown: number,
	hitTime: number,
	reach: number,
	arc: number,
	maxTargets: number,
	swing: string,
	knockback: number,
}

-- Hotbar order: Slot2 is the first kind, Slot3 the second, and so on (keys 2, 3...).
-- A slot shows only once the player owns a tool of its kind.
Tools.Kinds = { "Axe", "Pickaxe", "Shovel", "Rod" }

Tools.KindNames = {
	Axe = "Axe",
	Pickaxe = "Pickaxe",
	Shovel = "Shovel",
	Rod = "Fishing Rod",
}

Tools.Defs = {
	-- ==================== World 1 (The Sunny Meadows) ====================
	-- Placeholder numbers: an oak (Config/Gathering, 50 hp) falls in 5 chops, about 4 s.
	WoodenAxe = {
		id = "WoodenAxe",
		name = "Wooden Axe",
		kind = "Axe",
		tier = 1,
		world = 1,
		sell = 11,
		power = 20,
		rarity = "Common",
		price = 50,
		icon = "rbxassetid://120793441722751",
		handed = 1,
		cooldown = 0.8,
		hitTime = 0.52,
		reach = 5,
		arc = 70,
		maxTargets = 1,
		knockback = 0,
		-- the Machete's diagonal: a chop down and across into the trunk
		swing = "Diagonal",
	},
	WoodenPickaxe = {
		id = "WoodenPickaxe",
		name = "Wooden Pickaxe",
		kind = "Pickaxe",
		tier = 1,
		world = 1,
		sell = 14,
		power = 20,
		rarity = "Common",
		price = 50,
		icon = "rbxassetid://123876463543492",
		handed = 1,
		cooldown = 0.9,
		hitTime = 0.58,
		reach = 5,
		arc = 70,
		maxTargets = 1,
		knockback = 0,
		-- the World 3 pickaxes' swing: up over the shoulder, then down into the rock
		swing = "Mine",
	},
	-- Fishing (Config/Fishing): held in one hand, cast with both (handed 2 gives the cast
	-- its left hand; the hold leaves it free). Its swing is the cast, and the swing's "Hit"
	-- marker is the moment the line is let go. A rod never breaks nodes (power 0).
	WoodenRod = {
		id = "WoodenRod",
		name = "Wooden Rod",
		kind = "Rod",
		tier = 1,
		world = 1,
		sell = 16,
		power = 0,
		rarity = "Common",
		price = 75,
		icon = "rbxassetid://91808020801922",
		handed = 2,
		cooldown = 1.0,
		hitTime = 0.56,
		reach = 0,
		arc = 0,
		maxTargets = 0,
		knockback = 0,
		swing = "Cast",
	},

	-- ==================== World 2 (The Redwood Forest) ====================
	-- The approved table (2026-10-20, memory tools-per-world): World 2 sells a Stone Axe and a
	-- Stone Rod (no pickaxe: the Wooden Pickaxe lasts until World 3). Models: Blender
	-- w2_tools_build, art/meshes/w2_tools.fbx, built to the wooden ones' sizes ("Redwood +
	-- slate": knapped slate, vine lashing; the axe's amber grip, the all-stone rod's teal reel).
	-- Prices, power, sell and the recipes are placeholders.
	StoneAxe = {
		id = "StoneAxe",
		name = "Stone Axe",
		kind = "Axe",
		tier = 2,
		world = 2,
		sell = 110,
		power = 200,
		rarity = "Uncommon",
		price = 500,
		icon = "rbxassetid://138518954912606",
		-- the upgrade (2026-10-20): the Wooden Axe, World 1's gathered wood and stone, and World
		-- 2's enemy drops (the user: "giving the requirements depth and an actual tree"). Not
		-- Redwood Logs: only a Stone Axe can chop those. Numbers are placeholders.
		recipe = {
			tool = "WoodenAxe",
			materials = {
				{ id = "OakLog", count = 8 },
				{ id = "Stone", count = 8 },
				{ id = "FoxFur", count = 6 },
				{ id = "BoarTusk", count = 2 },
			},
		},
		handed = 1,
		cooldown = 0.8,
		hitTime = 0.52,
		reach = 5,
		arc = 70,
		maxTargets = 1,
		knockback = 0,
		swing = "Diagonal",
	},
	StoneRod = {
		id = "StoneRod",
		name = "Stone Rod",
		kind = "Rod",
		tier = 2,
		world = 2,
		sell = 160,
		power = 0,
		rarity = "Uncommon",
		price = 750,
		icon = "rbxassetid://115528900023286",
		-- the upgrade (2026-10-20, the user: like the axe's): the Wooden Rod, World 1's wood and
		-- stone, and World 2's Fox Fur and Boar Tusk. Not fish: a Stone Rod catches World 2's.
		recipe = {
			tool = "WoodenRod",
			materials = {
				{ id = "OakLog", count = 6 },
				{ id = "Stone", count = 6 },
				{ id = "FoxFur", count = 4 },
				{ id = "BoarTusk", count = 3 },
			},
		},
		handed = 2,
		cooldown = 1.0,
		hitTime = 0.56,
		reach = 0,
		arc = 0,
		maxTargets = 0,
		knockback = 0,
		swing = "Cast",
	},

	-- ==================== World 3 (The Crystal Caverns) ====================
	-- (2026-10-24, the user: "Crystal" fits the caves) World 3 sells a Crystal Pickaxe (from the
	-- Wooden Pickaxe: World 2 had none) and a Crystal Rod (from the Stone Rod); the Stone Axe carries
	-- on. Models: Blender w3_tools_build, art/meshes/w3_tools.fbx, the wooden / stone ones' sizes
	-- (crystal arms in iron, a purple grip; a jointed cyan / pink / purple rod, a pink reel). The
	-- recipes follow World 2's: the tool before, the last world's gathered things, this world's
	-- enemy drops. Prices, power x10 World 2's; all placeholders.
	CrystalPickaxe = {
		id = "CrystalPickaxe",
		name = "Crystal Pickaxe",
		kind = "Pickaxe",
		tier = 3,
		world = 3,
		sell = 1100,
		power = 2000,
		rarity = "Rare",
		price = 5000,
		icon = "rbxassetid://126315296261096",
		recipe = {
			tool = "WoodenPickaxe",
			materials = {
				{ id = "RedwoodLog", count = 8 },
				{ id = "AmberSap", count = 1 },
				{ id = "BatWing", count = 6 },
				{ id = "GolemPebble", count = 2 },
			},
		},
		handed = 1,
		cooldown = 0.9,
		hitTime = 0.58,
		reach = 5,
		arc = 70,
		maxTargets = 1,
		knockback = 0,
		swing = "Mine",
	},
	CrystalRod = {
		id = "CrystalRod",
		name = "Crystal Rod",
		kind = "Rod",
		tier = 3,
		world = 3,
		sell = 1600,
		power = 0,
		rarity = "Rare",
		price = 7500,
		icon = "rbxassetid://103248912912671",
		recipe = {
			tool = "StoneRod",
			materials = {
				{ id = "RedwoodLog", count = 6 },
				{ id = "Perch", count = 4 },
				{ id = "BatWing", count = 4 },
				{ id = "GolemPebble", count = 3 },
			},
		},
		handed = 2,
		cooldown = 1.0,
		hitTime = 0.56,
		reach = 0,
		arc = 0,
		maxTargets = 0,
		knockback = 0,
		swing = "Cast",
	},
} :: { [string]: ToolDef }

-- Studio only (testing): every player owns these from the start. Emptied 2026-10-19 now
-- that tools are sold on the Weapons stall's Tools tab (the admin `tool` action still
-- grants one for a test).
Tools.testStartTools = {} :: { string }

function Tools.get(id: any): ToolDef?
	return if type(id) == "string" then Tools.Defs[id] else nil
end

-- The hotbar slot number for a kind (Slot2 for the first kind), or nil.
function Tools.slotOf(kind: string): number?
	for i, k in Tools.Kinds do
		if k == kind then
			return i + 1
		end
	end
	return nil
end

-- The player's owned tool ids, from their "OwnedTools" attribute (ToolService publishes
-- it). Works on both sides.
function Tools.owned(player: Player): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local text = player:GetAttribute("OwnedTools")
	for id in (if type(text) == "string" then text else ""):gmatch("[^,]+") do
		if Tools.Defs[id] then
			out[id] = true
		end
	end
	return out
end

-- The best tool of a kind in an owned set: the highest tier.
function Tools.bestOf(owned: { [string]: boolean }, kind: string): ToolDef?
	local best: ToolDef? = nil
	for id in owned do
		local def = Tools.Defs[id]
		if def and def.kind == kind and (best == nil or def.tier > best.tier) then
			best = def
		end
	end
	return best
end

return Tools
