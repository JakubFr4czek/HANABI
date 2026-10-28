extends Node
## Boot splash (D7) on the XR rig, driven through XrSim (run with --xr-sim):
## a trigger or A/X press skips the splash without skipping the intro, and A/X
## skips the intro itself once it runs.

const MAIN_SCENE := preload("res://scenes/main.tscn")

var failures := 0
var _sim: XrSim


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	# One run per process: a second XR rig in the same process crashes OpenXR's re-init.
	var run: RunGame = MAIN_SCENE.instantiate()
	add_child(run)
	await _frames(3)
	var xr := run.player as XRPlayer
	_sim = get_tree().get_first_node_in_group("xr_sim") as XrSim
	var splash := run.run_splash
	var cam := xr.get_node("XROrigin3D/XRCamera3D") as Camera3D
	_check("XR launch shows the boot splash, intro waits", xr != null and splash.is_active()
		and not run.run_intro.is_active())
	_check("XR boards stand ~3 m ahead at eye height, world-locked", _boards_placed(splash, cam))

	await _frames(40)
	_sim.set_button("left", "ax_button", true)
	await _frames(1)
	_sim.set_button("left", "ax_button", false)
	_check("A/X starts the splash fade, intro not started by that press",
		splash.is_active() and not run.run_intro.is_active())
	await _run_until_idle(splash, 120)
	await _frames(30)
	_check("A/X skip hands over to the intro once and does not skip it",
		run.run_intro.is_active() and GameEvents.recent(20, "run_intro_started").size() == 1)

	await _frames(20)
	_sim.set_button("right", "ax_button", true)
	await _frames(2)
	_sim.set_button("right", "ax_button", false)
	await _frames(20)
	_check("A/X during the intro skips it into the run",
		run.state == RunGame.RunState.PLAYING and not run.run_intro.is_active())
	run.queue_free()
	await _frames(2)


## Steps frames until the splash ends (capped).
func _run_until_idle(splash: RunSplash, max_frames: int) -> void:
	for _i in max_frames:
		if not splash.is_active():
			return
		await get_tree().process_frame


func _boards_placed(splash: RunSplash, cam: Camera3D) -> bool:
	var anchor := splash.global_position
	var eye := cam.global_position
	var flat := Vector3(anchor.x - eye.x, 0.0, anchor.z - eye.z)
	var distance_ok := absf(flat.length() - 3.0) <= 0.1
	var height_ok := absf(anchor.y - eye.y) <= 0.2
	var locked := splash.get_parent() != cam and not cam.is_ancestor_of(splash)
	var facing := splash.global_basis.z.dot(-flat.normalized()) > 0.99
	return distance_ok and height_ok and locked and facing


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
