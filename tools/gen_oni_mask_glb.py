#!/usr/bin/env python3
"""Regenerate mid-poly Oni mask GLB (project CC0) for RunOniBoss.

No third-party download — committed mesh for §14/§16 license audit.
"""
import os

import numpy as np
import trimesh

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "enemies", "oni_mask_run.glb")


def main() -> None:
    # Face shell (elongated, chin forward).
    face = trimesh.creation.icosphere(subdivisions=2, radius=0.14)
    face.vertices[:, 2] *= 0.52
    face.vertices[:, 1] *= 1.08
    face.vertices[:, 0] *= 0.88
    face.vertices[:, 2] += 0.025
    face.vertices[:, 1] -= 0.02

    # Brow ridge + cheek planes for silhouette at 3–8 m.
    brow = trimesh.creation.box(extents=[0.22, 0.05, 0.08])
    brow.apply_translation([0.0, 0.11, 0.06])
    cheek_l = trimesh.creation.box(extents=[0.06, 0.10, 0.10])
    cheek_l.apply_translation([-0.11, -0.02, 0.05])
    cheek_r = cheek_l.copy()
    cheek_r.apply_translation([0.22, 0.0, 0.0])

    # Jaw / teeth block (readable grin).
    jaw = trimesh.creation.box(extents=[0.16, 0.07, 0.10])
    jaw.apply_translation([0.0, -0.10, 0.08])
    for tx in np.linspace(-0.06, 0.06, 5):
        tooth = trimesh.creation.box(extents=[0.018, 0.035, 0.022])
        tooth.apply_translation([tx, -0.12, 0.11])
        face = trimesh.util.concatenate([face, tooth])

    # Eye sockets (dark recess).
    for sx in (-1, 1):
        socket = trimesh.creation.icosphere(subdivisions=1, radius=0.028)
        socket.vertices[:, 2] *= 0.45
        socket.apply_translation([0.055 * sx, 0.04, 0.10])
        face = trimesh.util.concatenate([face, socket])

    for sx in (-1, 1):
        horn = trimesh.creation.cone(radius=0.038, height=0.24, sections=12)
        horn.apply_transform(trimesh.transformations.rotation_matrix(np.radians(-22 * sx), [0, 0, 1]))
        horn.apply_transform(trimesh.transformations.rotation_matrix(np.radians(38), [1, 0, 0]))
        horn.apply_translation([0.095 * sx, 0.13, 0.05])
        face = trimesh.util.concatenate([face, horn])

    face = trimesh.util.concatenate([face, brow, cheek_l, cheek_r, jaw])
    face.merge_vertices()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    face.export(OUT)
    print("Wrote", OUT, "verts", len(face.vertices), "tris", len(face.faces))


if __name__ == "__main__":
    main()
