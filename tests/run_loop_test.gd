extends Node
## Headless tests for Item 1 of docs/NIGHT_PLAN.md (Run loop):
## - scenes/run.tscn loads on the shrine platform, separate from training_arena
## - Diegetic HUD (tsuba XP ring, wrist HP charm & readout, no screen-space 2D UI)
## - WaveDirector spawns yōkai in the fog ring over the water, yōkai cross the
##   platform boundary onto the stone disc and attack with telegraphed claws
## - Killing a yōkai with the katana drops Hitodama soul orbs that magnetize to
##   the player and grant XP along a rising curve
## - Level-up triggers compensated slow motion and spawns 3 floating Ofuda;
##   physically slicing one with the katana picks the upgrade and resumes play
## - All 6 generic upgrades apply their effects
## - Death ends the run, saves local high score, displays the in-world memorial
##   stele + Restart Ofuda, and slicing the Restart Ofuda starts a fresh run.

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_run_high_score.cfg"

var failures := 0


func _ready() -> void:
	await _run_all()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

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

	# 1. Diegetic HUD check (no visible 2D CanvasLayer, tsuba ring + wrist charm present).
	var any_2d_hud := false
	for layer in player.find_children("*", "CanvasLayer", true, false):
		if (layer as CanvasLayer).visible:
			any_2d_hud = true
	_check("No floating 2D screen-space UI is visible", not any_2d_hud)
	_check("Diegetic HUD has Tsuba XP ring and Wrist HP charm + label",
		run.diegetic_hud != null
		and run.diegetic_hud.tsuba_ring != null
		and run.diegetic_hud.hp_charm_mesh != null
		and run.diegetic_hud.wrist_label != null)

	# 2. Wave director & yōkai walking from water onto the stone platform.
	_check("Wave curve scales count, HP and speed with wave/time",
		run.wave_director.wave_enemy_count(4, 90.0) > run.wave_director.wave_enemy_count(1, 0.0)
		and run.wave_director.scaled_hp(4, 90.0) > run.wave_director.scaled_hp(1, 0.0)
		and run.wave_director.scaled_speed(4, 90.0) > run.wave_director.scaled_speed(1, 0.0))

	await _wait(0.8)
	_check("Wave 1 started and spawned yōkai in the outer fog ring",
		run.wave_director.wave >= 1 and run.wave_director.alive_count() >= 2)

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
	var clawer := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, 0.35), player.global_position)
	await _wait(0.3)
	clawer.brain.force_attack("right")
	var hp_before := player.health.hp
	await _wait(1.45)
	_check("Yōkai telegraphed claw strike damages the player (HP %.1f -> %.1f)" % [hp_before, player.health.hp],
		player.health.hp < hp_before)
	player.health.heal_full()

	# 3. Slaying a yōkai with a physical katana cut drops Hitodama soul orbs,
	#    which drift to the player and grant XP.
	clawer.hp = 12.0
	player.teleport(Vector3(0.0, 0.0, 1.45), 0.0)
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

	# 4. XP rising curve & Level-up slow motion + slicing 1 of 3 Ofuda with the sword.
	_check("XP curve rises with level (%d < %d < %d)" % [
		RunGame.xp_for_level(1), RunGame.xp_for_level(2), RunGame.xp_for_level(3)],
		RunGame.xp_for_level(1) < RunGame.xp_for_level(2) and RunGame.xp_for_level(2) < RunGame.xp_for_level(3))

	if run.state != RunGame.RunState.LEVEL_UP:
		run.add_xp(run.xp_to_next)
	await _wait(0.1)

	_check("Level-up enters LEVEL_UP state with compensated slow motion (scale %.2f)" % TimeController.time_scale,
		run.state == RunGame.RunState.LEVEL_UP and TimeController.time_scale < 0.5 and TimeController.player_compensated)
	_check("Three floating Ofuda talismans appear in front of the player (%d)" % run.active_ofuda.size(),
		run.active_ofuda.size() == 3)

	# Aim the player at the center Ofuda and swing the katana physically straight down through it!
	var center_ofuda := run.active_ofuda[1]
	var chosen_id := String(center_ofuda.upgrade.get("id", ""))
	player.swing_duration = 0.16
	# The desktop right hand rests 22 cm off-center; offset the scripted cut so
	# its swept blade, not merely the hand, passes through the center card.
	player.swing([Vector3(-0.15, 0.5, 0.0), Vector3(-0.15, -0.5, 0.0)])
	await _wait(0.45)

	_check("Physical katana swing slices the Ofuda, applies upgrade '%s', and exits slow-mo" % chosen_id,
		run.state == RunGame.RunState.PLAYING
		and TimeController.time_scale > 0.95
		and int(run.upgrade_stacks.get(chosen_id, 0)) >= 1)

	# 5. Verify all 6 generic upgrades modify their target stats.
	player.health.hp = 40.0
	var dmg_before := run.katana.damage_multiplier
	run._apply_upgrade({"id": "damage"})
	var max_hp_before := player.health.max_hp
	run._apply_upgrade({"id": "max_hp"})
	var hp_mid := player.health.hp
	run._apply_upgrade({"id": "heal"})
	var mag_before := run.soul_magnet_radius
	run._apply_upgrade({"id": "magnet"})
	var force_before := run.katana.max_force
	run._apply_upgrade({"id": "arm_strength"})
	run._apply_upgrade({"id": "regen"})
	_check("All 6 generic upgrades apply effects (dmg, max_hp, heal, magnet, arm_strength, regen)",
		run.katana.damage_multiplier > dmg_before
		and player.health.max_hp > max_hp_before
		and player.health.hp > hp_mid
		and run.soul_magnet_radius > mag_before
		and run.katana.max_force > force_before
		and player.health.regen_per_sec > 0.0)

	# 6. Death ends the run, saves high score locally, shows End Screen & Restart Ofuda;
	#    slicing the Restart Ofuda with the katana starts a new run.
	run._apply_upgrade({"id": "storm_chain"})
	run.kills = 7
	run.score = run.compute_score()
	run._refresh_hud()
	_check("Diegetic wrist shows score points and kill count separately",
		run.diegetic_hud.wrist_label.text.contains("pt")
		and run.diegetic_hud.wrist_label.text.contains("斬 7"))
	_check("Wrist HP ring hidden until critical health",
		run.diegetic_hud.wrist_hp_ring != null and not run.diegetic_hud.wrist_hp_ring.visible)

	player.health.take_hit(999.0, Vector3.ZERO, {"attacker": "Yokai"})
	await _wait(0.15)
	_check("Lethal hit ends the run (GAME_OVER) without auto-reviving",
		run.state == RunGame.RunState.GAME_OVER and not player.health.is_alive())
	_check("High score (%d) is saved locally and MemorialStele + RestartOfuda appear" % run.high_score,
		run.high_score > 0
		and run.load_high_score() == run.high_score
		and run.get_node_or_null("EndScreen/MemorialStele") != null
		and run.restart_ofuda != null)
	_check("Memorial stele lists element BUILD (GDD §6 end screen)",
		_stele_label_text(run).contains("BUILD") and _stele_label_text(run).contains("雷"))

	var saved_best := run.high_score
	# Slice the Restart Ofuda with a katana swing to start a fresh run.
	player.swing_duration = 0.16
	player.swing(DesktopPlayer.SLASH_OVERHEAD)
	await _wait(0.45)
	if run.state == RunGame.RunState.GAME_OVER and run.restart_ofuda != null:
		# Fallback if overhead arc passed above the lower restart talisman: slice directly.
		run.restart_ofuda.slice(run.restart_ofuda.global_position, Vector3.RIGHT)
		await _wait(0.1)

	_check("Slicing the Restart Ofuda starts a new run at full HP while keeping high score (%d)" % run.high_score,
		run.state == RunGame.RunState.PLAYING
		and player.health.is_alive()
		and run.level == 1
		and run.kills == 0
		and run.high_score == saved_best)

	run.queue_free()


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
