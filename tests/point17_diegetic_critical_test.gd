extends Node
## The HP ring follows the player's real health in the run scene (D14; replaces the old
## "ring only when critical" rule): the fill is HP/max, the colour runs teal -> amber -> red,
## and the pulse starts below a quarter of health. Damage goes through PlayerHealth, as in play.
##   godot --headless --path . --fixed-fps 90 res://tests/point17_diegetic_critical_test.tscn -- --desktop

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
	var hud := run.diegetic_hud
	var health := (run.player as DesktopPlayer).health

	health.hp = health.max_hp
	run._refresh_hud()
	await _frames(2)
	_check("full health: the ring is full and teal", absf(float(hud._ring_cache.get("hp_fill", 0.0)) - 1.0) < 0.01
		and (hud._ring_cache.get("hp_color") as Color).g > (hud._ring_cache.get("hp_color") as Color).r)
	_check("full health: no pulse", float(hud._ring_cache.get("hp_pulse", 1.0)) == 0.0)

	health.hp = health.max_hp * 0.5
	run._refresh_hud()
	await _frames(2)
	var half: Color = hud._ring_cache.get("hp_color")
	_check("half health: the ring is about half and amber (fill %.2f, %s)" % [float(hud._ring_cache.get("hp_fill", 0.0)), half],
		absf(float(hud._ring_cache.get("hp_fill", 0.0)) - 0.5) < 0.01 and half.r > 0.9 and half.b < 0.3)

	health.hp = health.max_hp * 0.2
	run._refresh_hud()
	await _frames(2)
	var low: Color = hud._ring_cache.get("hp_color")
	_check("critical health: the ring is red and pulses (%s)" % [low],
		low.r > 0.85 and low.g < 0.3 and float(hud._ring_cache.get("hp_pulse", 0.0)) == 1.0)

	# The ring is part of the readout, so it only renders when the wrist is raised.
	var player := run.player as DesktopPlayer
	_check("lowered wrist: the ring is not drawn", not hud.ring.is_visible_in_tree())
	player.wrist_check = true
	await _frames(20)
	_check("raised wrist: the ring is drawn", hud.ring.is_visible_in_tree())
	player.wrist_check = false
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
