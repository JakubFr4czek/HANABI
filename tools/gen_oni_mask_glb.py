#!/usr/bin/env python3
"""Regenerate sculpted Oni mask GLB + tangent-space normal map (project CC0).

No third-party mesh download. Run from repo root:
    python3 tools/gen_oni_mask_glb.py
"""
import os
import struct
import zlib

import numpy as np
import trimesh

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT_GLB = os.path.join(ROOT, "assets", "models", "enemies", "oni_mask_run.glb")
OUT_NRM = os.path.join(ROOT, "assets", "models", "enemies", "oni_mask_run_normal.png")
TEX = 256


def _horn(sx: float) -> trimesh.Trimesh:
    horn = trimesh.creation.cylinder(radius=0.038, height=0.26, sections=10)
    horn.apply_transform(trimesh.transformations.rotation_matrix(np.radians(-18 * sx), [0, 0, 1]))
    horn.apply_transform(trimesh.transformations.rotation_matrix(np.radians(42), [1, 0, 0]))
    horn.apply_translation([0.10 * sx, 0.14, 0.04])
    return horn


def build_mesh() -> trimesh.Trimesh:
    face = trimesh.creation.icosphere(subdivisions=3, radius=0.145)
    face.vertices[:, 2] *= 0.48
    face.vertices[:, 1] *= 1.10
    face.vertices[:, 0] *= 0.90
    face.vertices[:, 2] += 0.03
    face.vertices[:, 1] -= 0.025

    brow = trimesh.creation.box(extents=[0.24, 0.065, 0.10])
    brow.apply_translation([0.0, 0.12, 0.075])
    brow.vertices[:, 2] += 0.02

    for sx in (-1, 1):
        ridge = trimesh.creation.box(extents=[0.09, 0.04, 0.06])
        ridge.apply_translation([0.07 * sx, 0.10, 0.09])
        brow = trimesh.util.concatenate([brow, ridge])

    jaw = trimesh.creation.box(extents=[0.17, 0.08, 0.11])
    jaw.apply_translation([0.0, -0.11, 0.085])

    snout = trimesh.creation.box(extents=[0.12, 0.06, 0.08])
    snout.apply_translation([0.0, -0.06, 0.12])

    parts = [face, brow, jaw, snout]
    for sx in (-1, 1):
        socket = trimesh.creation.icosphere(subdivisions=2, radius=0.032)
        socket.vertices[:, 2] *= 0.35
        socket.apply_translation([0.058 * sx, 0.045, 0.11])
        parts.append(socket)
        cheek = trimesh.creation.box(extents=[0.05, 0.11, 0.09])
        cheek.apply_translation([0.12 * sx, -0.02, 0.06])
        parts.append(cheek)

    for i, tx in enumerate(np.linspace(-0.07, 0.07, 7)):
        fang = trimesh.creation.cone(radius=0.012 if i % 2 == 0 else 0.009, height=0.055, sections=8)
        fang.apply_translation([tx, -0.14, 0.12])
        fang.apply_transform(trimesh.transformations.rotation_matrix(np.radians(12), [1, 0, 0]))
        parts.append(fang)

    for sx in (-1, 1):
        parts.append(_horn(sx))

    mesh = trimesh.util.concatenate(parts)
    mesh.merge_vertices()
    mesh.fix_normals()
    return mesh


def height_field(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Front-facing mask height in UV space (0..1)."""
    x = (u - 0.5) * 2.2
    y = (v - 0.42) * 2.4
    r = np.sqrt(x * x + y * y)
    base = np.clip(1.0 - r * 1.15, 0.0, 1.0) ** 1.6
    brow = np.exp(-((x) ** 2 / 0.08 + (y - 0.35) ** 2 / 0.02)) * 0.35
    nose = np.exp(-(x ** 2 / 0.015 + (y + 0.05) ** 2 / 0.04)) * 0.22
    jaw = np.exp(-((x) ** 2 / 0.12 + (y + 0.42) ** 2 / 0.03)) * 0.28
    fangs = np.zeros_like(u)
    for tx in np.linspace(-0.35, 0.35, 7):
        fangs += np.exp(-((x - tx) ** 2 / 0.002 + (y + 0.38) ** 2 / 0.008)) * 0.45
    horns = (
        np.exp(-((x - 0.42) ** 2 / 0.03 + (y - 0.38) ** 2 / 0.05))
        + np.exp(-((x + 0.42) ** 2 / 0.03 + (y - 0.38) ** 2 / 0.05))
    ) * 0.55
    return base + brow + nose + jaw + fangs + horns


def write_normal_png(path: str) -> None:
    u = np.linspace(0, 1, TEX, dtype=np.float32)
    v = np.linspace(1, 0, TEX, dtype=np.float32)
    uu, vv = np.meshgrid(u, v)
    h = height_field(uu, vv)
    du = np.gradient(h, axis=1)
    dv = np.gradient(h, axis=0)
    strength = 4.5
    nx = -du * strength
    ny = -dv * strength
    nz = np.ones_like(nx)
    n = np.stack([nx, ny, nz], axis=-1)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    rgb = ((n * 0.5 + 0.5) * 255.0).astype(np.uint8)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        from PIL import Image

        Image.fromarray(rgb, mode="RGB").save(path, format="PNG")
    except ImportError:
        raw = b"".join(b"\x00" + rgb[y, :].tobytes() for y in range(TEX))
        def chunk(tag: bytes, data: bytes) -> bytes:
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

        ihdr = struct.pack(">IIBBBBB", TEX, TEX, 8, 2, 0, 0, 0)
        idat = zlib.compress(raw, 9)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
        with open(path, "wb") as f:
            f.write(png)


def main() -> None:
    mesh = build_mesh()
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    mesh.export(OUT_GLB)
    write_normal_png(OUT_NRM)
    print("Wrote", OUT_GLB, "verts", len(mesh.vertices), "tris", len(mesh.faces))
    print("Wrote", OUT_NRM)


if __name__ == "__main__":
    main()
