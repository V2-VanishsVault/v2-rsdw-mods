"""Generates a theme's own panel art (no game art) into FrameMage/Art/themes/<theme>/ui/.

    python tools/make_theme.py            (Demi-human: moonstone and wispy gold light)

Pure standard library, like make_icons.py. Pieces:
  panel_stone.png   seamless moonstone, tiled behind panels (wraps on every edge)
  panel_stone_slate.png, panel_stone_marble.png   the other stones players can pick (settings: stone)
  panel_frame.png   9-slice frame of light: a gold hairline, brightest at the corners, with three curves
                    converging in each corner and faint compass arcs behind (after the game's own menus)
  title_line.png    9-slice title bar / drag bar / button: faint dark glass edged with a hairline of light
                    (gold lettering sits on it)
  keycap.png        9-slice keycap: dark face, hairline gold rim
  title_plate.png   the older solid gold plate (kept for themes that want it)
  bar_bevel.png     overlay for the "bevelled" progress-bar style (settings: bars.style)
  bar_facet.png     overlay for the "faceted" style: a hard bevel, facets meeting in a ridge
Images are made at twice their drawn size (theme.lua sizes) so they stay sharp on 1440p and 4K.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from make_icons import png, sd_round_rect  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "FrameMage", "Art", "themes")


# --- noise that wraps (period in lattice cells) --------------------------------------------------------------

def _hash(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def pnoise(x, y, period, seed=0):
    """Value noise in [0,1] that repeats every `period` units (x, y in lattice units)."""
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    def h(a, b):
        return _hash(a % period, b % period, seed)
    a, b, c, d = h(ix, iy), h(ix + 1, iy), h(ix, iy + 1), h(ix + 1, iy + 1)
    top = a + (b - a) * sx
    return top + ((c + (d - c) * sx) - top) * sy


def pnoise_xy(x, y, period_x, period_y, seed=0):
    """Value noise repeating every period_x lattice cells across and period_y down (for stretched patterns)."""
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    def h(a, b):
        return _hash(a % period_x, b % period_y, seed)
    a, b, c, d = h(ix, iy), h(ix + 1, iy), h(ix, iy + 1), h(ix + 1, iy + 1)
    top = a + (b - a) * sx
    return top + ((c + (d - c) * sx) - top) * sy


def pfbm(x, y, period, seed=0, octaves=4):
    total, amp, norm = 0.0, 0.5, 0.0
    for o in range(octaves):
        f = 2 ** o
        total += amp * pnoise(x * f, y * f, period * f, seed + o)
        norm += amp
        amp *= 0.5
    return total / norm


def worley(x, y, period, seed):
    """Nearest jittered point in a wrapping grid: (distance, second distance, that point's hash)."""
    ix, iy = math.floor(x), math.floor(y)
    best, second, tag = 9.0, 9.0, 0.0
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx, cy = ix + dx, iy + dy
            px = cx + _hash(cx % period, cy % period, seed)
            py = cy + _hash(cx % period, cy % period, seed + 17)
            d = math.hypot(x - px, y - py)
            if d < best:
                best, second, tag = d, best, _hash(cx % period, cy % period, seed + 31)
            elif d < second:
                second = d
    return best, second, tag


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


def clamp01(v):
    return max(0.0, min(1.0, v))


def to_bytes(rgba):
    r, g, b, a = rgba
    return [round(clamp01(r) * 255), round(clamp01(g) * 255), round(clamp01(b) * 255), round(clamp01(a) * 255)]


def image(w, h, fn):
    out = []
    for y in range(h):
        for x in range(w):
            out += to_bytes(fn(x + 0.5, y + 0.5))
    return out


def cover(d):
    """Anti-aliased coverage of a signed distance (pixels): 1 inside, 0 outside, smooth across one pixel."""
    return clamp01(0.5 - d)


def over(dst, src, a):
    """Composite colour src with alpha a over dst (both straight RGBA)."""
    da = dst[3]
    oa = a + da * (1 - a)
    if oa <= 0:
        return (0.0, 0.0, 0.0, 0.0)
    return tuple((src[i] * a + dst[i] * da * (1 - a)) / oa for i in range(3)) + (oa,)


# --- General: polished granite, gold inlay ---------------------------------------------------------------

STONE_PX = 256  # tile size in pixels; repeats seamlessly
GRAIN = 3.2     # pixels per crystal cell (drawn at half size: a fine, polished grain)
BASE = (0.115, 0.115, 0.125)
MICA = (0.055, 0.055, 0.06)
FELDSPAR = (0.29, 0.285, 0.275)
QUARTZ = (0.17, 0.17, 0.18)
GOLD_HI = (1.00, 0.89, 0.58)
GOLD = (0.86, 0.66, 0.26)
GOLD_LO = (0.50, 0.34, 0.10)


def granite(px, py, brighten=0.0):
    """Granite colour at a pixel of the wrapping tile."""
    cells = STONE_PX / GRAIN
    gx, gy = px / GRAIN, py / GRAIN
    d1, d2, tag = worley(gx, gy, round(cells), 5)
    edge = clamp01((d2 - d1) * 3.0)  # 0 at a crystal boundary
    if tag < 0.62:
        c = mix(BASE, QUARTZ, tag * 0.5)
    elif tag < 0.82:
        c = MICA
    elif tag < 0.95:
        c = QUARTZ
    else:
        c = FELDSPAR
    c = mix(MICA, c, 0.75 + 0.25 * edge)  # faint seams between crystals
    mottle = pfbm(px / 64.0, py / 64.0, STONE_PX // 64, 9)  # broad cloudiness: depth under the polish
    c = tuple(v * (0.80 + 0.40 * mottle) + brighten for v in c)
    return c


def panel_stone():
    w = h = STONE_PX
    return w, h, image(w, h, lambda x, y: granite(x, y) + (1.0,))


def gold_line(t):
    """Gold across a rounded bar: t in [-1, 1] from one side to the other (fake cylinder lighting)."""
    light = math.cos(t * math.pi / 2)              # brightest along the middle
    spec = max(0.0, 1 - abs(t + 0.35) * 3.2) ** 2  # a hot streak just above centre
    c = mix(GOLD_LO, GOLD, light * 1.15)
    return mix(c, GOLD_HI, spec)


def panel_frame():
    """128px frame (drawn 64 units): dark outline, raised polished rim, gold inlay, corner diamonds."""
    S = 128
    R_OUT = 10
    INLAY = 15.0   # inlay line centre, inset from the edge (px)
    INLAY_W = 4.0
    RIM = 9.0      # width of the raised rim

    def fn(x, y):
        outer = sd_round_rect(x, y, S / 2, S / 2, S / 2, S / 2, R_OUT)
        col = (0, 0, 0, 0)
        if outer > 1:
            return col
        # raised rim: polished stone, lit from the top left
        depth = -outer  # px inside the edge
        rim = clamp01((RIM - depth) + 0.5) * cover(outer)
        if rim > 0:
            nx = (x - S / 2) / (S / 2)
            ny = (y - S / 2) / (S / 2)
            # smooth polished bevel (no grain: the 9-slice stretches the edges, grain would streak)
            light = 0.09 * (-(nx + ny) / 2)
            curve = math.sin(clamp01(depth / RIM) * math.pi)  # rounded profile: brightest mid-rim
            v = 0.07 + 0.06 * curve + light * curve
            col = over(col, (v, v, v * 1.05, 1.0), rim)
        # thin black outline and the rim's inner shadow line
        col = over(col, (0.01, 0.01, 0.01, 1), cover(abs(outer + 0.8) - 0.9))
        col = over(col, (0.0, 0.0, 0.0, 1), 0.55 * cover(abs(outer + RIM) - 0.7))
        # gold inlay: a rounded rectangle line
        line = sd_round_rect(x, y, S / 2, S / 2, S / 2 - INLAY, S / 2 - INLAY, R_OUT - 4)
        t = line / (INLAY_W / 2)
        if abs(t) < 1.4:
            col = over(col, gold_line(max(-1, min(1, t))) + (1.0,), cover(abs(line) - INLAY_W / 2))
            col = over(col, (0, 0, 0, 1), 0.35 * cover(abs(line - INLAY_W / 2 - 0.7) - 0.5))  # engraved shadow
        # corner diamonds on the inlay line
        for cx in (INLAY, S - INLAY):
            for cy in (INLAY, S - INLAY):
                d = (abs(x - cx) + abs(y - cy)) / math.sqrt(2) - 6.8
                if d < 1.5:
                    facet = 1.0 if (x - cx) + (y - cy) < 0 else 0.0  # top-left facets catch the light
                    c = mix(GOLD_LO, GOLD_HI, 0.35 + 0.55 * facet)
                    col = over(col, c + (1.0,), cover(d))
                    col = over(col, (0.15, 0.09, 0.02, 1), 0.8 * cover(abs(d + 0.4) - 0.45))
                    col = over(col, GOLD_HI + (1.0,), cover(math.hypot(x - cx, y - cy) - 1.3))
        return col

    return S, S, image(S, S, fn)


def title_plate():
    """256x64 polished gold plate (drawn 128x32): bevelled, brushed, engraved border line, end diamonds."""
    W, H = 256, 64
    R = 7

    def fn(x, y):
        d = sd_round_rect(x, y, W / 2, H / 2, W / 2 - 1, H / 2 - 1, R)
        if d > 1:
            return (0, 0, 0, 0)
        v = y / H
        # vertical polish: a bright band high up, warm shadow low down
        band = math.exp(-((v - 0.30) / 0.16) ** 2)
        c = mix(GOLD, GOLD_HI, band * 0.75)
        c = mix(c, GOLD_LO, clamp01((v - 0.62) / 0.38) * 0.65)
        brush = pnoise(x / 40.0, y / 1.4, 1 << 20, 3)  # fine horizontal brushing
        c = tuple(ch * (0.93 + 0.12 * brush) for ch in c)
        # bevel: lit top edge, dark bottom edge
        depth = -d
        if depth < 4:
            k = 1 - depth / 4
            c = mix(c, GOLD_HI if v < 0.5 else GOLD_LO, k * 0.8)
        col = c + (cover(d),)
        col = over(col, (0.20, 0.12, 0.03, 1), cover(abs(d + 0.6) - 0.8))  # outline
        # engraved line, 7px in
        e = sd_round_rect(x, y, W / 2, H / 2, W / 2 - 8, H / 2 - 8, 4)
        col = over(col, (0.36, 0.23, 0.06, 1), 0.85 * cover(abs(e) - 0.8))
        col = over(col, GOLD_HI + (1,), 0.55 * cover(abs(e - 1.6) - 0.5))
        # small diamonds at each end of the engraved line
        for cx in (17, W - 17):
            dd = (abs(x - cx) + abs(y - H / 2)) / math.sqrt(2) - 4.2
            col = over(col, (0.30, 0.19, 0.05, 1), cover(dd))
            col = over(col, GOLD_HI + (1,), 0.8 * cover(dd + 2.2))
        return col

    return W, H, image(W, H, fn)


def keycap():
    """128px keycap (drawn 64): gold rim, dished stone face lit from above."""
    S = 128

    def fn(x, y):
        outer = sd_round_rect(x, y, S / 2, S / 2, S / 2 - 3, S / 2 - 3, 18)
        if outer > 1:
            return (0, 0, 0, 0)
        col = (0, 0, 0, 0)
        t = clamp01(-outer / 7.0)
        col = over(col, gold_line(1 - 2 * t) + (1.0,), cover(outer))
        face = sd_round_rect(x, y, S / 2, S / 2 - 3, S / 2 - 12, S / 2 - 14, 12)
        if face < 1:
            shade = 0.04 * (1 - y / S) - 0.03
            col = over(col, granite(x * 2 % STONE_PX, y * 2 % STONE_PX, 0.05 + shade) + (1,), cover(face))
            col = over(col, (0, 0, 0, 1), 0.6 * cover(abs(face) - 0.8))
        return col

    return S, S, image(S, S, fn)


# --- High Elf: moonstone and wispy gold light ---------------------------------------------------------------

LIGHT = (1.0, 0.86, 0.55)


def moonstone(px, py):
    """Seamless moonstone: dark blue-grey with a soft drifting sheen (wraps every STONE_PX)."""
    n = pfbm(px / 64.0, py / 64.0, STONE_PX // 64, 51)
    sheen = pfbm(px / 128.0, py / 128.0, STONE_PX // 128, 61)
    v = 0.075 + 0.03 * n
    c = (v * 0.92, v * 1.0, v * 1.22)
    return mix(c, (0.40, 0.52, 0.74), max(0.0, sheen - 0.36) * 0.55)


def moonstone_tile():
    w = h = STONE_PX
    return w, h, image(w, h, lambda x, y: moonstone(x, y) + (1.0,))


def slate(px, py):
    """Seamless slate: calm, near-plain dark stone with faint cleavage lines (wraps every STONE_PX)."""
    n = pfbm(px / 64.0, py / 64.0, STONE_PX // 64, 21)
    cleave = pnoise_xy(px / 64.0, py / 4.0, STONE_PX // 64, STONE_PX // 4, 5)  # stretched along x: thin layers
    v = 0.088 + 0.022 * n + 0.009 * cleave
    return (v * 0.97, v, v * 1.08)


def black_marble(px, py):
    """Seamless black marble with thin white veins (wraps every STONE_PX: the vein waves complete whole cycles)."""
    tau = 2 * math.pi / STONE_PX
    base = 0.05 + 0.025 * pfbm(px / 64.0, py / 64.0, STONE_PX // 64, 3)
    warp = pfbm(px / 64.0, py / 64.0, STONE_PX // 64, 8) * 7.0
    s1 = abs(math.sin(px * tau * 1 + py * tau * 2 + warp))
    s2 = abs(math.sin(px * tau * 3 - py * tau * 1 + warp * 1.6 + 2.0))
    vein = math.exp(-s1 / 0.035) * 0.48 + math.exp(-s2 / 0.02) * 0.18
    return mix((base, base, base * 1.05), (0.72, 0.71, 0.69), vein)


def tile_of(fn):
    def make():
        w = h = STONE_PX
        return w, h, image(w, h, lambda x, y: fn(x, y) + (1.0,))
    return make


def hair(col, d, alpha, width=1.0, halo=3.6):
    """A line of light: thin core plus a soft halo (sizes in pixels of the 2x art)."""
    if alpha <= 0.003 or d > halo * 3:
        return col
    col = over(col, LIGHT + (1.0,), math.exp(-(d / halo) ** 2) * 0.22 * alpha)
    return over(col, mix(GOLD, GOLD_HI, 0.6) + (1.0,), alpha * cover(d - width))


def ellipse_dist(px, py, cx, cy, a, b):
    dx, dy = px - cx, py - cy
    f = (dx / a) ** 2 + (dy / b) ** 2 - 1
    g = 2 * math.hypot(dx / (a * a), dy / (b * b))
    return abs(f) / max(g, 1e-6)


def light_frame():
    """128px frame (drawn 64): transparent inside; everything is light. The corners hold all the detail and stay
    fixed in 9-slicing; the edges between them stretch, so they are an even, dimmer line."""
    S = 128
    INSET = 7.0
    MARGIN = 58                    # the 9-slice corner size (frameMargin = 58/128)
    CONV, REACH = 22.0, (22.0, 36.0, 52.0)
    EDGE_A = 0.42                  # brightness of the stretched edges

    def fn(x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        u = (x - INSET) if x < S / 2 else (S - INSET - x)   # from the frame line, per corner
        v = (y - INSET) if y < S / 2 else (S - INSET - y)
        if u < -6 or v < -6:
            return col
        # the square hairline: bright at the corner, easing to EDGE_A by the slice boundary
        along = max(u, v)
        a = EDGE_A + (1 - EDGE_A) * clamp01(1 - along / (MARGIN - INSET - 4)) ** 1.5
        d = min(abs(u) if v >= -1 else 99, abs(v) if u >= -1 else 99)
        col = hair(col, d, a)
        # three curves converging on the horizontal edge
        for b in REACH:
            if u <= CONV + 8 and v <= b + 8:
                if u > CONV:
                    dd = math.hypot(u - CONV, v)
                elif v > b:
                    dd = math.hypot(u, v - b)
                else:
                    dd = ellipse_dist(u, v, CONV, b, CONV, b)
                k = math.hypot(u - CONV, v) / (b + CONV)
                col = hair(col, dd, 0.95 * math.exp(-k * 1.6) + 0.12, 0.85)
        # faint compass arcs, fading before the slice boundary
        fade = clamp01(1 - math.hypot(u, v) / (MARGIN - INSET))
        for (cx, cy, r, aa) in ((30, 30, 26, 0.16), (18, 40, 22, 0.10)):
            col = hair(col, abs(math.hypot(u - cx, v - cy) - r), aa * fade, 0.7)
        # bloom where the curves meet the edge
        r2 = ((u - CONV) ** 2 + v * v) / 160.0
        col = over(col, LIGHT + (1.0,), math.exp(-r2) * 0.25)
        return col

    return S, S, image(S, S, fn)


def title_line():
    """256x64 (drawn 128x32): faint dark glass, a hairline of light round it, brighter towards the corners."""
    W, H = 256, 64
    INSET = 3.0

    def fn(x, y):
        u = (x - INSET) if x < W / 2 else (W - INSET - x)
        v = (y - INSET) if y < H / 2 else (H - INSET - y)
        if u < -3 or v < -3:
            return (0, 0, 0, 0)
        col = (0.03, 0.04, 0.06, 0.62 * cover(-min(u, v) - 0.5))
        d = min(abs(u) if v >= -1 else 99, abs(v) if u >= -1 else 99)
        a = 0.55 + 0.45 * clamp01(1 - max(u, v) / 40.0)
        col = hair(col, d, a, 1.0, 3.0)
        # a tiny converging curve in each corner, like the panels
        if u <= 12 and v <= 12:
            col = hair(col, ellipse_dist(u, v, 12, 12, 12, 12), 0.7, 0.8, 2.5)
        return col

    return W, H, image(W, H, fn)


def light_keycap():
    """128px keycap (drawn 64): dark face, hairline gold rim with a faint inner line."""
    S = 128

    def fn(x, y):
        outer = sd_round_rect(x, y, S / 2, S / 2, S / 2 - 6, S / 2 - 6, 14)
        if outer > 8:
            return (0, 0, 0, 0)
        col = (0.03, 0.04, 0.06, 0.85 * cover(outer))
        col = hair(col, abs(outer), 0.95, 1.4, 3.0)
        col = hair(col, abs(outer + 7), 0.25, 0.8, 2.0)
        return col

    return S, S, image(S, S, fn)


def bar_bevel():
    """128x32 overlay that turns a flat progress bar into a bevelled, glassy one. Only white light and black shade,
    so it works over any bar colour; drawn over the whole bar (9-sliced: the rounded ends keep their shape)."""
    W, H = 128, 32

    def fn(x, y):
        v = y / H                      # 0 top .. 1 bottom
        e = 1.0                        # shading runs the full length (no end treatment)
        col = (0.0, 0.0, 0.0, 0.0)
        # bright rim along the top edge, then a glossy band that fades by the middle
        rim = math.exp(-((v - 0.05) / 0.045) ** 2) * 0.55
        gloss = clamp01(1 - (v - 0.10) / 0.32) * 0.30 if v > 0.08 else 0.0
        hi = max(rim, gloss) * (0.55 + 0.45 * clamp01(e))
        if hi > 0:
            col = over(col, (1.0, 1.0, 1.0, 1.0), hi)
        # shade towards the bottom, with a crisp dark lip
        shade = clamp01((v - 0.58) / 0.42) ** 1.6 * 0.42
        lip = math.exp(-((v - 0.95) / 0.04) ** 2) * 0.35
        col = over(col, (0.0, 0.0, 0.0, 1.0), max(shade, lip))
        return col

    return W, H, image(W, H, fn)


def bar_facet():
    """128x32 overlay for a hard bevel: a light top facet and a dark bottom facet meeting in a ridge along the
    middle. Top and bottom only: the ends are left plain (the pointed right end is the tip cap's)."""
    W, H = 128, 32
    HALF = H / 2.0
    TOP, BOTTOM = 0.26, -0.34

    def fn(x, y):
        top = y < HALF
        k = TOP if top else BOTTOM
        depth = (y if top else H - y) / HALF
        k *= 1.0 - 0.35 * depth                    # strongest at the outer edge
        col = (1.0, 1.0, 1.0, k) if k > 0 else (0.0, 0.0, 0.0, -k)
        if y < 1.6:
            col = over(col, (1.0, 1.0, 1.0, 1.0), 0.35)
        if y > H - 1.6:
            col = over(col, (0.0, 0.0, 0.0, 1.0), 0.45)
        if abs(y - (HALF - 0.6)) < 0.7:              # the ridge
            col = over(col, (1.0, 1.0, 1.0, 1.0), 0.22)
        return col

    return W, H, image(W, H, fn)


TIP_W, TIP_H = 32, 64   # tip art: 32x64 px, drawn 16 units long at the bar's height


def _tip_inside(x, y):
    """Signed distance (px, approx.) inside the pointed tip: a triangle from the left edge to a point at the right."""
    half = TIP_H / 2.0
    # the two slanted edges run from (0, 0) and (0, H) to (W, H/2)
    slope = half / TIP_W
    d_top = (y - x * slope)                    # >0 below the top edge
    d_bot = (TIP_H - y) - x * slope            # >0 above the bottom edge
    n = math.hypot(1, slope)
    return min(d_top / n, d_bot / n)


def bar_cap():
    """The tip's shape in white; the game tints it with the bar's colour."""
    def fn(x, y):
        return (1.0, 1.0, 1.0, cover(-_tip_inside(x, y)))
    return TIP_W, TIP_H, image(TIP_W, TIP_H, fn)


TAPER_W, TAPER_H, TAPER_POINT = 128, 64, 32   # full-length tapered overlays: drawn 64x32 units, point 16 units


def _tapered(shade):
    """A full-length overlay whose right TAPER_POINT pixels are the point: shade(x, y) -> (rgba) over the body, the
    same shading cut to the triangle over the point, so the bevel runs unbroken into the tip."""
    body = TAPER_W - TAPER_POINT

    def fn(x, y):
        if x < body:
            return shade(x, y, 1.0, None)
        inside = _tip_inside(x - body, y)
        a = cover(-inside)
        if a <= 0:
            return (0, 0, 0, 0)
        return shade(x, y, a, inside)

    return TAPER_W, TAPER_H, image(TAPER_W, TAPER_H, fn)


def bar_facet_tapered():
    """Hard bevel: light top facet, dark bottom facet, a ridge along the middle running to the point; crisp rims
    along the top and bottom edges and along both slants of the point."""
    H = TAPER_H
    HALF = H / 2.0

    def shade(x, y, a, inside):
        top = y < HALF
        k = 0.26 if top else -0.34
        depth = (y if top else H - y) / HALF
        k *= 1.0 - 0.35 * depth
        col = (1.0, 1.0, 1.0, k * a) if k > 0 else (0.0, 0.0, 0.0, -k * a)
        edge = min(y, H - y) if inside is None else min(inside, y, H - y)
        if edge < 3.2:                               # rims: light along the upper edges, dark along the lower
            col = over(col, (1.0, 1.0, 1.0, 1.0) if top else (0.0, 0.0, 0.0, 1.0), (0.35 if top else 0.45) * a)
        if abs(y - (HALF - 1.2)) < 1.4:                # the ridge, all the way to the point
            col = over(col, (1.0, 1.0, 1.0, 1.0), 0.22 * a)
        return col

    return _tapered(shade)


def bar_bevel_tapered():
    """Soft bevel: a bright rim, a glossy upper band and shade underneath, running into the point."""
    H = TAPER_H

    def shade(x, y, a, inside):
        v = y / H
        rim = math.exp(-((v - 0.05) / 0.045) ** 2) * 0.55
        gloss = clamp01(1 - (v - 0.10) / 0.32) * 0.30 if v > 0.08 else 0.0
        col = (0.0, 0.0, 0.0, 0.0)
        hi = max(rim, gloss)
        if inside is not None:                         # along the upper slant, the rim follows the edge
            hi = max(gloss, math.exp(-(inside / 2.5) ** 2) * 0.5 if y < H / 2 else 0.0)
        if hi > 0:
            col = over(col, (1.0, 1.0, 1.0, 1.0), hi * a)
        sh = clamp01((v - 0.58) / 0.42) ** 1.6 * 0.42
        lip = math.exp(-((v - 0.95) / 0.04) ** 2) * 0.35
        if inside is not None and y > H / 2:
            lip = max(lip, math.exp(-(inside / 2.5) ** 2) * 0.35)
        return over(col, (0.0, 0.0, 0.0, 1.0), max(sh, lip) * a)

    return _tapered(shade)


def bar_outline():
    """A fine gold edge round the whole tapered bar (top, bottom, left end and both slants of the point), matching
    the gold hairline of the icon rings. Same layout as the tapered overlays: drawn 64x32 units, point 16."""
    body = TAPER_W - TAPER_POINT
    H = TAPER_H
    WIDTH = 1.5                                    # px of the 2x art: ~0.75 units, like the ring's line

    def fn(x, y):
        if x < body:
            inside = min(x, y, H - y)
        else:
            inside = _tip_inside(x - body, y)
        if inside < -2.5 or inside > 6:
            return (0, 0, 0, 0)
        d = abs(inside - WIDTH)                    # the line runs just inside the bar's edge
        col = (0.0, 0.0, 0.0, 0.0)
        col = over(col, LIGHT + (1.0,), math.exp(-(d / 2.2) ** 2) * 0.25)   # soft glow
        return over(col, (1.0, 0.84, 0.55, 1.0), cover(d - WIDTH / 2 - 0.25))

    return TAPER_W, TAPER_H, image(TAPER_W, TAPER_H, fn)


def bar_track():
    """128x64 (drawn 64x32): the dark track behind the fill, its right quarter the pointed end (the 9-slice right
    margin), with a faint dark rim."""
    W, H = 128, 64
    POINT = 32                                     # px: the point's length (drawn 16 units)

    def fn(x, y):
        if x < W - POINT:
            inside = min(x, y, H - y)
        else:
            inside = _tip_inside(x - (W - POINT), y) if True else 0
        a = cover(-inside + 0.5) if x >= W - POINT else 1.0
        if a <= 0:
            return (0, 0, 0, 0)
        col = (0.05, 0.045, 0.05, 0.86 * a)
        if inside < 2.0:
            col = over(col, (0.0, 0.0, 0.0, 1.0), 0.6 * a)
        return col

    return W, H, image(W, H, fn)


def crop(make, x0, x1):
    """A vertical strip (columns x0..x1) of a generated image: the bar's body or point as a piece of its own."""
    def piece():
        w, h, px = make()
        out = []
        for y in range(h):
            row = px[(y * w + x0) * 4:(y * w + x1) * 4]
            out += row
        return x1 - x0, h, out
    return piece


# The shaped bar is built from separate pieces in game (9-slicing the point proved unreliable): a body, stretched
# along the bar, and a point of fixed length. Both are cut from the same full-length art, so they meet exactly.
BODY = (40, 88)     # a slice of the body: no ends
POINT = (96, 128)   # the right 32 px: the point


THEME_LUA = """-- Demi-human theme: moonstone and wispy gold light (High Elf meets Dwarven). Colours are linear RGB (0..1).
-- Sizes are UI units (1920x1080 reference): the art in ui/ is made at twice these, so it stays sharp.
return {
    gold = { 0.86, 0.66, 0.26 },          -- highlights (the selected row in lists)
    ink = { 1.0, 0.84, 0.52 },            -- lettering on title bars, drag bars and buttons: gold light
    heading = { 0.95, 0.76, 0.40 },
    label = { 0.88, 0.88, 0.92 },
    dim = { 0.58, 0.60, 0.66 },
    panelColor = { 0.07, 0.08, 0.10, 0.94 },
    panelTile = 128,
    frameSize = 64,
    frameMargin = 0.453,                   -- 58 of the frame art's 128 pixels are corner
    panelPad = { 18, 16, 18, 16 },
    titleArt = "title_line.png",
    titleSize = { 128, 32 },
    titleMargin = { 0.25, 0.35 },
    keySize = 64,
    keyMargin = 0.32,
}
"""


def main():
    theme = sys.argv[1] if len(sys.argv) > 1 else "demihuman"
    if theme != "demihuman":
        raise SystemExit("only the Demi-human theme is generated so far")
    out = os.path.join(ROOT, theme, "ui")
    os.makedirs(out, exist_ok=True)
    for name, make in (("panel_stone.png", moonstone_tile), ("panel_stone_slate.png", tile_of(slate)),
                       ("panel_stone_marble.png", tile_of(black_marble)), ("panel_frame.png", light_frame),
                       ("title_line.png", title_line), ("title_plate.png", title_plate),
                       ("keycap.png", light_keycap), ("bar_bevel.png", bar_bevel),
                       ("bar_facet.png", bar_facet), ("bar_track.png", bar_track), ("bar_cap.png", bar_cap),
                       ("bar_facet_tapered.png", bar_facet_tapered), ("bar_bevel_tapered.png", bar_bevel_tapered),
                       ("bar_outline.png", bar_outline),
                       ("bar_track_body.png", crop(bar_track, *BODY)), ("bar_tip_track.png", crop(bar_track, *POINT)),
                       ("bar_facet_body.png", crop(bar_facet_tapered, *BODY)),
                       ("bar_tip_facet.png", crop(bar_facet_tapered, *POINT)),
                       ("bar_bevel_body.png", crop(bar_bevel_tapered, *BODY)),
                       ("bar_tip_bevel.png", crop(bar_bevel_tapered, *POINT)),
                       ("bar_outline_body.png", crop(bar_outline, *BODY)),
                       ("bar_tip_outline.png", crop(bar_outline, *POINT))):
        w, h, px = make()
        png(os.path.join(out, name), w, h, px)
        print("wrote", name, w, "x", h)
    with open(os.path.join(ROOT, theme, "theme.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(THEME_LUA)
    print("wrote theme.lua")


if __name__ == "__main__":
    main()
