"""Round stone discs for the menu shortcuts' circles (Pillow).

From each background tile (panel_stone*.png, panel_bg_*.png) a 128 px disc: the stone, softly edged, a little darker toward its rim so
the theme's rim sits on it as on a recessed face. Written beside the tile as <tile>_disc.png.

Run: python tools/make_stone_discs.py
"""
import math
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "FrameMage", "Art", "themes")
S = 128


def disc(tile):
    tile = tile.convert("RGBA")
    out = Image.new("RGBA", (S, S))
    c = (S - 1) / 2
    R = S / 2 - 1
    for y in range(S):
        for x in range(S):
            r = math.hypot(x - c, y - c)
            a = max(0.0, min(1.0, R - r + 0.5))  # antialiased edge
            if a <= 0:
                continue
            p = tile.getpixel((x % tile.width, y % tile.height))
            # recessed: darker toward the rim, a touch more along the top (the rim's shadow falls on it)
            k = 1.0 - 0.45 * max(0.0, (r - R * 0.55) / (R * 0.45)) ** 2
            if y < c:
                k -= 0.08 * max(0.0, (r - R * 0.7) / (R * 0.3))
            out.putpixel((x, y), (int(p[0] * k), int(p[1] * k), int(p[2] * k), int(255 * a)))
    return out


def main():
    for theme in sorted(os.listdir(ROOT)):
        ui = os.path.join(ROOT, theme, "ui")
        if not os.path.isdir(ui):
            continue
        for f in sorted(os.listdir(ui)):
            if f.startswith(("panel_stone", "panel_bg_")) and f.endswith(".png") and not f.endswith("_disc.png"):
                disc(Image.open(os.path.join(ui, f))).save(os.path.join(ui, f[:-4] + "_disc.png"))
                print("disc:", theme, f)


if __name__ == "__main__":
    main()
