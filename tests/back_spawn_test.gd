extends Node
## Nothing spawns behind the player (P6, uwaga 6). The back sector is 120° wide, centred
## on the opposite of the view direction, so a spawn is refused within 60° of "behind".
##   - 10 min of simulated waves with the view turning round: no yōkai, no Oni, in that sector.
##   - Straggler recall: a yōkai pulled back into the ring also lands outside it.
##   godot --headless --path . --fixed-fps 90 res://tests/back_spawn_test.tscn

const RUN_SCENE := preload("res://scenes/run.tscn")
const SIM_SECONDS := 600.0
const STEP := 0.1
const BACK_LIMIT_DEG := 60.0
const ONI_REFUSALS := 3

var failures := 0


func _ready() -> void:
	await _run()
	await _pacing_checks()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(10)
	var player := run.player as DesktopPlayer
	var director := run.wave_director
	director.stop_director()
	director.clear_enemies()
	director.start_director()

	# Spawns are recorded with the view yaw they were made under (a dict: lambdas copy ints).
	var sim := {"yaw": 0.0}
	var last_view := Vector3.ZERO
	var spawned: Array[Dictionary] = []
	director.enemy_spawned.connect(func(y: Yokai) -> void:
		spawned.append({"pos": y.global_position, "yaw": sim.yaw}))
	var center := player.global_position
	for step in int(SIM_SECONDS / STEP):
		# The view turns a full circle every ~14 s, so every sector passes over the spawner.
		sim.yaw = step * STEP * 0.45
		last_view = Vector3(sin(sim.yaw), 0.0, cos(sim.yaw))
		director.step_director(STEP, center, last_view)
		if step % 30 == 29:
			# Kill-and-clear every 3 s so the planner keeps spawning for the whole 10 min.
			director.clear_enemies()
	var closest := INF
	for s in spawned:
		closest = minf(closest, _from_behind_deg(s.pos, center, s.yaw))
	_check("10 min of waves: %d yōkai spawned" % spawned.size(), spawned.size() >= 40)
	_check("No yōkai in the back sector over 10 min (closest to dead behind %.1f°, limit %.0f°)" % [closest, BACK_LIMIT_DEG],
		spawned.size() >= 40 and closest >= BACK_LIMIT_DEG)

	# The Oni has its own ring placement: same rule, with the view turned to several sides.
	var oni_count := 0
	var oni_closest := INF
	var oni_in_front := 0
	for i in 36:
		var yaw := i * TAU / 36.0
		director.clear_enemies()
		var oni := director.spawn_oni_boss(center, Vector3(sin(yaw), 0.0, cos(yaw)))
		if oni == null:
			continue
		oni_count += 1
		oni_closest = minf(oni_closest, _from_behind_deg(oni.global_position, center, yaw))
		# N13 entrance: in front of the player, in frame, 6–7.5 m away (fallback ring: 9.2 m).
		var off := oni.global_position - center
		off.y = 0.0
		if absf(angle_difference(yaw, atan2(off.x, off.z))) <= deg_to_rad(23.0) \
				and off.length() >= 5.9 and off.length() <= 7.6:
			oni_in_front += 1
	_check("Oni placed in every view direction (%d of 36)" % oni_count, oni_count >= 30)
	_check("N13: Oni enters in front of the player at 6–7.5 m (%d of %d)" % [oni_in_front, oni_count],
		oni_count >= 30 and oni_in_front >= oni_count - 4)
	_check("Oni never in the back sector (closest to dead behind %.1f°)" % oni_closest,
		oni_count >= 30 and oni_closest >= BACK_LIMIT_DEG)
	director.clear_enemies()

	# Straggler recall: a yōkai left 60 m behind the player is pulled into the ring, not behind.
	# The recall works from the view the director was last stepped with, so measure from that view.
	var view := last_view
	var far := center + Vector3(0.0, 0.0, -60.0)
	far.y = run.forest_world.height_at(far.x, far.z)
	var left := director.spawn_enemy_at(far, center)
	left.brain.attacks_enabled = false
	director.recall_stragglers(center)
	await _frames(2)
	var recalled := left.root_part().global_position
	var recall_closest := _from_behind_deg(recalled, center, atan2(view.x, view.z))
	_check("Recalled yōkai came back into the ring (%.1f m)" % Vector2(recalled.x - center.x, recalled.z - center.z).length(),
		recalled.distance_to(far) > 10.0)
	_check("Recalled yōkai is not in the back sector (closest to dead behind %.1f°)" % recall_closest,
		recall_closest >= BACK_LIMIT_DEG)
	# A refused Oni cue is retried every tick, not dropped for the whole oni_interval. The
	# refusals are injected: the first ONI_REFUSALS placements find no legal spot.
	director.stop_director()
	director.clear_enemies()
	director.start_director()
	director.refuse_oni_placements(ONI_REFUSALS)
	var oni_at := {"tick": -1}
	director.oni_spawned.connect(func(_oni: RunOniBoss) -> void:
		if oni_at.tick < 0:
			oni_at.tick = sim.get("tick", -1)
		)
	var due_tick := -1
	var interval_ticks := int(director.get_profile().oni_interval / STEP)
	# The Oni is cued when a PEAK wave opens, so run until one does (up to 20 min).
	for tick in int(SIM_SECONDS * 2.0 / STEP):
		sim.tick = tick
		sim.yaw = tick * STEP * 0.45
		director.step_director(STEP, center, Vector3(sin(sim.yaw), 0.0, cos(sim.yaw)))
		if due_tick < 0 and director.oni_due():
			due_tick = tick
		if oni_at.tick >= 0:
			break
		if tick % 30 == 29:
			director.clear_enemies()
	var waited: int = oni_at.tick - due_tick if oni_at.tick >= 0 and due_tick >= 0 else -1
	_check("Oni cue refused %d times, then placed %d ticks after it was due (limit %d)" % [ONI_REFUSALS, waited, ONI_REFUSALS],
		waited >= 0 and waited <= ONI_REFUSALS and waited <= interval_ticks)
	director.stop_director()
	director.clear_enemies()
	run.queue_free()


## N7 pacing (docs/SPAWN_PLAN.md, "N7 – pomiar"): 8 minutes on the real run.tscn forest with
## the stand-in player (N7PacingSim). Stationary, so no physics frames are needed.
const PACING_SECONDS := 480.0
const PACING_SEED := 7
const DEMO_SECONDS := 180.0
const MAX_SKIPPED_SHARE := 0.05
const MAX_QUIET_AFTER_60 := 10.0


func _pacing_checks() -> void:
	var first := await _pacing_run(PACING_SEED, "default", PACING_SECONDS)
	var s: Dictionary = first.summary
	var skip_share: float = float(s.skipped) / maxf(float(s.requested), 1.0)
	_check("8 min: %d spawns requested, %d skipped by P6 (%.1f%%, limit %.0f%%)" % [s.requested, s.skipped, skip_share * 100.0, MAX_SKIPPED_SHARE * 100.0],
		s.requested >= 40 and skip_share <= MAX_SKIPPED_SHARE)
	_check("8 min: no spawn (yōkai or guard) in the back sector (%d of %d)" % [s.behind, s.spawned],
		s.spawned >= 40 and s.behind == 0)
	_check("8 min: every spawn in the view cone is behind geometry (%d of %d in cone hidden)" % [s.in_cone_occluded, s.in_cone],
		s.in_cone == s.in_cone_occluded)
	_check("8 min: no gap longer than %.0f s without a live enemy after 60 s (longest %.1f s)" % [MAX_QUIET_AFTER_60, s.longest_empty_after_60],
		s.longest_empty_after_60 <= MAX_QUIET_AFTER_60)
	_check("8 min: never more live yōkai than the Quest cap (max %d)" % s.max_alive,
		s.max_alive <= WaveProfile.QUEST_YOKAI_CAP)
	# The 3-minute demo on the real forest: the Oni is placed in [60, 100] s (N13: earlier entrance), and the stand-in
	# player meets the first yōkai in the calm opening (not before 20 s).
	var demo := await _pacing_run(PACING_SEED, "demo", DEMO_SECONDS)
	var demo_s: Dictionary = demo.summary
	_check("Demo 3 min: the Oni is placed at %.1f s, inside [60, 100] s" % demo_s.first_oni,
		demo_s.first_oni >= 60.0 and demo_s.first_oni <= 100.0)
	_check("Demo 3 min: the first yōkai reaches the player at %.1f s (after the calm opening)" % demo_s.first_contact,
		demo_s.first_contact >= 20.0)
	_check("Demo 3 min: never more live yōkai than the Quest cap (max %d)" % demo_s.max_alive,
		demo_s.max_alive <= WaveProfile.QUEST_YOKAI_CAP)


## One stationary 8-minute run. The summary and spawn list are taken before the run is freed.
func _pacing_run(seed_value: int, profile_file: String, seconds: float) -> Dictionary:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	# The forest streams its first chunks on worker threads: give them time to land, or two
	# runs with the same seed see different neighbours (and so different spawn points).
	await _frames(120)
	run.set_physics_process(false)
	if profile_file != "default":
		run.wave_director.profile = load(WaveProfile.preset_path(profile_file)) as WaveProfile
	var sim := N7PacingSim.new()
	await sim.play(get_tree(), run, run.wave_director, seconds, seed_value, false)
	var result := {"summary": sim.summary(), "spawns": sim.spawns}
	run.queue_free()
	await _frames(3)
	return result



## Degrees between the direction from [param center] to [param pos] and straight behind a
## view turned to [param yaw_view]. 0 = dead behind; the back sector is everything under 60.
func _from_behind_deg(pos: Vector3, center: Vector3, yaw_view: float) -> float:
	var dir_yaw := atan2(pos.x - center.x, pos.z - center.z)
	return rad_to_deg(absf(angle_difference(yaw_view + PI, dir_yaw)))


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
