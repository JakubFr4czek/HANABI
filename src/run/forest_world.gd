class_name ForestWorld
extends Node3D
## Endless forest illusion around the run shrine (docs/NIGHT_PLAN.md §3, GDD §9).
## Rolling hills from FastNoiseLite, props via shared MultiMeshes (trees, torii,
## lanterns, rocks). Chunks recycle with the player, who can walk out of the
## shrine clearing into the forest: every chunk carries a terrain collider, and
## view ranges / ground fade are measured from the camera so fog swallows the
## chunk edges wherever the player stands.

const CHUNK_SIZE := 28.0
const CHUNK_RADIUS := 1
## The run spawns in a small glade of the forest itself (no dojo disc): trees
## stand a few metres away and the ground starts rolling soon after.
const CLEARING_RADIUS := 5.2
const PROP_CLEARING_RADIUS := 3.4
const CLEARING_HEIGHT := 0.0
const HILL_AMPLITUDE := 3.1
## Smaller mounds and hollows on top of the rolling hills.
const BUMP_AMPLITUDE := 0.42
const TERRAIN_RES := 19
## Chunks are 28 m and the 3×3 ring keeps >= 14 m loaded around the player;
## everything is fully fogged by VIEW_RANGE_END (RunGame.RUN_FOG_END <= it).
const VIEW_RANGE_END := 14.0
## The ground no longer discards itself near the player: hills cut away under
## their trees left props floating. Depth fog alone dissolves them.
const GROUND_FADE_START := 60.0
const GROUND_FADE_END := 70.0
## Shader layer -> Poly Haven texture set in assets/textures/forest_ground/.
const GROUND_LAYERS := {"soil": "forrest_ground_01", "grass": "leafy_grass", "stone": "rocky_trail"}
const SHAFT_SHADER := preload("res://src/shaders/moon_shaft.gdshader")
const MAX_SHAFTS_PER_CHUNK := 5
const SHAFT_LENGTH := 15.0
const GROUND_SHADER := preload("res://src/shaders/forest_ground.gdshader")
const WET_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const TORII_SCENE := preload("res://assets/models/environment/forest_quaternius/torii_gate_polyfork.glb")
## Grab3D CC0 cherry tree, crown simplified, scaled to a tall shrine cedar.
const TREE_SCENE := preload("res://assets/models/environment/forest_trees/cherry_forest.gltf")
const TREE_DIFFUSE := preload("res://src/shaders/forest_diffuse.gdshader")
const TREE_ALBEDO := preload("res://assets/models/environment/forest_trees/cherry_forest_albedo.jpg")
const TREE_NORMAL := preload("res://assets/models/environment/forest_trees/cherry_forest_normal.jpg")
const TORII_MESH_SCALE := 0.42
## Trunks and gate pillars collide on their own layer: the player walks into
## them, yōkai ragdolls do not (their limbs snag and topple them); yōkai steer
## around them instead (trunk_push).
const TRUNK_LAYER := 64
const TRUNK_CELL := 3.0
## Trees per chunk side on the jittered grid (28 m / 9 ≈ 3.1 m spacing).
const TREE_GRID := 9
## Fog is solid by 9 m. Trees past this are the fog's color already, so they
## are not drawn; the mesh is a real tree and drawing every chunk would blow
## the Quest primitive cap.
const TREE_DRAW_RADIUS := 9.5
const MAX_TREES_PER_CHUNK := TREE_GRID * TREE_GRID
## Full-size gates met now and then in the fog (GDD §9).
const MAX_TORII_PER_CHUNK := 1
const TORII_CHUNK_CHANCE := 0.34
const TORII_HEIGHT := Vector2(4.2, 6.2)
const MAX_LANTERNS_PER_CHUNK := 5
const MAX_ROCKS_PER_CHUNK := 4

var follow: Node3D
## Unit vector toward the moon (RunGame sets it from the Moon light).
var moon_direction := Vector3(0.25, 0.9, 0.35).normalized()
var chunk_count := 0
var active_chunk_keys: Array[Vector2i] = []
var center_chunk := Vector2i.ZERO

var _chunks: Dictionary = {}
## Vector2i cell -> Array of Vector3(x, z, radius) for trunk_push().
var _trunk_cells: Dictionary = {}
var _height_noise := FastNoiseLite.new()
var _bump_noise := FastNoiseLite.new()
var _scatter_noise := FastNoiseLite.new()
var _corridor_noise := FastNoiseLite.new()
var _tree_mesh: Mesh
var _shaft_mesh: QuadMesh
var _shaft_mat: ShaderMaterial
var _torii_mesh: Mesh
var _lantern_mesh: Mesh
var _rock_mesh: Mesh
var _ground_mat: ShaderMaterial
var _tree_mat: ShaderMaterial
var _torii_mat: ShaderMaterial
var _lantern_mat: ShaderMaterial
var _rock_mat: ShaderMaterial
var _lightmap_gi: LightmapGI
var _static_gi := false


func uses_static_gi() -> bool:
	return _static_gi


## Procedural chunks recycle — no stable UV2 for LightmapGI. We fake contact
## shadowing in forest shaders instead (NIGHT_PLAN §8).
func uses_shader_baked_look() -> bool:
	return true


func setup(p_follow: Node3D, arena_lightmap: LightmapGI = null) -> void:
	add_to_group("forest_world")
	follow = p_follow
	_height_noise.seed = 0x464F52455354
	_height_noise.frequency = 0.034
	_height_noise.fractal_octaves = 3
	_bump_noise.seed = 0x42554D50
	_bump_noise.frequency = 0.11
	_bump_noise.fractal_octaves = 1
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
	_trunk_cells.clear()
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
	_refresh_tree_draw(follow.global_position)


func height_at(wx: float, wz: float) -> float:
	var d := Vector2(wx, wz).length()
	if d < CLEARING_RADIUS - 1.2:
		return CLEARING_HEIGHT
	var blend := smoothstep(CLEARING_RADIUS - 1.5, CLEARING_RADIUS + 9.0, d)
	var n := _height_noise.get_noise_2d(wx, wz) * HILL_AMPLITUDE
	n += _bump_noise.get_noise_2d(wx, wz) * BUMP_AMPLITUDE
	return lerpf(CLEARING_HEIGHT, CLEARING_HEIGHT + n, blend)


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
			_forget_trunks(_chunks[key] as Node3D)
			(_chunks[key] as Node3D).queue_free()
			_chunks.erase(key)
	active_chunk_keys.clear()
	for key in wanted.keys():
		active_chunk_keys.append(key)
		if not _chunks.has(key):
			_chunks[key] = _make_chunk(key)
	chunk_count = _chunks.size()
	if follow:
		_refresh_tree_draw(follow.global_position)


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
	terrain.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_set_view_range(terrain)
	root.add_child(terrain)
	root.add_child(_build_terrain_collider(terrain.mesh as ArrayMesh))

	var clearing_props := 0
	clearing_props += _populate_multimesh(root, "Trees", _tree_mesh, _tree_mat, MAX_TREES_PER_CHUNK, coord, 0)
	clearing_props += _populate_multimesh(root, "Torii", _torii_mesh, _torii_mat, MAX_TORII_PER_CHUNK, coord, 1)
	clearing_props += _populate_multimesh(root, "Lanterns", _lantern_mesh, _lantern_mat, MAX_LANTERNS_PER_CHUNK, coord, 2)
	clearing_props += _populate_multimesh(root, "Rocks", _rock_mesh, _rock_mat, MAX_ROCKS_PER_CHUNK, coord, 3)
	_place_senbon_corridor(root, coord)
	_place_moon_shafts(root, coord)
	root.set_meta("clearing_props", clearing_props)
	return root


func _populate_multimesh(root: Node3D, label: String, mesh: Mesh, mat: Material, max_count: int,
		coord: Vector2i, kind: int) -> int:
	var transforms: Array[Transform3D] = []
	var clearing_hits := 0
	# Deterministic per chunk and kind, so a recycled chunk grows back the same.
	# (The old per-index LCG hash was correlated and lined trees up in rows.)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([coord.x, coord.y, kind, 0x464F52])
	for p in _scatter_points(rng, kind, max_count):
		var lx: float = p.x
		var lz: float = p.y
		var wx := root.position.x + lx
		var wz := root.position.z + lz
		if _in_clearing(wx, wz):
			clearing_hits += 1
			continue
		var density := _scatter_noise.get_noise_2d(wx * 0.09, wz * 0.09) * 0.5 + 0.5
		if kind == 0:
			# Clumps and thinner stands, never empty swaths.
			if rng.randf() > lerpf(0.5, 0.97, density):
				continue
		elif kind == 1:
			# A gate now and then: about one chunk in three holds one.
			if rng.randf() > TORII_CHUNK_CHANCE:
				continue
		elif kind == 3:
			if density < 0.56:
				continue
		elif density < 0.5:
			continue
		var hy := height_at(wx, wz)
		var scale := rng.randf_range(0.85, 1.4)
		if kind == 1:
			scale = torii_scale_for_height(rng.randf_range(TORII_HEIGHT.x, TORII_HEIGHT.y))
		elif kind == 2:
			scale *= rng.randf_range(0.7, 0.95)
		elif kind == 3:
			scale *= rng.randf_range(1.0, 2.3)  # boulders, not pebbles
		var angle := rng.randf() * TAU
		var basis := Basis.from_euler(Vector3(0.0, angle, 0.0)) * Basis.from_scale(Vector3.ONE * scale)
		var xf := Transform3D(basis, Vector3(lx, hy, lz))
		transforms.append(xf)
		var props: Array = root.get_meta("prop_world_positions", [])
		props.append(Vector3(wx, hy, wz))
		root.set_meta("prop_world_positions", props)
	if kind == 0:
		root.set_meta("tree_local_xfs", transforms)
	if not transforms.is_empty():
		_commit_multimesh(root, label, mesh, mat, transforms)
		if kind == 0 or kind == 1:
			root.add_child(_build_trunk_colliders(transforms, kind, root))
	return clearing_hits


## Local (x, z) candidates. Trees use a jittered grid (one per ~3 m cell):
## even spacing reads as a natural stand, pure random leaves clumps and holes.
func _scatter_points(rng: RandomNumberGenerator, kind: int, max_count: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var half := CHUNK_SIZE * 0.5
	if kind == 0:
		var cell := CHUNK_SIZE / float(TREE_GRID)
		for cx in TREE_GRID:
			for cz in TREE_GRID:
				pts.append(Vector2(-half + (float(cx) + rng.randf_range(0.08, 0.92)) * cell,
					-half + (float(cz) + rng.randf_range(0.08, 0.92)) * cell))
		return pts
	for _i in max_count:
		pts.append(Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)))
	return pts


## Shafts of moonlight through canopy gaps: a few per chunk, one always over
## the spawn glade so the run opens under a beam.
func _place_moon_shafts(root: Node3D, coord: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([coord.x, coord.y, 0x4D4F4F4E])
	# Steeper than the real moon so beams drop between trunks instead of
	# lying across the forest.
	var axis := Vector3(moon_direction.x * 0.45, maxf(moon_direction.y, 0.55), moon_direction.z * 0.45).normalized()
	var transforms: Array[Transform3D] = []
	var count := rng.randi_range(2, MAX_SHAFTS_PER_CHUNK)
	for i in count:
		var lx := rng.randf_range(-CHUNK_SIZE * 0.5, CHUNK_SIZE * 0.5)
		var lz := rng.randf_range(-CHUNK_SIZE * 0.5, CHUNK_SIZE * 0.5)
		if coord == Vector2i.ZERO and i == 0:
			lx = 1.2
			lz = -1.6
		var wx := root.position.x + lx
		var wz := root.position.z + lz
		var width := rng.randf_range(0.9, 2.1)
		var basis := Basis(axis.cross(Vector3.FORWARD).normalized() * width, axis * SHAFT_LENGTH, Vector3.FORWARD)
		transforms.append(Transform3D(basis, Vector3(lx, height_at(wx, wz) - 0.3, lz)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _shaft_mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = "MoonShafts"
	inst.multimesh = mm
	inst.material_override = _shaft_mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Vertices are rebuilt in the shader; give culling the full beam volume.
	inst.custom_aabb = AABB(Vector3(-CHUNK_SIZE, -2.0, -CHUNK_SIZE), Vector3(CHUNK_SIZE * 2.0, SHAFT_LENGTH + 4.0, CHUNK_SIZE * 2.0))
	root.add_child(inst)


## Solid trunks and gate pillars. The player stops on TRUNK_LAYER; yōkai
## ragdolls ignore it (limbs snag and topple) and steer with trunk_push.
func _build_trunk_colliders(transforms: Array[Transform3D], kind: int, root: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TrunkColliders" if kind == 0 else "ToriiColliders"
	body.collision_layer = TRUNK_LAYER
	body.collision_mask = 0
	var registered: Array = root.get_meta("trunk_entries", [])
	for xf in transforms:
		var s := xf.basis.get_scale().x
		if kind == 0:
			# Chest-height bark is about 0.45 m across at scale 1.
			var trunk_r := 0.42 * s
			_add_cylinder(body, xf.origin + Vector3(0.0, 1.8 * s, 0.0), trunk_r, 3.6 * s)
			registered.append(_remember_trunk(root.position + xf.origin, trunk_r))
		else:
			# Two pillars, each ~0.34 of the gate width off its center.
			var h := _torii_mesh.get_aabb().size.y * s if _torii_mesh else 4.5
			var half_span := _torii_mesh.get_aabb().size.x * s * 0.34 if _torii_mesh else 1.5
			var side := xf.basis.x.normalized()
			for sgn_v in [-1.0, 1.0]:
				var sgn := float(sgn_v)
				var pillar := xf.origin + side * half_span * sgn
				_add_cylinder(body, pillar + Vector3(0.0, h * 0.35, 0.0), h * 0.045, h * 0.7)
				registered.append(_remember_trunk(root.position + pillar, h * 0.045))
	root.set_meta("trunk_entries", registered)
	return body


func _remember_trunk(world: Vector3, radius: float) -> Array:
	var cell := Vector2i(int(floor(world.x / TRUNK_CELL)), int(floor(world.z / TRUNK_CELL)))
	var entry := Vector3(world.x, world.z, radius)
	if not _trunk_cells.has(cell):
		_trunk_cells[cell] = []
	(_trunk_cells[cell] as Array).append(entry)
	return [cell, entry]


func _forget_trunks(root: Node3D) -> void:
	for pair in root.get_meta("trunk_entries", []):
		var list: Array = _trunk_cells.get(pair[0], [])
		list.erase(pair[1])
		if list.is_empty():
			_trunk_cells.erase(pair[0])


## Steering push away from trunks / gate pillars near [param pos] for a body
## heading along [param heading]: mostly sideways, so a trunk in the way is
## walked around instead of pushing straight back against the walk.
func trunk_push(pos: Vector3, heading: Vector3, reach: float = 0.95) -> Vector3:
	var push := Vector3.ZERO
	var cx := int(floor(pos.x / TRUNK_CELL))
	var cz := int(floor(pos.z / TRUNK_CELL))
	var h := Vector3(heading.x, 0.0, heading.z)
	h = h.normalized() if h.length_squared() > 1e-4 else Vector3.FORWARD
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			for e in _trunk_cells.get(Vector2i(cx + ox, cz + oz), []):
				var t: Vector3 = e
				var away := Vector3(pos.x - t.x, 0.0, pos.z - t.y)
				var gap := away.length() - t.z
				if gap >= reach or away.length_squared() < 1e-6:
					continue
				var strength := 1.0 - maxf(gap, 0.0) / reach
				var lateral := away - h * away.dot(h)
				if lateral.length_squared() < 1e-4:
					lateral = h.cross(Vector3.UP)
				push += lateral.normalized() * strength * 1.3 + away.normalized() * strength * 0.4
	return push


static func _add_cylinder(body: StaticBody3D, pos: Vector3, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	cs.position = pos
	body.add_child(cs)


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
	mm_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_set_view_range(mm_inst)
	root.add_child(mm_inst)
	call_deferred("_refresh_multimesh_transforms", mm_inst, transforms)


func _refresh_multimesh_transforms(mm_inst: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	if not is_instance_valid(mm_inst) or mm_inst.multimesh == null:
		return
	if mm_inst.name == "Trees" and follow:
		_refresh_tree_draw(follow.global_position)
		return
	var mm := mm_inst.multimesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])


## Trees past the fog are the fog. Keep their colliders; drop the draw.
func _refresh_tree_draw(origin: Vector3) -> void:
	var r2 := TREE_DRAW_RADIUS * TREE_DRAW_RADIUS
	for key in _chunks:
		var chunk := _chunks[key] as Node3D
		var inst := chunk.get_node_or_null("Trees") as MultiMeshInstance3D
		if inst == null or inst.multimesh == null:
			continue
		var all: Array = chunk.get_meta("tree_local_xfs", [])
		var mm := inst.multimesh
		var near: Array[Transform3D] = []
		var base := chunk.position
		for xf in all:
			var placed := xf as Transform3D
			var dx := base.x + placed.origin.x - origin.x
			var dz := base.z + placed.origin.z - origin.z
			if dx * dx + dz * dz > r2:
				continue
			near.append(placed)
		# instance_count is what the headless perf probe counts. A visibility
		# cap on top of the full buffer still submitted every tree.
		mm.instance_count = near.size()
		for i in near.size():
			mm.set_instance_transform(i, near[i])


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
	mm_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_set_view_range(mm_inst)
	root.add_child(mm_inst)

	var transforms: Array[Transform3D] = []
	var gate_count := 4 + int((_hash01(_hash_coord(coord, 9, 0), 0) * 4.0))
	var spacing := 4.2
	var start := -spacing * float(gate_count - 1) * 0.5
	for g in gate_count:
		var along := start + float(g) * spacing
		var lx := along if axis_x else -CHUNK_SIZE * 0.15
		var lz := -CHUNK_SIZE * 0.15 if axis_x else along
		var wx := root.position.x + lx
		var wz := root.position.z + lz
		if _in_clearing(wx, wz, 0.35):
			continue
		var hy := height_at(wx, wz)
		var s := torii_scale_for_height(4.4 + float(g) * 0.12)
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


func _build_terrain_collider(mesh: ArrayMesh) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainCollider"
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(mesh.get_faces())
	shape.shape = concave
	body.add_child(shape)
	return body


func _in_clearing(wx: float, wz: float, margin: float = 0.0) -> bool:
	return Vector2(wx, wz).length() < PROP_CLEARING_RADIUS + margin


## Instance scale that makes the shared gate mesh [param height] metres tall.
func torii_scale_for_height(height: float) -> float:
	var h := _torii_mesh.get_aabb().size.y if _torii_mesh else 1.0
	return height / maxf(h, 0.1)


## World position of the generated gate nearest to [param from] (INF if none).
func nearest_torii_position(from: Vector3) -> Vector3:
	var best := Vector3.INF
	for key in _chunks:
		var chunk := _chunks[key] as Node3D
		for child in chunk.get_children():
			if child is MultiMeshInstance3D and String(child.name) in ["Torii", "SenbonTorii"]:
				var mm := (child as MultiMeshInstance3D).multimesh
				for i in mm.instance_count:
					var p := chunk.global_transform * mm.get_instance_transform(i).origin
					if best == Vector3.INF or p.distance_to(from) < best.distance_to(from):
						best = p
	return best


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
	_ground_mat.set_shader_parameter("fill", 0.0)
	_ground_mat.set_shader_parameter("cavity_ao", 0.85)
	_ground_mat.set_shader_parameter("ambient_fill", 0.1)
	# Damp, not mirror-wet: wet normals over 1K scans sparkle white in VR.
	_ground_mat.set_shader_parameter("wetness", 0.3)
	_ground_mat.set_shader_parameter("roughness_wet", 0.72)
	for layer in GROUND_LAYERS:
		var dir := "res://assets/textures/forest_ground/%s/%s" % [GROUND_LAYERS[layer], GROUND_LAYERS[layer]]
		_ground_mat.set_shader_parameter(layer + "_albedo", load(dir + "_diff_1k.jpg"))
		_ground_mat.set_shader_parameter(layer + "_normal", load(dir + "_nor_gl_1k.jpg"))
	_ground_mat.set_shader_parameter("fog_fade_start", GROUND_FADE_START)
	_ground_mat.set_shader_parameter("fog_fade_end", GROUND_FADE_END)

	_tree_mat = ShaderMaterial.new()
	_tree_mat.shader = TREE_DIFFUSE
	_tree_mat.set_shader_parameter("albedo_texture", TREE_ALBEDO)
	_tree_mat.set_shader_parameter("normal_texture", TREE_NORMAL)

	_torii_mat = ShaderMaterial.new()
	_torii_mat.shader = WET_SHADER
	_torii_mat.set_shader_parameter("base_color", Color(0.28, 0.06, 0.05))
	_torii_mat.set_shader_parameter("roughness_dry", 0.84)
	_torii_mat.set_shader_parameter("roughness_wet", 0.72)
	_torii_mat.set_shader_parameter("wetness", 0.28)
	_torii_mat.set_shader_parameter("waterline_y", -10.0)
	_torii_mat.set_shader_parameter("fill", 0.35)
	_torii_mat.set_shader_parameter("specular_scale", 0.0)
	_torii_mat.set_shader_parameter("fog_fill", 0.22)
	_torii_mat.set_shader_parameter("procedural_ao", 0.55)

	_lantern_mat = ShaderMaterial.new()
	_lantern_mat.shader = WET_SHADER
	_lantern_mat.set_shader_parameter("base_color", Color(0.42, 0.4, 0.36))
	_lantern_mat.set_shader_parameter("roughness_dry", 0.88)
	_lantern_mat.set_shader_parameter("roughness_wet", 0.75)
	_lantern_mat.set_shader_parameter("wetness", 0.25)
	_lantern_mat.set_shader_parameter("waterline_y", -10.0)
	_lantern_mat.set_shader_parameter("fill", 0.3)
	_lantern_mat.set_shader_parameter("specular_scale", 0.0)
	_lantern_mat.set_shader_parameter("fog_fill", 0.2)
	_lantern_mat.set_shader_parameter("emission_tint", Color(0.04, 0.05, 0.06))

	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = WET_SHADER
	_rock_mat.set_shader_parameter("base_color", Color(0.16, 0.16, 0.17))
	_rock_mat.set_shader_parameter("roughness_dry", 0.92)
	_rock_mat.set_shader_parameter("roughness_wet", 0.8)
	_rock_mat.set_shader_parameter("wetness", 0.22)
	_rock_mat.set_shader_parameter("waterline_y", -10.0)
	_rock_mat.set_shader_parameter("fill", 0.28)
	_rock_mat.set_shader_parameter("specular_scale", 0.0)
	_rock_mat.set_shader_parameter("fog_fill", 0.18)


## No per-node visibility range: Godot measures it to the node origin, i.e. a
## 28 m chunk's center, which culled every chunk but the one under the player
## (and all its trees). Depth fog (RunGame.RUN_FOG_END) hides chunk edges.
func _set_view_range(inst: GeometryInstance3D) -> void:
	inst.visibility_range_begin = 0.0
	inst.visibility_range_end = 0.0


func _build_meshes() -> void:
	_shaft_mesh = QuadMesh.new()
	_shaft_mesh.size = Vector2(1.0, 1.0)
	_shaft_mesh.center_offset = Vector3(0.0, 0.5, 0.0)
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = SHAFT_SHADER
	# Same grey as the fog, dim. A blue-white beam reads as a plastic tube.
	_shaft_mat.set_shader_parameter("shaft_color", Color(0.62, 0.64, 0.66))
	_shaft_mat.set_shader_parameter("intensity", 0.2)
	_tree_mesh = _merge_scene_meshes(TREE_SCENE, 1.0)
	if _tree_mesh == null:
		_tree_mesh = _build_tree_mesh()
	_torii_mesh = _build_torii_mesh()
	_lantern_mesh = _build_lantern_mesh()
	_rock_mesh = _extract_rock_mesh()


## Japanese cedar (sugi) as in shrine forests: a tall straight trunk and dark
## tiered canopy high overhead. In fog the forest reads through its trunks,
## which fade with distance; the old low broadleaf canopies hung at head
## height like floating boulders.
func _build_tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.42
	trunk.height = 15.5
	trunk.radial_segments = 7
	trunk.rings = 1
	trunk.cap_top = false
	trunk.cap_bottom = false
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 7.6, 0.0)))
	# Root flare so the trunk does not stab into the ground like a pole.
	var flare := CylinderMesh.new()
	flare.top_radius = 0.41
	flare.bottom_radius = 0.78
	flare.height = 0.9
	flare.radial_segments = 7
	flare.rings = 1
	flare.cap_top = false
	flare.cap_bottom = false
	st.append_from(flare, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)))
	# Lowest boughs far overhead: the player walks among bare trunks.
	var tiers := [[8.6, 2.6, 3.6], [11.0, 2.1, 3.2], [13.2, 1.5, 2.8], [15.0, 0.9, 2.2]]
	for t in tiers:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = float(t[1])
		cone.height = float(t[2])
		cone.radial_segments = 8
		cone.rings = 1
		cone.cap_bottom = true
		st.append_from(cone, 0, Transform3D(Basis(Vector3.UP, float(t[0])), Vector3(0.0, float(t[0]) + float(t[2]) * 0.5, 0.0)))
	st.generate_normals()
	return st.commit()

func _build_torii_mesh() -> ArrayMesh:
	var merged := _merge_scene_meshes(TORII_SCENE, TORII_MESH_SCALE)
	if merged:
		return merged
	return _box_mesh(Vector3(1.6, 1.5, 0.2), Vector3(0.0, 0.75, 0.0))


func _build_lantern_mesh() -> ArrayMesh:
	var parts: Array[Mesh] = []
	parts.append(_box_mesh(Vector3(0.22, 0.42, 0.22), Vector3(0.0, 0.21, 0.0)))
	parts.append(_box_mesh(Vector3(0.34, 0.28, 0.34), Vector3(0.0, 0.56, 0.0)))
	parts.append(_box_mesh(Vector3(0.4, 0.08, 0.4), Vector3(0.0, 0.76, 0.0)))
	return _merge_meshes(parts)


## The scanned rock_face_01 is ~20k triangles; dozens of MultiMesh copies blew
## the Quest triangle budget. A noise-displaced low-poly boulder (~80 tris)
## reads the same through rain and fog.
func _extract_rock_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 0.62
	sphere.radial_segments = 9
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = 0x524F434B
	noise.frequency = 2.1
	for i in verts.size():
		var v := verts[i]
		var bump := 1.0 + noise.get_noise_3dv(v * 1.7) * 0.32
		verts[i] = Vector3(v.x * bump * 1.25, maxf(v.y * bump, -0.12), v.z * bump * 0.95)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx.size():
		st.add_vertex(verts[idx[i]])
	st.generate_normals()
	return st.commit()


static func _merge_scene_meshes(scene: PackedScene, scale_factor: float) -> ArrayMesh:
	var inst := scene.instantiate()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wrote := false
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		var mesh := mesh_i.mesh
		if mesh == null:
			continue
		var local := _accumulate_local_transform(mesh_i, inst)
		var scaled := Transform3D(local.basis.scaled(Vector3.ONE * scale_factor), local.origin * scale_factor)
		st.append_from(mesh, 0, scaled)
		wrote = true
	inst.free()
	return st.commit() if wrote else null


static func _accumulate_local_transform(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


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
