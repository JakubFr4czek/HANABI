class_name OfudaTalisman
extends Node3D
## Floating paper talisman (Ofuda, docs/GDD.md §6, NIGHT_PLAN.md §1).
##
## Hovers in front of the player during a slow-motion level-up (or as the
## Restart talisman on the run-over screen). Slicing it with the katana splits
## it in two glowing halves (preserving the inscribed kanji & text on each half)
## and selects the upgrade.

signal sliced(ofuda: OfudaTalisman, upgrade: Dictionary)

const SHADER := preload("res://src/shaders/ofuda.gdshader")
const WIDTH := 0.26
const HEIGHT := 0.56

var upgrade: Dictionary = {}
var index := 0
var is_sliced := false
var is_dismissed := false

var _card_root := Node3D.new()
var _mesh_inst := MeshInstance3D.new()
var _mat := ShaderMaterial.new()
var _body := StaticBody3D.new()
var _header_lbl: Label3D
var _kanji_lbl: Label3D
var _title_lbl: Label3D
var _sub_lbl: Label3D
var _clock := 0.0
var _phase := 0.0
var _fade := 1.0
var _upper_half: MeshInstance3D
var _lower_half: MeshInstance3D
var _half_vel_up := Vector3.ZERO
var _half_vel_down := Vector3.ZERO
var _prev_blade_tips := {}  # weapon -> Vector3
var _prev_blade_starts := {}  # weapon -> Vector3


func setup(p_upgrade: Dictionary, p_index: int = 0) -> void:
	upgrade = p_upgrade.duplicate()
	index = p_index
	_phase = float(p_index) * 1.35


func _ready() -> void:
	add_to_group("ofuda_talismans")
	add_child(_card_root)

	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	_mat.shader = SHADER
	var accent: Color = upgrade.get("color", Color(1.0, 0.32, 0.24))
	_mat.set_shader_parameter("accent_color", accent)
	_mesh_inst.mesh = quad
	_mesh_inst.material_override = _mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_card_root.add_child(_mesh_inst)

	_build_labels(accent)
	_build_collider()


func _build_labels(accent: Color) -> void:
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Hiragino Mincho ProN", "YuMincho", "Songti SC", "Noto Serif CJK JP", "Hiragino Sans", "Arial Unicode MS"
	])

	var stack_num := int(upgrade.get("next_stack", 1))
	var header_text: String = String(upgrade.get("header", "御札 · TIER %d" % stack_num))
	_header_lbl = make_label(header_text, sys_font, 26, 0.0011, Color(0.88, 0.78, 0.56), Vector3(0, 0.21, 0.004))
	_card_root.add_child(_header_lbl)

	var kanji_str := String(upgrade.get("kanji", "斬"))
	var kanji_col := Color(accent.r * 1.45 + 0.18, accent.g * 1.45 + 0.18, accent.b * 1.45 + 0.18, 1.0)
	_kanji_lbl = make_label(kanji_str, sys_font, 114, 0.00145, kanji_col, Vector3(0, 0.068, 0.005))
	_card_root.add_child(_kanji_lbl)

	var title_str := String(upgrade.get("title", "UPGRADE"))
	_title_lbl = make_label(title_str, sys_font, 34, 0.00105, Color(0.97, 0.96, 0.99), Vector3(0, -0.095, 0.004))
	_card_root.add_child(_title_lbl)

	var sub_str := String(upgrade.get("subtitle", ""))
	_sub_lbl = make_label(sub_str, sys_font, 26, 0.00095, Color(0.78, 0.84, 0.94), Vector3(0, -0.165, 0.004))
	_card_root.add_child(_sub_lbl)


static func make_label(txt: String, font: Font, fsize: int, psize: float, col: Color, pos: Vector3) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font = font
	lbl.font_size = fsize
	lbl.pixel_size = psize
	lbl.modulate = col
	lbl.shaded = false
	lbl.double_sided = true
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0.01, 0.01, 0.02, 0.95)
	lbl.position = pos
	return lbl


func _build_collider() -> void:
	# Layer 4 (bit 8 = enemy_body) so HeldWeapon contacts report hits on it.
	_body.name = "OfudaBody"
	_body.collision_layer = 8
	_body.collision_mask = 0
	_body.set_meta("hit_receiver", self)
	_body.set_meta("body_part", "ofuda")
	_body.set_meta("zone", "torso")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH * 1.15, HEIGHT * 1.1, 0.08)
	cs.shape = box
	_body.add_child(cs)
	_card_root.add_child(_body)


## Called when HeldWeapon's contact solver hits this Ofuda.
func receive_hit(_part: Node, hit: Dictionary) -> Dictionary:
	var pt: Vector3 = hit.get("point", global_position)
	var dir: Vector3 = hit.get("direction", Vector3.RIGHT)
	slice(pt, dir)
	hit["damage"] = 0.0
	return hit


## Slice this Ofuda in half and emit [signal sliced].
func slice(cut_point: Vector3 = Vector3.ZERO, cut_dir: Vector3 = Vector3.RIGHT) -> void:
	if is_sliced or is_dismissed:
		return
	is_sliced = true
	_body.collision_layer = 0
	var world_pt := cut_point if cut_point != Vector3.ZERO else global_position
	var accent: Color = upgrade.get("color", Color(1.0, 0.35, 0.25))
	Sfx.play_at("ofuda_slice", world_pt, -2.0, 3.5)
	Sfx.play_at("cut", world_pt, 0.5)
	Sfx.play_at("blade_ring", world_pt, -3.0)
	if is_inside_tree() and get_tree().current_scene:
		SparkBurst.spawn(get_tree().current_scene, world_pt, cut_dir, accent * 1.45, 22, 3.4)
		var elem := String(upgrade.get("element", Elements.NONE))
		if elem != Elements.NONE:
			ElementFirework.spawn(get_tree().current_scene, world_pt, elem, 0.75)

	# Replace whole card mesh with two separating halves carrying their labels.
	_card_root.visible = false
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	var slope := clampf(cut_dir.y * 0.35, -0.35, 0.35)

	_upper_half = MeshInstance3D.new()
	var mat_u := _mat.duplicate() as ShaderMaterial
	mat_u.set_shader_parameter("half_mode", 1)
	mat_u.set_shader_parameter("cut_slope", slope)
	_upper_half.mesh = quad
	_upper_half.material_override = mat_u
	_upper_half.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_upper_half.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_upper_half)
	if _header_lbl and is_instance_valid(_header_lbl):
		_header_lbl.reparent(_upper_half, false)
	if _kanji_lbl and is_instance_valid(_kanji_lbl):
		_kanji_lbl.reparent(_upper_half, false)

	_lower_half = MeshInstance3D.new()
	var mat_l := _mat.duplicate() as ShaderMaterial
	mat_l.set_shader_parameter("half_mode", 2)
	mat_l.set_shader_parameter("cut_slope", slope)
	_lower_half.mesh = quad
	_lower_half.material_override = mat_l
	_lower_half.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lower_half.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_lower_half)
	if _title_lbl and is_instance_valid(_title_lbl):
		_title_lbl.reparent(_lower_half, false)
	if _sub_lbl and is_instance_valid(_sub_lbl):
		_sub_lbl.reparent(_lower_half, false)

	var side_push := cut_dir.normalized() if cut_dir.length_squared() > 0.001 else Vector3.RIGHT
	_half_vel_up = Vector3(side_push.x * 0.45, 0.52, side_push.z * 0.20)
	_half_vel_down = Vector3(-side_push.x * 0.38, -0.48, -side_push.z * 0.20)

	sliced.emit(self, upgrade)


## Fade out without being chosen (when a sibling Ofuda was sliced).
func dismiss() -> void:
	if is_sliced or is_dismissed:
		return
	is_dismissed = true
	_body.collision_layer = 0


func _physics_process(_delta: float) -> void:
	# Advance in real time so animations and blade-slice detection work smoothly
	# during level-up slow motion.
	var dt := TimeController.real_tick()
	_clock += dt

	if is_sliced:
		_fade = maxf(_fade - dt * 2.2, 0.0)
		if _upper_half and _lower_half:
			_upper_half.position += _half_vel_up * dt
			_upper_half.rotation.z += 1.3 * dt
			_lower_half.position += _half_vel_down * dt
			_lower_half.rotation.z -= 1.15 * dt
			(_upper_half.material_override as ShaderMaterial).set_shader_parameter("opacity", _fade)
			(_lower_half.material_override as ShaderMaterial).set_shader_parameter("opacity", _fade)
			for lbl in [_header_lbl, _kanji_lbl, _title_lbl, _sub_lbl]:
				if lbl and is_instance_valid(lbl):
					lbl.modulate.a = _fade
		if _fade <= 0.02:
			queue_free()
		return

	if is_dismissed:
		_fade = maxf(_fade - dt * 3.5, 0.0)
		_mat.set_shader_parameter("opacity", _fade)
		_card_root.position.y -= dt * 0.25
		for lbl in [_header_lbl, _kanji_lbl, _title_lbl, _sub_lbl]:
			if lbl and is_instance_valid(lbl):
				lbl.modulate.a = _fade
		if _fade <= 0.02:
			queue_free()
		return

	# Gentle floating hover in slow motion on the inner card root so global_position stays intact.
	_card_root.position.y = sin(_clock * 2.4 + _phase) * 0.022
	_card_root.rotation.z = sin(_clock * 1.7 + _phase) * 0.025
	_mat.set_shader_parameter("glow_strength", 1.55 + sin(_clock * 2.8 + _phase) * 0.28)

	_check_blade_slice(dt)


func _check_blade_slice(real_dt: float) -> void:
	for w in get_tree().get_nodes_in_group("player_weapons"):
		var weapon := w as HeldWeapon
		if weapon == null or not weapon.is_held():
			_prev_blade_tips.erase(w)
			_prev_blade_starts.erase(w)
			continue
		var tip := weapon.get_tip_global()
		var start := weapon.get_blade_start_global()
		var prev_tip: Vector3 = _prev_blade_tips.get(w, tip)
		var prev_start: Vector3 = _prev_blade_starts.get(w, start)
		_prev_blade_tips[w] = tip
		_prev_blade_starts[w] = start
		var tip_speed := tip.distance_to(prev_tip) / maxf(real_dt, 1e-4)
		var speed := maxf(weapon.measured_tip_speed, tip_speed)
		if speed < 1.1:
			continue
		# Check if the blade segment [start, tip] passes through the Ofuda's local rectangle.
		var inv := _card_root.global_transform.affine_inverse()
		var local_a := inv * start
		var local_b := inv * tip
		var candidates: Array[Vector3] = [
			Geometry3D.get_closest_point_to_segment(Vector3.ZERO, local_a, local_b),
			Geometry3D.get_closest_point_to_segment(Vector3.ZERO, inv * prev_tip, local_b),
			Geometry3D.get_closest_point_to_segment(Vector3.ZERO, inv * prev_start, local_a),
		]
		for closest in candidates:
			# A fast VR cut is judged by the swept blade with a small hand-tracking
			# allowance around the narrow paper, not a single-frame point sample.
			if absf(closest.x) <= WIDTH * 0.90 and absf(closest.y) <= HEIGHT * 0.58 and absf(closest.z) <= 0.16:
				var dir := (tip - prev_tip).normalized() if tip.distance_to(prev_tip) > 0.001 else Vector3.RIGHT
				slice(_card_root.global_transform * closest, dir)
				return
