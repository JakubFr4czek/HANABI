# N20 – gotowość do zgłoszenia (log run.tscn, dokumentacja, licencje)

Status: **GOTOWE**. Kod gry, oświetlenie, mgła, niebo, environment, materiały i testy bez zmian.
Zmiany tylko w dokumentacji.

## 1. Log run.tscn (1×, headless, `timeout 300`, `--quit-after 2700`, `-- --desktop`)
Wynik: exit 0, `GUARD SUMMARY: clean`. **Zero SCRIPT ERROR, zero brakujących zasobów, zero null reference.**
W logu są tylko komunikaty środowiska, nie błędy gry:
- OpenXR: brak runtime'u na maszynie → gra przechodzi na desktop rig (oczekiwane).
- `Property not found: xr/openxr/extensions/hand_tracking`: odczyt modułu OpenXR silnika (ostrzeżenie, bez skutków).
- Jolt: „custom solver bias … '<unknown>'”: ostrzeżenie silnika. W projekcie nic nie ustawia `custom_solver_bias`
  (grep), więc nie ma czego poprawiać w skryptach.
- Przebieg okienkowy do zrzutu: dodatkowo `3 resources still in use at exit`. To wyciek przy wyjściu z `--quit-after`
  (Movie Maker), nie wpływa na grę. Nie ruszałem.

Znalezione błędy skryptów: **0**. Poprawione: **0** (kodu nie zmieniałem, więc testów systemu nie uruchamiałem).

## 2. Dokumentacja i licencje
- `docs/SUBMISSION.md`: boss w runie to Oni z kataną (nie kanabō). Wejście 6–7,5 m przed graczem, 1,8 s intro,
  skala 1,08 (~1,95 m), retreat back-hop, śmierć przy HP 0. Odrzucanie spóźnionych odpowiedzi AI i znikanie dymka.
  Tryb `-- --demo` (Oni w 60 s, rozjaśnienie startu 10 s + 8 s). Opis yōkai z N12. Tabela zgodności rozszerzona
  o stałe z kodu.
- `README.md`: wiersz „Yōkai Enemies & Boss” zaktualizowany o N12–N19, w „Run on desktop” dopisany `-- --demo`.
- `CREDITS.md`: shader ostrza bossa (N16) jako własny. Notka, że N12–N19 nie dodały zewnętrznych assetów
  (`git diff d71656c~1 0a2d5b4 -- assets addons` jest pusty).
- `ci/check_licenses.py`: 177/177 plików w `assets/` ma wpis i dozwoloną licencję.
- Sekrety: w gicie z `secrets/` jest tylko `meta_api_key.txt.example`. Grep wzorców kluczy znajduje wyłącznie
  hashe w URL-ach Sketchfab i `"test-key-not-a-secret"` w testach.
- Pliki > 50 MB: brak (największy to `YujiBoku-Regular.ttf`, 8,5 MB).

## 3. Zrzut
`n20_run_25s.png`: run.tscn, xvfb, opengl3, 960×540, Movie Maker 30 fps, klatka 749 (~25 s), desktop rig.
Widać las w deszczu, rozwidlenie ścieżki, torii i hokorę we mgle oraz katanę w ręce. Klimat jak wcześniej.
