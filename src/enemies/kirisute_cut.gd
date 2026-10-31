class_name KirisuteCut
extends RefCounted
## Kirisute (tachi, docs/ELEMENTS_PLAN.md D4): a clean cut through a yōkai splits
## its body along the plane the blade swept. Every convex part is cut with
## [MeshSlicer]; the two halves of the body each gather their skin, cap and
## decorations into one loose [KirisuteChunk], which falls where it was cut.

## Convex hull points per part half (Quest budget, see D4 §6).
const HULL_POINTS := 32
## The two halves start this far apart along the plane normal, so the glowing cut
## is open in the very frame it happens (they would otherwise overlap and read
## as one whole body until the impulse has moved them).
const SEPARATION := 0.03
## Cap glow when the cut is fresh, and once it has cooled.
const CAP_HOT := 2.4
const CAP_COOL := 0.35

static var _claim_frame := -1
static var _claims := 0


## Normal of the cut plane for a blade moving along [param motion] with its
## edge axis [param blade_axis]: n = m × a. The plane contains both vectors,
## so the blade sweeps it. The side n points to is the "above" half.
## Zero when the two vectors are parallel (a thrust cuts no plane).
static func plane_normal(motion: Vector3, blade_axis: Vector3) -> Vector3:
	var n := motion.cross(blade_axis)
	return n.normalized() if n.length_squared() > 1e-8 else Vector3.ZERO


## Takes one of this physics frame's cut slots. False once
## [constant ElementBalance.KIRISUTE_CUTS_PER_FRAME] cuts split bodies this frame.
static func claim_cut() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _claim_frame:
		_claim_frame = frame
		_claims = 0
	if _claims >= ElementBalance.KIRISUTE_CUTS_PER_FRAME:
		return false
	_claims += 1
	return true


## The colour a school's cut glows in. Ink is glossy black, so its glow is a deep
## indigo kept dimmer than the others (a bright one bleaches to white).
static func glow_color(element: String) -> Color:
	if element == Elements.INK:
		return Color(0.30, 0.38, 0.85)
	return Elements.color(element)


## How hard the cut glows when fresh (the emission multiplier of its cap).
static func hot_energy(element: String) -> float:
	return 0.8 if element == Elements.INK else CAP_HOT


## A cut that does not split (an elite's wound, or an Oni's): sparks in the
## school's colour spray out along the blade and a sharp sound marks it.
static func wound(scene: Node, point: Vector3, motion: Vector3, element: String) -> void:
	SparkBurst.spawn(scene, point, motion, glow_color(element), 12, 2.2)
	Sfx.play_at("yokai_slice", point, -6.0, 2.0, 1.05)


## Splits [param body] (a node with a [code]parts[/code] dictionary of
## [RagdollPart]) along the plane through [param point] with [param normal].
## [param motion] is the blade's travel; [param element] colours the cut.
## The pieces are added to [param parent]. Returns them, or nothing when the
## plane misses the body (one side empty): then the body is not split.
static func split(body: Node3D, parts: Dictionary, parent: Node, point: Vector3, normal: Vector3,
		motion: Vector3, element: String) -> Array[KirisuteChunk]:
	var pieces: Array[KirisuteChunk] = []
	if normal.length_squared() < 1e-8:
		return pieces
	var sides := {"above": _new_side(), "below": _new_side()}
	var cap := KirisuteChunk.make_cap_material(element)
	for part_name in parts:
		var part := parts[part_name] as RagdollPart
		if part == null or not part.visible:
			continue
		var primary := _primary_mesh(part)
		if primary == null:
			continue
		var xf := part.global_transform
		var arrays := MeshSlicer.surface_arrays(primary.mesh)
		var verts_in: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts_in.is_empty():
			continue
		var whole := MeshSlicer.volume_of(_triangles(arrays))
		var halves := MeshSlicer.cut(arrays, xf.affine_inverse() * point, (xf.basis.transposed() * normal).normalized())
		for side_name in ["above", "below"]:
			var half: Dictionary = halves[side_name]
			var verts: PackedVector3Array = half.verts
			if verts.is_empty():
				continue
			var side: Dictionary = sides[side_name]
			side.mass += part.mass * clampf(float(half.volume) / maxf(whole, 1e-9), 0.0, 1.0)
			var cap_from: int = half.cap_from
			_group(side, primary.material_override, primary.material_override, half.verts, half.normals, half.uvs,
				0, cap_from, xf, point)
			_group(side, "cap", cap, half.verts, half.normals, half.uvs, cap_from, verts.size(), xf, point)
			side.hulls.append(MeshSlicer.decimate_points(_to_chunk(verts, xf, point), HULL_POINTS))
		# Only decorations marked keep_on_piece travel with a piece: each one is a
		# surface, i.e. a draw call, and a piece has to cost less than the living body.
		for child in part.get_children():
			if child is MeshInstance3D and child != primary and child.has_meta("keep_on_piece") \
					and child.mesh and child.is_visible_in_tree():
				var mi := child as MeshInstance3D
				var side_name := "above" if normal.dot(mi.global_transform * mi.get_aabb().get_center() - point) >= 0.0 else "below"
				_group_mesh(sides[side_name], mi, point)
	if not _has_geometry(sides["above"]) or not _has_geometry(sides["below"]):
		return pieces
	KirisuteChunk.make_room(2)
	var anchor := parts.get("pelvis") as RagdollPart
	var base := anchor.linear_velocity * 0.5 if anchor else Vector3.ZERO
	var spin := motion.cross(normal)
	spin = spin.normalized() if spin.length_squared() > 1e-8 else Vector3.UP
	for side_name in ["above", "below"]:
		var sign_ := 1.0 if side_name == "above" else -1.0
		var chunk := _build_chunk(sides[side_name], cap, element)
		parent.add_child(chunk)
		chunk.global_transform = Transform3D(Basis.IDENTITY, point + normal * sign_ * SEPARATION)
		chunk.linear_velocity = base + normal * sign_ * 1.2 + motion * 0.8 + Vector3.UP * 1.0
		chunk.angular_velocity = spin * sign_ * 6.0
		pieces.append(chunk)
	return pieces


## The body shape of a [RagdollPart]: its first MeshInstance3D child with a
## primitive or array mesh (`_decorate_part` adds it before any decoration; the N3
## tapered forms are ArrayMeshes, see YokaiForms).
static func _primary_mesh(part: Node3D) -> MeshInstance3D:
	for child in part.get_children():
		var m := (child as MeshInstance3D).mesh if child is MeshInstance3D else null
		if m is PrimitiveMesh or m is ArrayMesh:
			return child as MeshInstance3D
	return null


static func _new_side() -> Dictionary:
	return {"groups": {}, "hulls": [], "mass": 0.0}


static func _has_geometry(side: Dictionary) -> bool:
	return not (side.groups as Dictionary).is_empty()


## Appends triangles [from, to) of a half to the side's surface group [param key]
## (a material instance, or "cap"), moved from part space into chunk space.
static func _group(side: Dictionary, key: Variant, material: Material, verts: PackedVector3Array,
		normals: PackedVector3Array, uvs: PackedVector2Array, from: int, to: int,
		xf: Transform3D, origin: Vector3) -> void:
	if to <= from:
		return
	var groups: Dictionary = side.groups
	# Material groups are keyed by instance, so two parts sharing a material share a surface.
	var group_key: Variant = key
	if key is Material:
		group_key = (key as Material).get_instance_id()
	elif key == null:
		group_key = 0
	if not groups.has(group_key):
		groups[group_key] = {"material": material, "verts": PackedVector3Array(),
			"normals": PackedVector3Array(), "uvs": PackedVector2Array()}
	var g: Dictionary = groups[group_key]
	var gv: PackedVector3Array = g.verts
	var gn: PackedVector3Array = g.normals
	var gu: PackedVector2Array = g.uvs
	for i in range(from, to):
		gv.append(xf * verts[i] - origin)
		gn.append((xf.basis * normals[i]).normalized())
		gu.append(uvs[i])
	g.verts = gv
	g.normals = gn
	g.uvs = gu


## Adds a whole decoration mesh (a horn, the mask, an eye) to the side that holds
## its centre. Decorations are never sliced; they travel with their half.
static func _group_mesh(side: Dictionary, mi: MeshInstance3D, origin: Vector3) -> void:
	var mesh := mi.mesh
	for s in mesh.get_surface_count():
		var arrays := MeshSlicer.surface_arrays(mesh, s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts := _expand_vec3(arrays, Mesh.ARRAY_VERTEX)
		var normals := _expand_vec3(arrays, Mesh.ARRAY_NORMAL)
		if normals.size() != verts.size():
			normals.resize(verts.size())
			normals.fill(Vector3.UP)
		var uvs := _expand_vec2(arrays, Mesh.ARRAY_TEX_UV)
		if uvs.size() != verts.size():
			uvs.resize(verts.size())
		var material: Material = mi.material_override
		if material == null:
			material = mesh.surface_get_material(s)
		_group(side, material, material, verts, normals, uvs, 0, verts.size(), mi.global_transform, origin)


## Triangle list of a surface (indexed or not).
static func _triangles(arrays: Array) -> PackedVector3Array:
	return _expand_vec3(arrays, Mesh.ARRAY_VERTEX)


## One Vector3 attribute of a surface as a triangle list (the index applied).
static func _expand_vec3(arrays: Array, attribute: int) -> PackedVector3Array:
	var source: PackedVector3Array = arrays[attribute] if arrays[attribute] != null else PackedVector3Array()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if index.is_empty():
		return source
	var out := PackedVector3Array()
	out.resize(index.size())
	for i in index.size():
		out[i] = source[index[i]]
	return out


## One Vector2 attribute of a surface as a triangle list (the index applied).
static func _expand_vec2(arrays: Array, attribute: int) -> PackedVector2Array:
	var source: PackedVector2Array = arrays[attribute] if arrays[attribute] != null else PackedVector2Array()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if index.is_empty():
		return source
	var out := PackedVector2Array()
	out.resize(index.size())
	for i in index.size():
		out[i] = source[index[i]]
	return out


static func _to_chunk(verts: PackedVector3Array, xf: Transform3D, origin: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		out[i] = xf * verts[i] - origin
	return out


static func _build_chunk(side: Dictionary, cap: StandardMaterial3D, element: String) -> KirisuteChunk:
	var chunk := KirisuteChunk.new()
	chunk.name = "Kirisute_piece"
	chunk.mass = maxf(float(side.mass), 0.3)
	chunk.collision_layer = 0
	chunk.collision_mask = 1
	chunk.continuous_cd = true
	chunk.linear_damp = 0.15
	chunk.angular_damp = 1.2
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.05
	chunk.physics_material_override = phys
	var mesh := ArrayMesh.new()
	var materials: Array[Material] = []
	for key in side.groups:
		var g: Dictionary = side.groups[key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_NORMAL] = g.normals
		arrays[Mesh.ARRAY_TEX_UV] = g.uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		materials.append(cap if key is String else g.material as Material)
	for s in materials.size():
		mesh.surface_set_material(s, materials[s])
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	chunk.add_child(visual)
	chunk.visual = visual
	chunk.cap_material = cap
	chunk.hot_energy = cap.emission_energy_multiplier
	for hull: PackedVector3Array in side.hulls:
		if hull.size() < 4:
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = hull
		var cs := CollisionShape3D.new()
		cs.shape = shape
		chunk.add_child(cs)
	return chunk
