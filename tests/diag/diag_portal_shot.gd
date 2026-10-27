extends Node
## Intro gate look (non-headless): the katana being drawn out of the portal.

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_intro_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var run: RunGame = RUN_SCENE.instantiate()
	add_child(run)
	var player := run.player as DesktopPlayer
	await _frames(2)
	var intro := run.run_intro
	await _until(func(): return intro._descent_done)
	player.camera.rotation.x = deg_to_rad(-14.0)
	var marks := [RunIntro.PORTAL_OPEN_SEC + 0.35, RunIntro.PORTAL_OPEN_SEC + 1.4, RunIntro.PORTAL_OPEN_SEC + 2.5]
	for k in marks.size():
		await _until(func(): return intro._portal_t >= marks[k])
		await _shot("portal_%d" % k)
	await _until(func(): return intro._waiting_grab)
	await _frames(20)
	await _shot("portal_3")
	get_tree().quit(0)


func _until(cond: Callable) -> void:
	for i in 1200:
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
