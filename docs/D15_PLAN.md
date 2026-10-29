# Plan D15: Boss Oni sterowany przez AI (Meta Muse Spark / Llama)

## 1. Diagnoza obecnego stanu bossa

### Dlaczego boss nic nie robił:
1. **Zasięg uwięzi (`leash_radius`):** `TrainingDummy` korzysta z `DuelistBrain`, który domyślnie ograniczał ruch do `leash_radius = 3.0 m` wokół punktu `home_position`. W `WaveDirector.spawn_oni_boss` boss spawnował się w odległości 9.2 m od gracza (`_ring_point(..., 9.2)`), przez co po 3 metrach marszu zatrzymywał się w odległości >6 m od gracza.
2. **Warunek ataku:** W `DuelistBrain` ataki są dozwolone tylko przy `dist <= range + MAX_STEP` (~2.55 m). Ponieważ boss nie mógł podejść bliżej niż 6.2 m, nigdy nie podejmował inicjatywy i stał bezczynnie w mgle.
3. **Brak parametrów w profilu:** `EnemyCatalog.make_oni_profile` definiował `tactics = {"kind": "oni"}` bez explicit `attacks: true`, `track_player: true`, ani podniesionego `leash_radius`.
4. **Prowadzenie kotwicy fizycznej (`max_anchor_lead`):** `TrainingDummy` miał `max_anchor_lead = 0.0` (stworzony jako statyczny manekin w dojo), co blokowało naturalne podążanie kotwicy ragdolla w terenie za poruszającym się celem na większe dystanse (w przeciwieństwie do `Yokai`, który ma `max_anchor_lead = 0.4`).

### Dlaczego był za duży / "gigantyczny":
1. Sztywna skala roota `scale = Vector3(1.28, 1.28, 1.28)` w `run_oni_boss.gd` w połączeniu ze skalami nałożonych skorup meshów (`shell.scale = 1.14`, `mask.scale = 1.18`, `club.scale = 1.15`) oraz domyślną pozycją i rozmiarami kończyn dawały nienaturalne proporcje i zaburzenia fizyki Jolt/Godot na węzłach RigidBody3D.
2. Brak skalowania hitboksów kolizyjnych pod realny wymiar w metrach VR: w VR postać o wzroście 2.6–2.8 m powinna górować nad graczem (~1.75 m) jako potężny wódz demonów, ale mieścić się w całości w kadrze kamery z odległości ~5 m (FOV ~90° obejmuje ~10 m w pionie przy 5 m dystansu).

---

## 2. Architektura rozwiązania

### Krok 1: Skala i geometria (~2.5–3.0 m)
- Wysokość docelowa: ~2.7 m (od podłoża do szczytu rogów).
- Przeskalowanie definicji części (`_define_parts`) lub jednolite, stabilne skalowanie w `RunOniBoss`:
  - Dopasowane hitboksy (pelvis, chest, head, ramiona, nogi) do wizualnej bryły.
  - Maczugi Kanabō z precyzyjnym hurtboksem do uderzeń w gracza.
  - Weryfikacja: z odległości 5 m cały boss (stopy i rogi) widoczny w kadrze gracza.

### Krok 2: Walka lokalna (offline & failsafe)
- Podchodzenie do gracza w trybie walki (`max_anchor_lead = 0.6`, brak blokady uwięzi na arenie, dynamiczne zamykanie dystansu).
- 3 telegrafowane ataki z wyraźnymi sygnałami (wind-up, błysk oczu, dźwięk `enemy_tell`):
  1. **Kanabō Slam (pionowy):** potężne uderzenie z góry, długi wind-up, duży zasięg, okno na kontrę.
  2. **Demon Sweep (poziomy):** szerokie zamachnięcie na wysokości klatki piersiowej.
  3. **Demonic Thrust (pchnięcie / lunge):** gwałtowny wypad w przód.
- Fazy walki wg % HP:
  - Faza 1 (100%–60% HP): metodyczne podchodzenie, pojedyncze ataki, dłuższe telegrafowanie (~0.7 s).
  - Faza 2 (60%–30% HP): agresywne natarcia, kombinacje 2 ataków, szybsze odzyskiwanie równowagi (~0.5 s), wzmocnione światło rim light.
  - Faza 3 (<30% HP): wściekłość (enrage), bezlitosne tempo, parry stawia bossa w stan podatności na kontratak.
- Rzeczywiste zadawanie obrażeń graczowi przez `PlayerHealth.take_hit`. Bez `Engine.time_scale = 0`.

### Krok 3: Warstwa decyzyjna AI ("Mózg" bossa)
- Komponent `OniAiBrain` / `OniAiClient`:
  - Wywołania asynchroniczne via `HTTPRequest` co 3–5 sekund.
  - Payload wejściowy: stan walki (HP bossa, HP gracza, dystans, faza, ostatnie akcje gracza: parry/cut/hit).
  - Walidacja odpowiedzi przez ścisłą białą listę (whitelist):
    - `tactic`: `["stalk", "advance", "retreat", "circle_left", "circle_right", "taunt"]`
    - `attack`: `["slam", "sweep", "thrust", "combo"]`
    - `target_distance`: float z zakresu [1.5, 4.5]
    - `speech`: krótki tekst (maks. 80 znaków) do dymka.
  - Failsafe: timeout (3.0 s), błąd sieciowy, błędny JSON lub brak klucza natychmiast wraca do lokalnej logiki bez opóźniania ani jednej klatki.

### Krok 4: Integracja z Meta Model API i konfiguracja (Review Fix)
- **Faktyczny endpoint Meta (OpenAI-compatible) i źródło dokumentacji:**
  - Zgodnie z oficjalną dokumentacją Meta Model API (Chat Completions): https://dev.meta.ai/docs/protocols/chat-completions
    domyślnym adresem jest `https://api.meta.ai/v1/chat/completions`, model `muse-spark-1.3`, autoryzacja `Authorization: Bearer <MODEL_API_KEY>`.
  - `llama-api.meta.com` nie występuje w dokumentacji Meta Model API; Llama API to osobny produkt (`https://api.llama.com/compat/v1`) z innymi modelami, więc nie jest domyślnym endpointem bossa.
  - Alternatywne endpointy zgodne z OpenAI `/v1/chat/completions` można wpisać ręcznie w Settings (np. Groq albo Together AI); presety pozostają wyłącznie wygodą, nie są wymagane.
- **Konfigurowalność w Settings:**
  - Domyślny adres: `https://api.meta.ai/v1/chat/completions` (zdefiniowany w `VRComfortSettings.DEFAULT_META_ENDPOINT` oraz `OniAiClient.DEFAULT_META_ENDPOINT`).
  - Użytkownik / deweloper może swobodnie zmienić endpoint w ustawieniach (`ai_endpoint` w `user://hanabi_vr.cfg` via `set_meta_api_endpoint()`).
  - `OniAiClient` wysyła zapytanie pod `VrComfortSettings.instance.get_effective_meta_api_endpoint()` (z fallbackiem na stałą), więc pole `ai_endpoint` naprawdę steruje ruchem; test `endpoint z Settings trafia do zapytania` przechwytuje URL bez sieci.
- **Bezpieczeństwo i maskowanie kluczy:**
  - Klucz API pobierany jest hierarchicznie:
    1. Zapisany w konfiguracji gracza (`user://hanabi_vr.cfg`, pole `ai_meta_api_key`).
    2. Z lokalnego pliku `secrets/meta_api_key.txt` (ściśle ignorowany w `.gitignore`).
    3. W repozytorium udostępniony jest WYŁĄCZNIE szablon `secrets/meta_api_key.txt.example`.
  - **Zero kluczy w logach:** Klucz w logach systemowych, konsoli i `GameEvents` jest zawsze rygorystycznie maskowany (`mask_key()` -> `●●●●...ab12`).
  - W razie braku klucza, timeoutu (>3.0s) lub błędu sieci, system natychmiast wraca do zoptymalizowanego lokalnego zachowania taktycznego offline bez utraty choćby jednej klatki.

### Krok 5: Dymek tekstowy (Speech Bubble)
- 3D Billboard nad głową bossa (wysokość ~3.0 m).
- Stylistyka Hanabi: ciemny tusz japoński (sumi-e) z subtelną krawędzią, elegancka typografia, brak kiczu.
- Znika po 3.5–4.5 s z płynnym fade-out.
- Pozycjonowanie odporne na geometrię i kąty kamery VR.

### Krok 6: Testy i weryfikacja wizualna
- Testy headless:
  - Boss porusza się do gracza, inicjuje ataki, zadaje obrażenia `PlayerHealth`.
  - Mock dostawcy AI: decyzja poprawnie przekłada się na zachowanie bossa.
  - Odpowiedź śmieciowa / timeout -> bezpieczny powrót do lokalnej walki.
  - Wysokość i zasięg bossa w granicach 2.5–3.0 m.
- Test wizualny na prawdziwej scenie `run.tscn`:
  - Boss widoczny w kadrze z 5 m.
  - Dymek tekstowy wyrenderowany i czytelny na tle mgły.
  - Zrzuty ekranu zapisane do `docs/d15/`:
    - `01_boss_scale_vs_player.png` (porównanie skali boss vs gracz)
    - `02_boss_attack_windup.png` (wind-up i telegrafowanie ataku)
    - `03_boss_speech_bubble.png` (dymek tekstowy nad bossem)
