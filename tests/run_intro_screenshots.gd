extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_intro_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = false
	add_child(run)
	var player := run.player as DesktopPlayer
	player.camera.rotation.x = deg_to_rad(-10.0)
	await _frames(95)
	await _shot("intro_hover_petals")
	await _frames(210)
	await _shot("intro_touchdown_ripple")
	run.queue_free()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
