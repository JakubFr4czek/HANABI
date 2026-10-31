class_name SakuraScatter
extends MultiMeshInstance3D
## A body coming apart into sakura petals: petals are born inside the visible
## meshes of a node (weighted by their volume), carried off on the wind with a
## slow flutter and tumble, and fade out over a few seconds. One MultiMesh
## per burst, simulated on the CPU (cheap at these counts on Quest).

const PETAL_SHADER := preload("res://src/shaders/sakura_petal.gdshader")
## The night wind the petals ride (m/s); gusts swell it a little.
const WIND := Vector3(0.78, 0.0, 0.3)
const MAX_ALIVE := 6

static var _alive: Array[SakuraScatter] = []
static var _material: ShaderMaterial
static var _mesh: QuadMesh

var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _axis: PackedVector3Array
var _angle: PackedFloat32Array
var _spin: PackedFloat32Array
var _life: PackedFloat32Array
var _phase: PackedFloat32Array
var _size: PackedFloat32Array
var _tint: PackedColorArray
var _buffer := PackedFloat32Array()
var _age := 0.0
var _max_life := 0.0


## Burst [param count] petals out of every visible mesh under [param source]
## into [param parent]. [param push] is the body's motion handed to the
## petals; [param tint] tints them (kill element, white for none).
static func burst_from(source: Node3D, parent: Node, count: int, push: Vector3 = Vector3.ZERO, tint: Color = Color.WHITE) -> SakuraScatter:
	if parent == null or source == null:
		return null
	var boxes: Array = []
	var total := 0.0
	for node in source.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var box := mi.get_aabb()
		var vol := maxf(box.size.x * box.size.y * box.size.z, 1e-5)
		boxes.append([mi.global_transform, box, vol])
		total += vol
	if boxes.is_empty():
		return null
	while _alive.size() >= MAX_ALIVE:
		var oldest: SakuraScatter = _alive.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var s := SakuraScatter.new()
	s.name = "SakuraScatter"
	s._setup(count)
	parent.add_child(s)
	s.global_transform = Transform3D.IDENTITY
	tint = tint.clamp()
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	for i in count:
		# Pick a mesh by volume, then a point inside its box.
		var pick := rng.randf() * total
		var chosen: Array = boxes[-1]
		for b in boxes:
			pick -= float(b[2])
			if pick <= 0.0:
				chosen = b
				break
		var xf: Transform3D = chosen[0]
		var box: AABB = chosen[1]
		var local := box.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * box.size
		s._pos[i] = xf * local
		# Out of the body, a little up, then the wind takes over.
		var out := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.2, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		s._vel[i] = push * 0.35 + out * rng.randf_range(0.3, 1.0)
		s._axis[i] = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		s._angle[i] = rng.randf() * TAU
		s._spin[i] = rng.randf_range(2.0, 6.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		s._life[i] = rng.randf_range(2.6, 4.2)
		s._phase[i] = rng.randf() * TAU
		s._size[i] = rng.randf_range(0.8, 1.25)
		# Mostly sakura pink, some paler; the kill element tints the burst.
		var pale := rng.randf() * 0.45
		s._tint[i] = Color(1.0, 1.0, 1.0).lerp(tint, 0.35) * Color(1.0, 1.0 - pale * 0.2, 1.0 - pale * 0.1)
		s._max_life = maxf(s._max_life, s._life[i])
	s._write(0.0)
	_alive.append(s)
	return s


func _setup(count: int) -> void:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(0.075, 0.1)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = PETAL_SHADER
		_material.render_priority = 4
		_material.set_shader_parameter("petal_color", Color(1.0, 0.42, 0.66))
		_material.set_shader_parameter("rim_color", Color(1.1, 0.7, 0.9))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh
	mm.instance_count = count
	multimesh = mm
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Packed arrays are values: resize each member itself, not a loop copy.
	_pos.resize(count)
	_vel.resize(count)
	_axis.resize(count)
	_angle.resize(count)
	_spin.resize(count)
	_life.resize(count)
	_phase.resize(count)
	_size.resize(count)
	_tint.resize(count)


func _process(delta: float) -> void:
	_age += delta
	var gust := 1.0 + 0.35 * sin(_age * 0.9) + 0.15 * sin(_age * 2.3)
	var wind := WIND * gust + Vector3.UP * 0.38
	for i in _pos.size():
		var v := _vel[i]
		# Drag toward the wind, a sideways flutter and a slow sink: petals
		# glide, they do not fall.
		v = v.lerp(wind, clampf(delta * 1.4, 0.0, 1.0))
		var flutter := sin(_age * 3.1 + _phase[i]) * 0.55
		v += Vector3(-WIND.z, 0.0, WIND.x).normalized() * flutter * delta * 2.0
		v.y += (sin(_age * 2.2 + _phase[i] * 1.7) * 0.35 - 0.1) * delta * 3.0
		_vel[i] = v
		_pos[i] += v * delta
		_angle[i] += _spin[i] * delta
	_write(delta)
	if _age >= _max_life:
		queue_free()


## Petal [param i]'s opacity now: it slowly fades the whole way, gone at
## the end of its life.
func petal_alpha(i: int) -> float:
	var t := clampf(_age / _life[i], 0.0, 1.0)
	return (1.0 - t) * (1.0 - t * 0.35)


func petal_count() -> int:
	return _pos.size()


func petal_center() -> Vector3:
	var sum := Vector3.ZERO
	for p in _pos:
		sum += p
	return sum / maxf(float(_pos.size()), 1.0)


## One buffer upload per frame instead of two RenderingServer calls per
## petal (up to ~1000 calls a frame with a few bursts alive on Quest).
## Layout per instance: 3x4 transform, rows (12 floats), then RGBA.
func _write(_delta: float) -> void:
	var n := _pos.size()
	if _buffer.size() != n * 16:
		_buffer.resize(n * 16)
	for i in n:
		var t := clampf(_age / _life[i], 0.0, 1.0)
		var sz := _size[i] * lerpf(1.0, 0.7, t)
		var b := Basis(_axis[i], _angle[i]).scaled(Vector3.ONE * sz)
		var o := _pos[i]
		var k := i * 16
		_buffer[k] = b.x.x; _buffer[k + 1] = b.y.x; _buffer[k + 2] = b.z.x; _buffer[k + 3] = o.x
		_buffer[k + 4] = b.x.y; _buffer[k + 5] = b.y.y; _buffer[k + 6] = b.z.y; _buffer[k + 7] = o.y
		_buffer[k + 8] = b.x.z; _buffer[k + 9] = b.y.z; _buffer[k + 10] = b.z.z; _buffer[k + 11] = o.z
		var c := _tint[i]
		_buffer[k + 12] = c.r; _buffer[k + 13] = c.g; _buffer[k + 14] = c.b; _buffer[k + 15] = petal_alpha(i)
	multimesh.buffer = _buffer


func _exit_tree() -> void:
	_alive.erase(self)
