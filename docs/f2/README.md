# F2: torii przodem do ścieżki

Jakub (02.11): "torii sie spwnuja bokiem do sciezki (sciezka powinna przechodzic przez srodek)".

## Co było
- Dekoracyjne torii w chunkach stały 2,8 m obok ścieżki z losowym obrotem: do 89,9° w poprzek ścieżki
  (pomiar: 46 bram przy ścieżce, najgorsza 89,9°).
- Bramy gry (ToriiManager) już były ustawiane wzdłuż ścieżki, ale styczną brano z surowej trasy,
  a świat renderuje wygładzoną linię (różnice do 22° na zakrętach).

## Co zmieniono
- Dekoracyjne bramy są planowane per chunk z danych (ścieżka, pnie, ziarno świata): przy ścieżce
  przyciągane na linię środkową (wygładzoną, jak na ekranie) i obracane wzdłuż niej.
- Pnie, dodatkowe i tylne drzewa, latarnie i kamienie omijają świetlisty prostokąt przejścia każdej bramy
  (słupy włącznie, +0,6 m), niezależnie od kolejności budowy chunków.
- Bramy gry biorą styczną z wygładzonej linii.

## Test
- `tests/torii_placement_test.gd`, sekcja F2: 20 światów, 194 bramy (64 z nich poza ścieżką, nie sprawdzane
  pod kątem ścieżki). Wynik: odchylenie środka 0,00 m (najgorsza), kąt 0,0°, 0 pni/drzew i 0 latarni/kamieni
  w przejściu.

## Kadry (tests/torii_path_view_test.gd, okno, xvfb)
- `post_path_view.png`: kamera na ścieżce 14 m za punktem (-16,98; -7,13), wzdłuż ścieżki. Środek przejścia
  bramy w środku kadru (offset 0,000 szerokości).
- `pre_path_view.png`: ta sama kamera na starszym kodzie (5b8d6ca).

Uczciwie: te dwa kadry NIE pokazują poprawki dekoracyjnych bram. Brama w środku kadru jest w obu
przypadkach tą samą bramą gry (ustawioną wzdłuż ścieżki już wcześniej), a punkt kamery był wybrany
ręcznie (`--gate`), nie na dekoracyjnej bramie. Poprawka dekoracyjnych bram jest potwierdzona danymi
(pomiar 89,9° → 0°), a nie tymi kadrami. Czysta para PRZED/PO dekoracyjnej bramy wymaga kamery ustawionej
na bramie, która w starym kodzie stoi bokiem; to do zrobienia.
