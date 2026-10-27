class_name SparkBurst
extends CPUParticles3D
## One-shot burst of glowing sparks (blade clashes, parries). CPU particles so
## it also works on the Compatibility renderer on Quest. Frees itself.


static func spawn(parent: Node, at: Vector3, normal: Vector3, color: Color, amount_: int = 24, speed: float = 3.0) -> SparkBurst:
	if parent != null and VfxPool:
		VfxPool.spawn_spark(parent, at, normal, color, amount_, speed)
		return null
	return _spawn_ephemeral(parent, at, normal, color, amount_, speed)


static func _spawn_ephemeral(parent: Node, at: Vector3, normal: Vector3, color: Color, amount_: int, speed: float) -> SparkBurst:
	var s := SparkBurst.new()
	s.setup_pooled(_shared_quad_mesh(), _shared_base_mat())
	s.fire_from_pool(at, normal, color, amount_, speed)
	parent.add_child(s)
	s.finished.connect(s.queue_free)
	return s


func setup_pooled(quad: QuadMesh, mat: StandardMaterial3D) -> void:
	one_shot = true
	explosiveness = 0.95
	lifetime = 0.35
	spread = 70.0
	gravity = Vector3(0, -6, 0)
	scale_amount_min = 0.5
	scale_amount_max = 1.1
	particle_flag_align_y = true
	mesh = quad
	material_override = mat
	if color_ramp == null:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		color_ramp = ramp


func fire_from_pool(at: Vector3, normal: Vector3, color: Color, amount_: int, speed: float) -> void:
	amount = amount_
	direction = normal if normal.length_squared() > 0.001 else Vector3.UP
	initial_velocity_min = speed * 0.5
	initial_velocity_max = speed
	if material_override is StandardMaterial3D:
		(material_override as StandardMaterial3D).albedo_color = color
	global_position = at
	restart()
	emitting = true


static func shared_streak_texture() -> Texture2D:
	return _soft_streak()


static var _quad_mesh: QuadMesh
static var _base_mat: StandardMaterial3D


static func _shared_quad_mesh() -> QuadMesh:
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(0.005, 0.045)
	return _quad_mesh


static func _shared_base_mat() -> StandardMaterial3D:
	if _base_mat == null:
		_base_mat = StandardMaterial3D.new()
		_base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_base_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_base_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_base_mat.albedo_texture = _soft_streak()
		_base_mat.vertex_color_use_as_albedo = true
		_base_mat.disable_fog = true
	return _base_mat


static var _streak_tex: Texture2D


static func _soft_streak() -> Texture2D:
	if _streak_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 16
		t.height = 64
		_streak_tex = t
	return _streak_tex
