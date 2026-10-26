class_name SakuraTreeGenerator
extends Node3D
## Monumental ancient Japanese sakura tree standing in the water outside the stone
## arena disc, with massive gnarled boughs sweeping high over the water and reaching
## toward the edge of the dojo (GDD §9).
## 1) `TrunkAndBranches` (MultiMeshInstance3D): dark, almost-black gnarled trunk, massive
##    roots emerging from the water mirror, sweeping primary boughs, secondary forked limbs,
##    and fine outer twigs — 1 draw call, GI_MODE_STATIC.
## 2) `BlossomCanopy` (MultiMeshInstance3D): 2,400+ small crossed petal-cluster quads
##    distributed in distinct, layered bonsai/shrine clouds around branch tips with clear sky gaps,
##    deep wine-magenta interior depth, Fresnel/rim neon glow, and restrained bright accents — 1 draw call.

const BARK_SHADER := preload("res://src/shaders/sakura_bark.gdshader")
const CANOPY_SHADER := preload("res://src/shaders/sakura_canopy.gdshader")

@export var random_seed: int = 10847
@export var cluster_count: int = 2400

var bark_multimesh_instance: MultiMeshInstance3D
var canopy_multimesh_instance: MultiMeshInstance3D


func _ready() -> void:
	build_tree()


func build_tree() -> void:
	for child in get_children():
		child.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	# Collect tapered branch segments: each dictionary has `p0`, `p1`, `r0`, `r1`, `tier`.
	var segments: Array[Dictionary] = []
	# Collect blossom cloud centers: each dictionary has `center`, `radii`, `exposure`, `height_norm`.
	var clouds: Array[Dictionary] = []

	# 1. Massive ancient roots emerging from the dark water mirror around the trunk base.
	var root_angles := [-2.8, -2.05, -1.30, -0.55, 0.25, 1.05, 1.85, 2.55]
	for r_ang in root_angles:
		var dir := Vector3(cos(r_ang), 0.0, sin(r_ang))
		var perp := Vector3(-dir.z, 0.0, dir.x)
		var r_pts: Array[Vector3] = [
			dir * 0.35 + Vector3(0.0, 1.15, 0.0),
			dir * 1.35 + Vector3(0.0, 0.45, 0.0) + perp * rng.randf_range(-0.22, 0.22),
			dir * 2.65 + Vector3(0.0, -0.05, 0.0) + perp * rng.randf_range(-0.35, 0.35),
		]
		_add_polyline_segments(segments, r_pts, 0.46, 0.11, 0.05)

	# 2. Monumental gnarled main trunk rising out of the water and leaning toward the arena (+X, +Z).
	var trunk_pts: Array[Vector3] = [
		Vector3(0.0, -0.25, 0.0),
		Vector3(0.32, 1.35, 0.14),
		Vector3(0.84, 2.85, 0.32),
		Vector3(0.62, 4.35, 0.58),
		Vector3(1.22, 5.75, 0.86),
	]
	_add_polyline_segments(segments, trunk_pts, 0.88, 0.46, 0.2)

	# Secondary gnarled lower trunk fork splitting outward over the water (-X, -Z).
	var sub_trunk_pts: Array[Vector3] = [
		trunk_pts[1],
		trunk_pts[1] + Vector3(-0.78, 1.22, -0.42),
		trunk_pts[1] + Vector3(-1.75, 2.45, -0.95),
		trunk_pts[1] + Vector3(-2.65, 3.55, -1.45),
	]
	_add_polyline_segments(segments, sub_trunk_pts, 0.58, 0.28, 0.35)

	var fork_origin := trunk_pts[4]
	var lower_fork := trunk_pts[3]
	var mid_fork := trunk_pts[2]
	var west_fork := sub_trunk_pts[3]

	# 3. Six monumental sweeping boughs with organic S-curves:
	# The tree stands outside the platform in the water (~(-9.2, 0, -4.6)), and its longest right boughs
	# sweep gracefully up and across the water toward the edge of the stone dojo disc!
	var bough_defs := [
		# Tier 1: Giant low-sweeping bough reaching from the water over the western rim of the stone disc (+X, +Z)
		{
			"pts": [
				mid_fork,
				mid_fork + Vector3(1.85, 0.62, 0.88),
				mid_fork + Vector3(3.85, 1.02, 1.68),
				mid_fork + Vector3(5.65, 1.08, 2.32),
				mid_fork + Vector3(7.15, 0.72, 2.78),
			],
			"r0": 0.42, "r1": 0.11, "cloud_scale": Vector3(1.75, 0.48, 1.62), "weight": 4
		},
		# Tier 2: Mid-right bough arching between the dojo disc and the giant northern torii (+X, -Z)
		{
			"pts": [
				lower_fork,
				lower_fork + Vector3(1.48, 0.96, -0.58),
				lower_fork + Vector3(3.22, 1.78, -1.22),
				lower_fork + Vector3(4.95, 2.25, -1.42),
				lower_fork + Vector3(6.45, 2.08, -1.24),
			],
			"r0": 0.39, "r1": 0.105, "cloud_scale": Vector3(1.88, 0.52, 1.75), "weight": 3
		},
		# Tier 3: High majestic apex crown bough arching high over the arena edge
		{
			"pts": [
				fork_origin,
				fork_origin + Vector3(0.76, 1.48, 0.22),
				fork_origin + Vector3(1.82, 2.86, 0.42),
				fork_origin + Vector3(3.18, 3.72, 0.56),
				fork_origin + Vector3(4.55, 3.82, 0.64),
			],
			"r0": 0.38, "r1": 0.10, "cloud_scale": Vector3(2.05, 0.56, 1.92), "weight": 4
		},
		# Tier 4: Upper central-left crown tier high in the storm sky
		{
			"pts": [
				fork_origin,
				fork_origin + Vector3(-0.62, 1.56, 0.62),
				fork_origin + Vector3(-1.45, 3.08, 1.35),
				fork_origin + Vector3(-2.15, 4.16, 2.08),
				fork_origin + Vector3(-2.72, 4.38, 2.65),
			],
			"r0": 0.36, "r1": 0.095, "cloud_scale": Vector3(1.95, 0.54, 1.82), "weight": 3
		},
		# Tier 5: Outward weeping bough off the secondary trunk overhanging the outer water mirror (-X, -Z)
		{
			"pts": [
				west_fork,
				west_fork + Vector3(-1.35, 0.78, -0.68),
				west_fork + Vector3(-2.85, 1.38, -1.46),
				west_fork + Vector3(-4.25, 1.56, -2.12),
				west_fork + Vector3(-5.45, 1.18, -2.62),
			],
			"r0": 0.31, "r1": 0.088, "cloud_scale": Vector3(1.82, 0.50, 1.72), "weight": 2
		},
		# Tier 6: Back-north bough framing the distant sunken torii gates
		{
			"pts": [
				lower_fork,
				lower_fork + Vector3(0.14, 1.22, -1.56),
				lower_fork + Vector3(0.32, 2.28, -3.28),
				fork_origin + Vector3(0.18, 1.68, -4.68),
				fork_origin + Vector3(0.05, 1.42, -5.95),
			],
			"r0": 0.34, "r1": 0.092, "cloud_scale": Vector3(1.78, 0.50, 1.68), "weight": 2
		},
	]

	for bough in bough_defs:
		var pts: Array[Vector3] = []
		for p in bough["pts"]:
			pts.append(p as Vector3)
		_add_polyline_segments(segments, pts, bough["r0"], bough["r1"], 0.5)

		# Register main terminal blossom cloud pad at the bough tip.
		var tip: Vector3 = pts[pts.size() - 1]
		var w_main: int = bough["weight"]
		for _w in w_main:
			clouds.append({
				"center": tip + Vector3(0.0, 0.18, 0.0),
				"radii": bough["cloud_scale"] as Vector3,
				"exposure": 0.85,
				"height_norm": clampf((tip.y - 3.2) / 6.5, 0.0, 1.0),
			})

		# Spawn secondary forked branches along the outer bough (s_idx 2 and 3)
		# so the monumental dark trunk and lower bough forks stay open and clearly readable.
		for s_idx in [2, 3]:
			var base_p: Vector3 = pts[s_idx]
			var forward_dir: Vector3 = (pts[s_idx + 1] - pts[s_idx]).normalized()
			var side_sign := 1.0 if (s_idx % 2 == 0) else -1.0
			var side_dir := forward_dir.cross(Vector3.UP).normalized() * side_sign
			if side_dir.length_squared() < 0.01:
				side_dir = Vector3(side_sign, 0.0, 0.0)

			var sub_dir := (forward_dir * 0.56 + side_dir * 0.74 + Vector3(0.0, 0.30, 0.0)).normalized()
			var sub_len := rng.randf_range(1.85, 2.75)
			var mid_p := base_p + sub_dir * (sub_len * 0.52) + Vector3(0.0, 0.32, 0.0)
			var end_p := base_p + sub_dir * sub_len + Vector3(0.0, 0.14, 0.0)
			var sub_pts: Array[Vector3] = [base_p, mid_p, end_p]
			var start_r := lerpf(bough["r0"], bough["r1"], float(s_idx) / 4.0) * 0.68
			_add_polyline_segments(segments, sub_pts, start_r, 0.058, 0.78)

			clouds.append({
				"center": end_p + Vector3(0.0, 0.14, 0.0),
				"radii": Vector3(rng.randf_range(1.22, 1.68), rng.randf_range(0.36, 0.50), rng.randf_range(1.22, 1.68)),
				"exposure": rng.randf_range(0.48, 0.94),
				"height_norm": clampf((end_p.y - 3.2) / 6.5, 0.0, 1.0),
			})

			# Fine tertiary twigs off each secondary branch for visible dark woodwork inside the blossoms.
			for t_i in 2:
				var twig_sign := 1.0 if t_i == 0 else -1.0
				var twig_base := mid_p.lerp(end_p, 0.35 + 0.35 * float(t_i))
				var twig_side := sub_dir.cross(Vector3.UP).normalized() * twig_sign
				var twig_dir := (sub_dir * 0.65 + twig_side * 0.58 + Vector3(0.0, 0.20 - 0.18 * float(t_i), 0.0)).normalized()
				var twig_end := twig_base + twig_dir * rng.randf_range(0.98, 1.52)
				var twig_pts: Array[Vector3] = [twig_base, twig_base.lerp(twig_end, 0.5) + Vector3(0.0, 0.10, 0.0), twig_end]
				_add_polyline_segments(segments, twig_pts, 0.062, 0.026, 0.95)

				clouds.append({
					"center": twig_end + Vector3(0.0, 0.10, 0.0),
					"radii": Vector3(0.95, 0.34, 0.95),
					"exposure": rng.randf_range(0.64, 1.0),
					"height_norm": clampf((twig_end.y - 3.2) / 6.5, 0.0, 1.0),
				})

	_build_bark_multimesh(segments, rng)
	_build_canopy_multimesh(clouds, rng)


func _add_polyline_segments(
	out_segments: Array[Dictionary],
	pts: Array[Vector3],
	r_start: float,
	r_end: float,
	tier_base: float
) -> void:
	var n := pts.size() - 1
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var dir := (p1 - p0).normalized()
		if i > 0:
			p0 -= dir * (lerpf(r_start, r_end, t0) * 0.35)
		if i < n - 1:
			p1 += dir * (lerpf(r_start, r_end, t1) * 0.25)
		out_segments.append({
			"p0": p0,
			"p1": p1,
			"r0": lerpf(r_start, r_end, t0),
			"r1": lerpf(r_start, r_end, t1),
			"tier": clampf(tier_base + t1 * 0.2, 0.0, 1.0),
		})


func _build_bark_multimesh(segments: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.78
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1

	var mat := ShaderMaterial.new()
	mat.shader = BARK_SHADER
	cyl.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = cyl
	mm.instance_count = segments.size()

	for i in segments.size():
		var seg: Dictionary = segments[i]
		var p0: Vector3 = seg["p0"]
		var p1: Vector3 = seg["p1"]
		var delta := p1 - p0
		var len := delta.length()
		var up := delta / maxf(len, 0.0001)
		var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.92 else Vector3.RIGHT
		var x_axis := up.cross(ref).normalized()
		var z_axis := x_axis.cross(up).normalized()

		var avg_r: float = (float(seg["r0"]) + float(seg["r1"])) * 0.5
		var basis := Basis(x_axis * avg_r, up * len, z_axis * avg_r)
		var mid := (p0 + p1) * 0.5
		mm.set_instance_transform(i, Transform3D(basis, mid))
		mm.set_instance_custom_data(i, Color(float(seg["tier"]), rng.randf(), 0.0, 0.0))

	bark_multimesh_instance = MultiMeshInstance3D.new()
	bark_multimesh_instance.name = "TrunkAndBranches"
	bark_multimesh_instance.multimesh = mm
	bark_multimesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	bark_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(bark_multimesh_instance)


func _build_canopy_multimesh(clouds: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	var mesh := _create_crossed_blossom_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = CANOPY_SHADER
	mesh.surface_set_material(0, mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cluster_count

	for i in cluster_count:
		var cloud: Dictionary = clouds[i % clouds.size()]
		var center: Vector3 = cloud["center"]
		var radii: Vector3 = cloud["radii"]

		# Concentrate twigs in flattened, layered horizontal bonsai pads with open sky gaps between pads.
		var u := rng.randf_range(0.0, TAU)
		var v := rng.randf_range(-1.0, 1.0)
		var shell_r := pow(rng.randf(), 0.44)
		var horiz := sqrt(maxf(0.0, 1.0 - v * v))
		var local_dir := Vector3(cos(u) * horiz, v, sin(u) * horiz)
		var offset := Vector3(
			local_dir.x * radii.x * shell_r,
			local_dir.y * radii.y * shell_r,
			local_dir.z * radii.z * shell_r
		)
		# Drooping outer blossom tips.
		offset.y -= shell_r * shell_r * 0.22

		var pos := center + offset
		var scale_val := lerpf(0.46, 0.28, shell_r) * rng.randf_range(0.85, 1.25)
		var basis := Basis.from_euler(Vector3(
			rng.randf_range(-0.55, 0.55),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.55, 0.55)
		)).scaled(Vector3.ONE * scale_val)

		var cloud_exp: float = cloud["exposure"]
		var outer_exp := clampf(cloud_exp * (0.28 + 0.72 * shell_r) * (0.5 + 0.5 * clampf(local_dir.y + 0.45, 0.0, 1.0)), 0.04, 1.0)
		var accent_roll := rng.randf() * (0.35 + 0.65 * shell_r)

		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_custom_data(i, Color(
			rng.randf(),
			accent_roll,
			outer_exp,
			float(cloud["height_norm"])
		))

	canopy_multimesh_instance = MultiMeshInstance3D.new()
	canopy_multimesh_instance.name = "BlossomCanopy"
	canopy_multimesh_instance.multimesh = mm
	canopy_multimesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	canopy_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(canopy_multimesh_instance)


func _create_crossed_blossom_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var planes := [
		Basis.IDENTITY,
		Basis.from_euler(Vector3(0.32, deg_to_rad(62.0), -0.18)),
		Basis.from_euler(Vector3(-0.48, deg_to_rad(124.0), 0.28)),
	]
	for b: Basis in planes:
		var n := (b * Vector3.BACK).normalized()
		var v0 := b * Vector3(-0.5, -0.5, 0.0)
		var v1 := b * Vector3(0.5, -0.5, 0.0)
		var v2 := b * Vector3(0.5, 0.5, 0.0)
		var v3 := b * Vector3(-0.5, 0.5, 0.0)

		st.set_normal(n)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(v0)
		st.set_normal(n)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(v1)
		st.set_normal(n)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(v2)

		st.set_normal(n)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(v0)
		st.set_normal(n)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(v2)
		st.set_normal(n)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(v3)

	return st.commit()
