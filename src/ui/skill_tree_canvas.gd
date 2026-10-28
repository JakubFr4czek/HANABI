class_name SkillTreeCanvas
extends Control
## The skill-tree scroll, drawn as one 2D canvas (docs/ELEMENTS_PLAN.md (e)).
##
## A [SkillTreeMenu] shows this inside a SubViewport on a single world-space
## quad: one draw call, fog-proof, crisp text. The canvas is pure presentation
## plus layout: it never spends Ofuda (the menu does, through
## RunGame.unlock_skill) and answers [method hit_test] for the pointer.
##
## Layout (1600 x 1000 px, about 1 px per headset pixel at 1.1 m):
## header (title, Ofuda balance, close) / four element tabs / the five-node
## tree of the chosen element on the left / detail + UNLOCK button on the right /
## footer (controls, what is on the blade).

const SIZE := Vector2(1600.0, 1000.0)

# --- Palette: sumi lacquer, gilt edging, cinnabar seals. -----------------------
const LACQUER := Color(0.040, 0.038, 0.056, 0.95)
const LACQUER_RAISED := Color(0.075, 0.07, 0.095, 0.98)
const LACQUER_SUNK := Color(0.022, 0.021, 0.032, 0.98)
const GILT := Color(0.80, 0.66, 0.42)
const GILT_DIM := Color(0.80, 0.66, 0.42, 0.34)
const PAPER := Color(0.94, 0.91, 0.84)
const DIM := Color(0.62, 0.62, 0.70)
const FAINT := Color(0.42, 0.42, 0.52)
const CINNABAR := Color(0.86, 0.29, 0.21)

const ROLE_CAPTION := {1: "AWAKENING", 2: "ABILITY 1", 3: "ABILITY 2", 4: "RESONANCE", 5: "MASTER"}
const ROLE_LONG := {
	1: "SCHOOL AWAKENING", 2: "ABILITY 1 FOCUS", 3: "ABILITY 2 FOCUS",
	4: "ELEMENTAL RESONANCE", 5: "MASTER TECHNIQUE",
}
const ELEMENT_TITLE := {
	Elements.SAKURA: "SAKURA", Elements.STORM: "STORM", Elements.INK: "INK", Elements.SHADOW: "SHADOW",
}

## Restrained school colors for the lacquer UI (the game's own accents are
## far too neon for engraved plaques): rose, steel blue, slate, amethyst.
static func accent_of(el: String) -> Color:
	match el:
		Elements.SAKURA: return Color(0.90, 0.57, 0.69)
		Elements.STORM: return Color(0.52, 0.77, 0.91)
		Elements.INK: return Color(0.68, 0.74, 0.88)
		Elements.SHADOW: return Color(0.72, 0.58, 0.90)
	return Color(0.85, 0.88, 0.96)


# --- Layout ---------------------------------------------------------------------
const TAB_SIZE := Vector2(352.0, 84.0)
const TAB_GAP := 20.0
const TAB_ORIGIN := Vector2(66.0, 120.0)
const NODE_SIZE := Vector2(340.0, 120.0)
const TREE_COLUMN := {1: 500.0, 2: 270.0, 3: 730.0, 4: 500.0, 5: 500.0}
const TREE_ROW := {1: 340.0, 2: 504.0, 3: 504.0, 4: 668.0, 5: 832.0}
const DETAIL_RECT := Rect2(990.0, 236.0, 544.0, 664.0)
const UNLOCK_RECT := Rect2(1018.0, 786.0, 488.0, 88.0)
const CLOSE_RECT := Rect2(1488.0, 26.0, 70.0, 70.0)
const BALANCE_RECT := Rect2(1150.0, 22.0, 310.0, 82.0)

## Real-time animation clock (seconds), advanced by the menu, not by game time.
var anim_time := 0.0

var tree: SkillTreeData
var balance := 0
## Selected tab (an element id) and the node shown in the detail pane.
var element := Elements.SAKURA
var selected_id := ""
## {"kind": "tab"|"node"|"unlock"|"close", "key": int|String} or empty.
var hover: Dictionary = {}
## Element on the katana now and its seconds left, for the footer.
var blade_element := Elements.NONE
var blade_seconds := 0.0
var hint_text := ""
## Transient detail-pane message (why a purchase failed).
var status_text := ""
var _flash_id := ""
var _flash_t := -1.0
var _deny_t := -1.0


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- State helpers (the menu drives these) ---------------------------------------

func flash_unlock(node_id: String) -> void:
	_flash_id = node_id
	_flash_t = 0.0


func flash_denied() -> void:
	_deny_t = 0.0


func advance(delta: float) -> void:
	anim_time += delta
	if _flash_t >= 0.0:
		_flash_t += delta
		if _flash_t > 0.9:
			_flash_t = -1.0
	if _deny_t >= 0.0:
		_deny_t += delta
		if _deny_t > 0.4:
			_deny_t = -1.0


func nodes() -> Array[Dictionary]:
	return SkillTreeData.nodes_for_element(element)


func selected_node() -> Dictionary:
	return SkillTreeData.node_by_id(selected_id)


## The node the pane should open on for [param el]: the cheapest one that can
## be bought next, else the last owned, else the first.
func default_node_for(el: String) -> String:
	if tree == null:
		return ""
	var best := ""
	var best_cost := 1 << 30
	for n: Dictionary in SkillTreeData.nodes_for_element(el):
		var id := String(n.id)
		if not tree.is_unlocked(id) and tree.prerequisites_met(id) and int(n.cost) < best_cost:
			best = id
			best_cost = int(n.cost)
	if best != "":
		return best
	var last := ""
	for n: Dictionary in SkillTreeData.nodes_for_element(el):
		if tree.is_unlocked(String(n.id)):
			last = String(n.id)
	return last if last != "" else String(SkillTreeData.nodes_for_element(el)[0].id)


## "owned", "available" (prerequisites met) or "locked".
func node_state(id: String) -> String:
	if tree == null:
		return "locked"
	if tree.is_unlocked(id):
		return "owned"
	return "available" if tree.prerequisites_met(id) else "locked"


func owned_count(el: String) -> int:
	var c := 0
	for n: Dictionary in SkillTreeData.nodes_for_element(el):
		if tree != null and tree.is_unlocked(String(n.id)):
			c += 1
	return c


# --- Geometry --------------------------------------------------------------------

func tab_rect(i: int) -> Rect2:
	return Rect2(TAB_ORIGIN + Vector2(float(i) * (TAB_SIZE.x + TAB_GAP), 0.0), TAB_SIZE)


func node_rect(node: Dictionary) -> Rect2:
	var tier := int(node.tier)
	var center := Vector2(float(TREE_COLUMN[tier]), float(TREE_ROW[tier]))
	return Rect2(center - NODE_SIZE * 0.5, NODE_SIZE)


## What lies under canvas point [param p]: {"kind", "key"} or {}.
func hit_test(p: Vector2) -> Dictionary:
	if CLOSE_RECT.has_point(p):
		return {"kind": "close", "key": ""}
	for i in Elements.COMBAT_ELEMENTS.size():
		if tab_rect(i).has_point(p):
			return {"kind": "tab", "key": i}
	for n: Dictionary in nodes():
		if node_rect(n).has_point(p):
			return {"kind": "node", "key": String(n.id)}
	if UNLOCK_RECT.has_point(p) and selected_id != "":
		return {"kind": "unlock", "key": selected_id}
	return {}


## Short readable verdict for the selected node's action.
## Returns {"mode": owned|ready|poor|locked, "label": String}.
func button_spec(id: String) -> Dictionary:
	if tree == null or id == "":
		return {"mode": "locked", "label": ""}
	var n := SkillTreeData.node_by_id(id)
	var cost := int(n.cost)
	match node_state(id):
		"owned":
			return {"mode": "owned", "label": "UNLOCKED"}
		"available":
			if balance >= cost:
				return {"mode": "ready", "label": "UNLOCK   札 × %d" % cost}
			return {"mode": "poor", "label": "NEED 札 × %d MORE" % (cost - balance)}
	return {"mode": "locked", "label": "LOCKED"}


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	if tree == null:
		return
	_draw_backdrop()
	_draw_header()
	_draw_tabs()
	_draw_tree()
	_draw_detail()
	_draw_footer()


## Single-line text with its top edge at [param pos].y.
func _text(s: String, pos: Vector2, font_size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, weight := 500) -> void:
	var f := UiTypography.font(weight)
	draw_string(f, Vector2(pos.x, pos.y + f.get_ascent(font_size)), s, align, width, font_size, color)


## Largest font size (≤ [param max_size]) at which the longest word of
## [param s] still fits [param width]; long names never run over the edge.
func _fit(s: String, width: float, max_size: int, weight := 500, min_size := 18) -> int:
	var f := UiTypography.font(weight)
	var size := max_size
	while size > min_size:
		var widest := 0.0
		for word in s.split(" "):
			widest = maxf(widest, f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		if widest <= width:
			break
		size -= 1
	return size


## Largest size at which the whole single line [param s] fits [param width].
func _fit_line(s: String, width: float, max_size: int, weight := 500, min_size := 18) -> int:
	var f := UiTypography.font(weight)
	var size := max_size
	while size > min_size and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 1
	return size


## Wrapped text; returns its height.
func _wrapped(s: String, pos: Vector2, font_size: int, color: Color, width: float,
		max_lines := -1, align := HORIZONTAL_ALIGNMENT_LEFT, weight := 500) -> float:
	var f := UiTypography.font(weight)
	draw_multiline_string(f, Vector2(pos.x, pos.y + f.get_ascent(font_size)), s, align, width,
			font_size, max_lines, color)
	return f.get_multiline_string_size(s, align, width, font_size, max_lines).y


func _box(rect: Rect2, bg: Color, border: Color, border_w: int, radius: int,
		shadow := 0, shadow_col := Color(0, 0, 0, 0)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = shadow_col
	draw_style_box(sb, rect)


func _draw_backdrop() -> void:
	_box(Rect2(Vector2.ZERO, SIZE), LACQUER, Color(GILT, 0.8), 3, 28)
	_box(Rect2(Vector2(14, 14), SIZE - Vector2(28, 28)), Color(0, 0, 0, 0), GILT_DIM, 1, 20)
	# Soft sheen from the top, like lacquer under a lantern.
	draw_polygon(PackedVector2Array([Vector2(26, 26), Vector2(SIZE.x - 26, 26),
			Vector2(SIZE.x - 26, 330), Vector2(26, 330)]),
			PackedColorArray([Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.045), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
	# Corner brackets.
	for c in [Vector2(34, 34), Vector2(SIZE.x - 34, 34), Vector2(34, SIZE.y - 34), Vector2(SIZE.x - 34, SIZE.y - 34)]:
		var sx := 1.0 if c.x < SIZE.x * 0.5 else -1.0
		var sy := 1.0 if c.y < SIZE.y * 0.5 else -1.0
		draw_polyline(PackedVector2Array([c + Vector2(0, 28) * sy, c, c + Vector2(28, 0) * sx]), GILT, 2.0, true)


func _draw_header() -> void:
	_text("術", Vector2(62, 22), 74, GILT)
	_text("ELEMENTAL ARTS", Vector2(150, 22), 40, PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 650)
	_text("一時停止", Vector2(580, 32), 24, GILT)
	_text("Spend Ofuda to deepen the school on your blade", Vector2(152, 68), 26, DIM)
	# Ofuda balance plaque.
	_box(BALANCE_RECT, LACQUER_SUNK, Color(CINNABAR, 0.85), 2, 12)
	_text("OFUDA", Vector2(BALANCE_RECT.position.x + 22, BALANCE_RECT.position.y + 10), 20, DIM)
	_text("札 × %d" % balance, Vector2(BALANCE_RECT.position.x + 22, BALANCE_RECT.position.y + 28), 46, PAPER)
	# Close.
	var hot := String(hover.get("kind", "")) == "close"
	_box(CLOSE_RECT, Color(CINNABAR, 0.30) if hot else LACQUER_SUNK, Color(GILT, 0.9 if hot else 0.5), 2, 35)
	_text("閉", CLOSE_RECT.position + Vector2(0, 8), 46, PAPER if hot else DIM, HORIZONTAL_ALIGNMENT_CENTER, CLOSE_RECT.size.x)
	# Rule under the header.
	draw_line(Vector2(66, 108), Vector2(SIZE.x - 66, 108), GILT_DIM, 1.5, true)


func _draw_tabs() -> void:
	for i in Elements.COMBAT_ELEMENTS.size():
		var el: String = Elements.COMBAT_ELEMENTS[i]
		var r := tab_rect(i)
		var accent := accent_of(el)
		var active := el == element
		var hot := String(hover.get("kind", "")) == "tab" and int(hover.get("key", -1)) == i
		var bg := LACQUER_RAISED
		if active:
			bg = Color(accent.r * 0.20, accent.g * 0.20, accent.b * 0.20, 0.98)
		elif hot:
			bg = Color(0.11, 0.105, 0.14, 0.98)
		var border := Color(accent, 0.95) if active else (Color(GILT, 0.8) if hot else GILT_DIM)
		_box(r, bg, border, 3 if active else 2, 14)
		_text(Elements.build_label(el), r.position + Vector2(18, 4), 62, accent if active or hot else Color(accent, 0.75))
		_text(String(ELEMENT_TITLE[el]), r.position + Vector2(98, 10), 32, PAPER if active else DIM)
		# Progress pips.
		var owned := owned_count(el)
		for k in 5:
			var c := r.position + Vector2(104 + float(k) * 24.0, 58)
			if k < owned:
				draw_circle(c, 7.0, accent)
			else:
				draw_arc(c, 6.5, 0.0, TAU, 20, Color(DIM, 0.7), 1.8, true)
		# "On the blade now" marker.
		if el == blade_element:
			var m := r.position + Vector2(r.size.x - 22, 22)
			draw_circle(m, 8.0, accent)
			draw_arc(m, 13.0, 0.0, TAU, 28, Color(accent, 0.5), 2.0, true)
			_text("BLADE", r.position + Vector2(r.size.x - 108, 52), 20, Color(accent, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, 86)
		if active:
			draw_line(r.position + Vector2(18, r.size.y - 1), r.position + Vector2(r.size.x - 18, r.size.y - 1), accent, 4.0, true)


func _draw_tree() -> void:
	var accent := accent_of(element)
	# A faint ensō (brush circle) behind the tree: calm, not decoration for its own sake.
	draw_arc(Vector2(500, 586), 292.0, deg_to_rad(-70.0), deg_to_rad(235.0), 72, Color(accent, 0.10), 5.0, true)
	# Links first, plaques over them.
	for n: Dictionary in nodes():
		var reqs: Array = []
		reqs.append_array(n.get("requires_all", []))
		reqs.append_array(n.get("requires_any", []))
		for req_id: String in reqs:
			_draw_link(SkillTreeData.node_by_id(req_id), n, accent)
	for n: Dictionary in nodes():
		_draw_node(n, accent)


func _draw_link(from_n: Dictionary, to_n: Dictionary, accent: Color) -> void:
	var a := node_rect(from_n)
	var b := node_rect(to_n)
	var p0 := Vector2(a.position.x + a.size.x * 0.5, a.end.y)
	var p3 := Vector2(b.position.x + b.size.x * 0.5, b.position.y)
	var mid_y := p0.y + 10.0
	var pts := PackedVector2Array([p0, Vector2(p0.x, mid_y), Vector2(p3.x, mid_y), p3])
	var from_owned := tree.is_unlocked(String(from_n.id))
	var to_owned := tree.is_unlocked(String(to_n.id))
	if from_owned and to_owned:
		draw_polyline(pts, Color(accent, 0.22), 11.0, true)
		draw_polyline(pts, accent, 4.0, true)
	elif from_owned:
		draw_polyline(pts, Color(GILT, 0.85), 3.0, true)
	else:
		draw_polyline(pts, Color(FAINT, 0.55), 2.0, true)


func _draw_node(n: Dictionary, accent: Color) -> void:
	var id := String(n.id)
	var r := node_rect(n)
	var state := node_state(id)
	var cost := int(n.cost)
	var affordable := balance >= cost
	var selected := id == selected_id
	var hot := String(hover.get("kind", "")) == "node" and String(hover.get("key", "")) == id
	var pulse := 0.5 + 0.5 * sin(anim_time * 3.2)

	var bg := LACQUER_RAISED
	var border := GILT_DIM
	var border_w := 2
	var title_col := DIM
	var badge_col := FAINT
	var shadow := 0
	var shadow_col := Color(0, 0, 0, 0)
	match state:
		"owned":
			bg = Color(accent.r * 0.24, accent.g * 0.24, accent.b * 0.24, 0.98)
			border = accent
			border_w = 3
			title_col = PAPER
			badge_col = PAPER
			shadow = 16
			shadow_col = Color(accent, 0.38)
		"available":
			bg = Color(0.095, 0.09, 0.12, 0.98)
			border = Color(accent, 0.55 + 0.4 * pulse) if affordable else Color(GILT, 0.7)
			border_w = 3
			title_col = PAPER
			badge_col = accent
			if affordable:
				shadow = 12
				shadow_col = Color(accent, 0.12 + 0.18 * pulse)
		_:
			bg = LACQUER_SUNK
	if hot and not selected:
		bg = bg.lightened(0.07)
	_box(r, bg, border, border_w, 12, shadow, shadow_col)
	if selected:
		_box(r.grow(8.0), Color(0, 0, 0, 0), Color(GILT, 0.95), 2, 18)

	# Kanji badge.
	var badge := Rect2(r.position + Vector2(12, 14), Vector2(92, 92))
	_box(badge, Color(0, 0, 0, 0.38), Color(badge_col, 0.4), 1, 10)
	var kanji := String(n.kanji)
	var kanji_size := mini(48, int(84.0 / float(maxi(kanji.length(), 1))))
	_text(kanji, badge.position + Vector2(0, (badge.size.y - kanji_size * 1.18) * 0.5), kanji_size,
			badge_col, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x)

	# Title (two lines max) and cost / state.
	var title_w := r.size.x - 132.0
	_wrapped(String(n.title), r.position + Vector2(116, 12), _fit(String(n.title), title_w, 26, 600), title_col,
			title_w, 2, HORIZONTAL_ALIGNMENT_LEFT, 600)
	match state:
		"owned":
			_text("OWNED", r.position + Vector2(116, 84), 24, accent)
			# Cinnabar seal.
			var seal := r.position + Vector2(r.size.x - 20, 20)
			draw_circle(seal, 11.0, CINNABAR)
			draw_arc(seal, 11.0, 0.0, TAU, 24, Color(1, 0.8, 0.7, 0.7), 1.5, true)
		"available":
			_text("札 × %d" % cost, r.position + Vector2(116, 80), 30, GILT if affordable else CINNABAR)
		_:
			_text("札 × %d" % cost, r.position + Vector2(116, 80), 28, FAINT)
			_draw_lock(r.position + Vector2(218, 97))
	# Role caption above the plaque.
	_text(String(ROLE_CAPTION[int(n.tier)]), r.position + Vector2(6, -26), 20, FAINT)
	# Unlock flash.
	if _flash_t >= 0.0 and _flash_id == id:
		var k := _flash_t / 0.9
		_box(r.grow(8.0 + 46.0 * k), Color(0, 0, 0, 0), Color(1.0, 0.86, 0.55, 0.9 * (1.0 - k)), 4, 20 + int(30.0 * k))


func _draw_lock(c: Vector2) -> void:
	var body := Rect2(c - Vector2(11, 3), Vector2(22, 17))
	_box(body, Color(FAINT, 0.9), Color(FAINT, 0.9), 0, 3)
	draw_arc(c + Vector2(0, -3), 7.5, PI, TAU, 14, Color(FAINT, 0.9), 2.4, true)


func _draw_detail() -> void:
	var r := DETAIL_RECT
	_box(r, LACQUER_SUNK, GILT_DIM, 2, 18)
	var n := selected_node()
	if n.is_empty():
		return
	var accent := accent_of(String(n.element))
	var id := String(n.id)
	var x := r.position.x + 30.0
	var w := r.size.x - 60.0

	# Soft school-colored wash behind the heading.
	draw_polygon(PackedVector2Array([r.position + Vector2(6, 6), Vector2(r.end.x - 6, r.position.y + 6),
			Vector2(r.end.x - 6, r.position.y + 150), r.position + Vector2(6, 150)]),
			PackedColorArray([Color(accent, 0.16), Color(accent, 0.16), Color(accent, 0.0), Color(accent, 0.0)]))
	var kanji := String(n.kanji)
	var kanji_size := mini(92, int(172.0 / float(maxi(kanji.length(), 1))))
	_text(kanji, Vector2(x, r.position.y + 22 + (92 - kanji_size) * 0.5), kanji_size, accent)
	_text("TIER %d  ·  %s" % [int(n.tier), String(ROLE_CAPTION[int(n.tier)])],
			Vector2(x + 190, r.position.y + 20), 21, DIM)
	var head_w := w - 190.0
	_wrapped(String(n.title), Vector2(x + 190, r.position.y + 52), _fit(String(n.title), head_w, 36, 650, 22), PAPER,
			head_w, 2, HORIZONTAL_ALIGNMENT_LEFT, 650)
	var rule_y := r.position.y + 156.0
	draw_line(Vector2(x, rule_y), Vector2(x + w, rule_y), GILT_DIM, 1.5, true)

	# What it does.
	_wrapped(String(n.subtitle), Vector2(x, rule_y + 18.0), 32, PAPER, w, 4)

	# Requirements (left) and cost (right).
	var req_y := r.position.y + 344.0
	_text("REQUIRES", Vector2(x, req_y), 22, DIM)
	var all_reqs: Array = n.get("requires_all", [])
	var any_reqs: Array = n.get("requires_any", [])
	var line_y := req_y + 30.0
	var req_w := w - 170.0
	if all_reqs.is_empty() and any_reqs.is_empty():
		_text("Nothing: the first step", Vector2(x, line_y), 24, FAINT)
	for rid: String in all_reqs:
		line_y += _draw_requirement(rid, Vector2(x, line_y), accent, req_w)
	if not any_reqs.is_empty():
		if any_reqs.size() > 1:
			_text("any one of", Vector2(x, line_y), 20, FAINT)
			line_y += 24.0
		for rid: String in any_reqs:
			line_y += _draw_requirement(rid, Vector2(x, line_y), accent, req_w)
	var cost_x := x + w - 150.0
	_text("COST", Vector2(cost_x, req_y), 22, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 150.0)
	_text("札 × %d" % int(n.cost), Vector2(cost_x, req_y + 24), 46, GILT, HORIZONTAL_ALIGNMENT_RIGHT, 150.0)
	_text("you hold 札 × %d" % balance, Vector2(cost_x - 60, req_y + 84), 22, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
	if status_text != "":
		_text(status_text, Vector2(x, UNLOCK_RECT.position.y - 42.0), 24, Color(CINNABAR, 0.95),
				HORIZONTAL_ALIGNMENT_CENTER, w)

	_draw_unlock_button(id, accent)


## Draws one prerequisite line; returns the height it used.
func _draw_requirement(req_id: String, pos: Vector2, accent: Color, width: float) -> float:
	var req := SkillTreeData.node_by_id(req_id)
	var met := tree.is_unlocked(req_id)
	var c := pos + Vector2(10, 15)
	var diamond := PackedVector2Array([c + Vector2(0, -8), c + Vector2(8, 0), c + Vector2(0, 8), c + Vector2(-8, 0)])
	if met:
		draw_colored_polygon(diamond, accent)
	else:
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), CINNABAR, 2.0, true)
	var req_title := String(req.title)
	_text(req_title, pos + Vector2(30, 0), _fit_line(req_title, width - 30.0, 25, 500, 18), PAPER if met else Color(CINNABAR, 0.95),
			HORIZONTAL_ALIGNMENT_LEFT, width - 30.0)
	return 34.0


func _draw_unlock_button(id: String, accent: Color) -> void:
	var spec := button_spec(id)
	var mode := String(spec.mode)
	var hot := String(hover.get("kind", "")) == "unlock"
	var r := UNLOCK_RECT
	if _deny_t >= 0.0:
		r.position.x += sin(_deny_t * 70.0) * 9.0 * (1.0 - _deny_t / 0.4)
	var pulse := 0.5 + 0.5 * sin(anim_time * 3.2)
	match mode:
		"ready":
			var bg := Color(0.62 + 0.08 * pulse, 0.13, 0.10, 0.98)
			if hot:
				bg = Color(0.80, 0.18, 0.12, 1.0)
			_box(r, bg, Color(1.0, 0.78, 0.55, 0.95), 3, 16, 14, Color(CINNABAR, 0.22 + 0.18 * pulse))
			_text(String(spec.label), r.position + Vector2(0, 20), 42, PAPER, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		"owned":
			_box(r, Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 0.95), Color(accent, 0.85), 2, 16)
			_text(String(spec.label), r.position + Vector2(0, 22), 38, accent, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		"poor":
			_box(r, LACQUER_RAISED, Color(CINNABAR, 0.9 if hot else 0.6), 2, 16)
			_text(String(spec.label), r.position + Vector2(0, 24), 36, Color(CINNABAR, 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_:
			_box(r, LACQUER_SUNK, GILT_DIM, 2, 16)
			_text(String(spec.label), r.position + Vector2(0, 24), 36, FAINT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_footer() -> void:
	draw_line(Vector2(66, 918), Vector2(SIZE.x - 66, 918), GILT_DIM, 1.5, true)
	_text(hint_text, Vector2(70, 938), 24, DIM, HORIZONTAL_ALIGNMENT_LEFT, 880.0)
	var blade := "BLADE  ·  PLAIN STEEL"
	var col := DIM
	if blade_element != Elements.NONE:
		blade = "BLADE  ·  %s %s  ·  %d s" % [Elements.build_label(blade_element),
				String(ELEMENT_TITLE.get(blade_element, "")), ceili(blade_seconds)]
		col = accent_of(blade_element)
	_text(blade, Vector2(SIZE.x - 70 - 560, 938), 24, col, HORIZONTAL_ALIGNMENT_RIGHT, 560)
