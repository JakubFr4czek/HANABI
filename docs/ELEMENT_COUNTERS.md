# D17 – Wrogowie z żywiołami i krąg kontr

*Status: plan (krok 0), 2026-10-30. Zadanie od Jakuba (29.10): „żeby żywioły się kontrowały i zadawały sobie więcej obrażeń;
ten sam żywioł – znacznie mniej; katana bez żywiołu = baseline."*

## 0. Stan wyjściowy (przed D17)

- **Żywioły:** 4 (Sakura 桜, Storm 雷, Ink 墨, Shadow 影) + `none` (goła stal). Źródło: `src/core/elements.gd`, GDD §5, ELEMENTS_PLAN.md.
- **Gracz:** katana trzyma jeden żywioł przez 20 s (`ElementSystem`). Gola stal = `Elements.NONE`.
- **Wrogowie roju (swarm):** `WaveDirector.spawn_enemy_at` zawsze wywołuje `configure_kind(SWARM, Elements.NONE)`. **Rój nie ma żywiołu.**
- **Elity:** mają żywioł, losowany równomiernie z 4 (`EnemyCatalog.elite_element_for_roll`). Mają `resistances` per żywioł
  (`EnemyCatalog.make_elite_profile`): własny ×0.34, „słaby” ×1.72, fizyczny ×0.42. Słabość z `ELITE_COUNTER_ELEMENT`
  to **pary wzajemne** (Storm↔Ink, Sakura↔Shadow), a nie krąg.
- **Oni:** bez żywiołu (`make_oni_profile`, brak `element`).
- **Pipeline obrażeń:** `Yokai.receive_hit` → `EnemyProfile.damage_multiplier(zone, element)` = mnożnik strefy × `resistances[element]`.
  Potem: parry-armor elity (×0.26 / ×1.35), kirisute, sever, `snappedf(…, 0.1)`.
- **Wzorce:** `ElementBalance` już jest jedynym źródłem liczb żywiołów (E4). Kontry tam nie ma.

## 1. Krąg kontr (cztery żywioły, każdy kontruje dokładnie jeden i jest kontrowany przez jeden)

Krąg skierowany: `Ink → Storm → Sakura → Shadow → Ink` (strzałka = „kontruje”, czyli atak żywiołem po lewej strony
mocniej rani wroga żywiołem po prawej).

| Atakujący (gracz) | Kontruje (×1.5) | Fabuła (1 linia) |
|---|---|---|
| **Ink 墨** | Storm 雷 | Mokry tusz gasi iskrę: pędzel uziemia wyładowanie, zanim dotknie wroga. |
| **Storm 雷** | Sakura 桜 | Burza rozwiewa płatki: grzmot rozrzuca kruche ostrza z każdej strony. |
| **Sakura 桜** | Shadow 影 | Blask płatków przebija cień: pink light spala to, co ukrywa się w mroku. |
| **Shadow 影** | Ink 墨 | Cień zna każdy ślad pędzla: Yami-watari wchodzi w lukę, którą tusz zostawia. |

Pary, które nie są na kręgu, są **neutralne** (×1.0): Ink↔Sakura, Storm↔Shadow (przeciwległe wierzchołki).
Relacja „kontruje” jest jednokierunkowa: Storm kontruje Sakurę, a Sakura nie kontruje Storm.

Zmiana względem obecnych par elitarnych: Storm-elita nadal jest słaba na Ink (bez zmian), Shadow-elita nadal słaba na Sakura (bez zmian),
Sakura-elita słaba na **Storm** (było Shadow), Ink-elita słaba na **Shadow** (było Storm). Stare pary wzajemne (Storm↔Ink, Sakura↔Shadow)
przestają istnieć, bo krąg wymaga, żeby każdy żywioł kontrował tylko jeden.

## 2. Mnożniki (startowe, do balansu)

| Relacja (atakujący → obrońca) | Mnożnik | Stałe w `ElementBalance` |
|---|---|---|
| kontra (krąg, jedna krawędź) | ×1.5 | `COUNTER_MULTIPLIER` |
| ten sam żywioł | ×0.5 | `SAME_MULTIPLIER` |
| neutralny (przekątna, albo wróg bez żywiołu, albo gracz bez żywiołu) | ×1.0 | `NEUTRAL_MULTIPLIER` |
| **gola katana (`none`) przeciw dowolnemu wrogowi** | **×1.0 zawsze** (baseline) | – |

Funkcja: `ElementBalance.matchup(attacker, defender) -> float`. Jedna tabela, bez magicznych liczb w `yokai.gd`/`held_weapon.gd`.

## 3. Decyzje

1. **Kolejność w pipeline obrażeń wroga** (zapisana w `EnemyProfile.damage_multiplier`):
   `baza × zone (głowa 1.5 / tułów 1.0 / kończyna 0.7) × matchup (ElementBalance) × resistances[żywioł ataku] → parry-armor elity → kirisute/sever → snappedf(0.1)`.
   Mnożenie jest przemienne, więc kolejność nie zmienia wyniku przed zaokrągleniem; ważna jest kolejność **przed** parry-armor i zaokrągleniem.
2. **Elity:** element-owe wpisy w `resistances` są usunięte, bo ring przejmuje tę rolę (dwa źródła dałyby ×2.58 i ×0.17 – za ostro).
   Zostaje `physical` ×0.42 i parry-armor (bez zmian). `resistances` jako etap zostaje w pipeline dla przyszłych wrogów (AI phase, GDD §8).
   Konsekwencja: elita z tym samym żywiołem dostaje ×0.5 zamiast ×0.34, a słabość ×1.5 zamiast ×1.72. Mniej surowe, ale z jedną tabelą.
3. **Wróg też zadaje więcej graczowi z kontrującym żywiołem? NIE.** Obrażenia wroga w stronę gracza są bez zmian. Powód: gracz już wybiera
   żywioł bramą torii i ma tu przewagę; kara za trafienie w „złym” momencie zamieniłaby każdy las w podatek. Kontra działa tylko w stronę wroga.
4. **Wagi losowania rój:** per fala, czyli liczone z czasu biegu w chwili spawnu (`WaveProfile.element_weights_for(t)`):
   - udział gola stal (`none`) rośnie/spada liniowo od `plain_share_start` (na początku, 0.70) do `plain_share_full` (na pełnym napięciu, 0.35);
   - reszta dzielona wagami `weight_sakura / weight_storm / weight_ink / weight_shadow` (domyślnie po 1.0);
   - wagi są w `WaveProfile` (`@export`), w panelu „Fale” (dock) jako grupa „Żywioły”.
5. **Elity:** żywioł losowany równomiernie (bez zmian). Nie zależą od wag rój.
6. **Oni:** bez żywiołu (`none`) w D17. Oni jest bossem z kilkoma atakami; dodanie żywiołu wymagałoby też wizualu na masce.
   Hak już jest (`EnemyProfile.element`), więc to zmiana jednej linii. Odłożone, nie zapomniane.
7. **Czytelność w VR (z ~8 m, bez kół, bez `no_depth_test`):**
   - rój z żywiołem: kolor **oczu i EyeGlow** oraz **sigila na masce** w kolorze żywiołu (ten sam język co elita, z mniejszym `ELITE_LIFT`); skóra bez zmian, żeby rój nie zlał się z elitami;
   - elita: bez zmian (oczy, sigil, pasek, pazury, lekki tint skóry).
   - Cząstki żywiołu na wrogu: pomijamy w D17 (budżet 345 draw calls). Oczy i sigil to ~0 nowych wywołań.
8. **Trafienie (feedback), bez liczb na ekranie:**
   - **kontra (×1.5):** dłuższy hit-stop (+0.02 s, do limitu 0.08 s), dodatkowy impuls haptyczny, rozbłysk iskier w kolorze żywiołu gracza (`SparkBurst`);
   - **ten sam żywioł (×0.5):** przytłumiony dźwięk „odbicia” (`blade_ring` / `impact_light` ciszej o 6 dB), mniej iskier w barwie żywiołu, krótszy impuls;
   - **neutralny / bez żywiołu:** bez zmian.
   Liczby obrażeń nie pojawiają się na ekranie (jest `DamageNumber` tylko do debugu).
9. **Balans:** `tools/balance_model.gd` dostaje funkcję średniego mnożnika dla dobranej szkoły wobec miksu wrogów z wagami fali.
   Cel: run 8 min wygrywalny bez żywiołu (gola stal ≥ 0.6 wysiłku), a z dobrym doborem wyraźnie lepszy.
10. **Testy (krytyczne, szybkie):** patrz sekcja 5.

## 4. Pliki (plan)

- `src/run/element_balance.gd`: krąg, `matchup()`, mnożniki.
- `src/enemies/enemy_profile.gd`: `element`, `damage_multiplier(zone, attacker)` z matchup.
- `src/enemies/enemy_catalog.gd`: usunięcie `ELITE_COUNTER_ELEMENT` (zastępuje ring), elita bez wpisów per żywioł, `make_swarm_profile(hp, element)`.
- `src/enemies/yokai.gd`: `element` (zamiast `elite_element`), wizual rój z żywiołem, `hit["matchup"]`.
- `src/weapons/held_weapon.gd`: feedback kontra / ten sam żywioł.
- `src/run/wave_profile.gd` + `data/waves/*.tres` + `addons/hanabi_spawn/wave_dock.gd`: wagi żywiołów.
- `src/run/wave_director.gd`: losowanie żywiołu roju per spawn.
- `tools/balance_model.gd`, `tools/balance_sim.gd`: średni mnożnik i sprawdzenie 8 min.
- Testy: `tests/elements_test.gd` (ring, mnożniki, neutral, katana=1.0, spójność kręgu), `tests/enemy_variants_test.gd` (spawner 4 żywiołów, elita + mnożnik),
  `tests/d17_element_screenshots.gd` (okno, nie headless: piksele, zrzuty do `docs/d17/`).

## 5. Plan testów

Headless (w istniejących suitach, bez nowych długich czekań):
- kontra = ×1.5, ten sam = ×0.5, neutral = ×1.0, gola katana (`none`) = ×1.0 dla każdego żywiołu wroga;
- krąg spójny: każdy żywioł kontruje dokładnie jeden i jest kontrowany przez dokładnie jeden;
- spawner: w krokowanej fali pojawiają się wrogowie wszystkich 4 żywiołów wg wag (z tolerancją), a udział gołej stali zgadza się z `plain_share_*`;
- elita z żywiołem: `damage_multiplier` = zone × matchup × resistances (w tej kolejności, testowane na profilu z wpisem `resistances`).

Windowed (pikselowe, `SKIP` w headless):
- 4 żywioły w scenie `run.tscn` z ~8 m: średni kolor 5×5 px wokół rzutu oczu na ekran, odległość kolorów między parami ≥ próg;
- zrzuty: `docs/d17/`.

## 6. Ryzyka

- Zmiana elit (brak element-owych `resistances`) zmienia odczuwalny balans elit. Trzeba zmierzyć w `balance_sim`.
- Kontra ×1.5 może rozbić „gola stal jest wygrywalna”. Będzie sprawdzone w symulacji i wagach fali.
- Czytelność koloru w mgle: oczy elity są już jasne (`ELITE_LIFT`); rój z mniejszym liftem może zniknąć w mgle. Patrz zrzuty.

## 7. Realizacja i ocena (D17, 2026-10-30)

### 7.1 Co zrobiono
- **Krąg i mnożniki:** `ElementBalance.BEATS`, `matchup()`, `beats()`, `countered_by()`, `COUNTER_MULTIPLIER` 1.5, `SAME_MULTIPLIER` 0.5, `NEUTRAL_MULTIPLIER` 1.0.
- **Pipeline wroga:** `EnemyProfile.element` i `damage_multiplier()` = zone × ring × resistance; parry-armour i kirisute dalej bez zmian. Ability (`receive_element_damage`) też przechodzi przez ring.
- **Rój z żywiołem:** `WaveProfile.plain_share()`, `school_weights()`, `roll_swarm_element()`; grupa „Elements” w panelu „Fale” (6 wierszy). `WaveDirector` losuje przy każdym spawnie roju. Elity bez zmian (równomiernie).
- **Wygląd:** żywioł roju w oczach, EyeGlow i sigilu (`Elements.eye_color`, `SCHOOL_EYE_GLOW` 1.4). Skóra i szarfa bez zmian, żeby rój nie wyglądał jak elita z daleka. Naprawiono nadpisywanie wyglądu w `_ready`.
- **Feedback:** kontra: hit-stop +0.02 s, drugi impuls haptyczny, rozbłysk ciała w akcencie żywiołu, iskry w barwie oczu. Ten sam żywioł: stłumiony „clink” i mało iskier, krótszy impuls.
- **Balans:** `BalanceModel.draft_matchup()` (plain / blind / read), `READY_COUNTER_SHARE` 0.5 (założenie), `balance_sim` ma blok COUNTER RING.
- **Testy:** `elements_test` (krąg, mnożniki, neutral, katana ×1.0, kolejność mnożników, draft), `enemy_variants_test` (udział żywiołów w roju, spawner 4 żywiołów). Pikselowy test wizualny `d17_element_visual_test` (okno).

### 7.2 Wyniki (zmierzone)
- **Hit (prawdziwa ścieżka `HeldWeapon._handle_hit`, wróg Storm, 900 HP):** gola stal 16.9, kontra (Ink) 25.3 = ×1.50, ten sam żywioł (Storm) 8.4 = ×0.50.
- **Kolor w kadrze, 8 m (`docs/d17/1_four_schools_8m.png`):** najbliższa para 0.22 RGB (próg 0.12). Sakura różowa, Storm cyjanowa, Ink bladoniebieska, Shadow fioletowa.
- **Balans, 8 min, „average”:** gola stal 39 zabójstw, LV 7, 6 pkt (bez zmian względem przed D17). Blind ×1.000, read ×1.111: 40 zabójstw, ten sam poziom. Czyli ring zmienia tempo walki (≈ −10 % czasu na zabicie), ale w szeregowym modelu ekonomii daje ~1 zabójstwo w 8 min.

### 7.3 Decyzje podjęte bez pytania (do przeglądu)
1. Krąg jest jednokierunkowy i 4-cykliczny (nie pary wzajemne); przekątne są neutralne. Stare pary elitarne zmieniły się: Ink-elita słaba na Shadow (było Storm), Sakura-elita słaba na Storm (było Shadow).
2. Elity nie mają już element-owych `resistances` (ring je zastępuje). Zostaje `physical` ×0.42 (bez zmian). Efekt: elita tego samego żywiołu bierze ×0.5 zamiast ×0.34, a na słabość ×1.5 zamiast ×1.72.
3. Wróg nie zadaje więcej graczowi z kontrującym żywiołem (punkt 3 planu).
4. Rój: udział gołej stali liniowo 70 % → 35 % w rampie; reszta wagami z panelu.
5. Oni bez żywiołu w D17 (hak `EnemyProfile.element` gotowy).
6. Ink w oczach jest bladoniebieski-biały (`Elements.eye_color`), a nie czarny z palety GDD. Powód: czarny/indygo ginie w mgle i zlewa się z cyjanem Storm. Akcent UI i kolory `Elements.color` bez zmian.
7. Kolor trafienia kontry = akcent żywiołu (nie jasne oczy), bo jasny ink dawał białe ciało.

### 7.4 Ocena surowa (co jest słabe)
- **Czytelność z 8 m:** światło w oczach to 5–8 px. Kolor czyta się jako kropka, a sigil na masce w mgle nie jest czytelny. Bez zoomu gracz rozpoznaje szkołę tylko dzięki kolorowi oczu. Mocniejsza rozdzielczość wymagałaby większej emisji albo lekkiego tintu skóry (koszt: podobieństwo do elity).
- **Mylące halo:** pomarańczowa i niebieska poświata latarni (torii) stoi tuż za wrogami i w kadrze 1 wygląda jak żywioł samego wroga. To problem sceny, nie D17, ale psuje czytelność.
- **Ciężki rozbłysk kontry z bliska:** cała postać na 0.12 s w bladym kolorze (amplituda 0.55). Trzeba zmierzyć w grze, czy nie męczy.
- **Ink nie wygląda jak ink** (patrz decyzja 6): palety GDD §5 i kolor czarnego tuszu nie są oddane na wrogach.
- **Balans nieprzetestowany w walce:** ring zmienia tempo walki o ~10 %, ale model jest szeregowy i zakłada 50 % „gotowości” kontry. Dopiero gra pokaże, czy gracz w ogóle czyta żywioł roju.
- **Ability bez osobnego feedbacku:** trafienie zdolnością kontrującą dostaje rozbłysk ciała, ale nie ma hit-stopu ani haptyki. Świadomie pominięte.
- **Dźwięk nie był odsłuchany:** `blade_ring` / `impact_light` ciszej o 6–8 dB to wartości z oka, nie z miksu.
