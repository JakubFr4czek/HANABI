#!/usr/bin/env bash
# Persistent per-job cache on the self-hosted box runner (replaces actions/cache).
# Usage: ci/box_cache.sh restore|save <name> <path-in-checkout>
# Lives under $HANABI_CI_CACHE (default /home/box/ci-cache); only ever touches
# $HANABI_CI_CACHE/<name> and the given path inside the checkout.
set -euo pipefail
op="$1"; name="$2"; rel="$3"
root="${HANABI_CI_CACHE:-/home/box/ci-cache}"
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad cache name: $name"; exit 1; }
[[ "$rel" != /* && "$rel" != *..* ]] || { echo "path must be relative to the checkout: $rel"; exit 1; }
dir="$root/$name"
case "$op" in
  restore)
    if [[ -d "$dir" ]]; then rm -rf "$rel"; mkdir -p "$(dirname "$rel")"; cp -a "$dir" "$rel"; echo "cache $name restored ($(du -sh "$rel" | cut -f1))";
    else echo "cache $name empty"; fi ;;
  save)
    if [[ -e "$rel" ]]; then mkdir -p "$root"; rm -rf "$dir.tmp"; cp -a "$rel" "$dir.tmp"; rm -rf "$dir"; mv "$dir.tmp" "$dir"; echo "cache $name saved";
    else echo "nothing to save at $rel"; fi ;;
  *) echo "usage: $0 restore|save <name> <path>"; exit 1 ;;
esac
