extends Node
## The footpath is visible in the game, not only in the data (docs/WORLDGEN_TOOL.md).
## Runs the real run scene and checks:
##  a) the forest has its paths and the ground under the glade carries path weight;
##  b) a path starts within 6 m of the player's spawn;
##  c) the trail reads against the ground beside it: its luminance is at least 25% above
##     the duff, computed from the material parameters the shader really uses
##     (the packed-earth texture, its tint and gain), with the shader's own tints
##     for the neighbouring soil and grass. On a build without the trail material
##     the trail is the stone layer, which the same check measures;
##  d) no trunk or boulder stands inside the path's half width plus its clearance.
##   godot --headless --path . --fixed-fps 90 res://tests/worldgen_path_game_test.tscn

const RUN_SCENE := preload("res://scenes/run.tscn")
# The shader multiplies the soil, grass and stone by these literal vectors in
# linear light (they are not source_color uniforms, so they are not converted).
const SOIL_TINT := Vector3(0.58, 0.50, 0.44)
const GRASS_TINT := Vector3(0.42, 0.52, 0.40)
const STONE_TINT := Vector3(0.50, 0.52, 0.54)
const OLD_TRAIL_DARKEN := 0.86
const MIN_CONTRAST := 0.25

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

	var contrast := _trail_contrast(forest)
	_check("The trail is %.0f%% brighter than the ground beside it (need %.0f%%)" % [contrast * 100.0, MIN_CONTRAST * 100.0],
		contrast >= MIN_CONTRAST)

	var reach := forest._path_half_width() + forest.profile.path_tree_clearance - 0.5
	var worst := INF
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		var field := forest._path_field(key)
		var centre := Vector2(key.x * forest.profile.chunk_size, key.y * forest.profile.chunk_size)
		for s in forest._tree_spots(key).get("spots", []):
			var spot: Vector4 = s
			worst = minf(worst, forest._field_at(field, Vector2(spot.x, spot.y) - centre))
		for p in chunk.get_meta("undergrowth_world_positions", []):
			var stone: Vector3 = p
			worst = minf(worst, forest._field_at(field, Vector2(stone.x, stone.z) - centre))
	_check("No trunk or boulder stands within the path clearance (nearest %.2f m, need %.2f m)" % [worst, reach],
		worst >= reach)
	run.queue_free()
	await get_tree().process_frame


## Luminance of the trail over the luminance of the ground beside it, minus one.
## Both come from the live ground material: the trail from its packed-earth
## texture (or, without one, the stone layer it used to share), the ground beside
## it from the soil and grass textures with the shader's own tints.
func _trail_contrast(forest: ForestWorld) -> float:
	var mat := forest._ground_mat
	var trail_lin: Vector3
	var path_texture := mat.get_shader_parameter("path_albedo") as Texture2D
	if path_texture != null:
		var tint: Color = mat.get_shader_parameter("path_tint")
		var gain := float(mat.get_shader_parameter("path_gain"))
		trail_lin = _linear_mean(path_texture) * _linear(tint) * gain
	else:
		trail_lin = _linear_mean(load("res://assets/textures/forest_ground/rocky_trail/rocky_trail_diff_1k.jpg")) \
			* STONE_TINT * OLD_TRAIL_DARKEN
	var soil := _linear_mean(load("res://assets/textures/forest_ground/forrest_ground_01/forrest_ground_01_diff_1k.jpg")) * SOIL_TINT
	var grass := _linear_mean(load("res://assets/textures/forest_ground/leafy_grass/leafy_grass_diff_1k.jpg")) * GRASS_TINT
	var beside := 0.5 * soil + 0.5 * grass
	var beside_lum := _luminance(beside)
	if beside_lum <= 0.0:
		return -1.0
	return _luminance(trail_lin) / beside_lum - 1.0


static func _linear(c: Color) -> Vector3:
	return Vector3(_s2l(c.r), _s2l(c.g), _s2l(c.b))


static func _s2l(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _luminance(c: Vector3) -> float:
	return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z


## Mean colour of a texture in linear light, sampled on a 64×64 downscale.
static func _linear_mean(texture: Texture2D) -> Vector3:
	var img := texture.get_image()
	# Imported ground textures are block-compressed: read them as RGBA first.
	if img.is_compressed():
		img.decompress()
	img.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var sum := Vector3.ZERO
	for y in 64:
		for x in 64:
			var c := img.get_pixel(x, y)
			sum += Vector3(_s2l(c.r), _s2l(c.g), _s2l(c.b))
	return sum / 4096.0


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
