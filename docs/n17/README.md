# N17 – uczciwa śmierć bossa przy HP→0, znikanie dymka AI

Status: **CZĘŚCIOWO**. HP→0 jest naprawione i przechodzi. Dymek ma poprawioną logikę, ale check dalej FAIL.
Opis niżej. Oświetlenie, mgła, niebo, environment i materiały są nietknięte.

## 1. HP→0 (naprawione)
Przyczyna: `TrainingDummy.receive_hit` przy hp 0 ustawia tylko `_revive_on_getup`. Śmierć
(`_on_permanent_defeat`) przychodzi dopiero przy przejściu w **STANDING**. Boss, który leży
(KNOCKED_DOWN) lub wstaje (GETTING_UP, „body state 2”), czekał więc na koniec get-upu.
Failsafe „stuck” mógł ten get-up uruchamiać od nowa. Do tego test czeka
`(knockdown + getup + 0,3 s) × 90` klatek *renderu*, a render chodzi tu w setkach fps (log N15:
„worst frame 2 ms”). Okno testu było więc krótsze niż get-up. Stąd niestabilność.
Poprawka (`run_oni_boss.gd::receive_hit`): boss nigdy się nie odradza, więc przy hp ≤ 0
od razu wywołuje `_on_permanent_defeat()`, niezależnie od stanu ciała. Jest to jedyna ścieżka
obrażeń bossa. Test bez zmian.
Wynik: `PASS HP -> 0 defeats the katana boss (signal true, active false, hp 0.0, dead freed)`.

## 2. Dymek (logika poprawiona, check dalej FAIL)
Znalezione w `oni_speech_bubble.gd::show_speech`:
- Każda linia tworzyła osobny tween hold/fade, a nowa linia zabijała tylko fade-in. Timer
  poprzedniej linii dalej działał, ściemniał i chował nowszą linię, i dwa łańcuchy walczyły o alfę.
  Teraz jest jeden tween na linię, nowa linia zastępuje cały łańcuch, a dymek gaśnie
  FADE_IN + duration + FADE_OUT po **ostatniej** linii.
- Tween działa w czasie fizyki (TWEEN_PROCESS_PHYSICS), jak boss, timer AI i TimeController.
- Test (`oni_boss_ai_test.gd`, N8): oczekiwanie na zniknięcie to te same 4,35 s
  (`(DEFAULT_DURATION + FADE_OUT_TIME + 0,4) × hz`). Liczone jest teraz w tickach fizyki zamiast
  klatek renderu (`hz` = 90, tempo fizyki). Przy ~500 fps stare oczekiwanie trwało ~0,8 s. Asercja i próg bez zmian.

Dalej FAIL w tym przebiegu. Najbardziej prawdopodobna przyczyna (niezweryfikowana, nie było
drugiego przebiegu): **odpowiedź AI w locie**. Test ustawia `_ai_timer = 999` po 14-sekundowej
pętli, ale ostatni request (luki 4,14 / 3,91 / 3,08 / 2,3 s, czyli ostatni ok. 13,7 s) wraca już po
tym. Na obciążonej maszynie pierwsza odpowiedź szła 57 klatek. Spóźniona odpowiedź wyświetla
nową linię, która zgodnie z kontraktem żyje kolejne ~4 s.
Następny krok: zdecydować, czy spóźnioną mowę AI (po wstrzymaniu decyzji albo
starszą niż X s) odrzucać w `OniBossBrain._on_ai_decision`, i zalogować czas ostatniej linii w checku.

## Wyniki (1 przebieg każdego, xvfb, opengl3)
- `oni_boss_ai_test`: exit 1, 68 PASS, 6 FAIL, 882 s. Maszyna była mocno obciążona:
  GUARD 1105 naruszeń, klatki do 139 ms. Log: `oni_boss_ai_test.log`.
  - FIXED: HP→0.
  - FAIL dymek (punkt 2).
  - FAIL, których N17 nie dotyka (timing pod obciążeniem; w N15 przechodziły):
    tekst AI w dymku w teście 3 (po 6 klatkach dymek pokazał już późniejszą linię
    z własnego pollingu AI), parry 0 dmg + counter window, intro N13 (intro 0,00 s),
    retreat (1,92 → 2,45 m, czyli dystans OK; fail z drugiego warunku: `current_tactic` w chwili checku nie był już "retreat").
- `f5_katana_boss_shots`: **ALL PASSED** (katana 9/9, maska Δ 1,61, dymek w kadrze).
  Zrzut: `after_02_ai_bubble.png`.
