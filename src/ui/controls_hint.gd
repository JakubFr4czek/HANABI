class_name ControlsHint
extends Node3D
## F4: the controls hint at the start of a run (docs/f4/CONTROLS.md). A small dark
## plate with four Latin lines ([method ControlsMap.hint_lines]), set once in the world
## in front of the eyes when play begins (not head-locked: comfort), slightly below eye
## level. It fades out after [const SHOW_SEC] or as soon as the player walks off
## ([const MOVE_DISMISS_M]) and then frees itself. RunGame shows it once per run.

signal dismissed

const SHOW_SEC := 6.0
const FADE_SEC := 0.6
const MOVE_DISMISS_M := 0.6
const DISTANCE := 1.5
const DROP := 0.22
const PLATE_SIZE := Vector2(0.56, 0.2)
const PLATE_COLOR := Color(0.035, 0.04, 0.07, 0.78)
const RULE_COLOR := Color(0.78, 0.62, 0.34, 0.85)
const TEXT_COLOR := Color(0.93, 0.9, 0.82)
const LINE_PITCH := 0.04
const FONT_SIZE := 30
const PIXEL_SIZE := 0.00072

var lines: Array[String] = []
var _head: Node3D
var _start := Vector3.ZERO
var _age := 0.0
var _alpha := 0.0
var _leaving := false
var _labels: Array[Label3D] = []
var _plate_mat := StandardMaterial3D.new()
var _rule_mat := StandardMaterial3D.new()


func setup(head: Node3D, dominant: String) -> void:
	_head = head
	lines = ControlsMap.hint_lines(dominant)


func _ready() -> void:
	name = "ControlsHint"
	_build()
	_place()
	_apply_alpha()


func _place() -> void:
	if _head == null or not is_instance_valid(_head):
		return
	var fwd := -_head.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-4 else Vector3.FORWARD
	var pos := _head.global_position + fwd * DISTANCE + Vector3.DOWN * DROP
	# The plate's front (+Z, where quads and Label3D face) looks back at the eyes:
	# -Z points along the view. (F4 round 1: it faced away and read mirrored.)
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
	# Tilt the top away a little so the face looks up at the eyes above it.
	rotate_object_local(Vector3.RIGHT, -atan2(DROP, DISTANCE))
	_start = _head.global_position


func _build() -> void:
	for m in [_plate_mat, _rule_mat]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true
		# Drawn over the world like the Oni speech bubble: no tree, rain or ground
		# geometry may hide it, and fog never eats it.
		m.no_depth_test = true
	_plate_mat.albedo_color = PLATE_COLOR
	_plate_mat.render_priority = 10
	_rule_mat.render_priority = 11
	_rule_mat.albedo_color = RULE_COLOR
	var plate := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = PLATE_SIZE
	plate.mesh = q
	plate.material_override = _plate_mat
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plate)
	# Two thin gilt rules, top and bottom, as on the menu board.
	for y in [PLATE_SIZE.y * 0.5 - 0.008, -PLATE_SIZE.y * 0.5 + 0.008]:
		var rule := MeshInstance3D.new()
		var rq := QuadMesh.new()
		rq.size = Vector2(PLATE_SIZE.x - 0.04, 0.0016)
		rule.mesh = rq
		rule.material_override = _rule_mat
		rule.position = Vector3(0.0, y, 0.001)
		rule.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rule)
	var font := UiTypography.font(600)
	var top := LINE_PITCH * (lines.size() - 1) * 0.5
	for i in lines.size():
		var lbl := Label3D.new()
		lbl.text = lines[i]
		lbl.font = font
		lbl.font_size = FONT_SIZE
		lbl.pixel_size = PIXEL_SIZE
		lbl.modulate = TEXT_COLOR
		lbl.outline_size = 4
		lbl.outline_modulate = Color(0.01, 0.01, 0.02, 0.9)
		lbl.shaded = false
		lbl.double_sided = true
		lbl.no_depth_test = true
		lbl.fixed_size = false
		lbl.render_priority = 15
		lbl.outline_render_priority = 14
		lbl.position = Vector3(0.0, top - i * LINE_PITCH, 0.002)
		add_child(lbl)
		_labels.append(lbl)


func _process(delta: float) -> void:
	_age += delta
	if not _leaving:
		var walked := 0.0
		if _head and is_instance_valid(_head):
			var d := _head.global_position - _start
			d.y = 0.0
			walked = d.length()
		if _age >= SHOW_SEC or walked >= MOVE_DISMISS_M:
			_leaving = true
		_alpha = minf(1.0, _alpha + delta / FADE_SEC)
	else:
		_alpha -= delta / FADE_SEC
		if _alpha <= 0.0:
			_alpha = 0.0
			_apply_alpha()
			dismissed.emit()
			queue_free()
			return
	_apply_alpha()


func is_leaving() -> bool:
	return _leaving


func _apply_alpha() -> void:
	_plate_mat.albedo_color.a = PLATE_COLOR.a * _alpha
	_rule_mat.albedo_color.a = RULE_COLOR.a * _alpha
	for l in _labels:
		l.modulate.a = _alpha
		l.outline_modulate.a = 0.9 * _alpha
	visible = _alpha > 0.001
