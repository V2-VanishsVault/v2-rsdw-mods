"""Wizard theme pieces (the magic class): black volcanic glass and arcane blue light.

The two big pieces - the window frame (rune-etched obsidian corners: Ansuz, Kenaz, Algiz, Dagaz) and its crest - are
painted by an image model over exact layout templates and cleaned up by make_wizard_art.py (wizard_src/ holds the
paintings and templates). Everything small (buttons, boxes, rims, bar edges, tooltips, keycaps) is drawn here, from
Warrior's shapes in polished obsidian with a glowing blue inlay: at those sizes painted detail turns to mush.
"""
import math

import inlay
import vitals_art
from inlay import rod
from make_theme import clamp01, cover, image, mix, over

GLASS = (0.018, 0.022, 0.04)
SQ2 = math.sqrt(2)
MAT, LINE = inlay.OBSIDIAN, inlay.BLUE
BRIGHT = {"core": (0.88, 0.97, 1.0), "edge": (0.22, 0.58, 1.0), "glow": (0.42, 0.76, 1.0)}


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
    """64x64 (drawn 32): Elven's tick - two gently curved strokes, widest where they meet, tapering to a point
    at both ends - as a glowing laser-etched line like the runes: blue-white at its heart, a soft blue bloom round it,
    the bloom thinning to the tips with the stroke."""
    S = 64
    A, B, C = (12.0, 31.0), (26.0, 47.0), (53.0, 13.0)   # short stroke A-B, long stroke B-C (Elven's)
    W = 4.2
    BOW1, BOW2 = 3.0, 5.0

    def curve(p, q, bow, steps=40):
        mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        dx, dy = q[0] - p[0], q[1] - p[1]
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L
        cx, cy = mx - nx * bow * 2, my - ny * bow * 2
        pts = []
        for i in range(steps + 1):
            t = i / steps
            a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t * t
            pts.append((a * p[0] + b * cx + c * q[0], a * p[1] + b * cy + c * q[1], t))
        return pts

    ARM1, ARM2 = curve(A, B, BOW1), curve(B, C, BOW2)

    def near(px, py, pts):
        best, bt = 1e9, 0.0
        for (x0, y0, t0), (x1, y1, t1) in zip(pts, pts[1:]):
            dx, dy = x1 - x0, y1 - y0
            L2 = dx * dx + dy * dy or 1e-9
            u = max(0.0, min(1.0, ((px - x0) * dx + (py - y0) * dy) / L2))
            d = math.hypot(px - (x0 + u * dx), py - (y0 + u * dy))
            if d < best:
                best, bt = d, t0 + (t1 - t0) * u
        return best, bt

    def fn(x, y):
        d1, t1 = near(x, y, ARM1)
        d2, t2 = near(x, y, ARM2)
        w1, w2 = W * t1, W * (1 - t2)
        d = min(d1 - w1, d2 - w2)                   # < 0 inside the stroke
        width = max(w1 if d1 - w1 <= d2 - w2 else w2, 0.4) / W
        bloom = 0.8 * width * math.exp(-(max(d, 0.0) / 4.5) ** 2)
        core = clamp01(0.5 - d)
        a = max(bloom, core)
        if a <= 0.004:
            return (0.0, 0.0, 0.0, 0.0)
        c = mix(LINE["glow"], LINE["core"], core)
        spine = min(d1, d2)                          # the hot center along the stroke's middle
        c = mix(c, (0.95, 0.99, 1.0), core * clamp01(1.2 - spine / max(1.0, W * width)) * 0.85)
        return c + (a,)

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
    """256x64 (made at twice its drawn 128x32, then saved at that), 9-slice like the title bars: a solid plate of
    polished obsidian - Elven's build: a raised rim lit by the way it faces, a groove 8px in glowing faintly
    blue, the face sunk under it. The same all the way across (the middle is stretched)."""
    WD, H = 256, 64
    C = 2.0

    def sd(x, y):
        return sd_cut_box(x, y, WD / 2, H / 2, WD / 2 - C, H / 2 - C, 6)

    gsd = lambda px, py: sd_cut_box(px, py, WD / 2, H / 2, WD / 2 - 9, H / 2 - 9, 3)

    def fn(x, y):
        d = sd(x, y)
        if d > 1:
            return (0.0, 0.0, 0.0, 0.0)
        t = y / H
        # glass: near black, a soft sheen across its upper half, a cool reflection low down
        c = mix((0.03, 0.035, 0.06), (0.16, 0.18, 0.26), 0.8 * math.exp(-((t - 0.3) / 0.16) ** 2))
        c = mix(c, (0.05, 0.12, 0.30), 0.35 * math.exp(-((t - 0.8) / 0.12) ** 2))
        g = gsd(x, y)
        c = inlay.framed_plate(c, d, g, inlay.facing(sd, x, y), inlay.facing(gsd, x, y),
                               (0.70, 0.80, 1.0), (0.0, 0.0, 0.01), (0.10, 0.40, 0.95))
        return c + (cover(d),)

    return WD, H, image(WD, H, fn)


def ornament():
    """32x32 (drawn about 9 units): a small black glass disc with the Kenaz rune etched in it, glowing blue - set into
    each end of a filled button, beside its text."""
    S = 32
    c0 = (S - 1) / 2
    R = 11.5

    def seg(px, py, x0, y0, x1, y1):
        dx, dy = x1 - x0, y1 - y0
        t = clamp01(((px - x0) * dx + (py - y0) * dy) / (dx * dx + dy * dy))
        return math.hypot(px - (x0 + t * dx), py - (y0 + t * dy))

    def fn(x, y):
        r = math.hypot(x - c0, y - c0)
        if r > R + 1:
            return (0, 0, 0, 0)
        lit = clamp01(0.5 - ((x - c0) * 0.4 + (y - c0) * 0.9) / (R * 1.6))
        c = mix((0.01, 0.012, 0.02), (0.30, 0.36, 0.50), 0.15 + 0.5 * lit * lit)
        c = mix(c, (0.75, 0.85, 1.0), 0.6 * math.exp(-((x - c0 + 4) ** 2 + (y - c0 + 4) ** 2) / 5.0))  # the glint
        # Kenaz: an open angle, pointing left
        d = min(seg(x, y, c0 + 3.5, c0 - 6, c0 - 3, c0), seg(x, y, c0 - 3, c0, c0 + 3.5, c0 + 6))
        c = mix(c, LINE["glow"], 0.55 * math.exp(-(d / 2.4) ** 2))
        c = mix(c, LINE["core"], clamp01(1.4 - d))
        c = mix(c, (0.0, 0.0, 0.01), 0.7 * clamp01((r - (R - 1.5)) / 1.5))
        return c + (clamp01(R + 0.5 - r),)

    return S, S, image(S, S, fn)


def tip_band():
    """256x128 (drawn 128x64), 9-slice like Elven's: no sides - dark translucent glass fading out toward both
    ends, edged top and bottom by the frame's glowing channel (its own colors, sampled from the painting: a cyan-white
    center, electric blue, a deep-blue fringe in a dark groove, star flecks along it) - the line the crests sit on,
    so a crest's channel runs straight into it. Nothing changes down its height."""
    import random
    W, H = 256, 128
    AT = 6.0              # the channel's center in from the top and bottom (tipLine 6: the game slices by pixels)
    FADE = 56.0
    rnd = random.Random(7)
    flecks = {int(rnd.uniform(0, W)) for _ in range(28)}

    def fn(x, y):
        e = min(x, W - x)
        k = clamp01(e / FADE) ** 1.4
        v = min(y, H - y)
        glass = 0.84 - 0.16 * clamp01(1 - (v - AT) / 40.0)
        col = (0.035, 0.035, 0.045, glass * k * clamp01((v - AT + 1.0) / 2.0))
        dl = abs(v - AT)
        if dl < 3.6:
            groove = (0.01, 0.015, 0.04)
            c = mix(groove, (2 / 255, 45 / 255, 180 / 255), clamp01(2.8 - dl))
            c = mix(c, (20 / 255, 140 / 255, 250 / 255), clamp01(1.9 - dl))
            c = mix(c, (65 / 255, 210 / 255, 254 / 255), clamp01(1.0 - dl))
            if int(x) in flecks and dl < 1.2:
                c = mix(c, (0.85, 0.97, 1.0), 0.8)
            col = over(col, c + (1.0,), k * clamp01(3.6 - dl))
        return col

    return W, H, image(W, H, fn)


def tip_banner():
    """256x56 (drawn 128x28), 9-slice (margin 0.22 x 0.3): the banner a timed tooltip shows its time on - dark glass
    between two thin obsidian strips with the blue inlay, the glass and strips fading out toward both ends (like the
    tooltip band). The same all the way along the middle (it stretches)."""
    W, H = 256, 56
    AT, HW = 4.0, 3.2
    FADE = 56.0

    def fn(x, y):
        e = min(x, W - x)
        k = clamp01(e / FADE) ** 1.4
        v = min(y, H - y)
        col = (0.03, 0.035, 0.06, 0.92 * k * clamp01((v - AT + 1.0) / 2.0))

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
    ("check_mark.png", check_mark), ("tip_band.png", tip_band), ("tip_banner.png", tip_banner),
    ("button_rim.png", lambda: button_rim()), ("button_rim_on.png", lambda: button_rim(True)),
    ("check_box.png", lambda: check_box()), ("check_box_hover.png", lambda: check_box(bright=True)),
    ("check_box_on.png", lambda: check_box(True)), ("check_box_on_hover.png", lambda: check_box(True, True)),
    ("title_line.png", title_line), ("plate_selected.png", selected_plate), ("plate_ornament.png", ornament), ("keycap.png", keycap),
) + vitals_art.pieces(MAT, LINE, vitals_art.obsidian_edge)

THEME_LUA = """-- Wizard theme (the magic class): black volcanic glass and arcane blue light - the window frame faceted
-- obsidian with a glowing blue channel and a laser-etched rune in each corner (Ansuz, Kenaz, Algiz, Dagaz). Colors are
-- linear RGB (0..1). Only what differs from Elven is here. The art in ui/ is made by tools/make_theme.py wizard.
return {
    gold = { 0.16, 0.52, 1.00 },          -- highlights (the selected row in lists): arcane blue
    ink = { 0.72, 0.88, 1.00 },           -- lettering on title bars, drag bars and buttons: pale blue light
    heading = { 0.45, 0.75, 1.00 },
    label = { 0.86, 0.88, 0.94 },
    dim = { 0.55, 0.58, 0.66 },
    panelColor = { 0.04, 0.045, 0.07, 0.94 },
    background = "panel_bg_starfield.png",    -- the panels' background when it's the theme's own (settings: stone)
    selectedInk = { 0.80, 0.92, 1.00 },     -- lettering on a selected (grouped) title bar: light on the glass
    -- the level-up celebration: a bright blue number (two tones: fill and outline) on a pulsing blue glow
    celebrate = {
        number = { 0.45, 0.80, 1.00 }, outline = { 0.02, 0.08, 0.30 }, glow = { 0.20, 0.55, 1.00 },
        title = { 0.88, 0.94, 1.00 }, label = { 0.62, 0.84, 1.00 },
        sparks = { { 0.40, 0.75, 1 }, { 0.75, 0.92, 1 }, { 0.20, 0.40, 1 }, { 0.95, 0.97, 1 }, { 0.55, 0.45, 1 } },
    },
    -- the frame: 512px art drawn at 256 units, its corners 96px (the rune plates in them 68px, the band turning
    -- behind), its edges tiled. The band is thicker than Warrior's - 48px of art, its channel 30px in - so it reaches
    -- further out (frameOutset 20). frameLine (where window crests sit) is where the channel is in game, measured: 23.5
    -- units (the frame draws at about 0.8 units per art pixel there, not the 0.5 its frameSize implies)
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = 23.5,
    frameToEdge = true,
    frameOutset = 20,
    frameDraw = "border",
    panelPad = { 56, 52, 56, 52 },           -- (Frame Mage's own panels: clear of the rune plates, which draw at about
                                             -- 0.8 units per art pixel - ~54 units from the frame's outer edge)
    framePadExtra = 30,
    flourishSize = { 128, 64 },
    flourishLine = 46,
    tipFlourishScale = 0.5,
}
"""
