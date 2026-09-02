#!/usr/bin/env python3
"""
Generate monochrome menu-bar TEMPLATE icons for Expandr from the brand panda.

A macOS menu-bar (NSStatusItem) template image is a single-colour shape defined
by its ALPHA channel; the system tints it for light/dark bars. So we extract the
panda's dark features (outline, ears, eye patches, nose) as opaque black on a
transparent background, crop to the head, and centre it on a square canvas.

Outputs (overwriting the tray-state resources wired in espanso/src/icon.rs):
  icon.png              normal   (full opacity)
  icondisabled.png      disabled (dimmed -> reads as "off")
  iconsystemdisabled.png secure-input (dimmed)

Source panda (expandr.png) is left untouched for later use as the .app icon.
Re-run after changing expandr.png.
"""
from PIL import Image, ImageChops, ImageFilter
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent / "espanso" / "src" / "res" / "macos"
SRC = HERE / "expandr.png"
OUT = 256          # output canvas size (px); macOS scales down to bar height
PAD = 0.02         # padding fraction around the panda (near-zero: fill the slot)

# The panda ink is dark AND neutral (R~=G~=B); the orange background is
# chromatic even where it is as dark as the ink (the gradient bottom reaches
# the ink's luminance). So we key on colour, not brightness:
#   ink = luminance < LUM_MAX  AND  chroma (max-min channel) < CHROMA_MAX
LUM_MAX = 115      # excludes the white face
CHROMA_MAX = 28    # excludes orange (even dark orange), keeps neutral black


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    w, h = src.size
    src_alpha = src.split()[3]           # the panda PNG's own transparency
    im = src.convert("RGB")
    r, g, b = im.split()
    lum = im.convert("L")

    # chroma = max(R,G,B) - min(R,G,B)
    mx = ImageChops.lighter(ImageChops.lighter(r, g), b)
    mn = ImageChops.darker(ImageChops.darker(r, g), b)
    chroma = ImageChops.subtract(mx, mn)

    lum_ok = lum.point(lambda v: 255 if v < LUM_MAX else 0)
    neutral = chroma.point(lambda v: 255 if v < CHROMA_MAX else 0)
    opaque = src_alpha.point(lambda v: 255 if v > 200 else 0)  # ignore transparent edges
    alpha = ImageChops.multiply(ImageChops.multiply(lum_ok, neutral), opaque)
    alpha = alpha.filter(ImageFilter.MedianFilter(3))  # kill isolated specks

    # Crop to the DENSE panda region, not scattered faint noise in the orange
    # field: dilate the strong-ink mask so the whole head is one solid blob,
    # take its bbox. This ignores stray pixels that would otherwise shrink the
    # panda into a corner.
    strong = alpha.point(lambda v: 255 if v >= 128 else 0)
    blob = strong.filter(ImageFilter.MaxFilter(15))    # close gaps within the head
    bbox = blob.getbbox()
    if bbox is None:
        raise SystemExit("no ink pixels found — check thresholds")
    print(f"source {w}x{h}  all-alpha bbox={alpha.getbbox()}  panda bbox={bbox} "
          f"(LUM_MAX={LUM_MAX} CHROMA_MAX={CHROMA_MAX})")
    # discard everything outside the panda bbox (removes orange-field noise)
    alpha = alpha.crop(bbox)

    # centre on a padded square canvas
    cw, ch = alpha.size
    side = int(max(cw, ch) * (1 + 2 * PAD))
    canvas = Image.new("L", (side, side), 0)
    canvas.paste(alpha, ((side - cw) // 2, (side - ch) // 2))
    canvas = canvas.resize((OUT, OUT), Image.LANCZOS)

    def save(name: str, scale: float) -> None:
        a = canvas.point(lambda v: int(v * scale))
        black = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
        black.putalpha(a)
        black.save(HERE / name)
        print(f"wrote {name}  (alpha x{scale})")

    save("icon.png", 1.0)              # normal
    save("icondisabled.png", 0.35)     # disabled
    save("iconsystemdisabled.png", 0.35)  # secure input


if __name__ == "__main__":
    main()
