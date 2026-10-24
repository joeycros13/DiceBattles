"""World run simulation: how long a player takes to reach the next world.

Plays one player from spawning to buying the next world's gate, many times
with random drops, and reports how long it took. Two goals:

--goal gate (the default since 2026-10-20, the user's target: a typical free player buys
the World 2 gate in 30 minutes or more): the run ends the moment the gate is bought. The
player still plays normally on the way: Dale's steps as they come, the tools, both armour
sets when it has the level and materials, any weapon that drops, and a shop weapon whenever
it can afford one that hits harder per second than its best. It never chases a drop-only
weapon (the Mace) or anything else only for completion.

--goal all (the 2026-10-19 measure): the gate only once the world is finished:
  * every weapon of the world except secrets (drops, shop buys, the quest reward)
  * every armour set of the world, crafted
  * the world's whole questline
  * the gathering tools the world needs (axe, pickaxe; the rod only with --rod)
  * the gate: its level, coins and materials
Left out on purpose (the user's rule, 2026-10-19): game passes, boosts and luck,
potions (drinking and brewing), the secret weapon and the secret core, and the
secret enemy.

World 2 and later start where a typical player arrives (--from 1, 2026-10-20): the previous
world's weapons and armour are loaded so the carried gear works (--start-weapons, --start-armor,
--start-wear, --start-level, --start-coins; the defaults are World 1's gate-goal result: level 25,
about 1,000 coins, the Weathervane Spear, Harvest Knight worn).

--upgrades N (2026-10-20, the user's base for World 2: arriving with World 1's upgrades maxed):
the Health, Defense, Attack and Attack Speed upgrades at level N (Config/Upgrades steps: +5% max
HP, -1% damage taken, +3% damage, -1.5% swing time a level). Off (0) by default: upgrades are
outside a world's run.

Every game number comes from world<N>.json, which dump_world.luau writes from
the real configs and the map in Studio. Only the player's behaviour is assumed;
those numbers are in PLAYER below.

  py world_sim.py                     # World 1, 2,000 runs
  py world_sim.py --runs 5000 --seed 3
  py world_sim.py --set boss.PumpkinMace=0.05 --set gate.coins=2000   # try changes
  py world_sim.py --trace             # one run, step by step
"""
import argparse, json, math, random, statistics, sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).parent

# ---------------------------------------------------------------------------
# The player: the only numbers here that aren't the game's.
PLAYER = {
    "detour": 1.3,           # walking routes vs a straight line (paths, hills, fences)
    "sprint": False,         # no base sprint since 2026-10-19 (an upgrade, outside the run)
    "hitRate": 0.85,         # share of swings that land (misses, enemies wandering)
    "critChance": 0.10,      # Balance.Melee.critChance: a landed hit is a crit this often
    "critMultiplier": 1.5,   # Balance.Melee.critMultiplier: and deals this times its damage
    "engageSeconds": 1.0,    # lining up the first swing once in range
    "talkSeconds": 15,       # one Dale visit: hand in, read, take the next step
    "shopSeconds": 8,        # one visit to a stall (open, pick, buy)
    "regen": 0.01,           # Roblox's default Health script: 1% of max HP per second
    "restMargin": 1.5,       # rest before a fight until HP is this times what it should take (fights vary:
                             # since 2026-10-24 a small enemy takes ~50%, two or three hits, so a real
                             # player tops up first; 1.1 until then, when deaths were rare anyway)
    "replanEvery": 4,        # kills between rethinking what to farm
    "closeEnough": 0.10,     # activities paying within this share of the best are equal: the nearest wins
    "tooStrong": 0.7,        # skip a fight that would take this share of max HP: get stronger first
                             # (0.9 until 2026-10-24; with ~50% small-enemy fights a player backs off sooner)
}


def load(world):
    data = json.load(open(HERE / f"world{world}.json", encoding="utf-8"))
    # Luau's JSONEncode writes an empty table as [] (World 2 has no gathering or tools yet)
    for k in ("gathering", "tools", "armor", "weapons"):
        if isinstance(data.get(k), list):
            data[k] = {}
    return data


def listify(t):
    """JSON from Luau keeps arrays as {"1": .., "2": ..}."""
    if isinstance(t, dict) and all(k.isdigit() for k in t):
        return [t[k] for k in sorted(t, key=int)]
    return t or []


def dist(a, b):
    return math.hypot(a[0] - b[0], a[2] - b[2])


# ---------------------------------------------------------------------------
class World:
    def __init__(self, data, rod=False, goal="gate"):
        self.d = data
        self.goal = goal
        cfg = data["config"]
        self.enemies = {}
        for group, boss in ((cfg["enemies"], False), (cfg["bosses"], True)):
            for eid, e in group.items():
                if e.get("secret"):
                    continue  # the secret enemy is outside the run
                e = dict(e)
                e["boss"] = boss
                e["drops"] = [x for x in listify(e.get("drops")) if not self.secret_weapon(x["weapon"])]
                e["materials"] = [x for x in listify(e.get("materials"))]
                self.enemies[eid] = e
        times = cfg.get("respawn") or {}
        self.respawn = {}
        for eid, e in self.enemies.items():
            self.respawn[eid] = times.get("boss" if e["boss"] else e.get("tier", ""), 30 if e["boss"] else 20)
        self.markers = {}
        for m in data["map"]["markers"]:
            if m["archetype"] in self.enemies:
                self.markers.setdefault(m["archetype"], []).append(m)
        self.nodes = {}
        for n in data["map"]["nodes"]:
            self.nodes.setdefault(n["node"], []).append(n["pos"])
        self.gather = {gid: dict(g, drops=listify(g["drops"])) for gid, g in data["gathering"].items()}
        self.places = data["map"]["places"]
        self.healZones = data["map"].get("healZones", [])
        self.weapons = {w: v for w, v in data["weapons"].items()}
        self.tools = data["tools"]
        self.armor = {a: dict(v, recipe=listify(v["recipe"])) for a, v in data["armor"].items()}
        self.gate = dict(data["gate"], materials=listify(data["gate"].get("materials")))
        self.quest = [data["quest"]["steps"][k] for k in sorted(data["quest"]["steps"], key=int)]
        for s in self.quest:
            if "items" in s:
                s["items"] = listify(s["items"])
        self.lv = data["leveling"]
        self.speed = data["walkSpeed"] * (data["balance"]["sprint"] if PLAYER["sprint"] else 1)
        self.respawnTime = data["respawnTime"]
        # the goals
        # every weapon a player can collect here (reported either way); only --goal all needs them
        self.allWeapons = {w for w, v in self.weapons.items() if self.counts(v)}
        self.needWeapons = set(self.allWeapons) if goal == "all" else set()
        self.needTools = {t for t, v in self.tools.items() if v["kind"] in ("Axe", "Pickaxe") or (rod and v["kind"] == "Rod")}
        # A tool made from the one before it (World 2's stone tools, 2026-10-20) also needs
        # materials. Only this world's count: the older tool and the older world's gathered
        # materials are carried in from the last world.
        here = {x["id"] for e in self.enemies.values() for x in e["materials"]}
        here |= {x["id"] for g in self.gather.values() for x in g["drops"]}
        self.toolRecipe = {}
        for t, v in self.tools.items():
            r = (v.get("recipe") or {}).get("materials") or {}
            self.toolRecipe[t] = [x for x in listify(r) if x["id"] in here]

    def secret_weapon(self, wid):
        w = self.d["weapons"].get(wid, {})
        return bool(w.get("secret")) or w.get("rarity") in ("Secret", "Relic", "Transcendent")

    def counts(self, w):
        # every weapon a player collects in this world, minus the starter, secrets and carried gear
        return not w.get("starter") and not w.get("carried") and not self.secret_weapon(w["id"])

    # level curve
    def scale_at(self, level):
        """Leveling.scaleAt: the world scale from each gate's level on (2026-10-23)."""
        m = 1
        for at, mult in self.lv.get("scale", []):
            if level >= at:
                m = mult
        return m

    def need(self, level):
        if self.lv.get("growth"):
            # Leveling since 2026-10-24: x10 every 25 levels (a world), each level a share more
            return math.floor(self.lv["first"] * self.lv["growth"] ** (level - self.lv["start"]) + 0.5)
        return (self.lv["first"] + self.lv["step"] * (level - self.lv["start"])) * self.scale_at(level)

    def level_of(self, total):
        level, left = self.lv["start"], total
        while left >= self.need(level):
            left -= self.need(level)
            level += 1
        return level

    def exp_for(self, level):
        return sum(self.need(l) for l in range(self.lv["start"], level))

    def max_hp(self, level, armor):
        if self.lv.get("growth"):
            base = math.floor(self.lv["baseHealth"] * self.lv["growth"] ** (level - self.lv["start"]) + 0.5)
        else:
            base = (self.lv["baseHealth"] + self.lv["healthPerLevel"] * (level - self.lv["start"])) * self.scale_at(level)
        return base + (self.armor[armor]["health"] if armor else 0)


# ---------------------------------------------------------------------------
START = {}
# upgrade levels, --upgrades N (every upgrade at N since 2026-10-24: the base player arrives maxed;
# it was only Health, Defense, Attack and Attack Speed). Config/Upgrades steps a level.
UPG = {"health": 0, "defense": 0, "attack": 0, "speed": 0, "critChance": 0, "critDamage": 0,
       "regen": 0, "coins": 0, "exp": 0, "luck": 0, "gathering": 0, "sprint": 0}
UPG_STEP = {"health": 0.05, "defense": -0.01, "attack": 0.03, "speed": -0.015, "critChance": 0.01, "critDamage": 0.05,
            "regen": 0.0015, "coins": 0.04, "exp": 0.04, "luck": 0.05, "gathering": 0.01, "sprint": 0.04}


def upg(name):
    return 1 + UPG_STEP[name] * UPG[name]


def crit():
    """(chance, multiplier) with the Crit upgrades."""
    return (PLAYER["critChance"] + UPG_STEP["critChance"] * UPG["critChance"],
            PLAYER["critMultiplier"] + UPG_STEP["critDamage"] * UPG["critDamage"])


def lucky(chance):
    return min(1.0, chance * upg("luck"))


class Run:
    def __init__(self, world, rng, overrides=None, trace=False):
        self.w, self.rng, self.trace_on = world, rng, trace
        self.t = 0.0
        self.probe = {"kill": {}, "step": {}, "wear": {}}  # levels things happen at (--probe)
        self.pos = list(world.places["spawn"])
        self.coins = 0
        self.exp = 0
        self.mats = {}
        self.weapons = {w for w, v in world.weapons.items() if v.get("starter")}
        self.tools = set()
        self.armor = set()
        self.wearing = None
        self.hp = world.max_hp(1, None)
        self.step = 0              # quest step index; len(quest) = done
        self.accepted = False      # the current step has been taken from the giver
        self.progress = 0
        self.gateDone = False
        self.dead = {}             # (archetype, marker index) -> time it comes back
        self.nodeDown = {}         # (node kind, index) -> time it stands again
        self.log = {}              # seconds spent per activity
        self.deaths = 0
        self.rests = 0.0
        self.got = {}              # weapon -> (time, how)
        self.zoneReady = 0.0       # when a heal zone (the fountain) can heal again
        self.fountainUses = 0
        self.earlyDeaths = 0
        self.earlyRest = 0.0
        self.levelHeals = 0
        self.fights = []           # (time, enemy, share of max HP it took)
        self.kills = {}
        if START:
            self.weapons |= set(START.get("weapons", []))
            self.armor |= set(START.get("armor", []))
            self.wearing = START.get("wear") or self.wearing
            self.exp = world.exp_for(START.get("level", 1))
            self.coins = START.get("coins", 0)
            self.hp = self.maxhp()

    # --- helpers -----------------------------------------------------------
    def say(self, *a):
        if self.trace_on:
            print("%6.1f min  %s" % (self.t / 60, " ".join(str(x) for x in a)))

    def spend(self, what, seconds):
        self.t += seconds
        self.log[what] = self.log.get(what, 0) + seconds
        if self.wearing:  # --probe: time worn at each level
            h = self.probe["wear"].setdefault(self.wearing, {})
            lv = self.level()
            h[lv] = h.get(lv, 0) + seconds
        # regen while doing anything
        self.hp = min(self.maxhp(), self.hp + self.maxhp() * self.regen() * seconds)

    def level(self):
        return self.w.level_of(self.exp)

    def worn(self, key):
        """An armour bonus of the set worn (Config/Armor regen / speed), 0 without one."""
        return self.w.armor[self.wearing].get(key, 0) if self.wearing else 0

    def regen(self):
        """Share of max HP healed a second: Roblox's 1%, the set's regen, the Regen upgrade."""
        return PLAYER["regen"] + self.worn("regen") + UPG_STEP["regen"] * UPG["regen"]

    def spd(self):
        # walk speed x (1 + armour speed), capped like Armor.MAX_SPEED (Swiftness is outside the run);
        # with the Sprint upgrade the player sprints everywhere (Bonuses.speed adds its share)
        boost = min(self.worn("speed"), 0.5)
        if UPG["sprint"] > 0:
            boost += 0.16 + UPG_STEP["sprint"] * UPG["sprint"]
        return self.w.speed * (1 + boost)

    def maxhp(self):
        return self.w.max_hp(self.level(), self.wearing) * upg("health")

    def walk(self, to, what="walking"):
        seconds = dist(self.pos, to) * PLAYER["detour"] / self.spd()
        self.spend(what, seconds)
        self.pos = list(to)

    def defense(self):
        return self.w.armor[self.wearing]["defense"] if self.wearing else 0.0

    def add_exp(self, n):
        before = self.level()
        self.exp += n
        if self.level() > before:
            # a level up heals to full (ExpService)
            self.hp = self.maxhp()
            self.levelHeals += 1

    # --- combat ------------------------------------------------------------
    def dps(self, wid):
        v = self.w.weapons[wid]
        return v["damage"] * upg("attack") / (v["cooldown"] * upg("speed"))

    def best_dps(self):
        return max(self.dps(x) for x in self.weapons)

    def upgrades(self):
        """Shop weapons not owned that hit harder per second than the best one held."""
        best = self.best_dps()
        return sorted((x for x, v in self.w.weapons.items() if v.get("price") and not v.get("carried") and x not in self.weapons
                       and not self.w.secret_weapon(x) and self.dps(x) > best), key=lambda x: self.w.weapons[x]["price"])

    def best_weapon(self, enemy):
        e = self.w.enemies[enemy]
        armor = e["melee"].get("armor", 0)
        best = None
        for wid in self.weapons:
            v = self.w.weapons[wid]
            per = v["damage"] * upg("attack") * (1 - (0 if v.get("ignoreArmor") else armor))
            chance, mult = crit()
            per *= 1 + chance * (mult - 1)  # crits on average
            hits = math.ceil(e["hp"] / per)
            ttk = (v["hitTime"] + (hits - 1) * v["cooldown"] / PLAYER["hitRate"]) * upg("speed")
            if best is None or ttk < best[1]:
                best = (wid, ttk)
        return best[0]

    def fight(self, enemy, weapon, dry=False):
        """One fight, hit by hit. Returns (seconds, damage taken)."""
        e = self.w.enemies[enemy]
        m = e["melee"]
        v = self.w.weapons[weapon]
        per = v["damage"] * upg("attack") * (1 - (0 if v.get("ignoreArmor") else m.get("armor", 0)))
        cooldown = v["cooldown"] * upg("speed")
        hp = e["hp"]
        rng = self.rng if not dry else random.Random(1)
        t = PLAYER["engageSeconds"] + v["hitTime"] * upg("speed")
        first_hit = None
        knocks = []           # times the enemy was knocked back
        chance, mult = crit()
        while True:
            if rng.random() < PLAYER["hitRate"]:
                hp -= per * (mult if rng.random() < chance else 1)
                if first_hit is None:
                    first_hit = t
                knocks.append(t)
                if hp <= 1e-6:
                    break
            t += cooldown
        end = t
        # the enemy fights back from its first hit until it dies
        taken = 0
        if first_hit is not None:
            na = first_hit + 0.5   # FIRST_ATTACK_DELAY
            back = v.get("knockback", 0) / max(1, m["chaseSpeed"])
            while na + m["windup"] < end:
                # a knockback puts it out of reach for a moment
                pushed = [k for k in knocks if k <= na and k + back > na]
                if pushed:
                    na = pushed[-1] + back
                    continue
                lands = na + m["windup"]
                # knocked out of reach during the windup: the attack misses
                missed = v.get("knockback", 0) >= 3 and any(na < k < lands for k in knocks)
                if not missed:
                    taken += max(1, math.floor(m["damage"] * (1 - self.defense()) * upg("defense") + 0.5))
                na += m["cooldown"]
        return end, taken

    def use_fountain(self, markers, rest_seconds):
        """Heal at a heal zone instead of resting, if the detour is quicker."""
        if not self.w.healZones:
            return False
        target = min(markers, key=lambda m: dist(self.pos, m["pos"]))["pos"]
        best = None
        for z in self.w.healZones:
            go = dist(self.pos, z["pos"]) * PLAYER["detour"] / self.spd()
            back = dist(z["pos"], target) * PLAYER["detour"] / self.spd()
            direct = dist(self.pos, target) * PLAYER["detour"] / self.spd()
            wait = max(0, self.zoneReady - (self.t + go))
            extra = go + wait + back - direct
            if best is None or extra < best[0]:
                best = (extra, z, wait)
        extra, z, wait = best
        if extra >= rest_seconds:
            return False
        self.walk(z["pos"], "walking to the fountain")
        if wait > 0:
            self.spend("waiting for the fountain", wait)
        self.hp = self.maxhp()
        self.zoneReady = self.t + z["cooldown"]
        self.fountainUses += 1
        return True

    def beatable(self, enemy):
        _, expect = self.fight(enemy, self.best_weapon(enemy), dry=True)
        return expect < self.maxhp() * PLAYER["tooStrong"]

    def kill(self, enemy):
        """Walk to the nearest living one, (rest if needed), fight it, collect."""
        w = self.w
        markers = w.markers[enemy]
        weapon = self.best_weapon(enemy)
        # resting first if this fight would kill us
        _, expect = self.fight(enemy, weapon, dry=True)
        want = min(self.maxhp(), expect * PLAYER["restMargin"])
        if self.hp < want and expect < self.maxhp():
            need = (want - self.hp) / (self.maxhp() * self.regen())
            if need > 0 and not self.use_fountain(markers, need):
                self.rests += need
                if self.t < 600:
                    self.earlyRest += need
                self.spend("resting", need)
        # pick a target: the nearest one alive, or the next to come back
        best = None
        for i, m in enumerate(markers):
            ready = self.dead.get((enemy, i), 0)
            arrive = self.t + dist(self.pos, m["pos"]) * PLAYER["detour"] / self.spd()
            when = max(arrive, ready)
            if best is None or when < best[0]:
                best = (when, i, m)
        when, i, m = best
        self.walk(m["pos"], "walking")
        if when > self.t:
            self.spend("waiting for respawns", when - self.t)
        seconds, taken = self.fight(enemy, weapon)
        if taken >= self.hp:
            # died partway: respawn at the plaza, walk back, the enemy is back to full
            self.deaths += 1
            if self.t < 600:
                self.earlyDeaths += 1
            self.spend("fighting " + enemy, seconds * (self.hp / max(1, taken)))
            self.spend("dying", w.respawnTime)
            self.pos = list(w.places["spawn"])
            self.hp = self.maxhp()
            return False
        self.fights.append((self.t, enemy, taken / self.maxhp()))
        self.hp -= taken
        self.spend("fighting " + enemy, seconds)
        self.dead[(enemy, i)] = self.t + w.respawn[enemy]
        e = w.enemies[enemy]
        self.kills[enemy] = self.kills.get(enemy, 0) + 1
        h = self.probe["kill"].setdefault(enemy, {})
        h[self.level()] = h.get(self.level(), 0) + 1
        got = round(self.rng.randint(e["coins"]["min"], e["coins"]["max"]) * upg("coins"))
        self.coins += got
        if self.accepted and self.cur() and self.cur()["kind"] == "earn":
            self.progress += got
        self.add_exp(round(e.get("exp", 0) * upg("exp")))
        for x in e["materials"]:
            if self.rng.random() < lucky(x["chance"]):
                n = self.rng.randint(x["min"], max(x["min"], x["max"]))
                self.mats[x["id"]] = self.mats.get(x["id"], 0) + n
                c = self.cur()
                if self.accepted and c and c["kind"] == "gather" and c["target"] == x["id"]:
                    self.progress += n
        for x in e["drops"]:
            if x["weapon"] not in self.weapons and self.rng.random() < lucky(x["chance"]):
                self.weapons.add(x["weapon"])
                self.got[x["weapon"]] = (self.t, "dropped by " + enemy)
                self.say("drop!", x["weapon"], "from", enemy)
        if self.accepted and self.cur() and self.cur()["kind"] == "kill" and self.cur()["target"] == enemy:
            self.progress += 1
        return True

    def gather_one(self, kind):
        """Break the nearest standing node of this kind with the best tool."""
        w = self.w
        g = w.gather[kind]
        tool = next((t for t in self.tools if w.tools[t]["kind"] == g["tool"]), None)
        if tool is None:
            return False
        tv = w.tools[tool]
        best = None
        for i, p in enumerate(w.nodes[kind]):
            up = self.nodeDown.get((kind, i), 0)
            arrive = self.t + dist(self.pos, p) * PLAYER["detour"] / self.spd()
            when = max(arrive, up)
            if best is None or when < best[0]:
                best = (when, i, p)
        when, i, p = best
        self.walk(p, "walking")
        if when > self.t:
            self.spend("waiting for nodes", when - self.t)
        hits = math.ceil(g["hp"] / tv["power"])
        swings = 0
        landed = 0
        while landed < hits:
            swings += 1
            if self.rng.random() < 0.95:   # a standing node is easy to hit
                landed += 1
        self.spend("gathering", PLAYER["engageSeconds"] + tv["hitTime"] + (swings - 1) * tv["cooldown"])
        self.nodeDown[(kind, i)] = self.t + g["respawn"]
        for x in g["drops"]:
            if self.rng.random() < x["chance"]:
                n = self.rng.randint(x["min"], max(x["min"], x["max"]))
                if self.rng.random() < UPG_STEP["gathering"] * UPG["gathering"]:
                    n *= 2  # the Gathering upgrade doubles a drop
                self.mats[x["id"]] = self.mats.get(x["id"], 0) + n
                c = self.cur()
                if self.accepted and c and c["kind"] == "gather" and c["target"] == x["id"]:
                    self.progress += n
        return True

    # --- the quest ---------------------------------------------------------
    def cur(self):
        return self.w.quest[self.step] if self.step < len(self.w.quest) else None

    def step_ready(self):
        c = self.cur()
        if not c or not self.accepted:
            return False
        k = c["kind"]
        if k in ("kill", "gather"):
            return self.progress >= c["count"]
        if k == "level":
            return self.level() >= c["level"]
        if k == "bring":
            return all(self.mats.get(x["id"], 0) >= x["count"] for x in c["items"])
        if k in ("earn",):
            return self.progress >= c.get("count", c.get("amount", 0))
        if k == "give":
            return self.coins >= c.get("count", c.get("amount", 0))
        return True

    def visit_giver(self):
        """Hand in what's ready and take the next step (one conversation)."""
        self.walk(self.w.places["questGiver"], "walking")
        self.spend("talking", PLAYER["talkSeconds"])
        while True:
            c = self.cur()
            if c is None:
                return
            if not self.accepted:
                self.accepted, self.progress = True, 0
                self.say("quest step", self.step + 1, "accepted:", c["kind"], c.get("target", c.get("level", "")))
                if not self.step_ready():
                    return
            if not self.step_ready():
                return
            if c["kind"] == "bring":
                for x in c["items"]:
                    self.mats[x["id"]] -= x["count"]
            if c["kind"] == "give":
                self.coins -= c.get("count", c.get("amount", 0))
            r = c.get("reward", {})
            self.probe["step"].setdefault(str(self.step + 1), {}).setdefault(self.level(), 0)
            self.probe["step"][str(self.step + 1)][self.level()] += 1
            self.coins += r.get("coins", 0)
            self.add_exp(r.get("exp", 0))
            if r.get("item"):
                self.mats[r["item"]] = self.mats.get(r["item"], 0) + 1
            if r.get("weapon") and not self.w.secret_weapon(r["weapon"]):
                self.weapons.add(r["weapon"])
                self.got[r["weapon"]] = (self.t, "quest reward")
            self.say("quest step", self.step + 1, "done")
            self.step += 1
            self.accepted = False

    # --- what is still needed ------------------------------------------------
    def mat_needs(self):
        """Materials still to collect for everything left (armour, quest, gate)."""
        need = {}
        for a, v in self.w.armor.items():
            if a not in self.armor:
                for x in v["recipe"]:
                    need[x["id"]] = need.get(x["id"], 0) + x["count"]
        for s in self.w.quest[self.step:]:
            for x in s.get("items", []):
                need[x["id"]] = need.get(x["id"], 0) + x["count"]
        if not self.gateDone:
            for x in self.w.gate["materials"]:
                need[x["id"]] = need.get(x["id"], 0) + x["count"]
        for t in self.w.needTools - self.tools:
            for x in self.w.toolRecipe[t]:
                need[x["id"]] = need.get(x["id"], 0) + x["count"]
        return {k: max(0, n - self.mats.get(k, 0)) for k, n in need.items()}

    def tool_ready(self, t):
        return (self.coins >= self.w.tools[t]["price"]
                and all(self.mats.get(x["id"], 0) >= x["count"] for x in self.w.toolRecipe[t]))

    def coin_need(self):
        n = sum(self.w.weapons[x].get("price", 0) for x in self.w.needWeapons - self.weapons if self.w.weapons[x].get("price"))
        if self.w.goal == "gate":
            ups = self.upgrades()
            n += self.w.weapons[ups[0]]["price"] if ups else 0
        n += sum(v["coins"] for a, v in self.w.armor.items() if a not in self.armor)
        n += sum(self.w.tools[t]["price"] for t in self.w.needTools - self.tools)
        if not self.gateDone:
            n += self.w.gate["coins"]
        for s in self.w.quest[self.step:]:
            if s["kind"] in ("give", "earn"):
                n += s.get("count", s.get("amount", 0))
        return max(0, n - self.coins)

    def level_need(self):
        lv = [self.w.gate["level"]] + ([] if self.w.goal == "gate" else [v["level"] for a, v in self.w.armor.items() if a not in self.armor])
        return max(0, self.w.exp_for(max(lv)) - self.exp)

    def drop_only_missing(self):
        """Weapons still missing that can't be bought or earned from the quest."""
        quest = {s.get("reward", {}).get("weapon") for s in self.w.quest}
        return [x for x in self.w.needWeapons - self.weapons if not self.w.weapons[x].get("price") and x not in quest]

    # --- shopping ------------------------------------------------------------
    def shop(self, final=False):
        """At the plaza: tools, weapon upgrades, armour. Returns True if anything happened."""
        w = self.w
        did = False
        # tools first: they're cheap and the quest needs them
        for t in sorted(w.needTools - self.tools, key=lambda t: w.tools[t]["price"]):
            if self.tool_ready(t):
                self.coins -= w.tools[t]["price"]
                for x in w.toolRecipe[t]:
                    self.mats[x["id"]] -= x["count"]
                self.tools.add(t)
                self.say("made", t)
                did = True
        # the gate's coins come last: keep them only once everything else is bought
        missing = sorted((x for x in w.needWeapons - self.weapons if w.weapons[x].get("price")), key=lambda x: w.weapons[x]["price"])
        if w.goal == "gate":
            # the best upgrade it can afford
            affordable = [x for x in self.upgrades() if self.coins >= w.weapons[x]["price"]]
            missing = [max(affordable, key=self.dps)] if affordable else []
        for x in missing:
            if self.coins >= w.weapons[x]["price"]:
                self.coins -= w.weapons[x]["price"]
                self.weapons.add(x)
                self.got[x] = (self.t, "bought")
                did = True
        for a, v in sorted(w.armor.items(), key=lambda kv: kv[1]["order"]):
            if a in self.armor or self.level() < v["level"] or self.coins < v["coins"]:
                continue
            # keep what the current quest step still has to hand in
            reserved = {}
            c = self.cur()
            if c and c["kind"] == "bring":
                for x in c["items"]:
                    reserved[x["id"]] = x["count"]
            if all(self.mats.get(x["id"], 0) - reserved.get(x["id"], 0) >= x["count"] for x in v["recipe"]):
                for x in v["recipe"]:
                    self.mats[x["id"]] -= x["count"]
                self.coins -= v["coins"]
                self.armor.add(a)
                self.wearing = a
                self.say("crafted", a)
                did = True
        if did:
            self.spend("shopping", PLAYER["shopSeconds"])
        return did

    def go_shop(self):
        stall = self.w.places.get("WeaponStation") or self.w.places["spawn"]
        if dist(self.pos, stall) > 40:
            self.walk(stall, "walking")
        return self.shop()

    def can_shop_something(self):
        w = self.w
        if any(self.tool_ready(t) for t in w.needTools - self.tools):
            return True
        if any(self.coins >= w.weapons[x]["price"] for x in w.needWeapons - self.weapons if w.weapons[x].get("price")):
            return True
        if w.goal == "gate" and any(self.coins >= w.weapons[x]["price"] for x in self.upgrades()):
            return True
        for a, v in w.armor.items():
            if a not in self.armor and self.level() >= v["level"] and self.coins >= v["coins"] and all(self.mats.get(x["id"], 0) >= x["count"] for x in v["recipe"]):
                return True
        return False

    # --- choosing what to farm ------------------------------------------------
    def rates(self, activity):
        """Rough yields per second of an activity, for picking what to do."""
        w = self.w
        if activity in w.gather:
            g = w.gather[activity]
            tool = next((t for t in self.tools if w.tools[t]["kind"] == g["tool"]), None)
            if not tool:
                return None
            tv = w.tools[tool]
            n = len(w.nodes[activity])
            per = PLAYER["engageSeconds"] + tv["hitTime"] + (math.ceil(g["hp"] / tv["power"]) - 1) * tv["cooldown"] + 25 / self.spd() * PLAYER["detour"]
            cycle = max(per, (per * n + g["respawn"]) / n)
            out = {}
            for x in g["drops"]:
                out[x["id"]] = x["chance"] * (x["min"] + x["max"]) / 2 / cycle
            return out
        e = w.enemies[activity]
        weapon = self.best_weapon(activity)
        fight, _ = self.fight(activity, weapon, dry=True)
        n = len(w.markers[activity])
        gap = 0 if n == 1 else 45
        per = fight + gap * PLAYER["detour"] / self.spd()
        cycle = max(per, (fight + w.respawn[activity]) / n)
        out = {"coins": (e["coins"]["min"] + e["coins"]["max"]) / 2 / cycle, "exp": e.get("exp", 0) / cycle}
        for x in e["materials"]:
            out[x["id"]] = x["chance"] * (x["min"] + x["max"]) / 2 / cycle
        for x in e["drops"]:
            out["weapon:" + x["weapon"]] = x["chance"] / cycle
        return out

    def choose(self):
        """The activity that moves the remaining needs along fastest."""
        needs = {"coins": self.coin_need(), "exp": self.level_need()}
        needs.update(self.mat_needs())
        for x in self.drop_only_missing():
            needs["weapon:" + x] = 1
        scored = []
        for act in list(self.w.enemies) + list(self.w.gather):
            if act in self.w.enemies and not self.beatable(act):
                continue
            r = self.rates(act)
            if not r:
                continue
            score = sum(r.get(k, 0) / v for k, v in needs.items() if v > 0)
            if score > 0:
                scored.append((score, act))
        if not scored:
            return None
        # a real player doesn't walk across the map for a few percent more (2026-10-24): anything
        # within PLAYER.closeEnough of the best counts, and the nearest of those wins
        top = max(sc for sc, _ in scored)
        near = [act for sc, act in scored if sc >= top * (1 - PLAYER["closeEnough"])]
        return min(near, key=self.distance_to)

    def distance_to(self, act):
        spots = [m["pos"] for m in self.w.markers[act]] if act in self.w.enemies else self.w.nodes[act]
        return min(dist(self.pos, p) for p in spots)

    def do(self, activity, times=1):
        for _ in range(times):
            if activity in self.w.gather:
                if not self.gather_one(activity):
                    return
            else:
                self.kill(activity)

    # --- the whole run ---------------------------------------------------------
    def done(self):
        return self.gateDone

    def play(self, limit=6 * 3600):
        w = self.w
        self.visit_giver()
        while not self.done() and self.t < limit:
            if w.goal == "gate" and self.ready_for_gate():
                self.buy_gate()
                break
            c = self.cur()
            if c and self.accepted and self.step_ready():
                self.visit_giver()
                if self.can_shop_something():
                    self.go_shop()
                continue
            if self.can_shop_something():
                self.go_shop()
            if c and self.accepted:
                k = c["kind"]
                if k == "kill":
                    if self.beatable(c["target"]):
                        self.do(c["target"])
                        continue
                    # too strong for now: level up and gear up on something else
                if k == "gather":
                    self.farm_material(c["target"])
                    continue
                if k == "bring":
                    short = [x for x in c["items"] if self.mats.get(x["id"], 0) < x["count"]]
                    self.farm_material(short[0]["id"])
                    continue
                # level, earn, give: farm by need
            if c is None:
                # questline done: finish the rest, then buy the gate
                if self.ready_for_gate():
                    self.buy_gate()
                    break
            act = self.choose()
            if act is None:
                # nothing left to farm but something to buy
                self.go_shop()
                if self.ready_for_gate():
                    self.buy_gate()
                    break
                continue
            if act in w.gather and not self.ensure_tool(w.gather[act]["drops"][0]["id"]):
                continue
            self.do(act, PLAYER["replanEvery"])
        return self

    def node_for(self, material):
        return next((g for g, v in self.w.gather.items() if any(x["id"] == material for x in v["drops"])), None)

    def enemy_for(self, material):
        """The beatable enemy that drops this material fastest (Rowan's Fox Fur, 2026-10-21)."""
        best = None
        for e, v in self.w.enemies.items():
            for x in v["materials"]:
                if x["id"] == material and self.beatable(e):
                    r = (self.rates(e) or {}).get(material, 0)
                    if best is None or r > best[0]:
                        best = (r, e)
        return best[1] if best else None

    def farm_material(self, material):
        """One round of getting a material: break its node, or fight the enemy that drops it."""
        if self.node_for(material):
            if self.ensure_tool(material):
                self.do(self.node_for(material))
            return
        e = self.enemy_for(material)
        if e:
            self.do(e)
        else:
            act = self.choose()
            if act:
                self.do(act)

    def ensure_tool(self, material):
        kind = self.w.gather[self.node_for(material)]["tool"]
        if any(self.w.tools[t]["kind"] == kind for t in self.tools):
            return True
        tool = min((t for t, v in self.w.tools.items() if v["kind"] == kind), key=lambda t: self.w.tools[t]["price"])
        if self.tool_ready(tool):
            self.go_shop()
            return True
        # not ready for the tool yet: farm what it still needs (its materials, then coins)
        short = [x["id"] for x in self.w.toolRecipe[tool] if self.mats.get(x["id"], 0) < x["count"]]
        e = self.enemy_for(short[0]) if short else None
        self.do(e or min((e for e in self.w.enemies if not self.w.enemies[e]["boss"]), key=lambda e: self.w.enemies[e]["hp"]), 2)
        return False

    def ready_for_gate(self):
        g = self.w.gate
        if self.w.goal == "gate":
            return (self.level() >= g["level"] and self.coins >= g["coins"]
                    and all(self.mats.get(x["id"], 0) >= x["count"] for x in g["materials"]))
        return (self.step >= len(self.w.quest) and not (self.w.needWeapons - self.weapons)
                and len(self.armor) == len(self.w.armor) and self.w.needTools <= self.tools
                and self.level() >= g["level"] and self.coins >= g["coins"]
                and all(self.mats.get(x["id"], 0) >= x["count"] for x in g["materials"]))

    def buy_gate(self):
        self.walk(self.w.places["gate"], "walking")
        self.spend("shopping", PLAYER["shopSeconds"])
        self.coins -= self.w.gate["coins"]
        for x in self.w.gate["materials"]:
            self.mats[x["id"]] -= x["count"]
        self.gateDone = True
        self.say("bought the gate")


# ---------------------------------------------------------------------------
def apply_overrides(data, sets):
    """--set boss.PumpkinMace=0.05, gate.coins=2000, gate.CrystalShard=20, enemy.Chicken.coins=6-12,
    respawn.boss=30, weapon.Scythe.price=1500, armor.HarvestKnight.coins=600"""
    cfg = data["config"]
    for s in sets:
        key, val = s.split("=", 1)
        parts = key.split(".")
        num = lambda v: float(v) if "." in v else int(v)
        if parts[0] in ("boss", "drop"):
            for group in (cfg["enemies"], cfg["bosses"]):
                for e in group.values():
                    for x in listify(e.get("drops")):
                        if x["weapon"] == parts[1] and (parts[0] == "drop" or e in cfg["bosses"].values()):
                            x["chance"] = float(val)
        elif parts[0] == "enemy":
            e = cfg["enemies"].get(parts[1]) or cfg["bosses"][parts[1]]
            if parts[2] == "coins":
                lo, hi = val.split("-")
                e["coins"] = {"min": int(lo), "max": int(hi)}
            elif parts[2] == "material":
                for x in listify(e["materials"]):
                    x["chance"] = float(val)
            elif parts[2] in ("damage", "cooldown", "windup", "armor"):
                e["melee"][parts[2]] = num(val)
            else:
                e[parts[2]] = num(val)
        elif parts[0] == "gate":
            g = data["gate"]
            if parts[1] in ("level", "coins"):
                g[parts[1]] = num(val)
            else:
                # gate.CrystalShard=20: a material's count (0 drops it)
                mats = [x for x in listify(g.get("materials")) if x["id"] != parts[1]]
                if int(val) > 0:
                    mats.append({"id": parts[1], "count": int(val)})
                g["materials"] = mats
        elif parts[0] == "respawn":
            cfg.setdefault("respawn", {})[parts[1]] = num(val)
        elif parts[0] == "weapon":
            data["weapons"][parts[1]][parts[2]] = num(val)
        elif parts[0] == "armor":
            a = data["armor"][parts[1]]
            if parts[2] in a:
                a[parts[2]] = num(val)
            else:
                for x in listify(a["recipe"]):
                    if x["id"] == parts[2]:
                        x["count"] = num(val)
        elif parts[0] == "level":
            data["leveling"][{"first": "first", "step": "step", "hp": "healthPerLevel", "growth": "growth", "basehp": "baseHealth"}[parts[1]]] = float(val)
        elif parts[0] == "quest":
            data["quest"]["steps"][parts[1]][parts[2]] = num(val)
        elif parts[0] == "player":
            PLAYER[parts[1]] = num(val)
        else:
            sys.exit("unknown --set " + s)


def curve_total(lv, level):
    if lv.get("growth"):
        return sum(math.floor(lv["first"] * lv["growth"] ** (l - lv["start"]) + 0.5) for l in range(lv["start"], level))
    return sum(lv["first"] + lv["step"] * (l - lv["start"]) for l in range(lv["start"], level))


def curve_level(lv, total):
    level = lv["start"]
    while curve_total(lv, level + 1) <= total:
        level += 1
    return level


def remap(data, old):
    """Move every level requirement to the level that needs the same total EXP on the
    new curve, so requirements arrive at the same point in the run. Prints the map."""
    new = data["leveling"]
    def m(level):
        return curve_level(new, curve_total(old, level))
    changes = []
    for a in data["armor"].values():
        changes.append(("armour " + a["id"], a["level"], m(a["level"])))
        a["level"] = m(a["level"])
    for k, st in data["quest"]["steps"].items():
        if st["kind"] == "level":
            changes.append(("quest step " + k, st["level"], m(st["level"])))
            st["level"] = m(st["level"])
    changes.append(("gate", data["gate"]["level"], m(data["gate"]["level"])))
    data["gate"]["level"] = m(data["gate"]["level"])
    print("  level requirements moved:", ", ".join("%s %d -> %d" % c for c in changes))


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p / 100 * len(xs)))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--world", type=int, default=1)
    ap.add_argument("--runs", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--probe", help="write the levels kills, quest hand-ins and worn armour happen at to this JSON file")
    ap.add_argument("--rod", action="store_true", help="count the fishing rod as a tool to buy")
    ap.add_argument("--goal", choices=("gate", "all"), default="gate", help="gate: stop at the gate; all: finish the world first")
    ap.add_argument("--from", dest="prev", type=int, default=None, help="arrive from this world: load its weapons and armour for the carried gear")
    ap.add_argument("--start-level", type=int, default=25)
    ap.add_argument("--start-coins", type=int, default=1000)
    ap.add_argument("--start-weapons", default="WeathervaneSpear")
    ap.add_argument("--start-armor", default="FarmhandsGear,HarvestKnight")
    ap.add_argument("--start-wear", default="HarvestKnight")
    ap.add_argument("--set", action="append", default=[])
    ap.add_argument("--upgrades", type=int, default=0, help="every upgrade at this level (the maxed arrival: 3 in World 2, 6 in World 3)")
    ap.add_argument("--trace", action="store_true")
    ap.add_argument("--remap", action="store_true", help="after level.* changes, move level requirements to the same EXP")
    a = ap.parse_args()
    data = load(a.world)
    if a.prev is None and a.world > 1:
        a.prev = a.world - 1
    if a.prev:
        prev = load(a.prev)
        for wid, v in prev["weapons"].items():
            data["weapons"].setdefault(wid, dict(v, carried=True))
        for aid, v in prev["armor"].items():
            data["armor"].setdefault(aid, dict(v, carried=True))
        START.update({
            "level": a.start_level, "coins": a.start_coins,
            "weapons": [x for x in a.start_weapons.split(",") if x],
            "armor": [x for x in a.start_armor.split(",") if x],
            "wear": a.start_wear or None,
        })
    for k in UPG:
        UPG[k] = a.upgrades
    old_curve = dict(data["leveling"])
    apply_overrides(data, a.set)
    if a.remap:
        remap(data, old_curve)
    world = World(data, rod=a.rod, goal=a.goal)
    rng = random.Random(a.seed)
    if a.trace:
        r = Run(world, rng, trace=True).play()
        print("total %.1f min, deaths %d, level %d" % (r.t / 60, r.deaths, r.level()))
        return
    runs = [Run(world, rng).play() for _ in range(a.runs)]
    if a.probe:
        merged = {"kill": {}, "step": {}, "wear": {}}
        for r in runs:
            for kind, groups in r.probe.items():
                for key, hist in groups.items():
                    out = merged[kind].setdefault(key, {})
                    for lv, n in hist.items():
                        out[lv] = out.get(lv, 0) + n
        with open(a.probe, "w") as f:
            json.dump(merged, f)
    times = [r.t / 60 for r in runs]
    if a.goal == "gate":
        print("World %d: %d runs (goal: buy the gate: level %d, %d coins, %s)" % (a.world, a.runs, world.gate["level"], world.gate["coins"],
              ", ".join("%d %s" % (x["count"], x["id"]) for x in world.gate["materials"])))
    else:
        print("World %d: %d runs (goals: %d weapons, %d armour, %d quest steps, gate)" % (
            a.world, a.runs, len(world.needWeapons), len(world.armor), len(world.quest)))
    print("  finish time  typical (median) %.1f min | fastest quarter %.1f | slowest quarter %.1f | 9 in 10 by %.1f | worst %.1f" % (
        statistics.median(times), pct(times, 25), pct(times, 75), pct(times, 90), max(times)))
    acts = {}
    for r in runs:
        for k, v in r.log.items():
            acts[k] = acts.get(k, 0) + v / 60 / len(runs)
    print("  where the time goes (average minutes):")
    for k, v in sorted(acts.items(), key=lambda kv: -kv[1]):
        print("    %-28s %5.1f" % (k, v))
    print("  kills (average):", ", ".join("%s %.0f" % (e, sum(r.kills.get(e, 0) for r in runs) / len(runs)) for e in world.enemies))
    early = [f for r in runs for f in r.fights if f[0] < 600]
    print("  first 10 minutes: a fight takes %.0f%% of max HP on average (bulls %.0f%%), deaths %.2f, resting %.1f min" % (
        100 * statistics.mean(f[2] for f in early) if early else 0,
        100 * statistics.mean([f[2] for f in early if f[1] == "Bull"] or [0]),
        statistics.mean(r.earlyDeaths for r in runs),
        statistics.mean(r.earlyRest for r in runs) / 60))
    print("  fountain uses %.1f, level-up heals %.1f" % (statistics.mean(r.fountainUses for r in runs), statistics.mean(r.levelHeals for r in runs)))
    print("  deaths %.2f, resting %.1f min, final level %.1f, coins left %.0f" % (
        statistics.mean(r.deaths for r in runs), statistics.mean(r.rests for r in runs) / 60,
        statistics.mean(r.level() for r in runs), statistics.mean(r.coins for r in runs)))
    print("  how each weapon was got (share of runs, typical minute):")
    if a.goal == "gate":
        best = Counter(max(r.weapons, key=r.dps) for r in runs)
        print("  at the gate: quest steps done %.1f of %d, armour sets %.1f, best weapon: %s" % (
            statistics.mean(r.step for r in runs), len(world.quest), statistics.mean(len(r.armor) for r in runs),
            ", ".join("%s %d%%" % (world.weapons[k]["name"], 100 * n / len(runs)) for k, n in best.most_common())))
    for wid in sorted(world.allWeapons, key=lambda x: world.weapons[x].get("order", 99)):
        hows = {}
        mins = []
        for r in runs:
            if wid in r.got:
                hows[r.got[wid][1]] = hows.get(r.got[wid][1], 0) + 1
                mins.append(r.got[wid][0] / 60)
        desc = ", ".join("%s %d%%" % (h, 100 * n / len(runs)) for h, n in sorted(hows.items(), key=lambda kv: -kv[1]))
        print("    %-20s %-60s at %.1f min" % (world.weapons[wid]["name"], desc, statistics.median(mins) if mins else -1))
    unfinished = sum(1 for r in runs if not r.done())
    if unfinished:
        print("  WARNING: %d runs hit the 6-hour limit" % unfinished)


if __name__ == "__main__":
    main()
