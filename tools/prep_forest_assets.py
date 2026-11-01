#!/usr/bin/env python3
"""Bakes a downloaded glb pack (assets_incoming/, D5) into one game-ready glb.

The result is a single mesh with one baseColor atlas, in metres, base on y = 0
and centred on the origin. Each part's texture is packed into a grid atlas and
the UVs are remapped, so the forest's one-material MultiMesh draw keeps the
scan's colours (the Godot merge in ForestWorld keeps surface 0 only).

  python3 tools/prep_forest_assets.py SRC.glb DST.glb [--scale 1.0] [--tris 0] [--atlas 2048]

--scale  metres per source unit (Sketchfab "cm" scans: 0.01)
--tris   decimate the whole mesh to about this many triangles (0 = keep)
--atlas  atlas edge in pixels (each part's texture is resized to fit its cell)
--rotate-y  turn about Y in degrees (a gate modelled along Z: 90)
--min-faces  floor of triangles per part when decimating (default 64)
--key-blue  key blue-dominant backdrop pixels to black (cut away by the forest shader)
--part   keep only these parts (the index printed by the dump; repeatable), e.g. to drop a
         stalk card whose alpha the RGB atlas would lose
--alpha  keep the baseColor alpha (RGBA atlas): ferns and other alpha-cut cards (D5 undergrowth).
         Needs a material with an alpha channel; the forest's cut-out reads it (alpha_from_texture).

Needs trimesh, Pillow, numpy, fast-simplification and rtree (pip install --user; binary wheels).
"""
from __future__ import annotations

import argparse
import math
import sys

import numpy as np
import trimesh
from PIL import Image


def parts_of(src: str, scale: float, keep: list[int] | None, rotate_y: float = 0.0) -> list[trimesh.Trimesh]:
    scene = trimesh.load(src, force="scene")
    parts = []
    for i, m in enumerate(scene.dump()):
        if keep and i not in keep:
            continue
        if not isinstance(m, trimesh.Trimesh) or len(m.faces) == 0:
            continue
        m = m.copy()
        m.apply_scale(scale)
        if rotate_y:
            m.apply_transform(trimesh.transformations.rotation_matrix(math.radians(rotate_y), [0, 1, 0]))
        parts.append(m)
    return parts


def base_texture(m: trimesh.Trimesh, alpha: bool = False) -> Image.Image:
    """The part's baseColor image; a flat cell of its colour factor when it has none.

    With alpha the image keeps its alpha channel (RGBA); otherwise it is flattened to RGB.
    """
    mat = getattr(m.visual, "material", None)
    tex = getattr(mat, "baseColorTexture", None)
    if tex is not None:
        return tex.convert("RGBA" if alpha else "RGB")
    factor = getattr(mat, "baseColorFactor", None)
    rgba = tuple(int(c) for c in (factor if factor is not None else (200, 200, 200, 255)))
    rgba = rgba if alpha else rgba[:3]
    return Image.new("RGBA" if alpha else "RGB", (4, 4), rgba)


def key_blue(img: Image.Image) -> Image.Image:
    """Blue-dominant pixels become black: a card's navy backdrop, not foliage.

    The forest shader cuts black away as a gap (cherry atlas convention), so a keyed
    backdrop drops out. Green leaves and brown bark are not blue-dominant and stay.
    """
    a = np.asarray(img).astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    navy = (b > r * 11 // 10) & (b > g * 21 // 20) & (b > 40)
    a[navy] = 0
    return Image.fromarray(a.astype(np.uint8))


def pack_atlas(parts: list[trimesh.Trimesh], edge: int, key: bool, alpha: bool = False) -> Image.Image:
    """Grid atlas over the distinct textures; remaps each part's UVs in place."""
    images = [base_texture(m, alpha) for m in parts]
    if key and not alpha:
        images = [key_blue(img) for img in images]
    unique: list[Image.Image] = []
    slot: dict[int, int] = {}
    for img in images:
        if id(img) not in slot:
            slot[id(img)] = len(unique)
            unique.append(img)
    cols = math.ceil(math.sqrt(max(1, len(unique))))
    rows = math.ceil(max(1, len(unique)) / cols)
    cell = edge // cols
    # RGBA atlas: the empty cells stay fully transparent (alpha 0), so no card leaks into them.
    atlas = Image.new("RGBA", (cell * cols, cell * rows), (128, 128, 128, 0)) if alpha \
        else Image.new("RGB", (cell * cols, cell * rows), (128, 128, 128))
    for k, img in enumerate(unique):
        c, r = k % cols, k // cols
        atlas.paste(img.resize((cell, cell), Image.LANCZOS), (c * cell, r * cell))
    for m, img in zip(parts, images):
        k = slot[id(img)]
        c, r = k % cols, k // cols
        raw_uv = getattr(m.visual, "uv", None)
        uv = np.asarray(raw_uv, dtype=np.float64) if raw_uv is not None else np.zeros((len(m.vertices), 2))
        uv = np.clip(uv, 0.0, 1.0)  # scans are not tiling: a UV of exactly 1.0 must stay on its cell
        uv[:, 0] = (c + uv[:, 0]) / cols
        uv[:, 1] = (r + uv[:, 1]) / rows
        m.visual = trimesh.visual.TextureVisuals(uv=uv, material=trimesh.visual.material.PBRMaterial(baseColorTexture=atlas))
    return atlas


def decimate_keep_uv(src: trimesh.Trimesh, target: int) -> trimesh.Trimesh:
    """Quadric decimation, then UVs and material carried back from the source surface.

    trimesh's decimation drops the texture coords, so each new vertex takes its UV
    from the closest point on the original mesh (barycentric interpolation).
    """
    out = src.simplify_quadric_decimation(face_count=target)
    # Collapsing edges can flip some faces; the forest shader culls back faces, so they must agree again.
    trimesh.repair.fix_winding(out)
    raw_uv = np.asarray(src.visual.uv, dtype=np.float64)
    closest, _, tid = trimesh.proximity.closest_point(src, out.vertices)
    tri_faces = src.faces[tid]
    bary = trimesh.triangles.points_to_barycentric(src.triangles[tid], closest)
    uv = np.einsum("nk,nkd->nd", bary, raw_uv[tri_faces])
    out.visual = trimesh.visual.TextureVisuals(uv=uv, material=src.visual.material)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--tris", type=int, default=0)
    ap.add_argument("--atlas", type=int, default=2048)
    ap.add_argument("--rotate-y", type=float, default=0.0, help="turn the model about Y (degrees) before baking")
    ap.add_argument("--min-faces", type=int, default=64, help="floor per part when decimating (keeps thin parts such as a lantern's column)")
    ap.add_argument("--key-blue", action="store_true", help="key blue-dominant backdrop pixels to black (card foliage)")
    ap.add_argument("--part", type=int, action="append", help="keep only these parts (index in the scene dump, repeatable)")
    ap.add_argument("--alpha", action="store_true", help="keep baseColor alpha in an RGBA atlas (ferns, alpha-cut cards)")
    args = ap.parse_args()

    parts = parts_of(args.src, args.scale, args.part, args.rotate_y)
    total = sum(len(p.faces) for p in parts)
    print(f"source: {len(parts)} parts, {total} triangles")

    if args.tris and total > args.tris:
        # Decimate each part in proportion to its share, keeping its UVs.
        for i, p in enumerate(parts):
            target = max(args.min_faces, int(args.tris * len(p.faces) / total))
            if len(p.faces) > target:
                parts[i] = decimate_keep_uv(p, target)

    atlas = pack_atlas(parts, args.atlas, args.key_blue, args.alpha)

    merged = trimesh.util.concatenate(parts)
    lo, hi = merged.bounds
    merged.apply_translation([-(lo[0] + hi[0]) / 2.0, -lo[1], -(lo[2] + hi[2]) / 2.0])
    _ = merged.vertex_normals  # bake normals into the export
    merged.export(args.dst)

    lo, hi = merged.bounds
    print(f"out: {args.dst}: {len(merged.faces)} triangles, size {np.round(hi - lo, 2).tolist()} m, atlas {atlas.size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
