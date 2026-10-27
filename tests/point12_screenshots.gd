extends Node
## Point-12 visuals: CC0 forest/torii in fog, nothing readable past giant torii,
## Oni close-up, elemental firework in fog.

const RUN_SCENE := preload("res://scenes/run.tscn")

var out_dir := "/tmp/hanabi_point12_shots"


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

	# Forest + CC0 torii readable inside ~12 m.
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	player.camera.rotation.x = deg_to_rad(-9.0)
	await _frames(40)
	await _shot("1_forest_cc0_torii_near")

	# Through giant torii: hills/trees must dissolve — no hard horizon line.
	player.teleport(Vector3(0.0, 0.0, 0.35), deg_to_rad(180.0))
	player.camera.rotation.x = deg_to_rad(-3.0)
	await _frames(35)
	await _shot("2_beyond_giant_torii_fog")

	# Oni readable at ma-ai (~3 m).
	player.teleport(Vector3(0.0, 0.0, 2.85), 0.0)
	player.camera.rotation.x = deg_to_rad(-5.0)
	var oni := run.wave_director.spawn_oni_boss(player.global_position)
	oni.global_position = Vector3(0.0, 1.0, -3.8)
	oni.home_position = oni.global_position
	oni.set_attacks_enabled(false)
	oni.set_pose("guard")
	var face := player.global_position
	face.y = oni.global_position.y
	oni.look_at(face, Vector3.UP)
	await _frames(28)
	await _shot("3_oni_close_mask")

	# Firework in heavy fog ring.
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-8.0)
	var burst_at := Vector3(0.0, 1.15, -2.5)
	var y := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -2.5), player.global_position)
	y.last_kill_element = Elements.SAKURA
	y.die({"point": burst_at, "direction": Vector3.UP})
	await _frames(6)
	ElementFirework.spawn(run, burst_at, Elements.STORM, 1.2)
	await _frames(8)
	await _shot("4_firework_in_fog")

	run.queue_free()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	else:
		await _frames(2)
	var tex := get_viewport().get_texture()
	if tex == null:
		push_warning("point12_screenshots: no viewport texture for %s (use non-headless Godot)" % name)
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		push_warning("point12_screenshots: empty image for %s" % name)
		return
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
