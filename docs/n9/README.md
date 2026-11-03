# N9 – menu premium: z płaskiej karty w obiekt w świecie

Zrzuty z gry (`run.tscn`, desktop, ta sama kamera PRZED/PO), robione przez `tests/n9_menu_visual_test.tscn -- --shots docs/n9` (PRZED: ten sam skrypt bez sprawdzeń, uruchomiony na commicie 6289f84 w osobnym worktree, `--before`).

| Ujęcie | PRZED | PO |
|---|---|---|
| Drzewko (Sakura) | `n9_before_01_tree.png` | `n9_after_01_tree.png` |
| Settings › Movement | `n9_before_02_settings_movement.png` | `n9_after_02_settings_movement.png` |
| Mapa sterowania | `n9_before_03_controls_map.png` | `n9_after_03_controls_map.png` |
| 30° z boku, 2.2 m (grubość) | `n9_before_04_angle30.png` | `n9_after_04_angle30.png` |
| Credits (nowe) | – | `n9_after_05_credits.png`, `n9_after_06_credits_scrolled.png` |
| Animacja w połowie (≈0.1 s) | – | `n9_after_07_opening_lift.png` |

## Co zrobione

- **Tablica laki zamiast karty** (`src/ui/skill_tree_menu.gd`): papier 1.44 × 0.9 m wygięty na walcu R = 3 m (krawędzie ~9 cm bliżej gracza), rama 3.6 cm z fazą łapiącą światło, złoty wałeczek wokół papieru, złote okucia w narożnikach, płyta tylna – łącznie 5.2 cm grubości. Rama, okucia i tył to **jeden mesh / jedno wywołanie rysowania**, unshaded, z „latarnią” wypieczoną w kolorach wierzchołków (nie zależy od świateł sceny ani mgły, tanio na Queście). W trybie „drawn on top” rama też ignoruje głębię.
- **Papier** (`skill_tree_canvas.gd`): ciepła kuro-urushi (nie czerń) z fakturą washi (dwie warstwy szumu FastNoiseLite, generowane raz), ciepłe DIM/FAINT, zewnętrzna złota ramka narysowana zniknęła (robi to fizyczna rama).
- **Ruch**: otwarcie = tablica podnosi się o 5 cm i rozkłada z 6 % wysokości w 0.25 s (ease-out cubic), zamknięcie = odwrotnie w 0.16 s; liczone w czasie rzeczywistym (`delta / Engine.time_scale`), nigdy przez time_scale. Dźwięki proceduralne CC0 (`tools/gen_n9_menu_audio.py`): szelest papieru + stuk drewna przy otwarciu, niższy stuk przy zamknięciu, suchy „tick” przy każdym wyborze; impuls haptyczny na lewej ręce przy otwarciu, haptyka przy wyborze jak dotąd.
- **Czytelność**: patrz niżej. Minimalny rozmiar tekstu podniesiony z 16 do 18 px.
- **Credits** (wymóg Jakuba): Settings › 謝 CREDITS (7. zakładka; także dopisek „VR · CREDITS” na zakładce Settings, klawisz K). 39 pozycji z `data/credits.json`: nazwa, autor, źródło (URL), licencja, do czego użyte; CC BY wyróżnione kolorem. Przewijanie: złote strzałki (ray + trigger, 5 wierszy), gałka kontrolera, który celuje w tablicę (7 wierszy/s, lekki impuls na wiersz), kółko myszy. Ta sama lista jest generowana do `CREDITS.md` (`python3 tools/gen_credits.py`). Brak autora: „thunderclap” (OpenGameArt) → `docs/CREDITS_TODO.md`. `data/credits.json` dodany do `include_filter` eksportu Questa.

## Decyzje

- **Większy panel zamiast większych fontów.** Układ canvasu (1600 × 1000 px) się nie zmienia; panel urósł z 1.2 do 1.44 m, czyli 0.9 mm/px. Z odległości 1.1 m to to samo co stara karta oglądana z 0.92 m (zadanie: „z 0.8–1 m”). Kąt jest niezależny od odległości, bo UiPlacement skaluje panel proporcjonalnie do dystansu.
- **Pomiar kątowy per napis.** Test liczy każdy napis każdej z 11 stron w miejscu, gdzie leży na wygiętej tablicy, od prawdziwej głowy (XR sim): treść 22 px = 1.02° ze środka, najgorszy napis treści 0.91° na krawędzi, najmniejszy drobny druk (18 px) 0.74° w najgorszym miejscu. Progi testu: ≥ 1° ze środka, ≥ 0.85° wszędzie dla treści, ≥ 0.7° wszędzie dla drobnego.
- **Wyjątek – ciasne miejsca.** Gdy żadne miejsce nie mieści pełnej tablicy (np. yōkai 0.7 m przed graczem), UiPlacement próbuje jeszcze raz w skali 0.72 (`COMPACT_FIT`, 1.09 m – trochę mniej niż stara karta), zanim przejdzie do rysowania na wierzchu. Wtedy tekst ma ~0.74° / 0.6°. Wolałem mniejszą tablicę niż tablicę przecinającą wroga albo obróconą o > 50°.
- **Zamknięcie z animacją**: `is_open` gaśnie od razu (świat rusza, wskaźniki znikają), węzeł chowa się po 0.16 s. Test „tapping Left Menu again closes it” sprawdza teraz natychmiastowe zamknięcie i ukrycie po czasie animacji (nie osłabiony – sprawdza to samo plus kolejność).

## Testy

- `vr_menu_pause_test`: animacja ≤ 0.3 s czasu rzeczywistego przy wymuszonym `time_scale` 0.25, świat przez cały czas w pauzie, menu nie dotyka time_scale; ease-out; zamknięcie w 0.16 s; dźwięki załadowane; rozmiar kątowy każdego napisu; Credits: zakładka triggerem, strzałki, koniec listy, gałka ręki celującej, zamknięcie; dane: każde CC BY ma autora, każdy wiersz CC BY z LICENSES.md jest w Credits, CREDITS.md zawiera każdą pozycję, nieznani autorzy są w CREDITS_TODO.
- `ui_clipping_test`: próbki z prawdziwej geometrii (przód ramy i płyta tylna na łuku, 70 próbek) przy pniach, ścianach, torii, yōkai, na wzgórzach; rama też „on top” w trybie blocked; mesh ramy mieści się w strefie, którą UiPlacement sprawdza.
- `quest_perf_test`: wywołania rysowania menu liczone po powierzchniach (≤ 6: papier + rama + 2×2 wskaźniki), rama = 1 powierzchnia, budżet 345 przy otwartym menu, `data/credits.json` w eksporcie.
- `n9_menu_visual_test` (okienkowy, headless = SKIP): na `run.tscn` – cztery szyny ramy renderują się jako laka (czerwono-czarne), 4 okucia jako złoto, kontrast tytułu i treści ≥ 4.5:1, papier nie czarny, tablica w centrum i ≥ 50 % szerokości, pod kątem 30° ściana zewnętrzna ≥ 4 px i ma kolor laki.

## Co słabe (surowo)

- Grubość pod 30° to tylko ~4 px na desktopie 960 px – widać ją, ale nie „krzyczy”; w goglach (bliżej, stereo) czyta się lepiej, ale nie zmierzyłem tego w headsecie.
- Okucia to płaskie płytki; brak gwoździ/grawerunku, z bliska wyglądają prosto. Rama nie ma faktury drewna pod laką (świadomie gładka laka, ale bez mikro-połysku zależnego od ruchu głowy – światło jest wypieczone, nie reaguje na patrzenie).
- Na desktopowym FOV 75° wygięcie wygląda mocniej niż w VR.
- Credits: długie wiersze (np. „Old Torii”) zmniejszają się do 18 px – czytelne, ale gęste.
- Dźwięki są proceduralne; brzmią poprawnie w spektrum, ale nie słuchałem ich w goglach.
