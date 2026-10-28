#!/bin/zsh
# Runs one test scene under `timeout 600` (headless, except the windowed render tests); writes /tmp/hanabi_tests/<name>.{log,result}.
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-.tools/Godot.app/Contents/MacOS/Godot}
OUT=/tmp/hanabi_tests
mkdir -p $OUT
name=$1
ARGS="--desktop"
# Tests that drive the real XRPlayer through XrSim need --xr-sim instead.
if [[ $name == xr_play_test || $name == vr_menu_pause_test || $name == boot_splash_xr_test ]]; then ARGS="--xr-sim"; fi
# Tests that read rendered pixels need a real window: no --headless for them.
HEADLESS="--headless"
if [[ $name == worldgen_path_visible_test || $name == boot_splash_visual_test ]]; then HEADLESS=""; fi
start=$SECONDS
timeout 600 $GODOT ${=HEADLESS} --path . --fixed-fps 90 res://tests/$name.tscn -- ${=ARGS} > $OUT/$name.log 2>&1
echo "$name exit=$? $((SECONDS-start))s" > $OUT/$name.result
