extends Node
## XRPlayer rig settings without a headset: element cycling, eye height limits,
## dominant hand (which holder and stick move), walking pace stacking, the
## menu/scripted-move lock, and one-signal-per-press edge detection.
##   godot --headless --path . --fixed-fps 90 res://tests/xr_rig_test.tscn -- --desktop

const PLAYER_SCENE := preload("res://scenes/player/xr_player.tscn")

var failures := 0
var xr: XRPlayer


func _ready() -> void:
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	xr = PLAYER_SCENE.instantiate()
	var start_xr := xr.get_node_or_null("StartXR")
	if start_xr:
		xr.remove_child(start_xr)
		start_xr.free()
	add_child(xr)
	await _frames(2)

	_check_element_cycle()
	_check_height_limits()
	_check_dominant_hand()
	_check_walk_pace_stacks()
	await _check_lock_and_pause()
	_check_press_edges()
	xr.queue_free()


func _check_element_cycle() -> void:
	var all := Elements.ALL
	_check("the element cycle steps to the next element", XRPlayer.next_element(all[0]) == all[1])
	_check("the element cycle wraps from the last element back to the first",
		XRPlayer.next_element(all[all.size() - 1]) == all[0])
	_check("an unknown element starts the cycle again", XRPlayer.next_element("nope") == all[0])


func _check_height_limits() -> void:
	xr.adjust_height(10.0)
	_check("eye height offset stops at +0.80 m", is_equal_approx(xr.height_offset, 0.80))
	var body := xr.get_node("XROrigin3D/PlayerBody")
	_check("the physics body follows the height offset", is_equal_approx(float(body.get("player_height_offset")), 0.80))
	xr.adjust_height(-10.0)
	_check("eye height offset stops at -0.45 m", is_equal_approx(xr.height_offset, -XRPlayer.HEIGHT_LIMIT))
	xr.adjust_height(0.45)
	_check("a small step moves the offset by exactly that amount", is_equal_approx(xr.height_offset, 0.0))


func _check_dominant_hand() -> void:
	var direct := xr._get_movement_direct()
	xr.set_dominant_hand("LEFT")
	_check("dominant hand accepts any case", xr.dominant_hand == "left")
	_check("left-dominant: the left holder is the weapon hand", xr.get_dominant_holder() == xr.left_holder
		and xr.get_offhand_holder() == xr.right_holder)
	_check("left-dominant: the right stick moves the player", direct.get_parent() == xr.right_controller)
	xr.set_dominant_hand("middle")
	_check("an unknown hand name changes nothing", xr.dominant_hand == "left")
	xr.set_dominant_hand("right")
	_check("right-dominant: the left stick moves and the right holder fights",
		xr.get_dominant_controller() == xr.right_controller and direct.get_parent() == xr.left_controller)


func _check_walk_pace_stacks() -> void:
	var base := xr.get_move_speed()
	_check("the locomotion provider has a real top speed", base > 0.0)
	xr.set_walk_scale(0.5)
	_check("walking pace scales the top speed", is_equal_approx(xr.get_move_speed(), base * 0.5))
	xr.set_move_speed_scale(2.0)
	_check("the ink boost stacks with walking pace instead of replacing it",
		is_equal_approx(xr.get_move_speed(), base))
	xr.set_walk_scale(1.0)
	_check("ink boost alone doubles the base speed", is_equal_approx(xr.get_move_speed(), base * 2.0))
	xr.set_move_speed_scale(1.0)
	_check("both scales back to 1.0 restore the base speed", is_equal_approx(xr.get_move_speed(), base))


func _check_lock_and_pause() -> void:
	var direct := xr._get_movement_direct()
	var turn := xr._get_movement_turn()
	var body := xr.get_node("XROrigin3D/PlayerBody")
	xr.set_rig_locked(true)
	_check("a scripted move locks the body and both locomotion providers",
		not body.get("enabled") and not direct.get("enabled") and not turn.get("enabled"))
	xr.set_rig_locked(false)
	_check("unlocking gives the body and locomotion back", body.get("enabled") and direct.get("enabled") and turn.get("enabled"))

	body.set("velocity", Vector3(1.0, 0.0, 1.0))
	xr.set_locomotion_enabled(false)
	_check("the pause menu parks the body with no leftover velocity",
		not body.get("enabled") and (body.get("velocity") as Vector3).is_zero_approx())
	_check("the pause menu also disables both stick providers", not direct.get("enabled") and not turn.get("enabled"))
	xr.set_locomotion_enabled(true)
	_check("closing the menu restores the stick providers", direct.get("enabled") and turn.get("enabled"))

	xr.teleport_feet(Vector3(3.0, 0.0, -2.0))
	await _frames(2)
	var feet := xr.feet_position()
	_check("a blink lands the feet on the target (x, z)", is_equal_approx(feet.x, 3.0) and is_equal_approx(feet.z, -2.0))


func _check_press_edges() -> void:
	var seen := []
	for down in [false, true, true, false, true]:
		seen.append(xr._pressed_once("edge_test", down))
	_check("a button press fires once, on the frame it goes down", seen == [false, true, false, false, true])


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
