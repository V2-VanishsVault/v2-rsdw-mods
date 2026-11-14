"""Draws Storage Mage's default-look tab icons, one pair per bag.

python -I tools/draw_tab_art.py            all bags
python -I tools/draw_tab_art.py Gems Ores  some bags

Writes StorageMage/Art/default/T_SM_Tab_<Bag>_Normal.png and _Highlight.png (the names are a contract with
Frame Mage themes; <Bag> is the bag's tag name: ToolBelt, Herbs, Gems, Ores, Seeds, Fishing, RuneEssence).
The game's tab icons (T_Icon_<Name>_Normal / _Highlight) are shown at 62x32; these are drawn at 2x (124x64)
for sharpness and shown at 62x32. Shapes are drawn 4x larger again and scaled down for smooth edges.

Each icon is a white-on-black mask in a 64x64 design box centred in the canvas: 255 adds, 0 cuts (cuts show
as dark lines, since the outline behind fills them).
"""
import math
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

OUT_W, OUT_H = 124, 64          # 2x the 62x32 brush
SS = 4                          # supersampling on top of that
W, H = OUT_W * SS, OUT_H * SS

# The game's tab textures include the plate behind the icon, so ours do too. Colours sampled from an in-game
# screenshot (2026-11-13) of the Ammo tab (normal) and the Quest tab (highlight). Plate: about 49 of the 62
# units wide, centred, full height. Each plate: outer edge, frame, a bright top line, inner line, and a
# vertical gradient (top, bottom) inside.
COLOURS = {
    "normal": {"fill": (138, 140, 134, 255), "dark": (22, 20, 18, 170),
               # In game the frame line vanished against the inside (2026-11-13): the game's line is ~(96, 93, 84)
               # on an inside of ~70, so a darker inside and a brighter, olive line.
               "plate": {"edge": (48, 48, 48), "frame": (118, 112, 88), "top": (124, 118, 94), "inner": (64, 62, 60),
                         "grad": ((76, 74, 72), (64, 62, 61)), "alpha": 232, "line": 2.0}},
    "highlight": {"fill": (212, 206, 182, 255), "dark": (40, 30, 18, 190),
                  "plate": {"edge": (110, 92, 62), "frame": (222, 198, 128), "top": (240, 222, 160),
                            "inner": (118, 98, 64), "grad": ((160, 136, 96), (128, 106, 72)), "alpha": 255,
                            "line": 2.0}},   # the selected tab's gold frame is bolder
}
# Plate and icon placement, measured against the game's tabs on screen (2026-11-13): the game's plate is 94 x 60
# of the 124 x 64 texture, touching the bottom with a gap above; its icon sits a little below the plate's centre.
PLATE_W = 94
PLATE_TOP = 4                   # its edges matched the game's plates in game (2026-11-13)
# Each icon is fitted by its own outline, so they all match whatever their drawing's extent: measured in game
# (2026-11-13), the game's icons are about 35 of the texture's 64 pixels tall, up to ~40 wide, centred 36 down.
ICON_MAX_H = 35
ICON_MAX_W = 40                 # 44 made wide icons (Ores, Fishing) bigger than the game's
ICON_CENTRE_Y = 36
ICON_SCALE = 1.0                # design box -> canvas, before fitting
ICON_DY = 0


def P(x, y):
    """Design units -> supersampled pixels."""
    s = H / 64.0
    return (W / 2 + (x - 32) * ICON_SCALE * s, (32 + (y - 32) * ICON_SCALE + ICON_DY) * s)


def poly(d, pts, fill=255):
    d.polygon([P(x, y) for x, y in pts], fill=fill)


def circle(d, cx, cy, r, fill=255):
    (x0, y0), (x1, y1) = P(cx - r, cy - r), P(cx + r, cy + r)
    d.ellipse([x0, y0, x1, y1], fill=fill)


def rotated_rect(cx, cy, length, width, angle_deg):
    a = math.radians(angle_deg)
    dx, dy = math.cos(a), math.sin(a)
    nx, ny = -dy, dx
    hl, hw = length / 2, width / 2
    return [(cx + dx * hl + nx * hw, cy + dy * hl + ny * hw), (cx + dx * hl - nx * hw, cy + dy * hl - ny * hw),
            (cx - dx * hl - nx * hw, cy - dy * hl - ny * hw), (cx - dx * hl + nx * hw, cy - dy * hl + ny * hw)]


def line(d, x1, y1, x2, y2, w, fill=0):
    length = math.hypot(x2 - x1, y2 - y1)
    ang = math.degrees(math.atan2(y2 - y1, x2 - x1))
    poly(d, rotated_rect((x1 + x2) / 2, (y1 + y2) / 2, length, w, ang), fill)


def leaf(d, x, y, length, width, angle_deg, fill=255, rib=True):
    """A pointed leaf from its base (x, y) along angle_deg (0 = right, -90 = up)."""
    a = math.radians(angle_deg)
    ux, uy, nx, ny = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
    side1, side2 = [], []
    for i in range(0, 21):
        t = i / 20
        hw = width / 2 * math.sin(math.pi * t) ** 0.8
        px, py = x + ux * length * t, y + uy * length * t
        side1.append((px + nx * hw, py + ny * hw))
        side2.append((px - nx * hw, py - ny * hw))
    poly(d, side1 + side2[::-1], fill)
    if rib:
        line(d, x + ux * length * 0.15, y + uy * length * 0.15, x + ux * length * 0.8, y + uy * length * 0.8, 0.9)


def seed(d, cx, cy, length, width, angle_deg):
    """A teardrop seed centred at (cx, cy), pointed end along angle_deg."""
    a = math.radians(angle_deg)
    ux, uy, nx, ny = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
    pts = []
    for i in range(0, 41):
        th = 2 * math.pi * i / 40
        along = math.cos(th) * length / 2
        across = math.sin(th) * width / 2 * (0.55 + 0.45 * (1 - math.cos(th)) / 2) ** 1.0
        if math.cos(th) > 0:                       # narrow towards the point
            across *= 1 - 0.75 * math.cos(th) ** 2
        pts.append((cx + ux * along + nx * across, cy + uy * along + ny * across))
    poly(d, pts)
    line(d, cx - ux * length * 0.3, cy - uy * length * 0.3, cx + ux * length * 0.3, cy + uy * length * 0.3, 0.9)


def shard(d, cx, cy, length, width, angle_deg, tip):
    """A crystal: a bar along angle_deg with a pointed end `tip` long beyond its far end, and a centre ridge."""
    a = math.radians(angle_deg)
    ux, uy, nx, ny = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
    hl, hw = length / 2, width / 2
    far = (cx + ux * hl, cy + uy * hl)
    near = (cx - ux * hl, cy - uy * hl)
    poly(d, [(near[0] + nx * hw, near[1] + ny * hw), (far[0] + nx * hw, far[1] + ny * hw),
             (far[0] + ux * tip, far[1] + uy * tip),
             (far[0] - nx * hw, far[1] - ny * hw), (near[0] - nx * hw, near[1] - ny * hw)])
    line(d, near[0], near[1], far[0] + ux * tip, far[1] + uy * tip, 0.9)


def new_mask():
    m = Image.new("L", (W, H), 0)
    return m, ImageDraw.Draw(m)


# ---- the icons ----------------------------------------------------------------------------------------------

def toolbelt():
    """A pickaxe and an axe crossed behind a belt with a buckle."""
    m, d = new_mask()
    poly(d, rotated_rect(32, 30, 43, 4.2, 48))      # handles, short enough to end behind the belt
    poly(d, rotated_rect(32, 30, 43, 4.2, -48))
    # Pickaxe head: a bar across the up-left handle end, tapering to two points.
    hx, hy = 32 - math.cos(math.radians(48)) * 20, 30 - math.sin(math.radians(48)) * 20
    perp = math.radians(48 + 90)
    px, py = math.cos(perp), math.sin(perp)
    ax, ay = math.cos(math.radians(48)), math.sin(math.radians(48))
    poly(d, [(hx + px * 14 + ax * 4, hy + py * 14 + ay * 4), (hx + px * 2 - ax * 2.6, hy + py * 2 - ay * 2.6),
             (hx - px * 2 - ax * 2.6, hy - py * 2 - ay * 2.6), (hx - px * 14 + ax * 4, hy - py * 14 + ay * 4),
             (hx - px * 3 + ax * 2.4, hy - py * 3 + ay * 2.4), (hx + px * 3 + ax * 2.4, hy + py * 3 + ay * 2.4)])
    # Axe head on the up-right handle end: a blade sticking out sideways with a curved edge.
    ux, uy = math.cos(math.radians(-48)), math.sin(math.radians(-48))
    nx, ny = -uy, ux
    bx, by = 32 + ux * 20, 30 + uy * 20

    def at(along, out):
        return (bx + ux * along + nx * out, by + uy * along + ny * out)
    blade = [at(1, 1.5), at(-7, 1.5), at(-10.5, 9)]
    for t in range(0, 11):
        a = -0.9 + 1.8 * t / 10
        blade.append(at(-4.5 + math.sin(a) * 9.5, 9 + math.cos(a) * 3.5))
    blade.append(at(3.5, 9))
    poly(d, blade)
    poly(d, [at(2.2, -2.2), at(-1.5, -2.2), at(-1.5, 2), at(2.2, 2)])
    # The belt, with a buckle and stitching.
    poly(d, [(6, 38), (58, 38), (58, 47), (6, 47)])
    poly(d, [(25.5, 36), (38.5, 36), (38.5, 49), (25.5, 49)], 0)
    poly(d, [(27, 37.5), (37, 37.5), (37, 47.5), (27, 47.5)])
    poly(d, [(29.5, 40), (34.5, 40), (34.5, 45), (29.5, 45)], 0)
    poly(d, [(31.3, 40), (32.7, 40), (32.7, 45), (31.3, 45)])
    for x in list(range(9, 24, 4)) + list(range(41, 56, 4)):
        poly(d, [(x, 41.8), (x + 1.4, 41.8), (x + 1.4, 43.2), (x, 43.2)], 0)
    return m


def herbs():
    """A leafy sprig: a curved stem with leaves on alternate sides."""
    m, d = new_mask()
    stem = [(32 + 3 * math.sin(t / 10 * 2.2), 54 - 40 * t / 10) for t in range(11)]
    for (x1, y1), (x2, y2) in zip(stem, stem[1:]):
        line(d, x1, y1, x2, y2, 2.2, 255)
    leaf(d, 33.5, 44, 15, 8, -25)        # right, low
    leaf(d, 33.0, 36, 13, 7.5, -150)     # left
    leaf(d, 34.5, 28, 12, 7, -30)        # right, high
    leaf(d, 33.5, 21, 10, 6, -140)       # left, high
    leaf(d, 34.3, 16, 9, 5.5, -80)       # the tip
    return m


def gems():
    """A cut gem, seen from the side, with its facets."""
    m, d = new_mask()
    poly(d, [(17, 24), (25, 13), (39, 13), (47, 24), (32, 51)])
    line(d, 17, 24, 47, 24, 1.1)                       # girdle
    line(d, 25, 13, 28.5, 24, 1.0)                     # crown facets
    line(d, 39, 13, 35.5, 24, 1.0)
    line(d, 32, 13, 28.5, 24, 1.0)
    line(d, 32, 13, 35.5, 24, 1.0)
    line(d, 28.5, 24, 32, 51, 1.0)                     # pavilion facets
    line(d, 35.5, 24, 32, 51, 1.0)
    line(d, 21, 24, 32, 51, 0.9)
    line(d, 43, 24, 32, 51, 0.9)
    gx, gy = 49, 11                                    # a sparkle, clear of the gem
    poly(d, [(gx, gy - 4.5), (gx + 1.1, gy - 1.1), (gx + 4.5, gy), (gx + 1.1, gy + 1.1), (gx, gy + 4.5),
             (gx - 1.1, gy + 1.1), (gx - 4.5, gy), (gx - 1.1, gy - 1.1)])
    return m


def ores():
    """A lump of rock with nuggets of ore in it."""
    m, d = new_mask()
    poly(d, [(11, 46), (10, 37), (15, 27), (25, 19), (37, 18), (47, 23), (53, 32), (54, 43), (48, 50), (20, 51)])
    for pts in ([(20, 31), (26, 27), (29, 33), (24, 37)],          # nuggets: cut a ring, fill the middle
                [(35, 26), (41, 25), (43, 30), (38, 32)],
                [(33, 39), (40, 37), (44, 43), (37, 46), (32, 44)],
                [(16, 41), (21, 40), (22, 45), (17, 46)]):
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        poly(d, [(cx + (x - cx) * 1.45, cy + (y - cy) * 1.45) for x, y in pts], 0)
        poly(d, pts)
    line(d, 28, 21, 31, 27, 0.9)                                   # cracks
    line(d, 47, 33, 50, 39, 0.9)
    return m


def seeds():
    """Three seeds, the middle one sprouting."""
    m, d = new_mask()
    seed(d, 19, 43, 17, 11, -55)
    seed(d, 45, 43, 17, 11, -125)
    seed(d, 32, 40, 18, 12, -90)
    line(d, 32, 32, 32, 19, 2.3, 255)                              # the sprout
    leaf(d, 32, 20, 13, 7.5, -35)
    leaf(d, 32, 21.5, 12, 7, -150)
    return m


def fishing():
    """A fish with a hook beside it."""
    m, d = new_mask()
    body = []
    for i in range(0, 41):
        th = 2 * math.pi * i / 40
        x = 30 + math.cos(th) * 16
        y = 33 + math.sin(th) * 8.5 * (1 - 0.25 * math.cos(th))
        body.append((x, y))
    poly(d, body)
    poly(d, [(44, 33), (54, 24), (51, 33), (54, 42)])              # tail
    poly(d, [(26, 25.5), (33, 21), (38, 26)])                      # dorsal fin
    circle(d, 20, 31, 1.8, 0)                                      # eye
    line(d, 25, 27, 24, 39, 1.0)                                   # gill
    return m


def runeessence():
    """The game's rune essence shape: a chunk of stone with two peaks and a notch on top, tapering towards the
    bottom and leaning a little right, with crystal streaks across its lower right."""
    m, d = new_mask()
    poly(d, [(22, 12), (29.5, 21.5), (38.5, 11), (45.5, 17), (47.5, 32), (44, 44.5), (36.5, 52), (27, 52.5),
             (19.5, 46.5), (16, 32), (17, 18)])
    line(d, 29.5, 21.5, 30.5, 38, 1.0)                             # the ridge down from the notch
    line(d, 30.5, 38, 22, 47, 0.9)                                 # the front face's lower edge
    for (x1, y1, x2, y2) in ((33, 38, 47, 31.5), (31.5, 44, 45.5, 38), (33, 49.5, 42.5, 45.5)):
        line(d, x1, y1, x2, y2, 1.7)                               # crystal streaks
    return m


ICONS = {"ToolBelt": toolbelt, "Herbs": herbs, "Gems": gems, "Ores": ores, "Seeds": seeds,
         "Fishing": fishing, "RuneEssence": runeessence}


FALLOFF = 3.5                   # output px of soft dark edge outside the frame line (the game's plates fade out)
INNER_SHADE = 7.0               # output px over which the inside darkens towards the frame


def plate(kind):
    """The tab's plate, like the game's (close-up, 2026-11-13): a soft dark falloff around the outside, a thin
    frame line inset from the edge, and inside a slightly mottled vertical gradient that darkens towards the
    frame. Computed per output pixel, then scaled up to the drawing size."""
    import random
    p = COLOURS[kind]["plate"]
    a = p["alpha"]
    small = Image.new("RGBA", (OUT_W, OUT_H), (0, 0, 0, 0))
    px = small.load()
    x0 = (OUT_W - PLATE_W) / 2
    x1 = x0 + PLATE_W
    y0, y1 = PLATE_TOP, OUT_H
    (r0, g0, b0), (r1, g1, b1) = p["grad"]
    rnd = random.Random(7)                      # fixed seed: the same file every run
    for y in range(OUT_H):
        for x in range(OUT_W):
            cx, cy = x + 0.5, y + 0.5
            # Distance in from the plate's outer edge. Sides and top only: the game's plates have no bottom
            # border, they run straight into the tab row's line below.
            dist = min(cx - x0, x1 - cx, cy - y0)
            if dist <= 0:
                continue
            n = rnd.uniform(-4, 4)
            if dist < FALLOFF:                                 # soft dark edge, fading out
                t = dist / FALLOFF
                col, alpha = p["edge"], a * (0.15 + 0.85 * t ** 1.4)
            elif dist < FALLOFF + p.get("line", 1.0):          # the frame line
                col = p["top"] if cy - y0 < FALLOFF + 1.0 else p["frame"]
                alpha = a
            else:                                              # inside: gradient, darker near the frame
                t = (cy - y0) / (y1 - y0)
                base = (r0 + (r1 - r0) * t, g0 + (g1 - g0) * t, b0 + (b1 - b0) * t)
                shade = 1 - 0.16 * max(0.0, 1 - (dist - FALLOFF - 1.0) / INNER_SHADE)
                col = tuple(c * shade + n for c in base)
                alpha = a
            px[x, y] = tuple(max(0, min(255, int(c))) for c in col) + (int(alpha),)
    return small.resize((W, H), Image.BILINEAR)


def fit(mask):
    """Scales the icon's outline to fit ICON_MAX_W x ICON_MAX_H and centres it at (middle, ICON_CENTRE_Y)."""
    box = mask.getbbox()
    if not box:
        return mask
    part = mask.crop(box)
    s = min(ICON_MAX_W * SS / part.width, ICON_MAX_H * SS / part.height)
    part = part.resize((max(1, round(part.width * s)), max(1, round(part.height * s))), Image.LANCZOS)
    out = Image.new("L", (W, H), 0)
    out.paste(part, (round(W / 2 - part.width / 2), round(ICON_CENTRE_Y * SS - part.height / 2)))
    return out


def render(mask, kind):
    c = COLOURS[kind]
    mask = fit(mask)
    # A soft dark edge / drop shadow behind the shape, like the game's icons.
    outline = mask.filter(ImageFilter.MaxFilter(int(SS * 1.5) * 2 + 1))
    img = plate(kind)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (W, H), c["dark"]), (0, int(SS * 1.2)), outline)
    img = Image.alpha_composite(img, shadow)
    icon = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    icon.paste(Image.new("RGBA", (W, H), c["fill"]), (0, 0), mask)
    img = Image.alpha_composite(img, icon)
    return img.resize((OUT_W, OUT_H), Image.LANCZOS)


def main(names):
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "StorageMage", "Art", "default")
    os.makedirs(root, exist_ok=True)
    for name in names or ICONS:
        mask = ICONS[name]()
        for kind in COLOURS:
            path = os.path.join(root, "T_SM_Tab_%s_%s.png" % (name, kind.capitalize()))
            render(mask, kind).save(path)
            print(os.path.normpath(path))


if __name__ == "__main__":
    main(sys.argv[1:])
