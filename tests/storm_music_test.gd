extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var music := run.get_node_or_null("StormMusic") as StormMusic
	_check("Run spawns StormMusic on Music bus", music != null)
	if music:
		_check("StormMusic uses dual players for seam-safe loop", music._players.size() == 2)
		music.duck_for_level_up(0.04, -6.0)
		await _frames(55)
		_check("Level-up duck returns toward base volume", absf(music._duck_offset_db) < 0.5)
	var forest := run.get_node_or_null("RunForestAmbience") as RunForestAmbience
	if forest and forest._player:
		_check("Forest wind on Ambience bus (not Music)", forest._player.bus == Sfx.AMBIENCE_BUS)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
