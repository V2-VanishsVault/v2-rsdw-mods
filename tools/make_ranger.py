"""Ranger theme art (the ranged class): of the woods - every border a band of grained wood with a green line inlaid
down its middle, soft rounded corners (where Warrior's are cut), and leaves for ornament. The material-and-inlay
drawing is shared with the other class themes (tools/inlay.py).

    python tools/make_theme.py ranger

Makes the same pieces as Demi-human under the same names (anything not made here - the stones, the progress-bar
overlays - comes from Demi-human, so the player's stone choice carries over):
  panel_frame.png     9-slice: the wooden band with its green inlay, rounded corners; in each corner a carved plate
                      where the inlay frills out into two curling scrolls, and a leaf
  panel_flourish.png  a carved wooden crest on the top line, green inlay scrolls in it and a leaf rising from it
  check_mark.png      two wooden strokes with the green inlay, tapering to points
  check_box*.png      a rounded box of dark glass in the wooden border (and the tick)
  button_rim*.png     the rounded wooden border alone, for game buttons (selected: the inlay glows brighter)
  tip_band.png        tooltip band: dark glass between wooden strips that round off at both ends
  title_line.png      title bars / buttons / text boxes: dark glass in a narrow wooden border
  keycap.png          rounded keycap in the wooden border
Same sizes and 9-slice margins as Demi-human, so theme.lua only changes colors.
"""
import math

import inlay
import vitals_art
from inlay import rod
from make_icons import sd_round_rect
from make_theme import clamp01, cover, image, mix, over

GLASS = (0.03, 0.035, 0.03)
MAT, LINE = inlay.WOOD, inlay.GREEN
BRIGHT = {"core": (0.88, 1.0, 0.72), "edge": (0.22, 0.72, 0.22), "glow": (0.50, 1.0, 0.40)}
GROOVE = 0.22    # the inlay is a fine line in wood (a narrower channel than the steel's)
LEAF_DK, LEAF, LEAF_HI = (0.04, 0.10, 0.035), (0.14, 0.27, 0.08), (0.36, 0.46, 0.22)   # deep, natural ivy green


def leaf(col, x, y, a, b, w):
    """A leaf from its stem end a to its tip b, w wide at the middle: pointed at the tip, lit on the side facing
    the light, with a pale vein down the middle and a soft shadow under it."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy) or 1e-9
    ux, uy = dx / L, dy / L
    t = ((x - a[0]) * ux + (y - a[1]) * uy) / L
    across = (x - a[0]) * -uy + (y - a[1]) * ux
    tc = clamp01(t)
    half = w * math.sin(math.pi * tc) ** 0.7 * (1 - 0.25 * tc)
    d = abs(across) - half if 0 <= t <= 1 else math.hypot(x - (a[0] + tc * dx), y - (a[1] + tc * dy))
    if d > 6:
        return col
    if d > 0:
        return over(col, (0.0, 0.0, 0.0, 1.0), 0.4 * math.exp(-(d / 2.2) ** 2))
    # the side whose outward direction faces the light is lit; the other is in shade
    side = (-uy, ux) if across >= 0 else (uy, -ux)
    lit = clamp01(0.5 + 0.9 * (side[0] * inlay.LIGHT[0] + side[1] * inlay.LIGHT[1]))
    k = clamp01(abs(across) / max(half, 0.6))
    c = mix(mix(LEAF_DK, LEAF, 0.4 + 0.6 * lit), LEAF_DK, k * k * 0.5)
    if abs(across) < 0.7 and 0.04 < t < 0.92:      # the vein
        c = mix(c, LEAF_HI, 0.7)
    return over(col, c + (1.0,), cover(d))


# --- panel frame -----------------------------------------------------------------------------------------------
# The frame is wide and wraps round the window (theme.lua frameToEdge + frameOutset): 512px art drawn at 256 UI
# units, its corners 96px (48 units) and its edges TILED (frameDraw "border") - every pattern along the band repeats
# every 320px (inlay.TILE), the middle section's length, so the edges repeat seamlessly instead of stretching. The
# band 34px of the art (17 units) from its very edge, its center line 18px in (frameLine 9).

FS = 512
BAND_HW = 17.0
BAND_C = 18.0


def frame_sd(x, y):
    """The panel frame's center line: a square BAND_C in from the art's edge. Measured square (the larger of the
    two distances), so the band's outer corners are square too: the panel's stone behind is square, and a rounded
    corner would show it. Each corner is covered by its carved block anyway (the band runs under it)."""
    h = FS / 2 - BAND_C
    return max(abs(x - FS / 2) - h, abs(y - FS / 2) - h)


def fold(c):
    """A coordinate in its corner's terms (0 at the art's edge, growing inward)."""
    return c if c < FS / 2 else FS - c


# The corner's carving, in corner coordinates (u, v from the corner): a carved wooden block over the band's
# corner. The band's green line runs in from each edge to a ring of inlay round a four-petalled rosette, and from
# the ring two small tendrils curl off toward the panel, one either side of the diagonal.
RING_C, RING_R = 21.0, 9.0
_meet = RING_C + math.sqrt(RING_R ** 2 - (18.0 - RING_C) ** 2)     # where the line (18 in) meets the ring
LINES = [[(48.0, 18.0), (_meet, 18.0)], [(18.0, 48.0), (18.0, _meet)]]
ROSE = [(RING_C + 5.5 * math.cos(2 * t) * math.cos(t), RING_C + 5.5 * math.cos(2 * t) * math.sin(t))
        for t in [i * 2 * math.pi / 160 for i in range(161)]]
_a = math.radians(22)
TENDRIL = [(RING_C + RING_R * math.cos(_a), RING_C + RING_R * math.sin(_a))] +     inlay.scroll((0, 0), 37.0, 30.5, 5.5, 1.2, math.pi * 0.95, 0.85, steps=50)[1:]
TENDRIL2 = [(q, p) for (p, q) in TENDRIL]


def corner_art(u, v):
    """Distance to the corner's green inlay (lines, ring, rosette, tendrils)."""
    d = abs(math.hypot(u - RING_C, v - RING_C) - RING_R)
    for pts in [ROSE, TENDRIL, TENDRIL2]:
        d = min(d, inlay.polyline_dist(u, v, pts))
    return d


def corner_plate_sd(x, y):
    """The carved block over each corner, on top of the band (both edges run in under it): square at the frame's
    own corner, reaching just past the band (48px, 24 units, the band being 17) so it barely enters the window,
    its inner side scooped out in a curve."""
    u, v = fold(x), fold(y)
    box = max(abs(u - 24.0) - 24.0, abs(v - 24.0) - 24.0)
    scoop = 24.0 - math.hypot(u - 64.0, v - 64.0)
    return max(box, scoop)


# --- the log --------------------------------------------------------------------------------------------------
# Each side of the frame is a single rounded log (after the user's reference: smooth, barkless, deep wavy grain,
# knots) with an ivy vine winding along it. Everything along it - its bulges, its grain, its knots, the vine and
# its leaves - repeats exactly every inlay.TILE px, so the frame's edges tile seamlessly.

TILE = inlay.TILE
TAU = 2 * math.pi
LOG_LO, LOG, LOG_HI = (0.11, 0.075, 0.05), (0.37, 0.26, 0.17), (0.58, 0.45, 0.32)   # weathered brown
GROOVE_C = (0.09, 0.06, 0.04)
VINE_DK, VINE = (0.08, 0.09, 0.05), (0.27, 0.27, 0.15)   # woody, barky
# knots: (along, across share of the radius, size px) - each repeats every TILE
KNOTS = ((70.0, -0.30, 5.5), (232.0, 0.35, 4.0))
# ivy leaves along the vine: (along, which side of the vine: 1 / -1, length px)
IVY = ((14.0, 1, 23.0), (70.0, -1, 21.0), (128.0, 1, 22.0), (186.0, -1, 20.0), (244.0, 1, 23.0), (296.0, -1, 19.0))


def wave(along, terms):
    """A sum of sines repeating every TILE: terms = ((amplitude, cycles per tile, phase), ...)."""
    return sum(a * math.sin(TAU * k * along / TILE + p) for (a, k, p) in terms)


def log_shape(along):
    """The log's center offset and radius (px) at a point along it: it bulges, thins and wanders a little."""
    center = wave(along, ((1.1, 1, 0.4), (0.5, 3, 2.0)))
    radius = 14.6 + wave(along, ((1.3, 1, 1.9), (0.7, 2, 0.3), (0.4, 5, 4.1)))
    return center, radius


def wrap(a, ref):
    """`a` moved by whole tiles to the copy nearest `ref` (for things that repeat along the log)."""
    return a + round((ref - a) / TILE) * TILE


def vine_at(along, radius):
    """Where the vine crosses the log (across, px) and its slope, winding over it twice a tile."""
    k = TAU * 2 / TILE
    v = 0.62 * radius * math.sin(k * along + 0.8) + 1.5 * math.sin(k * 2.5 * along)
    dv = 0.62 * radius * k * math.cos(k * along + 0.8) + 1.5 * k * 2.5 * math.cos(k * 2.5 * along)
    return v, dv


def ivy_leaf(col, px, py, a, b, w, tone=1.0):
    """An ivy leaf from stem end a to tip b: broad and heart-shaped at the stem, pointed at the tip, dark green with
    a paler vein."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy) or 1e-9
    ux, uy = dx / L, dy / L
    t = ((px - a[0]) * ux + (py - a[1]) * uy) / L
    across = (px - a[0]) * -uy + (py - a[1]) * ux
    if t < -0.15 or t > 1.05:
        return col
    tc = clamp01(t)
    half = w * math.sin(math.pi / 2 * min(1.0, tc * 2.4 + 0.2)) * (1 - tc) ** 0.75   # broad near the stem, pointed
    half *= 1.0 + 0.22 * math.sin(tc * math.pi * 3.0 - 0.6)                          # ivy's shallow lobes
    d = abs(across) - half
    if d > 4:
        return col
    if d > 0:
        return over(col, (0.0, 0.0, 0.0, 1.0), 0.22 * math.exp(-((d - 0.6) / 2.2) ** 2))
    k = clamp01(abs(across) / max(half, 0.5))
    lit_side = across * (ux * inlay.LIGHT[1] - uy * inlay.LIGHT[0]) < 0
    lit = 0.6 + 0.4 * (1 if lit_side else -0.5)
    c = mix(mix(LEAF_DK, LEAF, lit), LEAF_DK, k * k * 0.55)
    c = tuple(min(1.0, ch * tone) for ch in c)          # each leaf a slightly different green
    # mottled, as real leaves are: soft patches of lighter and yellower green
    mot = inlay.pfbm(px / 5.0 + a[0], py / 5.0 + a[1], 64, 137)
    c = mix(c, (0.30, 0.36, 0.14), 0.35 * clamp01(mot * 1.6 - 0.6))
    c = mix(c, LEAF_DK, 0.35 * clamp01(1 - (half - abs(across)) / 1.2))    # a darker rim, not an outline
    # side veins running out from the midrib toward the tip, and the midrib itself
    vph = t * 5.0 - k * 1.6
    vein = math.exp(-((vph - math.floor(vph) - 0.5) / 0.09) ** 2) * (1 - k) * (t < 0.9)
    c = mix(c, LEAF_HI, 0.22 * vein)
    if abs(across) < 0.55 and t < 0.88:
        c = mix(c, LEAF_HI, 0.45)
    # the waxy gloss of an ivy leaf on its lit half
    if lit_side:
        c = mix(c, (0.80, 0.86, 0.70), 0.22 * math.exp(-((k - 0.35) / 0.18) ** 2) * (1 - t))
    return over(col, c + (1.0,), clamp01(0.5 - d * 0.7))    # a soft edge


def log_band(col, x, y):
    """The frame's log at (x, y): its shadow, its rounded body with deep wavy grain and knots, and the ivy."""
    d = frame_sd(x, y)
    if abs(d) > BAND_HW + 6:
        return col
    g = inlay.gradient(frame_sd, x, y)
    along = x * -g[1] + y * g[0]
    center, radius = log_shape(along)
    a = d - center                                    # across the log, from its own center line
    aa = abs(a)
    if aa > radius:                                   # its shadow on the stone (the ivy may still reach out here)
        col = over(col, (0.0, 0.0, 0.0, 1.0), 0.55 * math.exp(-((aa - radius) / 3.0) ** 2))
    else:
        col = log_body(col, along, a, radius, g)
    return ivy(col, along, a, radius)


def log_body(col, along, a, radius, g):
    """The log's rounded body at (along, a): deep wavy grain bending round its knots, lit from the top left."""
    aa = abs(a)
    p = a / radius                                    # -1..1 across
    # knots: grain flows round them (pushed away across the log), and their rings
    push, knot_c = 0.0, None
    for (ka, kp, ks) in KNOTS:
        kx = wrap(ka, along)
        ky = kp * radius
        dist = math.hypot(along - kx, a - ky)
        push += (2.4 * ks) * math.exp(-(dist / (ks * 2.2)) ** 2) * (1 if a >= ky else -1)
        if dist < ks:
            ring = 0.5 + 0.5 * math.sin(dist * 2.1)
            knot_c = mix(mix(LOG_LO, LOG, 0.35), LOG, 0.25 + 0.5 * ring * (dist / ks))
    # the grain: a few deep grooves flowing along the log, wavering, bending round the knots
    flow = a + push + 2.2 * (inlay.pfbm(along / 64.0, a / 20.0 + 3.0, TILE // 64, 61) - 0.5) * 2 \
        + 0.8 * math.sin(TAU * 3 * along / TILE + a * 0.2)
    ph = flow / 5.5
    f = ph - math.floor(ph)
    # each groove's width wanders, so they read as worn cracks in the wood rather than drawn lines
    gw = 0.05 + 0.05 * inlay.pfbm(along / 32.0, flow / 5.5 + 7.0, TILE // 32, 79)
    groove = math.exp(-((f - 0.5) / gw) ** 2)
    rim = math.exp(-((f - 0.5 + gw * 1.8) / 0.06) ** 2)  # the lit lip on the near side of each groove
    # and fine grain between them
    f2 = flow / 1.7 - math.floor(flow / 1.7)
    fine = math.exp(-((f2 - 0.5) / 0.14) ** 2)
    tone = inlay.pfbm(along / 40.0, a / 8.0 + 9.0, TILE // 40, 67)
    c = mix(LOG, LOG_HI, clamp01(tone * 1.3 - 0.2))
    fiber = inlay.pfbm(along / 4.0, a * 1.3, TILE // 4, 71) - 0.5
    c = mix(c, LOG_HI if fiber > 0 else LOG_LO, abs(fiber) * 0.45)
    c = mix(c, LOG_LO, 0.16 * fine)
    c = mix(c, LOG_HI, 0.18 * rim)
    c = mix(c, GROOVE_C, 0.6 * groove)
    if knot_c is not None:
        c = knot_c
    # round: lit on the side turned to the light, shaded on the other, with a soft sheen along the top
    slope = p / math.sqrt(max(1 - p * p, 0.02))
    nx, ny, nz = g[0] * slope, g[1] * slope, 1.0
    n = math.sqrt(nx * nx + ny * ny + nz * nz)
    diff = clamp01((nx * inlay.LIGHT[0] + ny * inlay.LIGHT[1] + nz * inlay.LIGHT[2]) / n)
    spec = clamp01((nx * inlay.HALF[0] + ny * inlay.HALF[1] + nz * inlay.HALF[2]) / n) ** 14
    c = mix(LOG_LO, c, clamp01(0.15 + 1.1 * diff))
    c = mix(c, LOG_HI, 0.25 * spec)
    return over(col, c + (1.0,), cover(aa - radius))


WRAP = TILE / 3.0   # px along the board for one turn of the ivy round it (three turns a tile: it repeats seamlessly)
# leaves on each turn: (where on the turn - 0 and 1 being the board's edges as the vine crosses its face -, which
# side of the vine, length px, tone)
WRAP_LEAVES = ((0.22, 1, 19.0, 0.92), (0.50, -1, 21.0, 1.05), (0.78, 1, 17.0, 0.97))


def wrap_at(along, radius):
    """The ivy spiraling round the board, seen from the front: (across px, slope, in front?). One turn every WRAP
    px: across the face on a slant from one edge to the other, then round behind the board, out of sight."""
    th = TAU * along / WRAP + 0.5
    r = radius - 1.2
    return r * math.cos(th), -r * math.sin(th) * TAU / WRAP, math.sin(th) > 0


def ivy(col, along, a, radius):
    """The ivy at (along, a): a vine wound round the board - crossing its face on a slant, slipping round its edges
    and behind it - with leaves growing from where it's in front, alternating either side, and its shadow."""
    vv, dv, front = wrap_at(along, radius)
    vd = abs(a - vv) / math.sqrt(1 + dv * dv)
    th = TAU * along / WRAP + 0.5
    near = math.sin(th)                                  # 1 at the middle of the face, 0 at the edges
    if front and vd < 5.0:
        # its shadow on the board, cast down and away from the light
        sd_ = abs(a - vv - 1.4) / math.sqrt(1 + dv * dv)
        col = over(col, (0.0, 0.0, 0.0, 1.0), 0.32 * near * math.exp(-((sd_ - 1.2) / 1.5) ** 2))
        wv = 1.5 + 0.4 * near                            # a little thicker where it's nearest
        k = clamp01(1 - vd / wv)
        bark = inlay.pfbm(along / 2.0, vd + 9.0, TILE // 2, 83)
        c = mix(mix(VINE_DK, VINE, k * (0.5 + 0.5 * near)), VINE_DK, 0.4 * bark)
        col = over(col, c + (1.0,), clamp01(0.5 - (vd - wv) * 0.8))
    turn = math.floor((along - (-0.5 * WRAP / TAU)) / WRAP)
    for t0 in (turn - 1, turn, turn + 1):
        base = t0 * WRAP - 0.5 * WRAP / TAU             # where this turn's front crossing starts
        for j, (f, side, ll, tone) in enumerate(WRAP_LEAVES):
            lx = base + f * WRAP / 2.0                   # the front half of the turn is its first WRAP / 2
            if abs(along - lx) > ll + 8:
                continue
            sv, sdv, _ = wrap_at(lx, radius)
            nrm = math.hypot(1, sdv)
            tip = (lx + side * sdv / nrm * ll * 0.55 + ll * 0.55, sv - side * ll / nrm * 0.55)
            tip = (tip[0], max(-radius + 1.0, min(radius - 1.0, tip[1])))
            col = ivy_leaf(col, along, a, (lx, sv), tip, ll * 0.5, tone)
    return col


def plank(col, x, y):
    """The frame's board at (x, y), after the user's references (planed, worn planks): planed oak with dense fine
    grain, its long edges worn darker with a thin lit arris along them, a few light scratches; the ivy over it."""
    d = frame_sd(x, y)
    hw = BAND_HW - 0.5
    ad = abs(d)
    if ad > hw + 6:
        return col
    g = inlay.gradient(frame_sd, x, y)
    along = x * -g[1] + y * g[0]
    if ad > hw:
        col = over(col, (0.0, 0.0, 0.0, 1.0), 0.5 * math.exp(-((ad - hw) / 3.0) ** 2))
    else:
        c = inlay.oak(along, d)
        e = hw - ad                                   # in from the board's edge
        side = 1.0 if d >= 0 else -1.0
        lit = clamp01(0.5 + 0.9 * side * (g[0] * inlay.LIGHT[0] + g[1] * inlay.LIGHT[1]))
        c = mix(c, (0.06, 0.035, 0.02), 0.55 * math.exp(-e / 2.2) + 0.18 * math.exp(-e / 7.0))   # worn edges
        c = mix(c, (0.80, 0.64, 0.44), 0.30 * lit * math.exp(-((e - 1.3) / 0.6) ** 2))           # the arris
        # light scratches: short, sparse, a little across the grain
        sc = inlay.pnoise_xy((along + d * 2.0) / 10.0, d * 0.9 + 70.0, TILE // 10, 256, 131)
        c = mix(c, (0.68, 0.52, 0.34), 0.35 * clamp01((sc - 0.86) / 0.06))
        col = over(col, c + (1.0,), cover(ad - hw))
    return ivy(col, along, d, hw)


BIND = (80.0, 96.0)     # where each corner's ivy binding wraps the log: px in from the frame's edge (it ends exactly
                        # where the corner piece does - 96px - so none of it lands in the repeating section)


def binding(col, x, y):
    """Near each corner, ivy wound tightly round the log a few times. It sits where the tiled edge meets the
    corner piece, so where the repeat is cut short (the log can't line up there) the join falls on its edge."""
    u, v = fold(x), fold(y)
    if v < 44 and BIND[0] <= u < BIND[1]:
        e = u
    elif u < 44 and BIND[0] <= v < BIND[1]:
        e = v
    else:
        return col
    d = frame_sd(x, y)
    if abs(d) > BAND_HW + 1.5:
        return col
    k = clamp01(1 - abs(d) / (BAND_HW + 1.5))
    strand = ((e - BIND[0]) + d * 0.55) % 5.6
    c = mix(VINE_DK, VINE, clamp01(1 - abs(strand - 2.6) / 2.4) * (0.4 + 0.6 * k))
    if strand > 4.9:
        c = VINE_DK
    edge = min(e - BIND[0], BIND[1] - e)
    c = mix((0.02, 0.06, 0.02), c, clamp01(edge / 1.4))
    return over(col, c + (1.0,), cover(abs(d) - BAND_HW - 1.5))


def panel_frame():
    """512px (drawn 256 units), 96px corners and tiled edges (repeating every 320px): each side a single planed
    oak board - dense fine grain, worn darker edges, a few scratches - with an ivy vine winding along it, bound round with ivy near each corner. Over each corner sits
    a small carved block (covering where the logs meet) with a green inlay ring round a rosette, two tendrils
    curling off it, and a small leaf pointing from the block into the panel."""
    S = FS

    def fn(x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        u, v = fold(x), fold(y)
        if min(u, v) > 74:      # the frame's empty middle
            return col
        col = plank(col, x, y)
        col = binding(col, x, y)
        if u < 72 and v < 72:
            col = leaf(col, u, v, (42.0, 42.0), (57.0, 57.0), 4.2)
            col = inlay.plate(col, x, y, corner_plate_sd, inlay.OAK, bevel=4.0, grain=(0.0, -1.0))
            d = corner_plate_sd(x, y)
            if d < 0.5:
                col = inlay.inlay_line(col, corner_art(u, v), LINE, width=1.3, channel=2.1, mat=inlay.OAK)
                col = inlay.inlay_line(col, abs(d + 5.0), LINE, width=0.7, channel=1.2, mat=inlay.OAK)  # edging
        return col

    return S, S, image(S, S, fn)


# --- flourish --------------------------------------------------------------------------------------------------

def flourish_fn():
    """The flourish's drawing at 128x64 art (it's sampled at twice that size for the wide frame's flourish): a
    carved wooden crest standing on the top line (y = BASE), edged with green inlay and holding two green scrolls
    that curl out and up from its foot, a leaf rising from its middle past its top; a wooden twig runs out along
    the line from either side, a leaf lying along each."""
    CX, BASE = 64.0, 46.0
    RX, RY = 24.0, 20.0
    RIGHT = inlay.scroll((CX + 1.0, BASE - 3.0), CX + 9.0, BASE - 11.0, 7.0, 1.3, math.pi / 2, -0.95)
    LEFT = [(2 * CX - px, py) for (px, py) in RIGHT]

    def crest_sd(x, y):
        k = math.hypot((x - CX) / RX, (y - BASE) / RY)
        return max((k - 1) * min(RX, RY), y - BASE - 1.0)

    def fn(x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        for side in (-1, 1):
            col = rod(col, x, y, (CX, BASE), (CX + side * 56.0, BASE), 2.8, 0.0, MAT)
            col = leaf(col, x, y, (CX + side * 24.0, BASE - 1.0), (CX + side * 46.0, BASE - 9.0), 3.6)
        col = inlay.plate(col, x, y, crest_sd, MAT)
        d = crest_sd(x, y)
        if d < 0.5:
            col = inlay.inlay_line(col, abs(d + 4.0), LINE, mat=MAT)
            col = inlay.inlay_line(col, min(inlay.polyline_dist(x, y, RIGHT), inlay.polyline_dist(x, y, LEFT)),
                                   LINE, mat=MAT)
        return leaf(col, x, y, (CX, BASE - 13.0), (CX, BASE - 33.0), 3.2)

    return fn


def panel_flourish():
    """256x128 (drawn 128x64 units, flourishLine 46): the flourish at twice its drawing's size, for the wide frame."""
    fn = flourish_fn()
    return 256, 128, image(256, 128, lambda x, y: fn(x / 2, y / 2))


# --- tick and checkboxes ---------------------------------------------------------------------------------------

def check_mark():
    """64x64 (drawn 32): two wooden strokes meeting at the joint, widest there and tapering to points, with the
    green inlay down their middle."""
    S = 64
    A, B, C = (12.0, 32.0), (26.0, 47.0), (54.0, 12.0)

    def fn(x, y):
        col = rod((0.0, 0.0, 0.0, 0.0), x, y, B, A, 4.6, 0.0, MAT, LINE)
        return rod(col, x, y, B, C, 4.6, 0.0, MAT, LINE)

    return S, S, image(S, S, fn)


def round_border(S, center, r, hw, glass, bright=False):
    """A square rounded border of plain wood - too narrow to hold an inlay - with dark glass inside when `glass`;
    `bright` (selected, hovered) rings it with green light. As fn(x, y)."""
    h = S / 2 - center

    def sd(x, y):
        return sd_round_rect(x, y, S / 2, S / 2, h, h, r)

    def fn(x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        d = sd(x, y)
        if glass:
            col = GLASS + ((0.74 if bright else 0.64) * cover(d + hw),)
        if bright:
            col = over(col, LINE["glow"] + (1.0,), 0.5 * math.exp(-((abs(d) - hw) / 3.0) ** 2))
        return inlay.band(col, x, y, sd, hw, MAT, LINE, groove=0.0)

    return fn


def button_rim(bright=False):
    """64x64 (drawn 32), 9-slice: the rounded wooden border alone (nothing inside), over a game button;
    `bright` = selected (ringed with green light)."""
    S = 64
    return S, S, image(S, S, round_border(S, 2.6, 8.0, 1.25, False, bright))


def check_box(ticked=False, bright=False):
    """64x64 (drawn 32): a rounded box of dark glass in the wooden border, optionally with the tick."""
    S = 64
    rim = round_border(S, 3.0, 8.0, 1.4, True, bright)
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
    """256x64 (drawn 128x32), 9-slice: dark glass with rounded corners in a narrow border of plain wood
    (too narrow for an inlay)."""
    W, H = 256, 64
    C, HW = 3.2, 1.6      # a thin border: it mustn't crowd what the bar or button holds

    def sd(x, y):
        return sd_round_rect(x, y, W / 2, H / 2, W / 2 - C, H / 2 - C, 14)

    def fn(x, y):
        col = GLASS + (0.64 * cover(sd(x, y) + HW),)
        return inlay.band(col, x, y, sd, HW, MAT, LINE, groove=0.0)

    return W, H, image(W, H, fn)


def selected_plate():
    """256x64 (drawn 128x32), 9-slice like the title bars: a solid plate of planed oak with softly rounded
    corners, its edges worn darker and a lit edge along the top - a title bar picked into the editor's group."""
    WD, H = 256, 64
    C = 2.0

    def sd(x, y):
        return sd_round_rect(x, y, WD / 2, H / 2, WD / 2 - C, H / 2 - C, 10)

    def fn(x, y):
        d = sd(x, y)
        if d > 1:
            return (0.0, 0.0, 0.0, 0.0)
        e = -d
        # (the same all the way across: the plate's middle is stretched, and anything that changed along it showed as
        # a seam - the grain runs straight along it, varying down it only)
        c = inlay.oak(53.0, y * 0.6)
        c = mix(c, (0.06, 0.035, 0.02), 0.55 * math.exp(-e / 2.0) + 0.15 * math.exp(-e / 6.0))
        lit = inlay.facing(sd, x, y)
        c = mix(c, (0.80, 0.64, 0.44), 0.35 * max(0.0, lit) * math.exp(-((e - 1.4) / 0.7) ** 2))
        # Demi-human's build: a raised rim, a groove cut 8px in, the face sunk under it
        gsd = lambda px, py: sd_round_rect(px, py, WD / 2, H / 2, WD / 2 - 9, H / 2 - 9, 5)
        g = gsd(x, y)
        c = inlay.framed_plate(c, d, g, lit, inlay.facing(gsd, x, y),
                               (0.86, 0.70, 0.48), (0.10, 0.06, 0.03), (0.07, 0.04, 0.02))
        col = c + (cover(d),)
        return col

    return WD, H, image(WD, H, fn)


def ornament():
    """32x32 (drawn about 9 units): a brass peg driven into the oak, lit from the top left - set into each end of a
    filled button, beside its text (a separate picture, so it's never stretched with the button)."""
    S = 32
    c0 = (S - 1) / 2
    R = 10.5

    def fn(x, y):
        r = math.hypot(x - c0, y - c0)
        if r > R + 1:
            return (0, 0, 0, 0)
        lit = clamp01(0.5 - ((x - c0) * 0.4 + (y - c0) * 0.9) / (R * 1.6))
        c = mix((0.30, 0.18, 0.06), (0.98, 0.84, 0.52), 0.15 + 0.8 * lit)
        c = mix(c, (1.0, 0.95, 0.80), 0.5 * math.exp(-((x - c0 + 3) ** 2 + (y - c0 + 3) ** 2) / 6.0))
        c = mix(c, (0.12, 0.07, 0.02), 0.65 * clamp01((r - (R - 1.5)) / 1.5))
        return c + (clamp01(R + 0.5 - r),)

    return S, S, image(S, S, fn)


def tip_band():
    """256x128 (drawn 128x64), 9-slice like Demi-human's: no sides - dark translucent glass that fades out toward
    both ends, edged top and bottom by a strip of oak with the green inlay. Nothing changes down its height, so a tall tooltip
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
        return inlay.band(col, x, y, sd, HW, MAT, LINE, groove=GROOVE, alpha=k)

    return W, H, image(W, H, fn)


def keycap():
    """128px keycap (drawn 64): dark face in a rounded wooden border with the green inlay."""
    S = 128

    def sd(x, y):
        return sd_round_rect(x, y, S / 2, S / 2, S / 2 - 6, S / 2 - 6, 16)

    def fn(x, y):
        col = GLASS + (0.88 * cover(sd(x, y) + 2.5),)
        return inlay.band(col, x, y, sd, 2.5, MAT, LINE, groove=0.0)

    return S, S, image(S, S, fn)


PIECES = (
    ("panel_frame.png", panel_frame), ("panel_flourish.png", panel_flourish),
    ("check_mark.png", check_mark), ("tip_band.png", tip_band),
    ("button_rim.png", lambda: button_rim()), ("button_rim_on.png", lambda: button_rim(True)),
    ("check_box.png", lambda: check_box()), ("check_box_hover.png", lambda: check_box(bright=True)),
    ("check_box_on.png", lambda: check_box(True)), ("check_box_on_hover.png", lambda: check_box(True, True)),
    ("title_line.png", title_line), ("plate_selected.png", selected_plate), ("plate_ornament.png", ornament), ("keycap.png", keycap),
) + vitals_art.pieces(inlay.OAK, LINE, vitals_art.wood_edge)

THEME_LUA = """-- Ranger theme (the ranged class): of the woods - rounded corners, every border grained wood with a green inlay,
-- leaves for ornament. Colors are linear RGB (0..1). Only what differs from Demi-human is here; everything else
-- (sizes, the stones) comes from it. The art in ui/ is made by tools/make_theme.py ranger, at Demi-human's sizes.
return {
    gold = { 0.22, 0.58, 0.18 },          -- highlights (the selected row in lists): ranger green
    ink = { 0.80, 1.0, 0.64 },            -- lettering on title bars, drag bars and buttons: leaf light
    heading = { 0.58, 0.88, 0.42 },
    label = { 0.90, 0.88, 0.82 },
    dim = { 0.60, 0.58, 0.50 },
    panelColor = { 0.07, 0.07, 0.05, 0.94 },
    selectedInk = { 0.98, 0.93, 0.82 },     -- lettering on a selected (grouped) title bar: light on the oak
    -- the level-up celebration: a green number (two tones: fill and outline) on a pulsing green glow, sparks to match
    celebrate = {
        number = { 0.58, 0.94, 0.36 }, outline = { 0.04, 0.17, 0.04 }, glow = { 0.36, 0.88, 0.24 },
        title = { 0.92, 0.98, 0.84 }, label = { 0.76, 0.96, 0.60 },
        sparks = { { 0.58, 0.94, 0.36 }, { 0.96, 0.86, 0.42 }, { 0.30, 0.72, 0.26 }, { 0.92, 1, 0.82 }, { 0.78, 0.56, 0.30 } },
    },
    -- the wide border: 512px art drawn at 256 units, wrapping round each window - from its edge (frameToEdge) out
    -- 10 units more (frameOutset), so the band's inner edge sits about where Demi-human's line does and never
    -- covers a window's contents - its corners 48 units and its edges tiled, not stretched (frameDraw "border")
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = 9,
    frameToEdge = true,
    frameOutset = 10,
    frameDraw = "border",
    panelPad = { 40, 36, 40, 36 },         -- Frame Mage's own panels: their contents clear the band and corners
    framePadExtra = 26,                    -- (and panels with their own inset get this much more)
    flourishSize = { 128, 64 },            -- the flourish at twice Demi-human's size, to match
    flourishLine = 46,
    tipFlourishScale = 0.5,                -- tooltips keep a small one
}
"""
