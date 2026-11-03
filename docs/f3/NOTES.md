# F3 — kapliczka: oczywista aktywacja

## Stan przed zmianą (kod z 2b68519)

**Jak aktywuje się ofuda (wybór):**
- **Desktop:** klawisz **E**, `run_game.gd: _unhandled_input` → `reach_for_offering()` → na jedną
  klatkę fizyki `_desktop_reach = true` → `_poll_shrine_touch` bierze `nearest_altar()`
  (ołtarz najbliższego zapalonego shrine'a) i sprawdza `HokoraShrine.is_touched_by`:
  dystans do ołtarza ≤ `HOKORA_HAND_RADIUS` 0.35 m oraz gracz ≤ `HOKORA_TOUCH_RADIUS` 2.2 m w poziomie
  i ≤ 2 m w pionie.
- **VR:** dłoń (bez trzymanego miecza, `holder.held == null`) w promieniu 0.35 m od ołtarza,
  gracz w zasięgu 2.2 m. Ołtarz to stół na wysokości ~0.42 m (`ALTAR_LOCAL`), ok. 0.78 m od środka
  kapliczki.
- Nie ma przycisku „interact" ani gestu do odczytania: jedyne ustawienie to odległość 2.2 m i
  trafienie w mały stolik.

**Dlaczego to jest nieczytelne:**
1. Zero podpowiedzi. Nic w świecie ani w HUD nie mówi, że kapliczka czeka na gracza, ani że to
   stół (ołtarz) jest punktem aktywacji — a nie sama kapliczka, dzwon czy latarnia.
2. Dwa różne cele w jednym miejscu: dzwon (suzu, 60 s cooldown, ładunek żywiołu) i stół ofiarny
   (ofuda). Oba wiszą przy froncie, E wybiera „bliższy", więc stojąc przy stole gracz dzwoni
   zamiast aktywować — albo odwrotnie, zależnie od kąta.
3. Ołtarz ma tylko delikatnie świecącą czerwoną tkaninę (emisja 0.45); w mgle i w nocy to
   nie jest czytelny cel.
4. Rozbieżność z dokumentacją: `docs/HOKORA_INTERACTION.md` opisuje mechanikę, nie to, co widać.
5. Brak feedbacku przed aktywacją (kapliczka nie reaguje na zbliżenie), a przy odmowie tylko
   cichy dzwonek — gracz nie wie, czy „nie zadziałało", czy „nie tędy".

## Decyzje dla F3

- **Zasięg podpowiedzi:** 2.0 m w poziomie od ołtarza (mniej niż 2.2 m aktywacji, więc hint
  pojawia się zanim gracz może wcisnąć). Podpowiedź znika, gdy kapliczka zgaszona albo trwa wybór.
- **Podświetlenie:** ciepły, powolny puls czerwonej tkaniny ołtarza i lekkie wzmocnienie halo
  latarni (bez nowych świateł, bez neonu). Świat i mgła nietknięte.
- **Tabliczka:** papierowy szyld w drewnianej ramie na słupku po lewej od ołtarza, Label3D w fontcie UiTypography,
  tekst z bindingu: desktop „E │ MAKE AN OFFERING", VR „TOUCH THE ALTAR".
  Decyzja: **VR nie dostaje „A / X"**, bo A/X jest już zajęty przez `ability_1_requested`
  (xr_player.gd:130), a zmiana przypisania zepsułaby zdolności. Aktywacja w VR zostaje dłonią
  na stole (już działa). Tekst po angielsku, zgodnie z resztą UI (np. nazwy kart ofudy).
- **Aktywacja:** bez zmiany — jedno naciśnięcie E / jeden dotyk dłonią. Feedback: dzwonek
  (`hokora_suzu`, już był), rozbłysk świecy (tween emisji i świateł), krótka wibracja na obu
  kontrolerach (VR), potem istniejący wybór ofudy. Po wyborze kapliczka gaśnie na resztę przebiegu,
  podpowiedź znika na stałe.
- **Testy:** patrz `tests/hokora_test.gd` (sekcja F3) i `tests/f3_prompt_shots.gd` (zdjęcia).
