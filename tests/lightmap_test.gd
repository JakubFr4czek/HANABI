extends Node
## Headless checks that the arena is ready for a LightmapGI bake in the editor:
## every mesh marked GI Mode = Static has a UV2 channel, the arena's static
## stone and torii are among them, and the animated/unlit layers (sky dome,
## water, mist, the seal) stay out of the bake. Run:
##   godot --headless --path . res://tests/lightmap_test.tscn
## Exit code 0 when everything passed.

const ARENA := preload("res://scenes/training_arena.tscn")
const MUST_BAKE := ["PlatformDisc", "PlatformRim", "NorthThreshold", "GiantTorii"]
const NEVER_BAKE := ["SkyDome", "WaterMirror", "WaterMistLow", "WaterMistHigh", "SpawnSeal", "StormLightning"]

var failures := 0


func _ready() -> void:
	var arena := ARENA.instantiate()
	_run(arena)
	arena.free()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run(arena: Node) -> void:
	var lightmap := arena.get_node_or_null("Arena/LightmapGI") as LightmapGI
	_check("LightmapGI node exists", lightmap != null)

	var bakeable: Array[String] = []
	var missing_uv2: Array[String] = []
	var tris := 0
	for node in arena.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
			continue
		var path := String(arena.get_path_to(mi))
		if _has_uv2(mi.mesh):
			bakeable.append(path)
			tris += _triangles(mi.mesh)
		else:
			missing_uv2.append(path)
	print("  bakeable meshes: %d (%d triangles)" % [bakeable.size(), tris])
	_check("Every GI-static mesh has UV2 %s" % [missing_uv2], missing_uv2.is_empty())
	for name in MUST_BAKE:
		_check("%s is GI static with UV2" % name, bakeable.any(func(p: String) -> bool: return p.contains(name)))

	for name in NEVER_BAKE:
		var mi := arena.find_child(name, true, false) as GeometryInstance3D
		_check("%s is left out of the bake" % name, mi != null and mi.gi_mode == GeometryInstance3D.GI_MODE_DISABLED)

	if lightmap and lightmap.light_data:
		print("  baked lightmap data present: %s" % lightmap.light_data.resource_path)
	else:
		print("  no baked lightmap yet (bake it in the editor)")


static func _has_uv2(mesh: Mesh) -> bool:
	if mesh.get_surface_count() == 0:
		return false
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty() or arrays[Mesh.ARRAY_TEX_UV2] == null or (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).is_empty():
			return false
	return true


static func _triangles(mesh: Mesh) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var idx = arrays[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
