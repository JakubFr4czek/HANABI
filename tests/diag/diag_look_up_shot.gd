extends Node
## Screenshots looking up into the canopy from a few spots (non-headless):
##   godot --path . res://tests/diag/diag_look_up_shot.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(20)
	var shots := [[Vector3(0, 0, 2), 0.0, 55.0], [Vector3(0, 0, 0), 2.0, 75.0], [Vector3(3, 0, -4), 4.0, 40.0], [Vector3(-5, 0, 2), 1.0, 30.0]]
	for k in shots.size():
		var s: Array = shots[k]
		player.teleport(s[0], s[1])
		player.camera.rotation.x = deg_to_rad(s[2])
		await _frames(30)
		await _shot("look_up_%d" % k)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)
