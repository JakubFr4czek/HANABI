extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_enemy_shots"


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
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	player.camera.rotation.x = deg_to_rad(-8.0)

	var elite := run.wave_director.spawn_elite_at(Vector3(0.0, 0.0, -2.2), player.global_position, Elements.SHADOW)
	var s1 := run.wave_director.spawn_enemy_at(Vector3(-1.4, 0.0, -3.2), player.global_position)
	var s2 := run.wave_director.spawn_enemy_at(Vector3(1.3, 0.0, -3.0), player.global_position)
	s1.set_pose("stalk")
	s2.set_pose("stalk")
	elite.brain.force_attack("right")
	elite.set_pose("stalk")
	await _frames(28)
	await _shot("elite_shadow_pack")

	run.wave_director.clear_enemies()
	var oni := run.wave_director.spawn_oni_boss(player.global_position)
	oni.global_position = Vector3(0.0, 0.0, -2.35)
	oni.home_position = oni.global_position
	oni.rotation.y = 0.0
	oni.reset_body()
	player.teleport(Vector3(0.0, 0.0, 2.8), 0.0)
	player.camera.rotation.x = deg_to_rad(-6.0)
	oni.set_attacks_enabled(true)
	(oni.brain as DuelistBrain).force_attack("vertical")
	await _frames(8)
	if oni.sword:
		oni.sword.attacking = true
	await _frames(34)
	await _shot("oni_boss_windup")

	run.queue_free()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
