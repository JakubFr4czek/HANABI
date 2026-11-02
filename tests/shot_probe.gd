class_name ShotProbe
extends RefCounted
## Pixel probes for the windowed visual checks (N6, docs/n6/): the screen rectangle a
## local box projects to in the current frame, and the brightness and hue of the pixels
## inside it. A headless run renders nothing, so callers check [method rendering] first
## and print a SKIP line instead.


static func rendering() -> bool:
	return DisplayServer.get_name() != "headless"


## Screen rectangle covered by [param local] (a box in [param xform]'s space), clamped to
## the viewport. Empty when every corner is behind the camera.
static func box_rect(cam: Camera3D, xform: Transform3D, local: AABB, viewport: Vector2) -> Rect2i:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var corner := local.position + local.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)
		var world := xform * corner
		if cam.is_position_behind(world):
			continue
		var p := cam.unproject_position(world)
		lo = lo.min(p)
		hi = hi.max(p)
	if lo.x == INF:
		return Rect2i()
	var r := Rect2i(Vector2i(lo.floor()), Vector2i((hi - lo).ceil()))
	return r.intersection(Rect2i(Vector2i.ZERO, Vector2i(viewport)))


## Rec.709 luma of a colour (sRGB values as stored in the frame).
static func luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Mean luma over the rectangle.
static func mean_luma(img: Image, rect: Rect2i) -> float:
	var sum := 0.0
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			sum += luma(img.get_pixel(x, y))
			n += 1
	return sum / maxf(float(n), 1.0)


## Luma at quantile [param q] (0..1) over the rectangle.
static func quantile_luma(img: Image, rect: Rect2i, q: float) -> float:
	var values := PackedFloat32Array()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			values.append(luma(img.get_pixel(x, y)))
	if values.is_empty():
		return 0.0
	values.sort()
	return values[clampi(int(q * float(values.size())), 0, values.size() - 1)]


## Mean colour of the brightest [param share] of the rectangle's pixels (0..1).
static func bright_colour(img: Image, rect: Rect2i, share: float) -> Color:
	var px: Array[Color] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			px.append(img.get_pixel(x, y))
	if px.is_empty():
		return Color.BLACK
	px.sort_custom(func(a: Color, b: Color) -> bool: return luma(a) > luma(b))
	var n := maxi(1, int(share * float(px.size())))
	var acc := Color(0, 0, 0, 1)
	for k in n:
		acc += px[k]
	return Color(acc.r / n, acc.g / n, acc.b / n, 1.0)


## True for a warm colour: hue between [param lo] and [param hi] degrees (orange to yellow
## by default) and enough saturation to read as a colour, not as grey fog.
static func is_warm(c: Color, lo := 10.0, hi := 70.0, min_sat := 0.35) -> bool:
	var h := c.h * 360.0
	return h >= lo and h <= hi and c.s >= min_sat
