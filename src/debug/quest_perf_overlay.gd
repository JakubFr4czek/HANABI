class_name QuestPerfOverlay
extends CanvasLayer
## Toggleable Quest profiling HUD (NIGHT_PLAN §8). FPS, frame time, draw calls.

const TOGGLE_ACTION := &"quest_perf_hud"

var _label: Label
var _show_stats := false
var _smooth_fps := 72.0


static func should_enable() -> bool:
	if OS.get_cmdline_user_args().has("--perf-hud"):
		return true
	return ProjectSettings.get_setting("hanabi/debug/quest_perf_hud", false)


static func attach_if_needed(root: Node) -> void:
	if not should_enable():
		return
	if root.get_node_or_null("QuestPerfOverlay") != null:
		return
	var hud := QuestPerfOverlay.new()
	hud.name = "QuestPerfOverlay"
	root.add_child(hud)


func _init() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_label = Label.new()
	_label.name = "Stats"
	_label.position = Vector2(12, 10)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.82, 0.95, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	_show_stats = should_enable()
	_label.visible = _show_stats
	set_process(_show_stats)
	if not InputMap.has_action(TOGGLE_ACTION):
		InputMap.add_action(TOGGLE_ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F3
		InputMap.action_add_event(TOGGLE_ACTION, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		_show_stats = not _show_stats
		_label.visible = _show_stats
		set_process(_show_stats)


func _process(_delta: float) -> void:
	if not _show_stats:
		return
	var fps := Engine.get_frames_per_second()
	_smooth_fps = lerpf(_smooth_fps, fps, 0.12)
	var info := RunPerfProbe.rendering_info()
	var ms: float = float(info.get("process_ms", 0.0))
	var draw: int = int(info.get("draw_calls", 0))
	var prims: int = int(info.get("primitives", 0))
	var root := get_tree().current_scene
	var parts := RunPerfProbe.estimate_particles(root)
	var lights := RunPerfProbe.count_dynamic_lights(root)
	var voices := RunPerfProbe.count_audio_voices(root)
	_label.text = "Quest perf  F3 toggle\n%.0f fps (%.1f ms)  draw %d  prims %d\nparticles~%d  lights %d  audio~%d" % [
		_smooth_fps, ms, draw, prims, parts, lights, voices]
