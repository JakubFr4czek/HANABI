class_name AtmosphereMetrics
extends RefCounted
## Pixel measurements of a rendered run frame (N4). Static helpers shared by the
## windowed suite (worldgen_path_visible_test.gd) and the shot tool
## (n4_atmosphere_shots.gd), so the numbers in docs/n4 and the test checks are the same.
## Luminance is display-space (sRGB values weighted Rec.709), 0 black .. 1 white.


static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Mean display luminance of a patch of (2·half+1)² pixels around a world point, or -1
## when the point is behind the camera or off the frame.
static func patch_lum(img: Image, cam: Camera3D, world: Vector3, half: int = 3) -> float:
	if cam.is_position_behind(world):
		return -1.0
	var s := cam.unproject_position(world)
	var cx := int(round(s.x))
	var cy := int(round(s.y))
	if cx < half or cy < half or cx >= img.get_width() - half or cy >= img.get_height() - half:
		return -1.0
	var sum := 0.0
	var n := 0
	for y in range(cy - half, cy + half + 1):
		for x in range(cx - half, cx + half + 1):
			sum += lum(img.get_pixel(x, y))
			n += 1
	return sum / n


## Mean colour of a patch (for hue checks), or Color(-1,...) when off the frame.
static func patch_color(img: Image, cam: Camera3D, world: Vector3, half: int = 3) -> Color:
	if cam.is_position_behind(world):
		return Color(-1.0, 0.0, 0.0)
	var s := cam.unproject_position(world)
	var cx := int(round(s.x))
	var cy := int(round(s.y))
	if cx < half or cy < half or cx >= img.get_width() - half or cy >= img.get_height() - half:
		return Color(-1.0, 0.0, 0.0)
	var acc := Color(0.0, 0.0, 0.0, 0.0)
	var n := 0
	for y in range(cy - half, cy + half + 1):
		for x in range(cx - half, cx + half + 1):
			var c := img.get_pixel(x, y)
			acc += Color(c.r, c.g, c.b, 1.0)
			n += 1
	return Color(acc.r / n, acc.g / n, acc.b / n, 1.0)


## RMS contrast of the whole frame: standard deviation / mean of display luminance,
## sampled every [param step] pixels.
static func rms_contrast(img: Image, step: int = 4) -> float:
	var sum := 0.0
	var sum2 := 0.0
	var n := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var l := lum(img.get_pixel(x, y))
			sum += l
			sum2 += l * l
			n += 1
	var mean := sum / maxf(1.0, n)
	var variance := maxf(0.0, sum2 / maxf(1.0, n) - mean * mean)
	return sqrt(variance) / maxf(mean, 0.0001)


## Mean display luminance of the whole frame's upper band (sky and crowns), sampled every 4 px.
static func mean_lum(img: Image, y0: float = 0.0, y1: float = 1.0) -> float:
	var sum := 0.0
	var n := 0
	for y in range(int(y0 * img.get_height()), int(y1 * img.get_height()), 4):
		for x in range(0, img.get_width(), 4):
			sum += lum(img.get_pixel(x, y))
			n += 1
	return sum / maxf(1.0, n)


## Shaft detector (moonbeam column): the top quarter of the frame, column by column.
## Returns {excess, width} where excess = peak column brightness above the median column
## (display luminance) and width = share of the frame width of the columns that are
## brighter than the median by at least half of that peak (the widest such run).
static func shaft(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var top := int(h * 0.25)
	var cols := PackedFloat32Array()
	for x in range(0, w, 2):
		var sum := 0.0
		var n := 0
		for y in range(0, top, 4):
			sum += lum(img.get_pixel(x, y))
			n += 1
		cols.append(sum / maxf(1.0, n))
	var sorted := cols.duplicate()
	sorted.sort()
	var median := sorted[sorted.size() / 2]
	var peak := 0.0
	for v in cols:
		peak = maxf(peak, v - median)
	var best := 0
	if peak > 0.0:
		var run := 0
		for v in cols:
			if v - median >= peak * 0.5:
				run += 1
				best = maxi(best, run)
			else:
				run = 0
	return {"excess": peak, "width": float(best * 2) / float(w)}


static func hue_deg(c: Color) -> float:
	return c.h * 360.0


## Circular hue difference in degrees (0..180).
static func hue_gap(a: Color, b: Color) -> float:
	var d := absf(hue_deg(a) - hue_deg(b))
	return minf(d, 360.0 - d)


## Unit direction of the trail nearest to [param p] (xz), or zero.
static func trail_direction(forest: ForestWorld, p: Vector2) -> Vector2:
	var found := forest.paths.samples_in_rect(Rect2(p - Vector2(30.0, 30.0), Vector2(60.0, 60.0)), 1.0)
	var best := Vector2.ZERO
	var best_d := INF
	for s in found:
		var d := Vector2(s.x, s.y).distance_to(p)
		if d < best_d and d > 0.0:
			best_d = d
			best = Vector2(s.z, s.w)
	return best


## Trail point about [param metres] ahead of [param from] along [param dir], or Vector2.INF.
static func trail_point(forest: ForestWorld, from: Vector2, dir: Vector2, metres: float) -> Vector2:
	var found := forest.paths.samples_in_rect(Rect2(from - Vector2(30.0, 30.0), Vector2(60.0, 60.0)), 0.5)
	var best := Vector2.INF
	var best_err := INF
	for s in found:
		var p := Vector2(s.x, s.y)
		var rel := p - from
		if rel.dot(dir) <= 0.0:
			continue
		var err := absf(rel.length() - metres)
		if err < best_err:
			best_err = err
			best = p
	return best


## World xz-and-base positions of every planted trunk in the loaded ring (trees and focal trees).
static func trunk_bases(forest: ForestWorld) -> PackedVector3Array:
	var out := PackedVector3Array()
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		for e in forest.profile.trees.size():
			for label in ["Trees%d" % e, "Focal%d" % e]:
				for xf in chunk.get_meta("xfs_" + label, []):
					var t: Transform3D = xf
					out.append(chunk.position + t.origin)
	return out


## Share of cyan pixels (hue 170..215 deg, saturation >= 0.35, value >= 0.25) in a window
## around the screen position of [param world] (window half-size [param half] px).
static func cyan_share(img: Image, cam: Camera3D, world: Vector3, half: int = 60) -> float:
	if cam.is_position_behind(world):
		return -1.0
	var s := cam.unproject_position(world)
	var cx := int(s.x)
	var cy := int(s.y)
	var hits := 0
	var n := 0
	for y in range(maxi(cy - half, 0), mini(cy + half, img.get_height())):
		for x in range(maxi(cx - half, 0), mini(cx + half, img.get_width())):
			var c := img.get_pixel(x, y)
			n += 1
			var h := hue_deg(c)
			if h >= 170.0 and h <= 215.0 and c.s >= 0.35 and c.v >= 0.25:
				hits += 1
	return float(hits) / maxf(1.0, float(n))


## Mean display luminance of the ground beside the trail: patches at [param distances] metres
## ahead of the camera (on the ground), at lateral [param offsets] metres. Off-frame patches are skipped.
static func ground_mean(img: Image, cam: Camera3D, forest: ForestWorld, distances: Array, offsets: Array) -> float:
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = cam.global_transform.basis.x
	var base: Vector3 = cam.global_position
	var sum := 0.0
	var n := 0
	for d in distances:
		var c: Vector3 = base + fwd * float(d)
		for o in offsets:
			var p: Vector3 = c + right * float(o)
			var world: Vector3 = Vector3(p.x, forest.height_at(p.x, p.z) + 0.05, p.z)
			var l: float = patch_lum(img, cam, world, 3)
			if l >= 0.0:
				sum += l
				n += 1
	print("MEASURE ground patches on screen: %d (distances %s)" % [n, str(distances)])
	if n == 0:
		return -1.0
	return sum / float(n)


## Trunks against the mist: the planted trunks 8..20 m away that sit nearest the middle of the
## frame (up to TRUNK_CANDIDATES). Returns the largest |fog beside a trunk - trunk| in display
## luminance, or -1 when no candidate is on screen.
const TRUNK_CANDIDATES := 8

static func trunk_contrast(img: Image, cam: Camera3D, forest: ForestWorld) -> float:
	var mid := Vector2(img.get_width() * 0.5, img.get_height() * 0.5)
	var cands: Array = []
	for b in trunk_bases(forest):
		var top: Vector3 = b + Vector3.UP * 1.5
		var dist: float = cam.global_position.distance_to(top)
		if dist < 8.0 or dist > 20.0 or cam.is_position_behind(top):
			continue
		var s: Vector2 = cam.unproject_position(top)
		if s.x < 40.0 or s.x > img.get_width() - 40.0 or s.y < 40.0 or s.y > img.get_height() - 40.0:
			continue
		cands.append([s.distance_to(mid), top])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var best := -1.0
	for k in mini(TRUNK_CANDIDATES, cands.size()):
		var top: Vector3 = cands[k][1]
		var trunk: float = patch_lum(img, cam, top, 2)
		# Mist behind the trunk: 1.2 m aside and 5 m higher (the ground behind it is dark, not mist).
		var beside: float = patch_lum(img, cam, top + cam.global_transform.basis.x * 1.2 + Vector3.UP * 3.5, 2)
		if trunk < 0.0 or beside < 0.0:
			continue
		best = maxf(best, absf(beside - trunk))
	return best
