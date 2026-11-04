# N16 – katana bossa widoczna w kadrze

Status: **CZĘŚCIOWO** (katana: zrobione i check przechodzi; drugi przebieg oni_boss_ai_test: 2 faile, opis niżej).

## 1. Czy fail istniał przed N15 (21107dc vs e2d6076)
Nie uruchamiałem sceny na 21107dc. Super-zasada pozwala na jeden przebieg sceny wizualnej na końcu.
Rozstrzygnąłem to z kodu:
- `git diff 21107dc e2d6076` zmienia tylko `oni_boss_brain.gd` (taktyka retreat), `oni_boss_ai_test.gd` i docs.
- W `f5_katana_boss_shots` zrzut `img` powstaje przy `brain._ai_timer = 999`, zanim padnie jakakolwiek
  decyzja AI. Taktyka retreat nie może się więc wykonać przed zrzutem, a kod N15 nie dotyka tego kadru.
- **Wniosek: fail jest starszy niż N15.** Ma dwie przyczyny, obie istniały już na 21107dc:
  1. **Ciemna klinga.** Księżyc ma `light_specular = 0`, a odbicia są wyłączone
     (`REFLECTION_SOURCE_DISABLED`), więc metaliczna stal (metallic 0,75, emisja 0,16) wychodzi
     prawie czarna. Na ciemnym lesie klinga ma 2–5 px szerokości.
  2. **Pomiar w złej klatce.** Test liczył pozycję klingi dopiero po fazie dymka, ~44 klatki
     po zrzucie. Boss w tym czasie lekko się kołysze (~4 px w poziomie), a okno próbki ma ±2 px.
     Próbki trafiały więc obok 2-pikselowej klingi. Po samym połysku, bez poprawki testu, check
     dalej dawał 2/9, choć klinga była na zrzucie wyraźna (sprawdzone na pikselach:
     jasna linia x 462–467, y 186–258).

## 2. Zmiana (tylko klinga bossa)
- `src/shaders/boss_blade_steel.gdshader` (nowy): ten sam stalowy albedo/metallic/roughness co
  wcześniej, plus emisja w chłodnym kolorze stali (0,62/0,70/0,86). Składa się z delikatnego
  połysku całej klingi (0,2), księżycowej linii na obu długich krawędziach (0,9) i lekkiego rimu
  pod kątem patrzenia (0,6).
- `run_oni_boss.gd::_steel_blade` daje ten materiał tylko na BoxMesh klingi. Rękojeść, tsuba,
  ciało, rim ciała, światło, mgła, niebo i environment zostały bez zmian. Katana gracza
  (`katana_steel.gdshader`) też jest nietknięta.

## 3. Test (progi bez zmian)
`tests/f5_katana_boss_shots.gd`: punkty klingi (mid, tip) są zapisywane w klatce zrzutu `img`,
a nie 44 klatki później. Progi bez zmian: ≥4/9 próbek, Δ > 0,05, r = 2.

## Wyniki
- `f5_katana_boss_shots` (xvfb, gl_compatibility, 960×540): **ALL PASSED**, katana **9/9**.
  Boss 3,95 m, ciało 52%, maska Δ 1,63, dymek OK.
  Uwaga: scena szła 2 razy. Pierwszy przebieg (sam shader) dał 2/9 i ujawnił błąd czasu pomiaru
  z punktu 1.2. Drugi przebieg był po poprawce testu.
- Nie mierzyłem, czy stara ciemna klinga przeszłaby z poprawionym testem. Sam połysk jest
  na zrzutach wyraźny.
- `oni_boss_ai_test` (drugi przebieg po N15, trwał ~39 min): 2 FAIL.
  - Retreat: **PASS** (2,16 → 2,91 m). Flank, fallback, HTTP, requests itd. też PASS.
  - **FAIL HP → 0** (signal false, active true, hp 0, dead false, body state 2). Boss leży
    w knockdown i nie dochodzi do get-up / `_on_permanent_defeat` w oknie testu. N15 miał tu PASS,
    więc to niestabilne (timing przy obciążonej maszynie?), nie naprawione.
  - **FAIL „the bubble is gone a few seconds after the last line”**: nowy fail, nieanalizowany.
  - N16 zmienia tylko materiał klingi i test f5. Na logikę bossa, HP ani dymek nie ma wpływu.

## Zrzuty
- `before_01_boss_4m.png`: stan e2d6076 (ten sam kadr z N15). Klinga ginie.
- `after_01_boss_4m.png`: N16. Klinga czyta się jako jasna stal od dłoni ponad głowę.
- `after_02_ai_bubble.png`: N16, kadr z dymkiem AI (ten sam przebieg).

## Dalej
1. HP → 0 w oni_boss_ai_test: boss utyka w knockdown (body state 2). Sprawdzić czas get-up
   względem okna testu.
2. Fail znikania dymka: zbadać.
