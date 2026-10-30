class_name ToriiGate
extends Node3D
## Interactive Torii Gate Scene for Hanabi (docs/ELEMENTS_PLAN.md Phase E2a).
##
## Implements:
## - Authentic Shinto Myōjin architecture: curved Kasagi with sori & upturned eaves,
##   Shimaki, through-Nuki with kusabi wedges, Gakuzuka plaque strut, slightly inclined
##   Hashira (uchikorobi), and carved octagonal granite Daiishi foundation plinths.
## - Distinct element aesthetics in GDD palette (Sakura, Storm, Ink, Shadow).
## - Unshaded additive volumetric lantern halo piercing 10.5m milk fog up to 35m (fog_disabled).
## - Plane crossing detection by player body (filtering out weapons and hands).
## - 45.0m distance reactivation rule.

signal gate_crossed(element: String, gate: ToriiGate)

const WET_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const HALO_SHADER := preload("res://src/shaders/torii_lantern_halo.gdshader")

## Lantern light per element. The halo is mixed over the pale fog (not added), so
## these are saturated, and the ink gate's is darker than the fog it sits in.
const HALO_COLORS := {
	Elements.SAKURA: Color(1.0, 0.22, 0.58),
	Elements.STORM: Color(0.12, 0.62, 1.0),
	Elements.INK: Color(0.14, 0.18, 0.62),
	Elements.SHADOW: Color(0.62, 0.18, 0.95),
}
const HALO_CORES := {
	Elements.SAKURA: Color(1.0, 0.86, 0.92),
	Elements.STORM: Color(0.88, 0.97, 1.0),
	Elements.INK: Color(0.42, 0.5, 0.95),
	Elements.SHADOW: Color(0.9, 0.7, 1.0),
}
## Seconds for the light to rise (a gate waking) and to drain (a spent gate).
const WAKE_SECONDS := 2.0
const SPEND_SECONDS := 0.9
const FLARE_SECONDS := 0.7

const APERTURE_WIDTH: float = 2.4
const APERTURE_HEIGHT: float = 3.2
const APERTURE_DEPTH: float = 0.8
const CLEARANCE_RADIUS: float = 3.2
const REACTIVATION_DISTANCE: float = 45.0
const PLAYER_BODY_LAYER: int = XRPlayer.COLLISION_LAYER_BODY

@export var element: String = Elements.SAKURA:
	set(val):
		element = val
		_apply_element_style()

@export var is_active: bool = true:
	set(val):
		is_active = val
		_apply_active_state()

var _gate_mesh: MeshInstance3D
var _stone_mesh: MeshInstance3D
var _lantern_core: MeshInstance3D
var _halo_mesh: MeshInstance3D
var _crossing_area: Area3D
var _static_body: StaticBody3D

var _gate_mat: ShaderMaterial
var _stone_mat: ShaderMaterial
var _lantern_mat: StandardMaterial3D
var _halo_mat: ShaderMaterial

var _tracked_bodies: Dictionary = {} # Node -> Vector3 (previous pos)
var _player_ref: Node3D = null
var _prev_player_pos: Vector3 = Vector3.INF
## Lantern light: 0 dormant .. 1 awake, plus a short flare when the gate is crossed.
var _glow: float = 1.0
var _flare: float = 0.0
var _glow_ready := false


func _ready() -> void:
	add_to_group("torii_gates")
	_build_components()
	_apply_element_style()
	_apply_active_state()


func _build_components() -> void:
	# 1. Authentic Shinto Timber Mesh (Kasagi, Shimaki, Nuki, Gakuzuka, Hashira)
	if _gate_mesh == null:
		_gate_mesh = MeshInstance3D.new()
		_gate_mesh.name = "TimberMesh"
		_gate_mesh.mesh = _build_authentic_torii_mesh()
		_gate_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_gate_mesh)

	_gate_mat = ShaderMaterial.new()
	_gate_mat.shader = WET_SHADER
	_gate_mat.set_shader_parameter("roughness_dry", 0.78)
	_gate_mat.set_shader_parameter("roughness_wet", 0.62)
	_gate_mat.set_shader_parameter("wetness", 0.28)
	_gate_mat.set_shader_parameter("waterline_y", -10.0)
	_gate_mat.set_shader_parameter("fill", 0.35)
	_gate_mat.set_shader_parameter("specular_scale", 0.0)
	_gate_mat.set_shader_parameter("fog_fill", 0.22)
	_gate_mat.set_shader_parameter("procedural_ao", 0.65)
	_gate_mesh.material_override = _gate_mat

	# 2. Carved Granite Daiishi Foundation Plinths
	if _stone_mesh == null:
		_stone_mesh = MeshInstance3D.new()
		_stone_mesh.name = "StonePlinths"
		_stone_mesh.mesh = _build_daiishi_mesh()
		_stone_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_stone_mesh)

	_stone_mat = ShaderMaterial.new()
	_stone_mat.shader = WET_SHADER
	_stone_mat.set_shader_parameter("base_color", Color(0.18, 0.19, 0.20))
	_stone_mat.set_shader_parameter("roughness_dry", 0.90)
	_stone_mat.set_shader_parameter("roughness_wet", 0.75)
	_stone_mat.set_shader_parameter("wetness", 0.35)
	_stone_mat.set_shader_parameter("procedural_ao", 0.80)
	_stone_mesh.material_override = _stone_mat

	# 3. Static collision: 2 pillars, 2 stone plinths, and top lintel beams
	if _static_body == null:
		_static_body = StaticBody3D.new()
		_static_body.name = "ToriiCollision"
		_static_body.collision_layer = 1 | 64  # Environment & Trunk layer
		_static_body.collision_mask = 0
		add_child(_static_body)

		# Left Pillar (slightly inclined)
		var left_col := CollisionShape3D.new()
		var left_cyl := CylinderShape3D.new()
		left_cyl.radius = 0.20
		left_cyl.height = 2.8
		left_col.shape = left_cyl
		left_col.position = Vector3(-1.13, 1.75, 0.0)
		_static_body.add_child(left_col)

		# Right Pillar (slightly inclined)
		var right_col := CollisionShape3D.new()
		var right_cyl := CylinderShape3D.new()
		right_cyl.radius = 0.20
		right_cyl.height = 2.8
		right_col.shape = right_cyl
		right_col.position = Vector3(1.13, 1.75, 0.0)
		_static_body.add_child(right_col)

		# Left Stone Base
		var left_stone := CollisionShape3D.new()
		var left_stone_cyl := CylinderShape3D.new()
		left_stone_cyl.radius = 0.28
		left_stone_cyl.height = 0.36
		left_stone.shape = left_stone_cyl
		left_stone.position = Vector3(-1.15, 0.18, 0.0)
		_static_body.add_child(left_stone)

		# Right Stone Base
		var right_stone := CollisionShape3D.new()
		var right_stone_cyl := CylinderShape3D.new()
		right_stone_cyl.radius = 0.28
		right_stone_cyl.height = 0.36
		right_stone.shape = right_stone_cyl
		right_stone.position = Vector3(1.15, 0.18, 0.0)
		_static_body.add_child(right_stone)

		# Lintel Beam
		var beam_col := CollisionShape3D.new()
		var beam_box := BoxShape3D.new()
		beam_box.size = Vector3(3.4, 0.55, 0.45)
		beam_col.shape = beam_box
		beam_col.position = Vector3(0.0, 3.12, 0.0)
		_static_body.add_child(beam_col)

	# 4. Hanging Lantern (Hexagonal Tōrō)
	var lantern_anchor := Node3D.new()
	lantern_anchor.name = "Lantern"
	lantern_anchor.position = Vector3(-0.95, 2.38, 0.0)
	add_child(lantern_anchor)

	_lantern_core = MeshInstance3D.new()
	_lantern_core.name = "LanternCore"
	_lantern_core.mesh = _lantern_mesh()
	_lantern_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lantern_mat = StandardMaterial3D.new()
	_lantern_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lantern_mat.albedo_texture = _paper_texture()
	_lantern_mat.emission_texture = _paper_texture()
	_lantern_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lantern_core.material_override = _lantern_mat
	lantern_anchor.add_child(_lantern_core)

	# Volumetric Lantern Halo (fog_disabled to pierce milk fog)
	_halo_mesh = MeshInstance3D.new()
	_halo_mesh.name = "VolumetricHalo"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 5.2)
	_halo_mesh.mesh = quad
	_halo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = HALO_SHADER
	_halo_mesh.material_override = _halo_mat
	lantern_anchor.add_child(_halo_mesh)

	# 6. Crossing Trigger Volume (detects player body layer 2 + weapons layer 4/16)
	if _crossing_area == null:
		_crossing_area = Area3D.new()
		_crossing_area.name = "CrossingArea"
		_crossing_area.collision_layer = 0
		_crossing_area.collision_mask = PLAYER_BODY_LAYER
		_crossing_area.monitorable = false
		add_child(_crossing_area)

		var area_shape := CollisionShape3D.new()
		var area_box := BoxShape3D.new()
		area_box.size = Vector3(APERTURE_WIDTH, APERTURE_HEIGHT, APERTURE_DEPTH)
		area_shape.shape = area_box
		area_shape.position = Vector3(0.0, APERTURE_HEIGHT * 0.5, 0.0)
		_crossing_area.add_child(area_shape)

		_crossing_area.body_entered.connect(_on_body_entered)
		_crossing_area.body_exited.connect(_on_body_exited)


func _build_authentic_torii_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Kasagi: Curved top roof lintel with pronounced sori curvature and flared eaves
	_add_curved_beam(st, 3.6, 0.28, 0.30, 3.12, 0.14, 0.08)

	# 2. Shimaki: Secondary curved lintel directly below kasagi
	_add_curved_beam(st, 3.15, 0.18, 0.24, 2.94, 0.08, 0.02)

	# 3. Nuki: Lower horizontal tie-beam piercing through both pillars with projecting ends
	_add_box(st, Vector3(0.0, 2.38, 0.0), Vector3(3.0, 0.20, 0.14))
	# Kusabi (wedges outside pillars)
	_add_box(st, Vector3(-1.32, 2.38, 0.0), Vector3(0.06, 0.26, 0.16))
	_add_box(st, Vector3(1.32, 2.38, 0.0), Vector3(0.06, 0.26, 0.16))

	# 4. Gakuzuka: Center tablet strut connecting Nuki to Shimaki
	_add_box(st, Vector3(0.0, 2.66, 0.0), Vector3(0.24, 0.38, 0.10))

	# 5. Hashira: Two pillars with subtle inward inclination (uchikorobi) and taper
	_add_tapered_pillar(st, Vector3(-1.15, 0.35, 0.0), Vector3(-1.11, 2.94, 0.0), 0.18, 0.15, 12)
	_add_tapered_pillar(st, Vector3(1.15, 0.35, 0.0), Vector3(1.11, 2.94, 0.0), 0.18, 0.15, 12)

	st.generate_normals()
	return st.commit()


func _build_daiishi_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Octagonal carved granite plinths at base of pillars
	_add_octagonal_plinth(st, Vector3(-1.15, 0.0, 0.0), 0.26, 0.35)
	_add_octagonal_plinth(st, Vector3(1.15, 0.0, 0.0), 0.26, 0.35)
	st.generate_normals()
	return st.commit()


func _add_curved_beam(st: SurfaceTool, length: float, height: float, depth: float, base_y: float, sori_height: float, end_flare: float) -> void:
	var segments := 16
	var hx := length * 0.5
	var hy := height * 0.5
	var hz := depth * 0.5

	var prev_ring: Array[Vector3] = []
	for i in range(segments + 1):
		var u := float(i) / float(segments)
		var x := -hx + u * length
		var nx := x / hx
		var sori := nx * nx * sori_height
		if absf(nx) > 0.85:
			sori += pow((absf(nx) - 0.85) / 0.15, 2.0) * end_flare

		var cy := base_y + sori
		var ring: Array[Vector3] = [
			Vector3(x, cy + hy, -hz),
			Vector3(x, cy + hy, hz),
			Vector3(x, cy - hy, hz),
			Vector3(x, cy - hy, -hz),
		]

		if i > 0:
			for k in 4:
				var next_k := (k + 1) % 4
				st.add_vertex(prev_ring[k])
				st.add_vertex(ring[k])
				st.add_vertex(ring[next_k])

				st.add_vertex(prev_ring[k])
				st.add_vertex(ring[next_k])
				st.add_vertex(prev_ring[next_k])

		if i == 0:
			# Left end cap
			st.add_vertex(ring[0])
			st.add_vertex(ring[2])
			st.add_vertex(ring[1])

			st.add_vertex(ring[0])
			st.add_vertex(ring[3])
			st.add_vertex(ring[2])
		elif i == segments:
			# Right end cap
			st.add_vertex(ring[0])
			st.add_vertex(ring[1])
			st.add_vertex(ring[2])

			st.add_vertex(ring[0])
			st.add_vertex(ring[2])
			st.add_vertex(ring[3])

		prev_ring = ring


func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var c := center
	var v: Array[Vector3] = [
		Vector3(-hx, -hy, -hz) + c, Vector3(hx, -hy, -hz) + c,
		Vector3(hx, hy, -hz) + c, Vector3(-hx, hy, -hz) + c,
		Vector3(-hx, -hy, hz) + c, Vector3(hx, -hy, hz) + c,
		Vector3(hx, hy, hz) + c, Vector3(-hx, hy, hz) + c,
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[1]])
		st.add_vertex(v[f[2]])

		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[2]])
		st.add_vertex(v[f[3]])


func _add_tapered_pillar(st: SurfaceTool, base_p: Vector3, top_p: Vector3, r_base: float, r_top: float, sides: int = 12) -> void:
	var base_ring: Array[Vector3] = []
	var top_ring: Array[Vector3] = []
	for i in range(sides):
		var ang := float(i) / float(sides) * TAU
		var ca := cos(ang)
		var sa := sin(ang)
		base_ring.append(base_p + Vector3(ca * r_base, 0.0, sa * r_base))
		top_ring.append(top_p + Vector3(ca * r_top, 0.0, sa * r_top))

	for i in range(sides):
		var next_i := (i + 1) % sides
		st.add_vertex(base_ring[i])
		st.add_vertex(top_ring[i])
		st.add_vertex(top_ring[next_i])

		st.add_vertex(base_ring[i])
		st.add_vertex(top_ring[next_i])
		st.add_vertex(base_ring[next_i])


func _add_octagonal_plinth(st: SurfaceTool, base_center: Vector3, radius: float, height: float) -> void:
	var sides := 8
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	var chamfer_top: Array[Vector3] = []

	var r_top := radius * 0.92
	var h_chamfer := height * 0.12

	for i in range(sides):
		var ang := (float(i) + 0.5) / float(sides) * TAU
		var ca := cos(ang)
		var sa := sin(ang)
		bottom.append(base_center + Vector3(ca * radius, 0.0, sa * radius))
		top.append(base_center + Vector3(ca * radius, height - h_chamfer, sa * radius))
		chamfer_top.append(base_center + Vector3(ca * r_top, height, sa * r_top))

	for i in range(sides):
		var next_i := (i + 1) % sides
		st.add_vertex(bottom[i])
		st.add_vertex(top[i])
		st.add_vertex(top[next_i])

		st.add_vertex(bottom[i])
		st.add_vertex(top[next_i])
		st.add_vertex(bottom[next_i])

		st.add_vertex(top[i])
		st.add_vertex(chamfer_top[i])
		st.add_vertex(chamfer_top[next_i])

		st.add_vertex(top[i])
		st.add_vertex(chamfer_top[next_i])
		st.add_vertex(top[next_i])

	var center_top := base_center + Vector3(0.0, height, 0.0)
	for i in range(sides):
		var next_i := (i + 1) % sides
		st.add_vertex(center_top)
		st.add_vertex(chamfer_top[i])
		st.add_vertex(chamfer_top[next_i])


static var _paper: ImageTexture
static var _lantern_mesh_cache: ArrayMesh


## Andon paper: pale, a little brighter in the middle, in a dark timber frame
## (top, bottom, sides, one cross rib). Shared by every gate.
## Paper of a hexagonal andon: six panels (16 px each) with dark ribs between
## them, soft light towards the middle of each panel, dark bands top and bottom.
static func _paper_texture() -> ImageTexture:
	if _paper == null:
		var w := 96
		var h := 64
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		for y in h:
			for x in w:
				var px := float(x % 16) / 16.0
				var across := 1.0 - absf(px - 0.5) * 2.0
				var down := 1.0 - absf(float(y) - h * 0.5) / (h * 0.5)
				var c := 0.62 + 0.38 * across * (0.55 + 0.45 * down)
				var rib := x % 16 < 2
				var band := y < 6 or y >= h - 6
				img.set_pixel(x, y, Color(0.05, 0.04, 0.04) if (rib or band) else Color(c, c, c))
		_paper = ImageTexture.create_from_image(img)
	return _paper


## One-surface hexagonal paper lantern: a slightly tapered body, a hexagonal roof
## with an overhang and a dark base. A single draw call (the old box was a flat
## square at 6 m). UV rows 0..6/64 and 58/64..1 are the dark bands of the texture.
static func _lantern_mesh() -> ArrayMesh:
	if _lantern_mesh_cache != null:
		return _lantern_mesh_cache
	const SIDES := 6
	const R_BOTTOM := 0.095
	const R_TOP := 0.112
	const Y_BOTTOM := -0.115
	const Y_TOP := 0.115
	const ROOF_R := 0.185
	const ROOF_PEAK := 0.215
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SIDES:
		var a0 := TAU * float(i) / SIDES
		var a1 := TAU * float(i + 1) / SIDES
		var u0 := float(i) / SIDES
		var u1 := float(i + 1) / SIDES
		var b0 := Vector3(cos(a0) * R_BOTTOM, Y_BOTTOM, sin(a0) * R_BOTTOM)
		var b1 := Vector3(cos(a1) * R_BOTTOM, Y_BOTTOM, sin(a1) * R_BOTTOM)
		var t0 := Vector3(cos(a0) * R_TOP, Y_TOP, sin(a0) * R_TOP)
		var t1 := Vector3(cos(a1) * R_TOP, Y_TOP, sin(a1) * R_TOP)
		_lantern_quad(st, [b0, b1, t1, t0], [Vector2(u0, 0.92), Vector2(u1, 0.92), Vector2(u1, 0.08), Vector2(u0, 0.08)])
		# Roof: an overhanging underside, then the pitched hexagonal cap.
		var o0 := Vector3(cos(a0) * ROOF_R, Y_TOP, sin(a0) * ROOF_R)
		var o1 := Vector3(cos(a1) * ROOF_R, Y_TOP, sin(a1) * ROOF_R)
		var dark := Vector2(u0, 0.02)
		_lantern_quad(st, [t0, t1, o1, o0], [dark, dark, dark, dark])
		var peak := Vector3(0.0, ROOF_PEAK, 0.0)
		for v: Vector3 in [o0, o1, peak]:
			st.set_uv(dark)
			st.add_vertex(v)
		# Base plate.
		for v: Vector3 in [b1, b0, Vector3(0.0, Y_BOTTOM, 0.0)]:
			st.set_uv(Vector2(u0, 0.98))
			st.add_vertex(v)
	_lantern_mesh_cache = st.commit()
	return _lantern_mesh_cache


static func _lantern_quad(st: SurfaceTool, v: Array, uv: Array) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(v[i])


func _apply_element_style() -> void:
	if _gate_mat == null or _lantern_mat == null or _halo_mat == null:
		return
	var timber_color: Color
	var accent: Color
	match element:
		Elements.SAKURA:
			timber_color = Color(0.28, 0.06, 0.05)
			accent = Elements.accent_color(Elements.SAKURA)
		Elements.STORM:
			timber_color = Color(0.08, 0.08, 0.10)
			accent = Elements.accent_color(Elements.STORM)
		Elements.INK:
			timber_color = Color(0.03, 0.03, 0.03)
			accent = Elements.accent_color(Elements.INK)
		Elements.SHADOW:
			timber_color = Color(0.18, 0.16, 0.22)
			accent = Elements.accent_color(Elements.SHADOW)
		_:
			timber_color = Color(0.24, 0.08, 0.07)
			accent = Color(0.9, 0.85, 0.8)

	_gate_mat.set_shader_parameter("base_color", timber_color)
	_halo_mat.set_shader_parameter("glow_color", HALO_COLORS.get(element, accent))
	_halo_mat.set_shader_parameter("core_color", HALO_CORES.get(element, Color(1.0, 0.95, 0.9)))
	_halo_mat.set_shader_parameter("phase", fposmod(global_position.x * 0.37 + global_position.z * 0.53, TAU) if is_inside_tree() else 0.0)
	_apply_glow()


func _apply_active_state() -> void:
	if _lantern_mat == null or _halo_mat == null:
		return
	if not _glow_ready:
		# First look: show the state as it is, no transition.
		_glow_ready = true
		_glow = 1.0 if is_active else 0.0
		_apply_glow()
		set_process(false)
	elif not is_active and _glow > 0.0:
		_flare = 1.0  # the light flares as the player passes through, then drains
		set_process(true)
	else:
		set_process(true)  # waking up: rises over WAKE_SECONDS


## Spent gates drain and wake gently (real time, not slow-mo), then stop processing.
func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	var target := 1.0 if is_active else 0.0
	var rate := (1.0 / WAKE_SECONDS) if is_active else (1.0 / SPEND_SECONDS)
	_glow = move_toward(_glow, target, real * rate)
	_flare = maxf(_flare - real / FLARE_SECONDS, 0.0)
	_apply_glow()
	if is_equal_approx(_glow, target) and _flare <= 0.0:
		set_process(false)


func _apply_glow() -> void:
	if _lantern_mat == null or _halo_mat == null:
		return
	var accent := Elements.accent_color(element)
	var level := _glow + _flare * 1.4
	_halo_mat.set_shader_parameter("intensity", level)
	if _halo_mesh:
		_halo_mesh.visible = level > 0.01
	# A spent lantern is dull paper: a trace of its colour, no light.
	_lantern_mat.albedo_color = Color(0.09, 0.085, 0.09).lerp(accent, clampf(level, 0.0, 1.0))
	_lantern_mat.emission_enabled = level > 0.02
	_lantern_mat.emission = accent
	_lantern_mat.emission_energy_multiplier = 0.4 + 1.1 * level
	# A lit lantern stays visible in the mist; a spent one fades into it.
	_lantern_mat.disable_fog = level > 0.15


func _is_weapon_or_hand(body: Node) -> bool:
	if body == null:
		return false
	if body == self or body == _static_body or body.get_parent() == self or body.owner == self:
		return true
	if body is BladeBody or body is HeldWeapon or body is XRController3D:
		return true
	if body.is_in_group("weapons") or body.is_in_group("player_weapons") or body.is_in_group("hands"):
		return true
	var p := body.get_parent()
	if p:
		if p is HeldWeapon or p is BladeBody or p is XRController3D:
			return true
		if p.is_in_group("weapons") or p.is_in_group("player_weapons") or p.is_in_group("hands"):
			return true
	return false


func _is_player_body(body: Node) -> bool:
	if body == null:
		return false
	if _is_weapon_or_hand(body):
		return false
	if body.is_in_group("player_body"):
		return true
	if body is XRPlayer or body is DesktopPlayer:
		return true
	if body is CollisionObject3D and ((body as CollisionObject3D).collision_layer & PLAYER_BODY_LAYER) != 0:
		return true
	return false


func _on_body_entered(body: Node3D) -> void:
	if not _is_player_body(body):
		return
	_tracked_bodies[body] = body.global_position


func _on_body_exited(body: Node3D) -> void:
	_tracked_bodies.erase(body)


func _physics_process(_delta: float) -> void:
	var player_pos := _resolve_player_pos()

	if is_active:
		# Check plane crossing for tracked bodies
		for body in _tracked_bodies.keys():
			if not is_instance_valid(body):
				_tracked_bodies.erase(body)
				continue
			var p_curr: Vector3 = body.global_position
			var p_prev: Vector3 = _tracked_bodies.get(body, p_curr)
			_tracked_bodies[body] = p_curr
			if _eval_crossing(p_prev, p_curr):
				trigger_cross(body)
				return

		# Check direct player plane crossing if player position is known
		if player_pos != Vector3.INF and _prev_player_pos != Vector3.INF:
			if global_position.distance_to(player_pos) <= 4.0:
				if _eval_crossing(_prev_player_pos, player_pos):
					trigger_cross(_player_ref)
					return
		_prev_player_pos = player_pos
	else:
		# 45.0m Reactivation Rule: reactivates iff player moves >= 45.0m away
		if player_pos != Vector3.INF:
			var d := global_position.distance_to(player_pos)
			if d >= REACTIVATION_DISTANCE and _reactivation_clear():
				reactivate()


## A spent gate stays spent while a live gate stands too close to its spot (ToriiManager).
func _reactivation_clear() -> bool:
	var manager := get_parent() as ToriiManager
	return manager == null or manager.can_reactivate(self)


func _eval_crossing(prev_pos: Vector3, curr_pos: Vector3) -> bool:
	if prev_pos.distance_to(curr_pos) > 5.0:
		return false
	var l_curr := to_local(curr_pos)
	# 1. Direct aperture volume presence (with vertical tolerance for terrain slopes / head / feet)
	if absf(l_curr.x) <= APERTURE_WIDTH * 0.5 and l_curr.y >= -1.0 and l_curr.y <= APERTURE_HEIGHT + 1.0 and absf(l_curr.z) <= APERTURE_DEPTH:
		return true

	# 2. Continuous segment plane crossing
	var l_prev := to_local(prev_pos)
	if (l_prev.z > 0.0 and l_curr.z <= 0.0) or (l_prev.z < 0.0 and l_curr.z >= 0.0):
		var dz := l_curr.z - l_prev.z
		var alpha := -l_prev.z / dz if absf(dz) > 1e-5 else 0.5
		var cross_pt := l_prev.lerp(l_curr, alpha)
		if absf(cross_pt.x) <= APERTURE_WIDTH * 0.5 and cross_pt.y >= -1.0 and cross_pt.y <= APERTURE_HEIGHT + 1.0:
			return true
	return false


func trigger_cross(body: Node = null) -> void:
	if not is_active:
		return
	if body != null and not _is_player_body(body):
		return
	is_active = false
	_imbue_target(body)
	gate_crossed.emit(element, self)
	GameEvents.log_event("torii_gate_crossed", {"element": element, "position": global_position})
	if Sfx:
		Sfx.play_at("bonsho_gate", global_position + Vector3(0.0, 2.5, 0.0), -4.0, 14.0, 1.15)


var target_element_system: ElementSystem = null

## A crossing stores the gate's element as a charge (D21); the player spends it later.
func _imbue_target(_body: Node) -> void:
	if target_element_system and is_instance_valid(target_element_system):
		_store_charge(target_element_system)
		return
	var run := _find_run_game()
	if run and run.element_system and is_instance_valid(run.element_system):
		_store_charge(run.element_system)
		return
	if get_tree():
		var es := get_tree().get_first_node_in_group("element_system") as ElementSystem
		if es and is_instance_valid(es):
			_store_charge(es)
			return
		var scene := get_tree().current_scene
		if scene:
			for child in scene.get_children():
				if child is ElementSystem:
					_store_charge(child)
					return
	push_warning("ToriiGate: No ElementSystem found for element '%s'. Charge skipped." % element)


## Systems without a charge buffer fall back to an immediate imbue.
func _store_charge(es: ElementSystem) -> void:
	if es.has_method("add_charge"):
		es.add_charge(element)
	else:
		es.imbue(element)


func reactivate() -> void:
	if not is_active:
		is_active = true


var run_game: RunGame = null

func _find_run_game() -> RunGame:
	if run_game and is_instance_valid(run_game):
		return run_game
	var p: Node = get_parent()
	while p:
		if p is RunGame:
			run_game = p
			return run_game
		p = p.get_parent()
	var scene := get_tree().current_scene if get_tree() else null
	if scene:
		if scene is RunGame:
			run_game = scene
			return run_game
		for child in scene.get_children():
			if child is RunGame:
				run_game = child
				return run_game
	return null


func _resolve_player_pos() -> Vector3:
	if _player_ref and is_instance_valid(_player_ref):
		if _player_ref is XRPlayer:
			return (_player_ref as XRPlayer).feet_position()
		return _player_ref.global_position

	var run := _find_run_game()
	if run and run.player and is_instance_valid(run.player):
		_player_ref = run.player
		if _player_ref is XRPlayer:
			return (_player_ref as XRPlayer).feet_position()
		return _player_ref.global_position

	var p = get_tree().get_first_node_in_group("player")
	if p and is_instance_valid(p):
		_player_ref = p as Node3D
		return _player_ref.global_position
	return Vector3.INF


func set_player_reference(p: Node3D) -> void:
	_player_ref = p
	if _player_ref:
		_prev_player_pos = _resolve_player_pos()
