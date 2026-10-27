extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_point9_vfx"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	run.wave_director.stop_director()
	var player := run.player as DesktopPlayer
	player.teleport(Vector3(0.0, 0.0, 2.4), 0.0)
	player.camera.rotation.x = deg_to_rad(-8.0)

	SoulOrb.spawn_cluster(run._souls_root, Vector3(0.0, 1.05, -1.2), 10, 6, Elements.SAKURA)
	await _frames(20)
	await _shot("hitodama_cluster")

	var y := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -2.0), player.global_position)
	y.set_pose("stalk")
	y.last_kill_element = Elements.STORM
	y.die({"point": y.global_position + Vector3(0, 1.2, 0), "direction": Vector3.UP})
	await _frames(18)
	await _shot("element_death_firework")

	var elite := run.wave_director.spawn_elite_at(Vector3(1.8, 0.0, -2.4), player.global_position, Elements.SHADOW)
	elite.set_pose("stalk")
	await _frames(18)
	await _shot("elite_halo_fog")

	var oni := run.wave_director.spawn_oni_boss(player.global_position)
	oni.global_position = Vector3(-0.5, 0.0, -2.6)
	oni.home_position = oni.global_position
	oni.set_attacks_enabled(false)
	oni.set_pose("guard")
	await _frames(22)
	await _shot("oni_fog_silhouette")

	run.queue_free()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
