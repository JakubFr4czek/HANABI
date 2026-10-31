extends Node
## XR controller input on the real XRPlayer, without a headset (XrSim fake trackers):
## A/X and B/Y routing with and without a blade in hand, tap vs hold on B and Menu
## (toggle attacks, recenter, eye height saved on release), grip blocking the view
## buttons, the off-hand charge trigger, thumbstick click cycling the blade's element,
## the parry echo on the free hand, and the glove dressing.
##   godot --headless --path . --fixed-fps 90 res://tests/xr_input_test.tscn -- --desktop
## Exit code 0 when everything passed.

const PLAYER_SCENE := preload("res://scenes/player/xr_player.tscn")
const KATANA_SCENE := preload("res://scenes/weapons/katana.tscn")
const KANABO_SCENE := preload("res://scenes/weapons/kanabo.tscn")
const SETTINGS_TEST_FILE := "xr_input_test.cfg"
const SETTINGS_TEST_PATH := "user://" + SETTINGS_TEST_FILE
## Frame counts at the fixed 90 Hz tick: a tap stays well inside TAP_MAX_SEC (0.35 s),
## a hold clears RECENTER_HOLD_SEC (0.6 s), and the Menu hold needs 1.0 s.
const TAP_FRAMES := 8
const HOLD_FRAMES := 80
const MENU_HOLD_FRAMES := 100
const HEAD_HEIGHT := 1.65
## Parked well away from the rig so a grab never picks it up by accident.
const FAR_POINT := Vector3(40.0, 0.0, 40.0)
const HAPTIC_ECHO := 0.45

var failures := 0
var xr: XRPlayer
var sim: XrSim
var katana: HeldWeapon
var kanabo: HeldWeapon
var counts := {}
var logged: Array = []
var last_direction := Vector3.ZERO


func _ready() -> void:
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	var saved_path: String = VrComfortSettings.settings_path
	var saved_haptic: int = VrComfortSettings.haptic_percent
	VrComfortSettings.settings_path = SETTINGS_TEST_PATH
	VrComfortSettings.haptic_percent = 100
	_remove_test_file()

	sim = XrSim.new()
	add_child(sim)
	xr = PLAYER_SCENE.instantiate()
	var start_xr := xr.get_node_or_null("StartXR")
	if start_xr:
		xr.remove_child(start_xr)
		start_xr.free()
	add_child(xr)
	katana = KATANA_SCENE.instantiate() as HeldWeapon
	kanabo = KANABO_SCENE.instantiate() as HeldWeapon
	add_child(katana)
	add_child(kanabo)
	katana.global_position = FAR_POINT
	kanabo.global_position = FAR_POINT + Vector3(1.0, 0.0, 0.0)
	katana.freeze = true
	kanabo.freeze = true
	_connect_signals()
	await _frames(3)

	await _check_ax_with_empty_hands()
	await _check_ax_with_blade()
	await _check_aim_follows_head()
	await _check_b_with_blade()
	await _check_b_tap_and_hold()
	await _check_b_stick_changes_height()
	await _check_grip_blocks_view_buttons()
	await _check_menu_button()
	await _check_charge_activation()
	await _check_thumbstick_cycles_element()
	await _check_run_element_mode()
	await _check_parry_echo()
	_check_gloves()

	VrComfortSettings.settings_path = saved_path
	VrComfortSettings.haptic_percent = saved_haptic
	_remove_test_file()


# --- Sections ----------------------------------------------------------------

## A with nothing in hand is the room reset; holding it fires once, not per frame.
func _check_ax_with_empty_hands() -> void:
	await _release_all()
	_clear()
	await _tap("right", "ax_button")
	_check("A with empty hands resets the room, it fires no ability",
		_count("reset_requested") == 1 and _count("ability_1_requested") == 0)
	await _hold("right", "ax_button", HOLD_FRAMES)
	_check("holding A resets once, not on every frame", _count("reset_requested") == 2)


## With a blade in hand, A is ability 1 and aims along the view (flattened).
func _check_ax_with_blade() -> void:
	await _release_all()
	_clear()
	await _hold_blade("right", katana)
	await _tap("right", "ax_button")
	_check("A with a blade in hand fires ability 1, not a reset",
		_count("ability_1_requested") == 1 and _count("reset_requested") == 0)
	_check("ability 1 aims straight ahead when the head looks ahead", last_direction.is_equal_approx(Vector3.FORWARD))


## The aim is flat: pitching the head does not tilt it, yaw turns it, and looking
## straight up leaves no flat direction, so it falls back to forward.
func _check_aim_follows_head() -> void:
	_clear()
	_set_head(Basis(Vector3.RIGHT, -PI / 4.0))
	await _tap("right", "ax_button")
	_check("looking 45 degrees down still aims flat, not into the floor",
		last_direction.is_equal_approx(Vector3.FORWARD) and is_zero_approx(last_direction.y))

	_set_head(Basis(Vector3.UP, PI / 2.0))
	await _tap("right", "ax_button")
	_check("turning the head 90 degrees turns the aim with it",
		last_direction.is_equal_approx(Vector3(-1.0, 0.0, 0.0)))

	_set_head(Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.RIGHT, PI / 2.0))
	await _tap("right", "ax_button")
	_check("looking straight up has no flat aim and falls back to forward",
		last_direction.is_equal_approx(Vector3.FORWARD))
	_set_head(Basis.IDENTITY)
	await _frames(2)


## B with a blade in the dominant hand is ability 2; B on the empty hand is the view
## action (tap toggles attacks) even while the other hand holds the blade.
func _check_b_with_blade() -> void:
	_clear()
	await _tap("right", "by_button")
	_check("B with a blade in the right hand fires ability 2, not a view action",
		_count("ability_2_requested") == 1 and _count("toggle_attacks_requested") == 0)
	_check("ability 2 aims the same flat way as ability 1", last_direction.is_equal_approx(Vector3.FORWARD))
	await _tap("left", "by_button")
	_check("B on the empty hand toggles attacks while the other hand holds the blade",
		_count("toggle_attacks_requested") == 1 and _count("ability_2_requested") == 1)


## B alone: a tap toggles attacks; a hold past 0.6 s recenters and does not also toggle.
func _check_b_tap_and_hold() -> void:
	await _release_all()
	_clear()
	await _tap("right", "by_button")
	_check("a short B tap toggles attacks", _count("toggle_attacks_requested") == 1)
	_clear()
	await _hold("right", "by_button", HOLD_FRAMES)
	_check("a long B hold recenters the view", _logged("xr_recenter"))
	_check("a long B hold does not also toggle attacks on release", _count("toggle_attacks_requested") == 0)


## B held with the turn stick up raises the eye height (saved on release); that hold
## never recenters, and the other hand's stick cannot move the height.
func _check_b_stick_changes_height() -> void:
	await _release_all()
	_clear()
	var start := xr.height_offset
	sim.set_stick("right", Vector2(0.0, 1.0))
	await _hold("right", "by_button", HOLD_FRAMES)
	sim.set_stick("right", Vector2.ZERO)
	var gained := xr.height_offset - start
	_check("pushing the turn stick up while B is held raises the eye height (+%.2f m)" % gained,
		gained > 0.15 and gained < 0.35)
	_check("a stick-driven hold does not recenter the view", not _logged("xr_recenter"))
	_check("releasing B saves the eye height to the settings file", _saved_height_matches())

	var before := xr.height_offset
	sim.set_stick("left", Vector2(0.0, 1.0))
	await _hold("left", "by_button", HOLD_FRAMES)
	sim.set_stick("left", Vector2.ZERO)
	_check("only the turn-stick hand moves the eye height", is_equal_approx(xr.height_offset, before))


## Gripping makes B a grab gesture, not a view action: no toggle, no recenter.
func _check_grip_blocks_view_buttons() -> void:
	await _release_all()
	_clear()
	logged.clear()
	sim.set_grip("left", 1.0)
	await _tap("left", "by_button")
	await _hold("left", "by_button", HOLD_FRAMES)
	sim.set_grip("left", 0.0)
	await _frames(2)
	_check("B while gripping does not toggle attacks", _count("toggle_attacks_requested") == 0)
	_check("B while gripping does not recenter the view", not _logged("xr_recenter"))


## Menu: a tap opens the menu; a 1 s hold recenters and does not open the menu.
func _check_menu_button() -> void:
	await _release_all()
	_clear()
	await _tap("left", "menu_button")
	_check("a short Menu tap requests the menu", _count("menu_requested") == 1)
	await _hold("left", "menu_button", MENU_HOLD_FRAMES)
	_check("a long Menu hold recenters the view", _logged("xr_recenter"))
	_check("a long Menu hold does not also open the menu", _count("menu_requested") == 1)


## The off-hand trigger spends a charge only while the other hand alone holds a blade.
func _check_charge_activation() -> void:
	await _release_all()
	_clear()
	await _hold_blade("right", katana)
	await _pull_trigger("left", 0.9)
	_check("the off-hand trigger spends a charge while the other hand holds the blade",
		_count("charge_activation_requested") == 1)
	await _pull_trigger("left", 0.4)
	_check("a light trigger pull (under the threshold) spends nothing",
		_count("charge_activation_requested") == 1)

	_release_hand("right")
	await _frames(2)
	await _hold_blade("left", kanabo)
	await _pull_trigger("right", 0.9)
	_check("the right trigger works the same with the blade in the left hand",
		_count("charge_activation_requested") == 2)

	await _hold_blade("right", katana)
	await _pull_trigger("left", 0.9)
	_check("with blades in both hands the trigger spends nothing",
		_count("charge_activation_requested") == 2)


## Thumbstick click cycles the element of the blade in that hand, one step per click.
func _check_thumbstick_cycles_element() -> void:
	await _release_all()
	_clear()
	await _hold_blade("right", katana)
	var before := katana.element
	await _tap("right", "primary_click")
	_check("clicking the thumbstick cycles the blade's element", katana.element == XRPlayer.next_element(before))
	var middle := katana.element
	await _tap("right", "primary_click")
	_check("the next click moves on to the element after that",
		katana.element == XRPlayer.next_element(middle) and katana.element != middle)


## In a run, A with empty hands fires ability 1 instead of resetting, the thumbstick
## never cycles elements, and B fires ability 2 from the off-hand blade.
func _check_run_element_mode() -> void:
	await _release_all()
	_clear()
	xr.run_element_mode = true
	await _tap("right", "ax_button")
	_check("in a run, A with empty hands fires ability 1 instead of resetting",
		_count("ability_1_requested") == 1 and _count("reset_requested") == 0)

	await _hold_blade("left", kanabo)
	var before := kanabo.element
	_clear()
	await _tap("left", "primary_click")
	_check("in a run, the thumbstick click never changes the blade's element", kanabo.element == before)
	await _tap("right", "by_button")
	_check("in a run, B fires ability 2 from the blade in the other hand", _count("ability_2_requested") == 1)
	xr.run_element_mode = false


## A parry echoes softly into the free hand only; the blade hand gets nothing.
func _check_parry_echo() -> void:
	await _release_all()
	await _hold_blade("right", katana)
	xr.left_holder.last_pulse_amplitude = -1.0
	xr.right_holder.last_pulse_amplitude = -1.0
	GameEvents.parry.emit({})
	await get_tree().create_timer(0.3).timeout
	_check("a parry echoes into the free hand", is_equal_approx(xr.left_holder.last_pulse_amplitude, HAPTIC_ECHO))
	_check("the hand holding the blade gets no parry echo", xr.right_holder.last_pulse_amplitude == -1.0)


func _check_gloves() -> void:
	var gloved := true
	var meshes := 0
	for model in [xr.get_node("XROrigin3D/LeftHand/LeftHandModel"), xr.get_node("XROrigin3D/RightHand/RightHandModel")]:
		for mesh in (model as Node).find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			gloved = gloved and (mesh as MeshInstance3D).material_override == XRPlayer.glove_material()
	_check("both hand models wear the glove material (%d meshes)" % meshes, meshes > 0 and gloved)
	_check("the gloves are the run's dark indigo", XRPlayer.glove_material().albedo_color.is_equal_approx(XRPlayer.GLOVE_ALBEDO))


# --- Helpers -----------------------------------------------------------------

func _connect_signals() -> void:
	xr.reset_requested.connect(_bump.bind("reset_requested"))
	xr.toggle_attacks_requested.connect(_bump.bind("toggle_attacks_requested"))
	xr.ability_1_requested.connect(_on_ability.bind("ability_1_requested"))
	xr.ability_2_requested.connect(_on_ability.bind("ability_2_requested"))
	xr.charge_activation_requested.connect(_bump.bind("charge_activation_requested"))
	xr.menu_requested.connect(_bump.bind("menu_requested"))
	GameEvents.event_logged.connect(_on_event)


func _on_ability(direction: Vector3, signal_name: String) -> void:
	_bump(signal_name)
	last_direction = direction


func _on_event(event: Dictionary) -> void:
	logged.append(event)


func _bump(signal_name: String) -> void:
	counts[signal_name] = _count(signal_name) + 1


func _count(signal_name: String) -> int:
	return counts.get(signal_name, 0)


func _clear() -> void:
	counts.clear()
	logged.clear()


func _logged(event_type: String) -> bool:
	for event in logged:
		if event.get("type") == event_type:
			return true
	return false


func _holder(side: String) -> WeaponHolder:
	return xr.left_holder if side == "left" else xr.right_holder


func _set_head(basis: Basis) -> void:
	sim.set_head(Transform3D(basis, Vector3(0.0, HEAD_HEIGHT, 0.0)))
	await _frames(3)


func _press(side: String, button: String, down: bool) -> void:
	sim.set_button(side, button, down)


func _tap(side: String, button: String) -> void:
	_press(side, button, true)
	await _frames(TAP_FRAMES)
	_press(side, button, false)
	await _frames(2)


func _hold(side: String, button: String, frames: int) -> void:
	_press(side, button, true)
	await _frames(frames)
	_press(side, button, false)
	await _frames(2)


func _pull_trigger(side: String, value: float) -> void:
	sim.set_trigger(side, value)
	await _frames(3)
	sim.set_trigger(side, 0.0)
	await _frames(2)


## Puts [param weapon] into the hand's holder at its grip pose and closes the fist on it.
func _hold_blade(side: String, weapon: HeldWeapon) -> void:
	await _frames(2)
	var holder := _holder(side)
	holder.release()
	weapon.global_transform = holder.global_transform
	holder.grab(weapon)
	sim.set_grip(side, 1.0)
	await _frames(2)


func _release_hand(side: String) -> void:
	sim.set_grip(side, 0.0)
	_holder(side).release()


func _release_all() -> void:
	for side in ["left", "right"]:
		sim.set_grip(side, 0.0)
		sim.set_trigger(side, 0.0)
		sim.set_stick(side, Vector2.ZERO)
		for button in ["ax_button", "by_button", "menu_button", "primary_click"]:
			sim.set_button(side, button, false)
	xr.left_holder.release()
	xr.right_holder.release()
	await _frames(2)


func _saved_height_matches() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_TEST_PATH) != OK:
		return false
	var saved := float(cfg.get_value("view", "height_offset", -99.0))
	return absf(saved - xr.height_offset) < 0.01


func _remove_test_file() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists(SETTINGS_TEST_FILE):
		dir.remove(SETTINGS_TEST_FILE)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
