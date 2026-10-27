#!/usr/bin/env python3
"""Regenerate mid-poly Oni mask GLB (project CC0) for RunOniBoss."""
import os

import numpy as np
import trimesh

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "enemies", "oni_mask_run.glb")


def main() -> None:
    face = trimesh.creation.icosphere(subdivisions=2, radius=0.14)
    face.vertices[:, 2] *= 0.55
    face.vertices[:, 1] *= 1.05
    face.vertices[:, 0] *= 0.85
    face.vertices[:, 2] += 0.02
    for sx in (-1, 1):
        horn = trimesh.creation.cone(radius=0.035, height=0.22, sections=12)
        horn.apply_transform(trimesh.transformations.rotation_matrix(np.radians(-25 * sx), [0, 0, 1]))
        horn.apply_transform(trimesh.transformations.rotation_matrix(np.radians(35), [1, 0, 0]))
        horn.apply_translation([0.09 * sx, 0.12, 0.06])
        face = trimesh.util.concatenate([face, horn])
    face.merge_vertices()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    face.export(OUT)
    print("Wrote", OUT, "verts", len(face.vertices), "tris", len(face.faces))


if __name__ == "__main__":
    main()
