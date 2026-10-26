class_name SparkBurst
extends CPUParticles3D
## One-shot burst of glowing sparks (blade clashes, parries). CPU particles so
## it also works on the Compatibility renderer on Quest. Frees itself.


static func spawn(parent: Node, at: Vector3, normal: Vector3, color: Color, amount_: int = 24, speed: float = 3.0) -> SparkBurst:
	var s := SparkBurst.new()
	s.amount = amount_
	s.one_shot = true
	s.explosiveness = 0.95
	s.lifetime = 0.35
	s.direction = normal if normal.length_squared() > 0.001 else Vector3.UP
	s.spread = 70.0
	s.initial_velocity_min = speed * 0.5
	s.initial_velocity_max = speed
	s.gravity = Vector3(0, -6, 0)
	s.scale_amount_min = 0.5
	s.scale_amount_max = 1.1
	# Thin streaks stretched along their velocity read as hot metal, not confetti.
	s.particle_flag_align_y = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.005, 0.045)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.albedo_texture = _soft_streak()
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	s.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	s.color_ramp = ramp
	parent.add_child(s)
	s.global_position = at
	s.emitting = true
	s.finished.connect(s.queue_free)
	return s


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
