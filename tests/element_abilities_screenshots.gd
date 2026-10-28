extends Node
## Headless-window screenshots of all 8 E2b abilities for visual review.
## Run (needs a display, NOT --headless):
##   Godot --path . res://tests/element_abilities_screenshots.tscn -- --shots /tmp/hanabi_ability_shots

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_ability_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	run.state = RunGame.RunState.PLAYING
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-16.0)
	var dummy := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -1.6), player.global_position)
	await _frames(6)

	var shots: Array = [
		[Elements.SAKURA, 1, "sakura1_senbonzakura"],
		[Elements.SAKURA, 2, "sakura2_hanamai"],
		[Elements.STORM, 1, "storm1_raikiri"],
		[Elements.STORM, 2, "storm2_shiden"],
		[Elements.INK, 1, "ink1_sumi_gaeshi"],
		[Elements.INK, 2, "ink2_kage_nawa"],
		[Elements.SHADOW, 1, "shadow1_kagemusha"],
		[Elements.SHADOW, 2, "shadow2_yami_watari"],
	]
	for entry in shots:
		if dummy == null or not is_instance_valid(dummy) or dummy.is_dead:
			dummy = run.wave_director.spawn_enemy_at(player.global_position + Vector3(0.0, 0.0, -1.6), player.global_position)
		run.element_system.imbue(String(entry[0]), 20.0)
		run.element_system.ability_1_cooldown = 0.0
		run.element_system.ability_2_cooldown = 0.0
		if int(entry[1]) == 1:
			run.element_system.execute_ability_1(Vector3.BACK)
		else:
			run.element_system.execute_ability_2(Vector3.BACK)
		await _frames(2)
		# Self-centred effects (orbit barrier, decoy) sit at the player's feet:
		# step back so they enter the frame instead of hiding under the camera.
		if String(entry[2]) in ["sakura2_hanamai", "shadow1_kagemusha"]:
			player.teleport(player.global_position + Vector3(0.0, 0.0, 2.6), 0.0)
			await _frames(2)
		await _shot(String(entry[2]))
		await _frames(10)
	run.queue_free()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)
