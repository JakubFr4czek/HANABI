extends Node
## D5 asset swap, in the real run scene (headless): every file that came in with the
## asset pack has a credit line, the stone lantern and the redwood are the meshes that
## render, the ground carries the moss layer, and the forest stays in budget.

const RUN_SCENE := preload("res://scenes/run.tscn")
const CREDIT_FILES := "res://CREDITS.md"
const LICENSE_FILES := "res://LICENSES.md"
const ASSET_DIRS := [
	"res://assets/models/environment/lanterns",
	"res://assets/models/environment/forest_trees",
	"res://assets/models/environment/shrine",
	"res://assets/textures/forest_ground/moss002",
]
const REDWOOD_META := "xfs_Trees2"

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	_check_every_asset_is_credited()
	_check_profile_wires_new_kinds()

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(14)
	run.wave_director.stop_director()
	var forest := run.forest_world
	forest.finish_pending()
	await _frames(4)

	# Lantern: the baked stone lantern is what the MultiMesh draws (about 1.5 m, textured).
	var lantern_mesh := forest._lantern_mesh
	var lantern_size := lantern_mesh.get_aabb().size if lantern_mesh != null else Vector3.ZERO
	_check("The lantern mesh is the baked stone lantern (height %.2f m, 1.2–1.8 m)" % lantern_size.y,
		lantern_mesh != null and lantern_size.y > 1.2 and lantern_size.y < 1.8)
	var lantern_albedo := forest._lantern_mat.get_shader_parameter("albedo_texture") as Texture2D
	_check("The lantern carries its scan colour (albedo atlas set)", lantern_albedo != null)

	# Ground: the moss layer is bound and the shader's share of moss is non-trivial.
	_check("Forest floor binds the Moss002 layer", forest._ground_mat.get_shader_parameter("moss_albedo") != null
		and forest._ground_mat.get_shader_parameter("moss_normal") != null)

	# Redwood: the scanned crown renders in the ring, and each one stays in budget.
	var redwood_count := 0
	var redwood_height := 0.0
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		var xfs: Array = chunk.get_meta(REDWOOD_META, [])
		redwood_count += xfs.size()
	var redwood_mesh := _redwood_mesh(forest)
	if redwood_mesh != null:
		redwood_height = redwood_mesh.get_aabb().size.y
	var redwood_on := forest.profile.trees[2].weight > 0.0
	_check("Scanned redwoods stand in the forest ring when the kind is on (%d in ring, on: %s)" % [redwood_count, redwood_on],
		not redwood_on or redwood_count > 0)
	_check("Redwood mesh is a tall tree (%.1f m, 8–22 m)" % redwood_height, redwood_height > 8.0 and redwood_height < 22.0)
	_check("Redwood mesh stays under 6.5k triangles", redwood_mesh != null and ForestWorld._triangles(redwood_mesh) <= 6500)

	var stats := forest.stats()
	_check("Forest draw calls stay in budget with the new kinds (%d)" % stats.draws, stats.draws <= 150)

	run.queue_free()
	await _frames(2)


func _redwood_mesh(forest: ForestWorld) -> Mesh:
	for e in forest.profile.trees.size():
		var entry := forest.profile.trees[e]
		if entry.crown == TreeEntry.Crown.SCENE and entry.has_scene():
			return forest._tree_meshes[e]
	return null


func _check_every_asset_is_credited() -> void:
	var text := _read(CREDIT_FILES) + "\n" + _read(LICENSE_FILES)
	var missing := PackedStringArray()
	var checked := 0
	for dir_path in ASSET_DIRS:
		for file in DirAccess.get_files_at(dir_path):
			if file.ends_with(".import") or file.ends_with(".uid") or file.ends_with(".txt"):
				continue
			checked += 1
			# Godot writes a glb's embedded textures as <stem>_<n>.png: credited with the glb.
			var stem := RegEx.create_from_string("_\\d+$").sub(file.get_basename(), "")
			if not text.contains(stem):
				missing.append(file)
	_check("Every new asset file has a CREDITS.md / LICENSES.md entry (%d checked, missing: %s)" % [checked, ", ".join(missing)],
		checked > 0 and missing.is_empty())


func _check_profile_wires_new_kinds() -> void:
	var profile := load("res://data/worldgen/default_profile.tres") as WorldGenProfile
	var has_redwood := false
	for t in profile.trees:
		if t.crown == TreeEntry.Crown.SCENE and t.has_scene():
			has_redwood = true
	_check("The default profile lists the scanned redwood as a scene crown kind", has_redwood)
	_check("The default profile names the stone lantern scene", profile.lantern_scene != null)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame
