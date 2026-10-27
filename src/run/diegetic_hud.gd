class_name DiegeticHud
extends Node3D
## Minimal diegetic HUD (docs/GDD.md §6, NIGHT_PLAN.md §1):
## - XP ring inlaid around the katana tsuba (guard)
## - Glowing HP charm (omamori bead) + XP ring + engraved time & score readout on
##   the player's wrist kote bracer (no floating 2D screen-space UI).

const RING_SHADER := preload("res://src/shaders/hud_ring.gdshader")
const WET_SURFACE_SHADER := preload("res://src/shaders/wet_surface.gdshader")

var tsuba_ring: MeshInstance3D
var tsuba_ring_front: MeshInstance3D
var wrist_unit: Node3D
var hp_charm_mesh: MeshInstance3D
var wrist_hp_ring: MeshInstance3D
var wrist_label: Label3D

var _tsuba_mat := ShaderMaterial.new()
var _wrist_hp_mat := ShaderMaterial.new()
var _charm_mat := StandardMaterial3D.new()
var _lacquer_mat := ShaderMaterial.new()
var _trim_mat := ShaderMaterial.new()
var _parry_glow := 0.0


func setup(player: Node3D, katana: HeldWeapon) -> void:
	# Hide any 2D debug CanvasLayer on the desktop player so the HUD is 100% diegetic.
	if player:
		for layer in player.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false

	_setup_tsuba_ring(katana)
	_setup_wrist_unit(player)
	update_hud(100.0, 100.0, 0, 30, 1, 1, 0, 0, 0.0, Elements.NONE)


func _setup_tsuba_ring(katana: HeldWeapon) -> void:
	if katana == null:
		return
	for n_name in ["TsubaXpRing", "TsubaXpRingFront"]:
		var existing := katana.get_node_or_null(n_name)
		if existing:
			existing.queue_free()

	var quad := QuadMesh.new()
	# Outer diameter 0.126 m wraps cleanly outside the 0.092 m bronze tsuba disc.
	quad.size = Vector2(0.126, 0.126)
	_tsuba_mat.shader = RING_SHADER
	_tsuba_mat.set_shader_parameter("inner_radius", 0.64)
	_tsuba_mat.set_shader_parameter("outer_radius", 0.92)
	_tsuba_mat.set_shader_parameter("segments", 10)
	_tsuba_mat.set_shader_parameter("glow_boost", 2.35)
	_tsuba_mat.set_shader_parameter("fill_color", Color(0.35, 0.88, 1.0))

	tsuba_ring = MeshInstance3D.new()
	tsuba_ring.name = "TsubaXpRing"
	tsuba_ring.mesh = quad
	tsuba_ring.material_override = _tsuba_mat
	tsuba_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tsuba_ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Placed on the handle side of the tsuba (guard_z = -0.085), tilted slightly toward the wielder's eyes.
	tsuba_ring.position = Vector3(0.0, 0.004, katana.guard_z + 0.008)
	tsuba_ring.rotation.x = deg_to_rad(-18.0)
	katana.add_child(tsuba_ring)

	tsuba_ring_front = MeshInstance3D.new()
	tsuba_ring_front.name = "TsubaXpRingFront"
	tsuba_ring_front.mesh = quad
	tsuba_ring_front.material_override = _tsuba_mat
	tsuba_ring_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tsuba_ring_front.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	tsuba_ring_front.position = Vector3(0.0, 0.002, katana.guard_z - 0.008)
	katana.add_child(tsuba_ring_front)


func _setup_wrist_unit(player: Node3D) -> void:
	if player == null:
		return
	wrist_unit = Node3D.new()
	wrist_unit.name = "DiegeticWristUnit"

	# Matte dark-lacquer wrist bracer plate with moonlit sky fill.
	_lacquer_mat.shader = WET_SURFACE_SHADER
	_lacquer_mat.set_shader_parameter("base_color", Color(0.09, 0.09, 0.14))
	_lacquer_mat.set_shader_parameter("roughness_dry", 0.72)
	_lacquer_mat.set_shader_parameter("roughness_wet", 0.36)
	_lacquer_mat.set_shader_parameter("wetness", 0.45)
	_lacquer_mat.set_shader_parameter("waterline_y", -10.0)
	_lacquer_mat.set_shader_parameter("fill", 1.75)

	# Vermilion-lacquer shrine trim on top & bottom edges of the wrist plate.
	_trim_mat.shader = WET_SURFACE_SHADER
	_trim_mat.set_shader_parameter("base_color", Color(0.34, 0.28, 0.16))
	_trim_mat.set_shader_parameter("roughness_dry", 0.68)
	_trim_mat.set_shader_parameter("roughness_wet", 0.34)
	_trim_mat.set_shader_parameter("wetness", 0.45)
	_trim_mat.set_shader_parameter("waterline_y", -10.0)
	_trim_mat.set_shader_parameter("fill", 1.8)

	var bracer := MeshInstance3D.new()
	bracer.name = "BracerPlate"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.132, 0.012, 0.072)
	bracer.mesh = bm
	bracer.material_override = _lacquer_mat
	bracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bracer.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	wrist_unit.add_child(bracer)

	for sz in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.136, 0.015, 0.006)
		rail.mesh = rm
		rail.position = Vector3(0.0, 0.001, 0.035 * sz)
		rail.material_override = _trim_mat
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rail.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		wrist_unit.add_child(rail)

	# Glowing HP Charm (spirit bead set on the left of the wrist bracer).
	_charm_mat.albedo_color = Color(0.2, 0.9, 0.75)
	_charm_mat.roughness = 0.35
	_charm_mat.emission_enabled = true
	_charm_mat.emission = Color(0.25, 0.95, 0.78)
	_charm_mat.emission_energy_multiplier = 1.8

	hp_charm_mesh = MeshInstance3D.new()
	hp_charm_mesh.name = "HPCharm"
	var sphere := SphereMesh.new()
	sphere.radius = 0.012
	sphere.height = 0.020
	sphere.radial_segments = 12
	sphere.rings = 6
	hp_charm_mesh.mesh = sphere
	hp_charm_mesh.material_override = _charm_mat
	hp_charm_mesh.position = Vector3(-0.040, 0.008, 0.0)
	hp_charm_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hp_charm_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	wrist_unit.add_child(hp_charm_mesh)

	# Outer HP ring around the charm.
	wrist_hp_ring = MeshInstance3D.new()
	wrist_hp_ring.name = "WristHpRing"
	var hp_quad := QuadMesh.new()
	hp_quad.size = Vector2(0.048, 0.048)
	_wrist_hp_mat.shader = RING_SHADER
	_wrist_hp_mat.set_shader_parameter("inner_radius", 0.64)
	_wrist_hp_mat.set_shader_parameter("outer_radius", 0.92)
	_wrist_hp_mat.set_shader_parameter("segments", 10)
	wrist_hp_ring.mesh = hp_quad
	wrist_hp_ring.material_override = _wrist_hp_mat
	wrist_hp_ring.position = Vector3(-0.040, 0.007, 0.0)
	wrist_hp_ring.rotation.x = -PI * 0.5
	wrist_hp_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wrist_hp_ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	wrist_unit.add_child(wrist_hp_ring)

	# Inner XP ring around the charm.
	# Engraved wrist readout (time, score, level) on the lacquer bracer.
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Hiragino Mincho ProN", "YuMincho", "Noto Serif CJK JP", "Hiragino Sans", "Arial Unicode MS"
	])
	wrist_label = Label3D.new()
	wrist_label.name = "WristLabel"
	wrist_label.font = sys_font
	wrist_label.font_size = 26
	wrist_label.pixel_size = 0.00038
	wrist_label.shaded = false
	wrist_label.double_sided = true
	wrist_label.outline_size = 6
	wrist_label.outline_modulate = Color(0.01, 0.01, 0.02, 0.95)
	wrist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wrist_label.modulate = Color(0.82, 0.86, 0.92, 0.92)
	wrist_label.position = Vector3(0.008, 0.008, 0.0)
	wrist_label.rotation.x = -PI * 0.5
	wrist_unit.add_child(wrist_label)

	if player is XRPlayer:
		var xr := player as XRPlayer
		xr.left_controller.add_child(wrist_unit)
		wrist_unit.position = Vector3(0.0, 0.028, 0.065)
		wrist_unit.rotation = Vector3(deg_to_rad(15.0), 0.0, deg_to_rad(-25.0))
	elif player is DesktopPlayer:
		var dp := player as DesktopPlayer
		dp.set_screen_hud_visible(false)
		dp.camera.add_child(wrist_unit)
		# Held on the lower-left forearm in peripheral view, angled toward the eyes.
		wrist_unit.position = Vector3(-0.22, -0.165, -0.38)
		wrist_unit.rotation = Vector3(deg_to_rad(62.0), deg_to_rad(16.0), deg_to_rad(-8.0))
	else:
		player.add_child(wrist_unit)


func _process(delta: float) -> void:
	if _parry_glow > 0.0:
		_parry_glow = maxf(_parry_glow - delta, 0.0)


## Brief tsuba ring flare when the player lands a parry (GDD §4).
func on_parry() -> void:
	_parry_glow = 0.42


func update_hud(hp: float, max_hp: float, xp: int, xp_to_next: int, level: int, wave: int, score: int, kills: int, run_seconds: float, active_element: String) -> void:
	var xp_ratio := clampf(float(xp) / float(maxi(xp_to_next, 1)), 0.0, 1.0)
	var hp_ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)

	var elem_col := Color(0.36, 0.88, 1.0)
	if active_element != Elements.NONE:
		elem_col = SoulOrb.orb_color(active_element)

	_tsuba_mat.set_shader_parameter("fill_ratio", xp_ratio)
	_tsuba_mat.set_shader_parameter("fill_color", elem_col)
	_tsuba_mat.set_shader_parameter("glow_boost", 2.35 + _parry_glow * 6.0)
	var hp_col := Color(0.26, 0.95, 0.76)
	if hp_ratio < 0.35:
		hp_col = Color(1.0, 0.20, 0.16)
	elif hp_ratio < 0.65:
		hp_col = Color(1.0, 0.72, 0.24)
	_wrist_hp_mat.set_shader_parameter("fill_ratio", hp_ratio)
	_wrist_hp_mat.set_shader_parameter("fill_color", hp_col)
	_charm_mat.albedo_color = hp_col * 0.85
	_charm_mat.emission = hp_col
	_charm_mat.emission_energy_multiplier = 0.7 + hp_ratio * 1.5

	if wrist_label:
		var mins := int(run_seconds) / 60
		var secs := int(run_seconds) % 60
		wrist_label.text = "LV %d · 波 %d\n%02d:%02d · %d pt · 斬 %d" % [level, wave, mins, secs, score, kills]
