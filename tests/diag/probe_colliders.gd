extends Node
## Measures prop meshes against their colliders (headless).

func _ready() -> void:
	var fw := ForestWorld.new()
	add_child(fw)
	fw.profile = WorldGenProfile.make_default()
	fw._apply_profile()
	var tree: Mesh = fw._tree_meshes[0]
	var a := tree.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var bands := {}
	for i in v.size():
		if uv[i].x > 1.5 or uv[i].y > 1.5:
			continue
		var r := Vector2(v[i].x, v[i].z).length()
		if r > 1.2:
			continue
		var b := int(floor(v[i].y * 2.0))
		if b < 0 or b > 12:
			continue
		bands[b] = maxf(float(bands.get(b, 0.0)), r)
	var keys := bands.keys()
	keys.sort()
	for b in keys:
		print("TREE y %.1f-%.1f max r %.3f" % [b * 0.5, b * 0.5 + 0.5, bands[b]])
	var roots := 0.0
	for i in v.size():
		if uv[i].x > 1.5:
			roots = maxf(roots, v[i].y)
	print("TREE root/collar max y %.2f" % roots)
	var torii: Mesh = fw._torii_mesh
	print("TORII aabb ", torii.get_aabb())
	var ta := torii.surface_get_arrays(0)
	var tv: PackedVector3Array = ta[Mesh.ARRAY_VERTEX]
	var ys: Array[float] = []
	for p in tv:
		ys.append(p.y)
	ys.sort()
	# Height histogram of x-extent: where the frame is narrow (pillars) vs wide (beams).
	var box := torii.get_aabb()
	for k in 10:
		var y0 := box.position.y + box.size.y * k / 10.0
		var y1 := y0 + box.size.y / 10.0
		var xmin := INF
		var xmax := -INF
		var zmin := INF
		var zmax := -INF
		var n := 0
		for p in tv:
			if p.y >= y0 and p.y < y1:
				xmin = minf(xmin, p.x); xmax = maxf(xmax, p.x); zmin = minf(zmin, p.z); zmax = maxf(zmax, p.z); n += 1
		print("TORII y %.2f-%.2f n %d x [%.2f, %.2f] z [%.2f, %.2f]" % [y0, y1, n, xmin, xmax, zmin, zmax])
	print("ROCK aabb ", fw._under_meshes[0].get_aabb())
	print("LANTERN aabb ", fw._lantern_mesh.get_aabb())
	get_tree().quit()
