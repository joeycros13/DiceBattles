"""Crit Chance and Crit Damage upgrade icons (2026-10-22, the user: the hit bubble's comic
burst as a red / yellow background; a sword or other damage symbol for Crit Damage, an
exclamation mark or percent sign for Crit Chance). Drawn in the upgrade icons' "puffy toy"
style (upgrade_icons_v2.dc.html): 128-unit viewBox, ink 2b1b3d strokes, glossy gradients,
a white highlight, a sparkle, a soft ground shadow.

    python crit_icons.py            # writes crit_icons.dc.html (every draft, data-export names)
    python ../ui/svg_render.py crit_icons.dc.html <out_dir>

Each draft is SYMBOLS[name] on one of the BACKGROUNDS; DRAFTS lists the combinations shown.

The user's picks (2026-10-22): Crit Damage = the sword with the red up-arrow badge, Crit
Chance = the exclamation mark. The background is ONE burst shape drawn twice: the red burst,
then the yellow burst as an exact copy (same spikes, same turn, same curved edges) scaled
down by INNER about the same centre, so it sits inside the red with a red band all round.
"""
import math
import os

INK = "#2b1b3d"
SPARKLE = ('<path d="M104.0 12.0 L106.1 18.9 L113.0 21.0 L106.1 23.1 L104.0 30.0 L101.9 23.1 '
           'L95.0 21.0 L101.9 18.9 Z" fill="#ffffff" stroke="#2b1b3d" stroke-width="2"></path>')
SHADOW = '<ellipse cx="64" cy="118" rx="38" ry="5" fill="#000000" opacity="0.2"></ellipse>'


def star(cx, cy, spikes, r_out, r_in, turn=0.0, curve=0.0):
    """A comic burst: spike lengths from `spikes` (x r_out), valleys at r_in, each edge
    bowed in toward the centre by `curve` like the hit bubble's (hit_burst.py)."""
    pts = []
    n = len(spikes)
    for i, k in enumerate(spikes):
        a = i / n * math.tau - math.pi / 2 + turn
        pts.append((cx + math.cos(a) * r_out * k, cy + math.sin(a) * r_out * k))
        b = a + math.tau / n / 2
        pts.append((cx + math.cos(b) * r_in, cy + math.sin(b) * r_in))
    d = f"M {pts[0][0]:.1f} {pts[0][1]:.1f}"
    for i in range(len(pts)):
        p, q = pts[i], pts[(i + 1) % len(pts)]
        mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        d += f" Q {mx + (cx - mx) * curve:.1f} {my + (cy - my) * curve:.1f} {q[0]:.1f} {q[1]:.1f}"
    return d + " Z"


# Uneven like the hit bubble's burst (art/tools/ui/hit_burst.py), so it reads hand-drawn.
SPIKES = [1.0, 0.88, 0.97, 0.86, 1.0, 0.9, 0.95, 0.87, 0.98]
CX, CY = 64, 62
R_OUT, R_IN, TURN, CURVE = 57, 37, 0.18, 0.06  # the red burst (its top spike clears the edge)
INNER = 0.72  # the yellow copy's size against the red
INNER_STROKE = 4  # the yellow's ink line, a little lighter than the red's 5


def burst(scale):
    return star(CX, CY, SPIKES, R_OUT * scale, R_IN * scale, TURN, CURVE)


def background(id_, burst_top, burst_bottom, rays_top, rays_bottom, inner=INNER):
    return f"""<defs><linearGradient id="{id_}R" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{rays_top}"></stop><stop offset="1" stop-color="{rays_bottom}"></stop></linearGradient><linearGradient id="{id_}B" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{burst_top}"></stop><stop offset="1" stop-color="{burst_bottom}"></stop></linearGradient></defs>
{SHADOW}
<path d="{burst(1)}" fill="url(#{id_}R)" stroke="{INK}" stroke-width="5" stroke-linejoin="round"></path>
<path d="{burst(inner)}" fill="url(#{id_}B)" stroke="{INK}" stroke-width="{INNER_STROKE}" stroke-linejoin="round"></path>"""


BACKGROUNDS = {
    # yellow burst on red rays: the in-game crit bubble's colours turned round
    "yellow": lambda id_: background(id_, "#fff27a", "#f5a623", "#ff6a4d", "#d42638"),
    # the yellow copy at other sizes, to compare
    "yellow66": lambda id_: background(id_, "#fff27a", "#f5a623", "#ff6a4d", "#d42638", 0.66),
    "yellow80": lambda id_: background(id_, "#fff27a", "#f5a623", "#ff6a4d", "#d42638", 0.80),
}

SWORD = """<defs><linearGradient id="{id}Bl" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ffffff"></stop><stop offset="0.5" stop-color="#dfe6ee"></stop><stop offset="1" stop-color="#a7b3c2"></stop></linearGradient><linearGradient id="{id}Gd" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe27a"></stop><stop offset="1" stop-color="#e09a12"></stop></linearGradient></defs>
<g transform="translate(64 62) scale(0.74) rotate({turn}) translate(-64 -64)" stroke="#2b1b3d" stroke-width="7.5" stroke-linejoin="round">
<path d="M64 0 L76 14 V78 H52 V14 Z" fill="url(#{id}Bl)"></path>
<path d="M64 10 V72" stroke="#9fb0c4" stroke-width="5"></path>
<rect x="36" y="76" width="56" height="12" rx="6" fill="url(#{id}Gd)"></rect>
<rect x="57" y="88" width="14" height="22" rx="4" fill="#8a4d26"></rect>
<path d="M57 96 H71 M57 103 H71" stroke="#5a2f16" stroke-width="3.5"></path>
<circle cx="64" cy="116" r="8" fill="url(#{id}Gd)"></circle>
</g>"""


def sword(id_, turn=42):
    return SWORD.format(id=id_, turn=turn)


def crossed_swords(id_):
    return sword(id_ + "a", -38) + sword(id_ + "b", 38)


def mallet(id_):
    return f"""<defs><linearGradient id="{id_}M" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff8a7a"></stop><stop offset="1" stop-color="#c8283a"></stop></linearGradient></defs>
<g transform="rotate(-32 64 62)" stroke="{INK}" stroke-linejoin="round">
<rect x="58" y="44" width="12" height="54" rx="5" fill="#c58a4a" stroke-width="6"></rect>
<path d="M58 84 H70 M58 91 H70" stroke="#7a4a20" stroke-width="3"></path>
<rect x="30" y="22" width="68" height="30" rx="11" fill="url(#{id_}M)" stroke-width="6"></rect>
<rect x="24" y="24" width="10" height="26" rx="4" fill="#ffd23f" stroke-width="5"></rect>
<rect x="94" y="24" width="10" height="26" rx="4" fill="#ffd23f" stroke-width="5"></rect>
<ellipse cx="50" cy="30" rx="10" ry="3.5" fill="#ffffff" opacity="0.75" stroke="none"></ellipse>
</g>
<g stroke="{INK}" stroke-width="5" stroke-linecap="round"><path d="M96 70 L108 66 M94 82 L106 84 M88 92 L96 102"></path></g>"""


def sword_up(id_):
    """The Attack sword with a red up-arrow badge: more damage."""
    return sword(id_, 42) + f"""<defs><linearGradient id="{id_}U" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff7a5c"></stop><stop offset="1" stop-color="#d42638"></stop></linearGradient></defs>
<circle cx="94" cy="92" r="17" fill="url(#{id_}U)" stroke="{INK}" stroke-width="5"></circle>
<path d="M94 82 L104 94 H98 V102 H90 V94 H84 Z" fill="#ffffff" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"></path>"""


def bang(id_, x=64, color=("#ff7a5c", "#d42638"), scale=1.0):
    """A chunky exclamation mark."""
    return f"""<defs><linearGradient id="{id_}X" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{color[0]}"></stop><stop offset="1" stop-color="{color[1]}"></stop></linearGradient></defs>
<g transform="translate({x} 62) scale({scale}) translate(-64 -62)" stroke="{INK}" stroke-width="6" stroke-linejoin="round">
<path d="M52 24 H76 L70 74 H58 Z" fill="url(#{id_}X)"></path>
<circle cx="64" cy="90" r="10" fill="url(#{id_}X)"></circle>
<ellipse cx="60" cy="34" rx="4" ry="7" fill="#ffffff" opacity="0.8" stroke="none" transform="rotate(-8 60 34)"></ellipse>
</g>"""


def double_bang(id_):
    return bang(id_ + "a", 50, scale=0.86) + bang(id_ + "b", 80, scale=0.86)


def percent(id_, color=("#ff7a5c", "#d42638"), hole="#fff27a"):
    return f"""<defs><linearGradient id="{id_}P" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{color[0]}"></stop><stop offset="1" stop-color="{color[1]}"></stop></linearGradient></defs>
<path d="M86 30 L42 96" stroke="{INK}" stroke-width="20" stroke-linecap="round"></path>
<path d="M86 30 L42 96" stroke="url(#{id_}P)" stroke-width="9" stroke-linecap="round"></path>
<g stroke="{INK}" stroke-width="6"><circle cx="44" cy="40" r="14" fill="url(#{id_}P)"></circle><circle cx="84" cy="86" r="14" fill="url(#{id_}P)"></circle></g>
<g stroke="{INK}" stroke-width="4"><circle cx="44" cy="40" r="5" fill="{hole}"></circle><circle cx="84" cy="86" r="5" fill="{hole}"></circle></g>
<ellipse cx="39" cy="33" rx="4" ry="2.5" fill="#ffffff" opacity="0.8" transform="rotate(-35 39 33)"></ellipse>"""


def target(id_):
    """A bullseye with a tiny exclamation in the middle: a lucky hit."""
    return f"""<g stroke="{INK}" stroke-width="5">
<circle cx="64" cy="62" r="32" fill="#ffffff"></circle>
<circle cx="64" cy="62" r="23" fill="#e8384a"></circle>
<circle cx="64" cy="62" r="14" fill="#ffffff"></circle>
</g>
<g transform="translate(64 62) scale(0.36) translate(-64 -62)">{bang(id_, 64).split("</defs>", 1)[1]}</g>
<defs><linearGradient id="{id_}X" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff7a5c"></stop><stop offset="1" stop-color="#d42638"></stop></linearGradient></defs>
<ellipse cx="48" cy="44" rx="7" ry="3" fill="#ffffff" opacity="0.8" transform="rotate(-40 48 44)"></ellipse>"""


SYMBOLS = {
    "Sword": sword,
    "CrossedSwords": crossed_swords,
    "Mallet": mallet,
    "SwordUp": sword_up,
    "Bang": lambda id_: bang(id_, scale=0.86),  # sits inside the yellow burst
    "DoubleBang": double_bang,
    "Percent": percent,
    "Target": target,
}

# (export name, label, upgrade, symbol, background)
DRAFTS = [
    ("CritDamage", "Inner burst 72%", "Crit Damage", "SwordUp", "yellow"),
    ("CritChance", "Inner burst 72%", "Crit Chance", "Bang", "yellow"),
    ("CritDamage_66", "Inner burst 66%", "Crit Damage", "SwordUp", "yellow66"),
    ("CritChance_66", "Inner burst 66%", "Crit Chance", "Bang", "yellow66"),
    ("CritDamage_80", "Inner burst 80%", "Crit Damage", "SwordUp", "yellow80"),
    ("CritChance_80", "Inner burst 80%", "Crit Chance", "Bang", "yellow80"),
]


def icon(export, symbol, bg, size=150):
    id_ = export.replace("_", "")
    body = BACKGROUNDS[bg](id_ + "bg") + "\n" + SYMBOLS[symbol](id_) + "\n" + SPARKLE
    return (f'<svg data-export="{export}" role="img" aria-label="{export}" viewBox="0 0 128 128" '
            f'style="width: {size}px; height: {size}px">\n{body}\n</svg>')


def artboard():
    cells = []
    for export, label, upgrade, symbol, bg in DRAFTS:
        cells.append(f"""<div style="background: #fff8ec; border: 4px solid #2b1b3d; border-radius: 22px; box-shadow: 0 5px 0 #2b1b3d; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 6px; padding: 10px">
{icon(export, symbol, bg)}
<span style="font-size: 18px">{upgrade}</span><span style="font-size: 14px; opacity: .7">{label}</span>
</div>""")
    return f"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Crit upgrade icons</title>
<link href="https://fonts.googleapis.com/css2?family=Luckiest+Guy&amp;display=swap" rel="stylesheet"></head>
<body style="margin:0">
<div style="width: 1100px; box-sizing: border-box; padding: 28px; background: #e4f5f8; font-family: 'Luckiest Guy', sans-serif; color: #2b1b3d; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 18px">
{chr(10).join(cells)}
</div>
</body>
</html>
"""


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "crit_icons.dc.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write(artboard())
    print("wrote crit_icons.dc.html")
