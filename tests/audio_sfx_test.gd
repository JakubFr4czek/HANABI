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
	Sfx.play_at("soul_collect", Vector3.ZERO, -20.0)
	Sfx.play_at("firework", Vector3(1, 0, 0), -20.0)
	_check("Sfx play_at uses pooled players without new nodes", Sfx.get_child_count() <= 30)
	await _check_music()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


## The run music must actually be playing, on a bus that exists, at a level
## a headset speaker can hear (the old -23.5 dB was near-silent in VR).
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
	# A stopped lead (focus loss, stream hiccup) restarts on its own.
	lead.stop()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("stopped music restarts itself", lead.playing)
	music.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
