class_name DistantFireworks
extends Node
## Distant matsuri fireworks (D18, docs/FIREWORKS_PLAN.md): far, muffled bursts
## behind the mist that the player hears and sees but never reaches. Atmosphere
## only: no points, no pickups, nothing for enemies or the blade to react to.
##
## Far bursts come at random gaps (profile "Distant fireworks"), sometimes in short
## series, 150–400 m away above the tree line, each in a new direction. Now and
## then a rarer, nearer burst (40–80 m, behind the trees) is brighter and louder.
## Sound travels at the speed of sound (distance / 343 m/s) through the "Fireworks"
## bus: low-pass, reverb, compressor, limiter. The glow is an additive quad seen
## through fog; there is no dynamic light (fog ends at 11 m, so a light at 40 m
## would light nothing visible). Settings > ACCESS flash dims the glow only.
##
## Everything is pooled in _ready: a burst reuses the glow quads, the spark
## emitter and the two sound players, so a burst never allocates nodes. Time
## advances through advance(), called from _process; tests call it directly.

enum Kind { FAR, NEAR }

const SOUND_SPEED := 343.0
const BUS := &"Fireworks"
const GLOW_SHADER := preload("res://src/shaders/distant_firework_glow.gdshader")
## Heavy impact thunder (Kenney Impact, CC0) for the far boom; a soft pop joins the near bursts.
const FAR_SAMPLES: Array[AudioStream] = [
	preload("res://assets/audio/sfx/cc0_storm/thunder_impact_heavy_1.ogg"),
	preload("res://assets/audio/sfx/cc0_storm/thunder_impact_heavy_2.ogg"),
]
const NEAR_SAMPLE := preload("res://assets/audio/sfx/kenney_run/firework_pop_soft_000.ogg")
## Muted palette: amber, dusty rose, pale gold and one cool violet. Never neon (GDD §9 art rule).
const GLOW_COLORS: Array[Color] = [
	Color(0.95, 0.6, 0.36),
	Color(0.88, 0.5, 0.62),
	Color(0.92, 0.76, 0.5),
	Color(0.5, 0.56, 0.9),
]
const MIN_ANGLE_DEG := 70.0
const DIRECTION_TRIES := 64
const FAR_ELEVATION_DEG := Vector2(4.0, 9.0)
const FAR_HEIGHT := Vector2(18.0, 60.0)
const NEAR_HEIGHT := Vector2(14.0, 30.0)
const SERIES_GAP := Vector2(0.6, 2.5)
const SERIES_EXTRA := Vector2i(1, 3)
const WAVE_NEAR_DELAY := Vector2(0.0, 3.0)
const GLOW_POOL := 3
const VOICE_POOL := 2
const SPARK_AMOUNT := 10
const SPARK_LIFE := 1.0
const GLOW_RADIUS := {Kind.FAR: 40.0, Kind.NEAR: 12.0}
## How strong the expanding shell is at the start, per kind.
const SHELL_GAIN := {Kind.FAR: 0.35, Kind.NEAR: 0.6}
const GLOW_LIFE := {Kind.FAR: 2.4, Kind.NEAR: 1.8}
const GLOW_RISE := 0.18
const GLOW_DECAY := 0.7
const NEAR_GLOW_BOOST := 1.3
const LOG_LIMIT := 200

## Last bursts, newest last. Tests read it; the game keeps only LOG_LIMIT entries.
var burst_log: Array[Dictionary] = []

var profile: WorldGenProfile
var player: Node3D
var enabled := false

var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _next_far := 0.0
var _next_near := 0.0
var _series_left := 0
var _wave_near_at := -1.0
var _last_azimuths: Array[float] = []
var _glows: Array[MeshInstance3D] = []
var _glow_mats: Array[ShaderMaterial] = []
## Per glow: seconds of life so far (-1 = idle), its kind and its peak intensity.
var _glow_age: Array[float] = []
var _glow_kind: Array[int] = []
var _glow_peak: Array[float] = []
var _sparks: GPUParticles3D
var _spark_mat: ShaderMaterial
var _voices: Array[AudioStreamPlayer3D] = []
var _pending: Array[Dictionary] = []
var _lowpass: AudioEffectLowPassFilter = null
var _bus_idx := -1


func _ready() -> void:
	# Keeps time with the tree: menus and the pause hold the sky still.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_ensure_bus()
	for i in GLOW_POOL:
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		var mat := ShaderMaterial.new()
		mat.shader = GLOW_SHADER
		var glow := MeshInstance3D.new()
		glow.name = "Glow%d" % i
		glow.mesh = quad
		glow.material_override = mat
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.visible = false
		add_child(glow)
		_glows.append(glow)
		_glow_mats.append(mat)
		_glow_age.append(-1.0)
		_glow_kind.append(Kind.FAR)
		_glow_peak.append(0.0)
	_spark_mat = ShaderMaterial.new()
	_spark_mat.shader = GLOW_SHADER
	var spark_quad := QuadMesh.new()
	spark_quad.size = Vector2(0.6, 0.6)
	var particles := ParticleProcessMaterial.new()
	particles.direction = Vector3.UP
	particles.spread = 60.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0.0, -2.2, 0.0)
	particles.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 4.0
	particles.scale_min = 0.5
	particles.scale_max = 0.8
	_sparks = GPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.amount = SPARK_AMOUNT
	_sparks.lifetime = SPARK_LIFE
	_sparks.one_shot = true
	_sparks.explosiveness = 0.0
	_sparks.emitting = false
	_sparks.process_material = particles
	_sparks.draw_pass_1 = spark_quad
	_sparks.material_override = _spark_mat
	add_child(_sparks)
	for i in VOICE_POOL:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Voice%d" % i
		voice.bus = BUS
		# Unit size far beyond the 40–400 m range: the level is the designed one,
		# only the pan follows the burst.
		voice.unit_size = 400.0
		voice.max_distance = 4000.0
		add_child(voice)
		_voices.append(voice)
	_apply_bus_volume()
	VrComfortSettings.settings_changed.connect(_apply_bus_volume)


## Sets the world, the player and the profile (null = the shipped defaults).
func setup(world: WorldGenProfile, rig: Node3D) -> void:
	profile = world if world != null else WorldGenProfile.new()
	player = rig


## Seeds the schedule (tests and screenshots). Without it the run is random.
func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value


## Starts the schedule (run_started) or stops it (death). Bursts already on
## screen finish their own life either way.
func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		_next_far = _clock + _rng.randf_range(_far_gap_min(), _far_gap_max())
		_next_near = _clock + _rng.randf_range(_near_gap_min(), _near_gap_max())
		_series_left = 0


## Wave start hook (D10). Sometimes a near burst comes a moment after a wave begins.
func on_wave_started(_wave: int, _total: int) -> void:
	if not enabled or profile == null:
		return
	if _rng.randf() < profile.firework_wave_chance:
		_wave_near_at = _clock + _rng.randf_range(WAVE_NEAR_DELAY.x, WAVE_NEAR_DELAY.y)


## One frame of the schedule, the glows, the sound queue. Called from _process.
func advance(delta: float) -> void:
	_clock += delta
	if enabled and profile != null and player != null:
		if _clock >= _next_far:
			_far_event()
		if _clock >= _next_near:
			_next_near = _clock + _rng.randf_range(_near_gap_min(), _near_gap_max())
			fire(Kind.NEAR)
		if _wave_near_at >= 0.0 and _clock >= _wave_near_at:
			_wave_near_at = -1.0
			fire(Kind.NEAR)
	_update_glows(delta)
	_flush_sounds()


## The intro's single far burst (GDD §9, title plate): sound only, since the plate
## hides the world from the camera.
func fire_intro_burst() -> Dictionary:
	if profile == null:
		profile = WorldGenProfile.new()
	return fire(Kind.FAR, false)


## One burst now. [param show_glow] = false keeps the sound and skips the visuals.
## [param at_azimuth] aims it (radians, 0 = straight ahead of the player; screenshots).
## Returns what happened (kind, distance, azimuth, height, delay, ...).
func fire(kind: int, show_glow: bool = true, at_azimuth: float = NAN) -> Dictionary:
	var origin := player.global_position if player != null else Vector3.ZERO
	var azimuth := at_azimuth if not is_nan(at_azimuth) else _pick_azimuth()
	if not is_nan(at_azimuth):
		_remember_azimuth(azimuth)
	var dir := Vector3(sin(azimuth), 0.0, -cos(azimuth))
	var dist := 0.0
	var height := 0.0
	if kind == Kind.FAR:
		dist = _rng.randf_range(profile.firework_far_min, profile.firework_far_max)
		var elevation := deg_to_rad(_rng.randf_range(FAR_ELEVATION_DEG.x, FAR_ELEVATION_DEG.y))
		height = clampf(dist * tan(elevation), FAR_HEIGHT.x, FAR_HEIGHT.y)
	else:
		dist = _rng.randf_range(profile.firework_near_min, profile.firework_near_max)
		height = _rng.randf_range(NEAR_HEIGHT.x, NEAR_HEIGHT.y)
	var at := origin + dir * dist + Vector3(0.0, height, 0.0)
	var color := GLOW_COLORS[_rng.randi() % GLOW_COLORS.size()]
	var flash := VrComfortSettings.flash_scale()
	var delay := dist / SOUND_SPEED
	var peak := profile.firework_glow * flash * (NEAR_GLOW_BOOST if kind == Kind.NEAR else 1.0)
	if show_glow and flash > 0.0 and peak > 0.0:
		_start_glow(at, color, peak, kind)
		if kind == Kind.NEAR:
			_start_sparks(at, color, flash)
	var series_start := _series_left == 0
	var sound := {
		"at": _clock + delay,
		"pos": at,
		"stream": NEAR_SAMPLE if kind == Kind.NEAR else FAR_SAMPLES[_rng.randi() % FAR_SAMPLES.size()],
		"db": profile.firework_near_db if kind == Kind.NEAR else profile.firework_far_db,
		"cutoff": profile.firework_near_cutoff_hz if kind == Kind.NEAR else profile.firework_far_cutoff_hz,
		"pitch": _rng.randf_range(0.92, 1.05),
	}
	_pending.append(sound)
	var info := {
		"t": _clock,
		"kind": "near" if kind == Kind.NEAR else "far",
		"dist": dist,
		"azimuth": azimuth,
		"height": height,
		"delay": delay,
		"color": color,
		"glow": show_glow and flash > 0.0 and peak > 0.0,
		"series_start": series_start,
		"db": sound.db,
		"cutoff": sound.cutoff,
	}
	burst_log.append(info)
	if burst_log.size() > LOG_LIMIT:
		burst_log.pop_front()
	return info


## Glows on screen right now (pool size is GLOW_POOL).
func active_glow_count() -> int:
	var n := 0
	for g in _glows:
		if g.visible:
			n += 1
	return n


## Draw calls this system adds right now: visible glows plus the spark emitter.
func visible_draw_calls() -> int:
	return active_glow_count() + (1 if _sparks.emitting else 0)


## Sound players currently playing (VOICE_POOL is the cap).
func active_voice_count() -> int:
	var n := 0
	for v in _voices:
		if v.playing:
			n += 1
	return n


## Bursts whose sound has not reached the listener yet.
func pending_sound_count() -> int:
	return _pending.size()


## Number of OmniLight3D nodes under this system (always 0: no dynamic light).
func light_count() -> int:
	return find_children("*", "Light3D", true, false).size()


## Node count under this system. Stays flat across bursts: the pool is fixed.
func pool_node_count() -> int:
	return find_children("*", "", true, false).size()


## A far burst. Inside a series the next one follows after a short gap; the last
## burst of a series hands over to the long interval, and so does a lone burst.
func _far_event() -> void:
	var member := _series_left > 0
	fire(Kind.FAR)
	if member:
		_series_left -= 1
		var gap := SERIES_GAP if _series_left > 0 else Vector2(_far_gap_min(), _far_gap_max())
		_next_far = _clock + _rng.randf_range(gap.x, gap.y)
	elif _rng.randf() < profile.firework_series_chance:
		_series_left = _rng.randi_range(SERIES_EXTRA.x, SERIES_EXTRA.y)
		_next_far = _clock + _rng.randf_range(SERIES_GAP.x, SERIES_GAP.y)
	else:
		_next_far = _clock + _rng.randf_range(_far_gap_min(), _far_gap_max())


## A new direction at least MIN_ANGLE_DEG from the last two bursts. If the tries run
## out, the best one found is used. With the far bursts this frequent, 12 tries
## failed about once in a hundred bursts; 64 makes the fallback practically unreachable.
func _pick_azimuth() -> float:
	var best := 0.0
	var best_gap := -1.0
	for _i in DIRECTION_TRIES:
		var a := _rng.randf() * TAU
		var gap := INF
		for prev in _last_azimuths:
			gap = minf(gap, absf(wrapf(a - prev, -PI, PI)))
		if gap >= deg_to_rad(MIN_ANGLE_DEG):
			best = a
			break
		if gap > best_gap:
			best = a
			best_gap = gap
	_remember_azimuth(best)
	return best


func _remember_azimuth(azimuth: float) -> void:
	_last_azimuths.append(azimuth)
	if _last_azimuths.size() > 2:
		_last_azimuths.pop_front()


func _start_glow(at: Vector3, color: Color, peak: float, kind: int) -> void:
	# Free glow first, else the oldest one that is still fading.
	var pick := -1
	var oldest := -1.0
	for i in GLOW_POOL:
		if _glow_age[i] < 0.0:
			pick = i
			break
		if _glow_age[i] > oldest:
			oldest = _glow_age[i]
			pick = i
	_glow_age[pick] = 0.0
	_glow_kind[pick] = kind
	_glow_peak[pick] = peak
	var glow := _glows[pick]
	glow.global_position = at
	glow.visible = true
	_glow_mats[pick].set_shader_parameter("tint", Color(color.r, color.g, color.b, 1.0))
	_glow_mats[pick].set_shader_parameter("intensity", 0.0)
	_glow_mats[pick].set_shader_parameter("shell_radius", 0.0)
	_glow_mats[pick].set_shader_parameter("shell_gain", 0.0)
	_face_player(glow)


func _update_glows(delta: float) -> void:
	for i in GLOW_POOL:
		if _glow_age[i] < 0.0:
			continue
		_glow_age[i] += delta
		var kind: int = _glow_kind[i]
		var age := _glow_age[i]
		if age >= GLOW_LIFE[kind]:
			_glow_age[i] = -1.0
			_glows[i].visible = false
			_glow_mats[i].set_shader_parameter("intensity", 0.0)
			continue
		# Quick rise, then a long soft fade. A shell of light opens out from the core
		# and dies away as it grows, the way a shell blooms in the sky.
		var rise := clampf(age / GLOW_RISE, 0.0, 1.0)
		var env := rise * rise * (3.0 - 2.0 * rise)
		if age > GLOW_RISE:
			env *= exp(-(age - GLOW_RISE) / GLOW_DECAY)
		var t := clampf(age / GLOW_LIFE[kind], 0.0, 1.0)
		_glow_mats[i].set_shader_parameter("intensity", _glow_peak[i] * env)
		_glow_mats[i].set_shader_parameter("shell_radius", 0.15 + 0.75 * t)
		_glow_mats[i].set_shader_parameter("shell_gain", SHELL_GAIN[kind] * (1.0 - t) * (1.0 - t))
		_glows[i].scale = Vector3.ONE * GLOW_RADIUS[kind]
		_face_player(_glows[i])


## Glows are flat quads; turning them toward the player keeps them round.
func _face_player(glow: Node3D) -> void:
	if player == null or not glow.is_inside_tree():
		return
	var eye := player.global_position + Vector3(0.0, 1.5, 0.0)
	if glow.global_position.distance_squared_to(eye) > 0.0001:
		glow.look_at(eye, Vector3.UP)


func _start_sparks(at: Vector3, color: Color, flash: float) -> void:
	_sparks.global_position = at
	_spark_mat.set_shader_parameter("tint", Color(color.r, color.g, color.b, 1.0))
	_spark_mat.set_shader_parameter("intensity", flash * 0.25)
	_spark_mat.set_shader_parameter("shell_gain", 0.0)
	_sparks.restart()
	_sparks.emitting = true


func _flush_sounds() -> void:
	var i := 0
	while i < _pending.size():
		var item: Dictionary = _pending[i]
		if _clock < item.at:
			i += 1
			continue
		_pending.remove_at(i)
		_play_sound(item)


## Two voices at most: when both are busy the boom is dropped, not stacked.
func _play_sound(item: Dictionary) -> void:
	var voice: AudioStreamPlayer3D = null
	for v in _voices:
		if not v.playing:
			voice = v
			break
	if voice == null:
		return
	if _lowpass:
		_lowpass.cutoff_hz = item.cutoff
	voice.stream = item.stream
	voice.volume_db = item.db
	voice.pitch_scale = item.pitch
	voice.global_position = item.pos
	voice.play()


## Bus "Fireworks": low-pass (per burst, set at the sound), reverb, compressor, limiter.
## Sent to Master, so the Ambience slider governs it (see _apply_bus_volume).
func _ensure_bus() -> void:
	_bus_idx = AudioServer.get_bus_index(BUS)
	if _bus_idx < 0:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, BUS)
		AudioServer.set_bus_send(_bus_idx, &"Master")
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = profile.firework_far_cutoff_hz if profile else 450.0
		AudioServer.add_bus_effect(_bus_idx, lowpass)
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.9
		reverb.predelay_msec = 60.0
		reverb.damping = 0.7
		reverb.spread = 0.9
		reverb.hipass = 0.1
		reverb.dry = 0.35
		reverb.wet = 0.65
		AudioServer.add_bus_effect(_bus_idx, reverb)
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -18.0
		compressor.ratio = 3.0
		compressor.attack_us = 20000.0
		compressor.release_ms = 250.0
		AudioServer.add_bus_effect(_bus_idx, compressor)
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -3.0
		AudioServer.add_bus_effect(_bus_idx, limiter)
	for i in AudioServer.get_bus_effect_count(_bus_idx):
		var fx := AudioServer.get_bus_effect(_bus_idx, i)
		if fx is AudioEffectLowPassFilter:
			_lowpass = fx as AudioEffectLowPassFilter


## The Ambience slider of Settings > AUDIO sets the level of the fireworks.
func _apply_bus_volume() -> void:
	if _bus_idx < 0:
		return
	var level: float = VrComfortSettings.audio_percent["ambience"] / 100.0
	AudioServer.set_bus_volume_db(_bus_idx, linear_to_db(level) if level > 0.001 else -80.0)


func _far_gap_min() -> float:
	return profile.firework_interval_min


func _far_gap_max() -> float:
	return profile.firework_interval_max


func _near_gap_min() -> float:
	return profile.firework_near_interval_min


func _near_gap_max() -> float:
	return profile.firework_near_interval_max


func _process(delta: float) -> void:
	advance(delta)
