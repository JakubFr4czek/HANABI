# Nagrywanie dema (N10)

Obraz z gogli trzęsie się z głową i jest kwadratowy. Do wideo służy **kamera widza**:
druga kamera w osobnym viewporcie 16:9 (1280×720, bez MSAA/TAA), pokazywana w oknie
na pulpicie. Headset dalej renderuje normalnie. Domyślnie jest **wyłączona**.

## Klawisze (okno gry na PC)

| Klawisz | Działanie |
|---|---|
| **F7** | wyłączona → **1. osoba wygładzona** → **3. osoba za ramieniem** → wyłączona |
| **F9** | **czysty kadr**: chowa HUD debug/perf (np. F3 FPS); wrist HUD i dymek Oni zostają |
| F3 | licznik FPS/draw calls (do sprawdzenia płynności, przed nagraniem schowaj F9) |

Start od razu w danym trybie: `-- --spectator=fp` albo `-- --spectator=tp`, plus `--clean-frame`.

- **1. osoba wygładzona**: pozycja filtrowana (5/s, skok głowy 10 cm = ~7 mm w pierwszej klatce),
  yaw/pitch 3,5/s, pitch ograniczony do ±35°, **roll zawsze 0** (poziomy horyzont), FOV 80°.
- **3. osoba za ramieniem**: 2,3 m za głową, 0,45 m wyżej, 0,55 m w prawo. Wysięgnik to
  sphere-cast (r 0,25 m) po terenie i pniach (warstwy 1 i 64): przy przeszkodzie skraca się
  natychmiast, potem wraca płynnie – kamera nie wchodzi w drzewa.

## Wydajność / Quest

Kamera widza powstaje tylko na PC (`SpectatorCamera.platform_ok()`: brak tagów `android`/`mobile`/`web`),
więc na Queście nie ma drugiego renderu. Na PC, gdy tryb jest wyłączony, viewport ma
`UPDATE_DISABLED` (zero kosztu). Na PCVR viewport widza jest podpinany do okna
(`viewport_attach_to_screen`) zamiast lustra lewego oka; na desktopie pokazuje go pełnoekranowy
TextureRect pod nakładkami debug.

## Jak nagrać (OBS)

1. Uruchom grę na PCVR (Quest Link / Air Link + SteamVR/OpenXR) albo w trybie desktop.
2. OBS: źródło **Przechwytywanie okna** → okno HANABI, kanwa 1920×1080, 60 fps.
   Audio: przechwytywanie dźwięku aplikacji (lub pulpit).
3. W oknie gry: **F7** (1. osoba) i **F9** (czysty kadr). Na ujęcia walki z boku **F7** jeszcze raz (3. osoba).

## Przebieg ok. 3 min

1. **0:00 Splash** HANABI/NANJO (1. osoba, nie ruszaj głową gwałtownie).
2. **0:15 Opening strike** – cios otwierający.
3. **0:30 Intro** – brama, chwyt katany.
4. **0:50 Walka** – fale yōkai; przełącz na 3. osobę (F7) na 20–30 s, potem z powrotem.
5. **1:30 Torii** i ścieżka przez las.
6. **1:50 Kapliczka** – ofuda, wybór buffa.
7. **2:10 Oni** z dymkiem AI (3. osoba dobrze pokazuje dymek nad głową).
8. **2:40 Śmierć / ema** – stela, przecięcie emy (1. osoba).

Zrzuty obu trybów: `docs/n10/` (test `tests/n10_spectator_visual_test.tscn`).
