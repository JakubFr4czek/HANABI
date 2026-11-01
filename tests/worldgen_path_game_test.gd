extends Node
## The footpath is part of the game's forest (docs/WORLDGEN_TOOL.md). Runs the real
## run scene and checks:
##  a) the forest has its paths and the ground under the glade carries path weight;
##  b) a path starts within 6 m of the player's spawn;
##  c) lanterns stand on the trail, at least path_lantern_spacing apart in a chunk,
##     and clear of the gates of their chunk;
##  d) no trunk or boulder stands inside the path's half width plus its clearance.
## How the trail looks on screen is checked in worldgen_path_visible_test, from the
## pixels of the rendered frame (not from material parameters).
##   godot --headless --path . --fixed-fps 90 res://tests/worldgen_path_game_test.tscn

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
	for k in 20:
		await get_tree().process_frame
	var forest := run.forest_world
	_check("The run builds the forest with its path network", forest != null and forest.paths != null)
	var glade := forest._chunks.get(Vector2i.ZERO) as Node3D
	var weights := _vertex_weights(glade)
	_check("The ground under the glade carries path weight (max %.2f)" % _max_of(weights), _max_of(weights) > 0.9)

	var spawn := run.find_child("PlayerSpawn", true, false) as Node3D
	var spawn_xz := Vector2(spawn.global_position.x, spawn.global_position.z) if spawn else Vector2(0.0, 1.8)
	var near := forest.paths.nearest_point(spawn_xz, 6.0)
	_check("A path starts within 6 m of the spawn (nearest %s)" % str(near), near != Vector2.INF)

	_check_lanterns(forest)

	var reach := forest._path_half_width() + forest.profile.path_tree_clearance - 0.5
	var worst := INF
	var fern_worst := INF
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		var field := forest._path_field(key)
		var centre := Vector2(key.x * forest.profile.chunk_size, key.y * forest.profile.chunk_size)
		for s in forest._tree_spots(key).get("spots", []):
			var spot: Vector4 = s
			worst = minf(worst, forest._field_at(field, Vector2(spot.x, spot.y) - centre))
		# Boulders (and any other floor kind) keep the clearance; along-path kinds (N5 ferns) stand on the
		# trail's edge by design, so they get their own rule below: off the gravel and its edge.
		for u in forest.profile.undergrowth.size():
			for xf in chunk.get_meta("xfs_Undergrowth%d" % u, []):
				var at: Vector3 = (xf as Transform3D).origin
				var d := forest._field_at(field, Vector2(at.x, at.z))
				if forest.profile.undergrowth[u].along_path:
					fern_worst = minf(fern_worst, d)
				else:
					worst = minf(worst, d)
	_check("No trunk or boulder stands within the path clearance (nearest %.2f m, need %.2f m)" % [worst, reach],
		worst >= reach)
	# The ground shader loops over each chunk's centre-line segments per pixel: they must all fit.
	var over := 0
	var with_path := 0
	for key in forest._chunks:
		var mat := (forest._chunks[key] as Node3D).get_child(0) as MeshInstance3D
		var n: int = (mat.material_override as ShaderMaterial).get_shader_parameter("path_seg_count")
		if n > 0:
			with_path += 1
		if n > ForestWorld.PATH_SEGMENTS_MAX:
			over += 1
	_check("Every chunk hands all its trail segments to the ground shader (%d chunks with trail, %d over %d)" % [with_path, over, ForestWorld.PATH_SEGMENTS_MAX],
		with_path > 0 and over == 0)
	var edge := forest._path_half_width() + 0.6
	_check("Ferns exist along the trail (%s)" % ("none found" if fern_worst == INF else "nearest %.2f m" % fern_worst),
		fern_worst < INF)
	_check("Ferns stand on the trail's edge, never on the gravel (nearest %.2f m, need %.2f m)" % [fern_worst, edge],
		fern_worst >= edge)
	run.queue_free()
	await get_tree().process_frame


## Lanterns: on the trail, spaced along it, never beside a gate of their chunk.
func _check_lanterns(forest: ForestWorld) -> void:
	var spacing: float = forest.profile.path_lantern_spacing
	var total := 0
	var off_path := 0
	var too_close := 0
	var by_gate := 0
	var worst_gap := INF
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		var field := forest._path_field(key)
		var centre := Vector2(key.x * forest.profile.chunk_size, key.y * forest.profile.chunk_size)
		var lanterns: Array = chunk.get_meta("lantern_world_positions", [])
		var gates: Array = chunk.get_meta("torii_world_positions", [])
		for i in lanterns.size():
			var a: Vector3 = lanterns[i]
			total += 1
			if forest._field_at(field, Vector2(a.x, a.z) - centre) > forest._path_half_width() + 3.0:
				off_path += 1
			for g in gates:
				var gate: Vector3 = g
				if Vector2(a.x - gate.x, a.z - gate.z).length() < ForestWorld.LANTERN_CLEAR_OF_TORII:
					by_gate += 1
			for j in range(i + 1, lanterns.size()):
				var b: Vector3 = lanterns[j]
				var gap := Vector2(a.x - b.x, a.z - b.z).length()
				worst_gap = minf(worst_gap, gap)
				if gap < spacing - 0.01:
					too_close += 1
	_check("Lanterns stand on the trail (%d of %d more than 3 m from it)" % [off_path, total], total > 0 and off_path == 0)
	_check("Lanterns in a chunk keep %.0f m apart (closest %.2f m)" % [spacing, worst_gap if worst_gap < INF else -1.0],
		too_close == 0)
	_check("No lantern stands beside a gate of its chunk (%d too close)" % by_gate, by_gate == 0)


static func _vertex_weights(chunk: Node3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for child in chunk.get_children():
		if child is MeshInstance3D and String(child.name) == "Terrain":
			var colours: PackedColorArray = (child as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			for c in colours:
				out.append(c.r)
	return out


static func _max_of(values: PackedFloat32Array) -> float:
	var m := -INF
	for v in values:
		m = maxf(m, v)
	return m


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
