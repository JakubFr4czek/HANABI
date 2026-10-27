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
	add_child(run)
	await _frames(12)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var player := run.player as DesktopPlayer

	var elite := run.wave_director.spawn_elite_at(Vector3(2.0, 0.0, -3.0), player.global_position, Elements.STORM)
	_check("Elite yōkai spawn with an element identity", elite.is_elite() and elite.elite_element == Elements.STORM)
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

	run.wave_director.active = true
	run.wave_director.run_seconds = 55.0
	run.wave_director._oni_cooldown = 0.05
	run.wave_director.step_director(0.1, player.global_position)
	await _frames(4)
	_check("Wave director spawns a duelist Oni boss on a timer", run.wave_director.has_active_oni())
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
