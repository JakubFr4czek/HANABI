extends Node
## Unit tests for Torii gate placement, collider clearance (3.2m),
## gate spacing (18–32m from the player, 40m between gates), gates running along
## the footpaths (passage within 25° of the tangent), and elemental uptime ratio
## >= 0.65 in a 120s run.
##   godot --headless --path . --fixed-fps 90 res://tests/torii_placement_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(15)

	var p_pos := run._player_center()
	var tm: ToriiManager = run.forest_world.torii_manager
	_check("ToriiManager is initialized and attached to ForestWorld", tm != null)
	if tm == null:
		run.queue_free()
		return

	# 1. At least one gate exists in 18–32m radius of the player
	var gates := tm.get_active_gates()
	_check("Active Torii gates spawned in the forest", not gates.is_empty())

	var nearest_dist := INF
	var has_gate_in_range := false
	for g in gates:
		var d := g.global_position.distance_to(p_pos)
		nearest_dist = minf(nearest_dist, d)
		if d >= ToriiManager.MIN_SPAWN_DIST and d <= ToriiManager.MAX_SPAWN_DIST:
			has_gate_in_range = true

	_check("At least one gate exists in 18–32m radius (nearest=%.1f m)" % nearest_dist,
		has_gate_in_range and nearest_dist >= ToriiManager.MIN_SPAWN_DIST and nearest_dist <= ToriiManager.MAX_SPAWN_DIST)

	# Verify player body collision layer matches XRPlayer.COLLISION_LAYER_BODY (1 << 19)
	var player_body_layer := 0
	if run.player is DesktopPlayer:
		player_body_layer = (run.player as DesktopPlayer).collision_layer
	elif run.player is XRPlayer:
		var b := (run.player as XRPlayer)._body() as CharacterBody3D
		if b:
			player_body_layer = b.collision_layer
	_check("Player body in run game has XRPlayer.COLLISION_LAYER_BODY (layer=%d, expected=%d)" % [player_body_layer, XRPlayer.COLLISION_LAYER_BODY],
		(player_body_layer & XRPlayer.COLLISION_LAYER_BODY) != 0)

	# Benchmark the gate search (< 2.0 ms on desktop). The search is timed on its
	# own: _attempt_spawn_gate_in_range also instantiates a gate when it finds a
	# place, and that cost depends on how many gates already stand, not on the
	# search. One warm-up, then the median of five runs against single-run noise.
	tm.find_gate_spot(p_pos)
	var samples: Array[float] = []
	for k in 5:
		var t_start := Time.get_ticks_usec()
		tm.find_gate_spot(p_pos)
		samples.append((Time.get_ticks_usec() - t_start) / 1000.0)
	samples.sort()
	var median_ms: float = samples[2]
	_check("Gate search runs under 2.0 ms (median %.3f ms of 5)" % median_ms, median_ms < 2.0)

	# 2. Gate never spawns overlapping trunk or boulder colliders (clearance >= 3.2 m)
	# Real physics space query on TRUNK_LAYER (layer 64) with CylinderShape3D
	var space := run.get_world_3d().direct_space_state
	var physical_collision_hits := 0
	var min_multimesh_clearance := INF

	# MultiMesh instance inspection across active chunks
	var multimesh_instances: Array[Vector3] = []
	for key in run.forest_world._chunks:
		var chunk: Node3D = run.forest_world._chunks[key]
		if chunk == null or not is_instance_valid(chunk):
			continue
		for m_name in ["Trees0", "Undergrowth0", "Lanterns"]:
			var mm_node := chunk.get_node_or_null(m_name) as MultiMeshInstance3D
			if mm_node and mm_node.multimesh:
				var mm := mm_node.multimesh
				for i in mm.instance_count:
					var inst_pos: Vector3 = chunk.global_transform * mm.get_instance_transform(i).origin
					multimesh_instances.append(inst_pos)

	for g in gates:
		var gx := g.global_position.x
		var gy := g.global_position.y
		var gz := g.global_position.z

		# Physics cylinder query (radius = 3.2m, height = 4.0m)
		if space:
			var query := PhysicsShapeQueryParameters3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = ToriiGate.CLEARANCE_RADIUS - 0.05
			cyl.height = 4.0
			query.shape = cyl
			query.transform = Transform3D(Basis(), Vector3(gx, gy + 2.0, gz))
			query.collision_mask = ForestWorld.TRUNK_LAYER
			var hits := space.intersect_shape(query, 10)
			for hit in hits:
				var collider = hit.get("collider")
				if collider != g._static_body and collider != g:
					physical_collision_hits += 1

		# MultiMesh distance check
		for inst_pos in multimesh_instances:
			var d := Vector2(gx - inst_pos.x, gz - inst_pos.z).length()
			min_multimesh_clearance = minf(min_multimesh_clearance, d)

	_check("Physics query confirms 0 trunk/boulder collider overlaps inside 3.2m cylinder (hits=%d)" % physical_collision_hits,
		physical_collision_hits == 0)
	_check("MultiMesh instances maintain >= 3.2m clearance from gate center (min=%.2f m)" % min_multimesh_clearance,
		min_multimesh_clearance >= ToriiGate.CLEARANCE_RADIUS - 0.05)

	# 2b. Active gates keep MIN_GATE_SEPARATION from each other.
	var sep := _min_active_separation(tm)
	_check("Active gates keep >= %.0f m apart (closest pair=%.1f m)" % [ToriiManager.MIN_GATE_SEPARATION, sep],
		sep >= ToriiManager.MIN_GATE_SEPARATION - 0.01)

	# 2c. A gate beside a footpath runs along it: the passage direction is within 25° of
	# the path tangent, so the posts stand across the path. Checked on the live gates,
	# then on a gate placed on a footpath sample; off the paths the yaw is not path-based.
	var paths := run.forest_world.paths
	_check("The run builds the forest with its footpaths", paths != null)
	if paths != null:
		var worst_deg := 0.0
		var beside := 0
		for g in tm.get_active_gates():
			var tangent := _nearest_tangent(paths, Vector2(g.global_position.x, g.global_position.z), ToriiManager.PATH_ALIGN_RADIUS)
			if tangent != Vector2.ZERO:
				beside += 1
				worst_deg = maxf(worst_deg, _passage_angle_deg(g, tangent))
		_check("Gates beside a footpath run along it (%d beside, worst %.1f°)" % [beside, worst_deg],
			worst_deg < 25.0)

		var on_path := _footpath_sample_free_of_gates(paths, tm, p_pos)
		_check("Found a footpath sample away from the live gates", on_path.z != 0.0 or on_path.w != 0.0)
		if on_path.z != 0.0 or on_path.w != 0.0:
			var placed := tm.spawn_gate_at(on_path.x, on_path.y, Elements.SAKURA)
			var angle := _passage_angle_deg(placed, Vector2(on_path.z, on_path.w))
			_check("Gate placed on a footpath runs along its tangent (%.1f°)" % angle, angle < 25.0)
			tm.active_gates.erase(placed)
			tm.remove_child(placed)
			placed.free()

		var off := _off_path_spot(paths, p_pos)
		_check("Off the footpaths the gate yaw stays slope/player based (no path yaw)",
			off != Vector2.INF and is_nan(tm._path_yaw(off.x, off.y)))

	# 3. Uptime ratio >= 0.65 in 120s test with time stepping
	# We simulate a 120-second run traversal: player advances along a heading,
	# crossing gates, maintaining realistic movement speed (~1.5 m/s).
	# Time is stepped in discrete physics frames (120 seconds total).
	var dir := Vector3(0.0, 0.0, -1.0)
	var speed := 1.55 # m/s (realistic forest traversal pace)
	var step_dt := 0.1 # 100 ms physics step
	var total_steps := int(120.0 / step_dt)

	tm.gate_spawned.connect(func(g): print("SPAWNED GATE elem=", g.element, " pos=", g.global_position, " active_total=", tm.active_gates.size()))
	for g in tm.get_active_gates():
		g.gate_crossed.connect(func(elem, gate): print("CROSSED GATE elem=", elem, " time=", run.run_time))
	var current_target_gate: ToriiGate = null
	var min_pair_sep := INF
	for _i in total_steps:
		if _i % 10 == 0:
			min_pair_sep = minf(min_pair_sep, _min_active_separation(tm))
		if _i % 20 == 0 and current_target_gate:
			print("STEP %d: p_pos=%s gate=%s dist=%.2f active=%s" % [_i, p_pos, current_target_gate.global_position, p_pos.distance_to(current_target_gate.global_position), current_target_gate.is_active])
		if current_target_gate == null or not is_instance_valid(current_target_gate) or not current_target_gate.is_active:
			var min_d := INF
			current_target_gate = null
			for g in tm.get_active_gates():
				if g.is_active:
					var d := g.global_position.distance_to(p_pos)
					if d < min_d:
						min_d = d
						current_target_gate = g

		if current_target_gate and current_target_gate.is_active:
			var flat_diff := Vector2(current_target_gate.global_position.x - p_pos.x, current_target_gate.global_position.z - p_pos.z)
			if flat_diff.length() > 0.5:
				dir = Vector3(flat_diff.x, 0.0, flat_diff.y).normalized()
			# else keep existing dir to push cleanly straight through the plane
		else:
			dir = Vector3(-0.3, 0.0, -0.95).normalized()

		p_pos += dir * speed * step_dt
		if run.player is DesktopPlayer:
			(run.player as DesktopPlayer).teleport(p_pos, 0.0)
		elif run.player is XRPlayer:
			(run.player as XRPlayer).teleport_feet(p_pos)
		else:
			run.player.global_position = p_pos

		# Step physics
		run._physics_process(step_dt)
		run.forest_world._physics_process(step_dt)
		tm._physics_process(step_dt)
		for g in tm.get_active_gates():
			g._physics_process(step_dt)
		if run.element_system:
			run.element_system._physics_process(step_dt)
			# D21: gates store charges; the traveller presses the charge button as soon as the blade is plain steel.
			if run.element_system.can_activate_charge():
				run.element_system.activate_charge()
		if run.katana:
			run.katana._physics_process(step_dt)

	var uptime := run.element_uptime_ratio()
	print("TRAVERSAL UPTIME METRIC: active=%.1f s, total=%.1f s, ratio=%.3f (req >= 0.65)" % [
		run.element_active_seconds, run.run_time, uptime
	])
	_check("Elemental uptime ratio >= 0.65 in 120s run (actual=%.2f)" % uptime, uptime >= 0.65)
	_check("Active gates stayed >= %.0f m apart through the 120s run (closest pair=%.1f m)" % [
		ToriiManager.MIN_GATE_SEPARATION, min_pair_sep], min_pair_sep >= ToriiManager.MIN_GATE_SEPARATION - 0.01)

	run.queue_free()


## Closest distance between two active gates (INF with fewer than two).
func _min_active_separation(tm: ToriiManager) -> float:
	var best := INF
	var active: Array[ToriiGate] = []
	for g in tm.get_active_gates():
		if g.is_active:
			active.append(g)
	for i in active.size():
		for j in range(i + 1, active.size()):
			best = minf(best, active[i].global_position.distance_to(active[j].global_position))
	return best


## Unit tangent of the footpath nearest to [param p] within [param reach] (ZERO if none).
func _nearest_tangent(paths: ForestPaths, p: Vector2, reach: float) -> Vector2:
	var best := INF
	var tangent := Vector2.ZERO
	var segs := paths.segments_in_rect(Rect2(p - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	for k in range(0, segs.size() - 1, 2):
		if segs[k].distance_squared_to(segs[k + 1]) < 1e-9:
			continue
		var d := ForestPaths.segment_distance(p, segs[k], segs[k + 1])
		if d < best:
			best = d
			tangent = (segs[k + 1] - segs[k]).normalized()
	return tangent if best <= reach else Vector2.ZERO


## Angle in degrees between the gate's passage direction (local Z) and [param tangent].
func _passage_angle_deg(gate: ToriiGate, tangent: Vector2) -> float:
	var pass_dir := gate.global_transform.basis.z
	var v := Vector2(pass_dir.x, pass_dir.z).normalized()
	return rad_to_deg(acos(clampf(absf(v.dot(tangent.normalized())), 0.0, 1.0)))


## A footpath sample (x, z, tangent.x, tangent.y) near the player, more than 10 m away
## from it and 12 m from every live gate; all zero when there is none.
func _footpath_sample_free_of_gates(paths: ForestPaths, tm: ToriiManager, p_pos: Vector3) -> Vector4:
	var c := Vector2(p_pos.x, p_pos.z)
	for s in paths.samples_in_rect(Rect2(c - Vector2(40.0, 40.0), Vector2(80.0, 80.0)), 1.0):
		var q := Vector2(s.x, s.y)
		if q.distance_to(c) > 10.0 and not tm.is_near_gate(q.x, q.y, 12.0):
			return s
	return Vector4.ZERO


## A point 40 m from the player with no footpath within the alignment radius; INF if none.
func _off_path_spot(paths: ForestPaths, p_pos: Vector3) -> Vector2:
	var c := Vector2(p_pos.x, p_pos.z)
	for i in 24:
		var ang := TAU * float(i) / 24.0
		var q := c + Vector2(sin(ang), cos(ang)) * 40.0
		if _nearest_tangent(paths, q, ToriiManager.PATH_ALIGN_RADIUS) == Vector2.ZERO:
			return q
	return Vector2.INF


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
