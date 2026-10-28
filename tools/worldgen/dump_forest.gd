extends SceneTree
## Regression digest of the forest: builds the 3×3 ring around the origin with
## the same follow node the game uses and prints one line per chunk with the
## tree transforms (and gates), so a refactor can be proven to keep the same forest.
##   godot --headless --path . -s res://tools/worldgen/dump_forest.gd -- /tmp/forest_digest.txt

const CENTER_CHUNKS := 2

func _initialize() -> void:
	var out_path := "/tmp/forest_digest.txt"
	for arg in OS.get_cmdline_user_args():
		if arg.ends_with(".txt"):
			out_path = arg
	var follow := Node3D.new()
	root.add_child(follow)
	var forest := ForestWorld.new()
	root.add_child(forest)
	forest.setup(follow)
	var lines := PackedStringArray()
	var keys := forest._chunks.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 1000 + a.y < b.x * 1000 + b.y)
	for key in keys:
		var chunk := forest._chunks[key] as Node3D
		var trees := PackedStringArray()
		for xf in chunk.get_meta("tree_local_xfs", []):
			trees.append(_xf_str(xf))
		var focal := PackedStringArray()
		for xf in chunk.get_meta("sakura_tree_local_xfs", []):
			focal.append(_xf_str(xf))
		var gates := PackedStringArray()
		for p in chunk.get_meta("torii_world_positions", []):
			gates.append(str(p))
		lines.append("%s trees=%d:%s focal=%d:%s gates=%d:%s" % [str(key),
			trees.size(), str(",".join(trees).hash()), focal.size(), str(",".join(focal).hash()),
			gates.size(), str(",".join(gates).hash())])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()

	print("DIGEST chunks=%d -> %s" % [lines.size(), out_path])
	quit(0)


func _xf_str(xf: Transform3D) -> String:
	return "%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [xf.origin.x, xf.origin.y, xf.origin.z,
		xf.basis.get_scale().x, xf.basis.z.x, xf.basis.z.z]
