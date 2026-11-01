# N5 — las jak w koncepcie (stan, pomiary, decyzje)

Źródło: `docs/concept/forest_concept.jpg`. Zrzuty z gry (okno, xvfb, ta sama kamera PRZED/PO): `docs/n5/before/` (HEAD `48dfe1c`), `docs/n5/after/` (ta gałąź). Test wizualny: `tests/n5_forest_visual_test.tscn` (okienkowy, w headless SKIP).

## Co zrobione

| Punkt | Zmiana | Gdzie |
|---|---|---|
| Gęstość | Drugi rodzaj sugi `base_layout = false` (rozstaw 3 m, korona 0,6–0,9) sadzony po torii, więc układ torii się nie rusza. Rozstaw między pniami wynika z zasięgu koron, nie z samego odstępu. | `worldgen_profile.gd` (`_dense_cedar_entry`), `forest_world.gd` (`_extra_tree_spots`, `_near_extra`, `_near_base`, `_crown_reach_at`) |
| Gęstość — reguła | Pnie dodatkowe trzymają od pni bazowych i między sobą `0,75 × (r₁ + r₂)` (ta sama miara co `canopy_visual_quality_test`). Zasięg korony liczony jak w teście (przesunięcie dysku + promień). | `forest_world.gd` |
| Ścieżki | Krawędź liczona w shaderze z odległości do osi (kanał G wierzchołka, w metrach), szum szerokości 0,22 m. Kanał R (waga) zostaje dla testów. | `forest_world.gd` (`_path_colour`), `forest_ground.gdshader` |
| Paprocie | Asset `fern_zvanstone` (CC BY 4.0), bake RGBA (`tools/prep_forest_assets.py --alpha`), 299 tris, materiał `forest_diffuse` z cięciem po alfie, wpis podszytu `along_path` (tylko na krawędzi ścieżki, bez kolizji). | `assets/models/environment/undergrowth/`, `worldgen_profile.gd` (`_fern_entry`), `undergrowth_entry.gd`, `forest_world.gd` (`_card_material`) |
| Fade | Każdy rodzaj drzewa, sakura i paproć gasną ditherem na ostatnich 7 m (paprocie 18–26 m) przed krawędzią rysowania, zamiast ucinać się w jednym kroku. | `forest_diffuse.gdshader`, `sakura_tree.gdshader` (`draw_fade`), `forest_world.gd` (`_draw_fade`) |
| Sakura | Neon nie miał mgły ani fade'u — znikał twardo na 40 m. Teraz fade jak wyżej. | `sakura_tree.gdshader` |

## Pomiary

Gęstość (pnie na 100 m² w pierścieniu 8–30 m):

| | HEAD | teraz |
|---|---|---|
| wokół polany | 0,84 | **1,33** |
| wokół punktów ścieżki | 0,85 | **1,24** |

Nakładanie koron (`canopy_visual_quality_test`, limit 40%): **17,2%**. Otwarte niebo nad ścieżkami 97% (D19 bez zmian). Zasięg koron od pni ścieżki: min. **2,37 m** (limit 2,0 m).

Linia wzroku do torii z 35 m, blokada przez pnie: **48%** (test: ≥ 40%).

Budżet (`quest_perf_test`): draw calls **291** (limit 345, z menu 292 — zapas 53), prymitywy lasu **248 485** (limit 315 000). Przed zmianami: 302 768 w D5 notatkach, 135 759 w pierwszym pomiarze tej sesji — porównanie uczciwe tylko z pomiarem na HEAD, którego nie powtórzyłem w tej samej konfiguracji.

Krawędź ścieżki (pomiar: druga różnica pozycji krawędzi między wierszami obrazu, po rozmyciu 7 px, żeby deszcz nie tworzył fałszywych krawędzi):

| | maks. [px] | średnia [px] |
|---|---|---|
| PRZED (HEAD) | 5,78 | 1,24 |
| PO (ta gałąź, szum 0,22 m) | 4,48 | 1,01 |

**Próg 2,5 px NIE jest spełniony.** Test `n5_forest_visual_test` raportuje FAIL. Próbowałem szumu 0,10 m: maks. 3,74, średnia 1,27 — gorzej w średniej, więc wróciłem do 0,22 m. Poprawa jest realna, ale krawędź nadal nie jest tak gładka, jak wymaga zadanie.

Paprocie w kadrze: zmiana **2 707 pikseli** w pasie gruntu, gdy paprocie są widoczne (test: ≥ 150).

## Testy dodane / rozszerzone

- `forest_world_test`: gęstość w pierścieniu polany i ścieżek (≥ 1,0/100 m²), linia wzroku do torii (≥ 40%), fade każdego rodzaju przy krawędzi (bez skoku).
- `worldgen_path_game_test`: głazy i pnie 2,5 m od ścieżki (bez zmian progu); paprocie stoją na krawędzi, nie na żwirze (≥ 1,6 m od osi). Dla paproci zmieniłem źródło danych na metadane chunka (`xfs_Undergrowth*`), bo w headless odczyt bufora MultiMesh zwraca tożsamość.
- `n5_forest_visual_test` (okienkowy): krawędź ścieżki (druga różnica), paprocie w kadrze, zrzuty PRZED/PO.

## Co słabe (surowo)

- **Las nadal rzadki w zestawieniu z koncepcją.** 1,3 pnia/100 m² to +60%, nie „gęsty las”. Wąskim gardłem jest reguła koron względem pni bazowych (sugi z zasięgiem ~4–5 m i rozstawem 6 m). Dalsze zagęszczenie wymaga zmiany bazowego układu (rozstaw/korony sugi), a to przesuwa torii — poza zakresem tej zmiany. Zrzuty PO z polany pokazują to wprost.
- **Krawędź ścieżki nadal ma ząbki** wg miary (4,48 px > 2,5 px). Źródło nie jest zidentyfikowane; podejrzane: aliasing 7 cm strefy przejścia na małej rozdzielczości i szum szerokości.
- **Paprocie wyglądają jak karty**, nie jak roślina zbita przy pniach — nie robiłem przy pniach (tylko krawędź ścieżki), ani mchu na pniach (mossy_log nie zbadane).
- **Sakura z daleka:** fade jest, ale nie oceniłem na zrzucie w oczach (sakura_24m), a test wizualny nie sprawdza pop-inu sakury pikselowo.
- **Torii 35 m** na zrzucie PO nie zawsze kadruje bramę (kamera ustawiona na pozycję, nie na bramę).
- Ścieżki nie łączą się między chunkami inaczej niż dotąd (nie ruszane).

## Decyzje

- Dodatkowe rodzaje sugi/sosny/sekwoi są po torii (`base_layout = false`), więc układ torii zostaje ten sam — zgodnie z D5.
- Reguła koron (`0,75 × (r₁ + r₂)`) jest traktowana jako twarde ograniczenie gęstości, a nie cel do obejścia. Pnie scen (sekwoje) zmniejszyły się z 75 do 44 w ringu przez tę regułę — akceptuję jako koszt; to hero-drzewa.
- Paprocie: tylko krawędź ścieżki (`along_path`), bez kolizji, fade 18–26 m.
