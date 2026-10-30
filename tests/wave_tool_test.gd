extends Node
## Headless checks for the "Fale" tool (docs/SPAWN_TOOL.md): the panel builds without
## the editor, every preset loads into it, its numbers reach the planner, the chart
## draws the simulated run the game would play, a saved profile reads back the same,
## and the plugin compiles.
##   godot --headless --path . --fixed-fps 90 res://tests/wave_tool_test.tscn

const DOCK_SCRIPT := preload("res://addons/hanabi_spawn/wave_dock.gd")
const PLUGIN_SCRIPT := preload("res://addons/hanabi_spawn/plugin.gd")
const TMP_PATH := "user://wave_tool_test_profile.tres"

var failures := 0


func _ready() -> void:
	_run_all()
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var dock: WaveDock = DOCK_SCRIPT.new()
	add_child(dock)
	_check_builds_and_loads_presets(dock)
	_check_field_reaches_the_planner(dock)
	_check_chart_draws_the_run(dock)
	_check_save_round_trip(dock)
	_check_warnings(dock)
	_check_plugin_compiles()


func _check_builds_and_loads_presets(dock: WaveDock) -> void:
	var fields := 0
	for group in WaveDock.FIELDS:
		fields += WaveDock.FIELDS[group].size()
	_check("Dock builds one spin box per WaveProfile number (%d groups, %d fields)" % [WaveDock.FIELDS.size(), fields],
		dock._spins.size() == fields and fields >= 25)
	var all_load := true
	for entry in WaveProfile.preset_list():
		dock.load_preset(entry[0])
		all_load = all_load and dock.profile != null and dock.last_result != null
	_check("Every preset loads into the panel and simulates", all_load)
	var disk_before: Variant = _disk_value("default", "cap_hard")
	dock.set_field("cap_hard", 5.0)
	_check("Panel edits a copy: the preset on disk keeps its cap (%s, panel %d)" % [disk_before, dock.profile.cap_hard],
		_disk_value("default", "cap_hard") == disk_before and dock.profile.cap_hard == 5)


func _check_field_reaches_the_planner(dock: WaveDock) -> void:
	dock.load_preset("default")
	dock.set_field("calm_seconds", 200.0)
	_check("A field edited in the panel reaches the profile", is_equal_approx(dock.profile.calm_seconds, 200.0))
	var first := dock.last_result.first_minute_spawned
	var direct := WavePlanner.simulate(dock.profile, WaveDock.SIM_MINUTES * 60.0, WaveDock.SIM_SEED)
	_check("The panel's simulation is the planner's (spawned %d = %d)" % [dock.last_result.spawned, direct.spawned],
		dock.last_result.spawned == direct.spawned and first == direct.first_minute_spawned)
	_check("With a 200 s calm the first minute spawns at most 3 yōkai (%d)" % first, first <= 3)
	dock.load_preset("default")


func _check_chart_draws_the_run(dock: WaveDock) -> void:
	dock.load_preset("hardcore")
	dock._chart.queue_redraw()
	# Drawing happens on the next frame; the drawn point count is set in _draw.
	dock._chart._draw()
	var expected := dock.last_result.minutes.size()
	_check("Chart draws one point per simulated minute (%d of %d)" % [dock._chart.drawn_points, expected],
		expected == WaveDock.SIM_MINUTES and dock._chart.drawn_points == expected)
	dock.load_preset("default")


func _check_save_round_trip(dock: WaveDock) -> void:
	dock.load_preset("default")
	dock.set_field("oni_first_seconds", 222.0)
	var err := ResourceSaver.save(dock.profile, TMP_PATH)
	var back := load(TMP_PATH) as WaveProfile
	_check("Saved profile reads back with the same numbers", err == OK and back != null
		and is_equal_approx(back.oni_first_seconds, 222.0)
		and back.cap_hard == dock.profile.cap_hard)
	dock.load_preset("default")


func _check_warnings(dock: WaveDock) -> void:
	dock.load_preset("default")
	dock.set_field("cap_hard", 12.0)
	var lines := dock.validation_lines()
	var quest_warning := false
	for line in lines:
		if line.begins_with("UWAGA") and line.contains("Quest"):
			quest_warning = true
	_check("Cap above the Quest share is a warning in the panel", quest_warning)
	dock.set_field("cap_hard", 8.0)
	dock.set_field("ring_min", 12.0)
	var error_lines := 0
	for line in dock.validation_lines():
		if line.begins_with("BŁĄD"):
			error_lines += 1
	_check("Ring with min above max is an error in the panel (%d)" % error_lines, error_lines >= 1)
	dock.load_preset("default")


func _check_plugin_compiles() -> void:
	_check("Plugin script compiles and its dock is the Fale tool", PLUGIN_SCRIPT != null and DOCK_SCRIPT != null)


## The value of [param prop] in the preset file on disk, for the copy check.
func _disk_value(file: String, prop: String) -> Variant:
	var res := load(WaveProfile.preset_path(file)) as WaveProfile
	return res.get(prop) if res != null else null


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
