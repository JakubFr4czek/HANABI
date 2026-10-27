extends Node
## Long soak of a real run: waves spawn, an auto-swordsman cuts whatever comes
## close, and every physics tick each enemy body is checked for tearing (a
## part far off its rest distance to the pelvis) and for parts flung away.
## Prints every incident with the enemy's state. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/diag/diag_ragdoll_soak.tscn -- --desktop [--seconds 120]

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEAR_LIMIT := 0.6

var _incidents := 0
var _gap_incidents := 0
var _worst := {}  # instance id -> worst tear reported this life


func _ready() -> void:
	var seconds := 100.0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--seconds")
	if i >= 0 and i + 1 < args.size():
		seconds = float(args[i + 1])
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	for k in 12:
		await get_tree().physics_frame
	var player := run.player as DesktopPlayer
	var health := player.health
	var swing_cd := 0.0
	var swings := 0
	var flip := false
	var frames := int(seconds * 90.0)
	var max_alive := 0
	var deaths := [0]
	run.wave_director.enemy_died.connect(func(_e, _h): deaths[0] += 1)
	var hits: Array = []
	GameEvents.hit_landed.connect(func(h): hits.append(h))
	var severed := {}
	GameEvents.event_logged.connect(func(e): if e.get("type", "") == "enemy_dismembered": severed[e.part] = int(severed.get(e.part, 0)) + 1)
	for f in frames:
		await get_tree().physics_frame
		health.heal_full()
		if run.state == RunGame.RunState.LEVEL_UP and not run.active_ofuda.is_empty():
			run.slice_ofuda_choice(randi() % run.active_ofuda.size())
		swing_cd -= 1.0 / 90.0
		var nearest: ActiveRagdoll = null
		var best := 2.4
		for e in get_tree().get_nodes_in_group("enemies"):
			var r := e as ActiveRagdoll
			if r == null or not r.is_inside_tree() or r.parts.is_empty():
				continue
			if r.get("is_dead"):
				continue
			var d := Vector2(r.root_part().global_position.x - player.global_position.x, r.root_part().global_position.z - player.global_position.z).length()
			if d < best:
				best = d
				nearest = r
		if nearest and swing_cd <= 0.0:
			var to := nearest.root_part().global_position - player.global_position
			player.rotation.y = atan2(-to.x, -to.z)
			player.swing_duration = 0.13
			player.swing(DesktopPlayer.SLASH_HORIZONTAL if flip else DesktopPlayer.SLASH_OVERHEAD)
			flip = not flip
			swings += 1
			swing_cd = 0.45
		var alive := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			var r := e as ActiveRagdoll
			if r == null or not r.is_inside_tree() or r.parts.is_empty() or not r.visible:
				continue
			alive += 1
			_inspect(r, f / 90.0, player.global_position)
		max_alive = maxi(max_alive, alive)
	if args.has("--hit-stats"):
		var rows := hits.filter(func(h): return h.get("strike", "") == "edge")
		for key in ["speed", "power", "impulse", "base_damage"]:
			var v: Array = rows.map(func(h): return float(h.get(key, 0.0)))
			v.sort()
			if not v.is_empty():
				print("  %s: p25 %.2f  p50 %.2f  p75 %.2f  p90 %.2f  max %.2f" % [key, v[v.size() / 4], v[v.size() / 2], v[v.size() * 3 / 4], v[v.size() * 9 / 10], v[-1]])
		var kinds := {}
		for h in hits:
			kinds[h.get("strike", "?")] = int(kinds.get(h.get("strike", "?"), 0)) + 1
		print("  strikes: %s, edge hits %d" % [kinds, rows.size()])
	print("SOAK %.0f s: %d swings, %d kills, max %d bodies, %d incidents, %d joint-gap ticks, severed %s" % [seconds, swings, deaths[0], max_alive, _incidents, _gap_incidents, severed])
	get_tree().quit(1 if _incidents > 0 else 0)


func _inspect(r: ActiveRagdoll, t: float, player_pos: Vector3) -> void:
	var pelvis := r.root_part()
	var rest_root: Transform3D = r._rest[pelvis.name]
	var worst := 0.0
	var worst_part := ""
	for part_name in r.parts:
		if r is Yokai and (r as Yokai).is_severed(part_name):
			continue
		var part := r.parts[part_name] as RagdollPart
		var rest_d := ((r._rest[part_name] as Transform3D).origin - rest_root.origin).length()
		var tear := absf(part.global_position.distance_to(pelvis.global_position) - rest_d)
		if tear > worst:
			worst = tear
			worst_part = part_name
	# The real detachment measure: how far apart each joint's two halves are
	# (the anchor carried by the parent vs by the child). A raised arm moves
	# far from the pelvis legitimately; a torn joint opens a gap.
	var gap := 0.0
	var gap_part := ""
	for part_name in r.parts:
		var def: Dictionary = r._defs.get(part_name, {})
		if not def.has("parent") or not def.has("joint"):
			continue
		if r is Yokai and (r as Yokai).is_severed(part_name):
			continue
		var parent := r.parts.get(String(def.parent)) as RagdollPart
		var child := r.parts[part_name] as RagdollPart
		var j: Vector3 = def.joint
		var a := parent.global_transform * ((r._rest[parent.name] as Transform3D).affine_inverse() * j)
		var b := child.global_transform * ((r._rest[part_name] as Transform3D).affine_inverse() * j)
		if a.distance_to(b) > gap:
			gap = a.distance_to(b)
			gap_part = part_name
	if gap > 0.12:
		_gap_incidents += 1
		if _gap_incidents <= 12:
			print("t=%6.2f %s JOINT GAP %.2f m at %s | state %d dead %s" % [t, r.name, gap, gap_part, r.state, r.get("is_dead") == true])
	var far := pelvis.global_position.distance_to(player_pos)
	var id := r.get_instance_id()
	var dead: bool = r.get("is_dead") == true
	var key := "%d:%s" % [id, dead]
	# A limp dead body may fold onto itself (head onto the pelvis); only a
	# limb flung far off counts there.
	var limit := TEAR_LIMIT * (1.7 if dead else 1.0)
	if worst > limit and worst > float(_worst.get(key, 0.0)) + 0.5:
		_worst[key] = worst
		_incidents += 1
		print("t=%6.2f %s%s tear %.2f m at %s | state %d dead %s muscle %.2f pelvis %s dist %.1f" % [
			t, r.name, " (elite)" if r.has_method("is_elite") and r.is_elite() else "", worst, worst_part,
			r.state, dead, r.muscle, pelvis.global_position.snapped(Vector3.ONE * 0.1), far])
	if not dead and worst < 0.2:
		_worst.erase(key)
