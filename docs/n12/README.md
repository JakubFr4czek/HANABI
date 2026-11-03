# N12 – yōkai czytelniejsze, mniej klockowate (tylko wrogowie)

Zmiany (świat, las, sakura, światło sceny bez zmian):
- **Sylwetka** (`YokaiForms`): tors z zaokrąglonym trapezem/barkami (3 pierścienie zamiast płaskiej pokrywy) i kopułą brzucha; ręce i nogi zamknięte kopułami zamiast płaskich denek; `ORGANIC_LUMP` (±3 % promienia, stały hash) łamie „toczony" wygląd; `SHOULDER_HUNCH` – prawy bark lekko wyżej i szerzej (asymetria). Te same instancje meshy → **draw calls bez zmian**; trójkąty ciała ~670 → ~880 (≈ +8 % na całego wroga z maską 2.2k). Kolizje, hitboxy, cięcie (MeshSlicer, dismember_test PASS) i spawn bez zmian.
- **Materiał skóry**: chłodniejszy łupkowy kolor zamiast plastikowego niebieskiego, `procedural_ao` 0.7 (gradient góra–dół na każdej bryle), grain 0.5.
- **Rim** (`wet_surface.gdshader`, nowy uniform `rim_tint`, domyślnie czarny → świat nietknięty): księżycowo-srebrny fresnel tylko na skórze wrogów, wygaszony na powierzchniach skierowanych w górę (żeby nie rozjaśniać kołnierza za maską); szkoła lekko barwi rim (`SCHOOL_RIM_MIX`), elita mocniej akcentem; gaśnie razem z oczami przy śmierci.
- Test: `n3_yokai_visual_test` – nowa sekcja N12 (4 m: kontrast sylwetki ≥ 0.05 i rim podnosi luminancję o ≥ 0.006 względem tej samej klatki bez rimu; PRE bez rimu: 0.0013, PO: 0.0117). Test wyłącza też podpowiedź sterowania na starcie runu, która od czasu N3 zasłaniała głowę wroga.

Zrzuty (run.tscn, ta sama kamera): `PRE_/POST_swarm_4m.png`, `PRE_/POST_swarm_3m.png`.

Słabe / otwarte: sylwetka nadal prosta (to wciąż tuby, bez fałd szaty); rim subtelny – z 4 m widać go głównie na krawędziach ramion. Sprawdzenie „rogi na tle nieba" jest zależne od błyskawicy (w bazowym przebiegu 0.096, w ostatnim po zmianach 0.041 < 0.05, rogi i maska nie były zmieniane) – wymaga deterministycznej pogody w teście.

## Fix 1 (review: „PRE i PO wyglądają tak samo”)
- **Sylwetka**: tors w kształcie V (talia 0.10 → barki 0.24, zaokrąglone), pochylenie do przodu w samym meshu (`CHEST_LEAN` 0.30), sode przesunięte na barki, dłoń (spłaszczona elipsoida) i **stopa** wtopione w mesh kończyny (bez dodatkowego draw calla), pazury dłuższe (0.15 → 0.21 m). Trójkąty ciała ~670 → ~1250, czyli około +17 % na całego wroga. Draw calls bez zmian. Kolizje bez zmian.
- **Wróg „wisiał”**: to nie był błąd spawnu. Fizycznie stał na niewidocznym boxie stopy (`extra_shapes` nogi), a mesh nogi kończył się na kostce ~4 cm nad ziemią. Teraz stopa jest widoczna dokładnie na tym boxie.
- **Rim**: mocniejszy `SKIN_RIM` i szersze pasmo (`rim_power` 1.7, nowy uniform, domyślnie 2.4 jak dotąd), więc obrys torsu, głowy i nóg widać na 4 m. Lift w teście: 0.0013 → 0.0170.
- **Gradient albedo** wzdłuż każdej bryły: góra ciemnieje przy stawie, czyli cień kołnierza pod maską i ciemniejsze barki/biodra.
- **Rogi**: bez błyskawic kość słoniowa była tak ciemna jak niebo (test przechodził wcześniej tylko dzięki losowym błyskom). Dostały emisję własnego koloru (`HORN_LIFT` 0.5), kształt bez zmian. Gaśnie przy śmierci.
- **Test deterministyczny**: piorun wyłączony, `seed()` na wariacje pozy. Dwa przebiegi dały identyczne liczby. Progi bez zmian. Poprawione nawijanie trójkątów przy większym pochyleniu (oś pochylona razem z pierścieniami), co wyłapał `dismember_test`.

Słabe: stopy mają na zrzucie jasne kropki (rim i niebo na małej bryle), a ciało to nadal gładkie tuby bez fałd szaty. Odstęp kolorów szkół na 8 m jest bliski progu (0.14 przy progu 0.12). Czwarty wróg stoi w kadrze za pniem, a to się nie zmieniło.
