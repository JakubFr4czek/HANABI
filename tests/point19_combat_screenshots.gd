extends Node
## §19 desktop shots: Oni at ~2 m / ~6 m in fog during a wave, yōkai approach + flinch.

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_point19_combat"


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
	run.wave_director.wave = 4
	for k in 4:
		var ang := k * TAU / 4.0 + 0.4
		run.wave_director.spawn_enemy_at(
			Vector3(sin(ang) * 8.5, 0.0, cos(ang) * 8.5 - 2.0),
			player.global_position)

	var oni := run.wave_director.spawn_oni_boss(player.global_position)
	oni.set_attacks_enabled(false)
	oni.set_pose("guard")

	# ~2 m read in combat fog.
	oni.global_position = Vector3(0.0, 1.0, -2.15)
	oni.home_position = oni.global_position
	_face_player(oni, player)
	player.teleport(Vector3(0.0, 0.0, 0.05), 0.0)
	player.camera.rotation.x = deg_to_rad(-4.0)
	await _frames(40)
	await _shot("oni_fog_2m_wave")

	# ~6 m silhouette + distant yōkai ring.
	oni.global_position = Vector3(0.0, 1.0, -6.2)
	oni.home_position = oni.global_position
	_face_player(oni, player)
	player.teleport(Vector3(0.0, 0.0, 0.05), 0.0)
	player.camera.rotation.x = deg_to_rad(-1.5)
	await _frames(36)
	await _shot("oni_fog_6m_wave")

	run.wave_director.clear_enemies()
	var y := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -3.2), player.global_position)
	y.brain.move_speed = 2.1
	y.snap_pose("approach")
	player.teleport(Vector3(0.0, 0.0, 1.4), 0.0)
	player.camera.rotation.x = deg_to_rad(-8.0)
	await _frames(28)
	await _shot("yokai_approach_stride")

	y.brain.on_hit({"damage": 24.0, "power": 0.65, "zone": "chest"})
	await _frames(10)
	await _shot("yokai_flinch_hit")

	run.queue_free()
	get_tree().quit(0)


func _face_player(oni: Node3D, player: Node3D) -> void:
	var face := player.global_position
	face.y = oni.global_position.y
	oni.look_at(face, Vector3.UP)


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
		return
	var img := tex.get_image()
	if img and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)
