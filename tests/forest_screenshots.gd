extends Node
## Single-frame forest vista for visual review (run scene, no full run_screenshots loop).

const RUN_SCENE := preload("res://scenes/run.tscn")

var out_dir := "/tmp/hanabi_forest_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-10.0)
	await _frames(45)
	await _shot("forest_horizon")
	# Look out sideways from the shrine edge into the tree line.
	player.teleport(Vector3(3.5, 0.0, 1.0), -PI * 0.5)
	player.camera.rotation.x = deg_to_rad(-6.0)
	await _frames(30)
	await _shot("forest_from_shrine_edge")
	# Walked out among the hills, far from the shrine.
	player.teleport(Vector3(30.0, run.forest_world.height_at(30.0, 18.0), 18.0), PI * 0.25)
	player.camera.rotation.x = deg_to_rad(-6.0)
	await _frames(60)
	await _shot("forest_deep_walk")
	# Looking back at the shrine clearing from the tree line.
	player.teleport(Vector3(0.0, run.forest_world.height_at(0.0, 12.5), 12.5), 0.0)
	player.camera.rotation.x = deg_to_rad(-4.0)
	await _frames(45)
	await _shot("forest_back_to_shrine")
	# Forest floor at the feet: needle soil, grass patches, stones.
	player.teleport(Vector3(14.0, run.forest_world.height_at(14.0, 9.0), 9.0), 0.6)
	player.camera.rotation.x = deg_to_rad(-38.0)
	await _frames(30)
	await _shot("forest_floor")
	# Knee-high look at the nearest trunk, so the soil join is the subject.
	player.teleport(Vector3(14.0, run.forest_world.height_at(14.0, 9.0), 9.0), 0.6)
	await _frames(20)
	var trunk := _nearest_drawn_tree(run, player.global_position)
	if trunk != Vector3.INF:
		var away := player.global_position - trunk
		away.y = 0.0
		if away.length_squared() < 0.04:
			away = Vector3(0.0, 0.0, 1.0)
		away = away.normalized()
		var stand := trunk + away * 3.2
		var yaw := atan2(-away.x, -away.z)
		player.teleport(Vector3(stand.x, run.forest_world.height_at(stand.x, stand.z) + 0.2, stand.z), yaw)
		player.camera.rotation.x = deg_to_rad(-35.0)
		await _frames(8)
		print("trunk base at ", trunk, " cam ", player.global_position)
		_debug_roots(run, trunk)
		await _shot("forest_trunk_base")
	# Yōkai far off in the fog: only their eyes read.
	player.teleport(Vector3(0.0, 0.0, 0.0), 0.0)
	player.camera.rotation.x = deg_to_rad(0.0)
	run.wave_director.clear_enemies()
	for d in [6.0, 11.0, 16.0]:
		var ex: float = -1.6 + float(d) * 0.2
		run.wave_director.spawn_enemy_at(Vector3(ex, run.forest_world.height_at(ex, -d), -d), player.global_position).brain.attacks_enabled = false
	await _frames(12)
	for e in run.wave_director.alive_enemies():
		e.set_physics_process(false)
		print("eyes yokai at ", e.root_part().global_position)
	await _frames(6)
	await _shot("yokai_eyes_in_fog")
	run.wave_director.clear_enemies()
	# A gate the forest generator placed, met in the fog.
	var gate := run.forest_world.nearest_torii_position(Vector3.ZERO)
	if gate != Vector3.INF:
		var stand := gate + Vector3(0.0, 0.0, 7.0)
		player.teleport(Vector3(stand.x, run.forest_world.height_at(stand.x, stand.z), stand.z), 0.0)
		player.camera.rotation.x = deg_to_rad(4.0)
		await _frames(45)
		await _shot("forest_torii_7m")
	run.queue_free()
	get_tree().quit(0)


func _nearest_drawn_tree(run: RunGame, from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for chunk in run.forest_world.get_children():
		var trees := chunk.get_node_or_null("Trees") as MultiMeshInstance3D
		if trees == null or trees.multimesh == null:
			continue
		var mm := trees.multimesh
		for i in mm.instance_count:
			var p: Vector3 = trees.global_transform * mm.get_instance_transform(i).origin
			var d := Vector2(p.x - from.x, p.z - from.z).length()
			if d < best_d and d > 1.2:
				best_d = d
				best = p
	return best


func _debug_roots(run: RunGame, trunk_pos: Vector3) -> void:
	var best_d := INF
	var best_xf := Transform3D.IDENTITY
	var best_mm: MultiMesh = null
	for chunk in run.forest_world.get_children():
		var trees := chunk.get_node_or_null("Trees") as MultiMeshInstance3D
		if trees == null or trees.multimesh == null:
			continue
		var mm := trees.multimesh
		for i in mm.instance_count:
			var xf := trees.global_transform * mm.get_instance_transform(i)
			var d := Vector2(xf.origin.x - trunk_pos.x, xf.origin.z - trunk_pos.z).length()
			if d < best_d:
				best_d = d
				best_xf = xf
				best_mm = mm
	print("closest drawn trunk ", best_d)
	if best_mm == null:
		return
	var arrays: Array = best_mm.mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var above := 0
	var below := 0
	var hi := -999.0
	var lo := 999.0
	var hi_r := 0.0
	var out_high := 0
	for v in pos.size():
		if uvs[v].x < 1.5:
			continue
		var w: Vector3 = best_xf * pos[v]
		var ground := run.forest_world.height_at(w.x, w.z)
		var clearance := w.y - ground
		var radial := Vector2(w.x - best_xf.origin.x, w.z - best_xf.origin.z).length()
		hi = maxf(hi, clearance)
		lo = minf(lo, clearance)
		if clearance > hi - 0.001:
			hi_r = radial
		if clearance > 0.08 and radial > 1.3:
			out_high += 1
		if clearance > 0.02:
			above += 1
		else:
			below += 1
	print("roots above ", above, " below ", below, " clearance ", lo, " .. ", hi, " hi radial ", hi_r, " outside ", out_high)


func _nearest_tree(run: RunGame, from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for chunk in run.forest_world.get_children():
		if not chunk.has_meta("tree_local_xfs"):
			continue
		for xf in chunk.get_meta("tree_local_xfs"):
			var p: Vector3 = chunk.global_position + (xf as Transform3D).origin
			var d := Vector2(p.x - from.x, p.z - from.z).length()
			if d < best_d:
				best_d = d
				best = p
	return best


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
