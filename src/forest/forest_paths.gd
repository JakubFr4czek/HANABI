class_name ForestPaths
extends RefCounted
## The forest's footpaths (docs/WORLDGEN_TOOL.md, "Ścieżki").
##
## Nodes sit on a lattice of cells path_node_spacing metres wide, each jittered
## inside its cell by a point hash, and the glade at the origin is the start.
## Every node has a parent one step closer to the start (a random staircase:
## the parent is horizontal or vertical, chosen by hash), so every node is
## connected to the start by construction, anywhere in the infinite forest.
## A few extra lattice edges make loops. Each edge is routed by A* over a grid
## whose cost grows with the slope and with a meandering noise, smoothed with
## Chaikin's corner cutting and resampled every metre.
##
## Everything is a pure function of the world seed, the profile and the hill
## height, so chunks read the same network in any load order.
##
## References: A* (Hart, Nilsson, Raphael 1968); Chaikin (1974) corner cutting.

const ROUTE_CELL := 2.5
const ROUTE_MARGIN := 8.0
const SLOPE_COST := 6.0
const RESAMPLE := 1.0

var _p: WorldGenProfile
var _height: Callable
var _noise := FastNoiseLite.new()
var _routes: Dictionary = {}  # edge key -> PackedVector2Array


## [param height] is hill height (x, z) -> y. It must not read the forest's own
## mounds, or routing would depend on the trees that routing keeps clear.
func setup(profile: WorldGenProfile, height: Callable) -> void:
	_p = profile
	_height = height
	_routes.clear()
	_noise.seed = 0x50415448 ^ profile.world_seed
	_noise.frequency = 0.08
	_noise.fractal_octaves = 2


## Position of a lattice node. The origin node is the glade itself.
func node_xz(n: Vector2i) -> Vector2:
	if n == Vector2i.ZERO:
		return Vector2.ZERO
	var s := _p.path_node_spacing
	var jitter := Vector2(_r(n, 1) - 0.5, _r(n, 2) - 0.5) * s * 0.5
	return Vector2(n.x, n.y) * s + jitter


## The node one step closer to the start (Manhattan distance drops by one).
func parent_of(n: Vector2i) -> Vector2i:
	if n.x != 0 and (n.y == 0 or _r(n, 3) < 0.5):
		return Vector2i(n.x - signi(n.x), n.y)
	return Vector2i(n.x, n.y - signi(n.y))


## Edge key of two lattice nodes: Vector4i(a.x, a.y, b.x, b.y), a sorted first.
static func edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


## Every edge with an endpoint in the lattice cells around [param rect] (world
## xz). A segment crossing the rect has an endpoint one cell away at most.
func edges_in_rect(rect: Rect2) -> Array[Vector4i]:
	var out: Array[Vector4i] = []
	if _p == null or not _p.paths_enabled:
		return out
	var s := _p.path_node_spacing
	var i0 := floori(rect.position.x / s) - 1
	var i1 := ceili(rect.end.x / s) + 1
	var j0 := floori(rect.position.y / s) - 1
	var j1 := ceili(rect.end.y / s) + 1
	var seen := {}
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var n := Vector2i(i, j)
			if n != Vector2i.ZERO:
				_add_edge(out, seen, n, parent_of(n))
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var m := n + step
				if _is_loop(n, m):
					_add_edge(out, seen, n, m)
	return out


## The routed centre line of an edge: world xz points, one metre apart.
func polyline(key: Vector4i) -> PackedVector2Array:
	if _routes.has(key):
		return _routes[key]
	var a := Vector2i(key.x, key.y)
	var b := Vector2i(key.z, key.w)
	var line := _route(node_xz(a), node_xz(b))
	_routes[key] = line
	return line


## Segments (pairs of consecutive points) of the paths near [param rect].
func segments_in_rect(rect: Rect2, margin: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var box := rect.grow(margin)
	for key in edges_in_rect(rect):
		var line := polyline(key)
		for k in range(line.size() - 1):
			var a := line[k]
			var b := line[k + 1]
			if maxf(a.x, b.x) < box.position.x or minf(a.x, b.x) > box.end.x:
				continue
			if maxf(a.y, b.y) < box.position.y or minf(a.y, b.y) > box.end.y:
				continue
			out.append(a)
			out.append(b)
	return out


## Distance from [param p] to the nearest segment of a [method segments_in_rect] list.
static func distance_to_segments(segments: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for k in range(0, segments.size() - 1, 2):
		best = minf(best, segment_distance(p, segments[k], segments[k + 1]))
	return best


## Points along the paths inside [param rect], every [param spacing] metres.
## Each carries the path's unit tangent: Vector4(x, z, tangent.x, tangent.y).
func samples_in_rect(rect: Rect2, spacing: float) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var stride := maxi(int(round(spacing / RESAMPLE)), 1)
	for key in edges_in_rect(rect):
		var line := polyline(key)
		for k in range(0, line.size(), stride):
			var p := line[k]
			if not rect.has_point(p):
				continue
			var ahead := line[mini(k + 1, line.size() - 1)]
			var behind := line[maxi(k - 1, 0)]
			var t := (ahead - behind)
			t = t.normalized() if t.length_squared() > 1e-6 else Vector2.RIGHT
			out.append(Vector4(p.x, p.y, t.x, t.y))
	return out


## Closest point of the network to [param p] within [param radius] (INF if none).
func nearest_point(p: Vector2, radius: float) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for key in edges_in_rect(Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0)):
		for q in polyline(key):
			var d := q.distance_to(p)
			if d < best_d and d <= radius:
				best_d = d
				best = q
	return best


func _add_edge(out: Array[Vector4i], seen: Dictionary, a: Vector2i, b: Vector2i) -> void:
	var key := edge_key(a, b)
	if seen.has(key):
		return
	seen[key] = true
	out.append(key)


## Loop edges: a lattice edge that is not a tree edge is kept by a point hash.
func _is_loop(a: Vector2i, b: Vector2i) -> bool:
	if _p.path_loop_chance <= 0.0 or _is_tree_edge(a, b):
		return false
	var salt := 4 if a.y == b.y else 5
	return _r(a, salt) < _p.path_loop_chance


func _is_tree_edge(a: Vector2i, b: Vector2i) -> bool:
	return (a != Vector2i.ZERO and parent_of(a) == b) or (b != Vector2i.ZERO and parent_of(b) == a)


## Stateless hash in [0, 1) for a lattice node (salted per use).
func _r(n: Vector2i, salt: int) -> float:
	var h := hash([n.x, n.y, salt, _p.world_seed, 0x50415448])
	return float(h & 0x7fffffff) / 2147483647.0


## A* over a grid of ROUTE_CELL metres between two node positions, then
## Chaikin smoothing and resampling. Endpoints are kept exactly.
func _route(a: Vector2, b: Vector2) -> PackedVector2Array:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(ROUTE_MARGIN, ROUTE_MARGIN)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(ROUTE_MARGIN, ROUTE_MARGIN)
	var nx := int(ceil((hi.x - lo.x) / ROUTE_CELL)) + 1
	var ny := int(ceil((hi.y - lo.y) / ROUTE_CELL)) + 1
	var cost := PackedFloat32Array()
	cost.resize(nx * ny)
	for j in ny:
		for i in nx:
			var c := lo + Vector2(i, j) * ROUTE_CELL
			cost[j * nx + i] = _cell_cost(c)
	var start := _nearest_cell(a, lo, nx, ny)
	var goal := _nearest_cell(b, lo, nx, ny)
	var cells := _astar(cost, nx, ny, start, goal)
	var pts := PackedVector2Array()
	pts.append(a)
	for k in range(1, cells.size() - 1):
		var c: Vector2i = cells[k]
		pts.append(lo + Vector2(c.x, c.y) * ROUTE_CELL)
	pts.append(b)
	pts = _chaikin(pts, 2)
	return _resample(pts, RESAMPLE)


func _cell_cost(c: Vector2) -> float:
	var e := ROUTE_CELL
	var dx := float(_height.call(c.x + e, c.y)) - float(_height.call(c.x - e, c.y))
	var dz := float(_height.call(c.x, c.y + e)) - float(_height.call(c.x, c.y - e))
	var slope := Vector2(dx, dz).length() / (2.0 * e)
	var meander := _noise.get_noise_2d(c.x, c.y)
	return 1.0 + SLOPE_COST * slope + _p.path_curviness * absf(meander)


func _nearest_cell(p: Vector2, lo: Vector2, nx: int, ny: int) -> Vector2i:
	var i := clampi(int(round((p.x - lo.x) / ROUTE_CELL)), 0, nx - 1)
	var j := clampi(int(round((p.y - lo.y) / ROUTE_CELL)), 0, ny - 1)
	return Vector2i(i, j)


## Grid A* with 8 neighbours and a binary heap. Cost of a step is the mean of
## the two cells' costs, scaled by the step length.
func _astar(cost: PackedFloat32Array, nx: int, ny: int, start: Vector2i, goal: Vector2i) -> Array:
	var open := _Heap.new()
	var g := PackedFloat32Array()
	g.resize(nx * ny)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(nx * ny)
	came.fill(-1)
	var s_idx := start.y * nx + start.x
	var g_idx := goal.y * nx + goal.x
	g[s_idx] = 0.0
	open.push(_octile(start, goal), s_idx)
	while not open.is_empty():
		var cur: int = open.pop()
		if cur == g_idx:
			break
		var cx := cur % nx
		var cy := cur / nx
		for dy: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var x := cx + dx
				var y := cy + dy
				if x < 0 or y < 0 or x >= nx or y >= ny:
					continue
				var nb := y * nx + x
				var step := 1.41421 if dx != 0 and dy != 0 else 1.0
				var c := (cost[cur] + cost[nb]) * 0.5 * step
				if g[cur] + c < g[nb]:
					g[nb] = g[cur] + c
					came[nb] = cur
					open.push(g[nb] + _octile(Vector2i(x, y), goal), nb)
	var out: Array = []
	if came[g_idx] < 0 and g_idx != s_idx:
		out.append(start)
		out.append(goal)
		return out
	var k := g_idx
	while k != -1:
		out.push_front(Vector2i(k % nx, k / nx))
		if k == s_idx:
			break
		k = came[k]
	return out


static func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(float(a.x - b.x))
	var dy := absf(float(a.y - b.y))
	return maxf(dx, dy) + 0.41421 * minf(dx, dy)


static func _chaikin(pts: PackedVector2Array, rounds: int) -> PackedVector2Array:
	var cur := pts
	for _r in rounds:
		var out := PackedVector2Array()
		out.append(cur[0])
		for k in range(cur.size() - 1):
			var a := cur[k]
			var b := cur[k + 1]
			if k > 0:
				out.append(a.lerp(b, 0.25))
			if k < cur.size() - 2:
				out.append(a.lerp(b, 0.75))
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


## Points every [param step] metres of arc length, starting at the first point.
static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.is_empty():
		return out
	out.append(pts[0])
	var next := step
	var base := 0.0
	for k in range(pts.size() - 1):
		var a := pts[k]
		var b := pts[k + 1]
		var seg := a.distance_to(b)
		if seg <= 1e-9:
			continue
		while next <= base + seg:
			out.append(a.lerp(b, (next - base) / seg))
			next += step
		base += seg
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 1e-3:
		out.append(pts[pts.size() - 1])
	return out


## Distance from [param p] to the segment [param a]–[param b] (world xz).
static func segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-9:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Minimal binary min-heap of (priority, value) for the A* open set.
class _Heap:
	var _keys := PackedFloat32Array()
	var _vals := PackedInt32Array()

	func is_empty() -> bool:
		return _keys.is_empty()

	func push(key: float, val: int) -> void:
		_keys.append(key)
		_vals.append(val)
		var i := _keys.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if _keys[parent] <= _keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> int:
		var top := _vals[0]
		var last := _keys.size() - 1
		_swap(0, last)
		_keys.resize(last)
		_vals.resize(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < _keys.size() and _keys[l] < _keys[m]:
				m = l
			if r < _keys.size() and _keys[r] < _keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var k := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = k
		var v := _vals[a]
		_vals[a] = _vals[b]
		_vals[b] = v
