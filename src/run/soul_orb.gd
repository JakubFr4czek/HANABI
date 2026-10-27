class_name SoulOrb
extends Node3D
## Hitodama (soul drop, docs/GDD.md §6, NIGHT_PLAN.md §1).
##
## Spawned in clusters when a yōkai dies. Scatters outward with an initial arc,
## hovers and bobs like a ghostly spirit flame with a delicate wisp trail, then
## curves into the player when within the soul magnet radius (or after a short
## linger so distant kills are never lost in the water).

signal collected(xp_value: int, element: String)

const SHADER := preload("res://src/shaders/soul_orb.gdshader")

@export var xp_value := 6
@export var element := Elements.NONE
@export var hover_height := 0.92
@export var collect_distance := 0.48
## Seconds after spawning before the orb can be magnetized (lets the scatter burst read).
@export var scatter_time := 0.26
## Seconds before distant orbs begin drifting in even outside the magnet radius.
@export var auto_drift_delay := 2.4

var velocity := Vector3.ZERO
var _age := 0.0
var _phase := 0.0
var _collected := false
var _mesh_inst := MeshInstance3D.new()
var _mat := ShaderMaterial.new()
var _wisp := CPUParticles3D.new()

static var _shared_mesh: SphereMesh
static var _wisp_quad: QuadMesh


func _ready() -> void:
	add_to_group("soul_orbs")
	_phase = randf() * TAU
	if _shared_mesh == null:
		_shared_mesh = SphereMesh.new()
		_shared_mesh.radius = 0.115
		_shared_mesh.height = 0.26
		_shared_mesh.radial_segments = 14
		_shared_mesh.rings = 8
	var col := orb_color(element)
	_mat.shader = SHADER
	_mat.set_shader_parameter("soul_color", col)
	_mat.set_shader_parameter("phase", _phase)
	_mesh_inst.mesh = _shared_mesh
	_mesh_inst.material_override = _mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh_inst)

	# Delicate rising/trailing spirit motes behind the Hitodama flame.
	if _wisp_quad == null:
		_wisp_quad = QuadMesh.new()
		_wisp_quad.size = Vector2(0.018, 0.065)
	_wisp.amount = 5
	_wisp.lifetime = 0.38
	_wisp.local_coords = false
	_wisp.direction = Vector3.UP
	_wisp.spread = 22.0
	_wisp.initial_velocity_min = 0.25
	_wisp.initial_velocity_max = 0.55
	_wisp.gravity = Vector3(0.0, 0.9, 0.0)
	_wisp.particle_flag_align_y = true
	_wisp.mesh = _wisp_quad
	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wmat.albedo_color = col * 1.35
	wmat.vertex_color_use_as_albedo = true
	_wisp.material_override = wmat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.85))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	_wisp.color_ramp = ramp
	add_child(_wisp)


static func orb_color(elem: String) -> Color:
	match elem:
		Elements.SAKURA: return Color(1.0, 0.30, 0.70)
		Elements.STORM: return Color(0.34, 0.84, 1.0)
		Elements.INK: return Color(0.54, 0.64, 0.95)
		Elements.SHADOW: return Color(0.74, 0.30, 1.0)
		Elements.BLACK_LIGHTNING: return Color(0.32, 0.76, 1.0)
		Elements.PHANTOM_PETALS: return Color(0.96, 0.30, 0.94)
	return Color(0.40, 0.90, 0.98)


## Spawn a burst of [param count] soul orbs at [param origin].
static func spawn_cluster(parent: Node, origin: Vector3, count: int = 4, xp_each: int = 6, elem: String = Elements.NONE) -> Array[SoulOrb]:
	var out: Array[SoulOrb] = []
	for i in count:
		var orb: SoulOrb
		if VfxPool:
			orb = VfxPool.acquire_soul_orb(parent)
		else:
			orb = SoulOrb.new()
			parent.add_child(orb)
		orb.xp_value = xp_each
		orb.element = elem
		var col := orb_color(elem)
		orb._mat.set_shader_parameter("soul_color", col)
		if orb._wisp.material_override is StandardMaterial3D:
			(orb._wisp.material_override as StandardMaterial3D).albedo_color = col * 1.35
		var angle := (TAU * float(i) / float(maxi(count, 1))) + randf_range(-0.3, 0.3)
		var speed := randf_range(1.4, 2.6)
		orb.global_position = origin + Vector3(cos(angle) * 0.14, randf_range(0.05, 0.25), sin(angle) * 0.14)
		orb.velocity = Vector3(cos(angle) * speed, randf_range(1.6, 2.8), sin(angle) * speed)
		out.append(orb)
	return out


func activate_from_pool() -> void:
	_collected = false
	_age = 0.0
	velocity = Vector3.ZERO
	_phase = randf() * TAU
	_mat.set_shader_parameter("phase", _phase)
	visible = true
	_wisp.emitting = true
	show()


func deactivate_for_pool() -> void:
	_collected = true
	velocity = Vector3.ZERO
	_age = 0.0
	_wisp.emitting = false
	visible = false
	hide()


func step_orb(delta: float, target_pos: Vector3, magnet_radius: float) -> bool:
	if _collected:
		return true
	_age += delta
	var to_target := target_pos - global_position
	var dist := to_target.length()

	if _age >= scatter_time and dist <= collect_distance:
		_collect()
		return true

	var in_magnet := _age >= scatter_time and (dist <= magnet_radius or _age >= auto_drift_delay)
	if in_magnet:
		var dir := to_target / maxf(dist, 0.001)
		var pull_speed := lerpf(4.5, 13.5, clampf(1.0 - dist / maxf(magnet_radius, 0.5), 0.0, 1.0))
		if _age >= auto_drift_delay and dist > magnet_radius:
			pull_speed = 5.5
		# Slight swirl perpendicular to the pull direction so orbs spiral gracefully in.
		var swirl := Vector3(-dir.z, 0.0, dir.x) * (sin(_age * 7.0 + _phase) * 1.4 * clampf(dist * 0.4, 0.0, 1.0))
		velocity = velocity.lerp(dir * pull_speed + swirl, clampf(delta * 10.0, 0.0, 1.0))
		global_position += velocity * delta
	else:
		# Scatter arc settling into a gentle hover above the floor/water.
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 4.5, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 4.5, 0.0, 1.0))
		var target_y := hover_height + sin(_age * 3.0 + _phase) * 0.09
		var dy := target_y - global_position.y
		velocity.y = lerpf(velocity.y, dy * 5.0, clampf(delta * 6.0, 0.0, 1.0))
		global_position += velocity * delta
	return false


func _collect() -> void:
	if _collected:
		return
	_collected = true
	Sfx.play_at("blade_ring", global_position, -12.0, 2.5)
	if is_inside_tree() and get_tree().current_scene:
		SparkBurst.spawn(get_tree().current_scene, global_position, Vector3.UP, orb_color(element) * 1.6, 8, 1.8)
	collected.emit(xp_value, element)
	if VfxPool:
		VfxPool.release_soul_orb(self)
	else:
		queue_free()
