# Pokrycie: czego nie da się (albo nie warto) pokryć

Stan po D16 (Nano Coverage lokalnie, `ci/README.md`): linie 92.x%, `xr_player.gd` 82%.
Ten dokument opisuje to, co zostaje poza pokryciem, i dlaczego. Cel 95% całości nie jest
osiągany głównie przez `runtime_guard.gd`, a jego luki wynikają z konstrukcji strażnika.

## `src/debug/runtime_guard.gd` (ok. 76%)

Strażnik ma pilnować niezmienników w działającej grze i krzyczeć, gdy coś się psuje.
Większość jego gałęzi odpala się tylko wtedy, gdy gra jest zepsuta. Testy, które by je
wymusiły, testowałyby sztucznie zepsutą grę, a nie strażnika.

| Linie (stan sprzed pokrycia) | Co to jest | Dlaczego nieosiągalne w headless |
|---|---|---|
| 63–65 | `_ready`: gałąź `enabled == false` (release export bez `--guard`) | Testy działają na buildzie debug, więc strażnik zawsze jest włączony. Gałąź istnieje tylko dla eksportu. |
| 76–81 | `_exit_tree`: drenaż komunikatów i zdjęcie loggera | Wywołuje się przy wyjściu z procesu, już po tym, jak raport pokrycia zapisał dane. |
| 84–94, 166–174 | Logger Godota przekazuje błędy silnika z dowolnego wątku | Zależy od tego, jakie ostrzeżenia silnik wypisze w danym przebiegu. Nie da się tego wywołać deterministycznie bez zmiany silnika. Wyjątek: `queue_engine_message` z listą ignorowanych komunikatów jest pokryty w `runtime_guard_test`. |
| 137–138 | `_held`: ścieżka dla kluczy, których warunek nie trzyma się wystarczająco długo | Zależy od czasu rzeczywistego (sekundy trzymania warunku), a testy krokują fizykę, nie zegar. |
| 159 | `frame_hitch`: klatka dłuższa niż próg | Od czasu maszyny i obciążenia; test czasowy byłby niestabilny (a na zainstrumentowanej kopii zawsze by failował). |
| 185 | `orphan_leak`: rosnąca liczba osieroconych węzłów | Wymaga kilkudziesięciu sekund próbkowania, czyli prawdziwego czasu. |
| 206, 208 | `time_scale_stuck`, `hit_stop_stuck` | Wymusiłoby to zepsuty stan czasu gry. Strażnik ma to wyłapać, a nie testy go ustawiać. |
| 219–260 | Niezmienniki ragdolli: duch, NaN, prędkość części, zerwany staw, pod ziemią | Gałęzie odpalają się tylko przy uszkodzonym ragdollu. Pokrycie wymagałoby celowego psucia fizyki. |
| 268–316 | Niezmienniki broni i przebiegu: broń poza dłonią, pod ziemią, dyrektor fal nie wystartował, gracz martwy a przebieg trwa, gracz pod ziemią, wróg poza drzewem | Jak wyżej: odpalają się tylko przy złym stanie gry. |

Wszystkie gałęzie z raportem (`report(...)`) są poprawne w sensie kodu, ale nie są
wyzwalane przez działającą grę. Przy ich pokrywaniu łatwo napisać test, który przechodzi,
bo sam ustawił zepsuty stan, i nic nie mówi o grze. Dlatego zostają poza zakresem.

Co pokryto: liczniki naruszeń per kod, zachowanie pierwszego komunikatu, reset,
podsumowanie (czyste i z naruszeniami, także do pliku logu), filtr komunikatów silnika
i limit 200 oczekujących komunikatów.

## `src/player/xr_player.gd` (martwe gałęzie, 82% po D16)

Pozostałe nieosiągnięte linie to:

- Gałęzie `else` dla `VrComfortSettings == null` (ścieżka zapisu/odczytu do `ConfigFile`
  i `VIEW_SETTINGS_PATH`). Autoload `VrComfortSettings` zawsze istnieje, więc to martwy kod.
  Usunięcie go to zmiana logiki gry, a tego nie robimy w ramach pokrycia.
- Zapis ustawień po puszczeniu B po zmianie wysokości lub po recenter (`_save_view_settings`).
  Taki zapis trafia do realnej konfiguracji użytkownika. Test trzyma B do końca przebiegu
  i nigdy go nie puszcza, żeby nie dotknąć pliku.
- `teleport_feet` bez metody `teleport` i `feet_position` bez `PlayerBody`: nie występują
  w scenie gracza.

## Jak zmierzyć

Patrz `ci/README.md`, sekcja „Pokrycie lokalnie”. Instrumentowane przebiegi są kilka razy wolniejsze
i testy czasowe mogą na nich failować; wynik pokrycia liczy się z przebiegu, w którym zestaw przeszedł.
