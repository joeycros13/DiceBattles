--!strict
-- Enemies: enemy archetype stats + weighted action table (R-C7, R-C2).
-- All enemies share the same action set (attack / heal / shield / nothing);
-- only stats and weights differ. Bosses are ordinary archetypes scaled by
-- Balance.Enemy multipliers at spawn time (see Chapters boss flag).

export type ActionWeights = {
	attack: number,
	heal: number,
	shield: number,
	nothing: number,
}

export type EnemyDef = {
	id: string,
	name: string,
	hp: number,
	attack: number,
	heal: number, -- flat self-heal amount when the heal action is chosen
	shield: number, -- flat shield added when the shield action is chosen
	actions: ActionWeights,
	icon: string,
}

local Enemies = {}

Enemies.Defs = {
	Slime = {
		id = "Slime",
		name = "Slime",
		hp = 30,
		attack = 5,
		heal = 4,
		shield = 3,
		actions = { attack = 70, heal = 10, shield = 10, nothing = 10 },
		icon = "enemy/slime",
	},
	Goblin = {
		id = "Goblin",
		name = "Goblin",
		hp = 40,
		attack = 8,
		heal = 5,
		shield = 4,
		actions = { attack = 80, heal = 5, shield = 10, nothing = 5 },
		icon = "enemy/goblin",
	},
	Archer = {
		id = "Archer",
		name = "Archer",
		hp = 35,
		attack = 12,
		heal = 0,
		shield = 2,
		actions = { attack = 90, heal = 0, shield = 5, nothing = 5 },
		icon = "enemy/archer",
	},
	Golem = {
		id = "Golem",
		name = "Golem",
		hp = 80,
		attack = 7,
		heal = 6,
		shield = 12,
		actions = { attack = 50, heal = 10, shield = 35, nothing = 5 },
		icon = "enemy/golem",
	},
	-- Boss archetypes (spawned on the last stage; Balance multipliers applied).
	BossOgre = {
		id = "BossOgre",
		name = "Ogre Warlord",
		hp = 120,
		attack = 14,
		heal = 10,
		shield = 10,
		actions = { attack = 70, heal = 10, shield = 15, nothing = 5 },
		icon = "enemy/boss_ogre",
	},
	BossLich = {
		id = "BossLich",
		name = "Lich King",
		hp = 100,
		attack = 12,
		heal = 20,
		shield = 8,
		actions = { attack = 55, heal = 25, shield = 15, nothing = 5 },
		icon = "enemy/boss_lich",
	},
	BossDragon = {
		id = "BossDragon",
		name = "Elder Dragon",
		hp = 160,
		attack = 18,
		heal = 12,
		shield = 15,
		actions = { attack = 75, heal = 10, shield = 10, nothing = 5 },
		icon = "enemy/boss_dragon",
	},
} :: { [string]: EnemyDef }

function Enemies.get(id: string): EnemyDef?
	return Enemies.Defs[id]
end

return Enemies
