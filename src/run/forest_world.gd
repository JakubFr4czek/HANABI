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
## Broad, sparse hills and valleys over ~75 m. Mostly flat ground with an
## occasional big swell — never a washboard.
const HILL_AMPLITUDE := 4.6
## A gentle roll on top, over ~20 m.
const BUMP_AMPLITUDE := 0.18
const TERRAIN_RES := 41
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
## Fog is solid by RUN_FOG_END. Trees past this are the fog's color already,
## so they are not drawn; the mesh is a real tree and drawing every chunk
## would blow the Quest primitive cap.
const TREE_DRAW_RADIUS := 11.0
## Past the old 9.5 m line every second tree is skipped (stable per-tree hash,
## so walking does not shimmer): far trunks still read through the fog at a
## fraction of the Quest triangle cost.
const TREE_FAR_KEEP := 0.5
const TREE_FAR_START := 9.5
const MAX_TREES_PER_CHUNK := TREE_GRID * TREE_GRID
## Full-size gates met now and then in the fog (GDD §9). About one chunk in
## three holds gates (same chunk set as before, so no new MultiMesh draw
## calls); a chosen chunk holds a small group instead of a lone gate.
const MAX_TORII_PER_CHUNK := 3
const TORII_CHUNK_CHANCE := 0.34
const TORII_GROUP_KEEP := 0.75
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
## Chunk coord -> {spots: Array[Vector4], clearing: int}. Spots are world xz, scale, yaw.
var _tree_spot_cache: Dictionary = {}
var _spots_ready := false
## Trees reveal as the player approaches, not only at chunk borders.
var _last_tree_draw_pos := Vector3.INF
var _height_noise := FastNoiseLite.new()
var _bump_noise := FastNoiseLite.new()
var _floor_noise := FastNoiseLite.new()
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
	_tree_spot_cache.clear()
	_spots_ready = false
	_height_noise.seed = 0x464F52455354
	_height_noise.frequency = 0.013
	_height_noise.fractal_octaves = 3
	_bump_noise.seed = 0x42554D50
	_bump_noise.frequency = 0.05
	_bump_noise.fractal_octaves = 1
	# Roots and leaf pockets. Only the flats get them, so a steep hill stays walkable.
	_floor_noise.seed = 0x464C4F4F52
	_floor_noise.frequency = 0.38
	_floor_noise.fractal_octaves = 2
	_scatter_noise.seed = 0x534341545445
	_scatter_noise.frequency = 0.11
	_corridor_noise.seed = 0x53454E424F4E
	_corridor_noise.frequency = 0.018
	_spots_ready = true
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
	_tree_spot_cache.clear()
	_last_tree_draw_pos = Vector3.INF
	center_chunk = Vector2i.ZERO
	chunk_count = 0
	active_chunk_keys.clear()
	if follow:
		_rebuild_active_chunks()


## Where the player actually walks. Locomotion moves the XR origin/body, not
## the rig root, so the root stays at the spawn while the player walks away;
## anchoring chunks on it strands the whole forest behind (desktop rigs move
## the root itself, so they just use it).
func _anchor_position() -> Vector3:
	if follow != null and follow.has_method("feet_position"):
		return follow.call("feet_position")
	return follow.global_position


func _physics_process(_delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		return
	var anchor := _anchor_position()
	var next := _world_to_chunk(anchor)
	if next != center_chunk:
		center_chunk = next
		_rebuild_active_chunks()
	# Trees reveal while walking inside a chunk; a full 9-chunk rescan is a few
	# hundred distance checks, so only redo it after a couple of metres.
	if _last_tree_draw_pos == Vector3.INF or anchor.distance_to(_last_tree_draw_pos) > 2.0:
		_last_tree_draw_pos = anchor
		_refresh_tree_draw(anchor)


func height_at(wx: float, wz: float) -> float:
	var hill := _hill_height(wx, wz)
	if not _spots_ready:
		return hill
	return hill + _root_mound(wx, wz)


## Exact height of the rendered terrain mesh at (wx, wz): the mesh samples
## height_at() on the global 0.7 m lattice and splits each quad the same way,
## so this reproduces the visible ground instead of the analytic ideal.
func _mesh_height(wx: float, wz: float) -> float:
	var step := CHUNK_SIZE / float(TERRAIN_RES - 1)
	var fx := wx / step
	var fz := wz / step
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := height_at(float(ix) * step, float(iz) * step)
	var h10 := height_at(float(ix + 1) * step, float(iz) * step)
	var h01 := height_at(float(ix) * step, float(iz + 1) * step)
	var h11 := height_at(float(ix + 1) * step, float(iz + 1) * step)
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 * (tx + tz - 1.0) + h10 * (1.0 - tz) + h01 * (1.0 - tx)


## Lowest rendered ground within [param radius] of (wx, wz): planting the
## trunk below it keeps every root ribbon buried on slopes, where the analytic
## height sits above the downhill mesh.
func _mesh_min_height(wx: float, wz: float, radius: float) -> float:
	var low := _mesh_height(wx, wz)
	for i in 8:
		var a := TAU * float(i) / 8.0
		low = minf(low, _mesh_height(wx + cos(a) * radius, wz + sin(a) * radius))
	return low


## Hills, pockets and the glade. No tree mounds: those are added on top so the
## trunk can be sunk into soil that belongs to the ground.
func _hill_height(wx: float, wz: float) -> float:
	var d := Vector2(wx, wz).length()
	if d < CLEARING_RADIUS - 1.2:
		return CLEARING_HEIGHT
	var blend := smoothstep(CLEARING_RADIUS - 1.5, CLEARING_RADIUS + 9.0, d)
	var n := _height_noise.get_noise_2d(wx, wz) * HILL_AMPLITUDE
	n += _bump_noise.get_noise_2d(wx, wz) * BUMP_AMPLITUDE
	# Grade of the broad hill over a couple of metres. Pockets sit on the
	# flats; a slope that is already near the walk limit does not get steeper.
	var flat := _hill_flatness(wx, wz)
	var pocket := _floor_noise.get_noise_2d(wx, wz)
	var root := 1.0 - absf(_floor_noise.get_noise_2d(wx * 0.41 + 18.0, wz * 0.41))
	n += (pocket * 0.15 + root * root * 0.10) * flat
	return lerpf(CLEARING_HEIGHT, CLEARING_HEIGHT + n, blend)


func _hill_flatness(wx: float, wz: float) -> float:
	var sx := _height_noise.get_noise_2d(wx + 1.2, wz) - _height_noise.get_noise_2d(wx - 1.2, wz)
	var sz := _height_noise.get_noise_2d(wx, wz + 1.2) - _height_noise.get_noise_2d(wx, wz - 1.2)
	var grade := clampf(Vector2(sx, sz).length() * HILL_AMPLITUDE / 2.4, 0.0, 1.0)
	return 1.0 - smoothstep(0.22, 0.48, grade)


## Soil heaped against the trunk. Same spots the trees use, so the mound and
## the mesh meet. Fades out in the level glade and on slopes that are already steep.
func _root_mound(wx: float, wz: float) -> float:
	var d := Vector2(wx, wz).length()
	if d < CLEARING_RADIUS - 1.2:
		return 0.0
	var fade := smoothstep(CLEARING_RADIUS - 1.2, CLEARING_RADIUS + 2.2, d)
	var slope := _local_hill_slope(wx, wz)
	# Chunks are centered on their origin, so a point just west of 0 still
	# belongs to chunk 0. Search the round neighbourhood, not floor() — but
	# only the 4 m buckets the 1.6 m mound radius can touch.
	var cx := int(round(wx / CHUNK_SIZE))
	var cz := int(round(wz / CHUNK_SIZE))
	var best := 0.0
	var lox := int(floor((wx - 1.7) / MOUND_CELL))
	var hix := int(floor((wx + 1.7) / MOUND_CELL))
	var loz := int(floor((wz - 1.7) / MOUND_CELL))
	var hiz := int(floor((wz + 1.7) / MOUND_CELL))
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			var packed: Dictionary = _tree_spots(Vector2i(cx + ox, cz + oz))
			var cells: Dictionary = packed.get("cells", {})
			for bx in range(lox, hix + 1):
				for bz in range(loz, hiz + 1):
					for s in cells.get(Vector2i(bx, bz), []):
						var spot: Vector4 = s
						var dist := Vector2(wx - spot.x, wz - spot.y).length()
						if dist > 1.6:
							continue
						var t := 1.0 - smoothstep(0.35, 1.55, dist)
						best = maxf(best, t * 0.2 * spot.z)
	# Rise over one metre. The walk test uses the same step; a heap on a
	# face that is already steep is what pushed it past 40°.
	var settle := 1.0 - smoothstep(0.1, 0.26, slope)
	return best * settle * fade


func _local_hill_slope(wx: float, wz: float) -> float:
	var dx := _hill_height(wx + 0.5, wz) - _hill_height(wx - 0.5, wz)
	var dz := _hill_height(wx, wz + 0.5) - _hill_height(wx, wz - 0.5)
	return Vector2(dx, dz).length()


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
	# The soil mounds query tree spots of the ±1 neighbourhood, so keep that
	# halo cached and drop everything further: roaming must not grow memory.
	for key in _tree_spot_cache.keys():
		var c: Vector2i = key
		if maxi(absi(c.x - center_chunk.x), absi(c.y - center_chunk.y)) > CHUNK_RADIUS + 1:
			_tree_spot_cache.erase(key)
	if follow:
		_last_tree_draw_pos = _anchor_position()
		_refresh_tree_draw(_anchor_position())


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
	_collect_senbon_corridor(root, coord)
	clearing_props += _populate_multimesh(root, "Trees", _tree_mesh, _tree_mat, MAX_TREES_PER_CHUNK, coord, 0)
	clearing_props += _populate_multimesh(root, "Torii", _torii_mesh, _torii_mat, MAX_TORII_PER_CHUNK, coord, 1)
	clearing_props += _populate_multimesh(root, "Lanterns", _lantern_mesh, _lantern_mat, MAX_LANTERNS_PER_CHUNK, coord, 2)
	clearing_props += _populate_multimesh(root, "Rocks", _rock_mesh, _rock_mat, MAX_ROCKS_PER_CHUNK, coord, 3)
	_place_moon_shafts(root, coord)
	root.set_meta("clearing_props", clearing_props)
	return root


func _populate_multimesh(root: Node3D, label: String, mesh: Mesh, mat: Material, max_count: int,
		coord: Vector2i, kind: int) -> int:
	if kind == 0:
		return _populate_trees(root, coord)
	var transforms: Array[Transform3D] = []
	var clearing_hits := 0
	# Deterministic per chunk and kind, so a recycled chunk grows back the same.
	# (The old per-index LCG hash was correlated and lined trees up in rows.)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([coord.x, coord.y, kind, 0x464F52])
	# Torii existence is a separate hash (not the rng stream), so grouping
	# gates never moves trees or other props.
	var torii_exists := kind != 1 or _hash01(_hash_coord(coord, 1, 77), 0) < TORII_CHUNK_CHANCE
	# Keep-out: trees first, then everything already placed — gates never grow
	# through a trunk, lanterns and boulders keep their distance too. Neighbour
	# chunks' spots are already cached (their meshes queried mounds), so gates
	# near a border respect them too. Gates in one group stay close (they form
	# corridors), so torii check trees wide but each other narrow.
	var tree_keep: Array = []
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			var packed: Dictionary = _tree_spots(coord) if ox == 0 and oz == 0 \
				else _tree_spot_cache.get(coord + Vector2i(ox, oz), {})
			for s in packed.get("spots", []):
				var spot: Vector4 = s
				tree_keep.append(Vector3(spot.x, spot.y, 0.0))
	var placed: Array = []
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
			# Only chosen chunks hold gates; inside one, most candidates
			# stay, so gates come in small groups for the same draw calls.
			if not torii_exists:
				continue
			if rng.randf() > TORII_GROUP_KEEP:
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
		var tree_clear := 2.5 if kind == 1 else (1.0 if kind == 2 else 1.0 + scale * 0.5)
		if _spot_blocked(tree_keep, wx, wz, tree_clear):
			continue
		var prop_clear := 1.5 if kind == 1 else (1.0 if kind == 2 else 1.0 + scale * 0.5)
		if _spot_blocked(placed, wx, wz, prop_clear):
			continue
		placed.append(Vector3(wx, wz, prop_clear * 0.5))
		if kind == 1:
			# Gates stand upright: drop the whole frame below the lowest
			# ground under its span so no leg floats downhill.
			hy = _mesh_min_height(wx, wz, 2.0) - 0.05
		elif kind == 3:
			# Boulders sit half-buried instead of balancing on the slope.
			hy -= 0.15 * scale
		var angle := rng.randf() * TAU
		var basis := Basis.from_euler(Vector3(0.0, angle, 0.0)) * Basis.from_scale(Vector3.ONE * scale)
		var xf := Transform3D(basis, Vector3(lx, hy, lz))
		transforms.append(xf)
		var props: Array = root.get_meta("prop_world_positions", [])
		props.append(Vector3(wx, hy, wz))
		root.set_meta("prop_world_positions", props)
		if kind == 1:
			var gates: Array = root.get_meta("torii_world_positions", [])
			gates.append(Vector3(wx, hy, wz))
			root.set_meta("torii_world_positions", gates)
	if kind == 1:
		# Senbon corridors ride the same MultiMesh (one draw call): a node per
		# corridor cost a draw each against the Quest cap.
		transforms.append_array(root.get_meta("senbon_pending", []))
		root.set_meta("senbon_pending", [])
	if kind == 0:
		root.set_meta("tree_local_xfs", transforms)
	if not transforms.is_empty():
		_commit_multimesh(root, label, mesh, mat, transforms)
		if kind == 0 or kind == 1:
			root.add_child(_build_trunk_colliders(transforms, kind, root))
	return clearing_hits


## Same jitter and density as the old tree scatter, cached so the soil mound
## and the mesh share one set of trunks.
func _tree_spots(coord: Vector2i) -> Dictionary:
	if _tree_spot_cache.has(coord):
		return _tree_spot_cache[coord]
	var spots: Array[Vector4] = []
	var clearing := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([coord.x, coord.y, 0, 0x464F52])
	var origin := Vector2(float(coord.x) * CHUNK_SIZE, float(coord.y) * CHUNK_SIZE)
	# Crown spacing: no two trunks closer than TREE_MIN_DIST, including across
	# the chunk border (already-built neighbours are in the cache; a neighbour
	# built later avoids us the same way).
	var halo: Array[Vector2] = []
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			if ox == 0 and oz == 0:
				continue
			var packed: Dictionary = _tree_spot_cache.get(Vector2i(coord.x + ox, coord.y + oz), {})
			for s in packed.get("spots", []):
				var spot: Vector4 = s
				halo.append(Vector2(spot.x, spot.y))
	for p in _scatter_points(rng, 0, MAX_TREES_PER_CHUNK):
		var wx := origin.x + p.x
		var wz := origin.y + p.y
		if _in_clearing(wx, wz):
			clearing += 1
			continue
		var density := _scatter_noise.get_noise_2d(wx * 0.09, wz * 0.09) * 0.5 + 0.5
		if rng.randf() > lerpf(0.5, 0.97, density):
			continue
		if _too_close_to_trees(spots, halo, wx, wz):
			continue
		spots.append(Vector4(wx, wz, rng.randf_range(0.85, 1.4), rng.randf() * TAU))
	# 4 m buckets so mound queries check a handful of trunks instead of the
	# whole ±1-chunk neighbourhood on every height sample.
	var cells := {}
	for s in spots:
		var spot: Vector4 = s
		var key := Vector2i(int(floor(spot.x / MOUND_CELL)), int(floor(spot.y / MOUND_CELL)))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(spot)
	var packed := {"spots": spots, "clearing": clearing, "cells": cells}
	_tree_spot_cache[coord] = packed
	return packed


## Minimum trunk-to-trunk distance, inside the chunk and against the halo.
const TREE_MIN_DIST := 2.4
## Tree-spot bucket size for mound queries (the 1.6 m mound radius fits).
const MOUND_CELL := 4.0

func _too_close_to_trees(spots: Array[Vector4], halo: Array[Vector2], wx: float, wz: float) -> bool:
	for s in spots:
		var spot: Vector4 = s
		if Vector2(wx - spot.x, wz - spot.y).length() < TREE_MIN_DIST:
			return true
	for h in halo:
		if Vector2(wx - h.x, wz - h.y).length() < TREE_MIN_DIST:
			return true
	return false


## True when (wx, wz) intrudes on an occupied spot. Entries are Vector3
## (x, z, radius); clearance adds on top.
func _spot_blocked(occupied: Array, wx: float, wz: float, clearance: float) -> bool:
	for o in occupied:
		var e: Vector3 = o
		if Vector2(wx - e.x, wz - e.y).length() < clearance + e.z:
			return true
	return false


func _populate_trees(root: Node3D, coord: Vector2i) -> int:
	var packed := _tree_spots(coord)
	var transforms: Array[Transform3D] = []
	var props: Array = root.get_meta("prop_world_positions", [])
	for s in packed.spots:
		var spot: Vector4 = s
		var wx := spot.x
		var wz := spot.y
		var scale := spot.z
		var yaw := spot.w
		# Plant from the rendered mesh, sunk below the lowest ground in ribbon
		# reach: on a slope the analytic height floats above the downhill
		# mesh, which left roots standing in the air.
		var base := _mesh_min_height(wx, wz, 3.3) - 0.05 * scale
		# Lean with the hill, not the mound, so the roots lie on the slope
		# instead of sticking out on the downhill side.
		var up := Vector3.UP.lerp(_hill_normal(wx, wz), 0.72).normalized()
		var basis := _basis_up(up, yaw, scale)
		transforms.append(Transform3D(basis, Vector3(wx - root.position.x, base, wz - root.position.z)))
		props.append(Vector3(wx, base, wz))
	root.set_meta("prop_world_positions", props)
	root.set_meta("tree_local_xfs", transforms)
	if not transforms.is_empty():
		_commit_multimesh(root, "Trees", _tree_mesh, _tree_mat, transforms)
		root.add_child(_build_trunk_colliders(transforms, 0, root))
	return int(packed.clearing)


func _hill_normal(wx: float, wz: float) -> Vector3:
	var e := 0.9
	var dx := _hill_height(wx - e, wz) - _hill_height(wx + e, wz)
	var dz := _hill_height(wx, wz - e) - _hill_height(wx, wz + e)
	return Vector3(dx, e * 2.0, dz).normalized()


func _basis_up(up: Vector3, yaw: float, scale: float) -> Basis:
	var y := up.normalized()
	var x := y.cross(Vector3(0.0, 0.0, 1.0))
	if x.length_squared() < 1e-4:
		x = y.cross(Vector3(1.0, 0.0, 0.0))
	x = x.normalized()
	var z := x.cross(y).normalized()
	var b := Basis(x, y, z).rotated(y, yaw)
	return b.scaled(Vector3.ONE * scale)


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
			# Chest-height bark is about 0.45 m across at scale 1. The visual
			# trunk leans with the hill, so the collider leans with it —
			# a vertical tube let the player walk through the visible bark.
			var trunk_r := 0.42 * s
			var lean := xf.basis.orthonormalized()
			var up := (lean * Vector3.UP).normalized()
			_add_cylinder(body, Transform3D(lean, xf.origin + up * (1.8 * s)), trunk_r, 3.6 * s)
			registered.append(_remember_trunk(root.position + xf.origin, trunk_r))
		else:
			# Two pillars, each ~0.34 of the gate width off its center.
			var h := _torii_mesh.get_aabb().size.y * s if _torii_mesh else 4.5
			var half_span := _torii_mesh.get_aabb().size.x * s * 0.34 if _torii_mesh else 1.5
			var side := xf.basis.x.normalized()
			for sgn_v in [-1.0, 1.0]:
				var sgn := float(sgn_v)
				var pillar := xf.origin + side * half_span * sgn
				_add_cylinder(body, Transform3D(Basis.IDENTITY, pillar + Vector3(0.0, h * 0.35, 0.0)), h * 0.045, h * 0.7)
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


static func _add_cylinder(body: StaticBody3D, xf: Transform3D, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	cs.transform = xf
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
		_refresh_tree_draw(_anchor_position())
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
		var idx := 0
		for xf in all:
			var placed := xf as Transform3D
			var dx := base.x + placed.origin.x - origin.x
			var dz := base.z + placed.origin.z - origin.z
			var d2 := dx * dx + dz * dz
			if d2 > r2:
				idx += 1
				continue
			if d2 > TREE_FAR_START * TREE_FAR_START and _hash01(idx, 7) >= TREE_FAR_KEEP:
				idx += 1
				continue
			near.append(placed)
			idx += 1
		# instance_count is what the headless perf probe counts. A visibility
		# cap on top of the full buffer still submitted every tree.
		mm.instance_count = near.size()
		for i in near.size():
			mm.set_instance_transform(i, near[i])


func _collect_senbon_corridor(root: Node3D, coord: Vector2i) -> void:
	var corridor_val := _corridor_noise.get_noise_2d(float(coord.x) * 1.7, float(coord.y) * 1.7)
	if corridor_val < 0.64:
		return
	var axis_x := corridor_val > 0.72

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
		# Corridor gates keep the same trunk clearance as scattered ones.
		var blocked := false
		for ox in range(-1, 2):
			for oz in range(-1, 2):
				var packed: Dictionary = _tree_spots(coord) if ox == 0 and oz == 0 \
					else _tree_spot_cache.get(coord + Vector2i(ox, oz), {})
				for ts in packed.get("spots", []):
					var tspot: Vector4 = ts
					if Vector2(wx - tspot.x, wz - tspot.y).length() < 2.5:
						blocked = true
						break
				if blocked:
					break
			if blocked:
				break
		if blocked:
			continue
		var hy := _mesh_min_height(wx, wz, 2.0) - 0.05
		var s := torii_scale_for_height(4.4 + float(g) * 0.12)
		var basis := Basis.from_euler(Vector3(0.0, PI * 0.5 if axis_x else 0.0, 0.0)) * Basis.from_scale(Vector3.ONE * s)
		transforms.append(Transform3D(basis, Vector3(lx, hy, lz)))
		var props: Array = root.get_meta("prop_world_positions", [])
		props.append(Vector3(wx, hy, wz))
		root.set_meta("prop_world_positions", props)
		var gates: Array = root.get_meta("torii_world_positions", [])
		gates.append(Vector3(wx, hy, wz))
		root.set_meta("torii_world_positions", gates)
	# Committed with the chunk's Torii MultiMesh (pillars included, so the
	# corridor also steers yōkai and stops the player like other gates).
	root.set_meta("senbon_pending", transforms)


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
	# Shared vertices, then one normal per point, so a root reads as a mound
	# instead of a faceted plate.
	st.index()
	st.generate_normals()
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
			if child is MultiMeshInstance3D and String(child.name) == "Torii":
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
	_ground_mat.set_shader_parameter("ambient_fill", 0.08)
	_ground_mat.set_shader_parameter("normal_strength", 1.2)
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
	else:
		_tree_mesh = _rebuild_crown(_tree_mesh)
	_tree_mesh = _append_root_flare(_tree_mesh)
	_torii_mesh = _build_torii_mesh()
	_lantern_mesh = _build_lantern_mesh()
	_rock_mesh = _extract_rock_mesh()


## The scanned crown was decimated leaf cards cut out of a blob atlas: after
## the decimation the UV islands no longer matched the triangles, so seen from
## below the canopy was a cloud of ragged, see-through shards. Keep the bark
## (trunk and boughs, the atlas's bottom-left strip) and grow the crown again
## as solid foliage clumps where the scan's leaf mass was (weighted k-means of
## the scanned crown: centre, radius). ~1k triangles instead of ~5.3k.
const CROWN_CLUMPS := [
	[Vector3(0.08, 10.14, -3.36), 2.2], [Vector3(4.03, 9.42, -0.61), 2.1],
	[Vector3(-0.14, 11.66, 0.19), 2.3], [Vector3(5.80, 10.63, -2.85), 2.0],
	[Vector3(-6.12, 10.48, 2.53), 1.9], [Vector3(1.21, 9.88, 3.24), 2.1],
	[Vector3(3.41, 11.44, 4.86), 2.0], [Vector3(-1.83, 11.55, -5.30), 1.9],
	[Vector3(-4.06, 9.37, 0.38), 2.1],
]


func _rebuild_crown(scan: Mesh) -> ArrayMesh:
	var arrays := scan.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	for t in range(0, idx.size() - 2, 3):
		var uv_c := (uvs[idx[t]] + uvs[idx[t + 1]] + uvs[idx[t + 2]]) / 3.0
		var p_c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
		# Boughs map to the atlas's bottom-left strips; the trunk itself to a
		# small bark square, so it is kept by position (on the axis, below
		# the crown) instead.
		# Above the clumps' underside the boughs only poke out as shards.
		var bough := uv_c.x < 0.34 and uv_c.y > 0.66 and p_c.y < 8.8
		var trunk := Vector2(p_c.x, p_c.z).length() < 0.9 and p_c.y < 9.0
		if not bough and not trunk:
			continue  # leaf card
		for k in 3:
			st.set_normal(normals[idx[t + k]])
			st.set_uv(uvs[idx[t + k]])
			st.add_vertex(verts[idx[t + k]])
	var noise := FastNoiseLite.new()
	noise.seed = 0x4C454146
	noise.frequency = 0.9
	for c in CROWN_CLUMPS.size():
		_add_foliage_clump(st, CROWN_CLUMPS[c][0], float(CROWN_CLUMPS[c][1]), noise, c)
	# The bark is normal-mapped: without tangents its lighting turns to NaN
	# and the trunks vanish.
	st.generate_tangents()
	return st.commit()


## A lumpy, slightly flattened foliage mass with smooth normals. UV.y = 2
## marks it for the foliage branch of the tree shader; UV.x carries a
## per-vertex random shade.
func _add_foliage_clump(st: SurfaceTool, center: Vector3, radius: float, noise: FastNoiseLite, seed_i: int) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 11
	sphere.rings = 6
	var a := sphere.get_mesh_arrays()
	var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var si: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var cst := SurfaceTool.new()
	cst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var offset := Vector3(seed_i * 7.3, seed_i * 3.1, seed_i * 5.7)
	for i in sv.size():
		var d := sv[i]
		var bump := 1.0 + noise.get_noise_3dv(d * 1.6 + offset) * 0.38
		# Flatter underside: a canopy mass hangs, it is not a ball.
		var y := d.y * (0.62 if d.y < 0.0 else 0.8)
		var p := Vector3(d.x, y, d.z) * radius * bump
		cst.set_uv(Vector2(float(absi(hash(i * 31 + seed_i * 977)) % 1000) / 999.0, 2.0))
		cst.add_vertex(center + p)
	for i in si:
		cst.add_index(i)
	cst.generate_normals()
	# Smooth normals are computed on the shared vertices; then flatten the
	# index: appending an indexed surface to the non-indexed bark switches
	# the tool to indices and silently drops every bark triangle.
	cst.deindex()
	st.append_from(cst.commit(), 0, Transform3D.IDENTITY)


## Roots and a flare welded onto the trunk mesh (same draw call). UV.x > 1
## marks them for the root branch of the tree shader. They overlap the bark
## and run out onto the soil mound so the trunk does not end in a cut circle.
func _append_root_flare(mesh: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(mesh, 0, Transform3D.IDENTITY)
	var angles: Array[float] = [0.15, 1.05, 2.15, 3.25, 4.35, 5.35]
	var lengths: Array[float] = [2.15, 1.7, 2.45, 1.55, 2.3, 1.9]
	for i in angles.size():
		_add_root_ribbon(st, angles[i], lengths[i])
	_add_root_collar(st)
	return st.commit()


func _add_root_ribbon(st: SurfaceTool, angle: float, length: float) -> void:
	var dir := Vector3(cos(angle), 0.0, sin(angle))
	var side := Vector3(-dir.z, 0.0, dir.x)
	# Inner edge overlaps the trunk; the tip lies on the mound.
	var radii: Array[float] = [0.85, 0.85 + length * 0.45, 0.85 + length]
	# Sit on the soil apron, so the ridge reads above the heap.
	var heights: Array[float] = [0.58, 0.3, 0.07]
	var half_w: Array[float] = [0.34, 0.2, 0.07]
	var along: Array[float] = [0.0, 0.45, 1.0]
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for k in 3:
		var c := dir * radii[k] + Vector3(0.0, heights[k], 0.0)
		left.append(c - side * half_w[k])
		right.append(c + side * half_w[k])
	for k in 2:
		_add_root_quad(st, left[k], right[k], right[k + 1], left[k + 1], along[k], along[k + 1])


func _add_root_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, along0: float, along1: float) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.y < 0.0:
		n = -n
	_root_vert(st, a, n, along0)
	_root_vert(st, b, n, along0)
	_root_vert(st, c, n, along1)
	_root_vert(st, a, n, along0)
	_root_vert(st, c, n, along1)
	_root_vert(st, d, n, along1)


func _root_vert(st: SurfaceTool, p: Vector3, n: Vector3, along: float) -> void:
	st.set_normal(n)
	st.set_uv(Vector2(2.0 + along, 0.5))
	st.add_vertex(p)


## A low, lopsided heap of soil welded to the trunk. The inner ring climbs the
## bark so the mesh's flat bottom never meets the ground as a cut circle.
func _add_root_collar(st: SurfaceTool) -> void:
	var segs := 12
	var radii: Array[float] = [0.7, 1.35, 2.45]
	var heights: Array[float] = [0.5, 0.24, 0.03]
	var along: Array[float] = [0.0, 0.4, 0.92]
	var ring: Array = []
	for i in segs:
		var row: Array[Vector3] = []
		var ang := TAU * float(i) / float(segs)
		var wobble := 0.78 + 0.44 * _apron_n(i)
		for r in 3:
			var spread := 0.0 if r == 0 else lerpf(0.35, 1.0, float(r) / 2.0)
			var rad := radii[r] * lerpf(1.0, wobble, spread)
			var y := heights[r] * (0.82 + 0.36 * _apron_n(i + r * 5 + 2))
			row.append(Vector3(cos(ang) * rad, y, sin(ang) * rad))
		ring.append(row)
	for i in segs:
		var a: Array[Vector3] = ring[i]
		var b: Array[Vector3] = ring[(i + 1) % segs]
		for r in 2:
			_add_root_quad(st, a[r], b[r], b[r + 1], a[r + 1], along[r], along[r + 1])


func _apron_n(i: int) -> float:
	return float(absi(hash(i * 17 + 3)) % 1000) / 999.0


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
	# Chunk roots sit on coord * CHUNK_SIZE (terrain spans ±half around them),
	# so the mapping rounds; floor() lagged a rebuild by half a chunk.
	return Vector2i(int(round(pos.x / CHUNK_SIZE)), int(round(pos.z / CHUNK_SIZE)))


static func _hash_coord(coord: Vector2i, kind: int, index: int) -> int:
	return int(coord.x * 73856093 ^ coord.y * 19349663 ^ kind * 83492791 ^ index * 50331653) & 0x7fffffff


static func _hash01(seed: int, channel: int) -> float:
	return float((seed * 1103515245 + channel * 12345 + 12345) & 0x7fffffff) / float(0x7fffffff)
