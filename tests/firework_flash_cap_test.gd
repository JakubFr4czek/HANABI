extends Node
## Death fireworks must not spawn unbounded OmniLight3D nodes (Quest perf).
##   godot --headless --path . --fixed-fps 90 res://tests/firework_flash_cap_test.tscn -- --desktop

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
	await _frames(8)
	var origin := Vector3(0.0, 1.1, -1.5)
	for i in 16:
		ElementFirework.spawn(run, origin + Vector3(float(i % 4) * 0.35, 0.0, float(i / 4) * 0.25), Elements.STORM, 1.0)
	await _frames(2)
	var pool := get_node_or_null("/root/VfxPool")
	_check("VfxPool caps simultaneous firework flash lights",
		pool != null and pool.active_firework_flash_count() <= VfxPool.MAX_FIREWORK_FLASH_LIGHTS)
	var lights := 0
	for n in run.find_children("*", "OmniLight3D", true, false):
		if (n as OmniLight3D).name == "FireworkFlash":
			lights += 1
	_check("Scene has at most %d FireworkFlash lights right after burst" % VfxPool.MAX_FIREWORK_FLASH_LIGHTS,
		lights <= VfxPool.MAX_FIREWORK_FLASH_LIGHTS)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
