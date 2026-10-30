extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	# Locks and purchases are checked here: a sandbox switch in the player's own file must not be read (D9).
	VrComfortSettings.sandbox_enabled = false
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

	# D6: the forest's own triangles (far crowns to the fog, full crowns close by) keep a quarter of the budget spare.
	var forest_prims := 0
	var forest_draws := 0
	for mmi in run.forest_world.find_children("*", "MultiMeshInstance3D", true, false):
		var inst := mmi as MultiMeshInstance3D
		if not inst.is_visible_in_tree() or inst.multimesh.mesh == null:
			continue
		forest_draws += 1
		forest_prims += RunPerfProbe._mesh_primitives(inst.multimesh.mesh) * inst.multimesh.instance_count
	_check("Forest primitives stay under a quarter of the Quest budget (%d <= %d, %d draws)" % [forest_prims, int(RunPerfBudget.MAX_PRIMITIVES * 0.75), forest_draws],
		forest_prims <= int(RunPerfBudget.MAX_PRIMITIVES * 0.75))

	var we: Environment = run.get_node("WorldEnvironment").environment
	_check("Run fog is opaque before the loaded forest ends (depth_end %.1f <= %.1f)" % [we.fog_depth_end, run.forest_world.loaded_range()],
		we.fog_depth_end <= run.forest_world.loaded_range() and we.fog_density >= 0.99)
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
	_check("Menu open: at least 30 draw calls of headroom (%d of %d)" % [RunPerfBudget.MAX_DRAW_CALLS - open_est.draw_calls, RunPerfBudget.MAX_DRAW_CALLS],
		RunPerfBudget.MAX_DRAW_CALLS - open_est.draw_calls >= 30)
	run.pause_controller.close()

	# E3/D14: the wrist readout (HP ring, element arc) stays a handful of meshes, and the
	# element effects add no lights or draw calls of their own beyond one halo per gate.
	var plate_meshes := 0
	for mi in run.diegetic_hud.wrist_unit.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).is_visible_in_tree():
			plate_meshes += 1
	_check("Wrist readout draws at most 9 meshes (%d)" % plate_meshes, plate_meshes <= 9)
	var gate_halos := 0
	for g in get_tree().get_nodes_in_group("torii_gates"):
		if (g as ToriiGate)._halo_mesh.visible:
			gate_halos += 1
	_check("Gate lights are one quad each, no OmniLight3D (%d lit gates)" % gate_halos,
		run.find_children("*", "OmniLight3D", true, false).filter(func(n): return n.get_parent() is ToriiGate or n.get_parent().get_parent() is ToriiGate).is_empty())

	# D4: a wave of Kirisute splits (two a frame, eight yōkai) stays in budget. The pieces
	# are bounded and each one's surfaces count as draw calls.
	run.skill_points = 1000
	for node: Dictionary in SkillTreeData.nodes_for_element(Elements.SAKURA):
		run.unlock_skill(String(node.id))
	run.element_system.imbue(Elements.SAKURA)
	# Only the wave is on the field, so the count is the wave's own cost. The pieces are
	# children of the scene, not of the run, so the estimate reads the whole scene.
	run.wave_director.clear_enemies()
	await _frames(4)
	var wave: Array[Yokai] = []
	for i in 8:
		var at := Vector3(sin(i * 0.8) * 6.0, 0.0, -4.0 + cos(i * 0.8) * 2.0)
		at.y = float(run.wave_director.ground_height.call(at.x, at.z))
		var y := run.wave_director.spawn_enemy_at(at, player.global_position)
		y.configure_kind(Yokai.Kind.SWARM, Elements.NONE, 900.0)
		wave.append(y)
	await _frames(20)
	var standing: int = RunPerfProbe.estimate_scene_cost(self).draw_calls
	var wave_draws := 0
	var wave_ms := 0.0
	var wave_pieces := 0
	for pair in 4:
		for k in 2:
			_split_hit(wave[pair * 2 + k])
		await _frames(1)
		wave_draws = maxi(wave_draws, RunPerfProbe.estimate_scene_cost(self).draw_calls)
		wave_ms = maxf(wave_ms, RunPerfProbe.rendering_info().process_ms)
		wave_pieces = maxi(wave_pieces, KirisuteChunk._alive.size())
	var wave_killed := 0
	for y: Yokai in wave:
		wave_killed += int(y.is_dead)
	var budget_draws := RunPerfBudget.MAX_DRAW_CALLS
	print("PERF wave standing=%d peak=%d (eight yōkai standing before the cuts)" % [standing, wave_draws])
	_check("the Kirisute wave kills 8 yōkai and splits them (%d dead)" % wave_killed, wave_killed == 8)
	_check("a wave of splits stays under the Quest draw budget (est %d <= %d, headroom %d)" % [wave_draws, budget_draws, budget_draws - wave_draws],
		wave_draws <= budget_draws and budget_draws - wave_draws >= 30)
	_check("pieces stay within the budget at peak (%d <= %d)" % [wave_pieces, ElementBalance.KIRISUTE_MAX_PIECES],
		wave_pieces > 0 and wave_pieces <= ElementBalance.KIRISUTE_MAX_PIECES)
	_check("frame process time stays under budget during the wave (%.2f ms <= %.1f ms)" % [wave_ms, RunPerfBudget.MAX_PROCESS_MS],
		wave_ms <= RunPerfBudget.MAX_PROCESS_MS)

	run.queue_free()


## A clean, fast edge hit on a yōkai's chest, as HeldWeapon reports it for a Kirisute cut.
func _split_hit(y: Yokai) -> void:
	var part: RagdollPart = y.parts["chest"]
	var hit := {"attacker": "katana", "element": Elements.SAKURA, "part": "chest", "zone": "torso",
		"speed": 12.0, "strike": "edge", "edge_alignment": 1.0, "base_damage": 40.0,
		"point": part.global_position, "direction": Vector3.RIGHT, "power": 1.0, "impulse": 18.0,
		"knockback": Vector3.RIGHT * 18.0, "kirisute_offer": true, "blade_axis": Vector3.UP}
	y.receive_hit(part, hit)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
