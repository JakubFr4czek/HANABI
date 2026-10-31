class_name YokaiForms
extends RefCounted
## Visual forms of a yōkai body (N3, docs/n3/DECISIONS.md): tapered, lightly irregular
## meshes in place of the boxes of the ragdoll. Visual only: the collision shapes stay
## the boxes and capsules of yokai.gd, so the physics and the joints are unchanged.
##
## Every form is built once and shared by all yōkai (one mesh per form, no per-body
## allocation). Each is a closed or open triangle surface with normals and UVs, so
## MeshSlicer (D4) can cut the body meshes and the Kirisute pieces keep their skin.

const MASK_PATH := "res://assets/models/enemies/yokai_mask.glb"
const MASK_ALBEDO := "res://assets/models/enemies/yokai_mask_albedo.png"
const MASK_NORMAL := "res://assets/models/enemies/yokai_mask_normal.png"
const MASK_ORM := "res://assets/models/enemies/yokai_mask_orm.png"
## Tint over the mask albedo (a dark lacquered demon mask, lifted so the horns read), yōkai and Oni.
const MASK_TINT := Color(1.9, 1.55, 1.35)
## Eye glows sit in the mask's eye sockets, in the head's frame (metres).
const EYE_X := 0.0248
const EYE_Y := -0.02
const EYE_Z := 0.112

## (y, rx, rz) rings, bottom to top. The chest is wider than deep and narrows at the hips.
const CHEST_RINGS := [
	Vector3(-0.21, 0.135, 0.078), Vector3(-0.09, 0.160, 0.092), Vector3(0.04, 0.172, 0.100),
	Vector3(0.17, 0.158, 0.092), Vector3(0.21, 0.120, 0.078),
]
## Limb profiles: (fraction of the capsule's height, fraction of its radius), top to bottom.
const ARM_PROFILE := [Vector2(-0.5, 0.45), Vector2(-0.36, 0.70), Vector2(-0.1, 0.70), Vector2(0.12, 0.88), Vector2(0.32, 1.0), Vector2(0.5, 0.78)]
const LEG_PROFILE := [Vector2(-0.5, 0.62), Vector2(-0.3, 0.76), Vector2(-0.02, 0.92), Vector2(0.2, 1.0), Vector2(0.36, 1.12), Vector2(0.5, 0.72)]
## The visible head: inside the mask, never through its face (the collision sphere is 0.115).
const HEAD_VISUAL_RADIUS := 0.088
const PELVIS_RINGS := [Vector3(-0.085, 0.122, 0.080), Vector3(0.0, 0.140, 0.092), Vector3(0.085, 0.132, 0.086)]
const WRAP_RINGS := [Vector3(0.02, 0.178, 0.106), Vector3(0.13, 0.176, 0.104)]
const OBI_RINGS := [Vector3(0.0, 0.146, 0.098), Vector3(0.08, 0.148, 0.100)]
## A torn hakama on the hips: an open skirt whose hem is ragged (see tube's jag).
const HAKAMA_RINGS := [Vector3(-0.02, 0.150, 0.098), Vector3(-0.14, 0.175, 0.118), Vector3(-0.25, 0.192, 0.135)]
const HAKAMA_JAG := 0.035

static var _cache := {}


## The visual mesh of a ragdoll part with collision shape [param def] (see yokai.gd _define_parts).
static func body_mesh(part_name: String, def: Dictionary) -> Mesh:
	match part_name:
		"chest":
			return _cached("chest", func() -> Mesh: return tube(CHEST_RINGS, 12, true))
		"pelvis":
			return _cached("pelvis", func() -> Mesh: return tube(PELVIS_RINGS, 12, true))
	match String(def.shape):
		"capsule":
			var r := float(def.radius)
			var h := float(def.height)
			# Arms and legs taper like limbs (thin wrist and ankle, the thigh and forearm full).
			if part_name.begins_with("arm_") or part_name.begins_with("leg_"):
				var profile := ARM_PROFILE if part_name.begins_with("arm_") else LEG_PROFILE
				return _cached("limb_%s_%.3f_%.3f" % [part_name.substr(0, 3), r, h], func() -> Mesh:
					var rings: Array = []
					for step in profile:
						rings.append(Vector3(float(step.x) * h, float(step.y) * r, float(step.y) * r))
					return tube(rings, 10, true))
			return _cached("capsule_%.3f_%.3f" % [r, h], func() -> Mesh:
				var m := CapsuleMesh.new()
				m.radius = r
				m.height = h
				m.radial_segments = 10
				m.rings = 2
				return m)
		"sphere":
			# The head's visual is smaller than its collision sphere: the mask hugs the skull
			# and no sphere shows through the face (N3). The collision shape stays as it was.
			var rad := HEAD_VISUAL_RADIUS if part_name == "head" else float(def.radius)
			return _cached("sphere_%.3f" % rad, func() -> Mesh:
				var m := SphereMesh.new()
				m.radius = rad
				m.height = rad * 2.0
				m.radial_segments = 12
				m.rings = 6
				return m)
	return _cached("box_%s" % part_name, func() -> Mesh:
		var b := BoxMesh.new()
		b.size = def.size
		return b)


## The head's mask: the CC BY 4.0 demon mask (Eques_inferno), decimated to ~2.2k triangles,
## baked into the head's frame by tools/bake_yokai_mask.py. One surface, one material.
static func mask_mesh() -> Mesh:
	return _cached("mask", func() -> Mesh:
		var scene := load(MASK_PATH) as PackedScene
		if scene == null:
			return BoxMesh.new()
		var inst := scene.instantiate()
		var mesh: Mesh = null
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			mesh = (n as MeshInstance3D).mesh
			break
		inst.free()
		return mesh if mesh != null else BoxMesh.new())


## The mask's textures for the wet shader (albedo, normal, ORM: occlusion, roughness, metal).
static func mask_albedo() -> Texture2D:
	return load(MASK_ALBEDO) as Texture2D


static func mask_normal() -> Texture2D:
	return load(MASK_NORMAL) as Texture2D


static func mask_orm() -> Texture2D:
	return load(MASK_ORM) as Texture2D


static func eye_mesh() -> Mesh:
	return _cached("eye", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.0115
		m.height = 0.023
		m.radial_segments = 8
		m.rings = 4
		return m)


## A crimson sash band wrapped round the chest or the hips (a tube open at both ends).
static func sash_band(name_: String) -> Mesh:
	var rings := WRAP_RINGS if name_ == "wrap" else OBI_RINGS
	return _cached("band_" + name_, func() -> Mesh: return tube(rings, 12, false))


## A shoulder plate (sode) or the glowing sigil: a small ellipsoid of half-sizes (ax, ay, az).
static func ellipsoid(ax: float, ay: float, az: float, segs: int = 10) -> Mesh:
	var key := "ellipsoid_%.3f_%.3f_%.3f" % [ax, ay, az]
	return _cached(key, func() -> Mesh:
		var rings: Array = []
		var steps := 5
		for i in steps:
			var phi := lerpf(0.35, PI - 0.35, float(i) / float(steps - 1))
			rings.append(Vector3(-ay * cos(phi), ax * sin(phi), az * sin(phi)))
		return tube(rings, segs, true))


## The hakama skirt: an open ragged tube on the hips.
static func hakama() -> Mesh:
	return _cached("hakama", func() -> Mesh: return tube(HAKAMA_RINGS, 14, false, HAKAMA_JAG))


## A claw: a thin cone from the hand.
static func claw() -> Mesh:
	return _cached("claw", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.0015
		c.bottom_radius = 0.0075
		c.height = 0.15
		c.radial_segments = 5
		c.rings = 1
		return c)


## A closed or open tube through (y, rx, rz) rings, bottom to top, with [param segs] sides.
## [param jag] > 0 ragged-cuts the last ring (a torn hem). Winding is outward (clockwise
## front faces, Godot's convention), normals point out of the surface.
static func tube(rings: Array, segs: int, caps: bool, jag: float = 0.0) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := rings.size()
	for r in n:
		var ring: Vector3 = rings[r]
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var k := 1.0
			var dy := 0.0
			if jag > 0.0 and r == n - 1:
				# Torn hem: each strip keeps a different width and length (±jag metres).
				var h := _hash01(s)
				k = 1.0 + (h - 0.5) * 2.0 * jag / maxf(ring.y, 1e-3)
				dy = -jag * 1.4 * h * h
			verts.append(Vector3(cos(a) * ring.y * k, ring.x + dy, sin(a) * ring.z * k))
			norms.append(Vector3(cos(a) / maxf(ring.y, 1e-4), 0.0, sin(a) / maxf(ring.z, 1e-4)).normalized())
			uvs.append(Vector2(float(s) / float(segs), float(r) / float(maxi(n - 1, 1))))
	for r in n - 1:
		for s in segs:
			var a := r * segs + s
			var b := r * segs + (s + 1) % segs
			var c := (r + 1) * segs + s
			var d := (r + 1) * segs + (s + 1) % segs
			_add_tri(verts, idx, a, c, b)
			_add_tri(verts, idx, b, c, d)
	if caps and n >= 2:
		for e in [0, n - 1]:
			var ring: Vector3 = rings[e]
			var up := -1.0 if e == 0 else 1.0
			var center := verts.size()
			verts.append(Vector3(0.0, ring.x, 0.0))
			norms.append(Vector3(0.0, up, 0.0))
			uvs.append(Vector2(0.5, 0.5))
			var base: int = e * segs
			for s in segs:
				_add_tri_facing(verts, idx, center, base + s, base + (s + 1) % segs, Vector3(0.0, up, 0.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Adds triangle a,b,c with its winding turned so it faces away from the body axis.
static func _add_tri(verts: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, c: int) -> void:
	var p0 := verts[a]
	var centroid := (p0 + verts[b] + verts[c]) / 3.0
	var outward := centroid - Vector3(0.0, centroid.y, 0.0)
	_add_tri_facing(verts, idx, a, b, c, outward)


static func _add_tri_facing(_verts: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, c: int, outward: Vector3) -> void:
	var n := (_verts[b] - _verts[a]).cross(_verts[c] - _verts[a])
	if n.dot(outward) > 0.0:
		# Godot front faces are clockwise seen from outside: flip so the cross product points inward.
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


static func _hash01(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + 78.233) * 43758.5453, 1.0)


static func _cached(key: String, build: Callable) -> Mesh:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]
