extends Node
## Wrist HP ring appears only at critical health (§15/§17).
##   godot --headless --path . --fixed-fps 90 res://tests/point17_diegetic_critical_test.tscn -- --desktop

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
	var hud := run.diegetic_hud
	hud.update_hud(100.0, 100.0, 0, 30, 1, 1, 0, 0, 0.0, Elements.NONE)
	_check("HP ring hidden at full health", hud.wrist_hp_ring != null and not hud.wrist_hp_ring.visible)
	hud.update_hud(22.0, 100.0, 0, 30, 1, 1, 0, 0, 0.0, Elements.NONE)
	_check("HP ring visible below 30% health", hud.wrist_hp_ring.visible)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
