#!/usr/bin/env python3
"""
Build the full-colour macOS app icon (icon.icns) for Expandr from the brand art.

The source panda (expandr.png) sits low on a flat orange square, which looks
unbalanced and dated as a Dock icon. This recomposes it the macOS way:
  - lift the panda off the orange (colour keying: panda is neutral, bg orange)
  - centre it on a fresh vertical orange gradient
  - clip to the rounded-rect "squircle" with Apple's icon-grid proportions
    (824x824 content on a 1024 canvas, corner radius ~0.224*side)
then emits an .iconset and runs `iconutil` to produce icon.icns.

Re-run after changing expandr.png.  Requires macOS `iconutil`.
"""
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent.parent / "espanso" / "src" / "res" / "macos"
SRC = HERE / "expandr.png"
OUT_ICNS = HERE / "icon.icns"
MASTER = HERE / "expandr-appicon-1024.png"   # kept for reference / other platforms

CANVAS = 1024
CONTENT = 824            # rounded-rect size on the canvas (Apple icon grid)
RADIUS = int(CONTENT * 0.2237)
PANDA_FRAC = 0.66        # panda height as a fraction of the content square
TOP = (203, 116, 49)     # gradient top (sampled from expandr.png, lightened a touch)
BOTTOM = (150, 70, 28)   # gradient bottom


def vertical_gradient(size, top, bottom):
    w, h = size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        grad.putpixel((0, y), tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)))
    return grad.resize((w, h))


def extract_panda(src):
    """Return the panda head (black+white) on transparency, cropped tight."""
    rgba = src.convert("RGBA")
    src_alpha = rgba.split()[3]
    rgb = rgba.convert("RGB")
    r, g, b = rgb.split()
    mx = ImageChops.lighter(ImageChops.lighter(r, g), b)
    mn = ImageChops.darker(ImageChops.darker(r, g), b)
    chroma = ImageChops.subtract(mx, mn)
    # neutral (low chroma) = the black+white panda; orange is chromatic
    neutral = chroma.point(lambda v: 255 if v < 45 else 0)
    opaque = src_alpha.point(lambda v: 255 if v > 200 else 0)
    mask = ImageChops.multiply(neutral, opaque).filter(ImageFilter.MedianFilter(3))
    bbox = mask.getbbox()
    panda = rgba.copy()
    panda.putalpha(mask)
    return panda.crop(bbox)


def main():
    src = Image.open(SRC)
    panda = extract_panda(src)

    # compose: gradient background clipped to the squircle
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    bg = vertical_gradient((CONTENT, CONTENT), TOP, BOTTOM).convert("RGBA")
    mask = Image.new("L", (CONTENT, CONTENT), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, CONTENT - 1, CONTENT - 1], radius=RADIUS, fill=255)
    off = (CANVAS - CONTENT) // 2
    icon.paste(bg, (off, off), mask)

    # centre the panda within the content square
    target_h = int(CONTENT * PANDA_FRAC)
    scale = target_h / panda.height
    pw, ph = int(panda.width * scale), target_h
    panda = panda.resize((pw, ph), Image.LANCZOS)
    px = (CANVAS - pw) // 2
    py = off + (CONTENT - ph) // 2
    icon.alpha_composite(panda, (px, py))

    icon.save(MASTER)
    print(f"wrote {MASTER.name} ({CANVAS}x{CANVAS})")

    # build the .iconset and run iconutil
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    names = {
        16: ["icon_16x16.png"], 32: ["icon_16x16@2x.png", "icon_32x32.png"],
        64: ["icon_32x32@2x.png"], 128: ["icon_128x128.png"],
        256: ["icon_128x128@2x.png", "icon_256x256.png"],
        512: ["icon_256x256@2x.png", "icon_512x512.png"],
        1024: ["icon_512x512@2x.png"],
    }
    with tempfile.TemporaryDirectory() as td:
        iconset = Path(td) / "Expandr.iconset"
        iconset.mkdir()
        for s in sizes:
            im = icon.resize((s, s), Image.LANCZOS)
            for n in names[s]:
                im.save(iconset / n)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT_ICNS)], check=True)
    print(f"wrote {OUT_ICNS.name}")


if __name__ == "__main__":
    main()
