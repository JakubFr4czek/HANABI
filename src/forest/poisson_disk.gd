class_name PoissonDisk
extends RefCounted
## Bridson's fast Poisson-disk sampling (Robert Bridson, "Fast Poisson Disk
## Sampling in Arbitrary Dimensions", SIGGRAPH 2007 sketch). Points in a
## rectangle are at least [param radius] apart and fill it evenly ("blue
## noise"): the look of a planted stand without the clumps of pure random or
## the grid lines of a jittered grid. The grid of cells has side radius / √2,
## so each cell holds at most one point and a neighbour test looks at 5×5 cells.
##
## Deterministic: the same rng state gives the same points.

const CANDIDATES := 30


## Points inside the rectangle [param origin, origin + size], at least
## [param radius] apart. [param rng] drives every choice.
static func sample(rng: RandomNumberGenerator, origin: Vector2, size: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if radius <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return points
	var cell := radius / sqrt(2.0)
	var cols := maxi(int(ceil(size.x / cell)), 1)
	var rows := maxi(int(ceil(size.y / cell)), 1)
	var grid := PackedInt32Array()
	grid.resize(cols * rows)
	grid.fill(-1)
	var active: Array[int] = []

	var first := origin + Vector2(rng.randf() * size.x, rng.randf() * size.y)
	points.append(first)
	grid[_cell_index(first, origin, cell, cols, rows)] = 0
	active.append(0)
	while not active.is_empty():
		var pick := rng.randi_range(0, active.size() - 1)
		var base := points[active[pick]]
		var placed := false
		for _i in CANDIDATES:
			# Uniform in the annulus [radius, 2·radius) around the active point.
			var angle := rng.randf() * TAU
			var dist := radius * (1.0 + rng.randf())
			var cand := base + Vector2(cos(angle), sin(angle)) * dist
			if cand.x < origin.x or cand.y < origin.y or cand.x >= origin.x + size.x or cand.y >= origin.y + size.y:
				continue
			if _too_close(points, grid, cand, origin, cell, cols, rows, radius):
				continue
			points.append(cand)
			grid[_cell_index(cand, origin, cell, cols, rows)] = points.size() - 1
			active.append(points.size() - 1)
			placed = true
			break
		if not placed:
			# Retire the point: swap-remove keeps the active list short.
			active[pick] = active[active.size() - 1]
			active.pop_back()
	return points


static func _cell_index(p: Vector2, origin: Vector2, cell: float, cols: int, rows: int) -> int:
	var cx := clampi(int((p.x - origin.x) / cell), 0, cols - 1)
	var cz := clampi(int((p.y - origin.y) / cell), 0, rows - 1)
	return cz * cols + cx


static func _too_close(points: PackedVector2Array, grid: PackedInt32Array, p: Vector2, origin: Vector2,
		cell: float, cols: int, rows: int, radius: float) -> bool:
	var cx := clampi(int((p.x - origin.x) / cell), 0, cols - 1)
	var cz := clampi(int((p.y - origin.y) / cell), 0, rows - 1)
	# A point closer than radius lies at most two cells away (radius / cell = √2).
	for oz in range(maxi(cz - 2, 0), mini(cz + 2, rows - 1) + 1):
		for ox in range(maxi(cx - 2, 0), mini(cx + 2, cols - 1) + 1):
			var idx := grid[oz * cols + ox]
			if idx >= 0 and points[idx].distance_squared_to(p) < radius * radius:
				return true
	return false
