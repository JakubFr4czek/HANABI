extends Node
## D18 title plate after the boot splash (assets/text/INTRO_TEXT.md): the text is read from
## the file, the plate fades in and out within about 9 s, a skip ends it quickly,
## and its start cues the distant firework. Time is stepped by hand.
##   godot --headless --path . --fixed-fps 90 res://tests/intro_title_test.tscn -- --desktop

const STEP := 0.25

var failures := 0


func _ready() -> void:
	_text_and_fade()
	_plays_and_finishes()
	_skip_ends_it_quickly()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _text_and_fade() -> void:
	var lines := RunSplash.title_lines()
	_check("the title is read from assets/text/INTRO_TEXT.md (%d lines)" % lines.size(), lines.size() >= 2 and lines.size() <= 3)
	_check("a missing text file gives no lines", RunSplash.title_lines("res://docs/NO_SUCH_FILE.md").is_empty())
	_check("the plate starts black and is fully lit at 2 s", RunSplash.title_brightness(0.0) == 0.0 and RunSplash.title_brightness(2.0) == 1.0)
	_check("the plate fades out to black at the end (9 s)", absf(RunSplash.title_brightness(RunSplash.TITLE_SEC)) < 1e-6)
	_check("the plate lasts about 9 s", absf(RunSplash.TITLE_SEC - 9.0) < 0.01)


func _plays_and_finishes() -> void:
	var splash := _make_splash()
	var cues := [0]
	var ends := [0]
	splash.title_started.connect(func() -> void: cues[0] += 1)
	splash.finished.connect(func() -> void: ends[0] += 1)
	splash.start()
	splash._enter_phase(RunSplash.Phase.TITLE)
	_check("the title plate cues the firework exactly once", cues[0] == 1)
	_check("the board reports the title plate", splash.current_board() == "title")
	_check("the title label carries the file's lines",
		splash._title_label.text == "\n".join(RunSplash.title_lines()))
	for _i in 4:
		splash._process(STEP)
	_check("one second in, the plate shows its lines", splash._title_label.visible and splash._title_black.visible)
	_check("one second in, the plate is still dim (fade in)", splash._board_mat.albedo_color.r < 0.6)
	for _i in int(RunSplash.TITLE_SEC / STEP) + 2:
		splash._process(STEP)
	_check("after about 9 s the splash hands over to the intro", not splash.is_active() and ends[0] == 1)
	splash.queue_free()


func _skip_ends_it_quickly() -> void:
	var splash := _make_splash()
	var ends := [0]
	splash.finished.connect(func() -> void: ends[0] += 1)
	splash.start()
	splash._enter_phase(RunSplash.Phase.TITLE)
	for _i in 4:
		splash._process(STEP)
	splash.skip()
	for _i in 3:
		splash._process(STEP)
	_check("a skip ends the plate within half a second", not splash.is_active() and ends[0] == 1)
	splash.queue_free()


func _make_splash() -> RunSplash:
	var rig := Node3D.new()
	add_child(rig)
	var splash := RunSplash.new()
	add_child(splash)
	splash.setup(rig)
	return splash


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
