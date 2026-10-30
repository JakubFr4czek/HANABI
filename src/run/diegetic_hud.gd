class_name DiegeticHud
extends Node3D
## Wrist readout (docs/GDD.md §6, §15; D14). On the back of the left wrist:
## - a transparent HP ring: its length is the health share, its colour runs teal
##   (full) -> amber (half) -> red (a quarter and below), and it breathes gently
##   when critical. No panel, no frame behind it;
## - inside the ring, the white kcal estimate ([CalorieMeter]) over a clear centre;
## - outside the ring, a hairline for the time left on the imbued element;
## - over the ring's top-right, three charge orbs (D21, D22): an empty orb is a grey
##   outline, a filled one takes its element's colour. Oldest charge first;
## - under the ring: the element and its seconds, the two ability glyphs (bright
##   when ready) and the run line (rank, kills, points, XP, buffs).
## It is drawn only while the wrist is raised to the face (the check-the-watch
## gesture: close, face turned to the eyes, in view), with hysteresis and a short
## fade. Hidden, its subtree is hidden, so it costs no draw calls. On desktop the
## same readout is held on H. Nothing is drawn on the katana, and the text sits on the
## forearm side of the ring, where the hand mesh falls away (wrist_hud_test).

const RING_SHADER := preload("res://src/shaders/wrist_ring.gdshader")
## Bundled font: the system fonts the plate used before do not exist on Quest.
const HUD_FONT_PATH := "res://assets/fonts/YujiBoku-Regular.ttf"

## The quad the ring is drawn on (metres). The ring and its arcs stay inside it.
const PLATE_SIZE := Vector2(0.06, 0.06)
## Ring centre in the controller frame: on the back of the wrist, just past the palm.
## Text up is -Z. The rows of text sit below the ring, toward the elbow, so they never
## reach over the hand.
const RING_OFFSET := Vector3(0.0, 0.064, 0.098)
const RING_RADIUS := 0.0170
const RING_WIDTH := 0.0042
const ELEMENT_RADIUS := 0.0236
const ELEMENT_WIDTH := 0.0014
## The three charge orbs (D22): centre radius, orb radius, and clockwise angles from 12 o'clock.
const CHARGE_RADIUS := 0.0277
const CHARGE_SIZE := 0.0019
const CHARGE_ANGLES := Vector3(0.17, 0.61, 1.05)
const CHARGE_EMPTY_COLOR := Color(0.3, 0.3, 0.34)
## Text rows, as plate-up offsets from the ring centre (negative is below the ring).
const ELEMENT_ROW_UP := -0.0300
const ABILITY_ROW_UP := -0.0366
## Half the gap between the two ability glyphs (m), either side of the centre line.
const ABILITY_SPREAD := 0.0075
const STATUS_ROW_UP := -0.0432
const LABEL_Y := 0.0021
const KCAL_FONT := 34
const KCAL_UNIT_FONT := 14
## Kcal figure and unit, as plate-up offsets from the ring centre: the pair is centred on it.
const KCAL_ROW_UP := 0.0017
const KCAL_UNIT_ROW_UP := -0.0053
const ELEMENT_FONT := 22
const ABILITY_FONT := 18
const STATUS_FONT := 19

## Show and hide limits: the wrist to the eyes (m), the angle between the readout's
## face and the eyes (deg), and the fade time (s). Hiding needs the wider limits.
const SHOW_DIST := 0.35
const HIDE_DIST := 0.42
const SHOW_ANGLE_DEG := 45.0
const HIDE_ANGLE_DEG := 55.0
const FADE_SECONDS := 0.15
## Desktop: where the readout hangs in front of the camera while H is held.
const DESKTOP_OFFSET := Vector3(-0.16, -0.14, -0.30)

const MAX_FACE_TILT_DEG := 10.0
const TEAL := Color(0.36, 0.84, 0.72)
const AMBER := Color(0.98, 0.64, 0.24)
const RED := Color(0.95, 0.2, 0.16)
const HP_WARN_RATIO := 0.5
const HP_CRITICAL_RATIO := 0.25
## D9: the SANDBOX mark, amber, in the plate's top-left corner. The top is the only free edge:
## the element, ability and status rows all hang below the ring, and the ring keeps its clearance.
const SANDBOX_FONT := 18
const SANDBOX_COLOR := Color(1.0, 0.7, 0.3)
const KCAL_COLOR := Color(1.0, 1.0, 1.0)
const PARRY_GLOW_SECONDS := 0.42
const LEVEL_FLASH_SECONDS := 0.6
const LEVEL_TEXT_SECONDS := 1.5

var wrist_unit: Node3D
var wrist_face: Node3D
var ring: MeshInstance3D
## The white kcal figure inside the ring.
var kcal_label: Label3D
## The small "kcal" under the figure.
var kcal_unit_label: Label3D
## The imbued element: its kanji and the seconds left, under the ring.
var element_label: Label3D
## The ability glyphs: A and B, each bright when its ability is ready.
var ability_a_label: Label3D
var ability_b_label: Label3D
## The run line and the buffs, under the element rows.
var wrist_label: Label3D
## Debug builds: a small red count of RuntimeGuard violations on the plate,
## so a problem is noticed in the headset (details in the console / log).
var guard_label: Label3D
## D9: a sandbox run marks itself on the plate, so no demo is mistaken for a real run.
var sandbox_label: Label3D
var _sandbox_run := false

var _ring_mat := ShaderMaterial.new()
## The charges held (D21), oldest first, as the orbs show them. Set from charges_changed.
var _charges: Array[String] = []
var _ring_cache := {}
var _presence := 0.0
var _raised := false
var _follow_eyes := false
var _bound_player: Node3D = null
var _view_camera: Camera3D
var _elements: ElementSystem
var _calories: CalorieMeter
var _parry_glow := 0.0
var _level_flash := 0.0
var _level_text_left := 0.0
var _level_text := ""
var _stats := {}
## Whether the imbued element is in its last seconds (the element figure beats).
var _element_warn := false
## Real seconds since the HUD started; drives the element's beat (shaders have TIME, scripts do not).
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

	ring = MeshInstance3D.new()
	ring.name = "WristRing"
	var quad := QuadMesh.new()
	quad.size = PLATE_SIZE
	ring.mesh = quad
	ring.material_override = _ring_mat
	ring.position = Vector3(0.0, 0.0017, 0.0)
	ring.rotation.x = -PI * 0.5
	_no_shadow(ring)
	_ring_mat.shader = RING_SHADER
	_ring_mat.set_shader_parameter("size", PLATE_SIZE)
	_ring_mat.set_shader_parameter("ring_radius", RING_RADIUS)
	_ring_mat.set_shader_parameter("ring_width", RING_WIDTH)
	_ring_mat.set_shader_parameter("element_radius", ELEMENT_RADIUS)
	_ring_mat.set_shader_parameter("element_width", ELEMENT_WIDTH)
	_ring_mat.set_shader_parameter("charge_radius", CHARGE_RADIUS)
	_ring_mat.set_shader_parameter("charge_size", CHARGE_SIZE)
	_ring_mat.set_shader_parameter("charge_angles", CHARGE_ANGLES)
	_ring_mat.set_shader_parameter("charge_0", _charge_slot(0))
	_ring_mat.set_shader_parameter("charge_1", _charge_slot(1))
	_ring_mat.set_shader_parameter("charge_2", _charge_slot(2))
	wrist_face.add_child(ring)

	# Figures in Godot's built-in sans (the brush font's "1" reads as "7"), kanji
	# from the bundled brush font as the fallback.
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	if ResourceLoader.exists(HUD_FONT_PATH):
		font.fallbacks = [load(HUD_FONT_PATH)]
	font.variation_embolden = 0.35
	kcal_label = _make_label("KcalLabel", font, KCAL_FONT, _row(KCAL_ROW_UP))
	kcal_label.modulate = KCAL_COLOR
	kcal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kcal_unit_label = _make_label("KcalUnitLabel", font, KCAL_UNIT_FONT, _row(KCAL_UNIT_ROW_UP))
	kcal_unit_label.text = "kcal"
	kcal_unit_label.modulate = KCAL_COLOR
	kcal_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	element_label = _make_label("ElementLabel", font, ELEMENT_FONT, _row(ELEMENT_ROW_UP))
	element_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_a_label = _make_label("AbilityALabel", font, ABILITY_FONT, _row(ABILITY_ROW_UP) - Vector3(ABILITY_SPREAD, 0.0, 0.0))
	ability_a_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_b_label = _make_label("AbilityBLabel", font, ABILITY_FONT, _row(ABILITY_ROW_UP) + Vector3(ABILITY_SPREAD, 0.0, 0.0))
	ability_b_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrist_label = _make_label("WristLabel", font, STATUS_FONT, _row(STATUS_ROW_UP))
	wrist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrist_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	wrist_label.line_spacing = -2.0
	for l in _labels():
		# The figures sit on the ring and the orbs: draw them after the quad.
		l.render_priority = 2
		wrist_face.add_child(l)

	sandbox_label = _make_label("SandboxLabel", font, SANDBOX_FONT, Vector3(-PLATE_SIZE.x * 0.5 + 0.002, LABEL_Y, -PLATE_SIZE.y * 0.5 + 0.0038))
	sandbox_label.text = "SANDBOX"
	sandbox_label.modulate = SANDBOX_COLOR
	sandbox_label.render_priority = 2
	sandbox_label.visible = false
	wrist_face.add_child(sandbox_label)

	if RuntimeGuard.enabled:
		guard_label = _make_label("GuardLabel", font, 22, Vector3(PLATE_SIZE.x * 0.5 - 0.006, LABEL_Y, -PLATE_SIZE.y * 0.5 + 0.006))
		guard_label.modulate = Color(1.0, 0.25, 0.2)
		guard_label.visible = false
		wrist_face.add_child(guard_label)

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


func _row(up: float) -> Vector3:
	return Vector3(0.0, LABEL_Y, -up)


func _labels() -> Array[Label3D]:
	return [kcal_label, kcal_unit_label, element_label, ability_a_label, ability_b_label, wrist_label]


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
	l.outline_size = 8
	l.outline_modulate = Color(0.03, 0.02, 0.02, 0.95)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.modulate = Color(0.95, 0.92, 0.85, 0.98)
	# Text up is -Z on the plate; glyphs float just over the ring and keep
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
	_level_flash = maxf(_level_flash - delta, 0.0)
	_level_text_left = maxf(_level_text_left - delta, 0.0)
	if was_flashing and _level_text_left <= 0.0:
		_refresh_status()
	_orient_wrist_face(delta)

	var was_raised := _raised
	_raised = _gesture_held()
	if not was_raised and _raised:
		_trigger_wrist_haptic()
	_presence = move_toward(_presence, 1.0 if _raised else 0.0, delta / FADE_SECONDS)
	# The state is kept current even while hidden, so a raised wrist shows the right
	# figures at once; only the drawing (the subtree's visibility) follows the gesture.
	_refresh_ring()
	_refresh_element()
	_refresh_kcal()
	wrist_face.visible = _presence > 0.0
	for label in _labels():
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


func _trigger_wrist_haptic() -> void:
	if wrist_unit == null:
		return
	var ctrl := wrist_unit.get_parent() as XRController3D
	if ctrl and VrComfortSettings:
		var amp := VrComfortSettings.haptic_amplitude(0.22)
		if amp > 0.0:
			ctrl.trigger_haptic_pulse("haptic", 0.0, amp, 0.04, 0.0)


## The check-the-watch gesture (XR): the wrist close to the eyes, its face turned to
## them and in view, with hysteresis so it does not flicker at the edge. Desktop: H held.
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
	var face_deg := rad_to_deg(wrist_unit.global_basis.y.angle_to(to_eye / d))
	return d < near_limit and face_deg < face_limit and cam.is_position_in_frustum(anchor)


func _camera() -> Camera3D:
	if _view_camera and is_instance_valid(_view_camera):
		return _view_camera
	return get_viewport().get_camera_3d() if get_viewport() else null


## Pushes a uniform only when it changed (a shader uniform write is not free).
func _set_ring(key: String, value: Variant) -> void:
	if _ring_cache.get(key) == value:
		return
	_ring_cache[key] = value
	_ring_mat.set_shader_parameter(key, value)


func _refresh_ring() -> void:
	_set_ring("presence", snappedf(_presence, 0.01))
	var flash := _level_flash / LEVEL_FLASH_SECONDS
	_set_ring("glow", snappedf(clampf(maxf(_parry_glow / PARRY_GLOW_SECONDS, flash), 0.0, 1.0), 0.02))


func _refresh_element() -> void:
	if _elements == null or not is_instance_valid(_elements):
		return
	var es := _elements
	var element := es.current_element
	var active := element != Elements.NONE
	_set_ring("element_on", 1.0 if active else 0.0)
	_set_ring("element_fill", snappedf(es.imbue_ratio() if active else 0.0, 0.004))
	_element_warn = active and es.is_fade_warning
	if not active:
		_set_text(element_label, "")
		_set_text(ability_a_label, "")
		_set_text(ability_b_label, "")
		return
	_set_ring("element_color", Elements.accent_color(element))
	var tint := Elements.accent_color(element).lightened(0.35)
	_set_text(element_label, "%s %d" % [Elements.build_label(element), ceili(es.element_time_remaining)])
	# The last seconds of an imbue beat, like the blade and the element arc do.
	var beat := 0.35 + 0.65 * (0.5 + 0.5 * sin(_clock * 18.8496)) if _element_warn else 1.0
	# Brightness only: the alpha belongs to the fade in _process.
	element_label.modulate = Color(tint * beat, element_label.modulate.a)
	_set_text(ability_a_label, Elements.ability_glyph(element, 1))
	_set_text(ability_b_label, Elements.ability_glyph(element, 2))
	ability_a_label.modulate = Color(ability_colour(tint, es.ability_ready_ratio(1)), ability_a_label.modulate.a)
	ability_b_label.modulate = Color(ability_colour(tint, es.ability_ready_ratio(2)), ability_b_label.modulate.a)


## An ability glyph: dim while its ability recharges, the element's light once ready.
static func ability_colour(tint: Color, ready: float) -> Color:
	return Color(0.42, 0.4, 0.48).lerp(tint, clampf(ready, 0.0, 1.0))


func _refresh_kcal() -> void:
	var value := 0 if _calories == null else floori(_calories.kcal)
	_set_text(kcal_label, str(value))


func _set_text(label: Label3D, value: String) -> void:
	if label.text != value:
		label.text = value


## The engraved run line (plan section (f), D12): rank, kills and score; then XP to the
## next rank, the skill points to spend and the wave; then any buffs.
func _refresh_status() -> void:
	if _stats.is_empty():
		return
	var first: String = "位 %d · 斬 %d · %d pt" % [_stats.level, _stats.kills, _stats.score]
	if _level_text_left > 0.0:
		first = _level_text
	var lines := [first, "XP %d/%d · 点 %d · 波 %d" % [_stats.xp, _stats.xp_to_next, _stats.points, _stats.wave]]
	if _stats.buff != "":
		lines.append(_stats.buff)
	_set_text(wrist_label, "\n".join(lines))


func update_hud(hp: float, max_hp: float, xp: int, xp_to_next: int, level: int, wave: int, score: int, kills: int, run_seconds: float, active_element: String, points: int = 0, buff_text: String = "") -> void:
	var hp_ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_set_ring("hp_fill", snappedf(hp_ratio, 0.004))
	_set_ring("hp_color", hp_color(hp_ratio))
	_set_ring("hp_pulse", 1.0 if hp_ratio < HP_CRITICAL_RATIO else 0.0)
	_stats = {"xp": xp, "xp_to_next": xp_to_next, "level": level, "wave": wave, "score": score,
		"kills": kills, "points": points, "buff": buff_text}
	_refresh_status()


## Hands the HUD the element system it mirrors (called once by RunGame). The charge orbs
## follow its charges_changed signal, so they change the moment a charge is taken or spent.
func bind_elements(es: ElementSystem) -> void:
	_elements = es
	if not es.charges_changed.is_connected(_on_charges_changed):
		es.charges_changed.connect(_on_charges_changed)
	_on_charges_changed(es.get_charges())


## The orbs take the charges' colours, oldest first; the slots past the last charge are empty.
func _on_charges_changed(charges: Array[String]) -> void:
	_charges = charges.duplicate()
	for i in ElementSystem.MAX_CHARGES:
		_ring_mat.set_shader_parameter("charge_%d" % i, _charge_slot(i))


## One orb's shader value: its element's colour, and alpha as the fill (1 charged, 0 empty).
func _charge_slot(index: int) -> Color:
	if index < _charges.size():
		var accent := Elements.accent_color(_charges[index])
		return Color(accent.r, accent.g, accent.b, 1.0)
	return Color(CHARGE_EMPTY_COLOR, 0.0)


## Hands the HUD the calorie meter it shows inside the ring (called once by RunGame).
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


## Shows or hides the SANDBOX mark (D9): true for a run that used the sandbox.
func set_sandbox_run(on: bool) -> void:
	_sandbox_run = on


func on_parry() -> void:
	_parry_glow = PARRY_GLOW_SECONDS


## A level-up (D12): a short glow on the ring and the new level for the run line.
func flash_level_up(new_level: int) -> void:
	_level_flash = LEVEL_FLASH_SECONDS
	_level_text = "位 LV %d  ·  +1 点" % new_level
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
