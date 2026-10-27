class_name WeaponHolder
extends Node3D
## Grabs and holds a [HeldWeapon]. The holder's global transform is the grip
## pose the weapon follows: blade along -Z, so rotate this node (relative to the
## controller) to change how the sword sits in the hand.
##
## Supports free grabbing anywhere along the handle (tsuka) only — never the
## guard or the blade — as well as grabbing a weapon already held by the
## other hand for two-handed swordplay.
##
## Under an [XRController3D] it reads the grip and B/Y inputs itself:
## hold grip near a weapon to grab it, release grip to drop it, press B/Y to
## (while holding grip) recall the nearest free weapon. Under anything else (desktop
## rig) call [method grab] / [method release] directly.

@export_enum("left", "right") var side := "right"
@export var grab_radius := 0.3
@export var grip_action := "grip"
@export var recall_action := "by_button"
@export var grip_press_threshold := 0.6
@export var grip_release_threshold := 0.35
## The hand model shows on the weapon's grip only while that grip is within
## this distance (m) of the controller; farther away it goes back to the controller.
@export var hand_pin_max_distance := 0.3
## Under an XR controller (aim pose: -Z runs along the forearm, as the XR Tools
## hand shows) the handle sits in the closed fist's channel: the blade leaves the
## fist on the thumb side, pitched this far up from the forearm, edge forward.
## 76° is the knuckle line of the XR Tools hand's closed grip.
@export_range(0.0, 120.0) var xr_blade_pitch_degrees := 76.0
## Center of the closed fist in the controller's aim frame (right hand; the
## left hand mirrors it about [constant XR_HANDS_MIRROR_X]).
@export var xr_fist_center := Vector3(-0.003, -0.01, -0.012)

## The XR Tools left hand mirrors the right one about the plane x = 0.01 m.
const XR_HANDS_MIRROR_X := 0.01

var held: HeldWeapon = null

var _controller: XRController3D = null
var _recall_was_pressed := false
var _hand: Node3D = null  # XR Tools hand model next to us, if any
var _hand_anchor: Node3D = null  # follows the weapon; the hand model is pinned to it
var _hand_pinned := false
var _pattern_id := 0


func _ready() -> void:
	_controller = get_parent() as XRController3D
	if _controller:
		transform = xr_grip_transform()
		for sibling in _controller.get_children():
			if sibling is XRToolsHand:
				_hand = sibling


func get_grip_transform() -> Transform3D:
	return global_transform


## The holder's pose relative to its XR controller.
func xr_grip_transform() -> Transform3D:
	var center := xr_fist_center
	if side == "left":
		center.x = 2.0 * XR_HANDS_MIRROR_X - center.x
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(xr_blade_pitch_degrees)), center)


## Grab [param weapon].
## - If [param custom_local_grip] is a [Transform3D] or [Vector3], grip at that
##   local pose on the weapon (clamped to the handle).
## - Otherwise, if the weapon's grabbable body is within [member grab_radius],
##   grip it where the hand currently is relative to the weapon.
## - If the weapon is far away, fall back to the default origin grip.
func grab(weapon: HeldWeapon, custom_local_grip: Variant = null) -> void:
	if weapon == null:
		return
	if held == weapon and custom_local_grip == null:
		return
	if held and held != weapon:
		release()
	else:
		_unpin_hand()
	var local_grip := Transform3D.IDENTITY
	if custom_local_grip is Transform3D:
		var g: Transform3D = custom_local_grip
		local_grip = Transform3D(g.basis.orthonormalized(), weapon.clamp_grip_point(g.origin))
	elif custom_local_grip is Vector3:
		local_grip = Transform3D(Basis.IDENTITY, weapon.clamp_grip_point(custom_local_grip as Vector3))
	elif weapon.distance_to_grip(get_grip_transform().origin) <= grab_radius:
		local_grip = weapon.compute_local_grip(get_grip_transform())
	held = weapon
	weapon.on_grabbed(self, local_grip)
	_pin_hand_to(weapon, weapon.get_local_grip(self))


func release() -> void:
	if held:
		var w := held
		held = null
		_unpin_hand()
		w.on_released(self)


## Show the hand where the sword is, not where the controller is: when the blade
## is stopped by a wall, the hand stays on the handle where it
## grabbed the weapon.
func _pin_hand_to(weapon: HeldWeapon, local_grip: Transform3D = Transform3D.IDENTITY) -> void:
	if _hand == null or not _hand.has_method("add_target_override"):
		return
	_hand_anchor = Node3D.new()
	_hand_anchor.name = "HandAnchor_" + side
	weapon.add_child(_hand_anchor)
	_hand_anchor.transform = local_grip * transform.affine_inverse()
	_set_hand_pinned(true)


func _unpin_hand() -> void:
	if _hand_anchor:
		_set_hand_pinned(false)
		_hand_anchor.queue_free()
		_hand_anchor = null


func _set_hand_pinned(pinned: bool) -> void:
	if pinned == _hand_pinned or _hand == null or _hand_anchor == null:
		return
	_hand_pinned = pinned
	if pinned:
		_hand.add_target_override(_hand_anchor, 10)
	else:
		_hand.remove_target_override(_hand_anchor)


func _physics_process(_delta: float) -> void:
	if _hand_anchor == null:
		return
	# The anchor is where the controller would be if the weapon sat exactly in the hand.
	var gap := _hand_anchor.global_position.distance_to(get_parent_node_3d().global_position)
	if _hand_pinned and gap > hand_pin_max_distance:
		_set_hand_pinned(false)
	elif not _hand_pinned and gap < hand_pin_max_distance * 0.5:
		_set_hand_pinned(true)


## Teleport the nearest free weapon into the hand and grab it at its main grip.
func recall() -> void:
	var weapon := _nearest_weapon(INF, true)
	if weapon:
		weapon.global_transform = get_grip_transform()
		weapon.linear_velocity = Vector3.ZERO
		weapon.angular_velocity = Vector3.ZERO
		grab(weapon, Transform3D.IDENTITY)


## Controller vibration; no-op on the desktop rig.
func pulse(amplitude: float, duration: float) -> void:
	if _controller:
		_controller.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)


## Plays [amplitude, seconds] steps back to back in real time (unaffected by
## hit-stop and slow motion). A newer pattern cuts off an older one.
func pulse_pattern(steps: Array) -> void:
	if _controller == null:
		return
	_pattern_id += 1
	var id := _pattern_id
	for step in steps:
		if id != _pattern_id or not is_inside_tree():
			return
		pulse(step[0], step[1])
		await get_tree().create_timer(step[1], true, false, true).timeout


func _process(_delta: float) -> void:
	if _controller == null or not _controller.get_is_active():
		return
	var grip := _controller.get_float(grip_action)
	if held == null and grip > grip_press_threshold:
		var weapon := _nearest_weapon(grab_radius, false)
		if weapon:
			grab(weapon)
	elif held and grip < grip_release_threshold:
		release()

	var recall_pressed := _controller.is_button_pressed(recall_action)
	# Recall while making a fist (grip held), otherwise the grip-release check
	# above would drop the weapon again on the next frame.
	if recall_pressed and not _recall_was_pressed and held == null and grip > grip_press_threshold:
		recall()
	_recall_was_pressed = recall_pressed


func _nearest_weapon(max_distance: float, free_only: bool = false) -> HeldWeapon:
	var best: HeldWeapon = null
	var best_d := max_distance
	for node in get_tree().get_nodes_in_group("player_weapons"):
		var w := node as HeldWeapon
		if w == null or w.is_held_by(self):
			continue
		if free_only and w.is_held():
			continue
		if not free_only and w.holders.size() >= 2:
			continue
		var d := w.distance_to_grip(global_position)
		if d < best_d:
			best_d = d
			best = w
	return best
