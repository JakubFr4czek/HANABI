#!/usr/bin/env python3
"""Contact sheet: a grid of thumbnails with their file names, for a quick look at
many frames at once. Usage: ci/contact_sheet.py --dir frames --out sheet.png [--cols 4] [--thumb 400]"""
from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageDraw


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--thumb", type=int, default=400)
    ap.add_argument("--max", type=int, default=48)
    a = ap.parse_args()
    names = sorted(n for n in os.listdir(a.dir) if n.lower().endswith(".png"))[: a.max] if os.path.isdir(a.dir) else []
    if not names:
        print("contact sheet: no frames")
        return 0
    thumbs = []
    for n in names:
        im = Image.open(os.path.join(a.dir, n)).convert("RGB")
        im.thumbnail((a.thumb, a.thumb))
        thumbs.append((n, im))
    tw = a.thumb
    th = max(im.height for _, im in thumbs) + 18
    rows = (len(thumbs) + a.cols - 1) // a.cols
    sheet = Image.new("RGB", (a.cols * tw, rows * th), (20, 20, 24))
    draw = ImageDraw.Draw(sheet)
    for i, (n, im) in enumerate(thumbs):
        x, y = (i % a.cols) * tw, (i // a.cols) * th
        sheet.paste(im, (x, y))
        draw.text((x + 4, y + im.height + 2), n[:60], fill=(230, 230, 230))
    sheet.save(a.out)
    print(f"contact sheet: {len(thumbs)} frames -> {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
