class_name XRPlayer
extends Node3D
## VR player rig: XR Tools origin, camera, hands, smooth locomotion (left stick),
## snap turn (right stick) and a [WeaponHolder] in each hand.
## A/X emits [signal reset_requested] (the test room resets the dummy).

signal reset_requested

@onready var left_controller: XRController3D = $XROrigin3D/LeftHand
@onready var right_controller: XRController3D = $XROrigin3D/RightHand
@onready var left_holder: WeaponHolder = $XROrigin3D/LeftHand/WeaponHolder
@onready var right_holder: WeaponHolder = $XROrigin3D/RightHand/WeaponHolder

var _ax_was_pressed := false


func _process(_delta: float) -> void:
	var pressed := left_controller.is_button_pressed("ax_button") or right_controller.is_button_pressed("ax_button")
	if pressed and not _ax_was_pressed:
		reset_requested.emit()
	_ax_was_pressed = pressed
