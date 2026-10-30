class_name DesktopPlayer
extends CharacterBody3D
## Flat-screen fallback rig, used when no OpenXR runtime is available (e.g. on
## macOS) so sword physics can be tested without a headset.
##
## Click to capture the mouse, Esc to release. Mouse looks around; hold the
## right mouse button to move the sword hand with the mouse instead. WASD to
## walk. F / G / T play a scripted horizontal slash / overhead cut / thrust,
## X a wrist flick (no arm behind it),
## mouse wheel changes their speed. Hold Q to raise a high block (parry the
## dummy's overhead cut). E grabs or drops the weapon, 1 / 2 pick katana /
## kanabō, C cycles grip position along the handle,
## V toggles two-handed grip, Z cycles the element, P toggles the dummy's attacks.

signal toggle_attacks_requested
signal reset_requested
signal ability_1_requested(direction: Vector3)
signal ability_2_requested(direction: Vector3)
## L key: spend the oldest Torii charge (D21). The run decides whether it lands.
signal charge_activation_requested
signal menu_requested

const EYE_HEIGHT := 1.65
const HAND_REST := Vector3(0.22, -0.28, -0.42)
const HAND_RANGE := Vector2(0.6, 0.5)
## Scripted swings: hand offsets (see [member hand_offset]) the hand passes through.
const SLASH_HORIZONTAL := [Vector3(0.6, -0.22, 0), Vector3(-0.6, -0.3, 0)]  # torso height, right to left
const SLASH_OVERHEAD := [Vector3(0.05, 0.5, 0), Vector3(0.0, -0.5, 0)]
const THRUST := [Vector3(0, -0.2, -0.05), Vector3(0, -0.15, 0.42)]
## Hand pose (camera space) of the high block: blade across, above the eyes.
var BLOCK_HIGH := Transform3D(Basis.from_euler(Vector3(deg_to_rad(12.0), deg_to_rad(90.0), 0.0), EULER_ORDER_YXZ), Vector3(0.3, 0.12, -0.42))
## Preset local grip points cycled with C on desktop (along the handle only).
const GRIP_PRESETS := [
	Vector3.ZERO,
	Vector3(0.0, 0.0, -0.05),
	Vector3(0.0, 0.0, 0.16),
]

@export var move_speed := 3.0
@export var mouse_look_sensitivity := 0.0025
@export var mouse_hand_sensitivity := 0.0018

var camera := Camera3D.new()
var hand := Node3D.new()
var off_hand := Node3D.new()
var holder := WeaponHolder.new()
var left_holder := WeaponHolder.new()
var health := PlayerHealth.new()
var hurt_feedback := HurtFeedback.new()
## Hand offset from HAND_REST in camera space (x right, y up, z forward).
var hand_offset := Vector3.ZERO
## Held H: the desktop stand-in for the check-the-watch gesture, which raises the wrist readout.
var wrist_check := false
## Seconds a scripted swing takes (changed with the mouse wheel).
var swing_duration := 0.22
## Weapons that 1 / 2 / ... switch between (set by the room).
var weapons: Array = []
## 0..1 blend toward the high block pose (Q).
var block_amount := 0.0
## Force the block on (tests), regardless of the Q key.
var force_block := false
## Current desktop grip preset index (position along the handle).
var grip_preset_index := 0
## Whether the off-hand holder also grips the weapon on desktop.
var two_handed := false
## When true, WASD locomotion is disabled (run intro levitation).
var movement_locked := false
## Extra wrist yaw (radians) on top of the hand pose: a flick without moving the arm (X).
var flick_angle := 0.0

var _pitch := 0.0
var _swing_roll := 0.0
var _prev_hand_pos := HAND_REST
var _swing_tween: Tween
var _hud := Label.new()


func _ready() -> void:
	# Mouse look, the hand and the menu pointer keep working while a menu
	# pauses the game; walking is switched off in _physics_process.
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision_layer = XRPlayer.COLLISION_LAYER_BODY  # player_body (same layer as XR Tools)
	add_to_group("player_body")
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

	hand.add_child(off_hand)
	left_holder.name = "LeftHolder"
	left_holder.side = "left"
	off_hand.add_child(left_holder)

	health.head = camera
	add_child(health)
	hurt_feedback.setup(health, camera, [holder, left_holder])
	add_child(hurt_feedback)

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
	elif event is InputEventKey and event.physical_keycode == KEY_H and not event.echo:
		wrist_check = event.pressed
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
			KEY_X:
				flick()
			KEY_E:
				if holder.held:
					left_holder.release()
					holder.release()
				else:
					holder.recall()
					if two_handed and holder.held:
						_apply_desktop_grip(holder.held)
			KEY_1, KEY_2, KEY_3:
				var i: int = event.physical_keycode - KEY_1
				if i < weapons.size():
					take_weapon(weapons[i])
			KEY_C:
				cycle_grip_preset()
			KEY_V:
				set_two_handed(not two_handed)
			KEY_Z:
				if holder.held:
					holder.held.set_element(XRPlayer.next_element(holder.held.element))
			KEY_P:
				toggle_attacks_requested.emit()
			KEY_J:
				trigger_ability_1()
			KEY_K:
				trigger_ability_2()
			KEY_L:
				trigger_charge_activation()
			KEY_TAB, KEY_M:
				menu_requested.emit()
			KEY_R:
				reset_requested.emit()


func get_look_direction() -> Vector3:
	var dir := -camera.global_basis.z
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD


func trigger_ability_1() -> void:
	ability_1_requested.emit(get_look_direction())


func trigger_ability_2() -> void:
	ability_2_requested.emit(get_look_direction())


func trigger_charge_activation() -> void:
	charge_activation_requested.emit()


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
	if holder.held == weapon and not two_handed and grip_preset_index == 0:
		return
	left_holder.release()
	holder.release()
	weapon.global_transform = holder.get_grip_transform()
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO
	_apply_desktop_grip(weapon)
	weapon.snap_to_hand()


func cycle_grip_preset() -> void:
	grip_preset_index = (grip_preset_index + 1) % GRIP_PRESETS.size()
	if holder.held:
		_apply_desktop_grip(holder.held)


func set_two_handed(enabled: bool) -> void:
	two_handed = enabled
	if holder.held:
		_apply_desktop_grip(holder.held)
	else:
		left_holder.release()


func _apply_desktop_grip(weapon: HeldWeapon) -> void:
	left_holder.release()
	var primary_local: Vector3 = weapon.clamp_grip_point(GRIP_PRESETS[grip_preset_index])
	holder.grab(weapon, Transform3D(Basis.IDENTITY, primary_local))
	if two_handed:
		# The second hand takes the other end of the handle.
		var secondary_target := Vector3(0.0, 0.0, -0.02) if primary_local.z > 0.07 else Vector3(0.0, 0.0, 0.17)
		var secondary_local: Vector3 = weapon.clamp_grip_point(secondary_target)
		off_hand.position = secondary_local - primary_local
		left_holder.grab(weapon, Transform3D(Basis.IDENTITY, secondary_local))
	else:
		off_hand.position = Vector3.ZERO


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


## A wrist flick: the hand stays put, the wrist whips the blade across.
func flick(from_deg: float = 55.0, to_deg: float = -55.0, duration: float = 0.12) -> void:
	_kill_swing()
	_swing_tween = create_tween()
	_swing_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_swing_tween.set_ignore_time_scale(true)
	_swing_tween.tween_property(self, "flick_angle", deg_to_rad(from_deg), 0.12).set_trans(Tween.TRANS_SINE)
	_swing_tween.tween_property(self, "flick_angle", deg_to_rad(to_deg), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_interval(0.1)
	_swing_tween.tween_property(self, "flick_angle", 0.0, 0.3).set_trans(Tween.TRANS_SINE)


func _kill_swing() -> void:
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		# Menu open: stand still, but the hand still follows the view.
		velocity = Vector3.ZERO
		block_amount = move_toward(block_amount, 0.0, TimeController.real_tick() * 8.0)
		_update_hand()
		_hud.text = _hud_text()
		return
	if movement_locked:
		velocity = Vector3.ZERO
		move_and_slide()
		var real_delta := TimeController.real_tick()
		block_amount = move_toward(block_amount, 0.0, real_delta * 8.0)
		_update_hand()
		_hud.text = _hud_text()
		return
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
	var local := Transform3D(Basis.from_euler(Vector3(pitch, yaw + flick_angle, 0.0), EULER_ORDER_YXZ), pos)
	# Turn the wrist so the cutting edge (the hand's -Y) leads the swing, as a
	# player does without thinking in VR.
	var dt := TimeController.real_tick()
	var motion := (pos - _prev_hand_pos) / dt
	_prev_hand_pos = pos
	var blade := -local.basis.z
	var across := motion - blade * motion.dot(blade)
	var want_roll := 0.0
	if across.length() > 0.8:
		want_roll = (-local.basis.y).signed_angle_to(across.normalized(), blade)
	_swing_roll = lerp_angle(_swing_roll, want_roll, clampf(dt * 25.0, 0.0, 1.0))
	local.basis = Basis(blade, _swing_roll) * local.basis
	if block_amount > 0.0:
		local = local.interpolate_with(BLOCK_HIGH, block_amount)
	hand.global_transform = camera.global_transform * local


func set_screen_hud_visible(visible: bool) -> void:
	var layer := _hud.get_parent() as CanvasLayer
	if layer:
		layer.visible = visible


func _hud_text() -> String:
	var t := "HANABI desktop test rig (no XR runtime found)\n"
	t += "Click: capture mouse   Esc: release   WASD: walk   Mouse: look\n"
	t += "Hold RMB + mouse: move the weapon   F/G/T: slash / overhead / thrust   X: wrist flick   hold Q: high block\n"
	t += "Wheel: scripted swing time %.2f s   1/2: katana / kanabō   C: grip spot   V: 1H/2H   E: drop/take   Z: element\n" % swing_duration
	t += "P: dummy attacks on/off   R: reset dummy\n"
	if holder.held:
		var w := holder.held
		var grip_info := "%s, %s" % [w.get_grip_zone(holder), "2H" if w.is_two_handed() else "1H"]
		t += "%s [%s] (%s)   tip %.1f m/s   arm strength %.0f%%" % [w.weapon_name, w.element, grip_info, w.measured_tip_speed, w.strength * 100.0]
	else:
		t += "No weapon in hand (press 1 or 2)"
	if TimeController.time_scale < 1.0:
		t += "   TIME x%.2f" % TimeController.time_scale
	t += "\nHP %d / %d%s" % [ceili(health.hp), int(health.max_hp), "   DOWN" if not health.is_alive() else ""]
	return t
