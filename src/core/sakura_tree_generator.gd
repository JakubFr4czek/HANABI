class_name SakuraTreeGenerator
extends Node3D
## Procedural Japanese sakura tree built for Quest 3 / Compatibility performance:
## 1) `TrunkAndBranches` (MultiMeshInstance3D): dark, almost-black gnarled trunk, surface roots,
##    sweeping primary boughs (reaching out over the dojo platform & water mirror), secondary
##    forked limbs, and fine outer twigs — 1 draw call, GI_MODE_STATIC.
## 2) `BlossomCanopy` (MultiMeshInstance3D): 1,800+ small crossed petal-cluster quads
##    distributed in distinct, layered bonsai/shrine clouds around branch tips with clear sky gaps,
##    deep wine-magenta interior depth, Fresnel/rim neon glow, and restrained bright accents — 1 draw call.

const BARK_SHADER := preload("res://src/shaders/sakura_bark.gdshader")
const CANOPY_SHADER := preload("res://src/shaders/sakura_canopy.gdshader")

@export var random_seed: int = 10847
@export var cluster_count: int = 1850

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

	# 1. Surface roots gripping the stone platform.
	var root_angles := [-2.75, -1.95, -1.15, -0.45, 0.35, 1.25, 2.15]
	for r_ang in root_angles:
		var dir := Vector3(cos(r_ang), 0.0, sin(r_ang))
		var perp := Vector3(-dir.z, 0.0, dir.x)
		var r_pts: Array[Vector3] = [
			dir * 0.16 + Vector3(0.0, 0.48, 0.0),
			dir * 0.56 + Vector3(0.0, 0.18, 0.0) + perp * rng.randf_range(-0.10, 0.10),
			dir * 1.05 + Vector3(0.0, 0.02, 0.0) + perp * rng.randf_range(-0.16, 0.16),
		]
		_add_polyline_segments(segments, r_pts, 0.22, 0.052, 0.05)

	# 2. Main gnarled trunk leaning gracefully toward the arena center (+X, +Z in local/world)
	# with an S-curve and a secondary twin trunk fork so the dark woodwork silhouette is unmistakable.
	var trunk_pts: Array[Vector3] = [
		Vector3(0.0, -0.05, 0.0),
		Vector3(0.14, 0.58, 0.06),
		Vector3(0.36, 1.22, 0.14),
		Vector3(0.26, 1.88, 0.26),
		Vector3(0.52, 2.48, 0.38),
	]
	_add_polyline_segments(segments, trunk_pts, 0.42, 0.22, 0.2)

	# Secondary gnarled lower trunk fork splitting toward the water mirror (-X, -Z).
	var sub_trunk_pts: Array[Vector3] = [
		trunk_pts[1],
		trunk_pts[1] + Vector3(-0.34, 0.54, -0.18),
		trunk_pts[1] + Vector3(-0.78, 1.08, -0.42),
		trunk_pts[1] + Vector3(-1.18, 1.56, -0.64),
	]
	_add_polyline_segments(segments, sub_trunk_pts, 0.28, 0.14, 0.35)

	var fork_origin := trunk_pts[4]
	var lower_fork := trunk_pts[3]
	var mid_fork := trunk_pts[2]
	var west_fork := sub_trunk_pts[3]

	# 3. Six primary sweeping boughs with organic S-curves (ancient shrine sakura style):
	# well-separated horizontal tiers so dark limbs and open sky gaps are clearly visible between blossom pads.
	var bough_defs := [
		# Tier 1: Long low sweeping bough reaching over the dojo stone toward the center seal (+X, +Z)
		{
			"pts": [
				mid_fork,
				mid_fork + Vector3(0.85, 0.28, 0.42),
				mid_fork + Vector3(1.78, 0.46, 0.78),
				mid_fork + Vector3(2.65, 0.48, 1.08),
				mid_fork + Vector3(3.35, 0.32, 1.28),
			],
			"r0": 0.20, "r1": 0.058, "cloud_scale": Vector3(0.86, 0.24, 0.80), "weight": 3
		},
		# Tier 2: Mid-right bough arching toward the northern torii vista (+X, -Z)
		{
			"pts": [
				lower_fork,
				lower_fork + Vector3(0.68, 0.44, -0.28),
				lower_fork + Vector3(1.48, 0.82, -0.58),
				lower_fork + Vector3(2.28, 1.04, -0.68),
				lower_fork + Vector3(2.98, 0.96, -0.58),
			],
			"r0": 0.19, "r1": 0.055, "cloud_scale": Vector3(0.92, 0.26, 0.86), "weight": 3
		},
		# Tier 3: High majestic apex crown bough arching high above the trunk
		{
			"pts": [
				fork_origin,
				fork_origin + Vector3(0.34, 0.68, 0.10),
				fork_origin + Vector3(0.82, 1.32, 0.18),
				fork_origin + Vector3(1.45, 1.72, 0.24),
				fork_origin + Vector3(2.08, 1.76, 0.28),
			],
			"r0": 0.185, "r1": 0.052, "cloud_scale": Vector3(0.98, 0.28, 0.92), "weight": 3
		},
		# Tier 4: Upper central-left crown tier
		{
			"pts": [
				fork_origin,
				fork_origin + Vector3(-0.28, 0.72, 0.28),
				fork_origin + Vector3(-0.66, 1.42, 0.62),
				fork_origin + Vector3(-0.98, 1.92, 0.96),
				fork_origin + Vector3(-1.24, 2.02, 1.22),
			],
			"r0": 0.175, "r1": 0.050, "cloud_scale": Vector3(0.94, 0.27, 0.88), "weight": 3
		},
		# Tier 5: Outward weeping bough off the secondary trunk overhanging the water mirror (-X, -Z)
		{
			"pts": [
				west_fork,
				west_fork + Vector3(-0.62, 0.36, -0.32),
				west_fork + Vector3(-1.32, 0.64, -0.68),
				west_fork + Vector3(-1.98, 0.72, -0.98),
				west_fork + Vector3(-2.55, 0.54, -1.22),
			],
			"r0": 0.15, "r1": 0.046, "cloud_scale": Vector3(0.88, 0.25, 0.84), "weight": 2
		},
		# Tier 6: Back-north bough framing the giant torii gate
		{
			"pts": [
				lower_fork,
				lower_fork + Vector3(0.06, 0.56, -0.72),
				lower_fork + Vector3(0.14, 1.06, -1.52),
				fork_origin + Vector3(0.08, 0.78, -2.18),
				fork_origin + Vector3(0.02, 0.66, -2.78),
			],
			"r0": 0.165, "r1": 0.048, "cloud_scale": Vector3(0.86, 0.25, 0.82), "weight": 2
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
				"center": tip + Vector3(0.0, 0.10, 0.0),
				"radii": bough["cloud_scale"] as Vector3,
				"exposure": 0.85,
				"height_norm": clampf((tip.y - 1.6) / 2.9, 0.0, 1.0),
			})

		# Spawn secondary forked branches only near the outer half of each bough (s_idx 2 and 3)
		# so the lower/inner trunk and bough elbows stay completely bare and dramatically visible!
		for s_idx in [2, 3]:
			var base_p: Vector3 = pts[s_idx]
			var forward_dir: Vector3 = (pts[s_idx + 1] - pts[s_idx]).normalized()
			var side_sign := 1.0 if (s_idx % 2 == 0) else -1.0
			var side_dir := forward_dir.cross(Vector3.UP).normalized() * side_sign
			if side_dir.length_squared() < 0.01:
				side_dir = Vector3(side_sign, 0.0, 0.0)

			var sub_dir := (forward_dir * 0.56 + side_dir * 0.74 + Vector3(0.0, 0.30, 0.0)).normalized()
			var sub_len := rng.randf_range(0.88, 1.32)
			var mid_p := base_p + sub_dir * (sub_len * 0.52) + Vector3(0.0, 0.15, 0.0)
			var end_p := base_p + sub_dir * sub_len + Vector3(0.0, 0.06, 0.0)
			var sub_pts: Array[Vector3] = [base_p, mid_p, end_p]
			var start_r := lerpf(bough["r0"], bough["r1"], float(s_idx) / 4.0) * 0.68
			_add_polyline_segments(segments, sub_pts, start_r, 0.030, 0.78)

			clouds.append({
				"center": end_p + Vector3(0.0, 0.07, 0.0),
				"radii": Vector3(rng.randf_range(0.58, 0.82), rng.randf_range(0.18, 0.25), rng.randf_range(0.58, 0.82)),
				"exposure": rng.randf_range(0.48, 0.94),
				"height_norm": clampf((end_p.y - 1.6) / 2.9, 0.0, 1.0),
			})

			# Fine tertiary twigs off each secondary branch for visible dark woodwork inside the blossoms.
			for t_i in 2:
				var twig_sign := 1.0 if t_i == 0 else -1.0
				var twig_base := mid_p.lerp(end_p, 0.35 + 0.35 * float(t_i))
				var twig_side := sub_dir.cross(Vector3.UP).normalized() * twig_sign
				var twig_dir := (sub_dir * 0.65 + twig_side * 0.58 + Vector3(0.0, 0.20 - 0.18 * float(t_i), 0.0)).normalized()
				var twig_end := twig_base + twig_dir * rng.randf_range(0.48, 0.74)
				var twig_pts: Array[Vector3] = [twig_base, twig_base.lerp(twig_end, 0.5) + Vector3(0.0, 0.05, 0.0), twig_end]
				_add_polyline_segments(segments, twig_pts, 0.032, 0.014, 0.95)

				clouds.append({
					"center": twig_end + Vector3(0.0, 0.05, 0.0),
					"radii": Vector3(0.46, 0.17, 0.46),
					"exposure": rng.randf_range(0.64, 1.0),
					"height_norm": clampf((twig_end.y - 1.6) / 2.9, 0.0, 1.0),
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
		offset.y -= shell_r * shell_r * 0.12

		var pos := center + offset
		var scale_val := lerpf(0.28, 0.17, shell_r) * rng.randf_range(0.85, 1.25)
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
