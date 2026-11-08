"""Flat right ends for the vitals bars when "Shaped bars" is off (Pillow).

For every theme with bar body art, derives 8x64 end pieces from that body art, so the ends match it exactly:
  bar_end_track.png   the dark track      (the body track's middle column, repeated)
  bar_end_cap.png     the colour mask     (white wherever the track is)
  bar_end_bevel.png / bar_end_facet.png   the shading (the body shading's middle column)
  bar_end_outline.png the gold edge: the body edge's top and bottom lines plus a closing line down the right side

Run: python tools/make_bar_ends.py
"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "FrameMage", "Art", "themes")
W = 8


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


def main():
    for theme in sorted(os.listdir(ROOT)):
        ui = os.path.join(ROOT, theme, "ui")
        track = os.path.join(ui, "bar_track_body.png")
        if not os.path.exists(track):
            continue
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
            out = strip(ecol)
            gold = max(ecol, key=lambda p: p[3])  # the line's strongest pixel: its colour
            lit = [y for y, p in enumerate(ecol) if p[3] > 0]
            top, bottom = (lit[0], lit[-1]) if lit else (0, len(ecol) - 1)
            for y in range(top, bottom + 1):  # the closing line: 2 px, softer outer pixel like the top line
                out.putpixel((W - 2, y), (gold[0], gold[1], gold[2], 255))
                out.putpixel((W - 1, y), (gold[0], gold[1], gold[2], 150))
                out.putpixel((W - 3, y), (gold[0], gold[1], gold[2], max(out.getpixel((W - 3, y))[3], 110)))
            out.save(os.path.join(ui, "bar_end_outline.png"))
        print("bar ends:", theme)


if __name__ == "__main__":
    main()
