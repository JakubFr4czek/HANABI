class_name ForestWorld
extends Node3D
## Endless forest illusion around the run shrine (docs/NIGHT_PLAN.md §3, GDD §9).
## Rolling hills from FastNoiseLite, props via shared MultiMeshes (trees, torii,
## lanterns, rocks). Chunks recycle with the player; dense scene fog hides seams.

const CHUNK_SIZE := 28.0
const CHUNK_RADIUS := 1
const CLEARING_RADIUS := 10.4
const PROP_CLEARING_RADIUS := 13.2
const TERRAIN_RES := 13
const VIEW_RANGE_END := 17.5
const HILL_FADE_START := 11.0
const HILL_FADE_END := 14.0
const GROUND_SHADER := preload("res://src/shaders/forest_ground.gdshader")
const WET_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const ROCK_SCENE := preload("res://assets/models/environment/rocks/rock_face_01/rock_face_01.gltf")
const MAX_TREES_PER_CHUNK := 14
const MAX_TORII_PER_CHUNK := 4
const MAX_LANTERNS_PER_CHUNK := 5
const MAX_ROCKS_PER_CHUNK := 4

var follow: Node3D
var chunk_count := 0
var active_chunk_keys: Array[Vector2i] = []
var center_chunk := Vector2i.ZERO

var _chunks: Dictionary = {}
var _height_noise := FastNoiseLite.new()
var _scatter_noise := FastNoiseLite.new()
var _corridor_noise := FastNoiseLite.new()
var _tree_mesh: Mesh
var _torii_mesh: Mesh
var _lantern_mesh: Mesh
var _rock_mesh: Mesh
var _ground_mat: ShaderMaterial
var _tree_mat: ShaderMaterial
var _torii_mat: ShaderMaterial
var _lantern_mat: ShaderMaterial
var _rock_mat: ShaderMaterial
var _tree_mesh_lod: Mesh
var _lightmap_gi: LightmapGI
var _static_gi := false


func uses_static_gi() -> bool:
	return _static_gi


func setup(p_follow: Node3D, arena_lightmap: LightmapGI = null) -> void:
	follow = p_follow
	_height_noise.seed = 0x464F52455354
	_height_noise.frequency = 0.028
	_height_noise.fractal_octaves = 4
	_scatter_noise.seed = 0x534341545445
	_scatter_noise.frequency = 0.11
	_corridor_noise.seed = 0x53454E424F4E
	_corridor_noise.frequency = 0.018
	_build_materials()
	_build_meshes()
	_lightmap_gi = arena_lightmap
	_static_gi = _lightmap_gi != null
	_rebuild_active_chunks()


func reset() -> void:
	for key in _chunks.keys():
		(_chunks[key] as Node3D).queue_free()
	_chunks.clear()
	center_chunk = Vector2i.ZERO
	chunk_count = 0
	active_chunk_keys.clear()
	if follow:
		_rebuild_active_chunks()


func _physics_process(_delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		return
	var next := _world_to_chunk(follow.global_position)
	if next != center_chunk:
		center_chunk = next
		_rebuild_active_chunks()


func height_at(wx: float, wz: float) -> float:
	var d := Vector2(wx, wz).length()
	if d < CLEARING_RADIUS - 1.2:
		return -0.42
	var blend := smoothstep(CLEARING_RADIUS - 1.5, CLEARING_RADIUS + 5.5, d)
	var n := _height_noise.get_noise_2d(wx, wz)
	var h := lerpf(-0.42, n * 3.8, blend)
	if d > HILL_FADE_START:
		h = lerpf(h, -0.46, smoothstep(HILL_FADE_START, HILL_FADE_END, d))
	return h


func props_in_clearing() -> int:
	var count := 0
	for key in _chunks:
		count += int(_chunks[key].get_meta("clearing_props", 0))
	return count


func _rebuild_active_chunks() -> void:
	var wanted: Dictionary = {}
	for ox in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
		for oz in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
			wanted[center_chunk + Vector2i(ox, oz)] = true
	for key in _chunks.keys():
		if not wanted.has(key):
			(_chunks[key] as Node3D).queue_free()
			_chunks.erase(key)
	active_chunk_keys.clear()
	for key in wanted.keys():
		active_chunk_keys.append(key)
		if not _chunks.has(key):
			_chunks[key] = _make_chunk(key)
	chunk_count = _chunks.size()


func _make_chunk(coord: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	add_child(root)
	root.position = Vector3(coord.x * CHUNK_SIZE, 0.0, coord.y * CHUNK_SIZE)

	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = _build_terrain_mesh(coord)
	terrain.material_override = _ground_mat
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_set_view_range(terrain)
	root.add_child(terrain)

	var clearing_props := 0
	clearing_props += _populate_multimesh(root, "Trees", _tree_mesh, _tree_mat, MAX_TREES_PER_CHUNK, coord, 0, _tree_mesh_lod)
	clearing_props += _populate_multimesh(root, "Torii", _torii_mesh, _torii_mat, MAX_TORII_PER_CHUNK, coord, 1)
	clearing_props += _populate_multimesh(root, "Lanterns", _lantern_mesh, _lantern_mat, MAX_LANTERNS_PER_CHUNK, coord, 2)
	clearing_props += _populate_multimesh(root, "Rocks", _rock_mesh, _rock_mat, MAX_ROCKS_PER_CHUNK, coord, 3)
	_place_senbon_corridor(root, coord)
	root.set_meta("clearing_props", clearing_props)
	return root


func _populate_multimesh(root: Node3D, label: String, mesh: Mesh, mat: Material, max_count: int,
		coord: Vector2i, kind: int, lod_mesh: Mesh = null) -> int:
	var transforms: Array[Transform3D] = []
	var lod_transforms: Array[Transform3D] = []
	var clearing_hits := 0
	for i in max_count:
		var seed := _hash_coord(coord, kind, i)
		var lx := _hash01(seed, 1) * CHUNK_SIZE - CHUNK_SIZE * 0.5
		var lz := _hash01(seed, 2) * CHUNK_SIZE - CHUNK_SIZE * 0.5
		var wx := root.position.x + lx
		var wz := root.position.z + lz
		if Vector2(wx, wz).length() < PROP_CLEARING_RADIUS or Vector2(lx, lz).length_squared() < 0.04:
			clearing_hits += 1
			continue
		var scatter := _scatter_noise.get_noise_2d(wx * 0.09, wz * 0.09)
		var threshold := 0.12 if kind == 3 else (-0.05 if kind == 1 else 0.0)
		if scatter < threshold:
			continue
		if kind == 0 and scatter < 0.18:
			continue
		var hy := height_at(wx, wz)
		var scale := 0.85 + _hash01(seed, 3) * 0.55
		if kind == 1:
			scale *= 0.55 + _hash01(seed, 4) * 0.35
		elif kind == 2:
			scale *= 0.7 + _hash01(seed, 4) * 0.25
		elif kind == 3:
			scale *= 0.45 + _hash01(seed, 4) * 0.35
		var angle := _hash01(seed, 5) * TAU
		var basis := Basis.from_euler(Vector3(0.0, angle, 0.0)) * Basis.from_scale(Vector3.ONE * scale)
		var xf := Transform3D(basis, Vector3(lx, hy, lz))
		var dist := Vector2(wx, wz).length()
		if kind == 0 and lod_mesh != null and dist > 11.5:
			lod_transforms.append(xf)
		else:
			transforms.append(xf)
		var props: Array = root.get_meta("prop_world_positions", [])
		props.append(Vector3(wx, hy, wz))
		root.set_meta("prop_world_positions", props)
	if not transforms.is_empty():
		_commit_multimesh(root, label, mesh, mat, transforms)
	if not lod_transforms.is_empty() and lod_mesh != null:
		_commit_multimesh(root, label + "LOD", lod_mesh, mat, lod_transforms)
	if transforms.is_empty() and lod_transforms.is_empty():
		return clearing_hits
	return clearing_hits


func _commit_multimesh(root: Node3D, label: String, mesh: Mesh, mat: Material,
		transforms: Array[Transform3D]) -> void:
	var mm_inst := MultiMeshInstance3D.new()
	mm_inst.name = label
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	mm_inst.multimesh = mm
	mm_inst.material_override = mat
	mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mm_inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_set_view_range(mm_inst)
	root.add_child(mm_inst)
	call_deferred("_refresh_multimesh_transforms", mm_inst, transforms)


func _refresh_multimesh_transforms(mm_inst: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	if not is_instance_valid(mm_inst) or mm_inst.multimesh == null:
		return
	var mm := mm_inst.multimesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])


func _place_senbon_corridor(root: Node3D, coord: Vector2i) -> void:
	var corridor_val := _corridor_noise.get_noise_2d(float(coord.x) * 1.7, float(coord.y) * 1.7)
	if corridor_val < 0.64:
		return
	var axis_x := corridor_val > 0.72
	var mm_inst := MultiMeshInstance3D.new()
	mm_inst.name = "SenbonTorii"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _torii_mesh
	mm.instance_count = 0
	mm_inst.multimesh = mm
	mm_inst.material_override = _torii_mat
	mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mm_inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_set_view_range(mm_inst)
	root.add_child(mm_inst)

	var transforms: Array[Transform3D] = []
	var gate_count := 4 + int((_hash01(_hash_coord(coord, 9, 0), 0) * 4.0))
	var spacing := 3.6
	var start := -spacing * float(gate_count - 1) * 0.5
	for g in gate_count:
		var along := start + float(g) * spacing
		var lx := along if axis_x else -CHUNK_SIZE * 0.15
		var lz := -CHUNK_SIZE * 0.15 if axis_x else along
		var wx := root.position.x + lx
		var wz := root.position.z + lz
		if Vector2(wx, wz).length() < PROP_CLEARING_RADIUS + 0.35:
			continue
		var hy := height_at(wx, wz)
		var s := 0.42 + float(g) * 0.02
		var basis := Basis.from_euler(Vector3(0.0, PI * 0.5 if axis_x else 0.0, 0.0)) * Basis.from_scale(Vector3.ONE * s)
		transforms.append(Transform3D(basis, Vector3(lx, hy, lz)))
		var props: Array = root.get_meta("prop_world_positions", [])
		props.append(Vector3(wx, hy, wz))
		root.set_meta("prop_world_positions", props)
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])


func _build_terrain_mesh(coord: Vector2i) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := CHUNK_SIZE / float(TERRAIN_RES - 1)
	for z in TERRAIN_RES - 1:
		for x in TERRAIN_RES - 1:
			var x0 := -CHUNK_SIZE * 0.5 + float(x) * step
			var z0 := -CHUNK_SIZE * 0.5 + float(z) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var wx0 := coord.x * CHUNK_SIZE + x0
			var wz0 := coord.y * CHUNK_SIZE + z0
			var wx1 := coord.x * CHUNK_SIZE + x1
			var wz1 := coord.y * CHUNK_SIZE + z1
			var p00 := Vector3(x0, height_at(wx0, wz0), z0)
			var p10 := Vector3(x1, height_at(wx1, wz0), z0)
			var p01 := Vector3(x0, height_at(wx0, wz1), z1)
			var p11 := Vector3(x1, height_at(wx1, wz1), z1)
			_add_tri(st, p00, p10, p11)
			_add_tri(st, p00, p11, p01)
	return st.commit()


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


func _build_materials() -> void:
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GROUND_SHADER
	_ground_mat.set_shader_parameter("fill", 1.42)

	_tree_mat = ShaderMaterial.new()
	_tree_mat.shader = WET_SHADER
	_tree_mat.set_shader_parameter("base_color", Color(0.07, 0.09, 0.11))
	_tree_mat.set_shader_parameter("roughness_dry", 0.82)
	_tree_mat.set_shader_parameter("roughness_wet", 0.48)
	_tree_mat.set_shader_parameter("wetness", 0.55)
	_tree_mat.set_shader_parameter("waterline_y", -10.0)
	_tree_mat.set_shader_parameter("fill", 1.25)

	_torii_mat = ShaderMaterial.new()
	_torii_mat.shader = WET_SHADER
	_torii_mat.set_shader_parameter("base_color", Color(0.34, 0.05, 0.05))
	_torii_mat.set_shader_parameter("roughness_dry", 0.52)
	_torii_mat.set_shader_parameter("roughness_wet", 0.34)
	_torii_mat.set_shader_parameter("wetness", 0.62)
	_torii_mat.set_shader_parameter("waterline_y", -10.0)
	_torii_mat.set_shader_parameter("fill", 1.18)
	_torii_mat.set_shader_parameter("emission_tint", Color(0.12, 0.02, 0.02))

	_lantern_mat = ShaderMaterial.new()
	_lantern_mat.shader = WET_SHADER
	_lantern_mat.set_shader_parameter("base_color", Color(0.52, 0.48, 0.42))
	_lantern_mat.set_shader_parameter("roughness_dry", 0.68)
	_lantern_mat.set_shader_parameter("roughness_wet", 0.38)
	_lantern_mat.set_shader_parameter("wetness", 0.58)
	_lantern_mat.set_shader_parameter("waterline_y", -10.0)
	_lantern_mat.set_shader_parameter("fill", 1.35)
	_lantern_mat.set_shader_parameter("emission_tint", Color(0.08, 0.12, 0.18))

	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = WET_SHADER
	_rock_mat.set_shader_parameter("base_color", Color(0.14, 0.14, 0.16))
	_rock_mat.set_shader_parameter("roughness_dry", 0.86)
	_rock_mat.set_shader_parameter("roughness_wet", 0.52)
	_rock_mat.set_shader_parameter("wetness", 0.65)
	_rock_mat.set_shader_parameter("waterline_y", -10.0)
	_rock_mat.set_shader_parameter("fill", 1.2)


func _set_view_range(inst: GeometryInstance3D) -> void:
	inst.visibility_range_begin = 0.0
	inst.visibility_range_end = VIEW_RANGE_END
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _build_meshes() -> void:
	_tree_mesh = _build_tree_mesh()
	_tree_mesh_lod = _box_mesh(Vector3(0.35, 1.25, 0.35), Vector3(0.0, 0.62, 0.0))
	_torii_mesh = _build_torii_mesh()
	_lantern_mesh = _build_lantern_mesh()
	_rock_mesh = _extract_rock_mesh()


func _build_tree_mesh() -> ArrayMesh:
	var parts: Array[Mesh] = []
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.09
	trunk.bottom_radius = 0.13
	trunk.height = 1.15
	trunk.radial_segments = 10
	parts.append(trunk)
	for i in 3:
		var canopy := SphereMesh.new()
		canopy.radius = 0.55 - float(i) * 0.08
		canopy.height = canopy.radius * 1.6
		canopy.radial_segments = 12
		canopy.rings = 8
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(canopy, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.25 + float(i) * 0.22, 0.0)))
		parts.append(st.commit())
	return _merge_meshes(parts)


func _build_torii_mesh() -> ArrayMesh:
	# Mid-poly torii for MultiMesh (full GLB torii blows Quest primitive budgets).
	var parts: Array[Mesh] = []
	for sx in [-1.0, 1.0]:
		var pillar := CylinderMesh.new()
		pillar.height = 1.62
		pillar.top_radius = 0.065
		pillar.bottom_radius = 0.085
		pillar.radial_segments = 8
		var st_p := SurfaceTool.new()
		st_p.begin(Mesh.PRIMITIVE_TRIANGLES)
		st_p.append_from(pillar, 0, Transform3D(Basis.IDENTITY, Vector3(0.78 * sx, 0.81, 0.0)))
		parts.append(st_p.commit())
	parts.append(_box_mesh(Vector3(1.72, 0.11, 0.14), Vector3(0.0, 1.38, 0.0)))
	parts.append(_box_mesh(Vector3(1.88, 0.16, 0.18), Vector3(0.0, 1.52, -0.02)))
	parts.append(_box_mesh(Vector3(0.22, 0.08, 0.22), Vector3(0.0, 1.02, 0.0)))
	return _merge_meshes(parts)


func _build_lantern_mesh() -> ArrayMesh:
	var parts: Array[Mesh] = []
	parts.append(_box_mesh(Vector3(0.22, 0.42, 0.22), Vector3(0.0, 0.21, 0.0)))
	parts.append(_box_mesh(Vector3(0.34, 0.28, 0.34), Vector3(0.0, 0.56, 0.0)))
	parts.append(_box_mesh(Vector3(0.4, 0.08, 0.4), Vector3(0.0, 0.76, 0.0)))
	return _merge_meshes(parts)


func _extract_rock_mesh() -> Mesh:
	var mesh := _extract_scene_mesh(ROCK_SCENE, 1.0)
	return mesh if mesh else _box_mesh(Vector3(0.8, 0.5, 0.7), Vector3.ZERO)


static func _extract_scene_mesh(scene: PackedScene, scale_factor: float) -> Mesh:
	var inst := scene.instantiate()
	var found: Mesh
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh:
			found = (mi as MeshInstance3D).mesh
			break
	inst.free()
	if found == null:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xform := Transform3D(Basis.from_scale(Vector3.ONE * scale_factor), Vector3.ZERO)
	st.append_from(found, 0, xform)
	return st.commit()


static func _box_mesh(size: Vector3, center: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var c := center
	var corners := [
		Vector3(-hx, -hy, -hz) + c, Vector3(hx, -hy, -hz) + c, Vector3(hx, hy, -hz) + c, Vector3(-hx, hy, -hz) + c,
		Vector3(-hx, -hy, hz) + c, Vector3(hx, -hy, hz) + c, Vector3(hx, hy, hz) + c, Vector3(-hx, hy, hz) + c,
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		var n: Vector3 = (corners[f[1]] - corners[f[0]]).cross(corners[f[3]] - corners[f[0]]).normalized()
		st.set_normal(n)
		st.add_vertex(corners[f[0]])
		st.set_normal(n)
		st.add_vertex(corners[f[1]])
		st.set_normal(n)
		st.add_vertex(corners[f[2]])
		st.set_normal(n)
		st.add_vertex(corners[f[0]])
		st.set_normal(n)
		st.add_vertex(corners[f[2]])
		st.set_normal(n)
		st.add_vertex(corners[f[3]])
	return st.commit()


static func _merge_meshes(parts: Array[Mesh]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mesh in parts:
		st.append_from(mesh, 0, Transform3D.IDENTITY)
	return st.commit()


func total_prop_instances() -> int:
	var total := 0
	for key in _chunks:
		var chunk := _chunks[key] as Node3D
		for child in chunk.get_children():
			if child is MultiMeshInstance3D:
				total += (child as MultiMeshInstance3D).multimesh.instance_count
	return total


func nearest_prop_distance() -> float:
	var best := INF
	for key in _chunks:
		var chunk := _chunks[key] as Node3D
		for wp_v in chunk.get_meta("prop_world_positions", []):
			var wp: Vector3 = wp_v
			var flat := Vector2(wp.x, wp.z).length()
			if flat < PROP_CLEARING_RADIUS:
				best = minf(best, flat)
	return best


static func _world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CHUNK_SIZE)), int(floor(pos.z / CHUNK_SIZE)))


static func _hash_coord(coord: Vector2i, kind: int, index: int) -> int:
	return int(coord.x * 73856093 ^ coord.y * 19349663 ^ kind * 83492791 ^ index * 50331653) & 0x7fffffff


static func _hash01(seed: int, channel: int) -> float:
	return float((seed * 1103515245 + channel * 12345 + 12345) & 0x7fffffff) / float(0x7fffffff)
