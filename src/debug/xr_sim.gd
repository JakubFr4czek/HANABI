class_name XrSim
extends Node
## Headset-free XR: registers fake head and controller trackers with the
## XRServer and feeds them poses and inputs, so the real XRPlayer (XR Tools
## body, movement, hands, weapon holders, wrist HUD) runs exactly as with a
## headset, only steered by a script. Start the game with -- --xr-sim (or
## --xr-sim --guard) to get it; tests drive it through set_head/set_hand/...
##
## Poses are in XROrigin3D space, like real tracking.

var head_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.65, 0.0))
var hand_xf := {
	"left": Transform3D(Basis.IDENTITY, Vector3(-0.22, 1.05, -0.3)),
	"right": Transform3D(Basis.IDENTITY, Vector3(0.22, 1.05, -0.3)),
}

var _head := XRPositionalTracker.new()
var _hands := {"left": XRControllerTracker.new(), "right": XRControllerTracker.new()}
var _prev := {}


func _ready() -> void:
	add_to_group("xr_sim")
	process_physics_priority = -100  # poses land before anything reads them
	_head.type = XRServer.TRACKER_HEAD
	_head.name = &"head"
	XRServer.add_tracker(_head)
	for side in _hands:
		var t: XRControllerTracker = _hands[side]
		t.type = XRServer.TRACKER_CONTROLLER
		t.name = StringName(side + "_hand")
		t.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		XRServer.add_tracker(t)
		for input in ["grip", "trigger"]:
			t.set_input(input, 0.0)
		t.set_input("primary", Vector2.ZERO)
	_push(0.0)


func _exit_tree() -> void:
	XRServer.remove_tracker(_head)
	for side in _hands:
		XRServer.remove_tracker(_hands[side])


func set_head(xf: Transform3D) -> void:
	head_xf = xf


func set_hand(side: String, xf: Transform3D) -> void:
	hand_xf[side] = xf


func set_grip(side: String, value: float) -> void:
	(_hands[side] as XRControllerTracker).set_input("grip", value)


func set_trigger(side: String, value: float) -> void:
	(_hands[side] as XRControllerTracker).set_input("trigger", value)


func set_stick(side: String, value: Vector2) -> void:
	(_hands[side] as XRControllerTracker).set_input("primary", value)


func set_button(side: String, button: String, pressed: bool) -> void:
	(_hands[side] as XRControllerTracker).set_input(button, pressed)


func _physics_process(delta: float) -> void:
	_push(delta)


func _push(delta: float) -> void:
	_set_pose(_head, "head", head_xf, delta)
	for side in _hands:
		_set_pose(_hands[side], side, hand_xf[side], delta)


func _set_pose(t: XRPositionalTracker, key: String, xf: Transform3D, delta: float) -> void:
	var lin := Vector3.ZERO
	var ang := Vector3.ZERO
	if _prev.has(key) and delta > 0.0:
		var p: Transform3D = _prev[key]
		lin = (xf.origin - p.origin) / delta
		var dq := (xf.basis.get_rotation_quaternion() * p.basis.get_rotation_quaternion().inverse())
		ang = dq.get_axis() * dq.get_angle() / delta if dq.get_angle() > 1e-5 else Vector3.ZERO
	_prev[key] = xf
	t.set_pose(&"default", xf, lin, ang, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
