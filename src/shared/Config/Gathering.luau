--!strict
-- Gathering: the nodes players break for materials -- trees to chop, rocks to mine
-- (2026-10-18, agreed with the user: gathering lives in every world, spread through it in
-- clusters). You break a node with the right tool (Config/Tools: an axe for trees, a
-- pickaxe for rocks), each kind in its own hotbar slot. GatherService runs it.
--
-- A node in the map is a model tagged "GatherNode" whose `Node` attribute names one of
-- the defs below. It sits in its world's `Gathering` folder. Each player breaks nodes
-- for themselves: a node knocked down by one player stays standing for everyone else,
-- and comes back for that player after `respawn` seconds. So nobody steals anyone's rocks.
--
--   id       the key, the map's `Node` attribute
--   name     shown over the node's health bar
--   world    the world it belongs to
--   verb     what breaking it is called ("Chop", "Mine")
--   tool     the tool kind that breaks it (Tools.Kinds)
--   tier     the lowest tier of that tool that can (1 = World 1's); a node in a later
--            world needs that world's tool
--   hp       how much tool power breaks it; a higher tier hits harder, so later worlds'
--            tools clear early nodes quickly
--   respawn  seconds before a broken node comes back (for the player who broke it)
--   drops    rolled once when the node breaks, each entry on its own:
--            { id = Config/Materials id, min, max, chance (0..1) }
--
-- A node's model may hold a child named `Remains` (a stump, rubble): it shows only
-- while the node is broken, and the rest only while it stands.

-- World scale (2026-10-23, Config/Leveling): node health x2 / x8 for Worlds 1 / 2, like the tools'
-- power (Config/Tools).

local Gathering = {}

export type Drop = { id: string, min: number, max: number, chance: number }

export type NodeDef = {
	id: string,
	name: string,
	world: number,
	verb: string,
	tool: string,
	tier: number,
	hp: number,
	respawn: number,
	drops: { Drop },
}

Gathering.Tag = "GatherNode"

-- Damage on a node goes back to full when nobody has hit it for this long.
Gathering.healAfter = 12
-- Studs of slack on top of the tool's reach and the node's size, for network lag.
Gathering.reachSlack = 3

Gathering.Nodes = {
	-- ==================== World 1 (The Sunny Meadows) ====================
	-- The Wooden Axe / Pickaxe (power 10) fell an oak in 5 hits and break a boulder in 6.
	OakTree = {
		id = "OakTree",
		name = "Oak Tree",
		world = 1,
		verb = "Chop",
		tool = "Axe",
		tier = 1,
		hp = 100,
		respawn = 45,
		drops = {
			{ id = "OakLog", min = 2, max = 3, chance = 1 },
		},
	},
	Boulder = {
		id = "Boulder",
		name = "Boulder",
		world = 1,
		verb = "Mine",
		tool = "Pickaxe",
		tier = 1,
		hp = 120,
		respawn = 45,
		drops = {
			{ id = "Stone", min = 2, max = 3, chance = 1 },
		},
	},
	-- ==================== World 2 (The Redwood Forest) ====================
	-- (2026-10-20) Needs the Stone Axe (power 20): a redwood falls in 5 chops (4 with a Gatherer's
	-- potion I). Its rare drop is Amber Sap (placeholder 10%), used in Regen I (Config/Potions).
	RedwoodTree = {
		id = "RedwoodTree",
		name = "Redwood",
		world = 2,
		verb = "Chop",
		tool = "Axe",
		tier = 2,
		hp = 1000,
		respawn = 45,
		drops = {
			{ id = "RedwoodLog", min = 2, max = 3, chance = 1 },
			{ id = "AmberSap", min = 1, max = 1, chance = 0.1 },
		},
	},
	-- ==================== World 3 (The Crystal Caverns) ====================
	-- (2026-10-24, the user's design) Mining only: both need the Crystal Pickaxe (power 2,000),
	-- an Ore Rock in 6 hits like World 1's boulder and a cluster in 5. Models: Blender
	-- w3_gather_build, art/meshes/w3_gathering.fbx (a grey rock with orange ore veins and nuggets;
	-- a rounded rock with cyan, pink and purple crystals and a pink gem), unlike the cave's
	-- decoration ores and crystals. The Raw Gem is the cluster's rare drop (placeholder 10%).
	OreRock = {
		id = "OreRock",
		name = "Ore Rock",
		world = 3,
		verb = "Mine",
		tool = "Pickaxe",
		tier = 3,
		hp = 12000,
		respawn = 45,
		drops = {
			{ id = "IronOre", min = 2, max = 3, chance = 1 },
		},
	},
	CrystalCluster = {
		id = "CrystalCluster",
		name = "Crystal Cluster",
		world = 3,
		verb = "Mine",
		tool = "Pickaxe",
		tier = 3,
		hp = 10000,
		respawn = 45,
		drops = {
			{ id = "CrystalShard", min = 2, max = 3, chance = 1 },
			{ id = "RawGem", min = 1, max = 1, chance = 0.1 },
		},
	},
} :: { [string]: NodeDef }

function Gathering.get(id: any): NodeDef?
	return if type(id) == "string" then Gathering.Nodes[id] else nil
end

return Gathering
