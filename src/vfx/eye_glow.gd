class_name EyeGlow
extends RefCounted
## Fog-piercing eye points for yōkai and the Oni (src/shaders/eye_glow.gdshader).

const SHADER := preload("res://src/shaders/eye_glow.gdshader")

static var _quad: QuadMesh


## Adds a pair of glow points centered at [param local_pos] under [param parent],
## [param eye_sep] apart along the parent's X axis. Returns it so the owner can
## set its "glow" instance parameter (tell, dissolve).
static func attach(parent: Node3D, local_pos: Vector3, color: Color, eye_sep: float = 0.088, base_size: float = 0.05) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("glow_color", Color(color.r, color.g, color.b))
	mat.set_shader_parameter("base_size", base_size)
	mat.set_shader_parameter("eye_sep", eye_sep)
	var mi := MeshInstance3D.new()
	mi.name = "EyeGlow"
	mi.mesh = _quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The vertex shader billboards and resizes it; keep it from being culled.
	mi.extra_cull_margin = 2.0
	mi.position = local_pos
	parent.add_child(mi)
	return mi


static func set_glow(points: Array, value: float) -> void:
	for p in points:
		if is_instance_valid(p):
			(p as GeometryInstance3D).set_instance_shader_parameter("glow", value)


static func set_color(points: Array, color: Color) -> void:
	for p in points:
		if is_instance_valid(p):
			((p as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("glow_color", Color(color.r, color.g, color.b))
