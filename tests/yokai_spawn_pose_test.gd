extends Node
## Yokai must not spawn in rest T-pose (stalk snapped on pool reuse).
##   godot --headless --path . --fixed-fps 90 res://tests/yokai_spawn_pose_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(10)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var y := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -2.0), player.global_position)
	await _frames(14)
	_check("Spawned yōkai uses stalk/approach pose (not default guard T-pose)",
		y.current_pose == "stalk" or y.current_pose == "approach")
	var errs := y.pose_errors()
	var arm_err: float = float(errs.get("arm_r", 99.0))
	_check("Arm joints are near stalk targets (arm_r err %.1f°, not T-pose ~90°)" % arm_err, arm_err < 28.0)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
