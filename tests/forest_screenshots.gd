extends Node
## Single-frame forest vista for visual review (run scene, no full run_screenshots loop).

const RUN_SCENE := preload("res://scenes/run.tscn")

var out_dir := "/tmp/hanabi_forest_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-10.0)
	await _frames(45)
	await _shot("forest_horizon")
	# Look out sideways from the shrine edge into the tree line.
	player.teleport(Vector3(3.5, 0.0, 1.0), -PI * 0.5)
	player.camera.rotation.x = deg_to_rad(-6.0)
	await _frames(30)
	await _shot("forest_from_shrine_edge")
	# Walked out among the hills, far from the shrine.
	player.teleport(Vector3(30.0, run.forest_world.height_at(30.0, 18.0), 18.0), PI * 0.25)
	player.camera.rotation.x = deg_to_rad(-6.0)
	await _frames(60)
	await _shot("forest_deep_walk")
	# Looking back at the shrine clearing from the tree line.
	player.teleport(Vector3(0.0, run.forest_world.height_at(0.0, 12.5), 12.5), 0.0)
	player.camera.rotation.x = deg_to_rad(-4.0)
	await _frames(45)
	await _shot("forest_back_to_shrine")
	# Forest floor at the feet: needle soil, grass patches, stones.
	player.teleport(Vector3(14.0, run.forest_world.height_at(14.0, 9.0), 9.0), 0.6)
	player.camera.rotation.x = deg_to_rad(-38.0)
	await _frames(30)
	await _shot("forest_floor")
	# Yōkai far off in the fog: only their eyes read.
	player.teleport(Vector3(0.0, 0.0, 0.0), 0.0)
	player.camera.rotation.x = deg_to_rad(0.0)
	run.wave_director.clear_enemies()
	for d in [6.0, 11.0, 16.0]:
		var ex: float = -1.6 + float(d) * 0.2
		run.wave_director.spawn_enemy_at(Vector3(ex, run.forest_world.height_at(ex, -d), -d), player.global_position).brain.attacks_enabled = false
	await _frames(12)
	for e in run.wave_director.alive_enemies():
		e.set_physics_process(false)
		print("eyes yokai at ", e.root_part().global_position)
	await _frames(6)
	await _shot("yokai_eyes_in_fog")
	run.wave_director.clear_enemies()
	# A gate the forest generator placed, met in the fog.
	var gate := run.forest_world.nearest_torii_position(Vector3.ZERO)
	if gate != Vector3.INF:
		var stand := gate + Vector3(0.0, 0.0, 7.0)
		player.teleport(Vector3(stand.x, run.forest_world.height_at(stand.x, stand.z), stand.z), 0.0)
		player.camera.rotation.x = deg_to_rad(4.0)
		await _frames(45)
		await _shot("forest_torii_7m")
	run.queue_free()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
