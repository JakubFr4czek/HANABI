class_name StormLightning
extends MeshInstance3D
## Procedural distant branching lightning for the Dojo of the Storm (GDD §9).
## Builds a multi-branch 3D ribbon mesh with `lightning_bolt.gdshader` (no particles)
## and drives the brief scene-wide flash: the `storm_flash` / `storm_flash_dir`
## global shader uniforms (sky, water, mist, seal, katana), the fog and ambient
## light, and an optional flash light that is only switched on during a strike.

signal struck(direction: Vector2)

const BOLT_SHADER := preload("res://src/shaders/lightning_bolt.gdshader")

@export var min_interval := 3.2
@export var max_interval := 6.8
@export var initial_delay := 1.1
@export var strike_distance := 52.0
@export var top_height := 36.0
@export var bottom_height := -0.5

var flash_light: Light3D = null
var world_environment: Environment = null
var base_fog_light_color := Color(0.16, 0.16, 0.27, 1.0)
var base_ambient_energy := 0.22
var flash_fog_tint := Color(0.55, 0.72, 1.0, 1.0)
var current_intensity := 0.0

var _mesh := ImmediateMesh.new()
var _material := ShaderMaterial.new()
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _strike_age := -1.0
var _strike_duration := 0.34


func _ready() -> void:
	_rng.seed = 0x48414E414249  # deterministic sequence for repeatable visuals
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shader = BOLT_SHADER
	material_override = _material
	_timer = initial_delay
	_set_flash(0.0)


func _process(delta: float) -> void:
	if _strike_age >= 0.0:
		_strike_age += delta
		if _strike_age >= _strike_duration:
			_strike_age = -1.0
			_mesh.clear_surfaces()
			_set_flash(0.0)
		else:
			# Double-pulse flicker characteristic of cloud-to-water lightning.
			var t := _strike_age / _strike_duration
			var main_pulse := exp(-pow((t - 0.14) / 0.11, 2.0))
			var restrike := 0.78 * exp(-pow((t - 0.46) / 0.14, 2.0))
			var fade := clampf(main_pulse + restrike, 0.0, 1.0)
			_set_flash(fade)
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = _rng.randf_range(min_interval, max_interval)
		trigger_strike()


## Trigger a distant branching lightning bolt at [param azimuth_rad] (default:
## behind the giant torii in the north-northwest sky).
func trigger_strike(azimuth_rad: float = INF) -> void:
	var angle := azimuth_rad
	if is_inf(angle):
		# Frame the bolts in the northern storm sky behind the giant torii.
		var choices := [-0.32, 0.28, -0.55, 0.48, -0.14]
		angle = choices[_rng.randi() % choices.size()] + _rng.randf_range(-0.06, 0.06)
	var dir_xz := Vector2(sin(angle), -cos(angle)).normalized()
	var origin_top := Vector3(dir_xz.x * strike_distance, top_height, dir_xz.y * strike_distance)
	var origin_bot := Vector3(
		dir_xz.x * strike_distance + _rng.randf_range(-4.5, 4.5),
		bottom_height,
		dir_xz.y * strike_distance + _rng.randf_range(-2.0, 2.0)
	)
	_build_bolt_mesh(origin_top, origin_bot, Vector3(-dir_xz.y, 0.0, dir_xz.x))
	RenderingServer.global_shader_parameter_set("storm_flash_dir", dir_xz)
	_strike_age = 0.0
	_set_flash(1.0)
	struck.emit(dir_xz)


func _set_flash(value: float) -> void:
	current_intensity = value
	_material.set_shader_parameter("intensity", value)
	RenderingServer.global_shader_parameter_set("storm_flash", value)
	if flash_light:
		flash_light.visible = value > 0.01
		flash_light.light_energy = value * 1.6
	if world_environment:
		world_environment.fog_light_color = base_fog_light_color.lerp(flash_fog_tint, value * 0.22)
		world_environment.ambient_light_energy = base_ambient_energy * (1.0 + value * 1.5)


func _build_bolt_mesh(top: Vector3, bottom: Vector3, tangent: Vector3) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var trunk_pts := _subdivide_path(top, bottom, 16, 2.6, tangent)
	_append_ribbon(trunk_pts, 0.52, 0.18, tangent)

	# 4 forked branches splitting off the main trunk.
	for b in 4:
		var idx := _rng.randi_range(3, trunk_pts.size() - 5)
		var start_pt: Vector3 = trunk_pts[idx]
		var side := -1.0 if (b % 2 == 0) else 1.0
		var branch_len := _rng.randf_range(7.0, 13.5)
		var end_pt := start_pt + tangent * (side * _rng.randf_range(4.0, 8.5)) + Vector3(0.0, -branch_len, 0.0)
		var branch_pts := _subdivide_path(start_pt, end_pt, 7, 1.1, tangent)
		_append_ribbon(branch_pts, 0.26, 0.04, tangent)

	_mesh.surface_end()


func _subdivide_path(a: Vector3, b: Vector3, steps: int, jitter: float, tangent: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var offset := Vector3.ZERO
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var base := a.lerp(b, t)
		var envelope := sin(t * PI)
		if i > 0 and i < steps:
			offset = offset * 0.55 + (tangent * _rng.randf_range(-1.0, 1.0) + Vector3(0.0, _rng.randf_range(-0.25, 0.25), 0.0)) * jitter
		pts.append(base + offset * envelope)
	return pts


func _append_ribbon(pts: Array[Vector3], width_start: float, width_end: float, tangent: Vector3) -> void:
	var n := pts.size()
	for i in range(n - 1):
		var t0 := float(i) / float(n - 1)
		var t1 := float(i + 1) / float(n - 1)
		var w0 := lerpf(width_start, width_end, t0) * 0.5
		var w1 := lerpf(width_start, width_end, t1) * 0.5
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var seg_dir := (p1 - p0).normalized()
		var side := seg_dir.cross(tangent.cross(Vector3.UP)).normalized()
		if side.length_squared() < 0.1:
			side = tangent

		var l0 := p0 - side * w0
		var r0 := p0 + side * w0
		var l1 := p1 - side * w1
		var r1 := p1 + side * w1

		_v(l0, Vector2(0.0, t0)); _v(r0, Vector2(1.0, t0)); _v(r1, Vector2(1.0, t1))
		_v(l0, Vector2(0.0, t0)); _v(r1, Vector2(1.0, t1)); _v(l1, Vector2(0.0, t1))


func _v(pos: Vector3, uv: Vector2) -> void:
	_mesh.surface_set_uv(uv)
	_mesh.surface_add_vertex(pos)
