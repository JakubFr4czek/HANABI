# N18 – spóźnione odpowiedzi AI w dymku bossa, ponowny przebieg oni_boss_ai_test

Status: **CZĘŚCIOWO** (przekroczony limit czasu, maszyna mocno obciążona: load 6–11, wolny RAM ~0,5 GB).
Wygląd bez zmian: oświetlenie, mgła, niebo, environment i materiały są nietknięte.

## 1. Dymek: odrzucanie nieaktualnych odpowiedzi AI (zrobione)
`src/enemies/oni_boss_brain.gd`:
- Każdy request z `_poll_ai` dostaje numer (`_ai_request_seq`). Callback to `_on_ai_reply.bind(seq)`.
- `_on_ai_reply` odrzuca odpowiedź (log `oni_ai_decision_dropped` z `reason`), gdy:
  - `superseded`: po niej poszedł nowszy request,
  - `decisions_on_hold`: `_ai_timer > AI_MAX_POLL_GAP` (5 s, najdłuższa przerwa, jaką mózg ustawia sam).
    Wyższy timer oznacza, że decyzje są wstrzymane (intro, test, pauza),
  - `boss_dead`: body zwolnione, poza drzewem albo hp ≤ 0.
- Bezpośrednie `apply_ai_decision` (testy) działa jak dotąd. Testy i progi bez zmian.

## 2. Ponowny przebieg oni_boss_ai_test (1×, xvfb, opengl3)
Log: `oni_boss_ai_test.log`. **72 PASS, 0 FAIL** do chwili przerwania. Proces skończył się `timeout` (exit 124,
4756 s) w oczekiwaniu na check „the bubble is gone a few seconds after the last line”. Tego checku
(i dalszych sekcji N8) **nie zweryfikowano**.
Faile z N17, które teraz przechodzą (wniosek: to było obciążenie maszyny, kod bez zmian):
- tekst AI w dymku w teście 3 (`'Poczuj gniew demonów!'`),
- parry: 0 obrażeń (67.5 == 67.5) i okno kontry (1.63 s),
- wejście N13 (intro 1.47 s),
- retreat (2.08 → 3.32 m, taktyka retreat).

## Braki
- Check znikania dymka: nie ma wyniku (timeout przebiegu). Do zrobienia: przebieg na spokojnej maszynie.
- Zrzut z `f5_katana_boss_shots` nie został zrobiony (stop testów i scen zarządzony przez supervisora).
