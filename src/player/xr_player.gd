class_name XRPlayer
extends Node3D
## VR player rig: XR Tools origin, camera, hands, smooth locomotion (left stick),
## snap turn (right stick) and a [WeaponHolder] in each hand.
## A/X: [signal reset_requested]. B/Y tap without grip: [signal toggle_attacks_requested]
## (with grip, B/Y recalls a weapon, see WeaponHolder). Thumbstick click:
## cycle the element of the weapon in that hand.
## View: hold B/Y for 0.6 s to recenter on the headset; hold B and push the
## right stick up / down to raise or lower your eye height (saved).

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


func _ready() -> void:
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


func _process(_delta: float) -> void:
	if _pressed_once("ax", left_controller.is_button_pressed("ax_button") or right_controller.is_button_pressed("ax_button")):
		reset_requested.emit()
	for c in [left_controller, right_controller]:
		var gripping: bool = c.get_float("grip") > 0.6
		_step_view_button(c, gripping, _delta)
		if _pressed_once("click_" + c.name, c.is_button_pressed("primary_click")):
			var holder := left_holder if c == left_controller else right_holder
			if run_element_mode:
				element_ability_requested.emit(Vector3.ZERO)
			elif holder.held:
				holder.held.set_element(next_element(holder.held.element))


## B/Y without grip: tap = toggle_attacks_requested, hold = recenter, hold B +
## right stick up/down = eye height.
func _step_view_button(c: XRController3D, gripping: bool, delta: float) -> void:
	var key := String(c.name)
	var down := c.is_button_pressed("by_button") and not gripping
	if down:
		var t: float = _by_time.get(key, 0.0) + delta
		_by_time[key] = t
		if c == right_controller:
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
	height_offset = clampf(height_offset + delta_m, -HEIGHT_LIMIT, HEIGHT_LIMIT)
	_apply_height()


func _apply_height() -> void:
	var body := _body()
	if body:
		body.set("player_height_offset", height_offset)


func _load_view_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(VIEW_SETTINGS_PATH) == OK:
		height_offset = clampf(float(cfg.get_value("view", "height_offset", 0.0)), -HEIGHT_LIMIT, HEIGHT_LIMIT)


func _save_view_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("view", "height_offset", height_offset)
	cfg.save(VIEW_SETTINGS_PATH)
	GameEvents.log_event("xr_height_offset", {"meters": snappedf(height_offset, 0.01)})


func _body() -> Node3D:
	return get_node_or_null("XROrigin3D/PlayerBody") as Node3D


func _pressed_once(key: String, pressed: bool) -> bool:
	var was: bool = _was_pressed.get(key, false)
	_was_pressed[key] = pressed
	return pressed and not was


## Scripted rig moves (run intro hover, respawn on the seal): XR Tools'
## PlayerBody applies gravity to the origin every physics frame, so it
## would pull a hover back down. Locking only freezes the body and the
## locomotion providers. It deliberately does NOT touch the origin
## transform or teleport the body: resetting the origin to identity threw
## away the body's seating under the headset (a camera snap at lock and
## again at unlock, and the eye ending up wherever the body re-seated),
## and teleporting the body to the rig root made it yank the origin —
## and the camera — sideways on the next physics frame.
func set_rig_locked(locked: bool) -> void:
	var body := _body()
	if body:
		body.set("enabled", not locked)
		if not locked:
			body.set("velocity", Vector3.ZERO)
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
