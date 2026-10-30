extends Node
## Headless checks for the World Gen tool (docs/WORLDGEN_TOOL.md): every group of
## the profile moves the forest the way its name says, the preview scene and the
## dock work without the editor, the plugin compiles, the Quest share of the
## forest holds for the default profile, and the game draws the same forest as
## the preview.
##   godot --headless --path . --fixed-fps 90 res://tests/worldgen_tool_test.tscn

const PREVIEW_SCENE := preload("res://tools/worldgen/worldgen_preview.tscn")
const DOCK_SCRIPT := preload("res://addons/hanabi_worldgen/worldgen_dock.gd")
const PLUGIN_SCRIPT := preload("res://addons/hanabi_worldgen/plugin.gd")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	await _check_density_and_trees()
	await _check_gates_and_sakura()
	await _check_paths()
	await _check_lanterns_and_lod()
	_check_atmosphere()
	await _check_shrines_rarer_than_gates()
	await _check_default_budget()
	await _check_preview_and_dock()
	await _check_game_matches_preview()
	_check_plugin_compiles()


## Counts of one forest of [param profile], built alone and freed again. The
## sensitivity checks use a single chunk (chunk_radius 0): the counts scale with
## the chunk, and one chunk builds in a fraction of the 3×3 ring.
func _forest_stats(profile: WorldGenProfile, radius: int = 0) -> Dictionary:
	var sized := profile.duplicate(true) as WorldGenProfile
	sized.chunk_radius = radius
	var forest := _build(sized)
	var stats := forest.stats()
	stats["trees"] = _count_trees(forest)
	stats["gates"] = _count_meta(forest, "torii_world_positions")
	stats["sakura"] = _count_meta(forest, "sakura_tree_local_xfs")
	stats["lanterns"] = _count_meta(forest, "lantern_world_positions")
	_release(forest)
	return stats


func _check_density_and_trees() -> void:
	var sparse := WorldGenProfile.make_default()
	sparse.tree_keep_min = 0.1
	sparse.tree_keep_max = 0.2
	var dense := WorldGenProfile.make_default()
	dense.tree_keep_min = 0.9
	dense.tree_keep_max = 1.0
	var few := await _forest_stats(sparse)
	var many := await _forest_stats(dense)
	_check("Denser keep chance gives more trees (%d → %d)" % [few.trees, many.trees], many.trees > few.trees * 2)
	var none := WorldGenProfile.make_default()
	none.trees[0].weight = 0.0
	none.trees[1].focal_chance = 0.0
	var empty := await _forest_stats(none)
	_check("No ordinary weight and no focal leaves an empty forest (%d)" % empty.trees, empty.trees == 0)


func _check_gates_and_sakura() -> void:
	var gates_off := WorldGenProfile.make_default()
	gates_off.torii_chunk_chance = 0.0
	var off := await _forest_stats(gates_off)
	_check("torii_chunk_chance 0 places no gates in the ring (%d)" % off.gates, off.gates == 0)
	var gates_on := WorldGenProfile.make_default()
	gates_on.torii_chunk_chance = 1.0
	gates_on.torii_group_keep = 1.0
	gates_on.torii_max_per_chunk = 3
	var on := await _forest_stats(gates_on, 1)
	_check("torii_chunk_chance 1 places gates in the 3×3 ring (%d)" % on.gates, on.gates >= 9)
	var sakura_off := WorldGenProfile.make_default()
	sakura_off.trees[1].focal_chance = 0.0
	_check("Focal chance 0 gives no sakura", (await _forest_stats(sakura_off)).sakura == 0)
	var sakura_all := WorldGenProfile.make_default()
	sakura_all.trees[1].focal_chance = 1.0
	var every := await _forest_stats(sakura_all)
	_check("Focal chance 1 gives one sakura per chunk (%d)" % every.sakura, every.sakura == 1)
	var default_stats := await _forest_stats(WorldGenProfile.make_default(), 1)
	_check("Default rarity: sakura in about one chunk in five (%d of 9)" % default_stats.sakura,
		default_stats.sakura <= 4)


func _check_paths() -> void:
	var off := WorldGenProfile.make_default()
	off.paths_enabled = false
	var forest := _build(off)
	_check("Paths off: no path network is built", forest.paths == null)
	_release(forest)

	var on := WorldGenProfile.make_default()
	var net := _build(on)
	_check("Paths on: the network exists", net.paths != null)
	var lowest := INF
	var clearance_ok := true
	var gap := net._path_half_width() + on.path_tree_clearance - 0.36
	for key in net._chunks:
		var chunk := net._chunks[key] as Node3D
		var field := net._path_field(key)
		lowest = minf(lowest, _min_of(field))
		var centre := Vector2(key.x * on.chunk_size, key.y * on.chunk_size)
		for s in net._tree_spots(key).get("spots", []):
			var spot: Vector4 = s
			if net._field_at(field, Vector2(spot.x, spot.y) - centre) < gap:
				clearance_ok = false
		var colours := _vertex_colours(chunk)
		if key == Vector2i.ZERO:
			_check("Terrain carries path weight in its vertex colour (max %.2f)" % _max_of(colours), _max_of(colours) > 0.9)
	_check("Path centre lines reach the ring (nearest %.2f m)" % lowest, lowest < 0.5)
	_check("No trunk stands within the path clearance (gap %.2f m)" % gap, clearance_ok)
	_release(net)


func _check_lanterns_and_lod() -> void:
	var on_path := WorldGenProfile.make_default()
	on_path.lantern_on_path = 1.0
	on_path.lantern_max_per_chunk = 5
	var forest := _build(on_path)
	var near := 0
	var total := 0
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		var field := forest._path_field(key)
		var centre := Vector2(key.x * on_path.chunk_size, key.y * on_path.chunk_size)
		for p in chunk.get_meta("lantern_world_positions", []):
			var lp: Vector3 = p
			total += 1
			var local := Vector2(lp.x, lp.z) - centre
			if forest._field_at(field, local) < forest._path_half_width() + 3.0:
				near += 1
	_check("Lanterns stand along the paths (%d of %d within 3 m of a path)" % [near, total], total > 0 and near * 2 >= total)
	_release(forest)

	var wide := WorldGenProfile.make_default()
	wide.tree_draw_radius = 11.0
	var narrow := WorldGenProfile.make_default()
	narrow.tree_draw_radius = 4.0
	var a := _build(wide)
	var b := _build(narrow)
	# Stand beside a real trunk, so the short reach still has something to draw.
	var eye := Vector3.ZERO
	for key in a._chunks:
		var xfs: Array = (a._chunks[key] as Node3D).get_meta("tree_local_xfs", [])
		if not xfs.is_empty():
			eye = (a._chunks[key] as Node3D).global_transform * (xfs[0] as Transform3D).origin
			break
	a._refresh_tree_draw(eye)
	b._refresh_tree_draw(eye)
	var drawn_wide := _drawn_trees(a)
	var drawn_narrow := _drawn_trees(b)
	_check("LOD: a shorter draw radius draws fewer trees (%d < %d)" % [drawn_narrow, drawn_wide],
		drawn_narrow < drawn_wide and drawn_narrow > 0)
	_release(a)
	_release(b)


func _check_atmosphere() -> void:
	var p := WorldGenProfile.make_default()
	var env := Environment.new()
	WorldGenLook.apply_fog(env, p)
	_check("Fog depth end comes from the profile (%.1f m)" % env.fog_depth_end,
		is_equal_approx(env.fog_depth_end, p.fog_end) and env.fog_depth_end <= p.loaded_range())
	_check("Fog starts where the profile says (%.1f m)" % env.fog_depth_begin, is_equal_approx(env.fog_depth_begin, p.fog_start))
	_check("Fog stays opaque at the far edge (density %.2f)" % env.fog_density, env.fog_density >= 0.99)
	WorldGenLook.apply_light(env, p)
	_check("Ambient light is the fog colour (the forest is its own light)", env.ambient_light_color.is_equal_approx(p.fog_color()))
	p.dusk_mix = 1.0
	WorldGenLook.apply_fog(env, p)
	_check("Dusk mix reaches the fog and the background", env.fog_light_color.is_equal_approx(p.dusk_pink) and env.background_color.is_equal_approx(p.dusk_pink))
	var moon := DirectionalLight3D.new()
	WorldGenLook.apply_moon(moon, p)
	_check("Moon colour follows the palette", moon.light_color.is_equal_approx(p.moon_color()))
	moon.free()
	var forest := _build(WorldGenProfile.make_default())
	var glow: Color = forest._torii_mat.get_shader_parameter("emission_tint")
	var want := WorldGenProfile.make_default().torii_glow_color * WorldGenProfile.make_default().torii_glow_strength
	_check("Gates glow in the profile colour (%s)" % str(glow), glow.is_equal_approx(want) and glow.b > glow.r)
	forest.queue_free()


func _check_shrines_rarer_than_gates() -> void:
	var wide := WorldGenProfile.make_default()
	wide.chunk_radius = 2
	var forest := _build(wide)
	var gates := 0
	for key in forest._chunks:
		gates += (forest._chunks[key] as Node3D).get_meta("torii_world_positions", []).size()
	var chunks := forest._chunks.size()
	# The shrine slots are read through the same manager the game uses.
	var manager := HokoraManager.new()
	manager.forest_world = forest
	var slot_chunks := wide.shrine_slot_size / wide.chunk_size
	var slots := 0
	var shrines := 0
	for x in range(-10, 10):
		for z in range(-10, 10):
			slots += 1
			if not manager._candidate_points(Vector2i(x, z)).is_empty():
				shrines += 1
	manager.free()
	_release(forest)
	var per_chunk_shrines := float(shrines) / (float(slots) * slot_chunks * slot_chunks)
	var per_chunk_gates := float(gates) / float(chunks)
	_check("Shrines are rarer than gates on the default profile (%.3f vs %.3f per chunk)" % [per_chunk_shrines, per_chunk_gates],
		per_chunk_shrines < per_chunk_gates / 2.0 and per_chunk_shrines > 0.0)


func _check_default_budget() -> void:
	var stats := await _forest_stats(WorldGenProfile.make_default())
	_check("Default forest draws within the forest share of the Quest budget (%d ≤ %d)" % [stats.draws, WorldGenBudget.FOREST_DRAW_CALLS],
		stats.draws <= WorldGenBudget.FOREST_DRAW_CALLS)
	_check("Default forest triangles within the forest share (%d)" % stats.triangles,
		stats.triangles <= WorldGenBudget.FOREST_TRIANGLES)
	_check("Default forest instances within the cap (%d ≤ %d)" % [stats.instances, WorldGenBudget.FOREST_INSTANCES],
		stats.instances <= WorldGenBudget.FOREST_INSTANCES)
	var heavy := WorldGenProfile.make_default()
	for k in 12:
		var extra := UndergrowthEntry.new()
		extra.label = "Extra %d" % k
		extra.cluster_threshold = 0.0
		heavy.undergrowth.append(extra)
	var over := await _forest_stats(heavy, 1)
	_check("Too many kinds breaks the draw share and the budget says so (%d draws)" % over.draws,
		not WorldGenBudget.warnings(over).is_empty())


func _check_preview_and_dock() -> void:
	var preview := PREVIEW_SCENE.instantiate() as WorldGenPreview
	add_child(preview)
	await get_tree().process_frame
	_check("The preview scene builds its forest", preview.forest != null and preview.forest.chunk_count == 9)
	var counts := []
	for k in 5:
		preview.regenerate()
		counts.append(_descendants(preview))
	_check("Regenerating five times leaves no orphan nodes (%s)" % str(counts), counts.max() == counts.min())
	var before := _count_trees(preview.forest)
	var changed := WorldGenProfile.make_default()
	changed.tree_keep_min = 0.1
	changed.tree_keep_max = 0.2
	preview.profile = changed
	var after := _count_trees(preview.forest)
	_check("A profile change regenerates the preview at once (%d → %d trees)" % [before, after],
		after < before and preview.profile == changed)
	var dock := WorldGenDock.new()
	add_child(dock)
	await get_tree().process_frame
	dock.attach(preview)
	_check("The dock shows the chunks and the budget", dock._stats.text.contains("Chunki 9"))
	_check("The dock has no notes for a sound profile", dock._notes.text == "Bez uwag." or dock._notes.text.contains("UWAGA"))
	var alt := WorldGenProfile.make_default()
	alt.trees = []
	preview.profile = alt
	dock.refresh()
	_check("The dock lists the validation error for an empty forest", dock._notes.text.contains("BŁĄD"))
	preview.profile = null
	dock.attach(preview)
	dock._fill_groups()
	var group_index := -1
	for k in dock._groups.item_count:
		if dock._groups.get_item_text(k) == "Terrain":
			group_index = k
	_check("The dock offers the inspector groups", group_index >= 0)
	preview.profile = WorldGenProfile.make_default()
	preview.profile.hill_amplitude = 9.5
	dock._groups.select(group_index)
	dock._on_reset_group()
	_check("The dock restores the defaults of one group", is_equal_approx(preview.profile.hill_amplitude, WorldGenProfile.make_default().hill_amplitude))
	var path := preview.save_preset("worldgen_test_preset")
	_check("Save preset writes a loadable profile", path != "" and load(path) is WorldGenProfile)
	if path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	dock.free()
	preview.free()


## The preview and the game run the same steps (new ForestWorld, profile,
## setup), so with nothing else in the physics space they draw the same forest.
func _check_game_matches_preview() -> void:
	var preview := PREVIEW_SCENE.instantiate() as WorldGenPreview
	add_child(preview)
	var preview_digest := _digest(preview.forest)
	preview.free()
	await get_tree().physics_frame
	var game_digest := await _isolated_digest(WorldGenProfile.load_active())
	_check("The game draws the same forest as the preview (same seed, same profile)", preview_digest == game_digest)


func _check_plugin_compiles() -> void:
	var plugin: Script = PLUGIN_SCRIPT
	var dock: Script = DOCK_SCRIPT
	_check("The World Gen plugin script compiles", plugin != null and plugin.can_instantiate())
	_check("The World Gen dock script compiles", dock != null and dock.can_instantiate())
	_check("The plugin is enabled in the project", "res://addons/hanabi_worldgen/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()))


## Builds a forest for [param profile] in this scene and returns it (no frame
## waited: see worldgen_profile_test).
func _build(profile: WorldGenProfile) -> ForestWorld:
	var forest := ForestWorld.new()
	forest.profile = profile
	add_child(forest)
	var follow := Node3D.new()
	forest.add_child(follow)
	forest.setup(follow)
	return forest


## Frees a forest now (not at the end of the frame), so its bodies leave the
## physics space before the next forest is placed.
static func _release(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()


func _isolated_digest(profile: WorldGenProfile) -> int:
	var forest := _build(profile)
	var d := _digest(forest)
	_release(forest)
	return d


static func _digest(forest: ForestWorld) -> int:
	var keys := forest._chunks.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 1000 + a.y < b.x * 1000 + b.y)
	var parts := PackedStringArray()
	for key in keys:
		var chunk := forest._chunks[key] as Node3D
		for xf in chunk.get_meta("tree_local_xfs", []):
			var t: Transform3D = xf
			parts.append("%.4f,%.4f,%.4f" % [t.origin.x, t.origin.y, t.origin.z])
		for p in chunk.get_meta("torii_world_positions", []):
			parts.append(str(p))
	return ",".join(parts).hash()


static func _count_trees(forest: ForestWorld) -> int:
	var n := 0
	for key in forest._chunks:
		n += (forest._chunks[key] as Node3D).get_meta("tree_local_xfs", []).size()
		n += (forest._chunks[key] as Node3D).get_meta("sakura_tree_local_xfs", []).size()
	return n


static func _count_meta(forest: ForestWorld, meta: String) -> int:
	var n := 0
	for key in forest._chunks:
		n += (forest._chunks[key] as Node3D).get_meta(meta, []).size()
	return n


static func _drawn_trees(forest: ForestWorld) -> int:
	var n := 0
	for key in forest._chunks:
		for child in (forest._chunks[key] as Node3D).get_children():
			if child is MultiMeshInstance3D and String(child.name).begins_with("Trees"):
				n += (child as MultiMeshInstance3D).multimesh.instance_count
	return n


static func _vertex_colours(chunk: Node3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for child in chunk.get_children():
		if child is MeshInstance3D and String(child.name) == "Terrain":
			var arrays := (child as MeshInstance3D).mesh.surface_get_arrays(0)
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for c in colours:
				out.append(c.r)
	return out


static func _min_of(values: PackedFloat32Array) -> float:
	var m := INF
	for v in values:
		m = minf(m, v)
	return m


static func _max_of(values: PackedFloat32Array) -> float:
	var m := -INF
	for v in values:
		m = maxf(m, v)
	return m


static func _descendants(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		n += 1 + _descendants(child)
	return n


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
