class_name OfudaPickup
extends Node3D
## Ofuda (御札) currency pickup (docs/ELEMENTS_PLAN.md section (d), Phase E2c).
##
## A small physical paper talisman (0.08 m × 0.16 m) with a cinnabar seal,
## dropped by defeated yōkai. It hovers just above the ground, bobs gently,
## and is drawn into the player by the same magnet rule as Hitodama soul
## orbs (SoulOrb.step_orb): inside the magnet radius, or automatically after
## a short linger so a distant drop is never lost. Collected Ofuda are the
## run's only skill-tree currency (RunGame.ofuda_count), spent exclusively
## through RunGame.unlock_skill — never at level-up.
##
## Quest budget: one shared quad + one shared shader material for every
## pickup, no lights, no particles.

signal collected(pickup: OfudaPickup)

const SHADER := preload("res://src/shaders/ofuda.gdshader")
const WIDTH := 0.08
const HEIGHT := 0.16

## Height of the paper above the ground it fell on.
@export var hover_height := 0.5
@export var collect_distance := 0.5
## Seconds after spawning before the pickup can be magnetized (scatter reads first).
@export var scatter_time := 0.26
## Seconds before distant pickups drift in even outside the magnet radius.
@export var auto_drift_delay := 2.4

var velocity := Vector3.ZERO

var _age := 0.0
var _phase := 0.0
var _floor_y := 0.0
var _collected := false
var _mesh_inst := MeshInstance3D.new()

static var _shared_mesh: QuadMesh
static var _shared_mat: ShaderMaterial


func _ready() -> void:
	add_to_group("ofuda_pickups")
	_phase = randf() * TAU
	if _shared_mesh == null:
		_shared_mesh = QuadMesh.new()
		_shared_mesh.size = Vector2(WIDTH, HEIGHT)
	if _shared_mat == null:
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = SHADER
		_shared_mat.set_shader_parameter("accent_color", Color(0.92, 0.22, 0.14))
		_shared_mat.set_shader_parameter("glow_strength", 1.35)
	_mesh_inst.mesh = _shared_mesh
	_mesh_inst.material_override = _shared_mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh_inst)


## Drops [param count] Ofuda around [param origin] (a slain yōkai's chest).
static func spawn_drops(parent: Node, origin: Vector3, count: int,
		rng: RandomNumberGenerator = null) -> Array[OfudaPickup]:
	var out: Array[OfudaPickup] = []
	if count <= 0:
		return out
	var scatter := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		scatter.randomize()
	for i in count:
		var pickup := OfudaPickup.new()
		parent.add_child(pickup)
		var angle := (TAU * float(i) / float(count)) + scatter.randf_range(-0.4, 0.4)
		var dist := scatter.randf_range(0.25, 0.65)
		pickup._floor_y = origin.y - 0.95
		pickup.global_position = origin + Vector3(cos(angle) * dist, -0.45, sin(angle) * dist)
		pickup.velocity = Vector3(cos(angle) * scatter.randf_range(0.6, 1.2),
			scatter.randf_range(0.4, 0.9), sin(angle) * scatter.randf_range(0.6, 1.2))
		out.append(pickup)
	return out


## Advances the pickup one physics step toward [param target_pos] under the
## soul-magnet rule. Returns true once collected (the node frees itself).
func step_pickup(delta: float, target_pos: Vector3, magnet_radius: float) -> bool:
	if _collected:
		return true
	_age += delta
	# Face the player flat-on so the cinnabar seal always reads.
	var to_target := target_pos - global_position
	if Vector2(to_target.x, to_target.z).length_squared() > 0.001:
		rotation.y = atan2(to_target.x, to_target.z)
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
		velocity = velocity.lerp(dir * pull_speed, clampf(delta * 10.0, 0.0, 1.0))
		global_position += velocity * delta
	else:
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 4.5, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 4.5, 0.0, 1.0))
		var target_y := _floor_y + hover_height + sin(_age * 2.6 + _phase) * 0.05
		var dy := target_y - global_position.y
		velocity.y = lerpf(velocity.y, dy * 5.0, clampf(delta * 6.0, 0.0, 1.0))
		global_position += velocity * delta
	return false


func _collect() -> void:
	if _collected:
		return
	_collected = true
	# Crisp paper intake, pitched up from the soul breath so ears learn it.
	Sfx.play_at("soul_collect", global_position, -9.0, 2.4, 1.45)
	collected.emit(self)
	queue_free()
