class_name SpectatorCamera
extends Node
## N10: demo-recording camera for the desktop window (PCVR and the desktop rig). A second
## camera in its own 16:9 SubViewport follows the player's head through a filter: position
## and yaw/pitch are smoothed, roll is always zero (level horizon), FOV 80°. The headset
## keeps rendering its own eyes; only the window shows this view. Off by default.
##   F7  cycles: off -> first person (smoothed) -> third person (over the shoulder) -> off
##   F9  "clean frame": hides the debug/perf HUD on the window (wrist HUD, Oni bubble stay)
##   --spectator=fp|tp, --clean-frame on the command line start in that state.
## Never created on Quest/Android (see [method platform_ok]). See docs/DEMO_RECORDING.md.

enum Mode { OFF, FIRST_PERSON, THIRD_PERSON }

const MODE_KEY := KEY_F7
const CLEAN_KEY := KEY_F9
const FOV := 80.0
const VIEW_SIZE := Vector2i(1280, 720)
## Position filter rate (1/s): a 10 cm head jump moves the camera ~0.7 cm in a 72 Hz frame.
const POS_RATE := 5.0
## Yaw/pitch filter rate (1/s).
const ROT_RATE := 3.5
## Pitch is kept within this (degrees) so a look at the floor does not swing the video.
const MAX_PITCH := 35.0
## Third person: boom from the head (back, up, right of the shoulder), metres.
const TP_BACK := 2.3
const TP_UP := 0.45
const TP_RIGHT := 0.55
## Sphere kept clear of trunks/terrain around the third-person camera.
const TP_RADIUS := 0.25
## The boom grows back after an obstacle at this rate (1/s); shortening is immediate.
const TP_EXTEND_RATE := 2.5
## Static world the boom may not enter: terrain/props (1) and trunks (ForestWorld.TRUNK_LAYER).
const COLLISION_MASK := 1 | 64
## Groups whose nodes are debug/perf HUD hidden by the clean frame (QuestPerfOverlay joins it).
const DEBUG_GROUP := &"debug_hud"

var mode := Mode.OFF
var clean_frame := false
## Head to follow; null = the first node in "player_head" (XRCamera3D or the desktop camera).
var head_override: Node3D = null
var viewport: SubViewport
var camera: Camera3D
var _display: CanvasLayer
var _rect: TextureRect
var _attached_to_screen := false
var _pos := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _boom := TP_BACK
var _primed := false
var _hidden_debug: Array[Node] = []


## True on PC builds; false on Quest/Android/mobile (feature tags), so the spectator never costs
## a second render there.
static func platform_ok(features: PackedStringArray = PackedStringArray()) -> bool:
	if features.is_empty():
		for f in ["android", "mobile", "web"]:
			if OS.has_feature(f):
				return false
		return true
	return not (features.has("android") or features.has("mobile") or features.has("web"))


## Adds the spectator under [param root] when the platform allows it; returns it (or null).
static func attach_if_supported(root: Node, features: PackedStringArray = PackedStringArray()) -> SpectatorCamera:
	if not platform_ok(features):
		return null
	var existing := root.get_node_or_null("SpectatorCamera") as SpectatorCamera
	if existing:
		return existing
	var s := SpectatorCamera.new()
	s.name = "SpectatorCamera"
	root.add_child(s)
	return s


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "SpectatorView"
	viewport.size = VIEW_SIZE
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.audio_listener_enable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	camera = Camera3D.new()
	camera.name = "SpectatorCam"
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 400.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	viewport.add_child(camera)
	camera.current = true
	var args := OS.get_cmdline_user_args()
	if args.has("--clean-frame"):
		set_clean_frame(true)
	if args.has("--spectator=tp"):
		set_mode(Mode.THIRD_PERSON)
	elif args.has("--spectator=fp") or args.has("--spectator"):
		set_mode(Mode.FIRST_PERSON)
	else:
		_apply_mode()


func _exit_tree() -> void:
	if mode != Mode.OFF:
		mode = Mode.OFF
		_apply_mode()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		MODE_KEY:
			set_mode(((mode + 1) % 3) as Mode)
			get_viewport().set_input_as_handled()
		CLEAN_KEY:
			set_clean_frame(not clean_frame)
			get_viewport().set_input_as_handled()


func set_mode(m: Mode) -> void:
	if m != Mode.OFF and mode == Mode.OFF:
		_primed = false
	mode = m
	_apply_mode()
	if m != Mode.OFF:
		GameEvents.log_event("spectator_mode", {"mode": ["off", "fp", "tp"][m]})


func set_clean_frame(on: bool) -> void:
	clean_frame = on
	if on:
		for n in get_tree().get_nodes_in_group(DEBUG_GROUP):
			if n is CanvasItem and (n as CanvasItem).visible:
				(n as CanvasItem).visible = false
				_hidden_debug.append(n)
			elif n is CanvasLayer and (n as CanvasLayer).visible:
				(n as CanvasLayer).visible = false
				_hidden_debug.append(n)
			elif n is Node3D and (n as Node3D).visible:
				(n as Node3D).visible = false
				_hidden_debug.append(n)
	else:
		for n in _hidden_debug:
			if is_instance_valid(n):
				n.set("visible", true)
		_hidden_debug.clear()


func is_active() -> bool:
	return mode != Mode.OFF


## The window shows the spectator: on PCVR the SubViewport is blitted to the screen in place of
## the left-eye mirror; on desktop a full-window TextureRect shows it under the debug overlays.
func _apply_mode() -> void:
	if viewport == null:
		return
	var on := mode != Mode.OFF
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_physics_process(on)
	var main := get_viewport()
	if main == null:
		return
	if main.use_xr:
		_set_screen_attach(on)
	else:
		if on and _display == null:
			_display = CanvasLayer.new()
			_display.name = "SpectatorDisplay"
			_display.layer = 64
			_rect = TextureRect.new()
			_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_rect.texture = viewport.get_texture()
			_display.add_child(_rect)
			add_child(_display)
		if _display:
			_display.visible = on


func _set_screen_attach(on: bool) -> void:
	var main := get_viewport()
	var win_size := Vector2(DisplayServer.window_get_size())
	if on:
		# Letterbox the 16:9 view into the window; the XR viewport stops mirroring the eye.
		var s := minf(win_size.x / VIEW_SIZE.x, win_size.y / VIEW_SIZE.y)
		var sz := Vector2(VIEW_SIZE) * s
		RenderingServer.viewport_attach_to_screen(main.get_viewport_rid(), Rect2(), DisplayServer.INVALID_WINDOW_ID)
		RenderingServer.viewport_attach_to_screen(viewport.get_viewport_rid(), Rect2((win_size - sz) * 0.5, sz), DisplayServer.MAIN_WINDOW_ID)
		_attached_to_screen = true
	elif _attached_to_screen:
		RenderingServer.viewport_attach_to_screen(viewport.get_viewport_rid(), Rect2(), DisplayServer.INVALID_WINDOW_ID)
		RenderingServer.viewport_attach_to_screen(main.get_viewport_rid(), Rect2(Vector2.ZERO, win_size), DisplayServer.MAIN_WINDOW_ID)
		_attached_to_screen = false


func _head() -> Node3D:
	if head_override and is_instance_valid(head_override):
		return head_override
	return get_tree().get_first_node_in_group("player_head") as Node3D


func _physics_process(delta: float) -> void:
	step(delta)


## One filter step (public for tests: fixed delta, no real-time waits).
func step(delta: float) -> void:
	var head := _head()
	if head == null or not head.is_inside_tree() or mode == Mode.OFF:
		return
	var hp := head.global_position
	var f := -head.global_basis.z
	var yaw := atan2(-f.x, -f.z)
	var pitch := clampf(asin(clampf(f.y, -1.0, 1.0)), -deg_to_rad(MAX_PITCH), deg_to_rad(MAX_PITCH))
	if not _primed:
		_pos = hp
		_yaw = yaw
		_pitch = pitch
		_boom = TP_BACK
		_primed = true
	else:
		_pos = _pos.lerp(hp, 1.0 - exp(-POS_RATE * delta))
		var kr := 1.0 - exp(-ROT_RATE * delta)
		_yaw = lerp_angle(_yaw, yaw, kr)
		_pitch = lerpf(_pitch, pitch, kr)
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	if mode == Mode.FIRST_PERSON:
		camera.global_transform = Transform3D(basis, _pos)
		return
	# Third person: a boom behind the right shoulder, level, shortened by a sphere cast.
	var flat_basis := Basis.from_euler(Vector3(0.0, _yaw, 0.0))
	var dir := (flat_basis.z * TP_BACK + flat_basis.x * TP_RIGHT + Vector3.UP * TP_UP).normalized()
	var full := Vector3(TP_BACK, TP_UP, TP_RIGHT).length()
	var allowed := _clear_length(_pos, dir, full)
	if allowed < _boom:
		_boom = allowed
	else:
		_boom = minf(allowed, lerpf(_boom, allowed, 1.0 - exp(-TP_EXTEND_RATE * delta)))
	var cam_pos := _pos + dir * _boom
	var look_pitch := _pitch * 0.6 - deg_to_rad(8.0)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(look_pitch, _yaw, 0.0)), cam_pos)


## Free length along [param dir] from [param from] for a TP_RADIUS sphere (static world only).
func _clear_length(from: Vector3, dir: Vector3, full: float) -> float:
	var world := camera.get_world_3d()
	if world == null:
		return full
	var space := world.direct_space_state
	if space == null:
		return full
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TP_RADIUS
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = dir * full
	q.collision_mask = COLLISION_MASK
	q.collide_with_areas = false
	var r := space.cast_motion(q)
	if r.size() < 2:
		return full
	return maxf(0.0, full * r[0] - 0.05)
