class_name ToriiGate
extends Node3D
## Interactive Torii Gate Scene for Hanabi (docs/ELEMENTS_PLAN.md Phase E2a).
##
## Implements:
## - Authentic Shinto Myōjin architecture: curved Kasagi with sori & upturned eaves,
##   Shimaki, through-Nuki with kusabi wedges, Gakuzuka plaque strut, slightly inclined
##   Hashira (uchikorobi), and carved octagonal granite Daiishi foundation plinths.
## - Distinct element aesthetics in GDD palette (Sakura, Storm, Ink, Shadow).
## - Unshaded additive volumetric lantern halo piercing 10.5m milk fog up to 35m (fog_disabled).
## - Spatialized 3D wind chime (fūrin) for natural audio localization without UI arrows.
## - Plane crossing detection by player body (filtering out weapons and hands).
## - 45.0m distance reactivation rule.

signal gate_crossed(element: String, gate: ToriiGate)

const WET_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const HALO_SHADER := preload("res://src/shaders/torii_lantern_halo.gdshader")
const CHIME_AUDIO := preload("res://assets/audio/sfx/hanabi_proc/torii_furin_chime.wav")

const APERTURE_WIDTH: float = 2.4
const APERTURE_HEIGHT: float = 3.2
const APERTURE_DEPTH: float = 0.8
const CLEARANCE_RADIUS: float = 3.2
const REACTIVATION_DISTANCE: float = 45.0
const PLAYER_BODY_LAYER: int = XRPlayer.COLLISION_LAYER_BODY

@export var element: String = Elements.SAKURA:
	set(val):
		element = val
		_apply_element_style()

@export var is_active: bool = true:
	set(val):
		is_active = val
		_apply_active_state()

var _gate_mesh: MeshInstance3D
var _stone_mesh: MeshInstance3D
var _lantern_core: MeshInstance3D
var _lantern_frame: MeshInstance3D
var _halo_mesh: MeshInstance3D
var _crossing_area: Area3D
var _static_body: StaticBody3D
var _chime_player: AudioStreamPlayer3D

var _gate_mat: ShaderMaterial
var _stone_mat: ShaderMaterial
var _lantern_mat: StandardMaterial3D
var _halo_mat: ShaderMaterial

var _tracked_bodies: Dictionary = {} # Node -> Vector3 (previous pos)
var _player_ref: Node3D = null
var _prev_player_pos: Vector3 = Vector3.INF
var _chime_cooldown: float = 0.5


func _ready() -> void:
	add_to_group("torii_gates")
	_build_components()
	_apply_element_style()
	_apply_active_state()


func _build_components() -> void:
	# 1. Authentic Shinto Timber Mesh (Kasagi, Shimaki, Nuki, Gakuzuka, Hashira)
	if _gate_mesh == null:
		_gate_mesh = MeshInstance3D.new()
		_gate_mesh.name = "TimberMesh"
		_gate_mesh.mesh = _build_authentic_torii_mesh()
		_gate_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_gate_mesh)

	_gate_mat = ShaderMaterial.new()
	_gate_mat.shader = WET_SHADER
	_gate_mat.set_shader_parameter("roughness_dry", 0.78)
	_gate_mat.set_shader_parameter("roughness_wet", 0.62)
	_gate_mat.set_shader_parameter("wetness", 0.28)
	_gate_mat.set_shader_parameter("waterline_y", -10.0)
	_gate_mat.set_shader_parameter("fill", 0.35)
	_gate_mat.set_shader_parameter("specular_scale", 0.0)
	_gate_mat.set_shader_parameter("fog_fill", 0.22)
	_gate_mat.set_shader_parameter("procedural_ao", 0.65)
	_gate_mesh.material_override = _gate_mat

	# 2. Carved Granite Daiishi Foundation Plinths
	if _stone_mesh == null:
		_stone_mesh = MeshInstance3D.new()
		_stone_mesh.name = "StonePlinths"
		_stone_mesh.mesh = _build_daiishi_mesh()
		_stone_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_stone_mesh)

	_stone_mat = ShaderMaterial.new()
	_stone_mat.shader = WET_SHADER
	_stone_mat.set_shader_parameter("base_color", Color(0.18, 0.19, 0.20))
	_stone_mat.set_shader_parameter("roughness_dry", 0.90)
	_stone_mat.set_shader_parameter("roughness_wet", 0.75)
	_stone_mat.set_shader_parameter("wetness", 0.35)
	_stone_mat.set_shader_parameter("procedural_ao", 0.80)
	_stone_mesh.material_override = _stone_mat

	# 3. Static collision: 2 pillars, 2 stone plinths, and top lintel beams
	if _static_body == null:
		_static_body = StaticBody3D.new()
		_static_body.name = "ToriiCollision"
		_static_body.collision_layer = 1 | 64  # Environment & Trunk layer
		_static_body.collision_mask = 0
		add_child(_static_body)

		# Left Pillar (slightly inclined)
		var left_col := CollisionShape3D.new()
		var left_cyl := CylinderShape3D.new()
		left_cyl.radius = 0.20
		left_cyl.height = 2.8
		left_col.shape = left_cyl
		left_col.position = Vector3(-1.13, 1.75, 0.0)
		_static_body.add_child(left_col)

		# Right Pillar (slightly inclined)
		var right_col := CollisionShape3D.new()
		var right_cyl := CylinderShape3D.new()
		right_cyl.radius = 0.20
		right_cyl.height = 2.8
		right_col.shape = right_cyl
		right_col.position = Vector3(1.13, 1.75, 0.0)
		_static_body.add_child(right_col)

		# Left Stone Base
		var left_stone := CollisionShape3D.new()
		var left_stone_cyl := CylinderShape3D.new()
		left_stone_cyl.radius = 0.28
		left_stone_cyl.height = 0.36
		left_stone.shape = left_stone_cyl
		left_stone.position = Vector3(-1.15, 0.18, 0.0)
		_static_body.add_child(left_stone)

		# Right Stone Base
		var right_stone := CollisionShape3D.new()
		var right_stone_cyl := CylinderShape3D.new()
		right_stone_cyl.radius = 0.28
		right_stone_cyl.height = 0.36
		right_stone.shape = right_stone_cyl
		right_stone.position = Vector3(1.15, 0.18, 0.0)
		_static_body.add_child(right_stone)

		# Lintel Beam
		var beam_col := CollisionShape3D.new()
		var beam_box := BoxShape3D.new()
		beam_box.size = Vector3(3.4, 0.55, 0.45)
		beam_col.shape = beam_box
		beam_col.position = Vector3(0.0, 3.12, 0.0)
		_static_body.add_child(beam_col)

	# 4. Hanging Lantern (Hexagonal Tōrō)
	var lantern_anchor := Node3D.new()
	lantern_anchor.name = "Lantern"
	lantern_anchor.position = Vector3(-0.95, 2.38, 0.0)
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

	# Volumetric Lantern Halo (fog_disabled to pierce milk fog)
	_halo_mesh = MeshInstance3D.new()
	_halo_mesh.name = "VolumetricHalo"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_halo_mesh.mesh = quad
	_halo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = HALO_SHADER
	_halo_mesh.material_override = _halo_mat
	lantern_anchor.add_child(_halo_mesh)

	# 5. Spatialized 3D Wind Chime (fūrin)
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

	# 6. Crossing Trigger Volume (detects player body layer 2 + weapons layer 4/16)
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


func _build_authentic_torii_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Kasagi: Curved top roof lintel with pronounced sori curvature and flared eaves
	_add_curved_beam(st, 3.6, 0.28, 0.30, 3.12, 0.14, 0.08)

	# 2. Shimaki: Secondary curved lintel directly below kasagi
	_add_curved_beam(st, 3.15, 0.18, 0.24, 2.94, 0.08, 0.02)

	# 3. Nuki: Lower horizontal tie-beam piercing through both pillars with projecting ends
	_add_box(st, Vector3(0.0, 2.38, 0.0), Vector3(3.0, 0.20, 0.14))
	# Kusabi (wedges outside pillars)
	_add_box(st, Vector3(-1.32, 2.38, 0.0), Vector3(0.06, 0.26, 0.16))
	_add_box(st, Vector3(1.32, 2.38, 0.0), Vector3(0.06, 0.26, 0.16))

	# 4. Gakuzuka: Center tablet strut connecting Nuki to Shimaki
	_add_box(st, Vector3(0.0, 2.66, 0.0), Vector3(0.24, 0.38, 0.10))

	# 5. Hashira: Two pillars with subtle inward inclination (uchikorobi) and taper
	_add_tapered_pillar(st, Vector3(-1.15, 0.35, 0.0), Vector3(-1.11, 2.94, 0.0), 0.18, 0.15, 12)
	_add_tapered_pillar(st, Vector3(1.15, 0.35, 0.0), Vector3(1.11, 2.94, 0.0), 0.18, 0.15, 12)

	st.generate_normals()
	return st.commit()


func _build_daiishi_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Octagonal carved granite plinths at base of pillars
	_add_octagonal_plinth(st, Vector3(-1.15, 0.0, 0.0), 0.26, 0.35)
	_add_octagonal_plinth(st, Vector3(1.15, 0.0, 0.0), 0.26, 0.35)
	st.generate_normals()
	return st.commit()


func _add_curved_beam(st: SurfaceTool, length: float, height: float, depth: float, base_y: float, sori_height: float, end_flare: float) -> void:
	var segments := 16
	var hx := length * 0.5
	var hy := height * 0.5
	var hz := depth * 0.5

	var prev_ring: Array[Vector3] = []
	for i in range(segments + 1):
		var u := float(i) / float(segments)
		var x := -hx + u * length
		var nx := x / hx
		var sori := nx * nx * sori_height
		if absf(nx) > 0.85:
			sori += pow((absf(nx) - 0.85) / 0.15, 2.0) * end_flare

		var cy := base_y + sori
		var ring: Array[Vector3] = [
			Vector3(x, cy + hy, -hz),
			Vector3(x, cy + hy, hz),
			Vector3(x, cy - hy, hz),
			Vector3(x, cy - hy, -hz),
		]

		if i > 0:
			for k in 4:
				var next_k := (k + 1) % 4
				st.add_vertex(prev_ring[k])
				st.add_vertex(ring[k])
				st.add_vertex(ring[next_k])

				st.add_vertex(prev_ring[k])
				st.add_vertex(ring[next_k])
				st.add_vertex(prev_ring[next_k])

		if i == 0:
			# Left end cap
			st.add_vertex(ring[0])
			st.add_vertex(ring[2])
			st.add_vertex(ring[1])

			st.add_vertex(ring[0])
			st.add_vertex(ring[3])
			st.add_vertex(ring[2])
		elif i == segments:
			# Right end cap
			st.add_vertex(ring[0])
			st.add_vertex(ring[1])
			st.add_vertex(ring[2])

			st.add_vertex(ring[0])
			st.add_vertex(ring[2])
			st.add_vertex(ring[3])

		prev_ring = ring


func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var c := center
	var v: Array[Vector3] = [
		Vector3(-hx, -hy, -hz) + c, Vector3(hx, -hy, -hz) + c,
		Vector3(hx, hy, -hz) + c, Vector3(-hx, hy, -hz) + c,
		Vector3(-hx, -hy, hz) + c, Vector3(hx, -hy, hz) + c,
		Vector3(hx, hy, hz) + c, Vector3(-hx, hy, hz) + c,
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[1]])
		st.add_vertex(v[f[2]])

		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[2]])
		st.add_vertex(v[f[3]])


func _add_tapered_pillar(st: SurfaceTool, base_p: Vector3, top_p: Vector3, r_base: float, r_top: float, sides: int = 12) -> void:
	var base_ring: Array[Vector3] = []
	var top_ring: Array[Vector3] = []
	for i in range(sides):
		var ang := float(i) / float(sides) * TAU
		var ca := cos(ang)
		var sa := sin(ang)
		base_ring.append(base_p + Vector3(ca * r_base, 0.0, sa * r_base))
		top_ring.append(top_p + Vector3(ca * r_top, 0.0, sa * r_top))

	for i in range(sides):
		var next_i := (i + 1) % sides
		st.add_vertex(base_ring[i])
		st.add_vertex(top_ring[i])
		st.add_vertex(top_ring[next_i])

		st.add_vertex(base_ring[i])
		st.add_vertex(top_ring[next_i])
		st.add_vertex(base_ring[next_i])


func _add_octagonal_plinth(st: SurfaceTool, base_center: Vector3, radius: float, height: float) -> void:
	var sides := 8
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	var chamfer_top: Array[Vector3] = []

	var r_top := radius * 0.92
	var h_chamfer := height * 0.12

	for i in range(sides):
		var ang := (float(i) + 0.5) / float(sides) * TAU
		var ca := cos(ang)
		var sa := sin(ang)
		bottom.append(base_center + Vector3(ca * radius, 0.0, sa * radius))
		top.append(base_center + Vector3(ca * radius, height - h_chamfer, sa * radius))
		chamfer_top.append(base_center + Vector3(ca * r_top, height, sa * r_top))

	for i in range(sides):
		var next_i := (i + 1) % sides
		st.add_vertex(bottom[i])
		st.add_vertex(top[i])
		st.add_vertex(top[next_i])

		st.add_vertex(bottom[i])
		st.add_vertex(top[next_i])
		st.add_vertex(bottom[next_i])

		st.add_vertex(top[i])
		st.add_vertex(chamfer_top[i])
		st.add_vertex(chamfer_top[next_i])

		st.add_vertex(top[i])
		st.add_vertex(chamfer_top[next_i])
		st.add_vertex(top[next_i])

	var center_top := base_center + Vector3(0.0, height, 0.0)
	for i in range(sides):
		var next_i := (i + 1) % sides
		st.add_vertex(center_top)
		st.add_vertex(chamfer_top[i])
		st.add_vertex(chamfer_top[next_i])


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


func _is_weapon_or_hand(body: Node) -> bool:
	if body == null:
		return false
	if body == self or body == _static_body or body.get_parent() == self or body.owner == self:
		return true
	if body is BladeBody or body is HeldWeapon or body is XRController3D:
		return true
	if body.is_in_group("weapons") or body.is_in_group("player_weapons") or body.is_in_group("hands"):
		return true
	var p := body.get_parent()
	if p:
		if p is HeldWeapon or p is BladeBody or p is XRController3D:
			return true
		if p.is_in_group("weapons") or p.is_in_group("player_weapons") or p.is_in_group("hands"):
			return true
	return false


func _is_player_body(body: Node) -> bool:
	if body == null:
		return false
	if _is_weapon_or_hand(body):
		return false
	if body.is_in_group("player_body"):
		return true
	if body is XRPlayer or body is DesktopPlayer:
		return true
	if body is CollisionObject3D and ((body as CollisionObject3D).collision_layer & PLAYER_BODY_LAYER) != 0:
		return true
	return false


func _on_body_entered(body: Node3D) -> void:
	if not _is_player_body(body):
		return
	_tracked_bodies[body] = body.global_position


func _on_body_exited(body: Node3D) -> void:
	_tracked_bodies.erase(body)


func _physics_process(delta: float) -> void:
	var player_pos := _resolve_player_pos()

	if is_active:
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
	if prev_pos.distance_to(curr_pos) > 5.0:
		return false
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
	if body != null and not _is_player_body(body):
		return
	is_active = false
	_imbue_target(body)
	gate_crossed.emit(element, self)
	GameEvents.log_event("torii_gate_crossed", {"element": element, "position": global_position})


var target_element_system: ElementSystem = null

func _imbue_target(_body: Node) -> void:
	if target_element_system and is_instance_valid(target_element_system):
		target_element_system.imbue(element)
		return
	var run := _find_run_game()
	if run and run.element_system and is_instance_valid(run.element_system):
		run.element_system.imbue(element)
		return
	if get_tree():
		var es := get_tree().get_first_node_in_group("element_system") as ElementSystem
		if es and is_instance_valid(es):
			es.imbue(element)
			return
		var scene := get_tree().current_scene
		if scene:
			for child in scene.get_children():
				if child is ElementSystem:
					child.imbue(element)
					return
	push_warning("ToriiGate: No ElementSystem found to imbue element '%s'. Imbue skipped to prevent untimed element state." % element)


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
