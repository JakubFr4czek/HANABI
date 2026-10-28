#!/usr/bin/env bash
# Verifies the tools the box runner is expected to have (installed once, not per run).
# Usage: ci/box_tools_check.sh tool [tool...]   -> fails listing anything missing.
set -uo pipefail
# The runner is started by run.sh (no systemd on the box), which ignores the runner's .path file,
# so the box tool dirs are not on PATH by default. Add them for this step and all later steps.
tools_root="${HANABI_CI_TOOLS:-/home/box/ci-tools}"
for d in "$tools_root/venv/bin" "$tools_root/bin"; do
  if [[ -d "$d" && ":$PATH:" != *":$d:"* ]]; then
    PATH="$d:$PATH"
    [[ -n "${GITHUB_PATH:-}" ]] && echo "$d" >> "$GITHUB_PATH"
  fi
done
export PATH
missing=()
for t in "$@"; do
  if [[ "$t" == py:* ]]; then python3 -c "import ${t#py:}" 2>/dev/null || missing+=("$t");
  else command -v "$t" >/dev/null || missing+=("$t"); fi
done
if (( ${#missing[@]} )); then echo "::error::missing on runner: ${missing[*]} (see ci/README.md, 'Runner na boxie')"; exit 1; fi
echo "runner tools ok: $*"
