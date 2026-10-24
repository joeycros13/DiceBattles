--!strict
-- Fishing: casting a rod into the water for fish (2026-10-18, the user's design). A
-- fishing rod is a gathering tool (Config/Tools, kind "Rod"); fish are materials
-- (Config/Materials, `fished`). FishingService runs it on the server, FishingController
-- and FishingRingUI on the client.
--
--   1. Cast: a click with the rod out swings it back over the head with both hands and
--      throws the bobber about 5 blocks ahead (`castDistance`). It has to land on water:
--      a part tagged "FishingWater" (Fishing.Tag) whose `Spot` attribute names one of the
--      Spots below. Anywhere along the water works: the pier or any bank.
--   2. Wait: after `biteDelay` seconds a fish's shadow swims in (`approachSeconds`), then
--      bites: the bobber sinks under for `biteSeconds`. Click while it is under to hook
--      the fish; miss it and the bobber comes back up and you wait for the next one.
--      Clicking while nothing bites reels the line in.
--   3. Rings: three rings close in, one after another (`ringGap` between them). Click
--      while the closing ring is inside the target zone, three times in a row. A miss,
--      or letting a ring close, and the fish gets away. Harder fish close faster and
--      have a thinner zone (Difficulty).
--   4. Landed: the line pulls back and the fish pops up out of the water; it goes into
--      the player's materials (MaterialService.drop, the side toast).
--
-- A spot needs a rod of its `tier` or better (the user, 2026-10-20: tools only work for their
-- own world; a World 1 rod in a World 2 pond doesn't, and "Needs a Stone Rod" pops up, like
-- a weak axe on a tree). FishingService refuses the cast; FishingController shows the popup.
--
-- Every fish is the same model in the water, a dark shadow (ReplicatedStorage/Assets/
-- Fishing/FishShadow); only the icons differ (user, 2026-10-18).
--
-- Rings are measured in "closer scale": the closing ring starts at `ringStart` times the
-- target's size and shrinks to `ringEnd` over the fish's `closeSeconds`; the target zone
-- is 1 +- the fish's `zone`. Fishing.zoneTimes gives the seconds it is inside, which the
-- client draws and the server checks.

local Fishing = {}

export type Difficulty = { closeSeconds: number, zone: number }
export type FishEntry = { id: string, weight: number }
export type Spot = { id: string, name: string, world: number, tier: number, fish: { FishEntry } }

Fishing.Tag = "FishingWater"

-- The cast (client, checked loosely by the server)
Fishing.castDistance = 20 -- studs ahead of the player the bobber lands (about 5 blocks)
Fishing.castHeight = 7 -- how far the bobber's arc rises above the straight line
Fishing.flightSeconds = 0.8
Fishing.maxCastRange = 30 -- the server refuses a landing farther than this from the player
Fishing.lineBreak = 36 -- walking this far from the bobber reels the line in

-- The wait and the bite (server)
Fishing.biteDelay = { 3, 8 } -- seconds after landing (and after each missed bite)
Fishing.approachSeconds = 1.6 -- the shadow swims to the bobber before it bites
Fishing.biteSeconds = { 1, 2 } -- how long the bobber stays under (user: 1-2 s)

-- The rings
Fishing.rings = 3
Fishing.ringGap = 0.5 -- seconds from one ring's hit (the band turns yellow) to the next ring (user, 2026-10-19)
Fishing.ringStart = 1.7 -- closer scale at the start of a ring
Fishing.ringEnd = 0.4 -- closer scale when the ring has closed (a miss)
-- Seconds of slack on the server's ring check, for network lag both ways.
Fishing.ringSlack = 0.35

-- Generous zones (user: "so the players dont mess up"), harder for harder fish.
Fishing.Difficulty = {
	Easy = { closeSeconds = 1.7, zone = 0.32 },
	Medium = { closeSeconds = 1.35, zone = 0.26 },
	Hard = { closeSeconds = 1.05, zone = 0.2 },
} :: { [string]: Difficulty }

-- Which difficulty each fish (a Config/Materials id) fights with.
Fishing.Fish = {
	Minnow = "Easy",
	Sunfish = "Medium",
	GoldenCarp = "Hard",
	Trout = "Easy",
	Perch = "Medium",
	RainbowTrout = "Hard",
	Glowfish = "Easy",
	BlindCavefish = "Medium",
	CrystalEel = "Hard",
} :: { [string]: string }

Fishing.Spots = {
	-- World 1's pond, by Finn's fishing hut
	SunnyPond = {
		id = "SunnyPond",
		name = "The Pond",
		world = 1,
		tier = 1,
		fish = {
			{ id = "Minnow", weight = 60 },
			{ id = "Sunfish", weight = 30 },
			{ id = "GoldenCarp", weight = 10 },
		},
	},
	-- World 2's creek and pond: one water part (Ground/Creek/Water), so the whole creek fishes
	-- too. The approved table's fish (memory tools-per-world): Trout and the rare Rainbow Trout, plus
	-- the Perch (the user, 2026-10-20: three tiers like World 1's pond, at its weights).
	RedwoodPond = {
		id = "RedwoodPond",
		name = "The Creek",
		world = 2,
		tier = 2,
		fish = {
			{ id = "Trout", weight = 60 },
			{ id = "Perch", weight = 30 },
			{ id = "RainbowTrout", weight = 10 },
		},
	},
	-- World 3's glowing lake in the middle hall (Ground/Lake/Water, 2026-10-24): the user's fish
	-- (memory tools-per-world), a Crystal Rod or better.
	CrystalLake = {
		id = "CrystalLake",
		name = "The Glowing Lake",
		world = 3,
		tier = 3,
		fish = {
			{ id = "Glowfish", weight = 60 },
			{ id = "BlindCavefish", weight = 30 },
			{ id = "CrystalEel", weight = 10 },
		},
	},
} :: { [string]: Spot }

function Fishing.spot(id: any): Spot?
	return if type(id) == "string" then Fishing.Spots[id] else nil
end

-- The rod a spot needs: the name of the lowest-tier rod that can fish it ("Stone Rod").
function Fishing.rodFor(spot: Spot): string
	local Tools = require(script.Parent:WaitForChild("Tools"))
	local best: any = nil
	for _, def in Tools.Defs do
		if def.kind == "Rod" and def.tier >= spot.tier and (best == nil or def.tier < best.tier) then
			best = def
		end
	end
	return if best then best.name else "better rod"
end

function Fishing.difficultyOf(fishId: string): Difficulty
	return Fishing.Difficulty[Fishing.Fish[fishId] or "Easy"] or Fishing.Difficulty.Easy
end

-- The closer's scale `t` seconds into a ring of this difficulty.
function Fishing.closerScale(difficulty: Difficulty, t: number): number
	local u = math.clamp(t / difficulty.closeSeconds, 0, 1)
	return Fishing.ringStart + (Fishing.ringEnd - Fishing.ringStart) * u
end

-- Seconds into a ring when the closer enters the zone and when it leaves it.
function Fishing.zoneTimes(difficulty: Difficulty): (number, number)
	local span = Fishing.ringStart - Fishing.ringEnd
	local enter = (Fishing.ringStart - (1 + difficulty.zone)) / span * difficulty.closeSeconds
	local leave = (Fishing.ringStart - (1 - difficulty.zone)) / span * difficulty.closeSeconds
	return enter, leave
end

-- A fish's chance at a spot (0..1), for the Index's drop slip.
function Fishing.chanceAt(spot: Spot, fishId: string): number?
	local total, mine = 0, nil
	for _, entry in spot.fish do
		total += entry.weight
		if entry.id == fishId then
			mine = entry.weight
		end
	end
	return if mine and total > 0 then mine / total else nil
end

return Fishing
