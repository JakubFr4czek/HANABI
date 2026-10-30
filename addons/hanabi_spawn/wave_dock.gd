@tool
class_name WaveDock
extends VBoxContainer
## The "Fale" dock: the yōkai wave presets (data/waves), every number of the
## WaveProfile, the simulated run as a chart and table, and the validation list
## (docs/SPAWN_TOOL.md). Built in code, so the test suite can create it without the
## editor. The chart and the table come from WavePlanner.simulate, the same code the
## game runs.

const SIM_MINUTES := 8
const SIM_SEED := 7

## [property, label, min, max, step] per group, in the order the panel shows them.
const FIELDS := {
	"Pacing": [
		["calm_seconds", "Cisza na start (s)", 0.0, 300.0, 1.0],
		["ramp_seconds", "Czas narastania (s)", 60.0, 1200.0, 10.0],
		["initial_wave_delay", "Pierwsza fala po (s)", 0.0, 30.0, 0.5],
		["rest_calm", "Przerwa w ciszy (s)", 0.5, 60.0, 0.5],
		["rest_full", "Przerwa na pełnym napory (s)", 0.5, 30.0, 0.5],
		["max_wave_duration", "Fala zamyka się po (s)", 5.0, 60.0, 0.5],
	],
	"Budget": [
		["wave_credits_start", "Budżet fali na starcie", 0.0, 40.0, 0.5],
		["wave_credits_full", "Budżet fali na pełnym napory", 0.0, 60.0, 0.5],
		["elite_cost", "Koszt elity", 0.5, 20.0, 0.5],
	],
	"Director": [
		["peak_every_waves", "Szczyt co N fal", 2.0, 10.0, 1.0],
		["peak_budget_mult", "Mnożnik budżetu szczytu", 0.5, 3.0, 0.05],
		["relax_budget_mult", "Mnożnik budżetu relaksu", 0.1, 1.0, 0.05],
		["peak_rest_mult", "Mnożnik przerwy po szczycie", 0.1, 2.0, 0.05],
		["relax_rest_mult", "Mnożnik przerwy po relaksie", 0.5, 4.0, 0.05],
	],
	"Caps": [
		["cap_start", "Cap żywych na starcie", 1.0, 12.0, 1.0],
		["cap_step_seconds", "Co ile s cap rośnie", 10.0, 300.0, 5.0],
		["cap_hard", "Cap twardy", 1.0, 16.0, 1.0],
	],
	"Spawn ring": [
		["ring_min", "Pierścień: od (m)", 3.0, 20.0, 0.1],
		["ring_max", "Pierścień: do (m)", 3.0, 20.0, 0.1],
		["view_half_angle", "Kąt poza kadrem (°)", 30.0, 90.0, 1.0],
	],
	"Enemies": [
		["elite_from_seconds", "Elity od (s)", 0.0, 900.0, 5.0],
		["elite_chance_full", "Szansa elity na końcu", 0.0, 1.0, 0.01],
	],
	"Scaling": [
		["base_hp", "HP yōkai (bazowe)", 10.0, 500.0, 1.0],
		["hp_per_wave", "HP za falę (ułamek)", 0.0, 1.0, 0.01],
		["hp_per_second", "HP za sekundę (ułamek)", 0.0, 0.05, 0.001],
		["elite_hp_mult", "Mnożnik HP elity", 1.0, 5.0, 0.05],
	],
	"Oni": [
		["oni_first_seconds", "Oni pierwszy raz po (s)", 0.0, 900.0, 5.0],
		["oni_interval", "Oni co (s)", 20.0, 900.0, 5.0],
		["oni_hp_mult", "Mnożnik HP Oni", 1.0, 20.0, 0.1],
	],
}

var profile: WaveProfile = null
var preset_file := "default"
var last_result: WavePlanner.SimResult = null
var _title: Label
var _presets: OptionButton
var _spins := {}
var _chart: WaveChart
var _table: RichTextLabel
var _notes: RichTextLabel
var _status: Label


func _ready() -> void:
	_build()
	load_preset(preset_file)


## Loads a preset as an editable copy: the file on disk changes only on "Zapisz".
func load_preset(file: String) -> void:
	preset_file = file
	var res := load(WaveProfile.preset_path(file)) as WaveProfile
	profile = res.duplicate(true) as WaveProfile if res != null else WaveProfile.new()
	_sync_fields()
	simulate()


## Sets one WaveProfile field from the panel (or a test) and refreshes the chart and notes.
func set_field(prop: String, value: float) -> void:
	profile.set(prop, value)
	if _spins.has(prop):
		(_spins[prop] as SpinBox).set_value_no_signal(value)
	simulate()


## Runs the planner for SIM_MINUTES and redraws the chart, the table and the notes.
func simulate() -> void:
	if profile == null:
		return
	last_result = WavePlanner.simulate(profile, SIM_MINUTES * 60.0, SIM_SEED)
	if _chart != null:
		_chart.show_result(profile, last_result)
	_refresh_table()
	_refresh_notes()


func save_preset() -> String:
	if profile == null:
		return ""
	var path := WaveProfile.preset_path(preset_file)
	var err := ResourceSaver.save(profile, path)
	_say("Zapisano: %s" % path if err == OK else "Zapis nie powiódł się (%d)." % err)
	return path if err == OK else ""


func reset_to_defaults() -> void:
	var fresh := WaveProfile.new()
	for group in FIELDS:
		for row in FIELDS[group]:
			profile.set(row[0], fresh.get(row[0]))
	_sync_fields()
	simulate()
	_say("Przywrócono domyślne wartości (tylko w panelu, zapis wymaga „Zapisz”).")


## Text of the validation list, one line per error or warning (what the notes show).
func validation_lines() -> PackedStringArray:
	return profile.validate() if profile != null else PackedStringArray()


func _build() -> void:
	custom_minimum_size = Vector2(300, 0)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	add_child(_title)

	_presets = OptionButton.new()
	_presets.tooltip_text = "Preset fal (data/waves). Wybór wczytuje kopię do edycji."
	for entry in WaveProfile.preset_list():
		_presets.add_item(entry[1])
		_presets.set_item_metadata(_presets.item_count - 1, entry[0])
	_presets.item_selected.connect(func(index: int) -> void:
		load_preset(_presets.get_item_metadata(index)))
	add_child(_presets)

	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_button("Symuluj run 8 min", simulate, "Przelicza wykres i tabelę."))
	row.add_child(_button("Zapisz preset", save_preset, "Zapisuje profil do data/waves."))
	row.add_child(_button("Domyślne", reset_to_defaults, "Przywraca domyślne wartości wszystkich grup."))

	_chart = WaveChart.new()
	add_child(_chart)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	for group in FIELDS:
		var header := Label.new()
		header.text = group
		header.add_theme_color_override("font_color", Color(0.95, 0.80, 0.52))
		fields.add_child(header)
		for spec in FIELDS[group]:
			fields.add_child(_field_row(spec))

	_table = RichTextLabel.new()
	_table.bbcode_enabled = true
	_table.fit_content = true
	_table.custom_minimum_size = Vector2(280, 0)
	add_child(_table)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = true
	_notes.fit_content = true
	_notes.custom_minimum_size = Vector2(280, 0)
	add_child(_notes)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_status)


func _field_row(spec: Array) -> HBoxContainer:
	var prop: String = spec[0]
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = spec[1]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = prop
	line.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = spec[2]
	spin.max_value = spec[3]
	spin.step = spec[4]
	spin.custom_minimum_size = Vector2(110, 0)
	spin.value_changed.connect(func(v: float) -> void:
		set_field(prop, v))
	line.add_child(spin)
	_spins[prop] = spin
	return line


func _sync_fields() -> void:
	_title.text = "Fale – %s" % _preset_label()
	for prop in _spins:
		(_spins[prop] as SpinBox).set_value_no_signal(float(profile.get(prop)))


func _preset_label() -> String:
	for entry in WaveProfile.preset_list():
		if entry[0] == preset_file:
			return entry[1]
	return preset_file


func _refresh_table() -> void:
	if last_result == null:
		_table.text = ""
		return
	var lines := PackedStringArray()
	lines.append("[b]min · fala · żywi/cap · zespawnowano (roi/elity)[/b]")
	for row in last_result.minutes:
		lines.append("%d · %d · %d/%d · %d (%d/%d)  śr. %.1f" % [row.minute, row.wave,
			row.alive, row.cap, row.spawned, row.swarm, row.elite, row.avg_alive])
	lines.append("Razem: %d zespawnowanych, %d zabójstw, szczyt %d naraz, pierwsza minuta %d." % [
		last_result.spawned, last_result.kills, last_result.max_alive, last_result.first_minute_spawned])
	_table.text = "\n".join(lines)


func _refresh_notes() -> void:
	var lines := PackedStringArray()
	for line in validation_lines():
		lines.append(_bbcode(line))
	_notes.text = "\n".join(lines) if not lines.is_empty() else "Bez uwag."
	if last_result != null and last_result.max_alive > WaveProfile.QUEST_YOKAI_CAP:
		_notes.text += "\n" + _bbcode("UWAGA: szczyt %d naraz przekracza cap Quest %d." % [
			last_result.max_alive, WaveProfile.QUEST_YOKAI_CAP])


func _button(text: String, handler: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(handler)
	return b


func _say(text: String) -> void:
	if _status != null:
		_status.text = text


static func _bbcode(line: String) -> String:
	if line.begins_with("BŁĄD"):
		return "[color=#ff6b61]%s[/color]" % line
	return "[color=#e6c27a]%s[/color]" % line


## The simulated run: the wave cap (grey steps) and the average yōkai alive per minute
## (gold). Drawn from the planner's per-minute rows, so it is the game's curve.
class WaveChart:
	extends Control
	const CAP_COLOR := Color(0.55, 0.60, 0.68)
	const LIVE_COLOR := Color(0.95, 0.80, 0.52)
	const BG := Color(0.10, 0.11, 0.14)
	var drawn_points := 0
	var _minutes: Array[Dictionary] = []
	var _calm := 0.0
	var _oni := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(280, 150)

	func show_result(profile: WaveProfile, result: WavePlanner.SimResult) -> void:
		_minutes = result.minutes
		_calm = profile.calm_seconds / 60.0
		_oni = profile.oni_first_seconds / 60.0
		queue_redraw()

	func _draw() -> void:
		drawn_points = 0
		draw_rect(Rect2(Vector2.ZERO, size), BG)
		if _minutes.is_empty():
			return
		var top := float(WaveProfile.QUEST_YOKAI_CAP + 1)
		var last := float(_minutes.size())
		var pad := 18.0
		var plot := Rect2(Vector2(pad, 8.0), size - Vector2(pad + 6.0, pad + 12.0))
		draw_rect(plot, Color(1, 1, 1, 0.04), false, 1.0)
		# Quest cap line, dashed by hand.
		var quest_y := plot.position.y + plot.size.y * (1.0 - float(WaveProfile.QUEST_YOKAI_CAP) / top)
		var x := plot.position.x
		while x < plot.end.x:
			draw_line(Vector2(x, quest_y), Vector2(minf(x + 5.0, plot.end.x), quest_y), Color(0.9, 0.42, 0.38, 0.6), 1.0)
			x += 9.0
		var cap_points := PackedVector2Array()
		var live_points := PackedVector2Array()
		for row in _minutes:
			var px := plot.position.x + plot.size.x * (float(row.minute) / last)
			cap_points.append(Vector2(px, plot.position.y + plot.size.y * (1.0 - float(row.cap) / top)))
			live_points.append(Vector2(px, plot.position.y + plot.size.y * (1.0 - float(row.avg_alive) / top)))
			drawn_points += 1
		if cap_points.size() > 1:
			draw_polyline(cap_points, CAP_COLOR, 1.5, true)
			draw_polyline(live_points, LIVE_COLOR, 2.5, true)
		for marker: float in [_calm, _oni]:
			if marker > 0.0 and marker < last:
				var mx: float = plot.position.x + plot.size.x * (marker / last)
				draw_line(Vector2(mx, plot.position.y), Vector2(mx, plot.end.y), Color(1, 1, 1, 0.18), 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(pad, size.y - 4.0),
			"0 · minuty · 8", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.74, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(2.0, plot.position.y + 10.0), "%d" % WaveProfile.QUEST_YOKAI_CAP,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.42, 0.38))
