# CI HANABI (GitHub Actions)

Cztery osobne workflowy, każdy co 2 h (`0 */2 * * *`, UTC) i ręcznie (`workflow_dispatch`).
Żaden nie jest wymaganym checkiem, a kroki mają `continue-on-error`, więc nic nie blokuje merge'a.

| Workflow | Co sprawdza | Artefakty |
|---|---|---|
| `code-quality.yml` | gdlint + gdformat --check (bez `addons/`), profil `ci/gdlintrc` | `code-quality-report` |
| `security-assets.yml` | gitleaks (cała historia, zredagowane), licencje assetów (`ci/check_licenses.py`), rozmiar repo (`ci/size_report.py`) | `security-assets-report` |
| `correctness.yml` | `tools/run_tests.sh` (Xvfb dla testu renderu), fuzzing `tests/ci/fuzz_runner.gd`, pokrycie Nano Coverage | `test-logs`, `fuzz-logs`, `coverage-report` |
| `visual-perf.yml` | stałe zrzuty `tests/ci/visual_snapshots.gd` + diff z poprzednim runem, perf JSON (>20% skok), wizualny fuzzing `tests/ci/visual_fuzz.gd` | `visual-baseline`, `visual-diff`, `visual-fuzz-frames` |

Wszystko leci zawsze w całości co 2 h na self-hosted runnerze `eepy-box` (etykiety `self-hosted, hanabi, box`),
więc minuty GitHub Actions nie są zużywane. Każdy workflow ma własną grupę `concurrency` z
`cancel-in-progress: false`: nowy run czeka na poprzedni zamiast go przerywać.

## Runner na boxie

- Runner: `/home/box/actions-runner-hanabi` (brak systemd, więc `watchdog.sh` co 60 s sprawdza `Runner.Listener`
  i w razie potrzeby startuje `run.sh`; logi `runner.log`, `watchdog.log`). Start po restarcie maszyny:
  `cd /home/box/actions-runner-hanabi && setsid nohup ./watchdog.sh >/dev/null 2>&1 < /dev/null &`
- Narzędzia (zainstalowane raz): Godot 4.7.2 w `/home/box/ci-tools/godot` (`GODOT_DIR` z `.env` runnera,
  `ci/setup_godot.sh` pobiera go tylko gdy brak), gdlint/gdformat + gitleaks w `/home/box/ci-tools/bin`,
  Nano Coverage (prebuilt) w `/home/box/ci-tools/nano-coverage/nano_coverage_godot`, z apt: zsh, xvfb,
  Mesa llvmpipe, ImageMagick, scons; python3 z pillow/numpy.
- Cache zamiast `actions/cache`: `ci/box_cache.sh restore|save <nazwa> <ścieżka>` w `/home/box/ci-cache/<nazwa>`
  (import `.godot` per workflow, baseline zrzutów `visual-baseline`, aktualizowany tylko z `main`).
- `ci/box_tools_check.sh` failuje krok z listą brakujących narzędzi zamiast instalować je w jobie.
- `.github/actionlint.yaml` deklaruje etykiety runnera dla actionlint.

## Lokalnie

```sh
# fuzz (seed z logu CI)
godot --headless --path . --fixed-fps 90 res://tests/ci/fuzz_runner.tscn -- --xr-sim --seed=1 --steps=250
# wizualny fuzz, jedno miejsce
godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 960x540 \
  res://tests/ci/visual_fuzz.tscn -- --desktop --seed=7 --locations=12 --dirs=4 --only=3 --out=/tmp/vfuzz
# stałe zrzuty + perf
godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 960x540 \
  res://tests/ci/visual_snapshots.tscn -- --desktop --out=/tmp/shots
```
