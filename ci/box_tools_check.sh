#!/usr/bin/env bash
# Verifies the tools the box runner is expected to have (installed once, not per run).
# Usage: ci/box_tools_check.sh tool [tool...]   -> fails listing anything missing.
set -uo pipefail
missing=()
for t in "$@"; do
  if [[ "$t" == py:* ]]; then python3 -c "import ${t#py:}" 2>/dev/null || missing+=("$t");
  else command -v "$t" >/dev/null || missing+=("$t"); fi
done
if (( ${#missing[@]} )); then echo "::error::missing on runner: ${missing[*]} (see ci/README.md, 'Runner na boxie')"; exit 1; fi
echo "runner tools ok: $*"
