#!/usr/bin/env python3
"""Pixel diff of this run's screenshots against the previous run's.
For every PNG in --current that also exists in --previous: mean absolute
difference, % of pixels changed by more than --pixel-threshold, and a diff
image (changed pixels in red over a darkened frame) in --out.
Usage: ci/image_diff.py --current shots --previous prev_shots --out diff [--md r.md] [--json r.json]
Exit 1 when a frame changed more than --fail-percent (step is continue-on-error)."""
from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image


def load(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--current", required=True)
    ap.add_argument("--previous", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--pixel-threshold", type=int, default=24, help="0-255 per channel")
    ap.add_argument("--fail-percent", type=float, default=5.0)
    ap.add_argument("--md")
    ap.add_argument("--json")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    rows, flagged = [], []
    names = sorted(n for n in os.listdir(a.current) if n.endswith(".png")) if os.path.isdir(a.current) else []
    for name in names:
        cur_p, prev_p = os.path.join(a.current, name), os.path.join(a.previous, name)
        if not os.path.exists(prev_p):
            rows.append({"name": name, "status": "new"})
            continue
        cur, prev = load(cur_p), load(prev_p)
        if cur.shape != prev.shape:
            prev = np.asarray(Image.fromarray(prev.astype(np.uint8)).resize(cur.shape[1::-1]), dtype=np.int16)
        delta = np.abs(cur - prev).max(axis=2)
        changed = delta > a.pixel_threshold
        pct = float(changed.mean() * 100.0)
        mad = float(np.abs(cur - prev).mean())
        vis = (cur * 0.35).astype(np.uint8)
        vis[changed] = [255, 32, 32]
        Image.fromarray(vis).save(os.path.join(a.out, name.replace(".png", "_diff.png")))
        row = {"name": name, "status": "compared", "changed_percent": round(pct, 2), "mean_abs_diff": round(mad, 2)}
        rows.append(row)
        if pct > a.fail_percent:
            flagged.append(row)
    lines = ["## Zrzuty z gry vs poprzedni przebieg", ""]
    if not names:
        lines.append("Brak zrzutów w tym przebiegu.")
    elif not os.path.isdir(a.previous) or not os.listdir(a.previous):
        lines.append("Brak poprzedniego przebiegu do porównania (pierwszy run) – zapisuję bazę.")
    lines += ["", "| Zrzut | Zmienione piksele | Śr. różnica |", "|---|---|---|"]
    for r in rows:
        if r["status"] == "new":
            lines.append(f"| `{r['name']}` | nowy | – |")
        else:
            warn = " ⚠️" if r in flagged else ""
            lines.append(f"| `{r['name']}` | {r['changed_percent']}%{warn} | {r['mean_abs_diff']} |")
    report = "\n".join(lines)
    print(report)
    if a.md:
        open(a.md, "w", encoding="utf-8").write(report + "\n")
    if a.json:
        json.dump({"rows": rows, "flagged": flagged}, open(a.json, "w"), indent=2)
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main())
