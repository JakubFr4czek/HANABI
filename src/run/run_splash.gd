class_name RunSplash
extends Node3D
## Boot splash (D7), played once at launch before the seiza intro: the HANABI
## film (a firework over the wordmark), a black gap, then the NANJO studio film.
## Both are 1280x720 Theora clips in assets/splash/ (30 fps, no sound). A
## VideoStreamPlayer draws each clip into a SubViewport, and an unshaded board
## shows that viewport. On desktop the board covers the window; in VR it is a
## fixed panel, world-locked and yaw-only, about 3.5 m ahead at eye height. While
## a film plays the camera culls everything else and sees a black environment
## with no fog, glow or camera effects, so no forest, sky, rain or hands show
## through. The rain, forest wind and thunder buses are muted while the films
## play, so the splash is silent until the intro. Time advances by the frame
## delta only; nothing here touches Engine.time_scale.

signal finished

## Distance from the eye to the board, in metres.
const BOARD_DISTANCE := 3.5
## VR panel width in metres: about 69 degrees across at BOARD_DISTANCE, a cinema-sized
## screen that still leaves the edges of a headset's view black.
const VR_BOARD_WIDTH := 4.8
const VIDEO_SIZE := Vector2i(1280, 720)
const VIDEO_ASPECT := 16.0 / 9.0
## Visual layer 20: the board draws here and the camera's cull mask keeps only it.
const SPLASH_LAYER := 1 << 19
const TRIGGER_THRESHOLD := 0.5
const HANABI_CLIP := preload("res://assets/splash/hanabi.ogv")
const NANJO_CLIP := preload("res://assets/splash/nanjo.ogv")
const POP_SFX := preload("res://assets/audio/sfx/kenney_run/firework_pop_soft_000.ogg")
## The firework bursts 0.93 s into the HANABI film; the pop plays on the burst.
const BURST_AT := 0.93
## Black between the two films, in seconds.
const BLACK_GAP := 0.3
## A skip (trigger, A/X, Space, Enter, Esc or mouse) fades the board out this fast.
const SKIP_FADE := 0.4
## The intro fades up from black over this long after the splash hands over.
const VEIL_FADE := 0.6

enum Phase { HANABI, GAP, NANJO }

var active := false

var _player: Node3D
var _camera: Camera3D
var _phase := Phase.HANABI
var _phase_t := 0.0
## Seconds since the skip press, or -1 while the timeline runs normally.
var _skip_t := -1.0
var _popped := false
var _viewport: SubViewport
var _video: VideoStreamPlayer
var _quad: QuadMesh
var _board: MeshInstance3D
var _board_mat: StandardMaterial3D
var _void_env: Environment
var _pop: AudioStreamPlayer
var _saved_cull_mask := 0
var _saved_environment: Environment
var _saved_attributes: CameraAttributes
var _xr_was_down := false
var _total_seconds := 0.0


func _ready() -> void:
	visible = false
	set_process(false)
	_build_visuals()


func setup(player: Node3D) -> void:
	_player = player


func is_active() -> bool:
	return active


## Which film is on screen: "hanabi", "gap" or "nanjo"; "" when the splash is not running.
func current_board() -> String:
	if not active:
		return ""
	return ["hanabi", "gap", "nanjo"][_phase]


## Seconds of the current film that have played.
func clip_position() -> float:
	return _video.stream_position


## Length of the whole splash in seconds: both films and the black gap.
func total_seconds() -> float:
	return _total_seconds


func start() -> void:
	if active or _player == null:
		return
	active = true
	_skip_t = -1.0
	_popped = false
	_camera = get_viewport().get_camera_3d()
	_place_board()
	_hide_world()
	_mute_world_audio(true)
	_lock_rig(true)
	_xr_was_down = _xr_down()
	visible = true
	set_process(true)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	GameEvents.log_event("boot_splash_started", {})
	_enter_phase(Phase.HANABI)
	_show_phase()


## Ends both films at once with a short fade; the intro starts after it.
func skip() -> void:
	if not active or _skip_t >= 0.0:
		return
	_skip_t = 0.0
	GameEvents.log_event("boot_splash_skipped", {"phase": Phase.keys()[_phase].to_lower()})


func _process(delta: float) -> void:
	if not active:
		return
	var down := _xr_down()
	if down and not _xr_was_down:
		skip()
	_xr_was_down = down
	_step(delta)


func _input(event: InputEvent) -> void:
	if not active:
		return
	var pressed := false
	if event is InputEventMouseButton:
		pressed = event.is_pressed()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		pressed = (event as InputEventKey).physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]
	if pressed:
		skip()
		get_viewport().set_input_as_handled()


func _step(delta: float) -> void:
	if _skip_t >= 0.0:
		_skip_t += delta
		if _skip_t >= SKIP_FADE:
			_finish(true)
			return
	else:
		_phase_t += delta
		if _phase == Phase.GAP and _phase_t >= BLACK_GAP:
			_enter_phase(Phase.NANJO)
		elif _phase == Phase.HANABI and not _popped and _video.stream_position >= BURST_AT:
			_popped = true
			_pop.play()
	_show_phase()


## A film that reaches its end moves the splash on: HANABI to the gap, NANJO to the intro.
func _on_clip_finished() -> void:
	if _skip_t >= 0.0:
		return
	match _phase:
		Phase.HANABI:
			_enter_phase(Phase.GAP)
		Phase.NANJO:
			_finish(false)


func _enter_phase(next: Phase) -> void:
	_phase = next
	_phase_t = 0.0
	match next:
		Phase.HANABI:
			GameEvents.log_event("boot_splash_board", {"board": "hanabi"})
			_play_clip(HANABI_CLIP)
		Phase.GAP:
			_video.stop()
		Phase.NANJO:
			GameEvents.log_event("boot_splash_board", {"board": "nanjo"})
			_play_clip(NANJO_CLIP)


func _play_clip(clip: VideoStream) -> void:
	_video.stream = clip
	_video.play()


func _show_phase() -> void:
	_board.visible = _phase != Phase.GAP
	# The skip fade darkens the film; the films themselves end on black.
	var brightness := 1.0 if _skip_t < 0.0 else clampf(1.0 - _skip_t / SKIP_FADE, 0.0, 1.0)
	_board_mat.albedo_color = Color(brightness, brightness, brightness)


func _exit_tree() -> void:
	if active:
		_mute_world_audio(false)


func _finish(skipped: bool) -> void:
	active = false
	set_process(false)
	visible = false
	_video.stop()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_restore_world()
	_mute_world_audio(false)
	_lock_rig(false)
	GameEvents.log_event("boot_splash_finished", {"skipped": skipped})
	_veil_from_black()
	finished.emit()


## Places the board BOARD_DISTANCE ahead of the camera, at its eye height, facing it.
## Only yaw is taken from the head, so the horizon stays level.
func _place_board() -> void:
	var eye: Vector3
	var forward: Vector3
	if _camera:
		eye = _camera.global_position
		forward = -_camera.global_basis.z
	else:
		eye = _player.global_position + Vector3(0.0, 1.6, 0.0)
		forward = -_player.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), eye + forward * BOARD_DISTANCE)
	_quad.size = _board_size()


## Desktop: the board covers the whole window at BOARD_DISTANCE, letterboxed in the
## black void when the window is not 16:9. VR and any other rig: the fixed VR panel.
func _board_size() -> Vector2:
	var width := VR_BOARD_WIDTH
	if _player is DesktopPlayer and _camera:
		var view := _camera.get_viewport().get_visible_rect().size
		var view_aspect := view.x / view.y
		var span := 2.0 * BOARD_DISTANCE * tan(deg_to_rad(_camera.fov) * 0.5)
		var frame_w := span * view_aspect if _camera.keep_aspect == Camera3D.KEEP_HEIGHT else span
		var frame_h := frame_w / view_aspect
		width = minf(frame_w, frame_h * VIDEO_ASPECT)
	return Vector2(width, width / VIDEO_ASPECT)


## The Ambience (rain, forest wind) and World (thunder, impacts) buses are silent
## under the films; they come back with the intro.
func _mute_world_audio(muted: bool) -> void:
	for bus in [Sfx.AMBIENCE_BUS, Sfx.WORLD_BUS]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_mute(idx, muted)


func _hide_world() -> void:
	if _camera == null:
		return
	_saved_cull_mask = _camera.cull_mask
	_saved_environment = _camera.environment
	_saved_attributes = _camera.attributes
	_camera.cull_mask = SPLASH_LAYER
	_camera.environment = _void_env
	_camera.attributes = null


func _restore_world() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	_camera.cull_mask = _saved_cull_mask
	_camera.environment = _saved_environment
	_camera.attributes = _saved_attributes


## A black veil on the camera fades out as the intro starts, so the forest
## comes up from black instead of popping in.
func _veil_from_black() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = Color.BLACK
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var veil := MeshInstance3D.new()
	veil.mesh = quad
	veil.material_override = mat
	veil.position = Vector3(0.0, 0.0, -0.2)
	_camera.add_child(veil)
	var tween := veil.create_tween()
	tween.tween_method(func(a: float) -> void: mat.albedo_color.a = a, 1.0, 0.0, VEIL_FADE)
	tween.tween_callback(veil.queue_free)


## Reads a film's length; the player is idle here, so the stream it keeps is harmless.
func _film_length(clip: VideoStream) -> float:
	_video.stream = clip
	return _video.get_stream_length()


func _build_visuals() -> void:
	_void_env = Environment.new()
	_void_env.background_mode = Environment.BG_COLOR
	_void_env.background_color = Color.BLACK
	_void_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_void_env.ambient_light_color = Color.BLACK
	_void_env.ambient_light_energy = 0.0
	_void_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

	_viewport = SubViewport.new()
	_viewport.size = VIDEO_SIZE
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_video = VideoStreamPlayer.new()
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.finished.connect(_on_clip_finished)
	_viewport.add_child(_video)
	_total_seconds = _film_length(HANABI_CLIP) + BLACK_GAP + _film_length(NANJO_CLIP)

	_board_mat = StandardMaterial3D.new()
	_board_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_board_mat.albedo_texture = _viewport.get_texture()
	_board_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_quad = QuadMesh.new()
	_board = MeshInstance3D.new()
	_board.mesh = _quad
	_board.material_override = _board_mat
	_board.layers = SPLASH_LAYER
	add_child(_board)

	_pop = AudioStreamPlayer.new()
	_pop.stream = POP_SFX
	_pop.volume_db = -10.0
	add_child(_pop)


## Holds the player still while the films play; the intro takes over after.
func _lock_rig(locked: bool) -> void:
	if _player is DesktopPlayer:
		(_player as DesktopPlayer).movement_locked = locked
	elif _player is XRPlayer:
		(_player as XRPlayer).set_rig_locked(locked)


func _xr_down() -> bool:
	var xr := _player as XRPlayer
	if xr == null:
		return false
	for c in [xr.left_controller, xr.right_controller]:
		if c and (c.is_button_pressed("ax_button") or c.get_float("trigger") > TRIGGER_THRESHOLD):
			return true
	return false
