extends Node
## Headless coverage for docs/NIGHT_PLAN.md item 2:
## four gated element trees, two-element / six-slot cap, combat effects,
## both evolutions, seal progress and bounded Quest-oriented VFX.

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_elements_high_score.cfg"

var failures := 0
var run: RunGame
var player: DesktopPlayer


func _ready() -> void:
	await _run_all()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = TEST_SAVE_PATH
	add_child(run)
	await _frames(12)
	player = run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)

	_test_pool_and_limits()
	await _test_storm_and_ink()
	await _test_sakura_and_shadow()
	run.queue_free()


func _test_pool_and_limits() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var first_hand := UpgradePool.pick_choices(3, {}, 1.0, rng, [], 0)
	_check("Every eligible Ofuda hand exposes an element choice",
		first_hand.any(func(c: Dictionary) -> bool: return c.has("element")))
	var tier_two_locked := UpgradePool.available_element_upgrades({}, [Elements.SAKURA])
	_check("Element trees are ordered; Sakura II is locked before Sakura I",
		not tier_two_locked.any(func(c: Dictionary) -> bool: return String(c.id) == "sakura_orbit"))

	run._apply_upgrade({"id": "storm_chain"})
	run._apply_upgrade({"id": "ink_pool"})
	run._apply_upgrade({"id": "sakura_petals"})
	_check("A run binds at most two elements",
		run.element_system.active_elements == [Elements.STORM, Elements.INK]
		and not run.upgrade_stacks.has("sakura_petals"))


func _test_storm_and_ink() -> void:
	run._apply_upgrade({"id": "storm_charge"})
	run._apply_upgrade({"id": "storm_overload"})
	run._apply_upgrade({"id": "ink_tendrils"})
	run._apply_upgrade({"id": "ink_depth"})
	_check("Two complete trees occupy six element slots",
		UpgradePool.element_slot_count(run.upgrade_stacks) == 6)
	_check("Storm + Ink evolves into black lightning and colors the blade",
		run.element_system.has_evolution(Elements.BLACK_LIGHTNING)
		and run.katana.element == Elements.BLACK_LIGHTNING)

	var e1 := run.wave_director.spawn_enemy_at(Vector3(-0.7, 0.0, -0.8), player.global_position)
	var e2 := run.wave_director.spawn_enemy_at(Vector3(0.5, 0.0, -1.1), player.global_position)
	var e3 := run.wave_director.spawn_enemy_at(Vector3(1.2, 0.0, -1.5), player.global_position)
	await _frames(5)
	var hp_before := [e1.hp, e2.hp, e3.hp]
	run.element_system.on_blade_hit({
		"attacker": run.katana.weapon_name,
		"damage": 20.0,
		"point": ElementSystem._enemy_center(e1),
		"direction": Vector3.RIGHT,
	})
	await _frames(3)
	_check("Storm chains through several nearby yōkai",
		e1.hp < hp_before[0] and e2.hp < hp_before[1])
	_check("Black lightning paints Ink pools at chained targets",
		run.element_system._ink_pools.size() >= 2)

	run.element_system.storm_charge = 1.0
	var charged_before := e3.hp
	run.element_system._chain_cooldown = 1.0
	run.element_system.on_blade_hit({
		"attacker": run.katana.weapon_name,
		"damage": 25.0,
		"point": ElementSystem._enemy_center(e3),
		"direction": Vector3.FORWARD,
	})
	_check("A fully charged Storm strike discharges bonus damage",
		run.element_system.storm_charge == 0.0 and e3.hp < charged_before)

	run.element_system.paint_ink(ElementSystem._enemy_center(e1))
	await _seconds(0.28)
	_check("Ink pools slow yōkai standing in the painted area", e1.is_slowed())
	var ink_hp := e1.hp
	await _seconds(1.1)
	_check("Ink tendrils damage trapped yōkai", e1.is_dead or e1.hp < ink_hp)

	for i in 9:
		run.element_system.paint_ink(Vector3(float(i) * 0.1, 0.0, -0.4))
	_check("Ink VFX pool is hard-capped for Quest", run.element_system._ink_pools.size() <= ElementSystem.MAX_INK_POOLS)
	for i in 20:
		run.element_system._spawn_shadow_trace(Vector3.ZERO, Vector3(float(i % 3), 1.0, -2.0))
	_check("Short-lived mesh VFX are hard-capped for Quest",
		run.element_system._transients.size() <= ElementSystem.MAX_TRANSIENT_MESHES)

	var seal := run.get_node("Arena/SpawnSeal") as MeshInstance3D
	var seal_mat := seal.material_override as ShaderMaterial
	_check("Spawn seal lights both element quadrants and the evolution star",
		int(seal_mat.get_shader_parameter("active_elements_mask")) == 6
		and int(seal_mat.get_shader_parameter("evolution_mask")) == 1)


func _test_sakura_and_shadow() -> void:
	run.start_run()
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)
	for id in ["sakura_petals", "sakura_orbit", "sakura_heal", "shadow_blink", "shadow_darkness", "shadow_veil"]:
		run._apply_upgrade({"id": id})
	_check("Sakura + Shadow evolves into phantom petals",
		run.element_system.has_evolution(Elements.PHANTOM_PETALS)
		and run.katana.element == Elements.PHANTOM_PETALS)
	_check("Sakura creates the evolved five-blade orbit",
		run.element_system._orbit_petals.size() == 5)

	var petal_target := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -1.0), player.global_position)
	await _frames(4)
	var petal_hp := petal_target.hp
	run.element_system.debug_release_petals(
		(ElementSystem._enemy_center(petal_target) - run.katana.get_tip_global()).normalized())
	await _seconds(0.55)
	_check("Cutting phantom petals seek, damage and confuse yōkai",
		petal_target.is_dead or petal_target.hp < petal_hp)
	for i in 5:
		run.element_system.debug_release_petals(Vector3.FORWARD)
	_check("Flying petal meshes are hard-capped for Quest",
		run.element_system._petals.size() <= ElementSystem.MAX_PETALS)

	player.health.hp = 60.0
	run.element_system.on_enemy_died(petal_target)
	_check("Maxed Sakura grants light healing", player.health.hp > 60.0)

	var before_blink := player.global_position
	var confused := run.wave_director.spawn_enemy_at(before_blink + Vector3(-2.2, 0.0, 0.0), player.global_position)
	await _frames(3)
	var blinked := run.element_system.try_shadow_blink(Vector3.LEFT)
	await _frames(3)
	_check("Shadow performs a short bounded combat blink",
		blinked and player.global_position.distance_to(before_blink) > 1.0
		and player.global_position.distance_to(before_blink) < 3.1)
	_check("Blink darkness confuses nearby enemies",
		confused.is_confused() and not run.element_system._darkness_areas.is_empty())

	var seal := run.get_node("Arena/SpawnSeal") as MeshInstance3D
	var seal_mat := seal.material_override as ShaderMaterial
	_check("Phantom-petal seal state uses Sakura + Shadow and evolution mark",
		int(seal_mat.get_shader_parameter("active_elements_mask")) == 9
		and int(seal_mat.get_shader_parameter("evolution_mask")) == 2)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(int(seconds * Engine.physics_ticks_per_second))
