class_name SoulVesselManager
extends Node3D
## F7: the goal of a run. The souls of the villagers are sealed in COUNT soul vessels
## (SoulVessel) scattered through the forest. Releasing all of them saves the village
## and ends the run (RunGame). See docs/f7/README.md.
##
## Placement is planned once per run, from the world seed and the footpath network alone
## (ForestPaths is analytic, it does not need loaded chunks), so a seed always gives the
## same COUNT spots: each beside a footpath sample (PATH_OFFSET_MIN..MAX m off the axis,
## within PATH_REACH of the network), RING_MIN..RING_MAX m from the spawn and at least
## MIN_SPACING m from every other vessel and clear of torii gates. A vessel node is built
## only inside SPAWN_RADIUS and freed past CULL_RADIUS; a released one stays released.

signal soul_released(index: int, released: int, total: int)

const COUNT := 5
const RING_MIN := 50.0
const RING_MAX := 150.0
const MIN_SPACING := 45.0
const PATH_OFFSET_MIN := 1.4
const PATH_OFFSET_MAX := 2.6
const PATH_REACH := 8.0
const SPAWN_RADIUS := 60.0
const CULL_RADIUS := 75.0
## Player within this many metres (flat) of a vessel: A/X (E on desktop) releases it.
const REACH_RADIUS := 2.4
const MAX_TRIES := 400
const SEED_SALT := 0x534F554C  # "SOUL"

var forest_world: ForestWorld
var torii_manager: ToriiManager
var follow: Node3D
## What the sign prints before "RELEASE IT" (RunGame sets it from the rig).
var key_text := "A / X"
var spots: Array[Vector3] = []
var _released: Dictionary = {}  # index -> true
var _nodes: Dictionary = {}     # index -> SoulVessel


func setup(p_forest: ForestWorld, p_follow: Node3D, p_torii: ToriiManager) -> void:
	forest_world = p_forest
	follow = p_follow
	torii_manager = p_torii


## Run start: frees every vessel and plans the COUNT spots for this seed again.
func reset(start: Vector3) -> void:
	for n in _nodes.values():
		if is_instance_valid(n):
			(n as Node).queue_free()
	_nodes.clear()
	_released.clear()
	spots = plan_spots(start)


func released_count() -> int:
	return _released.size()


func total() -> int:
	return spots.size()


func is_released(i: int) -> bool:
	return _released.has(i)


func vessel(i: int) -> SoulVessel:
	var v := _nodes.get(i) as SoulVessel
	return v if is_instance_valid(v) else null


## The COUNT vessel spots (y = ground) for this world seed around [param start].
func plan_spots(start: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if forest_world == null or forest_world.paths == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = (forest_world.profile.world_seed ^ SEED_SALT) & 0x7FFFFFFF
	var origin := Vector2(start.x, start.z)
	var base := rng.randf() * TAU
	for attempt in MAX_TRIES:
		if out.size() >= COUNT:
			break
		# Spread round the spawn: each pick aims at the next sector first.
		var ang := base + TAU * float(out.size()) / float(COUNT) + rng.randf_range(-0.55, 0.55)
		var dist := rng.randf_range(RING_MIN + 6.0, RING_MAX - 6.0)
		var target := origin + Vector2(cos(ang), sin(ang)) * dist
		var samples := forest_world.paths.samples_in_rect(Rect2(target - Vector2(20, 20), Vector2(40, 40)), 2.0)
		if samples.is_empty():
			continue
		var s: Vector4 = samples[rng.randi_range(0, samples.size() - 1)]
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var off := rng.randf_range(PATH_OFFSET_MIN, PATH_OFFSET_MAX)
		var at := Vector2(s.x, s.y) + Vector2(-s.w, s.z) * side * off
		if not _is_valid(at, origin, out):
			continue
		out.append(Vector3(at.x, forest_world.height_at(at.x, at.y), at.y))
	return out


func _is_valid(at: Vector2, origin: Vector2, taken: Array[Vector3]) -> bool:
	var d := at.distance_to(origin)
	if d < RING_MIN or d > RING_MAX:
		return false
	for o in taken:
		if at.distance_to(Vector2(o.x, o.z)) < MIN_SPACING:
			return false
	if forest_world.paths.nearest_point(at, PATH_REACH) == Vector2.INF:
		return false
	if torii_manager and torii_manager.is_near_gate(at.x, at.y, 4.0):
		return false
	return true


## The unreleased vessel within REACH_RADIUS of the player, or -1.
func vessel_in_reach() -> int:
	if follow == null or not is_instance_valid(follow):
		return -1
	var p := _player_pos()
	var best := -1
	var best_d := REACH_RADIUS
	for i in spots.size():
		if _released.has(i):
			continue
		var d := Vector2(spots[i].x - p.x, spots[i].z - p.z).length()
		if d <= best_d:
			best_d = d
			best = i
	return best


## A/X or E: releases the vessel in reach. Returns true when a soul was released.
func try_release() -> bool:
	var i := vessel_in_reach()
	if i < 0:
		return false
	return release(i)


## Releases vessel [param i] once (the counter goes up exactly once).
func release(i: int) -> bool:
	if i < 0 or i >= spots.size() or _released.has(i):
		return false
	_released[i] = true
	var v := vessel(i)
	if v:
		v.release()
	GameEvents.log_event("soul_released", {"index": i, "released": _released.size(), "total": spots.size()})
	soul_released.emit(i, _released.size(), spots.size())
	return true


func _physics_process(delta: float) -> void:
	if forest_world == null or follow == null or not is_instance_valid(follow):
		return
	var p := _player_pos()
	var near := vessel_in_reach()
	for i in spots.size():
		var d := Vector2(spots[i].x - p.x, spots[i].z - p.z).length()
		var v := vessel(i)
		if v == null and d <= SPAWN_RADIUS and not _released.has(i):
			v = _spawn(i)
		elif v != null and d > CULL_RADIUS and v._release_t < 0.0:
			v.queue_free()
			_nodes.erase(i)
			continue
		if v:
			v.step(delta, p, i == near, key_text)


func _spawn(i: int) -> SoulVessel:
	var v := SoulVessel.new()
	v.name = "SoulVessel_%d" % i
	v.index = i
	add_child(v)
	var at := spots[i]
	v.global_position = Vector3(at.x, forest_world.height_at(at.x, at.z), at.z)
	# Face the footpath, so the statuette greets whoever walks by.
	var path := forest_world.paths.nearest_point(Vector2(at.x, at.z), PATH_REACH)
	if path != Vector2.INF and path.distance_to(Vector2(at.x, at.z)) > 0.1:
		v.rotation.y = atan2(path.x - at.x, path.y - at.z)
	_nodes[i] = v
	return v


func _player_pos() -> Vector3:
	if follow.has_method("feet_position"):
		return follow.call("feet_position")
	return follow.global_position
