"""Panel backgrounds (Pillow): the paintings in tools/backgrounds_src/<name>.png made into seamless tiles.

Frame Mage's own panels (and the windows it restyles) are filled with a tiled picture: these, painted by an image model and kept in backgrounds_src/ so the
tiles rebuild without it. Each is scaled to 512 px (drawn 256 units, so the painting's detail repeats seldom) and made seamless: the picture shifted by half its size, and its middle blended over the edges,
so each edge meets the opposite one. Written to Elven's ui/ as panel_bg_<name>.png (every theme finds it there).

Run: python tools/make_backgrounds.py   (then make_stone_discs.py, for the menu shortcuts' round versions)
"""
import os
import sys

from PIL import Image, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "backgrounds_src")
OUT = os.path.join(HERE, "..", "FrameMage", "Art", "themes", "elven", "ui")
S = 512

# Per background: (brightness, contrast) against the painting, 1 = as painted (text must read on it)
TONE = {
    "parchment": (0.62, 0.9),   # (painted bright and orange: darkened to a deep umber)
    "starfield": (1.5, 1.25),   # (painted almost black)
    "forge": (0.95, 0.8),       # (its hammer marks blotchy where the halves blend: flattened a little)
}

# Points of light added over a painting (the starfield's stars and the ember ash's embers were too faint to survive
# the scaling): how many, their colors, how big; seeded so the tile rebuilds the same, and each wraps round the
# tile's edges, so they tile too. `halo`: a wider, fainter glow round each (embers smolder)
STARS = {
    "starfield": {"count": 140, "tints": ((1.0, 1.0, 1.0), (0.8, 0.88, 1.0), (0.9, 0.82, 1.0))},
    "embers": {"count": 110, "tints": ((1.0, 0.55, 0.12), (1.0, 0.38, 0.06), (1.0, 0.72, 0.30)), "halo": 3.5,
               "seed": 11},
}


def add_stars(img, spec):
    import math
    import random
    rnd = random.Random(spec.get("seed", 7))
    px = img.load()
    w, h = img.size
    halo = spec.get("halo", 0)
    for _ in range(spec["count"]):
        cx, cy = rnd.uniform(0, w), rnd.uniform(0, h)
        big = rnd.random() < 0.12
        r = rnd.uniform(1.4, 2.4) if big else rnd.uniform(0.6, 1.2)
        k0 = rnd.uniform(0.35, 0.85) if big else rnd.uniform(0.2, 0.55)
        tint = rnd.choice(spec["tints"])
        if halo:
            # the glow first: wide and faint, in a deeper version of the ember's color
            hr = r * halo
            reach = int(hr * 2.5) + 1
            for dy in range(-reach, reach + 1):
                for dx in range(-reach, reach + 1):
                    x, y = int(cx) + dx, int(cy) + dy
                    k = 0.28 * k0 * math.exp(-(math.hypot(x + 0.5 - cx, y + 0.5 - cy) / hr) ** 2)
                    if k < 0.01:
                        continue
                    x, y = x % w, y % h
                    p = px[x, y]
                    deep = (tint[0] * 0.9, tint[1] * 0.4, tint[2] * 0.2)
                    px[x, y] = tuple(int(p[i] + (255 * deep[i] - p[i]) * k) for i in range(3))
        reach = int(r * 3) + 1
        for dy in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                x, y = int(cx) + dx, int(cy) + dy
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                k = k0 * math.exp(-(d / r) ** 2)
                if k < 0.01:
                    continue
                x, y = x % w, y % h
                p = px[x, y]
                px[x, y] = tuple(int(p[i] + (255 * tint[i] - p[i]) * k) for i in range(3))
    return img


def seamless(img):
    """Each edge blended into the opposite one: the picture shifted by half, its (continuous) middle faded in over
    the edges, along both axes."""
    w, h = img.size
    for axis in (0, 1):
        shifted = Image.new(img.mode, (w, h))
        if axis == 0:
            shifted.paste(img.crop((w // 2, 0, w, h)), (0, 0))
            shifted.paste(img.crop((0, 0, w // 2, h)), (w - w // 2, 0))
        else:
            shifted.paste(img.crop((0, h // 2, w, h)), (0, 0))
            shifted.paste(img.crop((0, 0, w, h // 2)), (0, h - h // 2))
        n = w if axis == 0 else h
        fade = n // 4
        ramp = [int(255 * max(0.0, 1.0 - min(i, n - 1 - i) / fade)) for i in range(n)]
        mask = Image.new("L", (w, h))
        if axis == 0:
            mask.putdata([ramp[x] for y in range(h) for x in range(w)])
        else:
            mask.putdata([ramp[y] for y in range(h) for x in range(w)])
        img = Image.composite(shifted, img, mask)
    return img


def make(name):
    img = Image.open(os.path.join(SRC, name + ".png")).convert("RGB").resize((S, S), Image.LANCZOS)
    img = seamless(img)
    bright, contrast = TONE.get(name, (1.0, 1.0))
    if bright != 1.0:
        img = ImageEnhance.Brightness(img).enhance(bright)
    if contrast != 1.0:
        img = ImageEnhance.Contrast(img).enhance(contrast)
    if name in STARS:
        img = add_stars(img, STARS[name])
    img.save(os.path.join(OUT, "panel_bg_%s.png" % name))
    print("background:", name)


def main():
    names = sys.argv[1:] or sorted(f[:-4] for f in os.listdir(SRC) if f.endswith(".png"))
    for n in names:
        make(n)


if __name__ == "__main__":
    main()
