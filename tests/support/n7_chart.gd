class_name N7Chart
extends RefCounted
## Draws the N7 chart straight from the simulation samples (no plotting library on this
## machine): live enemies (yōkai + guards + Oni) against run time, one line per run.
## Axes: x = run time 0–480 s (grid every minute), y = enemies 0–12. The grey line is the
## Quest cap (8 yōkai). Colours: one per run, listed in the sidecar text file.

const W := 960
const H := 420
const PAD := 40
const T_MAX := 480.0
const Y_MAX := 12.0
const PALETTE := [
	Color(0.95, 0.45, 0.25), Color(0.30, 0.75, 0.90), Color(0.55, 0.90, 0.40),
	Color(0.95, 0.85, 0.30), Color(0.80, 0.50, 0.95), Color(0.95, 0.95, 0.95),
]


static func write_png(runs: Array, path: String) -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.07, 0.08, 0.10))
	var plot_w := W - 2 * PAD
	var plot_h := H - 2 * PAD
	for minute in range(0, int(T_MAX / 60.0) + 1):
		var x := _px_x(minute * 60.0, plot_w)
		_vline(img, x, PAD, H - PAD, Color(0.22, 0.24, 0.28))
	for y in range(0, int(Y_MAX) + 1):
		var py := _px_y(float(y), plot_h)
		_hline(img, PAD, W - PAD, py, Color(0.22, 0.24, 0.28))
	_hline(img, PAD, W - PAD, _px_y(8.0, plot_h), Color(0.60, 0.60, 0.60))
	_hline(img, PAD, W - PAD, H - PAD, Color(0.7, 0.7, 0.7))
	_vline(img, PAD, PAD, H - PAD, Color(0.7, 0.7, 0.7))
	for i in runs.size():
		var color: Color = PALETTE[i % PALETTE.size()]
		var prev := Vector2.INF
		for row in runs[i].samples:
			var total: float = float(row.yokai + row.guards + row.oni)
			var p := Vector2(_px_x(float(row.t), plot_w), _px_y(total, plot_h))
			if prev != Vector2.INF:
				_line(img, prev, p, color)
			prev = p
	img.save_png(path)


static func _px_x(t: float, plot_w: int) -> float:
	return PAD + t / T_MAX * plot_w


static func _px_y(v: float, plot_h: int) -> float:
	return PAD + plot_h - v / Y_MAX * plot_h


static func _hline(img: Image, x0: float, x1: float, y: float, c: Color) -> void:
	for x in range(int(x0), int(x1)):
		_put(img, x, int(y), c)


static func _vline(img: Image, x: float, y0: float, y1: float, c: Color) -> void:
	for y in range(int(y0), int(y1)):
		_put(img, int(x), y, c)


static func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		_put(img, int(round(p.x)), int(round(p.y)), c)


static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)
