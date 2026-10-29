extends Node
## Boot splash (D7) as it is drawn, windowed (not headless): it reads the pixels
## the frame shows. Desktop: the HANABI film fills the window, goes black in the
## gap, and the NANJO film is centred on it. VR framing: a fixed panel about
## 3.5 m ahead sits in the middle of a headset-sized view, the rest is black.
## Time advances by frame deltas (run with --fixed-fps 90).
##   godot --path . --fixed-fps 90 res://tests/boot_splash_visual_test.tscn -- --desktop

const MAIN_SCENE := preload("res://scenes/main.tscn")
## Pixel sampling: every STEP-th pixel, to keep the scan cheap.
const STEP := 4
## A pixel counts as lit above this luminance.
const LIT := 0.5
## Film times (seconds into the clip) the frames are read at: the firework at its
## peak, and the NANJO logo fully unveiled.
const HANABI_PEAK := 1.63
const HANABI_WORDMARK := 2.6
const NANJO_HOLD := 2.4
## Under the firework, where the HANABI wordmark is set (about 0.72 of the frame height).
const WORDMARK := Rect2(0.3, 0.7, 0.4, 0.12)
const CENTRE := Rect2(0.3, 0.2, 0.4, 0.6)
const FULL := Rect2(0.0, 0.0, 1.0, 1.0)
## The outer strips of the frame, clear of the film's content.
const EDGE_LEFT := Rect2(0.0, 0.0, 0.12, 1.0)
const EDGE_RIGHT := Rect2(0.88, 0.0, 0.12, 1.0)
const DEBUG_DIR := "/tmp/hanabi_d7_fix1"

var failures := 0


func _ready() -> void:
	# Project rule: no window in the suite. Reading the framebuffer headless never
	# returns a frame, so this check is reported as SKIP instead of hanging the run.
	if DisplayServer.get_name() == "headless":
		print("SKIP  boot splash pixel checks need a window (run windowed by hand, see docs/QUEST_TEST.md)")
		get_tree().quit(0)
		return
	DirAccess.make_dir_recursive_absolute(DEBUG_DIR)
	await _run_desktop()
	await _run_vr_framing()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_desktop() -> void:
	var run: RunGame = MAIN_SCENE.instantiate()
	add_child(run)
	await _frames(2)
	var splash := run.run_splash
	_check("Desktop: the launch scene shows the film splash", splash.is_active())

	await _until_film("hanabi", HANABI_PEAK, splash)
	var img := await _frame()
	_save(img, "desktop_hanabi_peak")
	var centre := _sample(img, CENTRE)
	var edges := _sample(img, EDGE_LEFT)
	var right := _sample(img, EDGE_RIGHT)
	_check("Desktop HANABI: the firework is lit in the centre of the window (mean %.3f)" % centre.mean,
		centre.mean > 0.03 and centre.bright > 0.01)
	_check("Desktop HANABI: the sides of the window stay black (left %.3f, right %.3f)" % [edges.mean, right.mean],
		edges.mean < 0.02 and right.mean < 0.02)
	await _until_film("hanabi", HANABI_WORDMARK, splash)
	img = await _frame()
	_save(img, "desktop_hanabi_wordmark")
	var wordmark := _sample(img, WORDMARK)
	_check("Desktop HANABI: the wordmark is lit under the firework (%.2f%% of pixels)" % (wordmark.bright * 100.0),
		wordmark.bright > 0.002)

	await _until_board(splash, "gap")
	img = await _frame()
	_save(img, "desktop_gap")
	var gap := _sample(img, FULL)
	_check("Desktop gap: the screen is black (mean %.4f)" % gap.mean, gap.mean < 0.01)

	await _until_film("nanjo", NANJO_HOLD, splash)
	img = await _frame()
	_save(img, "desktop_nanjo_hold")
	var logo := _sample(img, FULL)
	_check("Desktop NANJO: the logo is lit (%.2f%% of pixels)" % (logo.bright * 100.0), logo.bright > 0.002)
	_check("Desktop NANJO: the logo sits in the middle of the frame (centre x %.3f)" % logo.centre_x,
		absf(logo.centre_x - 0.5) < 0.05)

	run.queue_free()
	await _frames(2)


## A headset-sized view (about 107 degrees across at 16:9): the fixed VR panel
## should sit in the middle, with black void on both sides.
func _run_vr_framing() -> void:
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

	await _until_film("hanabi", HANABI_PEAK, splash)
	var img := await _frame()
	_save(img, "vr_hanabi_peak")
	var panel := _sample(img, FULL)
	_check("VR framing: the firework is centred in the view (centre x %.3f)" % panel.centre_x,
		absf(panel.centre_x - 0.5) < 0.05)
	var sides := _sample(img, EDGE_LEFT)
	var other_side := _sample(img, EDGE_RIGHT)
	_check("VR framing: the panel leaves black void on both sides (left %.3f, right %.3f)" % [sides.mean, other_side.mean],
		sides.mean < 0.01 and other_side.mean < 0.01)

	await _until_film("nanjo", NANJO_HOLD, splash)
	img = await _frame()
	_save(img, "vr_nanjo_hold")
	var logo := _sample(img, FULL)
	_check("VR framing NANJO: the logo sits in the middle of the view (%.3f to %.3f)" % [logo.x_min, logo.x_max],
		logo.x_min > 0.3 and logo.x_max < 0.7 and logo.x_max - logo.x_min > 0.15)

	await _until_idle(splash)
	rig.queue_free()
	splash.queue_free()
	await _frames(2)


## Steps frames until [param film] has played [param seconds] of its clip.
func _until_film(film: String, seconds: float, splash: RunSplash) -> void:
	for _i in 2000:
		if splash.current_board() == film and splash.clip_position() >= seconds:
			return
		await get_tree().process_frame


func _until_board(splash: RunSplash, board: String) -> void:
	for _i in 2000:
		if splash.current_board() == board:
			return
		await get_tree().process_frame


func _until_idle(splash: RunSplash) -> void:
	for _i in 2000:
		if not splash.is_active():
			return
		await get_tree().process_frame


## The frame as drawn this step.
func _frame() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Scans the pixels inside [param box] (normalised, 0..1) on a STEP grid.
func _sample(img: Image, box: Rect2) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var lum_sum := 0.0
	var count := 0
	var lit := 0
	var x_sum := 0.0
	var x_min := 1.0
	var x_max := 0.0
	for y in range(int(box.position.y * h), int(box.end.y * h), STEP):
		for x in range(int(box.position.x * w), int(box.end.x * w), STEP):
			var luminance := img.get_pixel(x, y).get_luminance()
			lum_sum += luminance
			count += 1
			if luminance > LIT:
				var nx := float(x) / w
				lit += 1
				x_sum += nx
				x_min = minf(x_min, nx)
				x_max = maxf(x_max, nx)
	return {
		"mean": lum_sum / maxi(count, 1),
		"bright": float(lit) / maxi(count, 1),
		"centre_x": x_sum / maxi(lit, 1),
		"x_min": x_min,
		"x_max": x_max,
	}


func _save(img: Image, label: String) -> void:
	img.save_png(DEBUG_DIR.path_join(label + ".png"))


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
