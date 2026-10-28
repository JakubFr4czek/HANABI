#!/usr/bin/env python3
"""Compares perf.json from this run with the previous run's: flags any metric
that grew by more than --threshold (default 20%).
Usage: ci/perf_compare.py --current perf.json [--previous prev/perf.json] [--md r.md]
Exit 1 when a metric jumped (step is continue-on-error)."""
from __future__ import annotations

import argparse
import json
import os
import sys


def flat(d: dict, prefix: str = "") -> dict[str, float]:
    out: dict[str, float] = {}
    for k, v in d.items():
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            out.update(flat(v, key + "."))
        elif isinstance(v, (int, float)) and not isinstance(v, bool):
            out[key] = float(v)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--current", required=True)
    ap.add_argument("--previous")
    ap.add_argument("--threshold", type=float, default=0.20)
    ap.add_argument("--noisy-threshold", type=float, default=0.50,
                    help="for timings (*_ms): CI machines vary, so only a big jump counts")
    ap.add_argument("--md")
    a = ap.parse_args()
    cur = flat(json.load(open(a.current)))
    prev = flat(json.load(open(a.previous))) if a.previous and os.path.exists(a.previous) else {}
    lines = ["## Wydajność (stała scena, renderer programowy)", "",
             "Czas klatki pochodzi z llvmpipe na CPU, więc liczy się trend, nie wartość. Draw calle i prymitywy są porównywalne między przebiegami (nie 1:1 z Questem: inna rozdzielczość, brak stereo).", "",
             "| Metryka | Teraz | Poprzednio | Zmiana |", "|---|---|---|---|"]
    jumps = []
    for k in sorted(cur):
        c = cur[k]
        p = prev.get(k)
        if p is None:
            lines.append(f"| `{k}` | {c:g} | – | – |")
            continue
        change = (c - p) / p if p else (0.0 if c == 0 else float("inf"))
        limit = a.noisy_threshold if "_ms" in k else a.threshold
        flag = change > limit
        if flag:
            jumps.append(k)
        lines.append(f"| `{k}` | {c:g} | {p:g} | {change * 100:+.0f}%{' ⚠️' if flag else ''} |")
    if not prev:
        lines += ["", "Brak poprzedniego przebiegu – to jest baza."]
    elif jumps:
        lines += ["", f"**Skok > {a.threshold * 100:.0f}%:** " + ", ".join(f"`{j}`" for j in jumps)]
    report = "\n".join(lines)
    print(report)
    if a.md:
        open(a.md, "w", encoding="utf-8").write(report + "\n")
    return 1 if jumps else 0


if __name__ == "__main__":
    sys.exit(main())
