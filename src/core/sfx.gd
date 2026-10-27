extends Node
## One-shot positional sound effects (autoload "Sfx").
##
## Pooled AudioStreamPlayer3D nodes; streams loaded once at boot. World bus has
## light reverb + limiter. Ambience bus gets slow-mo low-pass ducking.

const CATEGORIES := {
	"swing": ["res://assets/audio/sfx/sword_swing", ""],
	"clash": ["res://assets/audio/sfx/sword_clash", ""],
	"impact_light": ["res://assets/audio/sfx/impact", "impactPlank"],
	"impact_heavy": ["res://assets/audio/sfx/impact", "impactPunch"],
	"blade_ring": ["res://assets/audio/sfx/sword_clash", ""],
	"thunder": ["res://assets/audio/sfx/cc0_storm", "thunder"],
	"enemy_tell": ["res://assets/audio/generated", "enemy_tell"],
	"player_hurt": ["res://assets/audio/generated", "player_hurt"],
	"cut": ["res://assets/audio/generated", "cut"],
	"slap": ["res://assets/audio/generated", "slap"],
	"firework": ["res://assets/audio/sfx/kenney_run", "firework"],
	"soul_collect": ["res://assets/audio/sfx/kenney_run", "soul_collect"],
	"ofuda_slice": ["res://assets/audio/sfx/kenney_run", "ofuda_slice"],
	"level_up": ["res://assets/audio/sfx/kenney_run", "level_up"],
	"yokai_slice": ["res://assets/audio/sfx/kenney_run", "yokai_slice"],
}
const POOL_SIZE := 24
const WORLD_BUS := &"World"
const AMBIENCE_BUS := &"Ambience"
const MUSIC_BUS := &"Music"
const MAX_WORLD_DB := 4.0

var _streams := {}  # category -> AudioStreamRandomizer
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _ambience_lowpass_idx := -1
var _ambience_base_db := 0.0
var _music_base_db := 0.0


func _ready() -> void:
	_setup_buses()
	for category in CATEGORIES:
		_load_category(category)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 4.0
		player.max_polyphony = 1
		player.bus = WORLD_BUS
		add_child(player)
		_pool.append(player)
	if TimeController:
		TimeController.effect_started.connect(_on_time_effect)


func _process(_delta: float) -> void:
	_update_slow_mo_audio()


func play_at(category: String, position: Vector3, volume_db: float = 0.0, unit_size: float = 4.0, pitch_scale: float = 1.0) -> void:
	if not _streams.has(category):
		return
	var player := _acquire_player()
	player.stream = _streams[category]
	player.volume_db = clampf(volume_db, -36.0, MAX_WORLD_DB)
	player.pitch_scale = clampf(pitch_scale, 0.65, 1.45)
	player.unit_size = unit_size
	player.global_position = position
	player.play()


func _acquire_player() -> AudioStreamPlayer3D:
	for i in POOL_SIZE:
		var idx := (_next + i) % POOL_SIZE
		var p := _pool[idx]
		if not p.playing:
			_next = (idx + 1) % POOL_SIZE
			return p
	var player := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	return player


func _load_category(category: String) -> void:
	var dir: String = CATEGORIES[category][0]
	var prefix: String = CATEGORIES[category][1]
	var randomizer := AudioStreamRandomizer.new()
	randomizer.random_pitch = 1.06
	randomizer.random_volume_offset_db = 1.5
	for file in ResourceLoader.list_directory(dir):
		if file.get_extension() not in ["ogg", "wav"]:
			continue
		if prefix != "" and not file.begins_with(prefix):
			continue
		var stream := load(dir.path_join(file)) as AudioStream
		if stream:
			randomizer.add_stream(-1, stream)
	if randomizer.streams_count > 0:
		_streams[category] = randomizer
	else:
		push_warning("Sfx: no sounds found for '%s' in %s" % [category, dir])


func _on_time_effect(kind: String, _scale: float, _duration: float) -> void:
	if kind == "slow_motion":
		_update_slow_mo_audio(true)


func _update_slow_mo_audio(_force: bool = false) -> void:
	var bus := AudioServer.get_bus_index(AMBIENCE_BUS)
	if bus < 0:
		return
	var slow := TimeController.is_active("slow_motion")
	if _ambience_lowpass_idx < 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20500.0
		lp.resonance = 0.5
		AudioServer.add_bus_effect(bus, lp)
		_ambience_lowpass_idx = AudioServer.get_bus_effect_count(bus) - 1
	var lp_fx := AudioServer.get_bus_effect(bus, _ambience_lowpass_idx) as AudioEffectLowPassFilter
	if lp_fx:
		lp_fx.cutoff_hz = 900.0 if slow else 20500.0
	var duck := -10.0 if slow else 0.0
	var amb := AudioServer.get_bus_index(AMBIENCE_BUS)
	if amb >= 0:
		AudioServer.set_bus_volume_db(amb, _ambience_base_db + duck)
	var mus := AudioServer.get_bus_index(MUSIC_BUS)
	if mus >= 0:
		AudioServer.set_bus_volume_db(mus, _music_base_db + duck)


func _setup_buses() -> void:
	if AudioServer.get_bus_index(WORLD_BUS) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, WORLD_BUS)
		AudioServer.set_bus_send(i, &"Master")
		var reverb := AudioEffectReverb.new()
		reverb.predelay_msec = 45.0
		reverb.room_size = 0.75
		reverb.damping = 0.6
		reverb.spread = 0.85
		reverb.hipass = 0.12
		reverb.dry = 1.0
		reverb.wet = 0.22
		AudioServer.add_bus_effect(i, reverb)
		var limiter := AudioEffectHardLimiter.new()
		limiter.pre_gain_db = 0.0
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(i, limiter)
	if AudioServer.get_bus_index(AMBIENCE_BUS) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, AMBIENCE_BUS)
		AudioServer.set_bus_send(i, &"Master")
		_ambience_base_db = AudioServer.get_bus_volume_db(i)
	if AudioServer.get_bus_index(MUSIC_BUS) < 0:
		var j := AudioServer.bus_count
		AudioServer.add_bus(j)
		AudioServer.set_bus_name(j, MUSIC_BUS)
		AudioServer.set_bus_send(j, &"Master")
		_music_base_db = AudioServer.get_bus_volume_db(j)
