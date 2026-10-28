extends Node
## Central repository and manager for VR Comfort & Accessibility settings
## (docs/GDD.md §14, docs/ELEMENTS_PLAN.md).
##
## Persists to `user://hanabi_vr.cfg` and configures godot-xr-tools:
## - Vignette toggle and strength (auto-vignette on movement/turn)
## - Turning mode (snap vs smooth), snap angle, smooth turn speed
## - Dominant-hand swap (katana hand, wrist HUD side, stick assignment)
## - Seated-mode height calibration and eye height offset

signal settings_changed

const SETTINGS_PATH := "user://hanabi_vr.cfg"

const SNAP_ANGLES: Array[float] = [15.0, 30.0, 45.0, 60.0, 90.0]
const SMOOTH_SPEEDS: Array[float] = [1.0, 1.5, 2.0, 3.0, 4.0]
const VIGNETTE_STRENGTHS: Array[float] = [0.25, 0.50, 0.75, 1.00]

const HEIGHT_MIN := -0.45
const HEIGHT_MAX := 0.80
const HEIGHT_STEP := 0.05
const SEATED_DEFAULT_BOOST := 0.35

var vignette_enabled: bool = true
var vignette_strength: float = 0.50
var snap_turning: bool = true
var snap_angle: float = 45.0
var smooth_turn_speed: float = 2.0
var dominant_hand: String = "right"
var seated_mode: bool = false
var seated_height: float = 0.35
var height_offset: float = 0.0

static var instance: VrComfortSettings = null


func _init() -> void:
	if instance == null:
		instance = self


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return

	if cfg.has_section("view"):
		height_offset = clampf(float(cfg.get_value("view", "height_offset", height_offset)), HEIGHT_MIN, HEIGHT_MAX)

	if cfg.has_section("comfort"):
		vignette_enabled = bool(cfg.get_value("comfort", "vignette_enabled", vignette_enabled))
		vignette_strength = clampf(float(cfg.get_value("comfort", "vignette_strength", vignette_strength)), 0.0, 1.0)
		snap_turning = bool(cfg.get_value("comfort", "snap_turning", snap_turning))
		snap_angle = float(cfg.get_value("comfort", "snap_angle", snap_angle))
		smooth_turn_speed = float(cfg.get_value("comfort", "smooth_turn_speed", smooth_turn_speed))
		dominant_hand = String(cfg.get_value("comfort", "dominant_hand", dominant_hand)).to_lower()
		if dominant_hand != "left" and dominant_hand != "right":
			dominant_hand = "right"
		seated_mode = bool(cfg.get_value("comfort", "seated_mode", seated_mode))
		seated_height = float(cfg.get_value("comfort", "seated_height", seated_height))
		if cfg.has_section_key("comfort", "height_offset"):
			height_offset = clampf(float(cfg.get_value("comfort", "height_offset", height_offset)), HEIGHT_MIN, HEIGHT_MAX)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	# Backward compatibility with existing view settings
	cfg.set_value("view", "height_offset", height_offset)

	cfg.set_value("comfort", "vignette_enabled", vignette_enabled)
	cfg.set_value("comfort", "vignette_strength", vignette_strength)
	cfg.set_value("comfort", "snap_turning", snap_turning)
	cfg.set_value("comfort", "snap_angle", snap_angle)
	cfg.set_value("comfort", "smooth_turn_speed", smooth_turn_speed)
	cfg.set_value("comfort", "dominant_hand", dominant_hand)
	cfg.set_value("comfort", "seated_mode", seated_mode)
	cfg.set_value("comfort", "seated_height", seated_height)
	cfg.set_value("comfort", "height_offset", height_offset)

	var err := cfg.save(SETTINGS_PATH)
	if err == OK:
		GameEvents.log_event("vr_comfort_saved", {
			"vignette": vignette_enabled,
			"vignette_strength": vignette_strength,
			"snap_turning": snap_turning,
			"snap_angle": snap_angle,
			"smooth_turn_speed": smooth_turn_speed,
			"dominant_hand": dominant_hand,
			"seated_mode": seated_mode,
			"height_offset": snappedf(height_offset, 0.01),
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
		if not vignette_enabled:
			vignette.set("radius", 1.0)
			if vignette.has_node("Mesh"):
				(vignette.get_node("Mesh") as CanvasItem if vignette.get_node("Mesh") is CanvasItem else vignette.get_node("Mesh") as Node3D).visible = false


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
	dominant_hand = "right"
	seated_mode = false
	seated_height = 0.35
	height_offset = 0.0
	if player:
		apply_to_player(player)
	save_settings()
