class_name XRPlayer
extends Node3D
## VR player rig: XR Tools origin, camera, hands, smooth locomotion (left stick),
## snap turn (right stick) and a [WeaponHolder] in each hand.
## A/X: [signal reset_requested]. B/Y without grip: [signal toggle_attacks_requested]
## (with grip, B/Y recalls a weapon, see WeaponHolder). Thumbstick click:
## cycle the element of the weapon in that hand.

signal reset_requested
signal toggle_attacks_requested
signal element_ability_requested(direction: Vector3)

@onready var left_controller: XRController3D = $XROrigin3D/LeftHand
@onready var right_controller: XRController3D = $XROrigin3D/RightHand
@onready var left_holder: WeaponHolder = $XROrigin3D/LeftHand/WeaponHolder
@onready var right_holder: WeaponHolder = $XROrigin3D/RightHand/WeaponHolder

var health := PlayerHealth.new()
var hurt_feedback := HurtFeedback.new()
## RunGame turns this on so thumbstick click invokes the bound combat ability
## instead of the training-room element color cycler.
var run_element_mode := false

var _was_pressed := {}


func _ready() -> void:
	GameEvents.parry.connect(_on_parry)
	var camera := $XROrigin3D/XRCamera3D as Node3D
	health.head = camera
	add_child(health)
	hurt_feedback.setup(health, camera, [left_holder, right_holder])
	add_child(hurt_feedback)


## The weapon hand(s) get the full parry pattern from the weapon; a free hand
## feels a softer echo so the parry lands in the whole body.
func _on_parry(_info: Dictionary) -> void:
	for h in [left_holder, right_holder]:
		if h.held == null:
			h.pulse_pattern([[0.0, 0.03], [0.45, 0.1]])


func _process(_delta: float) -> void:
	if _pressed_once("ax", left_controller.is_button_pressed("ax_button") or right_controller.is_button_pressed("ax_button")):
		reset_requested.emit()
	for c in [left_controller, right_controller]:
		var gripping: bool = c.get_float("grip") > 0.6
		if _pressed_once("by_" + c.name, c.is_button_pressed("by_button")) and not gripping:
			toggle_attacks_requested.emit()
		if _pressed_once("click_" + c.name, c.is_button_pressed("primary_click")):
			var holder := left_holder if c == left_controller else right_holder
			if run_element_mode:
				element_ability_requested.emit(Vector3.ZERO)
			elif holder.held:
				holder.held.set_element(next_element(holder.held.element))


func _pressed_once(key: String, pressed: bool) -> bool:
	var was: bool = _was_pressed.get(key, false)
	_was_pressed[key] = pressed
	return pressed and not was


## Scripted rig moves (run intro hover, respawn on the seal): XR Tools'
## PlayerBody is top-level and applies gravity to the origin every physics
## frame, so it would pull a hover back down. Locking freezes the body and
## locomotion and recenters the origin on this node so moving the rig root
## places the player exactly.
func set_rig_locked(locked: bool) -> void:
	var origin := $XROrigin3D as XROrigin3D
	origin.transform = Transform3D.IDENTITY
	var body := origin.get_node_or_null("PlayerBody")
	if body:
		body.set("enabled", not locked)
		if not locked:
			body.set("velocity", Vector3.ZERO)
			(body as Node3D).global_transform = origin.global_transform
	for path in ["XROrigin3D/LeftHand/MovementDirect", "XROrigin3D/RightHand/MovementTurn"]:
		var provider := get_node_or_null(path)
		if provider:
			provider.set("enabled", not locked)


## Where the player actually stands. Locomotion moves the XR origin, not this
## root node, so the root stays at the spawn while the player walks away.
func feet_position() -> Vector3:
	var body := get_node_or_null("XROrigin3D/PlayerBody") as Node3D
	if body:
		return body.global_position
	return ($XROrigin3D as Node3D).global_position


## Moves the standing player to [param pos] (combat blink) through XR Tools so
## the body and origin stay together.
func teleport_feet(pos: Vector3) -> void:
	var body := get_node_or_null("XROrigin3D/PlayerBody") as Node3D
	if body and body.has_method("teleport"):
		body.call("teleport", Transform3D(body.global_basis, pos))
	else:
		($XROrigin3D as Node3D).global_position = pos


static func next_element(current: String) -> String:
	var i := Elements.ALL.find(current)
	return Elements.ALL[(i + 1) % Elements.ALL.size()]
