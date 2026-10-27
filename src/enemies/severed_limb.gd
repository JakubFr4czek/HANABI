class_name SeveredLimb
extends RigidBody3D
## A limb a very strong clean cut took off a yōkai: a free rigid body built
## from copies of the part's shapes and meshes. The original part stays
## jointed inside the ragdoll (hidden, touching nothing), so the body never
## has a joint torn out and the solver has nothing to detonate.
##
## The limb tumbles off along the cut with a trail of spirit embers from the
## wound, lands on the terrain, lies there for a moment and shrinks away.

## Severed limbs alive at once; the oldest goes first beyond this (Quest budget).
const MAX_ALIVE := 8
## Seconds a limb stays before it is gone, and the shrink at the end of that.
const LIFETIME := 4.0
const SHRINK_TIME := 0.6

static var _alive: Array[SeveredLimb] = []

var _age := 0.0
var _visuals: Array[Node3D] = []
var _ember_time := 0.0
var _ember_color := Color(1.7, 0.3, 0.16)


## Copy [param part] into a free limb under [param parent], thrown along
## [param cut_dir] with [param impulse] (N·s). Returns the limb.
static func spawn_from(parent: Node, part: RagdollPart, cut_dir: Vector3, impulse: float, ember_color: Color) -> SeveredLimb:
	while _alive.size() >= MAX_ALIVE:
		var oldest: SeveredLimb = _alive.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var limb := SeveredLimb.new()
	limb.name = "Severed_" + part.name
	limb.mass = maxf(part.mass * 0.6, 0.8)
	# Terrain only: the limb must not block the player, be cut again or
	# shove the living yōkai around.
	limb.collision_layer = 0
	limb.collision_mask = 1
	limb.continuous_cd = true
	limb.angular_damp = 1.2
	limb.linear_damp = 0.15
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	mat.bounce = 0.05
	limb.physics_material_override = mat
	limb._ember_color = ember_color
	for child in part.get_children():
		if child is CollisionShape3D:
			limb.add_child(child.duplicate())
		elif child is MeshInstance3D:
			var mi := child.duplicate() as MeshInstance3D
			# Own copy of the material: the body's dissolve fades its shared
			# skin, and the limb keeps its own clock.
			if mi.material_override:
				mi.material_override = mi.material_override.duplicate()
			limb.add_child(mi)
			limb._visuals.append(mi)
	parent.add_child(limb)
	limb.global_transform = part.global_transform
	var dir := cut_dir.normalized() if cut_dir.length_squared() > 1e-6 else Vector3.UP
	# Off along the blade's travel, a little up so it arcs before it lands,
	# with a tumble about the axis the blade cut through.
	limb.linear_velocity = part.linear_velocity * 0.5 + dir * clampf(impulse * 0.18, 1.6, 4.2) + Vector3.UP * 1.3
	var spin_axis := dir.cross(part.global_basis.y)
	if spin_axis.length_squared() < 1e-4:
		spin_axis = part.global_basis.x
	limb.angular_velocity = spin_axis.normalized() * clampf(impulse * 0.5, 4.0, 11.0)
	_alive.append(limb)
	return limb


func _physics_process(delta: float) -> void:
	_age += delta
	# Embers keep leaking from the cut end for a moment as the limb flies.
	if _age < 0.5:
		_ember_time -= delta
		if _ember_time <= 0.0:
			_ember_time = 0.07
			SparkBurst.spawn(get_parent(), global_position + global_basis.y * 0.15, -global_basis.y, _ember_color, 4, 0.9)
	var left := LIFETIME - _age
	if left < SHRINK_TIME:
		# Shrink the meshes, not the body: a scaled rigid body fights the solver.
		var s := maxf(left / SHRINK_TIME, 0.02)
		for v in _visuals:
			if is_instance_valid(v):
				v.scale = Vector3.ONE * s
	if _age >= LIFETIME:
		queue_free()


func _exit_tree() -> void:
	_alive.erase(self)
