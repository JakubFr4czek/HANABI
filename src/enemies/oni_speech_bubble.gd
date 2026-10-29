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


func _ready() -> void:
	_setup_bubble_visuals()
	visible = false


func _setup_bubble_visuals() -> void:
	# 1. Subtle crimson/gold outer border
	_border_plate = MeshInstance3D.new()
	_border_plate.name = "BorderPlate"
	var border_quad := QuadMesh.new()
	border_quad.size = Vector2(0.96, 0.28)
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
	quad.size = Vector2(0.92, 0.24)
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
	_label.width = 270.0
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
	visible = false
	_set_alpha(0.0)
	speech_dismissed.emit()


## Returns true if a speech line is currently displayed.
func is_showing() -> bool:
	return visible and _alpha > 0.05


## The line currently set on the bubble (empty before the first speech).
func get_text() -> String:
	return _label.text if _label else ""
