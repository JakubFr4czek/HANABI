class_name MeshSlicer
extends RefCounted
## Cuts a triangle mesh by a plane into two closed halves (docs/ELEMENTS_PLAN.md,
## D4 §3). A half is the skin triangles on its side plus the cap: the planar
## face the cut leaves behind, facing out of that half.
##
## Built for the yōkai's convex primitives (box, capsule, sphere). A convex
## body cut by a plane gives one convex section, so the cap is one loop. Any
## simple loop still works. Runs once per cut and allocates only what that cut
## needs; nothing here runs per frame.

## Points closer than this to the plane count as on it (m).
const EPSILON := 1e-5
## Cut-edge endpoints are matched on this grid (m), so the halves join watertight.
const JOIN_GRID := 1e-4
## Planar cap UVs: metres to texture repeats.
const CAP_UV_SCALE := 6.0


## The arrays of a mesh's first surface (or of [param surface]), as
## [method Mesh.surface_get_arrays] returns them. Primitive meshes give theirs
## through [method PrimitiveMesh.get_mesh_arrays].
static func surface_arrays(mesh: Mesh, surface := 0) -> Array:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_arrays(surface)
	if mesh is PrimitiveMesh:
		return (mesh as PrimitiveMesh).get_mesh_arrays()
	return []


## Cuts [param arrays] (a surface's ARRAY_* list) by the plane through
## [param plane_point] with normal [param plane_normal]. Returns
## {"above": side, "below": side}. "above" is the side the normal points to. A
## side is a Dictionary:
##   "verts", "normals", "uvs": triangle lists in the input space;
##   "cap_from": index of the first cap vertex (skin is [0, cap_from));
##   "volume": m³ of the closed half.
static func cut(arrays: Array, plane_point: Vector3, plane_normal: Vector3) -> Dictionary:
	var n := plane_normal.normalized()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tri_count := (index.size() if not index.is_empty() else verts.size()) / 3
	var sign_ := winding_sign(verts, norms, index)
	var above := _new_side()
	var below := _new_side()
	var segments: Array = []
	for t in tri_count:
		var corners: Array = []
		for k in 3:
			var vi := index[t * 3 + k] if not index.is_empty() else t * 3 + k
			var d := n.dot(verts[vi] - plane_point)
			if absf(d) < EPSILON:
				d = 0.0
			corners.append([verts[vi], norms[vi], uvs[vi], d])
		_add_fan(above["verts"], above["normals"], above["uvs"], _clip(corners, 1.0))
		_add_fan(below["verts"], below["normals"], below["uvs"], _clip(corners, -1.0))
		var seg := _segment_on_plane(corners)
		if not seg.is_empty():
			segments.append(seg)
	var loops := _loops(segments)
	var u := _plane_basis_u(n)
	var v := n.cross(u)
	var cap_above := _cap_triangles(loops, plane_point, u, v, -n, sign_)
	var cap_below := _cap_triangles(loops, plane_point, u, v, n, sign_)
	_finish_side(above, cap_above)
	_finish_side(below, cap_below)
	return {"above": above, "below": below}


## Reduces a point cloud to at most [param max_count] points that still span
## its hull well (greedy farthest-point sampling). Used for collision hulls.
static func decimate_points(points: PackedVector3Array, max_count: int) -> PackedVector3Array:
	if points.size() <= max_count:
		return points
	var centre := Vector3.ZERO
	for p in points:
		centre += p
	centre /= float(points.size())
	var first := 0
	var far := -1.0
	for i in points.size():
		var d := points[i].distance_squared_to(centre)
		if d > far:
			far = d
			first = i
	var out := PackedVector3Array([points[first]])
	var best := PackedFloat32Array()
	best.resize(points.size())
	for i in points.size():
		best[i] = points[i].distance_squared_to(points[first])
	while out.size() < max_count:
		var pick := 0
		var pick_d := -1.0
		for i in points.size():
			if best[i] > pick_d:
				pick_d = best[i]
				pick = i
		if pick_d <= 0.0:
			break
		out.append(points[pick])
		for i in points.size():
			best[i] = minf(best[i], points[i].distance_squared_to(points[pick]))
	return out


## Signed volume (m³, absolute) of a closed triangle list.
static func volume_of(verts: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(0, verts.size() - 2, 3):
		total += verts[i].dot(verts[i + 1].cross(verts[i + 2]))
	return absf(total) / 6.0


static func _new_side() -> Dictionary:
	return {"verts": PackedVector3Array(), "normals": PackedVector3Array(),
		"uvs": PackedVector2Array(), "cap_from": 0, "volume": 0.0}


## Whether a source triangle's winding agrees with its vertex normals: +1 when
## (b - a) × (c - a) points along the normal, -1 when it points against it.
static func winding_sign(verts: PackedVector3Array, norms: PackedVector3Array, index: PackedInt32Array) -> float:
	var score := 0.0
	var tri_count := (index.size() if not index.is_empty() else verts.size()) / 3
	for t in tri_count:
		var a := index[t * 3] if not index.is_empty() else t * 3
		var b := index[t * 3 + 1] if not index.is_empty() else t * 3 + 1
		var c := index[t * 3 + 2] if not index.is_empty() else t * 3 + 2
		score += (verts[b] - verts[a]).cross(verts[c] - verts[a]).dot(norms[a])
	return 1.0 if score >= 0.0 else -1.0


## Sutherland–Hodgman clip of one convex polygon. Each corner is
## [position, normal, uv, signed distance]. Keeps the side where
## d × keep ≥ 0 and adds the points where edges cross the plane.
static func _clip(poly: Array, keep: float) -> Array:
	var out: Array = []
	var m := poly.size()
	for i in m:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % m]
		var da := float(a[3]) * keep
		var db := float(b[3]) * keep
		if da >= 0.0:
			out.append(a)
		if (da > 0.0 and db < 0.0) or (da < 0.0 and db > 0.0):
			var t := float(a[3]) / (float(a[3]) - float(b[3]))
			out.append([(a[0] as Vector3).lerp(b[0], t), (a[1] as Vector3).lerp(b[1], t).normalized(),
				(a[2] as Vector2).lerp(b[2], t), 0.0])
	return out


## Fan-triangulates a clipped convex polygon into the side's triangle lists.
static func _add_fan(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, poly: Array) -> void:
	for k in range(1, poly.size() - 1):
		for corner: Array in [poly[0], poly[k], poly[k + 1]]:
			verts.append(corner[0])
			normals.append(corner[1])
			uvs.append(corner[2])


## The cut segment this triangle leaves on the plane, [from, to], or empty.
## Sides are classed as d >= 0 against d < 0 (the same split [method _clip]
## uses), so a corner lying on the plane is an endpoint, never a double point.
static func _segment_on_plane(corners: Array) -> Array:
	var pts: Array = []
	for i in 3:
		var a: Array = corners[i]
		var b: Array = corners[(i + 1) % 3]
		var da := float(a[3])
		var db := float(b[3])
		if (da >= 0.0) != (db >= 0.0):
			var t := da / (da - db)
			pts.append((a[0] as Vector3).lerp(b[0], t))
	if pts.size() != 2:
		return []
	return pts


## Joins segments into closed loops through matching (grid-rounded) endpoints.
static func _loops(segments: Array) -> Array:
	var pos_of := {}
	var adj := {}
	for seg: Array in segments:
		var ka := _key(seg[0])
		var kb := _key(seg[1])
		if ka == kb:
			continue
		pos_of[ka] = seg[0]
		pos_of[kb] = seg[1]
		if not adj.has(ka):
			adj[ka] = []
		if not adj.has(kb):
			adj[kb] = []
		(adj[ka] as Array).append(kb)
		(adj[kb] as Array).append(ka)
	var loops: Array = []
	var seen := {}
	for start: Vector3i in adj.keys():
		if seen.has(start):
			continue
		var loop: Array = []
		var prev := Vector3i(2147483647, 0, 0)
		var cur := start
		while not seen.has(cur):
			seen[cur] = true
			loop.append(pos_of[cur])
			var next := Vector3i(2147483647, 0, 0)
			for nb: Vector3i in adj[cur]:
				if nb != prev and not seen.has(nb):
					next = nb
					break
			if next.x == 2147483647:
				break
			prev = cur
			cur = next
		if loop.size() >= 3:
			loops.append(loop)
	return loops


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x / JOIN_GRID), roundi(p.y / JOIN_GRID), roundi(p.z / JOIN_GRID))


static func _plane_basis_u(n: Vector3) -> Vector3:
	var u := n.cross(Vector3.UP)
	if u.length_squared() < 1e-4:
		u = n.cross(Vector3.RIGHT)
	return u.normalized()


## Triangulates every loop in its plane and orients the triangles so their
## winding agrees with [param facing] (the outward normal of this half's cap).
static func _cap_triangles(loops: Array, origin: Vector3, u: Vector3, v: Vector3,
		facing: Vector3, sign_: float) -> Dictionary:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for loop: Array in loops:
		var flat := PackedVector2Array()
		for p: Vector3 in loop:
			var rel := p - origin
			flat.append(Vector2(rel.dot(u), rel.dot(v)))
		var tris := Geometry2D.triangulate_polygon(flat)
		for i in range(0, tris.size(), 3):
			var a: Vector3 = loop[tris[i]]
			var b: Vector3 = loop[tris[i + 1]]
			var c: Vector3 = loop[tris[i + 2]]
			if (b - a).cross(c - a).dot(facing) * sign_ < 0.0:
				var swap := b
				b = c
				c = swap
			for p in [a, b, c]:
				verts.append(p)
				var rel: Vector3 = p - origin
				uvs.append(Vector2(rel.dot(u), rel.dot(v)) * CAP_UV_SCALE)
	return {"verts": verts, "uvs": uvs, "normal": facing}


static func _finish_side(side: Dictionary, cap: Dictionary) -> void:
	var verts: PackedVector3Array = side["verts"]
	var normals: PackedVector3Array = side["normals"]
	var uvs: PackedVector2Array = side["uvs"]
	side["cap_from"] = verts.size()
	var cap_verts: PackedVector3Array = cap["verts"]
	var cap_uvs: PackedVector2Array = cap["uvs"]
	var facing: Vector3 = cap["normal"]
	for i in cap_verts.size():
		verts.append(cap_verts[i])
		normals.append(facing)
		uvs.append(cap_uvs[i])
	side["volume"] = volume_of(verts)
