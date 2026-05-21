#!/usr/bin/env python3
"""
Generate parts/greets/backdrop.png — the greets DYCP scroller backdrop.

Design: peephole / rabbithole look.
  - Blue field at edges, black ellipse in the centre (= the "hole" the
    sprite scroller emerges from).
  - Ellipse boundary is dithered (checkerboard black/blue band) so the
    transition feels soft + organic instead of a clinical curve.
  - "GREETINGS TO" centred at the top, "THE LEGENDS" centred at the
    bottom — both rendered 2x-scaled chargen letters with a yellow-to-
    white vertical gradient (top half yellow, bottom half white) for
    that demoscene "warm sunset" sexy feel.

Re-run any time the layout / text needs to change. Convert to .kla:

  python3 tools/png_to_koala.py parts/greets/backdrop.png \\
      parts/greets/backdrop.kla

then rebuild. Both PNG and .kla are tracked in the repo so a fresh
clone builds without needing this script.

Pixel font comes from parts/greets/chargen.bin (the C64 uppercase ROM)
scaled 2x in both dimensions: each chargen pixel becomes a 2x2 hw
block. After png_to_koala halves the width (320 hw → 160 logical), a
chargen pixel ends up 1 logical wide × 2 logical tall — chunky-but-
readable letters at ~16 hw px tall.
"""
from PIL import Image
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHARGEN = (ROOT / "parts/greets/chargen.bin").read_bytes()
OUT_PNG = ROOT / "parts/greets/backdrop.png"

# C64 Pepto palette (16 colours).
PEPTO = [
    (0, 0, 0), (255, 255, 255), (136, 57, 50), (103, 182, 189),
    (139, 63, 150), (85, 160, 73), (64, 49, 141), (191, 206, 114),
    (139, 84, 41), (87, 66, 0), (184, 105, 98), (80, 80, 80),
    (120, 120, 120), (148, 224, 137), (120, 105, 196), (159, 159, 159),
]

# Palette indices used in this backdrop. png_to_koala.py maps PNG
# pixels by RGB distance to its fixed 4-slot set { $00 black, $06 blue,
# $07 yellow, $01 white }, so any indices NOT in those 4 will map to
# whichever of the 4 is nearest in RGB. Using the right four indices
# here makes the mapping unambiguous.
BLACK, WHITE, BLUE, YELLOW = 0, 1, 6, 7


def render_letter_gradient(img, ch, x, y):
    """Draw a chargen letter at (x, y) scaled 2x in both dimensions.
    Top half (chargen rows 0..3) → yellow, bottom half (rows 4..7) →
    white. Each chargen pixel becomes a 2x2 hw block.
    """
    if ch == ' ':
        return
    sc = ord(ch.upper()) - 0x40
    if sc < 1 or sc > 26:
        return
    off = sc * 8
    for row in range(8):
        byte = CHARGEN[off + row]
        colour = YELLOW if row < 4 else WHITE
        for bit in range(8):
            if byte & (0x80 >> bit):
                px = x + bit * 2
                py = y + row * 2
                # 2×2 hw block per chargen pixel
                img.putpixel((px,     py    ), colour)
                img.putpixel((px + 1, py    ), colour)
                img.putpixel((px,     py + 1), colour)
                img.putpixel((px + 1, py + 1), colour)


def render_text(img, text, centre_x, y):
    """Draw a string of letters centred horizontally at centre_x,
    with the gradient fill from render_letter_gradient."""
    width = len(text) * 16
    x = centre_x - width // 2
    for i, ch in enumerate(text):
        render_letter_gradient(img, ch, x + i * 16, y)


def fill_ellipse_dithered(img, cx, cy, a, b):
    """Paint a black ellipse on a blue field with a dithered band at
    the boundary. ((x-cx)/a)² + ((y-cy)/b)² < 1 - margin = pure black,
    > 1 + margin = pure blue, in between = checkerboard dither so the
    edge fades organically.

    Important: the koala converter halves WIDTH (each logical pixel =
    2 hw px wide), so all hw-px positions must come in pairs of two
    that share the same colour. The "checker" therefore alternates in
    pairs of 2 hw px horizontally — single-pixel dithers would average
    out after the halve and produce uniform colour instead of texture.
    """
    BAND = 0.10   # ± fraction of normalised radius for the dither band
    for y in range(200):
        for x in range(0, 320, 2):
            # Normalised "radius" — 0 at centre, 1 on ellipse boundary
            dx = (x + 0.5 - cx) / a
            dy = (y + 0.5 - cy) / b
            r2 = dx * dx + dy * dy
            if r2 <= (1.0 - BAND) ** 2:
                colour = BLACK
            elif r2 >= (1.0 + BAND) ** 2:
                colour = BLUE
            else:
                # Dither band — checkerboard with 2-hw-px pair grain
                # so it survives the koala width-halving.
                cell = ((x // 2) + (y // 1)) & 1
                colour = BLACK if cell == 0 else BLUE
            img.putpixel((x,     y), colour)
            img.putpixel((x + 1, y), colour)


def main():
    img = Image.new('P', (320, 200), color=BLUE)
    palette = []
    for r, g, b in PEPTO:
        palette.extend([r, g, b])
    palette.extend([0] * (768 - len(palette)))
    img.putpalette(palette)

    # ---- Peephole: black ellipse on the blue field ----
    # Centre slightly low so the visual focal point lines up with the
    # DYCP sprites at raster Y=130 (not the geometric centre Y=100).
    # Wide enough horizontally that sprite chars near the left/right
    # edges still land on the dark interior, tall enough that the
    # text above/below doesn't crowd the ellipse boundary.
    fill_ellipse_dithered(img, cx=160, cy=120, a=180, b=80)

    # ---- White-and-yellow text top: "GREETINGS TO" ----
    # Y=8 → rows 1..3 inside the upper blue band, well above the
    # ellipse top (which only kisses Y≈40 at its peak).
    render_text(img, "GREETINGS TO", 160, 8)

    # ---- White-and-yellow text bottom: "THE LEGENDS" ----
    # Y=176 → rows 22..24 inside the lower blue band, well below the
    # ellipse bottom (which reaches its lowest point around Y≈200).
    # 16 hw px tall letters fit between Y=176 and the screen bottom.
    render_text(img, "THE LEGENDS", 160, 176)

    img.save(OUT_PNG)
    print(f'wrote {OUT_PNG}')


if __name__ == '__main__':
    main()
