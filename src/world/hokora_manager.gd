class_name HokoraManager
extends Node3D
## Places hokora shrines in the endless forest (docs/ELEMENTS_PLAN.md, D1).
##
## The forest is cut into square slots of profile.shrine_slot_chunks chunks
## (WorldGenProfile, docs/WORLDGEN_TOOL.md). A slot holds at most one shrine
## (profile.shrine_slot_chance). Its
## candidate points come from a seed that depends only on the slot, so the same
## slot always proposes the same place in every run and the world stays fixed.
## The first candidate that passes the placement rules is cached for the run.
## Validation runs once, when the player first comes within spawn range (the
## chunks around the spot are loaded by then), so streaming never changes the
## answer.
##
## Shrines are built inside spawn range and freed past cull range. A used slot
## (its yellow Ofuda choice taken, D12) is remembered for the whole run: walking back
## never lights it again. Walking up to a shrine does nothing; a hand on the offering
## table does (see [method poll_touch]).

const SHRINE_SCENE := preload("res://scenes/world/hokora_shrine.tscn")
## Keep the footprint half a chunk away from the slot edge.
const SLOT_MARGIN := 14.0
## Alternates tried when the main pick is blocked. The forest is dense: torii use
## 24 angles × 8 distances, shrines get as many points per slot.
const MAX_ALTERNATES := 40
## Footprint radius that must stay free of trunks, boulders and lanterns (the
## plinth is ~0.75 m half-width; trunks add their own radius on top).
const CLEARANCE := 1.6
const TICK := 0.25
const WORLD_SEED := 0x484F4B4F  # "HOKO"
const OPENING_DISTANCE := ElementBalance.HOKORA_OPENING_DISTANCE

var forest_world: ForestWorld
## Edge of one slot, metres (profile.shrine_slot_chunks × chunk_size, set in setup).
var slot_size := 112.0
var follow: Node3D
var torii_manager: ToriiManager
var start_position := Vector3.ZERO
var start_forward := Vector3.FORWARD
## Set by RunGame: a touch opens a choice only while the run is PLAYING (not in the
## intro, not on the end screen). Shrines still glow and ring either way.
var accepting_offerings := true

var _candidates: Dictionary = {}  # Vector2i -> Vector3 (Vector3.INF = no shrine)
var _shrines: Dictionary = {}     # Vector2i -> HokoraShrine (built now)
var _used: Dictionary = {}        # Vector2i -> true (kept for the run)
var _tick := TICK
var _clearance_query: PhysicsShapeQueryParameters3D = null
var _clearance_shape: CylinderShape3D = null


func setup(p_forest: ForestWorld, p_follow: Node3D, p_torii: ToriiManager) -> void:
	forest_world = p_forest
	slot_size = p_forest.profile.shrine_slot_chunks * p_forest.profile.chunk_size
	follow = p_follow
	torii_manager = p_torii


## Run start: forgets every shrine and candidate, then proposes the opening shrine
## in front of the spawn (the forest chunks around the spawn must already exist).
func reset(p_start: Vector3, p_forward: Vector3) -> void:
	# Freed now: a queued shrine keeps its colliders in the physics space, and
	# the placement checks of the new run would see a shrine that is gone.
	for slot in _shrines.keys():
		var s := _shrines[slot] as HokoraShrine
		if is_instance_valid(s):
			var parent := s.get_parent()
			if parent != null:
				parent.remove_child(s)
			s.free()
	_shrines.clear()
	_used.clear()
	_candidates.clear()
	start_position = p_start
	var flat := Vector3(p_forward.x, 0.0, p_forward.z)
	start_forward = flat.normalized() if flat.length_squared() > 1e-4 else Vector3.FORWARD
	_tick = TICK
	_candidates[Vector2i.ZERO] = _opening_spot()


func shrine_at(slot: Vector2i) -> HokoraShrine:
	var s := _shrines.get(slot) as HokoraShrine
	return s if is_instance_valid(s) else null


func alive_shrines() -> Array[HokoraShrine]:
	var out: Array[HokoraShrine] = []
	for s in _shrines.values():
		if is_instance_valid(s):
			out.append(s as HokoraShrine)
	return out


func used_count() -> int:
	return _used.size()


## The shrine a hand in [param hands] touches this frame, or null. Only lit shrines
## are checked, nearest first, so a hand on one shrine never opens another.
func poll_touch(hands: Array[Vector3]) -> HokoraShrine:
	var p := _player_pos()
	var best: HokoraShrine = null
	var best_d := INF
	for s in _shrines.values():
		var shrine := s as HokoraShrine
		if not is_instance_valid(shrine) or not shrine.lit:
			continue
		var d := shrine.altar_position().distance_to(p)
		if d >= best_d:
			continue
		for hand in hands:
			if shrine.is_touched_by(hand, p):
				best = shrine
				best_d = d
				break
	return best


## The altar of the shrine nearest to the player, or Vector3.INF when none is lit
## within reach. Desktop uses it for the reach key (E), so a desktop player touches the
## same offering table a VR hand would.
func nearest_altar() -> Vector3:
	var p := _player_pos()
	var best := Vector3.INF
	for s in _shrines.values():
		var shrine := s as HokoraShrine
		if not is_instance_valid(shrine) or not shrine.lit:
			continue
		var altar := shrine.altar_position()
		if altar.distance_to(p) < best.distance_to(p):
			best = altar
	return best


## The choice of [param shrine] was taken: it goes dark and stays dark for the run.
func consume(shrine: HokoraShrine) -> void:
	_used[shrine.slot] = true
	shrine.consume()


func slot_of(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / slot_size), roundi(p.z / slot_size))


func _physics_process(delta: float) -> void:
	if forest_world == null or follow == null or not is_instance_valid(follow):
		return
	var p := _player_pos()
	for s in _shrines.values():
		var shrine := s as HokoraShrine
		if is_instance_valid(shrine):
			shrine.step(delta, p)
	_tick += delta
	if _tick >= TICK:
		_tick = 0.0
		_cull(p)
		_spawn_near(p)


func _spawn_near(p: Vector3) -> void:
	var center := slot_of(p)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var slot := center + Vector2i(dx, dz)
			if _shrines.has(slot):
				continue
			var spot := _spot_for(slot, p)
			if spot == Vector3.INF:
				continue
			if Vector2(spot.x - p.x, spot.z - p.z).length() <= ElementBalance.HOKORA_SPAWN_RADIUS:
				_spawn(slot, spot)


func _cull(p: Vector3) -> void:
	for slot in _shrines.keys():
		var s := _shrines[slot] as HokoraShrine
		if not is_instance_valid(s):
			_shrines.erase(slot)
			continue
		var d := Vector2(s.global_position.x - p.x, s.global_position.z - p.z).length()
		if d > ElementBalance.HOKORA_CULL_RADIUS:
			s.queue_free()
			_shrines.erase(slot)


## The validated spot of [param slot], or Vector3.INF when the slot has no shrine.
## An unvalidated slot is only checked once the player is within spawn range
## of its first candidate; until then nothing is cached.
func _spot_for(slot: Vector2i, p: Vector3) -> Vector3:
	if _candidates.has(slot):
		return _candidates[slot]
	var points := _candidate_points(slot)
	if points.is_empty():
		_candidates[slot] = Vector3.INF
		return Vector3.INF
	if Vector2(points[0].x - p.x, points[0].z - p.z).length() > ElementBalance.HOKORA_SPAWN_RADIUS:
		return Vector3.INF
	var chosen := Vector3.INF
	for point in points:
		if _is_valid_spot(point):
			chosen = point
			break
	_candidates[slot] = chosen
	return chosen


## Deterministic candidate points of a slot: first the main pick, then the
## alternates. Empty when the seed decides this slot gets no shrine.
func _candidate_points(slot: Vector2i) -> Array[Vector3]:
	var rng := _slot_rng(slot, 0)
	var out: Array[Vector3] = []
	if rng.randf() > forest_world.profile.shrine_slot_chance:
		return out
	var center := Vector2(slot.x, slot.y) * slot_size
	var half := slot_size * 0.5 - SLOT_MARGIN
	for i in 1 + MAX_ALTERNATES:
		var x := center.x + rng.randf_range(-half, half)
		var z := center.y + rng.randf_range(-half, half)
		out.append(Vector3(x, 0.0, z))
	return out


## The opening shrine: the first valid spot in a fan in front of the spawn
## (±90° in 7.5° steps, straight ahead first), at OPENING_DISTANCE and, if that
## ring is blocked, a little nearer or farther (all within spawn range).
func _opening_spot() -> Vector3:
	var order: Array[int] = [0]
	for k in range(1, 13):
		order.append(k)
		order.append(-k)
	for distance in [OPENING_DISTANCE, OPENING_DISTANCE - 2.0, OPENING_DISTANCE + 2.0, OPENING_DISTANCE - 4.0]:
		for k in order:
			var dir := start_forward.rotated(Vector3.UP, deg_to_rad(7.5 * float(k)))
			var spot: Vector3 = start_position + dir * float(distance)
			spot.y = 0.0
			if _is_valid_spot(spot):
				return spot
	return Vector3.INF


func _is_valid_spot(spot: Vector3) -> bool:
	if forest_world == null:
		return false
	if Vector2(spot.x - start_position.x, spot.z - start_position.z).length() < ElementBalance.HOKORA_MIN_START_DISTANCE:
		return false
	if torii_manager and torii_manager.is_near_gate(spot.x, spot.z, ElementBalance.HOKORA_TORII_CLEARANCE):
		return false
	if not forest_world.is_clear_of_props(spot.x, spot.z, CLEARANCE):
		return false
	# A plinth on a steep slope floats on one side: the height difference across
	# the footprint (2 m) must stay small.
	var gx := forest_world.height_at(spot.x + 1.0, spot.z) - forest_world.height_at(spot.x - 1.0, spot.z)
	var gz := forest_world.height_at(spot.x, spot.z + 1.0) - forest_world.height_at(spot.x, spot.z - 1.0)
	if Vector2(gx, gz).length() > 0.6:
		return false
	return not _overlaps_trunk(spot)


func _overlaps_trunk(spot: Vector3) -> bool:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return false
	if _clearance_query == null:
		_clearance_query = PhysicsShapeQueryParameters3D.new()
		_clearance_shape = CylinderShape3D.new()
		_clearance_shape.radius = CLEARANCE
		_clearance_shape.height = 4.0
		_clearance_query.shape = _clearance_shape
		_clearance_query.collision_mask = ForestWorld.TRUNK_LAYER
	var h := forest_world.height_at(spot.x, spot.z)
	_clearance_query.transform = Transform3D(Basis(), Vector3(spot.x, h + 2.0, spot.z))
	return not space.intersect_shape(_clearance_query, 1).is_empty()


func _spawn(slot: Vector2i, spot: Vector3) -> void:
	var shrine := SHRINE_SCENE.instantiate() as HokoraShrine
	shrine.name = "Hokora_%d_%d" % [slot.x, slot.y]
	shrine.slot = slot
	add_child(shrine)
	shrine.position = Vector3(spot.x, forest_world.height_at(spot.x, spot.z), spot.z)
	shrine.rotation.y = _slot_rng(slot, 1).randf() * TAU
	forest_world.connect_shrine(shrine)
	shrine.set_lit(not _used.has(slot))
	_shrines[slot] = shrine


func _slot_rng(slot: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (WORLD_SEED ^ (slot.x * 73856093) ^ (slot.y * 19349663) ^ (salt * 83492791)) & 0x7FFFFFFF
	return rng


func _player_pos() -> Vector3:
	if follow.has_method("feet_position"):
		return follow.call("feet_position")
	return follow.global_position
