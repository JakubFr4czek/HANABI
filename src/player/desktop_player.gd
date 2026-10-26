class_name DesktopPlayer
extends CharacterBody3D
## Flat-screen fallback rig, used when no OpenXR runtime is available (e.g. on
## macOS) so sword physics can be tested without a headset.
##
## Click to capture the mouse, Esc to release. Mouse looks around; hold the
## right mouse button to move the sword hand with the mouse instead. WASD to
## walk. F / G / T play a scripted horizontal slash / overhead cut / thrust,
## mouse wheel changes their speed. Hold Q to raise a high block (parry the
## dummy's overhead cut). E grabs or drops the weapon, 1 / 2 pick katana /
## kanabō, Z cycles the element, P toggles the dummy's attacks.

signal toggle_attacks_requested

const EYE_HEIGHT := 1.65
const HAND_REST := Vector3(0.22, -0.28, -0.42)
const HAND_RANGE := Vector2(0.6, 0.5)
## Scripted swings: hand offsets (see [member hand_offset]) the hand passes through.
const SLASH_HORIZONTAL := [Vector3(0.6, -0.22, 0), Vector3(-0.6, -0.3, 0)]  # torso height, right to left
const SLASH_OVERHEAD := [Vector3(0.05, 0.5, 0), Vector3(0.0, -0.5, 0)]
const THRUST := [Vector3(0, -0.2, -0.05), Vector3(0, -0.15, 0.42)]
## Hand pose (camera space) of the high block: blade across, above the eyes.
var BLOCK_HIGH := Transform3D(Basis.from_euler(Vector3(deg_to_rad(12.0), deg_to_rad(90.0), 0.0), EULER_ORDER_YXZ), Vector3(0.3, 0.12, -0.42))

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
## Weapons that 1 / 2 / ... switch between (set by the room).
var weapons: Array = []
## 0..1 blend toward the high block pose (Q).
var block_amount := 0.0
## Force the block on (tests), regardless of the Q key.
var force_block := false

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
			KEY_1, KEY_2, KEY_3:
				var i: int = event.physical_keycode - KEY_1
				if i < weapons.size():
					take_weapon(weapons[i])
			KEY_Z:
				if holder.held:
					holder.held.set_element(XRPlayer.next_element(holder.held.element))
			KEY_P:
				toggle_attacks_requested.emit()


## Move the player instantly; the held weapon comes along instead of flying
## across the room behind the hand.
func teleport(position_: Vector3, yaw: float = 0.0) -> void:
	global_position = position_
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO
	_update_hand()
	if holder.held:
		holder.held.snap_to_hand()


## Drop what we hold and pull [param weapon] into the hand.
func take_weapon(weapon: HeldWeapon) -> void:
	if holder.held == weapon:
		return
	holder.release()
	weapon.global_transform = holder.get_grip_transform()
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO
	holder.grab(weapon)


## Play a scripted swing through the given hand offsets, then return to rest.
func swing(points: Array) -> void:
	_kill_swing()
	_swing_tween = create_tween()
	_swing_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	# The player's hand moves in real time, even during slow motion (like in VR).
	_swing_tween.set_ignore_time_scale(true)
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
	var real_delta := TimeController.real_tick()
	var want_block := 1.0 if (force_block or Input.is_physical_key_pressed(KEY_Q)) else 0.0
	block_amount = move_toward(block_amount, want_block, real_delta * 8.0)
	_update_hand()
	_hud.text = _hud_text()


## Place the hand in front of the camera. Moving the hand sideways also yaws the
## blade, and up/down pitches it, like a wrist following the arm.
func _update_hand() -> void:
	var pos := HAND_REST + Vector3(hand_offset.x, hand_offset.y, -hand_offset.z)
	var yaw := -hand_offset.x * 1.4
	var pitch := deg_to_rad(40.0) + hand_offset.y * 2.0
	var local := Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ), pos)
	if block_amount > 0.0:
		local = local.interpolate_with(BLOCK_HIGH, block_amount)
	hand.global_transform = camera.global_transform * local


func _hud_text() -> String:
	var t := "HANABI desktop test rig (no XR runtime found)\n"
	t += "Click: capture mouse   Esc: release   WASD: walk   Mouse: look\n"
	t += "Hold RMB + mouse: move the weapon   F/G/T: slash / overhead / thrust   hold Q: high block\n"
	t += "Wheel: scripted swing time %.2f s   1/2: katana / kanabō   E: drop/take   Z: element\n" % swing_duration
	t += "P: dummy attacks on/off   R: reset dummy\n"
	if holder.held:
		var w := holder.held
		t += "%s [%s]   tip %.1f m/s   arm strength %.0f%%" % [w.weapon_name, w.element, w.measured_tip_speed, w.strength * 100.0]
	else:
		t += "No weapon in hand (press 1 or 2)"
	if TimeController.time_scale < 1.0:
		t += "   TIME x%.2f" % TimeController.time_scale
	return t
