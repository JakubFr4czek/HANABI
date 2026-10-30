extends Node
## Headless coverage for docs/NIGHT_PLAN.md item 3: chunked forest hills,
## recycled props, shrine clearing, and Quest-oriented instance budgets.

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
	var forest := run.forest_world
	var player := run.player as DesktopPlayer
	_check("RunGame spawns the endless forest around the shrine", forest != null)
	_check("Forest keeps a bounded 3×3 chunk ring", forest.chunk_count == 9)

	var before := forest.center_chunk
	player.teleport(Vector3(34.0, 0.0, 6.0), 0.0)
	await _frames(6)
	_check("Forest chunks recycle when the player crosses chunk borders",
		forest.center_chunk != before)

	var nearest := forest.nearest_prop_distance()
	_check("Shrine clearing stays free of forest props",
		nearest >= forest.profile.prop_clearing_radius - 0.05 or nearest == INF)
	_check("Spawn glade is level ground (%.2f m)" % forest.height_at(2.0, 2.0),
		absf(forest.height_at(2.0, 2.0) - ForestWorld.CLEARING_HEIGHT) < 0.01)
	# Big, sparse swells: a long transect must cross metres of relief, while the
	# ground right outside the glade stays nearly flat.
	var relief := 0.0
	for k in 24:
		relief = maxf(relief, absf(forest.height_at(20.0 + k * 6.0, 14.0 - k * 4.0) - ForestWorld.CLEARING_HEIGHT))
	_check("Sparse hills and valleys roll through the forest (relief %.2f m)" % relief, relief > 2.0)
	var near_flat := 0.0
	for k in 12:
		near_flat = maxf(near_flat, absf(forest.height_at(8.0 + k * 1.0, 6.0) - ForestWorld.CLEARING_HEIGHT))
	_check("Ground near the glade stays nearly flat (%.2f m)" % near_flat, near_flat < 1.0)
	# Walkable everywhere: XR Tools and the desktop body climb up to 45°.
	var steepest := 0.0
	for gx in 60:
		for gz in 60:
			var x := -60.0 + gx * 2.0
			var z := -60.0 + gz * 2.0
			var dx := forest.height_at(x + 0.5, z) - forest.height_at(x - 0.5, z)
			var dz := forest.height_at(x, z + 0.5) - forest.height_at(x, z - 0.5)
			steepest = maxf(steepest, rad_to_deg(atan(Vector2(dx, dz).length())))
	_check("Slopes stay walkable (steepest %.1f° < 40°)" % steepest, steepest < 40.0)

	# Walk out into the forest: the terrain under the player is solid.
	player.teleport(Vector3(31.0, 3.5, 9.0), 0.0)
	await _frames(90)
	var ground := forest.height_at(player.global_position.x, player.global_position.z)
	_check("Player stands on forest terrain far from the shrine (feet %.2f, ground %.2f)" % [player.global_position.y, ground],
		player.is_on_floor() and absf(player.global_position.y - ground) < 0.35)
	var boundary := run.get_node_or_null("Room/Boundary") as StaticBody3D
	_check("Dojo ring wall no longer fences the run", boundary == null or boundary.collision_layer == 0)

	var water := run.get_node_or_null("Arena/WaterMirror") as MeshInstance3D
	_check("Run replaces the endless water mirror with forest terrain", water != null and not water.visible)

	var props := forest.total_prop_instances()
	_check("Shared MultiMesh props stay within a Quest-friendly budget", props > 24 and props < 980)

	# Chunks are centered on coord * chunk_size, so the mapping must round.
	var half := forest.profile.chunk_size * 0.5
	_check("Chunk mapping matches centered chunks",
		forest._world_to_chunk(Vector3(half - 0.1, 0.0, 0.0)) == Vector2i(0, 0)
		and forest._world_to_chunk(Vector3(half + 0.1, 0.0, 0.0)) == Vector2i(1, 0)
		and forest._world_to_chunk(Vector3(-half - 0.1, 0.0, 0.0)) == Vector2i(-1, 0))
	_check("Fog bubble opened past the 9 m closet (end %.1f m)" % forest.profile.fog_end,
		forest.profile.fog_end > 9.0 and forest.profile.fog_end <= forest.loaded_range())
	_check("Trees draw out to the fog (radius %.1f m)" % forest.profile.tree_draw_radius,
		forest.profile.tree_draw_radius >= forest.profile.fog_end)
	_check("Chunks hold up to %d torii gates" % forest.profile.torii_max_per_chunk,
		forest.profile.torii_max_per_chunk >= 2)
	# Gate positions come from chunk meta (MultiMesh buffers read back empty
	# under the headless renderer, so nearest_torii_position is device-only).
	var gate_positions: Array = []
	for key in forest._chunks:
		gate_positions.append_array((forest._chunks[key] as Node3D).get_meta("torii_world_positions", []))
	_check("A torii gate stands somewhere in the ring (%d placed)" % gate_positions.size(),
		not gate_positions.is_empty())

	# Trunks stop the player: a chest-height ray at the nearest drawn trunk
	# must hit the trunk-collider layer (idle frame: the space is unlocked).
	await get_tree().process_frame
	var space := run.get_world_3d().direct_space_state
	var blocked := false
	# Trunk positions come from chunk meta: MultiMesh buffers read back empty
	# under the headless renderer.
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		var xfs: Array = chunk.get_meta("tree_local_xfs", [])
		if xfs.is_empty():
			continue
		var trunk := chunk.global_transform * (xfs[0] as Transform3D).origin
		var query := PhysicsRayQueryParameters3D.create(
			trunk + Vector3(2.0, 0.0, 0.0) + Vector3.UP * 1.2, trunk + Vector3.UP * 1.2)
		query.collision_mask = ForestWorld.TRUNK_LAYER
		var hit: Dictionary = space.intersect_ray(query)
		blocked = not hit.is_empty()
		break
	_check("Drawn trunks block movement (chest-height ray hits a trunk)", blocked)

	# Crowns keep their distance and gates stand clear of trunks.
	var tree_xy: Array[Vector2] = []
	for key in forest._chunks:
		for s in (forest._tree_spots(key).get("spots", [])):
			var spot: Vector4 = s
			tree_xy.append(Vector2(spot.x, spot.y))
	var min_gap := INF
	for i in tree_xy.size():
		for j in range(i + 1, tree_xy.size()):
			min_gap = minf(min_gap, tree_xy[i].distance_to(tree_xy[j]))
	_check("Tree trunks keep %dm spacing (min %.2f m)" % [forest.profile.trees[0].min_spacing, min_gap],
		min_gap >= forest.profile.trees[0].min_spacing - 0.01)
	var gate_clear := INF
	for g in gate_positions:
		var gv: Vector3 = g
		for t in tree_xy:
			gate_clear = minf(gate_clear, Vector2(gv.x - t.x, gv.z - t.y).length())
	_check("Every torii stands clear of trunks (nearest %.2f m)" % gate_clear,
		gate_positions.is_empty() or gate_clear >= 2.4)

	# Roots stay buried: every planted trunk base sits at or below the
	# rendered ground around it. (Planted transforms come from chunk meta:
	# MultiMesh buffers read back empty under the headless renderer.)
	var floating := 0
	var sampled := 0
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		for xf in chunk.get_meta("tree_local_xfs", []):
			var local: Vector3 = (xf as Transform3D).origin
			var w := chunk.global_transform * local
			# Root reach of the current tree mesh (ribbon tip ~2.1 m).
			var mesh_floor := forest._mesh_min_height(w.x, w.z, 2.1)
			sampled += 1
			if w.y > mesh_floor + 0.02:
				floating += 1
	_check("Planted trunk bases sit in the ground (%d/%d buried)" % [sampled - floating, sampled],
		sampled > 0 and floating == 0)

	# Rare emissive pink sakura focal trees (Zadanie 7 / GDD §9)
	var sakura_count := 0
	var sakura_floating := 0
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		var xfs: Array = chunk.get_meta("sakura_tree_local_xfs", [])
		for xf in xfs:
			sakura_count += 1
			var local: Vector3 = (xf as Transform3D).origin
			var w := chunk.global_transform * local
			var mesh_floor := forest._mesh_min_height(w.x, w.z, 2.1 * forest.profile.trees[1].focal_scale_boost)
			if w.y > mesh_floor + 0.02:
				sakura_floating += 1
	_check("Rare sakura trees spawn as focal points (%d in 3x3 ring)" % sakura_count,
		sakura_count >= 1 and sakura_count <= 4)
	_check("Sakura trunk bases sit in the ground (%d/%d buried)" % [sakura_count - sakura_floating, sakura_count],
		sakura_count > 0 and sakura_floating == 0)

	var nearest_sakura := forest.nearest_sakura_position(Vector3.ZERO)
	_check("Nearest sakura focal tree is positioned in the forest (%s)" % str(nearest_sakura),
		nearest_sakura != Vector3.INF and nearest_sakura.length() > forest.profile.clearing_radius)

	# Verify Focal1 MultiMesh uses the dedicated sakura shader with emission parameters
	var has_sakura_mm := false
	var valid_sakura_shader := false
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		var s_inst := chunk.get_node_or_null("Focal1") as MultiMeshInstance3D
		if s_inst != null and s_inst.material_override is ShaderMaterial:
			has_sakura_mm = true
			var sm: ShaderMaterial = s_inst.material_override
			if sm.shader == ForestWorld.SAKURA_TREE_SHADER and sm.get_shader_parameter("neon_pink_accent") != null:
				valid_sakura_shader = true
				break
	_check("Sakura focal trees use dedicated emissive neon shader", has_sakura_mm and valid_sakura_shader)

	# Walking inside one chunk toward the treeline must reveal trees without
	# waiting for a chunk-border crossing.
	player.teleport(Vector3(0.0, forest.height_at(0.0, 26.0) + 0.5, 26.0), 0.0)
	await _frames(10)
	var chunk_before: Vector2i = forest.center_chunk
	var drawn_before := _drawn_trees(forest)
	player.teleport(Vector3(8.0, forest.height_at(8.0, 34.0) + 0.5, 34.0), 0.0)
	await _frames(10)
	_check("Tree visibility refreshes while walking inside one chunk (not only at borders)",
		forest.center_chunk == chunk_before and _drawn_trees(forest) != drawn_before)

	# Roaming far must not accumulate one tree-spot cache entry per visited chunk.
	player.teleport(Vector3(500.0, forest.height_at(500.0, 500.0) + 0.5, 500.0), 0.0)
	await _frames(10)
	_check("Tree-spot cache stays bounded while roaming (%d entries)" % forest._tree_spot_cache.size(),
		forest._tree_spot_cache.size() <= 30)
	await _lod_checks(run, forest, player)
	run.queue_free()


## D6: the forest reads out to the fog. Full crowns stand close, far crowns carry on
## to the fog's end, nothing pops at a chunk border or at the LOD band, the next
## ring fills over frames, and a trunk can hide a far gate's glow.
func _lod_checks(run: RunGame, forest: ForestWorld, player: DesktopPlayer) -> void:
	var profile := forest.profile
	var near_r := profile.lod_near_radius + profile.lod_fade * 0.5
	forest.finish_pending()
	player.teleport(Vector3(0.0, forest.height_at(0.0, 0.0) + 0.2, 0.0), 0.0)
	await _frames(2)
	forest.finish_pending()
	forest._refresh_tree_draw(player.global_position)
	var far_band := _count_between(forest.drawn_far_origins, player.global_position, 14.0, 40.0)
	_check("Far crowns stand from 14 m to 40 m, where the fog is nearly full (%d drawn)" % far_band, far_band > 0)
	var full_max := _farthest(forest.drawn_full_origins, player.global_position)
	_check("Full crowns stay inside the LOD band (farthest %.1f m, band edge %.1f m)" % [full_max, near_r],
		full_max <= near_r + 0.01)
	var scene_max := _farthest(forest.drawn_scene_origins, player.global_position)
	_check("Scanned crowns (redwood) stand to tree_draw_radius, no LOD band (farthest %.1f m)" % scene_max,
		scene_max <= profile.tree_draw_radius + 0.01 and (forest.drawn_scene_origins.is_empty() or scene_max > near_r))
	var all_max := maxf(full_max, _farthest(forest.drawn_far_origins, player.global_position))
	_check("Nothing is drawn past tree_draw_radius (farthest %.1f m)" % all_max,
		all_max <= profile.tree_draw_radius + 0.01)
	var far_tris := _triangles(forest._tree_far_meshes[0])
	_check("A far crown is at most 500 triangles (%d)" % far_tris, far_tris > 0 and far_tris <= 500)
	# The far crowns are what the camera sees: some stand in its horizontal view cone.
	var forward := -player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var in_view := 0
	for o in forest.drawn_far_origins:
		var to := o - player.global_position
		to.y = 0.0
		var dist := to.length()
		if dist >= 14.0 and dist <= 40.0 and forward.dot(to / dist) > cos(deg_to_rad(35.0)):
			in_view += 1
	_check("Far crowns fill the view ahead (%d in a 70 degree cone, 14–40 m)" % in_view, in_view > 0)

	# Walking 80 m across two chunk borders: every ordinary tree inside the draw
	# radius is drawn at every step (full or far crown, never neither), so a
	# border cannot pop a tree in or out of view.
	var missing := 0
	var extra := 0
	var steps := 0
	var x := -20.0
	while x <= 60.0:
		player.teleport(Vector3(x, forest.height_at(x, 0.0) + 0.2, 0.0), 0.0)
		await _frames(1)
		forest.finish_pending()
		forest._refresh_tree_draw(player.global_position)
		var drawn := {}
		for o in forest.drawn_full_origins:
			drawn[o] = true
		for o in forest.drawn_far_origins:
			drawn[o] = true
		for o in forest.drawn_scene_origins:
			drawn[o] = true
		var expected := _ring_trees_within(forest, player.global_position, profile.tree_draw_radius)
		for o in expected:
			if not drawn.has(o):
				missing += 1
		for o in drawn.keys():
			if not expected.has(o):
				extra += 1
		steps += 1
		x += 0.25
	_check("Every tree inside the draw radius is drawn at each of %d steps across two borders (%d missing, %d extra)" % [steps, missing, extra],
		missing == 0 and extra == 0)

	# Crossing a border queues the new ring; it is built over frames, not in one stall.
	player.teleport(Vector3(profile.chunk_size * 0.5 - 1.0, forest.height_at(profile.chunk_size * 0.5 - 1.0, 0.0), 0.0), 0.0)
	forest.finish_pending()
	await _frames(1)
	player.teleport(Vector3(profile.chunk_size * 0.5 + 2.0, forest.height_at(profile.chunk_size * 0.5 + 2.0, 0.0), 0.0), 0.0)
	await _frames(1)
	var queued := forest._pending_chunks.size() + (1 if forest._building != null else 0)
	_check("Crossing a border queues the new ring instead of building it at once (%d waiting)" % queued, queued > 0)
	var frames := 0
	while (forest._building != null or not forest._pending_chunks.is_empty()) and frames < 300:
		await _frames(1)
		frames += 1
	_check("The queued ring is ready after %d frames, nine chunks loaded" % frames,
		frames < 300 and forest.chunk_count == 9)

	# A trunk between the eye and a gate 20–36 m away hides part of its glow (the halo is depth-tested).
	forest.finish_pending()
	var gate := Vector3.INF
	for key in forest._chunks:
		for g in (forest._chunks[key] as Node3D).get_meta("torii_world_positions", []):
			var gv: Vector3 = g
			var d := Vector2(gv.x, gv.z).length()
			if gate == Vector3.INF and d >= 20.0 and d <= 36.0:
				gate = gv
	if gate == Vector3.INF:
		_check("A torii gate stands 20–36 m from the spawn for the sight-line check", false)
		return
	var dir := Vector3(gate.x, 0.0, gate.z).normalized()
	var stand := gate - dir * 25.0
	player.teleport(Vector3(stand.x, forest.height_at(stand.x, stand.z) + 0.2, stand.z), 0.0)
	await _frames(2)
	forest.finish_pending()
	var eye := player.camera.global_position
	var space := run.get_world_3d().direct_space_state
	var blocked := 0
	var sight_lines := 0
	for i in 9:
		var side := Vector3(-dir.z, 0.0, dir.x) * (-0.6 + 0.15 * float(i))
		# Stops 2 m short of the gate, so its own posts are not the blocker.
		var target := gate - dir * 2.0 + Vector3(0.0, 2.2, 0.0) + side
		var query := PhysicsRayQueryParameters3D.create(eye, target, ForestWorld.TRUNK_LAYER)
		sight_lines += 1
		if not space.intersect_ray(query).is_empty():
			blocked += 1
	_check("Trunks hide part of a gate's glow 25 m away (%d of %d sight lines blocked)" % [blocked, sight_lines],
		blocked >= 1 and blocked < sight_lines)


## Origins of every ordinary tree of the loaded ring within [param radius] of [param origin].
func _ring_trees_within(forest: ForestWorld, origin: Vector3, radius: float) -> Dictionary:
	var out := {}
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		for xf in chunk.get_meta("tree_local_xfs", []):
			var w := chunk.position + (xf as Transform3D).origin
			if Vector2(w.x - origin.x, w.z - origin.z).length() <= radius:
				out[w] = true
	return out


func _count_between(points: PackedVector3Array, origin: Vector3, lo: float, hi: float) -> int:
	var n := 0
	for p in points:
		var d := Vector2(p.x - origin.x, p.z - origin.z).length()
		if d >= lo and d <= hi:
			n += 1
	return n


func _farthest(points: PackedVector3Array, origin: Vector3) -> float:
	var far := 0.0
	for p in points:
		far = maxf(far, Vector2(p.x - origin.x, p.z - origin.z).length())
	return far


static func _triangles(mesh: Mesh) -> int:
	var total := 0
	for si in mesh.get_surface_count():
		total += (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _drawn_trees(forest: ForestWorld) -> int:
	var total := 0
	for key in forest._chunks:
		var inst := (forest._chunks[key] as Node3D).get_node_or_null("Trees0") as MultiMeshInstance3D
		if inst and inst.multimesh:
			total += inst.multimesh.instance_count
	return total
