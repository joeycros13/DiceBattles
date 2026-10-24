"""The comic hit bubble behind enemy damage numbers (the user's reference, 2026-10-21:
a white starburst with a thick black outline, like a comic "POW!").

Writes hit_burst.html, one <svg data-export="hit_burst"> to render with
svg_render.py:

    python hit_burst.py
    python svg_render.py hit_burst.html ../../ui/hud 512 8771

The face is pure white so the game can tint it (ImageColor3) without touching the
ink outline. The spikes come from a fixed list, so a redraw comes out the same.
"""
import math
import os

INK = "#2b1b3d"
W, H = 520, 400
CX, CY = W / 2, H / 2 + 6
# Outer spike lengths (x the ellipse radius), going round from the right; uneven like
# a hand-drawn burst. Valleys sit between them at INNER.
SPIKES = [1.0, 0.83, 0.95, 0.8, 1.0, 0.86, 0.93, 0.81, 0.98, 0.85, 0.94, 0.82, 0.97]
INNER = 0.69
RX, RY = 238, 170  # the burst's ellipse (wider than tall, like the reference)
CURVE = 0.1  # how far each edge bows in toward the centre (concave comic sides)
OUTLINE = 14
SHADOW = (6, 8)  # the ink shadow's offset, down and right


def point(angle, k):
    return CX + math.cos(angle) * RX * k, CY + math.sin(angle) * RY * k


def burst_path():
    n = len(SPIKES)
    pts = []
    for i, k in enumerate(SPIKES):
        a = (i / n) * math.tau - math.pi / 2 + 0.1
        pts.append(point(a, k))
        pts.append(point(a + math.tau / n / 2, INNER))
    d = f"M {pts[0][0]:.1f} {pts[0][1]:.1f}"
    for i in range(len(pts)):
        p, q = pts[i], pts[(i + 1) % len(pts)]
        mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        cx, cy = mx + (CX - mx) * CURVE, my + (CY - my) * CURVE
        d += f" Q {cx:.1f} {cy:.1f} {q[0]:.1f} {q[1]:.1f}"
    return d + " Z"


def svg():
    d = burst_path()
    sx, sy = SHADOW
    return f"""<svg data-export="hit_burst" viewBox="0 0 {W} {H}" width="{W}" height="{H}">
  <path d="{d}" transform="translate({sx} {sy})" fill="{INK}" stroke="{INK}" stroke-width="{OUTLINE}" stroke-linejoin="miter" stroke-miterlimit="8"/>
  <path d="{d}" fill="#ffffff" stroke="{INK}" stroke-width="{OUTLINE}" stroke-linejoin="miter" stroke-miterlimit="8"/>
</svg>"""


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "hit_burst.html"), "w", encoding="utf-8") as f:
        f.write("<!doctype html><meta charset='utf-8'><body style='background:#c33'>\n" + svg() + "\n</body>\n")
    print("wrote hit_burst.html")
