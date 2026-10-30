# D11 — Opening strike (cinematic po logach)

> Jakub, 28 X 13:40: „po logach taki cinematic z gry mega fast paced jakieś 3 sekundy gdzie grasz — ścina katana, pokoleci przeciwników na pół i na końcu np. używa skilla, który przechodzi w cały biały ekran”. Nie nagrywamy w VR — zaskryptowane w silniku.

## Co jest w grze

Sekwencja przy starcie: **splash (HANABI → NANJO → tytuł) → opening strike (~3,3 s) → biel → intro (seiza)**.
Pominięcie splasha (skip) pomija także opening strike, prosto do intro. Skip w trakcie opening strike: szybkie wygaszenie do bieli (0,4 s) i intro.

Kod: `src/cinematic/opening_strike.gd` (`class_name OpeningStrike`), scena `scenes/cinematic/opening_strike.tscn`, podpięcie w `src/run/run_game.gd` (`_on_boot_splash_finished`, `_on_opening_strike_finished`).

## Scena

- **Las:** prawdziwy generator (`ForestWorld`) z aktywnego profilu WorldGen (D8), stały seed z profilu. Oświetlenie i mgła z `WorldGenLook`, ten sam wygląd co w biegu.
- **Sześć yōkai** stoi w polu przed kamerą. Ciała są zamrożone w miejscu postawienia, bo na zboczu wolne ragdolle zsuwały się o ~0,6 m i płaszczyzna cięcia mijała ciało (diagnoza w testach).
- **Kamera POV:** pierwsza osoba, katana w prawej dłoni. Zaskryptowane przeloty („dashe”) między stacjami (3 ease-out, 0,25–0,3 s), kick FOV podczas przelotu, wstrząs po trafieniu, który gaśnie w ~0,1 s. Pozycja jest funkcją czasu zegara sekwencji, więc każda klatka jest deterministyczna.
- **Cięcia:** pięć zwykłych cięć i finisher. Każde trafienie idzie przez `Yokai.receive_hit` z `kirisute_offer` i `blade_axis`, czyli tą samą ścieżką co żywe ostrze (D4). Płaszczyzna = `KirisuteCut.plane_normal(motion, axis)`. Ostrze porusza się 9 m/s (próg Kirisute to 8 m/s), krawędź prowadzi (`classify_strike` → `edge`, zgodność 1,00).
- **Żywioły:** Sakura (Hanadachi), Storm, Ink, Shadow, Storm, Sakura (finisher). Kolor przekroju i śladu z `Elements.color`.
- **Hit-stop lokalny:** po każdym cięciu zegar sekwencji zwalnia do 0,12× na 0,07 s rzeczywistego czasu. `Engine.time_scale` nigdy nie jest zmieniane.
- **Finisher (~0,6 s):** w punkcie kontaktu wybucha firework żywiołu (`ElementFirework`, skala 1,4), potem przejście w biel (2,98–3,22 s). Biel trzyma się do końca (3,32 s). Potem wejście w intro: welon z bieli gaśnie w 0,6 s. Płaski tint z pierwszej wersji usunięty.
- **Glow przekroju:** nowe kawałki startują 1,6× mocniej niż kawałki biegu (`CUT_GLOW_BOOST`, tylko w tej scenie; test sprawdza próg dla najciemniejszej szkoły, Ink).

## VR i desktop

Jak splash (`RunSplash`): świat renderuje się do `SubViewport` (własny `World3D`) i jest pokazany na desce.
- **VR:** stały panel 4,8 m, 3,5 m przed gogle, przypięty do yaw głowy. Rig gracza jest zablokowany, a kamera XR nigdy nie jest przesuwana.
- **Desktop:** deska wypełnia okno.

Dźwięki są podpięte pod punkt widza (scena ma własną przestrzeń), a `Ambience` i `World` są wyciszone na czas sekwencji.

## Zmiany w kodzie gry (poza nową sceną)

- `Yokai._fx_scene()`: efekty yōkai (przekrój, iskry, fajerwerk, płatki) idą do `SubViewport`, w którym yōkai stoi, a w biegu nadal do `get_tree().current_scene` (zachowanie bez zmian). Powód: `SceneTree.current_scene` przyjmuje tylko bezpośrednie dziecko roota.
- `RunSplash.was_skipped` i `RunSplash.fade_veil()` (wspólny welon dla splasha i opening strike).
- `RunGame`: tworzy `run_cinematic` po splashu i przygotowuje stage w trakcie planszy tytułu (`prepare()`), żeby budowa lasu nie była widoczna.

## Lokacja (ograniczenie)

Kinowa scena stoi na polanie startu (origin, promień ~5,2 m, bez drzew), z układem skalowanym do 0,7. Próby przeniesienia w głąb lasu nie wyszły: w (30, 18) pień zasłaniał kamerę, w (-36, -30) kamera stawała w pniu (zrzut w rundzie, odrzucony). Sonda 9 m czystego miejsca nie znalazła kandydatów w siatce co 6 m. Ostatnia próba (42, −18), jedna runda: las jest w kadrze (`docs/d11/forest_attempt_glade_42_-18_cut1.png`), ale pień stoi za finiszerem i przy szóstym cięciu zasłania cel (`..._finisher.png`), więc wersja została cofnięta na polanę startu. Skutek: w kadrze brak lasu z konceptu.

**Świecenie przekroju** nie jest rozwiązane: 1,6× glow nie przebija się na zrzutach z kamery sceny. Ograniczenie, do rozwiązania przy następnej iteracji (emisja krawędzi). Do zrobienia: maska wycinki drzew w strefie sceny (ForestWorld bez zmian w generatorze) albo ręcznie wybrana, zweryfikowana lokacja.

## Decyzje podjęte bez pytania (do przeglądu)

- Opening strike jest częścią rozruchu, nie biegu. Pominięcie splasha pomija też opening strike (zgodnie z „skip pomija całość”).
- Sześć yōkai, nie cztery: każdy cios to osobny cel, a finisher to szósty.
- Brak nowych assetów. Używamy istniejących modeli yōkai, katany, lasu i dźwięków cięć. Nic nie dochodzi do `CREDITS.md`.
- Opening strike nie jest zapisywany przez Movie Maker do repo; `build/cinematic/opening_strike.avi` jest w `.gitignore`.
- Stage budujemy w trakcie planszy tytułu, nie przy starcie gry, żeby nie dokładać kosztu do startu i do testów wydajności biegu.

## Testy

- `tests/opening_strike_test.gd` (headless, na prawdziwym `run.tscn`): stage w osobnym świecie i z profilem biegu; sześć yōkai; każde cięcie to „edge” wg `classify_strike` przy ≥ 8 m/s; trafienie w kadrze; sześć rozcięć; pieces ≤ `KIRISUTE_MAX_PIECES`; draw calls ≤ budżet; flash przed bielą; biel pełna; ~3 s zegara; hit-stop; `Engine.time_scale` = 1; rig nieruchomy; jedno przekazanie na bieli; stage zwolniony; skip ≤ fade; skip zachowuje wykonane cięcia; splash bez skipu uruchamia sekwencję, splash ze skipem omija ją.
- `tests/boot_splash_test.gd`: zaktualizowane, bo intro czeka teraz na opening strike (ta sama asercja „intro raz”, po sekwencji).

## Screenshoty

`docs/d11/` — zrzuty z gry (okno, nie preview), sceny `tests/opening_strike_screenshots.tscn`.

## Ocena (surowo, zrzuty z gry w `docs/d11/`)

**Działa:** pierwszoosobowy kadr, sześć yōkai w kadrze, ostrze widoczne w każdym cięciu; po cięciu ciało rozpada się na dwa kawałki i leżą na ziemi; finisher przechodzi w biel (`d11_6_white.png` to pełna biel); sekwencja trwa 3,3 s na zegarze.

**Słabe (nie naprawione):**
- **Brak lasu w kadrze.** Scena stoi na polanie startu (promień ~5,2 m, bez drzew). Kadry widzą ścieżkę, torii i nocne wzgórza, a nie las z konceptu. Próba przesunięcia na środek lasu odpadła: drzewa stają w stacjach kamery (pień ~1 m). Sondaż 9 m czystego miejsca w lesie nie znalazł kandydatów. Do rozwiązania: maska wycinki drzew w strefie sceny albo ręcznie wybrane miejsce z mapy.
- **Przekrój nadal słabo czytelny.** Po cięciu połowy to niebieskie bloki (`d11_2`, `d11_4`); glow 1,6× nie przebija się na tej odległości. Do poprawy: emisja samej krawędzi zamiast całego przekroju.
- **Yōkai to istniejący model** (prymitywy, „robot”), daleko od premium z GDD §16. Nie zmieniałem go w tym kroku.
- **Finisher:** firework w punkcie kontaktu jest na zrzucie mały (`d11_4`). Nie widać go jako rozbłysku; do zrobienia: większa skala albo rozbłysk na ostrzu.
- **Ślad katany** jest prawie niewidoczny.
- **Wideo (Movie Maker):** patrz niżej w podsumowaniu.

**Dalej:** wybór czystego miejsca w lesie lub maska drzew, mocniejszy przekrój (emisja krawędzi), finisher z rozbłyskiem zamiast tintu, ślad katany.
