extends Node
## D21 in VR: the off-hand trigger spends the oldest Torii charge while the sword hand
## holds the katana. The sword-hand trigger does nothing, and a charge waits while an
## element still burns. Driven through the real XRPlayer by XrSim.
##   godot --headless --path . --fixed-fps 90 res://tests/element_charges_xr_test.tscn -- --xr-sim

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0
var run: RunGame
var xr: XRPlayer
var sim: XrSim


func _ready() -> void:
	await _run_all()
	RuntimeGuard.print_summary()
	_check("the runtime guard stayed clean (%d violations)" % RuntimeGuard.violation_count(), RuntimeGuard.violation_count() == 0)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	RuntimeGuard.reset()
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://test_element_charges_xr_save.cfg"
	VrComfortSettings.settings_path = "user://test_element_charges_xr_settings.cfg"
	VrComfortSettings.sandbox_enabled = false
	add_child(run)
	await _frames(12)
	xr = run.player as XRPlayer
	sim = get_tree().get_first_node_in_group("xr_sim") as XrSim
	_check("the XR player runs on simulated tracking", xr != null and sim != null)
	if xr == null or sim == null:
		return
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	# The sim's fist must stay closed or the holder drops the katana.
	sim.set_grip("right", 1.0)
	await _frames(3)
	if xr.right_holder.held != run.katana:
		xr.right_holder.grab(run.katana)
		run.katana.snap_to_hand()
	await _frames(3)
	_check("the sword hand holds the katana and the off-hand is free",
		xr.right_holder.held == run.katana and xr.left_holder.held == null)

	run.element_system.add_charge(Elements.SAKURA)
	run.element_system.add_charge(Elements.STORM)

	# The sword hand's trigger is not a charge button.
	await _pull("right")
	_check("the sword-hand trigger does not spend a charge", run.element_system.charges.size() == 2
		and run.element_system.current_element == Elements.NONE)

	# The off-hand trigger spends the oldest charge.
	await _pull("left")
	_check("the off-hand trigger spends the oldest charge (Sakura on the blade)",
		run.element_system.current_element == Elements.SAKURA and run.element_system.charges == [Elements.STORM])

	# While Sakura burns, another pull is refused.
	await _pull("left")
	_check("a pull while Sakura burns keeps the Storm charge waiting",
		run.element_system.current_element == Elements.SAKURA and run.element_system.charges == [Elements.STORM])

	# Once the element burns out, the waiting charge can be spent.
	run.element_system.element_time_remaining = 0.01
	await _frames(3)
	_check("Sakura burns out to plain steel", run.element_system.current_element == Elements.NONE)
	await _pull("left")
	_check("after burn-out the off-hand trigger spends the Storm charge",
		run.element_system.current_element == Elements.STORM and run.element_system.charges.is_empty())

	run.queue_free()
	await _frames(3)


## One press and release of a trigger on the sim; the edge is read on the press frame.
func _pull(side: String) -> void:
	sim.set_trigger(side, 1.0)
	await _frames(3)
	sim.set_trigger(side, 0.0)
	await _frames(3)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
