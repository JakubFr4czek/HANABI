# D18: odległe fajerwerki matsuri — notatka dla Jakuba

Plan i decyzje: [`docs/FIREWORKS_PLAN.md`](../FIREWORKS_PLAN.md). Tekst intro: [`assets/text/INTRO_TEXT.md`](../../assets/text/INTRO_TEXT.md).

## Do odsłuchu

- `far_boom_preview.ogg`: daleki huk (Kenney Impact, CC0), ok. −21 dB.
- `near_boom_preview.ogg`: bliski huk z trzaskiem (`firework_pop_soft`, CC0), ok. −11 dB.

Te pliki to **offline'owe przybliżenie** busa (ffmpeg: `lowpass` + `aecho`). Źródłem prawdy jest żywy bus w grze (poniżej). Nie słyszałem ich w grze, bo test odpala się bez dźwięku. Oceń je na słuchawkach i na goglach.

## Bus `Fireworks` (src/world/distant_fireworks.gd, `_ensure_bus`)

| Efekt | Ustawienie | Po co |
|---|---|---|
| Wysyłka | Master (nie World, bo World ma reverb i jest wyciszany pod filmami) | suwak Ambience z Ustawień steruje głośnością busa |
| LowPassFilter | cutoff 450 Hz (daleki), 1100 Hz (bliski), ustawiany w chwili dźwięku | wytłumienie, im dalej tym niżej |
| Reverb | room 0.9, predelay 60 ms, damping 0.7, dry 0.35, wet 0.65 | pogłos lasu, mokry > suchy |
| Compressor | próg −18 dB, ratio 3, atak 20 ms, zwolnienie 250 ms | wyrównanie, bez ostrych pików |
| HardLimiter | sufit −3 dB | zapas przed wyjściem |

Poziomy w dźwięku: daleki −21 dB (zakres −24…−18), bliski −11 dB (zakres −12…−9). `AudioStreamPlayer3D` z `unit_size` 400, więc tłumienie odległości nie działa w zakresie 40–400 m, a zostaje tylko panorama.

Opóźnienie: dystans / 343 m/s. Dla 150–400 m: 0.44–1.17 s. Dla bliskich 40–80 m: 0.12–0.23 s.

## Wizja

- Glow: quad z shaderem `src/shaders/distant_firework_glow.gdshader`. Unshaded, additive, `fog_disabled`, z włączonym testem głębi. Rdzeń gaussowski, szeroka mgliska poświata i rozszerzająca się powłoka. Wszystko zanika do zera przed krawędzią quada.
- Kolory (stonowane, nie neon): bursztyn, różowy pył, jasne złoto, fiolet.
- Daleki: promień 40 m, bez cząstek. Bliski: promień 12 m, z 10 iskrami.
- Brak `OmniLight3D`: mgła kończy się przy 11 m, więc światło przy 40+ m nie oświetla nic widocznego.
- Budżet: 3 quady w puli + 1 emiter iskier = max 4 wywołania; 0 świateł; 2 głosy audio (pula). Na Queście nie mierzyłem.

## Test wizualny (okno, nie headless)

`tests/d18_fireworks_visual_test.tscn` mierzy na prawdziwej scenie `run.tscn`:

- Pomiar ma miejsce przy wyłączonym deszczu i cząstkach (krople zmieniają się między klatkami i fałszują wynik). Porównanie dwóch klatek w tym samym momencie: z poświatą i bez, zamrożony wybuch.
- Wyniki (ostatni przebieg): daleki wybuch podnosi jasność o **0.064** (maks. nad obszarem), szczyt 0.47, brak jasnych plam, krawędź kroku **0.047** (próg 0.05, blisko progu; krawędź to prawdopodobnie zasłonięcie przez zbocze terenu, a nie ostrość poświaty). Bliski wybuch (samą poświatą): **0.136** przy szczycie 0.59, krawędź 0.008.

Zrzuty: `desktop_title_plate.png` (plansza intro, okno), `00_same_frame_no_burst*.png`, `01_far_burst_in_mist*.png`, `02_near_burst_behind_trees*.png`. Bez `_rain` deszcz wyłączony (pomiar), z `_rain` włączony (tak to wygląda w grze).

## Ocena surowa zrzutów (wymóg GDD: premium, nie sylwester)

- **Daleki (`01_..._rain`):** wygląda jak bladoniebieskofioletowa mgliska poświata za torii. Nic nie oślepia i nie ma ostrych krawędzi. Ale jest tak słaby, że przy szybkim spojrzeniu można go nie zauważyć. Słabe: nie widać „wybuchu" ani powłoki, to raczej światło we mgle. Do poprawy, jeśli Jakub chce, żeby był wyraźniejszy: zwiększyć `firework_glow` w profilu (z 0.10 w górę) albo wzmocnić powłokę.
- **Bliski (`02_..._rain`, `02_...`):** miękki różowy oświetlony obłok z kilkoma iskierkami. Jest za okrągły i wygląda bardziej jak duch-światło niż wybuch. Iskry czytają się jak pył, nie jak eksplozja. Słabe: brak wyraźnej struktury powłoki w tym dystansie.
- **Ogólnie:** kolor i jasność trzymają się palety i nie ma neonu. Kształt jest za prosty, żeby uznać go za wybuch fajerwerku. Najlepsza część to ciche, pełne mgły rozświetlenie. Nie mierzyłem tego na goglach ani nie słuchałem w grze.

## Plansza intro (`desktop_title_plate.png`)

Cinzel (małe kapitaliki), wyśrodkowane, na czarnym tle, czytelne. Pierwsza wersja miała linię na ok. 83% szerokości planszy (ok. 60° w VR), więc skróciłem propozycję w `INTRO_TEXT.md`. Najdłuższa linia to teraz ok. 67%. Surowo: plansza jest czysta, bez kiczu, ale to tylko szkic tekstu do redakcji Jakuba.

## Co nie jest sprawdzone

- Dźwięk w grze: testy sprawdzają plan (opóźnienie, bus, poziomy, cutoff), nie słyszą go. Odsłuch na Queście to punkt kontrolny.
- Wydajność na Queście 3: budżet policzony, nie zmierzony.
- Dock World Gen pokazuje nową grupę „Distant fireworks" tylko, jeśli dock czyta grupy z `group_names()`. Nie sprawdzałem tego w doku.
- Hook do fal D10 (`WaveDirector.wave_started`) jest podpięty, ale nie strojony z choreografią fal.
