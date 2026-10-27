extends Node
## Petal death look (non-headless): a yokai killed before the camera, shots as
## it bursts and as the petals drift off.

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	run.xp_to_next = 999999
	var player := run.player as DesktopPlayer
	player.teleport(Vector3(0, 0, 0), 0.0)
	player.camera.rotation.x = deg_to_rad(-8.0)
	var at := Vector3(-0.6, 0.0, -2.6)
	at.y = float(run.wave_director.ground_height.call(at.x, at.z))
	var y := run.wave_director.spawn_enemy_at(at, Vector3.ZERO)
	await _frames(40)
	y.die({})
	for i in 150:
		await get_tree().physics_frame
		if not y.visible:
			break
	await _frames(6)
	await _shot("petals_0")
	await _frames(60)
	await _shot("petals_1")
	await _frames(90)
	await _shot("petals_2")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)
