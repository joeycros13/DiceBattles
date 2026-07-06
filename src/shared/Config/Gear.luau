--!strict
-- Gear: gear definitions (id, slot, rarity, base stat) (R-E1..R-E7).
-- baseStat is the Common-rarity magnitude for the slot's stat; runtime scales it
-- by the piece's rarity multiplier (Rarities) and the slot's level (Balance).
-- If baseStat is nil, systems fall back to Balance.GearBaseStat[slot.stat].

export type GearDef = {
	id: string,
	name: string,
	slot: string, -- Slots.Defs key
	rarity: string, -- Rarities.Defs key
	baseStat: number?, -- override for the slot's stat magnitude
	icon: string, -- logical asset id for AssetResolver
}

local Gear = {}

Gear.Defs = {
	-- Helmet (hp)
	IronHelm = { id = "IronHelm", name = "Iron Helm", slot = "Helmet", rarity = "Common", baseStat = 20, icon = "gear/helmet" },
	SteelHelm = { id = "SteelHelm", name = "Steel Helm", slot = "Helmet", rarity = "Uncommon", baseStat = 20, icon = "gear/helmet" },
	RunicHelm = { id = "RunicHelm", name = "Runic Helm", slot = "Helmet", rarity = "Rare", baseStat = 20, icon = "gear/helmet" },

	-- Weapon (attack)
	WoodSword = { id = "WoodSword", name = "Wooden Sword", slot = "Weapon", rarity = "Common", baseStat = 5, icon = "gear/weapon" },
	IronSword = { id = "IronSword", name = "Iron Sword", slot = "Weapon", rarity = "Uncommon", baseStat = 5, icon = "gear/weapon" },
	FlameBlade = { id = "FlameBlade", name = "Flame Blade", slot = "Weapon", rarity = "Rare", baseStat = 5, icon = "gear/weapon" },
	DragonFang = { id = "DragonFang", name = "Dragon Fang", slot = "Weapon", rarity = "Epic", baseStat = 5, icon = "gear/weapon" },

	-- Belt (healAmount)
	LeatherBelt = { id = "LeatherBelt", name = "Leather Belt", slot = "Belt", rarity = "Common", baseStat = 8, icon = "gear/belt" },
	HealerSash = { id = "HealerSash", name = "Healer's Sash", slot = "Belt", rarity = "Rare", baseStat = 8, icon = "gear/belt" },

	-- Charm (critChance)
	LuckyCharm = { id = "LuckyCharm", name = "Lucky Charm", slot = "Charm", rarity = "Common", baseStat = 0.03, icon = "gear/charm" },
	CritGem = { id = "CritGem", name = "Crit Gem", slot = "Charm", rarity = "Epic", baseStat = 0.03, icon = "gear/charm" },

	-- Chestplate (damageReduction)
	LeatherVest = { id = "LeatherVest", name = "Leather Vest", slot = "Chestplate", rarity = "Common", baseStat = 0.02, icon = "gear/chestplate" },
	PlateArmor = { id = "PlateArmor", name = "Plate Armor", slot = "Chestplate", rarity = "Rare", baseStat = 0.02, icon = "gear/chestplate" },
	Aegis = { id = "Aegis", name = "Aegis", slot = "Chestplate", rarity = "Legendary", baseStat = 0.02, icon = "gear/chestplate" },

	-- Boots (dodgeChance)
	Sandals = { id = "Sandals", name = "Sandals", slot = "Boots", rarity = "Common", baseStat = 0.03, icon = "gear/boots" },
	SwiftBoots = { id = "SwiftBoots", name = "Swift Boots", slot = "Boots", rarity = "Uncommon", baseStat = 0.03, icon = "gear/boots" },
	PhantomBoots = { id = "PhantomBoots", name = "Phantom Boots", slot = "Boots", rarity = "Epic", baseStat = 0.03, icon = "gear/boots" },
} :: { [string]: GearDef }

function Gear.get(id: string): GearDef?
	return Gear.Defs[id]
end

-- All gear ids for a given slot (unordered).
function Gear.idsForSlot(slotId: string): { string }
	local ids: { string } = {}
	for id, def in Gear.Defs do
		if def.slot == slotId then
			table.insert(ids, id)
		end
	end
	return ids
end

return Gear
