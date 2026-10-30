extends Node
## D21: elemental charges from Torii gates. A crossing stores the gate's element
## (MAX_CHARGES = 3, FIFO); the player spends the oldest one to saturate the katana,
## only while the blade is plain steel. Also checks the desktop L key and the run wiring.
##   godot --headless --path . --fixed-fps 90 res://tests/element_charges_test.tscn -- --desktop

const TORII_SCENE := preload("res://scenes/world/torii_gate.tscn")
const KATANA_SCENE := preload("res://scenes/weapons/katana.tscn")
const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_element_charges_high_score.cfg"

var failures := 0
var elem_sys: ElementSystem
var katana: HeldWeapon
var player_body: StaticBody3D


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	katana = KATANA_SCENE.instantiate()
	add_child(katana)

	elem_sys = ElementSystem.new()
	elem_sys.name = "ElementSystem"
	add_child(elem_sys)
	elem_sys.setup(null, katana)

	player_body = StaticBody3D.new()
	player_body.name = "PlayerBody"
	player_body.collision_layer = ToriiGate.PLAYER_BODY_LAYER
	player_body.add_to_group("player_body")
	player_body.position = Vector3(500.0, 0.0, 500.0)  # far from every gate: only the crossings below count
	add_child(player_body)
	await _frames(2)

	# 1. One gate crossing stores one charge (the blade is still plain steel).
	var gate_a := await _make_gate(Elements.SAKURA, Vector3(0.0, 0.0, 0.0))
	_cross(gate_a)
	await _frames(2)
	_check("1. Passing a Torii gate adds a charge (charges.size() == 1)",
		elem_sys.charges.size() == 1 and elem_sys.charges[0] == Elements.SAKURA)
	_check("1b. The crossing does not imbue the katana yet", katana.element == Elements.NONE and elem_sys.current_element == Elements.NONE)

	# 2. Three gates fill the buffer, oldest first.
	var gate_b := await _make_gate(Elements.STORM, Vector3(10.0, 0.0, 0.0))
	_cross(gate_b)
	var gate_c := await _make_gate(Elements.INK, Vector3(20.0, 0.0, 0.0))
	_cross(gate_c)
	await _frames(2)
	_check("2. Three crossings fill the buffer (charges.size() == 3)", elem_sys.charges.size() == 3)
	_check("2b. The buffer keeps crossing order: Sakura, Storm, Ink",
		elem_sys.get_charges() == [Elements.SAKURA, Elements.STORM, Elements.INK])

	# 3. A fourth gate is refused: the buffer stays at its limit.
	var gate_d := await _make_gate(Elements.SHADOW, Vector3(30.0, 0.0, 0.0))
	_cross(gate_d)
	await _frames(2)
	_check("3. A fourth crossing does not exceed MAX_CHARGES (charges.size() == 3)", elem_sys.charges.size() == ElementSystem.MAX_CHARGES)
	_check("3b. add_charge refuses a fourth charge", elem_sys.add_charge(Elements.SHADOW) == false)
	_check("3c. The refused charge is not kept", elem_sys.charges.size() == 3 and not elem_sys.charges.has(Elements.SHADOW))

	# 4. Activation spends the oldest charge (FIFO) and saturates the katana.
	var activated := elem_sys.activate_charge()
	_check("4. Activation succeeds on plain steel", activated)
	_check("4b. The oldest charge (Sakura) is the one that imbues the katana",
		elem_sys.current_element == Elements.SAKURA and katana.element == Elements.SAKURA)
	_check("4c. Activation spends one charge (charges.size() == 2, Storm and Ink remain)",
		elem_sys.charges.size() == 2 and elem_sys.charges == [Elements.STORM, Elements.INK])

	# 5. While Sakura still burns, the next charge is refused and the buffer is untouched.
	_check("5. can_activate_charge is false while an element is active", elem_sys.can_activate_charge() == false)
	_check("5b. activate_charge is refused while an element is active", elem_sys.activate_charge() == false)
	_check("5c. The refused activation leaves the buffer untouched",
		elem_sys.charges == [Elements.STORM, Elements.INK] and elem_sys.current_element == Elements.SAKURA)

	# 6. Once the element expires, the next charge can be activated.
	elem_sys.element_time_remaining = 0.01
	elem_sys._physics_process(0.1)
	_check("6. Sakura expires to plain steel", elem_sys.current_element == Elements.NONE and katana.element == Elements.NONE)
	_check("6b. A charge can be activated again on plain steel", elem_sys.can_activate_charge())
	_check("6c. The next charge (Storm) imbues the katana", elem_sys.activate_charge() and katana.element == Elements.STORM)
	_check("6d. One charge (Ink) is still waiting", elem_sys.charges == [Elements.INK])

	# 6e. The buffer is a copy: edits to it do not change the real charges.
	var snapshot := elem_sys.get_charges()
	snapshot.clear()
	_check("6e. get_charges returns a copy", elem_sys.charges.size() == 1)

	# 6f. charges_changed fires on add, spend and reset, with the new buffer.
	var seen: Array = []
	var on_changed := func(list: Array[String]) -> void: seen.append(list.size())
	elem_sys.charges_changed.connect(on_changed)
	elem_sys.add_charge(Elements.SHADOW)
	elem_sys.reset()
	elem_sys.charges_changed.disconnect(on_changed)
	_check("6f. charges_changed reports add (2) and reset (0)", seen == [2, 0])
	_check("6g. reset clears the buffer and the katana", elem_sys.charges.is_empty() and katana.element == Elements.NONE)

	# 7. Run wiring: the player's request spends a charge, desktop L key included.
	await _check_run_wiring()

	katana.queue_free()
	elem_sys.queue_free()
	player_body.queue_free()
	gate_a.queue_free()
	gate_b.queue_free()
	gate_c.queue_free()
	gate_d.queue_free()


func _check_run_wiring() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = TEST_SAVE_PATH
	add_child(run)
	await _frames(12)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(2)

	var desktop := run.player as DesktopPlayer
	_check("7. The run uses the desktop player", desktop != null)
	if desktop == null:
		run.queue_free()
		await _frames(2)
		return
	_check("7a. The desktop player announces charge_activation_requested to the run",
		desktop.charge_activation_requested.is_connected(run._on_charge_activation_requested))
	_check("7b. The run is playing with no element on the blade", run.state == RunGame.RunState.PLAYING and run.element_system.current_element == Elements.NONE)

	run.element_system.add_charge(Elements.SAKURA)
	desktop.charge_activation_requested.emit()
	_check("7c. The request spends the charge and saturates the katana",
		run.element_system.current_element == Elements.SAKURA and run.element_system.charges.is_empty())

	# Sakura burns: the request is refused, the stored Storm charge waits.
	run.element_system.add_charge(Elements.STORM)
	desktop.charge_activation_requested.emit()
	_check("7d. A request while Sakura burns keeps the Storm charge waiting",
		run.element_system.current_element == Elements.SAKURA and run.element_system.charges == [Elements.STORM])

	# The L key is the desktop control for the same request.
	run.element_system.reset()
	run.element_system.add_charge(Elements.INK)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	desktop._unhandled_input(key)
	_check("7e. The L key spends the charge (Ink on the blade)", run.element_system.current_element == Elements.INK)

	run.queue_free()
	await _frames(3)
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _make_gate(element_name: String, pos: Vector3) -> ToriiGate:
	var gate: ToriiGate = TORII_SCENE.instantiate()
	gate.element = element_name
	gate.position = pos
	add_child(gate)
	await _frames(2)
	return gate


## A player crossing: the gate sees the player body pass through its aperture.
func _cross(gate: ToriiGate) -> void:
	gate.trigger_cross(player_body)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
