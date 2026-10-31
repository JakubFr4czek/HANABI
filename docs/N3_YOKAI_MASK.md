# N3: twarze i sylwetki yōkai (maska demona, tapered ciała)

Problem: wrogowie wyglądali jak klocki (głowa-pudełko, tułów-prostopadłościan, patyczkowe kończyny).
Zrzuty PRE/POST: `docs/n3/` (ten sam kadr, ta sama kamera, ta sama scena `run.tscn`).

## Decyzje

1. **Maska (yōkai i Oni): `Japanese demon mask` by Eques_inferno, CC BY 4.0.**
   Zdecymowana do 1 700 trójkątów (`tools/bake_yokai_mask.py`, Blender headless, edge-collapse),
   przeniesiona do układu głowy (twarz +Z, góra +Y, metry), szerokość 0,176 m, nos 0,135 m przed
   środkiem głowy. Tekstury 1K: albedo, ORM (occlusion/roughness/metal), normal map.
   Oczy szkoły siedzą w gniazdach maski (`YokaiForms.EYE_X/Y/Z`), zaświecone punktami EyeGlow.
   Zapis: `assets/models/enemies/yokai_mask.glb` + `yokai_mask_{albedo,orm,normal}.png`.
   Bake jest powtarzalny: skrypt daje bajt-w-bajt ten sam glb.

2. **Elita: ta sama maska, bez menpō.** Decyzja zamiast drugiego modelu (`menpo_mask_aid`, 41k tris):
   elita czyta się po kolorze żywiołu w oczach, sigilu, pazurach i skórze (jak dotąd), a jeden model
   zmniejsza koszt i liczbę zasobów. Menpō nie jest używane.

3. **Oni: maska zamieniona.** Porównanie (render Blender, `docs/n3/ONI_head_PRE_left_POST_right.png`
   oraz zrzut z gry `POST_5_oni_close.png`): stara maska była blokiem (pudła i pierścień),
   nowa ma sylwetkę rogów i zęby. Wspólna maska, skala węzła 2,35 (efektywna szerokość
   jak poprzednio ~0,41 m). Procedural body i kanabō bez zmian. Usunięte stare pliki
   `oni_mask_run.glb` i `oni_mask_run_normal.png` (w git).

4. **Sylwetka: formy zamiast pudeł** (`src/enemies/yokai_forms.gd`):
   - tułów i miednica: zwężane, eliptyczne przekroje (`tube`), klatka szersza niż głębsza;
   - ramiona i nogi: zwężane tuby (cienki nadgarstek i kostka, pełne przedramię i udo);
   - głowa: sfera wizualna r=0,088 (fizyczna kolizja nadal r=0,115), żeby maska nie chowała się w czaszce;
   - pasy (wrap, obi), naramienniki (sode), sigil, hakama (podarty kilt) i pazury (stożki): osobne siatki;
   - wszystkie kształty są wspólne (`_cached`), materiały współdzielone.
   Fizyka (ciała, kolizje, stawy, limity) NIE zmieniona. Nie skalowano węzłów ragdolla.

5. **Cięcie (D4) na nowych siatkach:** `KirisuteCut._primary_mesh` przyjmuje `ArrayMesh` (wcześniej
   tylko prymitywy). Maska ma `keep_on_piece` i jedzie z kawałkiem, w którym leży środek.

## Budżety (zmierzone)

| | przed | po | limit |
|---|---|---|---|
| trójkąty na yōkai | ~700 (szac.) | 3 506 | `RunPerfBudget.MAX_YOKAI_TRIANGLES` = 4 000 |
| surface (draw) na yōkai | 27 | 23 | `MAX_YOKAI_DRAWS` = 24 (nie rośnie o więcej niż 1 na wroga) |
| prymitywy, 8 yōkai (quest_perf) | – | 162 229 | 420 000 |
| draw calls przy hard capie | – | 276 (peak w quest_perf) | 345 |

Trójkąty szacowane ręcznie dla „przed”: nie mierzone w poprzednim commicie.

## Testy

- `enemy_variants_test`: każdy yōkai (rój i elita) ma maskę na głowie, brak BoxMesh na głowie/tułowiu/miednicy,
  ≤ 4 000 trójkątów i ≤ 24 surface.
- `dismember_test` (`_test_slicer`): tuby klatki, miednicy i naramiennik cięte jak prymitywy: dwie
  połówki zamknięte na przekroju, nawijanie zgodne z normalnymi, przekrój jako osobna powierzchnia.
- `quest_perf_test`: ośmiu yōkai na hard capie mieści się w budżecie trójkątów i draw surface.
- `n3_yokai_visual_test` (okienkowy, SKIP headless): 8 m – cztery szkoły w różnych kolorach oczu
  (różnica ≥ 0,12; wynik 0,17–0,20); 3 m – kontrast sylwetki z mgłą (średnio ≥ 0,05; wynik ~0,27);
  rozcięcie daje dwa kawałki.

## Uczciwa ocena (surowo)

**Lepiej, ale jeszcze nie „premium”.**

- Maska jest rozpoznawalna od ~1,5 m (rogi, zęby, ciemna twarz i oczy). Przy 3 m to ciemna
  plama z mocnymi oczami; rogi i usta prawie znikają w rozdzielczości 960×540.
- Tułów i kończyny są zwężone, ale nadal sztywne (prosty cylinder z ramionami-tubami).
  Skóra jest w niebieskiej poświacie księżyca (sky fill) – desaturacja z GDD nie jest w pełni widoczna.
- Hakama wygląda jak kilt, nie jak łachman. Fałdy i rozdarcia są zbyt regularne.
- Kadr rozcięcia (`POST_4_kirisute_cut.png`) nie pokazuje wyraźnie samego cięcia; to
  kadr kilka klatek po nim. Przekrój w kolorze żywiołu nie jest na zrzucie czytelny.
- Oni: maska dobra, ale ma lekki szum (speckle) z bliska i jest częściowo przykryta
  górną częścią korpusu. Ciało Oni (blokowe) nie było ruszane – to osobna praca.
- Test kontrastu sylwetki przechodzi także PRZED zmianą (0,26 vs 0,27 po): sylwetka była
  czytelna już wcześniej. Poprawa jest w detalu (maska, zęby, oczy), nie w kontraście.
- Test kolorów 8 m na PRE jest przybliżony: próbkowanie używa współrzędnych oczu NOWEJ maski
  (w starym drzewie oczy są gdzie indziej). Wynik PRE (0,10) pokazuje raczej, że stare oczy
  słabo odcinały się od tła.

## Co dalej (poza zakresem N3)

- Ciało Oni (blokowe) i jego kanabō.
- Desaturacja skóry roju (sky fill w `wet_surface.gdshader`), wspólna dla wszystkich wrogów; zmiana globalna.
- Pazury i hakama z kilkoma wariantami kształtu, żeby rój nie wyglądał jak jeden model powielony.
- Wygładzenie maski (ok. 2,2k tris dawałoby lepszy profil rogów; budżet jest tu ciasny).
