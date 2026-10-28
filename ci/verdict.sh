#!/usr/bin/env bash
# Last step of a job: turns the outcomes of its continue-on-error checks into the job result.
# Steps keep continue-on-error so every report and artifact is still produced; this step then
# fails the job (red run, ❌ in the summary) if any check failed. The workflows are not required
# checks, so a red run never blocks a merge.
# Usage: ci/verdict.sh "label=outcome" ["label=outcome" ...]   (outcome: success|failure|skipped|cancelled)
set -uo pipefail
bad=()
lines=()
for kv in "$@"; do
  label="${kv%=*}"; outcome="${kv##*=}"
  case "$outcome" in
    success) lines+=("- ✅ ${label}") ;;
    skipped) lines+=("- ⏭️ ${label} (pominięte)") ;;
    *) lines+=("- ❌ ${label} (${outcome:-brak wyniku})"); bad+=("$label") ;;
  esac
done
{
  echo
  if (( ${#bad[@]} )); then echo "## ❌ Wynik: ${#bad[@]} z $# sprawdzeń nie przeszło"; else echo "## ✅ Wynik: wszystko przeszło"; fi
  echo
  printf '%s\n' "${lines[@]}"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
if (( ${#bad[@]} )); then echo "::error::failed checks: ${bad[*]}"; exit 1; fi
echo "all checks passed: $*"
