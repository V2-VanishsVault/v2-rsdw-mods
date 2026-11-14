"""The Wizard theme's two painted pieces, made game-ready (Pillow).

An image model painted them over exact layout templates (wizard_src/*_template.png, kept with the paintings). Here
they are fitted to what the game needs:

  panel_frame.png    512x512 (drawn 256 units): the painting at half size; transparent inside the band; its four
                     corners (the rune plates) 96px; each side, between the corners, looped so it repeats seamlessly
                     (frameDraw "border" tiles the sides: a side's two ends must run into each other)
  panel_flourish.png 256x128 (drawn 128x64): the crest cut out, its base on row 92 (flourishLine 46), centered

Run: python tools/make_wizard_art.py (make_theme.py wizard runs it too)
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "wizard_src")
OUT = os.path.join(HERE, "..", "FrameMage", "Art", "themes", "wizard", "ui")

S = 512          # the frame art
CORNER = 96      # its corners (frameMargin 0.1875): the slices the game keeps whole
PLATE = 68       # the rune plate in each, at the outer corner (34 units: a little wider than the band's 24)
BAND = 48        # the band, from the art's edge
CHANNEL = 30     # the painted channel's center, from the art's edge (the painting put it here, not at the template's
                 # 24 - measured; theme.lua frameLine is half this)
CHANNEL_HALF = 6 # the channel's glow, either side of its center


def loop_x(strip):
    """A strip made to repeat along its width: blended with itself shifted by half, the shifted copy taking over
    toward both ends - so its right end runs straight into its left."""
    w, h = strip.size
    shifted = Image.new(strip.mode, (w, h))
    shifted.paste(strip.crop((w // 2, 0, w, h)), (0, 0))
    shifted.paste(strip.crop((0, 0, w // 2, h)), (w - w // 2, 0))
    mask = Image.new("L", (w, h))
    fade = max(1, w // 4)
    for x in range(w):
        e = min(x, w - 1 - x)                    # distance from the nearer end
        v = int(255 * max(0.0, 1.0 - e / fade))  # 255 at the ends (all shifted copy), 0 from a quarter in
        for y in range(h):
            mask.putpixel((x, y), v)
    return Image.composite(shifted, strip, mask)


def inlay_square(img, box, inset, scale=1.0):
    """The frame's own inlay channel laid round a square plate (box = its left, top, right, bottom in img), `inset` px
    in from its edge: copied pixel for pixel from the painted band (rows round its channel, along its tiled length),
    so it is exactly the channel - its groove, glow and star flecks. `scale` = the frame art's pixels per pixel here
    (a piece drawn smaller per pixel than the frame samples the channel finer, to keep its drawn width)."""
    painted = Image.open(os.path.join(SRC, "frame_painted.png")).convert("RGB").resize((S, S), Image.LANCZOS)
    src = painted.load()
    px = img.load()
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    half = (x1 - x0) / 2.0 - inset
    REACH = 6                                   # px of the channel either side of its center (in frame art)
    for y in range(y0, y1):
        for x in range(x0, x1):
            u, v = x + 0.5 - cx, y + 0.5 - cy
            t = (max(abs(u), abs(v)) - half) * scale      # across the line, in frame-art px (+ outward)
            if abs(t) > REACH:
                continue
            along = (x if abs(v) >= abs(u) else y) * scale  # along the side
            sx = CORNER + int(along * 2.7) % (S - 2 * CORNER)
            sy = int(round(CHANNEL + t))
            r, g, b = src[sx, sy]
            k = min(1.0, (REACH - abs(t)) / 1.5)          # (soft at the outer rows)
            pr, pg, pb, pa = px[x, y]
            px[x, y] = (int(pr + (r - pr) * k), int(pg + (g - pg) * k), int(pb + (b - pb) * k), pa)


def frame():
    painted = Image.open(os.path.join(SRC, "frame_painted.png")).convert("RGBA").resize((S, S), Image.LANCZOS)
    out = painted.copy()
    # each side between its corners, looped (top and bottom along x; left and right turned to run along x)
    lo, hi = CORNER, S - CORNER
    for box, turn in (((lo, 0, hi, BAND), False), ((lo, S - BAND, hi, S), False),
                      ((0, lo, BAND, hi), True), ((S - BAND, lo, S, hi), True)):
        side = out.crop(box)
        if turn:
            side = side.transpose(Image.ROTATE_90)
        side = loop_x(side)
        if turn:
            side = side.transpose(Image.ROTATE_270)
        out.paste(side, box[:2])
    # the corners: the band runs round each one (continuing its sides), with the rune plate - smaller than the
    # corner, so it reaches less far into the window - over the turn, bordered in the inlay
    sides = {"top": out.crop((lo, 0, hi, BAND)), "bottom": out.crop((lo, S - BAND, hi, S)),
             "left": out.crop((0, lo, BAND, hi)), "right": out.crop((S - BAND, lo, S, hi))}
    L = hi - lo                                          # a side's length (its repeat)
    plates = {}
    for bx, by in ((0, 0), (S - CORNER, 0), (0, S - CORNER), (S - CORNER, S - CORNER)):
        plates[(bx, by)] = painted.crop((bx, by, bx + CORNER, by + CORNER)).resize((PLATE, PLATE), Image.LANCZOS)
    po = out.load()
    for bx, by in plates:
        hs = sides["top"] if by == 0 else sides["bottom"]
        vs = sides["left"] if bx == 0 else sides["right"]
        hp, vp = hs.load(), vs.load()
        for y in range(by, by + CORNER):
            for x in range(bx, bx + CORNER):
                v = min(y, S - 1 - y)                    # into the frame from the top / bottom edge
                u = min(x, S - 1 - x)
                if v < BAND:                             # the top / bottom band, carried on into the corner
                    po[x, y] = hp[(x - lo) % L, y - (0 if by == 0 else S - BAND)]
                elif u < BAND:                           # the side band, carried on
                    po[x, y] = vp[x - (0 if bx == 0 else S - BAND), (y - lo) % L]
                else:
                    po[x, y] = (0, 0, 0, 0)
        # the plate in the outer corner
        px0 = bx if bx == 0 else bx + CORNER - PLATE
        py0 = by if by == 0 else by + CORNER - PLATE
        plate = plates[(bx, by)]
        inlay_square(plate, (0, 0, PLATE, PLATE), 6)
        out.paste(plate, (px0, py0))
    # see-through inside the band, except the plates
    alpha = Image.new("L", (S, S), 0)
    a = alpha.load()
    for y in range(S):
        for x in range(S):
            u, v = min(x, S - 1 - x), min(y, S - 1 - y)
            if (u < PLATE and v < PLATE) or u < BAND or v < BAND:
                a[x, y] = 255
            elif u < BAND + 1 or v < BAND + 1:
                a[x, y] = 128                    # (a soft inner edge)
    out.putalpha(alpha)
    out.save(os.path.join(OUT, "panel_frame.png"))
    print("wrote panel_frame.png", out.size)


def crest():
    path = os.path.join(SRC, "crest_cut.png")
    if not os.path.exists(path):
        print("no crest yet (wizard_src/crest_cut.png)")
        return
    img = Image.open(path).convert("RGBA")
    img = img.crop(img.getbbox())
    # fit it: 112px tall at most, 240 wide
    k = min(112 / img.height, 240 / img.width)
    img = img.resize((max(1, int(img.width * k)), max(1, int(img.height * k))), Image.LANCZOS)
    # its own glowing channel (the bar along its base): the bluest row in its lower part, placed on the frame's
    # channel (row 92: flourishLine 46), so the two lines run into each other
    px = img.load()
    best, line = -1.0, img.height - 1
    for y in range(int(img.height * 0.55), img.height):
        blue = sum(max(0, px[x, y][2] - (px[x, y][0] + px[x, y][1]) / 2) * px[x, y][3] / 255
                   for x in range(img.width)) / img.width
        if blue > best:
            best, line = blue, y
    out = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
    out.alpha_composite(img, ((256 - img.width) // 2, 92 - line))
    # its channel replaced by the frame's own (same thickness and glow; both arts are drawn at half size): the
    # frame's top band rows round its channel, laid over the crest's base wherever the crest is solid
    fr = Image.open(os.path.join(OUT, "panel_frame.png")).convert("RGBA").load()
    o = out.load()
    for dy in range(-CHANNEL_HALF, CHANNEL_HALF + 1):
        y = 92 + dy
        for x in range(256):
            if o[x, y][3] > 200:
                src = fr[CORNER + (x * 7) % (S - 2 * CORNER), CHANNEL + dy]
                o[x, y] = (src[0], src[1], src[2], o[x, y][3])
    out.save(os.path.join(OUT, "panel_flourish.png"))
    print("wrote panel_flourish.png", img.size)


def plate(size):
    """The blank obsidian plate (like the frame's rune plates, painted with no rune) at `size`, or None."""
    path = os.path.join(SRC, "plate_painted.png")
    if not os.path.exists(path):
        return None
    return Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)


def glow_rim(img, strength):
    """A blue glow round the plate's edge, as the frame's channel glows (hovered boxes)."""
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            e = min(x, y, w - 1 - x, h - 1 - y)
            k = strength * max(0.0, 1.0 - e / 4.0)
            if k > 0:
                r, g, b, a = px[x, y]
                px[x, y] = (int(r + (40 - r) * k), int(g + (130 - g) * k), int(b + (255 - b) * k), a)
    return img


def boxes():
    """The check boxes on the obsidian plate: plain, hovered (its edge glowing), ticked (the glowing tick laid on)."""
    base = plate(64)
    if base is None:
        print("no plate yet (wizard_src/plate_painted.png): the drawn boxes stay")
        return
    inlay_square(base, (0, 0, 64, 64), 6)     # bordered in the glowing inlay
    import make_wizard
    from make_theme import image
    W, H, tick = make_wizard.check_mark()
    tick = Image.frombytes("RGBA", (W, H), bytes(tick))
    for name, ticked, hover in (("check_box.png", False, False), ("check_box_hover.png", False, True),
                                ("check_box_on.png", True, False), ("check_box_on_hover.png", True, True)):
        img = base.copy()
        if hover:
            img = glow_rim(img, 0.8)
        if ticked:
            img.alpha_composite(tick)
        img.save(os.path.join(OUT, name))
    print("wrote the check boxes on the obsidian plate")


def weight_icon():
    """80x80: the obsidian plate with the weight traced on it as a glowing etched outline, like the runes."""
    base = plate(80)
    if base is None:
        return None
    inlay_square(base, (0, 0, 80, 80), 7, 0.7)     # bordered in the glowing inlay
    from make_weight_art import weight_sd
    import math
    px = base.load()
    for y in range(80):
        for x in range(80):
            w = abs(weight_sd(x + 0.5, y + 0.5, 80))
            k1 = 0.7 * math.exp(-(w / 3.0) ** 2)
            k2 = max(0.0, min(1.0, 1.8 - w))
            r, g, b, a = px[x, y]
            r, g, b = r + (41 - r) * k1, g + (133 - g) * k1, b + (255 - b) * k1
            r, g, b = r + (180 - r) * k2, g + (235 - g) * k2, b + (255 - b) * k2
            px[x, y] = (int(r), int(g), int(b), a)
    return base


RUNE_BOX = (114, 30, 147, 78)   # the crest's painted rune (Ansuz), in panel_flourish.png


def draw_rune(img, box, strokes):
    """A rune etched in the frame's glow: strokes (in a unit box) inside `box` - a cyan-white core, electric blue,
    a soft blue bloom."""
    import math
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    segs = [((x0 + a * w, y0 + b * h), (x0 + c * w, y0 + d * h)) for (a, b), (c, d) in strokes]
    px = img.load()
    for y in range(max(0, y0 - 6), min(img.height, y1 + 6)):
        for x in range(max(0, x0 - 6), min(img.width, x1 + 6)):
            dmin = 99.0
            for (ax, ay), (bx, by) in segs:
                dx, dy = bx - ax, by - ay
                t = max(0.0, min(1.0, ((x + 0.5 - ax) * dx + (y + 0.5 - ay) * dy) / (dx * dx + dy * dy)))
                dmin = min(dmin, math.hypot(x + 0.5 - (ax + t * dx), y + 0.5 - (ay + t * dy)))
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            k1 = 0.7 * math.exp(-(dmin / 3.2) ** 2)
            k2 = max(0.0, min(1.0, 2.2 - dmin))
            k3 = max(0.0, min(1.0, 1.1 - dmin))
            r, g, b = r + (2 - r) * k1, g + (60 - g) * k1, b + (200 - b) * k1
            r, g, b = r + (20 - r) * k2, g + (140 - g) * k2, b + (250 - b) * k2
            r, g, b = r + (90 - r) * k3, g + (225 - g) * k3, b + (254 - b) * k3
            px[x, y] = (int(r), int(g), int(b), a)


def erase_rune(img, box):
    """The painted rune taken out of the crest's arch: its blue glow turned back to the arch's dark glass."""
    px = img.load()
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            blue = max(0, b - (r + g) / 2) / 255.0
            k = min(1.0, blue * 5.0)
            px[x, y] = (int(r + (5 - r) * k), int(g + (8 - g) * k), int(b + (20 - b) * k), a)


SOWILO = [((0.68, 0.0), (0.30, 0.42)), ((0.30, 0.42), (0.70, 0.58)), ((0.70, 0.58), (0.32, 1.0))]


def tooltip_line(img, row=92, scale=4.0):
    """The tooltip's own edge line (make_wizard.tip_band: its colors and widths) drawn across the crest's base, at the
    crest's drawing scale (`scale` art px per tooltip px: the crest is drawn at a quarter of its art's size, the band
    at its own) - so the line runs through the crest exactly as bright and thick as on either side of it."""
    import random
    px = img.load()
    w = img.width
    # where the crest's base is (solid on its line), so the line runs the crest's width and no further
    xs = [x for x in range(w) if px[x, row][3] > 200]
    if not xs:
        return
    x0, x1 = min(xs), max(xs)
    rnd = random.Random(11)
    flecks = {int(rnd.uniform(x0, x1)) // int(scale) for _ in range(6)}
    for y in range(max(0, int(row - 3.6 * scale)), min(img.height, int(row + 3.6 * scale) + 1)):
        dl = abs(y + 0.5 - row) / scale                    # in tooltip px
        for x in range(x0, x1 + 1):
            c = (0.01, 0.015, 0.04)                        # the groove
            def mix(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
            c = mix(c, (2 / 255, 45 / 255, 180 / 255), max(0.0, min(1.0, 2.8 - dl)))
            c = mix(c, (20 / 255, 140 / 255, 250 / 255), max(0.0, min(1.0, 1.9 - dl)))
            c = mix(c, (65 / 255, 210 / 255, 254 / 255), max(0.0, min(1.0, 1.0 - dl)))
            if x // int(scale) in flecks and dl < 1.2:
                c = mix(c, (0.85, 0.97, 1.0), 0.8)
            k = max(0.0, min(1.0, 3.6 - dl))
            r, g, b, a = px[x, y]
            px[x, y] = (int(r + (c[0] * 255 - r) * k), int(g + (c[1] * 255 - g) * k),
                        int(b + (c[2] * 255 - b) * k), max(a, int(255 * k)))


def tip_crests():
    """The tooltips' crests (drawn at a quarter of their art's size, half a frame's): the crest with its channel twice
    as thick (thin, it averaged to dark at that size), and for the bottom line the crest turned upside down with an
    upright Sowilo in its arch instead of an upside-down Ansuz (Frame Mage draws this one as it is, unflipped)."""
    src = Image.open(os.path.join(OUT, "panel_flourish.png")).convert("RGBA")
    fr = Image.open(os.path.join(OUT, "panel_frame.png")).convert("RGBA").load()
    top = src.copy()
    tooltip_line(top)
    top.save(os.path.join(OUT, "tip_flourish.png"))
    bottom = top.copy()
    erase_rune(bottom, RUNE_BOX)
    bottom = bottom.transpose(Image.FLIP_TOP_BOTTOM)
    x0, y0, x1, y1 = RUNE_BOX
    fy0, fy1 = 128 - y1, 128 - y0                         # where the arch is, upside down
    draw_rune(bottom, (x0 + 4, fy0 + 3, x1 - 4, fy1 - 3), SOWILO)
    bottom.save(os.path.join(OUT, "tip_flourish_bottom.png"))
    print("wrote tip_flourish.png, tip_flourish_bottom.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    frame()
    crest()
    tip_crests()
    boxes()
    icon = weight_icon()
    if icon:
        icon.save(os.path.join(OUT, "weight_icon.png"))
        print("wrote weight_icon.png on the obsidian plate")


if __name__ == "__main__":
    main()
