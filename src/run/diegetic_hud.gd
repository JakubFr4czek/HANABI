class_name DiegeticHud
extends Node3D
## Wrist readout (docs/GDD.md §6, §15; D14, F1). On the back of the left wrist, a plain
## column of Latin rows, each a label, a value and, where it has one, a bar or pips:
## - HP: a bar (teal -> amber -> red, pulsing when critical) and the current / max;
## - KCAL: the estimate from [CalorieMeter] as a bar (full at KCAL_BAR_FULL) and a figure;
## - ŁADUNKI: the charges held (D21) as pips in their element's colour, oldest first; while an
##   element is imbued, its seconds left in the element's colour beside them;
## - CZAS: the run time, mm:ss. A level-up flashes here for a moment (LV n, +1 PT).
## Further rows (STAMINA, DUSZE) are added with [method set_row] and sit under the last one.
## No panel, no frame behind them, and no japanese glyphs: the wrist is Latin only (F1).
## It is drawn only while the wrist is raised to the face (the check-the-watch
## gesture: close, forearm level, face turned to the eyes, in view), with hysteresis and
## a short fade. A hand held upright with its back to the eyes does not show it. Hidden, its subtree is hidden, so it costs no draw calls. On desktop the
## same readout is held on H. Nothing is drawn on the katana, and the text sits on the
## forearm side of the back of the wrist, where the hand mesh falls away (wrist_hud_test).

const HUD_FONT_PATH := "res://assets/fonts/YujiBoku-Regular.ttf"

## The plate (metres): the readout's frame, the lean compensation and the SANDBOX corner.
const PLATE_SIZE := Vector2(0.06, 0.06)
## Readout origin in the controller frame: on the back of the wrist, just past the palm.
## Text up is -Z (toward the hand); the rows run toward the elbow (+Z).
const RING_OFFSET := Vector3(0.0, 0.064, 0.098)
const LABEL_Y := 0.0021

## The column (plate frame, z = plate depth). Row i's top edge sits at ROW_TOP + i * ROW_PITCH.
const PANEL_HALF_WIDTH := 0.026
const ROW_TOP := -0.0215
const ROW_PITCH := 0.0185
const ROW_LABEL_DOWN := 0.0050
const ROW_BAR_DOWN := 0.0125
const BAR_HEIGHT := 0.0034
const PIP_SIZE := 0.0046
const PIP_PITCH := 0.0062
## Dark backing plate under the rows (F1 rev.): text reads on any ground. Its margin around the text.
const PLATE_PAD := 0.0055
const PLATE_COLOR := Color(0.035, 0.04, 0.07, 0.72)
const LABEL_FONT := 31
const VALUE_FONT := 39
const SANDBOX_FONT := 18
const GUARD_FONT := 22

const TEAL := Color(0.36, 0.84, 0.72)
const AMBER := Color(0.98, 0.64, 0.24)
const RED := Color(0.95, 0.2, 0.16)
const HP_WARN_RATIO := 0.5
const HP_CRITICAL_RATIO := 0.25
const TRACK_COLOR := Color(0.08, 0.08, 0.1, 0.55)
const CHARGE_EMPTY_COLOR := Color(0.3, 0.3, 0.34)
const LABEL_COLOR := Color(0.96, 0.93, 0.84)
const VALUE_COLOR := Color(1.0, 1.0, 1.0)
const KCAL_BAR_COLOR := Color(0.98, 0.84, 0.52)
## The kcal bar fills at this estimate (kcal): a bar for a whole run, not a goal.
const KCAL_BAR_FULL := 100.0
const SANDBOX_COLOR := Color(1.0, 0.7, 0.3)
const PARRY_GLOW_SECONDS := 0.42
const LEVEL_TEXT_SECONDS := 1.5

## Show and hide limits: the wrist to the eyes (m), the angle between the readout's
## face and the eyes (deg), the forearm's lift above level (deg), and the fade time (s).
## Hiding needs the wider limits.
const SHOW_DIST := 0.35
const HIDE_DIST := 0.42
const SHOW_ANGLE_DEG := 45.0
const HIDE_ANGLE_DEG := 55.0
## The forearm lies level when the watch is checked; an upright hand does not show it (P9).
const SHOW_FOREARM_DEG := 35.0
const HIDE_FOREARM_DEG := 50.0
const FADE_SECONDS := 0.15
## Desktop: where the readout hangs in front of the camera while H is held.
const DESKTOP_OFFSET := Vector3(-0.16, -0.14, -0.30)

const MAX_FACE_TILT_DEG := 10.0

var wrist_unit: Node3D
var wrist_face: Node3D
var _font: Font
## The SANDBOX mark (D9), in the plate's top-left corner, clear of the rows.
var sandbox_label: Label3D
var _sandbox_run := false
## Debug builds: a small red count of RuntimeGuard violations on the plate.
var guard_label: Label3D

## The rows by key, in the order they were added (top to bottom).
var _rows := {}
var _row_keys: Array[String] = []
var _labels: Array[Label3D] = []
## Every bar and pip material, with its resting alpha: the fade scales the alpha.
var _mat_alpha := {}
var _bars: Array[MeshInstance3D] = []
var _plate: MeshInstance3D

var _presence := 0.0
var _raised := false
var _follow_eyes := false
var _bound_player: Node3D = null
var _view_camera: Camera3D
var _elements: ElementSystem
var _calories: CalorieMeter
var _parry_glow := 0.0
var _level_text_left := 0.0
var _level_text := ""
var _level_label := ""
var _hp := 100.0
var _max_hp := 100.0
var _hp_colour := TEAL
## HP at or under a quarter: the bar pulses.
var hp_critical := false
var _run_seconds := 0.0
## The charges held (D21), oldest first, as the pips show them. Set from charges_changed.
var _charges: Array[String] = []
## Whether the imbued element is in its last seconds (its seconds beat).
var _element_warn := false
## Real seconds since the HUD started; drives the beats (shaders have TIME, scripts do not).
var _clock := 0.0


static func hp_color(ratio: float) -> Color:
	if ratio >= HP_WARN_RATIO:
		return AMBER.lerp(TEAL, clampf((ratio - HP_WARN_RATIO) / (1.0 - HP_WARN_RATIO), 0.0, 1.0))
	if ratio >= HP_CRITICAL_RATIO:
		return RED.lerp(AMBER, clampf((ratio - HP_CRITICAL_RATIO) / (HP_WARN_RATIO - HP_CRITICAL_RATIO), 0.0, 1.0))
	return RED


func setup(player: Node3D, _katana: HeldWeapon) -> void:
	_bound_player = player
	if player:
		for layer in player.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
	_view_camera = _resolve_view_camera(player)

	_setup_wrist_unit(player)
	update_hud(100.0, 100.0, 0, 30, 1, 1, 0, 0, 0.0, Elements.NONE)
	if VrComfortSettings and not VrComfortSettings.settings_changed.is_connected(_on_comfort_settings_changed):
		VrComfortSettings.settings_changed.connect(_on_comfort_settings_changed)


func _resolve_view_camera(player: Node3D) -> Camera3D:
	if player is DesktopPlayer:
		return (player as DesktopPlayer).camera
	if player is XRPlayer:
		var xr := player as XRPlayer
		if xr.get_viewport() and xr.get_viewport().get_camera_3d():
			return xr.get_viewport().get_camera_3d()
	return get_viewport().get_camera_3d() if get_viewport() else null


func _setup_wrist_unit(player: Node3D) -> void:
	if player == null:
		return
	wrist_unit = Node3D.new()
	wrist_unit.name = "DiegeticWristUnit"
	wrist_face = Node3D.new()
	wrist_face.name = "WristFace"
	wrist_face.visible = false
	wrist_unit.add_child(wrist_face)

	# Figures in Godot's built-in sans (the brush font's "1" reads as "7"); the bundled
	# brush font is only the fallback for glyphs the sans lacks.
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	if ResourceLoader.exists(HUD_FONT_PATH):
		font.fallbacks = [load(HUD_FONT_PATH)]
	font.variation_embolden = 0.35
	_font = font

	_plate = _quad("ReadoutPlate", Vector3.ZERO, Vector2(1.0, 1.0), PLATE_COLOR)
	(_plate.material_override as StandardMaterial3D).render_priority = 1
	wrist_face.add_child(_plate)
	_bars.append(_plate)
	_plate.visible = true

	# The four rows of F1, in reading order. F6 (stamina) and F7 (souls) add theirs with set_row.
	_add_row("hp", "HP")
	_add_row("kcal", "KCAL")
	_add_row("charges", "ŁADUNKI")
	_add_row("time", "CZAS")

	sandbox_label = _make_label("SandboxLabel", font, SANDBOX_FONT, Vector3(-PLATE_SIZE.x * 0.5 + 0.002, LABEL_Y, -PLATE_SIZE.y * 0.5 + 0.0038))
	sandbox_label.text = "SANDBOX"
	sandbox_label.modulate = SANDBOX_COLOR
	sandbox_label.visible = false
	wrist_face.add_child(sandbox_label)
	_labels.append(sandbox_label)

	if RuntimeGuard.enabled:
		guard_label = _make_label("GuardLabel", font, GUARD_FONT, Vector3(PLATE_SIZE.x * 0.5 - 0.006, LABEL_Y, -PLATE_SIZE.y * 0.5 + 0.006))
		guard_label.modulate = Color(1.0, 0.25, 0.2)
		guard_label.visible = false
		wrist_face.add_child(guard_label)
		_labels.append(guard_label)

	if player is XRPlayer:
		var xr := player as XRPlayer
		var offhand: XRController3D = xr.get_offhand_controller() if xr.has_method("get_offhand_controller") else xr.left_controller
		offhand.add_child(wrist_unit)
		# Back of the wrist, rolled a little toward the thumb so a
		# "check the watch" turn of the forearm shows it to the eyes.
		var is_right := (offhand == xr.right_controller)
		wrist_unit.position = RING_OFFSET
		wrist_unit.rotation = Vector3(deg_to_rad(6.0), 0.0, deg_to_rad(14.0 if is_right else -14.0))
		_follow_eyes = true
	elif player is DesktopPlayer:
		var dp := player as DesktopPlayer
		dp.set_screen_hud_visible(false)
		# The sword hand is the right. The readout hangs on the camera's left, so a
		# slash does not whip it out of view.
		dp.camera.add_child(wrist_unit)
		wrist_unit.position = DESKTOP_OFFSET
		# Pinned to the camera: face it once, squarely, text upright.
		var to_cam := -DESKTOP_OFFSET.normalized()
		var x_axis := Vector3.RIGHT.slide(to_cam).normalized()
		wrist_unit.basis = Basis(x_axis, to_cam, x_axis.cross(to_cam).normalized())
	else:
		player.add_child(wrist_unit)


## The top edge of row [param index] in the plate frame (z; negative is toward the hand).
static func row_top(index: int) -> float:
	return ROW_TOP + float(index) * ROW_PITCH


## Adds a row to the readout (F1 API). A row is a label on the left and a value on the right,
## with a bar under them when [param ratio] is 0..1, or pips when [param pips] is given.
## [method set_row] creates a row the first time its key is used, so F6 and F7 only call it.
func set_row(key: String, label_text: String, value_text: String, ratio: float = -1.0,
		colour: Color = TEAL, pips: Array[Color] = [], value_colour: Color = VALUE_COLOR) -> void:
	var row: Dictionary = _rows.get(key, {})
	if row.is_empty():
		row = _add_row(key, label_text)
	_set_text(row.label, label_text)
	_set_text(row.value, value_text)
	row.value.modulate = value_colour
	var has_pips := not pips.is_empty()
	# With pips the value sits on the pips' line, right of them; otherwise on the label's line.
	row.value.position.z = row_top(int(row.index)) + (ROW_BAR_DOWN if has_pips else ROW_LABEL_DOWN)
	var has_bar := ratio >= 0.0 and not has_pips
	row.track.visible = has_bar
	row.fill.visible = has_bar and ratio > 0.0
	if has_bar:
		var share := clampf(ratio, 0.0001, 1.0)
		row.fill.scale.x = share
		row.fill.position.x = -PANEL_HALF_WIDTH + share * PANEL_HALF_WIDTH
		_paint(row.fill_mat, colour)
	for i in row.pips.size():
		var pip: MeshInstance3D = row.pips[i]
		pip.visible = has_pips and i < pips.size()
		if pip.visible:
			_paint(row.pip_mats[i], pips[i] if pips[i].a > 0.5 else CHARGE_EMPTY_COLOR)
	_rows[key] = row
	if not _row_keys.has(key):
		_row_keys.append(key)


## The row's value text, or "" for an unknown key (tests and the F6/F7 readers).
func row_value(key: String) -> String:
	var row: Dictionary = _rows.get(key, {})
	return "" if row.is_empty() else (row.value as Label3D).text


## The row's label text, or "" for an unknown key.
func row_label(key: String) -> String:
	var row: Dictionary = _rows.get(key, {})
	return "" if row.is_empty() else (row.label as Label3D).text


## The bar's share in 0..1 (0 when the row has no bar or is unknown).
func row_fill(key: String) -> float:
	var row: Dictionary = _rows.get(key, {})
	if row.is_empty() or not (row.fill as MeshInstance3D).visible:
		return 0.0
	return (row.fill as MeshInstance3D).scale.x


## The row's label and value nodes, for the contrast and layout checks.
func row_labels(key: String) -> Array[Label3D]:
	var row: Dictionary = _rows.get(key, {})
	if row.is_empty():
		return []
	return [row.label, row.value]


## The row keys in the order they sit on the readout, top to bottom.
func row_keys() -> Array[String]:
	return _row_keys.duplicate()


## One row: its label and value and its bar and pips, as nodes.
func _add_row(key: String, label_text: String) -> Dictionary:
	var index := _row_keys.size()
	var top := row_top(index)
	var row := {"index": index}
	row.label = _make_label("%sLabel" % key.capitalize(), _font, LABEL_FONT, Vector3(-PANEL_HALF_WIDTH, LABEL_Y, top + ROW_LABEL_DOWN))
	(row.label as Label3D).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	(row.label as Label3D).modulate = LABEL_COLOR
	(row.label as Label3D).text = label_text
	row.value = _make_label("%sValue" % key.capitalize(), _font, VALUE_FONT, Vector3(PANEL_HALF_WIDTH, LABEL_Y, top + ROW_LABEL_DOWN))
	(row.value as Label3D).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bar_z := top + ROW_BAR_DOWN
	row.track = _quad("%sTrack" % key.capitalize(), Vector3(0.0, LABEL_Y, bar_z), Vector2(PANEL_HALF_WIDTH * 2.0, BAR_HEIGHT), TRACK_COLOR)
	row.fill = _quad("%sFill" % key.capitalize(), Vector3(0.0, LABEL_Y, bar_z), Vector2(PANEL_HALF_WIDTH * 2.0, BAR_HEIGHT), TEAL)
	row.fill_mat = (row.fill as MeshInstance3D).material_override
	row.pips = []
	row.pip_mats = []
	for i in ElementSystem.MAX_CHARGES:
		var at := Vector3(-PANEL_HALF_WIDTH + PIP_SIZE * 0.5 + float(i) * PIP_PITCH, LABEL_Y, bar_z)
		var pip := _quad("%sPip%d" % [key.capitalize(), i], at, Vector2(PIP_SIZE, PIP_SIZE), CHARGE_EMPTY_COLOR)
		row.pips.append(pip)
		row.pip_mats.append(pip.material_override)
	for l in [row.label, row.value]:
		wrist_face.add_child(l)
		_labels.append(l)
		l.visible = false
	for m in [row.track, row.fill] + row.pips:
		wrist_face.add_child(m)
		_bars.append(m)
		m.visible = false
	_rows[key] = row
	_row_keys.append(key)
	_fit_plate()
	return row


## The backing plate covers the column: from the top row's top edge to the bottom of the last bar, padded.
func _fit_plate() -> void:
	if _plate == null:
		return
	var top := ROW_TOP - PLATE_PAD
	var bottom := row_top(_row_keys.size() - 1) + ROW_BAR_DOWN + BAR_HEIGHT * 0.5 + PLATE_PAD
	(_plate.mesh as QuadMesh).size = Vector2(PANEL_HALF_WIDTH * 2.0 + PLATE_PAD * 2.0, bottom - top)
	_plate.position = Vector3(0.0, LABEL_Y - 0.0004, (top + bottom) * 0.5)


## A flat bar or pip, lying on the plate like the labels, unshaded and faded with the readout.
func _quad(node_name: String, at: Vector3, size: Vector2, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = colour
	mat.render_priority = 2
	mi.material_override = mat
	mi.position = at
	mi.rotation.x = -PI * 0.5
	_no_shadow(mi)
	_mat_alpha[mat] = colour.a
	return mi


## Sets a bar or pip colour (its alpha is the fade, set each frame).
func _paint(mat: StandardMaterial3D, rgb: Color) -> void:
	var c := mat.albedo_color
	if c.r == rgb.r and c.g == rgb.g and c.b == rgb.b:
		return
	mat.albedo_color = Color(rgb.r, rgb.g, rgb.b, c.a)


func _no_shadow(mi: GeometryInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _make_label(node_name: String, font: Font, size: int, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.font = font
	l.font_size = size
	l.pixel_size = 0.00026
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.shaded = false
	l.double_sided = false
	l.outline_size = 14
	l.outline_modulate = Color(0.03, 0.02, 0.02, 0.95)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.modulate = Color(0.95, 0.92, 0.85, 0.98)
	# Text up is -Z on the plate; glyphs float just over the bars and keep
	# the depth test, so the hand still occludes them.
	l.position = at
	l.rotation.x = -PI * 0.5
	l.visible = false
	return l


func _process(delta: float) -> void:
	if wrist_unit == null:
		return
	_clock += delta
	_parry_glow = maxf(_parry_glow - delta, 0.0)
	var was_flashing := _level_text_left > 0.0
	_level_text_left = maxf(_level_text_left - delta, 0.0)
	if was_flashing and _level_text_left <= 0.0:
		_level_label = ""
	_orient_wrist_face(delta)

	var was_raised := _raised
	_raised = _gesture_held()
	if not was_raised and _raised:
		_trigger_wrist_haptic()
	_presence = move_toward(_presence, 1.0 if _raised else 0.0, delta / FADE_SECONDS)
	# The state is kept current even while hidden, so a raised wrist shows the right
	# figures at once; only the drawing (the subtree's visibility) follows the gesture.
	_refresh_rows()
	wrist_face.visible = _presence > 0.0
	if wrist_face.visible:
		_fade_plate()
	for label in _labels:
		label.visible = _presence > 0.02 and label.text != ""
		label.modulate.a = 0.98 * _presence
		label.outline_modulate.a = 0.95 * _presence
	if sandbox_label:
		sandbox_label.visible = _sandbox_run and _presence > 0.02
		sandbox_label.modulate.a = 0.98 * _presence
	if guard_label:
		var n := RuntimeGuard.violation_count()
		guard_label.visible = n > 0
		if n > 0:
			guard_label.text = "! %d" % n


## Every bar and pip takes the readout's fade in its alpha; the HP bar also breathes when critical
## and brightens on a parry.
func _fade_plate() -> void:
	if hp_critical or _parry_glow > 0.0:
		var hp_row: Dictionary = _rows.get("hp", {})
		if not hp_row.is_empty():
			var beat := 0.55 + 0.45 * (0.5 + 0.5 * sin(_clock * 6.0)) if hp_critical else 1.0
			var glow := clampf(_parry_glow / PARRY_GLOW_SECONDS, 0.0, 1.0) * 0.6
			var rgb := _hp_colour * beat
			rgb = rgb.lerp(Color.WHITE, glow)
			var fill_mat: StandardMaterial3D = hp_row.fill_mat
			fill_mat.albedo_color = Color(rgb.r, rgb.g, rgb.b, fill_mat.albedo_color.a)
	for mi in _bars:
		var mat := mi.material_override as StandardMaterial3D
		var c := mat.albedo_color
		var a: float = _mat_alpha[mat] * _presence
		if absf(c.a - a) > 0.001:
			mat.albedo_color = Color(c.r, c.g, c.b, a)


func _trigger_wrist_haptic() -> void:
	if wrist_unit == null:
		return
	var ctrl := wrist_unit.get_parent() as XRController3D
	if ctrl and VrComfortSettings:
		var amp := VrComfortSettings.haptic_amplitude(0.22)
		if amp > 0.0:
			ctrl.trigger_haptic_pulse("haptic", 0.0, amp, 0.04, 0.0)


## The check-the-watch gesture (XR): the wrist close to the eyes, its forearm level, its face
## turned to them and in view, with hysteresis so it does not flicker at the edge.
## Desktop: H held.
func _gesture_held() -> bool:
	if _bound_player is DesktopPlayer:
		return (_bound_player as DesktopPlayer).wrist_check
	var cam := _camera()
	if cam == null or wrist_unit == null or not wrist_unit.is_inside_tree():
		return false
	var anchor := wrist_unit.global_position
	var to_eye := cam.global_position - anchor
	var d := to_eye.length()
	if d < 0.0001:
		return false
	var near_limit := HIDE_DIST if _raised else SHOW_DIST
	var face_limit := HIDE_ANGLE_DEG if _raised else SHOW_ANGLE_DEG
	var forearm_limit := HIDE_FOREARM_DEG if _raised else SHOW_FOREARM_DEG
	var face_deg := rad_to_deg(wrist_unit.global_basis.y.angle_to(to_eye / d))
	# The forearm runs along the wrist's +Z (toward the elbow). Its lift is the angle it makes
	# with level, whichever way it points, so a hand held up or down reads the same.
	var forearm_deg := rad_to_deg(asin(clampf(absf(wrist_unit.global_basis.z.y), 0.0, 1.0)))
	return d < near_limit and face_deg < face_limit and forearm_deg < forearm_limit and cam.is_position_in_frustum(anchor)


func _camera() -> Camera3D:
	if _view_camera and is_instance_valid(_view_camera):
		return _view_camera
	return get_viewport().get_camera_3d() if get_viewport() else null


## Pushes the rows' values from the state held here: HP, kcal, the charges and the imbue,
## the run time (or the level-up flash). Text is only written when it changed.
func _refresh_rows() -> void:
	if _rows.is_empty():
		return
	var hp_ratio := clampf(_hp / maxf(_max_hp, 1.0), 0.0, 1.0)
	_hp_colour = hp_color(hp_ratio)
	hp_critical = hp_ratio < HP_CRITICAL_RATIO
	set_row("hp", "HP", "%d / %d" % [ceili(_hp), ceili(_max_hp)], hp_ratio, _hp_colour)

	var kcal := 0.0 if _calories == null else _calories.kcal
	set_row("kcal", "KCAL", str(floori(kcal)), clampf(kcal / KCAL_BAR_FULL, 0.0, 1.0), KCAL_BAR_COLOR)

	var pips: Array[Color] = []
	for i in ElementSystem.MAX_CHARGES:
		pips.append(_charge_slot(i))
	var element_value := ""
	var element_colour := VALUE_COLOR
	var es := _elements if _elements and is_instance_valid(_elements) else null
	_element_warn = es != null and es.current_element != Elements.NONE and es.is_fade_warning
	if es and es.current_element != Elements.NONE:
		var tint := Elements.accent_color(es.current_element).lightened(0.35)
		# The last seconds of an imbue beat, like the blade and the element arc do.
		var beat := 0.35 + 0.65 * (0.5 + 0.5 * sin(_clock * 18.8496)) if _element_warn else 1.0
		element_colour = Color(tint * beat, 1.0)
		element_value = "%d s" % ceili(es.element_time_remaining)
	set_row("charges", "ŁADUNKI", element_value, -1.0, VALUE_COLOR, pips, element_colour)

	if _level_text_left > 0.0:
		var no_pips: Array[Color] = []
		set_row("time", _level_label, _level_text, -1.0, VALUE_COLOR, no_pips, KCAL_BAR_COLOR)
	else:
		set_row("time", "CZAS", _clock_text(_run_seconds))


## mm:ss for the run time.
static func _clock_text(seconds: float) -> String:
	var total := maxi(floori(seconds), 0)
	return "%02d:%02d" % [total / 60, total % 60]


func _set_text(label: Label3D, value: String) -> void:
	if label.text != value:
		label.text = value


## Shows or hides the SANDBOX mark (D9): true for a run that used the sandbox.
func set_sandbox_run(on: bool) -> void:
	_sandbox_run = on


func on_parry() -> void:
	_parry_glow = PARRY_GLOW_SECONDS


## The charge slots as the shader-free pips take them: the element's colour with alpha 1 when
## filled, alpha 0 when empty; oldest first.
func charge_slots() -> Array[Color]:
	var out: Array[Color] = []
	for i in ElementSystem.MAX_CHARGES:
		out.append(_charge_slot(i))
	return out


## One pip's value: its element's colour, and alpha as the fill (1 charged, 0 empty).
func _charge_slot(index: int) -> Color:
	if index < _charges.size():
		var accent := Elements.accent_color(_charges[index])
		return Color(accent.r, accent.g, accent.b, 1.0)
	return Color(CHARGE_EMPTY_COLOR, 0.0)


## A level-up (D12): a short flash of the time row, which reads LV n and +1 PT for a moment.
func flash_level_up(new_level: int) -> void:
	_level_label = "LV %d" % new_level
	_level_text = "+1 PT"
	_level_text_left = LEVEL_TEXT_SECONDS


func update_wrist_attachment(player: Node3D) -> void:
	if player is XRPlayer and wrist_unit:
		var xr := player as XRPlayer
		var offhand: XRController3D = xr.get_offhand_controller() if xr.has_method("get_offhand_controller") else xr.left_controller
		if wrist_unit.get_parent() != offhand and offhand != null:
			wrist_unit.reparent(offhand)
			var is_right := (offhand == xr.right_controller)
			wrist_unit.position = RING_OFFSET
			wrist_unit.rotation = Vector3(deg_to_rad(6.0), 0.0, deg_to_rad(14.0 if is_right else -14.0))


func _on_comfort_settings_changed() -> void:
	if _bound_player:
		update_wrist_attachment(_bound_player)


## Hands the HUD the element system it mirrors (called once by RunGame). The charge pips
## follow its charges_changed signal, so they change the moment a charge is taken or spent.
func bind_elements(es: ElementSystem) -> void:
	_elements = es
	if not es.charges_changed.is_connected(_on_charges_changed):
		es.charges_changed.connect(_on_charges_changed)
	_on_charges_changed(es.get_charges())


## The pips take the charges' colours, oldest first; the slots past the last charge are empty.
func _on_charges_changed(charges: Array[String]) -> void:
	_charges = charges.duplicate()


## Hands the HUD the calorie meter it shows (called once by RunGame).
func bind_calories(meter: CalorieMeter) -> void:
	_calories = meter


func _orient_wrist_face(delta: float) -> void:
	if not _follow_eyes or wrist_face == null or wrist_unit == null:
		return
	var cam := _camera()
	if cam == null:
		return
	var wrist := wrist_unit.global_basis.orthonormalized()
	var to_cam := (cam.global_position - wrist_unit.global_position)
	if to_cam.length_squared() < 1e-6:
		return
	var local_dir := (wrist.inverse() * to_cam.normalized())
	var tilt := Quaternion.IDENTITY
	if local_dir.y > 0.05:
		var angle := minf(Vector3.UP.angle_to(local_dir), deg_to_rad(MAX_FACE_TILT_DEG))
		var axis := Vector3.UP.cross(local_dir)
		if axis.length_squared() > 1e-8:
			tilt = Quaternion(axis.normalized(), angle)
	var current := wrist_face.quaternion
	wrist_face.quaternion = current.slerp(tilt, clampf(delta * 10.0, 0.0, 1.0))
	# Leaning the plate drops its far edge toward the hand by
	# sin(angle)·half-width; lift the face by the same amount so the edge
	# never dips below the untilted plane into the hand mesh.
	var lean := wrist_face.quaternion.get_angle()
	wrist_face.position.y = sin(lean) * PLATE_SIZE.x * 0.57


## The state of the readout, from the run (RunGame calls this every tick).
func update_hud(hp: float, max_hp: float, xp: int, xp_to_next: int, level: int, wave: int, score: int, kills: int, run_seconds: float, active_element: String, points: int = 0, buff_text: String = "") -> void:
	_hp = hp
	_max_hp = max_hp
	_run_seconds = run_seconds
	_refresh_rows()
