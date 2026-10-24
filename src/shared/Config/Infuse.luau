--!strict
-- Infuse: the secret super weapon's cores and sockets (memory secret-weapon-plan, 2026-10-12).
--
-- Each world's secret enemy drops that world's core (Config/Materials `core`). Cores are set into the
-- blade at that world's Infuser, a stone altar beside the Crafter (a model tagged "Infuser" with a
-- "World" attribute; InfuseService checks the player stands at one).
--   * The FIRST core must be the Farm Core: infusing it into the Rusty Blade awakens it into the
--     Worldheart Blade (the Rusty Blade and the core are used up).
--   * Every later core goes in IN WORLD ORDER (user, 2026-10-12): world N's core only once worlds
--     1..N-1 are in, so a tier-N blade always holds worlds 1..N (its inventory icon shows exactly
--     those gems). At its own world's Infuser.
-- Sockets are fixed per world: socket N holds world N's core. Socket 1 is in the guard; 2..8 run down
-- the blade toward the tip. The Worldheart template carries an Attachment "Socket<N>" for each on its
-- Grip (UpVector out of the face, GemScale attribute); InfuseService sets a small copy of the core's
-- model (ReplicatedStorage/Assets/Cores/<id>) into each filled socket.
-- The player's infused cores reach the client as the "InfusedCores" attribute ("FarmCore,ForestCore").

local Materials = require(script.Parent:WaitForChild("Materials"))

local Infuse = {}

Infuse.SOCKETS = 8
Infuse.FIRST = "FarmCore"
Infuse.BLADE = "RustyBlade"
Infuse.AWAKENED = "WorldheartBlade"
-- seconds the client's reveal plays before the new blade goes into the hand and the popup shows
Infuse.REVEAL_SECONDS = 3.2
-- how close (studs, flat) to an Infuser's centre a request still counts
Infuse.RANGE = 12

-- ---------- the Worldheart Blade's tiers (user, 2026-10-12) ----------
-- With N cores it beats World N's secret weapon by about 10%: World 1's Corn Cob does 50 damage a
-- second, World 2's Marshmallow Stick 75 (before the 2026-10-13 rescale, see DPS below). Worlds 4..8 have
-- no secret yet, so their tiers are placeholders until those are designed (then set DPS[n] to theirs x1.1).
-- Every core after the first also adds 10% attack speed and 5% reach, so all 8 cores give +70% speed
-- and +35% reach; the longer reach shows as an energy blade over the steel (InfuseService), the
-- model itself never grows. Damage per hit is worked out from the target DPS and the faster swing.
Infuse.BASE_COOLDOWN = 0.95
Infuse.BASE_REACH = 8.5
Infuse.SPEED_PER_CORE = 0.10
Infuse.REACH_PER_CORE = 0.05
-- (2026-10-13) Tiers 1..3 = that world's secret x1.1 after the weapons were rescaled to boss HP
-- (Corn Cob 47, Marshmallow Stick 312, Rock Candy Club 675 DPS); 4..8 are placeholders at x2 per core.
-- World scale (2026-10-23, the user: World 1 near 100, World 2 1K, World 3 10K...): each tier was
-- multiplied by its world's offense scale, x2 / x8 / x32 / x128... (see Config/Leveling). Tier 2 follows
-- World 2's weapons x0.8 (2026-10-24, the rescale: a maxed World 2 player near 1,000 DPS): 819 x 1.1;
-- tier 3 World 3's x0.63 (near 10,000): 7,197 x 1.1.
Infuse.DPS = { 103.4, 900.9, 7916.7, 100531.2, 804249.6, 6433996.8, 51471974.4, 411775795.2 } -- damage per second at 1..8 cores (trial numbers)

export type Tier = { cores: number, damage: number, cooldown: number, reach: number, speedBonus: number, reachBonus: number }

-- The blade's stats with `cores` cores in it (1..SOCKETS).
function Infuse.tier(cores: number): Tier
	local n = math.clamp(math.floor(cores), 1, Infuse.SOCKETS)
	local speedBonus = Infuse.SPEED_PER_CORE * (n - 1)
	local reachBonus = Infuse.REACH_PER_CORE * (n - 1)
	local cooldown = Infuse.BASE_COOLDOWN / (1 + speedBonus)
	return {
		cores = n,
		damage = math.floor(Infuse.DPS[n] * cooldown + 0.5),
		cooldown = cooldown,
		reach = Infuse.BASE_REACH * (1 + reachBonus),
		speedBonus = speedBonus,
		reachBonus = reachBonus,
	}
end

-- How many cores the player has infused (at least 1 once it has awakened).
function Infuse.count(player: Player): number
	local n = 0
	for _ in Infuse.infused(player) do
		n += 1
	end
	return math.max(n, 1)
end

-- Each tier is its own weapon (2026-10-12): tier 1 is WorldheartBlade, tier N WorldheartBlade<N>.
function Infuse.bladeOf(tier: number): string
	return if tier <= 1 then Infuse.AWAKENED else Infuse.AWAKENED .. tostring(tier)
end

-- A weapon's Worldheart tier (nil for every other weapon).
function Infuse.tierOf(def: any): number?
	return if type(def) == "table" and type(def.worldheartTier) == "number" then def.worldheartTier else nil
end

-- The cores shown in a tier-N blade's sockets. Cores go in world order, so a tier-N blade holds
-- worlds 1..N; an admin-given blade (no cores infused) is topped up the same way.
function Infuse.gemsFor(player: Player, tier: number): { string }
	local list = {}
	local seen = {}
	local infused = {}
	for id in Infuse.infused(player) do
		table.insert(infused, id)
	end
	table.sort(infused, function(a, b)
		return (Infuse.socketOf(a) or 99) < (Infuse.socketOf(b) or 99)
	end)
	for _, id in infused do
		if #list < tier then
			table.insert(list, id)
			seen[id] = true
		end
	end
	local world = 1
	while #list < tier and world <= Infuse.SOCKETS do
		local id = Infuse.coreOfWorld(world)
		if id and not seen[id] then
			table.insert(list, id)
			seen[id] = true
		end
		world += 1
	end
	return list
end

-- A weapon def as it swings: a Worldheart Blade's damage, cooldown and reach follow its tier; every
-- other weapon is returned unchanged. Used by MeleeService (hits), WeaponController (swing speed,
-- reach) and the tiles' damage labels. (`player` is kept for callers; the tier is the weapon's.)
function Infuse.adjust(_player: Player, def: any): any
	local tier = Infuse.tierOf(def)
	if not tier then
		return def
	end
	local t = Infuse.tier(tier)
	local copy = table.clone(def)
	copy.damage = t.damage
	copy.cooldown = t.cooldown
	copy.reach = t.reach
	return copy
end

-- The core that belongs to a world (nil if that world has none yet).
function Infuse.coreOfWorld(world: number): string?
	for _, def in Materials.list() do
		if def.core and def.world == world then
			return def.id
		end
	end
	return nil
end

-- Whether `id` is the next core this player may set: its socket must be the next one in order.
function Infuse.isNext(player: Player, id: string): boolean
	local socket = Infuse.socketOf(id)
	local n = 0
	for _ in Infuse.infused(player) do
		n += 1
	end
	return socket ~= nil and socket == n + 1
end

-- A core's socket: its world.
function Infuse.socketOf(id: string): number?
	local def = Materials.get(id)
	return if def and def.core then def.world else nil
end

-- The player's infused cores, from their "InfusedCores" attribute. Works on both sides.
function Infuse.infused(player: Player): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local text = player:GetAttribute("InfusedCores")
	for id in (if type(text) == "string" then text else ""):gmatch("[^,]+") do
		out[id] = true
	end
	return out
end

-- Where a core's gem sits in a socket: the gem model (pivot at its centre, axis up its Y) is
-- scaled by the socket's GemScale and set so its girdle sits just proud of the hollow. The gem is
-- mirrored about its girdle (2026-10-13: same bevel top and bottom), so the girdle IS its centre and
-- the lower half sits in the hollow. GEM_TURN spins it about its axis so its emblem stands upright
-- toward the blade's tip (each emblem's foot points at an octagon edge), which also lines the gem's
-- octagon up with the socket rim's (both flat across the blade). Worked out for the Worldheart's
-- sockets (UpVector out of the face, blade tip along the grip's -Z).
Infuse.GIRDLE_LIFT = 0.012
Infuse.GEM_TURN = math.rad(202.5)
function Infuse.gemCFrame(socket: Attachment): (CFrame, number)
	local s = socket:GetAttribute("GemScale")
	local scale = if type(s) == "number" then s else 1
	return socket.WorldCFrame * CFrame.new(0, Infuse.GIRDLE_LIFT, 0) * CFrame.Angles(0, Infuse.GEM_TURN, 0), scale
end

return Infuse
