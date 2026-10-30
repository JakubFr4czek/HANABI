extends Node
## A whole cycle as played: intro, the grab, a fight with level-ups, death,
## the restart ema, the intro again and a second fight. Nothing from
## the first run may leak into the second. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/run_cycle_test.tscn -- --desktop
## Exit code 0 when everything passed.

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0
var run: RunGame


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	run = RUN_SCENE.instantiate()
	add_child(run)
	var dp := run.player as DesktopPlayer
	for cycle in 2:
		var label := "run %d" % (cycle + 1)
		await _until(func(): return run.run_intro._waiting_grab, 1400)
		_check("%s: the intro offers the katana" % label, run.run_intro._waiting_grab and not run.katana.grab_locked)
		dp.take_weapon(run.katana)
		await _frames(10)
		_check("%s: the grab starts the run (state %d)" % [label, run.state], run.state == RunGame.RunState.PLAYING)
		_check("%s: the gate is shut and the glow fades" % label, not run.run_intro._portal.visible)
		_check("%s: fresh run (kills %d, level %d, wave %d, hp %.0f)" % [label, run.kills, run.level, run.wave_director.wave, dp.health.hp],
			run.kills == 0 and run.level == 1 and dp.health.hp >= dp.health.max_hp - 0.01)
		await _fight(25.0)
		_check("%s: the fight went on (kills %d)" % [label, run.kills], run.kills > 0)
		if cycle == 0:
			run.wave_director.spawn_oni_boss(dp.global_position)
			await _frames(30)
			_check("run 1: the boss is on the field before the death", run.wave_director.has_active_oni())
		# Die and look at the aftermath.
		dp.health._invulnerable = 0.0
		dp.health.take_hit(10000.0, dp.global_position + Vector3.FORWARD)
		await _frames(30)
		_check("%s: death ends the run" % label, run.state == RunGame.RunState.GAME_OVER)
		_check("%s: no live enemy or boss stays on the field (%d alive, oni %s)" % [label, run.wave_director.alive_count(), run.wave_director.has_active_oni()],
			run.wave_director.alive_count() == 0 and not run.wave_director.has_active_oni())
		# D13: the old rule (full speed on the end screen) is replaced by a slow fall that never freezes time.
		for f in 200:
			await get_tree().physics_frame
			if absf(TimeController.time_scale - TimeController.DEATH_FALL_SCALE) < 0.001:
				break
		_check("%s: the world sinks to the slow-fall scale, time never stops (%.2f)" % [label, TimeController.time_scale],
			absf(TimeController.time_scale - TimeController.DEATH_FALL_SCALE) < 0.001 and Engine.time_scale > 0.0)
		await _until(func(): return run.restart_ema != null and is_instance_valid(run.restart_ema) and run.restart_ema.is_armed(), 600)
		var head := get_tree().get_first_node_in_group("player_head") as Node3D
		var ground := run.forest_world.height_at(head.global_position.x, head.global_position.z)
		var above := run.restart_ema.global_position.y - ground
		_check("%s: the restart ema hangs at hand height over the player's ground (%.2f m)" % [label, above], above > 1.0 and above < 1.5)
		run.restart_ema.slice(run.restart_ema.global_position, Vector3.RIGHT)
		await _frames(10)
		_check("%s: the restart ema starts a new intro" % label, run.state == RunGame.RunState.INTRO and run.run_intro.is_active())
		_check("%s: the katana is out of the hand and locked for the gate" % label, not run.katana.is_held() and run.katana.grab_locked)
		var souls := run._souls_root.get_children().filter(func(c): return c is SoulOrb).size()
		_check("%s: no soul orbs carried over (%d)" % [label, souls], souls == 0)
		_check("%s: no slow motion carried over" % label, not TimeController.is_active())
	var music := run.get_node_or_null("StormMusic") as StormMusic
	var playing := music != null and music._players.any(func(p): return p.playing)
	_check("the music still plays after two runs", playing)
	var stats: Dictionary = VfxPool.pool_stats()
	_check("VFX pools stay bounded (%s)" % stats, int(stats.sparks_allocated) <= VfxPool.MAX_SPARK and int(stats.souls_allocated) <= VfxPool.MAX_SOUL)
	run.queue_free()


## An auto-swordsman cuts whatever comes close (D1: a level-up asks for nothing).
func _fight(seconds: float) -> void:
	var dp := run.player as DesktopPlayer
	var cd := 0.0
	var flip := false
	for f in int(seconds * 90.0):
		await get_tree().physics_frame
		dp.health.heal(5.0)
		cd -= 1.0 / 90.0
		var best := 2.4
		var target: Yokai = null
		for y in run.wave_director.alive_enemies():
			var d := y.root_part().global_position.distance_to(dp.global_position)
			if d < best:
				best = d
				target = y
		if target and cd <= 0.0:
			var to := target.root_part().global_position - dp.global_position
			dp.rotation.y = atan2(-to.x, -to.z)
			dp.swing_duration = 0.14
			dp.swing(DesktopPlayer.SLASH_HORIZONTAL if flip else DesktopPlayer.SLASH_OVERHEAD)
			flip = not flip
			cd = 0.45


func _until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
