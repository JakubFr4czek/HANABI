extends Node3D
## Diagnostic: muscles only (no gravity, no balance help, floating). Does the pose converge?
func _ready() -> void:
	var d := TrainingDummy.new()
	d.profile = load("res://data/enemies/training_dummy.tres")
	d.position = Vector3(0, 2, 0)
	add_child(d)
	d.upright_gain = 0.0; d.height_gain = 0.0; d.gravity_compensation = 0.0; d.anchor_gain = 0.0
	for b in d._all_bodies: b.gravity_scale = 0.0
	var pose: Dictionary = d._define_poses()["guard"]
	for t in [0.3, 1.0, 3.0]:
		for i in int(t * 90) - (0 if t == 0.3 else 0):
			await get_tree().physics_frame
		var worst := 0.0
		var line := ""
		for n in d._order:
			var def: Dictionary = d._defs[n]
			if def.get("parent", "") == "": continue
			var rel: Basis = (d.parts[def.parent] as Node3D).global_basis.inverse() * (d.parts[n] as Node3D).global_basis
			var tgt := Basis.from_euler(pose.get(n, Vector3.ZERO) * PI / 180.0)
			var err := rad_to_deg(rel.get_rotation_quaternion().angle_to(tgt.get_rotation_quaternion()))
			worst = maxf(worst, err)
			line += "%s:%.0f " % [n, err]
		var w := 0.0
		for b in d._all_bodies: w = maxf(w, b.angular_velocity.length())
		print("t+%.1f worst err %.1f°, max ang vel %.2f | %s" % [t, worst, w, line])
	get_tree().quit()
