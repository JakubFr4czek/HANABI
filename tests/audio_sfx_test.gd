extends Node

var failures := 0


func _ready() -> void:
	_check_rain_loops()
	_check("Sfx exposes Kenney run categories", Sfx._streams.has("firework") and Sfx._streams.has("soul_collect"))
	_check("Thunder uses single distant roll (no crack category)", not Sfx.CATEGORIES.has("thunder_crack"))
	_check("Blade ring uses recorded sword clashes (not generated)", Sfx.CATEGORIES["blade_ring"][0].contains("sword_clash"))
	_check("Cut/slap/hurt use Kenney CC0 combat (not generated)", Sfx.CATEGORIES["cut"][0].contains("cc0_combat")
		and Sfx.CATEGORIES["slap"][0].contains("cc0_combat")
		and Sfx.CATEGORIES["player_hurt"][0].contains("cc0_combat"))
	_check("Swing uses StarNinjas CC0 recordings", Sfx.CATEGORIES["swing"][0].contains("sword_swing"))
	_check("Cut category has multiple variants", Sfx._streams["cut"].streams_count >= 3)
	_check("Thunder loads CC0 storm recordings", Sfx.CATEGORIES["thunder"][0].contains("cc0_storm"))
	_check("Sfx pool is pre-sized for combat", Sfx._pool.size() >= 20)

	# Zadanie 5: Bonshō temple bell cues
	_check("Bonsho category exposes recorded temple bell cues", Sfx._streams.has("bonsho") and Sfx.CATEGORIES["bonsho"][0].contains("bonsho"))
	_check("Bonsho oni and gate categories exist", Sfx._streams.has("bonsho_oni") and Sfx._streams.has("bonsho_gate"))
	_check("Bonsho run start stream has exactly 1 cue", Sfx._streams["bonsho"].streams_count == 1)
	_check("Bonsho oni stream has exactly 1 cue", Sfx._streams["bonsho_oni"].streams_count == 1)
	_check("Bonsho gate stream has exactly 1 cue", Sfx._streams["bonsho_gate"].streams_count == 1)

	# Verify DC offset and zero-start for all bonsho recordings (AudioStreamWAV.data)
	_check("bonsho_run_start.wav has zero click and <1% DC offset", _check_wav_dc_clean("res://assets/audio/sfx/bonsho/bonsho_run_start.wav"))
	_check("bonsho_oni.wav has zero click and <1% DC offset", _check_wav_dc_clean("res://assets/audio/sfx/bonsho/bonsho_oni.wav"))
	_check("bonsho_gate.wav has zero click and <1% DC offset", _check_wav_dc_clean("res://assets/audio/sfx/bonsho/bonsho_gate.wav"))

	Sfx.play_at("soul_collect", Vector3.ZERO, -20.0)
	Sfx.play_at("firework", Vector3(1, 0, 0), -20.0)
	Sfx.play_at("bonsho", Vector3(0, 3, -12), -20.0)
	Sfx.play_at("bonsho_oni", Vector3(0, 3, -15), -20.0)
	Sfx.play_at("bonsho_gate", Vector3(0, 2, 0), -20.0)
	_check("Sfx play_at uses pooled players without new nodes", Sfx.get_child_count() <= 30)

	# D13: katana grab whisper, blade-tip whoosh threshold and voice limit, forest bed budget.
	_check("Grab category loads the steel whisper", Sfx._streams.has("grab"))
	_check("Whoosh stays silent below its speed threshold", HeldWeapon.whoosh_level(6.9, 7.0) == 0.0)
	_check("Whoosh rises with tip speed and caps at full level",
		HeldWeapon.whoosh_level(9.0, 7.0) > 0.3 and HeldWeapon.whoosh_level(9.0, 7.0) < HeldWeapon.whoosh_level(20.0, 7.0)
		and HeldWeapon.whoosh_level(40.0, 7.0) == 1.0)
	await _check_swing_voice_limit()
	await _check_forest_bed_budget()
	# Music (lead + layer) 2, rain 1, forest bed, Sfx pool: the design budget, checked again as real voices below.
	var design_voices: int = Sfx.POOL_SIZE + RunForestAmbience.VOICES + 1 + 2
	_check("Design voice budget: pool + forest bed + rain + music (%d <= %d)" % [design_voices, Sfx.VOICE_BUDGET],
		design_voices <= Sfx.VOICE_BUDGET)

	await _check_music_and_voice_cap()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


## Verifies 16-bit PCM WAV has no click at start (|first_sample| near 0) and |DC mean| < 1% full scale.
func _check_wav_dc_clean(path: String) -> bool:
	var stream := load(path) as AudioStreamWAV
	if not stream:
		return false
	var data := stream.data
	if data.is_empty():
		return false
	var first_sample: int = data.decode_s16(0)
	var sum: float = 0.0
	var sample_count: int = data.size() / 2
	for i in sample_count:
		sum += data.decode_s16(i * 2)
	var mean: float = sum / float(sample_count)
	var mean_pct: float = absf(mean) / 32768.0 * 100.0
	print("  [%s] first_sample=%d, mean=%.2f (%.4f%% full scale)" % [path.get_file(), first_sample, mean, mean_pct])
	return mean_pct < 1.0 and absi(first_sample) <= 50


## A fast run of blade whooshes must never stack more than the per-category limit.
func _check_swing_voice_limit() -> void:
	for p in Sfx._pool:
		p.stop()
	for i in 6:
		Sfx.play_at("swing", Vector3(i * 0.2, 0, 0), -6.0)
	var swings := Sfx._category_voices("swing")
	_check("Whoosh voices are capped at %d (playing %d of 6 requests)" % [Sfx.CATEGORY_VOICE_LIMIT["swing"], swings],
		swings == Sfx.CATEGORY_VOICE_LIMIT["swing"])
	for p in Sfx._pool:
		p.stop()


## The forest bed (wind + two cricket loops) uses exactly its declared voices, and
## goes fully silent under a splash or menu so it frees them.
func _check_forest_bed_budget() -> void:
	var bed := RunForestAmbience.new()
	add_child(bed)
	await get_tree().process_frame
	bed.snap_to(true)
	await get_tree().process_frame
	_check("Forest bed plays wind + cricket emitter = %d voices (%d playing)" % [RunForestAmbience.VOICES, bed.voices_playing()],
		bed.voices_playing() == RunForestAmbience.VOICES)
	bed.snap_to(false)
	await get_tree().process_frame
	_check("Forest bed is silent under a splash or menu (%d playing)" % bed.voices_playing(), bed.voices_playing() == 0)
	bed.queue_free()


func _count_playing_players_in_tree() -> int:
	var count := 0
	for p in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		if (p as AudioStreamPlayer).playing:
			count += 1
	for p in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		if (p as AudioStreamPlayer3D).playing:
			count += 1
	return count


## The run music must actually be playing, on a bus that exists, at a level
## a headset speaker can hear, with a subtle CC0 shakuhachi & taiko layer.
## Real voice cap test counts every playing player in SceneTree under full storm + combat load.
func _check_music_and_voice_cap() -> void:
	var music := StormMusic.new()
	add_child(music)
	var storm_ambience := StormAmbience.new()
	add_child(storm_ambience)
	var forest_ambience := RunForestAmbience.new()
	add_child(forest_ambience)
	forest_ambience.snap_to(true)

	await get_tree().process_frame
	await get_tree().process_frame

	var bus_idx := AudioServer.get_bus_index(Sfx.MUSIC_BUS)
	_check("music bus exists", bus_idx >= 0)
	var lead: AudioStreamPlayer = music._players[music._lead]
	_check("run music is playing", lead.playing)
	var chain_db: float = lead.volume_db + (AudioServer.get_bus_volume_db(bus_idx) if bus_idx >= 0 else -80.0)
	_check("music level is audible (chain %.1f dB)" % chain_db, chain_db > -20.0)

	# Shakuhachi & taiko layer on the Music bus (Zadanie 5)
	var layer: AudioStreamPlayer = music.get_layer_player()
	_check("shakuhachi/taiko layer player exists", layer != null)
	_check("shakuhachi/taiko layer is on Music bus", layer != null and layer.bus == Sfx.MUSIC_BUS)
	_check("shakuhachi/taiko layer is playing", layer != null and layer.playing)
	var layer_db: float = (layer.volume_db if layer else -80.0) + (AudioServer.get_bus_volume_db(bus_idx) if bus_idx >= 0 else -80.0)
	_check("layer level is audible and subtle (chain %.1f dB)" % layer_db, layer_db > -25.0 and layer_db < -10.0)

	# A stopped lead (focus loss, stream hiccup) restarts on its own.
	lead.stop()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("stopped music restarts itself", lead.playing)

	# A stopped layer also restarts on its own.
	if layer:
		layer.stop()
		await get_tree().process_frame
		await get_tree().process_frame
		_check("stopped music layer restarts itself", layer.playing)

	# Persistent soundscape players check
	var base_ambient_voices := _count_playing_players_in_tree()
	_check("Persistent soundscape active in tree (music, layer, rain, wind; %d >= 4)" % base_ambient_voices, base_ambient_voices >= 4)

	# Soft cap verification for bonsho_gate
	# Fill Sfx pool up to MAX_ACTIVE_WORLD_VOICES (20)
	for i in Sfx.MAX_ACTIVE_WORLD_VOICES:
		Sfx.play_at("clash", Vector3(i * 0.1, 0, 0), -20.0)
	var active_before := Sfx._active_world_voices()
	_check("Sfx pool reached soft cap threshold (%d >= %d)" % [active_before, Sfx.MAX_ACTIVE_WORLD_VOICES], active_before >= Sfx.MAX_ACTIVE_WORLD_VOICES)

	# Trigger bonsho_gate while pool is saturated; soft cap must drop it
	Sfx.play_at("bonsho_gate", Vector3(0, 2, 0), -20.0)
	var active_after_gate := Sfx._active_world_voices()
	_check("Soft cap drops bonsho_gate when pool is at voice limit (%d == %d)" % [active_after_gate, active_before], active_after_gate == active_before)

	# Non-soft-capped cues (e.g. cut, bonsho, bonsho_oni) still play safely via pool reuse
	Sfx.play_at("bonsho_oni", Vector3(0, 3, -15), -20.0)

	# Full heavy combat burst stress test: 40 simultaneous cues with music, layer, rain, wind
	for i in 40:
		Sfx.play_at("clash", Vector3(i * 0.05, 0, 0), -20.0)
		Sfx.play_at("cut", Vector3(-i * 0.05, 0, 0), -20.0)
		Sfx.play_at("bonsho", Vector3(0, 3, -12), -20.0)
		Sfx.play_at("bonsho_gate", Vector3(0, 2, 0), -20.0)

	var total_tree_voices := _count_playing_players_in_tree()
	print("SceneTree playing voices under heavy combat stress: %d (Quest 3 cap <= 28)" % total_tree_voices)
	_check("Real total playing players in SceneTree stays strictly <= 28 (%d <= 28)" % total_tree_voices, total_tree_voices <= 28)

	music.queue_free()
	storm_ambience.queue_free()
	forest_ambience.queue_free()


## The rain bed loops whatever the import settings: a one-shot WAV plays as a
## looping copy, and the source resource is left alone.
func _check_rain_loops() -> void:
	var def := StormAmbience.new()
	add_child(def)
	var ogg := def.rain_player.stream as AudioStreamOggVorbis
	_check("the default rain bed is an OGG that loops", ogg != null and ogg.loop)
	def.queue_free()
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var silence := PackedByteArray()
	silence.resize(22050 * 2)
	wav.data = silence
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var amb := StormAmbience.new()
	amb.rain_stream = wav
	add_child(amb)
	var looped := amb.rain_player.stream as AudioStreamWAV
	_check("a one-shot rain WAV plays as a looping copy", looped != wav and looped.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	_check("the loop covers the whole rain clip", looped.loop_end == 22050)
	_check("the source rain resource is not changed", wav.loop_mode == AudioStreamWAV.LOOP_DISABLED)
	amb.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
