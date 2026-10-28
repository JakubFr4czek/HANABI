class_name PauseController
extends Node
## Opens and closes the skill-tree menu and owns the pause around it
## (docs/ELEMENTS_PLAN.md (e), Phase E2d).
##
## Pausing is get_tree().paused, never Engine.time_scale = 0: the XR rig, the
## hands, the pointer and the menu keep processing (process_mode ALWAYS) so the
## player can look around and point; yōkai, waves, the element timer,
## cooldowns, the run clock and player regeneration stand still. On top of that:
## - [TimeController] parks its effects (a parry slow-mo resumes with exactly
##   the time it had left) and Engine.time_scale reads 1.0 meanwhile;
## - the held katana is frozen kinematic and glued to the hand;
## - XR locomotion and snap turn are off, desktop walking too;
## - particle emitters stop (speed_scale 0); music gets the 750 Hz low-pass;
## - the panel is placed with [UiPlacement] so it never intersects geometry.
##
## Left Menu button (tap) or Tab / M toggles, Esc and the close button close.

signal opened
signal closed

const TRIGGER_PRESS := 0.72
const TRIGGER_RELEASE := 0.4

var run_game: RunGame
var player: Node3D
var katana: HeldWeapon
var menu: SkillTreeMenu
var is_open := false
## The pose the last open used (UiPlacement.place result).
var last_pose: Dictionary = {}

var _katana_was_frozen := false
var _katana_freeze_mode := RigidBody3D.FREEZE_MODE_STATIC
var _frozen_emitters: Dictionary = {}  # Node -> speed_scale before the pause
var _trigger_down := {"left": false, "right": false}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(game: RunGame, p_player: Node3D, p_katana: HeldWeapon) -> void:
	run_game = game
	player = p_player
	katana = p_katana
	menu = SkillTreeMenu.new()
	menu.name = "SkillTreeMenu"
	add_child(menu)
	menu.close_requested.connect(close)
	menu.haptic_sink = _haptic
	if game.has_signal("run_started") and not game.run_started.is_connected(close):
		game.run_started.connect(close)
	if game.has_signal("run_ended") and not game.run_ended.is_connected(_on_run_ended):
		game.run_ended.connect(_on_run_ended)


## Menus open only mid-fight: not in the intro, on a level-up choice or after death.
func can_open() -> bool:
	return run_game != null and run_game.state == RunGame.RunState.PLAYING and not is_open


func toggle() -> void:
	if is_open:
		close()
	elif can_open():
		open()


func open() -> void:
	if not can_open():
		return
	var pose := _compute_pose()
	last_pose = pose
	is_open = true
	TimeController.suspend()
	get_tree().paused = true
	_freeze_katana()
	_freeze_emitters()
	_set_locomotion(false)
	Sfx.set_pause_ducking(true)
	var blade_el := Elements.NONE
	var blade_left := 0.0
	if run_game.element_system:
		blade_el = run_game.element_system.current_element
		blade_left = run_game.element_system.element_time_remaining
	menu.open(run_game, pose, blade_el, blade_left, _hint_text())
	Sfx.play_at("ofuda_slice", pose.transform.origin, -12.0, 4.0, 0.85)
	GameEvents.log_event("skill_menu_opened", {"ofuda": run_game.ofuda_count, "blocked": bool(pose.blocked), "distance": snappedf(float(pose.distance), 0.01)})
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	menu.close()
	_set_locomotion(true)
	_thaw_emitters()
	_thaw_katana()
	get_tree().paused = false
	TimeController.resume()
	Sfx.set_pause_ducking(false)
	Sfx.play_at("ofuda_slice", _head_position(), -14.0, 4.0, 0.7)
	GameEvents.log_event("skill_menu_closed", {})
	closed.emit()


func _on_run_ended(_summary: Dictionary) -> void:
	close()


func _input(event: InputEvent) -> void:
	# Menu hotkeys: handled here, before the rig and the weapon switch see them.
	if not is_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = (event as InputEventKey).physical_keycode
	match key:
		KEY_ESCAPE:
			close()
		KEY_1, KEY_2, KEY_3, KEY_4:
			menu.select_element(Elements.COMBAT_ELEMENTS[key - KEY_1])
		KEY_5, KEY_C:
			menu.select_settings()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			menu.unlock_selected("mouse")
		_:
			return
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_open:
		return
	if run_game.state != RunGame.RunState.PLAYING:
		close()
		return
	_follow_katana()
	_feed_pointers()


# --- Placement ---------------------------------------------------------------------

func _head() -> Node3D:
	return get_tree().get_first_node_in_group("player_head") as Node3D


func _head_position() -> Vector3:
	var h := _head()
	return h.global_position if h else Vector3(0.0, 1.6, 0.0)


func _compute_pose() -> Dictionary:
	var head := _head()
	var head_pos := head.global_position if head else Vector3(0.0, 1.65, 0.0)
	var heading := -head.global_basis.z if head else Vector3.FORWARD
	if absf(heading.y) > 0.9:  # looking straight up or down: use the body's way
		heading = run_game._player_forward_direction()
	var ground := Callable()
	if run_game.forest_world:
		ground = run_game.forest_world.height_at
	var holder: Node3D = head if head else (run_game as Node3D)
	var space: PhysicsDirectSpaceState3D = holder.get_world_3d().direct_space_state
	return UiPlacement.place(space, head_pos, heading, SkillTreeMenu.PANEL_SIZE, ground)


# --- Freezing ----------------------------------------------------------------------

func _freeze_katana() -> void:
	if katana == null:
		return
	_katana_was_frozen = katana.freeze
	_katana_freeze_mode = katana.freeze_mode
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	katana.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	katana.freeze = true


## While paused the blade rides the hand exactly: no physics, no lag, no jitter.
func _follow_katana() -> void:
	if katana == null or not katana.is_held():
		return
	katana.global_transform = katana._compute_target_transform()


func _thaw_katana() -> void:
	if katana == null:
		return
	katana.freeze = _katana_was_frozen
	katana.freeze_mode = _katana_freeze_mode
	if katana.is_held():
		katana.snap_to_hand()
	else:
		katana.linear_velocity = Vector3.ZERO
		katana.angular_velocity = Vector3.ZERO


func _freeze_emitters() -> void:
	_frozen_emitters.clear()
	var root := get_tree().root
	for n in root.find_children("*", "GPUParticles3D", true, false):
		if not menu.is_ancestor_of(n):
			_frozen_emitters[n] = (n as GPUParticles3D).speed_scale
			(n as GPUParticles3D).speed_scale = 0.0
	for n in root.find_children("*", "CPUParticles3D", true, false):
		if not menu.is_ancestor_of(n):
			_frozen_emitters[n] = (n as CPUParticles3D).speed_scale
			(n as CPUParticles3D).speed_scale = 0.0


func _thaw_emitters() -> void:
	for n in _frozen_emitters:
		if is_instance_valid(n):
			n.set("speed_scale", _frozen_emitters[n])
	_frozen_emitters.clear()


func _set_locomotion(enabled: bool) -> void:
	if player is XRPlayer:
		(player as XRPlayer).set_locomotion_enabled(enabled)


# --- Pointers ----------------------------------------------------------------------

func _feed_pointers() -> void:
	if player is XRPlayer:
		var xr := player as XRPlayer
		for side in ["left", "right"]:
			var c := xr.left_controller if side == "left" else xr.right_controller
			if c == null or not c.get_is_active():
				menu.hide_pointer(side)
				continue
			var value := c.get_float("trigger")
			var down: bool = _trigger_down[side]
			down = value > TRIGGER_PRESS or (down and value > TRIGGER_RELEASE)
			_trigger_down[side] = down
			menu.update_pointer(side, c.global_position, -c.global_basis.z, down)
	elif player is DesktopPlayer:
		var cam := (player as DesktopPlayer).camera
		var origin := cam.global_position
		var dir := -cam.global_basis.z
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and cam.get_viewport():
			var mp := cam.get_viewport().get_mouse_position()
			origin = cam.project_ray_origin(mp)
			dir = cam.project_ray_normal(mp)
		menu.update_pointer("mouse", origin, dir, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), false)


func _haptic(pointer_id: String, amplitude: float, seconds: float) -> void:
	if player is XRPlayer:
		var xr := player as XRPlayer
		var holder := xr.left_holder if pointer_id == "left" else xr.right_holder
		if holder:
			holder.pulse(amplitude, seconds)


func _hint_text() -> String:
	if player is XRPlayer:
		return "TRIGGER  select   ·   MENU  close"
	return "CLICK  select   ·   1-4  school   ·   5/C  settings   ·   ENTER  unlock   ·   ESC  close"
