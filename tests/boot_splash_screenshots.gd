extends Node
## Boot splash screenshots (windowed, not headless): the HANABI board, the
## NANJO board, and the handover into the intro. Run with
## `-- --desktop --shots <dir>`.

const MAIN_SCENE := preload("res://scenes/main.tscn")

var out_dir := "/tmp/hanabi_d7"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var run: RunGame = MAIN_SCENE.instantiate()
	add_child(run)
	await _frames(3)
	var splash := run.run_splash
	var elapsed := await _advance(2.0, 0.0)
	await _shot("hanabi_hold")
	elapsed = await _advance(5.0, elapsed)
	await _shot("nanjo_hold")
	while splash.is_active():
		await get_tree().process_frame
	await _frames(12)
	await _shot("handover_veil")
	await _frames(60)
	await _shot("intro_after_splash")
	run.queue_free()
	get_tree().quit(0)


## Steps frames until [param target] seconds of splash time have passed.
func _advance(target: float, elapsed: float) -> float:
	while elapsed < target:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return elapsed


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
