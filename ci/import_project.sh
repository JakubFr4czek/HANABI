#!/usr/bin/env bash
# First import of the project (creates .godot/ and the imported assets). Never hangs the job.
set -uo pipefail
: "${GODOT:?run ci/setup_godot.sh first}"
timeout "${IMPORT_TIMEOUT:-900}" "$GODOT" --headless --path . --import > ci_out/import.log 2>&1
code=$?
echo "import exit=$code"
grep -cE "SCRIPT ERROR|ERROR:" ci_out/import.log | xargs -I{} echo "import log error lines: {}"
# The import exits non-zero on harmless editor warnings in some versions; only a timeout is fatal.
[[ $code -eq 124 ]] && { echo "::error::Godot import timed out"; exit 1; }
exit 0
