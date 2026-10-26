extends Node3D
## Diagnostic: does a Generic6DOFJoint3D limit hold under Jolt, and which sign does a limit use?
var a: RigidBody3D
var b: RigidBody3D
func _mk(pos: Vector3, frozen: bool) -> RigidBody3D:
	var r := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(0.1, 0.4, 0.1)
	cs.shape = bs; r.add_child(cs); r.position = pos; r.freeze = frozen; r.mass = 2.0
	r.collision_layer = 0; r.collision_mask = 0
	add_child(r); return r
func _run(axis: String, lim: Vector2, torque: Vector3, label: String) -> void:
	for c in get_children(): c.queue_free()
	await get_tree().physics_frame
	a = _mk(Vector3(0, 2, 0), true)
	b = _mk(Vector3(0, 1.6, 0), false)
	b.gravity_scale = 0.0
	var j := Generic6DOFJoint3D.new(); j.position = Vector3(0, 1.8, 0); add_child(j)
	j.node_a = j.get_path_to(a); j.node_b = j.get_path_to(b)
	for ax in ["x", "y", "z"]:
		var l: Vector2 = lim if ax == axis else Vector2.ZERO
		j.call("set_flag_" + ax, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(l.x))
		j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(l.y))
	for i in 180:
		b.apply_torque(torque)
		await get_tree().physics_frame
	var e := (a.global_basis.inverse() * b.global_basis).get_euler()
	print("%-34s -> rel euler deg %s" % [label, Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)).snapped(Vector3.ONE)])
func _ready() -> void:
	await _run("x", Vector2(-3, 140), Vector3(5, 0, 0), "x lim [-3,140], torque +x")
	await _run("x", Vector2(-3, 140), Vector3(-5, 0, 0), "x lim [-3,140], torque -x")
	await _run("x", Vector2(-3, 140), Vector3(0, 5, 0), "x lim [-3,140], torque +y (locked)")
	await _run("z", Vector2(-20, 110), Vector3(0, 0, 5), "z lim [-20,110], torque +z")
	await _run("z", Vector2(-20, 60), Vector3(0, 0, 5), "z lim [-20,60], torque +z")
	await _run("z", Vector2(-20, 60), Vector3(0, 0, -5), "z lim [-20,60], torque -z")
	await _run("y", Vector2(-30, 30), Vector3(0, 5, 0), "y lim [-30,30], torque +y")
	get_tree().quit()
