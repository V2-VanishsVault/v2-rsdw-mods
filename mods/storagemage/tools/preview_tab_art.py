"""Preview sheet of every tab icon (normal and highlight), at the size shown in game and enlarged.

python -I tools/preview_tab_art.py <out.png>
"""
import os
import sys
from PIL import Image

ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "StorageMage", "Art", "default")
NAMES = ["ToolBelt", "Herbs", "Gems", "Ores", "Seeds", "Fishing", "RuneEssence"]
BG = (52, 46, 40, 255)


def main(out):
    cell_w, cell_h, pad = 124, 64, 8
    big = Image.new("RGBA", (len(NAMES) * (cell_w + pad) + pad, 2 * (cell_h + pad) + pad), BG)
    small = Image.new("RGBA", (len(NAMES) * (62 + pad) + pad, 2 * (32 + pad) + pad), BG)
    for i, name in enumerate(NAMES):
        for j, kind in enumerate(("Normal", "Highlight")):
            img = Image.open(os.path.join(ART, "T_SM_Tab_%s_%s.png" % (name, kind))).convert("RGBA")
            big.alpha_composite(img, (pad + i * (cell_w + pad), pad + j * (cell_h + pad)))
            small.alpha_composite(img.resize((62, 32), Image.LANCZOS), (pad + i * (62 + pad), pad + j * (32 + pad)))
    sheet = Image.new("RGBA", (big.width * 2, big.height * 2 + small.height * 2 + 16), BG)
    sheet.alpha_composite(big.resize((big.width * 2, big.height * 2), Image.NEAREST), (0, 0))
    sheet.alpha_composite(small.resize((small.width * 2, small.height * 2), Image.NEAREST), (0, big.height * 2 + 16))
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main(sys.argv[1])
