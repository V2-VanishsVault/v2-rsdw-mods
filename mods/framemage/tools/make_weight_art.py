"""The inventory weight bar's art, per theme (pure Python, like the rest of the theme art).

  weight_trough.png  64x32 (drawn 32x16, 9-slice, margin 0.25): the theme's rim round a dark trough - the bar's
                     background
  weight_fill.png    64x32, the same slicing: white inside the rim, clear over it - the bar's fill (tinted by the
                     load color), so the fill sits inside the rim
  weight_icon.png    80x80: the weight symbol stamped into a plate of the theme's material (the painted plates
                     of Elven, Warrior, Ranger and Dwarven; the Wizard's obsidian)

Run: python tools/make_weight_art.py
"""
import math
import os

import inlay
from make_icons import png, sd_round_rect
from make_theme import clamp01, cover, image, mix, over

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "FrameMage", "Art", "themes")
TW, TH, RIM = 64, 32, 5.0


def rim_color(theme, e, x, y, top):
    """The rim's color e px in from the outer edge (0..RIM)."""
    if theme == "warrior":
        v = inlay.chrome_rim(e, 0.8 if top else 0.35)
        if v is None:
            c = inlay.brushed(37.0, y)
            return mix(c, (0.9, 0.9, 0.95) if top else (0.12, 0.12, 0.14), 0.3)
        return (v * 0.98, v, v * 1.03)
    if theme == "wizard":
        # black glass, a cool highlight along its lit top edge, a blue glow at its inner edge
        c = mix((0.02, 0.025, 0.05), (0.62, 0.72, 0.95), 0.5 * math.exp(-((e - 1.6) / 0.8) ** 2) if top else 0.0)
        return mix(c, (0.15, 0.50, 1.0), 0.6 * math.exp(-((e - (RIM - 0.8)) / 0.7) ** 2))
    if theme == "ranger":
        c = inlay.oak(53.0, y * 0.6)
        c = mix(c, (0.06, 0.035, 0.02), 0.6 * math.exp(-e / 1.2))
        if top:
            c = mix(c, (0.80, 0.64, 0.44), 0.4 * math.exp(-((e - 1.6) / 0.7) ** 2))
        return c
    if theme == "dwarven":
        # hammered bronze, lit along its top edge, darker toward the trough
        t = e / RIM
        c = mix((0.95, 0.70, 0.36) if top else (0.62, 0.36, 0.13), (0.22, 0.11, 0.04), abs(t - 0.35) * 1.5)
        return mix(c, (0.07, 0.035, 0.01), 0.7 * math.exp(-e / 0.7))
    # Elven: antique silver, lit on top, tarnished darker toward the trough
    t = e / RIM
    c = mix((0.92, 0.94, 0.98) if top else (0.55, 0.57, 0.61), (0.14, 0.15, 0.17), abs(t - 0.4) * 1.4)
    return mix(c, (0.04, 0.045, 0.05), 0.7 * math.exp(-e / 0.7))


def trough(theme):
    def fn(x, y):
        d = sd_round_rect(x, y, TW / 2, TH / 2, TW / 2 - 1, TH / 2 - 1, 5)
        if d > 1:
            return (0, 0, 0, 0)
        e = -d
        top = y < TH / 2
        if e < RIM:
            c = rim_color(theme, e, x, y, top)
        else:
            # the trough: dark, with the rim's shadow along its top
            c = (0.035, 0.033, 0.035)
            c = mix(c, (0.0, 0.0, 0.0), 0.6 * math.exp(-(y - RIM) / 2.5) if top else 0.0)
        return c + (cover(d),)
    return TW, TH, image(TW, TH, fn)


def fill():
    def fn(x, y):
        d = sd_round_rect(x, y, TW / 2, TH / 2, TW / 2 - RIM - 0.5, TH / 2 - RIM - 0.5, 2)
        if d > 1:
            return (0, 0, 0, 0)
        v = 1.0 - 0.22 * clamp01((y - RIM) / (TH - 2 * RIM))  # a little rounder: lighter on top
        return (v, v, v, cover(d))
    return TW, TH, image(TW, TH, fn)


def weight_sd(x, y, S):
    """Signed distance (roughly) to the weight symbol: a ring handle over a trapezoid body."""
    cx = S / 2
    y0, y1 = S * 0.40, S * 0.76
    t = clamp01((y - y0) / (y1 - y0))
    hw = S * (0.17 + 0.10 * t)
    body = max(abs(x - cx) - hw, y0 - y, y - y1) - 0.0
    ring = abs(math.hypot(x - cx, y - S * 0.32) - S * 0.085) - S * 0.035
    return min(body, ring)


def icon(theme):
    S = 80
    if theme == "wizard":
        return S, S, image(S, S, lambda x, y: wizard_icon(x, y, S))

    def fn(x, y):
        d = sd_round_rect(x, y, S / 2, S / 2, S / 2 - 2, S / 2 - 2, 12)
        if d > 1:
            return (0, 0, 0, 0)
        v = y / S
        if theme == "warrior":
            c = inlay.brushed(x * 1.3, y)
            c = mix(c, (1.0, 1.0, 1.0), 0.3 * math.exp(-((v - 0.3) / 0.14) ** 2))
            hi, lo, ink = (0.97, 0.98, 1.0), (0.16, 0.16, 0.18), (0.06, 0.06, 0.07)
        else:
            c = inlay.oak(x * 1.2, y * 0.6)
            hi, lo, ink = (0.86, 0.70, 0.48), (0.10, 0.06, 0.03), (0.07, 0.04, 0.02)
        # the plate's raised rim, then the symbol stamped in: dark inside, a lit lip below-right of its edge
        psd = lambda px, py: sd_round_rect(px, py, S / 2, S / 2, S / 2 - 2, S / 2 - 2, 12)
        c = inlay.framed_plate(c, d, 99.0, inlay.facing(psd, x, y), 0.0, hi, lo, ink)
        w = weight_sd(x, y, S)
        if w < 0:
            c = mix(c, ink, 0.75 * clamp01(-w + 0.5))
            # its upper-left inside wall in shadow, the lower-right catching light
            if weight_sd(x - 1.5, y - 1.5, S) > 0:
                c = mix(c, (0, 0, 0), 0.4)
        elif weight_sd(x - 1.4, y - 1.4, S) < 0:
            c = mix(c, hi, 0.45)
        return c + (cover(d),)
    return S, S, image(S, S, fn)


def wizard_icon(x, y, S):
    """The Wizard's: a faceted obsidian plate like the frame's rune plates (four bevels round a flat face, lit from
    the top left), the weight traced on it as a glowing laser-etched outline, like the runes."""
    d = sd_round_rect(x, y, S / 2, S / 2, S / 2 - 2, S / 2 - 2, 6)
    if d > 1:
        return (0, 0, 0, 0)
    c0 = S / 2
    inset = 13.0
    u, v = x - c0, y - c0
    face = max(abs(u), abs(v)) < c0 - inset
    if face:
        c = mix((0.02, 0.025, 0.045), (0.09, 0.10, 0.15), clamp01(0.5 - (u + v) / S))
    else:
        # which bevel: the side the point is nearest, by the diagonals
        if abs(v) >= abs(u):
            lit = 0.85 if v < 0 else 0.10           # top bevel faces the light, bottom away
        else:
            lit = 0.45 if u < 0 else 0.20           # left half lit, right in shade
        c = mix((0.01, 0.012, 0.02), (0.42, 0.48, 0.62), lit)
        # crisp highlight along the bevels' outer edge and their seams with the face
        c = mix(c, (0.80, 0.88, 1.0), 0.5 * math.exp(-((-d - 1.2) / 0.8) ** 2) * (1.0 if v < 0 or u < 0 else 0.3))
    edge = abs(max(abs(u), abs(v)) - (c0 - inset))
    c = mix(c, (0.65, 0.75, 0.95), 0.35 * math.exp(-(edge / 0.7) ** 2))
    # the weight: its outline etched and glowing
    w = abs(weight_sd(x, y, S))
    c = mix(c, (0.16, 0.52, 1.0), 0.7 * math.exp(-(w / 3.0) ** 2))
    c = mix(c, (0.70, 0.92, 1.0), clamp01(1.8 - w))
    return c + (cover(d),)



def main():
    for theme in ("elven", "warrior", "ranger", "wizard", "dwarven"):
        ui = os.path.join(ROOT, theme, "ui")
        for name, make in (("weight_trough.png", lambda: trough(theme)), ("weight_fill.png", fill)):
            w, h, px = make()
            png(os.path.join(ui, name), w, h, px)
        if theme == "wizard":
            import make_wizard_art   # (on the painted obsidian plate, like the frame's rune plates)
            plate_icon = make_wizard_art.weight_icon()
            if plate_icon:
                plate_icon.save(os.path.join(ui, "weight_icon.png"))
                print("weight art:", theme)
                continue
        if theme in ("elven", "warrior", "ranger", "dwarven") and os.path.exists(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                                             theme + "_src", "plate_painted.png")):
            import painted_art       # (on the painted plate, like the frame's corners)
            painted_art.Painted(theme).weight_icon()
            print("weight art:", theme)
            continue
        if theme != "elven":
            w, h, px = icon(theme)
            png(os.path.join(ui, "weight_icon.png"), w, h, px)
        print("weight art:", theme)


if __name__ == "__main__":
    main()
