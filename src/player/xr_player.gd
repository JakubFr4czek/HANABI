class_name XRPlayer
extends Node3D
## VR player rig: XR Tools origin, camera, hands, smooth locomotion (left stick),
## snap turn (right stick) and a [WeaponHolder] in each hand.
## A/X: [signal reset_requested]. B/Y without grip: [signal toggle_attacks_requested]
## (with grip, B/Y recalls a weapon, see WeaponHolder). Thumbstick click:
## cycle the element of the weapon in that hand.

signal reset_requested
signal toggle_attacks_requested

@onready var left_controller: XRController3D = $XROrigin3D/LeftHand
@onready var right_controller: XRController3D = $XROrigin3D/RightHand
@onready var left_holder: WeaponHolder = $XROrigin3D/LeftHand/WeaponHolder
@onready var right_holder: WeaponHolder = $XROrigin3D/RightHand/WeaponHolder

var _was_pressed := {}


func _process(_delta: float) -> void:
	if _pressed_once("ax", left_controller.is_button_pressed("ax_button") or right_controller.is_button_pressed("ax_button")):
		reset_requested.emit()
	for c in [left_controller, right_controller]:
		var gripping: bool = c.get_float("grip") > 0.6
		if _pressed_once("by_" + c.name, c.is_button_pressed("by_button")) and not gripping:
			toggle_attacks_requested.emit()
		if _pressed_once("click_" + c.name, c.is_button_pressed("primary_click")):
			var holder := left_holder if c == left_controller else right_holder
			if holder.held:
				holder.held.set_element(next_element(holder.held.element))


func _pressed_once(key: String, pressed: bool) -> bool:
	var was: bool = _was_pressed.get(key, false)
	_was_pressed[key] = pressed
	return pressed and not was


static func next_element(current: String) -> String:
	var i := Elements.ALL.find(current)
	return Elements.ALL[(i + 1) % Elements.ALL.size()]
