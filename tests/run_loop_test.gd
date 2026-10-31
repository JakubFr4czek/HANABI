extends Node
## Headless tests for Item 1 of docs/NIGHT_PLAN.md (Run loop):
## - scenes/run.tscn loads on the shrine platform, separate from training_arena
## - Diegetic HUD (tsuba XP ring, wrist HP charm & readout, no screen-space 2D UI)
## - WaveDirector spawns yōkai in the fog ring over the water, yōkai cross the
##   platform boundary onto the stone disc and attack with telegraphed claws
## - Killing a yōkai with the katana drops Hitodama soul orbs that magnetize to
##   the player and grant XP along a rising curve
## - Level-up is a rank plus a small heal (D1): no slow motion, no card choice,
##   no votive plaque or upgrade pool in play
## - Death ends the run, saves local high score, displays the in-world memorial
##   stele + Restart Ema, and slicing the Restart Ema starts a fresh run.

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_run_high_score.cfg"
const SANDBOX_SAVE_PATH := "user://test_run_sandbox_record.cfg"

var failures := 0


func _ready() -> void:
	# Fixed global seed: the gameplay streams (spawner, brains, ragdoll poses, soul orbs) draw
	# from it, so the run is reproducible instead of depending on the launch's random seed.
	seed(20260601)
	await _run_all()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	# The record checks below assume a normal run; a sandbox switch in the player's own file is not read.
	VrComfortSettings.sandbox_enabled = false

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = TEST_SAVE_PATH
	add_child(run)
	await _wait(0.2)

	var player := run.player as DesktopPlayer
	_check("RunGame instantiated with DesktopPlayer and katana held",
		player != null and run.katana != null and run.katana.is_held())
	_check("TrainingDummy is hidden and disabled in RunGame",
		run.dummy == null or not run.dummy.visible)

	# 1. Diegetic HUD check (no visible 2D CanvasLayer; the wrist ring and readout present).
	var any_2d_hud := false
	for layer in player.find_children("*", "CanvasLayer", true, false):
		if (layer as CanvasLayer).visible:
			any_2d_hud = true
	_check("No floating 2D screen-space UI is visible", not any_2d_hud)
	_check("Diegetic HUD: nothing on the katana, wrist HP ring + readout present",
		run.diegetic_hud != null
		and run.katana.get_node_or_null("TsubaXpRing") == null
		and run.katana.get_node_or_null("TsubaXpRingFront") == null
		and run.diegetic_hud.ring != null
		and run.diegetic_hud.wrist_label != null)
	# The readout is drawn only while the wrist is raised (XR: the gesture, see wrist_hud_test).
	# Desktop stands in with H, so lowered it is hidden and held it shows.
	var desktop := run.player as DesktopPlayer
	var hidden_low := not run.diegetic_hud.wrist_face.visible
	desktop.wrist_check = true
	await _wait(0.3)
	var shown_raised := run.diegetic_hud.wrist_face.visible
	desktop.wrist_check = false
	await _wait(0.3)
	_check("Wrist readout is drawn only while the wrist is raised", hidden_low and shown_raised and not run.diegetic_hud.wrist_face.visible)

	# 2. Wave director & yōkai walking from water onto the stone platform.
	var prof := run.wave_director.get_profile()
	_check("Wave curve grows the live cap, HP and speed with run time",
		prof.cap_at(90.0) > prof.cap_at(0.0)
		and run.wave_director.scaled_hp(4, 90.0) > run.wave_director.scaled_hp(1, 0.0)
		and run.wave_director.scaled_speed(4, 90.0) > run.wave_director.scaled_speed(1, 0.0))

	# Wave 1 opens after the calm lead-in: step the director past initial_wave_delay (no real waiting).
	await _wait(0.8)
	var lead_in := run.wave_director.get_profile().initial_wave_delay
	run.wave_director.step_director(lead_in + 0.1, player.global_position)
	_check("Wave 1 opens after the calm lead-in and spawns yōkai in the fog ring",
		run.wave_director.wave == 1 and run.wave_director.alive_count() >= 1)

	# Spawn a yōkai just outside the platform rim (r = 6.0 m in the water) and
	# verify it walks across the boundary (r = 5.2 m) onto the platform (r < 4.7 m).
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _wait(0.1)
	player.teleport(Vector3(0.0, 0.0, 1.5), 0.0)
	var walker := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -6.0), player.global_position)
	var start_r := Vector2(walker.root_part().global_position.x, walker.root_part().global_position.z).length()
	await _wait(3.2)
	var end_r := Vector2(walker.root_part().global_position.x, walker.root_part().global_position.z).length()
	_check("Yōkai walks from water (r %.2f m) across boundary onto platform (r %.2f m)" % [start_r, end_r],
		start_r > 5.5 and end_r < start_r - 0.35)

	# Verify yōkai claw attack damages player after telegraphed wind-up.
	walker.queue_free()
	await _wait(0.1)
	player.health.heal_full()
	player.teleport(Vector3(0.0, 0.0, 0.65), PI)
	var clawer := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -0.35), player.global_position)
	clawer.brain.force_attack("right")
	var hp_before := player.health.hp
	var deadline := Time.get_ticks_msec() + 2200
	while Time.get_ticks_msec() < deadline and player.health.hp >= hp_before:
		await _wait(0.05)
		if clawer.brain.state == YokaiBrain.State.SLASH:
			break
	if player.health.hp >= hp_before:
		clawer.snap_pose("slash_r")
		for _t in 16:
			await _wait(0.05)
			if player.health.hp < hp_before:
				break
	_check("Yōkai telegraphed claw strike damages the player (HP %.1f -> %.1f)" % [hp_before, player.health.hp],
		player.health.hp < hp_before)
	player.health.heal_full()

	# 3. Slaying a yōkai with a physical katana cut drops Hitodama soul orbs,
	#    which drift to the player and grant XP.
	clawer.hp = 12.0
	player.teleport(Vector3(0.0, 0.0, 1.45), 0.0)
	# The player body no longer blocks yōkai (no shoving in VR), so the claw
	# lunge leaves it wherever it ended; stand it at blade reach for the cut.
	clawer.place_at(Vector3(0.0, 0.0, 0.25), 0.0)
	await _wait(0.25)
	player.swing_duration = 0.16
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	await _wait(0.45)
	_check("Katana slash kills the yōkai and increments kill count (%d)" % run.kills,
		clawer.is_dead and run.kills >= 1)

	var orb_count := run.get_tree().get_nodes_in_group("soul_orbs").size()
	_check("Slain yōkai drops multiple Hitodama soul orbs (%d)" % orb_count, orb_count >= 2)

	# Wait for soul orbs to magnetize into the player and award XP.
	await _wait(1.2)
	_check("Hitodama orbs magnetize to the player and grant XP (xp=%d, level=%d)" % [run.xp, run.level],
		run.xp > 0 or run.level > 1)

	# 4. XP rising curve; a level-up is a rank and a heal (D1), never a card choice.
	_check("XP curve rises with level (%d < %d < %d)" % [
		RunGame.xp_for_level(1), RunGame.xp_for_level(2), RunGame.xp_for_level(3)],
		RunGame.xp_for_level(1) < RunGame.xp_for_level(2) and RunGame.xp_for_level(2) < RunGame.xp_for_level(3))

	# Level-up: rank goes up, HP is restored by LEVEL_UP_HEAL_HP, the game keeps
	# running at full speed and no votive plaque or card appears.
	player.health.hp = 40.0
	var level_before := run.level
	var points_before := run.skill_points
	run.add_xp(run.xp_to_next)
	await _wait(0.1)
	_check("Level-up raises the rank (%d -> %d) and heals %d HP (hp %.0f)" % [
		level_before, run.level, int(RunGame.LEVEL_UP_HEAL_HP), player.health.hp],
		run.level == level_before + 1 and absf(player.health.hp - (40.0 + RunGame.LEVEL_UP_HEAL_HP)) < 0.5)
	_check("Level-up gives exactly one skill point (%d -> %d)" % [points_before, run.skill_points],
		run.skill_points == points_before + 1)
	var hud := run.diegetic_hud
	_check("Level-up flashes the fire and shows the new level on the readout",
		hud._level_flash > 0.0 and hud._level_text.contains("LV %d" % run.level))
	_check("Level-up keeps playing: state PLAYING, no slow motion (scale %.2f)" % TimeController.time_scale,
		run.state == RunGame.RunState.PLAYING and TimeController.time_scale > 0.95)
	_check("Level-up presents no card: no votive plaque in the run",
		run.get_tree().get_nodes_in_group("votive_tablets").is_empty())

	# 6. Death ends the run, saves high score locally, shows End Screen & Restart Ema;
	#    slicing the Restart Ema with the katana starts a new run.
	# New system (ELEMENTS_PLAN): the blade element comes only from a Torii gate,
	# never from level-up cards. Imbue Storm directly as a gate crossing would.
	run.element_system.imbue(Elements.STORM)
	run.kills = 7
	run.score = run.compute_score()
	# The level-up readout ("LV n · +1 点") holds for 1.5 s; this check reads the normal readout.
	run.diegetic_hud._level_text_left = 0.0
	run._refresh_hud()
	_check("Diegetic wrist shows score points and kill count separately",
		run.diegetic_hud.wrist_label.text.contains("pt")
		and run.diegetic_hud.wrist_label.text.contains("斬 7"))
	_check("Wrist HP ring does not pulse at healthy HP",
		float(run.diegetic_hud._ring_cache.get("hp_pulse", 1.0)) == 0.0)

	run.calorie_meter.kcal = 45.8
	player.health.take_hit(999.0, Vector3.ZERO, {"attacker": "Yokai"})
	await _wait(0.15)
	_check("Lethal hit ends the run (GAME_OVER) without auto-reviving",
		run.state == RunGame.RunState.GAME_OVER and not player.health.is_alive())
	# D13: the death is a slow fall of the world, never a frozen one (time_scale 0 would stop the end screen).
	var never_zero := true
	var reached_fall := false
	for i in 200:
		never_zero = never_zero and Engine.time_scale > 0.0 and TimeController.time_scale > 0.0
		await get_tree().physics_frame
		if absf(TimeController.time_scale - TimeController.DEATH_FALL_SCALE) < 0.001:
			reached_fall = true
			break
	_check("Death: world sinks to the slow-fall scale and time_scale never reaches 0 (D13)",
		never_zero and reached_fall and TimeController.is_active("death_fall"))
	_check("Death: Sfx ducks Music/Ambience instead of silencing the end screen (D13)",
		Sfx._pause_tween != null and Sfx._pause_tween.is_valid())
	_check("High score (%d) is saved locally and MemorialStele + Restart Ema appear" % run.high_score,
		run.high_score > 0
		and run.load_high_score() == run.high_score
		and run.get_node_or_null("EndScreen/MemorialStele") != null
		and run.restart_ema != null)
	# The stele must list the element the blade carries (imbued via Torii gate).
	var stele_text := _stele_label_text(run)
	var lists_build := stele_text.contains("BUILD") and run.element_system.current_element != Elements.NONE
	if run.element_system.current_element != Elements.NONE:
		lists_build = lists_build and stele_text.contains(Elements.build_label(run.element_system.current_element))
	_check("Memorial stele lists element BUILD (GDD §6 end screen): %s" % stele_text.replace("\n", " | "),
		lists_build)
	_check("Memorial stele lists burned calories (45 kcal, GDD §15): %s" % stele_text.replace("\n", " | "),
		stele_text.contains("45 kcal"))

	var saved_best := run.high_score
	# Slice the Restart Ema with a katana swing to start a fresh run.
	player.swing_duration = 0.16
	player.swing(DesktopPlayer.SLASH_OVERHEAD)
	await _wait(0.45)
	if run.state == RunGame.RunState.GAME_OVER and run.restart_ema != null:
		# Fallback if overhead arc passed above the lower plaque: slice directly.
		run.restart_ema.slice(run.restart_ema.global_position, Vector3.RIGHT)
		await _wait(0.1)

	_check("Slicing the Restart Ema starts a new run at full HP while keeping high score (%d)" % run.high_score,
		run.state == RunGame.RunState.PLAYING
		and player.health.is_alive()
		and run.level == 1
		and run.kills == 0
		and run.high_score == saved_best)

	_spawn_pacing_checks(run)
	await _sandbox_keeps_no_record()
	run.queue_free()


## D9: a sandbox run never becomes a record. The same death with the same score is a record
## outside the sandbox, and only there. Deaths are called directly: the checks are the end state.
## D10: the yōkai waves. The pacing is checked on WavePlanner (the code the game and
## the editor panel both run); the first minute and the spawn points are checked on the
## live director in the real run scene, with the camera and the world geometry.
func _spawn_pacing_checks(run: RunGame) -> void:
	var director := run.wave_director
	var head := get_tree().get_first_node_in_group("player_head") as Camera3D
	var profile := director.get_profile()
	var demo := load(WaveProfile.preset_path("demo_gentle")) as WaveProfile
	var hard := load(WaveProfile.preset_path("hardcore")) as WaveProfile

	var errors := 0
	for p in [demo, profile, hard]:
		for line in p.validate():
			if line.begins_with("BŁĄD"):
				errors += 1
	_check("Wave presets (demo, default, hardcore) load and validate without errors (%d)" % errors,
		demo != null and hard != null and errors == 0)

	var calm := WavePlanner.simulate(profile, 480.0, 7)
	var again := WavePlanner.simulate(profile, 480.0, 7)
	var hard_run := WavePlanner.simulate(hard, 480.0, 7)
	_check("First minute: at most 4 yōkai spawned (%d), at most 3 alive at once (%d)" % [calm.first_minute_spawned, calm.first_minute_max_alive],
		calm.first_minute_spawned <= 4 and calm.first_minute_max_alive <= 3)
	_check("8-minute run is the same for the same seed and never above the Quest cap (max alive %d, cap %d)" % [calm.max_alive, WaveProfile.QUEST_YOKAI_CAP],
		calm.spawned == again.spawned and calm.kills == again.kills
		and calm.max_alive <= WaveProfile.QUEST_YOKAI_CAP and hard_run.max_alive <= WaveProfile.QUEST_YOKAI_CAP)
	_check("Hardcore spawns more yōkai over 8 minutes than the default (%d > %d)" % [hard_run.spawned, calm.spawned],
		hard_run.spawned > calm.spawned)

	var plan := WavePlanner.new(profile, 1)
	_check("Director cycle: waves 1-2 build, 3 peaks, 4 relaxes",
		plan.state_for_wave(1) == WavePlanner.State.BUILD and plan.state_for_wave(2) == WavePlanner.State.BUILD
		and plan.state_for_wave(3) == WavePlanner.State.PEAK and plan.state_for_wave(4) == WavePlanner.State.RELAX)

	# The Oni is cued after oni_first_seconds, and only at the start of a PEAK wave.
	var oni_plan := WavePlanner.new(profile, 3)
	var oni_state := -1
	var oni_at := -1.0
	for i in 6000:
		if oni_plan.step(0.1, 0, false).oni:
			oni_state = oni_plan.state
			oni_at = oni_plan.t
			break
	_check("Oni is cued at a PEAK wave after oni_first_seconds (at %.0f s)" % oni_at,
		oni_state == WavePlanner.State.PEAK and oni_at >= profile.oni_first_seconds)

	# Live director, first 60 s of run time (fixed 0.1 s steps, no waiting).
	director.stop_director()
	director.clear_enemies()
	director.start_director()
	var spawns: Array[Vector3] = []
	director.enemy_spawned.connect(func(y: Yokai) -> void: spawns.append(y.global_position))
	var center := head.global_position - Vector3(0.0, 0.35, 0.0)
	var forward := -head.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var alive_peak := 0
	for i in 600:
		director.step_director(0.1, center, forward)
		alive_peak = maxi(alive_peak, director.alive_count())
	_check("Live first minute: at most 4 yōkai spawned (%d), at most 3 alive (%d)" % [spawns.size(), alive_peak],
		spawns.size() >= 1 and spawns.size() <= 4 and alive_peak <= 3)

	# Every spawn point is outside the camera's view and clear of the world geometry.
	var in_view := 0
	var blocked := 0
	var yaw_view := atan2(forward.x, forward.z)
	var cone := deg_to_rad(profile.view_half_angle)
	var outside_cone := 0
	for pos in spawns:
		if head.is_position_in_frustum(pos + Vector3(0.0, 0.9, 0.0)):
			in_view += 1
		if not director.is_clear_of_world(pos):
			blocked += 1
		if absf(angle_difference(yaw_view, atan2(pos.x - center.x, pos.z - center.z))) >= cone:
			outside_cone += 1
	_check("Spawns are never in the camera's view (%d of %d in view)" % [in_view, spawns.size()],
		spawns.size() >= 1 and in_view == 0 and outside_cone == spawns.size())
	_check("Spawns are never inside solid geometry (%d of %d blocked)" % [blocked, spawns.size()],
		blocked == 0)
	# Same code path as the spawner, 300 times: the view test must see the camera's frame
	# (a point straight ahead is in view, so the check is not vacuous) and must find no
	# spawn point in it.
	var ahead := center + forward * 9.0
	_check("View check is real: a point 9 m straight ahead is in the camera frame",
		head.is_position_in_frustum(ahead + Vector3(0.0, 0.9, 0.0)))
	var drawn := 0
	var drawn_blocked := 0
	var placed := 0
	for i in 300:
		var pos := director.find_spawn_point(center, forward)
		# Vector3.INF is the spawner's "no legal spot this tick" (the spawn is skipped): not a point to test.
		if pos == Vector3.INF:
			continue
		placed += 1
		if head.is_position_in_frustum(pos + Vector3(0.0, 0.9, 0.0)):
			drawn += 1
		if not director.is_clear_of_world(pos):
			drawn_blocked += 1
	_check("300 spawn points from the spawner (%d placed): none in the camera frame (%d), none in geometry (%d)" % [placed, drawn, drawn_blocked],
		placed > 0 and drawn == 0 and drawn_blocked == 0)
	director.stop_director()
	director.clear_enemies()


func _sandbox_keeps_no_record() -> void:
	VrComfortSettings.sandbox_enabled = true
	var sandbox_run := await _death_with_score(SANDBOX_SAVE_PATH)
	var stele := _stele_label_text(sandbox_run)
	_check("sandbox death: the score (%d) is not a record (new_record %s, high score %d)" % [sandbox_run.score, sandbox_run.new_record, sandbox_run.high_score],
		sandbox_run.score > 0 and not sandbox_run.new_record and sandbox_run.high_score == 0)
	_check("sandbox death: no high-score file is written", not FileAccess.file_exists(SANDBOX_SAVE_PATH))
	_check("sandbox death: the stele says SANDBOX · NO RECORD and no NEW RECORD", stele.contains("SANDBOX") and not stele.contains("NEW RECORD"))
	sandbox_run.queue_free()
	await _wait(0.1)

	VrComfortSettings.sandbox_enabled = false
	var normal_run := await _death_with_score(SANDBOX_SAVE_PATH)
	_check("the same death outside the sandbox is a record (new_record %s, high score %d)" % [normal_run.new_record, normal_run.high_score],
		normal_run.new_record and normal_run.high_score == normal_run.score and FileAccess.file_exists(SANDBOX_SAVE_PATH))
	normal_run.queue_free()
	await _wait(0.1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SANDBOX_SAVE_PATH))


## A fresh run that is killed with a fixed score (3 kills, 60 s) and a clean high score.
func _death_with_score(save_path: String) -> RunGame:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var run_game: RunGame = RUN_SCENE.instantiate()
	run_game.skip_run_intro = true
	run_game.high_score_path = save_path
	add_child(run_game)
	await _wait(0.2)
	run_game.high_score = 0
	run_game.kills = 3
	run_game.run_time = 60.0
	run_game._on_player_died()
	return run_game


func _stele_label_text(run: RunGame) -> String:
	var board := run.get_node_or_null("EndScreen/MemorialStele")
	if board == null:
		return ""
	var parts: PackedStringArray = []
	for child in board.get_children():
		if child is Label3D:
			parts.append((child as Label3D).text)
	return "\n".join(parts)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
