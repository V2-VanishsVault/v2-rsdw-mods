"""The vitals' themed pieces for the class themes: the ring behind each bar's icon and the edge round the shaped
bars (Demi-human's are a gold hairline: tools/make_badges.py, make_theme.bar_outline). Same sizes and layout as
Demi-human's, so the bars feature uses them unchanged.

  badge_ring.png       112x112 (drawn bars.ringSize, 38 units): a dark face in a thin plain ring of the theme's
                       material, like its buttons' rims - Warrior polished steel, Ranger oak
  bar_outline.png      128x64 (drawn 64x32): the edge round the whole tapered bar, in the theme's material
  bar_outline_body.png / bar_tip_outline.png   its body and point, cut from it (as for Demi-human)
"""
import math

import inlay
from make_theme import (TAPER_H, TAPER_POINT, TAPER_W, _tip_inside, clamp01, cover, crop, image, mix, over,
                        BODY, POINT)

RING = 112


def badge_ring(mat, line):
    """A dark face with a thin plain ring of `mat` round it (like the buttons' rims), lit from the top left."""
    c = RING / 2
    R, HW = 47.0, 4.6                       # the ring's center line and half-width (px): as heavy as the gauges' rims

    def sd(x, y):
        return math.hypot(x - c, y - c) - R

    def fn(x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        r = math.hypot(x - c, y - c)
        # the face: dark glass, a touch lighter toward the top
        if r < R:
            t = clamp01((c - y) / R * 0.5 + 0.5)
            v = 0.05 + 0.07 * t
            col = over(col, (v, v * 1.02, v * 1.1, 1.0), cover(r - R))
        return inlay.band(col, x, y, sd, HW, mat, line, groove=0.0)   # plain: no inlay, as on the buttons

    return RING, RING, image(RING, RING, fn)


GAUGE = 136   # the gauge rim's art (drawn the gauge's size: the survival rings are 68 units)


def gauge_rim(mat):
    """A ring of the theme's material round a gauge's edge (nothing inside: the gauge shows through), lit from the
    top left, as thick as the vitals' icon rings look. `mat` = None: Demi-human's band of gold light."""
    c = GAUGE / 2
    R, HW = 62.0, 4.8

    def sd(x, y):
        return math.hypot(x - c, y - c) - R

    def fn(x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        if mat is None:
            d = sd(x, y)
            ad = abs(d)
            col = over(col, (1.0, 0.86, 0.55, 1.0), math.exp(-((ad - HW) / 2.5) ** 2) * 0.3 * (ad > HW))
            # a gold band, brighter along its middle, lit a little more at the top left
            k = clamp01(1 - ad / HW)
            lit = clamp01(0.55 + 0.45 * ((c - x) + (c - y)) / (2 * c))
            gold = mix((0.55, 0.38, 0.12), (1.0, 0.86, 0.55), 0.4 + 0.6 * k * lit)
            return over(col, gold + (1.0,), cover(ad - HW))
        return inlay.band(col, x, y, sd, HW, mat, inlay.RED, groove=0.0)

    return GAUGE, GAUGE, image(GAUGE, GAUGE, fn)


def bar_edge(shade):
    """The edge round the tapered bar (top, bottom, left end and both slants of the point), just inside its
    outline: shade(d, x, y) -> rgba for a pixel d px from the line's center (the same layout as make_theme's)."""
    body = TAPER_W - TAPER_POINT
    H = TAPER_H

    def fn(x, y):
        inside = min(x, y, H - y) if x < body else _tip_inside(x - body, y)
        if inside < -2.5 or inside > 8:
            return (0, 0, 0, 0)
        return shade(inside, x, y)

    return TAPER_W, TAPER_H, image(TAPER_W, TAPER_H, fn)


def steel_edge():
    """Polished steel: a bright chrome line along the bar's edge with a dark line inside it, brighter along the
    top (turned to the light) than the bottom."""
    def shade(inside, x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        top = y < TAPER_H / 2
        if -0.5 < inside < 5.2:
            k = clamp01(1 - abs(inside - 2.3) / 2.4)
            v = 0.40 + (0.55 if top else 0.28) * k
            col = over(col, (v * 0.98, v, v * 1.03, 1.0), cover(abs(inside - 2.3) - 2.4))
        if 5.2 <= inside < 6.6:
            col = over(col, (0.08, 0.08, 0.09, 1.0), 0.7)
        return col
    return bar_edge(shade)


def wood_edge():
    """Oak: a narrow strip of warm, lit wood along the bar's edge, a darker line inside it."""
    def shade(inside, x, y):
        col = (0.0, 0.0, 0.0, 0.0)
        top = y < TAPER_H / 2
        if -0.5 < inside < 5.0:
            k = clamp01(1 - abs(inside - 2.2) / 2.3)
            c = mix((0.30, 0.20, 0.12), (0.70, 0.54, 0.36) if top else (0.55, 0.40, 0.25), k)
            col = over(col, c + (1.0,), cover(abs(inside - 2.2) - 2.3))
        if 5.0 <= inside < 6.2:
            col = over(col, (0.07, 0.045, 0.03, 1.0), 0.65)
        return col
    return bar_edge(shade)


def pieces(mat, line, edge):
    """The vitals pieces for a theme, as (file name, maker) pairs for its PIECES."""
    return (("badge_ring.png", lambda: badge_ring(mat, line)), ("gauge_rim.png", lambda: gauge_rim(mat)),
            ("bar_outline.png", edge),
            ("bar_outline_body.png", crop(edge, *BODY)), ("bar_tip_outline.png", crop(edge, *POINT)))
