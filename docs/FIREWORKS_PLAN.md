# D18 — Odległe fajerwerki (motyw matsuri)

Jakub, 29.10: gra dzieje się podczas letniego festiwalu; w trakcie festiwalu yōkai się budzą. Fajerwerki są **straszakiem**: odległe, wytłumione, nieprzewidywalne. Nie są celem, nagrodą ani mechaniką. Gracz słyszy i widzi coś, czego nie może dosięgnąć.

## Decyzje

| # | Decyzja | Dlaczego |
|---|---|---|
| 1 | **Fabuła:** letnie matsuri, yōkai budzą się w trakcie festiwalu (GDD §1, §2). Nazwa festiwalu: propozycja w `assets/text/INTRO_TEXT.md`. | Jakub, 29.10. Uzasadnienie HANABI w GDD §1. |
| 2 | **Fajerwerki nie zmieniają rozgrywki.** Brak punktów, pickupów, celów, wpływu na wrogów. | Atmosfera i napięcie, nie nagroda. |
| 3 | **Dystans daleki:** 150–400 m od gracza, w poziomie. **Wysokość:** 18–60 m (nad linią drzew, za mgłą). | Mgła pełna przy 11 m, więc daleki wybuch jest tylko poświatą w mgle. |
| 4 | **Kierunek:** losowy azymut. Nowy kierunek musi różnić się o **≥ 70°** od dwóch poprzednich (nigdy w to samo miejsce dwa razy z rzędu). | Brak punktu odpalania do ustalenia. |
| 5 | **Rytm daleki:** odstęp losowy 20–60 s. Z szansą 30% seria 2–4 wybuchów co 0.6–2.5 s. Zero stałego rytmu. | Jakub: "nieokreślony", "żeby gracz się nie spodziewał". |
| 6 | **Eskalacja (bliski):** losowo co 120–240 s wybuch na **40–80 m**, za drzewami, nigdy bliżej niż 40 m. Jaśniejszy i głośniejszy (glow mocniejszy, dźwięk ok. −11 dB). Hook do fal D10: po `wave_started` z szansą 30% eskalacja za 0–3 s. | "Nie zawsze" zgodnie z opisem. |
| 7 | **Dźwięk opóźniony:** opóźnienie = dystans / 343 m/s. Dla 150–400 m daje 0.44–1.17 s (zgodne z 0.4–1.2 s). Dla bliskich 40–80 m: 0.12–0.23 s. | Prędkość dźwięku, bez magii. |
| 8 | **Bus audio `Fireworks`** (wysyłany do Master, nie do World, bo World ma już reverb i jest wyciszany pod filmami). Łańcuch: **LowPass** (cutoff ustawiany per wybuch: daleki 300–600 Hz, bliski 900–1200 Hz) → **Reverb** (room 0.9, predelay 60 ms, dry 0.35 / wet 0.65) → **Compressor** (próg −18 dB, ratio 3, atak 20 ms, zwolnienie 250 ms) → **HardLimiter** (sufit −3 dB). Głośność busa idzie suwakiem Ambience z Ustawień. | Jakub: "bardzo mi zależy na wytłumionym dźwięku". |
| 9 | **Głośność:** daleki −18…−24 dB, bliski −12…−9 dB. Dźwięk przestrzenny: `AudioStreamPlayer3D` z `unit_size` 400 (brak tłumienia w zakresie 40–400 m, tylko panorama). | Huk ma być daleki, nie głośny. |
| 10 | **Sample (CC0, już w repo):** `hanabi_proc`/`cc0_storm`: `thunder_impact_heavy_1/2` (Kenney Impact, CC0) jako huk; `firework_pop_soft_000` (Kenney, CC0) jako trzask tylko przy eskalacji. Bez nowych pobrań (sieć i konta niedostępne). Bus robi resztę. | Licencje już w CREDITS.md. |
| 11 | **Wizja:** pooled `MeshInstance3D` z quadem (shader: unshaded, additive, `fog_disabled`, depth test ON, depth write OFF). Dzięki `fog_disabled` daleki wybłysk jest widoczny w mgle, a drzewa i wzgórza w zasięgu chunków go zasłaniają. Trzy kolory stonowane (bursztyn, błękit-szary, przytłumiony róż), nigdy neon. | Premium: dużo mgły, mało blasku. |
| 12 | **Cząstki:** jeden `GPUParticles3D` one-shot (12–18 iskier), tylko dla bliskich. Daleki = sama poświata. | Iskra o średnicy 1 m z 300 m to ułamek stopnia, nie widać. |
| 13 | **Brak `OmniLight3D`.** Mgła gaśnie przy 11 m, więc światło przy 40+ m nie oświetla niczego widocznego. Błysk niesie poświata. | Usunięte z planu: zero kosztu, zero efektu. |
| 14 | **Redukcja błysków (Ustawienia > UŁATWIENIA):** `flash_scale()` mnoży jasność poświaty. Przy 0% poświata znika, dźwięk zostaje (jak grzmot pioruna). | Zgodne z D3. |
| 15 | **Budżet Quest 3:** +≤4 draw calls (3 quady w puli, 1 cząstki), 0 świateł dynamicznych, ≤2 głosy audio (pula 2 graczy). Zero alokacji nodów na wybuch. | GDD §9, QUEST_TEST. |
| 16 | **Parametry (D8):** grupa „Distant fireworks" w `WorldGenProfile`: przedziały interwału, szansa serii, dystanse, szanse eskalacji, głośności. Edycja w docku World Gen. | Jedno źródło prawdy. |
| 17 | **Intro (§9):** po splashu Nanjo plansza tekstowa (`assets/text/INTRO_TEXT.md`), zanim ruszy intro seiza. Gra nie ma osobnego menu głównego; plansza stoi na miejscu, w którym menu byłoby. Fade in 2 s, trzymanie 5 s, fade out 2 s (9 s). Pomijalna triggerem/A/X/Space/Enter/Esc (tak jak reszta splashu). Na początku planszy słychać jeden daleki wybuch. | Jakub: "wiąże intro z D18". |
| 18 | **Start i stop:** harmonogram rusza po `run_started`, zatrzymuje się po śmierci. Pauza = zatrzymanie (PROCESS_MODE_PAUSABLE). | Nie ma wybuchów podczas menu i end screenu. |

## Testy (krytyczne, krokowanie czasu, bez czekania)

Suita `tests/distant_fireworks_test.tscn` (headless, krok `advance(dt)`):
- odstępy serii 20–60 s, co najmniej 8 serii w 10 min symulacji,
- dystans daleki 150–400 m, bliski 40–80 m, nigdy bliżej niż 40 m,
- bliskie rzadko: 2–6 w 10 min, minimum 100 s między nimi,
- kolejne kierunki różnią się o ≥ 70°,
- dźwięk spóźniony: daleki 0.4–1.2 s, zawsze = dystans / 343,
- bus `Fireworks`: cutoff ≤ 800 Hz dla dalekich, ≤ 1.2 kHz dla bliskich; reverb z wet > dry; kompresor i limiter na miejscu; głośność w zakresie,
- budżet: draw calls ≤ +4, zero `OmniLight3D`, głosy ≤ 2, liczba nodów stała po 50 wybuchach,
- redukcja błysków: przy 0% poświata niewidoczna, dźwięk zaplanowany,
- plansza intro: pokazuje tekst z pliku, pomija się, kończy po czasie i przekazuje do intro.

Test wizualny `tests/d18_fireworks_visual_test.tscn`: **okno, nie headless**. Mierzy jasność pikseli nad linią drzew przed i po dalekim wybuchu oraz zapisuje trzy kadry do `docs/d18/` (daleki przez mgłę, bliski za drzewami, ten sam kadr bez wybuchu). W headless wypisuje `SKIP` (konwencja `run_tests.sh`).

## Poza zakresem D18
- Hook do D10 (fale) tylko jako sygnał; pełna choreografia fal nie jest częścią tego zadania.
- Nagrania do odsłuchu w `docs/d18/` są offline'owym przybliżeniem busa (ffmpeg: lowpass + echo). Żywy bus w grze jest źródłem prawdy.
