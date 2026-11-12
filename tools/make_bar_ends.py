"""Flat right ends for the vitals bars when "Shaped bars" is off (Pillow).

For every theme with bar body art, derives 8x64 end pieces from that body art, so the ends match it exactly:
  bar_end_track.png   the dark track      (the body track's middle column, repeated)
  bar_end_cap.png     the color mask     (white wherever the track is)
  bar_end_bevel.png / bar_end_facet.png   the shading (the body shading's middle column)
  bar_end_outline.png the gold edge: the body edge's top and bottom lines plus a closing line down the right side

Run: python tools/make_bar_ends.py
"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "FrameMage", "Art", "themes")
W = 16  # drawn bars.endWidth (6) UI units wide: about the same pixels per unit as the 64 px art is tall


def column(img):
    img = img.convert("RGBA")
    x = img.width // 2
    return [img.getpixel((x, y)) for y in range(img.height)]


def strip(col):
    out = Image.new("RGBA", (W, len(col)))
    for y, p in enumerate(col):
        for x in range(W):
            out.putpixel((x, y), p)
    return out


def closing_edge(ecol):
    """The flat end's edge: the body edge's top and bottom lines carried on, and a closing line down the right side
    with the same profile as they have (the top line's, turned on its side, in the upper half; the bottom line's in
    the lower half), so the end's edge is exactly as thick and shaded as the rest of the bar's."""
    H = len(ecol)
    out = Image.new("RGBA", (W, H))
    for y in range(H):
        for x in range(W):
            d_side = W - 1 - x  # how far in from the right
            # the side's pixel at that depth: from the top line's profile (upper half) or the bottom's (lower)
            side = ecol[d_side] if y < H / 2 else ecol[H - 1 - d_side]
            row = ecol[y]
            # the nearer edge wins (the corner: whichever line is closer); empty where neither reaches
            d_row = min(y, H - 1 - y)
            p = side if (d_side < d_row and side[3] > 0) else row
            out.putpixel((x, y), p)
    return out


def main():
    for theme in sorted(os.listdir(ROOT)):
        ui = os.path.join(ROOT, theme, "ui")
        track = os.path.join(ui, "bar_track_body.png")
        if os.path.exists(track):  # (a theme without its own track uses Elven's ends for it)
            tcol = column(Image.open(track))
            strip(tcol).save(os.path.join(ui, "bar_end_track.png"))
            strip([(255, 255, 255, 255 if p[3] > 0 else 0) for p in tcol]).save(os.path.join(ui, "bar_end_cap.png"))
        for style in ("bevel", "facet"):
            body = os.path.join(ui, "bar_%s_body.png" % style)
            if os.path.exists(body):
                strip(column(Image.open(body))).save(os.path.join(ui, "bar_end_%s.png" % style))
        edge = os.path.join(ui, "bar_outline_body.png")
        if os.path.exists(edge):
            ecol = column(Image.open(edge))
            out = closing_edge(ecol)
            out.save(os.path.join(ui, "bar_end_outline.png"))
        print("bar ends:", theme)


if __name__ == "__main__":
    main()
