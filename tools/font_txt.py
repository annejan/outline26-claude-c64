#!/usr/bin/env python3
"""
font_txt.py — convert Spritemate's "KickAss assembly (binary)" .txt
export into parts/greets/font.bin.

Spritemate exports 32 sprites as one file per sprite section, each
with 21 `.byte %bbbbbbbb,%bbbbbbbb,%bbbbbbbb` rows (21 rows × 3 bytes
= 63 bytes of bitmap data per sprite). We re-add the 1-byte padding
per slot to land on the 64-byte-per-sprite layout the greets loader
expects, and emit a single 2048-byte font.bin (32 × 64).

Usage:
    # in Spritemate: File → Export → Assembly Code →
    #                KICK ASS (binary notation), save to font.txt
    # somewhere under the repo, then:
    python3 tools/font_txt.py parts/greets/font.txt

    # (default path if you omit the arg:)
    python3 tools/font_txt.py
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TXT = os.path.join(REPO, "parts/greets/font.txt")
BIN = os.path.join(REPO, "parts/greets/font.bin")

ROWS_PER_SPRITE = 21
SPRITES_EXPECTED = 32
BYTES_PER_ROW = 3
PAD_PER_SPRITE = 1   # 21*3 = 63, pad to 64

# A line like:  .byte %00000001,%11111111,%10000000
LINE_RE = re.compile(r"\.byte\s+%([01]{8})\s*,\s*%([01]{8})\s*,\s*%([01]{8})")


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else TXT
    with open(src, "r") as f:
        text = f.read()
    rows = LINE_RE.findall(text)
    expected_rows = ROWS_PER_SPRITE * SPRITES_EXPECTED  # 672
    if len(rows) != expected_rows:
        raise SystemExit(
            f"{src}: found {len(rows)} sprite rows, expected {expected_rows} "
            f"(32 sprites × 21 rows). Did Spritemate export the full project?"
        )

    blob = bytearray()
    for idx, (b0, b1, b2) in enumerate(rows):
        blob.append(int(b0, 2))
        blob.append(int(b1, 2))
        blob.append(int(b2, 2))
        if (idx + 1) % ROWS_PER_SPRITE == 0:
            blob.append(0)  # 64-byte slot pad

    if len(blob) != SPRITES_EXPECTED * 64:
        raise SystemExit(f"internal: produced {len(blob)} bytes, expected 2048")

    with open(BIN, "wb") as f:
        f.write(blob)
    print(f"wrote {BIN} ({len(blob)} bytes from {len(rows)} sprite rows in {src})")


if __name__ == "__main__":
    main()
