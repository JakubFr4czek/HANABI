class_name StormRain
extends Node3D
## Rain for the Dojo of the Storm: a box of falling streaks that follows the
## active camera (position only, so it never swims with head rotation in VR),
## splashes on the stone platform, and drips from blade tips. GPU particles:
## one draw call each, also on the Compatibility renderer.

const STREAK_SHADER := preload("res://src/shaders/rain_streak.gdshader")

@export var rain_amount := 1400
@export var splash_amount := 160
@export var platform_radius := 4.9
@export var platform_height := 0.01

var rain: GPUParticles3D
var splashes: GPUParticles3D


func _ready() -> void:
	rain = _make_rain()
	add_child(rain)
	rain.top_level = true
	splashes = _make_splashes()
	add_child(splashes)
	splashes.position = Vector3(0.0, platform_height, 0.0)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		rain.global_position = cam.global_position + Vector3(0.0, 5.5, 0.0)


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = rain_amount
	p.lifetime = 0.9
	p.preprocess = 1.0
	p.fixed_fps = 0
	p.interpolate = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-8, -14, -8), Vector3(16, 16, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(6.0, 0.6, 6.0)
	pm.direction = Vector3(0.05, -1.0, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 12.5
	pm.gravity = Vector3(0, -3.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(0.007, 0.42), 0.45)
	return p


func _make_splashes() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Splashes"
	p.amount = splash_amount
	p.lifetime = 0.28
	p.fixed_fps = 0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-5.5, -0.5, -5.5), Vector3(11, 1.5, 11))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = platform_radius
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.0
	pm.direction = Vector3.UP
	pm.spread = 28.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(0.006, 0.02), 0.35)
	return p


## Slow drips falling off `weapon`'s tip; flung off with the swing.
static func add_blade_drips(weapon: Node3D, tip: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "BladeDrips"
	p.amount = 3
	p.lifetime = 0.7
	p.fixed_fps = 0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-2, -3, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.DOWN
	pm.spread = 10.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.inherit_velocity_ratio = 0.6
	pm.gravity = Vector3(0, -9.8, 0)
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(0.003, 0.03), 0.6)
	weapon.add_child(p)
	p.position = tip
	return p


static func _quad(size: Vector2, intensity: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var m := ShaderMaterial.new()
	m.shader = STREAK_SHADER
	m.set_shader_parameter("intensity", intensity)
	q.material = m
	return q
