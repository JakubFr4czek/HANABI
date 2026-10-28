extends Node
## Central repository and manager for VR settings: comfort, accessibility and
## audio (docs/GDD.md §14, docs/ELEMENTS_PLAN.md).
##
## Persists to `user://hanabi_vr.cfg`. Every save re-reads the file first and
## keeps the sections it does not own, so the pages never erase each other:
## - [view] eye height; [comfort] vignette, turning, dominant hand, seated, walk pace
## - [audio] Master / Music / SFX / Ambience volume, 0–100 % in 10 % steps
## - [access] lightning and firework flash strength, haptic strength
## - [body] body weight for the calorie estimate (D14), 40–150 kg in 5 kg steps
## It configures godot-xr-tools, the AudioServer buses (through [Sfx]) and the
## effects that read [method flash_scale] and [method haptic_amplitude].

signal settings_changed

const SETTINGS_PATH := "user://hanabi_vr.cfg"

const SNAP_ANGLES: Array[float] = [15.0, 30.0, 45.0, 60.0, 90.0]
const SMOOTH_SPEEDS: Array[float] = [1.0, 1.5, 2.0, 3.0, 4.0]
const VIGNETTE_STRENGTHS: Array[float] = [0.25, 0.50, 0.75, 1.00]
## Walking pace on top of the XR Tools default: slow / normal / fast.
const WALK_SCALES: Array[float] = [0.7, 1.0, 1.3]
const FLASH_LEVELS: Array[int] = [100, 50, 0]
const HAPTIC_LEVELS: Array[int] = [0, 50, 100]
const AUDIO_KEYS: Array[String] = ["master", "music", "sfx", "ambience"]
const VOLUME_STEP := 10
const WEIGHT_MIN := 40.0
const WEIGHT_MAX := 150.0
const WEIGHT_STEP := 5.0

const HEIGHT_MIN := -0.45
const HEIGHT_MAX := 0.80
const HEIGHT_STEP := 0.05
const SEATED_DEFAULT_BOOST := 0.35

var vignette_enabled: bool = true
var vignette_strength: float = 0.50
var snap_turning: bool = true
var snap_angle: float = 45.0
var smooth_turn_speed: float = 2.0
var walk_scale: float = 1.0
var dominant_hand: String = "right"
var seated_mode: bool = false
var seated_height: float = 0.35
var height_offset: float = 0.0
## Volumes in percent per bus key (AUDIO_KEYS).
var audio_percent: Dictionary = {"master": 100, "music": 100, "sfx": 100, "ambience": 100}
var flash_percent: int = 100
var haptic_percent: int = 100
## Body weight (kg) for the kcal estimate on the wrist ring (D14). An estimate, not a measure.
var body_weight_kg: float = 70.0

static var instance: VrComfortSettings = null


func _init() -> void:
	if instance == null:
		instance = self


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		apply_audio()
		return

	if cfg.has_section("view"):
		height_offset = clampf(float(cfg.get_value("view", "height_offset", height_offset)), HEIGHT_MIN, HEIGHT_MAX)

	if cfg.has_section("comfort"):
		vignette_enabled = bool(cfg.get_value("comfort", "vignette_enabled", vignette_enabled))
		vignette_strength = clampf(float(cfg.get_value("comfort", "vignette_strength", vignette_strength)), 0.0, 1.0)
		snap_turning = bool(cfg.get_value("comfort", "snap_turning", snap_turning))
		snap_angle = float(cfg.get_value("comfort", "snap_angle", snap_angle))
		smooth_turn_speed = float(cfg.get_value("comfort", "smooth_turn_speed", smooth_turn_speed))
		walk_scale = _snap_to(float(cfg.get_value("comfort", "walk_scale", walk_scale)), WALK_SCALES)
		dominant_hand = String(cfg.get_value("comfort", "dominant_hand", dominant_hand)).to_lower()
		if dominant_hand != "left" and dominant_hand != "right":
			dominant_hand = "right"
		seated_mode = bool(cfg.get_value("comfort", "seated_mode", seated_mode))
		seated_height = float(cfg.get_value("comfort", "seated_height", seated_height))
		if cfg.has_section_key("comfort", "height_offset"):
			height_offset = clampf(float(cfg.get_value("comfort", "height_offset", height_offset)), HEIGHT_MIN, HEIGHT_MAX)

	if cfg.has_section("audio"):
		for key in AUDIO_KEYS:
			audio_percent[key] = _snap_percent(cfg.get_value("audio", key, audio_percent[key]))

	if cfg.has_section("access"):
		flash_percent = int(_snap_to(float(cfg.get_value("access", "flash_percent", flash_percent)), FLASH_LEVELS))
		haptic_percent = int(_snap_to(float(cfg.get_value("access", "haptic_percent", haptic_percent)), HAPTIC_LEVELS))

	if cfg.has_section("body"):
		body_weight_kg = clampf(float(cfg.get_value("body", "weight_kg", body_weight_kg)), WEIGHT_MIN, WEIGHT_MAX)
	apply_audio()


func save_settings() -> void:
	# Keep the sections this call does not write (audio, access, other pages).
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("view", "height_offset", height_offset)

	cfg.set_value("comfort", "vignette_enabled", vignette_enabled)
	cfg.set_value("comfort", "vignette_strength", vignette_strength)
	cfg.set_value("comfort", "snap_turning", snap_turning)
	cfg.set_value("comfort", "snap_angle", snap_angle)
	cfg.set_value("comfort", "smooth_turn_speed", smooth_turn_speed)
	cfg.set_value("comfort", "walk_scale", walk_scale)
	cfg.set_value("comfort", "dominant_hand", dominant_hand)
	cfg.set_value("comfort", "seated_mode", seated_mode)
	cfg.set_value("comfort", "seated_height", seated_height)
	cfg.set_value("comfort", "height_offset", height_offset)

	for key in AUDIO_KEYS:
		cfg.set_value("audio", key, audio_percent[key])
	cfg.set_value("access", "flash_percent", flash_percent)
	cfg.set_value("access", "haptic_percent", haptic_percent)
	cfg.set_value("body", "weight_kg", body_weight_kg)

	var err := cfg.save(SETTINGS_PATH)
	if err == OK:
		GameEvents.log_event("vr_comfort_saved", {
			"vignette": vignette_enabled,
			"vignette_strength": vignette_strength,
			"snap_turning": snap_turning,
			"snap_angle": snap_angle,
			"smooth_turn_speed": smooth_turn_speed,
			"walk_scale": walk_scale,
			"dominant_hand": dominant_hand,
			"seated_mode": seated_mode,
			"height_offset": snappedf(height_offset, 0.01),
			"audio": audio_percent,
			"flash_percent": flash_percent,
			"haptic_percent": haptic_percent,
			"body_weight_kg": body_weight_kg,
		})
	settings_changed.emit()


## Applies current settings to an [XRPlayer] instance and XR Tools environment.
func apply_to_player(player: Node3D) -> void:
	if player == null:
		return

	# Height offset & body calibration
	if "height_offset" in player:
		player.height_offset = height_offset
	if player.has_method("_apply_height"):
		player._apply_height()
	elif player.has_method("_body"):
		var b = player._body()
		if b:
			b.set("player_height_offset", height_offset)

	# Dominant hand & locomotion assignment
	if player.has_method("set_dominant_hand"):
		player.set_dominant_hand(dominant_hand)
	if player.has_method("set_walk_scale"):
		player.set_walk_scale(walk_scale)

	# Movement turn settings
	var turn: Node = null
	if player.has_method("_get_movement_turn"):
		turn = player._get_movement_turn()
	else:
		turn = player.find_child("*MovementTurn*", true, false)

	if turn:
		if snap_turning:
			turn.set("turn_mode", 1)  # XRToolsMovementTurn.TurnMode.SNAP
			turn.set("step_turn_angle", snap_angle)
		else:
			turn.set("turn_mode", 2)  # XRToolsMovementTurn.TurnMode.SMOOTH
			turn.set("smooth_turn_speed", smooth_turn_speed)

	if XRToolsUserSettings:
		XRToolsUserSettings.snap_turning = snap_turning

	# Vignette configuration
	var vignette: Node = null
	if player.has_method("_get_vignette"):
		vignette = player._get_vignette()
	else:
		vignette = player.find_child("*Vignette*", true, false)

	if vignette:
		vignette.set("auto_adjust", vignette_enabled)
		# 0.0 strength = 0.65 inner radius (mild), 1.0 strength = 0.15 inner radius (strong)
		vignette.set("auto_inner_radius", lerp(0.65, 0.15, vignette_strength))
		var mesh: Node = vignette.get_node_or_null("Mesh")
		if vignette_enabled:
			if mesh:
				mesh.set("visible", true)
		else:
			vignette.set("radius", 1.0)
			if mesh:
				mesh.set("visible", false)


## Pushes the four volumes to the buses. Master and SFX are plain bus levels;
## Music and Ambience keep their slow-mo and pause ducks on top (see [Sfx]).
func apply_audio() -> void:
	if Sfx == null:
		return
	Sfx.set_bus_levels(
		audio_percent["master"] / 100.0,
		audio_percent["music"] / 100.0,
		audio_percent["sfx"] / 100.0,
		audio_percent["ambience"] / 100.0)


## Flash strength for the scene-wide lightning light and the firework lamps:
## 1.0 full, 0.5 softened, 0.0 none. Thunder and the bolt itself are unaffected.
func flash_scale() -> float:
	return flash_percent / 100.0


## Haptic amplitude after the player's strength setting (0 = no vibration).
func haptic_amplitude(amplitude: float) -> float:
	return amplitude * haptic_percent / 100.0


func set_volume_percent(key: String, percent: int) -> void:
	if not audio_percent.has(key):
		return
	audio_percent[key] = _snap_percent(percent)
	apply_audio()
	save_settings()


## One 10 % step up (+1) or down (-1) on a bus.
func step_volume(key: String, direction: int) -> void:
	if not audio_percent.has(key):
		return
	set_volume_percent(key, int(audio_percent[key]) + direction * VOLUME_STEP)


func set_flash_percent(percent: int) -> void:
	flash_percent = int(_snap_to(float(percent), FLASH_LEVELS))
	save_settings()


func set_haptic_percent(percent: int) -> void:
	haptic_percent = int(_snap_to(float(percent), HAPTIC_LEVELS))
	save_settings()


func adjust_body_weight(delta_kg: float) -> void:
	body_weight_kg = clampf(snappedf(body_weight_kg + delta_kg, WEIGHT_STEP), WEIGHT_MIN, WEIGHT_MAX)
	save_settings()


func set_walk_scale(pace: float, player: Node3D = null) -> void:
	walk_scale = _snap_to(pace, WALK_SCALES)
	if player:
		apply_to_player(player)
	save_settings()


func set_vignette_enabled(enabled: bool, player: Node3D = null) -> void:
	vignette_enabled = enabled
	if player:
		apply_to_player(player)
	save_settings()


func set_vignette_strength(strength: float, player: Node3D = null) -> void:
	vignette_strength = clampf(strength, 0.0, 1.0)
	if player:
		apply_to_player(player)
	save_settings()


func set_snap_turning(snap: bool, player: Node3D = null) -> void:
	snap_turning = snap
	if player:
		apply_to_player(player)
	save_settings()


func set_snap_angle(angle: float, player: Node3D = null) -> void:
	snap_angle = angle
	if player:
		apply_to_player(player)
	save_settings()


func set_smooth_turn_speed(speed: float, player: Node3D = null) -> void:
	smooth_turn_speed = speed
	if player:
		apply_to_player(player)
	save_settings()


func set_dominant_hand(hand: String, player: Node3D = null) -> void:
	var h := hand.to_lower()
	if h != "left" and h != "right":
		return
	dominant_hand = h
	if player:
		apply_to_player(player)
	save_settings()


func set_seated_mode(seated: bool, player: Node3D = null) -> void:
	seated_mode = seated
	if seated_mode:
		if height_offset < 0.20:
			height_offset = seated_height
	else:
		if absf(height_offset - seated_height) < 0.01:
			height_offset = 0.0
	if player:
		apply_to_player(player)
	save_settings()


func adjust_height(delta_m: float, player: Node3D = null) -> void:
	height_offset = clampf(height_offset + delta_m, HEIGHT_MIN, HEIGHT_MAX)
	if seated_mode and height_offset > 0.10:
		seated_height = height_offset
	if player:
		apply_to_player(player)
	save_settings()


func reset_height(player: Node3D = null) -> void:
	height_offset = seated_height if seated_mode else 0.0
	if player:
		apply_to_player(player)
	save_settings()


func reset_to_defaults(player: Node3D = null) -> void:
	vignette_enabled = true
	vignette_strength = 0.50
	snap_turning = true
	snap_angle = 45.0
	smooth_turn_speed = 2.0
	walk_scale = 1.0
	dominant_hand = "right"
	seated_mode = false
	seated_height = 0.35
	height_offset = 0.0
	for key in AUDIO_KEYS:
		audio_percent[key] = 100
	flash_percent = 100
	haptic_percent = 100
	apply_audio()
	if player:
		apply_to_player(player)
	save_settings()


static func _snap_percent(v: Variant) -> int:
	return clampi(roundi(float(v) / VOLUME_STEP) * VOLUME_STEP, 0, 100)


## The entry of [param levels] nearest to [param v].
static func _snap_to(v: float, levels: Array) -> float:
	var best := float(levels[0])
	for level in levels:
		if absf(float(level) - v) < absf(best - v):
			best = float(level)
	return best
