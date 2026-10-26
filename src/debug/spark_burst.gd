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
	s.scale_amount_min = 0.6
	s.scale_amount_max = 1.2
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.012, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = color
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
