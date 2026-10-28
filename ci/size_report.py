#!/usr/bin/env python3
"""Repository / asset size report: total size, size per top folder, the largest
tracked files, and every file over the limit (default 10 MB).
Usage: ci/size_report.py [--root .] [--limit-mb 10] [--top 25] [--md out.md] [--json out.json]
Exit 1 when a file is over the limit (the step is continue-on-error)."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys


def tracked(root: str) -> list[str]:
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True).stdout
        files = [p for p in out.decode().split("\0") if p]
        if files:
            return files
    except Exception:
        pass
    files = []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in (".git", ".godot")]
        files += [os.path.relpath(os.path.join(dp, f), root) for f in fn]
    return files


def mb(n: int) -> str:
    return f"{n / 1e6:.1f} MB"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--limit-mb", type=float, default=10.0)
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--md")
    ap.add_argument("--json")
    a = ap.parse_args()
    sizes = []
    for p in tracked(a.root):
        full = os.path.join(a.root, p)
        if os.path.isfile(full):
            sizes.append((os.path.getsize(full), p.replace(os.sep, "/")))
    sizes.sort(reverse=True)
    total = sum(s for s, _ in sizes)
    by_dir: dict[str, int] = {}
    for s, p in sizes:
        top = p.split("/", 1)[0] if "/" in p else "(root)"
        by_dir[top] = by_dir.get(top, 0) + s
    limit = int(a.limit_mb * 1e6)
    over = [(s, p) for s, p in sizes if s > limit]
    git_dir = 0
    gd = os.path.join(a.root, ".git")
    for dp, _dn, fn in os.walk(gd):
        git_dir += sum(os.path.getsize(os.path.join(dp, f)) for f in fn if os.path.isfile(os.path.join(dp, f)))
    lines = ["## Rozmiar repo i assetów", "",
             f"- plików: **{len(sizes)}**, razem **{mb(total)}**" + (f", `.git`: {mb(git_dir)}" if git_dir else ""),
             f"- plików > {a.limit_mb:g} MB: **{len(over)}**", "",
             "| Folder | Rozmiar |", "|---|---|"]
    lines += [f"| `{d}` | {mb(s)} |" for d, s in sorted(by_dir.items(), key=lambda kv: -kv[1])[:12]]
    lines += ["", f"### Największe pliki (top {a.top})", "", "| Plik | Rozmiar |", "|---|---|"]
    lines += [f"| `{p}` | {mb(s)}{' ⚠️' if s > limit else ''} |" for s, p in sizes[: a.top]]
    report = "\n".join(lines)
    print(report)
    if a.md:
        open(a.md, "w", encoding="utf-8").write(report + "\n")
    if a.json:
        json.dump({"total_bytes": total, "files": len(sizes), "git_bytes": git_dir,
                   "by_dir": by_dir, "largest": [{"path": p, "bytes": s} for s, p in sizes[: a.top]],
                   "over_limit": [{"path": p, "bytes": s} for s, p in over]},
                  open(a.json, "w"), indent=2)
    return 1 if over else 0


if __name__ == "__main__":
    sys.exit(main())
