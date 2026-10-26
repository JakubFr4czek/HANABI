class_name DesktopPlayer
extends CharacterBody3D
## Flat-screen fallback rig, used when no OpenXR runtime is available (e.g. on
## macOS) so sword physics can be tested without a headset.
##
## Click to capture the mouse, Esc to release. Mouse looks around; hold the
## right mouse button to move the sword hand with the mouse instead. WASD to
## walk. F / G / T play a scripted horizontal slash / overhead cut / thrust,
## mouse wheel changes their speed. E grabs or drops the sword.

const EYE_HEIGHT := 1.65
const HAND_REST := Vector3(0.22, -0.28, -0.42)
const HAND_RANGE := Vector2(0.6, 0.5)
## Scripted swings: hand offsets (see [member hand_offset]) the hand passes through.
const SLASH_HORIZONTAL := [Vector3(0.6, -0.22, 0), Vector3(-0.6, -0.3, 0)]  # torso height, right to left
const SLASH_OVERHEAD := [Vector3(0.05, 0.5, 0), Vector3(0.0, -0.5, 0)]
const THRUST := [Vector3(0, -0.2, -0.05), Vector3(0, -0.15, 0.42)]

@export var move_speed := 3.0
@export var mouse_look_sensitivity := 0.0025
@export var mouse_hand_sensitivity := 0.0018

var camera := Camera3D.new()
var hand := Node3D.new()
var holder := WeaponHolder.new()
## Hand offset from HAND_REST in camera space (x right, y up, z forward).
var hand_offset := Vector3.ZERO
## Seconds a scripted swing takes (changed with the mouse wheel).
var swing_duration := 0.22

var _pitch := 0.0
var _swing_tween: Tween
var _hud := Label.new()


func _ready() -> void:
	collision_layer = 1 << 19  # player_body (same layer as XR Tools)
	collision_mask = 1 | 2 | 8
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	camera.position.y = EYE_HEIGHT
	camera.fov = 75.0
	camera.near = 0.03
	camera.add_to_group("player_head")
	add_child(camera)
	camera.make_current()

	add_child(hand)
	holder.name = "RightHolder"
	holder.side = "right"
	hand.add_child(holder)

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	_update_hand()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			swing_duration = clampf(swing_duration - 0.02, 0.06, 0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			swing_duration = clampf(swing_duration + 0.02, 0.06, 0.6)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_kill_swing()
			hand_offset.x = clampf(hand_offset.x + event.relative.x * mouse_hand_sensitivity, -HAND_RANGE.x, HAND_RANGE.x)
			hand_offset.y = clampf(hand_offset.y - event.relative.y * mouse_hand_sensitivity, -HAND_RANGE.y, HAND_RANGE.y)
		else:
			rotate_y(-event.relative.x * mouse_look_sensitivity)
			_pitch = clampf(_pitch - event.relative.y * mouse_look_sensitivity, deg_to_rad(-80), deg_to_rad(80))
			camera.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				swing(SLASH_HORIZONTAL)
			KEY_G:
				swing(SLASH_OVERHEAD)
			KEY_T:
				swing(THRUST)
			KEY_E:
				if holder.held:
					holder.release()
				else:
					holder.recall()


## Play a scripted swing through the given hand offsets, then return to rest.
func swing(points: Array) -> void:
	_kill_swing()
	_swing_tween = create_tween()
	_swing_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_swing_tween.tween_property(self, "hand_offset", points[0], 0.15).set_trans(Tween.TRANS_SINE)
	for i in range(1, points.size()):
		_swing_tween.tween_property(self, "hand_offset", points[i], swing_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_interval(0.15)
	_swing_tween.tween_property(self, "hand_offset", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_SINE)


func _kill_swing() -> void:
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input.y += 1
	if Input.is_physical_key_pressed(KEY_S): input.y -= 1
	if Input.is_physical_key_pressed(KEY_A): input.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input.x += 1
	var dir := (global_basis.x * input.x - global_basis.z * input.y).normalized() if input != Vector2.ZERO else Vector3.ZERO
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
	_update_hand()
	_hud.text = _hud_text()


## Place the hand in front of the camera. Moving the hand sideways also yaws the
## blade, and up/down pitches it, like a wrist following the arm.
func _update_hand() -> void:
	var pos := HAND_REST + Vector3(hand_offset.x, hand_offset.y, -hand_offset.z)
	var yaw := -hand_offset.x * 1.4
	var pitch := deg_to_rad(40.0) + hand_offset.y * 2.0
	var local := Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ), pos)
	hand.global_transform = camera.global_transform * local


func _hud_text() -> String:
	var t := "HANABI desktop test rig (no XR runtime found)\n"
	t += "Click: capture mouse   Esc: release   WASD: walk   Mouse: look\n"
	t += "Hold RMB + mouse: move the sword   F/G/T: slash / overhead / thrust\n"
	t += "Wheel: scripted swing time %.2f s   E: grab/drop sword   R: reset dummy\n" % swing_duration
	if holder.held:
		t += "Tip speed: %.1f m/s" % holder.held.measured_tip_speed
	else:
		t += "Sword not held (press E)"
	return t
