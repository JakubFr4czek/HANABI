extends Node
## Renders screenshots of the RunGame loop (waves of yōkai, hitodama soul drops,
## diegetic HUD on tsuba & wrist, 3 floating Ofuda in slow-mo, sliced Ofuda,
## and in-world Game Over memorial stele + Restart Ofuda) for visual critique.

const RUN_SCENE := preload("res://scenes/run.tscn")

var out_dir := "/tmp/hanabi_run_shots"
var run: RunGame
var player: DesktopPlayer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://screenshots_high_score.cfg"
	add_child(run)
	player = run.player as DesktopPlayer
	run.wave_director.stop_director()
	await _frames(30)

	# 1. Yōkai pack emerging from the water mist onto the stone platform + Diegetic HUD
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-6.0)
	run.xp = 16
	run.xp_to_next = 24
	run.score = 340
	run.run_time = 42.0
	var e1 := run.wave_director.spawn_enemy_at(Vector3(-0.95, 0.0, -0.35), player.global_position)
	var e2 := run.wave_director.spawn_enemy_at(Vector3(0.85, 0.0, -0.85), player.global_position)
	var e3 := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -2.4), player.global_position)
	var _e4 := run.wave_director.spawn_enemy_at(Vector3(-2.3, 0.0, -3.9), player.global_position)
	await _frames(32)
	e1.brain.force_attack("right")
	await _frames(16)
	await _shot("1_yokai_wave_and_hud")

	# 1b. Endless forest hills, torii and lanterns swallowed by run fog.
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-8.0)
	run.wave_director.clear_enemies()
	await _frames(20)
	await _shot("1b_forest_horizon")

	# 2. Slain yōkai dissolving + Hitodama soul orbs swirling in toward the player
	if is_instance_valid(e1):
		e1.queue_free()
	e2.last_kill_element = Elements.SAKURA
	e2.die({"element": Elements.SAKURA})
	e3.last_kill_element = Elements.STORM
	e3.die({"element": Elements.STORM})
	SoulOrb.spawn_cluster(run._souls_root, Vector3(0.32, 1.05, 0.75), 5, 6, Elements.STORM)
	SoulOrb.spawn_cluster(run._souls_root, Vector3(-0.42, 0.98, 0.85), 5, 6, Elements.SAKURA)
	await _frames(18)
	await _shot("2_hitodama_souls")

	# 3. Level-up slow motion: 3 floating Ofuda talismans in front of the player
	run.wave_director.clear_enemies()
	run._clear_souls()
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	player.camera.rotation.x = deg_to_rad(-4.0)
	run.add_xp(run.xp_to_next)
	await _frames(25)
	await _shot("3_ofuda_level_up")

	# 4. Slicing the center Ofuda in half with the katana
	if run.active_ofuda.size() >= 2:
		var middle := run.active_ofuda[1]
		middle.slice(middle.global_position, Vector3(1.0, 0.25, 0.0))
	await _frames(10)
	await _shot("4_ofuda_sliced")

	await _frames(40)

	# 5. Sakura + Shadow build: phantom petal orbit, seeking cuts and darkness.
	run.start_run()
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	for id in ["sakura_petals", "sakura_orbit", "sakura_heal", "shadow_blink", "shadow_darkness", "shadow_veil"]:
		run._apply_upgrade({"id": id})
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	var phantom_target := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -0.7), player.global_position)
	run.wave_director.spawn_enemy_at(Vector3(-1.15, 0.0, -1.25), player.global_position)
	run.wave_director.spawn_enemy_at(Vector3(1.1, 0.0, -1.45), player.global_position)
	await _frames(10)
	run.element_system._spawn_darkness(Vector3(0.0, 0.0, -1.0))
	run.element_system.debug_release_petals(
		(ElementSystem._enemy_center(phantom_target) - run.katana.get_tip_global()).normalized())
	await _frames(2)
	await _shot("5_phantom_petals")

	# 6. Storm + Ink build: restrained black-lightning chains over glossy Sumi pools.
	run.start_run()
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	for id in ["storm_chain", "storm_charge", "storm_overload", "ink_pool", "ink_tendrils", "ink_depth"]:
		run._apply_upgrade({"id": id})
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-12.0)
	var ink_e1 := run.wave_director.spawn_enemy_at(Vector3(-0.75, 0.0, -0.55), player.global_position)
	var ink_e2 := run.wave_director.spawn_enemy_at(Vector3(0.55, 0.0, -1.0), player.global_position)
	var ink_e3 := run.wave_director.spawn_enemy_at(Vector3(1.35, 0.0, -1.75), player.global_position)
	await _frames(8)
	for enemy in [ink_e1, ink_e2, ink_e3]:
		enemy.hp = 300.0
		run.element_system.paint_ink(ElementSystem._enemy_center(enemy))
	await _frames(20)
	run.element_system.storm_charge = 1.0
	run.element_system.on_blade_hit({
		"attacker": run.katana.weapon_name,
		"damage": 28.0,
		"point": ElementSystem._enemy_center(ink_e1),
		"direction": Vector3.RIGHT,
	})
	await _frames(28)
	await _shot("6_black_lightning_ink")

	# 7. End screen in the world: Memorial Stele + Restart Ofuda
	run.kills = 14
	run.level = 5
	run.run_time = 135.0
	run.upgrade_stacks = {"damage": 2, "arm_strength": 1, "magnet": 1}
	run._clear_souls()
	run.element_system._clear_runtime_vfx()
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-5.0)
	player.health.take_hit(999.0, Vector3.ZERO, {"attacker": "Yokai"})
	await _frames(30)
	await _shot("7_end_screen_stele")

	if FileAccess.file_exists("user://screenshots_high_score.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://screenshots_high_score.cfg"))
	get_tree().quit(0)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	else:
		await _frames(2)
	var tex := get_viewport().get_texture()
	if tex == null:
		push_warning("run_screenshots: no viewport texture for %s" % shot_name)
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		push_warning("run_screenshots: empty image for %s" % shot_name)
		return
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)
