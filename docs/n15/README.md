# N15 – stabilność bossa: retreat, HP→0

## Przyczyna (retreat)
Taktyka `retreat` dawała bossowi tylko zwykły chód wstecz (`plant=false`, przyspieszenie 4 m/s²,
`anchor_gain` 0,08) i to tylko do 3,2 m od gracza. W pierwszych ~0,4 s `move_velocity` dopiero
skręca z bocznego ruchu flanki na „do tyłu”, a ciało goni kotwicę ruchu ze stałą ~0,15 s.
Przez to w 60 klatkach (0,67 s przy 90 Hz) ciało przechodziło tylko ~0,15 m. Ten sam log z N13
(prędkość ~1 m/s dopiero po 0,5 s, ciało nie nadąża) to pokazywał. Sam ruch nie miał też obejścia:
gdy za plecami stał pień albo skała, `_blocked_toward` zerował ruch i boss stał w miejscu.
Skala 1,08 nie jest przyczyną (bisekcja N13).

## Zmiana (src/enemies/oni_boss_brain.gd)
- **Odskok (hiki-ashi):** pierwsze 0,45 s retreatu to zaplanowany „burst” (`plant=true`):
  przyspieszenie 25 m/s², `anchor_gain` ×4, prędkość 1,7× (~1,9 m/s). Stopy suną do tyłu,
  potem boss normalnie odchodzi krokiem.
- **Dystans:** boss cofa się do `max(3,2 m, dystans startowy + 1 m)`, a nie zawsze do 3,2 m.
- **Przeszkoda za plecami:** gdy prosto do tyłu jest zablokowane, boss próbuje skosów
  ±35° i ±70° (strona zgodna z `_circle_dir`) i wybiera pierwszy wolny.
- Wygląd, skala 1,08, rim, environment i N14: bez zmian.

## HP→0
Ścieżka kodu jest poprawna: HP 0 → knockdown → get-up → `_on_permanent_defeat` → `oni_defeated`.
W przebiegu po zmianie check przechodzi (signal true, active false). Test nie był osłabiany,
dostał tylko diagnostykę w etykiecie (hp, is_dead, stan ciała), żeby kolejny fail dało się od razu
odczytać. Wcześniejsze faile najpewniej szły za tym samym rozjazdem czasu. Retreat, który nie
odszedł, zostawiał bossa w zwarciu i scenariusz po nim (fallback z 6 m, potem trafienie) startował
z innego stanu. To wniosek, nie zmierzony dowód.

## Wyniki
- oni_boss_ai_test przebieg 1: **ALL PASSED** (retreat 2,08 → 3,32 m, flank 1,04 m, HP→0 ok,
  Phase 3 windup 0,47 vs 0,68 s, requests gaps [4,39; 2,84; 3,61] s). Przebieg trwał 898 s,
  bo maszyna była obciążona.
- Scena wizualna `f5_katana_boss_shots` (xvfb, gl_compatibility, 960×540) → `after_01_boss_4m.png`
  i `after_02_ai_bubble.png`. Wyniki: boss 3,95 m od kamery, głowa i stopy w kadrze, ciało
  odcina się od lasu (51%), maska czyta się (Δ 1,57), dymek w kadrze: PASS.
  **FAIL: „katana is in frame and visible” (1/9 próbek).** Na zrzucie z intro (guard) ciemne,
  cienkie ostrze ginie na tle ciemnego torsu i lasu. N15 zmienia tylko footwork taktyki retreat,
  a ten kadr to planted guard z intro, więc najpewniej fail jest starszy (z czytelności N13).
  Nie sprawdziłem tego na bazowym commicie, bo zabrakło czasu.
- Ocena zrzutu: sylwetka i rim czytelne, maska wyraźna. Słabo: kończyny wyglądają jak cienkie
  rurki, katana bossa jest prawie niewidoczna (ciemna stal w ciemności). To do poprawy osobno,
  bo zakres N15 zabrania zmian wyglądu.
- **Brak drugiego przebiegu** oni_boss_ai_test: jeden przebieg trwał ~15 min, a limit 45 min się kończył.

## Dalej
1. Drugi przebieg oni_boss_ai_test (stabilność retreat/HP→0/windup/requests).
2. Check katany w `f5_katana_boss_shots`: porównać z 21107dc. Jeśli to N13, dać lekki połysk
   krawędzi samej klingi (bez zmiany rimu ciała).
