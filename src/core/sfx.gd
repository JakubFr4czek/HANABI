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
	"enemy_tell": ["res://assets/audio/sfx/cc0_combat", "enemy_tell"],
	"player_hurt": ["res://assets/audio/sfx/cc0_combat", "player_hurt"],
	"cut": ["res://assets/audio/sfx/cc0_combat", "cut"],
	"slap": ["res://assets/audio/sfx/cc0_combat", "slap"],
	"firework": ["res://assets/audio/sfx/kenney_run", "firework"],
	"soul_collect": ["res://assets/audio/sfx/kenney_run", "soul_collect"],
	"ofuda_slice": ["res://assets/audio/sfx/kenney_run", "ofuda_slice"],
	"level_up": ["res://assets/audio/sfx/kenney_run", "level_up"],
	"yokai_slice": ["res://assets/audio/sfx/kenney_run", "yokai_slice"],
	# Element imbue cues (E3): one quiet cue per school and the blade going plain.
	"imbue_sakura": ["res://assets/audio/sfx/hanabi_proc", "imbue_sakura"],
	"imbue_storm": ["res://assets/audio/sfx/hanabi_proc", "imbue_storm"],
	"imbue_ink": ["res://assets/audio/sfx/hanabi_proc", "imbue_ink"],
	"imbue_shadow": ["res://assets/audio/sfx/hanabi_proc", "imbue_shadow"],
	"element_fade": ["res://assets/audio/sfx/hanabi_proc", "element_fade"],
	# Hokora shrine handbell (D1): rings on approach, once per claim.
	"hokora_suzu": ["res://assets/audio/sfx/hanabi_proc", "hokora_suzu"],
	# Bonshō temple bell cues (Zadanie 5)
	"bonsho": ["res://assets/audio/sfx/bonsho", "bonsho_run_start"],
	"bonsho_oni": ["res://assets/audio/sfx/bonsho", "bonsho_oni"],
	"bonsho_gate": ["res://assets/audio/sfx/bonsho", "bonsho_gate"],
}
const POOL_SIZE := 24
const MAX_ACTIVE_WORLD_VOICES := 20
const SOFT_CAP_CATEGORIES := ["enemy_tell", "blade_ring", "slap", "bonsho_gate"]
const WORLD_BUS := &"World"
const AMBIENCE_BUS := &"Ambience"
const MUSIC_BUS := &"Music"
const MAX_WORLD_DB := 4.0
## Output endpoints of Quest Link / Air Link / Virtual Desktop on Windows.
const XR_HEADSET_AUDIO_KEYS := ["oculus", "meta quest", "quest", "rift", "virtual desktop"]

var _streams := {}  # category -> AudioStreamRandomizer
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _ambience_lowpass_idx := -1
var _ambience_base_db := 0.0
var _music_base_db := 0.0
## Slow-mo duck currently applied on the Music / Ambience buses (dB).
var _slow_duck_db := 0.0
## Pause menu ducking (docs/ELEMENTS_PLAN.md (e)(3)): 0 = normal, 1 = fully ducked.
const PAUSE_LOWPASS_HZ := 750.0
const PAUSE_MUSIC_DUCK_DB := -8.0
const PAUSE_AMBIENCE_DUCK_DB := -6.0
const PAUSE_FADE_SEC := 0.25
var _pause_amount := 0.0
var _pause_tween: Tween
var _music_lowpass_idx := -1


func _ready() -> void:
	# Cues played from a pause menu (and sounds still ringing out when it opens)
	# must keep running while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
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


## PCVR over Link / Air Link: Godot opens the Windows default output (often the
## PC speakers or a monitor), not the headset, so a VR session is silent in
## the headset. Pick the headset's endpoint when one is listed. Returns the
## chosen device name ("" when nothing matched; output stays on Default).
func route_to_xr_headset() -> String:
	var devices := AudioServer.get_output_device_list()
	print("Sfx: audio outputs ", devices, " current ", AudioServer.output_device)
	var chosen := ""
	for name in devices:
		var low := String(name).to_lower()
		for key in XR_HEADSET_AUDIO_KEYS:
			if low.contains(key):
				chosen = String(name)
				break
		if chosen != "":
			break
	if chosen != "" and chosen != AudioServer.output_device:
		AudioServer.output_device = chosen
	GameEvents.log_event("audio_output", {"devices": devices, "chosen": chosen, "current": AudioServer.output_device})
	return chosen


func _process(_delta: float) -> void:
	_update_slow_mo_audio()


func play_at(category: String, position: Vector3, volume_db: float = 0.0, unit_size: float = 4.0, pitch_scale: float = 1.0) -> void:
	if not _streams.has(category):
		return
	if SOFT_CAP_CATEGORIES.has(category) and _active_world_voices() >= MAX_ACTIVE_WORLD_VOICES:
		return
	var player := _acquire_player()
	player.stream = _streams[category]
	player.volume_db = clampf(volume_db, -36.0, MAX_WORLD_DB)
	player.pitch_scale = clampf(pitch_scale, 0.65, 1.45)
	player.unit_size = unit_size
	player.global_position = position
	player.play()


func _active_world_voices() -> int:
	var n := 0
	for p in _pool:
		if p.playing:
			n += 1
	return n


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
	var combat := category in ["swing", "clash", "cut", "slap", "impact_light", "impact_heavy", "player_hurt", "yokai_slice"]
	var bell := category.begins_with("bonsho")
	randomizer.random_pitch = 1.14 if combat else (1.02 if bell else 1.06)
	randomizer.random_volume_offset_db = 2.0 if combat else (0.8 if bell else 1.5)
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
	_slow_duck_db = -10.0 if slow else 0.0
	_apply_bus_levels()


## Composes the slow-mo duck and the pause duck on the Music / Ambience buses.
func _apply_bus_levels() -> void:
	var amb := AudioServer.get_bus_index(AMBIENCE_BUS)
	if amb >= 0:
		AudioServer.set_bus_volume_db(amb, _ambience_base_db + _slow_duck_db + PAUSE_AMBIENCE_DUCK_DB * _pause_amount)
	var mus := AudioServer.get_bus_index(MUSIC_BUS)
	if mus >= 0:
		AudioServer.set_bus_volume_db(mus, _music_base_db + _slow_duck_db + PAUSE_MUSIC_DUCK_DB * _pause_amount)
		if _music_lowpass_idx < 0:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20500.0
			lp.resonance = 1.0
			AudioServer.add_bus_effect(mus, lp)
			_music_lowpass_idx = AudioServer.get_bus_effect_count(mus) - 1
		var lp_fx := AudioServer.get_bus_effect(mus, _music_lowpass_idx) as AudioEffectLowPassFilter
		if lp_fx:
			# Log-space blend so the sweep sounds even.
			lp_fx.cutoff_hz = exp(lerpf(log(20500.0), log(PAUSE_LOWPASS_HZ), _pause_amount))


## Pause menu atmosphere: Music through a 750 Hz low-pass at -8 dB, Ambience
## -6 dB, the Sfx/World bus untouched so UI clicks stay crisp. Fades over
## [constant PAUSE_FADE_SEC] in real time. Instant when [param fade] is 0.
func set_pause_ducking(on: bool, fade: float = PAUSE_FADE_SEC) -> void:
	if _pause_tween and _pause_tween.is_valid():
		_pause_tween.kill()
	var target := 1.0 if on else 0.0
	if fade <= 0.0 or not is_inside_tree():
		_set_pause_amount(target)
		return
	_pause_tween = create_tween()
	_pause_tween.set_ignore_time_scale(true)
	_pause_tween.tween_method(_set_pause_amount, _pause_amount, target, fade)


func pause_amount() -> float:
	return _pause_amount


func _set_pause_amount(v: float) -> void:
	_pause_amount = v
	_apply_bus_levels()


## Player volumes (VrComfortSettings [audio]), linear 0..1 per bus. Music and
## Ambience keep their slow-mo and pause ducks on top of these levels.
func set_bus_levels(master: float, music: float, sfx: float, ambience: float) -> void:
	AudioServer.set_bus_volume_db(0, _linear_db(master))
	var world := AudioServer.get_bus_index(WORLD_BUS)
	if world >= 0:
		AudioServer.set_bus_volume_db(world, _linear_db(sfx))
	_music_base_db = _linear_db(music)
	_ambience_base_db = _linear_db(ambience)
	_apply_bus_levels()


static func _linear_db(v: float) -> float:
	return linear_to_db(v) if v > 0.001 else -80.0


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
		var music_limiter := AudioEffectHardLimiter.new()
		music_limiter.ceiling_db = -2.5
		music_limiter.pre_gain_db = 0.0
		AudioServer.add_bus_effect(j, music_limiter)
