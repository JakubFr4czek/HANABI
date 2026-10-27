class_name ToriiGate
extends Node3D
## Interactive elemental Torii gate for the endless forest (docs/ELEMENTS_PLAN.md).
## Imbues the player's katana with an element (~20 s) upon crossing the gate plane.
## Deactivates upon crossing and reactivates only after the player moves >= 45.0 m away.

signal gate_crossed(element: String, gate: ToriiGate)
signal gate_state_changed(is_active: bool)

const APERTURE_WIDTH: float = 2.8
const APERTURE_HEIGHT: float = 3.2
const APERTURE_DEPTH: float = 0.6
const REACTIVATION_DISTANCE: float = 45.0
const CLEARANCE_RADIUS: float = 3.2
const CLEARANCE_HEIGHT: float = 4.5
const PLAYER_BODY_LAYER: int = 1 << 19

const TORII_SCENE := preload("res://assets/models/environment/forest_quaternius/torii_gate_polyfork.glb")
const WET_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const HALO_SHADER := preload("res://src/shaders/torii_lantern_halo.gdshader")
const CHIME_AUDIO := preload("res://assets/audio/sfx/hanabi_proc/torii_furin_chime.wav")

@export var element: String = Elements.SAKURA:
	set(val):
		element = val
		_apply_element_style()

@export var is_active: bool = true:
	set(val):
		if is_active != val:
			is_active = val
			_apply_active_state()
			gate_state_changed.emit(is_active)

var _gate_mesh: MeshInstance3D
var _gate_mat: ShaderMaterial
var _lantern_core: MeshInstance3D
var _lantern_mat: StandardMaterial3D
var _halo_mesh: MeshInstance3D
var _halo_mat: ShaderMaterial
var _chime_player: AudioStreamPlayer3D
var _crossing_area: Area3D
var _static_body: StaticBody3D

var _tracked_bodies: Dictionary = {}  # Node3D -> Vector3 (prev world pos)
var _player_ref: Node3D = null
var _prev_player_pos := Vector3.INF
var _chime_cooldown: float = 1.0


func _ready() -> void:
	add_to_group("torii_gates")
	_build_components()
	_apply_element_style()
	_apply_active_state()


func _build_components() -> void:
	# Gate Mesh
	if _gate_mesh == null:
		var raw = TORII_SCENE.instantiate()
		var mesh_inst: MeshInstance3D = null
		for child in raw.get_children():
			if child is MeshInstance3D:
				mesh_inst = child
				break
			for sub in child.get_children():
				if sub is MeshInstance3D:
					mesh_inst = sub
					break
		if mesh_inst and mesh_inst.mesh:
			_gate_mesh = MeshInstance3D.new()
			_gate_mesh.name = "GateMesh"
			_gate_mesh.mesh = mesh_inst.mesh
			_gate_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(_gate_mesh)
		raw.queue_free()

	_gate_mat = ShaderMaterial.new()
	_gate_mat.shader = WET_SHADER
	_gate_mat.set_shader_parameter("roughness_dry", 0.84)
	_gate_mat.set_shader_parameter("roughness_wet", 0.72)
	_gate_mat.set_shader_parameter("wetness", 0.28)
	_gate_mat.set_shader_parameter("waterline_y", -10.0)
	_gate_mat.set_shader_parameter("fill", 0.35)
	_gate_mat.set_shader_parameter("specular_scale", 0.0)
	_gate_mat.set_shader_parameter("fog_fill", 0.22)
	_gate_mat.set_shader_parameter("procedural_ao", 0.55)
	if _gate_mesh:
		_gate_mesh.material_override = _gate_mat

	# Static collision: 2 pillars and top lintel beam
	if _static_body == null:
		_static_body = StaticBody3D.new()
		_static_body.name = "ToriiCollision"
		_static_body.collision_layer = 1 | 64  # Environment & Trunk layer
		_static_body.collision_mask = 0
		add_child(_static_body)

		# Left Pillar
		var left_col := CollisionShape3D.new()
		var left_cyl := CylinderShape3D.new()
		left_cyl.radius = 0.18
		left_cyl.height = 3.2
		left_col.shape = left_cyl
		left_col.position = Vector3(-1.15, 1.6, 0.0)
		_static_body.add_child(left_col)

		# Right Pillar
		var right_col := CollisionShape3D.new()
		var right_cyl := CylinderShape3D.new()
		right_cyl.radius = 0.18
		right_cyl.height = 3.2
		right_col.shape = right_cyl
		right_col.position = Vector3(1.15, 1.6, 0.0)
		_static_body.add_child(right_col)

		# Lintel Beam
		var beam_col := CollisionShape3D.new()
		var beam_box := BoxShape3D.new()
		beam_box.size = Vector3(2.8, 0.45, 0.45)
		beam_col.shape = beam_box
		beam_col.position = Vector3(0.0, 3.0, 0.0)
		_static_body.add_child(beam_col)

	# Hanging Lantern
	var lantern_anchor := Node3D.new()
	lantern_anchor.name = "Lantern"
	lantern_anchor.position = Vector3(-0.95, 2.55, 0.0)
	add_child(lantern_anchor)

	_lantern_core = MeshInstance3D.new()
	_lantern_core.name = "LanternCore"
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.26, 0.18)
	_lantern_core.mesh = box
	_lantern_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lantern_mat = StandardMaterial3D.new()
	_lantern_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lantern_core.material_override = _lantern_mat
	lantern_anchor.add_child(_lantern_core)

	# Fog-piercing unshaded volumetric halo
	_halo_mesh = MeshInstance3D.new()
	_halo_mesh.name = "VolumetricHalo"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 1.8)
	_halo_mesh.mesh = quad
	_halo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = HALO_SHADER
	_halo_mesh.material_override = _halo_mat
	lantern_anchor.add_child(_halo_mesh)

	# Spatialized 3D Wind Chime (fūrin)
	if _chime_player == null:
		_chime_player = AudioStreamPlayer3D.new()
		_chime_player.name = "ChimePlayer"
		_chime_player.stream = CHIME_AUDIO
		_chime_player.unit_size = 3.5
		_chime_player.max_distance = 40.0
		_chime_player.max_polyphony = 1
		_chime_player.bus = "Ambience"
		_chime_player.position = Vector3(0.0, 2.8, 0.0)
		add_child(_chime_player)

	# Crossing Trigger Volume (filters for PLAYER_BODY_LAYER only)
	if _crossing_area == null:
		_crossing_area = Area3D.new()
		_crossing_area.name = "CrossingArea"
		_crossing_area.collision_layer = 0
		_crossing_area.collision_mask = PLAYER_BODY_LAYER
		_crossing_area.monitorable = false
		add_child(_crossing_area)

		var area_shape := CollisionShape3D.new()
		var area_box := BoxShape3D.new()
		area_box.size = Vector3(APERTURE_WIDTH, APERTURE_HEIGHT, APERTURE_DEPTH)
		area_shape.shape = area_box
		area_shape.position = Vector3(0.0, APERTURE_HEIGHT * 0.5, 0.0)
		_crossing_area.add_child(area_shape)

		_crossing_area.body_entered.connect(_on_body_entered)
		_crossing_area.body_exited.connect(_on_body_exited)


func _apply_element_style() -> void:
	if _gate_mat == null or _lantern_mat == null or _halo_mat == null:
		return
	var timber_color: Color
	var accent: Color
	match element:
		Elements.SAKURA:
			timber_color = Color(0.28, 0.06, 0.05)
			accent = Elements.accent_color(Elements.SAKURA)
		Elements.STORM:
			timber_color = Color(0.08, 0.08, 0.10)
			accent = Elements.accent_color(Elements.STORM)
		Elements.INK:
			timber_color = Color(0.03, 0.03, 0.03)
			accent = Elements.accent_color(Elements.INK)
		Elements.SHADOW:
			timber_color = Color(0.18, 0.16, 0.22)
			accent = Elements.accent_color(Elements.SHADOW)
		_:
			timber_color = Color(0.24, 0.08, 0.07)
			accent = Color(0.9, 0.85, 0.8)

	_gate_mat.set_shader_parameter("base_color", timber_color)
	_lantern_mat.albedo_color = accent
	_halo_mat.set_shader_parameter("glow_color", accent)


func _apply_active_state() -> void:
	if _lantern_mat:
		_lantern_mat.emission_enabled = is_active
		if is_active:
			_lantern_mat.emission = Elements.accent_color(element)
	if _halo_mesh:
		_halo_mesh.visible = is_active
	if not is_active and _chime_player:
		_chime_player.stop()


func _on_body_entered(body: Node3D) -> void:
	# Filter: only track nodes that belong to player body, never weapons
	if body is BladeBody or body is HeldWeapon:
		return
	_tracked_bodies[body] = body.global_position


func _on_body_exited(body: Node3D) -> void:
	_tracked_bodies.erase(body)


func _physics_process(delta: float) -> void:
	var player_pos := _resolve_player_pos()

	if is_active:
		# Ambient chime playback when player is within hearing range (< 40m)
		if player_pos != Vector3.INF and global_position.distance_to(player_pos) <= 40.0:
			_chime_cooldown -= delta
			if _chime_cooldown <= 0.0:
				_chime_cooldown = randf_range(3.2, 5.0)
				if _chime_player and not _chime_player.playing:
					_chime_player.play()

		# Check plane crossing for tracked bodies
		for body in _tracked_bodies.keys():
			if not is_instance_valid(body):
				_tracked_bodies.erase(body)
				continue
			var p_curr: Vector3 = body.global_position
			var p_prev: Vector3 = _tracked_bodies.get(body, p_curr)
			_tracked_bodies[body] = p_curr
			if _eval_crossing(p_prev, p_curr):
				trigger_cross(body)
				return

		# Check direct player plane crossing if player position is known
		if player_pos != Vector3.INF and _prev_player_pos != Vector3.INF:
			if global_position.distance_to(player_pos) <= 4.0:
				if _eval_crossing(_prev_player_pos, player_pos):
					trigger_cross(_player_ref)
					return
		_prev_player_pos = player_pos
	else:
		# 45.0m Reactivation Rule: reactivates iff player moves >= 45.0m away
		if player_pos != Vector3.INF:
			var d := global_position.distance_to(player_pos)
			if d >= REACTIVATION_DISTANCE:
				reactivate()


func _eval_crossing(prev_pos: Vector3, curr_pos: Vector3) -> bool:
	var l_curr := to_local(curr_pos)
	# 1. Direct aperture volume presence (with vertical tolerance for terrain slopes / head / feet)
	if absf(l_curr.x) <= APERTURE_WIDTH * 0.5 and l_curr.y >= -1.0 and l_curr.y <= APERTURE_HEIGHT + 1.0 and absf(l_curr.z) <= APERTURE_DEPTH:
		return true

	# 2. Continuous segment plane crossing
	var l_prev := to_local(prev_pos)
	if (l_prev.z > 0.0 and l_curr.z <= 0.0) or (l_prev.z < 0.0 and l_curr.z >= 0.0):
		var dz := l_curr.z - l_prev.z
		var alpha := -l_prev.z / dz if absf(dz) > 1e-5 else 0.5
		var cross_pt := l_prev.lerp(l_curr, alpha)
		if absf(cross_pt.x) <= APERTURE_WIDTH * 0.5 and cross_pt.y >= -1.0 and cross_pt.y <= APERTURE_HEIGHT + 1.0:
			return true
	return false


func trigger_cross(body: Node = null) -> void:
	if not is_active:
		return
	is_active = false
	# Imbue player's katana / element system
	_imbue_target(body)
	gate_crossed.emit(element, self)
	GameEvents.log_event("torii_gate_crossed", {"element": element, "position": global_position})


var target_element_system: ElementSystem = null
var target_weapon: HeldWeapon = null

func _imbue_target(body: Node) -> void:
	if target_element_system and is_instance_valid(target_element_system):
		target_element_system.imbue(element, ElementSystem.ELEMENT_DURATION)
		return
	if target_weapon and is_instance_valid(target_weapon):
		target_weapon.imbue_element(element, HeldWeapon.ELEMENT_DURATION)
		return
	var run := _find_run_game()
	if run and run.element_system and is_instance_valid(run.element_system):
		run.element_system.imbue(element, ElementSystem.ELEMENT_DURATION)
		return
	if run and run.katana and is_instance_valid(run.katana):
		run.katana.imbue_element(element, HeldWeapon.ELEMENT_DURATION)
		return
	# Search scene tree for ElementSystem or HeldWeapon (prefer ElementSystem)
	var scene := get_tree().current_scene if get_tree() else null
	if scene:
		for child in scene.get_children():
			if child is ElementSystem:
				child.imbue(element, ElementSystem.ELEMENT_DURATION)
				return
		for child in scene.get_children():
			if child is HeldWeapon:
				child.imbue_element(element, HeldWeapon.ELEMENT_DURATION)
				return
	if body and body.has_method("imbue_element"):
		body.call("imbue_element", element)
	elif body and body.get_parent() and body.get_parent().has_method("imbue_element"):
		body.get_parent().call("imbue_element", element)


func reactivate() -> void:
	if not is_active:
		is_active = true
		_chime_cooldown = 0.5


var run_game: RunGame = null

func _find_run_game() -> RunGame:
	if run_game and is_instance_valid(run_game):
		return run_game
	var p: Node = get_parent()
	while p:
		if p is RunGame:
			run_game = p
			return run_game
		p = p.get_parent()
	var scene := get_tree().current_scene if get_tree() else null
	if scene:
		if scene is RunGame:
			run_game = scene
			return run_game
		for child in scene.get_children():
			if child is RunGame:
				run_game = child
				return run_game
	return null


func _resolve_player_pos() -> Vector3:
	if _player_ref and is_instance_valid(_player_ref):
		if _player_ref is XRPlayer:
			return (_player_ref as XRPlayer).feet_position()
		return _player_ref.global_position

	var run := _find_run_game()
	if run and run.player and is_instance_valid(run.player):
		_player_ref = run.player
		if _player_ref is XRPlayer:
			return (_player_ref as XRPlayer).feet_position()
		return _player_ref.global_position

	var p = get_tree().get_first_node_in_group("player")
	if p and is_instance_valid(p):
		_player_ref = p as Node3D
		return _player_ref.global_position
	return Vector3.INF


func set_player_reference(p: Node3D) -> void:
	_player_ref = p
	if _player_ref:
		_prev_player_pos = _resolve_player_pos()
