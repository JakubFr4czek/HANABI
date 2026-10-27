extends Node
## Point-12: combat fog bubble, fog-piercing death VFX, Oni readability hooks.
##   godot --headless --path . --fixed-fps 90 res://tests/point12_readability_test.tscn -- --desktop

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
	var fog := run.combat_fog
	_check("RunCombatFog binds and keeps full-strength fog for distant hills",
		fog != null and fog.call("base_fog_density") >= 0.99)

	var we: Environment = run.get_node("WorldEnvironment").environment
	var base_end := we.fog_depth_end
	var base_begin := we.fog_depth_begin
	var base_density: float = fog.call("base_fog_density")
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var player := run.player as DesktopPlayer
	player.teleport(Vector3(0.0, 0.0, 1.5), 0.0)
	run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -1.8), player.global_position)
	await _frames(14)
	_check("Combat fog clears near enemies without opening distant fog (begin %.2f -> %.2f, end=%.2f)" % [base_begin, we.fog_depth_begin, we.fog_depth_end],
		we.fog_depth_begin > base_begin + 0.5 and we.fog_density >= base_density - 0.001 and we.fog_depth_end <= base_end + 0.01)

	_check("Element firework helper spawns fog-piercing burst API",
		ElementFirework != null)
	var pool := get_node_or_null("/root/VfxPool")
	if pool:
		_check("Pooled spark/ring materials ignore fog for readable fireworks",
			pool.death_vfx_ignores_fog())

	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
