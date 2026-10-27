extends Node
## The run starts when the katana is taken, not when the descent ends: after
## the intro the blade hangs in the air before the player and the wave
## director stays quiet until a hand grabs it. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/intro_grab_test.tscn -- --desktop
## Exit code 0 when everything passed.

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	add_child(run)
	# No skip: ride the whole descent, ripple and materialize (~4.5 s real).
	# Watch the parked katana: it must never drop to the ground and rise again.
	var intro := run.run_intro
	var min_katana_y := INF
	var max_steps_lit := 0
	var steps_by_touchdown := -1
	for i in 560:
		await get_tree().physics_frame
		min_katana_y = minf(min_katana_y, run.katana.global_position.y)
		var lit := 0
		for st in intro._air_steps:
			lit += 1 if st.visible else 0
		max_steps_lit = maxi(max_steps_lit, lit)
		if steps_by_touchdown < 0 and intro._descent_done:
			steps_by_touchdown = intro._steps_taken
	var ground := run.spawn.global_position.y
	_check("the katana waits at the offering instead of falling (lowest %.2f m over ground)" % (min_katana_y - ground),
		min_katana_y - ground > 0.9)
	_check("the descent leaves glowing steps in the air (%d steps, up to %d lit at once)" % [steps_by_touchdown, max_steps_lit],
		steps_by_touchdown == RunIntro.AIR_STEPS and max_steps_lit >= 1)
	var petals_left := intro._petals.filter(func(p): return p.visible).size()
	_check("the petal swirl is gone once the katana is offered (%d left)" % petals_left, petals_left == 0)
	_check("the offered katana glows softly (glow %.2f)" % intro._glow, intro._glow > 0.4)
	_check("intro parks on the offering instead of starting the run",
		run.state == RunGame.RunState.INTRO and run.wave_director.wave == 0)
	_check("the katana hangs visible and unheld before the player",
		run.katana.visible and not run.katana.is_held())
	var spawn: Node3D = run.spawn
	var gap: float = run.katana.global_position.distance_to(spawn.global_position)
	_check("the offering floats within reach of the spawn (gap %.2f m)" % gap,
		gap > 0.2 and gap < 1.6)

	# Movement is already back before the grab: the player is not frozen in
	# place while the run waits for the katana to be taken.
	var dp0 := run.player as DesktopPlayer
	_check("the player can move before taking the katana", not dp0.movement_locked)
	var before := dp0.global_position
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(45)
	var ev_up := InputEventKey.new()
	ev_up.physical_keycode = KEY_W
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	_check("walking works before the grab (moved %.2f m)" % dp0.global_position.distance_to(before),
		dp0.global_position.distance_to(before) > 0.4)

	# Desktop E-grab stands in for the XR grip: taking starts the run.
	var dp := run.player as DesktopPlayer
	dp.take_weapon(run.katana)
	await _frames(30)
	_check("taking the katana starts the run",
		run.katana.is_held() and run.state == RunGame.RunState.PLAYING)
	await _frames(90)
	_check("the glow fades out once the katana is taken (glow %.2f)" % intro._glow, intro._glow < 0.02)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
