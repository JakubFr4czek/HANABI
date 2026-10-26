class_name WeaponHolder
extends Node3D
## Grabs and holds a [HeldWeapon]. The holder's global transform is the grip
## pose the weapon follows: blade along -Z, so rotate this node (relative to the
## controller) to change how the sword sits in the hand.
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

var held: HeldWeapon = null

var _controller: XRController3D = null
var _recall_was_pressed := false
var _hand: Node3D = null  # XR Tools hand model next to us, if any
var _hand_anchor: Node3D = null  # follows the weapon; the hand model is pinned to it


func _ready() -> void:
	_controller = get_parent() as XRController3D
	if _controller:
		for sibling in _controller.get_children():
			if sibling is XRToolsHand:
				_hand = sibling


func get_grip_transform() -> Transform3D:
	return global_transform


func grab(weapon: HeldWeapon) -> void:
	if weapon == null or weapon == held:
		return
	if weapon.holder and weapon.holder != self:
		weapon.holder.call("release")
	release()
	held = weapon
	weapon.on_grabbed(self)
	_pin_hand_to(weapon)


func release() -> void:
	if held:
		var w := held
		held = null
		_unpin_hand()
		w.on_released()


## Show the hand where the sword is, not where the controller is: when the blade
## is stopped by a wall, the hand stays on the hilt. The anchor sits on the
## weapon where the controller would be if the grip were exactly on target.
func _pin_hand_to(weapon: HeldWeapon) -> void:
	if _hand == null or not _hand.has_method("add_target_override"):
		return
	_hand_anchor = Node3D.new()
	_hand_anchor.name = "HandAnchor_" + side
	weapon.add_child(_hand_anchor)
	_hand_anchor.transform = transform.affine_inverse()
	_hand.add_target_override(_hand_anchor, 10)


func _unpin_hand() -> void:
	if _hand_anchor:
		if _hand:
			_hand.remove_target_override(_hand_anchor)
		_hand_anchor.queue_free()
		_hand_anchor = null


## Teleport the nearest free weapon into the hand and grab it.
func recall() -> void:
	var weapon := _nearest_weapon(INF)
	if weapon:
		weapon.global_transform = get_grip_transform()
		weapon.linear_velocity = Vector3.ZERO
		weapon.angular_velocity = Vector3.ZERO
		grab(weapon)


## Controller vibration; no-op on the desktop rig.
func pulse(amplitude: float, duration: float) -> void:
	if _controller:
		_controller.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)


func _process(_delta: float) -> void:
	if _controller == null or not _controller.get_is_active():
		return
	var grip := _controller.get_float(grip_action)
	if held == null and grip > grip_press_threshold:
		var weapon := _nearest_weapon(grab_radius)
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


func _nearest_weapon(max_distance: float) -> HeldWeapon:
	var best: HeldWeapon = null
	var best_d := max_distance
	for node in get_tree().get_nodes_in_group("player_weapons"):
		var w := node as HeldWeapon
		if w == null or (w.holder and w.holder != self):
			continue
		var d := w.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = w
	return best
