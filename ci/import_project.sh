#!/usr/bin/env bash
# First import of the project (creates .godot/ and the imported assets). Never hangs the job.
set -uo pipefail
: "${GODOT:?run ci/setup_godot.sh first}"
# arm64 runners (pi2) import textures as etc2 only, while the committed *.import files (from the Mac)
# also list s3tc. With a restored .godot cache, Godot sees matching .md5 files, skips the reimport and
# leaves the committed .import pointing at s3tc .ctex files that don't exist -> "Unable to open file"
# at runtime. Drop the .md5 of every texture whose listed dest file is missing so Godot reimports it
# and rewrites its .import for this platform.
stale=0
while IFS= read -r -d '' imp; do
  mapfile -t dests < <(grep -E '^dest_files=' "$imp" | grep -oE 'res://\.godot/imported/[^"]+' || true)
  for d in "${dests[@]}"; do
    f=".godot/imported/${d#res://.godot/imported/}"
    if [[ ! -e "$f" ]]; then
      base=$(sed -E 's/(-[0-9a-f]{32}).*/\1/' <<<"$f")
      rm -f "$base.md5"; stale=$((stale + 1)); break
    fi
  done
done < <(find . -path ./.godot -prune -o -name '*.import' -print0)
[[ -d .godot ]] && echo "stale imports forced to reimport: $stale"
timeout "${IMPORT_TIMEOUT:-900}" "$GODOT" --headless --path . --import > ci_out/import.log 2>&1
code=$?
echo "import exit=$code"
grep -cE "SCRIPT ERROR|ERROR:" ci_out/import.log | xargs -I{} echo "import log error lines: {}"
# The import exits non-zero on harmless editor warnings in some versions; only a timeout is fatal.
[[ $code -eq 124 ]] && { echo "::error::Godot import timed out"; exit 1; }
# Honest check: every dest file named by an .import must exist now.
missing=0
while IFS= read -r -d '' imp; do
  mapfile -t dests < <(grep -E '^dest_files=' "$imp" | grep -oE 'res://\.godot/imported/[^"]+' || true)
  for d in "${dests[@]}"; do
    [[ -e ".godot/imported/${d#res://.godot/imported/}" ]] || { missing=$((missing + 1)); echo "missing import: $d ($imp)"; }
  done
done < <(find . -path ./.godot -prune -o -name '*.import' -print0)
[[ $missing -gt 0 ]] && { echo "::error::$missing imported files still missing after import"; exit 1; }
exit 0
