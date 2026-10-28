#!/usr/bin/env bash
# Downloads the official Godot 4.7.2 Linux editor binary into $GODOT_DIR (cached by actions/cache)
# and exports GODOT=<path> to $GITHUB_ENV. Usage: ci/setup_godot.sh
set -euo pipefail
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GODOT_DIR="${GODOT_DIR:-$HOME/.godot-bin}"
BIN="$GODOT_DIR/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
if [[ ! -x "$BIN" ]]; then
  mkdir -p "$GODOT_DIR"
  url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  echo "Downloading $url"
  curl -fsSL --retry 3 -o "$GODOT_DIR/godot.zip" "$url"
  unzip -o -q "$GODOT_DIR/godot.zip" -d "$GODOT_DIR"
  rm -f "$GODOT_DIR/godot.zip"
  chmod +x "$BIN"
fi
"$BIN" --version
if [[ -n "${GITHUB_ENV:-}" ]]; then echo "GODOT=$BIN" >> "$GITHUB_ENV"; fi
echo "GODOT=$BIN"
