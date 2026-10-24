"""World 3's cave shell (2026-10-23 remodel): the floor, walls and ceiling of the way down and the
cave, as world-aligned boxes for Studio. The plan (halls, lanes, the curve) is layout.py's.

* A 2-stud grid over the area (on odd z, so it lines up with the cave mouth's rock steps). A cell
  is open (walkable) in the narrowing passage past the cave mouth (x 168..180, 34 wide to 17), the 90-degree curve south (radius 74 round (180, -1006), 17
  wide), a short neck into the entry hall, and the cave's halls and lanes (layout.cave_cells).
* Base floor height B: y 8 at the mouth, down 30 studs along the 128-stud way down, then y -22.
* Bumps (the user: uneven but flat): blocky 1-stud patches on a 4-stud grid (layout.bumps, its 2s
  cut to 1), only in a band 10-20 studs out from the walls (the middle of every hall is flat), none
  within 8 studs of the mouth; then every pair of neighbouring cells is evened to at most 1 stud apart
  (the higher one comes down), so nothing ever needs a jump.
* Floor blocks 4 studs thick under their top fill the open cells and the rock round them (walls stand
  on the floor; nothing past the walls), greedy-merged by top height; the cave's floor is one slab to y -22 with a 1-stud
  `Floor_1` layer over every raised patch and a `Floor_2` layer over the highest.
* Walls: rock cells up to 4 cells from open ground. The ring touching the floor is a low `Ledge`
  (to 6 above the base), a recess and an `Overhang` (the last 4 studs under the ceiling); the rings
  behind are solid `Rock` up to the ceiling. No bumps under them (hidden, and the slabs merge).
* Ceiling: one roof slab over the open ground and the walls, from the nearest open ground's base +
  ceiling height up to 4 over the highest ceiling beside it (rounded up to 8-stud levels). The way
  down is a blocky arch like the cave mouth's rock steps (the user: no smooth curve inside the
  mouth; `arch`, every step outside the mouth's stone arch), 1-stud steps from 20 at the walls
  to 29 in the mouth and about 20 past it; 28 in
  the lanes, stepped domes in the halls (40 / 45 / 50 at the middle, 28 at the edge, in 4-stud
  steps on 8-stud blocks). The top of the roof follows it, so the rock reads lumpy from World 2.
* Walls along the way down are plain rock (no ledge or recess), like the mouth's.

Writes a JSON list of [folder, name, cx, cy, cz, sx, sy, sz, colourHex] to the path given and prints
the counts. Studio builds it with the loader in the same folder."""
import json, math, random, sys
from collections import deque

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
import layout as L

GX0, GX1 = 110, 410           # the grid's x range (the west lanes reach x 151, their walls 145)
GZ0, GZ1 = -1541, -899        # and z range (odd: the cells line up with the cave mouth's 2-stud rock steps)
C = 2                         # cell size
NX, NZ = (GX1 - GX0) // C, (GZ1 - GZ0) // C
PATH_LEN = 12 + math.pi * L.R / 2   # 128
FLOOR_THICK = 4               # every floor block is this thick under its top (the user, 2026-10-24:
                              # the way down's columns reached down to y -30 for nothing)
RINGS = 2                     # wall thickness in cells (4 studs; nothing inside sees past the second)
TOP_EXTRA = 4                 # roof thickness over the ceiling
rng = random.Random(23)


def centre(i, j):
    return GX0 + C * i + C / 2, GZ0 + C * j + C / 2


def along(x, z):
    """(t, inside, off, hw) for the way down: t = studs from the mouth along the centreline,
    whether the point lies in the passage / curve / neck, how far it is off the centreline and
    the half-width there (for the arch)."""
    if 168 <= x < L.CURVE_START[0]:
        # narrowing from the mouth's 34 to 17; measured at the cell's mouth-side edge, so the
        # first cells have the mouth's own profile
        hw = 17 - 8.5 * (x - 1 - 168) / 12
        off = abs(z - L.MOUTH[1])
        return x - 168, off <= hw, off, hw
    dx, dz = x - L.CURVE_START[0], z - (L.CURVE_START[1] - L.R)
    if dx >= 0 and dz >= 0:
        a = math.atan2(dx, dz)
        off = abs(math.hypot(dx, dz) - L.R)
        return 12 + L.R * a, off <= L.WIDTH / 2, off, L.WIDTH / 2
    if dz < 0 and dz > -12:  # the neck into the entry hall
        off = abs(x - L.CX)
        return PATH_LEN, off <= L.WIDTH / 2, off, L.WIDTH / 2
    return (0 if x < L.CURVE_START[0] else PATH_LEN), False, 0, 0


def arch(off, hw):
    """The way down's ceiling over a cell, above its base: a blocky arch like the cave mouth's
    rock steps (springing 12 up, radius = the half-width, so 17 at the mouth), measured at the
    cell's inner edge and rounded up, so every step stays outside the circle (the user: from
    outside the mouth's stone arch, radius 16.4, hides them all)."""
    v = hw * hw - max(0, off - 1) ** 2
    return int(math.ceil(12 + math.sqrt(v))) if v > 0 else 12


def base(t):
    return math.floor(8 - L.DROP * min(t, PATH_LEN) / PATH_LEN + 0.5)


def main(out_path):
    # --- classify -------------------------------------------------------------------------
    is_open = [[False] * NZ for _ in range(NX)]
    B = [[0] * NZ for _ in range(NX)]
    ceil_rel = [[0] * NZ for _ in range(NX)]
    tvals = [[0.0] * NZ for _ in range(NX)]
    crown_rel = [[0] * NZ for _ in range(NX)]  # the way down's arch crown over a cell's spot
    for i in range(NX):
        for j in range(NZ):
            x, z = centre(i, j)
            if x < 168 and z > L.Z0:  # the cave mouth's own ground (World 2's), left as it is
                B[i][j] = 8
                continue
            t, inside, off, hw = along(x, z)
            tvals[i][j] = t
            B[i][j] = base(t) if z > L.Z0 or inside else L.FLOOR
            if inside:
                is_open[i][j] = True
                ceil_rel[i][j] = arch(off, hw)
                crown_rel[i][j] = arch(0, hw)
            cave_ceil = L.ceil_at(x - 1, z - 1) if z <= L.Z0 else None
            if cave_ceil:
                is_open[i][j] = True
                B[i][j] = L.FLOOR
                ceil_rel[i][j] = max(ceil_rel[i][j], dome(x, z, cave_ceil))
    # --- bumps and evening ------------------------------------------------------------------
    # the rough ground runs along the walls only (the user, 2026-10-23): 10-20 studs out from the
    # rock, the band's width wobbling along the wall, 1 stud high; the middle of every hall is flat
    wall_d = [[None] * NZ for _ in range(NX)]
    q = deque()
    for i in range(NX):
        for j in range(NZ):
            if not is_open[i][j]:
                wall_d[i][j] = 0
                q.append((i, j))
    while q:
        i, j = q.popleft()
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            a, b2 = i + di, j + dj
            if 0 <= a < NX and 0 <= b2 < NZ and wall_d[a][b2] is None:
                wall_d[a][b2] = wall_d[i][j] + 1
                q.append((a, b2))
    bump = L.bumps()
    H = [[0] * NZ for _ in range(NX)]
    for i in range(NX):
        for j in range(NZ):
            x, z = centre(i, j)
            bx = x - 1 - (int(x - 1 - L.CX) % 4)
            bz = z - ((z - L.Z0) % 4)
            b = bump.get((int(bx), int(bz)), 0)
            if tvals[i][j] < 8 and z > L.Z0:
                b = 0
            b = min(b, 1)  # 1 stud at most (the user, 2026-10-23)
            band = 15 + 5 * L.wobble(x * 1.7, z * 1.7)  # 10..20 studs from the rock
            if wall_d[i][j] is not None and wall_d[i][j] * C > band:
                b = 0
            H[i][j] = B[i][j] + b
    for i in range(NX):  # no bumps under the walls: hidden, and the slabs merge bigger
        for j in range(NZ):
            if not is_open[i][j]:
                H[i][j] = B[i][j]
    changed = True
    while changed:
        changed = False
        for i in range(NX):
            for j in range(NZ):
                for di, dj in ((1, 0), (0, 1)):
                    a, b2 = i + di, j + dj
                    if a < NX and b2 < NZ and is_open[i][j] and is_open[a][b2]:
                        h1, h2 = H[i][j], H[a][b2]
                        if h1 - h2 > 1:
                            H[i][j] = h2 + 1
                            changed = True
                        elif h2 - h1 > 1:
                            H[a][b2] = h1 + 1
                            changed = True
    # --- rings: distance to open ground, and the ceiling over the nearest open cell ----------
    dist = [[None] * NZ for _ in range(NX)]
    near = [[None] * NZ for _ in range(NX)]  # (base, ceil_abs, crown_abs) of the open ground it walls
    q = deque()
    for i in range(NX):
        for j in range(NZ):
            if is_open[i][j]:
                dist[i][j] = 0
                near[i][j] = (B[i][j], B[i][j] + ceil_rel[i][j], B[i][j] + max(ceil_rel[i][j], crown_rel[i][j]))
                q.append((i, j))
    while q:
        i, j = q.popleft()
        d = dist[i][j]
        if d >= RINGS:
            continue
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                a, b2 = i + di, j + dj
                if 0 <= a < NX and 0 <= b2 < NZ and (centre(a, b2)[0] >= 168 or centre(a, b2)[1] <= L.Z0):
                    if dist[a][b2] is None:
                        dist[a][b2] = d + 1
                        near[a][b2] = near[i][j]
                        q.append((a, b2))
                    elif dist[a][b2] == d + 1 and near[i][j][1] > near[a][b2][1]:
                        near[a][b2] = near[i][j]
    # --- boxes ------------------------------------------------------------------------------
    boxes = []
    def q2(v):
        return int(math.floor(v / 2 + 0.5) * 2)
    floor_key, ceil_key, wall_keys, layer_keys = {}, {}, {}, {}
    for i in range(NX):
        for j in range(NZ):
            d = dist[i][j]
            x, z = centre(i, j)
            if d is None:
                # nothing past the walls (the user, 2026-10-24: the base slab there showed as a
                # platform outside the cave); the rock islands' hollow insides stay open too
                # (the user, 2026-10-24: they need no roof)
                continue
            nb, nc, crown = near[i][j]
            if d == 0:
                if B[i][j] == L.FLOOR:
                    # the cave floor in layers like World 2's hills: one slab, then a 1-stud layer
                    # over every raised patch (they merge far better)
                    floor_key[(i, j)] = ("base", L.FLOOR)
                    for lvl in (1, 2):
                        if H[i][j] >= L.FLOOR + lvl:
                            layer_keys.setdefault(lvl, {})[(i, j)] = lvl
                else:
                    floor_key[(i, j)] = ("col", H[i][j])
            if x >= L.CURVE_START[0] and nb != L.FLOOR:
                nc = q2(nc)  # past the narrowing the arch steps 2 studs (fewer roof blocks)
            # inside, each column still comes down to its own ceiling, so the domes and the arch
            # keep their steps
            # the roof is about 4 thick everywhere (the user, 2026-10-24): 4 over the ceiling (the way
            # down's arch crown) at each spot, and over any neighbour's ceiling too, so a step down in
            # the roof never leaves a slot open to the sky
            high = max(crown, nc)
            for di in (-1, 0, 1):
                for dj in (-1, 0, 1):
                    a, b2 = i + di, j + dj
                    if 0 <= a < NX and 0 <= b2 < NZ and near[a][b2] is not None:
                        high = max(high, near[a][b2][1])
            top = int(math.ceil(high + TOP_EXTRA))
            if d == 0:
                # the roof over the walkable ground; the walls run up to the same top themselves
                ceil_key[(i, j)] = (nc, top)
            elif d == 1 and nb == L.FLOOR:  # the cave's walls; the way down's are plain rock
                ledge = nb + 6
                over = nc - 4
                wall_keys.setdefault("Ledge", {})[(i, j)] = (H[i][j] - FLOOR_THICK, ledge)
                lo = over if over - ledge >= 2 else ledge
                wall_keys.setdefault("Overhang", {})[(i, j)] = (lo, top)
            else:
                # no floor under the walls: they reach down as far as the floor does
                wall_keys.setdefault("Rock", {})[(i, j)] = (H[i][j] - FLOOR_THICK, top)
    def merge(cells):
        """Greedy rectangles of equal keys on the grid: [(i0, j0, i1, j1, key)]."""
        used = set()
        rects = []
        for i in range(NX):
            for j in range(NZ):
                if (i, j) in used or (i, j) not in cells:
                    continue
                k = cells[(i, j)]
                w = 1
                while (i + w, j) in cells and (i + w, j) not in used and cells[(i + w, j)] == k:
                    w += 1
                h = 1
                while all((i + a, j + h) in cells and (i + a, j + h) not in used and cells[(i + a, j + h)] == k for a in range(w)):
                    h += 1
                for a in range(w):
                    for b2 in range(h):
                        used.add((i + a, j + b2))
                rects.append((i, j, i + w, j + h, k))
        return rects
    def colour(hexs, shade=0.0):
        r, g, b = (int(hexs[k:k + 2], 16) for k in (0, 2, 4))
        f = 1 + shade  # one colour per kind, so neighbouring blocks merge (no per-block jitter)
        return "%02x%02x%02x" % tuple(max(0, min(255, int(v * f))) for v in (r, g, b))
    def add(folder, name, rect, y0, y1, hexs, shade=0.0):
        i0, j0, i1, j1 = rect
        x0, z0 = GX0 + C * i0, GZ0 + C * j0
        x1, z1 = GX0 + C * i1, GZ0 + C * j1
        if y1 - y0 <= 0:
            return
        boxes.append([folder, name, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0, colour(hexs, shade)])
    for (i0, j0, i1, j1, (kind, h)) in merge(floor_key):
        add("Floor", "Floor", (i0, j0, i1, j1), h - FLOOR_THICK, h, "7a7690")
    for lvl, cells in sorted(layer_keys.items()):
        for (i0, j0, i1, j1, _) in merge(cells):
            add("Floor", "Floor_%d" % lvl, (i0, j0, i1, j1), L.FLOOR + lvl - 1, L.FLOOR + lvl, "7a7690", 0.03 * lvl)
    for (i0, j0, i1, j1, (y0, y1)) in merge(ceil_key):
        add("Ceiling", "Ceiling", (i0, j0, i1, j1), y0, y1, "57536b")
    for name, hexs in (("Ledge", "6e6a85"), ("Overhang", "524e66"), ("Rock", "5c5872")):
        for (i0, j0, i1, j1, (y0, y1)) in merge(wall_keys.get(name, {})):
            add("Walls", name, (i0, j0, i1, j1), y0, y1, hexs)
    json.dump(boxes, open(out_path, "w"), separators=(",", ":"))
    counts = {}
    for b in boxes:
        counts[b[0] + "/" + b[1]] = counts.get(b[0] + "/" + b[1], 0) + 1
    print(len(boxes), "boxes", counts)
    hs = [H[i][j] for i in range(NX) for j in range(NZ) if is_open[i][j] and centre(i, j)[1] < L.Z0]
    print("cave floor tops", min(hs), "..", max(hs))


def dome(x, z, ceil):
    """A hall's ceiling: `ceil` at its middle, falling in 3-stud steps to 28 at its edge."""
    if ceil <= L.LANE_CEIL:
        return L.LANE_CEIL
    # measured at the middle of an 8-stud block, so the dome steps up in blocky terraces
    bx = L.CX + (math.floor((x - L.CX) / 8) + 0.5) * 8
    bz = L.Z0 - (math.floor((L.Z0 - z) / 8) + 0.5) * 8
    d = L.Z0 - bz
    for (cd, hl, hw, peak) in L.HALLS:
        e = ((d - cd) / hl) ** 2 + ((bx - L.CX) / hw) ** 2
        if e <= 1.2 and peak == ceil:
            v = L.LANE_CEIL + (peak - L.LANE_CEIL) * max(0.0, 1 - e) ** 0.6
            return int(L.LANE_CEIL + math.floor((v - L.LANE_CEIL) / 4) * 4)
    return L.LANE_CEIL


if __name__ == "__main__":
    main(sys.argv[1])
