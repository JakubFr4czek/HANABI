# N12 – yōkai czytelniejsze, mniej klockowate (tylko wrogowie)

Zmiany (świat, las, sakura, światło sceny bez zmian):
- **Sylwetka** (`YokaiForms`): tors z zaokrąglonym trapezem/barkami (3 pierścienie zamiast płaskiej pokrywy) i kopułą brzucha; ręce i nogi zamknięte kopułami zamiast płaskich denek; `ORGANIC_LUMP` (±3 % promienia, stały hash) łamie „toczony" wygląd; `SHOULDER_HUNCH` – prawy bark lekko wyżej i szerzej (asymetria). Te same instancje meshy → **draw calls bez zmian**; trójkąty ciała ~670 → ~880 (≈ +8 % na całego wroga z maską 2.2k). Kolizje, hitboxy, cięcie (MeshSlicer, dismember_test PASS) i spawn bez zmian.
- **Materiał skóry**: chłodniejszy łupkowy kolor zamiast plastikowego niebieskiego, `procedural_ao` 0.7 (gradient góra–dół na każdej bryle), grain 0.5.
- **Rim** (`wet_surface.gdshader`, nowy uniform `rim_tint`, domyślnie czarny → świat nietknięty): księżycowo-srebrny fresnel tylko na skórze wrogów, wygaszony na powierzchniach skierowanych w górę (żeby nie rozjaśniać kołnierza za maską); szkoła lekko barwi rim (`SCHOOL_RIM_MIX`), elita mocniej akcentem; gaśnie razem z oczami przy śmierci.
- Test: `n3_yokai_visual_test` – nowa sekcja N12 (4 m: kontrast sylwetki ≥ 0.05 i rim podnosi luminancję o ≥ 0.006 względem tej samej klatki bez rimu; PRE bez rimu: 0.0013, PO: 0.0117). Test wyłącza też podpowiedź sterowania na starcie runu, która od czasu N3 zasłaniała głowę wroga.

Zrzuty (run.tscn, ta sama kamera): `PRE_/POST_swarm_4m.png`, `PRE_/POST_swarm_3m.png`.

Słabe / otwarte: sylwetka nadal prosta (to wciąż tuby, bez fałd szaty); rim subtelny – z 4 m widać go głównie na krawędziach ramion. Sprawdzenie „rogi na tle nieba" jest zależne od błyskawicy (w bazowym przebiegu 0.096, w ostatnim po zmianach 0.041 < 0.05, rogi i maska nie były zmieniane) – wymaga deterministycznej pogody w teście.
