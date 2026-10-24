"""Gathering tool icons (World 1 2026-10-19, World 2's Stone Axe / Stone Rod 2026-10-20, World 3's Crystal Pickaxe / Crystal Rod 2026-10-24): the finishing pass of weapon_icons_w2.py for the
cel-shaded raw renders of the Wooden Axe, Pickaxe and Rod (Blender text block "w1_icons_rerender",
render(id), raw PNGs in art/icons/tools/raw). Crops to a square, adds the chunky ink outline and a
soft shadow down and to the right, saves 512 px icons to art/icons/tools, and builds a review sheet
on the common tile.
Usage: py tool_icons.py [ToolId ...]   (default: every tool below)
"""
import os
from PIL import Image, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(os.path.dirname(HERE))
RAW = os.path.join(ART, "icons", "tools", "raw")
TILES = os.path.join(ART, "ui", "inventory")
OUT = os.path.join(ART, "icons", "tools")
WEAPONS = ["WoodenAxe", "WoodenPickaxe", "WoodenRod", "StoneAxe", "StoneRod", "CrystalPickaxe", "CrystalRod"]
RARITY = {"WoodenAxe": "common", "WoodenPickaxe": "common", "WoodenRod": "common",
          "StoneAxe": "uncommon", "StoneRod": "uncommon",
          "CrystalPickaxe": "rare", "CrystalRod": "rare"}
INK = (22, 18, 28)
WORK, FINAL, OUTLINE, SHADOW, MARGIN = 1024, 512, 22, (14, 20), 0.06


def dilate(mask, px):
    out, left = mask, px
    while left > 0:
        step = min(left, 6)
        out = out.filter(ImageFilter.MaxFilter(step * 2 + 1))
        left -= step
    out = out.filter(ImageFilter.GaussianBlur(1.5))
    return out.point(lambda v: 255 if v > 100 else int(v * 2.55))


def finish(name):
    img = Image.open(os.path.join(RAW, name + ".png")).convert("RGBA")
    img = img.crop(img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
    side = int(max(img.size) / (1 - 2 * MARGIN - 2 * OUTLINE / WORK))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    sq = sq.resize((WORK, WORK), Image.LANCZOS)
    ring = dilate(sq.getchannel("A"), OUTLINE)
    out = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (WORK, WORK), INK + (0,))
    shadow.putalpha(ring.point(lambda v: int(v * 0.45)))
    out.alpha_composite(ImageChops.offset(shadow, *SHADOW).filter(ImageFilter.GaussianBlur(6)))
    ink = Image.new("RGBA", (WORK, WORK), INK + (0,))
    ink.putalpha(ring)
    out.alpha_composite(ink)
    out.alpha_composite(sq)
    out = out.resize((FINAL, FINAL), Image.LANCZOS)
    out.save(os.path.join(OUT, name + ".png"))
    return out


def sheet(icons, path):
    cell = 220
    img = Image.new("RGBA", (cell * len(icons) + 20, cell + 20), (196, 232, 238, 255))
    for i, (name, icon) in enumerate(icons):
        x = 10 + i * cell
        tp = os.path.join(TILES, "tile_%s.png" % RARITY[name])
        if os.path.exists(tp):
            img.alpha_composite(Image.open(tp).convert("RGBA").resize((cell - 12, cell - 12), Image.LANCZOS), (x + 6, 16))
        img.alpha_composite(icon.resize((cell - 30, cell - 30), Image.LANCZOS), (x + 15, 22))
    img.save(path)


if __name__ == "__main__":
    import sys
    os.makedirs(OUT, exist_ok=True)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    done = [(w, finish(w)) for w in (args or WEAPONS)]
    # a review sheet only when asked (art/ keeps live art only): --sheet=<path>
    for a in sys.argv[1:]:
        if a.startswith("--sheet="):
            sheet(done, a.split("=", 1)[1])
    print("saved", len(done), "icons")
