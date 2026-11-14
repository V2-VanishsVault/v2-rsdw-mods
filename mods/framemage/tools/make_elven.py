"""Elven theme art (the base theme): antique silver in frilly openwork filigree, with a channel of glowing
moonstone - the Ranger's rounded pieces (tools/make_ranger.py), worked in silver instead of oak.

    python tools/make_theme.py elven

The window frame, its crest, the check boxes and the weight icon are paintings (tools/elven_src/), fitted to the
game by tools/painted_art.py. The stones and the progress-bar art are drawn by make_theme.py: Elven is the base
theme, and the other themes use them too.
"""
import importlib.util
import os

import inlay
import vitals_art
from make_dwarven import in_metal, metal_edge

HERE = os.path.dirname(os.path.abspath(__file__))

MAT, LINE = inlay.SILVER, inlay.TEAL
GLASS = (0.03, 0.035, 0.045)
BRIGHT = {"core": (0.88, 1.0, 0.98), "edge": (0.30, 0.78, 0.80), "glow": (0.52, 0.98, 0.96)}

# silver by brightness: the oak pieces' shades (shadow .. highlight) mapped onto the metal's own colors
RAMP = ((0.0, (0.16, 0.17, 0.19)), (0.25, (0.46, 0.48, 0.52)), (0.5, (0.70, 0.72, 0.76)),
        (0.75, (0.86, 0.88, 0.91)), (1.0, (1.0, 1.0, 1.0)))


def _ranger():
    """A private copy of the Ranger's module, its materials swapped for silver and moonstone (the Ranger's own
    module stays oak and green)."""
    spec = importlib.util.spec_from_file_location("_ranger_as_elven", os.path.join(HERE, "make_ranger.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.MAT, mod.LINE, mod.BRIGHT, mod.GLASS = MAT, LINE, BRIGHT, GLASS
    return mod


R = _ranger()

# (the oak plate is dark: stretched a little brighter onto the silver)
_lift = lambda make: in_metal(make, tuple((min(1.0, a * 0.7), c) for a, c in RAMP[:-1]) + (RAMP[-1],))

PIECES = (
    ("check_mark.png", R.check_mark), ("tip_band.png", R.tip_band),
    ("button_rim.png", lambda: R.button_rim()), ("button_rim_on.png", lambda: R.button_rim(True)),
    ("check_box.png", lambda: R.check_box()), ("check_box_hover.png", lambda: R.check_box(bright=True)),
    ("check_box_on.png", lambda: R.check_box(True)), ("check_box_on_hover.png", lambda: R.check_box(True, True)),
    ("title_line.png", R.title_line), ("plate_selected.png", _lift(R.selected_plate)),
    ("plate_ornament.png", in_metal(R.ornament, RAMP)), ("keycap.png", R.keycap),
) + vitals_art.pieces(MAT, LINE, lambda: metal_edge((0.26, 0.27, 0.30), (0.74, 0.76, 0.80), (1.0, 1.0, 1.0)))

# the painted frame's settings, added to Elven's theme.lua (make_theme.py writes the rest)
FRAME_LUA = """    -- the frame: painted (tools/painted_art.py over an exact template), 512px art drawn at 256 units; a thick band
    -- wrapping round each window from its edge out 20 units more (frameOutset), smaller plates over its corners,
    -- its sides tiled (frameDraw "border"). frameLine is where its inlay runs in game (0.78 units per art pixel)
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = FRAMELINE,
    frameToEdge = true,
    frameOutset = 20,
    frameDraw = "border",
    panelPad = { 56, 52, 56, 52 },         -- Frame Mage's own panels: their contents clear the band and the plates
    framePadExtra = 30,                    -- (and panels with their own inset get this much more)
    flourishSize = { 128, 64 },            -- the crest
    flourishLine = 46,
    tipFlourishScale = 0.5,                -- tooltips keep a small one
    selectedInk = { 0.04, 0.05, 0.07 },    -- lettering on a selected (grouped) title bar: dark on the silver
    -- the level-up celebration: a silver number (two tones: fill and outline) on a pulsing moonstone glow
    celebrate = {
        number = { 0.90, 0.94, 1.00 }, outline = { 0.06, 0.10, 0.14 }, glow = { 0.46, 0.96, 0.94 },
        title = { 0.96, 1.00, 0.98 }, label = { 0.72, 0.94, 0.94 },
        sparks = { { 0.86, 0.90, 0.96 }, { 0.62, 1, 0.96 }, { 1, 1, 1 }, { 0.40, 0.80, 0.82 }, { 0.70, 0.74, 0.80 } },
    },
"""
