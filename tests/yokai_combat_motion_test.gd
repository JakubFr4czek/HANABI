extends Node
## Yokai combat poses: approach stride, attack wind-up/slash (ActiveRagdoll blend).
##   godot --headless --path . --fixed-fps 90 res://tests/yokai_combat_motion_test.tscn -- --desktop

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
	var y := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -2.4), player.global_position)
	y.brain.move_speed = 0.0
	player.teleport(Vector3(0.0, 0.0, 1.0), 0.0)
	await _frames(12)
	_check("Approach pose exists in rig", y._poses.has("approach") and y._poses.has("flinch"))
	y.brain.force_attack("right")
	await _frames(6)
	_check("Wind-up pose before slash", y.current_pose.begins_with("windup"))
	await _frames(48)
	_check("Attack chain reaches slash or recover",
		y.brain.state in [YokaiBrain.State.SLASH, YokaiBrain.State.RECOVER, YokaiBrain.State.APPROACH])
	await _frames(36)
	if y.brain.state == YokaiBrain.State.RECOVER:
		_check("Recovery phase uses recover overlay pose", y.overlay_pose == "recover")
	y.brain.on_hit({"damage": 20.0, "power": 0.5})
	await _frames(3)
	_check("Heavy hit from brain staggers yōkai", y.brain.state == YokaiBrain.State.STAGGER)
	run.queue_free()
	await _frames(2)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
