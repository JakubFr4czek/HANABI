extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(20)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var player := run.player as DesktopPlayer
	player.teleport(Vector3(0.0, 0.0, 1.2), 0.0)

	for i in 8:
		run.wave_director.spawn_enemy_at(
			Vector3(sin(i * 0.9) * 7.5, 0.0, cos(i * 0.9) * 7.5),
			player.global_position)
	run.upgrade_stacks["storm_chain"] = 1
	run.upgrade_stacks["sakura_petals"] = 1
	run.upgrade_stacks["ink_pool"] = 1
	# Element cards retired (E2b): imbue via the Torii-gate path for VFX load.
	run.element_system.imbue(Elements.STORM)
	run.element_system.debug_release_petals(Vector3.FORWARD)
	await _frames(8)
	if VfxPool:
		for i in 3:
			VfxPool.spawn_firework_flash(run, Vector3(1.6 * i - 1.6, 1.1, -3.2), Color(1.0, 0.4, 0.5), 1.0)
	ElementFirework.spawn(run, Vector3(0.0, 1.2, -3.0), Elements.STORM, 0.95)
	await _frames(12)

	var peak := {"draw_calls": 0, "primitives": 0, "process_ms": 0.0, "lights": 0, "voices": 0}
	for _f in 24:
		await get_tree().physics_frame
		var s := RunPerfProbe.rendering_info()
		peak.draw_calls = maxi(peak.draw_calls, s.draw_calls)
		peak.primitives = maxi(peak.primitives, s.primitives)
		peak.process_ms = maxf(peak.process_ms, s.process_ms)
		peak.lights = maxi(peak.lights, RunPerfProbe.count_dynamic_lights(run))
		peak.voices = maxi(peak.voices, RunPerfProbe.count_audio_voices(run))
	var est := RunPerfProbe.estimate_scene_cost(run)
	if peak.draw_calls <= 0:
		peak.draw_calls = est.draw_calls
	if peak.primitives <= 0:
		peak.primitives = est.primitives

	var bodies := RunPerfProbe.count_yokai_physics_bodies(run)
	var particles := RunPerfProbe.estimate_particles(run)
	var lights := maxi(RunPerfProbe.count_dynamic_lights(run), peak.lights)
	var voices := maxi(RunPerfProbe.count_audio_voices(run), peak.voices)
	print("PERF peak draw=%d prims=%d process_ms=%.2f bodies=%d particles~=%d lights=%d audio~=%d (baseline draw=%d prims=%d ms=%.1f)"
		% [peak.draw_calls, peak.primitives, peak.process_ms, bodies, particles, lights, voices,
			RunPerfBudget.BASELINE_DRAW_CALLS, RunPerfBudget.BASELINE_PRIMITIVES, RunPerfBudget.BASELINE_PROCESS_MS])

	_check("Draw calls under Quest budget (%d <= %d)" % [peak.draw_calls, RunPerfBudget.MAX_DRAW_CALLS],
		peak.draw_calls <= RunPerfBudget.MAX_DRAW_CALLS)
	_check("Triangle budget via primitives (%d <= %d)" % [peak.primitives, RunPerfBudget.MAX_PRIMITIVES],
		peak.primitives <= RunPerfBudget.MAX_PRIMITIVES)
	_check("Frame process time under budget (%.2f ms <= %.1f ms)"
		% [peak.process_ms, RunPerfBudget.MAX_PROCESS_MS],
		peak.process_ms <= RunPerfBudget.MAX_PROCESS_MS)
	_check("Yōkai physics bodies bounded (%d <= %d)" % [bodies, RunPerfBudget.MAX_YOKAI_PHYSICS_BODIES],
		bodies <= RunPerfBudget.MAX_YOKAI_PHYSICS_BODIES)
	_check("Particle estimate within 2–4k cap (%d <= %d)" % [particles, RunPerfBudget.MAX_PARTICLES],
		particles <= RunPerfBudget.MAX_PARTICLES)
	_check("Dynamic OmniLights bounded (%d <= %d)" % [lights, RunPerfBudget.MAX_DYNAMIC_LIGHTS],
		lights <= RunPerfBudget.MAX_DYNAMIC_LIGHTS)
	_check("Simultaneous audio voices bounded (%d <= %d)" % [voices, RunPerfBudget.MAX_AUDIO_VOICES],
		voices <= RunPerfBudget.MAX_AUDIO_VOICES)

	var we: Environment = run.get_node("WorldEnvironment").environment
	_check("Run fog is opaque before the loaded forest ends (depth_end %.1f <= %.1f)" % [we.fog_depth_end, ForestWorld.VIEW_RANGE_END],
		we.fog_depth_end <= ForestWorld.VIEW_RANGE_END and we.fog_density >= 0.99)
	_check("Forest uses shader baked-look instead of per-chunk LightmapGI",
		run.forest_world.uses_shader_baked_look())

	# E2d: the skill-tree menu open on top of the same stressed scene stays in budget.
	var menu := run.pause_controller.menu
	run.pause_controller.open()
	var feet := player.global_position
	menu.update_pointer("mouse", feet + Vector3(0.0, 1.65, 0.0), -menu.global_basis.z, false, false)
	await _frames(6)
	var menu_draws := 0
	for mi in menu.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).is_visible_in_tree():
			menu_draws += 1
	var open_est := RunPerfProbe.estimate_scene_cost(run)
	var open_lights := RunPerfProbe.count_dynamic_lights(run)
	var open_voices := RunPerfProbe.count_audio_voices(run)
	_check("Menu open: the panel and pointers add at most 6 draw calls (%d)" % menu_draws, menu_draws >= 1 and menu_draws <= 6)
	_check("Menu open: draw calls still under Quest budget (%d <= %d)" % [open_est.draw_calls, RunPerfBudget.MAX_DRAW_CALLS],
		open_est.draw_calls <= RunPerfBudget.MAX_DRAW_CALLS)
	_check("Menu open: no extra lights (%d <= %d) and voices stay bounded (%d <= %d)" % [open_lights, RunPerfBudget.MAX_DYNAMIC_LIGHTS, open_voices, RunPerfBudget.MAX_AUDIO_VOICES],
		open_lights <= RunPerfBudget.MAX_DYNAMIC_LIGHTS and open_voices <= RunPerfBudget.MAX_AUDIO_VOICES)
	_check("Menu open: its viewport updates on change only, not every frame",
		menu._viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS)
	run.pause_controller.close()

	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
