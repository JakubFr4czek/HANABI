#!/usr/bin/env python3
"""Asset licence check (non-blocking report).

Every file under assets/ must be covered by a path in LICENSES.md (or CREDITS.md),
and the licence on that row must be CC0 / CC BY / public domain / project-own.
Accepted licence cells: CC0, CC BY (not SA/NC/ND), public domain, SIL OFL 1.1 (fonts) and the explicit
marker "Project-own art" (own or AI-generated project art, see the rule in ci/README.md). Nothing else is waved through
by name: a file with no row still fails, and a row with another licence still needs a human look.
Paths are read from `backtick` tokens. A token may be a file, a glob (`sword.*.ogg`)
or a folder (`assets/fonts/`); a token without a folder (`oni_mask_run_normal.png`)
is relative to the folder of the previous token on the same line, as the files use it.

Usage: ci/check_licenses.py [--root .] [--md report.md] [--json report.json] [--since "24 hours ago"]
Exit code: 0 = clean, 1 = findings (the workflow step is continue-on-error).
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys

IGNORED_SUFFIXES = (".import", ".uid", ".md", ".gdignore", ".unwrap_cache")
IGNORED_NAMES = re.compile(r"^(LICEN[CS]E|COPYING|OFL)[^/]*$", re.I)
OK_LICENCE = re.compile(r"\bCC0\b|CC[ -]?BY(?![ -]?(SA|NC|ND))|public domain|project[- ]own|project author|"
                        r"HANABI\b|own asset|procedural|synthesi[sz]ed|no recordings|SIL OFL 1\.1|Project-own art", re.I)
WARN_LICENCE = re.compile(r"\bOFL\b|SIL|MIT|Apache|CC[ -]?BY[ -]?SA|commercial", re.I)
TOKEN = re.compile(r"`([^`]+)`")


def tokens_on_line(line: str) -> list[str]:
    """Asset path tokens of one Markdown line, with relative names resolved."""
    out: list[str] = []
    base = ""
    for raw in TOKEN.findall(line):
        tok = raw.strip()
        if tok.startswith("res://"):
            tok = tok[len("res://"):]
        if tok.startswith("assets/"):
            if tok.rstrip("/") == "assets":
                continue  # the folder as a whole is prose, not a licence row
            out.append(tok)
            base = tok if tok.endswith("/") else os.path.dirname(tok) + "/"
        elif base and ("/" not in tok.rstrip("/") or tok.endswith("/")) and re.search(r"[.*/]", tok):
            # `cc0_combat/` or `oni_mask_run_normal.png` next to an assets/ token
            if tok.endswith("/"):
                parent = os.path.dirname(base.rstrip("/")) + "/"
                out.append(parent + tok)
            else:
                out.append(base + tok)
    return out


def licence_text(line: str) -> str:
    """The licence cell of a table row, or the whole line for prose."""
    if line.lstrip().startswith("|"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        return cells[-1] if cells else line
    return line


def load_rules(root: str) -> list[tuple[str, str, str]]:
    rules = []
    for name in ("LICENSES.md", "CREDITS.md"):
        path = os.path.join(root, name)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                for tok in tokens_on_line(line):
                    rules.append((tok, licence_text(line), f"{name}:{n}"))
    return rules


def matches(tok: str, path: str) -> bool:
    if tok.endswith("/"):
        return path.startswith(tok)
    if any(c in tok for c in "*?["):
        return fnmatch.fnmatch(path, tok) or fnmatch.fnmatch(path, tok + "*")
    return path == tok


def asset_files(root: str) -> list[str]:
    files = []
    for dp, _dn, fn in os.walk(os.path.join(root, "assets")):
        for name in fn:
            if name.endswith(IGNORED_SUFFIXES) or IGNORED_NAMES.match(name):
                continue
            files.append(os.path.relpath(os.path.join(dp, name), root).replace(os.sep, "/"))
    return sorted(files)


def recently_added(root: str, since: str) -> set[str]:
    try:
        out = subprocess.run(["git", "-C", root, "log", f"--since={since}", "--diff-filter=A",
                              "--name-only", "--pretty=format:"], capture_output=True, text=True, check=True).stdout
        return {l.strip() for l in out.splitlines() if l.startswith("assets/")}
    except Exception:
        return set()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--md")
    ap.add_argument("--json")
    ap.add_argument("--since", default="24 hours ago")
    a = ap.parse_args()

    rules = load_rules(a.root)
    files = asset_files(a.root)
    new = recently_added(a.root, a.since)
    unlisted, not_cc, ok = [], [], 0
    for path in files:
        hits = [r for r in rules if matches(r[0], path)]
        if not hits:
            unlisted.append(path)
            continue
        # The most specific row decides: LICENSES.md table rows first, then the longest path.
        hits.sort(key=lambda h: (not h[2].startswith("LICENSES.md"), -len(h[0].rstrip("*/"))))
        lic = hits[0][1]
        if OK_LICENCE.search(lic):
            ok += 1
        else:
            not_cc.append((path, hits[0][2], (WARN_LICENCE.search(lic) or re.search(r".{0,30}", lic)).group(0)))

    lines = ["## Licencje assetów", "",
             f"- plików w `assets/`: **{len(files)}**, OK (CC0/CC BY/własne): **{ok}**",
             f"- bez wpisu w LICENSES.md/CREDITS.md: **{len(unlisted)}**",
             f"- z licencją inną niż CC0/CC BY: **{len(not_cc)}**", ""]
    if unlisted:
        lines += ["### Bez wpisu", ""] + [f"- `{p}`{' 🆕' if p in new else ''}" for p in unlisted[:200]] + [""]
    if not_cc:
        lines += ["### Licencja do sprawdzenia", ""] + [f"- `{p}` ({src}: {lic})" for p, src, lic in not_cc[:200]] + [""]
    report = "\n".join(lines)
    print(report)
    if a.md:
        with open(a.md, "w", encoding="utf-8") as f:
            f.write(report + "\n")
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({"files": len(files), "ok": ok, "unlisted": unlisted,
                       "not_cc": [{"path": p, "rule": s, "licence": l} for p, s, l in not_cc],
                       "new": sorted(new)}, f, indent=2)
    return 1 if unlisted or not_cc else 0


if __name__ == "__main__":
    sys.exit(main())
