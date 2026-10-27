class_name ElementFirework
extends RefCounted
## Restrained elemental death burst (GDD VFX, NIGHT_PLAN §7): sparse neon sparks
## on a dark base — no particle spam.

const MAX_PARTICLES := 36


static func spawn(parent: Node, at: Vector3, element: String, scale: float = 1.0) -> void:
	if parent == null:
		return
	var col := _burst_color(element)
	var vis := scale * 1.14
	var up := Vector3.UP
	SparkBurst.spawn(parent, at, up, col * 1.35, int(18 * vis), 3.65 * vis)
	SparkBurst.spawn(parent, at, Vector3(0.2, 0.85, 0.1).normalized(), col * 1.05, int(12 * vis), 2.85 * vis)
	if VfxPool:
		VfxPool.spawn_firework_flash(parent, at, col, vis)
	else:
		_fog_flash_ephemeral(parent, at, col, vis)
	if VfxPool:
		VfxPool.spawn_element_ring(parent, at, col, scale * 1.08)
	else:
		_ring_ephemeral(parent, at, col, scale)
	Sfx.play_at("firework", at, -7.0, 4.5 * scale, clampf(0.9 + scale * 0.12, 0.85, 1.25))


static func _fog_flash_ephemeral(parent: Node, at: Vector3, col: Color, vis: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = col.lerp(Color(1.0, 0.92, 0.95), 0.22)
	lamp.light_energy = 2.4 * vis
	lamp.omni_range = 3.8 * vis
	lamp.omni_attenuation = 1.35
	lamp.shadow_enabled = false
	parent.add_child(lamp)
	lamp.global_position = at + Vector3(0.0, 0.35, 0.0)
	var tw := parent.get_tree().create_tween()
	tw.tween_property(lamp, "light_energy", 0.0, 0.16)
	tw.tween_callback(lamp.queue_free)


static func _burst_color(element: String) -> Color:
	match element:
		Elements.STORM:
			return Color(0.42, 0.82, 1.55)
		Elements.INK:
			return Color(0.55, 0.68, 1.25)
		Elements.SAKURA:
			return Color(1.35, 0.32, 0.72)
		Elements.SHADOW:
			return Color(0.72, 0.22, 1.35)
		Elements.BLACK_LIGHTNING:
			return Color(0.22, 0.38, 1.45)
		Elements.PHANTOM_PETALS:
			return Color(1.05, 0.28, 0.82)
		_:
			return Color(1.45, 0.38, 0.22)


static func _ring_ephemeral(parent: Node, at: Vector3, col: Color, scale: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = mini(MAX_PARTICLES, int(22 * scale))
	p.one_shot = true
	p.explosiveness = 0.92
	p.lifetime = 0.42
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.6 * scale
	p.initial_velocity_max = 3.1 * scale
	p.gravity = Vector3(0, -2.5, 0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.006, 0.038)
	p.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = col * 0.75
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	p.material_override = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
