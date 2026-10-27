#!/usr/bin/env python3
"""Oni boss body shell + kanabō visual (project CC0). Run: python3 tools/gen_oni_body_glb.py"""
import os

import numpy as np
import trimesh

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT_BODY = os.path.join(ROOT, "assets", "models", "enemies", "oni_body_run.glb")
OUT_KANABO = os.path.join(ROOT, "assets", "models", "enemies", "oni_kanabo_run.glb")


def _stud(x: float, y: float, z: float) -> trimesh.Trimesh:
    s = trimesh.creation.icosphere(subdivisions=1, radius=0.014)
    s.apply_translation([x, y, z])
    return s


def build_body() -> trimesh.Trimesh:
    torso = trimesh.creation.box(extents=[0.52, 0.58, 0.30])
    torso.apply_translation([0.0, 0.42, 0.02])
    chest_plate = trimesh.creation.box(extents=[0.56, 0.22, 0.34])
    chest_plate.apply_translation([0.0, 0.62, 0.06])
    belly = trimesh.creation.box(extents=[0.44, 0.18, 0.26])
    belly.apply_translation([0.0, 0.38, 0.08])
    skirt = trimesh.creation.cylinder(radius=0.34, height=0.42, sections=14)
    skirt.apply_translation([0.0, 0.12, 0.0])
    skirt.vertices[:, 0] *= 1.05
    for sx in (-1, 1):
        shoulder = trimesh.creation.box(extents=[0.18, 0.12, 0.22])
        shoulder.apply_translation([0.28 * sx, 0.72, 0.02])
        sode = trimesh.creation.box(extents=[0.08, 0.28, 0.24])
        sode.apply_translation([0.34 * sx, 0.58, -0.02])
        parts = [shoulder, sode]
        for p in parts:
            torso = trimesh.util.concatenate([torso, p])
    belt = trimesh.creation.box(extents=[0.50, 0.07, 0.32])
    belt.apply_translation([0.0, 0.28, 0.05])
    loin = trimesh.creation.box(extents=[0.22, 0.14, 0.16])
    loin.apply_translation([0.0, 0.22, 0.12])
    for sx in (-1, 1):
        thigh = trimesh.creation.box(extents=[0.14, 0.36, 0.16])
        thigh.apply_translation([0.11 * sx, -0.02, 0.0])
        torso = trimesh.util.concatenate([torso, thigh])
    mesh = trimesh.util.concatenate([torso, chest_plate, belly, skirt, belt, loin])
    mesh.merge_vertices()
    mesh.fix_normals()
    return mesh


def build_kanabo() -> trimesh.Trimesh:
    handle = trimesh.creation.cylinder(radius=0.022, height=0.32, sections=10)
    handle.apply_translation([0.0, -0.18, 0.0])
    head = trimesh.creation.cylinder(radius=0.055, height=0.52, sections=12)
    head.apply_translation([0.0, 0.12, 0.0])
    head.vertices[:, 0] *= 1.08
    studs = []
    for y in np.linspace(-0.05, 0.32, 6):
        for ang in np.linspace(0, 2 * np.pi, 8, endpoint=False):
            studs.append(_stud(0.058 * np.cos(ang), y, 0.058 * np.sin(ang)))
    mesh = trimesh.util.concatenate([handle, head] + studs)
    mesh.merge_vertices()
    mesh.fix_normals()
    return mesh


def main() -> None:
    os.makedirs(os.path.dirname(OUT_BODY), exist_ok=True)
    body = build_body()
    body.export(OUT_BODY)
    kanabo = build_kanabo()
    kanabo.export(OUT_KANABO)
    print("Wrote", OUT_BODY, "verts", len(body.vertices))
    print("Wrote", OUT_KANABO, "verts", len(kanabo.vertices))


if __name__ == "__main__":
    main()
