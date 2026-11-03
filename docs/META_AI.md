# Meta AI w HANABI – Oni sterowany przez Muse Spark (N8)

## Jak włączyć
1. Menu (pauza) → **Ustawienia → META AI**.
2. Skopiuj klucz Meta Model API do schowka i kliknij **WKLEJ KLUCZ (SCHOWEK)**. Klucz trafia do `user://` (ustawienia gry), w UI widać tylko maskę `abcd••••••••wxyz`.
   Alternatywa przy buildzie z PC: plik `secrets/meta_api_key.txt` (jest w `.gitignore`, nigdy nie commitujemy).
3. **AI BOSS: WŁĄCZONY** (domyślnie tak). Język mowy: PL / EN.
4. Do nagrania wideo: **DEMO OVERLAY „ONI MYŚLI”: WŁ.** – pod dymkiem bossa pojawia się lakowa tabliczka
   `Oni myśli: flank_left – ai · Muse Spark` (albo `– fallback · lokalnie`). Domyślnie wyłączone.

Endpoint: `https://api.meta.ai/v1/chat/completions`, model `muse-spark-1.3` (format chat completions).

## Co jest wysyłane (co 2–5 s, tylko gdy boss walczy)
- Stan walki: HP bossa i gracza, dystans, faza (1–3), ostatnie akcje gracza (`cut` / `parry`).
- `player_style` – 2–3 fakty z logu zdarzeń (`GameEvents`, trafienia gracza):
  `cut_from` (`right` / `left` / `above` / `mixed` – skąd gracz zwykle tnie), `favourite_element`, `cuts`.
  Dzięki temu boss może powiedzieć np. „You always cut from the right.”
- Nic więcej: żadnych danych osobowych, nagrań, pozycji w świecie, identyfikatorów urządzenia.

Odpowiedź (JSON w `choices[0].message.content`): `tactic`, `attack`, `target_distance`, `speech`.

## Limity i walidacja
- Jedno zapytanie naraz; odstęp 2–5 s (nigdy per klatka). `max_tokens` 100.
- Whitelista taktyk (miecznik: `aggressive`, `defensive`, `feint`, `flank_left`, `flank_right`, `retreat`) i ataków (`slam`, `sweep`, `thrust`, `combo`); wszystko inne → własna logika duelisty (`duel`).
- Dystans przycięty do 1,4–1,9 m (zasięg ciosu). Mowa: jedna linia, bez znaków sterujących/cudzysłowów, max **60 znaków**, cięta na granicy słowa + „…”.
- Taktyka trzyma 4,5 s, potem wraca `duel`. Każda decyzja ląduje w logu jako `oni_ai_decision_applied` (taktyka, atak, źródło, powód fallbacku, pozycja bossa).

## Fallback (gra nigdy nie czeka na sieć)
| Sytuacja | Zachowanie |
|---|---|
| brak klucza / AI wyłączone | od razu lokalnie, zero ruchu sieciowego, zero logów |
| timeout (3 s liczone w klatkach gry) | anulowanie zapytania i fallback w tej samej klatce |
| 401 / 500 / błąd sieci | fallback (`http_401`, `http_500`, `net_*`) |
| śmieciowy JSON / treść nie-JSON | fallback (`bad_json`, `bad_content`) |
| taktyka spoza whitelisty | `duel` (lokalna logika), reszta odpowiedzi użyta |
Fallback = lokalna FSM duelisty + gotowe kwestie PL/EN dla każdej fazy, więc walka działa w 100% offline.

## Testy (bez klucza, bez internetu)
- `tests/meta_api_mock_server.gd` – lokalna atrapa API na `127.0.0.1` (GDScript `TCPServer`), tryby `ok`, `401`, `500`, `garbage`, `bad_content`, `hang`.
- Adres testowy działa **tylko w buildzie debug**: Ustawienia (`[meta_ai] endpoint`) albo `-- --oni-ai-endpoint=http://127.0.0.1:PORT/v1/chat/completions`. Build release przyjmuje wyłącznie `https://`.
- `tests/oni_boss_ai_test.tscn` (sekcja N8): run.tscn + prawdziwe HTTP do atrapy – rytm zapytań 2–5 s, `flank_left` wykonany (boss schodzi w bok), dymek + overlay, znikanie dymka, wszystkie błędy → fallback bez zawieszenia klatki, whitelista, przycinanie mowy, brak klucza.
- `tests/n8_meta_ai_shots.tscn` (okienkowy): piksele dymka z 4 m (tekst/kontrast, nad głową, nie zasłania bossa) + screenshoty w `docs/n8/`.
