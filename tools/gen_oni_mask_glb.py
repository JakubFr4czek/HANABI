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


def _displace_mask_shell(mesh: trimesh.Trimesh) -> None:
    v = mesh.vertices
    for i in range(len(v)):
        x, y, z = v[i]
        if z < 0.02:
            continue
        # Deep ocular cavities (read at 2–6 m in fog).
        for ex in (-0.062, 0.062):
            d = ((x - ex) ** 2) / 0.0018 + ((y - 0.035) ** 2) / 0.0012 + ((z - 0.105) ** 2) / 0.0009
            if d < 1.0:
                v[i, 2] -= 0.032 * (1.0 - d)
        # Brow ridge + nasal bridge.
        brow = np.exp(-((x) ** 2 / 0.004 + (y - 0.11) ** 2 / 0.003)) * 0.028
        nose = np.exp(-((x) ** 2 / 0.002 + (y + 0.02) ** 2 / 0.006)) * 0.022
        v[i, 2] += brow + nose
        # Cheek flare.
        cheek = np.exp(-((abs(x) - 0.11) ** 2 / 0.003 + (y + 0.02) ** 2 / 0.008)) * 0.018
        v[i, 2] += cheek
    mesh.vertices = v


def build_mesh() -> trimesh.Trimesh:
    face = trimesh.creation.icosphere(subdivisions=3, radius=0.148)
    face.vertices[:, 2] *= 0.46
    face.vertices[:, 1] *= 1.12
    face.vertices[:, 0] *= 0.88
    face.vertices[:, 2] += 0.035
    face.vertices[:, 1] -= 0.03
    _displace_mask_shell(face)

    brow_l = trimesh.creation.box(extents=[0.11, 0.055, 0.085])
    brow_l.apply_translation([-0.065, 0.115, 0.088])
    brow_r = brow_l.copy()
    brow_r.apply_translation([0.13, 0.0, 0.0])
    brow_center = trimesh.creation.box(extents=[0.08, 0.04, 0.07])
    brow_center.apply_translation([0.0, 0.125, 0.095])

    jaw = trimesh.creation.box(extents=[0.18, 0.09, 0.12])
    jaw.apply_translation([0.0, -0.115, 0.09])
    jaw.vertices[:, 2] += 0.015

    snout = trimesh.creation.box(extents=[0.11, 0.07, 0.09])
    snout.apply_translation([0.0, -0.055, 0.125])

    lip = trimesh.creation.box(extents=[0.14, 0.035, 0.05])
    lip.apply_translation([0.0, -0.155, 0.115])

    parts = [face, brow_l, brow_r, brow_center, jaw, snout, lip]
    for sx in (-1, 1):
        rim = trimesh.creation.torus(major_radius=0.034, minor_radius=0.008, major_sections=14, minor_sections=8)
        rim.apply_translation([0.06 * sx, 0.038, 0.108])
        rim.apply_transform(trimesh.transformations.rotation_matrix(np.radians(18), [0, 1, 0]))
        parts.append(rim)
        cheek = trimesh.creation.box(extents=[0.055, 0.12, 0.1])
        cheek.apply_translation([0.125 * sx, -0.025, 0.065])
        parts.append(cheek)

    for i, tx in enumerate(np.linspace(-0.075, 0.075, 5)):
        fang = trimesh.creation.cone(radius=0.014 if i % 2 == 0 else 0.01, height=0.062, sections=8)
        fang.apply_translation([tx, -0.148, 0.125])
        fang.apply_transform(trimesh.transformations.rotation_matrix(np.radians(14), [1, 0, 0]))
        parts.append(fang)
    for tx in (-0.04, 0.04):
        tusk = trimesh.creation.cone(radius=0.018, height=0.075, sections=9)
        tusk.apply_translation([tx, -0.165, 0.11])
        tusk.apply_transform(trimesh.transformations.rotation_matrix(np.radians(8), [1, 0, 0]))
        parts.append(tusk)

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
    strength = 5.8
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
