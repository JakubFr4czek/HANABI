class_name RunForestAmbience
extends Node
## Forest bed during survival runs (D13): wind in the crowns on the Ambience bus,
## cicadas/crickets at dusk as two spatial loops either side of the listener, and a
## temple bell from far off every 40–90 s, placed at random in the forest.
## Fades out under a splash, the end screen or a menu (set_active).
##
## Voices: wind 1 + one cricket emitter = [constant VOICES]. With the Sfx pool, the music
## (2), the rain bed (1) and this bed the mix is inside [constant Sfx.VOICE_BUDGET] (Quest, docs/QUEST_TEST.md §18).

const WIND := preload("res://assets/audio/sfx/hanabi_proc/forest_wind_loop.wav")
const CRICKETS := preload("res://assets/audio/sfx/hanabi_proc/crickets_loop.wav")
const VOICES := 2
const WIND_DB := -22.0
const CRICKET_DB := -20.0
## The one cricket emitter sits this far to the right of the listener and a little ahead,
## so turning the head sweeps the sound across the forest.
const CRICKET_OFFSET := Vector3(9.0, 0.0, -4.0)
const BELL_MIN_SEC := 40.0
const BELL_MAX_SEC := 90.0
const BELL_DISTANCE := 70.0
const BELL_DB := -9.0
const FADE_SEC := 1.5

## Set in tests (or by a rig without a current camera) to place the sounds.
var listener_override: Node3D = null
var bells_rung := 0
## 0 = silent, 1 = full forest bed.
var fade_amount := 0.0

var _wind: AudioStreamPlayer
var _cricket: AudioStreamPlayer3D
var _bell_in := 0.0
var _active := false
var _fade_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Keeps playing while a menu pauses the game (ducked by Sfx.set_pause_ducking).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = randi()
	_wind = AudioStreamPlayer.new()
	_wind.name = "ForestWind"
	_wind.stream = _looped(WIND)
	_wind.bus = Sfx.AMBIENCE_BUS
	add_child(_wind)
	_cricket = _make_cricket("Crickets")
	_bell_in = _next_bell_delay()
	_apply_levels()


func _process(delta: float) -> void:
	_place_crickets()
	if not _active:
		return
	_bell_in -= delta
	if _bell_in <= 0.0:
		_ring_far_bell()
		_bell_in = _next_bell_delay()


## Forest bed on (run playing) or off (splash, end screen, death). Fades over [constant FADE_SEC].
func set_active(on: bool) -> void:
	_active = on
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	var target := 1.0 if on else 0.0
	if not is_inside_tree():
		_set_fade(target)
		return
	_fade_tween = create_tween()
	_fade_tween.set_ignore_time_scale(true)
	_fade_tween.tween_method(_set_fade, fade_amount, target, FADE_SEC)


## Same as [method set_active] without the fade (tests, and a rig that starts mid-run).
func snap_to(on: bool) -> void:
	_active = on
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_set_fade(1.0 if on else 0.0)


func is_active() -> bool:
	return _active


## Voices this node can have playing at once (wind + the cricket emitter).
func voices_playing() -> int:
	var n := 0
	for p in [_wind, _cricket]:
		if p.playing:
			n += 1
	return n


func _set_fade(v: float) -> void:
	fade_amount = v
	_apply_levels()


func _apply_levels() -> void:
	var audible := fade_amount > 0.001
	var level := linear_to_db(maxf(fade_amount, 0.0001))
	_wind.volume_db = level + WIND_DB
	_cricket.volume_db = level + CRICKET_DB
	# A silent loop is stopped, so a quiet forest really frees its voices.
	for p in [_wind, _cricket]:
		if audible and not p.playing:
			p.play()
		elif not audible and p.playing:
			p.stop()


func _make_cricket(node_name: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.stream = _looped(CRICKETS)
	p.bus = Sfx.AMBIENCE_BUS
	p.unit_size = 6.0
	p.max_distance = 60.0
	add_child(p)
	return p


static func _looped(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var looped := wav.duplicate() as AudioStreamWAV
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_end = int(looped.get_length() * looped.mix_rate)
		return looped
	return stream


func _listener() -> Node3D:
	return listener_override if listener_override else get_viewport().get_camera_3d()


func _place_crickets() -> void:
	var cam := _listener()
	if cam == null:
		return
	_cricket.global_position = cam.global_transform * CRICKET_OFFSET


func _ring_far_bell() -> void:
	var cam := _listener()
	var at := cam.global_position if cam else Vector3.ZERO
	var dir := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
	if dir.is_zero_approx():
		dir = Vector3.FORWARD
	Sfx.play_at("bonsho", at + dir * BELL_DISTANCE, BELL_DB, 40.0, _rng.randf_range(0.92, 1.0))
	bells_rung += 1


func _next_bell_delay() -> float:
	return _rng.randf_range(BELL_MIN_SEC, BELL_MAX_SEC)
