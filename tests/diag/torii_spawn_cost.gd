extends Node
## Times one gate spawn (spawn_gate_at) at a fixed spot, and one gate search
## (find_gate_spot, when the build has it). Each spawned gate is removed again at
## once, so every sample sees the same gate count.
##   godot --headless --path . --fixed-fps 90 res://tests/diag/torii_spawn_cost.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
const SAMPLES := 9
const SPOT := Vector2(-19.05, 12.8)

func _ready() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	for _i in 15:
		await get_tree().physics_frame
	var tm: ToriiManager = run.forest_world.torii_manager
	var p_pos := run._player_center()

	var spawn_ms: Array[float] = []
	for _k in SAMPLES:
		var s0 := Time.get_ticks_usec()
		var g := tm.spawn_gate_at(SPOT.x, SPOT.y)
		spawn_ms.append((Time.get_ticks_usec() - s0) / 1000.0)
		tm.active_gates.erase(g)
		g.get_parent().remove_child(g)
		g.free()

	var search_ms: Array[float] = []
	if tm.has_method("find_gate_spot"):
		for _k in SAMPLES:
			var q0 := Time.get_ticks_usec()
			tm.call("find_gate_spot", p_pos)
			search_ms.append((Time.get_ticks_usec() - q0) / 1000.0)
		search_ms.sort()
		print("COST find_gate_spot median %.3f ms (min %.3f, max %.3f, n=%d)" % [search_ms[search_ms.size() / 2], search_ms[0], search_ms[-1], search_ms.size()])

	spawn_ms.sort()
	print("COST spawn_gate_at median %.3f ms (min %.3f, max %.3f, n=%d)" % [spawn_ms[spawn_ms.size() / 2], spawn_ms[0], spawn_ms[-1], spawn_ms.size()])
	print("COST gates_now=%d" % tm.get_active_gates().size())
	run.queue_free()
	get_tree().quit(0)
