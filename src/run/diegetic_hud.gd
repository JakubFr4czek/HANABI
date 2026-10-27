class_name DiegeticHud
extends Node3D
## Minimal diegetic HUD (docs/GDD.md §6, NIGHT_PLAN.md §1):
## - Glowing HP charm + engraved readout on the wrist kote (no screen-space UI,
##   nothing bolted onto the katana).
## - The wrist text only appears when the wrist is raised toward the face;
##   the HP charm and critical ring stay as the always-on glanceable signals.

const RING_SHADER := preload("res://src/shaders/hud_ring.gdshader")
const WET_SURFACE_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const HP_RING_CRITICAL_RATIO := 0.30
## Wrist-to-face distance (m) where the readout is fully shown / fully hidden.
const LABEL_SHOW_DIST := 0.42
const LABEL_HIDE_DIST := 0.62
## Bundled font: the system fonts the plate used before do not exist on Quest.
const HUD_FONT_PATH := "res://assets/fonts/YujiBoku-Regular.ttf"
const PLATE_SIZE := Vector2(0.1, 0.054)
const CHARM_X := -0.031
const TEXT_X := -0.009
const MAX_FACE_TILT_DEG := 25.0

var wrist_unit: Node3D
var wrist_face: Node3D
var hp_charm_mesh: MeshInstance3D
var wrist_hp_ring: MeshInstance3D
var wrist_label: Label3D
var hp_label: Label3D
var hp_gauge: MeshInstance3D
var xp_bar: MeshInstance3D

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


func setup(player: Node3D, katana: HeldWeapon) -> void:
	if player:
		for layer in player.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
	_view_camera = _resolve_view_camera(player)

	_setup_wrist_unit(player)
	update_hud(100.0, 100.0, 0, 30, 1, 1, 0, 0, 0.0, Elements.NONE)


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
	plate.position.y = -0.003
	plate.material_override = _lacquer_mat
	_no_shadow(plate)
	wrist_face.add_child(plate)

	var hx := PLATE_SIZE.x * 0.5
	var hz := PLATE_SIZE.y * 0.5
	for edge in [
		[Vector3(0.0, 0.0006, -hz), Vector3(PLATE_SIZE.x + 0.002, 0.0012, 0.0016)],
		[Vector3(0.0, 0.0006, hz), Vector3(PLATE_SIZE.x + 0.002, 0.0012, 0.0016)],
		[Vector3(-hx, 0.0006, 0.0), Vector3(0.0016, 0.0012, PLATE_SIZE.y)],
		[Vector3(hx, 0.0006, 0.0), Vector3(0.0016, 0.0012, PLATE_SIZE.y)],
	]:
		var trim := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = edge[1]
		trim.mesh = tm
		trim.position = edge[0]
		trim.material_override = _trim_mat
		_no_shadow(trim)
		wrist_face.add_child(trim)

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
	hp_label = _make_label("HpLabel", font, 44, Vector3(TEXT_X, 0.0012, -0.0085))
	wrist_label = _make_label("WristLabel", font, 26, Vector3(TEXT_X, 0.0012, 0.0062))
	wrist_label.line_spacing = -2.0
	wrist_face.add_child(hp_label)
	wrist_face.add_child(wrist_label)

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

	if player is XRPlayer:
		var xr := player as XRPlayer
		xr.left_controller.add_child(wrist_unit)
		# Back of the left wrist, rolled a little toward the thumb so a
		# "check the watch" turn of the forearm shows it to the eyes.
		wrist_unit.position = Vector3(0.0, 0.032, 0.058)
		wrist_unit.rotation = Vector3(deg_to_rad(12.0), 0.0, deg_to_rad(-22.0))
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
	ring.position = Vector3(CHARM_X, 0.0009, 0.0)
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
	_update_label_visibility()


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
		wrist_label.visible = false
		hp_label.visible = false
		return
	var d := wrist_unit.global_position.distance_to(cam.global_position)
	var a := clampf((LABEL_HIDE_DIST - d) / maxf(LABEL_HIDE_DIST - LABEL_SHOW_DIST, 0.01), 0.0, 1.0)
	for l in [wrist_label, hp_label]:
		(l as Label3D).visible = a > 0.02
		(l as Label3D).modulate.a = 0.98 * a
		(l as Label3D).outline_modulate.a = 0.95 * a


func update_hud(hp: float, max_hp: float, xp: int, xp_to_next: int, level: int, wave: int, score: int, kills: int, run_seconds: float, active_element: String) -> void:
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
		# Engraved readout in the game's voice: rank, wave, kills, score.
		wrist_label.text = "位 %d · 波 %d · 斬 %d\n%d pt" % [level, wave, kills, score]
