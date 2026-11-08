"""The ring behind the player's vital-bar icons (Frame Mage's own art; needs Pillow).

    python tools/make_badges.py

A dark disc with a hairline gold ring (the High Elf look). The game's own icons (stamina, health, special) are
drawn on top of it, slightly smaller. Drawn at 4x and downsampled; written to
FrameMage/Art/themes/demihuman/ui/badge_ring.png at 112x112. (glyph helpers below are kept for future badges)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "FrameMage", "Art", "themes", "demihuman", "ui")
SIZE = 112
SS = 4
N = SIZE * SS

GOLD = (255, 214, 140)
COLOURS = {"stamina": ((255, 214, 72), (190, 130, 20)),
           "health": ((236, 60, 60), (140, 18, 22)),
           "special": ((120, 180, 255), (40, 90, 190))}


def disc():
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c, r = N / 2, N / 2 - 6 * SS
    # soft glow behind the ring
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([c - r - 3 * SS, c - r - 3 * SS, c + r + 3 * SS, c + r + 3 * SS],
                                 outline=GOLD + (90,), width=6 * SS)
    im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(4 * SS)))
    d = ImageDraw.Draw(im)
    # dark face, slightly lighter at the top
    for i in range(int(r), 0, -SS):
        t = i / r
        v = int(14 + 18 * (1 - t))
        d.ellipse([c - i, c - i - (1 - t) * 4 * SS, c + i, c + i - (1 - t) * 4 * SS], fill=(v, v + 2, v + 8, 255))
    d.ellipse([c - r, c - r, c + r, c + r], outline=GOLD + (255,), width=int(2.2 * SS))
    d.ellipse([c - r + 5 * SS, c - r + 5 * SS, c + r - 5 * SS, c + r - 5 * SS], outline=GOLD + (60,), width=SS)
    return im


def glyph_layer(draw_fn, colours):
    """Draw the glyph as a mask, then fill it with a top-to-bottom gradient in the bar's colours."""
    mask = Image.new("L", (N, N), 0)
    draw_fn(ImageDraw.Draw(mask))
    hi, lo = colours
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    for y in range(N):
        t = min(1, max(0, (y - N * 0.25) / (N * 0.5)))
        gd.line([(0, y), (N, y)], fill=tuple(int(hi[k] * (1 - t) + lo[k] * t) for k in range(3)) + (255,))
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    # a thin dark edge so the glyph reads on the disc
    edge = mask.filter(ImageFilter.MaxFilter(2 * SS + 1))
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 200), (0, 0), edge)
    return Image.alpha_composite(shadow, out)


def P(x, y):
    """Badge-relative coordinates (0..1) to pixels."""
    return (x * N, y * N)


def line(d, pts, w):
    d.line([P(*p) for p in pts], fill=255, width=int(w * N), joint="curve")
    for p in (pts[0], pts[-1]):
        x, y = P(*p)
        r = w * N / 2
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)


def runner(d):
    """A figure mid-stride, leaning forward."""
    hx, hy, hr = 0.585, 0.285, 0.068
    d.ellipse([P(hx - hr, hy - hr), P(hx + hr, hy + hr)], fill=255)
    w = 0.072
    line(d, [(0.555, 0.385), (0.47, 0.58)], w)                       # torso
    line(d, [(0.545, 0.42), (0.66, 0.50), (0.73, 0.43)], w * 0.8)     # front arm
    line(d, [(0.53, 0.42), (0.42, 0.45), (0.35, 0.38)], w * 0.8)      # back arm
    line(d, [(0.47, 0.58), (0.60, 0.66), (0.57, 0.78)], w * 0.85)     # front leg
    line(d, [(0.47, 0.58), (0.38, 0.70), (0.26, 0.69)], w * 0.85)     # back leg


def heart(d):
    cx, top = 0.5, 0.37
    r = 0.13
    d.ellipse([P(cx - 2 * r + 0.012, top - r), P(cx + 0.012, top + r)], fill=255)
    d.ellipse([P(cx - 0.012, top - r), P(cx + 2 * r - 0.012, top + r)], fill=255)
    d.polygon([P(cx - 2 * r + 0.018, top + 0.04), P(cx + 2 * r - 0.018, top + 0.04), P(cx, 0.76)], fill=255)


def sword(d, angle):
    """One sword pointing up-and-out, rotated about the badge centre."""
    def rot(x, y):
        x, y = x - 0.5, y - 0.5
        c, s = math.cos(angle), math.sin(angle)
        return (0.5 + x * c - y * s, 0.5 + x * s + y * c)
    blade = [(0.475, 0.70), (0.475, 0.26), (0.5, 0.20), (0.525, 0.26), (0.525, 0.70)]
    guard = [(0.40, 0.70), (0.60, 0.70), (0.60, 0.735), (0.40, 0.735)]
    grip = [(0.483, 0.735), (0.517, 0.735), (0.517, 0.81), (0.483, 0.81)]
    for poly in (blade, guard, grip):
        d.polygon([P(*rot(*p)) for p in poly], fill=255)
    px, py = rot(0.5, 0.835)
    d.ellipse([P(px - 0.03, py - 0.03), P(px + 0.03, py + 0.03)], fill=255)


def swords(d):
    sword(d, math.radians(-38))
    sword(d, math.radians(38))


def badge(name, draw_fn):
    im = Image.alpha_composite(disc(), glyph_layer(draw_fn, COLOURS[name]))
    im = im.resize((SIZE, SIZE), Image.LANCZOS)
    path = os.path.join(OUT, "badge_%s.png" % name)
    im.save(path)
    print("wrote", os.path.basename(path), SIZE, "x", SIZE)


def shadow():
    """A soft round shadow for under the ring: 160x160 (the ring is 112 of it), blurred, black."""
    S2 = 160
    im = Image.new("RGBA", (S2 * SS, S2 * SS), (0, 0, 0, 0))
    c, r = S2 * SS / 2, (SIZE / 2 - 6) * SS
    ImageDraw.Draw(im).ellipse([c - r, c - r, c + r, c + r], fill=(0, 0, 0, 200))
    im = im.filter(ImageFilter.GaussianBlur(9 * SS))
    return im.resize((S2, S2), Image.LANCZOS)


def main():
    """The ring that sits behind the game's own bar icons (stamina, health, special), and its shadow."""
    os.makedirs(OUT, exist_ok=True)
    im = disc().resize((SIZE, SIZE), Image.LANCZOS)
    path = os.path.join(OUT, "badge_ring.png")
    im.save(path)
    print("wrote", os.path.basename(path), SIZE, "x", SIZE)
    shadow().save(os.path.join(OUT, "badge_shadow.png"))
    print("wrote badge_shadow.png 160 x 160")
    # the hand-drawn glyph badges are no longer used: the game's own icons sit on the ring
    for old in ("badge_stamina.png", "badge_health.png", "badge_special.png"):
        try:
            os.remove(os.path.join(OUT, old))
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    main()
