--!strict
-- Weapons: how every weapon in Config/Weapons is held and swung, as clips for
-- the R6 player rig.
--
--   WeaponClips.hold(def)       looping, priority Hold: how the weapon is carried
--                               (nil for unarmed weapons -- the arms stay free)
--   WeaponClips.swing(def)      the arms of one swing, priority Action, length 1
--                               (play at speed 1 / def.cooldown). Markers "Hit" at
--                               def.hitTime, "TrailOn" / "TrailOff" around it.
--   WeaponClips.swingBody(def)  the body of the same swing (twist, lean, lunge), an
--                               ADDITIVE clip -- play it alongside, at the same
--                               speed, so walking, bob and foot planting carry on.
--   WeaponClips.extra(def, name) another swing played with the def's hold and hands
--                               (the fishing rod's Reel): arms clip, body clip
--   WeaponClips.report(def)     how well the poses can actually be reached
-- Clips are built once per weapon and cached.
--
-- ==================== authoring ====================
-- Poses say where the RIGHT HAND is and where the WEAPON POINTS; the R6 solver
-- below works out the arm and the weapon's turn in the hand. All in the torso's
-- frame, studs from the torso's centre: +X right, +Y up, -Z forward. For scale:
-- shoulders are at (+-1, 0.5, 0), a hanging hand at (1.5, -1, 0), and a straight
-- arm reaches about 1.6 from its shoulder (+0.4 / -0.3 by sliding the shoulder).
--
--   hand = { x, y, z }   right hand position
--   dir  = { x, y, z }   weapon direction (the model's -Z), need not be unit
--   roll = degrees       turn about that direction (which way edges / flats face)
--   two  = 0..1          two-handed only: left hand on the shaft (1) or free (0)
--   off  = studs         where on the shaft the left hand goes (default: the
--                        model's OffGrip; slides along the shaft to stay reachable)
--   left = { x, y, z }   where the free left hand goes when two = 0
--   wy wp ry rz          body: twist left, lean forward, whole-body turn (deg),
--                        step forward (studs)
-- HOLDS[id] is one pose. SWINGS[name] is a list of keys { u = 0..1, ... }; fields
-- a key leaves out come from the hold (hand, dir, roll, two, off, left) or are 0
-- (body). So the first and last keys are just { u = 0 } and { u = 1 }.
--   ease = "out"         how the move INTO this key is timed. Default: eased in and
--                        out, so the motion comes to rest on every key (a key in
--                        the middle of a stroke reads as a pause). "out" starts at
--                        full speed and slows into the key (a strike straight out
--                        of a wind-up); "in" starts slow and arrives at full speed
--                        (a key the stroke passes THROUGH: pair it with "out" on
--                        the next key, spans sized so the speeds match); "linear"
--                        keeps one speed.
-- Every swing is right-handed: it starts on the right and travels to the left
-- (user, 2026-10-11).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = script.Parent.Parent
local Clip = require(Animation.Clip)

local Weapons = {}

type Key = { [string]: any }

-- ==================== holds ====================

Weapons.HOLDS = {
	-- one-handed, low and ready at the hip
	Dagger = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	Sickle = { hand = { 1.5, -0.8, -0.3 }, dir = { 0, 0.45, -1 }, roll = 0 },
	Machete = { hand = { 1.5, -0.85, -0.25 }, dir = { 0, 0.55, -1 }, roll = 0 },
	-- the Rusty Blade (Relic): the Machete's hold until it gets its own
	RustyBlade = { hand = { 1.5, -0.85, -0.25 }, dir = { 0, 0.55, -1 }, roll = 0 },
	WorldheartBlade = { hand = { 1.5, -0.85, -0.25 }, dir = { 0, 0.55, -1 }, roll = 0 },
	WorldheartBlade2 = { hand = { 1.5, -0.85, -0.25 }, dir = { 0, 0.55, -1 }, roll = 0 },
	WorldheartBlade3 = { hand = { 1.5, -0.85, -0.25 }, dir = { 0, 0.55, -1 }, roll = 0 },
	-- held by the shaft at the hip (the model's grip is on the shaft, the D-grip
	-- behind the hand), blade forward-up, flats up/down ready for the bonk
	Shovel = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.5, -1 }, roll = 90 },
	-- the giant Corn Cob (secret): held exactly like the Dagger (the user wants
	-- just two holds, one-handed and two-handed)
	CornCob = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	-- the Pumpkin King's Mace (Legendary): the one-handed hold as well
	PumpkinMace = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	-- both hands, head up on the left
	Pitchfork = { hand = { 1.1, -0.9, -0.75 }, dir = { -0.75, 0.65, -0.2 }, roll = 0, two = 1 },
	-- the Weathervane Spear (Legendary): the Pitchfork's two-handed hold (same
	-- grip and OffGrip spacing) until it gets its own sweep
	WeathervaneSpear = { hand = { 1.1, -0.9, -0.75 }, dir = { -0.75, 0.65, -0.2 }, roll = 0, two = 1 },
	-- both hands on the two pegs (right on the upper peg, left on the lower), the
	-- snath leaning up to the right, blade out to the right and curving down
	Scythe = { hand = { 0.9, 1.0, -1.25 }, dir = { 0.57, 0.82, -0.03 }, roll = 125, two = 1 },
	-- ==================== World 2 (2026-10-11) ====================
	-- one-handers: the Dagger's hold
	Hatchet = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	Cleaver = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	Mace = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	LanternFlail = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	MarshmallowStick = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	-- two-handers: the Pitchfork's hold
	WoodsmansAxe = { hand = { 1.1, -0.9, -0.75 }, dir = { -0.75, 0.65, -0.2 }, roll = 0, two = 1 },
	Greatclub = { hand = { 1.1, -0.9, -0.75 }, dir = { -0.75, 0.65, -0.2 }, roll = 0, two = 1 },
	HeartwoodStaff = { hand = { 1.1, -0.9, -0.75 }, dir = { -0.75, 0.65, -0.2 }, roll = 0, two = 1 },
	-- ==================== gathering tools (Config/Tools, 2026-10-18) ====================
	-- one-handed for now: the Dagger's hold, until they get their own
	WoodenAxe = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	WoodenPickaxe = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	-- the fishing rod: one hand at the hip, the rod pointing out ahead and up toward the
	-- water (user, 2026-10-18: one-handed normally, both hands only for the cast). The
	-- reel hangs under the rod (roll 0: the model's -Y is down).
	WoodenRod = { hand = { 1.45, -0.75, -0.45 }, dir = { 0, 0.45, -1 }, roll = 0, two = 0 },
	-- World 2's tools (2026-10-20) are built to the wooden ones' sizes, so they share their holds
	StoneAxe = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	StoneRod = { hand = { 1.45, -0.75, -0.45 }, dir = { 0, 0.45, -1 }, roll = 0, two = 0 },
	-- World 3's tools (2026-10-24) too
	CrystalPickaxe = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	CrystalRod = { hand = { 1.45, -0.75, -0.45 }, dir = { 0, 0.45, -1 }, roll = 0, two = 0 },
	-- the 10-stud Pinecone Staff (6.3 ahead of the hand, 3.8 behind): held level across
	-- the front, head out to the right and a touch back, the butt crossing in front of
	-- the body to the left hand (behind the grip, off = -1.6). The staff stays across the
	-- front so its long butt never passes through the body (user, 2026-10-11).
	Quarterstaff = { hand = { 1.1, -0.7, -0.8 }, dir = { 1, 0.12, 0.3 }, roll = 0, two = 1, off = -1.6 },
	-- ==================== World 3 (2026-10-13): borrowed holds for now ====================
	BatwingBlade = { hand = { 1.5, -0.85, -0.25 }, dir = { 0, 0.55, -1 }, roll = 0 },
	IronPickaxe = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	PebbleMallet = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	QueensFang = { hand = { 1.5, -0.85, -0.25 }, dir = { 0, 0.55, -1 }, roll = 0 },
	DiamondPickaxe = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 },
	-- the Machete's hold and diagonal swing (user, 2026-10-13)
	RockCandyClub = { hand = { 1.5, -0.85, -0.25 }, dir = { 0, 0.55, -1 }, roll = 0 },
	EmberCoalMaul = { hand = { 1.1, -0.9, -0.75 }, dir = { -0.75, 0.65, -0.2 }, roll = 0, two = 1 },
	-- the glaive: the Pinecone Staff's level hold across the front; the right hand on the upper
	-- wrap, the left on the lower wrap 1.9 behind it (OffGrip at +1.9, user 2026-10-13: hands on
	-- the handle, not the bare shaft)
	GeodeGlaive = { hand = { 1.1, -0.7, -0.8 }, dir = { 1, 0.12, 0.3 }, roll = 0, two = 1, off = -1.9 },
	-- the Gold Gauntlets (worn): a fight-ready guard, both fists up in front of the face with
	-- the arms angled up (user, 2026-10-13). The gloves line up with the forearms (def.worn),
	-- so only the hands' positions matter.
	GoldGauntlets = { hand = { 1.0, 1.05, -1.15 }, dir = { 0, 1, -1 }, roll = 0, two = 0, left = { -1.0, 1.05, -1.15 } },
} :: { [string]: Key }

-- ==================== swings ====================

-- the two-handed overhead lift (Splitter, Boulder Club): weapon straight up
local LIFT_HAND = { 0.8, 1.6, -0.95 }
local LIFT_DIR = { 0.05, 1, -0.1 }
local RECOVER_2H = { u = 0.9, hand = { 1.0, -0.4, -1.35 }, dir = { -0.45, 0.6, -0.65 }, two = 0, off = 1.9, left = { -1.1, -0.6, -0.6 }, ease = "in" }
-- on the way up the left hand also lets go (it can't slide down past the right
-- hand) and takes the haft again below it at the top; passed through at speed
local LIFT_FREE_2H = { u = 0.17, hand = { 1.05, 0.45, -1.15 }, dir = { -0.35, 0.85, -0.45 }, two = 0, off = 0.6, left = { -0.9, 0.0, -1.0 }, wy = -5, wp = -3, ease = "in" }
-- where the Hook passes in front of the body (see Hook)
local HOOK_MID = 0.55

Weapons.SWINGS = {
	-- Dagger: pull it back along the side, then lunge it straight forward.
	Jab = {
		{ u = 0 },
		{ u = 0.32, hand = { 1.45, -0.55, 0.75 }, dir = { 0, 0.1, -1 }, wy = -18, wp = -4 },
		{ u = 0.5, hand = { 0.85, 0.05, -1.4 }, dir = { -0.1, 0.02, -1 }, wy = 18, wp = 8, rz = 0.55 },
		{ u = 0.68, hand = { 0.9, 0.0, -1.35 }, dir = { -0.08, 0.02, -1 }, wy = 14, wp = 6, rz = 0.45 },
		{ u = 1 },
	},
	-- Sickle / Firefly Lantern: swing out to the right, then a flat hook straight
	-- across the body. The key in front of the body is passed THROUGH (ease "in" then
	-- "out"): it used to ease to a stop there, so the swing paused halfway (user,
	-- 2026-10-11). The spans are sized to the distances so the speed carries over.
	Hook = {
		{ u = 0 },
		{ u = 0.3, hand = { 2.45, 0.25, 0.35 }, dir = { 0.7, 0, -0.7 }, roll = 90, wy = -30 },
		{ u = HOOK_MID, hand = { 0.75, 0.15, -1.45 }, dir = { -0.2, 0, -1 }, roll = 90, wy = 8, wp = 6, rz = 0.2, ease = "in" },
		{ u = 0.7, hand = { -0.35, 0.05, -0.95 }, dir = { -1, 0, -0.35 }, roll = 90, wy = 35, wp = 6, ease = "out" },
		{ u = 1 },
	},
	-- Stone & Bone Cleaver: straight up over the head (the blade straight up, not
	-- tipped back), then one chop down in front, edge first (user, 2026-10-11).
	Cleave = {
		{ u = 0 },
		{ u = 0.36, hand = { 1.15, 2.0, -0.25 }, dir = { 0.02, 1, -0.05 }, wp = -6 },
		{ u = 0.56, hand = { 1.0, -0.1, -1.45 }, dir = { 0, -0.4, -1 }, wp = 10, rz = 0.3, ease = "out" },
		{ u = 0.74, hand = { 1.0, -0.15, -1.42 }, dir = { 0, -0.42, -1 }, wp = 8, rz = 0.25 },
		{ u = 1 },
	},
	-- Machete: raise it up to the right, then slash diagonally down across the body
	-- and all the way through.
	Diagonal = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.95, 1.65, 0.2 }, dir = { 1, 0.95, 0.3 }, wy = -25, wp = -5 },
		{ u = 0.52, hand = { 0.7, 0.2, -1.4 }, dir = { -0.6, -0.3, -1 }, wy = 15, wp = 10, rz = 0.3 },
		-- (the long blade must stay above the ground on the follow-through)
		{ u = 0.72, hand = { 0.0, -0.9, -0.8 }, dir = { -1, -0.3, -0.5 }, wy = 30, wp = 10 },
		{ u = 1 },
	},
	-- Shovel: straight up off the shoulder, then straight down. Bonk.
	Bonk = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.15, 2.05, -0.15 }, dir = { 0, 1, 0.25 }, wp = -8 },
		{ u = 0.6, hand = { 1.0, -0.15, -1.45 }, dir = { 0, -0.45, -1 }, wp = 14, rz = 0.3 },
		{ u = 0.76, hand = { 1.0, -0.25, -1.42 }, dir = { 0, -0.5, -1 }, wp = 12, rz = 0.25 },
		{ u = 1 },
	},
	-- Corn Cob: a bigger bonk for an 8.7-stud cob. Raised high with the cob tipped
	-- back over the shoulder, slammed down in front (the tip just meets the
	-- ground), held a beat, then back to the hold.
	CornBonk = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.05, 2.0, 0.05 }, dir = { 0.05, 0.75, 0.66 }, wp = -10 },
		{ u = 0.6, hand = { 0.95, -0.1, -1.45 }, dir = { 0, -0.14, -1 }, wp = 6, rz = 0.35 },
		{ u = 0.78, hand = { 0.95, -0.15, -1.42 }, dir = { 0, -0.16, -1 }, wp = 5, rz = 0.3 },
		{ u = 1 },
	},
	-- Pitchfork: bring it over to the right side (body turned right, both hands),
	-- then drive it forward like the dagger -- the right hand thrusts, the left
	-- lets go and guards.
	Thrust = {
		{ u = 0 },
		{ u = 0.3, hand = { 1.35, -0.6, 0.5 }, dir = { -0.41, 0.15, -0.9 }, two = 1, wy = -24, wp = -3 },
		{ u = 0.5, hand = { 1.05, -0.25, -1.35 }, dir = { 0.05, 0, -1 }, two = 0, left = { -0.9, -0.7, -1.2 }, wy = 12, wp = 10, rz = 0.9 },
		{ u = 0.7, hand = { 1.05, -0.28, -1.3 }, dir = { 0.05, 0, -1 }, two = 0, left = { -0.9, -0.7, -1.2 }, wy = 10, wp = 8, rz = 0.7 },
		{ u = 1 },
	},
	-- Scythe: the snath swung level out to the right (hands on both pegs, blade at
	-- the right end pointing forward), then one sweep across to the left at a
	-- slight downward angle. The blade's inner edge faces back along the snath,
	-- so with the snath out to the right it LEADS the leftward sweep.
	-- One unbroken stroke (user, 2026-10-11): there used to be a key in the middle
	-- of the sweep, and every key eases to a stop, so the swing paused halfway.
	-- A quick wind-up, then one sweep that builds up speed, is fastest at the hit
	-- (u ~0.46) and slows into the finish on the left (user, 2026-10-11: the sweep
	-- that left the wind-up at full speed and only slowed down read as a jolt and a
	-- drift, not "one fell sweep").
	Sweep = {
		{ u = 0 },
		{ u = 0.2, hand = { 1.6, -0.5, -1.15 }, dir = { 1, 0.2, 0 }, roll = 5, ry = -75, wp = 2 },
		{ u = 0.72, hand = { 1.5, -0.6, -1.1 }, dir = { 1, -0.12, 0 }, roll = 5, ry = 70, wp = 6 },
		{ u = 1 },
	},
	-- Weathervane Spear "Gust" (user's pick, 2026-10-19): one wide level sweep. The right
	-- hand holds the spear straight out in front (the left lets go: R6 arms can't both
	-- reach a shaft pointing ahead) and the BODY turns, like the Scythe's: wound up turned
	-- right with the tip out on the right, then round to the left in one eased sweep that
	-- is fastest as the tip passes in front (the hit, u ~0.46). A gust rolls out on the hit
	-- (impact = "Gust").
	Gust = {
		{ u = 0 },
		{ u = 0.24, hand = { 1.4, -0.7, -0.7 }, dir = { -0.05, 0.04, -1 }, two = 0, left = { -1.2, -0.6, -0.9 }, ry = -85, wp = 1 },
		{ u = 0.7, hand = { 1.2, -0.55, -1.0 }, dir = { -0.05, 0.02, -1 }, two = 0, left = { -1.25, -0.55, -0.7 }, ry = 70, wp = 6 },
		{ u = 0.84, hand = { 1.2, -0.56, -0.98 }, dir = { -0.05, 0.02, -1 }, two = 0, left = { -1.25, -0.55, -0.7 }, ry = 66, wp = 5 },
		{ u = 1 },
	},
	-- Pumpkin King's Mace "Pumpkin smash" (user's pick, 2026-10-19): raised high over the
	-- right shoulder, then one heavy diagonal smash down and across to the left, the
	-- pumpkin head just meeting the ground (impact = "Pumpkin": sparks and seeds there).
	PumpkinSmash = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.75, 1.7, 0.3 }, dir = { 0.6, 1, 0.45 }, wy = -28, wp = -8 },
		-- (measured: the head's lowest point lands at -3.05, the ground is -3)
		{ u = 0.58, hand = { 0.55, -0.25, -1.35 }, dir = { -0.5, -0.15, -0.9 }, wy = 20, wp = 8, rz = 0.35, ease = "out" },
		{ u = 0.78, hand = { 0.5, -0.3, -1.32 }, dir = { -0.5, -0.17, -0.88 }, wy = 18, wp = 6, rz = 0.3 },
		{ u = 1 },
	},
	-- Birch Hatchet: the Machete's diagonal chop, with a higher follow-through so
	-- the long bearded head stays above the ground.
	Chop1H = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.95, 1.65, 0.2 }, dir = { 1, 0.95, 0.3 }, wy = -25, wp = -5 },
		{ u = 0.52, hand = { 0.7, 0.2, -1.4 }, dir = { -0.6, -0.2, -1 }, wy = 15, wp = 8, rz = 0.3 },
		{ u = 0.72, hand = { 0.1, -0.55, -0.95 }, dir = { -1, 0.05, -0.45 }, wy = 28, wp = 6 },
		{ u = 1 },
	},
	-- Pinecone Staff: a right-handed sweep (user, 2026-10-11). Both hands keep the
	-- staff level across the front of the body, and the BODY turns: wound up to the
	-- right with the head out behind on the right, then one sweep round the front to the
	-- left. The staff never turns inside the body's frame, so its 3.8-stud butt stays
	-- in front of the body the whole way (it used to cut through the torso).
	StaffSweep = {
		{ u = 0 },
		{ u = 0.25, hand = { 1.2, -0.4, -0.9 }, dir = { 1, 0.15, 0.35 }, two = 1, off = -1.6, ry = -40, wp = -2 },
		{ u = 0.66, hand = { 1.0, -0.45, -1.35 }, dir = { 1, 0.06, -0.25 }, two = 1, off = -1.6, ry = 100, wp = 5 },
		{ u = 0.82, hand = { 1.0, -0.47, -1.32 }, dir = { 1, 0.05, -0.25 }, two = 1, off = -1.6, ry = 97, wp = 4 },
		{ u = 1 },
	},
	-- Lumberjack's Splitter (2H): the hands stack on the haft (left just behind the
	-- right, off = -0.55) so both can follow it overhead and down; one chop that
	-- stops with the lower bit clear of the ground (the head reaches 1.6 either side).
	-- The lift goes STRAIGHT UP, out in front-right of the face (user, 2026-10-11): it
	-- used to tip the head back over the shoulder, which swung it through the face and
	-- twisted the right arm.
	Chop2H = {
		{ u = 0, off = 1.9 },
		LIFT_FREE_2H,
		{ u = 0.36, hand = LIFT_HAND, dir = LIFT_DIR, two = 1, off = -0.55, wy = -10, wp = -6, ease = "out" },
		{ u = 0.6, hand = { 0.55, 0.3, -1.45 }, dir = { -0.02, -0.1, -1 }, two = 1, off = -0.55, wp = 8, rz = 0.4, ease = "out" },
		{ u = 0.78, hand = { 0.55, 0.26, -1.42 }, dir = { -0.02, -0.12, -1 }, two = 1, off = -0.55, wp = 7, rz = 0.3 },
		-- back to the hold: the left hand lets go (it can't slide past the right one
		-- along the haft) while the head comes up in front, and re-grips at the hold
		RECOVER_2H,
		{ u = 1, off = 1.9, ease = "out" },
	},
	-- Gold Gauntlets: a one-two. The right fist pulls back and punches straight out
	-- (the hit), then the left fist punches as the right comes back, the body twisting
	-- into each.
	Punch = {
		{ u = 0 },
		{ u = 0.16, hand = { 1.35, 1.55, -0.75 }, wy = -14 },
		{ u = 0.36, hand = { 0.45, 0.7, -1.6 }, left = { -1.0, 1.3, -1.05 }, wy = 22, wp = 6, rz = 0.35, ease = "out" },
		{ u = 0.5, hand = { 1.0, 1.3, -1.05 }, left = { -1.35, 1.55, -0.75 }, wy = 8, wp = 3 },
		{ u = 0.66, hand = { 1.0, 1.3, -1.05 }, left = { -0.45, 0.7, -1.6 }, wy = -20, wp = 6, rz = 0.3, ease = "out" },
		{ u = 1 },
	},
	-- Batwing Blade: the Hook turned over so the jagged scalloped edge (-Y) leads the cut
	-- across the body instead of the bone spine (user, 2026-10-13)
	HookEdge = {
		{ u = 0 },
		{ u = 0.3, hand = { 2.45, 0.25, 0.35 }, dir = { 0.7, 0, -0.7 }, roll = -90, wy = -30 },
		{ u = HOOK_MID, hand = { 0.75, 0.15, -1.45 }, dir = { -0.2, 0, -1 }, roll = -90, wy = 8, wp = 6, rz = 0.2, ease = "in" },
		{ u = 0.7, hand = { -0.35, 0.05, -0.95 }, dir = { -1, 0, -0.35 }, roll = -90, wy = 35, wp = 6, ease = "out" },
		{ u = 1 },
	},
	-- Iron / Diamond Pickaxe: a mining swing (user, 2026-10-13). Raised high with the head
	-- tipped back over the shoulder, then driven straight down in front so the point (-Y)
	-- bites down into the rock, held a beat, then back.
	Mine = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.1, 2.0, 0.05 }, dir = { 0.02, 0.85, 0.5 }, wp = -9 },
		{ u = 0.58, hand = { 0.95, -0.25, -1.45 }, dir = { 0, -0.45, -1 }, wp = 14, rz = 0.35, ease = "out" },
		{ u = 0.76, hand = { 0.95, -0.3, -1.42 }, dir = { 0, -0.48, -1 }, wp = 12, rz = 0.3 },
		{ u = 1 },
	},
	-- Diamond Pickaxe: the same mining swing, stopping a little higher and less steep for
	-- its 1.5x longer head (the point otherwise went 0.4 into the ground)
	MineLong = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.1, 2.0, 0.05 }, dir = { 0.02, 0.85, 0.5 }, wp = -9 },
		{ u = 0.58, hand = { 0.95, 0.05, -1.45 }, dir = { 0, -0.36, -1 }, wp = 12, rz = 0.35, ease = "out" },
		{ u = 0.76, hand = { 0.95, 0.0, -1.42 }, dir = { 0, -0.38, -1 }, wp = 10, rz = 0.3 },
		{ u = 1 },
	},
	-- Rock Candy Club: the Machete's diagonal with a higher follow-through for the long candy
	DiagonalLong = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.95, 1.65, 0.2 }, dir = { 1, 0.95, 0.3 }, wy = -25, wp = -5 },
		{ u = 0.52, hand = { 0.7, 0.2, -1.4 }, dir = { -0.6, -0.2, -1 }, wy = 15, wp = 8, rz = 0.3 },
		{ u = 0.72, hand = { 0.05, -0.65, -0.85 }, dir = { -1, -0.1, -0.5 }, wy = 30, wp = 8 },
		{ u = 1 },
	},
	-- Worldheart Blade (9 studs, 2026-10-15): the Machete's diagonal, levelled out on the
	-- follow-through so the long blade sweeps across in front instead of into the ground
	DiagonalHuge = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.95, 1.65, 0.2 }, dir = { 1, 0.95, 0.3 }, wy = -25, wp = -5 },
		{ u = 0.52, hand = { 0.7, 0.25, -1.4 }, dir = { -0.6, -0.1, -1 }, wy = 15, wp = 6, rz = 0.3 },
		{ u = 0.72, hand = { 0.1, -0.4, -0.95 }, dir = { -1, 0.1, -0.45 }, wy = 28, wp = 5 },
		{ u = 1 },
	},
	-- Geode Glaive: the Pinecone Staff's sweep with the left hand on the glaive's lower wrap
	GlaiveSweep = {
		{ u = 0 },
		{ u = 0.25, hand = { 1.2, -0.4, -0.9 }, dir = { 1, 0.15, 0.35 }, two = 1, off = -1.9, ry = -40, wp = -2 },
		{ u = 0.66, hand = { 1.0, -0.45, -1.35 }, dir = { 1, 0.06, -0.25 }, two = 1, off = -1.9, ry = 100, wp = 5 },
		{ u = 0.82, hand = { 1.0, -0.47, -1.32 }, dir = { 1, 0.05, -0.25 }, two = 1, off = -1.9, ry = 97, wp = 4 },
		{ u = 1 },
	},
	-- Boulder Club (2H): the same lift, slammed down until the boulder just meets
	-- the ground (the def's impact = "Slam" throws the dust ring there).
	Slam2H = {
		{ u = 0, off = 1.9 },
		LIFT_FREE_2H,
		{ u = 0.36, hand = LIFT_HAND, dir = LIFT_DIR, two = 1, off = -0.55, wy = -10, wp = -6, ease = "out" },
		{ u = 0.6, hand = { 0.55, 0.0, -1.45 }, dir = { -0.02, -0.25, -1 }, two = 1, off = -0.55, wp = 8, rz = 0.4, ease = "out" },
		{ u = 0.78, hand = { 0.55, -0.02, -1.42 }, dir = { -0.02, -0.26, -1 }, two = 1, off = -0.55, wp = 7, rz = 0.3 },
		RECOVER_2H,
		{ u = 1, off = 1.9, ease = "out" },
	},
	-- ==================== fishing (Config/Fishing, 2026-10-18) ====================
	-- The cast: the left hand comes onto the cork behind the right (off -0.55, toward the
	-- butt), both hands take the rod back over the head with a lean back, then whip it
	-- forward; the line is let go at the "Hit" marker (the rod's hitTime, 0.56), with the
	-- rod tip still high so the bobber flies out in an arc. The left hand lets go on the way
	-- back to the one-handed hold.
	Cast = {
		{ u = 0 },
		{ u = 0.14, hand = { 0.3, -0.2, -1.2 }, dir = { 0, 0.7, -1 }, two = 1, off = -0.55 },
		{ u = 0.4, hand = { 0.1, 1.8, -0.55 }, dir = { 0.05, 0.6, 0.8 }, two = 1, off = -0.55, wy = -8, wp = -7 },
		{ u = 0.56, hand = { 0.2, 1.0, -1.35 }, dir = { 0, 0.5, -1 }, two = 1, off = -0.55, wy = 4, wp = 8, ease = "out" },
		{ u = 0.72, hand = { 0.3, 0.35, -1.45 }, dir = { 0, 0.1, -1 }, two = 1, off = -0.55, wy = 3, wp = 6, rz = 0.3 },
		{ u = 0.88, hand = { 0.9, -0.4, -1.0 }, dir = { 0, 0.35, -1 }, two = 0, off = -0.55 },
		{ u = 1 },
	},
	-- Landing a fish (FishingController plays it through WeaponClips.extra): both hands,
	-- the rod yanked up and back so the line pulls the fish out of the water.
	Reel = {
		{ u = 0 },
		{ u = 0.22, hand = { 0.3, -0.25, -1.2 }, dir = { 0, 0.3, -1 }, two = 1, off = -0.55, wp = 4 },
		{ u = 0.5, hand = { 0.25, 1.25, -0.95 }, dir = { 0, 1, 0.2 }, two = 1, off = -0.55, wp = -9, wy = -4, ease = "out" },
		{ u = 0.78, hand = { 0.3, 1.0, -1.05 }, dir = { 0, 1, 0.1 }, two = 1, off = -0.55, wp = -5 },
		{ u = 1 },
	},
} :: { [string]: { Key } }

-- ==================== the R6 solver ====================

-- R6 shoulders (StarterPlayer/StarterCharacter), and the palm in arm space.
local RS_C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local RS_C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local LS_C0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
local LS_C1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
local PALM = Vector3.new(0, -1, 0)
local SLIDE_MIN, SLIDE_MAX = -0.3, 0.4 -- how far a shoulder may move toward its target
local REST_RIGHT = (RS_C0 * RS_C1:Inverse()) * PALM
local REST_LEFT = (LS_C0 * LS_C1:Inverse()) * PALM

local rad = math.rad

local function fromTo(a: Vector3, b: Vector3): CFrame
	local d = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		if d > 0 then
			return CFrame.identity
		end
		local perp = if math.abs(a.X) < 0.9 then Vector3.xAxis else Vector3.zAxis
		return CFrame.fromAxisAngle(a:Cross(perp).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(d))
end

-- Point a straight arm at `target`. Returns the joint pose (torso frame, about
-- the shoulder), the arm part's CFrame in torso space, and how far off it lands.
local function reach(c0: CFrame, c1: CFrame, target: Vector3): (CFrame, CFrame, number)
	local joint = c0.Position
	local rest = (c0 * c1:Inverse()) * PALM - joint
	local length = rest.Magnitude
	local toTarget = target - joint
	local dist = toTarget.Magnitude
	local dir = if dist > 1e-4 then toTarget / dist else rest.Unit
	local slide = math.clamp(dist - length, SLIDE_MIN, SLIDE_MAX)
	local pose = CFrame.new(dir * slide) * fromTo(rest.Unit, dir)
	local arm = CFrame.new(joint) * pose * c0.Rotation * c1:Inverse()
	return pose, arm, math.abs(dist - length - slide)
end

local function vec(t: { number }?, fallback: Vector3): Vector3
	return if t then Vector3.new(t[1], t[2], t[3]) else fallback
end

-- Where the left hand sits on the weapon (in the Grip's space), from the model.
local offGripCache: { [string]: Vector3 } = {}
local function offGripOf(def: any): Vector3
	local cached = offGripCache[def.id]
	if cached then
		return cached
	end
	local point = Vector3.new(0, 0, -1.9)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Weapons")
	-- gathering tools (Config/Tools) keep their models in Assets/Tools
	local tools = assets and assets:FindFirstChild("Tools")
	local model = (folder and folder:FindFirstChild(def.id)) or (tools and tools:FindFirstChild(def.id))
	local grip = model and (model :: Model).PrimaryPart
	local attachment = grip and grip:FindFirstChild("OffGrip")
	if attachment and attachment:IsA("Attachment") then
		point = attachment.Position
	end
	offGripCache[def.id] = point
	return point
end

type Solved = { channels: { [string]: CFrame }, body: CFrame, rightErr: number, leftErr: number }

-- One flat pose -> joint channels.
local function solve(p: any, def: any): Solved
	local out: { [string]: CFrame } = {}
	local rightPose, arm, rightErr = reach(RS_C0, RS_C1, p.hand)
	out.RightShoulder = rightPose
	local grip = arm * CFrame.new(PALM)
	-- a worn weapon (gauntlets) stays lined up with the forearm: no turn in the hand
	if not def.unarmed and not def.worn then
		local aim = fromTo(Vector3.new(0, 0, -1), p.dir.Unit) * CFrame.Angles(0, 0, rad(p.roll))
		local turn = grip.Rotation:Inverse() * aim
		out.Grip = turn
		grip = grip * turn
	end
	local leftErr = 0
	if (def.handed or 1) >= 2 then
		-- Left hand on the shaft, sliding along it to the most reachable point.
		local off = offGripOf(def)
		local along = if p.off then p.off else -off.Z
		local function at(distance: number): Vector3
			return grip * Vector3.new(off.X, off.Y, -distance)
		end
		local shaftPose, _, err = reach(LS_C0, LS_C1, at(along))
		if not p.off and err > 0.1 then
			-- Slide either way along the shaft (on the scythe the left hand sits
			-- behind the right one, toward the butt).
			for d = along - 1.2, along + 1.2, 0.1 do
				local candidate, _, e = reach(LS_C0, LS_C1, at(d))
				if e < err - 0.02 then
					shaftPose, err = candidate, e
				end
			end
		end
		local freePose, _, freeErr = reach(LS_C0, LS_C1, p.left)
		out.LeftShoulder = freePose:Lerp(shaftPose, math.clamp(p.two, 0, 1))
		leftErr = if p.two > 0.5 then err else freeErr
	end
	local body = CFrame.new(0, 0, -p.rz) * CFrame.Angles(0, rad(p.ry + p.wy), 0) * CFrame.Angles(rad(-p.wp), 0, 0)
	return { channels = out, body = body, rightErr = rightErr, leftErr = leftErr }
end

-- A key (with hold fallbacks) -> a flat pose table.
local function flat(key: Key, hold: Key): any
	local function pick(name: string)
		local value = key[name]
		if value == nil then
			value = hold[name]
		end
		return value
	end
	return {
		hand = vec(pick("hand"), REST_RIGHT),
		dir = vec(pick("dir"), Vector3.new(0, 0.3, -1)),
		roll = pick("roll") or 0,
		two = pick("two") or 0,
		off = pick("off"),
		left = vec(pick("left"), REST_LEFT),
		wy = key.wy or 0,
		wp = key.wp or 0,
		ry = key.ry or 0,
		rz = key.rz or 0,
	}
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Hands blend AROUND their shoulder (direction and distance separately), so a
-- straight arm stays straight between keys instead of cutting in toward the
-- shoulder, which a rigid R6 arm can't follow.
local function around(joint: Vector3, a: Vector3, b: Vector3, t: number): Vector3
	local ra, rb = a - joint, b - joint
	local la, lb = ra.Magnitude, rb.Magnitude
	if la < 1e-4 or lb < 1e-4 then
		return a:Lerp(b, t)
	end
	local dir = (ra / la):Lerp(rb / lb, t)
	if dir.Magnitude < 1e-4 then
		return a:Lerp(b, t)
	end
	return joint + dir.Unit * (la + (lb - la) * t)
end

local function lerpFlat(a: any, b: any, t: number): any
	local function n(x: number, y: number): number
		return x + (y - x) * t
	end
	return {
		hand = around(RS_C0.Position, a.hand, b.hand, t),
		dir = a.dir.Unit:Lerp(b.dir.Unit, t),
		roll = n(a.roll, b.roll),
		two = n(a.two, b.two),
		off = if a.off and b.off then n(a.off, b.off) else (a.off or b.off),
		left = around(LS_C0.Position, a.left, b.left, t),
		wy = n(a.wy, b.wy),
		wp = n(a.wp, b.wp),
		ry = n(a.ry, b.ry),
		rz = n(a.rz, b.rz),
	}
end

local function sampleKeys(keys: { Key }, u: number, hold: Key): any
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if u >= keys[i].u and u <= keys[i + 1].u then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	local span = b.u - a.u
	local x = if span > 0 then math.clamp((u - a.u) / span, 0, 1) else 1
	local t = if b.ease == "out" then 1 - (1 - x) * (1 - x)
		elseif b.ease == "in" then x * x
		elseif b.ease == "linear" then x
		else smooth(x)
	return lerpFlat(flat(a, hold), flat(b, hold), t)
end

-- ==================== clips ====================

local SAMPLES = 32
local TRAIL_BEFORE, TRAIL_AFTER = 0.2, 0.18

local function holdOf(def: any): Key
	if def.unarmed then
		return {}
	end
	return Weapons.HOLDS[def.id] or { hand = { 1.5, -0.85, -0.3 }, dir = { 0, 0.3, -1 } }
end

local holdCache: { [string]: any } = {}
local swingCache: { [string]: any } = {}
local bodyCache: { [string]: any } = {}

function Weapons.hold(def: any): any
	if def.unarmed then
		return nil
	end
	local cached = holdCache[def.id]
	if cached then
		return cached
	end
	local hold = holdOf(def)
	local solved = solve(flat({}, hold), def)
	local joints = {}
	for joint, cf in solved.channels do
		-- A two-handed weapon carried in one hand leaves the left arm free (unless the
		-- hold places the left hand, like the gauntlets' guard).
		if joint == "LeftShoulder" and (hold.two or 0) <= 0 and not hold.left then
			continue
		end
		joints[joint] = { { t = 0, cf = cf } }
	end
	local clip = Clip.new({
		name = "Hold_" .. def.id,
		priority = "Hold",
		looped = true,
		length = 1,
		fadeIn = 0.15,
		fadeOut = 0.15,
		joints = joints,
	})
	holdCache[def.id] = clip
	return clip
end

-- Builds the arms and body clips of one swing: the def's own (`swing`), or another named
-- swing held the same way (`extra`, cached under "<id>/<swing>").
local function build(def: any, swingName: string?, hitAt: number?)
	local cacheKey = if swingName then def.id .. "/" .. swingName else def.id
	local keys = Weapons.SWINGS[swingName or def.swing] or { { u = 0 }, { u = 1 } }
	local hold = holdOf(def)
	local arms: { [string]: { any } } = {}
	local body: { any } = {}
	for i = 0, SAMPLES do
		local u = i / SAMPLES
		local solved = solve(sampleKeys(keys, u, hold), def)
		for joint, cf in solved.channels do
			arms[joint] = arms[joint] or {}
			table.insert(arms[joint], { t = u, cf = cf, ease = "Linear" })
		end
		table.insert(body, { t = u, cf = solved.body, ease = "Linear" })
	end
	local hit = hitAt or def.hitTime or 0.5
	swingCache[cacheKey] = Clip.new({
		name = "Swing_" .. cacheKey,
		priority = "Action",
		length = 1,
		fadeIn = 0.04,
		fadeOut = 0.1,
		joints = arms,
		markers = {
			{ t = math.max(0, hit - TRAIL_BEFORE), name = "TrailOn" },
			{ t = hit, name = "Hit" },
			{ t = math.min(1, hit + TRAIL_AFTER), name = "TrailOff" },
		},
	})
	bodyCache[cacheKey] = Clip.new({
		name = "SwingBody_" .. cacheKey,
		priority = "Action",
		additive = true,
		length = 1,
		fadeIn = 0.04,
		fadeOut = 0.1,
		joints = { Root = body },
	})
end

function Weapons.swing(def: any): any
	if not swingCache[def.id] then
		build(def)
	end
	return swingCache[def.id]
end

function Weapons.swingBody(def: any): any
	if not bodyCache[def.id] then
		build(def)
	end
	return bodyCache[def.id]
end

-- Another swing in SWINGS played with this def's hold and hands (the rod's Reel): the arms
-- clip and its additive body clip, a "Hit" marker at `hitAt` (default 0.5).
function Weapons.extra(def: any, swingName: string, hitAt: number?): (any, any)
	local key = def.id .. "/" .. swingName
	if not swingCache[key] then
		build(def, swingName, hitAt)
	end
	return swingCache[key], bodyCache[key]
end

-- The pose at one point of a swing (u) or the hold (u = nil), solved: channel
-- CFrames plus the body pose -- for previews and tests.
function Weapons.pose(def: any, u: number?): Solved
	local hold = holdOf(def)
	if u == nil then
		return solve(flat({}, hold), def)
	end
	return solve(sampleKeys(Weapons.SWINGS[def.swing] or { { u = 0 }, { u = 1 } }, u, hold), def)
end

-- Worst reach error (studs) for each hand across the hold and the swing, and
-- the swing fraction where each happens (-1 = the hold).
function Weapons.report(def: any): (number, number, number, number)
	local right, left, rightAt, leftAt = 0, 0, 0, 0
	for i = -1, SAMPLES do
		local u = if i < 0 then nil else i / SAMPLES
		local solved = Weapons.pose(def, u)
		if solved.rightErr > right then
			right, rightAt = solved.rightErr, u or -1
		end
		if solved.leftErr > left then
			left, leftAt = solved.leftErr, u or -1
		end
	end
	return right, left, rightAt, leftAt
end

return Weapons
