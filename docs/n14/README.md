# N14 – jaśniejszy start runu w demie (pod filmik)

Decyzja (4.11, supervisor): pierwsze sekundy runu w demie były za ciemne do nagrania.

- **Tylko profil demo:** `-- --demo` (ten sam `WaveProfile.DEMO_FLAG` co N7/N13). Domyślny run bez zmian
  (`RunDemoGrade.enabled = false`, ekspozycja nie jest nawet zapisywana).
- **Tylko ekspozycja tonemapu:** `tonemap_exposure × 1,30` (profil domyślny 0,92 → 1,20) przez pierwsze
  **10 s** runu (intro liczy się jako t = 0), potem **8 s** smoothstep do wartości profilu.
  Paleta, mgła, kolor nieba/tła, ambient, księżyc, las i sakura – nietknięte; zero nowych świateł,
  cieni i draw calli. Ambientu świadomie nie ruszam: błyskawica nadpisuje `ambient_light_energy`
  i każda moja zmiana gryzłaby się z nią.
- Kod: `src/run/run_demo_grade.gd`, wpięty w `RunGame._configure_run_light` i `_physics_process`.
  Splash i opening strike mają własne „void” Environment na kamerze – efekt ich nie dotyczy.

## Zrzuty (run.tscn, ta sama kamera: spawn, ścieżka, torii 16 m, katana w ręce)

`before_start.png` (domyślny run / demo bez podbicia), `after_start.png` (demo, t = 0),
`after_fade.png` (demo po 19 s – identyczny z PRZED).
Generuje i sprawdza: `tests/n14_demo_start_visual_test.tscn -- --shots=docs/n14` (okienkowo; headless = SKIP).

Pomiar: średnia luminancja 0,071 → 0,092 (+30 %), ścieżka pod stopami 0,138 → 0,171,
kontrast bezwzględny (std) 0,135 → 0,155, przesunięcie odcienia 1,2°, mgła za torii 0,010 → 0,029
(torii odcina się mocniej), po fadzie 0,072 (= PRZED).

## Ocena (surowo)

Czytelniej: trawa przy ścieżce i ścieżka w dal wychodzą z czerni, torii ma jaśniejsze tło mgły,
fioletowe niebo i mgła mają ten sam odcień – klimat zostaje. Słabe: pnie i korony bliskich drzew
są dalej prawie czarne (ekspozycja nie podniesie zera), a katana zyskuje niewiele – to rim/materiał,
nie światło sceny. Podbicie jest celowo delikatne; jeśli na filmie nadal za ciemno, następny krok to
`EXPOSURE_LIFT` 0,40 (jedna stała), a nie zmiana świateł.
