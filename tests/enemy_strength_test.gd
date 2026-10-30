extends Node
## Ordinary yōkai are stronger (+40% HP, +25% damage) and that strength lives in the
## WaveProfile data. Elites and the Oni keep the stock numbers, and the planner's
## simulation uses the same HP as the spawned bodies.

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	_check_profile_data()
	_check_presets_inherit_strength()
	await _check_spawned_bodies()


func _check_profile_data() -> void:
	var p := WaveProfile.new()
	_check("Stock base HP and damage are unchanged (95 / 12)",
		is_equal_approx(p.hp_for(1, 0.0), 95.0) and is_equal_approx(p.damage_for(1), 12.0))
	_check("Swarm HP multiplier is data: 1.40", is_equal_approx(p.swarm_hp_mult, 1.4))
	_check("Swarm damage multiplier is data: 1.25", is_equal_approx(p.swarm_damage_mult, 1.25))
	_check("Ordinary yōkai at wave 1 have 133 HP (+40%)", is_equal_approx(p.swarm_hp_for(1, 0.0), 133.0))
	_check("Ordinary yōkai at wave 1 hit for 15 (+25%)", is_equal_approx(p.swarm_damage_for(1), 15.0))
	_check("Elite HP is the stock scaling (95 x elite mult)", is_equal_approx(p.hp_for(1, 0.0, true), 95.0 * p.elite_hp_mult))
	p.swarm_hp_mult = 2.0
	_check("Changing the swarm multiplier in the profile changes the swarm HP",
		is_equal_approx(p.swarm_hp_for(1, 0.0), 190.0))
	_check("...and leaves the elite HP alone", is_equal_approx(p.hp_for(1, 0.0, true), 95.0 * p.elite_hp_mult))


func _check_presets_inherit_strength() -> void:
	var all_ok := true
	for entry in WaveProfile.preset_list():
		var res := load(WaveProfile.preset_path(entry[0])) as WaveProfile
		all_ok = all_ok and res != null and is_equal_approx(res.swarm_hp_for(1, 0.0), 133.0) \
			and is_equal_approx(res.swarm_damage_for(1), 15.0)
	_check("Every preset file carries the same ordinary-yōkai strength", all_ok)


func _check_spawned_bodies() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(14)
	run.wave_director.stop_director()
	var director := run.wave_director
	var player := run.player as DesktopPlayer
	var p := director.get_profile()

	var swarm := director.spawn_enemy_at(Vector3(2.0, 0.0, 8.0), player.global_position)
	var wave := maxi(director.wave, 1)
	_check("Spawned swarm yōkai has the swarm HP from the profile (%.1f)" % swarm.profile.max_hp,
		is_equal_approx(swarm.profile.max_hp, p.swarm_hp_for(wave, director.run_seconds)))
	_check("Spawned swarm yōkai hits with the swarm damage",
		is_equal_approx(swarm.brain.base_damage, p.swarm_damage_for(wave)))

	var elite := director.spawn_elite_at(Vector3(-2.0, 0.0, 8.0), player.global_position, Elements.STORM)
	# EnemyCatalog.make_elite_profile applies its own 2.35x on top of the profile's elite HP.
	_check("Spawned elite keeps the stock HP (not the swarm multiplier)",
		is_equal_approx(elite.profile.max_hp, p.hp_for(wave, director.run_seconds, true) * 2.35))
	_check("Spawned elite keeps the stock damage",
		is_equal_approx(elite.brain.base_damage, p.damage_for(wave)))

	run.queue_free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
