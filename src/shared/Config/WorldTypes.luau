--!strict
-- WorldTypes: type-only leaf module shared by the per-world config files and the
-- Worlds aggregator that collects them.
--
-- These types would naturally live in Worlds/init.luau, but a world file needs
-- them and the aggregator requires every world file, so putting them there would
-- be a require cycle. Keeping them in a leaf module that requires nothing breaks
-- it. Enemies.luau re-exports the enemy ones so call sites keep familiar names.
--
-- Exports types only; returns an empty table at runtime (same as Shared/Types).

-- How an enemy fights back in real-time weapon combat (MeleeService).
export type MeleeDef = {
	damage: number, -- HP taken from the player per landed attack
	cooldown: number, -- seconds between attack starts
	windup: number, -- seconds from the attack starting to the hit landing
	range: number, -- studs the attack reaches past the enemy's own front (face, horns or weapon tip)
	chaseSpeed: number, -- studs/sec while chasing
	armor: number, -- 0..1 fraction of weapon damage ignored
	move: string, -- attack animation EnemyAnimator plays ("peck", "gore", "stab")
	-- Optional: several attack animations, one picked at random (evenly) each
	-- attack. They share damage, range and windup, so each must strike at the
	-- same moment. `move` is still the one shown before the first attack.
	moves: { string }?,
}

-- One weapon an enemy can drop: each entry rolls on its own every kill, so an
-- enemy can drop several at once (IndexService rolls them).
export type DropDef = {
	weapon: string, -- Config/Weapons id
	chance: number, -- 0..1 per kill
}

-- One crafting material an enemy can drop (Config/Materials): each entry rolls
-- on its own every kill, and a hit drops min..max of it (MaterialService).
export type MaterialDropDef = {
	id: string, -- Config/Materials id
	chance: number, -- 0..1 per kill
	min: number,
	max: number,
}

-- Coins a kill gives, picked at random between min and max (CoinService).
export type CoinRange = { min: number, max: number }

export type EnemyDef = {
	id: string,
	name: string,
	hp: number, -- max HP
	melee: MeleeDef?, -- absent: the enemy cannot be fought with weapons
	drops: { DropDef }?, -- weapons a kill can drop (shown in the Index)
	materials: { MaterialDropDef }?, -- crafting materials a kill can drop
	coins: CoinRange?, -- coins a kill gives (none if absent)
	exp: number?, -- EXP a kill gives (ExpService; none if absent)
	-- a regular enemy's kind, which sets its respawn time (WorldDef.respawn)
	tier: ("small" | "medium" | "elite")?,
	-- The Index picture: the model turned a little right, seen a little from
	-- above, on a transparent background (art/portraits/enemies/portrait_<id>.png).
	portrait: string?,
	-- A secret enemy (one hidden per world, 2026-10-12): left out of the Index, its
	-- counts and the NEW popup, so finding it stays a surprise.
	secret: boolean?,
	-- A picture shown ONLY in the admin panel's Mobs tab (2026-10-17, the user's
	-- request). Secret enemies use it instead of `portrait`, which the Index, NEW
	-- popup and quest UI all read, so their picture can never leak to players.
	adminPortrait: string?,
}

-- Tuning for the enemies that stand around in the world. Presence tuning that
-- applies to every world lives in Balance.WorldEnemy; this is only what differs
-- per world.
export type WorldEnemyDef = {
	-- Archetype used by a spawn marker that carries no Archetype attribute.
	archetype: string,
}

export type RespawnDef = { small: number, medium: number, elite: number, boss: number, secret: number }

export type WorldDef = {
	id: number,
	name: string, -- display name, e.g. "The Sunny Meadows"
	folder: string, -- matching Workspace.Worlds child name, e.g. "W01_SunnyMeadows"
	profile: string?, -- the Index's world card picture (a close-up of the map)
	-- The world's lighting while you're in it (AmbienceController): Lighting
	-- properties, plus tables for its Atmosphere / ColorCorrection / SunRays.
	lighting: { [string]: any }?,
	-- This world's own roster. An enemy type belongs to exactly one world.
	enemies: { [string]: EnemyDef },
	bosses: { [string]: EnemyDef },
	worldEnemy: WorldEnemyDef?,
	-- seconds until a defeated enemy comes back, by tier (Balance.WorldEnemy if absent)
	respawn: RespawnDef?,
}

return {}
