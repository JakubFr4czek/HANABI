#!/bin/zsh
# Runs every tests/*_test.tscn headless, N at a time, each under `timeout 600`.
# Usage: tools/run_tests.sh [jobs] [name-filter]   (logs: /tmp/hanabi_tests/<name>.log)
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-.tools/Godot.app/Contents/MacOS/Godot}
JOBS=${1:-4}
FILTER=${2:-}
OUT=/tmp/hanabi_tests
mkdir -p $OUT
names=($(ls tests/*_test.tscn tests/oni_boss_screenshots.tscn 2>/dev/null | xargs -n1 basename | sed 's/\.tscn$//' | grep -E "$FILTER"))
printf '%s\n' $names | xargs -P $JOBS -n1 tools/run_one_test.sh
pass=0; total=0
for n in $names; do
	total=$((total+1))
	r=$(cat $OUT/$n.result 2>/dev/null)
	# A GDScript runtime error in a sync check aborts that check silently, so it counts as a failure too.
	if [[ $r == *"exit=0 "* ]] && grep -q "ALL PASSED" $OUT/$n.log && ! grep -q "SCRIPT ERROR" $OUT/$n.log; then pass=$((pass+1)); else echo "FAIL: $r"; grep -E "FAIL|SCRIPT ERROR|TIMEOUT" $OUT/$n.log | head -5; fi
done
echo "testy: $pass/$total pass"
