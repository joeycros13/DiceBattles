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
		hp = 8,
		attack = 2,
		heal = 2,
		shield = 2,
		actions = { attack = 70, heal = 10, shield = 10, nothing = 10 },
		icon = "enemy/slime",
	},
	Goblin = {
		id = "Goblin",
		name = "Goblin",
		hp = 10,
		attack = 3,
		heal = 2,
		shield = 2,
		actions = { attack = 80, heal = 5, shield = 10, nothing = 5 },
		icon = "enemy/goblin",
	},
	Archer = {
		id = "Archer",
		name = "Archer",
		hp = 9,
		attack = 3,
		heal = 0,
		shield = 1,
		actions = { attack = 90, heal = 0, shield = 5, nothing = 5 },
		icon = "enemy/archer",
	},
	Golem = {
		id = "Golem",
		name = "Golem",
		hp = 15,
		attack = 3,
		heal = 3,
		shield = 4,
		actions = { attack = 50, heal = 10, shield = 35, nothing = 5 },
		icon = "enemy/golem",
	},
	-- Boss archetypes (spawned on the last stage; Balance multipliers applied).
	BossOgre = {
		id = "BossOgre",
		name = "Ogre Warlord",
		hp = 30,
		attack = 5,
		heal = 4,
		shield = 4,
		actions = { attack = 70, heal = 10, shield = 15, nothing = 5 },
		icon = "enemy/boss_ogre",
	},
	BossLich = {
		id = "BossLich",
		name = "Lich King",
		hp = 25,
		attack = 4,
		heal = 6,
		shield = 3,
		actions = { attack = 55, heal = 25, shield = 15, nothing = 5 },
		icon = "enemy/boss_lich",
	},
	BossDragon = {
		id = "BossDragon",
		name = "Elder Dragon",
		hp = 35,
		attack = 6,
		heal = 4,
		shield = 5,
		actions = { attack = 75, heal = 10, shield = 10, nothing = 5 },
		icon = "enemy/boss_dragon",
	},
} :: { [string]: EnemyDef }

function Enemies.get(id: string): EnemyDef?
	return Enemies.Defs[id]
end

return Enemies
