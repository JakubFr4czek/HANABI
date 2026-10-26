class_name SwordArmIK
extends RefCounted
## Real-time inverse kinematics for an [ActiveRagdoll] holding a sword in its
## right fist: finds chest + right arm joint angles that put the blade on a
## wanted line (where the blade starts above the guard, and its direction),
## then places the left hand on the handle.
##
## Pure math on the rest layout (no physics): forward kinematics of the pose
## angles, damped least squares on a finite-difference Jacobian, joint limits
## respected. Warm-started from the last solution, so a target that moves
## smoothly gives joint angles that move smoothly; a few iterations per tick
## are enough. The ragdoll's muscles then chase these angles like any pose.
##
## Frame: the body's rest frame (node origin between the feet, facing +Z, the
## pelvis at its rest height and upright). [method to_rest_frame] maps a world
## point there using the pelvis's actual transform.

const RIGHT := ["chest", "upper_arm_r", "lower_arm_r"]
const LEFT := ["upper_arm_l", "lower_arm_l"]
## Weight of the blade direction error against the position error (m per unit).
const DIR_WEIGHT := 0.35
## Damping of the least-squares step (larger = smaller, steadier steps).
const LAMBDA := 0.15
## Longest step (rad, whole joint vector) one iteration may take.
const MAX_STEP := 0.12
## Most the whole joint vector may change in one [method solve] call (rad):
## ~400°/s at 90 Hz, quick enough to block, never a jump between equivalent
## arm configurations.
const MAX_TICK_CHANGE := 0.075
## Pull (per rad) toward the comfortable start pose: settles the spare degrees
## of freedom so the arm does not wander into odd but valid configurations.
const REST_PULL := 0.03
## Joint angles stay this far (rad) inside the hard limits.
const LIMIT_MARGIN := 0.05
## The chest may lean forward / back at most this much (rad) for a guard.
const CHEST_PITCH := Vector2(-0.14, 0.42)

var body: ActiveRagdoll
## Current solution: part -> Vector3 euler (rad, YXZ like the poses).
var angles := {}
var blade_start := Vector3(0, 0, -0.12)
var blade_tip := Vector3(0, 0, -0.95)
## Where the left hand holds the handle, in the sword's local frame.
var handle_point := Vector3(0, 0, 0.11)
## Last solution's error: position (m) and direction (rad).
var error_position := 0.0
var error_angle := 0.0

var _grip_rest := Transform3D()  # the sword's rest-frame transform with the arm in rest pose
var _chain := {}  # part -> {parent, joint (rest), origin (rest), limits (Vector2 x/y/z rad)}
var _comfort := {}  # part -> Vector3 euler (rad): the start pose
var _pelvis_rest := Transform3D()
var _sword_in_forearm := Transform3D()


## [param grip] is where the sword sits in the rest frame while the arm is in
## its rest pose (it moves rigidly with the right forearm). [param start_pose]
## seeds the solution ({part: Vector3 euler degrees}, like a pose).
func setup(p_body: ActiveRagdoll, grip: Transform3D, sword: BladeBody, start_pose: Dictionary = {}) -> void:
	body = p_body
	_grip_rest = grip
	if sword:
		blade_start = sword.blade_start
		blade_tip = sword.blade_tip
	for part in RIGHT + LEFT:
		var def: Dictionary = body._defs[part]
		var lim: Dictionary = def.get("limits", {})
		var limits := []
		for key in ["x", "y", "z"]:
			var r: Vector2 = lim.get(key, Vector2(-180, 180))
			limits.append(Vector2(deg_to_rad(r.x), deg_to_rad(r.y)))
		_chain[part] = {
			"parent": def.parent,
			"joint": def.joint,
			"origin": (body._rest[part] as Transform3D).origin,
			"limits": limits,
			# Precomputed for the fast forward kinematics: the joint in the
			# parent's frame, and the part's origin relative to its joint.
			"joint_in_parent": (body._rest[def.parent] as Transform3D).affine_inverse() * (def.joint as Vector3),
			"offset": (body._rest[part] as Transform3D).origin - (def.joint as Vector3),
		}
	_pelvis_rest = body._rest[body.root_part().name]
	_sword_in_forearm = (body._rest["lower_arm_r"] as Transform3D).affine_inverse() * _grip_rest
	for part in RIGHT + LEFT:
		var e: Vector3 = start_pose.get(part, Vector3.ZERO)
		angles[part] = _clamp(part, Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
		_comfort[part] = angles[part]


## World point -> the body's rest frame, through the pelvis's real transform.
func to_rest_frame(world: Vector3) -> Vector3:
	var pelvis := body.root_part()
	var rest_pelvis: Transform3D = body._rest[pelvis.name]
	return rest_pelvis * (pelvis.global_transform.affine_inverse() * world)


## World direction -> the body's rest frame.
func dir_to_rest_frame(world_dir: Vector3) -> Vector3:
	return (body.root_part().global_basis.inverse() * world_dir).normalized()


## Rest-frame point -> world.
func to_world(rest: Vector3) -> Vector3:
	var pelvis := body.root_part()
	var rest_pelvis: Transform3D = body._rest[pelvis.name]
	return pelvis.global_transform * (rest_pelvis.affine_inverse() * rest)


## Move the solution toward the blade line ([param start], [param dir]) in the
## rest frame, then put the left hand on the handle.
func solve(start: Vector3, dir: Vector3, iterations: int = 2) -> void:
	var want_dir := dir.normalized()
	var before := angles.duplicate()
	for it in iterations:
		_dls_step(RIGHT, func(a: Dictionary) -> PackedFloat64Array:
			var sw := _sword(a)
			var s0: Vector3 = sw * blade_start
			var d: Vector3 = (sw.basis * (blade_tip - blade_start)).normalized()
			var e1: Vector3 = s0 - start
			var e2: Vector3 = (d - want_dir) * DIR_WEIGHT
			return PackedFloat64Array([e1.x, e1.y, e1.z, e2.x, e2.y, e2.z]))
	var handle := _sword(angles) * handle_point
	_dls_step(LEFT, func(a: Dictionary) -> PackedFloat64Array:
		var e: Vector3 = _left_hand(a) - handle
		return PackedFloat64Array([e.x, e.y, e.z]))
	_limit_change(before)
	var fk := forward(angles)
	error_position = (fk.start as Vector3).distance_to(start)
	error_angle = ((fk.tip - fk.start) as Vector3).normalized().angle_to(want_dir)


func _limit_change(before: Dictionary) -> void:
	var total := 0.0
	for part in angles:
		total += ((angles[part] as Vector3) - (before[part] as Vector3)).length_squared()
	total = sqrt(total)
	if total <= MAX_TICK_CHANGE:
		return
	var k := MAX_TICK_CHANGE / total
	for part in angles:
		angles[part] = (before[part] as Vector3).lerp(angles[part], k)


## Joint targets (part -> Quaternion relative to the parent) of the solution.
func joint_targets() -> Dictionary:
	var out := {}
	for part in angles:
		out[part] = Basis.from_euler(angles[part]).get_rotation_quaternion()
	return out


## One link of the chain: the child's frame from its parent's.
func _link(parent: Transform3D, part: String, a: Dictionary) -> Transform3D:
	var c: Dictionary = _chain[part]
	var b: Basis = parent.basis * Basis.from_euler(a[part])
	return Transform3D(b, parent * (c.joint_in_parent as Vector3) + b * (c.offset as Vector3))


## The sword's rest-frame transform for joint angles [param a].
func _sword(a: Dictionary) -> Transform3D:
	var chest := _link(_pelvis_rest, "chest", a)
	var upper := _link(chest, "upper_arm_r", a)
	return _link(upper, "lower_arm_r", a) * _sword_in_forearm


## Where the left hand is for joint angles [param a].
func _left_hand(a: Dictionary) -> Vector3:
	var chest := _link(_pelvis_rest, "chest", a)
	var upper := _link(chest, "upper_arm_l", a)
	return _link(upper, "lower_arm_l", a) * Vector3(0, -0.17, 0)


## Forward kinematics of [param a] in the rest frame: blade start / tip, the
## fist, the handle point for the left hand and the left hand itself.
func forward(a: Dictionary) -> Dictionary:
	var world := {}
	world["pelvis"] = body._rest[body.root_part().name]
	for part in RIGHT + LEFT:
		var c: Dictionary = _chain[part]
		var pw: Transform3D = world[c.parent]
		var joint_world: Vector3 = pw * ((body._rest[c.parent] as Transform3D).affine_inverse() * (c.joint as Vector3))
		var b: Basis = pw.basis * Basis.from_euler(a[part])
		world[part] = Transform3D(b, joint_world + b * ((c.origin as Vector3) - (c.joint as Vector3)))
	var sword: Transform3D = world["lower_arm_r"] * ((body._rest["lower_arm_r"] as Transform3D).affine_inverse() * _grip_rest)
	return {
		"start": sword * blade_start,
		"tip": sword * blade_tip,
		"fist": sword.origin,
		"handle": sword * handle_point,
		"left_hand": (world["lower_arm_l"] as Transform3D) * Vector3(0, -0.17, 0),
	}


# --- Solver ----------------------------------------------------------------------

## The free variables of [param parts]: [part, axis] pairs (chest roll stays 0,
## forearm twist about its own length is not used: the elbow is a hinge+twist).
func _vars(parts: Array) -> Array:
	var v := []
	for part in parts:
		var axes := [0, 1] if part == "chest" or part.begins_with("lower_arm") else [0, 1, 2]
		for ax in axes:
			v.append([part, ax])
	return v


func _dls_step(parts: Array, residual: Callable) -> void:
	var vars := _vars(parts)
	var full := func(a: Dictionary) -> PackedFloat64Array:
		var r: PackedFloat64Array = residual.call(a)
		for v in vars:
			r.append(((a[v[0]] as Vector3)[v[1]] - (_comfort[v[0]] as Vector3)[v[1]]) * REST_PULL)
		return r
	var r0: PackedFloat64Array = full.call(angles)
	var m := r0.size()
	var n := vars.size()
	var h := 0.01
	# Jacobian, column by column (m x n, row-major).
	var J := PackedFloat64Array()
	J.resize(m * n)
	for j in n:
		var trial := angles.duplicate()
		var e: Vector3 = trial[vars[j][0]]
		e[vars[j][1]] += h
		trial[vars[j][0]] = e
		var r: PackedFloat64Array = full.call(trial)
		for i in m:
			J[i * n + j] = (r[i] - r0[i]) / h
	# Solve (J^T J + λ² I) step = -J^T r0 (n x n).
	var A := PackedFloat64Array()
	A.resize(n * n)
	var g := PackedFloat64Array()
	g.resize(n)
	for a in n:
		var gs := 0.0
		for i in m:
			gs -= J[i * n + a] * r0[i]
		g[a] = gs
		for b in n:
			var s := 0.0
			for i in m:
				s += J[i * n + a] * J[i * n + b]
			A[a * n + b] = s + (LAMBDA * LAMBDA if a == b else 0.0)
	var step := _solve(A, g, n)
	var len := 0.0
	for j in n:
		len += step[j] * step[j]
	len = sqrt(len)
	var scale := minf(1.0, MAX_STEP / maxf(len, 1e-9))
	# Only take steps that help (halve otherwise): never oscillates.
	var cost0 := _norm2(r0)
	for attempt in 4:
		var trial := angles.duplicate()
		for j in n:
			var part: String = vars[j][0]
			var e: Vector3 = trial[part]
			e[vars[j][1]] += step[j] * scale
			trial[part] = _clamp(part, e)
		if _norm2(full.call(trial)) < cost0:
			angles = trial
			return
		scale *= 0.5


static func _norm2(r: PackedFloat64Array) -> float:
	var s := 0.0
	for x in r:
		s += x * x
	return s


## Gaussian elimination with partial pivoting on an m x m system.
static func _solve(A: PackedFloat64Array, b: PackedFloat64Array, m: int) -> PackedFloat64Array:
	var a := A.duplicate()
	var x := b.duplicate()
	for col in m:
		var piv := col
		for row in range(col + 1, m):
			if absf(a[row * m + col]) > absf(a[piv * m + col]):
				piv = row
		if piv != col:
			for k in m:
				var t := a[col * m + k]
				a[col * m + k] = a[piv * m + k]
				a[piv * m + k] = t
			var tb := x[col]
			x[col] = x[piv]
			x[piv] = tb
		var d := a[col * m + col]
		if absf(d) < 1e-12:
			continue
		for row in range(col + 1, m):
			var f := a[row * m + col] / d
			if f == 0.0:
				continue
			for k in range(col, m):
				a[row * m + k] -= f * a[col * m + k]
			x[row] -= f * x[col]
	for row in range(m - 1, -1, -1):
		var s := x[row]
		for k in range(row + 1, m):
			s -= a[row * m + k] * x[k]
		var d := a[row * m + row]
		x[row] = s / d if absf(d) > 1e-12 else 0.0
	return x


func _clamp(part: String, e: Vector3) -> Vector3:
	var lim: Array = _chain[part].limits
	for i in 3:
		var r: Vector2 = lim[i]
		if r.y - r.x > 2.0 * LIMIT_MARGIN:
			e[i] = clampf(e[i], r.x + LIMIT_MARGIN, r.y - LIMIT_MARGIN)
		else:
			e[i] = (r.x + r.y) * 0.5
	if part == "chest":
		e.x = clampf(e.x, CHEST_PITCH.x, CHEST_PITCH.y)
		e.z = 0.0
	if part.begins_with("lower_arm"):
		e.z = 0.0
	return e
