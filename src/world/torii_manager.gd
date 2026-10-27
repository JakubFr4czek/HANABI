class_name ToriiManager
extends Node3D
## Manages elemental Torii gates streaming in the endless forest (docs/ELEMENTS_PLAN.md).
## Guarantees gate spacing within 18–32 m of the player, collision clearance (3.2 m),
## 4-item shuffle bag rotation, and integration with chunk streaming.

signal gate_spawned(gate: ToriiGate)

const TORII_GATE_SCENE := preload("res://scenes/world/torii_gate.tscn")
const MIN_SPAWN_DIST: float = 18.0
const MAX_SPAWN_DIST: float = 32.0
const IDEAL_SPAWN_DIST: float = 24.0
const MIN_GATE_SEPARATION: float = 22.0
const CLEARANCE_RADIUS: float = 3.2
const SHRINE_CLEARING_RADIUS: float = 8.5
const COMBAT_SPAWN_SEPARATION: float = 14.0
const CULL_DISTANCE: float = 75.0

var forest_world: ForestWorld
var follow: Node3D
var run_game: RunGame

var active_gates: Array[ToriiGate] = []
var _shuffle_bag: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _spawn_check_timer: float = 0.0


func _ready() -> void:
	add_to_group("torii_managers")
	_rng.seed = 0x544F524949  # "TORII"


func setup(p_forest: ForestWorld, p_follow: Node3D, p_run: RunGame = null) -> void:
	forest_world = p_forest
	follow = p_follow
	run_game = p_run
	reset()
	_ensure_gates_ahead()


func reset() -> void:
	for gate in active_gates:
		if is_instance_valid(gate):
			gate.queue_free()
	active_gates.clear()
	_shuffle_bag.clear()
	_refill_shuffle_bag()
	_ensure_gates_ahead()


func _refill_shuffle_bag() -> void:
	_shuffle_bag = [Elements.SAKURA, Elements.STORM, Elements.INK, Elements.SHADOW]
	# Deterministic shuffle using our RNG
	for i in range(_shuffle_bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _shuffle_bag[i]
		_shuffle_bag[i] = _shuffle_bag[j]
		_shuffle_bag[j] = tmp


func next_element() -> String:
	if _shuffle_bag.is_empty():
		_refill_shuffle_bag()
	return _shuffle_bag.pop_front()


func is_near_gate(wx: float, wz: float, clearance: float = CLEARANCE_RADIUS) -> bool:
	for gate in active_gates:
		if is_instance_valid(gate):
			if Vector2(gate.global_position.x - wx, gate.global_position.z - wz).length() < clearance:
				return true
	return false


func get_active_gates() -> Array[ToriiGate]:
	var result: Array[ToriiGate] = []
	for g in active_gates:
		if is_instance_valid(g):
			result.append(g)
	return result


func nearest_gate(from_pos: Vector3) -> ToriiGate:
	var best: ToriiGate = null
	var min_d := INF
	for g in active_gates:
		if is_instance_valid(g):
			var d := g.global_position.distance_to(from_pos)
			if d < min_d:
				min_d = d
				best = g
	return best


func _physics_process(delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		return

	_spawn_check_timer += delta
	if _spawn_check_timer >= 0.5:
		_spawn_check_timer = 0.0
		_cull_distant_gates()
		_ensure_gates_ahead()


func _cull_distant_gates() -> void:
	var p_pos := _player_pos()
	if p_pos == Vector3.INF:
		return
	var kept: Array[ToriiGate] = []
	for g in active_gates:
		if is_instance_valid(g):
			if g.global_position.distance_to(p_pos) > CULL_DISTANCE:
				g.queue_free()
			else:
				kept.append(g)
	active_gates = kept


func _ensure_gates_ahead() -> void:
	var p_pos := _player_pos()
	if p_pos == Vector3.INF:
		return

	# Count active gates in the [MIN_SPAWN_DIST, MAX_SPAWN_DIST] range ahead
	var in_range_count := 0
	for g in active_gates:
		if is_instance_valid(g) and g.is_active:
			var d := g.global_position.distance_to(p_pos)
			if d >= MIN_SPAWN_DIST and d <= MAX_SPAWN_DIST:
				in_range_count += 1

	while in_range_count < 2 and active_gates.size() < 8:
		var spawned := _attempt_spawn_gate_in_range(p_pos)
		if spawned == null:
			break
		in_range_count += 1


func _attempt_spawn_gate_in_range(p_pos: Vector3) -> ToriiGate:
	var fwd := _player_forward()
	var base_angle := atan2(fwd.x, fwd.z)

	# Sweep 24 angles around player facing direction and multiple distances in [18.5, 31.5]
	var angle_count := 24
	var distances: Array[float] = [22.0, 24.0, 20.0, 26.0, 18.5, 28.0, 30.0, 31.5]

	for dist in distances:
		for i in angle_count:
			var sign_mult := 1.0 if (i % 2 == 0) else -1.0
			var off := (float(i) / float(angle_count)) * PI * sign_mult
			var ang := base_angle + off
			var cand_x := p_pos.x + sin(ang) * dist
			var cand_z := p_pos.z + cos(ang) * dist

			if _is_valid_location(cand_x, cand_z, p_pos):
				return spawn_gate_at(cand_x, cand_z)
	return null


func _is_valid_location(wx: float, wz: float, p_pos: Vector3) -> bool:
	if Vector2(wx, wz).length() < SHRINE_CLEARING_RADIUS:
		return false
	for g in active_gates:
		if is_instance_valid(g) and g.is_active:
			if Vector2(g.global_position.x - wx, g.global_position.z - wz).length() < MIN_GATE_SEPARATION:
				return false
	var d_player := Vector2(p_pos.x - wx, p_pos.z - wz).length()
	if d_player < MIN_SPAWN_DIST or d_player > MAX_SPAWN_DIST:
		return false
	if forest_world:
		if not forest_world.is_clear_of_props(wx, wz, CLEARANCE_RADIUS):
			return false
		var space := get_world_3d().direct_space_state if get_world_3d() else null
		if space:
			var query := PhysicsShapeQueryParameters3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = CLEARANCE_RADIUS
			cyl.height = 4.0
			query.shape = cyl
			var hy := forest_world.height_at(wx, wz)
			query.transform = Transform3D(Basis(), Vector3(wx, hy + 2.0, wz))
			query.collision_mask = ForestWorld.TRUNK_LAYER
			var hits := space.intersect_shape(query, 1)
			if not hits.is_empty():
				return false
	return true


func spawn_gate_at(wx: float, wz: float, elem: String = "") -> ToriiGate:
	var chosen_elem := elem if not elem.is_empty() else next_element()
	var hy := forest_world.height_at(wx, wz) if forest_world else 0.0

	# Align gate perpendicular to slope gradient
	var yaw := 0.0
	if forest_world:
		var gx := forest_world.height_at(wx + 1.0, wz) - forest_world.height_at(wx - 1.0, wz)
		var gz := forest_world.height_at(wx, wz + 1.0) - forest_world.height_at(wx, wz - 1.0)
		var grad := Vector2(gx, gz)
		if grad.length() > 0.04:
			# Perpendicular to slope
			yaw = atan2(-gz, gx)
		else:
			# Face roughly toward center or player
			var p_pos := _player_pos()
			if p_pos != Vector3.INF:
				yaw = atan2(p_pos.x - wx, p_pos.z - wz)

	if forest_world and forest_world.has_method("suppress_props_near"):
		forest_world.suppress_props_near(wx, wz, CLEARANCE_RADIUS + 0.3)
	var gate: ToriiGate = TORII_GATE_SCENE.instantiate() as ToriiGate
	gate.element = chosen_elem
	gate.position = Vector3(wx, hy, wz)
	gate.rotation = Vector3(0.0, yaw, 0.0)
	gate.run_game = run_game
	if follow:
		gate.set_player_reference(follow)

	add_child(gate)
	active_gates.append(gate)
	gate_spawned.emit(gate)
	return gate


func _player_pos() -> Vector3:
	if follow and is_instance_valid(follow):
		if follow.has_method("feet_position"):
			return follow.call("feet_position")
		return follow.global_position
	return Vector3.INF


func _player_forward() -> Vector3:
	if follow and is_instance_valid(follow):
		var f := -follow.global_transform.basis.z
		f.y = 0.0
		if f.length_squared() > 0.01:
			return f.normalized()
	return Vector3.FORWARD
