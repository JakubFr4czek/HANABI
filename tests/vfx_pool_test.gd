extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	_check("VfxPool autoload prewarms soul orbs", VfxPool != null and VfxPool._soul_free.size() >= 40)
	var before_sparks := VfxPool._spark_free.size()
	for _i in 12:
		SparkBurst.spawn(self, Vector3.ZERO, Vector3.UP, Color.WHITE, 8, 2.0)
	await _frames(8)
	await get_tree().create_timer(0.55).timeout
	_check("Spark bursts return to pool after finishing", VfxPool._spark_free.size() >= before_sparks)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	run.wave_director.stop_director()
	var pool_before := VfxPool._soul_free.size()
	var orbs := SoulOrb.spawn_cluster(run._souls_root, Vector3(0, 1, -1), 6, 5, Elements.SAKURA)
	_check("Soul cluster uses pooled orbs", orbs.size() == 6)
	for orb in orbs:
		orb._collect()
	await _frames(4)
	_check("Collected souls return to VfxPool", VfxPool._soul_free.size() >= pool_before)
	run.wave_director.stop_director()
	run.state = RunGame.RunState.GAME_OVER
	await _frames(4)
	run.queue_free()
	await _frames(2)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame
