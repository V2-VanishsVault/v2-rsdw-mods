"""Generates Frame Mage's own UI icons (no game art) into FrameMage/Art/_ui/.

    python tools/make_icons.py

Pure standard library: shapes are drawn as signed-distance fields with 4x4 supersampling and written as
RGBA PNGs. Used by the hotkey legend: mouse glyphs always, keycap only if the game's keycap texture can't
be found at runtime.
"""
import math
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "FrameMage", "Art", "_ui")
SS = 4  # supersampling per axis


def png(path, w, h, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def sd_round_rect(px, py, cx, cy, hw, hh, r):
    qx, qy = abs(px - cx) - (hw - r), abs(py - cy) - (hh - r)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r


def render(w, h, layers):
    """layers: list of (sdf(px,py)->distance, rgba) painted in order; inside = distance <= 0."""
    out = [0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            acc = [0.0, 0.0, 0.0, 0.0]  # premultiplied
            for sy in range(SS):
                for sx in range(SS):
                    px, py = x + (sx + 0.5) / SS, y + (sy + 0.5) / SS
                    c = [0.0, 0.0, 0.0, 0.0]
                    for sdf, col in layers:
                        if sdf(px, py) <= 0:
                            r, g, b, a = col(px, py) if callable(col) else col
                            # "over" compositing, premultiplied
                            c = [r * a + c[0] * (1 - a), g * a + c[1] * (1 - a), b * a + c[2] * (1 - a), a + c[3] * (1 - a)]
                    for i in range(4):
                        acc[i] += c[i]
            n = SS * SS
            a = acc[3] / n
            i = (y * w + x) * 4
            if a > 0:
                out[i:i + 4] = [round(acc[0] / n / a * 255), round(acc[1] / n / a * 255), round(acc[2] / n / a * 255), round(a * 255)]
    return out


def sd_polygon(pts):
    """Signed distance to a simple polygon (negative inside)."""
    def f(px, py):
        d = float("inf")
        inside = False
        n = len(pts)
        for i in range(n):
            ax, ay = pts[i]
            bx, by = pts[i - 1]
            ex, ey = bx - ax, by - ay
            wx, wy = px - ax, py - ay
            t = max(0.0, min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
            d = min(d, math.hypot(wx - ex * t, wy - ey * t))
            if (ay > py) != (by > py) and px < (bx - ax) * (py - ay) / (by - ay) + ax:
                inside = not inside
        return -d if inside else d
    return f


def mirror(w, sdf):
    return lambda px, py: sdf(w - px, py)


def ring(sdf, width):
    return lambda px, py: abs(sdf(px, py)) - width / 2


LIGHT = (0.92, 0.88, 0.80, 1.0)  # parchment white, close to the game's key text
GOLD = (1.0, 0.78, 0.33, 1.0)
DARK = (0.06, 0.05, 0.04, 0.85)


def mouse(button):
    w, h = 48, 64
    cx, cy, hw, hh = 24, 32, 17, 27
    body = lambda px, py: sd_round_rect(px, py, cx, cy, hw, hh, 16)
    top_half = lambda px, py: max(body(px, py), py - 27)       # upper part (buttons)
    left_btn = lambda px, py: max(top_half(px, py), px - (cx - 1.5))
    right_btn = lambda px, py: max(top_half(px, py), (cx + 1.5) - px)
    layers = [(body, DARK)]
    if button == "left":
        layers.append((left_btn, GOLD))
    elif button == "right":
        layers.append((right_btn, GOLD))
    layers += [
        (ring(body, 3), LIGHT),
        (lambda px, py: max(abs(py - 27) - 1.25, abs(px - cx) - hw + 2), LIGHT),  # button split, horizontal
        (lambda px, py: max(abs(px - cx) - 1.25, py - 27, 5 - py), LIGHT),         # button split, vertical
    ]
    if button == "middle":
        layers.append((lambda px, py: sd_round_rect(px, py, cx, 17, 3, 7, 3), GOLD))
    return w, h, render(w, h, layers)


def keycap():
    w, h = 64, 64
    outer = lambda px, py: sd_round_rect(px, py, 32, 32, 29, 29, 9)
    inner = lambda px, py: sd_round_rect(px, py, 32, 29, 23, 22, 6)
    return w, h, render(w, h, [(outer, (0.17, 0.15, 0.13, 0.95)), (ring(outer, 2.5), LIGHT),
                               (inner, (0.24, 0.21, 0.18, 1.0))])


# --- Ribbon banner (editor title) ---------------------------------------------------------------------
# Three pieces sharing one height: left end, a wide centre strip the game stretches to fit the text, right end.
# Band (front) spans BAND_TOP..BAND_BOT; the swallowtail ends sit lower and behind, joined by a shadowed fold.
# Material: aged parchment - mottled cream, burnt irregular edges, darker tails, brown fold shadow.
RH = 80
BAND_TOP, BAND_BOT = 4, 58
TAIL_TOP, TAIL_BOT = 22, 74
END_W = 76
MID_W = 384  # wide, so the mottling barely stretches between short and long names
PARCH = (0.87, 0.77, 0.57)
STAIN = (0.70, 0.56, 0.34)
BURNT = (0.36, 0.22, 0.11)
INK_EDGE = (0.27, 0.16, 0.08, 1.0)


def _hash(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def value_noise(x, y, seed=0):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = _hash(ix, iy, seed), _hash(ix + 1, iy, seed)
    c, d = _hash(ix, iy + 1, seed), _hash(ix + 1, iy + 1, seed)
    return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy


def fbm(x, y, seed=0):
    total, amp, freq = 0.0, 0.55, 1.0
    for o in range(4):
        total += amp * value_noise(x * freq, y * freq, seed + o)
        amp *= 0.5
        freq *= 2.1
    return total / 1.0


def mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(3))


def parchment(px, py, edge_dist, shade=1.0):
    """Parchment colour at a point `edge_dist` units inside the cloth's edge."""
    stain = fbm(px / 26.0, py / 18.0, 7)                    # broad blotches
    grain = value_noise(px / 2.2, py / 1.3, 3)               # fine fibres, slightly horizontal
    c = mix(PARCH, STAIN, (stain - 0.42) * 1.6)
    c = tuple(v * (0.94 + 0.08 * grain) for v in c)
    wobble = (fbm(px / 9.0, py / 9.0, 11) - 0.5) * 5.0      # ragged burn line
    burn = 1 - max(0.0, min(1.0, (edge_dist + wobble) / 7.0))
    c = mix(c, BURNT, burn ** 1.6 * 0.95)
    return (c[0] * shade, c[1] * shade, c[2] * shade, 1.0)


def band_colour(px, py):
    d = min(py - BAND_TOP, BAND_BOT - py)
    # a gentle curve: the middle of the strip catches a little more light
    t = (py - BAND_TOP) / (BAND_BOT - BAND_TOP)
    return parchment(px, py, d, 0.93 + 0.09 * math.cos((t - 0.45) * math.pi))


def band_layers(x0, x1):
    band = lambda px, py, x0=x0, x1=x1: max(BAND_TOP - py, py - BAND_BOT, x0 - px, px - x1)
    edge_top = lambda px, py, x0=x0, x1=x1: max(abs(py - (BAND_TOP + 0.6)) - 0.6, x0 - px, px - x1)
    edge_bot = lambda px, py, x0=x0, x1=x1: max(abs(py - (BAND_BOT - 0.6)) - 0.6, x0 - px, px - x1)
    shadow = lambda px, py, x0=x0, x1=x1: max(BAND_BOT - py, py - (BAND_BOT + 4), x0 - px, px - x1)
    return [(shadow, (0.10, 0.06, 0.02, 0.30)), (band, band_colour), (edge_top, INK_EDGE), (edge_bot, INK_EDGE)]


def ribbon_end_left():
    w = END_W
    notch = 20  # depth of the swallowtail fork
    join = w - 14  # where the band (front) starts in this piece
    tail = sd_polygon([(0, TAIL_TOP), (join + 6, TAIL_TOP), (join + 6, TAIL_BOT), (0, TAIL_BOT),
                       (notch, (TAIL_TOP + TAIL_BOT) / 2)])
    tail_colour = lambda px, py: parchment(px + 900, py, -tail(px, py), 0.80)  # behind the band: in shade
    fold = sd_polygon([(join, BAND_BOT), (w, BAND_BOT), (join, TAIL_BOT)])
    layers = [(tail, tail_colour), (ring(tail, 1.0), INK_EDGE), (fold, (0.30, 0.19, 0.09, 1.0))]
    # the band's own end: a short piece of the front cloth, with the turn of the fold shaded
    layers += band_layers(join, w + 1)
    curl = sd_polygon([(join, BAND_TOP), (join + 4, BAND_TOP), (join + 4, BAND_BOT), (join, BAND_BOT)])
    layers.append((curl, (0.42, 0.28, 0.14, 1.0)))
    return w, RH, render(w, RH, layers)


def ribbon_end_right():
    w, h, px = ribbon_end_left()
    out = [0] * len(px)
    for y in range(h):
        for x in range(w):
            i, j = (y * w + x) * 4, (y * w + (w - 1 - x)) * 4
            out[i:i + 4] = px[j:j + 4]
    return w, h, out


def ribbon_mid():
    return MID_W, RH, render(MID_W, RH, band_layers(-1, MID_W + 1))


# --- Celebration art ----------------------------------------------------------------------------------
# White so the game can tint them per burst (SetColorAndOpacity multiplies).

def radial(w, h, fn):
    """Per-pixel radial image: fn(r) -> (rgb, alpha) with r = distance from centre / (w/2)."""
    out = [0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            r = math.hypot(x + 0.5 - w / 2, y + 0.5 - h / 2) / (w / 2)
            (cr, cg, cb), a = fn(r, x + 0.5 - w / 2, y + 0.5 - h / 2)
            i = (y * w + x) * 4
            out[i:i + 4] = [round(cr * 255), round(cg * 255), round(cb * 255), round(max(0, min(1, a)) * 255)]
    return out


def spark():
    """A firework spark: hot core, soft halo, four faint rays."""
    w = 32
    def fn(r, dx, dy):
        core = math.exp(-(r / 0.16) ** 2)
        halo = math.exp(-(r / 0.45) ** 2) * 0.55
        ang = math.atan2(dy, dx)
        rays = (abs(math.cos(2 * ang)) ** 24) * math.exp(-(r / 0.9) ** 2) * 0.5
        return (1, 1, 1), min(1, core + halo + rays)
    return w, w, radial(w, w, fn)


def glow():
    """Soft round glow behind the level number."""
    w = 128
    def fn(r, dx, dy):
        return (1, 1, 1), math.exp(-(r / 0.55) ** 2) * (1 - min(1, r) ** 4)
    return w, w, radial(w, w, fn)


def chevron():
    """A downward chevron (V), white so it can be tinted; rotated in game to point right when collapsed."""
    w = 32
    def seg(ax, ay, bx, by, r):
        def f(px, py):
            ex, ey = bx - ax, by - ay
            t = max(0.0, min(1.0, ((px - ax) * ex + (py - ay) * ey) / (ex * ex + ey * ey)))
            return math.hypot(px - ax - ex * t, py - ay - ey * t) - r
        return f
    left = seg(8, 12, 16, 21, 2.6)
    right = seg(16, 21, 24, 12, 2.6)
    return w, w, render(w, w, [(lambda px, py: min(left(px, py), right(px, py)), (1, 1, 1, 1))])


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (w, h, px) in {
        "fm_mouse_left.png": mouse("left"),
        "fm_mouse_right.png": mouse("right"),
        "fm_mouse_middle.png": mouse("middle"),
        "fm_keycap.png": keycap(),
        "fm_ribbon_left.png": ribbon_end_left(),
        "fm_ribbon_right.png": ribbon_end_right(),
        "fm_ribbon_mid.png": ribbon_mid(),
        "fm_spark.png": spark(),
        "fm_glow.png": glow(),
        "fm_chevron.png": chevron(),
    }.items():
        png(os.path.join(OUT, name), w, h, px)
        print("wrote", name, w, "x", h)


if __name__ == "__main__":
    main()
