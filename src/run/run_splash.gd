class_name RunSplash
extends Node3D
## Boot splash (D7), played once at launch before the seiza intro: HANABI (a
## firework over the wordmark), a black gap, then the NANJO studio logo.
## Both boards stand world-locked about 3 m in front of the player at eye
## height, drawn on their own visual layer. While they play the camera culls
## everything else and sees a black environment, so no forest, sky, rain or
## hands show through. Time advances by the frame delta only; nothing here
## touches Engine.time_scale.

signal finished

const BOARD_DISTANCE := 3.0
## Visual layer 20: the boards draw here and the camera's cull mask keeps only it.
const SPLASH_LAYER := 1 << 19
const TRIGGER_THRESHOLD := 0.5
const FIREWORK_TEX := preload("res://assets/ui/splash/firework_transparent.png")
const NANJO_TEX := preload("res://assets/ui/splash/nanjo_logo_transparent.png")
const NANJO_SHADER := preload("res://src/shaders/splash_logo.gdshader")
const FONT := preload("res://assets/fonts/Cinzel-Variable.ttf")
const POP_SFX := preload("res://assets/audio/sfx/kenney_run/firework_pop_soft_000.ogg")

## Board layout in metres, centred on the eye-height anchor.
const FIREWORK_SIZE := 1.5
const FIREWORK_Y := 0.45
const FIREWORK_START_SCALE := 0.9
const WORDMARK_TEXT := "HANABI"
const WORDMARK_Y := -0.45
const WORDMARK_FONT_SIZE := 220
const WORDMARK_PIXEL_SIZE := 0.0014
const WORDMARK_SPACING := 18
const NANJO_WIDTH := 2.0
## The logo unveils from the top down past 1.0 so the bottom edge fully appears.
const NANJO_REVEAL_END := 1.1

## Timeline in seconds: fade in, hold, fade out (HANABI), then a black gap and
## the NANJO board on the same timing scheme.
const HANABI_IN := 0.6
const HANABI_HOLD := 2.5
const HANABI_OUT := 0.6
const BLACK_GAP := 0.3
const NANJO_IN := 0.8
const NANJO_HOLD := 2.0
const NANJO_OUT := 0.8
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
var _firework: MeshInstance3D
var _firework_mat: StandardMaterial3D
var _wordmark: Label3D
var _nanjo: MeshInstance3D
var _nanjo_mat: ShaderMaterial
var _void_env: Environment
var _pop: AudioStreamPlayer
var _saved_cull_mask := 0
var _saved_environment: Environment
var _xr_was_down := false


func _ready() -> void:
	visible = false
	set_process(false)
	_build_visuals()


func setup(player: Node3D) -> void:
	_player = player


func is_active() -> bool:
	return active


func start() -> void:
	if active or _player == null:
		return
	active = true
	_skip_t = -1.0
	_camera = get_viewport().get_camera_3d()
	_place_boards()
	_hide_world()
	_lock_rig(true)
	_xr_was_down = _xr_down()
	visible = true
	set_process(true)
	GameEvents.log_event("boot_splash_started", {})
	_enter_phase(Phase.HANABI)
	_show_phase()


## Ends both boards at once with a short fade; the intro starts after it.
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
		match _phase:
			Phase.HANABI:
				if _phase_t >= HANABI_IN + HANABI_HOLD + HANABI_OUT:
					_enter_phase(Phase.GAP)
			Phase.GAP:
				if _phase_t >= BLACK_GAP:
					_enter_phase(Phase.NANJO)
			Phase.NANJO:
				if _phase_t >= NANJO_IN + NANJO_HOLD + NANJO_OUT:
					_finish(false)
					return
	_show_phase()


func _enter_phase(next: Phase) -> void:
	_phase = next
	_phase_t = 0.0
	match next:
		Phase.HANABI:
			GameEvents.log_event("boot_splash_board", {"board": "hanabi"})
			_pop.play()
		Phase.NANJO:
			GameEvents.log_event("boot_splash_board", {"board": "nanjo"})


func _show_phase() -> void:
	var skip_fade := 1.0 if _skip_t < 0.0 else clampf(1.0 - _skip_t / SKIP_FADE, 0.0, 1.0)
	_firework.visible = _phase == Phase.HANABI
	_wordmark.visible = _phase == Phase.HANABI
	_nanjo.visible = _phase == Phase.NANJO
	match _phase:
		Phase.HANABI:
			var hanabi_alpha := _fade(_phase_t, HANABI_IN, HANABI_HOLD, HANABI_OUT) * skip_fade
			# The firework blooms from a little smaller while it fades in.
			var bloom := 1.0 - pow(1.0 - clampf(_phase_t / HANABI_IN, 0.0, 1.0), 3.0)
			_firework.scale = Vector3.ONE * lerpf(FIREWORK_START_SCALE, 1.0, bloom)
			_firework_mat.albedo_color = Color(1.0, 1.0, 1.0, hanabi_alpha)
			_wordmark.modulate = Color(1.0, 1.0, 1.0, hanabi_alpha)
		Phase.NANJO:
			var reveal := NANJO_REVEAL_END * smoothstep(0.0, NANJO_IN, _phase_t)
			var hold_end := NANJO_IN + NANJO_HOLD
			var nanjo_alpha := (1.0 - smoothstep(hold_end, hold_end + NANJO_OUT, _phase_t)) * skip_fade
			_nanjo_mat.set_shader_parameter("reveal", reveal)
			_nanjo_mat.set_shader_parameter("alpha", nanjo_alpha)


## Fade envelope: rises over [param fade_in], holds, then falls over [param fade_out].
static func _fade(t: float, fade_in: float, hold: float, fade_out: float) -> float:
	if t < fade_in:
		return smoothstep(0.0, fade_in, t)
	if t < fade_in + hold:
		return 1.0
	return 1.0 - smoothstep(0.0, fade_out, t - fade_in - hold)


func _finish(skipped: bool) -> void:
	active = false
	set_process(false)
	visible = false
	_restore_world()
	_lock_rig(false)
	GameEvents.log_event("boot_splash_finished", {"skipped": skipped})
	_veil_from_black()
	finished.emit()


## Places the boards 3 m ahead of the camera, at its eye height, facing it.
## Only yaw is taken from the head, so the horizon stays level.
func _place_boards() -> void:
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


func _hide_world() -> void:
	if _camera == null:
		return
	_saved_cull_mask = _camera.cull_mask
	_saved_environment = _camera.environment
	_camera.cull_mask = SPLASH_LAYER
	_camera.environment = _void_env


func _restore_world() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	_camera.cull_mask = _saved_cull_mask
	_camera.environment = _saved_environment


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


func _build_visuals() -> void:
	_void_env = Environment.new()
	_void_env.background_mode = Environment.BG_COLOR
	_void_env.background_color = Color.BLACK
	_void_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_void_env.ambient_light_color = Color.BLACK
	_void_env.ambient_light_energy = 0.0

	_firework_mat = StandardMaterial3D.new()
	_firework_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_firework_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_firework_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_firework_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_firework_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_firework_mat.albedo_texture = FIREWORK_TEX
	_firework = _board_quad(Vector2.ONE * FIREWORK_SIZE, _firework_mat, Vector3(0.0, FIREWORK_Y, 0.0))

	var font := FontVariation.new()
	font.base_font = FONT
	font.spacing_glyph = WORDMARK_SPACING
	_wordmark = Label3D.new()
	_wordmark.text = WORDMARK_TEXT
	_wordmark.font = font
	_wordmark.font_size = WORDMARK_FONT_SIZE
	_wordmark.pixel_size = WORDMARK_PIXEL_SIZE
	_wordmark.outline_size = 0
	_wordmark.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_wordmark.position = Vector3(0.0, WORDMARK_Y, 0.0)
	_wordmark.layers = SPLASH_LAYER
	add_child(_wordmark)

	_nanjo_mat = ShaderMaterial.new()
	_nanjo_mat.shader = NANJO_SHADER
	_nanjo_mat.set_shader_parameter("logo_tex", NANJO_TEX)
	_nanjo_mat.set_shader_parameter("alpha", 0.0)
	_nanjo_mat.set_shader_parameter("reveal", 0.0)
	var aspect := float(NANJO_TEX.get_height()) / float(NANJO_TEX.get_width())
	_nanjo = _board_quad(Vector2(NANJO_WIDTH, NANJO_WIDTH * aspect), _nanjo_mat, Vector3.ZERO)

	_pop = AudioStreamPlayer.new()
	_pop.stream = POP_SFX
	_pop.volume_db = -10.0
	add_child(_pop)


func _board_quad(size: Vector2, mat: Material, pos: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = mat
	mesh.position = pos
	mesh.layers = SPLASH_LAYER
	add_child(mesh)
	return mesh


## Holds the player still while the boards play; the intro takes over after.
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
