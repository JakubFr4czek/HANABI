extends Node
## GDD §9: the forest and its hills dissolve into fog before the edge of the loaded chunks.
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
	_check("Run depth fog is fully opaque before the loaded chunks end (end=%.2f m)" % env.fog_depth_end,
		env.fog_mode == Environment.FOG_MODE_DEPTH and env.fog_density >= 0.99
		and env.fog_depth_end <= ForestWorld.VIEW_RANGE_END)
	var horizon := run.horizon_fog_color
	var rendered := env.fog_light_color.srgb_to_linear()
	_check("Sky horizon takes the color the fog renders, so fogged hills vanish into it",
		absf(horizon.r - rendered.r) + absf(horizon.g - rendered.g) + absf(horizon.b - rendered.b) < 0.003)
	# The forest is walkable, so these are measured from the camera: props and
	# ground dissolve before the 14 m edge of the loaded 3×3 chunk ring.
	_check("Forest props fade out inside the loaded chunk ring (view end %.1f m)" % ForestWorld.VIEW_RANGE_END,
		ForestWorld.VIEW_RANGE_END <= ForestWorld.CHUNK_SIZE * 0.5)
	var mat := run.forest_world._ground_mat as ShaderMaterial
	_check("Ground is not cut away under props inside the loaded ring (fade from %.0f m)" % float(mat.get_shader_parameter("fog_fade_start")),
		float(mat.get_shader_parameter("fog_fade_start")) > ForestWorld.CHUNK_SIZE)
	_check("Forest starts close enough to read as a forest (props from %.1f m)" % ForestWorld.PROP_CLEARING_RADIUS,
		ForestWorld.PROP_CLEARING_RADIUS < 9.0)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
