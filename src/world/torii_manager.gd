class_name ToriiManager
extends Node3D
## Manages elemental Torii gates streaming in the endless forest (docs/ELEMENTS_PLAN.md).
## Guarantees gate spacing within 18–32 m of the player, 40 m between active gates,
## collision clearance (3.2 m), gates beside a footpath running along it (never across),
## 4-item shuffle bag rotation, and integration with chunk streaming.

signal gate_spawned(gate: ToriiGate)

const TORII_GATE_SCENE := preload("res://scenes/world/torii_gate.tscn")
const MIN_SPAWN_DIST: float = 18.0
const MAX_SPAWN_DIST: float = 32.0
const IDEAL_SPAWN_DIST: float = 24.0
## Minimum distance between active gates, so gates never bunch up in the walk.
const MIN_GATE_SEPARATION: float = 40.0
## A gate centre this close to a footpath axis takes the path's direction.
const PATH_ALIGN_RADIUS: float = 3.5
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
var _clearance_query: PhysicsShapeQueryParameters3D = null
var _clearance_cyl: CylinderShape3D = null
## Pose override while placing gates for a reset (see ensure_gates_ahead).
var _pose_at := Vector3.INF
var _pose_facing := Vector3.ZERO


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
	clear_gates()
	_shuffle_bag.clear()
	_refill_shuffle_bag()
	_ensure_gates_ahead()


## Removes every gate now (not at the end of the frame): a queued gate keeps its
## colliders in the physics space, and the next placement would see them.
func clear_gates() -> void:
	for gate in active_gates:
		if is_instance_valid(gate):
			var parent := gate.get_parent()
			if parent != null:
				parent.remove_child(gate)
			gate.free()
	active_gates.clear()


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


## A spent gate may come back in place (45 m rule) only when no other active gate
## stands within MIN_GATE_SEPARATION of it; otherwise it stays spent.
func can_reactivate(gate: ToriiGate) -> bool:
	for g in active_gates:
		if g != gate and is_instance_valid(g) and g.is_active:
			if g.global_position.distance_to(gate.global_position) < MIN_GATE_SEPARATION:
				return false
	return true


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


## Places gates ahead of the player up to the target count (run start and reset).
## [param at] and [param facing] stand in for the player's pose when the player is
## not yet on the spawn (a reset happens before the player is placed).
func ensure_gates_ahead(at: Vector3 = Vector3.INF, facing: Vector3 = Vector3.ZERO) -> void:
	_pose_at = at
	_pose_facing = facing
	_ensure_gates_ahead()
	_pose_at = Vector3.INF
	_pose_facing = Vector3.ZERO


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
	var spot := find_gate_spot(p_pos)
	if spot == Vector2.INF:
		return null
	return spawn_gate_at(spot.x, spot.y)


## The first valid place for a gate around the player, or Vector2.INF. Only
## searches: it spawns nothing, so it can be timed on its own.
func find_gate_spot(p_pos: Vector3) -> Vector2:
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
				return Vector2(cand_x, cand_z)
	return Vector2.INF


func _is_valid_location(wx: float, wz: float, p_pos: Vector3) -> bool:
	if wx * wx + wz * wz < SHRINE_CLEARING_RADIUS * SHRINE_CLEARING_RADIUS:
		return false
	var min_sep_sq := MIN_GATE_SEPARATION * MIN_GATE_SEPARATION
	for g in active_gates:
		if is_instance_valid(g) and g.is_active:
			var dx := g.global_position.x - wx
			var dz := g.global_position.z - wz
			if dx * dx + dz * dz < min_sep_sq:
				return false
	var dx_p := p_pos.x - wx
	var dz_p := p_pos.z - wz
	var d_player_sq := dx_p * dx_p + dz_p * dz_p
	if d_player_sq < MIN_SPAWN_DIST * MIN_SPAWN_DIST or d_player_sq > MAX_SPAWN_DIST * MAX_SPAWN_DIST:
		return false
	if forest_world:
		if not forest_world.is_clear_of_props(wx, wz, CLEARANCE_RADIUS):
			return false
		var space := get_world_3d().direct_space_state if get_world_3d() else null
		if space:
			if _clearance_query == null:
				_clearance_query = PhysicsShapeQueryParameters3D.new()
				_clearance_cyl = CylinderShape3D.new()
				_clearance_cyl.radius = CLEARANCE_RADIUS
				_clearance_cyl.height = 4.0
				_clearance_query.shape = _clearance_cyl
				_clearance_query.collision_mask = ForestWorld.TRUNK_LAYER
			var hy := forest_world.height_at(wx, wz)
			_clearance_query.transform = Transform3D(Basis(), Vector3(wx, hy + 2.0, wz))
			var hits := space.intersect_shape(_clearance_query, 1)
			if not hits.is_empty():
				return false
	return true


func spawn_gate_at(wx: float, wz: float, elem: String = "") -> ToriiGate:
	var chosen_elem := elem if not elem.is_empty() else next_element()
	var hy := forest_world.height_at(wx, wz) if forest_world else 0.0

	# Beside a footpath the gate runs along it; elsewhere it is perpendicular to the
	# slope, or faces the player.
	var yaw := _path_yaw(wx, wz)
	if is_nan(yaw):
		yaw = 0.0
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


## Yaw that runs the gate's passage (local Z) along the nearest footpath within
## PATH_ALIGN_RADIUS, or NAN when no path is that close. The posts (local X) then
## cross the path outside its strip, so a walker passes through the middle.
func _path_yaw(wx: float, wz: float) -> float:
	if forest_world == null or forest_world.paths == null:
		return NAN
	var p := Vector2(wx, wz)
	var reach := Vector2(PATH_ALIGN_RADIUS, PATH_ALIGN_RADIUS)
	var segments := forest_world.paths.segments_in_rect(Rect2(p - reach, reach * 2.0))
	var best := INF
	var tangent := Vector2.ZERO
	for k in range(0, segments.size() - 1, 2):
		var a := segments[k]
		var b := segments[k + 1]
		if (b - a).length_squared() < 1e-9:
			continue
		var d := ForestPaths.segment_distance(p, a, b)
		if d < best:
			best = d
			tangent = (b - a).normalized()
	if best > PATH_ALIGN_RADIUS:
		return NAN
	# The passage direction is (sin yaw, cos yaw), the convention of the player-facing branch.
	return atan2(tangent.x, tangent.y)


func _player_pos() -> Vector3:
	if _pose_at != Vector3.INF:
		return _pose_at
	if follow and is_instance_valid(follow):
		if follow.has_method("feet_position"):
			return follow.call("feet_position")
		return follow.global_position
	return Vector3.INF


func _player_forward() -> Vector3:
	if _pose_facing != Vector3.ZERO:
		return _pose_facing
	if follow and is_instance_valid(follow):
		var f := -follow.global_transform.basis.z
		f.y = 0.0
		if f.length_squared() > 0.01:
			return f.normalized()
	return Vector3.FORWARD
