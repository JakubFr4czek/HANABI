extends Node
## Prints where the quest_perf_test draw-call estimate comes from (visible
## MeshInstance3D / MultiMeshInstance3D nodes grouped by owner), with the menu
## closed and open. Run: godot --headless --path . res://tests/diag/diag_draw_breakdown.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")


func _ready() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	for _i in 20:
		await get_tree().physics_frame
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var player := run.player as DesktopPlayer
	player.teleport(Vector3(0.0, 0.0, 1.2), 0.0)
	for i in 8:
		run.wave_director.spawn_enemy_at(Vector3(sin(i * 0.9) * 7.5, 0.0, cos(i * 0.9) * 7.5), player.global_position)
	run.element_system.imbue(Elements.STORM)
	for _i in 30:
		await get_tree().physics_frame
	_report(run, "closed")
	run.pause_controller.open()
	for _i in 6:
		await get_tree().physics_frame
	_report(run, "menu open")
	get_tree().quit(0)


func _report(run: RunGame, label: String) -> void:
	var groups := {}
	var hidden_in_tree := {}
	var total := 0
	var real := 0
	for cls in ["MeshInstance3D", "MultiMeshInstance3D"]:
		for n in run.find_children("*", cls, true, false):
			if not (n as Node3D).visible:
				continue
			total += 1
			real += 1 if (n as Node3D).is_visible_in_tree() else 0
			if not (n as Node3D).is_visible_in_tree():
				hidden_in_tree[String(run.get_path_to(n)).split("/")[0] + "/" + String(run.get_path_to(n)).split("/")[1]] = true
			var path := String(run.get_path_to(n)).split("/")
			var key := "/".join(path.slice(0, mini(2, path.size() - 1)))
			groups[key] = int(groups.get(key, 0)) + 1
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a] > groups[b])
	print("== %s: estimate %d, truly visible in tree %d" % [label, total, real])
	for k in keys.slice(0, 18):
		print("   %4d  %s" % [groups[k], k])
