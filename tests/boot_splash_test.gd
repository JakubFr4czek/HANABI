extends Node
## Boot splash (D7) on the desktop rig: the launch scene plays the HANABI film,
## a black gap, the NANJO film, then the intro, each exactly once. Time advances
## by frame deltas (run with --fixed-fps 90), so nothing waits in real time.

const MAIN_SCENE := preload("res://scenes/main.tscn")

var failures := 0
var _gap_seen := false
var _time_scale_held := true


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = MAIN_SCENE.instantiate()
	add_child(run)
	await _frames(2)
	var splash := run.run_splash
	var cam := run.player.camera as Camera3D
	_check("Launch scene starts the boot splash and holds the intro back",
		splash.is_active() and not run.run_intro.is_active() and run.state == RunGame.RunState.INTRO)
	_check("Board stands 3.5 m ahead at eye height, world-locked and facing the player",
		_boards_placed(splash, cam))
	_check("World is hidden while the boards play (splash layer only, black environment)",
		cam.cull_mask == RunSplash.SPLASH_LAYER and cam.environment != null)
	var clip_before := splash.clip_position()
	await _frames(45)
	_check("The film plays in stepped time: 45 frames at 90 fps is 0.5 s of film",
		absf(splash.clip_position() - clip_before - 0.5) < 0.03)

	_key(KEY_R, true)
	_key(KEY_R, false)
	_check("R during the splash does not start a run or the intro", splash.is_active() and not run.run_intro.is_active())

	# The first film has already played for clip_position() seconds.
	var expected := splash.total_seconds() - splash.clip_position()
	var elapsed := await _run_until_idle(splash, 1200)
	var boards: Array = []
	for ev in GameEvents.recent(20, "boot_splash_board"):
		boards.append(ev["board"])
	_check("Films play HANABI then NANJO, once each", boards == ["hanabi", "nanjo"])
	_check("The black gap between the films is seen on screen", _gap_seen)
	_check("The rest of the splash runs the films and the gap, %.2f s (expected %.2f s)" % [elapsed, expected],
		absf(elapsed - expected) < 0.2)
	_check("Splash never touches Engine.time_scale", _time_scale_held and Engine.time_scale == 1.0)
	_check("Intro starts exactly once, right after the splash", run.run_intro.is_active()
		and GameEvents.recent(20, "run_intro_started").size() == 1)
	_check("World and camera are restored after the splash", cam.cull_mask != RunSplash.SPLASH_LAYER
		and cam.environment == null)
	run.queue_free()
	await _frames(2)

	# A press that ends the splash must not also skip the intro.
	run = MAIN_SCENE.instantiate()
	add_child(run)
	await _frames(2)
	splash = run.run_splash
	await _frames(90)
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	_check("A press skips the splash with a short fade, intro not started yet",
		splash.is_active() and not run.run_intro.is_active())
	await _run_until_idle(splash, 120)
	_check("Skipped splash hands over to the intro once", GameEvents.recent(20, "run_intro_started").size() == 1)
	await _frames(30)
	_check("The skip press does not carry into the intro", run.run_intro.is_active())
	run.queue_free()
	await _frames(2)


## Steps frames until the splash ends; returns the stepped seconds (capped).
## Also notes whether the black gap showed and whether time scale was ever touched.
func _run_until_idle(splash: RunSplash, max_frames: int) -> float:
	var elapsed := 0.0
	for _i in max_frames:
		if not splash.is_active():
			break
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		_gap_seen = _gap_seen or splash.current_board() == "gap"
		_time_scale_held = _time_scale_held and Engine.time_scale == 1.0
	return elapsed


func _boards_placed(splash: RunSplash, cam: Camera3D) -> bool:
	var anchor := splash.global_position
	var eye := cam.global_position
	var flat := Vector3(anchor.x - eye.x, 0.0, anchor.z - eye.z)
	var distance_ok := absf(flat.length() - RunSplash.BOARD_DISTANCE) <= 0.1
	var height_ok := absf(anchor.y - eye.y) <= 0.2
	var locked := splash.get_parent() != cam and not cam.is_ancestor_of(splash)
	var facing := splash.global_basis.z.dot(-flat.normalized()) > 0.99
	return distance_ok and height_ok and locked and facing


func _key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	get_viewport().push_input(ev)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
