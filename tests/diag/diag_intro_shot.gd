extends Node
## Intro look (non-headless): an air step mid-descent, then the glowing offering.

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_intro_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var run: RunGame = RUN_SCENE.instantiate()
	add_child(run)
	var player := run.player as DesktopPlayer
	await _frames(2)
	player.camera.rotation.x = deg_to_rad(-62.0)
	await _until(func(): return run.run_intro._steps_taken >= 3)
	await _frames(8)
	await _shot("air_step")
	await _until(func(): return run.run_intro._waiting_grab)
	player.camera.rotation.x = deg_to_rad(-18.0)
	await _frames(40)
	await _shot("offering_glow")
	get_tree().quit(0)


func _until(cond: Callable) -> void:
	for i in 900:
		if cond.call():
			return
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)
