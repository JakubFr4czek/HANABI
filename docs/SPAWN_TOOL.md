# Fale – narzędzie do strojenia wrogów (D10)

Cel: ustawiasz, ile yōkai pojawia się w czasie runu, bez kodu. Wszystkie liczby
fal żyją w jednym zasobie (`WaveProfile`, `data/waves/*.tres`). Gra czyta
wyłącznie z niego, a panel w edytorze edytuje ten sam zasób i pokazuje przebieg
symulowany tym samym kodem, który działa w grze (`WavePlanner`).

Zasady i uzasadnienie: `docs/SPAWN_PLAN.md`.

## Jak otworzyć

1. Włącz plugin `HANABI Spawn` (włączony w `project.godot`). Dock **Fale** jest
   obok docku **World Gen**, w tym samym miejscu (prawy panel, zakładki).
2. Nie potrzeba otwartej sceny. Dock czyta presety z `data/waves/`.

## Co jest na docku

- **Preset** (lista na górze): *Demo – łagodny*, *Domyślny*, *Hardcore*.
  Wybór wczytuje **kopię** do edycji. Plik na dysku zmienia się dopiero po
  *Zapisz preset*.
- **Symuluj run 8 min**: przelicza wykres i tabelę. Symulacja jest
  deterministyczna (ten sam seed, ten sam wynik).
- **Zapisz preset**: zapisuje edytowany profil do jego pliku w `data/waves/`.
- **Domyślne**: przywraca domyślne wartości wszystkich grup (dopiero po
  *Zapisz preset* trafiają na dysk).
- **Wykres**: szara linia to cap żywych (czerwona przerywana to cap Quest, 8),
  złota to średnia liczba żywych yōkai w każdej minucie. Pionowe linie:
  koniec ciszy i pierwsze Oni.
- **Tabela**: minuta → fala → żywi/cap → zespawnowano (w tym roi/elity) →
  średnia żywych.
- **Uwagi**: błędy na czerwono (gra się nie uruchomi), ostrzeżenia na żółto.

## Grupy parametrów

| Grupa | Co steruje | Przykład |
|---|---|---|
| **Pacing** | cisza na start, czas narastania, przerwy między falami | *Cisza na start* (domyślnie 75 s, demo 120 s) |
| **Budget** | ile kredytów wydaje fala (start, pełny napór), koszt elity | *Budżet fali na starcie* 1,0 kredyt = jeden yōkai |
| **Director** | cykl szczyt/relaks: co która fala jest szczytem, mnożniki budżetu i przerw | *Szczyt co N fal* (3): fala 3 szczyt, fala 4 relaks |
| **Caps** | ile yōkai może żyć naraz: start, co ile sekund cap rośnie, twardy sufit | *Cap twardy* 8 = zmierzona baza Quest |
| **Spawn ring** | pierścień wokół gracza i kąt poza kadrem | *Kąt poza kadrem* 60° |
| **Enemies** | od kiedy elity i jaka szansa na końcu rampy | *Elity od* (150 s) |
| **Scaling** | HP i jego wzrost (na falę i na sekundę), mnożnik elity, siła zwykłych yōkai (mnożnik HP i obrażeń) | *HP za sekundę* 0,004; zwykłe yōkai ×1,4 HP i ×1,25 obrażeń |
| **Oni** | pierwszy Oni, odstęp, mnożnik HP | *Oni pierwszy raz po* (180 s), potem co 100 s |

Oni pojawia się zawsze na początku fali **szczytu** (nie w środku relaksu),
po pierwszym czasie z *Oni pierwszy raz po* i nie więcej niż jeden naraz.

## Jak działa cykl fal (w skrócie)

- Fala ma budżet kredytów. Każdy yōkai kosztuje kredyty (zwykły 1, elita 4).
  Fala zamyka się, gdy wydała budżet i nikt nie żyje (albo po 18 s).
- Budżet rośnie od *startowego* do *pełnego* wraz z czasem (krzywą można
  zmienić w zasobie: `Budget curve`, w inspektorze).
- Co trzecia fala to **szczyt** (budżet ×1,5, krótsza przerwa), następna to
  **relaks** (budżet ×0,5, dłuższa przerwa). Pozostałe to narastanie.
- Cap żywych rośnie co *Co ile s cap rośnie* i nie przekracza *Cap twardy*.

## Walidacja

- **Błąd** (czerwony) – gra się nie uruchomi z tym profilem: cap startowy
  wyższy niż twardy, pierścień min ≥ max, mniej niż 2 w cyklu szczytu, elity
  po końcu rampy, pełny budżet niższy niż startowy.
- **Ostrzeżenie** (żółty) – cap twardy ponad 8 (zmierzona baza Quest:
  8 yōkai ≈ 338 wywołań rysowania z limitem 345), koszt zwykłego yōkai wyższy
  niż budżet pierwszej fali.

## Testy

`tests/run_loop_test.tscn` (pacing i pozycje spawnu w prawdziwej scenie),
`tests/wave_tool_test.tscn` (ten dock bez edytora), `tests/skill_tree_data_test.tscn`
(cele balansu drzewka, patrz niżej).

## Zmiany balansu, które przyszły z tą pracą

Nowa krzywa daje mniej zabójstw wcześnie, więc poziomy przychodzą wolniej.
Żeby cele drzewka (D12) zostały spełnione bez zmiany XP za wroga (24, 48, 64),
zmieniono progresję poziomów w `src/run/element_balance.gd`:

- `XP_FIRST_LEVEL` 150 → **60** (pierwszy poziom po ~3 zabójstwach, a nie 7),
- `XP_LEVEL_STEP` 45 → **40** (kolejne poziomy trochę szybciej).

GDD (sekcja Level-up) wymaga aktualizacji do tych liczb.

## Regeneracja presetów

Presety są generowane kodem (`tools/waves/make_presets.gd`), więc każda zmiana
jest widoczna w diffie. Po zmianie w `WaveProfile` (wartości domyślne) lub w
generatorze uruchom:

```
.tools/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/waves/make_presets.gd
```

Uwaga: `Domyślne` w panelu i `default.tres` to ten sam profil. Zmiana wartości
w panelu i *Zapisz preset* nadpisuje plik, więc po strojeniu zrób diff i
zatwierdź go świadomie.
