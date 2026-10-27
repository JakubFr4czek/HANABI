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

var wrist_unit: Node3D
var wrist_face: Node3D
var hp_charm_mesh: MeshInstance3D
var wrist_hp_ring: MeshInstance3D
var wrist_label: Label3D

var _wrist_hp_mat := ShaderMaterial.new()
var _charm_mat := StandardMaterial3D.new()
var _lacquer_mat := ShaderMaterial.new()
var _trim_mat := ShaderMaterial.new()
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
	_lacquer_mat.set_shader_parameter("base_color", Color(0.11, 0.10, 0.14))
	_lacquer_mat.set_shader_parameter("roughness_dry", 0.72)
	_lacquer_mat.set_shader_parameter("roughness_wet", 0.34)
	_lacquer_mat.set_shader_parameter("wetness", 0.52)
	_lacquer_mat.set_shader_parameter("waterline_y", -10.0)
	_lacquer_mat.set_shader_parameter("fill", 2.15)
	_lacquer_mat.set_shader_parameter("fog_rim", 0.35)
	_lacquer_mat.set_shader_parameter("emission_tint", Color(0.18, 0.14, 0.22))

	_trim_mat.shader = WET_SURFACE_SHADER
	_trim_mat.set_shader_parameter("base_color", Color(0.62, 0.14, 0.10))
	_trim_mat.set_shader_parameter("roughness_dry", 0.58)
	_trim_mat.set_shader_parameter("roughness_wet", 0.28)
	_trim_mat.set_shader_parameter("wetness", 0.55)
	_trim_mat.set_shader_parameter("waterline_y", -10.0)
	_trim_mat.set_shader_parameter("fill", 2.35)
	_trim_mat.set_shader_parameter("emission_tint", Color(0.45, 0.10, 0.06))

	var bracer := MeshInstance3D.new()
	bracer.name = "BracerPlate"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.118, 0.009, 0.064)
	bracer.mesh = bm
	bracer.material_override = _lacquer_mat
	bracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bracer.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	wrist_face.add_child(bracer)

	var rim := MeshInstance3D.new()
	rim.name = "BracerRimGlow"
	var rq := QuadMesh.new()
	rq.size = Vector2(0.128, 0.072)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.albedo_color = Color(0.85, 0.32, 0.18, 0.22)
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rim.mesh = rq
	rim.material_override = rim_mat
	rim.position = Vector3(0.0, 0.005, 0.0)
	rim.rotation.x = -PI * 0.5
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wrist_face.add_child(rim)

	for sz in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.122, 0.011, 0.004)
		rail.mesh = rm
		rail.position = Vector3(0.0, 0.001, 0.030 * sz)
		rail.material_override = _trim_mat
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rail.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		wrist_face.add_child(rail)

	_charm_mat.albedo_color = Color(0.55, 0.62, 0.68)
	_charm_mat.roughness = 0.55
	_charm_mat.emission_enabled = true
	_charm_mat.emission = Color(0.22, 0.48, 0.52)
	_charm_mat.emission_energy_multiplier = 0.35

	hp_charm_mesh = MeshInstance3D.new()
	hp_charm_mesh.name = "HPCharm"
	var sphere := SphereMesh.new()
	sphere.radius = 0.009
	sphere.height = 0.016
	sphere.radial_segments = 10
	sphere.rings = 5
	hp_charm_mesh.mesh = sphere
	hp_charm_mesh.material_override = _charm_mat
	hp_charm_mesh.position = Vector3(-0.034, 0.006, 0.0)
	hp_charm_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hp_charm_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	wrist_face.add_child(hp_charm_mesh)

	wrist_hp_ring = MeshInstance3D.new()
	wrist_hp_ring.name = "WristHpRing"
	var hp_quad := QuadMesh.new()
	hp_quad.size = Vector2(0.042, 0.042)
	_wrist_hp_mat.shader = RING_SHADER
	_wrist_hp_mat.set_shader_parameter("inner_radius", 0.64)
	_wrist_hp_mat.set_shader_parameter("outer_radius", 0.92)
	_wrist_hp_mat.set_shader_parameter("segments", 10)
	_wrist_hp_mat.set_shader_parameter("glow_boost", 2.85)
	wrist_hp_ring.mesh = hp_quad
	wrist_hp_ring.material_override = _wrist_hp_mat
	wrist_hp_ring.position = Vector3(-0.034, 0.005, 0.0)
	wrist_hp_ring.rotation.x = -PI * 0.5
	wrist_hp_ring.visible = false
	wrist_hp_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wrist_hp_ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	wrist_face.add_child(wrist_hp_ring)

	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Hiragino Mincho ProN", "YuMincho", "Noto Serif CJK JP", "Hiragino Sans", "Arial Unicode MS"
	])
	wrist_label = Label3D.new()
	wrist_label.name = "WristLabel"
	wrist_label.font = sys_font
	wrist_label.font_size = 24
	wrist_label.pixel_size = 0.00042
	wrist_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	wrist_label.shaded = false
	wrist_label.double_sided = true
	wrist_label.outline_size = 6
	wrist_label.outline_modulate = Color(0.08, 0.04, 0.02, 0.95)
	wrist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wrist_label.modulate = Color(0.92, 0.90, 0.84, 0.98)
	# Float clear of the bracer plate (top at 0.0045) so glyphs never sink
	# into the lacquer or the hand mesh; depth test stays on, so the hand
	# occludes the text naturally instead of it shining through.
	wrist_label.position = Vector3(0.006, 0.012, 0.0)
	wrist_label.rotation.x = -PI * 0.5
	wrist_label.visible = false
	wrist_face.add_child(wrist_label)

	if player is XRPlayer:
		var xr := player as XRPlayer
		xr.left_controller.add_child(wrist_unit)
		wrist_unit.position = Vector3(0.0, 0.032, 0.058)
		wrist_unit.rotation = Vector3(deg_to_rad(12.0), 0.0, deg_to_rad(-22.0))
	elif player is DesktopPlayer:
		var dp := player as DesktopPlayer
		dp.set_screen_hud_visible(false)
		# The sword hand is the right. The readout stays on a left wrist in
		# front of the body, so a slash does not whip the plate out of view.
		dp.camera.add_child(wrist_unit)
		wrist_unit.position = Vector3(-0.24, -0.22, -0.32)
		wrist_unit.rotation = Vector3(deg_to_rad(50.0), deg_to_rad(16.0), 0.0)
	else:
		player.add_child(wrist_unit)


func _process(_delta: float) -> void:
	if _parry_glow > 0.0:
		_parry_glow = maxf(_parry_glow - _delta, 0.0)
		_charm_mat.emission_energy_multiplier = _charm_base_energy + _parry_glow * 2.2
	_orient_wrist_face()
	_update_label_visibility()


func _orient_wrist_face() -> void:
	if wrist_face == null or wrist_unit == null:
		return
	var cam := _view_camera
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var origin := wrist_unit.global_position
	var to_cam := cam.global_position - origin
	if to_cam.length_squared() < 1e-6:
		return
	# The plate is a flat box in local XZ. Its readable side is +Y, so that
	# axis has to point at the eyes. look_at() aims Z and was showing the edge.
	var normal := to_cam.normalized()
	var across := wrist_unit.global_transform.basis.x
	if absf(across.dot(normal)) > 0.92:
		across = wrist_unit.global_transform.basis.z
	var x_axis := across.slide(normal)
	if x_axis.length_squared() < 1e-8:
		return
	x_axis = x_axis.normalized()
	# X cross Y must be Z. The other cross mirrors the plate and the text.
	var z_axis := x_axis.cross(normal).normalized()
	wrist_face.global_transform = Transform3D(Basis(x_axis, normal, z_axis), origin)


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
		return
	var d := wrist_unit.global_position.distance_to(cam.global_position)
	var a := clampf((LABEL_HIDE_DIST - d) / maxf(LABEL_HIDE_DIST - LABEL_SHOW_DIST, 0.01), 0.0, 1.0)
	wrist_label.visible = a > 0.02
	wrist_label.modulate.a = 0.98 * a


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

	if wrist_label:
		# Engraved readout in the game's voice: rank, wave, score, life,
		# kills, souls toward the next rank.
		wrist_label.text = "位 %d · 波 %d · %d pt\n命 %d · 斬 %d · 魂 %d/%d" % [
			level, wave, score, int(round(hp)), kills, xp, xp_to_next]
