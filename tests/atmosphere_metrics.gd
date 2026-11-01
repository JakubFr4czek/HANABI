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
