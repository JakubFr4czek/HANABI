extends Node
## Memorial stele with BUILD line at run end (point 13).

const RUN_SCENE := preload("res://scenes/run.tscn")

var out_dir := "/tmp/hanabi_point13_stele"


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
	run.element_system.imbue(Elements.STORM)
	run.kills = 12
	run.level = 4
	run.run_time = 98.0
	run.calorie_meter.kcal = 54.0
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-5.0)
	player.health.take_hit(999.0, Vector3.ZERO, {"attacker": "Yokai"})
	await _frames(36)
	await _shot("memorial_stele_build")

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
		push_warning("point13: no viewport texture (run without --headless)")
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
