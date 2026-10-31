# D14: Nowy HUD na nadgarstku (Wrist HUD)

Dokumentacja realizacji zadania D14 zgodnie z wytycznymi GDD i ustaleniami Jakuba.

## 1. Założenia i wygląd
- **Przezroczyste tło:** Całkowity brak jakiegokolwiek panelu, ramki czy pergaminu pod odczytem. Wszystkie elementy renderowane są w przezroczystości (`ALPHA = 0.0` poza grafiką).
- **Pierścień HP:** Gładki łuk wygenerowany w shaderze `src/shaders/wrist_ring.gdshader` z antyaliasingiem (`smoothstep`) i zaokrąglonymi końcami (`arc`).
  - Długość łuku odpowiada aktualnemu procentowi HP (`hp / max_hp`).
  - Kolorystyka płynna: pełne zdrowie = spokojny teal/szmaragd (`Color(0.36, 0.84, 0.72)`), ~50% = bursztyn (`Color(0.98, 0.64, 0.24)`), <25% = ostrzegawczy czerwony (`Color(0.95, 0.2, 0.16)`) z miękkim pulsem ostrzegawczym.
- **Wnętrze pierścienia:**
  - Animowany, proceduralny płomień w odcieniach czerwieni, pomarańczu i żółci (oparty na szumie fbm, tani w wykonaniu, unshaded, bez dynamicznego światła).
  - Wyraźna, biała liczba spalonych kalorii (`kcal`) umieszczona centralnie nad płomieniem (kontrast WCAG > 4.5:1, rzeczywisty 5.5:1).
- **Element zewnętrzny i statystyki:**
  - Subtelny, zewnętrzny cienki łuk wokół pierścienia odliczający czas trwania aktywnego żywiołu (oraz kanji i sekundy tuż pod pierścieniem).
  - Wskaźniki gotowości umiejętności A i B w kolorze żywiołu.
  - Grawerowany odczyt pod spodem: ranga, zabójstwa, punkty (`pt`), linia postępu (`XP / 点 / 波`) oraz aktywne buffy z kapliczki (D12).

## 2. Pokazywanie i gest "spojrzenie na zegarek"
- HUD jest renderowany **wyłącznie** po wykonaniu gestu spojrzenia na nadgarstek:
  - Odległość od oczu (kamery): `< 0.35 m` (histereza wygaszania przy `> 0.42 m`).
  - Kąt wewnętrznej/wierzchniej strony nadgarstka do wektora wzroku: `< 45°` (histereza wygaszania przy `> 55°`).
  - Przedramię leży poziomo: uniesienie przedramienia nad poziom `< 35°` (histereza wygaszania przy `> 50°`). Ręka trzymana pionowo, z grzbietem do oczu, nie pokazuje odczytu (P9).
  - Obecność w polu widzenia kamery (`cam.is_position_in_frustum`).
  - Płynny fade in/out trwający `0.15 s`.
- Gdy ręka jest opuszczona lub odwrócona, całe poddrzewo jest wyłączane (`wrist_face.visible = false`), co daje **0 dodatkowych draw calls**.
- Na desktopie gest jest symulowany przytrzymaniem klawisza **H** (`player.wrist_check`).

## 3. Brak clippingu z dłonią i kataną
- Punkt mocowania `RING_OFFSET = Vector3(0.0, 0.064, 0.098)` unosi taflę HUD nad wierzch nadgarstka.
- Test `tests/wrist_hud_test.gd` bada kolizję i footprint odczytu z wierzchołkami siatki dłoni XR (`mesh_Hand_Nails_low_L`) oraz kataną w różnych orientacjach ostrza (forward, up, down, yawed, rolled). Liczba przecięć wierzchołków wynosi 0.
- HUD zachowuje poprawne testowanie głębokości względem obiektów świata.

## 4. Licznik kalorii (CalorieMeter)
- Sprawdzony model fizjologiczny MET (Metabolic Equivalent of Task) dla aktywności VR:
  - Spoczynek/stanie: MET = 1.3
  - Praca ramion: do +2.6 MET przy prędkości dłoni 1.5 m/s
  - Poruszanie się: do +1.4 MET przy prędkości ciała 1.2 m/s
  - Maksymalny poziom wysiłku: MET = 5.3
- Formuła: `kcal = MET × waga (kg) × czas (godziny)`.
- Waga gracza konfigurowalna w menu Ustawień (D3): domyślnie 70 kg, zakres 40–150 kg z krokiem 5 kg.
- Zliczanie zatrzymuje się automatycznie podczas pauzy oraz poza stanem aktywnej gry (`RunState.PLAYING`).

## 5. Zrzuty ekranu i ocena surowa
Zrzuty z gry commitowane do `docs/d14/`:
- `wrist_hp100_gesture.png` – gest z bliska przy 100% HP (szmaragdowy pierścień, ogień, kalorie, zewnętrzny łuk żywiołu burzy).
- `wrist_hp50_gesture.png` – gest z bliska przy 50% HP (bursztynowy pierścień).
- `wrist_hp15_gesture.png` – gest z bliska przy 15% HP (czerwony pulsujący pierścień).
- `wrist_lowered_hidden.png` – ręka opuszczona (HUD niewidoczny, zero draw calls).

### Ocena surowa:
- **Dobre:** Przezroczyste tło całkowicie usuwa wrażenie sztucznego panelu 2D. Pierścień jest gładki, bez widocznych schodków czy artefaktów. Cyfry kalorii (biel) odznaczają się czytelnie na tle stylizowanego płomienia (kontrast 5.5:1). Histereza zapobiega migotaniu przy granicy zasięgu.
- **Słabe:** W kadrze desktopowym (pozycja testowa dłoni) HUD pojawia się w dolnej lewej ćwiartce ekranu pod kątem do kamery – w prawdziwych goglach VR wymaga to weryfikacji naturalnego ułożenia dłoni (kąt nachylenia kontrolera Quest). Płomień proceduralny ma minimalistyczny charakter i przy bardzo dynamicznych ruchach głowy może być mniej zauważalny niż tradycyjne cząsteczki.
- **Dalsze kroki:** Testy manualne na Quest 3 z kontrolerami Touch Plus oraz zbadanie haptycznego potwierdzenia otwarcia odczytu.

## 6. Uzupełnienia GDD §15 i czytelności kapliczki (D14.1 / Polish)
- **Kalorie na steli pamięci (Memorial Stele, GDD §15):** Po zakończeniu runu na płycie `MemorialStele` w podsumowaniu statystyk wyświetla się liczba spalonych kilokalorii (np. `00:07 · 斬 7 · LV 2 · 波 1 · 45 kcal`). Wartość jest przekazywana w słowniku `summary` sygnału `run_ended`.
- **Haptyka uniesienia nadgarstka:** Gdy gracz w VR unosi nadgarstek do twarzy i odczyt przechodzi ze stanu ukrytego do widocznego (`_raised` staje się `true`), kontroler pomocniczy generuje krótki, subtelny impuls haptyczny (40 ms, amplituda 0.22 z uwzględnieniem ustawień komfortu gracza), dając fizyczne potwierdzenie gestu.
- **Czytelny ołtarz kapliczki Hokora (D12 feedback):** Dodano nakrycie ołtarza (`AltarCloth`) w kolorze ciepłego cynobru z delikatną emisją (0.45 przy zapalonej kapliczce, wygaszane po złożeniu ofiary). Ołtarz jest teraz wyraźnie widoczny z kilku metrów we mgle, wskazując graczowi dokładne miejsce przyłożenia dłoni.
