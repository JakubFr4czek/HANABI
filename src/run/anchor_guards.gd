class_name AnchorGuards
extends Node
## Guards for the torii gates and hokora shrines (playtest note 5, backlog P5).
##
## Every gate and every shrine stands with 2–3 yōkai on a ring 6–12 m from it, off the
## footpath axis (no guard within 3 m of the path network), clear of trunks and rocks,
## preferably outside the player's view cone and never within 8 m of the player.
## The guards are ordinary WaveDirector yōkai: they fight, pay out kills and count toward
## the live cap (so the Quest yōkai budget holds). recall_stragglers leaves them at their
## post, and they are freed with their anchor when it streams away.
##
## A group is planned once, when the director runs and the anchor stands. A guard that
## dies is not replaced; a shrine that streams back in gets a new group.

const MIN_GUARDS := 2
const MAX_GUARDS := 3
const RING_MIN := 6.0
const RING_MAX := 12.0
## No guard stands within this distance of the footpath network.
const PATH_CLEARANCE := 3.0
## Keeps the guards of one anchor apart, so they do not stack into one body.
const GUARD_SEPARATION := 2.5
## A guard group never appears on top of the player (a shrine is built up to 34 m away).
const PLAYER_CLEARANCE := 8.0
const SPOT_ATTEMPTS := 40
const TICK := 0.25
const GUARD_SEED := 0x47554152  # "GUAR"

var wave_director: WaveDirector
var forest_world: ForestWorld
var torii_manager: ToriiManager
var hokora_manager: HokoraManager

## One record per anchor with a group: {anchor: Node3D, id: int, guards: Array[Yokai], spots: PackedVector3Array}.
var _posts: Array[Dictionary] = []
var _tick := TICK
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = GUARD_SEED


func setup(p_director: WaveDirector, p_forest: ForestWorld, p_torii: ToriiManager, p_hokora: HokoraManager) -> void:
	wave_director = p_director
	forest_world = p_forest
	torii_manager = p_torii
	hokora_manager = p_hokora


## One frame. [param player_pos] and [param view_forward] (horizontal, zero = none) keep new
## groups out of the player's view where the ring allows, so they do not pop in on screen.
func step(delta: float, player_pos: Vector3, view_forward: Vector3) -> void:
	if wave_director == null or not wave_director.active:
		return
	_tick += delta
	if _tick < TICK:
		return
	_tick = 0.0
	_prune()
	for anchor in _anchors():
		if _post_for(anchor).is_empty():
			_plan_group(anchor, player_pos, view_forward)


## The live guards of [param anchor] (a gate or a shrine).
func guards_of(anchor: Node3D) -> Array[Yokai]:
	var out: Array[Yokai] = []
	var post := _post_for(anchor)
	if post.is_empty():
		return out
	for g in post.guards:
		if is_instance_valid(g) and g.guard_post == post.id and not g.is_dead:
			out.append(g)
	return out


## The spots the guards of [param anchor] were placed on (world xz, y on the ground).
func spots_of(anchor: Node3D) -> PackedVector3Array:
	var post := _post_for(anchor)
	return post.spots if not post.is_empty() else PackedVector3Array()


## Up to [param count] guard spots on a ring round [param anchor], fewer when the ring has
## no room. Spots out of the player's view come first: an anchor straight ahead (about 30 m,
## a shrine) has its whole ring inside the view cone, and then the rest fill in from it.
## Spawns nothing, so the placement can be checked on its own.
func plan_spots(anchor: Vector3, count: int, player_pos: Vector3, view_forward: Vector3) -> PackedVector3Array:
	var spots := PackedVector3Array()
	if wave_director == null or forest_world == null:
		return spots
	spots = _fill_spots(spots, anchor, count, player_pos, view_forward, true)
	return _fill_spots(spots, anchor, count, player_pos, view_forward, false)


## Adds spots to [param spots] until [param count] are there (or the attempts run out) and
## returns them. [param out_of_view] applies the player's view cone as a rule.
func _fill_spots(spots: PackedVector3Array, anchor: Vector3, count: int, player_pos: Vector3, view_forward: Vector3, out_of_view: bool) -> PackedVector3Array:
	var cone_half := deg_to_rad(wave_director.get_profile().view_half_angle)
	var has_view := view_forward.length_squared() > 0.0001
	var yaw_view := atan2(view_forward.x, view_forward.z)
	var attempts := 0
	while spots.size() < count and attempts < SPOT_ATTEMPTS:
		attempts += 1
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(RING_MIN, RING_MAX)
		var x := anchor.x + sin(angle) * radius
		var z := anchor.z + cos(angle) * radius
		var from_player := Vector2(x - player_pos.x, z - player_pos.z)
		if from_player.length() < PLAYER_CLEARANCE:
			continue
		if out_of_view and has_view and absf(angle_difference(yaw_view, atan2(from_player.x, from_player.y))) < cone_half:
			continue
		if forest_world.paths != null and forest_world.paths.nearest_point(Vector2(x, z), PATH_CLEARANCE) != Vector2.INF:
			continue
		var pos := Vector3(x, _ground(x, z), z)
		if not wave_director.is_clear_of_world(pos):
			continue
		if _too_close(spots, pos):
			continue
		spots.append(pos)
	return spots


func _plan_group(anchor: Node3D, player_pos: Vector3, view_forward: Vector3) -> void:
	var id := anchor.get_instance_id()
	var count := _rng.randi_range(MIN_GUARDS, MAX_GUARDS)
	var spots := plan_spots(anchor.global_position, count, player_pos, view_forward)
	var profile := wave_director.get_profile()
	var guards: Array[Yokai] = []
	for pos in spots:
		var element := profile.roll_swarm_element(wave_director.run_seconds, _rng)
		guards.append(wave_director.spawn_enemy_at(pos, anchor.global_position, element, id))
	_posts.append({"anchor": anchor, "id": id, "guards": guards, "spots": spots})


## Drops the records of anchors that were freed or streamed away. Their guards still at the
## post go with them; a guard already dead is left to the director.
func _prune() -> void:
	var kept: Array[Dictionary] = []
	for post in _posts:
		if is_instance_valid(post.anchor):
			kept.append(post)
		else:
			_free_guards(post)
	_posts = kept


func _free_guards(post: Dictionary) -> void:
	for g in post.guards:
		if is_instance_valid(g) and g.guard_post == post.id and not g.is_dead:
			g.queue_free()


func _post_for(anchor: Node3D) -> Dictionary:
	var id := anchor.get_instance_id()
	for post in _posts:
		if post.id == id:
			return post
	return {}


func _anchors() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if torii_manager != null:
		for gate in torii_manager.get_active_gates():
			out.append(gate)
	if hokora_manager != null:
		for shrine in hokora_manager.alive_shrines():
			out.append(shrine)
	return out


func _too_close(spots: PackedVector3Array, pos: Vector3) -> bool:
	for s in spots:
		if Vector2(s.x - pos.x, s.z - pos.z).length() < GUARD_SEPARATION:
			return true
	return false


func _ground(x: float, z: float) -> float:
	return float(wave_director.ground_height.call(x, z)) if wave_director.ground_height.is_valid() else 0.0
