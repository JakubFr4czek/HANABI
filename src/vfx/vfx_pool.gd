extends Node
## Prewarmed pools for run-time VFX and soul orbs (NIGHT_PLAN §8). Avoids
## allocating nodes/meshes/materials during combat waves on Quest.

const SPARK_PREWARM := 28
const RING_PREWARM := 18
const SOUL_PREWARM := 56
const MAX_SPARK := 36
const MAX_RING := 24
const MAX_SOUL := 72

var _spark_free: Array[SparkBurst] = []
var _sparks_allocated := 0
var _rings_allocated := 0
var _souls_allocated := 0
var _ring_free: Array[CPUParticles3D] = []
var _soul_free: Array[SoulOrb] = []

var _spark_mesh: QuadMesh
var _spark_mat: StandardMaterial3D
var _ring_mesh: QuadMesh
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_shared_spark_assets()
	_build_shared_ring_assets()
	_prewarm_sparks(SPARK_PREWARM)
	_prewarm_rings(RING_PREWARM)
	_prewarm_souls(SOUL_PREWARM)


func pool_stats() -> Dictionary:
	return {
		"spark_free": _spark_free.size(),
		"ring_free": _ring_free.size(),
		"soul_free": _soul_free.size(),
		"sparks_allocated": _sparks_allocated,
		"rings_allocated": _rings_allocated,
		"souls_allocated": _souls_allocated,
	}


func ensure_run_budget(extra_souls: int = 32) -> void:
	var want_souls := mini(SOUL_PREWARM + extra_souls, MAX_SOUL)
	while _soul_free.size() < want_souls and _souls_allocated < MAX_SOUL:
		_soul_free.append(_make_soul_orb())
	while _spark_free.size() < SPARK_PREWARM and _sparks_allocated < MAX_SPARK:
		_spark_free.append(_make_spark())
	while _ring_free.size() < RING_PREWARM and _rings_allocated < MAX_RING:
		_ring_free.append(_make_ring())


func acquire_soul_orb(parent: Node):
	var orb: SoulOrb
	if _soul_free.is_empty():
		if _souls_allocated >= MAX_SOUL:
			return null
		orb = _make_soul_orb()
	else:
		orb = _soul_free.pop_back()
	if orb.get_parent():
		orb.get_parent().remove_child(orb)
	parent.add_child(orb)
	orb.activate_from_pool()
	return orb


func release_soul_orb(orb: SoulOrb) -> void:
	if orb == null or not is_instance_valid(orb):
		return
	orb.deactivate_for_pool()
	if orb.get_parent():
		orb.get_parent().remove_child(orb)
	add_child(orb)
	_soul_free.append(orb)


func spawn_spark(parent: Node, at: Vector3, normal: Vector3, color: Color, amount_: int = 24, speed: float = 3.0) -> void:
	var s: SparkBurst
	if _spark_free.is_empty():
		if _sparks_allocated >= MAX_SPARK:
			return
		s = _make_spark()
	else:
		s = _spark_free.pop_back()
	if s.get_parent():
		s.get_parent().remove_child(s)
	parent.add_child(s)
	s.fire_from_pool(at, normal, color, amount_, speed)
	get_tree().create_timer(s.lifetime + 0.08).timeout.connect(func() -> void:
		_return_spark(s), CONNECT_ONE_SHOT)


func spawn_element_ring(parent: Node, at: Vector3, col: Color, scale: float) -> void:
	var p: CPUParticles3D
	if _ring_free.is_empty():
		if _rings_allocated >= MAX_RING:
			return
		p = _make_ring()
	else:
		p = _ring_free.pop_back()
	if p.get_parent():
		p.get_parent().remove_child(p)
	parent.add_child(p)
	p.amount = mini(ElementFirework.MAX_PARTICLES, int(22 * scale))
	p.initial_velocity_min = 1.6 * scale
	p.initial_velocity_max = 3.1 * scale
	(_ring_mat as StandardMaterial3D).albedo_color = col * 0.75
	p.global_position = at
	p.restart()
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.08).timeout.connect(func() -> void:
		_return_ring(p), CONNECT_ONE_SHOT)


func _return_spark(s: SparkBurst) -> void:
	if not is_instance_valid(s):
		return
	if _spark_free.has(s):
		return
	s.emitting = false
	if s.get_parent():
		s.get_parent().remove_child(s)
	add_child(s)
	_spark_free.append(s)


func _return_ring(p: CPUParticles3D) -> void:
	if not is_instance_valid(p):
		return
	if _ring_free.has(p):
		return
	p.emitting = false
	if p.get_parent():
		p.get_parent().remove_child(p)
	add_child(p)
	_ring_free.append(p)


func _prewarm_sparks(n: int) -> void:
	for _i in n:
		_spark_free.append(_make_spark())


func _prewarm_rings(n: int) -> void:
	for _i in n:
		_ring_free.append(_make_ring())


func _prewarm_souls(n: int) -> void:
	for _i in n:
		_soul_free.append(_make_soul_orb())


func _make_soul_orb() -> SoulOrb:
	_souls_allocated += 1
	var orb := SoulOrb.new()
	orb.name = "SoulOrbPooled"
	add_child(orb)
	orb.deactivate_for_pool()
	return orb


func _make_spark() -> SparkBurst:
	_sparks_allocated += 1
	var s := SparkBurst.new()
	s.name = "SparkBurstPooled"
	add_child(s)
	s.setup_pooled(_spark_mesh, _spark_mat)
	if not s.finished.is_connected(_on_spark_finished):
		s.finished.connect(_on_spark_finished.bind(s))
	return s


func _on_spark_finished(s: SparkBurst) -> void:
	_return_spark(s)


func _make_ring() -> CPUParticles3D:
	_rings_allocated += 1
	var p := CPUParticles3D.new()
	p.name = "ElementRingPooled"
	p.one_shot = true
	p.explosiveness = 0.92
	p.lifetime = 0.42
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -2.5, 0)
	p.mesh = _ring_mesh
	p.material_override = _ring_mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	add_child(p)
	if not p.finished.is_connected(_on_ring_finished):
		p.finished.connect(_on_ring_finished.bind(p))
	return p


func _on_ring_finished(p: CPUParticles3D) -> void:
	_return_ring(p)


func _build_shared_spark_assets() -> void:
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.005, 0.045)
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spark_mat.albedo_texture = SparkBurst.shared_streak_texture()
	_spark_mat.vertex_color_use_as_albedo = true


func _build_shared_ring_assets() -> void:
	_ring_mesh = QuadMesh.new()
	_ring_mesh.size = Vector2(0.006, 0.038)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.vertex_color_use_as_albedo = true
