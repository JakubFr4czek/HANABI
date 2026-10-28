#!/usr/bin/env python3
"""Summarises an lcov.info: total line coverage, per-folder coverage and the
least covered files, as Markdown (and an HTML table, so it opens without genhtml).
Usage: ci/lcov_summary.py coverage-report/lcov.info [--md s.md] [--html s.html]"""
from __future__ import annotations

import argparse
import html
import os
import sys


def parse(path: str) -> dict[str, list[int]]:
    files: dict[str, list[int]] = {}
    cur = None
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if line.startswith("SF:"):
            cur = line[3:].replace("res://", "")
            files[cur] = [0, 0]
        elif line.startswith("DA:") and cur:
            _ln, hits = line[3:].split(",")[:2]
            files[cur][1] += 1
            if int(float(hits)) > 0:
                files[cur][0] += 1
        elif line == "end_of_record":
            cur = None
    return files


def pct(h: int, t: int) -> float:
    return 100.0 * h / t if t else 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("lcov")
    ap.add_argument("--md")
    ap.add_argument("--html")
    a = ap.parse_args()
    if not os.path.exists(a.lcov):
        msg = "## Pokrycie kodu\n\nBrak lcov.info – instrumentacja albo raport się nie udały (patrz log)."
        print(msg)
        if a.md:
            open(a.md, "w").write(msg + "\n")
        return 1
    files = parse(a.lcov)
    hit = sum(v[0] for v in files.values())
    tot = sum(v[1] for v in files.values())
    dirs: dict[str, list[int]] = {}
    for f, (h, t) in files.items():
        d = os.path.dirname(f) or "."
        dirs.setdefault(d, [0, 0])
        dirs[d][0] += h
        dirs[d][1] += t
    lines = ["## Pokrycie kodu (Nano Coverage)", "",
             f"**Linie: {pct(hit, tot):.1f}%** ({hit}/{tot}) w {len(files)} plikach", "",
             "| Folder | Pokrycie | Linie |", "|---|---|---|"]
    for d, (h, t) in sorted(dirs.items(), key=lambda kv: pct(*kv[1])):
        lines.append(f"| `{d}` | {pct(h, t):.0f}% | {h}/{t} |")
    worst = sorted(((pct(h, t), f, h, t) for f, (h, t) in files.items() if t >= 20))[:15]
    lines += ["", "### Najmniej pokryte pliki (≥ 20 linii)", "", "| Plik | Pokrycie |", "|---|---|"]
    lines += [f"| `{f}` | {p:.0f}% ({h}/{t}) |" for p, f, h, t in worst]
    report = "\n".join(lines)
    print(report)
    if a.md:
        open(a.md, "w", encoding="utf-8").write(report + "\n")
    if a.html:
        rows = "".join(f"<tr><td>{html.escape(f)}</td><td>{pct(h, t):.1f}%</td><td>{h}/{t}</td></tr>"
                       for f, (h, t) in sorted(files.items(), key=lambda kv: pct(*kv[1])))
        open(a.html, "w").write(f"<html><meta charset=utf-8><body><h1>HANABI coverage {pct(hit, tot):.1f}%</h1>"
                                f"<table border=1 cellpadding=4><tr><th>File</th><th>Lines</th><th>Hit/Total</th></tr>{rows}</table></body></html>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
