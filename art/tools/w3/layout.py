"""World 3 remodel layout (2026-10-23, the user's picks): the cave mouth and gate stay; a short
narrow passage, then a 90-degree curve south that goes down 30 studs in 1-stud steps; then the cave,
516 long x 264 wide like Worlds 1 and 2, running south: entry hall, a lane loop, the (bigger) middle
hall, a lane loop, the boss hall. Floors are blocky patches at 0 / 1 / 2 studs, never more than
1 stud between neighbours. Writes a top view (with World 2's corner for reference) to the given path.
The plan's numbers are the build's (world coordinates after the 2026-10-20 map moves)."""
import math, random, sys
from PIL import Image, ImageDraw, ImageFont

# ---- the plan -------------------------------------------------------------------------------
MOUTH = (168, -932)          # the mouth's inner end (floor y 8), heading east
CURVE_START = (180, -932)    # the narrow passage runs straight to here, then curves south
R = 74                       # the curve's centreline radius: it ends heading south at (254, -1006)
# (2026-10-23, the user: the first curve, R 102 and 192 long, was a touch long; this is 2/3 of it, 128)
WIDTH = 17                   # the passage and the curve
DROP = 30                    # y 8 at the top, -22 at the bottom
CX = CURVE_START[0] + R      # the cave's centre line (x 254)
Z0 = CURVE_START[1] - R      # where the cave starts (z -1006); it runs to Z0 - 516
FLOOR = 8 - DROP             # -22
# along the cave (d = studs south of Z0): halls (centre d, half-length, half-width, ceiling)
HALLS = [(54, 54, 66, 40), (262, 52, 72, 45), (464, 52, 70, 50)]
# lane loops (d from, d to, centre offset at the ends, extra bow in the middle, width); ceiling 28
LANES = [(84, 232, 50, 26, 50), (292, 436, 50, 26, 50)]
LANE_CEIL = 28


def wobble(a, b):
    return 0.6 * math.sin(a * 0.11 + b * 0.07) + 0.4 * math.sin(a * 0.043 - b * 0.12 + 1.7)


def ceil_at(x, z):
    """The cave's ceiling height over a point (from its lower corner on the 2-stud grid), or None
    where it's rock."""
    d, s = Z0 - z, x - CX
    best = None
    for (cd, hl, hw, ceil) in HALLS:
        if ((d - cd) / hl) ** 2 + (s / hw) ** 2 <= 1 + 0.12 * wobble(x, z):
            best = max(best or 0, ceil)
    for (a, b, base, bow, w) in LANES:
        if a <= d <= b:
            off = base + bow * math.sin(math.pi * (d - a) / (b - a))
            for side in (-1, 1):
                if abs(s - side * off) <= w / 2 + 2 * wobble(x, z):
                    best = max(best or 0, LANE_CEIL)
    return best


def cave_cells():
    """(x, z) of every open 2-stud cell -> its ceiling height."""
    cells = {}
    for x in range(CX - 140, CX + 140, 2):
        for z in range(Z0 - 520, Z0 + 2, 2):
            c = ceil_at(x, z)
            if c:
                cells[(x, z)] = c
    return cells


def bumps(seed=3):
    """Blocky 0/1/2 patches on a 4-stud grid: a smoothed random field, quantized, then no step
    between neighbours over 1 stud."""
    rng = random.Random(seed)
    coarse = {}

    def c(i, j):
        if (i, j) not in coarse:
            coarse[(i, j)] = rng.random()
        return coarse[(i, j)]

    def field(x, z):  # value noise, ~6-stud patches
        u, v = x / 6.0, z / 6.0
        i, j = math.floor(u), math.floor(v)
        fu, fv = u - i, v - j
        a = c(i, j) * (1 - fu) + c(i + 1, j) * fu
        b = c(i, j + 1) * (1 - fu) + c(i + 1, j + 1) * fu
        return a * (1 - fv) + b * fv

    level = {}
    for x in range(CX - 140, CX + 140, 4):
        for z in range(Z0 - 520, Z0 + 4, 4):
            f = field(x, z)
            level[(x, z)] = 0 if f < 0.38 else (1 if f < 0.68 else 2)
    changed = True
    while changed:
        changed = False
        for (x, z), l in level.items():
            if l == 2 and any(level.get((x + dx, z + dz), 1) == 0 for dx, dz in ((4, 0), (-4, 0), (0, 4), (0, -4))):
                level[(x, z)] = 1
                changed = True
    return level


# ---- drawing --------------------------------------------------------------------------------
S = 2
LEFT, TOP = -60, -820
W, H = 540 * S, 760 * S
X = lambda x: (x - LEFT) * S
Z = lambda z: (TOP - z) * S  # south is down
INK = (43, 27, 61)


def font(n):
    for f in ("arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(f, n)
        except OSError:
            pass
    return ImageFont.load_default()


def main(path):
    img = Image.new("RGB", (W, H), (34, 31, 46))
    d = ImageDraw.Draw(img)
    # World 2 (its south-east corner) for reference
    d.rectangle([X(-130), Z(-880), X(136), Z(-1012)], fill=(62, 118, 49))
    d.text((X(0), Z(-940)), "World 2", fill=(230, 240, 220), font=font(30), anchor="mm")
    # the mouth and gate (kept)
    d.rectangle([X(121), Z(-915), X(168), Z(-949)], fill=(101, 99, 119))
    d.rectangle([X(123), Z(-916), X(125), Z(-948)], fill=(143, 228, 247))
    d.text((X(142), Z(-900)), "mouth + gate", fill=(240, 240, 250), font=font(18), anchor="mm")
    # the passage and the curve, darker as they go down
    straight = CURVE_START[0] - MOUTH[0]
    path_len = straight + math.pi * R / 2
    t = 0.0
    while t < path_len:
        if t < straight:
            px, pz, ang = MOUTH[0] + t, MOUTH[1], 0.0
        else:
            a = (t - straight) / R
            px, pz, ang = CURVE_START[0] + R * math.sin(a), CURVE_START[1] - R * (1 - math.cos(a)), a
        y = 8 - DROP * t / path_len
        shade = int(90 + 70 * (y + 22) / 30)
        nx, nz = math.sin(ang), math.cos(ang)  # across the path
        d.line([X(px + nx * WIDTH / 2), Z(pz + nz * WIDTH / 2), X(px - nx * WIDTH / 2), Z(pz - nz * WIDTH / 2)],
               fill=(shade + 70, shade + 30, shade - 20), width=4)
        t += 1.0
    d.text((X(CURVE_START[0] - 4), Z(-990)), "curve south\n30 down\nabout 13 deg", fill=(240, 230, 210), font=font(18), anchor="mm", align="center")
    # the cave, with the bumpy floor's levels as lighter shades
    lv = bumps()
    base = {28: (110, 106, 132), 40: (128, 146, 184), 45: (140, 160, 200), 50: (152, 174, 214)}
    for (x, z), ceil in cave_cells().items():
        l = lv.get((x - (x - CX) % 4, z - (z - Z0) % 4), 0)
        col = tuple(min(255, v + 16 * l) for v in base[ceil])
        d.rectangle([X(x), Z(z), X(x + 2) - 1, Z(z - 2) - 1], fill=col)
    for (cd, hl, hw, ceil), name in zip(HALLS, ("entry hall", "middle hall", "boss hall")):
        d.text((X(CX), Z(Z0 - cd) - 12), name, fill=INK, font=font(24), anchor="mm")
        d.text((X(CX), Z(Z0 - cd) + 14), "ceiling %d" % ceil, fill=INK, font=font(18), anchor="mm")
    d.text((X(CX - 92), Z(Z0 - 158)), "lanes\nceiling 28", fill=(200, 196, 220), font=font(16), anchor="mm", align="center")
    # sizes
    d.line([X(CX - 132), Z(Z0 - 530), X(CX + 132), Z(Z0 - 530)], fill=(255, 255, 255), width=3)
    d.text((X(CX), Z(Z0 - 542)), "264", fill=(255, 255, 255), font=font(20), anchor="mm")
    d.line([X(CX + 150), Z(Z0), X(CX + 150), Z(Z0 - 516)], fill=(255, 255, 255), width=3)
    d.text((X(CX + 158), Z(Z0 - 258)), "516", fill=(255, 255, 255), font=font(20), anchor="lm")
    d.text((20, 16), "World 3 remodel: curve south, then the cave runs south", fill=(255, 255, 255), font=font(26))
    d.text((20, 52), "floor y -22; lighter = the bumpy floor's 1- and 2-stud patches", fill=(210, 210, 225), font=font(20))
    img.save(path)
    cells = cave_cells()
    print("cave x %d..%d, z %d..%d, open area %d sq studs" % (CX - 132, CX + 132, Z0 - 516, Z0, len(cells) * 4))


if __name__ == "__main__":
    main(sys.argv[1])
