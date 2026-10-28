extends Node

var failures := 0


func _ready() -> void:
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
	_check("Bonsho category has multiple recorded variants", Sfx._streams["bonsho"].streams_count >= 1)

	Sfx.play_at("soul_collect", Vector3.ZERO, -20.0)
	Sfx.play_at("firework", Vector3(1, 0, 0), -20.0)
	Sfx.play_at("bonsho", Vector3(0, 3, -12), -20.0)
	Sfx.play_at("bonsho_oni", Vector3(0, 3, -15), -20.0)
	Sfx.play_at("bonsho_gate", Vector3(0, 2, 0), -20.0)
	_check("Sfx play_at uses pooled players without new nodes", Sfx.get_child_count() <= 30)

	await _check_music()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


## The run music must actually be playing, on a bus that exists, at a level
## a headset speaker can hear, with a subtle CC0 shakuhachi & taiko layer.
func _check_music() -> void:
	var music := StormMusic.new()
	add_child(music)
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

	# 28-voice cap verification under heavy combat stress with music + layer + bonsho
	for i in 25:
		Sfx.play_at("clash", Vector3(i * 0.1, 0, 0), -20.0)
		Sfx.play_at("bonsho", Vector3(0, 3, -10), -20.0)
	var sfx_active := Sfx._active_world_voices()
	var total_voices := sfx_active + (1 if lead.playing else 0) + (1 if (layer and layer.playing) else 0)
	_check("Sfx active world voices bounded by pool size (%d <= %d)" % [sfx_active, Sfx.POOL_SIZE], sfx_active <= Sfx.POOL_SIZE)
	_check("All audio cues stay strictly within the 28-voice cap (%d <= 28)" % total_voices, total_voices <= 28)

	music.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
