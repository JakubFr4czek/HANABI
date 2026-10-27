extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_point8_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	ProjectSettings.set_setting("hanabi/debug/quest_perf_hud", true)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	QuestPerfOverlay.attach_if_needed(run)
	run.wave_director.stop_director()
	var player := run.player as DesktopPlayer
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	SoulOrb.spawn_cluster(run._souls_root, Vector3(0.2, 1.0, -0.5), 8, 6, Elements.STORM)
	await _frames(30)
	await _shot("souls_and_perf_hud")
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
