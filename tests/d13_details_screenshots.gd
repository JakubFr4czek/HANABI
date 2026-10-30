extends Node
## D13 detail screenshots (windowed, not headless): the katana with a fresh ink trace
## on the blade and the tsuka-ito grip, and the end screen after a death.
## Run: godot --path . --fixed-fps 90 res://tests/d13_details_screenshots.tscn -- --desktop --shots <dir>

const RUN_SCENE := preload("res://scenes/run.tscn")

var out_dir := "/tmp/hanabi_d13"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _blade_and_grip()
	await _death_screen()
	get_tree().quit(0)


func _blade_and_grip() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://d13_shots_high_score.cfg"
	add_child(run)
	await _frames(30)
	var katana: HeldWeapon = run.katana
	katana.imbue_element(Elements.STORM)
	katana.mark_trace()
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	# The guard, the grip and the lower blade, from the side the hand would see.
	var k := katana.global_transform
	cam.global_position = k * Vector3(0.36, 0.10, 0.12)
	cam.look_at(k * Vector3(0.0, 0.0, -0.16), Vector3.UP)
	cam.make_current()
	await _frames(20)
	await _shot("1_blade_trace_storm_grip")
	katana.mark_trace()
	katana.trace_left = 1.2
	await _frames(20)
	await _shot("2_blade_trace_fading")
	run.queue_free()
	await _frames(5)
	cam.queue_free()


func _death_screen() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://d13_shots_high_score.cfg"
	add_child(run)
	await _frames(30)
	run.kills = 12
	run.level = 4
	run.run_time = 214.0
	run.wave_director.wave = 6
	run.element_system.imbue(Elements.INK)
	run._on_player_died()
	await _frames(120)
	await _shot("3_death_screen_chiru")
	run.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
