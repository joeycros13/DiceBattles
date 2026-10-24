"""Each enemy's EXP and coins a second for a mid-world player, as a share of the best (the reward
ladder, 2026-10-24). py rates_probe.py [--set enemy.Fox.exp=70 ...]"""
import random, sys, world_sim as S

CASES = [  # world, previous world, level, weapons held, armour, worn, upgrades
    (1, None, 15, ["Dagger", "Sickle", "Machete", "Pitchfork", "Shovel", "Scythe"], ["FarmhandsGear", "HarvestKnight"], "HarvestKnight", 0),
    (2, 1, 38, ["PumpkinMace", "Hatchet", "Cleaver", "Quarterstaff", "Mace", "WoodsmansAxe", "Greatclub"], ["FarmhandsGear", "HarvestKnight", "WoodlandHide", "HeartwoodBark"], "HeartwoodBark", 3),
    (3, 2, 62, ["HeartwoodStaff", "BatwingBlade", "IronPickaxe", "PebbleMallet", "GoldGauntlets", "GeodeGlaive", "EmberCoalMaul"], ["WoodlandHide", "HeartwoodBark", "CaveRunner", "CrystalQueen"], "CrystalQueen", 6),
]


def measure(world, prev, level, weps, arm, wear, up, sets=()):
    data = S.load(world)
    if prev:
        pv = S.load(prev)
        for k, v in pv["weapons"].items():
            data["weapons"].setdefault(k, dict(v, carried=True))
        for k, v in pv["armor"].items():
            data["armor"].setdefault(k, dict(v, carried=True))
    S.apply_overrides(data, [s for s in sets if s.split(".")[1] in data["config"]["enemies"] or s.split(".")[1] in data["config"]["bosses"]])
    w = S.World(data)
    for k in S.UPG:
        S.UPG[k] = up
    S.START.clear()
    S.START.update(level=level, coins=0, weapons=weps, armor=arm, wear=wear)
    r = S.Run(w, random.Random(1))
    out = {}
    for e, v in w.enemies.items():
        rt = r.rates(e)
        out[e] = (v.get("tier") or ("boss" if v["boss"] else ""), v["exp"], sum(v["coins"].values()) / 2, rt["exp"], rt["coins"])
    return out


if __name__ == "__main__":
    sets = [a.split("=", 1)[1] if a.startswith("--set=") else a for a in sys.argv[1:] if a != "--set"]
    for case in CASES:
        out = measure(*case, sets=sets)
        ex = max(x[3] for x in out.values()); co = max(x[4] for x in out.values())
        elite = next(x for x in out.values() if x[0] == "elite")
        print(f"World {case[0]} (level {case[2]}):")
        for e, (tier, xp, c, er, cr) in out.items():
            print(f"  {e:13s} {tier:6s} {xp:7,} EXP {c:9,.0f} coins a kill ({xp / elite[1]:.2f} / {c / elite[2]:.2f} elites) | {100 * er / ex:3.0f}% EXP/s  {100 * cr / co:3.0f}% coins/s")
