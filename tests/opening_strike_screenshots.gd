extends Node
## D11 screenshots from the game itself: the run scene's opening strike, as the
## desktop player sees it (the board fills the window). Frames: the approach to the
## first cut, the first cut's contact, the third, the finisher's contact, the flash
## building, the white. Needs a display, NOT --headless:
##   godot --path . --fixed-fps 90 res://tests/opening_strike_screenshots.tscn -- --desktop --shots docs/d11
## A movie of the same cinematic (Movie Maker, 60 fps):
##   godot --path . --fixed-fps 60 --write-movie build/cinematic/opening_strike.avi res://tests/opening_strike_screenshots.tscn -- --desktop --movie

const RUN_SCENE := preload("res://scenes/run.tscn")

## Clock times to capture (s) and the file names they are saved under.
const SHOTS := [
	[0.30, "d11_1_approach"],
	[0.46, "d11_2_cut1_sakura_split"],
	[1.32, "d11_3_cut3_ink_split"],
	[2.66, "d11_4_finisher_hanadachi"],
	[2.92, "d11_5_flash_builds"],
	[3.28, "d11_6_white"],
]

var out_dir := "/tmp/hanabi_d11"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(150)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var cin := run.run_cinematic
	cin.start()
	# --movie: the cinematic alone, for Movie Maker (--write-movie); quits when it ends.
	if args_has_movie():
		await cin.finished
		get_tree().quit(0)
		return
	var next := 0
	while cin.is_active() and next < SHOTS.size():
		await get_tree().process_frame
		if cin.elapsed() >= float(SHOTS[next][0]):
			await _shot(String(SHOTS[next][1]))
			next += 1
	await _frames(4)
	run.queue_free()
	get_tree().quit(0)


func args_has_movie() -> bool:
	return "--movie" in OS.get_cmdline_user_args()


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)
