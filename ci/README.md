# CI HANABI (GitHub Actions)

Cztery osobne workflowy, każdy co 4 h (`7/12/17/22 */4 * * *`, UTC, rozstrzelone o kilka minut, bo jeden runner) i ręcznie (`workflow_dispatch`).
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

## Licencje assetów (`ci/check_licenses.py`)

Każdy plik w `assets/` musi mieć wiersz w `LICENSES.md` lub `CREDITS.md` (ścieżka w backtickach, folder lub glob).
Akceptowana licencja w komórce wiersza:

- CC0 / CC BY (bez SA/NC/ND) / public domain,
- **SIL OFL 1.1** – tylko dla fontów, z autorem i plikiem licencji w wierszu,
- **`Project-own art`** – własna grafika projektu, także AI-generated; znacznik musi być w wierszu wprost
  (obecnie: `project art` w ikonach i splashu to `Project-own art, AI-generated for HANABI by Nanjo`).
  Ogólne słowa typu „projekt” nie wystarczą.

Plik bez wiersza daje błąd (exit 1); inna licencja też. Skrypt nie ma listy wyjątków po nazwie pliku.
Przy dodawaniu assetu: wiersz w `LICENSES.md`, atrybucja w `CREDITS.md`, a dla CC BY – także w grze.

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

## Pokrycie lokalnie (macOS, bez boxa)

Nano Coverage da się zbudować i uruchomić na Macu, ale nigdy w repo (addon trafia tylko do kopii roboczej).
Kroki (SHA jak w `correctness.yml`, `NANO_COVERAGE_SHA`):

```sh
# 1. addon ze źródeł (scons: pip3 install --user scons)
git clone --recursive https://github.com/IgorBayerl/nano-coverage-godot /tmp/nano
cd /tmp/nano && git checkout fce7a0ae9281533456023275504bbd81d74d95be && git submodule update --init --recursive
scons -j8 target=editor build_tests=no    # -> demo/addons/nano_coverage_godot/bin/libnano_coverage_godot.macos.editor.universal.dylib

# 2. kopia projektu (bez .git i .tools), addon + ustawienia jak w CI
rsync -a --exclude .git --exclude .tools --exclude assets_raw --exclude assets_incoming --exclude secrets ./ /tmp/hanabi_cov/
cd /tmp/hanabi_cov && rm -rf addons/nano_coverage_godot && cp -r /tmp/nano/demo/addons/nano_coverage_godot addons/
# manifest oczekuje nazw per architektura: skopiuj dylib pod każdą z nich (macOS, universal)
for n in macos.editor.x86_64 macos.editor.arm64 macos.template_debug.x86_64 macos.template_debug.arm64 macos.template_release.x86_64 macos.template_release.arm64; do
  cp addons/nano_coverage_godot/bin/libnano_coverage_godot.macos.editor.universal.dylib addons/nano_coverage_godot/bin/nano_coverage_godot.$n.dylib; done
printf '\n[nano_coverage]\n\ngeneral/ignore_paths=PackedStringArray("res://tests/**", "res://tools/**", "res://ci/**", "**/*_test.gd")\n' >> project.godot
mkdir -p ci_out
G=/ścieżka/do/repo/.tools/Godot.app/Contents/MacOS/Godot

# 3. import, instrumentacja, testy, raport (raport przywraca skrypty)
"$G" --headless --path . --import
"$G" --headless --path . --script res://ci/coverage_instrument.gd
GODOT="$G" zsh tools/run_tests.sh 4
"$G" --headless --path . --script res://ci/coverage_report.gd
python3 ci/lcov_summary.py coverage-report/lcov.info --md ci_out/coverage.md
```

Uwagi: testy instrumentowane są kilka razy wolniejsze, a testy czasowe (np. `oni_boss_ai_test`, „kanabō swing connects”,
`blade_feel_test`, perf-checki) mogą wtedy failować bez zmiany kodu. Wynik pokrycia liczy się z przebiegu, w którym
zestaw testów przeszedł; w razie wątpliwości powtórz pojedynczy test (`tools/run_one_test.sh <nazwa>`) na zainstrumentowanej kopii.
Każde ponowne uruchomienie testów po instrumentacji wymaga ponownego `coverage_instrument.gd`, bo raport przywraca skrypty.

## Raspberry Pi runners (since 2026-11-02)
- All self-hosted CI ran on one self-hosted Raspberry Pi runner, so jobs ran one after another.
  Godot 4.7.2 arm64 in `~/ci-tools/godot`, gdtoolkit 4.5.0 + scons venv in `~/ci-tools/venv` (links in `~/ci-tools/bin`), gitleaks in `~/ci-tools/bin`,
  Nano Coverage built for arm64 in `~/ci-tools/nano-coverage/nano_coverage_godot`, cache and visual/perf baseline in `~/ci-cache`.
  Runner `~/actions-runner-hanabi`, user systemd unit `gh-runner-hanabi.service` (linger on).
- Perf is compared only with the previous run on the same Pi (llvmpipe on ARM), so the budget calibrates itself to the Pi.
- `raspberka` (Pi 1, 2 GB) and the box (`hanabi`) run nothing. quest-apk stays on `ubuntu-latest`.
- Import on pi2 takes ~100 s; one fuzz seed of 250 steps takes ~6 min.
