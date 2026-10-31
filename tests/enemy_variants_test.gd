extends Node
## Headless coverage for docs/NIGHT_PLAN.md item 4:
## elite resistances/weaknesses, parry-armor gate, Oni boss timer, navigation agents.

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
	await _frames(12)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var player := run.player as DesktopPlayer

	var elite := run.wave_director.spawn_elite_at(Vector3(2.0, 0.0, -3.0), player.global_position, Elements.STORM)
	_check("Elite yōkai spawn with an element identity", elite.is_elite() and elite.body_element == Elements.STORM)
	var chest := elite.parts["chest"] as RagdollPart
	var storm_hit := {
		"base_damage": 20.0, "zone": "torso", "element": Elements.STORM,
		"point": chest.global_position, "knockback": Vector3.ZERO,
	}
	var weak_hit := storm_hit.duplicate()
	weak_hit.element = Elements.INK
	elite.hp = elite.profile.max_hp
	elite.receive_hit(chest, storm_hit)
	var storm_dmg := float(storm_hit.damage)
	elite.hp = elite.profile.max_hp
	elite.receive_hit(chest, weak_hit)
	_check("Elite resists its own element and is weak to the counter element",
		storm_dmg < weak_hit.damage * 0.85)

	elite.hp = elite.profile.max_hp
	elite.brain._enter(YokaiBrain.State.APPROACH)
	var armored := {
		"base_damage": 24.0, "zone": "torso", "element": "physical",
		"point": chest.global_position, "knockback": Vector3.ZERO,
	}
	elite.receive_hit(chest, armored)
	var armored_dmg := float(armored.damage)
	elite.brain._enter(YokaiBrain.State.STAGGER)
	elite.hp = elite.profile.max_hp
	var opened := armored.duplicate()
	elite.receive_hit(chest, opened)
	_check("Elite parry-armor shrinks physical hits until staggered",
		armored_dmg < float(opened.damage) * 0.85 and armored_dmg < 24.0 * 0.35)

	_check("Swarm yōkai use NavigationAgent3D pathing",
		elite._nav_agent != null and elite.use_pathfinding)

	# D17: swarm yōkai roll a school by the wave's weights (plain share eases over the ramp),
	# and the spawner hands that school to the body and its profile.
	var weights := WaveProfile.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var start_counts := {}
	for i in 4000:
		var school := weights.roll_swarm_element(0.0, rng)
		start_counts[school] = int(start_counts.get(school, 0)) + 1
	var plain_start := float(start_counts.get(Elements.NONE, 0)) / 4000.0
	_check("calm start: about 70 %% of swarm yōkai are plain steel (got %.2f)" % plain_start,
		absf(plain_start - 0.70) < 0.03)
	var schools_even := true
	for e: String in Elements.COMBAT_ELEMENTS:
		var share := float(start_counts.get(e, 0)) / 4000.0
		schools_even = schools_even and absf(share - 0.075) < 0.02
	_check("schools share the rest evenly at equal weights", schools_even)
	var full_counts := {}
	for i in 4000:
		var school := weights.roll_swarm_element(weights.ramp_seconds, rng)
		full_counts[school] = int(full_counts.get(school, 0)) + 1
	var plain_full := float(full_counts.get(Elements.NONE, 0)) / 4000.0
	_check("ramp end: about 35 %% of swarm yōkai are plain (got %.2f)" % plain_full, absf(plain_full - 0.35) < 0.03)

	var school_bodies_ok := true
	for e: String in Elements.COMBAT_ELEMENTS:
		var swarm := run.wave_director.spawn_enemy_at(Vector3(-3.0, 0.0, -4.0), player.global_position, e)
		school_bodies_ok = school_bodies_ok and swarm.kind == Yokai.Kind.SWARM \
			and swarm.body_element == e and swarm.profile.element == e
	_check("spawner gives a swarm yōkai of each school its element (body and profile)", school_bodies_ok)
	run.wave_director.clear_enemies()

	# N3: the yōkai wear the demon mask and have no boxes on the head or the torso; one
	# yōkai stays inside the triangle and draw-call budget (RunPerfBudget).
	var forms_swarm := run.wave_director.spawn_enemy_at(Vector3(-3.0, 0.0, -4.0), player.global_position, Elements.STORM)
	var forms_elite := run.wave_director.spawn_elite_at(Vector3(3.0, 0.0, -4.0), player.global_position, Elements.INK)
	await _frames(2)
	for y: Yokai in [forms_swarm, forms_elite]:
		var who := "elite" if y.is_elite() else "swarm"
		var head := y.parts["head"] as RagdollPart
		var masks := 0
		for c in head.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh == YokaiForms.mask_mesh():
				masks += 1
		_check("%s yōkai wears the demon mask on its head (%d masks)" % [who, masks], masks == 1)
		var boxes := 0
		for part_name in ["head", "chest", "pelvis"]:
			for c in (y.parts[part_name] as RagdollPart).get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
					boxes += 1
		_check("%s yōkai has no boxes on head, chest or pelvis (%d)" % [who, boxes], boxes == 0)
		var cost := RunPerfProbe.yokai_cost(y)
		_check("%s yōkai stays within %d triangles (%d)" % [who, RunPerfBudget.MAX_YOKAI_TRIANGLES, cost.tris],
			cost.tris <= RunPerfBudget.MAX_YOKAI_TRIANGLES)
		_check("%s yōkai stays within %d draw surfaces (%d)" % [who, RunPerfBudget.MAX_YOKAI_DRAWS, cost.draws],
			cost.draws <= RunPerfBudget.MAX_YOKAI_DRAWS)
	run.wave_director.clear_enemies()

	# The Oni's timing is the planner's cue (tests/run_loop_test.gd); here the director
	# just has to summon a working duelist when asked.
	run.wave_director.active = true
	run.wave_director.spawn_oni_boss(player.global_position)
	await _frames(4)
	_check("Wave director summons a duelist Oni boss", run.wave_director.has_active_oni())
	var oni: RunOniBoss = run.wave_director.get_active_oni()
	_check("Oni uses DuelistBrain with attacks enabled",
		oni.brain is DuelistBrain and oni.attacks_enabled())

	oni.hp = 1.0
	var oni_chest := oni.parts["chest"] as RagdollPart
	oni.receive_hit(oni_chest, {
		"base_damage": 40.0, "zone": "torso", "element": "physical",
		"point": oni_chest.global_position, "knockback": Vector3.ZERO,
	})
	var defeat_wait := int((oni.profile.knockdown_time + oni.profile.getup_time + 0.2) * Engine.physics_ticks_per_second)
	await _frames(defeat_wait)
	_check("Oni boss is defeated permanently instead of reviving",
		not run.wave_director.has_active_oni())

	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
