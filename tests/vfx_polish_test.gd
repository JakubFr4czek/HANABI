extends Node

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
	await _frames(16)
	run.wave_director.stop_director()
	var player := run.player as DesktopPlayer
	var y := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -2.0), player.global_position)
	await _frames(6)
	y.snap_pose("stalk")
	await _frames(6)
	var arm_err: float = float(y.pose_errors().get("arm_r", 99.0))
	_check("Yōkai hold stalk pose instead of a bind T-pose",
		(y.current_pose == "stalk" or y.current_pose == "approach") and arm_err < 28.0)
	y.prepare_for_spawn()
	_check("prepare_for_spawn resets dead state", not y.is_dead and y.current_pose == "stalk")
	var oni: RunOniBoss = run.wave_director.spawn_oni_boss(player.global_position)
	await _frames(8)
	_check("Oni boss spawns with RunOniBoss visuals", oni != null and oni.is_in_group("oni_boss"))
	var pelvis := oni.parts.get("pelvis") as RagdollPart
	_check("Oni wears body shell and kanabō visual (not red ragdoll primitives)",
		pelvis != null and pelvis.get_node_or_null("OniBodyShell") != null
		and oni.parts.get("lower_arm_r").get_node_or_null("OniKanaboVisual") != null)
	_check("Oni boss uses demon flesh material, not default wood",
		oni._flesh != null and oni._flesh.get_shader_parameter("base_color").r < 0.2)
	var elite := run.wave_director.spawn_elite_at(Vector3(2.0, 0.0, -2.5), player.global_position, Elements.INK)
	await _frames(4)
	_check("Elite yōkai wear a visible elemental halo ring", elite._elite_halo != null)
	_check("Element firework helper exists for death VFX", ElementFirework != null)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
