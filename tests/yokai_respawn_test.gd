extends Node
## Pooled yōkai must come back as clean swarm bodies: an elite corpse recycled
## by WaveDirector and reused for a swarm spawn must lose its scale, halo,
## group and death-dissolve material state.

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
	await _frames(14)
	run.wave_director.stop_director()
	var director := run.wave_director
	var player := run.player as DesktopPlayer

	var elite := director.spawn_elite_at(Vector3(0.0, 0.0, 8.0), player.global_position, Elements.STORM)
	await _frames(4)
	_check("Elite spawns large with a halo", elite.scale.x > 1.05 and elite._elite_halo != null)
	elite.die({})
	# 0.95 s dissolve at 90 fps ≈ 86 frames; recycle happens on dissolve_finished.
	await _frames(140)
	_check("Dead elite is recycled into the pool", not is_instance_valid(elite) or elite.get_parent() != director)

	var swarm := director.spawn_enemy_at(Vector3(2.0, 0.0, 8.0), player.global_position)
	await _frames(4)
	_check("Pool reuses the recycled body", swarm == elite)
	_check("Respawned yōkai is alive and standing",
		not swarm.is_dead and swarm.state == ActiveRagdoll.State.STANDING)
	_check("Respawned swarm is back to normal size (was elite 1.14×)", swarm.scale.is_equal_approx(Vector3.ONE))
	_check("Respawned swarm lost the elite halo", swarm.find_child("EliteHalo", true, false) == null)
	_check("Respawned swarm left the elite group", not swarm.is_in_group("elite_yokai"))
	_check("Respawned skin fill restored (was dissolved to ~0.1)",
		float(swarm._skin.get_shader_parameter("fill")) > 1.0)
	_check("Respawned eyes glow again (were dissolved to ~0)",
		swarm._eyes.emission_energy_multiplier > 0.5)
	var pelvis := swarm.root_part() as RagdollPart
	_check("Respawned body collides again (layer 2)", pelvis != null and pelvis.collision_layer == 2)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
