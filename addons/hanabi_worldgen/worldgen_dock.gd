@tool
class_name WorldGenDock
extends VBoxContainer
## The "World Gen" dock: the preview's actions, the Quest budget readout and the
## validation list (docs/WORLDGEN_TOOL.md). Built in code, so the test suite
## can create it without the editor.

const SHOTS_FOLDER := "user://worldgen_shots"
const RED := Color(1.0, 0.42, 0.38)
const CALM := Color(0.82, 0.86, 0.92)

var preview: WorldGenPreview = null
var _title: Label
var _seed: Label
var _groups: OptionButton
var _stats: Label
var _notes: RichTextLabel
var _status: Label


func _ready() -> void:
	_build()
	refresh()


## Points the dock at a preview (or none). Refreshes on every regeneration.
func attach(p_preview: WorldGenPreview) -> void:
	if preview != null and preview.regenerated.is_connected(_on_regenerated):
		preview.regenerated.disconnect(_on_regenerated)
	preview = p_preview
	if preview != null:
		preview.regenerated.connect(_on_regenerated)
	_fill_groups()
	refresh()


## Redraws the seed, the budget and the notes from the attached preview.
func refresh() -> void:
	if _title == null:
		return
	if preview == null:
		_title.text = "World Gen"
		_seed.text = "Otwórz scenę tools/worldgen/worldgen_preview.tscn."
		_stats.text = ""
		_notes.text = ""
		return
	var world := preview.active_profile()
	_title.text = "World Gen – %s" % ("profil edytora" if preview.profile != null else "profil gry")
	_seed.text = "Seed %d · dym: %.2f · mgła %.1f–%.1f m" % [world.world_seed, world.dusk_mix, world.fog_start, world.fog_end]
	var stats: Dictionary = preview.last_stats
	var over: bool = stats.get("draws", 0) > WorldGenBudget.FOREST_DRAW_CALLS \
		or stats.get("triangles", 0) > WorldGenBudget.FOREST_TRIANGLES \
		or stats.get("instances", 0) > WorldGenBudget.FOREST_INSTANCES
	_stats.text = "Chunki %d · wywołania %d/%d · instancje %d · trójkąty %d · światła 0/%d" % [
		stats.get("chunks", 0), stats.get("draws", 0), WorldGenBudget.FOREST_DRAW_CALLS,
		stats.get("instances", 0), stats.get("triangles", 0), RunPerfBudget.MAX_DYNAMIC_LIGHTS]
	_stats.add_theme_color_override("font_color", RED if over else CALM)
	var lines := PackedStringArray()
	for line in world.validate():
		lines.append(_bbcode(line))
	for line in WorldGenBudget.warnings(stats):
		lines.append(_bbcode(line))
	_notes.text = "\n".join(lines) if not lines.is_empty() else "Bez uwag."


## Validation texts for the notes, with the errors in red.
static func notes_for(profile: WorldGenProfile, stats: Dictionary) -> Array[String]:
	var out: Array[String] = profile.validate()
	out.append_array(WorldGenBudget.warnings(stats))
	return out


func _on_regenerated(_stats: Dictionary) -> void:
	refresh()


func _build() -> void:
	custom_minimum_size = Vector2(260, 0)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	add_child(_title)
	_seed = Label.new()
	_seed.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_seed)

	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_button("Regeneruj", _on_regenerate, "Buduje las ponownie z profilu."))
	row.add_child(_button("Losuj seed", _on_new_seed, "Nowy seed: inny, ale powtarzalny las."))

	var row2 := HBoxContainer.new()
	add_child(row2)
	row2.add_child(_button("Zapisz preset", _on_save_preset, "Zapisuje profil jako data/worldgen/preset_seedN.tres."))
	row2.add_child(_button("Screenshot", _on_screenshot, "Zrzut widoku 3D edytora do user://worldgen_shots."))

	var reset_row := HBoxContainer.new()
	add_child(reset_row)
	_groups = OptionButton.new()
	_groups.tooltip_text = "Grupa parametrów do przywrócenia."
	_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_row.add_child(_groups)
	reset_row.add_child(_button("Przywróć domyślne", _on_reset_group, "Przywraca domyślne wartości tylko tej grupy."))

	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_stats)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = true
	_notes.fit_content = true
	_notes.scroll_active = false
	_notes.custom_minimum_size = Vector2(240, 0)
	add_child(_notes)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_status)


func _button(text: String, handler: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(handler)
	return b


func _fill_groups() -> void:
	if _groups == null:
		return
	_groups.clear()
	if preview == null:
		return
	for name in preview.active_profile().group_names():
		_groups.add_item(name)


func _on_regenerate() -> void:
	if preview != null:
		preview.regenerate()
		_say("Las przebudowany.")


func _on_new_seed() -> void:
	if preview != null:
		preview.new_seed()
		_say("Nowy seed: %d." % preview.active_profile().world_seed)


func _on_save_preset() -> void:
	if preview == null:
		return
	var path := preview.save_preset()
	_say("Zapisano preset: %s" % path if path != "" else "Nie udało się zapisać presetu.")


func _on_reset_group() -> void:
	if preview == null or _groups.selected < 0:
		return
	var group := _groups.get_item_text(_groups.selected)
	preview.editable_profile().reset_group(group)
	preview.regenerate()
	_say("Przywrócono domyślne: %s." % group)


func _on_screenshot() -> void:
	if preview == null:
		return
	if not Engine.is_editor_hint():
		_say("Zrzut działa w edytorze (widok 3D).")
		return
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOTS_FOLDER)
	var path := "%s/worldgen_seed%d.png" % [SHOTS_FOLDER, preview.active_profile().world_seed]
	var err := image.save_png(path)
	_say("Zapisano: %s" % path if err == OK else "Zrzut nie powiódł się (%d)." % err)


func _say(text: String) -> void:
	if _status != null:
		_status.text = text


static func _bbcode(line: String) -> String:
	if line.begins_with("BŁĄD"):
		return "[color=#ff6b61]%s[/color]" % line
	return "[color=#e6c27a]%s[/color]" % line
