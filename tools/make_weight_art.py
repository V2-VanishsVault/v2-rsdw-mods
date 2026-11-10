"""The inventory weight bar's art, per theme (pure Python, like the rest of the theme art).

  weight_trough.png  64x32 (drawn 32x16, 9-slice, margin 0.25): the theme's rim round a dark trough - the bar's
                     background
  weight_fill.png    64x32, the same slicing: white inside the rim, clear over it - the bar's fill (tinted by the
                     load color), so the fill sits inside the rim
  weight_icon.png    80x80: the weight symbol stamped into a plate of the theme's material (Warrior steel, Ranger
                     oak; Demi-human keeps the game's own icon, so it has none)

Run: python tools/make_weight_art.py
"""
import math
import os

import inlay
from make_icons import png, sd_round_rect
from make_theme import GOLD, GOLD_HI, GOLD_LO, clamp01, cover, image, mix, over

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
    if theme == "ranger":
        c = inlay.oak(53.0, y * 0.6)
        c = mix(c, (0.06, 0.035, 0.02), 0.6 * math.exp(-e / 1.2))
        if top:
            c = mix(c, (0.80, 0.64, 0.44), 0.4 * math.exp(-((e - 1.6) / 0.7) ** 2))
        return c
    # Demi-human: a gold line, lit on top
    t = e / RIM
    c = mix(GOLD_HI if top else GOLD, GOLD_LO, abs(t - 0.4) * 1.4)
    return mix(c, (0.20, 0.12, 0.03), 0.7 * math.exp(-e / 0.7))


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


def main():
    for theme in ("demihuman", "warrior", "ranger"):
        ui = os.path.join(ROOT, theme, "ui")
        for name, make in (("weight_trough.png", lambda: trough(theme)), ("weight_fill.png", fill)):
            w, h, px = make()
            png(os.path.join(ui, name), w, h, px)
        if theme != "demihuman":
            w, h, px = icon(theme)
            png(os.path.join(ui, "weight_icon.png"), w, h, px)
        print("weight art:", theme)


if __name__ == "__main__":
    main()
