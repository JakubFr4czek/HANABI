class_name SkillTreeCanvas
extends Control
## The skill-tree scroll, drawn as one 2D canvas (docs/ELEMENTS_PLAN.md (e)).
##
## A [SkillTreeMenu] shows this inside a SubViewport on a single world-space
## quad: one draw call, fog-proof, crisp text. The canvas is pure presentation
## plus layout: it never spends points (the menu does, through
## RunGame.unlock_skill) and answers [method hit_test] for the pointer.
##
## Layout (1600 x 1000 px, about 1 px per headset pixel at 1.1 m):
## header (title, points balance, close) / four element tabs / the five-node
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
const TAB_SIZE := Vector2(280.0, 84.0)
const TAB_GAP := 17.0
const TAB_ORIGIN := Vector2(66.0, 120.0)

# --- Settings tab (安 SETTINGS): five pages behind one sub-tab row. ---------------
const SETTINGS_ACCENT := Color(0.82, 0.76, 0.60)
const PAGE_AUDIO := 0
const PAGE_MOVE := 1
const PAGE_ACCESS := 2
const PAGE_CONTROLS := 3
const PAGE_AI := 4
const PAGE_SANDBOX := 5
const PAGE_NAMES := ["AUDIO", "MOVEMENT", "ACCESS", "CONTROLS", "AI BOSS", "SANDBOX"]
const PAGE_KANJI := ["音", "移", "補", "操", "知", "試"]
const PAGE_SUBTITLE := [
	"Four buses in 10 % steps. SFX plays a cue as you change it.",
	"Vignette, turning, walking pace and seated height.",
	"Photosensitive comfort: lightning flash and haptic strength.",
	"Both Quest 3 controllers. The katana follows your dominant hand.",
	"Meta Muse Spark / Llama model configuration, API key and AI combat.",
	"Demo and test mode: all skills unlocked. Off by default.",
]
## Six sub-tabs of equal width across the 1468 px page (D9 added SANDBOX).
const SUBNAV_RECTS := {
	"page_audio": Rect2(66.0, 218.0, 232.0, 44.0),
	"page_move": Rect2(312.0, 218.0, 232.0, 44.0),
	"page_access": Rect2(558.0, 218.0, 232.0, 44.0),
	"page_controls": Rect2(804.0, 218.0, 232.0, 44.0),
	"page_ai": Rect2(1050.0, 218.0, 232.0, 44.0),
	"page_sandbox": Rect2(1296.0, 218.0, 232.0, 44.0),
}
const SUBNAV_PAGE := {
	"page_audio": PAGE_AUDIO, "page_move": PAGE_MOVE,
	"page_access": PAGE_ACCESS, "page_controls": PAGE_CONTROLS,
	"page_ai": PAGE_AI, "page_sandbox": PAGE_SANDBOX,
}
const SETTINGS_RECTS := {
	PAGE_AUDIO: {
		"vol_master_dn": Rect2(884.0, 308.0, 84.0, 64.0),
		"vol_master_up": Rect2(1240.0, 308.0, 84.0, 64.0),
		"vol_music_dn": Rect2(884.0, 444.0, 84.0, 64.0),
		"vol_music_up": Rect2(1240.0, 444.0, 84.0, 64.0),
		"vol_sfx_dn": Rect2(884.0, 580.0, 84.0, 64.0),
		"vol_sfx_up": Rect2(1240.0, 580.0, 84.0, 64.0),
		"vol_ambience_dn": Rect2(884.0, 716.0, 84.0, 64.0),
		"vol_ambience_up": Rect2(1240.0, 716.0, 84.0, 64.0),
	},
	PAGE_MOVE: {
		"vignette_on": Rect2(230.0, 356.0, 160.0, 50.0),
		"vignette_off": Rect2(410.0, 356.0, 160.0, 50.0),
		"vignette_25": Rect2(230.0, 420.0, 110.0, 46.0),
		"vignette_50": Rect2(352.0, 420.0, 110.0, 46.0),
		"vignette_75": Rect2(474.0, 420.0, 110.0, 46.0),
		"vignette_100": Rect2(596.0, 420.0, 110.0, 46.0),
		"turn_snap": Rect2(230.0, 612.0, 186.0, 50.0),
		"turn_smooth": Rect2(424.0, 612.0, 186.0, 50.0),
		"snap_15": Rect2(230.0, 684.0, 85.0, 46.0),
		"snap_30": Rect2(325.0, 684.0, 85.0, 46.0),
		"snap_45": Rect2(420.0, 684.0, 85.0, 46.0),
		"snap_60": Rect2(515.0, 684.0, 85.0, 46.0),
		"snap_90": Rect2(610.0, 684.0, 85.0, 46.0),
		"smooth_10": Rect2(230.0, 748.0, 85.0, 46.0),
		"smooth_15": Rect2(325.0, 748.0, 85.0, 46.0),
		"smooth_20": Rect2(420.0, 748.0, 85.0, 46.0),
		"smooth_30": Rect2(515.0, 748.0, 85.0, 46.0),
		"smooth_40": Rect2(610.0, 748.0, 85.0, 46.0),
		"walk_slow": Rect2(1000.0, 356.0, 160.0, 50.0),
		"walk_normal": Rect2(1172.0, 356.0, 160.0, 50.0),
		"walk_fast": Rect2(1344.0, 356.0, 160.0, 50.0),
		"seated_off": Rect2(1000.0, 612.0, 250.0, 50.0),
		"seated_on": Rect2(1264.0, 612.0, 250.0, 50.0),
		"height_minus": Rect2(1000.0, 680.0, 120.0, 50.0),
		"height_plus": Rect2(1264.0, 680.0, 120.0, 50.0),
		"height_reset": Rect2(1396.0, 680.0, 120.0, 50.0),
		"recenter": Rect2(844.0, 748.0, 670.0, 50.0),
		"weight_minus": Rect2(1000.0, 850.0, 120.0, 44.0),
		"weight_plus": Rect2(1264.0, 850.0, 120.0, 44.0),
	},
	PAGE_ACCESS: {
		"flash_100": Rect2(460.0, 384.0, 320.0, 56.0),
		"flash_50": Rect2(800.0, 384.0, 320.0, 56.0),
		"flash_0": Rect2(1140.0, 384.0, 320.0, 56.0),
		"haptic_0": Rect2(460.0, 700.0, 260.0, 56.0),
		"haptic_50": Rect2(736.0, 700.0, 260.0, 56.0),
		"haptic_100": Rect2(1012.0, 700.0, 260.0, 56.0),
		"haptic_test": Rect2(1288.0, 700.0, 226.0, 56.0),
	},
	PAGE_CONTROLS: {
		"hand_right": Rect2(300.0, 270.0, 270.0, 50.0),
		"hand_left": Rect2(584.0, 270.0, 270.0, 50.0),
	},
	PAGE_AI: {
		"ai_toggle": Rect2(100.0, 370.0, 320.0, 56.0),
		"ai_key_paste": Rect2(440.0, 370.0, 320.0, 56.0),
		"ai_key_clear": Rect2(780.0, 370.0, 220.0, 56.0),
		"ai_lang_pl": Rect2(1020.0, 370.0, 160.0, 56.0),
		"ai_lang_en": Rect2(1200.0, 370.0, 160.0, 56.0),
	},
	PAGE_SANDBOX: {
		"sandbox_on": Rect2(460.0, 384.0, 320.0, 56.0),
		"sandbox_off": Rect2(800.0, 384.0, 320.0, 56.0),
	},
}
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
## The SETTINGS tab is open, and which of its pages (PAGE_*) shows.
var is_settings_tab := false
var settings_page := PAGE_AUDIO
## What the last draw of the controls page put on the panel (tests check it
## against the action map): callouts, and the bindings and action names they cover.
var drawn_callouts: Array[Dictionary] = []
var drawn_bindings: Array[String] = []
var drawn_actions: Array[String] = []
var selected_id := ""
## {"kind": "tab"|"node"|"unlock"|"close", "key": int|String} or empty.
var hover: Dictionary = {}
## Element on the katana now and its seconds left, for the footer.
var blade_element := Elements.NONE
var blade_seconds := 0.0
## The A / B abilities of the blade's element for the footer: [{glyph, name, ratio, seconds}].
var abilities: Array[Dictionary] = []
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


## Rect of settings control [param key] on the page that is showing (or Rect2()).
func settings_rect(key: String) -> Rect2:
	return (SETTINGS_RECTS[settings_page] as Dictionary).get(key, Rect2())


func _settings_hit_test(p: Vector2) -> Dictionary:
	for key: String in SUBNAV_RECTS:
		if (SUBNAV_RECTS[key] as Rect2).has_point(p):
			return {"kind": "settings", "key": key}
	for key: String in SETTINGS_RECTS[settings_page]:
		if (SETTINGS_RECTS[settings_page][key] as Rect2).has_point(p):
			return {"kind": "settings", "key": key}
	return {}


func hit_test(p: Vector2) -> Dictionary:
	if CLOSE_RECT.has_point(p):
		return {"kind": "close", "key": ""}
	for i in 5:
		if tab_rect(i).has_point(p):
			return {"kind": "tab", "key": i}
	if is_settings_tab:
		return _settings_hit_test(p)
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
				return {"mode": "ready", "label": "UNLOCK   点 × %d" % cost}
			return {"mode": "poor", "label": "NEED 点 × %d MORE" % (cost - balance)}
	return {"mode": "locked", "label": "LOCKED"}


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	if tree == null:
		return
	_draw_backdrop()
	_draw_header()
	_draw_tabs()
	if is_settings_tab:
		_draw_settings()
	else:
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
	if is_settings_tab:
		_text("安", Vector2(62, 22), 74, GILT)
		_text("SETTINGS", Vector2(150, 22), 40, PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 650)
		_text("設定", Vector2(760, 32), 24, GILT)
		_text(PAGE_SUBTITLE[settings_page], Vector2(152, 68), 26, DIM)
	else:
		_text("術", Vector2(62, 22), 74, GILT)
		_text("ELEMENTAL ARTS", Vector2(150, 22), 40, PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 650)
		_text("一時停止", Vector2(580, 32), 24, GILT)
		# D12: points come from levels; say so while the wallet is empty.
		var subtitle := "Spend points to deepen the school on your blade" if balance > 0 \
			else "Points: every level gives one, so keep fighting"
		_text(subtitle, Vector2(152, 68), 26, DIM)
	# Points balance plaque (D12).
	_box(BALANCE_RECT, LACQUER_SUNK, Color(CINNABAR, 0.85), 2, 12)
	_text("POINTS", Vector2(BALANCE_RECT.position.x + 22, BALANCE_RECT.position.y + 10), 20, DIM)
	_text("点 × %d" % balance, Vector2(BALANCE_RECT.position.x + 22, BALANCE_RECT.position.y + 28), 46, PAPER)
	# Close.
	var hot := String(hover.get("kind", "")) == "close"
	_box(CLOSE_RECT, Color(CINNABAR, 0.30) if hot else LACQUER_SUNK, Color(GILT, 0.9 if hot else 0.5), 2, 35)
	_text("閉", CLOSE_RECT.position + Vector2(0, 8), 46, PAPER if hot else DIM, HORIZONTAL_ALIGNMENT_CENTER, CLOSE_RECT.size.x)
	# Rule under the header.
	draw_line(Vector2(66, 108), Vector2(SIZE.x - 66, 108), GILT_DIM, 1.5, true)


func _draw_tabs() -> void:
	for i in 5:
		var r := tab_rect(i)
		var is_settings := (i == 4)
		var active := is_settings_tab if is_settings else (not is_settings_tab and Elements.COMBAT_ELEMENTS[i] == element)
		var hot := String(hover.get("kind", "")) == "tab" and int(hover.get("key", -1)) == i
		var accent := SETTINGS_ACCENT if is_settings else accent_of(Elements.COMBAT_ELEMENTS[i])
		var bg := LACQUER_RAISED
		if active:
			bg = Color(accent.r * 0.20, accent.g * 0.20, accent.b * 0.20, 0.98)
		elif hot:
			bg = Color(0.11, 0.105, 0.14, 0.98)
		var border := Color(accent, 0.95) if active else (Color(GILT, 0.8) if hot else GILT_DIM)
		_box(r, bg, border, 3 if active else 2, 14)
		if is_settings:
			_text("安", r.position + Vector2(16, 4), 62, accent if active or hot else Color(accent, 0.75))
			_text("SETTINGS", r.position + Vector2(86, 12), 30, PAPER if active else DIM)
			_text("VR CONFIG", r.position + Vector2(88, 54), 18, Color(accent, 0.9) if active else Color(DIM, 0.8))
		else:
			var el: String = Elements.COMBAT_ELEMENTS[i]
			_text(Elements.build_label(el), r.position + Vector2(16, 4), 62, accent if active or hot else Color(accent, 0.75))
			_text(String(ELEMENT_TITLE[el]), r.position + Vector2(86, 10), 30, PAPER if active else DIM)
			# Progress pips.
			var owned := owned_count(el)
			for k in 5:
				var c := r.position + Vector2(92 + float(k) * 22.0, 58)
				if k < owned:
					draw_circle(c, 6.5, accent)
				else:
					draw_arc(c, 6.0, 0.0, TAU, 20, Color(DIM, 0.7), 1.6, true)
			# "On the blade now" marker.
			if el == blade_element:
				var m := r.position + Vector2(r.size.x - 18, 18)
				draw_circle(m, 7.0, accent)
				draw_arc(m, 11.0, 0.0, TAU, 24, Color(accent, 0.5), 1.8, true)
				_text("BLADE", r.position + Vector2(r.size.x - 90, 50), 18, Color(accent, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, 72)
		if active:
			draw_line(r.position + Vector2(16, r.size.y - 1), r.position + Vector2(r.size.x - 16, r.size.y - 1), accent, 4.0, true)


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
			_text("点 × %d" % cost, r.position + Vector2(116, 80), 30, GILT if affordable else CINNABAR)
		_:
			_text("点 × %d" % cost, r.position + Vector2(116, 80), 28, FAINT)
			_draw_lock(r.position + Vector2(218, 97))
	# Role caption above the plaque.
	_text(String(ROLE_CAPTION[int(n.tier)]), r.position + Vector2(6, -27), 22, Color(FAINT, 1.0).lightened(0.12))
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
			Vector2(x + 190, r.position.y + 18), 22, DIM)
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
	# D9: in the sandbox nothing is charged, so the cost column says so instead of a price.
	if tree.sandbox:
		_text("SANDBOX", Vector2(cost_x, req_y), 22, Color(1.0, 0.7, 0.3), HORIZONTAL_ALIGNMENT_RIGHT, 150.0)
		_text("no cost", Vector2(cost_x - 60, req_y + 24), 36, Color(1.0, 0.7, 0.3), HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
	else:
		_text("COST", Vector2(cost_x, req_y), 22, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 150.0)
		_text("点 × %d" % int(n.cost), Vector2(cost_x, req_y + 24), 46, GILT, HORIZONTAL_ALIGNMENT_RIGHT, 150.0)
		_text("you hold 点 × %d" % balance, Vector2(cost_x - 60, req_y + 84), 22, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
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
	# D9: the tree says it is a sandbox in the footer, where the pause hint usually sits.
	if tree != null and tree.sandbox:
		_text("SANDBOX  ·  every node unlocked, nothing is spent", Vector2(70, 924), 24, Color(1.0, 0.7, 0.3), HORIZONTAL_ALIGNMENT_LEFT, 1080.0, 600)
	else:
		_text(hint_text, Vector2(70, 924), 24, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1080.0)
	var blade := "BLADE  ·  PLAIN STEEL"
	var col := DIM
	if blade_element != Elements.NONE:
		blade = "BLADE  ·  %s %s  ·  %d s" % [Elements.build_label(blade_element),
				String(ELEMENT_TITLE.get(blade_element, "")), ceili(blade_seconds)]
		col = accent_of(blade_element)
	_text(blade, Vector2(SIZE.x - 70 - 560, 926), 25, col, HORIZONTAL_ALIGNMENT_RIGHT, 560)
	# What the two face buttons do right now (frozen, like the rest of the world).
	if blade_element != Elements.NONE and abilities.size() == 2:
		var parts: Array[String] = []
		for i in 2:
			var a: Dictionary = abilities[i]
			var state := "ready" if float(a.ratio) >= 0.999 else "%d s" % ceili(float(a.seconds))
			parts.append("%s  %s %s  %s" % ["A" if i == 0 else "B", a.glyph, String(a.name).to_upper(), state])
		_text("   ·   ".join(parts), Vector2(70, 952), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1100.0)


func _draw_settings() -> void:
	_draw_subnav()
	match settings_page:
		PAGE_AUDIO:
			_draw_audio()
		PAGE_MOVE:
			_draw_move()
		PAGE_ACCESS:
			_draw_access()
		PAGE_CONTROLS:
			_draw_controls()
		PAGE_AI:
			_draw_ai()
		PAGE_SANDBOX:
			_draw_sandbox()
		_:
			_draw_controls()


func _draw_subnav() -> void:
	for key: String in SUBNAV_RECTS:
		var r: Rect2 = SUBNAV_RECTS[key]
		var page: int = SUBNAV_PAGE[key]
		var active := page == settings_page
		var hot := String(hover.get("kind", "")) == "settings" and String(hover.get("key", "")) == key
		var bg := Color(SETTINGS_ACCENT.r * 0.20, SETTINGS_ACCENT.g * 0.20, SETTINGS_ACCENT.b * 0.20, 0.98) if active \
			else (Color(0.11, 0.105, 0.14, 0.98) if hot else LACQUER_RAISED)
		var border := Color(SETTINGS_ACCENT, 0.95) if active else (Color(GILT, 0.8) if hot else GILT_DIM)
		_box(r, bg, border, 2 if active else 1, 12)
		var col := PAPER if (active or hot) else DIM
		var label := "%s  %s" % [PAGE_KANJI[page], PAGE_NAMES[page]]
		_text(label, r.position + Vector2(0, (r.size.y - 24.0) * 0.5 - 8.0), 24, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 600 if active else 500)
		if active:
			draw_line(r.position + Vector2(16, r.size.y - 1), r.position + Vector2(r.size.x - 16, r.size.y - 1), SETTINGS_ACCENT, 3.0, true)


## A settings control on the current page. [param font_size] 36 for the steppers.
func _settings_button(key: String, label: String, is_active: bool, accent := SETTINGS_ACCENT, font_size := 22) -> void:
	var r := settings_rect(key)
	if r.size == Vector2.ZERO:
		return
	var hot := String(hover.get("kind", "")) == "settings" and String(hover.get("key", "")) == key
	var bg := Color(accent.r * 0.28, accent.g * 0.28, accent.b * 0.28, 0.98) if is_active \
		else (Color(0.12, 0.115, 0.16, 0.98) if hot else LACQUER_SUNK)
	var border := Color(accent, 0.95) if is_active else (Color(GILT, 0.85) if hot else GILT_DIM)
	var text_col := PAPER if is_active else (Color(PAPER, 0.95) if hot else DIM)
	_box(r, bg, border, 2 if (is_active or hot) else 1, 10)
	var weight := 600 if is_active else 500
	# Long labels shrink to fit the button instead of being cut.
	var fsize := mini(font_size, _fit_line(label, r.size.x - 16.0, font_size, weight, 16)) if r.size.x >= 100.0 else 20
	_text(label, r.position + Vector2(0, (r.size.y - float(fsize)) * 0.5 - 8.0), fsize, text_col,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, weight)


## The +/- of a volume row, drawn as strokes (the font has no reliable minus sign).
func _stepper_glyphs(key: String) -> void:
	for dir in [["dn", -1.0], ["up", 1.0]]:
		var r := settings_rect("vol_%s_%s" % [key, dir[0]])
		var c := r.get_center()
		draw_line(c + Vector2(-13.0, 0.0), c + Vector2(13.0, 0.0), PAPER, 3.0, true)
		if dir[1] > 0.0:
			draw_line(c + Vector2(0.0, -13.0), c + Vector2(0.0, 13.0), PAPER, 3.0, true)


func _draw_audio() -> void:
	_box(Rect2(66.0, 268.0, 1468.0, 600.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	# key, title, what it covers
	var rows := [
		["master", "MASTER", "Everything you hear in the headset."],
		["music", "MUSIC", "Shakuhachi, koto and taiko under the run."],
		["sfx", "SFX", "Blades, bells, thunder. A cue plays when you change it."],
		["ambience", "AMBIENCE", "Rain, wind and the forest bed."],
	]
	for i in rows.size():
		var key: String = rows[i][0]
		var y0 := 288.0 + float(i) * 136.0
		var pct := int(VrComfortSettings.audio_percent[key]) if VrComfortSettings else 100
		_text(String(rows[i][1]), Vector2(96.0, y0 + 8.0), 30, PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
		_wrapped(String(rows[i][2]), Vector2(96.0, y0 + 50.0), 22, DIM, 740.0, 1)
		_settings_button("vol_%s_dn" % key, "", false)
		_settings_button("vol_%s_up" % key, "", false)
		_stepper_glyphs(key)
		var track := Rect2(988.0, y0 + 47.0, 236.0, 14.0)
		_box(track, LACQUER_SUNK, GILT_DIM, 1, 7)
		if pct > 0:
			_box(Rect2(track.position, Vector2(236.0 * pct / 100.0, 14.0)), SETTINGS_ACCENT, SETTINGS_ACCENT, 1, 7)
		_text("%d%%" % pct, Vector2(1336.0, y0 + 30.0), 34, PAPER, HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 600)
		if i < rows.size() - 1:
			draw_line(Vector2(96.0, y0 + 124.0), Vector2(1504.0, y0 + 124.0), GILT_DIM, 1.0, true)
	_text("Master scales every bus. Saved to user://hanabi_vr.cfg.", Vector2(96.0, 832.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1380.0)


func _draw_move() -> void:
	var vig_en := VrComfortSettings.vignette_enabled if VrComfortSettings else true
	var vig_st := VrComfortSettings.vignette_strength if VrComfortSettings else 0.50
	var snap_en := VrComfortSettings.snap_turning if VrComfortSettings else true
	var snap_deg := VrComfortSettings.snap_angle if VrComfortSettings else 45.0
	var smooth_spd := VrComfortSettings.smooth_turn_speed if VrComfortSettings else 2.0
	var walk := VrComfortSettings.walk_scale if VrComfortSettings else 1.0
	var seated := VrComfortSettings.seated_mode if VrComfortSettings else false
	var h_offset := VrComfortSettings.height_offset if VrComfortSettings else 0.0
	var weight := VrComfortSettings.body_weight_kg if VrComfortSettings else 70.0

	# Left column: vignette, then turning.
	_box(Rect2(66.0, 268.0, 714.0, 270.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	_text("動的視野制限   VIGNETTE", Vector2(90.0, 284.0), 26, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 666.0, 600)
	_text("Darkens the edges while walking or turning.", Vector2(90.0, 318.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 666.0)
	_text("VIGNETTE", Vector2(90.0, 369.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 600)
	_settings_button("vignette_on", "ENABLED", vig_en)
	_settings_button("vignette_off", "DISABLED", not vig_en)
	_text("STRENGTH", Vector2(90.0, 432.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 600)
	_settings_button("vignette_25", "25%", vig_en and absf(vig_st - 0.25) < 0.12)
	_settings_button("vignette_50", "50%", vig_en and absf(vig_st - 0.50) < 0.12)
	_settings_button("vignette_75", "75%", vig_en and absf(vig_st - 0.75) < 0.12)
	_settings_button("vignette_100", "100%", vig_en and absf(vig_st - 1.00) < 0.12)
	var bar_track := Rect2(230.0, 484.0, 476.0, 12.0)
	_box(bar_track, LACQUER_SUNK, GILT_DIM, 1, 6)
	if vig_en:
		_box(Rect2(230.0, 484.0, clampf(vig_st * 476.0, 8.0, 476.0), 12.0), SETTINGS_ACCENT, SETTINGS_ACCENT, 1, 6)

	_box(Rect2(66.0, 554.0, 714.0, 346.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	_text("視点回転方式   TURNING", Vector2(90.0, 570.0), 26, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 666.0, 600)
	_text("MODE", Vector2(90.0, 625.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 600)
	_settings_button("turn_snap", "SNAP TURN", snap_en)
	_settings_button("turn_smooth", "SMOOTH TURN", not snap_en)
	_text("ANGLE", Vector2(90.0, 696.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 600)
	for deg in [15, 30, 45, 60, 90]:
		_settings_button("snap_%d" % deg, "%d°" % deg, snap_en and absf(snap_deg - deg) < 1.0)
	_text("SPEED", Vector2(90.0, 760.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 600)
	for spd in [10, 15, 20, 30, 40]:
		_settings_button("smooth_%d" % spd, "%.1f" % (spd / 10.0), not snap_en and absf(smooth_spd - spd / 10.0) < 0.2)
	_text("Snap turning is recommended for comfort.", Vector2(90.0, 826.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 666.0)

	# Right column: walking pace, then seated mode and eye height.
	_box(Rect2(820.0, 268.0, 714.0, 270.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	_text("歩行速度   WALKING PACE", Vector2(844.0, 284.0), 26, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 666.0, 600)
	_text("Walking speed on the move stick. Slower is gentler.", Vector2(844.0, 318.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 666.0)
	_text("PACE", Vector2(844.0, 369.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 600)
	_settings_button("walk_slow", "SLOW  ×0.7", absf(walk - 0.7) < 0.05)
	_settings_button("walk_normal", "NORMAL", absf(walk - 1.0) < 0.05)
	_settings_button("walk_fast", "FAST  ×1.3", absf(walk - 1.3) < 0.05)
	_text("Ink boosts still stack on top of this pace.", Vector2(844.0, 432.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 666.0)

	_box(Rect2(820.0, 554.0, 714.0, 346.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	_text("姿勢と視点高さ   SEATED & EYE HEIGHT", Vector2(844.0, 570.0), 26, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 666.0, 600)
	_text("POSTURE", Vector2(844.0, 625.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 600)
	_settings_button("seated_off", "STANDING", not seated)
	_settings_button("seated_on", "SEATED MODE", seated)
	_text("EYE HEIGHT", Vector2(844.0, 693.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 600)
	_settings_button("height_minus", "-5 cm", false)
	var r_box := Rect2(1132.0, 680.0, 120.0, 50.0)
	_box(r_box, LACQUER_SUNK, GILT, 2, 10)
	var sign_str := "+" if h_offset >= 0.0 else ""
	_text("%s%.2f m" % [sign_str, h_offset], r_box.position + Vector2(0, 11), 24, PAPER, HORIZONTAL_ALIGNMENT_CENTER, r_box.size.x, 600)
	_settings_button("height_plus", "+5 cm", false)
	_settings_button("height_reset", "RESET", false)
	_settings_button("recenter", "◎ RECENTER HEADSET VIEW", false, Color(0.86, 0.45, 0.35))
	_text("Also hold B/Y for 0.6 s with an empty hand.", Vector2(844.0, 818.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 666.0)
	# Body weight for the kcal estimate on the wrist ring (D14).
	_text("BODY WEIGHT", Vector2(844.0, 862.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 600)
	_settings_button("weight_minus", "-5 kg", false)
	var w_box := Rect2(1132.0, 850.0, 120.0, 44.0)
	_box(w_box, LACQUER_SUNK, GILT, 2, 10)
	_text("%d kg" % roundi(weight), w_box.position + Vector2(0, 8), 24, PAPER, HORIZONTAL_ALIGNMENT_CENTER, w_box.size.x, 600)
	_settings_button("weight_plus", "+5 kg", false)


## SANDBOX page (D9): one switch. ON reads every node as unlocked; OFF gives back the run's own unlocks.
func _draw_sandbox() -> void:
	var on := VrComfortSettings.sandbox_enabled if VrComfortSettings else false
	_box(Rect2(66.0, 268.0, 1468.0, 300.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	_text("試   SANDBOX  ·  ALL SKILLS UNLOCKED", Vector2(90.0, 284.0), 26, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 1420.0, 600)
	_text("Every node of all four schools reads as unlocked, tier 5 included. Nothing is bought, no points spent.",
			Vector2(90.0, 318.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1420.0)
	_text("MODE", Vector2(90.0, 398.0), 24, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 340.0, 600)
	_settings_button("sandbox_on", "ON  ·  ALL SKILLS", on, SETTINGS_ACCENT, 26)
	_settings_button("sandbox_off", "OFF  ·  YOUR RUN", not on, SETTINGS_ACCENT, 26)
	_text("It takes effect at once, in the middle of a run too.", Vector2(460.0, 456.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1000.0)

	_box(Rect2(66.0, 584.0, 1468.0, 316.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	_text("STATUS", Vector2(90.0, 600.0), 26, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 1420.0, 600)
	if on:
		_wrapped("ON. Every node reads as unlocked (%d of %d). A sandbox run wears a SANDBOX mark on the wrist and never enters the high score."
				% [SkillTreeData.NODES.size(), SkillTreeData.NODES.size()],
				Vector2(90.0, 652.0), 24, Color(1.0, 0.7, 0.3), 1420.0)
	else:
		_wrapped("OFF. The tree shows only your own unlocks. Each node costs its points as usual.",
				Vector2(90.0, 652.0), 24, DIM, 1420.0)
	_wrapped("Your own unlocks and points come back exactly as they were when you switch it off. Points you earn in the meantime stay.",
			Vector2(90.0, 716.0), 22, DIM, 1420.0)


func _draw_access() -> void:
	var flash := VrComfortSettings.flash_percent if VrComfortSettings else 100
	var haptic := VrComfortSettings.haptic_percent if VrComfortSettings else 100

	_box(Rect2(66.0, 268.0, 1468.0, 300.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	_text("閃光の抑制   LIGHTNING & FIREWORK FLASH", Vector2(90.0, 284.0), 26, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 1420.0, 600)
	_text("The scene-wide light of lightning and the firework lamps. The bolt and the thunder stay.",
			Vector2(90.0, 318.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1420.0)
	_text("LIGHT FLASH", Vector2(90.0, 398.0), 24, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 340.0, 600)
	_settings_button("flash_100", "FULL  100 %", flash == 100, SETTINGS_ACCENT, 26)
	_settings_button("flash_50", "SOFT  50 %", flash == 50, SETTINGS_ACCENT, 26)
	_settings_button("flash_0", "OFF  0 %", flash == 0, SETTINGS_ACCENT, 26)
	_text("Choose OFF if flashes bother you. It applies from the next flash.", Vector2(460.0, 456.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1000.0)

	_box(Rect2(66.0, 584.0, 1468.0, 316.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	_text("触覚   HAPTIC STRENGTH", Vector2(90.0, 600.0), 26, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 1420.0, 600)
	_text("Vibration for hits, parries, hover pulses and the katana recall.", Vector2(90.0, 634.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1420.0)
	_text("VIBRATION", Vector2(90.0, 714.0), 24, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 340.0, 600)
	_settings_button("haptic_0", "OFF", haptic == 0, SETTINGS_ACCENT, 26)
	_settings_button("haptic_50", "HALF  50 %", haptic == 50, SETTINGS_ACCENT, 26)
	_settings_button("haptic_100", "FULL  100 %", haptic == 100, SETTINGS_ACCENT, 26)
	_settings_button("haptic_test", "▶  TEST", false, SETTINGS_ACCENT, 26)
	_text("TEST pulses the katana hand at the current strength.", Vector2(460.0, 772.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1000.0)


## The controller diagram: both controllers from the real action map, callouts
## on the outside with leader lines to each control, roles from the dominant hand.
func _draw_controls() -> void:
	var hand := String(VrComfortSettings.dominant_hand) if VrComfortSettings else "right"
	var layout := ControlsMap.layout(hand)
	var roles: Dictionary = layout.roles
	drawn_callouts.clear()
	drawn_bindings.clear()
	drawn_actions.clear()

	_text("DOMINANT HAND", Vector2(66.0, 284.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 226.0, 600)
	_settings_button("hand_right", "RIGHT  (STANDARD)", hand == "right", SETTINGS_ACCENT, 22)
	_settings_button("hand_left", "LEFT  (SOUTHPAW)", hand == "left", SETTINGS_ACCENT, 22)
	var summary: Array[String] = ControlsMap.summary(hand)
	for i in summary.size():
		_text(summary[i], Vector2(880.0, 270.0 + float(i) * 28.0), 22, PAPER if i == 0 else DIM, HORIZONTAL_ALIGNMENT_LEFT, 654.0, 600 if i == 0 else 500)

	for side in ["left", "right"]:
		var cx := 600.0 if side == "left" else 1000.0
		var sign_x := -1.0 if side == "left" else 1.0
		var tag := "KATANA HAND" if side == roles.katana else ("WRIST HUD" if side == roles.hud else "")
		_text("%s CONTROLLER" % side.to_upper(), Vector2(cx - 120.0, 332.0), 22, DIM, HORIZONTAL_ALIGNMENT_CENTER, 240.0, 600)
		_draw_controller(Vector2(cx, 585.0), sign_x, tag, side == roles.katana)
		for i in (layout.hands[side] as Array).size():
			_draw_callout(layout.hands[side][i], Vector2(cx, 585.0), i, side == "left")

	# Rules that are not tied to one button, then the inputs the game does not read.
	_text(String(layout.rules[0]), Vector2(66.0, 834.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1468.0)
	_text(String(layout.rules[1]), Vector2(66.0, 860.0), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 1468.0)
	var labels: Array[String] = []
	for g: Dictionary in layout.footnote:
		labels.append(String(g.label))
		_note_drawn(g)
	_text("Also in the map:  " + "  ·  ".join(labels), Vector2(66.0, 886.0), 22, FAINT, HORIZONTAL_ALIGNMENT_LEFT, 1468.0)


## One controller in front view (icon units; the left hand mirrors x). The
## tracking ring sits on the body, the face holds the controls, the handle
## tapers to a rounded grip and the trigger hangs at its front.
func _draw_controller(c: Vector2, sign_x: float, tag: String, is_katana: bool) -> void:
	var metal := Color(0.10, 0.095, 0.125, 1.0)
	var grip_fill := Color(0.075, 0.07, 0.095, 1.0)
	var edge := Color(GILT, 0.42)
	draw_arc(c + Vector2(0.0, -150.0), 34.0, 0.0, TAU, 56, Color(GILT, 0.30), 5.0, true)

	var handle := PackedVector2Array([c + Vector2(-58.0, 22.0), c + Vector2(58.0, 22.0)])
	for i in 9:  # right foot, from the side down to the bottom
		var a := PI * 0.5 * float(i) / 8.0
		handle.append(c + Vector2(30.0 + 20.0 * cos(a), 156.0 + 20.0 * sin(a)))
	for i in 9:  # left foot, from the bottom to the side
		var a := PI * 0.5 + PI * 0.5 * float(i) / 8.0
		handle.append(c + Vector2(-30.0 + 20.0 * cos(a), 156.0 + 20.0 * sin(a)))
	draw_colored_polygon(handle, grip_fill)
	draw_polyline(handle + PackedVector2Array([handle[0]]), edge, 1.5, true)

	var face := _rounded_points(Rect2(c.x - 112.0, c.y - 115.0, 224.0, 145.0), 34.0)
	draw_colored_polygon(face, metal)
	draw_polyline(face + PackedVector2Array([face[0]]), Color(GILT, 0.5), 2.0, true)
	_box(Rect2(c.x - 54.0, c.y + 121.0, 108.0, 18.0), Color(0, 0, 0, 0), Color(GILT, 0.30), 1, 9)

	var at := func(slot: String) -> Vector2:
		var a: Vector2 = ControlsMap.ANCHORS[slot]
		return c + Vector2(a.x * sign_x, a.y)
	var trig: Vector2 = at.call("trigger")
	_box(Rect2(trig - Vector2(13.0, 28.0), Vector2(26.0, 56.0)), LACQUER_SUNK, Color(GILT, 0.6), 1, 10)
	var stick: Vector2 = at.call("stick")
	draw_circle(stick, 30.0, Color(0.16, 0.15, 0.20, 1.0))
	draw_arc(stick, 30.0, 0.0, TAU, 40, GILT_DIM, 2.0, true)
	draw_arc(stick, 15.0, 0.0, TAU, 28, GILT_DIM, 1.0, true)
	for slot in ["face_top", "face_bottom"]:
		var p: Vector2 = at.call(slot)
		draw_circle(p, 14.0, Color(0.16, 0.15, 0.20, 1.0))
		draw_arc(p, 14.0, 0.0, TAU, 28, GILT_DIM, 1.5, true)
	var top: Vector2 = at.call("top_button")
	draw_arc(top, 10.0, 0.0, TAU, 24, Color(GILT, 0.7), 2.0, true)

	if tag != "":
		var pill := Rect2(c.x - 88.0, c.y - 217.0, 176.0, 26.0)
		var pill_col := SETTINGS_ACCENT if is_katana else DIM
		_box(pill, LACQUER_SUNK, Color(pill_col, 0.8), 1, 13)
		_text(tag, pill.position + Vector2(0, 1), 20, Color(pill_col, 0.95) if is_katana else DIM, HORIZONTAL_ALIGNMENT_CENTER, pill.size.x, 600)


## Corner-rounded outline of [param rect] as a closed polygon (clockwise on screen).
static func _rounded_points(rect: Rect2, radius: float, steps := 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [
		[rect.end - Vector2(radius, radius), 0.0],
		[Vector2(rect.position.x + radius, rect.end.y - radius), PI * 0.5],
		[rect.position + Vector2(radius, radius), PI],
		[Vector2(rect.end.x - radius, rect.position.y + radius), PI * 1.5],
	]
	for corner in corners:
		for i in steps + 1:
			var a: float = corner[1] + PI * 0.5 * float(i) / float(steps)
			out.append((corner[0] as Vector2) + Vector2(cos(a), sin(a)) * radius)
	return out


## A callout: title and body beside the controller, with a leader to its control.
func _draw_callout(c: Dictionary, origin: Vector2, index: int, is_left: bool) -> void:
	_note_drawn(c)
	var y := 344.0 + float(index) * 80.0
	var anchor: Vector2 = c.anchor
	var point := origin + anchor
	var col := Color(DIM, 0.9) if c.system else GILT
	var title_col := DIM if c.system else PAPER
	var leader_x := 416.0 if is_left else 1118.0
	var leader_y := y + 14.0
	draw_line(Vector2(leader_x, leader_y), point, Color(GILT, 0.45), 1.5, true)
	draw_circle(point, 4.5, col)
	if is_left:
		_text(String(c.title), Vector2(52.0, y), 26, title_col, HORIZONTAL_ALIGNMENT_RIGHT, 356.0, 600)
		_wrapped(String(c.body), Vector2(52.0, y + 30.0), 23, DIM, 356.0, 2, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_text(String(c.title), Vector2(1126.0, y), 26, title_col, HORIZONTAL_ALIGNMENT_LEFT, 408.0, 600)
		_wrapped(String(c.body), Vector2(1126.0, y + 30.0), 23, DIM, 408.0, 2, HORIZONTAL_ALIGNMENT_LEFT)


func _note_drawn(item: Dictionary) -> void:
	for b in item.bindings:
		if not drawn_bindings.has(String(b)):
			drawn_bindings.append(String(b))
	for a in item.actions:
		if not drawn_actions.has(String(a)):
			drawn_actions.append(String(a))
	if item.has("slot"):
		drawn_callouts.append({"side": item.side, "slot": item.slot, "title": item.title, "body": item.body})


func _draw_ai() -> void:
	_box(Rect2(66.0, 268.0, 1468.0, 600.0), LACQUER_RAISED, GILT_DIM, 2, 16)
	_text("META AI COMBAT INTELLIGENCE", Vector2(100.0, 296.0), 30, PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
	_wrapped("Oni Warlord dynamic tactical brain powered by Meta Model API (Muse Spark / Llama).", Vector2(100.0, 336.0), 22, DIM, 1400.0, 1)

	var active := VrComfortSettings.ai_boss_enabled if VrComfortSettings else true
	var key := VrComfortSettings.get_effective_meta_api_key() if VrComfortSettings else ""
	var masked := VrComfortSettings.get_masked_api_key() if VrComfortSettings else ""
	var lang := VrComfortSettings.ai_language if VrComfortSettings else "pl"

	_settings_button("ai_toggle", "AI BOSS: " + ("WŁĄCZONY" if active else "WYŁĄCZONY"), active)
	_settings_button("ai_key_paste", "WKLEJ KLUCZ (SCHOWEK)", false)
	_settings_button("ai_key_clear", "USUŃ KLUCZ", false)
	_settings_button("ai_lang_pl", "JĘZYK: PL", lang == "pl")
	_settings_button("ai_lang_en", "LANG: EN", lang == "en")

	var card_rect := Rect2(100.0, 460.0, 1400.0, 370.0)
	_box(card_rect, LACQUER_SUNK, GILT_DIM, 1, 12)

	_text("STATUS I KONFIGURACJA MODELU", Vector2(130.0, 485.0), 26, PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)

	var status_text := ""
	var status_col := GILT
	if not active:
		status_text = "STATUS: WYŁĄCZONY (Boss używa wyłącznie lokalnej sztucznej inteligencji)"
		status_col = DIM
	elif key != "":
		status_text = "STATUS: AKTYWNY (Połączono z Meta Model API: muse-spark-1.3)"
		status_col = Color(0.35, 0.95, 0.45)
	else:
		status_text = "STATUS: BRAK KLUCZA (Automatyczny lokalny fallback - walka rule-based działa w 100%)"
		status_col = Color(0.95, 0.65, 0.25)

	_text(status_text, Vector2(130.0, 528.0), 22, status_col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)

	var key_display := ("KLUCZ API META: " + masked) if key != "" else "KLUCZ API META: [NIE SKONFIGUROWANO]"
	_text(key_display, Vector2(130.0, 568.0), 22, PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)

	_text("DOSTAWCA: Meta Model API | MODEL: muse-spark-1.3 | ENDPOINT: https://api.meta.ai/v1", Vector2(130.0, 608.0), 20, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)

	var help1 := "Kolejność odczytu: 1. Ustawienia gry (user://), 2. Plik secrets/meta_api_key.txt, 3. Lokalny fallback."
	var help2 := "Brak sieci, błąd lub timeout (>3s) NIGDY nie zawiesza gry - boss natychmiast walczy lokalnym FSM."
	var help3 := "Klucz jest bezpiecznie maskowany i nigdy nie trafia do repozytorium ani logów zdarzeń."
	_wrapped(help1, Vector2(130.0, 655.0), 20, DIM, 1340.0, 1)
	_wrapped(help2, Vector2(130.0, 690.0), 20, DIM, 1340.0, 1)
	_wrapped(help3, Vector2(130.0, 725.0), 20, DIM, 1340.0, 1)
