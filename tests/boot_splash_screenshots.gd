extends Node
## Boot splash screenshots (windowed, not headless): the HANABI film at its
## burst, the NANJO film, the D18 title plate and the handover into the intro, on the desktop rig.
## With `--vr` it frames the fixed VR panel in a headset-sized view instead (about
## 107 degrees across, as the desktop camera at 16:9). Run with
## `-- --desktop --shots <dir>` or `-- --vr --shots <dir>`.

const MAIN_SCENE := preload("res://scenes/main.tscn")
## Film times the frames are taken at: the firework at its burst, the HANABI
## wordmark once it is set under the fading firework, and the NANJO logo unveiled.
const HANABI_BURST := 1.63
const HANABI_WORDMARK := 2.6
const NANJO_HOLD := 2.4

var out_dir := "/tmp/hanabi_d7_fix1"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	if args.has("--vr"):
		await _vr_framing()
	else:
		await _desktop()
	get_tree().quit(0)


func _desktop() -> void:
	var run: RunGame = MAIN_SCENE.instantiate()
	add_child(run)
	await _frames(3)
	var splash := run.run_splash
	await _until(splash, "hanabi", HANABI_BURST)
	await _shot("desktop_hanabi_burst")
	await _until(splash, "hanabi", HANABI_WORDMARK)
	await _shot("desktop_hanabi_wordmark")
	await _until(splash, "nanjo", NANJO_HOLD)
	await _shot("desktop_nanjo_hold")
	await _title_at(splash, 4.0)
	await _shot("desktop_title_plate")
	while splash.is_active():
		await get_tree().process_frame
	await _frames(12)
	await _shot("desktop_handover_veil")
	await _frames(60)
	await _shot("desktop_intro_after_splash")
	run.queue_free()


## The VR panel as a headset sees it: a camera with a 75 degree vertical field
## (about 107 across at 16:9) and the splash on a plain rig, so the board takes the
## fixed VR size.
func _vr_framing() -> void:
	var rig := Node3D.new()
	add_child(rig)
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.current = true
	rig.add_child(cam)
	var splash := RunSplash.new()
	add_child(splash)
	splash.setup(Node3D.new())
	await _frames(2)
	splash.start()
	await _until(splash, "hanabi", HANABI_BURST)
	await _shot("vr_hanabi_burst")
	await _until(splash, "hanabi", HANABI_WORDMARK)
	await _shot("vr_hanabi_wordmark")
	await _until(splash, "nanjo", NANJO_HOLD)
	await _shot("vr_nanjo_hold")


## Steps frames until the title plate (D18) has run [param seconds] (capped).
func _title_at(splash: RunSplash, seconds: float) -> void:
	for _i in 2000:
		if splash.current_board() == "title" and splash._phase_t >= seconds:
			return
		await get_tree().process_frame


## Steps frames until [param film] has played [param seconds] of its clip (capped).
func _until(splash: RunSplash, film: String, seconds: float) -> void:
	for _i in 2000:
		if splash.current_board() == film and splash.clip_position() >= seconds:
			return
		await get_tree().process_frame


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
