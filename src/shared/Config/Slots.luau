--!strict
-- Slots: the 6 equipment slots, the stat each provides, and UI placement.
-- Pure data (R-E2, R-E7). Layout: Left column top->bottom Helmet, Weapon, Belt;
-- Right column top->bottom Charm, Chestplate, Boots.

-- Canonical stat identifiers used across gear, talents, traits, and combat.
export type StatType =
	"hp"
	| "attack"
	| "critChance"
	| "dodgeChance"
	| "damageReduction"
	| "healAmount"

export type SlotDef = {
	id: string,
	name: string,
	stat: StatType,
	side: "Left" | "Right",
	row: number, -- 1 = top
}

local Slots = {}

-- All stat types a slot/gear/talent may modify (R-E7).
Slots.StatTypes = {
	"hp",
	"attack",
	"critChance",
	"dodgeChance",
	"damageReduction",
	"healAmount",
}

Slots.Order = { "Helmet", "Weapon", "Belt", "Charm", "Chestplate", "Boots" }

Slots.Defs = {
	Helmet = { id = "Helmet", name = "Helmet", stat = "hp", side = "Left", row = 1 },
	Weapon = { id = "Weapon", name = "Weapon", stat = "attack", side = "Left", row = 2 },
	Belt = { id = "Belt", name = "Belt", stat = "healAmount", side = "Left", row = 3 },
	Charm = { id = "Charm", name = "Charm", stat = "critChance", side = "Right", row = 1 },
	Chestplate = { id = "Chestplate", name = "Chestplate", stat = "damageReduction", side = "Right", row = 2 },
	Boots = { id = "Boots", name = "Boots", stat = "dodgeChance", side = "Right", row = 3 },
} :: { [string]: SlotDef }

function Slots.get(id: string): SlotDef?
	return Slots.Defs[id]
end

return Slots
