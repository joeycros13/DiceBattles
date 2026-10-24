"""The player-hurt and heal screen art (2026-10-22, the user's request: a red glow on the
screen's edge below half health, a green one and + signs for a healing potion).

  edge_glow.png   a white edge glow with a clear middle (alpha only), stretched over the
                  whole screen and tinted in Studio: red for low health, green for a heal
  heal_plus.png   a green + with a white rim and an ink outline: the heal particles

Run: py art/tools/ui/hurt_fx.py  -> art/ui/hud/
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "ui", "hud")

def edge_glow(size=512, inner=0.68, outer=1.04):
    im = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = im.load()
    for y in range(size):
        for x in range(size):
            # elliptical distance from the centre, 1 at the edge's middle
            dx, dy = (x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1
            # a squarish ellipse so the glow hugs the edges, a little stronger in the corners
            d = (abs(dx) ** 3 + abs(dy) ** 3) ** (1 / 3)
            t = min(1.0, max(0.0, (d - inner) / (outer - inner)))
            a = (t * t * (3 - 2 * t)) ** 1.4
            px[x, y] = (255, 255, 255, int(round(a * 255)))
    return im

def heal_plus(size=128):
    s = 4  # supersample
    n = size * s
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def plus(w, colour, r):
        c = n / 2
        d.rounded_rectangle([c - w / 2, c - n * 0.40, c + w / 2, c + n * 0.40], radius=r, fill=colour)
        d.rounded_rectangle([c - n * 0.40, c - w / 2, c + n * 0.40, c + w / 2], radius=r, fill=colour)
    plus(n * 0.36, (43, 27, 61, 255), n * 0.09)          # ink outline
    d2 = n * 0.36 - n * 0.07
    plus(d2, (255, 255, 255, 255), n * 0.07)             # white rim
    plus(d2 - n * 0.07, (79, 207, 92, 255), n * 0.05)    # green
    # a gloss on the top arm
    c = n / 2
    d.rounded_rectangle([c - n * 0.06, c - n * 0.31, c - n * 0.01, c - n * 0.16], radius=n * 0.02, fill=(190, 245, 196, 255))
    return im.resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    edge_glow().save(os.path.join(OUT, "edge_glow.png"))
    heal_plus().save(os.path.join(OUT, "heal_plus.png"))
    print("written")
