extends Node
## Headless coverage for docs/NIGHT_PLAN.md item 2:
## four gated element trees, one-element lock-in, combat effects per tree,
## seal progress and bounded Quest-oriented VFX.

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
	await _test_storm()
	await _test_ink()
	await _test_sakura()
	await _test_shadow()
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

	run.katana.set_element(Elements.NONE)
	run.element_system.reset()
	run._apply_upgrade({"id": "storm_chain"})
	_check("Level-up upgrade does not grant element to katana (remains NONE)", run.katana.element == Elements.NONE)
	run.element_system.imbue(Elements.STORM, 20.0)
	_check("Torii gate imbue binds element to blade for 20s", run.katana.element == Elements.STORM and run.element_system.element_time_remaining == 20.0)
	run._apply_upgrade({"id": "ink_pool"})
	run._apply_upgrade({"id": "sakura_petals"})
	_check("A run locks into a single upgrade element tree; later elements are refused",
		not run.upgrade_stacks.has("ink_pool")
		and not run.upgrade_stacks.has("sakura_petals"))


func _fresh_run() -> void:
	run.start_run()
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)


func _test_storm() -> void:
	run._apply_upgrade({"id": "storm_charge"})
	run._apply_upgrade({"id": "storm_overload"})
	run.element_system.imbue(Elements.STORM)
	run._update_element_seal()
	_check("One complete tree occupies three element slots",
		UpgradePool.element_slot_count(run.upgrade_stacks) == 3)
	_check("The bound element colors the blade",
		run.katana.element == Elements.STORM)

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

	for i in 20:
		run.element_system._spawn_shadow_trace(Vector3.ZERO, Vector3(float(i % 3), 1.0, -2.0))
	_check("Short-lived mesh VFX are hard-capped for Quest",
		run.element_system._transients.size() <= ElementSystem.MAX_TRANSIENT_MESHES)

	_check("Spawn seal lights the Storm quadrant and no evolution star",
		int((run.get_node("Arena/SpawnSeal") as MeshInstance3D).material_override.get_shader_parameter("active_elements_mask")) == 2
		and int((run.get_node("Arena/SpawnSeal") as MeshInstance3D).material_override.get_shader_parameter("evolution_mask")) == 0)


func _test_ink() -> void:
	await _fresh_run()
	for id in ["ink_pool", "ink_tendrils", "ink_depth"]:
		run._apply_upgrade({"id": id})
	run.element_system.imbue(Elements.INK)
	run._update_element_seal()
	_check("Ink binds alone and colors the blade", run.katana.element == Elements.INK)

	var victim := run.wave_director.spawn_enemy_at(Vector3(-0.7, 0.0, -0.8), player.global_position)
	await _frames(5)
	run.element_system.paint_ink(ElementSystem._enemy_center(victim))
	await _seconds(0.28)
	_check("Ink pools slow yōkai standing in the painted area", victim.is_slowed())
	var ink_hp := victim.hp
	await _seconds(1.1)
	_check("Ink tendrils damage trapped yōkai", victim.is_dead or victim.hp < ink_hp)

	for i in 9:
		run.element_system.paint_ink(Vector3(float(i) * 0.1, 0.0, -0.4))
	_check("Ink VFX pool is hard-capped for Quest", run.element_system._ink_pools.size() <= ElementSystem.MAX_INK_POOLS)
	_check("Spawn seal lights the Ink quadrant and no evolution star",
		int((run.get_node("Arena/SpawnSeal") as MeshInstance3D).material_override.get_shader_parameter("active_elements_mask")) == 4
		and int((run.get_node("Arena/SpawnSeal") as MeshInstance3D).material_override.get_shader_parameter("evolution_mask")) == 0)


func _test_sakura() -> void:
	await _fresh_run()
	for id in ["sakura_petals", "sakura_orbit", "sakura_heal"]:
		run._apply_upgrade({"id": id})
	run.element_system.imbue(Elements.SAKURA)
	run._update_element_seal()
	_check("Sakura binds alone and colors the blade", run.katana.element == Elements.SAKURA)
	_check("Sakura creates a three-blade orbit",
		run.element_system._orbit_petals.size() == 3)

	var petal_target := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -1.0), player.global_position)
	await _frames(4)
	var petal_hp := petal_target.hp
	run.element_system.debug_release_petals(
		(ElementSystem._enemy_center(petal_target) - run.katana.get_tip_global()).normalized())
	await _seconds(0.55)
	_check("Cutting petals damage yōkai",
		petal_target.is_dead or petal_target.hp < petal_hp)
	for i in 5:
		run.element_system.debug_release_petals(Vector3.FORWARD)
	_check("Flying petal meshes are hard-capped for Quest",
		run.element_system._petals.size() <= ElementSystem.MAX_PETALS)

	player.health.hp = 60.0
	run.element_system.on_enemy_died(petal_target)
	_check("Sakura grants light healing on a kill", player.health.hp > 60.0)
	_check("Spawn seal lights the Sakura quadrant and no evolution star",
		int((run.get_node("Arena/SpawnSeal") as MeshInstance3D).material_override.get_shader_parameter("active_elements_mask")) == 1
		and int((run.get_node("Arena/SpawnSeal") as MeshInstance3D).material_override.get_shader_parameter("evolution_mask")) == 0)


func _test_shadow() -> void:
	await _fresh_run()
	for id in ["shadow_blink", "shadow_darkness", "shadow_veil"]:
		run._apply_upgrade({"id": id})
	run.element_system.imbue(Elements.SHADOW)
	run._update_element_seal()
	_check("Shadow binds alone and colors the blade", run.katana.element == Elements.SHADOW)

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
	var gy := run.forest_world.height_at(player.global_position.x, player.global_position.z)
	_check("the blink lands on the ground there (%.2f m off the terrain)" % (player.global_position.y - gy),
		absf(player.global_position.y - gy) < 0.15)

	# Blink straight at a trunk: the player must stop short of the bark,
	# not end up inside the tree.
	run.element_system.blink_cooldown = 0.0
	var at := player.global_position
	var trunk_xf := Transform3D(Basis.IDENTITY, Vector3(at.x - 1.6, run.forest_world.height_at(at.x - 1.6, at.z), at.z))
	var trunk := run.forest_world._build_trunk_colliders([trunk_xf], 0, Node3D.new())
	run.add_child(trunk)
	await _frames(3)
	run.element_system.try_shadow_blink(Vector3.LEFT)
	await _frames(3)
	var gap := Vector2(player.global_position.x - trunk_xf.origin.x, player.global_position.z - trunk_xf.origin.z).length()
	_check("a blink at a tree stops short of the bark (%.2f m from the axis, bark ~%.2f m)" % [gap, run.forest_world._trunk_chest_radius],
		gap > run.forest_world._trunk_chest_radius + 0.2)
	trunk.queue_free()
	_check("Spawn seal lights the Shadow quadrant and no evolution star",
		int((run.get_node("Arena/SpawnSeal") as MeshInstance3D).material_override.get_shader_parameter("active_elements_mask")) == 8
		and int((run.get_node("Arena/SpawnSeal") as MeshInstance3D).material_override.get_shader_parameter("evolution_mask")) == 0)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(int(seconds * Engine.physics_ticks_per_second))
