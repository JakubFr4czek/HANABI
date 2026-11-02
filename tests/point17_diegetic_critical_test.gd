extends Node
## The HP bar follows the player's real health in the run scene (D14, F1; replaces the old
## "bar only when critical" rule): the fill is HP/max, the colour runs teal -> amber -> red,
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
	_check("full health: the ring is full and teal", absf(hud.row_fill("hp") - 1.0) < 0.01
		and hud._hp_colour.g > hud._hp_colour.r)
	_check("full health: no pulse", not hud.hp_critical)

	health.hp = health.max_hp * 0.5
	run._refresh_hud()
	await _frames(2)
	var half: Color = hud._hp_colour
	_check("half health: the bar is about half and amber (fill %.2f, %s)" % [hud.row_fill("hp"), half],
		absf(hud.row_fill("hp") - 0.5) < 0.01 and half.r > 0.9 and half.b < 0.3)

	health.hp = health.max_hp * 0.2
	run._refresh_hud()
	await _frames(2)
	var low: Color = hud._hp_colour
	_check("critical health: the bar is red and pulses (%s)" % [low],
		low.r > 0.85 and low.g < 0.3 and hud.hp_critical)

	# The HP bar is part of the readout, so it only renders when the wrist is raised.
	var player := run.player as DesktopPlayer
	_check("lowered wrist: the HP bar is not drawn", not hud.row_labels("hp")[0].is_visible_in_tree())
	player.wrist_check = true
	await _frames(20)
	_check("raised wrist: the HP bar is drawn", hud.row_labels("hp")[0].is_visible_in_tree())
	player.wrist_check = false
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
