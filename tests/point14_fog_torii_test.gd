extends Node
## GDD §9: forest/torii dissolve before the giant torii sightline; no hills past the gate.
##   godot --headless --path . --fixed-fps 90 res://tests/point14_fog_torii_test.tscn -- --desktop

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
	await _frames(12)
	var env: Environment = run.get_node("WorldEnvironment").environment
	_check("Run fog closes within ~10 m of the giant torii (end=%.2f)" % env.fog_depth_end,
		env.fog_depth_end <= 10.0 and env.fog_density >= 1.35)
	_check("Forest props fade out before torii line (view end %.1f m)" % ForestWorld.VIEW_RANGE_END,
		ForestWorld.VIEW_RANGE_END <= 13.0)
	var mat := run.forest_world._ground_mat as ShaderMaterial
	_check("Ground shader discards distant hills into fog",
		float(mat.get_shader_parameter("fog_fade_end")) <= 11.0)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
