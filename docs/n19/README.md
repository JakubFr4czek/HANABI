# N19 – krótki test dymka bossa i spóźnionych odpowiedzi AI

Status: **GOTOWE**. Kod gry bez zmian: test nie wykazał błędu, poprawka N18 działa.
Oświetlenie, mgła, niebo, environment i materiały są nietknięte. Istniejących testów i progów nie zmieniałem.
Pełnego `oni_boss_ai_test` nie uruchamiałem.

## Nowy test: `tests/oni_bubble_fade_test.tscn`
Boss z kataną stoi sam na podłodze. Nie używa run.tscn ani sieci. Zamiast klienta AI jest atrapa `HeldAiClient`,
która trzyma każdy request, dopóki test sam na niego nie odpowie. Dzięki temu test steruje tym,
kiedy odpowiedź „dolatuje”. Czas: **7 s** (headless), watchdog 120 s.

    timeout 180 $GODOT --headless --path . tests/oni_bubble_fade_test.tscn

Wynik: **13 PASS / 0 FAIL** (log: `oni_bubble_fade_test.log`):
1. Odpowiedź na czas pokazuje linię. W połowie czasu wyświetlania linia nadal jest widoczna. **Dymek znika 3,99 s
   po ostatniej linii** (fade-in + 3,5 s + fade-out = 4,01 s, próg ≤ 4,41 s).
2. Odpowiedź przy wstrzymanych decyzjach (`_ai_timer` 999) nie pokazuje linii i nie zmienia taktyki.
   Trafia do logu jako `decisions_on_hold`.
3. Dwa requesty w locie: nowsza odpowiedź się pokazuje, a starsza, która przychodzi później, jej nie zastępuje
   (`superseded`). Taktyka zostaje ta z nowszej odpowiedzi.
4. Odpowiedź po śmierci bossa (hp 0, przerwa między zapytaniami w normie 4,11 s) nie pokazuje linii (`boss_dead`).

Pierwszy przebieg miał 1 FAIL z winy samego testu. Sprawdzałem `is_showing()` w tym samym ticku,
w którym nowa linia dopiero zaczynała fade-in (0,06 s). Test czeka teraz na koniec fade-in. W kodzie gry niczego nie zmieniałem.

## Zrzut
`n19_02_ai_bubble.png` z `f5_katana_boss_shots` (xvfb, opengl3, 960×540, 19 s): 6/6 PASS,
w tym katana 9/9 i dymek AI nad głową.
