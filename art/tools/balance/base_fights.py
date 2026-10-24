"""Base fights: the anchor of every world's numbers (the user's rule, 2026-10-24).

Each world is tuned so a player arriving maxed from the world before ends a fight with
that world's small enemy at about 50% of their health:
  World 1: level 1, the Trowel (Dagger), no armour, no upgrades       vs the Chicken
  World 2: the W2 gate's level, Harvest Knight, every upgrade at 3,
           the Pumpkin King's Mace                                     vs the Fox
  World 3: the W3 gate's level, Heartwood Bark, every upgrade at 6,
           the Heartwood Staff                                         vs the Cave Bat
No potions or gamepasses. It also reports each world's "maxed DPS" (the user's size
target: about 100 / 1k / 10k): the world's secret weapon with that world's upgrades all
applied (level 3 a world unlocked), hits only, no crits, no Worldheart Blade.

The fight is world_sim.py's, hit by hit: an 85% hit rate, crits from the Crit upgrades,
the enemy attacking from the player's first hit (0.5 s delay, then windup / cooldown),
knockback pushing it out of reach -- except that the base fights leave the base weapon's
knockback out (2026-10-24: the simulation's knockback timing swung a Fox fight between 21% and
50% on a 0.1 s windup change; knockback stays a bonus for good play). Every number comes from
world<N>.json (dump_world.luau).

  py base_fights.py               # the three base fights, the ladders and maxed DPS
  py base_fights.py --runs 20000
"""
import argparse, json, math, random, statistics
from pathlib import Path

HERE = Path(__file__).parent

HIT_RATE = 0.85        # world_sim PLAYER.hitRate
ENGAGE = 1.0           # world_sim PLAYER.engageSeconds
FIRST_ATTACK = 0.5     # MeleeService FIRST_ATTACK_DELAY
CRIT_CHANCE, CRIT_MULT = 0.10, 1.5   # Balance.Melee, the Crit upgrades' level 0

# Config/Upgrades steps a level
UP = {"Health": 0.05, "Defense": -0.01, "Attack": 0.03, "AttackSpeed": -0.015,
      "CritDamage": 0.05, "CritChance": 0.01}

def load(n):
    return json.load(open(HERE / f"world{n}.json", encoding="utf-8"))


def enemies_of(data):
    out = {}
    for group, boss in ((data["config"]["enemies"], False), (data["config"]["bosses"], True)):
        for eid, e in group.items():
            if e.get("secret"):
                continue
            m = e["melee"]
            out[eid] = {"hp": e["hp"], "damage": m["damage"], "cooldown": m["cooldown"], "windup": m["windup"],
                        "armor": m.get("armor", 0), "chaseSpeed": m["chaseSpeed"],
                        "coins": (e["coins"]["min"], e["coins"]["max"]), "exp": e.get("exp", 0),
                        "tier": "boss" if boss else e.get("tier")}
    return out


def max_hp(lv, level, armor_health, up):
    if lv.get("growth"):
        # Leveling since 2026-10-24: x10 every 25 levels
        base = math.floor(lv["baseHealth"] * lv["growth"] ** (level - lv["start"]) + 0.5)
    else:
        scale = 1
        for at, mult in lv["scale"]:
            if level >= at:
                scale = mult
        base = (lv["baseHealth"] + lv["healthPerLevel"] * (level - lv["start"])) * scale
    return (base + armor_health) * (1 + UP["Health"] * up)


def fight(rng, weapon, enemy, up, taken_mult):
    """One fight. Returns (seconds, damage taken)."""
    per = weapon["damage"] * (1 + UP["Attack"] * up) * (1 - (0 if weapon.get("ignoreArmor") else enemy["armor"]))
    cooldown = weapon["cooldown"] * (1 + UP["AttackSpeed"] * up)
    chance, mult = CRIT_CHANCE + UP["CritChance"] * up, CRIT_MULT + UP["CritDamage"] * up
    hp = enemy["hp"]
    t = ENGAGE + weapon["hitTime"] * (1 + UP["AttackSpeed"] * up)
    first, knocks = None, []
    while True:
        if rng.random() < HIT_RATE:
            hp -= per * (mult if rng.random() < chance else 1)
            first = t if first is None else first
            knocks.append(t)
            if hp <= 1e-6:
                break
        t += cooldown
    end, taken = t, 0
    na = first + FIRST_ATTACK
    back = weapon.get("knockback", 0) / max(1, enemy["chaseSpeed"])
    while na + enemy["windup"] < end:
        pushed = [k for k in knocks if k <= na and k + back > na]
        if pushed:
            na = pushed[-1] + back
            continue
        lands = na + enemy["windup"]
        missed = weapon.get("knockback", 0) >= 3 and any(na < k < lands for k in knocks)
        if not missed:
            taken += max(1, math.floor(enemy["damage"] * taken_mult + 0.5))
        na += enemy["cooldown"]
    return end - ENGAGE, taken


def maxed_dps(weapon, up):
    """Hits only, no crits (Bonuses.dps): damage x Attack / (cooldown x Attack Speed)."""
    return weapon["damage"] * (1 + UP["Attack"] * up) / (weapon["cooldown"] * (1 + UP["AttackSpeed"] * up))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=10000)
    a = ap.parse_args()
    rng = random.Random(1)
    w1, w2, w3 = load(1), load(2), load(3)
    lv = w1["leveling"]
    weapons = dict(w1["weapons"]); weapons.update(w2["weapons"]); weapons.update(w3["weapons"])
    armor = dict(w1["armor"]); armor.update(w2["armor"])
    worlds = {1: enemies_of(w1), 2: enemies_of(w2), 3: enemies_of(w3)}
    gate_level = {2: w1["gate"]["level"], 3: w2["gate"]["level"]}
    bases = [
        (1, "Chicken", 1, "Dagger", None, 0),
        (2, "Fox", gate_level[2], "PumpkinMace", "HarvestKnight", 3),
        (3, "CaveBat", gate_level[3], "HeartwoodStaff", "HeartwoodBark", 6),
    ]
    print("BASE FIGHTS (target: about 50% of max HP taken)")
    for world, small, level, wid, aid, up in bases:
        wpn = dict(weapons[wid], knockback=0)
        arm = armor[aid] if aid else {"health": 0, "defense": 0}
        hp = max_hp(lv, level, arm["health"], up)
        taken_mult = (1 - arm["defense"]) * (1 + UP["Defense"] * up)
        print(f"\nWorld {world}: level {level}, {wpn['name']}, {aid or 'no armour'}, upgrades {up}: {hp:,.0f} HP, takes x{taken_mult:.3f}")
        for eid, e in worlds[world].items():
            res = [fight(rng, wpn, e, up, taken_mult) for _ in range(a.runs)]
            shares = [r[1] / hp for r in res]
            secs = [r[0] for r in res]
            hit = max(1, math.floor(e["damage"] * taken_mult + 0.5)) / hp
            mark = "  <- base" if eid == small else ""
            print(f"  {eid:13s} {e['tier'] or '':7s} hp {e['hp']:>7,} dmg {e['damage']:>6,}  fight {statistics.mean(secs):5.1f} s  "
                  f"takes {100 * statistics.mean(shares):5.1f}% (median {100 * statistics.median(shares):5.1f}%, a hit {100 * hit:4.1f}%)"
                  f"  coins {e['coins'][0]}-{e['coins'][1]}  exp {e['exp']:,}{mark}")
    print("\nMAXED DPS (target: about 100 / 1,000 / 10,000; secret weapon + the world's upgrades, hits only)")
    for world, wpn, up in ((1, weapons["CornCob"], 3), (2, weapons["MarshmallowStick"], 6), (3, weapons["RockCandyClub"], 9)):
        print(f"  World {world}: {wpn['id']} {wpn['damage']:,} / {wpn['cooldown']} s at upgrades {up}: {maxed_dps(wpn, up):,.0f} DPS")
    print("\nBASE WEAPONS' OWN DPS (with the base player's upgrades)")
    for world, small, level, wid, aid, up in bases:
        print(f"  World {world}: {weapons[wid]['name']} {maxed_dps(weapons[wid], up):,.1f} DPS at upgrades {up}")


if __name__ == "__main__":
    main()
