extends Node
## Diagnostic: solves block poses for the training dummy with forward
## kinematics of its pose angles (no physics). For each target blade line in
## the dummy's frame (x = its left, y = up from the floor, z = toward the
## player) it searches chest + right arm angles within the joint limits so the
## bokken lies on that line, then puts the left hand on the handle. Prints the
## pose dictionaries to paste into training_dummy.gd.
const ROOM := preload("res://scenes/test_room.tscn")
const TARGETS := {
	# start of the blade (just above the guard) and the blade direction
	"block_high": [Vector3(-0.28, 1.78, 0.38), Vector3(1.0, 0.18, 0.0)],
	"block_left": [Vector3(0.05, 1.0, 0.45), Vector3(0.45, 1.0, 0.25)],
	"block_right": [Vector3(-0.15, 1.0, 0.45), Vector3(-0.45, 1.0, 0.25)],
	"block_mid": [Vector3(-0.25, 1.05, 0.45), Vector3(0.7, 0.7, 0.15)],
}
const VARS := [["chest", 0], ["chest", 1], ["upper_arm_r", 0], ["upper_arm_r", 1], ["upper_arm_r", 2], ["lower_arm_r", 0], ["lower_arm_r", 1]]
const LEFT_VARS := [["upper_arm_l", 0], ["upper_arm_l", 1], ["upper_arm_l", 2], ["lower_arm_l", 0], ["lower_arm_l", 1]]

var d: TrainingDummy
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	var room = ROOM.instantiate()
	add_child(room)
	d = room.dummy
	rng.seed = 11
	for name in TARGETS:
		var tgt: Array = TARGETS[name]
		var best := {}
		var best_cost := INF
		for restart in 40:
			var pose := _random_pose()
			var c := _descend(pose, tgt, VARS, func(p): return _cost(p, tgt))
			if c < best_cost:
				best_cost = c
				best = pose
		var lb := INF
		var left := best.duplicate(true)
		for restart in 20:
			var p := best.duplicate(true)
			p["upper_arm_l"] = Vector3(rng.randf_range(-140, 40), rng.randf_range(-60, 60), rng.randf_range(-20, 100))
			p["lower_arm_l"] = Vector3(rng.randf_range(-140, 0), rng.randf_range(-50, 50), 0)
			var c := _descend(p, tgt, LEFT_VARS, func(q): return _left_cost(q))
			if c < lb:
				lb = c
				left = p
		var fk := _fk(left)
		print("%s: blade %s -> %s (cost %.4f), left hand off the handle %.3f m" % [name, fk.start.snapped(Vector3.ONE * 0.01), fk.tip.snapped(Vector3.ONE * 0.01), best_cost, sqrt(lb)])
		var line := '"%s": {' % name
		for part in ["chest", "head", "upper_arm_r", "lower_arm_r", "upper_arm_l", "lower_arm_l"]:
			var v: Vector3 = left.get(part, Vector3.ZERO)
			if part == "head":
				v = Vector3(-4, -left.chest.y * 0.7, 0)
			line += '"%s": Vector3(%d, %d, %d), ' % [part, roundi(v.x), roundi(v.y), roundi(v.z)]
		print("    ", line, "}")
	get_tree().quit()


func _random_pose() -> Dictionary:
	return {
		"chest": Vector3(rng.randf_range(-10, 20), rng.randf_range(-30, 30), 0),
		"upper_arm_r": Vector3(rng.randf_range(-150, 40), rng.randf_range(-70, 70), rng.randf_range(-100, 20)),
		"lower_arm_r": Vector3(rng.randf_range(-140, 0), rng.randf_range(-60, 60), 0),
		"upper_arm_l": Vector3(-50, 0, -20),
		"lower_arm_l": Vector3(-60, 0, 0),
	}


func _descend(pose: Dictionary, _tgt: Array, vars: Array, cost: Callable) -> float:
	var c: float = cost.call(pose)
	var step := 16.0
	while step > 0.25:
		var improved := false
		for v in vars:
			for s in [-1.0, 1.0]:
				var trial := pose.duplicate(true)
				var e: Vector3 = trial[v[0]]
				e[v[1]] += s * step
				trial[v[0]] = _clamp_limits(v[0], e)
				var tc: float = cost.call(trial)
				if tc < c - 1e-7:
					c = tc
					pose.merge(trial, true)
					improved = true
		if not improved:
			step *= 0.5
	return c


func _clamp_limits(part: String, e: Vector3) -> Vector3:
	var lim: Dictionary = d._defs[part].get("limits", {})
	var m := 3.0  # stay a little inside the hard limits
	for i in 3:
		var key: String = ["x", "y", "z"][i]
		var r: Vector2 = lim.get(key, Vector2(-180, 180))
		e[i] = clampf(e[i], r.x + m, r.y - m) if r.y - r.x > 2.0 * m else (r.x + r.y) * 0.5
	if part == "chest":
		e.x = clampf(e.x, -8.0, 24.0)
		e.z = 0.0
	return e


func _cost(pose: Dictionary, tgt: Array) -> float:
	var fk := _fk(pose)
	var dir: Vector3 = (fk.tip - fk.start).normalized()
	var want: Vector3 = (tgt[1] as Vector3).normalized()
	var c: float = fk.start.distance_squared_to(tgt[0]) + (1.0 - dir.dot(want)) * 0.6
	# Prefer an upright chest and keep the fist clear of the body.
	c += (pose.chest.x * pose.chest.x + pose.chest.y * pose.chest.y) * 1.5e-5
	var fist: Vector3 = fk.fist
	if fist.z < 0.22:
		c += (0.22 - fist.z) * (0.22 - fist.z) * 4.0
	return c


func _left_cost(pose: Dictionary) -> float:
	var fk := _fk(pose)
	return fk.left_hand.distance_squared_to(fk.handle)


## Forward kinematics of the pose angles from the rest layout.
func _fk(pose: Dictionary) -> Dictionary:
	var world := {}
	var pelvis := "pelvis"
	world[pelvis] = Transform3D(Basis.IDENTITY, d._rest[pelvis].origin)
	for part in d._order:
		var def: Dictionary = d._defs[part]
		var parent: String = def.get("parent", "")
		if parent == "":
			continue
		var e: Vector3 = pose.get(part, Vector3.ZERO)
		var q := Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
		var pw: Transform3D = world[parent]
		var joint_rest: Vector3 = def.joint
		var joint_world: Vector3 = pw * (d._rest[parent].affine_inverse() * joint_rest)
		var b: Basis = pw.basis * q
		world[part] = Transform3D(b, joint_world + b * (d._rest[part].origin - joint_rest))
	var rest_grip := Transform3D(Basis.looking_at(Vector3(0, -0.71, 0.71), Vector3.BACK), Vector3(-0.25, 0.86, 0.02))
	var sword: Transform3D = world["lower_arm_r"] * (d._rest["lower_arm_r"].affine_inverse() * rest_grip)
	var la: Transform3D = world["lower_arm_l"]
	return {
		"start": sword * d.sword.blade_start,
		"tip": sword * d.sword.blade_tip,
		"fist": sword.origin,
		"handle": sword * Vector3(0, 0, 0.11),
		"left_hand": la * Vector3(0, -0.17, 0),
	}
