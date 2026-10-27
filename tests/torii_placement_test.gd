extends Node
## Unit tests for Torii gate placement, collider clearance (3.2m),
## gate spacing (18–32m), and elemental uptime ratio >= 0.65 in a 120s run.
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

	# 2. Gate never spawns overlapping trunk or boulder colliders (clearance >= 3.2 m)
	var any_overlap := false
	var min_clearance := INF

	# Gather all tree spots from loaded chunks
	var tree_positions: Array[Vector3] = []
	for coord in run.forest_world.active_chunk_keys:
		var packed: Dictionary = run.forest_world._tree_spot_cache.get(coord, {})
		for s in packed.get("spots", []):
			var spot: Vector4 = s
			tree_positions.append(Vector3(spot.x, 0.0, spot.y))

	for g in gates:
		var gx := g.global_position.x
		var gz := g.global_position.z
		for tp in tree_positions:
			var d := Vector2(gx - tp.x, gz - tp.z).length()
			min_clearance = minf(min_clearance, d)
			if d < ToriiGate.CLEARANCE_RADIUS - 0.01:
				any_overlap = true

	_check("Gate never spawns inside trunk/boulder colliders (min clearance=%.2f m, req=%.1f m)" % [min_clearance, ToriiGate.CLEARANCE_RADIUS],
		not any_overlap and min_clearance >= ToriiGate.CLEARANCE_RADIUS - 0.01)

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
	for _i in total_steps:
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
		if run.katana:
			run.katana._physics_process(step_dt)

	var uptime := run.element_uptime_ratio()
	print("TRAVERSAL UPTIME METRIC: active=%.1f s, total=%.1f s, ratio=%.3f (req >= 0.65)" % [
		run.element_active_seconds, run.run_time, uptime
	])
	_check("Elemental uptime ratio >= 0.65 in 120s run (actual=%.2f)" % uptime, uptime >= 0.65)

	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
