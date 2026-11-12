"""Warrior theme art (the melee class): sharp, angular, forged - cut (chamfered) corners instead of curves, and
every border a band of polished steel with a line of red light inlaid down its middle (red: the game's color for
warriors). The metal-and-inlay drawing is shared with the other class themes (tools/inlay.py).

    python tools/make_theme.py warrior

Makes the same pieces as Elven under the same names (anything not made here - the stones, the progress-bar
overlays - comes from Elven, so the player's stone choice carries over):
  panel_frame.png     9-slice: the steel band with its red inlay, cut across every corner; in each corner a steel
                      diamond stud set with a red gem and a short spike pointing into the panel
  panel_flourish.png  a steel spearhead standing on the panel's top line (red inlay up its spine, a red gem in its
                      heart) with steel blades sweeping out from its foot
  check_mark.png      two straight steel strokes, widest at the joint, cut to points, red inlay down the middle
  check_box*.png      a cut-corner box of dark glass in the steel border (and the tick)
  button_rim*.png     the cut-corner steel border alone, for game buttons (selected: the inlay burns hotter)
  tip_band.png        tooltip band: dark glass between steel strips, the ends cut to a point
  title_line.png      title bars / buttons / text boxes: dark glass in a narrow steel border
  keycap.png          cut-corner keycap in the steel border
Same sizes and 9-slice margins as Elven, so theme.lua only changes colors.
"""
import math

import inlay
import vitals_art
from inlay import rod
from make_theme import clamp01, cover, image, mix, over

GLASS = (0.035, 0.03, 0.035)
SQ2 = math.sqrt(2)
MAT, LINE = inlay.STEEL, inlay.RED
BRIGHT = {"core": (1.0, 0.78, 0.62), "edge": (0.95, 0.22, 0.10), "glow": (1.0, 0.42, 0.22)}


def sd_cut_box(x, y, cx, cy, hx, hy, c):
    """Signed distance to a box (half-sizes hx, hy) with its corners cut off at 45 degrees by c: < 0 inside."""
    qx, qy = abs(x - cx) - hx, abs(y - cy) - hy
    box = math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0)
    return max(box, (qx + qy + c) / SQ2)


def gem(col, d, depth=3.2):
    """A red gem filling the shape with signed distance d: dark at its rim, bright in its heart."""
    if d > 1:
        return col
    k = clamp01(-d / depth)
    return over(col, mix(LINE["edge"], LINE["core"], k * k) + (1.0,), cover(d))


# --- panel frame -----------------------------------------------------------------------------------------------
# The frame is wide and wraps round the window (theme.lua frameToEdge + frameOutset): 512px art drawn at 256 UI
# units, its corners 96px (48 units) and its edges TILED (frameDraw "border") - every pattern along the band repeats
# every 320px (inlay.TILE), the middle section's length, so the edges repeat seamlessly instead of stretching. The
# band 34px of the art (17 units) from its very edge, its center line 18px in (frameLine 9).

FS = 512          # frame art size
BAND_HW = 17.0    # the band's half-width (px)
BAND_C = 18.0     # its center line, in from the art's edge
FCUT = 30.0       # how much each corner is cut


def frame_sd(x, y):
    """The panel frame's center line: a square BAND_C in from the art's edge. Measured square (the larger of the
    two distances), so the band's outer corners are square too: the panel's stone behind is square, and a cut or
    rounded corner would show it. Each corner is covered by its plate anyway (the band runs under it)."""
    h = FS / 2 - BAND_C
    return max(abs(x - FS / 2) - h, abs(y - FS / 2) - h)


def fold(c):
    """A coordinate in its corner's terms (0 at the art's edge, growing inward)."""
    return c if c < FS / 2 else FS - c


def corner_plate_sd(x, y):
    """The steel plate riveted over each corner, on top of the band (both edges run in under it): square at the
    frame's own corner, reaching just past the band (48px, 24 units, the band being 17) so it barely enters the
    window and never covers its contents; its inner corner cut deeply, so it points into the panel."""
    u, v = fold(x), fold(y)
    box = max(abs(u - 24.0) - 24.0, abs(v - 24.0) - 24.0)    # square to the art's corner, 48px (24 units) in
    inner = (u + v - 74.0) / SQ2                              # its inner corner cut deeply, pointing inward
    return max(box, inner)


def rivet(col, x, y, cx, cy, r):
    """A domed steel rivet: lit on its top-left shoulder, a small shadow below-right."""
    dx, dy = x - cx, y - cy
    d = math.hypot(dx, dy)
    if d > r + 3:
        return col
    col = over(col, (0.0, 0.0, 0.0, 1.0), 0.45 * math.exp(-(math.hypot(dx - 1.2, dy - 1.2) - r) ** 2 / 2.0)
               * (d > r - 0.5))
    if d > r + 0.5:
        return col
    g = (dx / d, dy / d) if d > 0 else (0.0, 0.0)
    c = inlay.shade(x, y, 0.0, g, 1.6 * (d / r) ** 1.5, MAT, 0.3)
    return over(col, c + (1.0,), cover(d - r))


COLLAR = (80.0, 96.0)   # px in from the frame's edge: a steel collar clamped round the band beside each corner


def collar(col, x, y, e):
    """A polished steel collar across the band, `e` px from the frame's edge along it (COLLAR[0] <= e < COLLAR[1]):
    chrome-rimmed, brushed across, a rivet in its middle. It ends exactly where the corner piece does (96px), so
    where the tiled edge is cut short (its pattern can't line up with the corner there) the join falls on its edge."""
    d = frame_sd(x, y)
    hw = BAND_HW + 1.5
    if abs(d) > hw:
        return col
    edge = min(e - COLLAR[0], COLLAR[1] - e, hw - abs(d))
    rim = inlay.chrome_rim(edge, 0.75)
    c = (rim * 0.98, rim, rim * 1.03) if rim is not None else inlay.brushed(d * 6.0, e * 3.0)
    col = over(col, c + (1.0,), cover(abs(d) - hw))
    return rivet(col, e, d, (COLLAR[0] + COLLAR[1]) / 2, 0.0, 2.6)


def panel_frame():
    """512px (drawn 256 units), 96px corners and tiled edges (repeating every 320px): a wide band of polished, brushed steel - crisp chrome
    rims at its edges, a row of rivets along each half, and down its middle a channel holding the red inlay -
    cut across every corner. Over each corner a small steel plate is riveted on, set with a red gem in a steel ring, and
    a short steel spike points from it into the panel. The edges between are plain band, tiling seamlessly."""
    S = FS

    def fn(x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        u, v = fold(x), fold(y)
        if min(u, v) > 74:      # the frame's empty middle
            return col
        col = inlay.wide_band(col, x, y, frame_sd, BAND_HW, MAT, LINE, groove=4.0, rivets=40)
        if v < 40 and COLLAR[0] <= u < COLLAR[1]:
            col = collar(col, x, y, u)
        elif u < 40 and COLLAR[0] <= v < COLLAR[1]:
            col = collar(col, x, y, v)
        if u < 72 and v < 72:
            col = rod(col, u, v, (34.0, 34.0), (54.0, 54.0), 4.6, 0.0, MAT, LINE)          # the spike
            col = inlay.plate(col, x, y, corner_plate_sd, MAT, bevel=4.0, grain=(0.0, -1.0))
            for (ru, rv) in ((9.0, 9.0), (9.0, 38.0), (38.0, 9.0)):
                col = rivet(col, u, v, ru, rv, 3.6)
            # the gem: a red diamond in a steel ring
            ring = (abs(u - 22.0) + abs(v - 22.0)) / SQ2 - 6.5
            col = gem(col, ring + 2.4, 4.2)
            col = inlay.band(col, u, v, lambda a, b: (abs(a - 22.0) + abs(b - 22.0)) / SQ2 - 6.5, 2.4, MAT, LINE,
                             groove=0.0)
        return col

    return S, S, image(S, S, fn)


# --- flourish --------------------------------------------------------------------------------------------------

def flourish_fn():
    """The flourish's drawing at 128x64 art (it's sampled at twice that size for the wide frame's flourish): a
    steel spearhead standing on the top line (y = BASE), a red inlay up its spine and a red gem in its heart, with
    two pairs of steel blades sweeping out from its foot."""
    CX, BASE = 64.0, 46.0
    TOP, MID, FOOT, HALF = BASE - 38.0, BASE - 13.0, BASE - 1.0, 10.0

    def half_at(y):
        if y <= MID:
            return HALF * clamp01((y - TOP) / (MID - TOP))
        return HALF * clamp01((FOOT - y) / (FOOT - MID))

    def fn(x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        for side in (-1, 1):   # blades first (under the head): widest at the foot, cut to a point
            for (tx, ty, w0) in ((50.0, 6.0, 2.2), (34.0, 14.0, 2.8)):
                col = rod(col, x, y, (CX + side * 8.0, BASE - 3.0), (CX + side * (8.0 + tx), BASE - ty), w0, 0.0, MAT)
        w = half_at(y)
        d = max((abs(x - CX) - w) * 0.85, TOP - y, y - FOOT)
        if 0 < d < 6:
            col = over(col, (0.0, 0.0, 0.0, 1.0), 0.45 * math.exp(-(d / 2.4) ** 2))
        if d < 1 and w > 0.3:
            # shaded as a ridge rising to its spine: each half tilts away from the middle
            g = (1.0 if x >= CX else -1.0, 0.0)
            c = inlay.metal(x, y, abs(x - CX) - w * 0.5, g, w * 0.5 + 0.6, MAT)
            if abs(x - CX) < 1.6 and TOP + 7 < y < FOOT - 3:
                c = mix(LINE["edge"], LINE["core"], clamp01(1 - abs(x - CX) / 1.6))
            col = over(col, c + (1.0,), cover(d))
        col = gem(col, (abs(x - CX) / 4.0 + abs(y - (MID + 1)) / 5.5 - 1) * 4.0)
        return col

    return fn


def panel_flourish():
    """256x128 (drawn 128x64 units, flourishLine 46): the flourish at twice its drawing's size, for the wide frame."""
    fn = flourish_fn()
    return 256, 128, image(256, 128, lambda x, y: fn(x / 2, y / 2))


# --- tick and checkboxes ---------------------------------------------------------------------------------------

def check_mark():
    """64x64 (drawn 32): two straight steel strokes meeting at the joint, widest there and cut to a point at both
    ends, with the red inlay down their middle."""
    S = 64
    A, B, C = (12.0, 32.0), (26.0, 47.0), (54.0, 12.0)

    def fn(x, y):
        col = rod((0.0, 0.0, 0.0, 0.0), x, y, B, A, 4.6, 0.0, MAT, LINE)
        return rod(col, x, y, B, C, 4.6, 0.0, MAT, LINE)

    return S, S, image(S, S, fn)


def cut_border(S, center, cut, hw, glass, bright=False):
    """A square cut-corner border of plain steel - too narrow to hold an inlay - with dark glass inside when
    `glass`; `bright` (selected, hovered) rings it with red light. As fn(x, y)."""
    h = S / 2 - center

    def sd(x, y):
        return sd_cut_box(x, y, S / 2, S / 2, h, h, cut)

    def fn(x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        d = sd(x, y)
        if glass:
            col = GLASS + ((0.74 if bright else 0.64) * cover(d + hw),)
        if bright:
            col = over(col, LINE["glow"] + (1.0,), 0.55 * math.exp(-((abs(d) - hw) / 3.0) ** 2))
        return inlay.band(col, x, y, sd, hw, MAT, LINE, groove=0.0)

    return fn


def button_rim(bright=False):
    """64x64 (drawn 32), 9-slice: the cut-corner steel border alone (nothing inside), over a game button; its
    corners cut short, so a narrow button's ends stay square-ish; `bright` = selected (ringed with red light)."""
    S = 64
    return S, S, image(S, S, cut_border(S, 2.6, 4.0, 1.25, False, bright))


def check_box(ticked=False, bright=False):
    """64x64 (drawn 32): a cut-corner box of dark glass in the steel border, optionally with the tick."""
    S = 64
    rim = cut_border(S, 3.0, 4.0, 1.4, True, bright)
    tick = check_mark()[2] if ticked else None

    def fn(x, y):
        col = rim(x, y)
        if tick:
            i = (int(y) * S + int(x)) * 4
            ta = tick[i + 3] / 255.0
            if ta > 0:
                col = over(col, (tick[i] / 255.0, tick[i + 1] / 255.0, tick[i + 2] / 255.0, 1.0), ta)
        return col

    return S, S, image(S, S, fn)


# --- title bars, tooltips, keycaps -----------------------------------------------------------------------------

def title_line():
    """256x64 (drawn 128x32), 9-slice: dark glass in a narrow border of plain steel (too narrow for an inlay), its
    corners cut short so the ends of short plates and buttons don't look pointed."""
    W, H = 256, 64
    C, HW = 3.2, 1.6      # a thin border: it mustn't crowd what the bar or button holds

    def sd(x, y):
        return sd_cut_box(x, y, W / 2, H / 2, W / 2 - C, H / 2 - C, 6)

    def fn(x, y):
        col = GLASS + (0.64 * cover(sd(x, y) + HW),)
        return inlay.band(col, x, y, sd, HW, MAT, LINE, groove=0.0)

    return W, H, image(W, H, fn)


def selected_plate():
    """256x64 (drawn 128x32), 9-slice like the title bars: a solid plate of polished, brushed steel with a chrome
    rim and short cut corners - a title bar picked into the editor's group."""
    WD, H = 256, 64
    C = 2.0

    def sd(x, y):
        return sd_cut_box(x, y, WD / 2, H / 2, WD / 2 - C, H / 2 - C, 6)

    def fn(x, y):
        d = sd(x, y)
        if d > 1:
            return (0.0, 0.0, 0.0, 0.0)
        rim = inlay.chrome_rim(-d, 0.575 + 0.225 * inlay.facing(sd, x, y))
        if rim is not None:
            c = (rim * 0.98, rim, rim * 1.03)
        else:
            # (the same all the way across: the plate's middle is stretched to the title's length, and anything that
            # changed along it showed as a seam where the stretch begins - so the brushing varies down it only)
            c = inlay.brushed(37.0, y)
            # the polish: a bright band across the upper half, darker below
            t = y / H
            c = mix(c, (1.0, 1.0, 1.0), 0.35 * math.exp(-((t - 0.32) / 0.12) ** 2))
            c = mix(c, (0.05, 0.05, 0.06), 0.25 * clamp01((t - 0.6) / 0.4))
            # Elven's build: a raised rim, an engraved groove 8px in, the face sunk under it
            g = sd_cut_box(x, y, WD / 2, H / 2, WD / 2 - 9, H / 2 - 9, 3)
            gsd = lambda px, py: sd_cut_box(px, py, WD / 2, H / 2, WD / 2 - 9, H / 2 - 9, 3)
            c = inlay.framed_plate(c, d, g, inlay.facing(sd, x, y), inlay.facing(gsd, x, y),
                                   (0.97, 0.98, 1.0), (0.16, 0.16, 0.18), (0.07, 0.07, 0.08))
        col = c + (cover(d),)
        return col

    return WD, H, image(WD, H, fn)


def ornament():
    """32x32 (drawn about 9 units): a domed steel rivet, lit from the top left - set into each end of a filled
    button, beside its text (a separate picture, so it's never stretched with the button)."""
    S = 32
    c0 = (S - 1) / 2
    R = 11.0

    def fn(x, y):
        r = math.hypot(x - c0, y - c0)
        if r > R + 1:
            return (0, 0, 0, 0)
        lit = clamp01(0.5 - ((x - c0) * 0.4 + (y - c0) * 0.9) / (R * 1.6))
        c = mix((0.10, 0.10, 0.11), (0.95, 0.96, 1.0), 0.2 + 0.75 * lit)
        c = mix(c, (1, 1, 1), 0.6 * math.exp(-((x - c0 + 3.5) ** 2 + (y - c0 + 3.5) ** 2) / 6.0))  # the glint
        c = mix(c, (0.05, 0.05, 0.06), 0.6 * clamp01((r - (R - 1.5)) / 1.5))                       # its edge
        return c + (clamp01(R + 0.5 - r),)

    return S, S, image(S, S, fn)


def tip_band():
    """256x128 (drawn 128x64), 9-slice like Elven's: no sides - dark translucent glass that fades out toward
    both ends, edged top and bottom by a strip of polished steel with the red inlay. Nothing changes down its height, so a tall tooltip
    stretches nothing but plain glass."""
    W, H = 256, 128
    AT, HW = 6.0, 4.5   # the strips' center line in from the top and bottom (on the flourishes' line), half-width
    FADE = 56.0           # how far in from each end the band reaches full strength (= the 9-slice end margin)

    def fn(x, y):
        e = min(x, W - x)
        k = clamp01(e / FADE) ** 1.4              # the glass and the strips fade away toward the ends
        v = min(y, H - y)
        glass = 0.84 - 0.16 * clamp01(1 - (v - AT) / 40.0)
        col = (0.035, 0.035, 0.04, glass * k * clamp01((v - AT + 1.0) / 2.0))

        def sd(px, py):
            return abs(min(py, H - py) - AT)
        return inlay.band(col, x, y, sd, HW, MAT, LINE, alpha=k)

    return W, H, image(W, H, fn)


def keycap():
    """128px keycap (drawn 64): dark face in a cut-corner steel border with the red inlay."""
    S = 128

    def sd(x, y):
        return sd_cut_box(x, y, S / 2, S / 2, S / 2 - 6, S / 2 - 6, 14)

    def fn(x, y):
        col = GLASS + (0.88 * cover(sd(x, y) + 2.5),)
        return inlay.band(col, x, y, sd, 2.5, MAT, LINE, groove=0.0)

    return S, S, image(S, S, fn)


PIECES = (
    ("check_mark.png", check_mark), ("tip_band.png", tip_band),
    ("button_rim.png", lambda: button_rim()), ("button_rim_on.png", lambda: button_rim(True)),
    ("check_box.png", lambda: check_box()), ("check_box_hover.png", lambda: check_box(bright=True)),
    ("check_box_on.png", lambda: check_box(True)), ("check_box_on_hover.png", lambda: check_box(True, True)),
    ("title_line.png", title_line), ("plate_selected.png", selected_plate), ("plate_ornament.png", ornament), ("keycap.png", keycap),
) + vitals_art.pieces(MAT, LINE, vitals_art.steel_edge)

THEME_LUA = """-- Warrior theme (the melee class): sharp, angular, forged - cut corners, every border polished steel with a red
-- inlay. Colors are linear RGB (0..1). Only what differs from Elven is here; everything else (sizes, the
-- stones) comes from it. The art in ui/ is made by tools/make_theme.py warrior, at Elven's sizes and margins.
return {
    gold = { 0.78, 0.12, 0.08 },          -- highlights (the selected row in lists): warrior red
    ink = { 1.0, 0.62, 0.50 },            -- lettering on title bars, drag bars and buttons: ember light
    heading = { 0.96, 0.40, 0.30 },
    label = { 0.88, 0.86, 0.86 },
    dim = { 0.60, 0.56, 0.56 },
    panelColor = { 0.08, 0.06, 0.06, 0.94 },
    background = "panel_bg_leather.png",    -- the panels' background when it's the theme's own (settings: stone)
    selectedInk = { 0.06, 0.06, 0.07 },     -- lettering on a selected (grouped) title bar: dark on the steel
    -- the level-up celebration: a red number (two tones: fill and outline) on a pulsing red glow, sparks to match
    celebrate = {
        number = { 1.00, 0.24, 0.16 }, outline = { 0.28, 0.02, 0.02 }, glow = { 1.00, 0.16, 0.08 },
        title = { 1.00, 0.88, 0.85 }, label = { 1.00, 0.62, 0.55 },
        sparks = { { 1, 0.25, 0.15 }, { 1, 0.55, 0.20 }, { 0.92, 0.92, 0.96 }, { 0.75, 0.05, 0.05 }, { 1, 0.80, 0.60 } },
    },
    -- the frame: painted (tools/painted_art.py over an exact template), 512px art drawn at 256 units; a thick band
    -- (48px of art) wrapping round each window from its edge out 20 units more (frameOutset), smaller plates over its
    -- corners, its sides tiled (frameDraw "border"). frameLine is where its inlay runs in game: the painting puts it
    -- 27px in, and the frame draws at about 0.78 units per art pixel (measured for the Wizard)
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = 21.1,
    frameToEdge = true,
    frameOutset = 20,
    frameDraw = "border",
    panelPad = { 56, 52, 56, 52 },         -- Frame Mage's own panels: their contents clear the band and the plates
    framePadExtra = 30,                    -- (and panels with their own inset get this much more)
    flourishSize = { 128, 64 },            -- the flourish at twice Elven's size, to match
    flourishLine = 46,
    tipFlourishScale = 0.5,                -- tooltips keep a small one
}
"""
