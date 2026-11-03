@tool
class_name ForestWorld
extends Node3D
## Endless forest illusion around the run shrine (docs/NIGHT_PLAN.md §3, GDD §9).
## Rolling hills from FastNoiseLite, props via shared MultiMeshes (trees, torii,
## lanterns, boulders). Chunks recycle with the player, who can walk out of the
## shrine clearing into the forest: every chunk carries a terrain collider, and
## view ranges / ground fade are measured from the camera so fog swallows the
## chunk edges wherever the player stands.
##
## Every generation number lives in the WorldGenProfile (src/forest/,
## docs/WORLDGEN_TOOL.md). What stays here is geometry: crown clumps, root
## ribbons, gate frames. The same profile and seed give the same forest.

## Shader layer -> Poly Haven texture set in assets/textures/forest_ground/.
const GROUND_LAYERS := {"soil": "forrest_ground_01", "grass": "leafy_grass", "stone": "rocky_trail"}
const SHAFT_SHADER := preload("res://src/shaders/moon_shaft.gdshader")
const GROUND_SHADER := preload("res://src/shaders/forest_ground.gdshader")
const MOSS_ALBEDO := preload("res://assets/textures/forest_ground/moss002/moss002_diff_1k.jpg")
const MOSS_NORMAL := preload("res://assets/textures/forest_ground/moss002/moss002_nor_gl_1k.jpg")
const WET_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const TREE_DIFFUSE := preload("res://src/shaders/forest_diffuse.gdshader")
const TREE_ALBEDO := preload("res://assets/models/environment/forest_trees/cherry_forest_albedo.jpg")
const TREE_NORMAL := preload("res://assets/models/environment/forest_trees/cherry_forest_normal.jpg")
const SAKURA_TREE_SHADER := preload("res://src/shaders/sakura_tree.gdshader")
const TORII_MESH_SCALE := 0.42
## Metres of path distance the vertex colour's G channel spans (see _path_colour).
const PATH_ENCODE_RANGE := 4.0
## Most centre-line segments a chunk hands to the ground shader (forest_ground.gdshader path_segs).
const PATH_SEGMENTS_MAX := 48
const PATH_SIMPLIFY_TOL := 0.12
## Metres around a shrine that stay free of the middle and back kinds (N5): the offering cards need room.
const SHRINE_RESERVE := 6.0
## Width of the distance fade at a kind's draw edge, metres (see _draw_fade).
## Share of the distance haze the back layer takes (see _back_material).
const BACK_HAZE_SHARE := 0.35
const DRAW_FADE_BAND := 7.0
## Foliage clumps are drawn this many times their listed radius, so neighbours merge into one canopy.
const CROWN_OVERSIZE := 1.18
## Metres of crown the open-sky rule keeps beyond the drawn reach (path-field lattice error and clump tips).
const CROWN_SKY_MARGIN := 0.3
## Slack added to every crown disc (metres): covers the far crown, which has fewer segments.
const CROWN_DISC_MARGIN := 0.1
## Lowest height a scanned crown counts for the sky rule: below it is trunk and root flare.
const SCENE_CROWN_FLOOR := 2.5
## Clearance of a layout-after tree from base trunks and from gates (metres).
const EXTRA_BASE_CLEAR := 4.5
## Share of the two crown reaches two trunks may overlap by before they are too close (N5): the
## canopy test's severe-overlap line (d < 0.75 × (r1 + r2)).
const CROWN_OVERLAP_SHARE := 0.75
const EXTRA_GATE_CLEAR := 5.0
## Trunks and gate pillars collide on their own layer: the player walks into
## them, yōkai ragdolls do not (their limbs snag and topple them); yōkai steer
## around them instead (trunk_push).
const TRUNK_LAYER := 64
const TRUNK_CELL := 3.0
## Gate candidates keep this far from a live gameplay gate (ToriiManager).
const GATE_CLEAR_OF_LIVE_GATE := 3.5
## A shrine is joined to a path that passes this close, metres.
const SHRINE_SPUR_REACH := 40.0
## How far a shrine spur strip floats above the rendered ground (metres).
const SPUR_LIFT := 0.03
## Largest cell of a shrine spur strip (metres), finer than the terrain lattice.
const SPUR_CELL := 0.5
## Senbon rows: axis threshold and the spacing from the corridor noise.
const SENBON_AXIS_THRESHOLD := 0.72
const CORRIDOR_SCALE := 1.7
## Candidate sites per wanted prop: the rest are rejected by trees and props.
const SITE_OVERSAMPLE := 3
## Kinds seed the per-chunk streams: gates 1, lanterns 2, undergrowth
## 3 + its index in the profile (trees use PoissonDisk, see _potential_trunks).
const KIND_TORII := 1
## The passage of a decorative gate, in its own frame: half width (across the path, past the posts) and
## half depth (along the path). Trunks, lanterns and boulders keep out of it plus TORII_OPENING_PAD.
const TORII_OPENING_HALF := Vector2(1.35, 1.0)
const TORII_OPENING_PAD := 0.6
## Decorative gates within this distance of a footpath are set on its centre line (see _torii_path_pose).
const TORII_PATH_SNAP := 3.5
const KIND_LANTERN := 2
const KIND_UNDERGROWTH := 3
## Lantern parts (size, centre) shared by the mesh and its collider.
## A low stone tōrō: base, shaft, ledge, light box, roof and finial (about 1 m).
const LANTERN_PARTS := [
	[Vector3(0.46, 0.12, 0.46), Vector3(0.0, 0.06, 0.0)],
	[Vector3(0.14, 0.40, 0.14), Vector3(0.0, 0.32, 0.0)],
	[Vector3(0.36, 0.06, 0.36), Vector3(0.0, 0.55, 0.0)],
	[Vector3(0.28, 0.26, 0.28), Vector3(0.0, 0.71, 0.0)],
	[Vector3(0.44, 0.07, 0.44), Vector3(0.0, 0.875, 0.0)],
	[Vector3(0.12, 0.10, 0.12), Vector3(0.0, 0.96, 0.0)],
]
## Lanterns keep this far from a gate of their chunk (metres, from its centre).
const LANTERN_CLEAR_OF_TORII := 3.5
## Height slices for a scanned lantern's collider (one convex hull each).
const LANTERN_SLICES := 10
## Trunk hull top (mesh space): above the reach of a raised blade. The
## trunk is hulled in slices this tall (overlapping a little), so the
## hull follows the taper and flare instead of bridging them.
const TRUNK_HULL_TOP := 4.4
const TRUNK_SLICE := 1.1
## Tree-spot bucket size for mound queries (the 1.6 m mound radius fits).
const MOUND_CELL := 4.0
## Blend of the hills into the glade, relative to clearing_radius.
const HILL_BLEND_START := 1.5
## Soil heaped against the trunk, relative to clearing_radius.
const MOUND_FADE_START := 1.2
const MOUND_FADE_END := 2.2

var profile: WorldGenProfile
var follow: Node3D
## Unit vector toward the moon (RunGame sets it from the Moon light).
var moon_direction := Vector3(0.25, 0.9, 0.35).normalized()
var chunk_count := 0
var active_chunk_keys: Array[Vector2i] = []
var center_chunk := Vector2i.ZERO

var _chunks: Dictionary = {}
## Vector2i cell -> Array of Vector3(x, z, radius) for trunk_push().
var _trunk_cells: Dictionary = {}
## Chunk coord -> {spots, ids, clearing, cells}. Spots are world xz, scale, yaw
## (Vector4); ids are the profile tree-entry index of each spot.
var _extra_spot_cache: Dictionary = {}
## Back-layer transforms per chunk: entry index -> Array[Transform3D] (N5, see _back_spots).
var _back_spot_cache: Dictionary = {}
var _back_mats: Array[Material] = []
## Silhouette of the back layer (N5): ~40 triangles, shared by every back kind's instances.
var _back_meshes: Dictionary = {}
## Ground positions (x, z) of shrines: the middle and back kinds keep SHRINE_RESERVE metres from them.
var _shrine_reserves: Array[Vector2] = []
var _back_tree_nodes: Dictionary = {}
var _tree_spot_cache: Dictionary = {}
## Decorative gates per chunk (see _torii_plan).
var _torii_plan_cache: Dictionary = {}
## Chunk coord -> {points: Array[Vector4] (x, z, entry, spacing), clearing: int}.
var _potential_cache: Dictionary = {}
## Chunk coord -> PackedFloat32Array: distance to the nearest path at every terrain vertex.
var _path_field_cache: Dictionary = {}
## The footpath network (null when the profile turns paths off).
var paths: ForestPaths = null
var _spots_ready := false
## Height of the terrain lattice at integer (ix, iz), world = index × step. Shared by
## the terrain mesh, the tree planting and the mound queries; cleared when the spots change.
var _lattice_heights: Dictionary = {}
## Chunks of the ring that wait for their turn to be built (one per physics frame).
var _pending_chunks: Array[Vector2i] = []
var _wanted_chunks: Dictionary = {}
## The chunk whose terrain is being sampled a few rows per frame (walking only).
var _building: TerrainBuild = null
var _building_key := Vector2i.ZERO
## Poisson samples started on worker threads: Vector3i(chunk x, z, entry) -> [task id, out].
var _poisson_jobs: Dictionary = {}
## Trees reveal as the player approaches, not only at chunk borders.
var _last_tree_draw_pos := Vector3.INF
## Physics frames a chunk that arrives while walking takes to grow its trees to full size.
const TREE_GROW_FRAMES := 30
var _height_noise := FastNoiseLite.new()
var _bump_noise := FastNoiseLite.new()
var _floor_noise := FastNoiseLite.new()
var _scatter_noise := FastNoiseLite.new()
var _corridor_noise := FastNoiseLite.new()
## Per profile tree entry: crown discs (Vector4: centre xyz in trunk space, reach), read by the sky rule.
var _crown_discs: Array = []
## Largest crown disc radius of any kind at its biggest scale (metres): sizes the path field.
var _crown_reach := 0.0
## Per profile tree entry: mesh, material, trunk hulls and chest radius.
var _tree_meshes: Array[Mesh] = []
var _tree_mats: Array[Material] = []
## Far crowns (see _build_far_tree_mesh) and their material, per profile tree entry.
var _tree_far_meshes: Array[Mesh] = []
var _tree_far_mats: Array[Material] = []
## One MultiMesh per ordinary entry for every far crown in the ring (one draw call for the forest, not one per chunk).
var _far_tree_nodes: Dictionary = {}
var _scene_tree_nodes: Dictionary = {}
## World origins of the crowns the last refresh drew (what the camera sees; tests read them).
var drawn_full_origins := PackedVector3Array()
var drawn_far_origins := PackedVector3Array()
## Scene crowns (D5 redwood) drawn to tree_draw_radius: no LOD band, so kept apart from the cedar's full crowns.
var drawn_scene_origins := PackedVector3Array()
## Growth (0 just planted .. 1 full size) of each drawn crown, parallel to the origins above.
var drawn_full_growth := PackedFloat32Array()
var drawn_far_growth := PackedFloat32Array()
var drawn_scene_growth := PackedFloat32Array()
var _tree_shapes: Array = []
var _tree_chest: Array[float] = []
## Per profile undergrowth entry: mesh, material and collider shape.
var _under_meshes: Array[Mesh] = []
var _under_mats: Array[Material] = []
var _under_shapes: Array[ConvexPolygonShape3D] = []
var _shaft_mesh: QuadMesh
var _shaft_mat: ShaderMaterial
var _torii_mesh: Mesh
var _lantern_mesh: Mesh
var _lantern_hulls: Array[ConvexPolygonShape3D] = []
## Collision shapes measured from the meshes above (see _build_prop_shapes):
## convex hulls of the visible surface, shared by every instance and placed
## with the instance's own transform, so bodies and the blade stop where the
## object visibly ends.
var _torii_shapes: Array[ConvexPolygonShape3D] = []
var _ground_mat: ShaderMaterial
var _torii_mat: ShaderMaterial
var _lantern_mat: ShaderMaterial
var _rock_material_cache: ShaderMaterial = null
## Profile numbers the height and clearance queries read on every call (a
## gate search asks for hundreds of heights). Copied once per profile in _apply_profile.
var _chunk_size := 28.0
var _clearing_radius := 5.2
var _prop_clearing := 3.4
var _hill_amplitude := 4.6
var _hill_blend := 9.0
var _bump_amplitude := 0.18
var _pocket_amount := 0.15
var _root_amount := 0.10
var _terrain_res := 41
var _lightmap_gi: LightmapGI
## Bark radius at chest height of the first tree kind (what a blade or body
## stops short of). Read by the tests and the blink checks.
var _trunk_chest_radius := 0.8
var _static_gi := false
var torii_manager: ToriiManager = null


func uses_static_gi() -> bool:
	return _static_gi


## Procedural chunks recycle — no stable UV2 for LightmapGI. We fake contact
## shadowing in forest shaders instead (NIGHT_PLAN §8).
func uses_shader_baked_look() -> bool:
	return true


func setup(p_follow: Node3D, arena_lightmap: LightmapGI = null) -> void:
	add_to_group("forest_world")
	follow = p_follow
	if profile == null:
		profile = WorldGenProfile.load_active()
	_lightmap_gi = arena_lightmap
	_static_gi = _lightmap_gi != null
	_apply_profile()
	if torii_manager == null:
		torii_manager = ToriiManager.new()
		torii_manager.name = "ToriiManager"
		add_child(torii_manager)
	# The ring first, then the gates: gate and shrine checks read the chunks, so
	# they must see the same world whether this is the first run or a reset.
	_rebuild_active_chunks()
	torii_manager.setup(self, follow, get_parent() as RunGame)


## Swaps the profile in place (the dock and the preview use this): meshes,
## materials and noise are rebuilt and every chunk is generated again.
func apply_profile(p_profile: WorldGenProfile) -> void:
	profile = p_profile
	_apply_profile()
	reset()


## A new run. [param anchor] (the spawn) centres the ring before it is built:
## the player may still stand far away from the spawn, and the opening shrine is
## checked against the ring around the spawn right after this call.
func reset(anchor: Vector3 = Vector3.INF, facing: Vector3 = Vector3.ZERO) -> void:
	# Freed now, not at the end of the frame: a queued chunk keeps its trunk
	# colliders in the physics space while the new ring is built, and gate and
	# shrine checks would see trunks that are gone.
	for key in _chunks.keys():
		var old := _chunks[key] as Node3D
		remove_child(old)
		old.free()
	_chunks.clear()
	_pending_chunks.clear()
	_building = null
	for key in _poisson_jobs.keys():
		WorkerThreadPool.wait_for_task_completion(_poisson_jobs[key][0])
	_poisson_jobs.clear()
	_trunk_cells.clear()
	_tree_spot_cache.clear()
	_torii_plan_cache.clear()
	_extra_spot_cache.clear()
	_back_spot_cache.clear()
	_potential_cache.clear()
	_path_field_cache.clear()
	_lattice_heights.clear()
	_last_tree_draw_pos = Vector3.INF
	center_chunk = _world_to_chunk(anchor) if anchor != Vector3.INF else Vector2i.ZERO
	chunk_count = 0
	active_chunk_keys.clear()
	# The same order as setup(): gates are cleared, the ring is rebuilt without
	# them, then the gates are placed on the new ring.
	if torii_manager:
		torii_manager.clear_gates()
	if follow:
		_rebuild_active_chunks()
	if torii_manager:
		torii_manager.ensure_gates_ahead(anchor, facing)


## Noise, materials and meshes come from the profile. Called whenever it changes.
func _apply_profile() -> void:
	_chunk_size = profile.chunk_size
	_clearing_radius = profile.clearing_radius
	_prop_clearing = profile.prop_clearing_radius
	_hill_amplitude = profile.hill_amplitude
	_hill_blend = profile.hill_blend_distance
	_bump_amplitude = profile.bump_amplitude
	_pocket_amount = profile.pocket_amount
	_root_amount = profile.root_amount
	_terrain_res = profile.terrain_resolution
	var seed_mix := profile.world_seed
	_tree_spot_cache.clear()
	_torii_plan_cache.clear()
	_extra_spot_cache.clear()
	_back_spot_cache.clear()
	_potential_cache.clear()
	_path_field_cache.clear()
	_lattice_heights.clear()
	_spots_ready = false
	_height_noise.seed = 0x464F52455354 ^ seed_mix
	_height_noise.frequency = profile.hill_frequency
	_height_noise.fractal_octaves = profile.hill_octaves
	_bump_noise.seed = 0x42554D50 ^ seed_mix
	_bump_noise.frequency = profile.bump_frequency
	_bump_noise.fractal_octaves = 1
	# Roots and leaf pockets. Only the flats get them, so a steep hill stays walkable.
	_floor_noise.seed = 0x464C4F4F52 ^ seed_mix
	_floor_noise.frequency = profile.floor_frequency
	_floor_noise.fractal_octaves = 2
	_scatter_noise.seed = 0x534341545445 ^ seed_mix
	_scatter_noise.frequency = 0.11
	_corridor_noise.seed = 0x53454E424F4E ^ seed_mix
	_corridor_noise.frequency = 0.018
	paths = null
	if profile.paths_enabled:
		paths = ForestPaths.new()
		paths.setup(profile, Callable(self, "_hill_height"))
	_spots_ready = true
	_build_materials()
	_build_meshes()


## Where the player actually walks. Locomotion moves the XR origin/body, not
## the rig root, so the root stays at the spawn while the player walks away;
## anchoring chunks on it strands the whole forest behind (desktop rigs move
## the root itself, so they just use it).
func _anchor_position() -> Vector3:
	if follow != null and follow.has_method("feet_position"):
		return follow.call("feet_position")
	return follow.global_position


func _exit_tree() -> void:
	# Prefetched samples still on worker threads finish before the forest is gone.
	for key in _poisson_jobs.keys():
		WorkerThreadPool.wait_for_task_completion(_poisson_jobs[key][0])
	_poisson_jobs.clear()


func _physics_process(_delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		return
	var anchor := _anchor_position()
	var next := _world_to_chunk(anchor)
	if next != center_chunk:
		# Walking moves one chunk at a time and the next ring is already loaded, so
		# the new ring builds over frames. A jump (teleport) has no floor under it
		# yet, so that one is built at once.
		var jump := maxi(absi(next.x - center_chunk.x), absi(next.y - center_chunk.y)) > 1
		center_chunk = next
		_rebuild_active_chunks(jump)
	_build_next_pending(true)
	# Trees reveal while walking inside a chunk; a full 9-chunk rescan is a few
	# hundred distance checks, so only redo it after a couple of metres. A chunk
	# that is still growing its trees is rescanned every frame until it is full size.
	if _last_tree_draw_pos == Vector3.INF or anchor.distance_to(_last_tree_draw_pos) > 2.0 or _any_tree_growing():
		_last_tree_draw_pos = anchor
		_refresh_tree_draw(anchor)


func height_at(wx: float, wz: float) -> float:
	var hill := _hill_height(wx, wz)
	if not _spots_ready:
		return hill
	return hill + _root_mound(wx, wz)


## Exact height of the rendered terrain mesh at (wx, wz): the mesh samples
## height_at() on the global lattice and splits each quad the same way,
## so this reproduces the visible ground instead of the analytic ideal.
func _mesh_height(wx: float, wz: float) -> float:
	var step := _chunk_size / float(_terrain_res - 1)
	var fx := wx / step
	var fz := wz / step
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := _lattice_height(ix, iz)
	var h10 := _lattice_height(ix + 1, iz)
	var h01 := _lattice_height(ix, iz + 1)
	var h11 := _lattice_height(ix + 1, iz + 1)
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 * (tx + tz - 1.0) + h10 * (1.0 - tz) + h01 * (1.0 - tx)


## Terrain height on the global lattice, cached: a chunk's trees read the same
## points its mesh already sampled (36 height queries per tree otherwise).
func _lattice_height(ix: int, iz: int) -> float:
	var key := Vector2i(ix, iz)
	if _lattice_heights.has(key):
		return _lattice_heights[key]
	var step := _chunk_size / float(_terrain_res - 1)
	var h := height_at(float(ix) * step, float(iz) * step)
	_lattice_heights[key] = h
	return h


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
	var clearing := _clearing_radius
	if d < clearing - MOUND_FADE_START:
		return CLEARING_HEIGHT
	var blend := smoothstep(clearing - HILL_BLEND_START, clearing + _hill_blend, d)
	var n := _height_noise.get_noise_2d(wx, wz) * _hill_amplitude
	n += _bump_noise.get_noise_2d(wx, wz) * _bump_amplitude
	# Grade of the broad hill over a couple of metres. Pockets sit on the
	# flats; a slope that is already near the walk limit does not get steeper.
	var flat := _hill_flatness(wx, wz)
	var pocket := _floor_noise.get_noise_2d(wx, wz)
	var root := 1.0 - absf(_floor_noise.get_noise_2d(wx * 0.41 + 18.0, wz * 0.41))
	n += (pocket * _pocket_amount + root * root * _root_amount) * flat
	return lerpf(CLEARING_HEIGHT, CLEARING_HEIGHT + n, blend)


func _hill_flatness(wx: float, wz: float) -> float:
	var sx := _height_noise.get_noise_2d(wx + 1.2, wz) - _height_noise.get_noise_2d(wx - 1.2, wz)
	var sz := _height_noise.get_noise_2d(wx, wz + 1.2) - _height_noise.get_noise_2d(wx, wz - 1.2)
	var grade := clampf(Vector2(sx, sz).length() * _hill_amplitude / 2.4, 0.0, 1.0)
	return 1.0 - smoothstep(0.22, 0.48, grade)


## Soil heaped against the trunk. Same spots the trees use, so the mound and
## the mesh meet. Fades out in the level glade and on slopes that are already steep.
func _root_mound(wx: float, wz: float) -> float:
	var clearing := _clearing_radius
	var d := Vector2(wx, wz).length()
	if d < clearing - MOUND_FADE_START:
		return 0.0
	var fade := smoothstep(clearing - MOUND_FADE_START, clearing + MOUND_FADE_END, d)
	# Chunks are centered on their origin, so a point just west of 0 still
	# belongs to chunk 0. Search the round neighbourhood, not floor() — but
	# only the 4 m buckets the 1.6 m mound radius can touch.
	var cx := int(round(wx / _chunk_size))
	var cz := int(round(wz / _chunk_size))
	var best := 0.0
	var lox := int(floor((wx - 1.7) / MOUND_CELL))
	var hix := int(floor((wx + 1.7) / MOUND_CELL))
	var loz := int(floor((wz - 1.7) / MOUND_CELL))
	var hiz := int(floor((wz + 1.7) / MOUND_CELL))
	var half := _chunk_size * 0.5
	for ox in range(-1, 2):
		# A neighbour's trunks can only reach this point if the 1.7 m reach crosses
		# the shared border: most points only ever query their own chunk.
		var nx := cx + ox
		if wx + 1.7 < nx * _chunk_size - half or wx - 1.7 > nx * _chunk_size + half:
			continue
		for oz in range(-1, 2):
			var nz := cz + oz
			if wz + 1.7 < nz * _chunk_size - half or wz - 1.7 > nz * _chunk_size + half:
				continue
			var packed: Dictionary = _tree_spots(Vector2i(nx, nz))
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
	# Most points have no trunk within reach: the slope (four hill samples) is
	# only worth computing where there is a heap to settle.
	if best <= 0.0:
		return 0.0
	# Rise over one metre. The walk test uses the same step; a heap on a
	# face that is already steep is what pushed it past 40°.
	var slope := _local_hill_slope(wx, wz)
	var settle := 1.0 - smoothstep(0.1, 0.26, slope)
	return best * settle * fade


func _local_hill_slope(wx: float, wz: float) -> float:
	var dx := _hill_height(wx + 0.5, wz) - _hill_height(wx - 0.5, wz)
	var dz := _hill_height(wx, wz + 0.5) - _hill_height(wx, wz - 0.5)
	return Vector2(dx, dz).length()


## Glade height: flat ground, the spawn is level by construction.
const CLEARING_HEIGHT := 0.0


func props_in_clearing() -> int:
	var count := 0
	for key in _chunks:
		count += int(_chunks[key].get_meta("clearing_props", 0))
	return count


## Builds the ring. [param build_now] false (walking) queues the new chunks and
## [method _build_next_pending] builds one per physics frame, so a border crossing
## never stalls a frame on three chunks at once.
func _rebuild_active_chunks(build_now := true) -> void:
	var wanted: Dictionary = {}
	var radius := profile.chunk_radius
	for ox in range(-radius, radius + 1):
		for oz in range(-radius, radius + 1):
			wanted[center_chunk + Vector2i(ox, oz)] = true
	_wanted_chunks = wanted
	for key in _chunks.keys():
		if not wanted.has(key):
			_forget_trunks(_chunks[key] as Node3D)
			(_chunks[key] as Node3D).queue_free()
			_chunks.erase(key)
	active_chunk_keys.clear()
	var still_wanted: Array[Vector2i] = []
	for key in _pending_chunks:
		if wanted.has(key) and not _chunks.has(key):
			still_wanted.append(key)
	_pending_chunks = still_wanted
	for key in wanted.keys():
		active_chunk_keys.append(key)
		if not _chunks.has(key):
			if build_now:
				_chunks[key] = _make_chunk(key)
			elif not _pending_chunks.has(key):
				_pending_chunks.append(key)
	chunk_count = _chunks.size()
	if not build_now:
		for ox in range(-radius - 2, radius + 3):
			for oz in range(-radius - 2, radius + 3):
				_prefetch_potentials(center_chunk + Vector2i(ox, oz))
	# The soil mounds query tree spots of the ±1 neighbourhood, so keep that
	# halo cached and drop everything further: roaming must not grow memory.
	for key in _tree_spot_cache.keys():
		var c: Vector2i = key
		if maxi(absi(c.x - center_chunk.x), absi(c.y - center_chunk.y)) > radius + 1:
			_tree_spot_cache.erase(key)
	for key in _potential_cache.keys():
		var c: Vector2i = key
		if maxi(absi(c.x - center_chunk.x), absi(c.y - center_chunk.y)) > radius + 2:
			_potential_cache.erase(key)
	for key in _extra_spot_cache.keys():
		var c: Vector2i = key
		if maxi(absi(c.x - center_chunk.x), absi(c.y - center_chunk.y)) > radius + 1:
			_extra_spot_cache.erase(key)
	for key in _back_spot_cache.keys():
		var c: Vector2i = key
		if maxi(absi(c.x - center_chunk.x), absi(c.y - center_chunk.y)) > radius + 1:
			_back_spot_cache.erase(key)
	for key in _path_field_cache.keys():
		var c: Vector2i = key
		if maxi(absi(c.x - center_chunk.x), absi(c.y - center_chunk.y)) > radius + 2:
			_path_field_cache.erase(key)
	if paths != null:
		var reach := (radius + 2.5) * _chunk_size
		var centre := Vector2(center_chunk.x, center_chunk.y) * _chunk_size
		paths.prune(Rect2(centre - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	if follow:
		_last_tree_draw_pos = _anchor_position()
		_refresh_tree_draw(_anchor_position())


## Terrain rows sampled per physics frame while walking (a row is 41 height queries).
const TERRAIN_ROWS_PER_FRAME := 2

## Builds the queued chunks a slice per physics frame, nearest-first (the ring is queued in order).
## [param walking] stamps the chunk so its trees grow in (see _tree_growth); finish_pending builds whole.
func _build_next_pending(walking: bool) -> void:
	if _building == null:
		while not _pending_chunks.is_empty():
			var key: Vector2i = _pending_chunks.pop_front()
			if _wanted_chunks.has(key) and not _chunks.has(key):
				_building = TerrainBuild.new(self, key)
				_building_key = key
				break
		if _building == null:
			return
	if not _building.sample(TERRAIN_ROWS_PER_FRAME):
		return
	var key := _building_key
	var terrain := _building.mesh()
	_building = null
	if _wanted_chunks.has(key) and not _chunks.has(key):
		_chunks[key] = _make_chunk(key, terrain)
		if walking:
			(_chunks[key] as Node3D).set_meta("grow_from", Engine.get_physics_frames())
		chunk_count = _chunks.size()


## Builds every queued chunk now (tests and the forest's own checks; play builds them over frames).
func finish_pending() -> void:
	while _building != null or not _pending_chunks.is_empty():
		_build_next_pending(false)
	chunk_count = _chunks.size()


func _make_chunk(coord: Vector2i, terrain_mesh: ArrayMesh = null) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	add_child(root)
	root.position = Vector3(coord.x * _chunk_size, 0.0, coord.y * _chunk_size)

	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = terrain_mesh if terrain_mesh != null else _build_terrain_mesh(coord)
	terrain.material_override = _chunk_ground_material(coord)
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_set_view_range(terrain)
	root.add_child(terrain)
	root.add_child(_build_terrain_collider(terrain.mesh as ArrayMesh))

	var clearing_props := 0
	clearing_props += _populate_trees(root, coord)
	clearing_props += _populate_torii(root, coord)
	clearing_props += _populate_extra_trees(root, coord)
	_populate_back_trees(root, coord)
	clearing_props += _populate_props(root, "Lanterns", _lantern_mesh, _lantern_mat, _lantern_spec(), coord, KIND_LANTERN)
	for u in profile.undergrowth.size():
		var entry := profile.undergrowth[u]
		clearing_props += _populate_props(root, "Undergrowth%d" % u, _under_meshes[u], _under_mats[u],
			_undergrowth_spec(entry), coord, KIND_UNDERGROWTH + u, u)
	_place_moon_shafts(root, coord)
	root.set_meta("clearing_props", clearing_props)
	return root


## Trees: the ordinary kinds share the chunk's trunks by weight, then each focal
## kind (sakura) turns one of them into its focal tree. One MultiMesh per kind.
func _populate_trees(root: Node3D, coord: Vector2i) -> int:
	var packed := _tree_spots(coord)
	var ordinary_all: Array[Transform3D] = []
	var focal_all: Array[Transform3D] = []
	_place_tree_spots(root, packed.spots, packed.ids, ordinary_all, focal_all)
	root.set_meta("tree_local_xfs", ordinary_all)
	root.set_meta("sakura_tree_local_xfs", focal_all)
	return int(packed.clearing)


## Layout-after kinds (TreeEntry.base_layout off): placed once the gates are planned, so
## they keep off the torii and never move the base trees.
func _populate_extra_trees(root: Node3D, coord: Vector2i) -> int:
	var extra := _extra_tree_spots(coord)
	if extra.spots.is_empty():
		return 0
	_place_tree_spots(root, extra.spots, extra.ids, [] as Array[Transform3D], [] as Array[Transform3D])
	return 0


## Plants the spots of one chunk: transforms, colliders, props, and one MultiMesh per kind.
func _place_tree_spots(root: Node3D, spots: Array, ids: PackedInt32Array,
		ordinary_all: Array[Transform3D], focal_all: Array[Transform3D]) -> void:
	var props: Array = root.get_meta("prop_world_positions", [])
	var per_kind: Dictionary = {}
	for i in spots.size():
		var spot: Vector4 = spots[i]
		var e: int = ids[i]
		var entry := profile.trees[e]
		var wx := spot.x
		var wz := spot.y
		var scale := spot.z
		var yaw := spot.w
		var reach := 2.1 * (entry.focal_scale_boost if entry.is_focal() else 1.0)
		# Plant from the rendered mesh, sunk below the lowest ground in ribbon
		# reach: on a slope the analytic height floats above the downhill
		# mesh, which left roots standing in the air.
		var base := _mesh_min_height(wx, wz, reach) - 0.05 * scale
		# Lean with the hill, not the mound, so the roots lie on the slope
		# instead of sticking out on the downhill side.
		var basis := _trunk_basis(Vector2(wx, wz), entry, yaw, scale)
		var xf := Transform3D(basis, Vector3(wx - root.position.x, base, wz - root.position.z))
		if not per_kind.has(e):
			per_kind[e] = [] as Array[Transform3D]
		(per_kind[e] as Array).append(xf)
		if entry.is_focal():
			focal_all.append(xf)
		else:
			ordinary_all.append(xf)
		props.append(Vector3(wx, base, wz))
	root.set_meta("prop_world_positions", props)
	for e in profile.trees.size():
		if not per_kind.has(e):
			continue
		var xfs: Array[Transform3D] = per_kind[e]
		var entry := profile.trees[e]
		var label := ("Focal%d" if entry.is_focal() else "Trees%d") % e
		root.set_meta("xfs_" + label, xfs)
		# A scene crown is drawn ring-wide (see _scene_tree_node), not once per chunk.
		if entry.crown != TreeEntry.Crown.SCENE:
			_commit_multimesh(root, label, _tree_meshes[e], _tree_mats[e], xfs)
		if entry.obstacle:
			root.add_child(_build_tree_colliders(xfs, e, root))


## Scatter for gates, lanterns and boulders: one MultiMesh per kind, placed
## with trunk and prop clearances from the spec (see _torii_spec and friends).
func _populate_props(root: Node3D, label: String, mesh: Mesh, mat: Material, spec: Dictionary,
		coord: Vector2i, kind: int, undergrowth_index := -1) -> int:
	var transforms: Array[Transform3D] = []
	var clearing_hits := 0
	# Deterministic per chunk and kind, so a recycled chunk grows back the same.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([coord.x, coord.y, kind, 0x464F52]) ^ profile.world_seed
	# Keep-out: trees first, then everything already placed, and the gates' passages (the
	# gate plan is data, so the order of chunk builds does not matter).
	var tree_keep := _prop_trunk_points(coord)
	var field := _path_field(coord)
	# Boulders keep the same clearance from the trail as trunks do (see _tree_spots).
	var path_keep := _path_half_width() + profile.path_tree_clearance
	var placed: Array = []
	var gates_near: Array = _torii_gates_ring(coord) if kind == KIND_LANTERN else []
	for p in _sites_for(rng, coord, spec):
		var lx: float = p.x
		var lz: float = p.y
		var wx := root.position.x + lx
		var wz := root.position.z + lz
		if _in_clearing(wx, wz):
			clearing_hits += 1
			continue
		if kind == KIND_LANTERN and _near_gate_of_chunk(gates_near, wx, wz):
			continue
		if _in_torii_opening(wx, wz, TORII_OPENING_PAD):
			continue
		if bool(spec.avoid_path) and not field.is_empty() and _field_at(field, Vector2(lx, lz)) < path_keep:
			continue
		# Along-path kinds (N5 ferns) stand on the edge only: a site inside another trail's
		# edge zone (where two footpaths meet) is skipped, so no fern sits on gravel.
		if bool(spec.get("path_only", false)) and not field.is_empty() and _field_at(field, Vector2(lx, lz)) < _path_half_width() + 0.6:
			continue
		var density := _scatter_noise.get_noise_2d(wx * profile.density_frequency, wz * profile.density_frequency) * 0.5 + 0.5
		if density < float(spec.cluster):
			continue
		var hy := height_at(wx, wz)
		var scale := rng.randf_range(float(spec.scale_min), float(spec.scale_max))
		var grow := float(spec.grow)
		var tree_clear := float(spec.tree_clear) + scale * grow
		if _spot_blocked(tree_keep, wx, wz, tree_clear):
			continue
		var prop_clear := float(spec.prop_clear) + scale * grow
		if _spot_blocked(placed, wx, wz, prop_clear):
			continue
		placed.append(Vector3(wx, wz, prop_clear * 0.5))
		# Boulders sit half-buried instead of balancing on the slope.
		hy -= float(spec.bury) * scale
		var angle := rng.randf() * TAU
		var basis := Basis.from_euler(Vector3(0.0, angle, 0.0)) * Basis.from_scale(Vector3.ONE * scale)
		transforms.append(Transform3D(basis, Vector3(lx, hy, lz)))
		if transforms.size() >= int(spec.max):
			break
		var props: Array = root.get_meta("prop_world_positions", [])
		props.append(Vector3(wx, hy, wz))
		root.set_meta("prop_world_positions", props)
		if kind >= KIND_UNDERGROWTH:
			var stones: Array = root.get_meta("undergrowth_world_positions", [])
			stones.append(Vector3(wx, hy, wz))
			root.set_meta("undergrowth_world_positions", stones)
		elif kind == KIND_LANTERN:
			var lanterns: Array = root.get_meta("lantern_world_positions", [])
			lanterns.append(Vector3(wx, hy, wz))
			root.set_meta("lantern_world_positions", lanterns)
	if not transforms.is_empty():
		_commit_multimesh(root, label, mesh, mat, transforms)
		# The kind's placed transforms, kept on the chunk like the trees' (headless reads of a
		# MultiMesh buffer come back as identity, so the tests read these).
		root.set_meta("xfs_" + label, transforms)
		if kind == KIND_LANTERN:
			root.add_child(_build_lantern_colliders(transforms, root))
		elif spec.obstacle:
			root.add_child(_build_undergrowth_colliders(transforms, undergrowth_index, root))
	return clearing_hits


## Decorative gates of one chunk: the footpath sites, snapped onto the rendered centre line, minus
## the ones in clearings, on the base trunks, or too close to each other. Decided from the path,
## the base trunks and the chunk's own seed only, so every chunk computes the same plan whatever
## order the chunks are built in. Vector4(x, z, yaw, scale) per gate, world xz.
func _torii_plan(coord: Vector2i) -> Array[Vector4]:
	if _torii_plan_cache.has(coord):
		return _torii_plan_cache[coord]
	var out: Array[Vector4] = []
	var spec := _torii_spec()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([coord.x, coord.y, KIND_TORII, 0x464F52]) ^ profile.world_seed
	# Only chosen chunks hold gates; inside one, most candidates stay, so gates come in small groups.
	var torii_exists := _hash01(_hash_coord(coord, 1, 77) ^ profile.world_seed, 0) < profile.torii_chunk_chance
	var tree_keep := _tree_trunk_points(coord)
	var placed: Array = []
	var origin := Vector2(float(coord.x), float(coord.y)) * _chunk_size
	if torii_exists:
		for p in _sites_for(rng, coord, spec):
			var wx := origin.x + p.x
			var wz := origin.y + p.y
			# A gate near a footpath stands on its centre line, facing along it (see _torii_path_pose).
			var pose := _torii_path_pose(wx, wz)
			if not is_nan(pose.z):
				wx = pose.x
				wz = pose.y
			if _in_clearing(wx, wz):
				continue
			if rng.randf() > profile.torii_group_keep:
				continue
			var scale := torii_scale_for_height(rng.randf_range(profile.torii_height_min, profile.torii_height_max))
			if _spot_blocked(tree_keep, wx, wz, float(spec.tree_clear)):
				continue
			var prop_clear := float(spec.prop_clear)
			if _spot_blocked(placed, wx, wz, prop_clear):
				continue
			placed.append(Vector3(wx, wz, prop_clear * 0.5))
			var yaw := pose.z if not is_nan(pose.z) else rng.randf() * TAU
			out.append(Vector4(wx, wz, yaw, scale))
			if out.size() >= int(spec.max):
				break
	out.append_array(_senbon_plan(coord))
	_torii_plan_cache[coord] = out
	return out


## Places the decorative gates of one chunk from its plan (see _torii_plan).
func _populate_torii(root: Node3D, coord: Vector2i) -> int:
	var transforms: Array[Transform3D] = []
	for g in _torii_plan(coord):
		var wx := g.x
		var wz := g.y
		# Live gates keep their own clear space; the decorative gate is left out there.
		if torii_manager and torii_manager.is_near_gate(wx, wz, GATE_CLEAR_OF_LIVE_GATE):
			continue
		# Gates stand upright: drop the whole frame below the lowest ground under its span.
		var hy := _mesh_min_height(wx, wz, 2.0) - 0.05
		var basis := Basis.from_euler(Vector3(0.0, g.z, 0.0)) * Basis.from_scale(Vector3.ONE * g.w)
		transforms.append(Transform3D(basis, Vector3(wx - root.position.x, hy, wz - root.position.z)))
		var props: Array = root.get_meta("prop_world_positions", [])
		props.append(Vector3(wx, hy, wz))
		root.set_meta("prop_world_positions", props)
		var gates: Array = root.get_meta("torii_world_positions", [])
		gates.append(Vector3(wx, hy, wz))
		root.set_meta("torii_world_positions", gates)
	if not transforms.is_empty():
		_commit_multimesh(root, "Torii", _torii_mesh, _torii_mat, transforms)
		root.set_meta("xfs_Torii", transforms)
		root.add_child(_build_torii_colliders(transforms, root))
	return 0


## Plan gates of the 3×3 chunks around [param coord], as Vector3(x, 0, z) for the distance rules.
func _torii_gates_ring(coord: Vector2i) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			for g in _torii_plan(coord + Vector2i(ox, oz)):
				out.append(Vector3(g.x, 0.0, g.y))
	return out


## True when the world point (wx, wz) lies in the passage of a decorative gate, or within [param pad]
## of it (posts included). The gate's frame: local z runs along the path, local x across it.
func _in_torii_opening(wx: float, wz: float, pad: float) -> bool:
	var cx := int(roundf(wx / _chunk_size))
	var cz := int(roundf(wz / _chunk_size))
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			for g in _torii_plan(Vector2i(cx + ox, cz + oz)):
				var d := Vector2(wx - g.x, wz - g.y)
				var along := Vector2(sin(g.z), cos(g.z))
				var across := Vector2(cos(g.z), -sin(g.z))
				if absf(d.dot(across)) <= TORII_OPENING_HALF.x + pad and absf(d.dot(along)) <= TORII_OPENING_HALF.y + pad:
					return true
	return false


func _torii_spec() -> Dictionary:
	return {
		"max": profile.torii_max_per_chunk, "spacing": profile.torii_min_spacing, "cluster": -1.0,
		"scale_min": 0.0, "scale_max": 0.0, "grow": 0.0,
		"tree_clear": profile.torii_tree_clearance, "prop_clear": profile.torii_prop_clearance,
		"bury": 0.0, "obstacle": true,
		"path_share": profile.torii_on_path, "path_offset": 0.0, "avoid_path": false,
	}


## Where a decorative gate at (wx, wz) stands on a footpath: the nearest centre-line point
## within TORII_PATH_SNAP, with the yaw that runs its passage along the path. Vector3(x, z, yaw);
## yaw is NAN when no footpath is that close (the gate keeps its random yaw).
func _torii_path_pose(wx: float, wz: float) -> Vector3:
	if paths == null:
		return Vector3(wx, wz, NAN)
	# The rendered centre line, so the gate meets the path the player sees (not the raw route).
	var n := paths.smooth_nearest(Vector2(wx, wz), TORII_PATH_SNAP, PATH_SIMPLIFY_TOL)
	if n == Vector4.ZERO:
		return Vector3(wx, wz, NAN)
	# The passage is local Z, (sin yaw, cos yaw): the same convention as ToriiManager.
	return Vector3(n.x, n.y, atan2(n.z, n.w))


func _lantern_spec() -> Dictionary:
	return {
		"max": profile.lantern_max_per_chunk, "spacing": profile.path_lantern_spacing,
		"cluster": -1.0,
		"scale_min": profile.lantern_scale_min, "scale_max": profile.lantern_scale_max, "grow": 0.0,
		"tree_clear": profile.lantern_clearance, "prop_clear": profile.lantern_clearance,
		"bury": 0.0, "obstacle": true,
		"path_share": profile.lantern_on_path, "path_offset": _path_half_width() + 1.4, "avoid_path": false,
		"path_only": true,
	}


func _undergrowth_spec(entry: UndergrowthEntry) -> Dictionary:
	# Along the footpaths: the sites are the trail edges only (path_only), so the kind never
	# lands on the gravel and never on the open floor. Otherwise the floor scatter as before.
	var along := entry.along_path
	return {
		"max": entry.max_per_chunk, "spacing": entry.min_spacing, "cluster": entry.cluster_threshold,
		"scale_min": entry.scale_min, "scale_max": entry.scale_max, "grow": 0.5,
		"tree_clear": entry.clearance, "prop_clear": entry.clearance,
		"bury": entry.bury, "obstacle": entry.obstacle,
		"path_share": 1.0 if along else 0.0,
		"path_offset": _path_half_width() + entry.path_edge_offset if along else 0.0,
		"avoid_path": not along, "path_only": along,
	}


## Trunk spots of the 3×3 ring: the keep-out set for scattered props.
## Spots of the layout-after kinds in one chunk, cached. A candidate stays when it is off the
## free ground's path, off the base trunks (EXTRA_BASE_CLEAR) and off the gates of the 3×3 ring
## (EXTRA_GATE_CLEAR), and keeps its own spacing from the extra trunks already accepted.
func _extra_tree_spots(coord: Vector2i) -> Dictionary:
	if _extra_spot_cache.has(coord):
		return _extra_spot_cache[coord]
	var size := _chunk_size
	var centre := Vector2(float(coord.x) * size, float(coord.y) * size)
	var field := _path_field(coord)
	var path_gap := _path_half_width() + profile.path_tree_clearance
	var base: Array = _tree_trunk_points(coord)
	var gates: Array[Vector3] = _torii_gates_ring(coord)
	var accepted: Array[Vector4] = []
	var spots: Array[Vector4] = []
	var ids := PackedInt32Array()
	for e in _extra_entries():
		var entry := profile.trees[e]
		for p in _take_poisson(coord, e):
			if _in_clearing(p.x, p.y):
				continue
			if not field.is_empty() and _field_at(field, p - centre) < path_gap:
				continue
			var density := _scatter_noise.get_noise_2d(p.x * profile.density_frequency, p.y * profile.density_frequency) * 0.5 + 0.5
			if _point_random(p.x, p.y, 1) > lerpf(profile.tree_keep_min, profile.tree_keep_max, density):
				continue
			var scale := lerpf(entry.scale_min, entry.scale_max, _point_random(p.x, p.y, 2))
			var yaw := _point_random(p.x, p.y, 3) * TAU if entry.random_yaw else 0.0
			var reach := _crown_reach_at(p, e, scale, yaw)
			# Crowns may touch the base crowns only as far as the canopy rule allows (see _near_extra).
			if _in_torii_opening(p.x, p.y, TORII_OPENING_PAD):
				continue
			if _near_base(base, p, reach) or _near_points3(gates, p, EXTRA_GATE_CLEAR):
				continue
			if _near_extra(accepted, p, e, entry.min_spacing, reach):
				continue
			if not _crown_clear(p, e, scale, yaw):
				continue
			var spot := Vector4(p.x, p.y, scale, yaw)
			spots.append(spot)
			ids.append(e)
			accepted.append(Vector4(p.x, p.y, float(e), reach))
	var packed := {"spots": spots, "ids": ids}
	_extra_spot_cache[coord] = packed
	return packed


static func _near_points(points: Array, p: Vector2, clear: float) -> bool:
	for q in points:
		var v: Vector3 = q
		if Vector2(v.x - p.x, v.y - p.y).length() < clear:
			return true
	return false


static func _near_points3(points: Array[Vector3], p: Vector2, clear: float) -> bool:
	for q in points:
		if Vector2(q.x - p.x, q.z - p.y).length() < clear:
			return true
	return false


static func _near_vec4(points: Array[Vector4], p: Vector2, clear: float) -> bool:
	for q in points:
		if Vector2(q.x - p.x, q.y - p.y).length() < maxf(clear, q.w):
			return true
	return false


## Base trunks of the 3×3 ring as (x, z, crown reach): the reach (see _crown_reach_at) is what the
## canopy rule of the layout-after kinds needs; the prop checks read only x and z.
func _tree_trunk_points(coord: Vector2i) -> Array:
	var out: Array = []
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			var packed: Dictionary = _tree_spots(coord + Vector2i(ox, oz))
			var spots: Array = packed.get("spots", [])
			var ids: PackedInt32Array = packed.get("ids", PackedInt32Array())
			for i in spots.size():
				var spot: Vector4 = spots[i]
				var reach := _crown_reach_at(Vector2(spot.x, spot.y), ids[i], spot.z, spot.w)
				out.append(Vector3(spot.x, spot.y, reach))
	return out


## Keep-out trunks for lanterns and boulders: the base trunks plus the layout-after
## trunks (sequoia, pine) of the 3×3 ring. Kept apart from _tree_trunk_points, which
## the layout-after spots themselves are built from. A neighbour's layout-after spots
## are read only when already cached: computing them early would fix them before the
## gates of that neighbour's ring are planned (the budget test caught a redwood that way).
## Until then a neighbour keeps out its layout-after candidates (the pure Poisson samples,
## a superset of its trunks), so a prop never lands beside a trunk that is yet to be planted.
func _prop_trunk_points(coord: Vector2i) -> Array:
	var out := _tree_trunk_points(coord)
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			var c := coord + Vector2i(ox, oz)
			if c != coord and not _extra_spot_cache.has(c):
				for e in _extra_entries():
					for p in _take_poisson(c, e):
						out.append(Vector3(p.x, p.y, 0.0))
				continue
			for s in _extra_tree_spots(c).get("spots", []):
				var spot: Vector4 = s
				out.append(Vector3(spot.x, spot.y, 0.0))
	return out


## Poisson-disk trunk candidates of a chunk, per ordinary kind (PoissonDisk,
## Bridson 2007). Each candidate survives the clearing and the density test
## here, so it is a pure function of the chunk, the seed and the profile:
## a neighbour can read it without knowing what else is loaded.
func _potential_trunks(coord: Vector2i) -> Dictionary:
	if _potential_cache.has(coord):
		return _potential_cache[coord]
	var points: Array[Vector4] = []
	var clearing := 0
	var size := _chunk_size
	var centre := Vector2(float(coord.x) * size, float(coord.y) * size)
	var field := _path_field(coord)
	var path_gap := _path_half_width() + profile.path_tree_clearance
	for e in _ordinary_entries():
		var entry := profile.trees[e]
		var sample := _take_poisson(coord, e)
		for p in sample:
			if _in_clearing(p.x, p.y):
				clearing += 1
				continue
			if not field.is_empty() and _field_at(field, p - centre) < path_gap:
				continue
			var density := _scatter_noise.get_noise_2d(p.x * profile.density_frequency, p.y * profile.density_frequency) * 0.5 + 0.5
			if _point_random(p.x, p.y, 1) > lerpf(profile.tree_keep_min, profile.tree_keep_max, density):
				continue
			var scale := lerpf(entry.scale_min, entry.scale_max, _point_random(p.x, p.y, 2))
			var yaw := _point_random(p.x, p.y, 3) * TAU if entry.random_yaw else 0.0
			if not _crown_clear(p, e, scale, yaw):
				continue
			points.append(Vector4(p.x, p.y, float(e), entry.min_spacing))
	var result := {"points": points, "clearing": clearing}
	_potential_cache[coord] = result
	return result


## The Poisson points of one ordinary kind in one chunk. The sampler is pure
## (its own rng, no shared state), so a prefetched sample from a worker thread is
## the same points as one computed here.
static func _poisson_samples(seed_value: int, origin: Vector2, size: Vector2, spacing: float, out: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	out[0] = PoissonDisk.sample(rng, origin, size, spacing)


func _poisson_seed(coord: Vector2i, e: int) -> int:
	return hash([coord.x, coord.y, e, 0x50495353]) ^ profile.world_seed


func _take_poisson(coord: Vector2i, e: int) -> PackedVector2Array:
	var key := Vector3i(coord.x, coord.y, e)
	if _poisson_jobs.has(key):
		var job: Array = _poisson_jobs[key]
		_poisson_jobs.erase(key)
		WorkerThreadPool.wait_for_task_completion(job[0])
		return (job[1] as Array)[0]
	var size := _chunk_size
	var origin := Vector2(coord.x * size, coord.y * size) - Vector2(size, size) * 0.5
	var out := [null]
	_poisson_samples(_poisson_seed(coord, e), origin, Vector2(size, size), profile.trees[e].min_spacing, out)
	return out[0]


## Starts the Poisson samples of a chunk on worker threads, ahead of the build.
func _prefetch_potentials(coord: Vector2i) -> void:
	if _potential_cache.has(coord):
		return
	var size := _chunk_size
	var origin := Vector2(coord.x * size, coord.y * size) - Vector2(size, size) * 0.5
	for e in _ordinary_entries() + _extra_entries():
		var key := Vector3i(coord.x, coord.y, e)
		if _poisson_jobs.has(key):
			continue
		var out := [null]
		var task := WorkerThreadPool.add_task(_poisson_samples.bind(_poisson_seed(coord, e), origin,
			Vector2(size, size), profile.trees[e].min_spacing, out), false, "poisson %d,%d" % [coord.x, coord.y])
		_poisson_jobs[key] = [task, out]


## Tree spot set for a chunk, cached. Returns {spots, ids, clearing, cells}.
## Spots are the candidates of this chunk that keep their distance from the
## accepted trunks here and from every candidate of the eight neighbours (a
## superset of what they accept, so the result never depends on load order).
func _tree_spots(coord: Vector2i) -> Dictionary:
	if _tree_spot_cache.has(coord):
		return _tree_spot_cache[coord]
	var own: Dictionary = _potential_trunks(coord)
	var halo: Array[Vector4] = []
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			if ox == 0 and oz == 0:
				continue
			halo.append_array(_potential_trunks(Vector2i(coord.x + ox, coord.y + oz)).points)
	var spots: Array[Vector4] = []
	var ids := PackedInt32Array()
	# Bucketed by spacing cells: a neighbour test looks at 3×3 cells instead of
	# every accepted spot and every halo candidate (the same answer, far fewer reads).
	var cell := _spacing_cell()
	var halo_grid := {}
	for h in halo:
		_grid_add(halo_grid, cell, h)
	var accepted_grid := {}
	for c in own.points:
		var cand: Vector4 = c
		var wx := cand.x
		var wz := cand.y
		if torii_manager and torii_manager.is_near_gate(wx, wz, GATE_CLEAR_OF_LIVE_GATE):
			continue
		if _too_close_to_trees(accepted_grid, halo_grid, cell, wx, wz, cand.w):
			continue
		var entry := profile.trees[int(cand.z)]
		var scale := lerpf(entry.scale_min, entry.scale_max, _point_random(wx, wz, 2))
		var yaw := _point_random(wx, wz, 3) * TAU
		spots.append(Vector4(wx, wz, scale, yaw if entry.random_yaw else 0.0))
		ids.append(int(cand.z))
		_grid_add(accepted_grid, cell, Vector4(wx, wz, 0.0, _spacing_of(int(cand.z))))
	# Focal kinds (sakura): one tree per chunk now and then, on the highest
	# spot near the chunk's middle. Chance per focal kind from its own hash.
	var focal_rank := 0
	for e in profile.trees.size():
		var entry := profile.trees[e]
		if not entry.is_focal():
			continue
		var chance_hash := _hash01(_hash_coord(coord, 4 + focal_rank, 101) ^ profile.world_seed, 0)
		focal_rank += 1
		# The spawn chunk stays open: no focal tree in it, as the opening glade needs.
		if chance_hash >= entry.focal_chance or spots.is_empty() or coord == Vector2i.ZERO:
			continue
		var idx := _pick_focal_spot(coord, spots, ids, e, entry.focal_scale_boost)
		if idx < 0:
			continue
		var s: Vector4 = spots[idx]
		spots[idx] = Vector4(s.x, s.y, s.z * entry.focal_scale_boost, s.w)
		ids[idx] = e
	var packed := {"spots": spots, "ids": ids, "clearing": int(own.clearing), "cells": _cells_of(spots)}
	_tree_spot_cache[coord] = packed
	return packed


## Entry indices of the ordinary (non-focal, weighted) tree kinds.
func _ordinary_entries() -> Array[int]:
	var out: Array[int] = []
	for e in profile.trees.size():
		var entry := profile.trees[e]
		if not entry.is_focal() and entry.weight > 0.0 and entry.base_layout and not entry.back_layer:
			out.append(e)
	return out


## Entry indices of the layout-after tree kinds (see TreeEntry.base_layout).
func _extra_entries() -> Array[int]:
	var out: Array[int] = []
	for e in profile.trees.size():
		var entry := profile.trees[e]
		if not entry.is_focal() and entry.weight > 0.0 and not entry.base_layout and not entry.back_layer:
			out.append(e)
	return out


## Layout-after spacing (N5): two trunks may stand only as far apart as their crowns allow, i.e.
## CROWN_OVERLAP_SHARE × (r1 + r2) (the canopy rule of canopy_visual_quality_test). A kind also keeps
## its own min_spacing from its own trunks. Trunk spacing alone let the crowns of different kinds
## interpenetrate (45 % severe pairs against the 40 % limit).
static func _near_extra(accepted: Array[Vector4], p: Vector2, e: int, own_spacing: float, reach: float) -> bool:
	for q in accepted:
		var need := CROWN_OVERLAP_SHARE * (reach + q.w)
		if int(q.z) == e:
			need = maxf(need, own_spacing)
		if Vector2(q.x, q.y).distance_to(p) < need:
			return true
	return false


## Horizontal crown reach of a planted tree, as canopy_visual_quality_test measures it: the farthest
## crown disc's horizontal offset from the trunk plus its radius, with the tree's own lean and yaw.
func _crown_reach_at(p: Vector2, e: int, scale: float, yaw: float) -> float:
	var basis := _trunk_basis(p, profile.trees[e], yaw, scale)
	var reach := 0.0
	for disc in _crown_discs[e]:
		var d: Vector4 = disc
		var off := basis * Vector3(d.x, d.y, d.z)
		reach = maxf(reach, Vector2(off.x, off.z).length() + d.w * scale)
	return reach


## True when a layout-after trunk at [param p] with crown reach [param reach] is too close to a base
## trunk (x, z, reach): the canopy rule (see _near_extra) and never closer than EXTRA_BASE_CLEAR.
static func _near_base(base: Array, p: Vector2, reach: float) -> bool:
	for q in base:
		var v: Vector3 = q
		if Vector2(v.x - p.x, v.y - p.y).length() < maxf(EXTRA_BASE_CLEAR, CROWN_OVERLAP_SHARE * (v.z + reach)):
			return true
	return false


## Silhouette variants per back-layer kind (N5): picked per tree by a stateless hash, so the wall repeats no shape.
const BACK_VARIANTS := 3

## Metres from the camera where a back-layer kind starts to show (its draw_from, else the profile's back_near).
func _back_near_of(e: int) -> float:
	return _back_near_of_entry(profile.trees[e])


func _back_near_of_entry(entry: TreeEntry) -> float:
	return entry.draw_from if entry.draw_from >= 0.0 else profile.back_near


## Chunk keys of every back-layer silhouette (kind × variant), in order.
func _back_keys() -> Array[int]:
	var out: Array[int] = []
	for e in _back_entries():
		for v in BACK_VARIANTS:
			out.append(back_key(e, v))
	return out


## Entry indices of the back-layer kinds (N5).
func _back_entries() -> Array[int]:
	var out: Array[int] = []
	for e in profile.trees.size():
		if profile.trees[e].back_layer and profile.trees[e].weight > 0.0:
			out.append(e)
	return out


## Back layer (N5): far silhouettes of the forest wall, placed per chunk after everything else.
## They keep off the paths (the sky rule), off the base and layout-after trunks, and off the gates,
## so they never stand in a trunk or over a trail. They have no collider and no layout role.
func _populate_back_trees(root: Node3D, coord: Vector2i) -> void:
	var spots := _back_spots(coord)
	for key in spots:
		root.set_meta("xfs_Back%d" % int(key), spots[key])
	for e in _back_entries():
		if not profile.trees[e].obstacle:
			continue
		var all: Array[Transform3D] = []
		for v in BACK_VARIANTS:
			all.append_array(spots.get(back_key(e, v), []))
		if not all.is_empty():
			root.add_child(_build_back_colliders(all, e, root))


## Trunk colliders of one back-layer kind (N5). Their registrations are remembered on the chunk, so a
## shrine founded later can take them out again (see reserve_shrine).
func _build_back_colliders(all: Array[Transform3D], e: int, root: Node3D) -> StaticBody3D:
	var before := (root.get_meta("trunk_entries", []) as Array).size()
	var body := _build_tree_colliders(all, e, root)
	var registered: Array = root.get_meta("trunk_entries", [])
	root.set_meta("back_trunk_entries", registered.slice(before))
	return body


## True when a ground point lies within SHRINE_RESERVE metres of a shrine.
func _reserved(p: Vector2) -> bool:
	for c in _shrine_reserves:
		if p.distance_to(c) < SHRINE_RESERVE:
			return true
	return false


## A shrine stands at [param at] (world): the middle and back kinds keep SHRINE_RESERVE metres from it.
## Chunks already built lose their silhouettes and colliders there; chunks built later skip them.
func reserve_shrine(at: Vector3) -> void:
	var c := Vector2(at.x, at.z)
	_shrine_reserves.append(c)
	for key in _chunks.keys():
		_strip_back_near(key, c)
	for key in _back_spot_cache.keys():
		var spots: Dictionary = _back_spot_cache[key]
		for k in spots:
			var kept: Array[Transform3D] = []
			for xf in spots[k]:
				var t: Transform3D = xf
				if _chunk_point(key, t.origin).distance_to(c) >= SHRINE_RESERVE:
					kept.append(t)
			spots[k] = kept


## World ground point of a chunk-local origin.
func _chunk_point(coord: Vector2i, local: Vector3) -> Vector2:
	return Vector2(float(coord.x) * _chunk_size + local.x, float(coord.y) * _chunk_size + local.z)


## Removes the back-layer silhouettes of one built chunk within SHRINE_RESERVE of [param c], and rebuilds the
## chunk's colliders of those kinds from what is left.
func _strip_back_near(coord: Vector2i, c: Vector2) -> void:
	var root := _chunks.get(coord) as Node3D
	if root == null:
		return
	var changed := {}
	for key in _back_keys():
		var list: Array = root.get_meta("xfs_Back%d" % key, [])
		var kept: Array[Transform3D] = []
		for xf in list:
			var t: Transform3D = xf
			if _chunk_point(coord, t.origin).distance_to(c) >= SHRINE_RESERVE:
				kept.append(t)
		if kept.size() != list.size():
			changed[key] = true
			root.set_meta("xfs_Back%d" % key, kept)
	if changed.is_empty():
		return
	for e in _back_entries():
		var kind_changed := false
		for v in BACK_VARIANTS:
			if changed.has(back_key(e, v)):
				kind_changed = true
		if not kind_changed:
			continue
		# Forget the old registrations, drop the old body, build the kept silhouettes again.
		var reg: Array = root.get_meta("trunk_entries", [])
		for pair in root.get_meta("back_trunk_entries", []):
			var cell: Vector2i = pair[0]
			(_trunk_cells.get(cell, []) as Array).erase(pair[1])
			reg.erase(pair)
		root.set_meta("trunk_entries", reg)
		root.set_meta("back_trunk_entries", [])
		for child in root.get_children():
			if child is StaticBody3D and String(child.name) == "TrunkColliders%d" % e:
				root.remove_child(child)
				child.queue_free()
		var all: Array[Transform3D] = []
		for v in BACK_VARIANTS:
			var k := back_key(e, v)
			var kept_list: Array = root.get_meta("xfs_Back%d" % k, [])
			all.append_array(kept_list)
			if _back_spot_cache.has(coord):
				(_back_spot_cache[coord] as Dictionary)[k] = kept_list
		if profile.trees[e].obstacle and not all.is_empty():
			root.add_child(_build_back_colliders(all, e, root))

## Key of one back-layer silhouette variant in the chunk spots and meta: kind index × 10 + variant.
static func back_key(e: int, variant: int) -> int:
	return e * 10 + variant


func _back_spots(coord: Vector2i) -> Dictionary:
	if _back_spot_cache.has(coord):
		return _back_spot_cache[coord]
	var size := _chunk_size
	var centre := Vector2(float(coord.x) * size, float(coord.y) * size)
	var field := _path_field(coord)
	var path_gap := _path_half_width() + profile.path_tree_clearance
	var gates: Array[Vector3] = _torii_gates_ring(coord)
	var accepted: Array[Vector4] = []
	var out := {}
	for e in _back_entries():
		var entry := profile.trees[e]
		var lists: Array = []
		for v in BACK_VARIANTS:
			lists.append([] as Array[Transform3D])
		for p in _take_poisson(coord, e):
			if _in_clearing(p.x, p.y) or _reserved(p):
				continue
			if not field.is_empty() and _field_at(field, p - centre) < path_gap:
				continue
			var scale := lerpf(entry.scale_min, entry.scale_max, _point_random(p.x, p.y, 2))
			var yaw := _point_random(p.x, p.y, 3) * TAU if entry.random_yaw else 0.0
			# Beyond back_near the trunk stands behind the near forest, so it may overlap a near crown;
			# it keeps off the gates and its own spacing only (the near rules would leave no room for a wall).
			if _in_torii_opening(p.x, p.y, TORII_OPENING_PAD):
				continue
			if _near_points3(gates, p, EXTRA_GATE_CLEAR):
				continue
			if _near_extra(accepted, p, e, entry.min_spacing, 0.0):
				continue
			if not _crown_clear(p, e, scale, yaw):
				continue
			accepted.append(Vector4(p.x, p.y, float(e), 0.0))
			var base_y := _mesh_min_height(p.x, p.y, 2.1 * scale) - 0.05 * scale
			var variant := clampi(int(_point_random(p.x, p.y, 5) * float(BACK_VARIANTS)), 0, BACK_VARIANTS - 1)
			(lists[variant] as Array[Transform3D]).append(Transform3D(_trunk_basis(p, entry, yaw, scale), Vector3(p.x - centre.x, base_y, p.y - centre.y)))
		for v in BACK_VARIANTS:
			out[back_key(e, v)] = lists[v]
	_back_spot_cache[coord] = out
	return out


## Stateless random in [0, 1) for a world point: the same point always draws
## the same value, whichever chunk asks, so the choices stay order-free.
func _point_random(wx: float, wz: float, salt: int) -> float:
	var h := hash([int(roundf(wx * 1000.0)), int(roundf(wz * 1000.0)), salt, profile.world_seed])
	return float(h & 0x7fffffff) / 2147483647.0


func _spacing_of(entry_index: int) -> float:
	if entry_index < 0 or entry_index >= profile.trees.size():
		return 2.4
	return profile.trees[entry_index].min_spacing


## Grid cell for the spacing test: the largest spacing of any tree kind, so a
## pair that is closer than its radius always sits in neighbouring cells.
func _spacing_cell() -> float:
	var widest := 1.0
	for entry in profile.trees:
		widest = maxf(widest, entry.min_spacing)
	return widest


static func _grid_key(cell: float, x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / cell), floori(z / cell))


## Entries carry (x, z, _, spacing) so the test reads each kind's own radius.
static func _grid_add(grid: Dictionary, cell: float, entry: Vector4) -> void:
	var key := _grid_key(cell, entry.x, entry.y)
	if not grid.has(key):
		grid[key] = [] as Array[Vector4]
	(grid[key] as Array[Vector4]).append(entry)


## True when a candidate at (wx, wz) would sit closer than its kind's spacing
## to an accepted trunk or to a neighbour's candidate. A pair keeps the larger
## of the two kinds' spacing.
static func _too_close_to_trees(accepted: Dictionary, halo: Dictionary, cell: float,
		wx: float, wz: float, spacing: float) -> bool:
	var centre := _grid_key(cell, wx, wz)
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			var key := Vector2i(centre.x + ox, centre.y + oz)
			if _any_closer(accepted.get(key, []), wx, wz, spacing):
				return true
			if _any_closer(halo.get(key, []), wx, wz, spacing):
				return true
	return false


static func _any_closer(entries: Array, wx: float, wz: float, spacing: float) -> bool:
	for e in entries:
		var other: Vector4 = e
		var r := maxf(spacing, other.w)
		var dx := wx - other.x
		var dz := wz - other.y
		if dx * dx + dz * dz < r * r:
			return true
	return false


func _pick_focal_spot(coord: Vector2i, spots: Array[Vector4], ids: PackedInt32Array, focal_e: int, boost: float) -> int:
	var chunk_center := Vector2(float(coord.x) * _chunk_size, float(coord.y) * _chunk_size)
	var best_idx := -1
	var best_score := -INF
	for i in spots.size():
		if profile.trees[ids[i]].is_focal():
			continue
		var s: Vector4 = spots[i]
		# A focal tree is bigger and has its own crown: it must pass the sky rule as itself.
		if not _crown_clear(Vector2(s.x, s.y), focal_e, s.z * boost, s.w):
			continue
		var dist_to_center := Vector2(s.x - chunk_center.x, s.y - chunk_center.y).length()
		var center_penalty := maxf(0.0, dist_to_center - (_chunk_size * 0.35)) * 0.3
		var h := _hill_height(s.x, s.y)
		var score := h - center_penalty
		if score > best_score:
			best_score = score
			best_idx = i
	return best_idx


## True when (wx, wz) intrudes on an occupied spot. Entries are Vector3
## (x, z, radius); clearance adds on top.
func suppress_props_near(wx: float, wz: float, radius: float) -> void:
	var affected_coords: Array[Vector2i] = []
	for c in _tree_spot_cache.keys():
		var packed: Dictionary = _tree_spot_cache[c]
		var spots: Array[Vector4] = []
		var ids := PackedInt32Array()
		var changed := false
		var old_ids: PackedInt32Array = packed.get("ids", PackedInt32Array())
		var k := 0
		for s in packed.get("spots", []):
			var spot: Vector4 = s
			if Vector2(spot.x - wx, spot.y - wz).length() >= radius:
				spots.append(spot)
				ids.append(old_ids[k])
			else:
				changed = true
			k += 1
		if changed:
			packed["spots"] = spots
			packed["ids"] = ids
			packed["cells"] = _cells_of(spots)
			_tree_spot_cache[c] = packed
			affected_coords.append(c)
	if not affected_coords.is_empty():
		_lattice_heights.clear()
	for c in affected_coords:
		if _chunks.has(c):
			_rebuild_chunk(c)


func _cells_of(spots: Array[Vector4]) -> Dictionary:
	var cells := {}
	for s in spots:
		var spot: Vector4 = s
		var key := Vector2i(int(floor(spot.x / MOUND_CELL)), int(floor(spot.y / MOUND_CELL)))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(spot)
	return cells


func _rebuild_chunk(coord: Vector2i) -> void:
	if not _chunks.has(coord):
		return
	var old := _chunks[coord] as Node3D
	_forget_trunks(old)
	old.queue_free()
	_chunks[coord] = _make_chunk(coord)


func is_clear_of_props(wx: float, wz: float, clearance: float) -> bool:
	var cl_sq := clearance * clearance
	var tree_cl_sq := (clearance + 0.35) * (clearance + 0.35)
	var size := _chunk_size
	var min_cx := int(round((wx - clearance - 0.35) / size))
	var max_cx := int(round((wx + clearance + 0.35) / size))
	var min_cz := int(round((wz - clearance - 0.35) / size))
	var max_cz := int(round((wz + clearance + 0.35) / size))

	for cx in range(min_cx, max_cx + 1):
		for cz in range(min_cz, max_cz + 1):
			var n_coord := Vector2i(cx, cz)
			var chunk := _chunks.get(n_coord) as Node3D
			if chunk != null and is_instance_valid(chunk):
				var props: Array = chunk.get_meta("prop_world_positions", [])
				for p in props:
					var prop_pos: Vector3 = p
					var dx := wx - prop_pos.x
					var dz := wz - prop_pos.z
					if dx * dx + dz * dz < cl_sq:
						return false
			else:
				var packed: Dictionary = _tree_spot_cache.get(n_coord, {})
				for s in packed.get("spots", []):
					var spot: Vector4 = s
					var dx := wx - spot.x
					var dz := wz - spot.y
					if dx * dx + dz * dz < tree_cl_sq:
						return false
	return true


func _spot_blocked(occupied: Array, wx: float, wz: float, clearance: float) -> bool:
	for o in occupied:
		var e: Vector3 = o
		if Vector2(wx - e.x, wz - e.y).length() < clearance + e.z:
			return true
	return false


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


func _path_half_width() -> float:
	return profile.path_width * 0.5


## Trodden spur from the nearest path to a shrine. Top level, in world space, so
## the shrine's own turn does not bend it; it is freed with the shrine.
func connect_shrine(shrine: Node3D) -> void:
	reserve_shrine(shrine.position)
	if paths == null:
		return
	var at := shrine.position
	var near := paths.nearest_point(Vector2(at.x, at.z), SHRINE_SPUR_REACH)
	if near == Vector2.INF:
		return
	# Routed like the network (A* on the slope), so the spur follows the hill
	# instead of cutting across it; _ribbon_mesh samples the ground every metre.
	var line := paths.route_between(near, Vector2(at.x, at.z))
	if line.size() < 2:
		return
	var spur := MeshInstance3D.new()
	spur.name = "PathSpur"
	spur.top_level = true
	spur.mesh = _ribbon_mesh(line)
	spur.material_override = _ground_mat
	spur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spur.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	shrine.add_child(spur)


## A flat strip of path along [param line] (world xz), lying on the terrain.
func _ribbon_mesh(line: PackedVector2Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := _path_half_width()
	var colour := Color(1.0, 0.0, 0.0, 1.0)
	for k in range(line.size() - 1):
		var a := line[k]
		var b := line[k + 1]
		var t := (b - a).normalized()
		var n := Vector2(-t.y, t.x) * hw
		# Cells of at most SPUR_CELL: the terrain mesh bends between its lattice points, so a long
		# flat triangle would sink into a hill between two of them.
		var along := maxi(ceili((b - a).length() / SPUR_CELL), 1)
		var across := maxi(ceili(2.0 * hw / SPUR_CELL), 1)
		for i in along:
			for j in across:
				var u0 := float(i) / along
				var u1 := float(i + 1) / along
				var v0 := -1.0 + 2.0 * float(j) / across
				var v1 := -1.0 + 2.0 * float(j + 1) / across
				var p00 := _spur_point(a, b, n, u0, v0)
				var p10 := _spur_point(a, b, n, u1, v0)
				var p11 := _spur_point(a, b, n, u1, v1)
				var p01 := _spur_point(a, b, n, u0, v1)
				for v in [p00, p11, p10, p00, p01, p11]:
					st.set_normal(Vector3.UP)
					st.set_color(colour)
					st.add_vertex(v)
	return st.commit()


## A point of the strip: u runs along the segment a→b, v across it (-1 and +1 at the edges).
## Lifted off the highest rendered ground around it (3×3 cells), not the analytic height the mesh
## misses on slopes: a flat cell between two vertices then never sinks into a hill's bulge.
func _spur_point(a: Vector2, b: Vector2, n: Vector2, u: float, v: float) -> Vector3:
	var p := a.lerp(b, u) + n * v
	var ground := -INF
	for ox in [-SPUR_CELL, 0.0, SPUR_CELL]:
		for oz in [-SPUR_CELL, 0.0, SPUR_CELL]:
			ground = maxf(ground, _mesh_height(p.x + ox, p.y + oz))
	return Vector3(p.x, ground + SPUR_LIFT, p.y)


## Distance from every terrain vertex of a chunk to the nearest path centre line,
## row-major (index j * res + i, same lattice as _build_terrain_mesh), capped at
## the reach the tree and terrain rules need. Empty when paths are off.
func _path_field(coord: Vector2i) -> PackedFloat32Array:
	if paths == null:
		return PackedFloat32Array()
	if _path_field_cache.has(coord):
		return _path_field_cache[coord]
	var res := _terrain_res
	var size := _chunk_size
	var step := size / float(res - 1)
	var half := size * 0.5
	var centre := Vector2(float(coord.x) * size, float(coord.y) * size)
	# Reach covers the sky corridor plus the widest crown, so a crown disc never reads a capped distance.
	var reach := _path_half_width() + maxf(maxf(2.0, profile.path_tree_clearance + 1.0),
			profile.sky_path_half + _sky_margin() + _crown_reach)
	var field := PackedFloat32Array()
	field.resize(res * res)
	field.fill(reach)
	var segments := paths.segments_in_rect(Rect2(centre - Vector2(half, half), Vector2(size, size)), reach)
	for k in range(0, segments.size() - 1, 2):
		var a := segments[k]
		var b := segments[k + 1]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach) - centre + Vector2(half, half)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach) - centre + Vector2(half, half)
		var i0 := clampi(int(floor(lo.x / step)), 0, res - 1)
		var i1 := clampi(int(ceil(hi.x / step)), 0, res - 1)
		var j0 := clampi(int(floor(lo.y / step)), 0, res - 1)
		var j1 := clampi(int(ceil(hi.y / step)), 0, res - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var vp := centre + Vector2(-half + float(i) * step, -half + float(j) * step)
				var d := minf(ForestPaths.segment_distance(vp, a, b), reach)
				var idx := j * res + i
				if d < field[idx]:
					field[idx] = d
	_path_field_cache[coord] = field
	return field


## Field value at a chunk-local point (nearest lattice vertex).
func _field_at(field: PackedFloat32Array, local: Vector2) -> float:
	var res := _terrain_res
	var step := _chunk_size / float(res - 1)
	var half := _chunk_size * 0.5
	var i := clampi(int(round((local.x + half) / step)), 0, res - 1)
	var j := clampi(int(round((local.y + half) / step)), 0, res - 1)
	return field[j * res + i]


## Lattice margin the sky rule adds: a lattice point sits at most 0.71 cells (a half diagonal) from the true distance.
func _sky_margin() -> float:
	return _chunk_size / float(_terrain_res - 1) * 0.71


## Distance from a world point to the nearest path centre line, read from the field of the chunk
## that holds the point (a crown can reach over into the next chunk).
func _path_distance_at(w: Vector2) -> float:
	var coord := _world_to_chunk(Vector3(w.x, 0.0, w.y))
	var field := _path_field(coord)
	if field.is_empty():
		return INF
	return _field_at(field, w - Vector2(coord.x, coord.y) * _chunk_size)


## Trunk basis of a tree at world point [param p]: it leans with the hill, turns by yaw and scales.
## Planting and the sky rule both use it, so a crown is judged where it is drawn.
func _trunk_basis(p: Vector2, entry: TreeEntry, yaw: float, scale: float) -> Basis:
	var up := Vector3.UP.lerp(_hill_normal(p.x, p.y), entry.hill_lean).normalized()
	return _basis_up(up, yaw, scale)


## True when a tree of entry [param e] at [param p] keeps its crown out of the open sky: every crown
## disc stays [member WorldGenProfile.sky_path_half] off each path centre line and clear of the glade disc.
## [param yaw] and [param scale] are the spot's own values, as planted.
func _crown_clear(p: Vector2, e: int, scale: float, yaw: float) -> bool:
	var entry := profile.trees[e]
	var basis := _trunk_basis(p, entry, yaw, scale)
	var limit := profile.sky_path_half + _sky_margin()
	for disc in _crown_discs[e]:
		var d: Vector4 = disc
		var off := basis * Vector3(d.x, d.y, d.z)
		var w := p + Vector2(off.x, off.z)
		# The disc is the crown's core: the drawn clumps reach CROWN_OVERSIZE past it, so the rule
		# measures that reach (the crown points test holds 2 m off the centre line).
		var r := d.w * scale * CROWN_OVERSIZE + CROWN_SKY_MARGIN
		if w.length() - r < profile.sky_glade_radius:
			return false
		if _path_distance_at(w) - r < limit:
			return false
	return true


## Local sites of one prop kind. A share of [param spec].path_share comes from
## the path (beside it, [param spec].path_offset metres off the centre line);
## the rest from Poisson-disk sampling. Both keep [param spec].spacing apart.
func _sites_for(rng: RandomNumberGenerator, coord: Vector2i, spec: Dictionary) -> Array[Vector2]:
	var count := int(spec.max)
	var spacing := float(spec.spacing)
	var share := float(spec.path_share)
	# Path-only kinds (lanterns) never fall back to random sites.
	var path_only: bool = spec.get("path_only", false)
	var poisson: Array[Vector2] = []
	if not path_only:
		# More candidates than kept: trees and props reject some, and a chunk of
		# 40 m needs room to place its full count (see the accept cap in _populate_props).
		poisson = _prop_sites(rng, count * SITE_OVERSAMPLE, spacing)
	if paths == null or share <= 0.0 or count <= 0:
		return poisson
	var size := _chunk_size
	var centre := Vector2(float(coord.x) * size, float(coord.y) * size)
	var on_path: Array[Vector2] = []
	for sample in paths.samples_in_rect(Rect2(centre - Vector2(size, size) * 0.5, Vector2(size, size)), spacing):
		var normal := Vector2(-sample.w, sample.z)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var site := Vector2(sample.x, sample.y) + normal * side * float(spec.path_offset)
		on_path.append(site - centre)
	for k in range(on_path.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp := on_path[k]
		on_path[k] = on_path[j]
		on_path[j] = tmp
	var picks: Array[Vector2] = []
	var want := int(round(float(count) * share))
	for site in on_path:
		if picks.size() >= want:
			break
		if _spaced(picks, site, spacing):
			picks.append(site)
	if path_only:
		return picks
	for site in poisson:
		if picks.size() >= count * SITE_OVERSAMPLE:
			break
		if _spaced(picks, site, spacing):
			picks.append(site)
	return picks


## True when a world point is within LANTERN_CLEAR_OF_TORII of a gate of the chunk.
static func _near_gate_of_chunk(gates: Array, wx: float, wz: float) -> bool:
	for g in gates:
		var e: Vector3 = g
		if Vector2(wx - e.x, wz - e.z).length() < LANTERN_CLEAR_OF_TORII:
			return true
	return false


static func _spaced(picks: Array[Vector2], site: Vector2, spacing: float) -> bool:
	for q in picks:
		if q.distance_to(site) < spacing:
			return false
	return true


## Local (x, z) sites for gates, lanterns and boulders: Poisson-disk samples
## (Bridson) at least [param spacing] apart, then [param count] of them picked
## at random. Any subset of a Poisson set keeps the spacing between its picks.
func _prop_sites(rng: RandomNumberGenerator, count: int, spacing: float) -> Array[Vector2]:
	var half := _chunk_size * 0.5
	var sample := PoissonDisk.sample(rng, Vector2(-half, -half), Vector2(_chunk_size, _chunk_size), spacing)
	for i in range(sample.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := sample[i]
		sample[i] = sample[j]
		sample[j] = tmp
	var out: Array[Vector2] = []
	for k in mini(count, sample.size()):
		out.append(sample[k])
	return out


## Shafts of moonlight through canopy gaps: a few per chunk, one always over
## the spawn glade so the run opens under a beam.
func _place_moon_shafts(root: Node3D, coord: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([coord.x, coord.y, 0x4D4F4F4E]) ^ profile.world_seed
	# Steeper than the real moon so beams drop between trunks instead of
	# lying across the forest.
	var axis := Vector3(moon_direction.x * 0.45, maxf(moon_direction.y, 0.55), moon_direction.z * 0.45).normalized()
	var transforms: Array[Transform3D] = []
	var size := _chunk_size
	var most := profile.shafts_max_per_chunk
	var count := rng.randi_range(mini(2, most), most) if most > 0 else 0
	for i in count:
		var lx := rng.randf_range(-size * 0.5, size * 0.5)
		var lz := rng.randf_range(-size * 0.5, size * 0.5)
		if coord == Vector2i.ZERO and i == 0:
			lx = 1.2
			lz = -1.6
		var wx := root.position.x + lx
		var wz := root.position.z + lz
		var width := rng.randf_range(0.9, 2.1)
		var basis := Basis(axis.cross(Vector3.FORWARD).normalized() * width, axis * profile.shaft_length, Vector3.FORWARD)
		transforms.append(Transform3D(basis, Vector3(lx, height_at(wx, wz) - 0.3, lz)))
	if transforms.is_empty():
		return
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
	inst.custom_aabb = AABB(Vector3(-size, -2.0, -size), Vector3(size * 2.0, profile.shaft_length + 4.0, size * 2.0))
	root.add_child(inst)


## Trunk collider bodies. The player and the blade stop on TRUNK_LAYER; yōkai
## ragdolls ignore it (limbs snag and topple) and steer with trunk_push.
func _new_collider(body_name: String, surface: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = TRUNK_LAYER
	body.collision_mask = 0
	# What the blade feels when it meets it (HeldWeapon reads this).
	body.set_meta("env_surface", surface)
	return body


## Collider body for placed props by kind: 0 trees (first tree kind), 1 gates,
## 2 lanterns, 3 and up undergrowth (kind minus 3). Same layout as the spawn kinds.
func _build_trunk_colliders(xfs: Array, kind: int, root: Node3D) -> StaticBody3D:
	var typed: Array[Transform3D] = []
	for xf in xfs:
		typed.append(xf)
	match kind:
		KIND_TORII:
			return _build_torii_colliders(typed, root)
		KIND_LANTERN:
			return _build_lantern_colliders(typed, root)
		0:
			return _build_tree_colliders(typed, 0, root)
	return _build_undergrowth_colliders(typed, maxi(kind - KIND_UNDERGROWTH, 0), root)


func _build_tree_colliders(xfs: Array[Transform3D], entry_index: int, root: Node3D) -> StaticBody3D:
	var body := _new_collider("TrunkColliders%d" % entry_index, "wood")
	var shapes: Array = _tree_shapes[entry_index]
	var chest: float = _tree_chest[entry_index]
	var registered: Array = root.get_meta("trunk_entries", [])
	for xf in xfs:
		var s := xf.basis.get_scale().x
		# Same transform as the drawn tree (lean with the hill, uniform
		# scale), on the hull of the tree's own bark.
		for shape in shapes:
			_add_shape(body, shape, xf)
		registered.append(_remember_trunk(root.position + xf.origin, chest * s))
	root.set_meta("trunk_entries", registered)
	return body


func _build_torii_colliders(xfs: Array[Transform3D], root: Node3D) -> StaticBody3D:
	var body := _new_collider("ToriiColliders", "wood")
	var registered: Array = root.get_meta("trunk_entries", [])
	var half_base := _torii_mesh.get_aabb().size.x if _torii_mesh else 1.5
	for xf in xfs:
		var s := xf.basis.get_scale().x
		for shape in _torii_shapes:
			_add_shape(body, shape, xf)
		var half_span := half_base * s * 0.36
		var side := xf.basis.x.normalized()
		for sgn in [-1.0, 1.0]:
			registered.append(_remember_trunk(root.position + xf.origin + side * half_span * float(sgn), 0.1 * s))
	root.set_meta("trunk_entries", registered)
	return body


## Convex hulls of horizontal slices of a mesh (LANTERN_SLICES bands, overlapping a little).
static func _lantern_slices(mesh: Mesh) -> Array[ConvexPolygonShape3D]:
	var out: Array[ConvexPolygonShape3D] = []
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var box := mesh.get_aabb()
	var band := box.size.y / float(LANTERN_SLICES)
	for k in LANTERN_SLICES:
		var lo := box.position.y + band * float(k) - 0.02
		var hi := box.position.y + band * float(k + 1) + 0.02
		var pts := PackedVector3Array()
		for v in verts:
			if v.y >= lo and v.y <= hi:
				pts.append(v)
		if pts.size() >= 4:
			out.append(_hull(pts))
	return out


func _build_lantern_colliders(xfs: Array[Transform3D], root: Node3D) -> StaticBody3D:
	var body := _new_collider("LanternColliders", "stone")
	var registered: Array = root.get_meta("trunk_entries", [])
	for xf in xfs:
		var s := xf.basis.get_scale().x
		if not _lantern_hulls.is_empty():
			for hull in _lantern_hulls:
				_add_shape(body, hull, xf)
		else:
			for part in LANTERN_PARTS:
				var box := BoxShape3D.new()
				box.size = part[0]
				_add_shape(body, box, xf * Transform3D(Basis.IDENTITY, part[1]))
		registered.append(_remember_trunk(root.position + xf.origin, 0.24 * s))
	root.set_meta("trunk_entries", registered)
	return body


func _build_undergrowth_colliders(xfs: Array[Transform3D], u: int, root: Node3D) -> StaticBody3D:
	var body := _new_collider("RockColliders%d" % u, "stone")
	var registered: Array = root.get_meta("trunk_entries", [])
	for xf in xfs:
		var s := xf.basis.get_scale().x
		_add_shape(body, _under_shapes[u], xf)
		registered.append(_remember_trunk(root.position + xf.origin, 0.55 * s))
	root.set_meta("trunk_entries", registered)
	return body


static func _add_shape(body: StaticBody3D, shape: Shape3D, xf: Transform3D) -> void:
	if shape == null:
		return
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


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
	mm_inst.custom_aabb = AABB(Vector3(-16.0, -2.0, -16.0), Vector3(32.0, 24.0, 32.0))
	root.add_child(mm_inst)
	call_deferred("_refresh_multimesh_transforms", mm_inst, transforms)


## Deferred: the node may already be freed by a reset. Both arguments are Variant:
## a typed parameter (even Object) fails the call before the validity check runs.
func _refresh_multimesh_transforms(node: Variant, transforms: Variant) -> void:
	if not is_instance_valid(node):
		return
	var mm_inst := node as MultiMeshInstance3D
	if mm_inst == null or mm_inst.multimesh == null:
		return
	if _is_tree_node(String(mm_inst.name)) and follow:
		_refresh_tree_draw(_anchor_position())
		return
	var mm := mm_inst.multimesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])


static func _is_tree_node(node_name: String) -> bool:
	return node_name.begins_with("Trees") or node_name.begins_with("Focal")


## Growth of the trees of one chunk: 0 at the physics frame it arrived, 1 once grown.
## Chunks that are built with the player already standing by (jumps, the start) have no
## "grow_from" stamp and are full size at once.
func _tree_growth(chunk: Node3D) -> float:
	if not chunk.has_meta("grow_from"):
		return 1.0
	var t := clampf(float(Engine.get_physics_frames() - int(chunk.get_meta("grow_from"))) / float(TREE_GROW_FRAMES), 0.0, 1.0)
	return smoothstep(0.0, 1.0, t)


## True while a walked-in chunk is still growing, including the frame it reaches full size.
func _any_tree_growing() -> bool:
	for key in _chunks:
		var chunk := _chunks[key] as Node3D
		if chunk.has_meta("grow_from") and Engine.get_physics_frames() - int(chunk.get_meta("grow_from")) <= TREE_GROW_FRAMES:
			return true
	return false


## The tree transform as drawn: the planted transform scaled about its root by [param growth].
static func _grown(placed: Transform3D, growth: float) -> Transform3D:
	if growth >= 1.0:
		return placed
	return Transform3D(placed.basis * growth, placed.origin)


## Which tree crowns are drawn, by distance from the camera. Full crowns within
## lod_near_radius, far crowns from there to tree_draw_radius, and the sakura to its
## own reach. Near and far overlap by lod_fade and cross-fade in the shader, so a
## tree changes crown without a pop. Colliders stay on every tree.
func _refresh_tree_draw(origin: Vector3) -> void:
	var near_r := profile.lod_near_radius
	var half_fade := profile.lod_fade * 0.5
	# Nothing is drawn past tree_draw_radius, even a full crown inside the LOD band.
	var near_hi2 := minf((near_r + half_fade) * (near_r + half_fade), profile.tree_draw_radius * profile.tree_draw_radius)
	var far_lo2 := (near_r - half_fade) * (near_r - half_fade)
	var draw2 := profile.tree_draw_radius * profile.tree_draw_radius
	var focal2 := profile.focal_draw_radius * profile.focal_draw_radius
	# Far crowns of the whole ring, in world space, per ordinary entry.
	var far_all: Dictionary = {}
	var scene_all: Dictionary = {}
	var back_all: Dictionary = {}
	drawn_full_origins.clear()
	drawn_far_origins.clear()
	drawn_scene_origins.clear()
	drawn_full_growth.clear()
	drawn_far_growth.clear()
	drawn_scene_growth.clear()
	for key in _chunks:
		var chunk := _chunks[key] as Node3D
		var base := chunk.position
		var growth := _tree_growth(chunk)
		for child in chunk.get_children():
			if not (child is MultiMeshInstance3D) or not _is_tree_node(String(child.name)):
				continue
			var inst := child as MultiMeshInstance3D
			if inst.multimesh == null:
				continue
			var label := String(inst.name)
			var all: Array = chunk.get_meta("xfs_" + label, [])
			var mm := inst.multimesh
			var near: Array[Transform3D] = []
			var focal := label.begins_with("Focal")
			# A scene crown (D5 redwood) is one full-detail mesh out to tree_draw_radius: no LOD band, no far copy.
			var full_only := not focal and profile.trees[int(label.trim_prefix("Trees"))].crown == TreeEntry.Crown.SCENE
			var full_hi2 := draw2 if full_only else near_hi2
			for xf in all:
				var placed := xf as Transform3D
				var dx := base.x + placed.origin.x - origin.x
				var dz := base.z + placed.origin.z - origin.z
				var d2 := dx * dx + dz * dz
				var drawn := _grown(placed, growth)
				if focal and d2 <= focal2 or not focal and d2 <= full_hi2:
					near.append(drawn)
					if not focal:
						drawn_full_origins.append(base + placed.origin)
						drawn_full_growth.append(growth)
				if not focal and not full_only and d2 >= far_lo2 and d2 <= draw2:
					var e := int(label.trim_prefix("Trees"))
					if not far_all.has(e):
						far_all[e] = [] as Array[Transform3D]
					(far_all[e] as Array[Transform3D]).append(Transform3D(drawn.basis, placed.origin + base))
					drawn_far_origins.append(base + placed.origin)
					drawn_far_growth.append(growth)
			# instance_count is what the headless perf probe counts; it is the only
			# draw limit on a MultiMesh (the buffer is written in full above).
			mm.instance_count = near.size()
			for i in near.size():
				mm.set_instance_transform(i, near[i])
		# Back layer (N5): far crowns between back_near and the draw radius, no near copy, no collider.
		for bkey in _back_keys():
			var e := bkey / 10
			for xf in chunk.get_meta("xfs_Back%d" % bkey, []):
				var placed := xf as Transform3D
				var bx := base.x + placed.origin.x - origin.x
				var bz := base.z + placed.origin.z - origin.z
				var bd2 := bx * bx + bz * bz
				if bd2 <= draw2 and bd2 >= _back_near_of(e) * _back_near_of(e):
					if not back_all.has(bkey):
						back_all[bkey] = [] as Array[Transform3D]
					(back_all[bkey] as Array[Transform3D]).append(Transform3D(_grown(placed, growth).basis, placed.origin + base))
		# Scene crowns (D5 redwood): full detail to tree_draw_radius, one MultiMesh for the whole ring.
		for e in profile.trees.size():
			if profile.trees[e].is_focal() or profile.trees[e].crown != TreeEntry.Crown.SCENE:
				continue
			for xf in chunk.get_meta("xfs_Trees%d" % e, []):
				var placed := xf as Transform3D
				var sx := base.x + placed.origin.x - origin.x
				var sz := base.z + placed.origin.z - origin.z
				if sx * sx + sz * sz <= draw2:
					if not scene_all.has(e):
						scene_all[e] = [] as Array[Transform3D]
					(scene_all[e] as Array[Transform3D]).append(Transform3D(_grown(placed, growth).basis, placed.origin + base))
					drawn_scene_origins.append(base + placed.origin)
					drawn_scene_growth.append(growth)
	for key in _back_keys():
		var back_list: Array = back_all.get(key, [])
		var back_node := _back_tree_node(key)
		back_node.multimesh.instance_count = back_list.size()
		for i in back_list.size():
			back_node.multimesh.set_instance_transform(i, back_list[i])
	for e in profile.trees.size():
		if profile.trees[e].is_focal() or profile.trees[e].crown == TreeEntry.Crown.SCENE or profile.trees[e].back_layer:
			continue
		var far_list: Array = far_all.get(e, [])
		var node := _far_tree_node(e)
		node.multimesh.instance_count = far_list.size()
		for i in far_list.size():
			node.multimesh.set_instance_transform(i, far_list[i])
	for e in profile.trees.size():
		if profile.trees[e].is_focal() or profile.trees[e].crown != TreeEntry.Crown.SCENE:
			continue
		var scene_list: Array = scene_all.get(e, [])
		var scene_node := _scene_tree_node(e)
		scene_node.multimesh.instance_count = scene_list.size()
		for i in scene_list.size():
			scene_node.multimesh.set_instance_transform(i, scene_list[i])


## Scene crowns of one entry, drawn across the whole ring in one MultiMesh (created on first use).
func _scene_tree_node(e: int) -> MultiMeshInstance3D:
	if _scene_tree_nodes.has(e):
		return _scene_tree_nodes[e]
	var inst := MultiMeshInstance3D.new()
	inst.name = "SceneTrees%d" % e
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tree_meshes[e]
	mm.instance_count = 0
	inst.multimesh = mm
	inst.material_override = _tree_mats[e]
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_set_view_range(inst)
	inst.custom_aabb = AABB(Vector3(-400.0, -2.0, -400.0), Vector3(800.0, 24.0, 800.0))
	add_child(inst)
	_scene_tree_nodes[e] = inst
	return inst


## The back-layer MultiMesh of one kind (N5): one node for the whole ring, far crowns only.
func _back_tree_node(key: int) -> MultiMeshInstance3D:
	if _back_tree_nodes.has(key):
		return _back_tree_nodes[key]
	var inst := MultiMeshInstance3D.new()
	inst.name = "BackTrees%d" % key
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _back_meshes[key]
	mm.instance_count = 0
	inst.multimesh = mm
	inst.material_override = _back_mats[key / 10]
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_set_view_range(inst)
	inst.custom_aabb = AABB(Vector3(-400.0, -2.0, -400.0), Vector3(800.0, 24.0, 800.0))
	add_child(inst)
	_back_tree_nodes[key] = inst
	return inst


## A far silhouette (N5 back layer): a tapered trunk and three crown tiers, about 40 triangles. Every
## vertex carries the leaf UV (UV.y 2), so the cut-out keeps it whole and it takes the dark foliage
## colour: a dark tree-line against the mist, as in the concept.
static func _build_back_silhouette(variant: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var leaf := Vector2(0.5, 2.0)
	# Variants: 0 three wide tiers (cedar), 1 four narrow tiers (tall pine), 2 two tiers with a flat top.
	var tiers := 3
	var tier_r := 2.9
	var tier_step := 2.1
	var tier_rise := 3.4
	if variant == 1:
		tiers = 4
		tier_r = 2.2
		tier_step = 1.6
		tier_rise = 2.8
	elif variant == 2:
		tiers = 2
		tier_r = 3.2
		tier_step = 2.6
		tier_rise = 2.4
	# Trunk: an open column, 8 sides, from the ground to the first tier.
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var r := 0.32
		var p0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		var q0 := p0 + Vector3(0.0, 3.4, 0.0)
		var q1 := p1 + Vector3(0.0, 3.4, 0.0)
		st.set_uv(leaf); st.add_vertex(p0)
		st.set_uv(leaf); st.add_vertex(q0)
		st.set_uv(leaf); st.add_vertex(q1)
		st.set_uv(leaf); st.add_vertex(p0)
		st.set_uv(leaf); st.add_vertex(q1)
		st.set_uv(leaf); st.add_vertex(p1)
	# Crown tiers: cones of 8 sides, apex up.
	for tier in tiers:
		var base_y := 2.6 + tier_step * float(tier)
		var radius := tier_r - 0.75 * float(tier)
		var apex := Vector3(0.0, base_y + tier_rise, 0.0)
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var b0 := Vector3(cos(a0) * radius, base_y, sin(a0) * radius)
			var b1 := Vector3(cos(a1) * radius, base_y, sin(a1) * radius)
			st.set_uv(leaf); st.add_vertex(b0)
			st.set_uv(leaf); st.add_vertex(b1)
			st.set_uv(leaf); st.add_vertex(apex)
	st.generate_normals()
	return st.commit()


## The far-crown MultiMesh of one ordinary entry, created on first use under the forest.
func _far_tree_node(e: int) -> MultiMeshInstance3D:
	if _far_tree_nodes.has(e):
		return _far_tree_nodes[e]
	var inst := MultiMeshInstance3D.new()
	inst.name = "FarTrees%d" % e
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tree_far_meshes[e]
	mm.instance_count = 0
	inst.multimesh = mm
	inst.material_override = _tree_far_mats[e]
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_set_view_range(inst)
	inst.custom_aabb = AABB(Vector3(-400.0, -2.0, -400.0), Vector3(800.0, 24.0, 800.0))
	add_child(inst)
	_far_tree_nodes[e] = inst
	return inst


## Senbon rows: short lines of gates in chunks where the corridor noise runs high.
## Senbon rows of one chunk (the corridor noise runs high there): Vector4(x, z, yaw, scale) per gate,
## world xz. Part of the chunk's gate plan (see _torii_plan), so trunks and props keep out of them too.
func _senbon_plan(coord: Vector2i) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var corridor_val := _corridor_noise.get_noise_2d(float(coord.x) * CORRIDOR_SCALE, float(coord.y) * CORRIDOR_SCALE)
	if corridor_val < profile.torii_row_threshold:
		return out
	var axis_x := corridor_val > SENBON_AXIS_THRESHOLD
	var size := _chunk_size
	var origin := Vector2(float(coord.x), float(coord.y)) * size
	var span := profile.torii_row_max - profile.torii_row_min + 1
	var gate_count := profile.torii_row_min + int((_hash01(_hash_coord(coord, 9, 0), 0) * float(span)))
	var spacing := profile.torii_row_spacing
	var start := -spacing * float(gate_count - 1) * 0.5
	for g in gate_count:
		var along := start + float(g) * spacing
		var lx := along if axis_x else -size * 0.15
		var lz := -size * 0.15 if axis_x else along
		var wx := origin.x + lx
		var wz := origin.y + lz
		if _in_clearing(wx, wz, 0.35):
			continue
		# Corridor gates keep the same trunk clearance as scattered ones.
		var blocked := false
		for ox in range(-1, 2):
			for oz in range(-1, 2):
				var packed: Dictionary = _tree_spots(coord + Vector2i(ox, oz))
				for ts in packed.get("spots", []):
					var tspot: Vector4 = ts
					if Vector2(wx - tspot.x, wz - tspot.y).length() < profile.torii_tree_clearance:
						blocked = true
						break
				if blocked:
					break
			if blocked:
				break
		if blocked:
			continue
		var yaw := PI * 0.5 if axis_x else 0.0
		out.append(Vector4(wx, wz, yaw, torii_scale_for_height(4.4 + float(g) * 0.12)))
	return out


## Ground mesh of a chunk. Vertex colour R is the path weight (1 on the
## trodden centre line, 0 off it); the ground shader lays the stone layer there.
func _build_terrain_mesh(coord: Vector2i) -> ArrayMesh:
	var build := TerrainBuild.new(self, coord)
	build.sample(build.res * build.res)
	return build.mesh()


## The terrain of one chunk, sampled in slices: the heights are one query per
## lattice point (the costly part) and the quads follow. Walking spreads a chunk
## over a few frames; setup builds it in one go.
class TerrainBuild extends RefCounted:
	var res := 0
	var lattice_step := 0.0
	var size := 0.0
	var heights := PackedFloat32Array()
	var field := PackedFloat32Array()
	var half_width := 0.0
	var height_row := 0
	var quad_row := 0
	var _forest: ForestWorld
	var _lattice_x := 0
	var _lattice_z := 0
	var _st := SurfaceTool.new()

	func _init(forest: ForestWorld, coord: Vector2i) -> void:
		_forest = forest
		size = forest._chunk_size
		res = forest._terrain_res
		lattice_step = size / float(res - 1)
		field = forest._path_field(coord)
		half_width = forest._path_half_width()
		heights.resize(res * res)
		# The chunk's corner sits on the global lattice (res is odd, so half a chunk is a whole number of steps).
		_lattice_x = coord.x * (res - 1) - (res - 1) / 2
		_lattice_z = coord.y * (res - 1) - (res - 1) / 2
		_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	## Samples up to [param budget] rows (lattice rows, then quad rows). True when done.
	func sample(budget: int) -> bool:
		while height_row < res and budget > 0:
			# Each lattice height is sampled once; a quad's corners are shared with its
			# neighbours, so sampling per quad did the same work four times over.
			for i in res:
				heights[height_row * res + i] = _forest._lattice_height(_lattice_x + i, _lattice_z + height_row)
			height_row += 1
			budget -= 1
		if height_row < res:
			return false
		while quad_row < res - 1 and budget > 0:
			_quad_row(quad_row)
			quad_row += 1
			budget -= 1
		return quad_row >= res - 1

	func _quad_row(z: int) -> void:
		for x in res - 1:
			var x0 := -size * 0.5 + float(x) * lattice_step
			var z0 := -size * 0.5 + float(z) * lattice_step
			var x1 := x0 + lattice_step
			var z1 := z0 + lattice_step
			var p00 := Vector3(x0, heights[z * res + x], z0)
			var p10 := Vector3(x1, heights[z * res + x + 1], z0)
			var p01 := Vector3(x0, heights[(z + 1) * res + x], z1)
			var p11 := Vector3(x1, heights[(z + 1) * res + x + 1], z1)
			var c00 := ForestWorld._path_colour(field, z * res + x, half_width)
			var c10 := ForestWorld._path_colour(field, z * res + x + 1, half_width)
			var c01 := ForestWorld._path_colour(field, (z + 1) * res + x, half_width)
			var c11 := ForestWorld._path_colour(field, (z + 1) * res + x + 1, half_width)
			ForestWorld._add_tri(_st, p00, p10, p11, c00, c10, c11)
			ForestWorld._add_tri(_st, p00, p11, p01, c00, c11, c01)

	## The finished mesh (call once [method sample] has returned true).
	func mesh() -> ArrayMesh:
		# Shared vertices, then one normal per point, so a root reads as a mound
		# instead of a faceted plate.
		_st.index()
		_st.generate_normals()
		return _st.commit()


## The ground material of one chunk (N5): a copy of the shared one, with this chunk's path centre
## lines, so the trail edge is drawn per pixel from the true curve (see forest_ground.gdshader).
func _chunk_ground_material(coord: Vector2i) -> ShaderMaterial:
	var mat := _ground_mat.duplicate() as ShaderMaterial
	var segs := PackedVector4Array()
	if paths != null:
		var size := _chunk_size
		var rect := Rect2(Vector2(coord) * size - Vector2(size, size) * 0.5, Vector2(size, size)).grow(4.0)
		segs = paths.smooth_segments_in_rect(rect, PATH_SIMPLIFY_TOL)
		if segs.size() > PATH_SEGMENTS_MAX:
			segs.resize(PATH_SEGMENTS_MAX)
	mat.set_shader_parameter("path_seg_count", segs.size())
	mat.set_shader_parameter("path_segs", segs)
	return mat


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
	return Vector2(wx, wz).length() < _prop_clearing + margin


## Instance scale that makes the shared gate mesh [param height] metres tall.
func torii_scale_for_height(height: float) -> float:
	var h := _torii_mesh.get_aabb().size.y if _torii_mesh else 1.0
	return height / maxf(h, 0.1)


## World position of the generated sakura focal tree nearest to [param from] (INF if none).
func nearest_sakura_position(from: Vector3) -> Vector3:
	var best := Vector3.INF
	for key in _chunks:
		var chunk := _chunks[key] as Node3D
		var xfs: Array = chunk.get_meta("sakura_tree_local_xfs", [])
		for xf in xfs:
			var p := chunk.global_transform * (xf as Transform3D).origin
			if best == Vector3.INF or p.distance_to(from) < best.distance_to(from):
				best = p
	return best


## Distance the loaded ring guarantees around the player (profile.loaded_range()).
## The fog must end inside it (fog_end), so no chunk edge is ever seen.
func loaded_range() -> float:
	return profile.loaded_range()


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


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca := Color.BLACK, cb := Color.BLACK, cc := Color.BLACK) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.add_vertex(c)


## Path weight of one terrain vertex as a colour (R): full on the centre line,
## fading over half a width to the shoulders.
static func _path_colour(field: PackedFloat32Array, idx: int, half_width: float) -> Color:
	if field.is_empty():
		return Color.BLACK
	var d := field[idx]
	# R: the trail weight (1 on the trail), kept for the tests and the old look.
	# G: the distance to the path centre line, in PATH_ENCODE_RANGE metres. The shader
	# draws the edge from G, so the edge is a smooth curve, not the 1 m lattice's steps.
	return Color(1.0 - smoothstep(half_width * 0.75, half_width * 1.2, d), clampf(d / PATH_ENCODE_RANGE, 0.0, 1.0), 0.0, 1.0)


func _build_materials() -> void:
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GROUND_SHADER
	_ground_mat.set_shader_parameter("fill", 0.0)
	_ground_mat.set_shader_parameter("cavity_ao", profile.ground_cavity_ao)
	_ground_mat.set_shader_parameter("ambient_fill", profile.ground_fill)
	_ground_mat.set_shader_parameter("normal_strength", profile.ground_normal_strength)
	# Damp, not mirror-wet: wet normals over 1K scans sparkle white in VR.
	_ground_mat.set_shader_parameter("wetness", profile.ground_wetness)
	_ground_mat.set_shader_parameter("roughness_wet", profile.ground_roughness_wet)
	for layer in GROUND_LAYERS:
		var dir := "res://assets/textures/forest_ground/%s/%s" % [GROUND_LAYERS[layer], GROUND_LAYERS[layer]]
		_ground_mat.set_shader_parameter(layer + "_albedo", load(dir + "_diff_1k.jpg"))
		_ground_mat.set_shader_parameter(layer + "_normal", load(dir + "_nor_gl_1k.jpg"))
	_ground_mat.set_shader_parameter("fog_fade_start", profile.ground_fade_start)
	# Footpath material: its own texture and warm tint (see forest_ground.gdshader).
	# Pale gravel (Poly Haven rocky_trail): lighter than the duff either side of it.
	_ground_mat.set_shader_parameter("path_albedo", load("res://assets/textures/forest_ground/rocky_trail/rocky_trail_diff_1k.jpg"))
	_ground_mat.set_shader_parameter("path_normal", load("res://assets/textures/forest_ground/rocky_trail/rocky_trail_nor_gl_1k.jpg"))
	# Moss on slopes and damp patches (D5, Moss002 CC0), before the grass and soil share the rest.
	_ground_mat.set_shader_parameter("moss_albedo", MOSS_ALBEDO)
	_ground_mat.set_shader_parameter("moss_normal", MOSS_NORMAL)
	_ground_mat.set_shader_parameter("path_tint", profile.path_tint)
	_ground_mat.set_shader_parameter("path_gain", profile.path_gain)
	# The edge is drawn from the distance in the vertex colour G (see _path_colour).
	_ground_mat.set_shader_parameter("path_half", _path_half_width())
	_ground_mat.set_shader_parameter("path_encode", PATH_ENCODE_RANGE)
	_ground_mat.set_shader_parameter("fog_fade_end", profile.ground_fade_end)
	_ground_mat.set_shader_parameter("distance_haze_start", profile.distance_haze_start)
	_ground_mat.set_shader_parameter("distance_haze_end", profile.distance_haze_end)
	_ground_mat.set_shader_parameter("distance_haze_max", profile.distance_haze_max)
	_ground_mat.set_shader_parameter("low_mist_amount", profile.low_mist_amount)
	_ground_mat.set_shader_parameter("low_mist_height", profile.low_mist_height)
	_ground_mat.set_shader_parameter("haze_far_color", profile.haze_far_color)

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
	# Cyan glow of the gates (profile torii_glow_*): the emission tint of the gate.
	_torii_mat.set_shader_parameter("emission_tint", profile.torii_glow_color * profile.torii_glow_strength)

	_lantern_mat = ShaderMaterial.new()
	_lantern_mat.shader = WET_SHADER
	# A baked scan carries its own colour (atlas in the albedo, see tools/prep_forest_assets.py).
	var lantern_albedo := _scene_albedo(profile.lantern_scene)
	_lantern_mat.set_shader_parameter("base_color", Color.WHITE if lantern_albedo != null else Color(0.42, 0.4, 0.36))
	_lantern_mat.set_shader_parameter("albedo_texture", lantern_albedo)
	_lantern_mat.set_shader_parameter("roughness_dry", 0.88)
	_lantern_mat.set_shader_parameter("roughness_wet", 0.75)
	_lantern_mat.set_shader_parameter("wetness", 0.25)
	_lantern_mat.set_shader_parameter("waterline_y", -10.0)
	_lantern_mat.set_shader_parameter("fill", 0.3)
	_lantern_mat.set_shader_parameter("specular_scale", 0.0)
	_lantern_mat.set_shader_parameter("fog_fill", 0.2)
	# Warm glow of the paper (N6): the tint multiplies the albedo, so only the paper
	# (yellow in the atlas) lights up; the stone takes a dim warm share. No light source.
	_lantern_mat.set_shader_parameter("emission_tint", Color(0.9, 0.6, 0.26))
	# Only the paper (bright, saturated in the atlas) glows; the stone and the dark wood stay
	# grey and unlit (N6). Moss on the up-facing caps of the stone.
	_lantern_mat.set_shader_parameter("paper_gate", 1.0)
	_lantern_mat.set_shader_parameter("moss_amount", 0.5)
	_lantern_mat.set_shader_parameter("moss_color", Color(0.24, 0.38, 0.14))
	# A rim of the sky and fog on the stone's edges: it reads as stone, not as a black pillar.
	_lantern_mat.set_shader_parameter("fog_rim", 1.0)
	_lantern_mat.set_shader_parameter("fill", 0.6)
	_lantern_mat.set_shader_parameter("fog_fill", 0.5)
	_lantern_mat.set_shader_parameter("sky_lit", 0.8)


## No per-node visibility range: Godot measures it to the node origin, i.e. a
## chunk's centre, which culled every chunk but the one under the player
## (and all its trees). Depth fog (the profile's fog_end) hides chunk edges.
func _set_view_range(inst: GeometryInstance3D) -> void:
	inst.visibility_range_begin = 0.0
	inst.visibility_range_end = 0.0


## Meshes and collision hulls that depend only on their scene and crown, not on
## the profile's numbers: built once per process and shared by every forest
## (the crown rebuild and the hulls are the slow part of a forest build).
static var _built: Dictionary = {}


static func _built_once(key: String, build: Callable) -> Variant:
	if not _built.has(key):
		_built[key] = build.call()
	return _built[key]


static func _scene_key(scene: PackedScene) -> String:
	return scene.resource_path if scene != null and scene.resource_path != "" else "procedural"


func _build_meshes() -> void:
	_shaft_mesh = QuadMesh.new()
	_shaft_mesh.size = Vector2(1.0, 1.0)
	_shaft_mesh.center_offset = Vector3(0.0, 0.5, 0.0)
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = SHAFT_SHADER
	# Same grey as the fog, dim. A blue-white beam reads as a plastic tube.
	_shaft_mat.set_shader_parameter("shaft_color", Color(0.62, 0.64, 0.66))
	_shaft_mat.set_shader_parameter("intensity", profile.shaft_intensity)
	_tree_meshes.clear()
	_tree_mats.clear()
	_crown_discs.clear()
	_crown_reach = 0.0
	_tree_far_meshes.clear()
	_tree_far_mats.clear()
	_back_mats.clear()
	_back_meshes.clear()
	for node in _back_tree_nodes.values():
		(node as Node).free()
	_back_tree_nodes.clear()
	for node in _far_tree_nodes.values():
		(node as Node).free()
	_far_tree_nodes.clear()
	for node in _scene_tree_nodes.values():
		(node as Node).free()
	_scene_tree_nodes.clear()
	_tree_shapes.clear()
	_tree_chest.clear()
	for entry in profile.trees:
		var key := "tree|%s|%d" % [_scene_key(entry.scene), entry.crown]
		var built := _built_once(key, _build_tree_parts.bind(entry)) as Dictionary
		_tree_meshes.append(built.mesh)
		_crown_discs.append(built.discs)
		for disc in built.discs:
			var d: Vector4 = disc
			_crown_reach = maxf(_crown_reach, d.w * entry.scale_max * entry.focal_scale_boost)
		# A scene crown (D5 redwood) brings its own atlas, with a higher cut level for its card background.
		var own_albedo: Texture2D = _scene_albedo(entry.scene) if entry.crown == TreeEntry.Crown.SCENE else null
		_tree_mats.append(_sakura_material(entry) if entry.crown == TreeEntry.Crown.SAKURA else _tree_material(0.0, own_albedo))
		var far_key := "tree_far|%s|%d" % [_scene_key(entry.scene), entry.crown]
		_tree_far_meshes.append(_built_once(far_key, _build_far_tree_mesh.bind(entry)) as Mesh)
		_tree_far_mats.append(_tree_material(1.0, own_albedo))
		var e := _back_mats.size()
		_back_mats.append(_back_material(own_albedo, entry) if entry.back_layer else null)
		for v in BACK_VARIANTS:
			if entry.back_layer:
				_back_meshes[back_key(e, v)] = _built_once("back_silhouette_%d" % v, _build_back_silhouette.bind(v)) as Mesh
		_tree_shapes.append(built.hulls)
		_tree_chest.append(float(built.chest))
	if not _tree_chest.is_empty():
		_trunk_chest_radius = _tree_chest[0]
	_torii_mesh = _built_once("torii|%s" % _scene_key(profile.torii_scene), _build_torii_mesh) as Mesh
	_torii_shapes = _built_once("torii_hulls|%s" % _scene_key(profile.torii_scene), _torii_hulls) as Array[ConvexPolygonShape3D]
	_lantern_mesh = _built_once("lantern|%s" % _scene_key(profile.lantern_scene), _build_lantern_mesh) as Mesh
	# A scanned lantern collides as a stack of convex slices (the procedural boxes do not match
	# its shape, and one hull over the pagoda roof would stand well off the drawn lantern).
	_lantern_hulls = _lantern_slices(_lantern_mesh) if profile.lantern_scene != null else []
	_under_meshes.clear()
	_under_mats.clear()
	_under_shapes.clear()
	for entry in profile.undergrowth:
		var key := "under|%s|%d" % [_scene_key(entry.scene), entry.source]
		var built := _built_once(key, _build_undergrowth_parts.bind(entry)) as Dictionary
		_under_meshes.append(built.mesh)
		_under_mats.append(_card_material(entry) if entry.cutout else _rock_material())
		_under_shapes.append(built.shape)


## Mesh, trunk hulls and chest radius of one tree kind.
func _build_tree_parts(entry: TreeEntry) -> Dictionary:
	var mesh := _tree_mesh_for(entry)
	var chest: Array = []
	var hulls := _trunk_hulls(mesh, chest)
	return {"mesh": mesh, "hulls": hulls, "chest": float(chest[0]), "discs": _crown_discs_for(entry, mesh)}


func _build_undergrowth_parts(entry: UndergrowthEntry) -> Dictionary:
	var mesh := _undergrowth_mesh_for(entry)
	return {"mesh": mesh, "shape": _hull(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])}


## The ordinary tree material. [param far] 0 is the full crown (fades out past the
## LOD band), 1 is the far crown (fades in). Both use the band from the profile.
func _tree_material(far: float, own_albedo: Texture2D = null) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TREE_DIFFUSE
	mat.set_shader_parameter("albedo_texture", TREE_ALBEDO if own_albedo == null else own_albedo)
	mat.set_shader_parameter("normal_texture", TREE_NORMAL)
	if own_albedo != null:
		mat.set_shader_parameter("cut_level", 0.08)
		mat.set_shader_parameter("normal_depth", 0.0)
	mat.set_shader_parameter("lod_far", far)
	var half := profile.lod_fade * 0.5
	# A scene crown has no LOD dissolve: it stays solid to tree_draw_radius (no far copy is built).
	var band := Vector2(profile.lod_near_radius - half, profile.lod_near_radius + half)
	if own_albedo != null:
		band = Vector2(1.0e5, 1.0e5 + 1.0)
	mat.set_shader_parameter("lod_band", band)
	mat.set_shader_parameter("draw_fade", _draw_fade(profile.tree_draw_radius))
	_set_atmosphere(mat)
	return mat


## Distance fade of a kind at its draw edge (N5): the crown dissolves over the last DRAW_FADE_BAND
## metres in front of [param radius], so it leaves the ring by dithering, never by popping.
func _draw_fade(radius: float) -> Vector2:
	return Vector2(radius - DRAW_FADE_BAND, radius)


## Height and distance haze from the profile (N4), shared by every forest material.
func _set_atmosphere(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("height_haze_low", profile.crown_haze_low)
	mat.set_shader_parameter("height_haze_high", profile.crown_haze_high)
	mat.set_shader_parameter("height_haze", profile.crown_haze_amount)
	mat.set_shader_parameter("distance_haze_start", profile.distance_haze_start)
	mat.set_shader_parameter("distance_haze_end", profile.distance_haze_end)
	mat.set_shader_parameter("distance_haze_max", profile.distance_haze_max)
	mat.set_shader_parameter("low_mist_amount", profile.low_mist_amount)
	mat.set_shader_parameter("low_mist_height", profile.low_mist_height)
	mat.set_shader_parameter("haze_far_color", profile.haze_far_color)


## Leaf cards with their own alpha (N5 ferns): the cut-out foliage shader on the baked RGBA atlas.
## No LOD band (one card, drawn as it is), and the same distance fade as the trees.
func _card_material(entry: UndergrowthEntry) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TREE_DIFFUSE
	mat.set_shader_parameter("albedo_texture", _scene_albedo(entry.scene))
	mat.set_shader_parameter("normal_texture", TREE_NORMAL)
	mat.set_shader_parameter("alpha_from_texture", true)
	mat.set_shader_parameter("cut_level", 0.5)
	mat.set_shader_parameter("normal_depth", 0.0)
	mat.set_shader_parameter("lod_far", 0.0)
	mat.set_shader_parameter("lod_band", Vector2(1.0e5, 1.0e5 + 1.0))
	mat.set_shader_parameter("draw_fade", Vector2(entry.fade_start, entry.fade_end))
	_set_atmosphere(mat)
	return mat


func _rock_material() -> ShaderMaterial:
	if _rock_material_cache == null:
		_rock_material_cache = ShaderMaterial.new()
		_rock_material_cache.shader = WET_SHADER
		_rock_material_cache.set_shader_parameter("base_color", Color(0.16, 0.16, 0.17))
		_rock_material_cache.set_shader_parameter("roughness_dry", 0.92)
		_rock_material_cache.set_shader_parameter("roughness_wet", 0.8)
		_rock_material_cache.set_shader_parameter("wetness", 0.22)
		_rock_material_cache.set_shader_parameter("waterline_y", -10.0)
		_rock_material_cache.set_shader_parameter("fill", 0.28)
		_rock_material_cache.set_shader_parameter("specular_scale", 0.0)
		_rock_material_cache.set_shader_parameter("fog_fill", 0.18)
	return _rock_material_cache


## Back layer material (N5): the far crown, dissolving in from back_near to back_near + back_fade.
## Its distance haze is a share of the forest's (BACK_HAZE_SHARE): the wall reads as dark trunks against
## the mist, as in the concept, instead of melting into it; the near forest keeps the full haze.
func _back_material(own_albedo: Texture2D, entry: TreeEntry) -> ShaderMaterial:
	var mat := _tree_material(1.0, own_albedo)
	var near := _back_near_of_entry(entry)
	mat.set_shader_parameter("lod_band", Vector2(near, near + profile.back_fade))
	mat.set_shader_parameter("distance_haze_max", profile.distance_haze_max * BACK_HAZE_SHARE)
	mat.set_shader_parameter("albedo_texture", TREE_ALBEDO)
	return mat


## Neon sakura material from the entry's colours (GDD §9: over-the-top neon pink).
func _sakura_material(entry: TreeEntry) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SAKURA_TREE_SHADER
	mat.set_shader_parameter("albedo_texture", TREE_ALBEDO)
	mat.set_shader_parameter("normal_texture", TREE_NORMAL)
	mat.set_shader_parameter("bark_tint", Color(0.12, 0.09, 0.08))
	mat.set_shader_parameter("deep_plum_color", Color(0.11, 0.02, 0.07))
	mat.set_shader_parameter("mid_petal_color", entry.petal_color)
	mat.set_shader_parameter("neon_pink_accent", entry.neon_color)
	mat.set_shader_parameter("rim_glow_color", entry.rim_color)
	mat.set_shader_parameter("stamen_color", Color(1.0, 0.88, 0.95))
	mat.set_shader_parameter("emission_strength", entry.emission)
	mat.set_shader_parameter("neon_sparsity", entry.neon_sparsity)
	mat.set_shader_parameter("draw_fade", _draw_fade(profile.focal_draw_radius))
	return mat


## Far crown of one entry (the LOD beyond lod_near_radius): the same crown
## centres as the full one, as coarse blobs, on a plain trunk. About 400
## triangles against the scan's ~2 000, so a forest of them stays in budget to
## tree_draw_radius. Sakura and scanned SCENE crowns keep their own mesh (see D5).
func _build_far_tree_mesh(entry: TreeEntry) -> Mesh:
	if entry.crown != TreeEntry.Crown.CEDAR:
		return _tree_mesh_for(entry)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_far_trunk(st, 0.8)
	var noise := FastNoiseLite.new()
	noise.seed = 0x4C454146
	noise.frequency = 0.9
	for c in CROWN_CLUMPS.size():
		_add_foliage_clump(st, CROWN_CLUMPS[c][0], float(CROWN_CLUMPS[c][1]) * CROWN_OVERSIZE, noise, c, 5, 2)
	st.generate_normals()
	return st.commit()


## A six-sided trunk from the ground to the fork, bark UVs (the tree shader reads
## UV for bark, leaf and root). [param chest] is the bark radius at chest height.
static func _add_far_trunk(st: SurfaceTool, chest: float) -> void:
	var bark := Vector2(0.2, 0.8)
	var rings := [[0.0, chest * 1.25], [7.3, chest * 0.7]]
	for k in 6:
		var a0 := TAU * float(k) / 6.0
		var a1 := TAU * float(k + 1) / 6.0
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var b0: Vector3 = d0 * float(rings[0][1]) + Vector3(0.0, float(rings[0][0]), 0.0)
		var b1: Vector3 = d1 * float(rings[0][1]) + Vector3(0.0, float(rings[0][0]), 0.0)
		var t0: Vector3 = d0 * float(rings[1][1]) + Vector3(0.0, float(rings[1][0]), 0.0)
		var t1: Vector3 = d1 * float(rings[1][1]) + Vector3(0.0, float(rings[1][0]), 0.0)
		for p in [b0, b1, t1, b0, t1, t0]:
			st.set_uv(bark)
			st.add_vertex(p)


## The tree mesh for one entry: its scene with a rebuilt crown (CEDAR,
## SAKURA) or as is (SCENE). Without a scene, the procedural cedar.
func _tree_mesh_for(entry: TreeEntry) -> Mesh:
	var raw: ArrayMesh = null
	if entry.has_scene():
		raw = _merge_scene_meshes(entry.scene, 1.0)
	if raw == null:
		return _build_tree_mesh()
	match entry.crown:
		TreeEntry.Crown.SAKURA:
			return _append_root_flare(_rebuild_crown(raw, SAKURA_CLUMPS, 4.2))
		TreeEntry.Crown.SCENE:
			return raw
	return _append_root_flare(_rebuild_crown(raw, CROWN_CLUMPS, 7.3))


func _undergrowth_mesh_for(entry: UndergrowthEntry) -> Mesh:
	if entry.source == UndergrowthEntry.Source.SCENE and entry.scene != null:
		var merged := _merge_scene_meshes(entry.scene, 1.0)
		if merged != null:
			return merged
	return _extract_rock_mesh()


## Trunk hulls of a tree mesh, sliced on the bark (see TRUNK_HULL_TOP). A mesh
## without bark UVs (imported assets) gets a plain column hull instead, so
## the trunk still stops the body. Also returns the chest radius via [param chest].
func _trunk_hulls(mesh: Mesh, chest: Array) -> Array:
	var hulls: Array = []
	var radii: Array[float] = []
	var a := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tris := PackedVector3Array()
	var n := idx.size() if not idx.is_empty() else v.size()
	for t in range(0, n - 2, 3):
		var i0 := idx[t] if not idx.is_empty() else t
		var i1 := idx[t + 1] if not idx.is_empty() else t + 1
		var i2 := idx[t + 2] if not idx.is_empty() else t + 2
		# Bark only: not the welded roots (UV.x > 1.5) or foliage
		# (UV.y > 1.5), and only the trunk column below the boughs.
		var uv_c := (uv[i0] + uv[i1] + uv[i2]) / 3.0 if not uv.is_empty() else Vector2.ZERO
		if uv_c.x > 1.5 or uv_c.y > 1.5:
			continue
		var c := (v[i0] + v[i1] + v[i2]) / 3.0
		if Vector2(c.x, c.z).length() > 1.25 or c.y > TRUNK_HULL_TOP + 0.3:
			continue
		tris.append_array([v[i0], v[i1], v[i2]])
		if c.y > 0.9 and c.y < 2.0:
			radii.append(Vector2(c.x, c.z).length())
	for pts in _slab_points(tris, 0.0, TRUNK_HULL_TOP, TRUNK_SLICE):
		hulls.append(_hull(pts))
	if radii.is_empty():
		# No bark on this mesh: a column of the mesh's own footprint.
		var column := PackedVector3Array()
		for k in 8:
			var ang := TAU * float(k) / 8.0
			column.append(Vector3(cos(ang) * 0.5, 0.0, sin(ang) * 0.5))
			column.append(Vector3(cos(ang) * 0.5, 4.4, sin(ang) * 0.5))
		hulls.append(_hull(column))
		chest.clear()
		chest.append(0.5)
	else:
		radii.sort()
		chest.clear()
		chest.append(radii[int(radii.size() * 0.9)])
	return hulls


## Torii frame hulls: left and right pillars plus the beam block.
func _torii_hulls() -> Array[ConvexPolygonShape3D]:
	var out: Array[ConvexPolygonShape3D] = []
	if _torii_mesh == null:
		return out
	var ta := _torii_mesh.surface_get_arrays(0)
	var tv: PackedVector3Array = ta[Mesh.ARRAY_VERTEX]
	var ti: PackedInt32Array = ta[Mesh.ARRAY_INDEX] if ta[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var box := _torii_mesh.get_aabb()
	# The tie beam (nuki) starts ~60% up; below it the frame is just the
	# two pillars, above it one block of beams.
	var beam_y := box.position.y + box.size.y * 0.6
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var n := ti.size() if not ti.is_empty() else tv.size()
	for t in range(0, n - 2, 3):
		var p0 := tv[ti[t] if not ti.is_empty() else t]
		var p1 := tv[ti[t + 1] if not ti.is_empty() else t + 1]
		var p2 := tv[ti[t + 2] if not ti.is_empty() else t + 2]
		var cx := (p0.x + p1.x + p2.x) / 3.0
		if cx < 0.0:
			left.append_array([p0, p1, p2])
		else:
			right.append_array([p0, p1, p2])
	var pillar_slice := (beam_y - box.position.y) / 3.0
	for side in [left, right]:
		for pts in _slab_points(side, box.position.y, beam_y, pillar_slice):
			out.append(_hull(pts))
	var all := left.duplicate()
	all.append_array(right)
	for pts in _slab_points(all, beam_y, box.end.y, box.end.y - beam_y):
		out.append(_hull(pts))
	return out


static func _hull(points: PackedVector3Array) -> ConvexPolygonShape3D:
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	return hull


## Cut the triangle soup [param tris] into horizontal slabs [y0, y1) of
## [param slice] height and return each slab's points: the triangles clipped
## to the slab, so a slab gets the exact cross-sections at its faces even
## where the mesh has no vertex inside it (a decimated trunk, a gate pillar
## that is one long quad). Empty or flat slabs are dropped.
static func _slab_points(tris: PackedVector3Array, y0: float, y1: float, slice: float) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var count := maxi(int(ceil((y1 - y0) / maxf(slice, 0.01) - 0.001)), 1)
	for k in count:
		var lo := y0 + slice * k
		var hi := minf(lo + slice, y1)
		var pts := PackedVector3Array()
		for t in range(0, tris.size() - 2, 3):
			var poly: Array[Vector3] = [tris[t], tris[t + 1], tris[t + 2]]
			poly = _clip_y(poly, lo, true)
			poly = _clip_y(poly, hi, false)
			for p in poly:
				pts.append(p)
		var y_min := INF
		var y_max := -INF
		for p in pts:
			y_min = minf(y_min, p.y)
			y_max = maxf(y_max, p.y)
		if pts.size() >= 4 and y_max - y_min > 0.01:
			out.append(pts)
	return out


## Keep the part of [param poly] above (or below) the plane y = [param y].
static func _clip_y(poly: Array[Vector3], y: float, keep_above: bool) -> Array[Vector3]:
	var res: Array[Vector3] = []
	if poly.is_empty():
		return res
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var a_in := a.y >= y if keep_above else a.y <= y
		var b_in := b.y >= y if keep_above else b.y <= y
		if a_in:
			res.append(a)
		if a_in != b_in and absf(b.y - a.y) > 1e-9:
			res.append(a.lerp(b, (y - a.y) / (b.y - a.y)))
	return res


## Roots and a flare welded onto the trunk mesh (same draw call). UV.x > 1
## marks them for the root branch of the tree shader. They overlap the bark
## and run out onto the soil mound so the trunk does not end in a cut circle.
func _append_root_flare(mesh: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(mesh, 0, Transform3D.IDENTITY)
	var angles: Array[float] = [0.15, 1.05, 2.15, 3.25, 4.35, 5.35]
	var lengths: Array[float] = [1.15, 0.9, 1.3, 0.85, 1.2, 1.0]
	for i in angles.size():
		_add_root_ribbon(st, angles[i], lengths[i])
	_add_root_collar(st)
	return st.commit()


func _add_root_ribbon(st: SurfaceTool, angle: float, length: float) -> void:
	var dir := Vector3(cos(angle), 0.0, sin(angle))
	var side := Vector3(-dir.z, 0.0, dir.x)
	# A root is a low ridge, not a flat fin: a raised spine with two skirts
	# falling to the soil. It dives below the local ground plane before its
	# tip, so on any slope the end is buried instead of hovering — the old
	# long flat ribbons floated over the downhill side like a black star.
	var frac: Array[float] = [0.0, 0.38, 0.72, 1.0]
	var heights: Array[float] = [0.62, 0.30, 0.04, -0.30]
	var half_w: Array[float] = [0.30, 0.21, 0.12, 0.045]
	var skirt := 0.16
	var ridge: Array[Vector3] = []
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for k in 4:
		var r := 0.78 + length * frac[k]
		var c := dir * r + Vector3(0.0, heights[k], 0.0)
		ridge.append(c)
		left.append(c - side * half_w[k] + Vector3(0.0, -skirt, 0.0))
		right.append(c + side * half_w[k] + Vector3(0.0, -skirt, 0.0))
	for k in 3:
		_add_root_quad(st, left[k], ridge[k], ridge[k + 1], left[k + 1], frac[k], frac[k + 1])
		_add_root_quad(st, ridge[k], right[k], right[k + 1], ridge[k + 1], frac[k], frac[k + 1])


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
	var radii: Array[float] = [0.7, 1.1, 1.5]
	var heights: Array[float] = [0.48, 0.16, -0.22]
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
	var merged: ArrayMesh = null
	if profile.torii_scene != null:
		merged = _merge_scene_meshes(profile.torii_scene, TORII_MESH_SCALE)
	if merged:
		return merged
	return _box_mesh(Vector3(1.6, 1.5, 0.2), Vector3(0.0, 0.75, 0.0))


func _build_lantern_mesh() -> ArrayMesh:
	if profile.lantern_scene != null:
		var merged := _merge_scene_meshes(profile.lantern_scene, 1.0)
		if merged:
			return merged
	var parts: Array[Mesh] = []
	for part in LANTERN_PARTS:
		parts.append(_box_mesh(part[0], part[1]))
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


## Albedo of the first surface of a scene (a baked atlas, see tools/prep_forest_assets.py).
static func _scene_albedo(scene: PackedScene) -> Texture2D:
	if scene == null:
		return null
	var inst := scene.instantiate()
	var found: Texture2D = null
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mat := (mi as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D if (mi as MeshInstance3D).mesh != null else null
		if mat != null and mat.albedo_texture != null:
			found = mat.albedo_texture
			break
	inst.free()
	return found


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


## Draw calls, instances and triangles of the forest as it is drawn now (the
## World Gen dock compares them with the Quest budget, see WorldGenBudget).
func stats() -> Dictionary:
	var draws := 0
	var instances := 0
	var triangles := 0
	for key in _chunks:
		var chunk := _chunks[key] as Node3D
		for child in chunk.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
				draws += 1
				triangles += _triangles(((child as MeshInstance3D).mesh))
				instances += 1
			elif child is MultiMeshInstance3D and (child as MultiMeshInstance3D).multimesh != null:
				var mm := (child as MultiMeshInstance3D).multimesh
				if mm.instance_count == 0:
					continue
				draws += 1
				instances += mm.instance_count
				triangles += _triangles(mm.mesh) * mm.instance_count
	return {"chunks": _chunks.size(), "draws": draws, "instances": instances, "triangles": triangles}


static func _triangles(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if not idx.is_empty():
		return idx.size() / 3
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size() / 3


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
			if flat < _prop_clearing:
				best = minf(best, flat)
	return best


## Chunk roots sit on coord * chunk_size (terrain spans ±half around them),
## so the mapping rounds; floor() lagged a rebuild by half a chunk.
func _world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(int(round(pos.x / _chunk_size)), int(round(pos.z / _chunk_size)))


static func _hash_coord(coord: Vector2i, kind: int, index: int) -> int:
	return int(coord.x * 73856093 ^ coord.y * 19349663 ^ kind * 83492791 ^ index * 50331653) & 0x7fffffff


static func _hash01(seed: int, channel: int) -> float:
	return float((seed * 1103515245 + channel * 12345 + 12345) & 0x7fffffff) / float(0x7fffffff)


## Clumps of the crown (centre, radius), the cedar and the sakura. Geometry, not profile.
const SAKURA_CLUMPS := [
	# Lower drooping/cascading blossom clusters (eye-level focal framing at 3.8 - 5.2 m height)
	[Vector3(3.2, 4.4, 1.6), 2.1],
	[Vector3(-3.0, 4.6, -1.8), 2.1],
	[Vector3(1.6, 4.2, -3.0), 2.0],
	[Vector3(-2.0, 4.3, 2.6), 2.0],
	[Vector3(0.2, 4.8, 3.4), 1.9],
	# Mid spreading boughs (cascading layers at 5.8 - 7.4 m height)
	[Vector3(4.2, 6.4, -0.6), 2.2],
	[Vector3(-4.0, 6.6, 1.0), 2.2],
	[Vector3(1.1, 6.2, -3.8), 2.1],
	[Vector3(-1.3, 6.5, 3.6), 2.1],
	[Vector3(3.4, 7.0, 2.4), 2.0],
	# High crown dome (8.4 - 9.8 m height)
	[Vector3(0.1, 9.2, -0.2), 2.4],
	[Vector3(2.2, 8.4, -1.6), 2.0],
	[Vector3(-2.0, 8.5, 1.7), 2.0],
	[Vector3(-1.6, 8.2, -2.2), 1.9],
]

## Compact on purpose: clump centres lie within ~2 m of the trunk, so a crown reaches ~4 m across
## (with CROWN_OVERSIZE). The old 9-14 m crowns covered their neighbours (V1: 59 % severe).
const CROWN_CLUMPS := [
	[Vector3(0.10, 10.14, -0.85), 1.25], [Vector3(1.60, 9.42, -0.35), 1.2],
	[Vector3(-0.14, 11.66, 0.16), 1.35], [Vector3(1.30, 10.63, -1.45), 1.15],
	[Vector3(-1.60, 10.48, 0.95), 1.2], [Vector3(0.85, 9.88, 1.60), 1.25],
	[Vector3(1.25, 11.44, 1.20), 1.15], [Vector3(-1.10, 11.55, -1.45), 1.15],
	[Vector3(-1.60, 9.37, -0.45), 1.25],
]


func _rebuild_crown(scan: Mesh, clumps: Array = CROWN_CLUMPS, fork_y_base: float = 7.3) -> ArrayMesh:
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
		# Trunk and boughs are mapped to the atlas's bottom-left bark strips.
		# Everything else is a leaf card, including a ring of dark ground
		# shards at the foot (the atlas's top-right square) that showed as
		# jagged black fragments around every trunk. Above the clumps'
		# underside the boughs only poke out as shards.
		var bark := uv_c.x < 0.34 and uv_c.y > 0.66 and p_c.y < 8.8
		if not bark:
			continue
		for k in 3:
			st.set_normal(normals[idx[t + k]])
			st.set_uv(uvs[idx[t + k]])
			st.add_vertex(verts[idx[t + k]])
	var noise := FastNoiseLite.new()
	noise.seed = 0x4C454146
	noise.frequency = 0.9
	for c in clumps.size():
		# Slightly oversized so neighbouring clumps merge into one canopy
		# mass instead of reading as separate balloons.
		_add_foliage_clump(st, clumps[c][0], float(clumps[c][1]) * CROWN_OVERSIZE, noise, c)
	# The scan's own boughs are cut at 8.8 m, well below the clump centres:
	# without a branch into each clump the crown read as floating balloons
	# tied to nothing. Grow a tapered bough from the fork into every clump.
	for c in clumps.size():
		_add_branch(st, clumps[c][0], float(clumps[c][1]), c, fork_y_base)
	# The bark is normal-mapped: without tangents its lighting turns to NaN
	# and the trunks vanish.
	st.generate_tangents()
	return st.commit()


## A tapered bough from the trunk fork (near the axis, just under where the
## scan's boughs end) into a foliage clump, ending inside the leaf mass.
## Three rings with a slight mid droop; UVs sit in the atlas bark strip so
## the tree shader treats it as bark, not leaf or root.
func _add_branch(st: SurfaceTool, clump_center: Vector3, clump_radius: float, seed_i: int, fork_y_base: float = 7.3) -> void:
	var fork_y := minf(clump_center.y - 0.7, fork_y_base + float(seed_i % 3) * 0.45)
	var fork := Vector3(clump_center.x * 0.10, fork_y, clump_center.z * 0.10)
	var to_center := clump_center - fork
	var end := clump_center - to_center.normalized() * clump_radius * 0.45
	var mid := fork.lerp(end, 0.52) + Vector3(0.0, -0.22, 0.0)
	var rings: Array[Vector3] = [fork, mid, end]
	var radii: Array[float] = [0.21, 0.12, 0.045]
	var segs := 7
	var frames: Array = []
	for r in rings.size():
		var tan: Vector3
		if r == 0:
			tan = (rings[1] - rings[0]).normalized()
		elif r == rings.size() - 1:
			tan = (rings[r] - rings[r - 1]).normalized()
		else:
			tan = (rings[r + 1] - rings[r - 1]).normalized()
		var side := tan.cross(Vector3.UP)
		if side.length_squared() < 1e-4:
			side = tan.cross(Vector3.RIGHT)
		side = side.normalized()
		var up2 := side.cross(tan).normalized()
		var ring: Array = []
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var n := (side * cos(a) + up2 * sin(a)).normalized()
			ring.append({"p": rings[r] + n * radii[r], "n": n, "u": float(s) / float(segs)})
		frames.append(ring)
	for r in frames.size() - 1:
		for s in segs:
			var s2 := (s + 1) % segs
			var a: Dictionary = frames[r][s]
			var b: Dictionary = frames[r][s2]
			var c: Dictionary = frames[r + 1][s2]
			var d: Dictionary = frames[r + 1][s]
			var v0 := 0.68 + 0.24 * (float(r) / float(frames.size() - 1))
			var v1 := 0.68 + 0.24 * (float(r + 1) / float(frames.size() - 1))
			_branch_vert(st, a, v0)
			_branch_vert(st, b, v0)
			_branch_vert(st, c, v1)
			_branch_vert(st, a, v0)
			_branch_vert(st, c, v1)
			_branch_vert(st, d, v1)


func _branch_vert(st: SurfaceTool, v: Dictionary, vcoord: float) -> void:
	st.set_normal(v.n)
	st.set_uv(Vector2(0.06 + 0.24 * float(v.u), vcoord))
	st.add_vertex(v.p)


## A lumpy, slightly flattened foliage mass with smooth normals. UV.y = 2
## marks it for the foliage branch of the tree shader; UV.x carries a
## per-vertex random shade.
func _add_foliage_clump(st: SurfaceTool, center: Vector3, radius: float, noise: FastNoiseLite, seed_i: int,
		segments := 11, rings := 6) -> void:
	var si: PackedInt32Array = _clump_sphere(segments, rings)[Mesh.ARRAY_INDEX]
	var pts := _clump_points(radius, noise, seed_i, segments, rings)
	var cst := SurfaceTool.new()
	cst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size():
		cst.set_uv(Vector2(float(absi(hash(i * 31 + seed_i * 977)) % 1000) / 999.0, 2.0))
		cst.add_vertex(center + pts[i])
	for i in si:
		cst.add_index(i)
	cst.generate_normals()
	# Smooth normals are computed on the shared vertices; then flatten the
	# index: appending an indexed surface to the non-indexed bark switches
	# the tool to indices and silently drops every bark triangle.
	cst.deindex()
	st.append_from(cst.commit(), 0, Transform3D.IDENTITY)


## The unit sphere a foliage clump is shaped from (vertices and indices).
static func _clump_sphere(segments: int, rings: int) -> Array:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = segments
	sphere.rings = rings
	return sphere.get_mesh_arrays()


## Local vertex positions of one foliage clump, the same numbers _add_foliage_clump draws:
## the noise bump, then the flattened underside. The sky rule reads these to size its discs.
static func _clump_points(radius: float, noise: FastNoiseLite, seed_i: int, segments: int, rings: int) -> PackedVector3Array:
	var sv: PackedVector3Array = _clump_sphere(segments, rings)[Mesh.ARRAY_VERTEX]
	var offset := Vector3(seed_i * 7.3, seed_i * 3.1, seed_i * 5.7)
	var pts := PackedVector3Array()
	pts.resize(sv.size())
	for i in sv.size():
		var d := sv[i]
		var bump := 1.0 + noise.get_noise_3dv(d * 1.6 + offset) * 0.38
		# Flatter underside: a canopy mass hangs, it is not a ball.
		var y := d.y * (0.62 if d.y < 0.0 else 0.8)
		pts[i] = Vector3(d.x, y, d.z) * radius * bump
	return pts


## Crown discs of one tree kind in trunk space (Vector4: centre xyz, reach). Every drawn crown
## point lies within its disc's reach of the centre, so the sky rule reads these, not the mesh.
func _crown_discs_for(entry: TreeEntry, mesh: Mesh) -> PackedVector4Array:
	if entry.crown == TreeEntry.Crown.SCENE:
		return _scene_crown_discs(mesh)
	var clumps: Array = SAKURA_CLUMPS if entry.crown == TreeEntry.Crown.SAKURA else CROWN_CLUMPS
	var noise := FastNoiseLite.new()
	noise.seed = 0x4C454146
	noise.frequency = 0.9
	var out := PackedVector4Array()
	for c in clumps.size():
		var pts := _clump_points(float(clumps[c][1]) * CROWN_OVERSIZE, noise, c, 11, 6)
		var reach := 0.0
		for p in pts:
			reach = maxf(reach, p.length())
		var centre: Vector3 = clumps[c][0]
		out.append(Vector4(centre.x, centre.y, centre.z, reach + CROWN_DISC_MARGIN))
	return out


## Crown discs of a scanned tree: its vertices from SCENE_CROWN_FLOOR up, grouped in 3 m cells,
## each cell a disc around the mean of its vertices.
func _scene_crown_discs(mesh: Mesh) -> PackedVector4Array:
	var cells := {}
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y < SCENE_CROWN_FLOOR:
				continue
			var key := Vector3i(floori(v.x / 3.0), floori(v.y / 3.0), floori(v.z / 3.0))
			if not cells.has(key):
				cells[key] = []
			(cells[key] as Array).append(v)
	var out := PackedVector4Array()
	for key in cells:
		var group: Array = cells[key]
		var mean := Vector3.ZERO
		for v in group:
			mean += v
		mean /= float(group.size())
		var reach := 0.0
		for v in group:
			reach = maxf(reach, (v - mean).length())
		out.append(Vector4(mean.x, mean.y, mean.z, reach + CROWN_DISC_MARGIN))
	return out
