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
	await _frames(16)
	run.wave_director.stop_director()
	var player := run.player as DesktopPlayer
	var y := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -2.0), player.global_position)
	await _frames(6)
	y.snap_pose("stalk")
	await _frames(6)
	var arm_err: float = float(y.pose_errors().get("arm_r", 99.0))
	_check("Yōkai hold stalk pose instead of a bind T-pose",
		(y.current_pose == "stalk" or y.current_pose == "approach") and arm_err < 28.0)
	y.prepare_for_spawn()
	_check("prepare_for_spawn resets dead state", not y.is_dead and y.current_pose == "stalk")
	var oni: RunOniBoss = run.wave_director.spawn_oni_boss(player.global_position)
	await _frames(8)
	_check("Oni boss spawns with RunOniBoss visuals", oni != null and oni.is_in_group("oni_boss"))
	var pelvis := oni.parts.get("pelvis") as RagdollPart
	_check("Oni wears body shell and kanabō visual (not red ragdoll primitives)",
		pelvis != null and pelvis.get_node_or_null("OniBodyShell") != null
		and oni.parts.get("lower_arm_r").get_node_or_null("OniKanaboVisual") != null)
	_check("Oni boss uses demon flesh material, not default wood",
		oni._flesh != null and oni._flesh.get_shader_parameter("base_color").r < 0.2)
	var elite := run.wave_director.spawn_elite_at(Vector3(2.0, 0.0, -2.5), player.global_position, Elements.INK)
	await _frames(4)
	# Elites carry their element in the body (eyes, sigil, sash, claws, skin),
	# never in a ring or an overlay that draws over the scene.
	_check("Elite yōkai has no ring, torus or no_depth_test overlay", not _has_overlay(elite) and elite.find_child("EliteHalo", true, false) == null)
	_check("Ink elite's eyes take the element colour (blue over red, swarm is red)",
		elite._eyes.emission.b > elite._eyes.emission.r and y._eyes.emission.r > y._eyes.emission.b)
	_check("Elite adds no draw calls over a swarm body (%d vs %d meshes)" % [_mesh_count(elite), _mesh_count(y)],
		_mesh_count(elite) <= _mesh_count(y))
	_check("Element firework helper exists for death VFX", ElementFirework != null)
	run.queue_free()


## True if [param body] draws a torus ring or a mesh that ignores depth (drawn through walls and bodies).
func _has_overlay(body: Node) -> bool:
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh is TorusMesh:
			return true
		var mat := mi.material_override as BaseMaterial3D
		if mat and mat.no_depth_test:
			return true
	return false


func _mesh_count(body: Node) -> int:
	return body.find_children("*", "MeshInstance3D", true, false).size()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
