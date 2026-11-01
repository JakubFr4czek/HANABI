#!/usr/bin/env python3
"""Lifts the near-black islands of the yōkai mask albedo to a dark cinnabar floor (N3 fix2).

The baked albedo (tools/bake_yokai_mask.py) keeps the source's red lacquer and ivory, but its
UV layout has large near-black islands; the face maps onto one, and it renders as sparkling
black. Every texel below the floor is raised to the floor colour, so the lacquer stays red and
the ivory stays ivory. Nothing else changes.

  python3 tools/retexture_yokai_mask.py assets/models/enemies/yokai_mask_albedo.png
Needs Pillow and numpy.
"""
import sys

import numpy as np
from PIL import Image

FLOOR = np.array([125, 36, 30], dtype=np.float32)  # dark cinnabar, sRGB


def main() -> None:
    path = sys.argv[1]
    img = Image.open(path).convert("RGB")
    a = np.asarray(img).astype(np.float32)
    out = np.maximum(a, FLOOR)
    Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(path)
    print("floor applied to", path, "texels lifted:", int((out != a).any(axis=2).sum()))


if __name__ == "__main__":
    main()
