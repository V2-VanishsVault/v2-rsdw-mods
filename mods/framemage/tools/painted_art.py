"""A painted theme's big pieces, made game-ready (Pillow) - the Wizard's pipeline (make_wizard_art.py), for any theme.

An image model paints a theme's window frame over an exact layout template (<theme>_src/frame_template.png), its
crest, and a blank corner plate (<theme>_src/*_painted.png, crest_cut.png: kept, so the art rebuilds without the model).
Here they're fitted to the game:

  panel_frame.png    512x512 (drawn 256 units): the painting at half size; transparent inside the band; each side
                     looped so it repeats seamlessly; at each corner the band turning behind a smaller plate (so it
                     reaches less far into windows), the plate bordered in the band's own inlay
  panel_flourish.png 256x128 (drawn 128x64): the crest cut out, its inlay on row 92 (flourishLine 46) and replaced by
                     the frame's own (same thickness and color)
  check_box*.png     the blank plate as the box, bordered in the inlay; the theme's own tick on it; hovered, its
                     edge lit in the inlay's color
  weight_icon.png    the blank plate with the weight outlined in the inlay's color

The inlay is found by its color (`accent`: "red", "green", "blue", "gold", "amber", "teal"), wherever the painting put it.

Run: python tools/painted_art.py <theme>   (make_theme.py runs it for the painted themes)
"""
import importlib
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))

S = 512          # the frame art
CORNER = 96      # its corners (frameMargin 0.1875): the slices the game keeps whole
PLATE = 68       # the plate in each, at the outer corner
BAND = 48        # the band, from the art's edge
REACH = 6        # the inlay's glow, either side of its center (frame art px)

# How strongly a pixel shows the theme's inlay color.
HUES = {
    "red": lambda r, g, b: r - (g + b) / 2,
    "green": lambda r, g, b: g - (r + b) / 2,
    "blue": lambda r, g, b: b - (r + g) / 2,
    "gold": lambda r, g, b: (r + g) / 2 - b,
    # (molten amber glows far redder and brighter than the bronze round it)
    "amber": lambda r, g, b: (r - g) * r / 255.0,
    "teal": lambda r, g, b: (g + b) / 2 - r,
}

# Each painted theme: its accent (to find the inlay) and the module drawing its small pieces (its tick).
THEMES = {
    "warrior": {"accent": "red", "module": "make_warrior", "reach": 6},
    # (the ivy crosses the Ranger's inlay: only its thin core is copied round the plates, leaving the leaves out)
    "ranger": {"accent": "green", "module": "make_ranger", "reach": 3},
    "dwarven": {"accent": "amber", "module": "make_dwarven", "reach": 3},
    "elven": {"accent": "teal", "module": "make_elven", "reach": 2},
}


class Painted:
    def __init__(self, theme):
        self.theme = theme
        cfg = THEMES[theme]
        self.hue = HUES[cfg["accent"]]
        self.module = cfg["module"]
        self.reach = cfg.get("reach", REACH)
        self.src = os.path.join(HERE, theme + "_src")
        self.out = os.path.join(HERE, "..", "FrameMage", "Art", "themes", theme, "ui")
        self.painted = Image.open(os.path.join(self.src, "frame_painted.png")).convert("RGBA").resize(
            (S, S), Image.LANCZOS)
        self.channel = self.find_channel()

    def find_channel(self):
        """Where the painted inlay runs, in from the art's edge (px): the row of the top band with the most of the
        accent color, along its length."""
        px = self.painted.load()
        best, row = -1e9, BAND // 2
        for y in range(4, BAND - 4):
            score = sum(self.hue(*px[x, y][:3]) for x in range(CORNER, S - CORNER, 3))
            if score > best:
                best, row = score, y
        print("%s: the inlay runs %d px in (frameLine %.1f: 0.78 units per art px, as measured for the Wizard)"
              % (self.theme, row, row * 0.783))
        return row

    # --- the frame --------------------------------------------------------------------------------------------------

    @staticmethod
    def loop_x(strip):
        w, h = strip.size
        shifted = Image.new(strip.mode, (w, h))
        shifted.paste(strip.crop((w // 2, 0, w, h)), (0, 0))
        shifted.paste(strip.crop((0, 0, w // 2, h)), (w - w // 2, 0))
        mask = Image.new("L", (w, h))
        fade = max(1, w // 4)
        for x in range(w):
            v = int(255 * max(0.0, 1.0 - min(x, w - 1 - x) / fade))
            for y in range(h):
                mask.putpixel((x, y), v)
        return Image.composite(shifted, strip, mask)

    def inlay_square(self, img, box, inset, scale=1.0):
        """The band's own inlay laid round a square plate, `inset` px in: copied from the painting, row for row."""
        src = self.painted.load()
        px = img.load()
        x0, y0, x1, y1 = box
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        half = (x1 - x0) / 2.0 - inset
        for y in range(y0, y1):
            for x in range(x0, x1):
                u, v = x + 0.5 - cx, y + 0.5 - cy
                t = (max(abs(u), abs(v)) - half) * scale
                if abs(t) > self.reach:
                    continue
                along = (x if abs(v) >= abs(u) else y) * scale
                sx = CORNER + int(along * 2.7) % (S - 2 * CORNER)
                r, g, b, _ = src[sx, int(round(self.channel + t))]
                k = min(1.0, (self.reach - abs(t)) / 1.5)
                pr, pg, pb, pa = px[x, y]
                px[x, y] = (int(pr + (r - pr) * k), int(pg + (g - pg) * k), int(pb + (b - pb) * k), pa)

    def frame(self):
        out = self.painted.copy()
        lo, hi = CORNER, S - CORNER
        for box, turn in (((lo, 0, hi, BAND), False), ((lo, S - BAND, hi, S), False),
                          ((0, lo, BAND, hi), True), ((S - BAND, lo, S, hi), True)):
            side = out.crop(box)
            if turn:
                side = side.transpose(Image.ROTATE_90)
            side = self.loop_x(side)
            if turn:
                side = side.transpose(Image.ROTATE_270)
            out.paste(side, box[:2])
        sides = {"top": out.crop((lo, 0, hi, BAND)), "bottom": out.crop((lo, S - BAND, hi, S)),
                 "left": out.crop((0, lo, BAND, hi)), "right": out.crop((S - BAND, lo, S, hi))}
        L = hi - lo
        po = out.load()
        for bx, by in ((0, 0), (S - CORNER, 0), (0, S - CORNER), (S - CORNER, S - CORNER)):
            plate = self.painted.crop((bx, by, bx + CORNER, by + CORNER)).resize((PLATE, PLATE), Image.LANCZOS)
            hp = (sides["top"] if by == 0 else sides["bottom"]).load()
            vp = (sides["left"] if bx == 0 else sides["right"]).load()
            for y in range(by, by + CORNER):
                for x in range(bx, bx + CORNER):
                    v, u = min(y, S - 1 - y), min(x, S - 1 - x)
                    if v < BAND:
                        po[x, y] = hp[(x - lo) % L, y - (0 if by == 0 else S - BAND)]
                    elif u < BAND:
                        po[x, y] = vp[x - (0 if bx == 0 else S - BAND), (y - lo) % L]
                    else:
                        po[x, y] = (0, 0, 0, 0)
            self.inlay_square(plate, (0, 0, PLATE, PLATE), 6)
            out.paste(plate, (bx if bx == 0 else bx + CORNER - PLATE, by if by == 0 else by + CORNER - PLATE))
        alpha = Image.new("L", (S, S), 0)
        a = alpha.load()
        for y in range(S):
            for x in range(S):
                u, v = min(x, S - 1 - x), min(y, S - 1 - y)
                if (u < PLATE and v < PLATE) or u < BAND or v < BAND:
                    a[x, y] = 255
                elif u < BAND + 1 or v < BAND + 1:
                    a[x, y] = 128
        out.putalpha(alpha)
        out.save(os.path.join(self.out, "panel_frame.png"))
        self.frame_img = out
        print("wrote panel_frame.png")

    # --- the crest --------------------------------------------------------------------------------------------------

    def crest(self):
        path = os.path.join(self.src, "crest_cut.png")
        if not os.path.exists(path):
            print("no crest yet (%s_src/crest_cut.png)" % self.theme)
            return
        img = Image.open(path).convert("RGBA")
        img = img.crop(img.getbbox())
        k = min(112 / img.height, 240 / img.width)
        img = img.resize((max(1, int(img.width * k)), max(1, int(img.height * k))), Image.LANCZOS)
        px = img.load()
        best, line = -1e9, img.height - 1
        for y in range(int(img.height * 0.5), img.height):
            s = sum(self.hue(*px[x, y][:3]) * px[x, y][3] / 255 for x in range(img.width))
            if s > best:
                best, line = s, y
        out = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
        out.alpha_composite(img, ((256 - img.width) // 2, 92 - line))
        fr = self.frame_img.load()
        o = out.load()
        for dy in range(-REACH, REACH + 1):
            y = 92 + dy
            for x in range(256):
                if o[x, y][3] > 200:
                    p = fr[CORNER + (x * 7) % (S - 2 * CORNER), self.channel + dy]
                    o[x, y] = (p[0], p[1], p[2], o[x, y][3])
        out.save(os.path.join(self.out, "panel_flourish.png"))
        print("wrote panel_flourish.png")

    # --- the plate pieces ---------------------------------------------------------------------------------------------

    def plate(self, size):
        path = os.path.join(self.src, "plate_painted.png")
        if not os.path.exists(path):
            return None
        return Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)

    def accent_rgb(self):
        """The inlay's brightest color, from the painting (the line the weight is outlined in, the hover glow)."""
        px = self.painted.load()
        best, col = -1e9, (255, 255, 255)
        for x in range(CORNER, S - CORNER, 2):
            for dy in (-1, 0, 1):
                p = px[x, self.channel + dy][:3]
                s = self.hue(*p) + sum(p) / 6
                if s > best:
                    best, col = s, p
        return col

    def boxes(self):
        base = self.plate(64)
        if base is None:
            print("no plate yet (%s_src/plate_painted.png): the drawn boxes stay" % self.theme)
            return
        self.inlay_square(base, (0, 0, 64, 64), 6)
        ar, ag, ab = self.accent_rgb()
        tick = self.tick((ar, ag, ab))
        for name, ticked, hover in (("check_box.png", False, False), ("check_box_hover.png", False, True),
                                    ("check_box_on.png", True, False), ("check_box_on_hover.png", True, True)):
            img = base.copy()
            if hover:
                px = img.load()
                for y in range(64):
                    for x in range(64):
                        k = 0.8 * max(0.0, 1.0 - min(x, y, 63 - x, 63 - y) / 4.0)
                        if k > 0:
                            r, g, b, a = px[x, y]
                            px[x, y] = (int(r + (ar - r) * k), int(g + (ag - g) * k), int(b + (ab - b) * k), a)
            if ticked:
                img.alpha_composite(tick)
            img.save(os.path.join(self.out, name))
        print("wrote the check boxes on the plate")

    @staticmethod
    def tick(accent):
        """64x64: Elven's tick (two curved strokes, widest at the joint, pointed at both ends) in the inlay's
        color - lit along its top, a dark edge round it so it reads on any plate."""
        S = 64
        A, B, C = (12.0, 31.0), (26.0, 47.0), (53.0, 13.0)
        W = 4.6

        def curve(p, q, bow, steps=40):
            mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
            dx, dy = q[0] - p[0], q[1] - p[1]
            L = math.hypot(dx, dy)
            nx, ny = -dy / L, dx / L
            cx, cy = mx - nx * bow * 2, my - ny * bow * 2
            return [((1 - t) ** 2 * p[0] + 2 * (1 - t) * t * cx + t * t * q[0],
                     (1 - t) ** 2 * p[1] + 2 * (1 - t) * t * cy + t * t * q[1], t)
                    for t in (i / 40 for i in range(41))]

        arms = (curve(A, B, 3.0), curve(B, C, 5.0))

        def near(px, py, pts):
            best, bt = 1e9, 0.0
            for (x0, y0, t0), (x1, y1, t1) in zip(pts, pts[1:]):
                dx, dy = x1 - x0, y1 - y0
                u = max(0.0, min(1.0, ((px - x0) * dx + (py - y0) * dy) / (dx * dx + dy * dy or 1e-9)))
                d = math.hypot(px - (x0 + u * dx), py - (y0 + u * dy))
                if d < best:
                    best, bt = d, t0 + (t1 - t0) * u
            return best, bt

        img = Image.new("RGBA", (S, S))
        px = img.load()
        ar, ag, ab = accent
        for y in range(S):
            for x in range(S):
                d1, t1 = near(x + 0.5, y + 0.5, arms[0])
                d2, t2 = near(x + 0.5, y + 0.5, arms[1])
                d = min(d1 - W * t1, d2 - W * (1 - t2))    # < 0 inside
                edge = max(0.0, min(1.0, 2.2 - d))           # the dark edge, a little wider than the stroke
                body = max(0.0, min(1.0, 0.5 - d))
                if edge <= 0:
                    continue
                lit = max(0.0, min(1.0, 0.6 - (y - 20) / 40))   # lighter toward the top
                r = ar + (255 - ar) * 0.35 * lit
                g = ag + (255 - ag) * 0.35 * lit
                b = ab + (255 - ab) * 0.35 * lit
                c = (r * body + 12 * (1 - body), g * body + 10 * (1 - body), b * body + 10 * (1 - body))
                px[x, y] = (int(c[0]), int(c[1]), int(c[2]), int(255 * edge))
        return img

    def weight_icon(self):
        base = self.plate(80)
        if base is None:
            return None
        self.inlay_square(base, (0, 0, 80, 80), 7, 0.7)
        from make_weight_art import weight_sd
        ar, ag, ab = self.accent_rgb()
        px = base.load()
        # (on a light plate - Elven's gold - the outline gets a dark edge, or the glowing line is lost on it)
        light = sum(sum(px[x, y][:3]) for x in range(20, 60, 4) for y in range(20, 60, 4)) / (3 * 100) > 150
        for y in range(80):
            for x in range(80):
                w = abs(weight_sd(x + 0.5, y + 0.5, 80))
                k1 = 0.55 * math.exp(-(w / 3.0) ** 2)            # a soft glow round the outline
                k2 = max(0.0, min(1.0, 1.8 - w))                  # the outline, in the inlay's color
                r, g, b, a = px[x, y]
                if light:
                    k0 = 0.85 * max(0.0, min(1.0, 3.4 - w))
                    r, g, b = r * (1 - k0) + 30 * k0, g * (1 - k0) + 18 * k0, b * (1 - k0) + 6 * k0
                    k1 = 0.0
                r, g, b = r + (ar * 0.6 - r) * k1, g + (ag * 0.6 - g) * k1, b + (ab * 0.6 - b) * k1
                r, g, b = r + (ar - r) * k2, g + (ag - g) * k2, b + (ab - b) * k2
                px[x, y] = (int(r), int(g), int(b), a)
        base.save(os.path.join(self.out, "weight_icon.png"))
        print("wrote weight_icon.png on the plate")
        return base

    def run(self):
        os.makedirs(self.out, exist_ok=True)
        self.frame()
        self.crest()
        self.boxes()
        self.weight_icon()


def main(theme):
    Painted(theme).run()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "warrior")
