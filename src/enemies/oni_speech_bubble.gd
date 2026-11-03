class_name OniSpeechBubble
extends Node3D
## Premium 3D billboard speech bubble for the Oni Boss (docs/GDD.md §8, Zadanie D15).
##
## Appears directly above the Oni's head in VR, facing the player camera.
## Styled with Japanese dark ink parchment aesthetic (translucent sumi-e black with subtle
## lacquer crimson border), high-contrast legible typography, smooth fade in/out.

signal speech_displayed(text: String)
signal speech_dismissed

const DEFAULT_DURATION := 3.5
const FADE_IN_TIME := 0.06
const FADE_OUT_TIME := 0.45

const BG_COLOR := Color(0.005, 0.005, 0.008)
const TEXT_COLOR := Color(0.96, 0.94, 0.88)
const BORDER_COLOR := Color(0.68, 0.16, 0.12)

var _bg_plate: MeshInstance3D
var _border_plate: MeshInstance3D
var _label: Label3D
var _tween: Tween
var _alpha := 0.0
var _bg_mat: StandardMaterial3D
var _border_mat: StandardMaterial3D
## N8 demo overlay: "Oni myśli: <taktyka> – <źródło>" on a small lacquer slip under the
## bubble; shown only with Settings › Meta AI › demo overlay on.
var _thought_plate: MeshInstance3D
var _thought_label: Label3D
var _thought_text := ""
var _speech_on := false

const THOUGHT_COLOR := Color(0.86, 0.72, 0.42)
## Plate padding around the text, in label pixels.
const PAD := Vector2(52.0, 30.0)


func _ready() -> void:
	_setup_bubble_visuals()
	_setup_thought_overlay()
	_set_speech_nodes(false)
	visible = false


func _process(_delta: float) -> void:
	_refresh_overlay()


func _set_speech_nodes(on: bool) -> void:
	_speech_on = on
	for n in [_border_plate, _bg_plate, _label]:
		if n != null:
			n.visible = on


## Fits both plates to the wrapped text so a 3-line taunt never spills over the edge.
func _fit_plates(text: String) -> void:
	var font: Font = _label.font if _label.font != null else ThemeDB.fallback_font
	var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, _label.width,
		_label.font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var w := (maxf(sz.x, 180.0) + PAD.x) * _label.pixel_size
	var h := (sz.y + PAD.y) * _label.pixel_size
	(_bg_plate.mesh as QuadMesh).size = Vector2(w, h)
	(_border_plate.mesh as QuadMesh).size = Vector2(w + 0.03, h + 0.03)
	if _thought_plate != null:
		_thought_plate.position.y = -h * 0.5 - 0.085
		_thought_label.position.y = _thought_plate.position.y


func _setup_thought_overlay() -> void:
	_thought_plate = MeshInstance3D.new()
	_thought_plate.name = "ThoughtPlate"
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.105)
	_thought_plate.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.disable_fog = true
	m.no_depth_test = true
	m.albedo_color = Color(0.03, 0.02, 0.02, 0.82)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.render_priority = 10
	_thought_plate.material_override = m
	_thought_plate.position.y = -0.24
	add_child(_thought_plate)
	_thought_label = Label3D.new()
	_thought_label.name = "ThoughtLabel"
	_thought_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_thought_label.no_depth_test = true
	_thought_label.font_size = 22
	_thought_label.pixel_size = 0.0036
	_thought_label.modulate = THOUGHT_COLOR
	_thought_label.outline_size = 4
	_thought_label.outline_modulate = Color(0.02, 0.01, 0.01, 0.9)
	_thought_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thought_label.render_priority = 15
	_thought_label.outline_render_priority = 14
	_thought_label.position.y = -0.24
	add_child(_thought_label)
	_thought_plate.visible = false
	_thought_label.visible = false


## N8: what the boss is thinking now (from [signal OniBossBrain.thought_changed]).
func set_thought(tactic: String, attack: String, source: String) -> void:
	var src := "ai · Muse Spark" if source == "ai" else ("mock" if source == "mock" else "fallback · lokalnie")
	var what := tactic
	if attack != "" and tactic in ["aggressive", "feint", "attack"]:
		what += " (" + attack + ")"
	_thought_text = "Oni myśli: %s – %s" % [what, src]
	_thought_label.text = _thought_text
	var font: Font = _thought_label.font if _thought_label.font != null else ThemeDB.fallback_font
	var w := font.get_string_size(_thought_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _thought_label.font_size).x
	(_thought_plate.mesh as QuadMesh).size = Vector2((w + 40.0) * _thought_label.pixel_size, 0.105)
	_refresh_overlay()


func get_thought() -> String:
	return _thought_text


## True while the demo overlay slip is on screen.
func is_overlay_showing() -> bool:
	return visible and _thought_label != null and _thought_label.visible


func _refresh_overlay() -> void:
	var on := _thought_text != "" and VrComfortSettings != null and VrComfortSettings.ai_demo_overlay
	if _thought_label != null and _thought_label.visible != on:
		_thought_label.visible = on
		_thought_plate.visible = on
	if on and not visible:
		visible = true


func _setup_bubble_visuals() -> void:
	# 1. Subtle crimson/gold outer border
	_border_plate = MeshInstance3D.new()
	_border_plate.name = "BorderPlate"
	var border_quad := QuadMesh.new()
	border_quad.size = Vector2(1.36, 0.36)
	_border_plate.mesh = border_quad

	_border_mat = StandardMaterial3D.new()
	_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_border_mat.disable_fog = true
	_border_mat.no_depth_test = true
	_border_mat.albedo_color = Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.0)
	_border_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_border_mat.render_priority = 10
	_border_plate.material_override = _border_mat
	add_child(_border_plate)

	# 2. Main dark sumi-e ink background plate
	_bg_plate = MeshInstance3D.new()
	_bg_plate.name = "BgPlate"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.30, 0.30)
	_bg_plate.mesh = quad

	_bg_mat = StandardMaterial3D.new()
	_bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bg_mat.disable_fog = true
	_bg_mat.no_depth_test = true
	_bg_mat.albedo_color = Color(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, 0.0)
	_bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bg_mat.render_priority = 11
	_bg_plate.material_override = _bg_mat
	add_child(_bg_plate)

	# 3. Label3D for text
	_label = Label3D.new()
	_label.name = "TextLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 32
	_label.pixel_size = 0.0036
	_label.modulate = Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.0)
	_label.outline_size = 5
	_label.outline_modulate = Color(0.02, 0.01, 0.02, 0.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = 340.0
	_label.render_priority = 15
	_label.outline_render_priority = 14
	add_child(_label)


## Shows a spoken line with smooth fade-in, stays for [param duration] seconds, then fades out.
func instant_show(text: String) -> void:
	show_speech(text, 15.0)
	_set_alpha(1.0)


func show_speech(text: String, duration: float = DEFAULT_DURATION) -> void:
	if text.strip_edges() == "":
		return

	_label.text = text
	_fit_plates(text)
	_set_speech_nodes(true)
	visible = true

	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.set_parallel(true)
	# Fade in
	_tween.tween_method(_set_alpha, _alpha, 1.0, FADE_IN_TIME)
	speech_displayed.emit(text)

	# Hold, then fade out
	var hold_tween := create_tween()
	hold_tween.tween_interval(FADE_IN_TIME + duration)
	hold_tween.tween_method(_set_alpha, 1.0, 0.0, FADE_OUT_TIME)
	hold_tween.tween_callback(_on_fade_out_finished)


func _set_alpha(val: float) -> void:
	_alpha = val
	if _border_mat:
		_border_mat.albedo_color.a = val * 0.85
	if _bg_mat:
		_bg_mat.albedo_color.a = val * 1.0
	if _label:
		_label.modulate.a = val
		_label.outline_modulate.a = val * 0.95


func _on_fade_out_finished() -> void:
	_set_speech_nodes(false)
	_set_alpha(0.0)
	visible = _thought_label != null and _thought_label.visible
	speech_dismissed.emit()


## Returns true if a speech line is currently displayed.
func is_showing() -> bool:
	return visible and _speech_on and _alpha > 0.05


## The line currently set on the bubble (empty before the first speech).
func get_text() -> String:
	return _label.text if _label else ""
