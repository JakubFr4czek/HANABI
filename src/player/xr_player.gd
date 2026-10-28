class_name XRPlayer
extends Node3D
## VR player rig: XR Tools origin, camera, hands, smooth locomotion (left stick),
## snap turn (right stick) and a [WeaponHolder] in each hand.
## A/X: [signal ability_1_requested] (or reset in dev). B/Y: [signal ability_2_requested]
## when holding katana (with grip when disarmed, B/Y recalls weapon).
## Left Menu button: tap = [signal menu_requested], hold 1.0s = [method recenter_view].
## Thumbstick click: cycle element in test room.

signal reset_requested
signal toggle_attacks_requested
signal ability_1_requested(direction: Vector3)
signal ability_2_requested(direction: Vector3)
signal menu_requested

## Standard collision layer for player body (layer 20, 1 << 19). Shared across
## XR Tools PlayerBody, DesktopPlayer, HeldWeapon, and Torii gates.
const COLLISION_LAYER_BODY: int = 1 << 19

@onready var left_controller: XRController3D = $XROrigin3D/LeftHand
@onready var right_controller: XRController3D = $XROrigin3D/RightHand
@onready var left_holder: WeaponHolder = $XROrigin3D/LeftHand/WeaponHolder
@onready var right_holder: WeaponHolder = $XROrigin3D/RightHand/WeaponHolder

var health := PlayerHealth.new()
var hurt_feedback := HurtFeedback.new()
## RunGame turns this on so thumbstick click invokes the bound combat ability
## instead of the training-room element color cycler.
var run_element_mode := false

var dominant_hand: String = "right"

var _was_pressed := {}

const VIEW_SETTINGS_PATH := "user://hanabi_vr.cfg"
const RECENTER_HOLD_SEC := 0.6
const TAP_MAX_SEC := 0.35
const HEIGHT_LIMIT := 0.45
const HEIGHT_RATE := 0.3  # m/s while the stick is held
## Extra eye height on top of the real tracked height (XR Tools'
## player_height_offset: the body stands this far below the origin).
var height_offset := 0.0
var _by_time := {}
var _by_used := {}
var _menu_hold_time := 0.0
var _menu_used := false
var _base_move_speed := -1.0
## Ink boost (RunGame) and the walking-pace setting, both multiplying the base speed.
var _move_scale := 1.0
var walk_scale := 1.0


func _ready() -> void:
	# The rig keeps tracking, rendering and reading the controllers while a
	# menu pauses the game (get_tree().paused): the player must still look
	# around and point. Gameplay nodes below us (PlayerHealth) opt back out.
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.parry.connect(_on_parry)
	var camera := $XROrigin3D/XRCamera3D as Node3D
	health.head = camera
	add_child(health)
	hurt_feedback.setup(health, camera, [left_holder, right_holder])
	add_child(hurt_feedback)
	# XR Tools would rescale everyone to a 1.85 m player from whatever the
	# headset reports on the body's first physics frame (often before tracking
	# settles, or mid run-intro). Use the real height plus the saved offset.
	var body := _body()
	if body:
		body.set("player_calibrate_height", false)
	_load_view_settings()
	_apply_height()


## The weapon hand(s) get the full parry pattern from the weapon; a free hand
## feels a softer echo so the parry lands in the whole body.
func _on_parry(_info: Dictionary) -> void:
	for h in [left_holder, right_holder]:
		if h.held == null:
			h.pulse_pattern([[0.0, 0.03], [0.45, 0.1]])


func _process(delta: float) -> void:
	# Button holds are timed in real seconds, also in slow-mo (delta is scaled).
	var _delta := delta / maxf(Engine.time_scale, 0.05)
	# Menu button handling (Left Menu button)
	if left_controller:
		var menu_down: bool = left_controller.is_button_pressed("menu_button")
		if menu_down:
			_menu_hold_time += _delta
			if _menu_hold_time >= 1.0 and not _menu_used:
				recenter_view()
				_menu_used = true
		elif _menu_hold_time > 0.0:
			if not _menu_used and _menu_hold_time <= TAP_MAX_SEC:
				menu_requested.emit()
			_menu_hold_time = 0.0
			_menu_used = false

	# Ability 1 (Button A / X)
	var ax_pressed := _pressed_once("ax_r", right_controller.is_button_pressed("ax_button")) \
		or _pressed_once("ax_l", left_controller.is_button_pressed("ax_button"))
	if ax_pressed:
		if run_element_mode or right_holder.held != null or left_holder.held != null:
			ability_1_requested.emit(_ability_direction(get_dominant_controller()))
		else:
			reset_requested.emit()

	# Ability 2 (Button B / Y when sword is held): exactly one signal per press.
	var by_r := _pressed_once("by_r", right_controller.is_button_pressed("by_button"))
	var by_l := _pressed_once("by_l", left_controller.is_button_pressed("by_button"))
	if by_r and right_holder.held != null:
		ability_2_requested.emit(_ability_direction(right_controller))
	elif by_l and left_holder.held != null:
		ability_2_requested.emit(_ability_direction(left_controller))
	elif run_element_mode and (by_r or by_l) and (right_holder.held != null or left_holder.held != null):
		ability_2_requested.emit(_ability_direction(get_dominant_controller()))

	for c in [left_controller, right_controller]:
		var holder := left_holder if c == left_controller else right_holder
		var gripping: bool = c.get_float("grip") > 0.6
		# Only route B/Y to dev/view actions when not holding a weapon
		if holder.held == null:
			_step_view_button(c, gripping, _delta)
		if _pressed_once("click_" + c.name, c.is_button_pressed("primary_click")):
			# Thumbstick click NEVER fires combat abilities (ELEMENTS_PLAN);
			# in the training room only, it cycles the held weapon's element.
			if not run_element_mode and holder.held:
				holder.held.set_element(next_element(holder.held.element))


func _ability_direction(_controller: XRController3D) -> Vector3:
	var camera := $XROrigin3D/XRCamera3D as Camera3D
	if camera:
		var f := -camera.global_basis.z
		f.y = 0.0
		if f.length_squared() > 0.01:
			return f.normalized()
	return Vector3.FORWARD


## B/Y without grip: tap = toggle_attacks_requested, hold = recenter, hold B +
## turn stick up/down = eye height.
func _step_view_button(c: XRController3D, gripping: bool, delta: float) -> void:
	var key := String(c.name)
	var down := c.is_button_pressed("by_button") and not gripping
	if down:
		var t: float = _by_time.get(key, 0.0) + delta
		_by_time[key] = t
		var turn_c := _get_turn_controller()
		if c == turn_c:
			var stick := c.get_vector2("primary").y
			if absf(stick) > 0.55:
				adjust_height(signf(stick) * HEIGHT_RATE * delta)
				_by_used[key] = true
		if t >= RECENTER_HOLD_SEC and not _by_used.get(key, false):
			recenter_view()
			_by_used[key] = true
	elif _by_time.has(key):
		var held: float = _by_time[key]
		var used: bool = _by_used.get(key, false)
		_by_time.erase(key)
		_by_used.erase(key)
		if used:
			_save_view_settings()
		elif held <= TAP_MAX_SEC:
			toggle_attacks_requested.emit()


## Puts the headset back on the rig origin facing forward, keeping its height.
func recenter_view() -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	for h in [left_holder, right_holder]:
		h.pulse_pattern([[0.0, 0.05], [0.12, 0.05]])
	GameEvents.log_event("xr_recenter", {})


func adjust_height(delta_m: float) -> void:
	height_offset = clampf(height_offset + delta_m, -HEIGHT_LIMIT, 0.80)
	_apply_height()


func _apply_height() -> void:
	var body := _body()
	if body:
		body.set("player_height_offset", height_offset)


func _load_view_settings() -> void:
	if VrComfortSettings:
		VrComfortSettings.load_settings()
		height_offset = VrComfortSettings.height_offset
		VrComfortSettings.apply_to_player(self)
	else:
		var cfg := ConfigFile.new()
		if cfg.load(VIEW_SETTINGS_PATH) == OK:
			height_offset = clampf(float(cfg.get_value("view", "height_offset", 0.0)), -HEIGHT_LIMIT, 0.80)


func _save_view_settings() -> void:
	if VrComfortSettings:
		VrComfortSettings.height_offset = height_offset
		VrComfortSettings.save_settings()
	else:
		var cfg := ConfigFile.new()
		cfg.set_value("view", "height_offset", height_offset)
		cfg.save(VIEW_SETTINGS_PATH)
	GameEvents.log_event("xr_height_offset", {"meters": snappedf(height_offset, 0.01)})


func _pressed_once(key: String, down: bool) -> bool:
	var was: bool = _was_pressed.get(key, false)
	_was_pressed[key] = down
	return down and not was


static func next_element(current: String) -> String:
	var i := Elements.ALL.find(current)
	return Elements.ALL[(i + 1) % Elements.ALL.size()]


## Dominant-hand helpers for combat and comfort settings
func get_dominant_holder() -> WeaponHolder:
	return left_holder if dominant_hand == "left" else right_holder


func get_offhand_holder() -> WeaponHolder:
	return right_holder if dominant_hand == "left" else left_holder


func get_dominant_controller() -> XRController3D:
	return left_controller if dominant_hand == "left" else right_controller


func get_offhand_controller() -> XRController3D:
	return right_controller if dominant_hand == "left" else left_controller


func _get_movement_direct() -> Node:
	return find_child("*MovementDirect*", true, false)


func _get_movement_turn() -> Node:
	return find_child("*MovementTurn*", true, false)


func _get_turn_controller() -> XRController3D:
	var turn := _get_movement_turn()
	if turn and turn.get_parent() is XRController3D:
		return turn.get_parent() as XRController3D
	return right_controller


func _get_vignette() -> Node:
	return find_child("*Vignette*", true, false)


func set_dominant_hand(hand: String) -> void:
	var h := hand.to_lower()
	if h != "left" and h != "right":
		return
	dominant_hand = h
	var direct := _get_movement_direct()
	var turn := _get_movement_turn()
	if direct and turn:
		if dominant_hand == "left":
			# Left-dominant: move with right stick, turn with left stick
			if direct.get_parent() != right_controller and right_controller != null:
				direct.reparent(right_controller)
			if turn.get_parent() != left_controller and left_controller != null:
				turn.reparent(left_controller)
		else:
			# Right-dominant: move with left stick, turn with right stick
			if direct.get_parent() != left_controller and left_controller != null:
				direct.reparent(left_controller)
			if turn.get_parent() != right_controller and right_controller != null:
				turn.reparent(right_controller)


## Scripted rig moves (run intro hover, respawn on the seal): XR Tools'
## PlayerBody applies gravity to the origin every physics frame, so it
## would pull a hover back down. Locking only freezes the body and the
## locomotion providers. It deliberately does NOT touch the origin
## transform or teleport the body.
func set_rig_locked(locked: bool) -> void:
	var body := _body()
	if body:
		body.set("enabled", not locked)
		if not locked:
			body.set("velocity", Vector3.ZERO)
	var direct := _get_movement_direct()
	if direct:
		direct.set("enabled", not locked)
	var turn := _get_movement_turn()
	if turn:
		turn.set("enabled", not locked)


## Smooth-locomotion and snap-turn providers on/off (the pause menu turns them
## off so a paused player cannot walk or turn away from the panel).
func set_locomotion_enabled(enabled: bool) -> void:
	var direct := _get_movement_direct()
	if direct:
		direct.set("enabled", enabled)
	var turn := _get_movement_turn()
	if turn:
		turn.set("enabled", enabled)


## Scales the smooth-locomotion top speed (1.0 = XR Tools default); used by
## Abyssal Sea's ink speed boost.
func set_move_speed_scale(scale: float) -> void:
	_move_scale = scale
	_apply_move_speed()


## The player's walking pace from Settings > MOVEMENT (1.0 = default). Stacks
## with the ink boost, so the two never overwrite each other.
func set_walk_scale(pace: float) -> void:
	walk_scale = pace
	_apply_move_speed()


func _apply_move_speed() -> void:
	var direct := _get_movement_direct()
	if direct == null:
		return
	if _base_move_speed < 0.0:
		_base_move_speed = float(direct.get("max_speed"))
	direct.set("max_speed", _base_move_speed * walk_scale * _move_scale)


func get_move_speed() -> float:
	var direct := _get_movement_direct()
	return float(direct.get("max_speed")) if direct else 0.0


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


func _body() -> Node3D:
	return get_node_or_null("XROrigin3D/PlayerBody") as Node3D
