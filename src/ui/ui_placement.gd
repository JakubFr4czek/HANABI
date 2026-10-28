class_name UiPlacement
extends RefCounted
## Where a world-space UI panel may stand (docs/ELEMENTS_PLAN.md (e)(4)).
##
## A panel opened next to a tree, a torii leg, a boulder or a wall must neither
## sink into it nor end up behind it. [method place] looks along the viewer's
## yaw-only heading and keeps the panel at its comfortable distance when the
## space ahead is free; when an obstacle is closer it pulls the panel in front
## of it (obstacle distance minus [constant WALL_MARGIN], never nearer than
## [constant MIN_DISTANCE]), scaling it down so it keeps its apparent size. If
## no distance works it turns the panel up to 50° either way to find free air (any more and it would leave the field of view).
## Every candidate is verified against static world, trunks, gates, boulders
## and yōkai bodies: a box the size of the (scaled) panel, [constant CLEARANCE_DEPTH]
## thick, must be empty, and nine sight lines from the eyes to the panel's
## corners, edge midpoints and centre must be unobstructed (a thin wall between
## the player and the panel would otherwise hide it from view). A returned pose
## that is not [code]blocked[/code] passes both.

## Environment (1), standing yōkai (2), fallen yōkai (8), trunks/gates/boulders (64).
const MASK := 1 | 2 | 8 | 64
## The same without yōkai: set pieces that never move (level-up talismans, the
## memorial stele), so a passing enemy does not make them swing around.
const STATIC_MASK := 1 | 64
const DEFAULT_DISTANCE := 1.1
const MIN_DISTANCE := 0.65
const WALL_MARGIN := 0.2
## Box depth around the panel plane that must be free (WALL_MARGIN each side).
const CLEARANCE_DEPTH := 0.4
## Free border around the panel's edges (each side), so even the frame never
## touches a trunk or pillar passing by.
const SIDE_MARGIN := 0.1
const DISTANCE_STEP := 0.05
const YAW_OFFSETS_DEG: Array[float] = [0.0, 25.0, -25.0, 50.0, -50.0]


## Panel pose for a viewer at [param head] facing [param heading] (flat, any
## length), panel [param size] metres at the default distance.
## [param ground_height] (x, z) -> terrain y keeps the bottom edge off hills.
## Returns {transform, distance, scale, yaw_offset_deg, blocked}.
static func place(space: PhysicsDirectSpaceState3D, head: Vector3, heading: Vector3, size: Vector2,
		ground_height: Callable = Callable(), exclude: Array[RID] = []) -> Dictionary:
	var flat := Vector3(heading.x, 0.0, heading.z)
	flat = flat.normalized() if flat.length_squared() > 1e-6 else Vector3.FORWARD
	for offset_deg in YAW_OFFSETS_DEG:
		var dir := flat.rotated(Vector3.UP, deg_to_rad(offset_deg))
		var dist := DEFAULT_DISTANCE
		while dist >= MIN_DISTANCE - 0.001:
			var xf := _panel_transform(head, dir, dist, size, ground_height)
			var scale := dist / DEFAULT_DISTANCE
			if is_clear(space, head, xf, size * scale, exclude):
				return {"transform": xf, "distance": dist, "scale": scale,
						"yaw_offset_deg": offset_deg, "blocked": false}
			dist -= DISTANCE_STEP
	# Nothing is clear: the minimum distance straight ahead, flagged so the
	# caller draws the panel on top of whatever it overlaps.
	var fb_xf := _panel_transform(head, flat, MIN_DISTANCE, size, ground_height)
	return {"transform": fb_xf, "distance": MIN_DISTANCE, "scale": MIN_DISTANCE / DEFAULT_DISTANCE,
			"yaw_offset_deg": 0.0, "blocked": true}


## Panel centre [param distance] along [param dir] from the head, facing back
## at the viewer (yaw only: no pitch or roll), at eye level minus a hand, kept
## 1.1–1.7 m above the ground under the viewer and clear of the ground under it.
static func _panel_transform(head: Vector3, dir: Vector3, distance: float, size: Vector2,
		ground_height: Callable) -> Transform3D:
	var scale := distance / DEFAULT_DISTANCE
	var pos := head + dir * distance
	var ground_here := _ground(ground_height, head.x, head.z, head.y - 1.7)
	var y := clampf(head.y - 0.12, ground_here + 1.1, ground_here + 1.7)
	var half_h := size.y * 0.5 * scale
	var ground_there := _ground(ground_height, pos.x, pos.z, ground_here)
	y = maxf(y, ground_there + half_h + 0.25)
	pos.y = y
	return Transform3D(Basis.looking_at(dir, Vector3.UP), pos)


static func _ground(fn: Callable, x: float, z: float, fallback: float) -> float:
	if fn.is_valid():
		return float(fn.call(x, z))
	return fallback


## True when the box of [param panel_size] x [constant CLEARANCE_DEPTH] around
## [param xf] (plus [constant SIDE_MARGIN] on every side) touches nothing in
## [constant MASK] and nothing in [constant MASK] stands between [param head] and the panel.
static func is_clear(space: PhysicsDirectSpaceState3D, head: Vector3, xf: Transform3D,
		panel_size: Vector2, exclude: Array[RID] = []) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(panel_size.x + 2.0 * SIDE_MARGIN, panel_size.y + 2.0 * SIDE_MARGIN, CLEARANCE_DEPTH)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = xf
	q.collision_mask = MASK
	q.exclude = exclude
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var half := panel_size * 0.5
	for ix in [-1.0, 0.0, 1.0]:
		for iy in [-1.0, 0.0, 1.0]:
			var target := xf * Vector3(half.x * ix, half.y * iy, 0.0)
			var ray := PhysicsRayQueryParameters3D.create(head, head.lerp(target, 0.97), MASK, exclude)
			if not space.intersect_ray(ray).is_empty():
				return false
	return true
