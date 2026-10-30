# Interakcja z kapliczką (hokora)

Jak gracz wchodzi w interakcję z kapliczką (P8, uwaga 7). Kapliczka ma dwa niezależne
punkty interakcji: **dzwon (suzu)** i **stół ofiarny (ołtarz)**.

## 1. Dzwon (suzu) — ładunek żywiołu

- **Co daje:** 1 ładunek żywiołu do `ElementSystem` (D21). Bufor trzyma max 3 ładunki.
- **Jak się dzwoni:**
  - **VR:** ostrze (koniec klingi) albo dłoń dotyka dzwonu.
  - **Desktop:** klawisz **E**, gdy dzwon jest bliżej gracza niż stół ofiarny.
- **Zasięg:** dotyk w promieniu `ElementBalance.HOKORA_BELL_HAND_RADIUS` (0.3 m) od dzwonu,
  gracz nie dalej niż `HOKORA_BELL_TOUCH_RADIUS` (2.0 m) od dzwonu w poziomie.
- **Cooldown:** `HOKORA_BELL_COOLDOWN` (60 s), osobno dla każdej kapliczki.
- **Pełny bufor:** dzwon dzwoni cicho i nie zużywa cooldownu (krótki odpoczynek 1.5 s).
  Ładunek nie przepada.
- **Żywiołu:** kolejne ładunki z jednej kapliczki idą po kolei przez żywioły bojowe
  (sakura, burza, tusz, cień), z przesunięciem zależnym od slotu.
- **Wskazówka:** dzwon lekko świeci, gdy gracz stoi w zasięgu i dzwon jest gotowy.
- **Działa także w zgaszonej kapliczce** (po wyborze ofudy). Dzwon jest niezależny od wyboru.

## 2. Stół ofiarny — wybór ofudy (D12)

Bez zmian: dłoń na stole ofiarnym (VR) albo E przy stole (desktop) otwiera żółte
karty ofudy. Wybór gasi kapliczkę na resztę przebiegu.

## 3. Pierwszeństwo na desktopie (E)

E sięga do najbliższego z dwóch celów, mierząc odległość po ziemi:
- dzwon gotowy i bliżej gracza niż stół → dzwoni,
- w innym wypadku (dzwon bliżej stołu, dzwon w cooldownie) → sięga do stołu, jak dotąd.

## 4. Gdzie jest w kodzie

- `src/world/hokora_shrine.gd`: model dzwonu, cooldown, zasięg, podświetlenie.
- `src/world/hokora_manager.gd`: `poll_bell`, `nearest_bell`.
- `src/run/run_game.gd`: `_poll_shrine_touch`, `_poll_shrine_bell`, `_ring_bell`.
- `src/run/element_balance.gd`: stałe `HOKORA_BELL_*`.
- Test: `tests/hokora_bell_test.gd`.
