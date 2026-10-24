"""World 3 gathered material and fish icons (2026-10-24): the same finishing as finish_w1_gather.py for the raw renders
of w3_gather_icons.html (raw/mat_<Id>.png, made by ../ui/svg_render.py): crop to the outline, fit the longer side to
464 px centred on 512, into art/icons/materials/. A review sheet on the rarity tiles only when asked
(--sheet=<path>; art/ keeps live art only).
Usage: py finish_w3_gather.py [--sheet=<path>]"""
import os
import sys
from PIL import Image

from finish_w1_gather import fit, OUT, TILES, HERE

ICONS = [("IronOre", "common"), ("CrystalShard", "common"), ("RawGem", "rare"),
         ("Glowfish", "common"), ("BlindCavefish", "uncommon"), ("CrystalEel", "rare")]

if __name__ == "__main__":
    done = [(name, rarity, fit(os.path.join(HERE, "raw", "mat_%s.png" % name), os.path.join(OUT, name + ".png"))) for name, rarity in ICONS]
    for a in sys.argv[1:]:
        if a.startswith("--sheet="):
            cell, gap = 220, 16
            sheet = Image.new("RGBA", (len(done) * (cell + gap) + gap, cell + 2 * gap), (196, 232, 238, 255))
            for i, (name, rarity, icon) in enumerate(done):
                x = gap + i * (cell + gap)
                tile = os.path.join(TILES, "tile_%s.png" % rarity)
                if os.path.exists(tile):
                    sheet.alpha_composite(Image.open(tile).convert("RGBA").resize((cell, cell), Image.LANCZOS), (x, gap))
                pad = cell // 9
                sheet.alpha_composite(icon.resize((cell - 2 * pad, cell - 2 * pad), Image.LANCZOS), (x + pad, gap + pad))
            sheet.save(a.split("=", 1)[1])
    print("saved", len(done), "icons")
