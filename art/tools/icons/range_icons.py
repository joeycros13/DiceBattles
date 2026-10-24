"""Range (weapon reach) and DPS icon drafts (2026-10-22, the user: every stat icon should be the
Upgrades panel's, and Range needs one of its own). Drawn in the upgrade icons' "puffy toy"
style (upgrade_icons_v2.dc.html): 128-unit viewBox, ink 2b1b3d strokes, glossy gradients,
a white highlight, a sparkle, a soft ground shadow.

    python range_icons.py           # writes range_icons.dc.html (every draft, data-export names)
    python ../ui/svg_render.py range_icons.dc.html <out_dir>

Range drafts: Span (a double-headed arrow between two posts), Target (an arrow flying into
a bullseye; the user's pick, refined so the arrow is shorter than the target), Tape (a tape
measure pulled out). DPS drafts (the user: DPS needs its own icon, not the Attack sword):
Stopwatch (the sword in front of the Attack Speed stopwatch), Bolt (the user's pick,
with the bolt lowered beside the blade), Flurry.
"""
import os

INK = "#2b1b3d"
SPARKLE = ('<path d="M104.0 12.0 L106.1 18.9 L113.0 21.0 L106.1 23.1 L104.0 30.0 L101.9 23.1 '
           'L95.0 21.0 L101.9 18.9 Z" fill="#ffffff" stroke="#2b1b3d" stroke-width="2"></path>')
SHADOW = '<ellipse cx="64" cy="116" rx="40" ry="5" fill="#000000" opacity="0.2"></ellipse>'


def span():
    return f"""<defs><linearGradient id="rSpG" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe27a"></stop><stop offset="1" stop-color="#e09a12"></stop></linearGradient>
<linearGradient id="rSpB" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6fb0ff"></stop><stop offset="1" stop-color="#2452c4"></stop></linearGradient></defs>
{SHADOW}
<rect x="8" y="34" width="16" height="72" rx="7" fill="url(#rSpB)" stroke="{INK}" stroke-width="6"></rect>
<rect x="104" y="34" width="16" height="72" rx="7" fill="url(#rSpB)" stroke="{INK}" stroke-width="6"></rect>
<path d="M28 70 L50 48 V61 H78 V48 L100 70 L78 92 V79 H50 V92 Z" fill="url(#rSpG)" stroke="{INK}" stroke-width="6" stroke-linejoin="round"></path>
<path d="M54 66 H74" stroke="#fff6c2" stroke-width="4" stroke-linecap="round" opacity="0.9"></path>
<ellipse cx="14" cy="44" rx="2.5" ry="6" fill="#ffffff" opacity="0.7"></ellipse>
<ellipse cx="110" cy="44" rx="2.5" ry="6" fill="#ffffff" opacity="0.7"></ellipse>
{SPARKLE}"""


def target():
    # the arrow is shorter than the target is wide (the user, 2026-10-22): it flies in
    # from the lower left and sticks in the bullseye, only its back half showing
    return f"""<defs><linearGradient id="rTgS" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#c58a4c"></stop><stop offset="1" stop-color="#8a4d26"></stop></linearGradient></defs>
{SHADOW}
<circle cx="74" cy="60" r="42" fill="#ff5a4e" stroke="{INK}" stroke-width="6"></circle>
<circle cx="74" cy="60" r="29" fill="#ffffff" stroke="{INK}" stroke-width="4"></circle>
<circle cx="74" cy="60" r="16" fill="#ff5a4e" stroke="{INK}" stroke-width="4"></circle>
<circle cx="74" cy="60" r="6" fill="#ffd23f" stroke="{INK}" stroke-width="3"></circle>
<ellipse cx="54" cy="34" rx="9" ry="4" fill="#ffffff" opacity="0.75" transform="rotate(-35 54 34)"></ellipse>
<path d="M24 98 L71 62" stroke="{INK}" stroke-width="12" stroke-linecap="round"></path>
<path d="M24 98 L71 62" stroke="url(#rTgS)" stroke-width="4.5" stroke-linecap="round"></path>
<path d="M36 89 L31 104 L25 107 L24 98 Z M36 89 L20 87 L15 91 L24 98 Z" fill="#3fa9f5" stroke="{INK}" stroke-width="4" stroke-linejoin="round"></path>
<path d="M6 70h12M4 82h10" stroke="{INK}" stroke-width="5" stroke-linecap="round"></path>
<path d="M18.0 12.0 L20.1 18.9 L27.0 21.0 L20.1 23.1 L18.0 30.0 L15.9 23.1 L9.0 21.0 L15.9 18.9 Z" fill="#ffffff" stroke="#2b1b3d" stroke-width="2"></path>"""


SWORD = """<g transform="rotate(42 64 64)" stroke="#2b1b3d" stroke-width="6" stroke-linejoin="round">
<path d="M64 0 L76 14 V78 H52 V14 Z" fill="url(#{p}B)"></path>
<path d="M64 10 V72" stroke="#9fb0c4" stroke-width="4"></path>
<rect x="36" y="76" width="56" height="12" rx="6" fill="url(#{p}G)"></rect>
<rect x="57" y="88" width="14" height="22" rx="4" fill="#8a4d26"></rect>
<path d="M57 96 H71 M57 103 H71" stroke="#5a2f16" stroke-width="3"></path>
<circle cx="64" cy="116" r="8" fill="url(#{p}G)"></circle>
</g>"""


def sword_defs(p):
    return (f'<linearGradient id="{p}B" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ffffff"></stop>'
            f'<stop offset="0.5" stop-color="#dfe6ee"></stop><stop offset="1" stop-color="#a7b3c2"></stop></linearGradient>'
            f'<linearGradient id="{p}G" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe27a"></stop>'
            f'<stop offset="1" stop-color="#e09a12"></stop></linearGradient>')


BOLT_DEFS = ('<linearGradient id="{p}Y" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff07a"></stop>'
             '<stop offset="1" stop-color="#f2a31f"></stop></linearGradient>')


def dps_watch():
    # the Attack sword in front of the Attack Speed stopwatch: damage x speed
    return f"""<defs>{sword_defs("dW")}{BOLT_DEFS.format(p="dW")}<linearGradient id="dWF" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"></stop><stop offset="1" stop-color="#d8e4ee"></stop></linearGradient></defs>
{SHADOW}
<g transform="translate(62 0) scale(0.54)">
<rect x="54" y="12" width="20" height="12" rx="4" fill="#ff8a3d" stroke="{INK}" stroke-width="7"></rect>
<circle cx="64" cy="70" r="40" fill="url(#dWF)" stroke="{INK}" stroke-width="8"></circle>
<circle cx="64" cy="70" r="31" fill="none" stroke="#3fa9f5" stroke-width="7"></circle>
<path d="M70 42 L48 76 H63 L56 100 L82 62 H67 Z" fill="url(#dWY)" stroke="{INK}" stroke-width="6" stroke-linejoin="round"></path>
</g>
<g transform="translate(-6 24) scale(0.74)">{SWORD.format(p="dW")}</g>"""


def dps_bolt():
    # the sword charged with a lightning bolt
    return f"""<defs>{sword_defs("dB")}{BOLT_DEFS.format(p="dB")}</defs>
{SHADOW}
<g transform="translate(-6 8) scale(0.9)">{SWORD.format(p="dB")}</g>
<path transform="translate(0 18)" d="M100 18 L80 50 H94 L86 76 L114 40 H99 Z" fill="url(#dBY)" stroke="{INK}" stroke-width="5" stroke-linejoin="round"></path>
<path d="M14 60h12M10 72h12" stroke="{INK}" stroke-width="5" stroke-linecap="round"></path>"""


def dps_flurry():
    # the sword with three quick slash streaks: hits coming fast
    return f"""<defs>{sword_defs("dF")}</defs>
{SHADOW}
<g transform="translate(-14 10) scale(0.86)">{SWORD.format(p="dF")}</g>
<g fill="none" stroke-linecap="round">
<path d="M70 20 Q104 34 112 66" stroke="{INK}" stroke-width="11"></path><path d="M70 20 Q104 34 112 66" stroke="#ffd23f" stroke-width="5"></path>
<path d="M78 46 Q100 56 104 82" stroke="{INK}" stroke-width="11"></path><path d="M78 46 Q100 56 104 82" stroke="#ff8a3d" stroke-width="5"></path>
<path d="M82 72 Q96 80 96 100" stroke="{INK}" stroke-width="11"></path><path d="M82 72 Q96 80 96 100" stroke="#ff5a4e" stroke-width="5"></path>
</g>"""


def tape():
    ticks = "".join(f'<path d="M{x} 84 V{90 if i % 2 else 94}" stroke="{INK}" stroke-width="3"></path>'
                    for i, x in enumerate(range(72, 112, 8)))
    return f"""<defs><linearGradient id="rTpC" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffe27a"></stop><stop offset="1" stop-color="#e09a12"></stop></linearGradient>
<linearGradient id="rTpT" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff4b8"></stop><stop offset="1" stop-color="#f2c84b"></stop></linearGradient></defs>
{SHADOW}
<rect x="56" y="80" width="62" height="20" rx="3" fill="url(#rTpT)" stroke="{INK}" stroke-width="5"></rect>
{ticks}
<path d="M114 74 V106" stroke="{INK}" stroke-width="10" stroke-linecap="round"></path>
<path d="M114 74 V106" stroke="#c9d3dd" stroke-width="4" stroke-linecap="round"></path>
<rect x="10" y="30" width="64" height="72" rx="24" fill="url(#rTpC)" stroke="{INK}" stroke-width="6"></rect>
<circle cx="42" cy="64" r="17" fill="#ff8a3d" stroke="{INK}" stroke-width="5"></circle>
<circle cx="42" cy="64" r="6" fill="#c9d3dd" stroke="{INK}" stroke-width="4"></circle>
<rect x="30" y="22" width="22" height="12" rx="5" fill="#3fa9f5" stroke="{INK}" stroke-width="5"></rect>
<ellipse cx="24" cy="44" rx="7" ry="3.5" fill="#ffffff" opacity="0.8" transform="rotate(-50 24 44)"></ellipse>
{SPARKLE}"""


DRAFTS = [("RangeTarget", "Range: Target", target), ("DpsWatch", "DPS A: Stopwatch", dps_watch),
          ("DpsBolt", "DPS B: Bolt", dps_bolt), ("DpsFlurry", "DPS C: Flurry", dps_flurry)]


def artboard():
    cells = []
    for export, label, fn in DRAFTS:
        cells.append(f"""<div style="background: #fff8ec; border: 4px solid #2b1b3d; border-radius: 22px; box-shadow: 0 5px 0 #2b1b3d; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 6px; padding: 10px">
<svg data-export="{export}" role="img" aria-label="Range {label}" viewBox="0 0 128 128" style="width: 150px; height: 150px">
{fn()}
</svg>
<span style="font-size: 22px">{label}</span>
</div>""")
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Range icon drafts</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?family=Luckiest+Guy&amp;display=swap" rel="stylesheet">
<style>body{{margin:0}}</style>
</helmet>
<div style="width: 960px; box-sizing: border-box; padding: 28px; background: #e4f5f8; font-family: 'Luckiest Guy', sans-serif; color: #2b1b3d; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 18px">
{chr(10).join(cells)}
</div>
</x-dc>
</body>
</html>
"""


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "range_icons.dc.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write(artboard())
    print("wrote range_icons.dc.html")
