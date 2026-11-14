"""Dwarven theme art (the forge): hammered bronze and dark iron with a channel of molten amber - the Warrior's
angular cut-corner pieces (tools/make_warrior.py), forged in bronze instead of steel.

    python tools/make_theme.py dwarven

The window frame, its crest, the check boxes and the weight icon are paintings (tools/dwarven_src/), fitted to the
game by tools/painted_art.py. Anything not made here (the stones, the progress-bar overlays) comes from Elven.
"""
import importlib.util
import os

import inlay
import vitals_art
from make_theme import clamp01, cover, mix, over

HERE = os.path.dirname(os.path.abspath(__file__))

MAT, LINE = inlay.BRONZE, inlay.AMBER
GLASS = (0.035, 0.028, 0.022)
BRIGHT = {"core": (1.0, 0.86, 0.52), "edge": (0.95, 0.42, 0.06), "glow": (1.0, 0.58, 0.16)}


def _warrior():
    """A private copy of the Warrior's module, its materials swapped for bronze and amber (the Warrior's own
    module stays steel and red)."""
    spec = importlib.util.spec_from_file_location("_warrior_as_dwarven", os.path.join(HERE, "make_warrior.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.MAT, mod.LINE, mod.BRIGHT, mod.GLASS = MAT, LINE, BRIGHT, GLASS
    return mod


W = _warrior()

# bronze by brightness: the steel pieces' gray (shadow .. highlight) mapped onto the metal's own colors
RAMP = ((0.0, (0.05, 0.025, 0.01)), (0.35, (0.36, 0.19, 0.06)), (0.65, (0.72, 0.45, 0.17)),
        (0.85, (0.95, 0.72, 0.38)), (1.0, (1.0, 0.93, 0.74)))


def on_ramp(ramp, v):
    for (a, ca), (b, cb) in zip(ramp, ramp[1:]):
        if v <= b:
            return mix(ca, cb, clamp01((v - a) / (b - a)))
    return ramp[-1][1]


def in_metal(make, ramp):
    """Another theme's piece recolored in this metal: each pixel's brightness looked up on the ramp (alpha kept)."""
    def run():
        w, h, px = make()
        out = list(px)
        for i in range(0, len(out), 4):
            if out[i + 3] == 0:
                continue
            v = (0.3 * out[i] + 0.59 * out[i + 1] + 0.11 * out[i + 2]) / 255.0
            r, g, b = on_ramp(ramp, v)
            out[i], out[i + 1], out[i + 2] = int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5)
        return w, h, out
    return run


def metal_edge(dark, mid, light):
    """The vitals bar's edge: a plain rounded strip of the metal (no inlay: small borders stay plain), lit along
    its top, a soft shadow on the bar inside it. Supersampled, for smooth slants on the point."""
    import math

    def shade(inside, x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        top = y < vitals_art.TAPER_H / 2
        if inside > 4.6:
            return over(col, (0.01, 0.005, 0.0, 1.0), 0.45 * math.exp(-((inside - 4.6) / 1.4) ** 2))
        if inside > -0.5:
            t = clamp01((inside + 0.5) / 5.1)
            c = mix(dark, mid, math.sin(math.pi * t))
            c = mix(c, light, (0.45 if top else 0.22) * math.exp(-((t - 0.38) / 0.17) ** 2))
            col = over(col, c + (1.0,), clamp01(inside + 0.5) * clamp01(5.1 - inside))
        return col
    return vitals_art.bar_edge(shade, ss=4)


def bronze_edge():
    return metal_edge((0.07, 0.035, 0.012), (0.48, 0.28, 0.09), (1.0, 0.84, 0.52))


PIECES = (
    ("check_mark.png", W.check_mark), ("tip_band.png", W.tip_band),
    ("button_rim.png", lambda: W.button_rim()), ("button_rim_on.png", lambda: W.button_rim(True)),
    ("check_box.png", lambda: W.check_box()), ("check_box_hover.png", lambda: W.check_box(bright=True)),
    ("check_box_on.png", lambda: W.check_box(True)), ("check_box_on_hover.png", lambda: W.check_box(True, True)),
    ("title_line.png", W.title_line), ("plate_selected.png", in_metal(W.selected_plate, RAMP)),
    ("plate_ornament.png", in_metal(W.ornament, RAMP)), ("keycap.png", W.keycap),
) + vitals_art.pieces(MAT, LINE, bronze_edge)

THEME_LUA = """-- Dwarven theme (the forge): hammered bronze and dark iron, knotwork, a channel of molten amber. Colors are linear
-- RGB (0..1). Only what differs from Elven is here; everything else (sizes, the stones) comes from it. The art in
-- ui/ is made by tools/make_theme.py dwarven.
return {
    gold = { 0.92, 0.48, 0.10 },          -- highlights (the selected row in lists): forge amber
    ink = { 1.0, 0.78, 0.46 },            -- lettering on title bars, drag bars and buttons: firelight
    heading = { 1.0, 0.62, 0.24 },
    label = { 0.90, 0.86, 0.80 },
    dim = { 0.62, 0.57, 0.50 },
    panelColor = { 0.07, 0.05, 0.035, 0.94 },
    background = "panel_bg_forge.png",    -- the panels' background when it's the theme's own (settings: stone)
    selectedInk = { 0.08, 0.04, 0.01 },     -- lettering on a selected (grouped) title bar: dark on the bronze
    -- the level-up celebration: a molten number (two tones: fill and outline) on a pulsing amber glow, sparks to match
    celebrate = {
        number = { 1.00, 0.62, 0.14 }, outline = { 0.26, 0.08, 0.01 }, glow = { 1.00, 0.40, 0.04 },
        title = { 1.00, 0.92, 0.78 }, label = { 1.00, 0.72, 0.40 },
        sparks = { { 1, 0.55, 0.10 }, { 1, 0.80, 0.30 }, { 1, 0.95, 0.75 }, { 0.85, 0.25, 0.02 }, { 0.70, 0.45, 0.20 } },
    },
    -- the frame: painted (tools/painted_art.py over an exact template), 512px art drawn at 256 units; a thick band
    -- wrapping round each window from its edge out 20 units more (frameOutset), smaller plates over its corners,
    -- its sides tiled (frameDraw "border"). frameLine is where its inlay runs in game (0.78 units per art pixel)
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = 26.6,
    frameToEdge = true,
    frameOutset = 20,
    frameDraw = "border",
    panelPad = { 56, 52, 56, 52 },         -- Frame Mage's own panels: their contents clear the band and the plates
    framePadExtra = 30,                    -- (and panels with their own inset get this much more)
    flourishSize = { 128, 64 },            -- the crest at twice Elven's size, to match
    flourishLine = 46,
    tipFlourishScale = 0.5,                -- tooltips keep a small one
}
"""
