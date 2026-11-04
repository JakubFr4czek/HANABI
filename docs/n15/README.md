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
