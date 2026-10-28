class_name DiegeticHud
extends Node3D
## Minimal diegetic HUD (docs/GDD.md §6, NIGHT_PLAN.md §1):
## - Glowing HP charm + engraved readout on the wrist kote (no screen-space UI,
##   nothing bolted onto the katana).
## - The wrist text only appears when the wrist is raised toward the face;
##   the HP charm and critical ring stay as the always-on glanceable signals.
## - E3: an element strip under the HP row: the crest (kanji + a ring that
##   drains with the imbue), the seconds left, and one ring per ability button
##   (A, B) that refills as the ability recharges. All read from the
##   [ElementSystem]; nothing is drawn on the katana.

const RING_SHADER := preload("res://src/shaders/hud_ring.gdshader")
const STRIP_SHADER := preload("res://src/shaders/wrist_element.gdshader")
const WET_SURFACE_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const HP_RING_CRITICAL_RATIO := 0.30
## Wrist-to-face distance (m) where the readout is fully shown / fully hidden.
const LABEL_SHOW_DIST := 0.42
const LABEL_HIDE_DIST := 0.62
## Bundled font: the system fonts the plate used before do not exist on Quest.
const HUD_FONT_PATH := "res://assets/fonts/YujiBoku-Regular.ttf"
## The plate: the HP row (z -0.027..0.027, as before) and, towards the elbow,
## the element strip. Text up is -Z.
const PLATE_SIZE := Vector2(0.108, 0.096)
const PLATE_CENTER_Z := 0.021
const HP_ROW_HALF_Z := 0.027
const STRIP_CENTER_Z := 0.049
const STRIP_SIZE := Vector2(0.1, 0.034)
const CHARM_X := -0.035
const TEXT_X := -0.013
## Glyph spacing in the ability label: three ideographic spaces' worth.
const PIP_GLYPH_FONT := 27
const CREST_FONT := 44
const TIME_FONT := 36
const MAX_FACE_TILT_DEG := 10.0

var wrist_unit: Node3D
var wrist_face: Node3D
var hp_charm_mesh: MeshInstance3D
var wrist_hp_ring: MeshInstance3D
var wrist_label: Label3D
var hp_label: Label3D
## Debug builds: a small red count of RuntimeGuard violations on the plate,
## so a problem is noticed in the headset (details in the console / log).
var guard_label: Label3D
var hp_gauge: MeshInstance3D
var xp_bar: MeshInstance3D
## E3 element strip: the shader quad (crest ring + two ability rings) and its labels.
var element_strip: MeshInstance3D
var crest_label: Label3D
var time_label: Label3D
var ability_label: Label3D

var _wrist_hp_mat := ShaderMaterial.new()
var _charm_mat := StandardMaterial3D.new()
var _lacquer_mat := ShaderMaterial.new()
var _trim_mat := StandardMaterial3D.new()
var _hp_gauge_mat := ShaderMaterial.new()
var _xp_mat := StandardMaterial3D.new()
var _xp_bar_left := 0.0
var _xp_bar_width := 0.1
var _follow_eyes := false
var _parry_glow := 0.0
var _view_camera: Camera3D
var _elements: ElementSystem
var _strip_mat := ShaderMaterial.new()
var _strip_cache := {}
var _shown_element := "?"
var _crest_flash := 0.0
var _time_shown := -1


var _bound_player: Node3D = null

func setup(player: Node3D, katana: HeldWeapon) -> void:
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
	wrist_unit.add_child(wrist_face)

	_lacquer_mat.shader = WET_SURFACE_SHADER
	_lacquer_mat.set_shader_parameter("base_color", Color(0.07, 0.065, 0.09))
	_lacquer_mat.set_shader_parameter("roughness_dry", 0.62)
	_lacquer_mat.set_shader_parameter("roughness_wet", 0.30)
	_lacquer_mat.set_shader_parameter("wetness", 0.45)
	_lacquer_mat.set_shader_parameter("waterline_y", -10.0)
	_lacquer_mat.set_shader_parameter("fill", 1.6)
	_lacquer_mat.set_shader_parameter("fog_rim", 0.2)
	_lacquer_mat.set_shader_parameter("emission_tint", Color(0.10, 0.08, 0.13))

	# Thin gilt frame: reads as a lacquered plaque, not a red slab, and its
	# faint glow keeps the outline visible in the night fog.
	_trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trim_mat.albedo_color = Color(0.78, 0.6, 0.32)

	var plate := MeshInstance3D.new()
	plate.name = "BracerPlate"
	var bm := BoxMesh.new()
	bm.size = Vector3(PLATE_SIZE.x, 0.006, PLATE_SIZE.y)
	plate.mesh = bm
	plate.position = Vector3(0.0, -0.003, PLATE_CENTER_Z)
	plate.material_override = _lacquer_mat
	_no_shadow(plate)
	wrist_face.add_child(plate)

	# One mesh for the whole gilt frame (outline + the rule between the HP row
	# and the element strip): a single draw call instead of one per edge.
	var frame := MeshInstance3D.new()
	frame.name = "GiltFrame"
	frame.mesh = _gilt_frame_mesh()
	frame.material_override = _trim_mat
	_no_shadow(frame)
	wrist_face.add_child(frame)

	# Left: the HP charm inside its gauge ring (always on, the glanceable
	# signal), with a red danger ring around it below 30 %.
	_charm_mat.albedo_color = Color(0.55, 0.62, 0.68)
	_charm_mat.roughness = 0.35
	_charm_mat.emission_enabled = true
	_charm_mat.emission = Color(0.22, 0.48, 0.52)
	_charm_mat.emission_energy_multiplier = 0.35

	hp_charm_mesh = MeshInstance3D.new()
	hp_charm_mesh.name = "HPCharm"
	var sphere := SphereMesh.new()
	sphere.radius = 0.0075
	sphere.height = 0.008
	sphere.radial_segments = 16
	sphere.rings = 6
	hp_charm_mesh.mesh = sphere
	hp_charm_mesh.material_override = _charm_mat
	hp_charm_mesh.position = Vector3(CHARM_X, 0.002, 0.0)
	_no_shadow(hp_charm_mesh)
	wrist_face.add_child(hp_charm_mesh)

	hp_gauge = _ring_quad("HpGauge", _hp_gauge_mat, 0.033, 0.74, 0.94, 20)
	_hp_gauge_mat.set_shader_parameter("track_color", Color(0.10, 0.10, 0.14))
	_hp_gauge_mat.set_shader_parameter("glow_boost", 1.6)
	wrist_face.add_child(hp_gauge)

	# A thin, unbroken halo just outside the gauge: frames it, never covers it.
	wrist_hp_ring = _ring_quad("WristHpRing", _wrist_hp_mat, 0.040, 0.87, 0.97, 1)
	_wrist_hp_mat.set_shader_parameter("glow_boost", 2.6)
	wrist_hp_ring.visible = false
	wrist_face.add_child(wrist_hp_ring)

	# Right: life in large figures, the run stats under it, souls toward the
	# next rank as a bar along the bottom edge.
	# Figures in Godot's built-in sans (the brush font's "1" reads as "7"),
	# kanji from the bundled brush font as the fallback.
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	if ResourceLoader.exists(HUD_FONT_PATH):
		font.fallbacks = [load(HUD_FONT_PATH)]
	font.variation_embolden = 0.35
	hp_label = _make_label("HpLabel", font, 44, Vector3(TEXT_X, 0.0021, -0.0085))
	wrist_label = _make_label("WristLabel", font, 26, Vector3(TEXT_X, 0.0021, 0.0062))
	wrist_label.line_spacing = -2.0
	wrist_face.add_child(hp_label)
	wrist_face.add_child(wrist_label)
	if RuntimeGuard.enabled:
		guard_label = _make_label("GuardLabel", font, 22, Vector3(PLATE_SIZE.x * 0.5 - 0.03, 0.0012, -HP_ROW_HALF_Z + 0.006))
		guard_label.modulate = Color(1.0, 0.25, 0.2)
		guard_label.visible = false
		wrist_face.add_child(guard_label)

	var hz := HP_ROW_HALF_Z
	var bar_w := PLATE_SIZE.x - 0.012
	var track := MeshInstance3D.new()
	track.name = "SoulBarTrack"
	var trm := BoxMesh.new()
	trm.size = Vector3(bar_w, 0.0008, 0.0022)
	track.mesh = trm
	track.position = Vector3(0.0, 0.0006, hz - 0.0042)
	var track_mat := StandardMaterial3D.new()
	track_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	track_mat.albedo_color = Color(0.16, 0.15, 0.2)
	track.material_override = track_mat
	_no_shadow(track)
	wrist_face.add_child(track)

	xp_bar = MeshInstance3D.new()
	xp_bar.name = "SoulBar"
	var xbm := BoxMesh.new()
	xbm.size = Vector3(bar_w, 0.0012, 0.0024)
	xp_bar.mesh = xbm
	_xp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_xp_mat.albedo_color = Color(0.55, 0.85, 1.0)
	xp_bar.material_override = _xp_mat
	_no_shadow(xp_bar)
	_xp_bar_left = -bar_w * 0.5
	_xp_bar_width = bar_w
	xp_bar.position = Vector3(0.0, 0.0009, hz - 0.0042)
	wrist_face.add_child(xp_bar)

	_build_element_strip(font)


	if player is XRPlayer:
		var xr := player as XRPlayer
		var offhand: XRController3D = xr.get_offhand_controller() if xr.has_method("get_offhand_controller") else xr.left_controller
		offhand.add_child(wrist_unit)
		# Back of the wrist, rolled a little toward the thumb so a
		# "check the watch" turn of the forearm shows it to the eyes.
		var is_right := (offhand == xr.right_controller)
		wrist_unit.position = Vector3(0.0, 0.058, 0.066)
		wrist_unit.rotation = Vector3(deg_to_rad(6.0), 0.0, deg_to_rad(14.0 if is_right else -14.0))
		_follow_eyes = true
	elif player is DesktopPlayer:
		var dp := player as DesktopPlayer
		dp.set_screen_hud_visible(false)
		# The sword hand is the right. The readout stays on a left wrist in
		# front of the body, so a slash does not whip the plate out of view.
		dp.camera.add_child(wrist_unit)
		wrist_unit.position = Vector3(-0.2, -0.17, -0.34)
		# Pinned to the camera: face it once, squarely, text upright.
		var to_cam := -wrist_unit.position.normalized()
		var x_axis := Vector3.RIGHT.slide(to_cam).normalized()
		wrist_unit.basis = Basis(x_axis, to_cam, x_axis.cross(to_cam).normalized())
	else:
		player.add_child(wrist_unit)


## Gilt outline of the plate plus a rule under the HP row, as one mesh.
func _gilt_frame_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := PLATE_SIZE.x * 0.5
	var z0 := PLATE_CENTER_Z - PLATE_SIZE.y * 0.5
	var z1 := PLATE_CENTER_Z + PLATE_SIZE.y * 0.5
	var t := 0.0016
	var h := 0.0012
	for bar in [
		[Vector3(0.0, h * 0.5, z0), Vector3(PLATE_SIZE.x + 0.002, h, t)],
		[Vector3(0.0, h * 0.5, z1), Vector3(PLATE_SIZE.x + 0.002, h, t)],
		[Vector3(-hx, h * 0.5, PLATE_CENTER_Z), Vector3(t, h, PLATE_SIZE.y)],
		[Vector3(hx, h * 0.5, PLATE_CENTER_Z), Vector3(t, h, PLATE_SIZE.y)],
		[Vector3(0.0, h * 0.5, HP_ROW_HALF_Z + 0.0025), Vector3(PLATE_SIZE.x - 0.012, h * 0.7, 0.0008)],
	]:
		_add_box(st, bar[0], bar[1])
	return st.commit()


static func _add_box(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var e := size * 0.5
	var v: Array[Vector3] = []
	for i in 8:
		v.append(c + Vector3(e.x if i & 1 else -e.x, e.y if i & 2 else -e.y, e.z if i & 4 else -e.z))
	for quad in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [2, 3, 7, 6], [0, 4, 5, 1]]:
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.add_vertex(v[quad[k]])


func _build_element_strip(font: Font) -> void:
	element_strip = MeshInstance3D.new()
	element_strip.name = "ElementStrip"
	var q := QuadMesh.new()
	q.size = STRIP_SIZE
	element_strip.mesh = q
	_strip_mat.shader = STRIP_SHADER
	_strip_mat.set_shader_parameter("size", STRIP_SIZE)
	element_strip.material_override = _strip_mat
	element_strip.position = Vector3(0.0, 0.0017, STRIP_CENTER_Z)
	element_strip.rotation.x = -PI * 0.5
	_no_shadow(element_strip)
	wrist_face.add_child(element_strip)

	# Crest ring centre and the pips' mid-point match the defaults of wrist_element.gdshader.
	crest_label = _make_label("CrestLabel", font, CREST_FONT, Vector3(-0.0355, 0.0021, STRIP_CENTER_Z))
	crest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label = _make_label("TimeLabel", font, TIME_FONT, Vector3(-0.0195, 0.0021, STRIP_CENTER_Z))
	ability_label = _make_label("AbilityLabel", font, PIP_GLYPH_FONT, Vector3(0.0305, 0.0021, STRIP_CENTER_Z))
	ability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for l in [crest_label, time_label, ability_label]:
		# The glyphs sit on the strip's dark discs: draw them after the quad.
		l.render_priority = 2
		wrist_face.add_child(l)
	_shown_element = "?"
	_apply_strip(Elements.NONE, 0.0, 0.0, 0.0, 0.0, false)


## Hands the HUD the element system it mirrors (called once by RunGame).
func bind_elements(es: ElementSystem) -> void:
	_elements = es
	_shown_element = "?"


func _strip_set(key: String, value: Variant) -> void:
	if _strip_cache.get(key) == value:
		return
	_strip_cache[key] = value
	_strip_mat.set_shader_parameter(key, value)


## Pushes the element state to the strip; only touches a value that changed.
func _apply_strip(element: String, ratio: float, left: float, ready1: float, ready2: float, warn: bool) -> void:
	if element_strip == null:
		return
	var active := element != Elements.NONE
	_strip_set("color", Elements.accent_color(element) if active else Color(0.5, 0.47, 0.55))
	_strip_set("lit", 1.0 if active else 0.0)
	_strip_set("crest_ratio", snappedf(ratio, 0.004))
	_strip_set("pip1_ratio", snappedf(ready1, 0.01))
	_strip_set("pip2_ratio", snappedf(ready2, 0.01))
	_strip_set("warn", 1.0 if warn else 0.0)
	_strip_set("left", left if warn else 0.0)
	_strip_set("flash", snappedf(_crest_flash, 0.02))
	if element != _shown_element:
		_shown_element = element
		var tint := Elements.accent_color(element).lightened(0.35) if active else Color(0.62, 0.6, 0.68)
		crest_label.text = Elements.build_label(element) if active else "門"
		crest_label.modulate = Color(tint, crest_label.modulate.a)
		ability_label.text = "%s\u3000\u3000%s" % [Elements.ability_glyph(element, 1), Elements.ability_glyph(element, 2)] if active else ""
		ability_label.modulate = Color(tint, ability_label.modulate.a)
		time_label.modulate = Color(tint, time_label.modulate.a)
		_time_shown = -2  # redraw the count for the new element
	var secs := ceili(left) if active else -1
	if secs != _time_shown:
		_time_shown = secs
		time_label.text = "%d" % secs if active else ""
	# The count turns warm in the last seconds, like the blade starts to beat.
	var warm := Elements.accent_color(element).lerp(Color(1.0, 0.72, 0.4), 0.7) if warn else Elements.accent_color(element).lightened(0.35)
	if active:
		time_label.modulate = Color(warm, time_label.modulate.a)


func _update_element_strip(delta: float) -> void:
	if _elements == null or not is_instance_valid(_elements) or element_strip == null:
		return
	var es := _elements
	if es.current_element != _shown_element and es.current_element != Elements.NONE:
		_crest_flash = 1.0
	_crest_flash = maxf(_crest_flash - delta / 0.7, 0.0)
	_apply_strip(es.current_element, es.imbue_ratio(), es.element_time_remaining,
		es.ability_ready_ratio(1), es.ability_ready_ratio(2), es.is_fade_warning)


func _no_shadow(mi: GeometryInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _ring_quad(node_name: String, mat: ShaderMaterial, size: float, inner: float, outer: float, segments: int) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = node_name
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mat.shader = RING_SHADER
	mat.set_shader_parameter("inner_radius", inner)
	mat.set_shader_parameter("outer_radius", outer)
	mat.set_shader_parameter("segments", segments)
	ring.mesh = q
	ring.material_override = mat
	ring.position = Vector3(CHARM_X, 0.0017, 0.0)
	ring.rotation.x = -PI * 0.5
	_no_shadow(ring)
	return ring


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
	# Text up is -Z on the plate; glyphs float just over the lacquer and keep
	# the depth test, so the hand still occludes them.
	l.position = at
	l.rotation.x = -PI * 0.5
	l.visible = false
	return l


func _process(delta: float) -> void:
	if _parry_glow > 0.0:
		_parry_glow = maxf(_parry_glow - delta, 0.0)
		_charm_mat.emission_energy_multiplier = _charm_base_energy + _parry_glow * 2.2
	_orient_wrist_face(delta)
	_update_element_strip(delta)
	_update_label_visibility()
	if guard_label:
		var n := RuntimeGuard.violation_count()
		guard_label.visible = n > 0
		if n > 0:
			guard_label.text = "! %d" % n


## In VR the plate rides the wrist rigidly and only leans toward the eyes by
## up to [constant MAX_FACE_TILT_DEG], smoothed. (Turning it fully to the
## camera every frame made it swim against the wrist and flip the text as
## the arm rolled.)
func _orient_wrist_face(delta: float) -> void:
	if not _follow_eyes or wrist_face == null or wrist_unit == null:
		return
	var cam := _view_camera
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d() if get_viewport() else null
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


func on_parry() -> void:
	_parry_glow = 0.42


var _charm_base_energy := 0.28


## The readout fades in only when the wrist is raised toward the face.
## (Desktop pins the wrist to the camera inside the show zone, so it reads
## as permanently raised there.)
func _update_label_visibility() -> void:
	if wrist_label == null or wrist_unit == null:
		return
	var cam := _view_camera
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		for l in [wrist_label, hp_label, crest_label, time_label, ability_label]:
			if l:
				(l as Label3D).visible = false
		return
	var d := wrist_unit.global_position.distance_to(cam.global_position)
	var a := clampf((LABEL_HIDE_DIST - d) / maxf(LABEL_HIDE_DIST - LABEL_SHOW_DIST, 0.01), 0.0, 1.0)
	for l in [wrist_label, hp_label, crest_label, time_label, ability_label]:
		if l == null:
			continue
		(l as Label3D).visible = a > 0.02 and (l as Label3D).text != ""
		(l as Label3D).modulate.a = 0.98 * a
		(l as Label3D).outline_modulate.a = 0.95 * a


func update_hud(hp: float, max_hp: float, xp: int, xp_to_next: int, level: int, wave: int, score: int, kills: int, run_seconds: float, active_element: String, ofuda_count: int = 0) -> void:
	var hp_ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var critical := hp_ratio <= HP_RING_CRITICAL_RATIO

	var hp_col := Color(0.38, 0.72, 0.68)
	if critical:
		hp_col = Color(1.0, 0.22, 0.18)
	elif hp_ratio < 0.55:
		hp_col = Color(0.92, 0.58, 0.28)

	if wrist_hp_ring:
		wrist_hp_ring.visible = critical
	if critical:
		_wrist_hp_mat.set_shader_parameter("fill_ratio", hp_ratio / HP_RING_CRITICAL_RATIO)
		_wrist_hp_mat.set_shader_parameter("fill_color", hp_col)

	_charm_mat.albedo_color = hp_col * Color(0.55, 0.55, 0.55, 1.0)
	_charm_mat.emission = hp_col
	_charm_base_energy = 0.28 + (1.0 - hp_ratio) * 0.55 + (0.65 if critical else 0.0)
	_charm_mat.emission_energy_multiplier = _charm_base_energy + _parry_glow * 2.2

	if hp_gauge:
		_hp_gauge_mat.set_shader_parameter("fill_ratio", hp_ratio)
		_hp_gauge_mat.set_shader_parameter("fill_color", hp_col)
	if hp_label:
		hp_label.text = "命 %d" % int(round(hp))
		hp_label.modulate = Color(hp_col.lightened(0.45), hp_label.modulate.a)
	if xp_bar:
		var r := clampf(float(xp) / maxf(float(xp_to_next), 1.0), 0.0, 1.0)
		xp_bar.visible = r > 0.001
		xp_bar.scale.x = maxf(r, 0.001)
		xp_bar.position.x = _xp_bar_left + _xp_bar_width * r * 0.5
	if wrist_label:
		# Engraved readout in the game's voice: rank, wave, kills, score,
		# and the spendable Ofuda tally (E2c, plan section (f)).
		wrist_label.text = "位 %d · 波 %d · 斬 %d\n%d pt · 札×%d" % [level, wave, kills, score, ofuda_count]

func update_wrist_attachment(player: Node3D) -> void:
	if player is XRPlayer and wrist_unit:
		var xr := player as XRPlayer
		var offhand: XRController3D = xr.get_offhand_controller() if xr.has_method("get_offhand_controller") else xr.left_controller
		if wrist_unit.get_parent() != offhand and offhand != null:
			wrist_unit.reparent(offhand)
			var is_right := (offhand == xr.right_controller)
			wrist_unit.position = Vector3(0.0, 0.058, 0.066)
			wrist_unit.rotation = Vector3(deg_to_rad(6.0), 0.0, deg_to_rad(14.0 if is_right else -14.0))


func _on_comfort_settings_changed() -> void:
	if _bound_player:
		update_wrist_attachment(_bound_player)
