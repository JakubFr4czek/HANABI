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
	await _frames(560)
	_check("intro parks on the offering instead of starting the run",
		run.state == RunGame.RunState.INTRO and run.wave_director.wave == 0)
	_check("the katana hangs visible and unheld before the player",
		run.katana.visible and not run.katana.is_held())
	var spawn: Node3D = run.spawn
	var gap: float = run.katana.global_position.distance_to(spawn.global_position)
	_check("the offering floats within reach of the spawn (gap %.2f m)" % gap,
		gap > 0.2 and gap < 1.6)

	# Desktop E-grab stands in for the XR grip: taking starts the run.
	var dp := run.player as DesktopPlayer
	dp.take_weapon(run.katana)
	await _frames(30)
	_check("taking the katana starts the run",
		run.katana.is_held() and run.state == RunGame.RunState.PLAYING)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
