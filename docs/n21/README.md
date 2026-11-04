# N21 – English by default + Meta API key baked into the Quest APK (CZĘŚCIOWO)

## 1. English
- Settings › META AI tab (src/ui/skill_tree_canvas.gd): all labels/status/help in English.
- HUD row ŁADUNKI → CHARGES; boss demo plate "Oni myśli" → "Oni thinks"; wave presets "Default"/"Demo – gentle".
- Boss duelist intro line → "Your path ends here!".
- VrComfortSettings.ai_language defaults to "en"; the old saved key `meta_ai/language` is ignored
  (migration: only the new key `language_n21` is read, missing → "en"). PL toggle stays optional.
- Oni prompt: speech "in English" + "The speech field MUST be written in English only."
- Fallback client language default "en" (EN fallback lines). PL lines remain only for the optional PL toggle.
- Not translated (editor/tool-only validation messages, comments): worldgen_profile / wave_profile / worldgen_budget checks.

## 2. Key in APK
- quest-apk.yml: step "Meta API key (from secret, never logged)" before import/export: writes
  secrets/meta_api_key.txt from `secrets.META_API_KEY` via env + printf; empty secret → message only, build continues.
- export_presets.cfg (Meta Quest only): include_filter += secrets/meta_api_key.txt.
- get_effective_meta_api_key() already reads res://secrets/meta_api_key.txt and strip_edges().
- .gitignore unchanged: /secrets/* excluded, *.example kept. No key in repo.

## 3. Checks
- oni_boss_ai_test (xvfb, opengl3, timeout 300): hit the 300 s timeout; 54 PASS, 6 FAIL
  (bubble text replaced by fallback line within 6 frames, parry ×2, N13 entrance intro 0.00 s, retreat ×2).
  The machine was low on RAM at the start (~450 MB free); N17 saw similar load-related timing fails. Not re-verified.
- n21_run.png: run.tscn, Movie Maker 30 fps 960×540, frame 450 (~15 s), 0 SCRIPT ERROR.
